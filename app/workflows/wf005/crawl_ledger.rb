# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf005
    # The ledger plumbing for WF-005 actor commands — the durable command execution, the
    # authorization decision (on allow AND deny), the audit record, the canonical event
    # envelope, the command result and the idempotency record. It is the exact WF-004
    # SourceLedger shape (same ActorLedgerWriters platform ledgers, same canonical envelope)
    # specialized to `WF-005` and generic over the command's target aggregate.
    #
    # Including handlers MUST define `ACTION`, `TARGET_TYPE` and `SUPPORTED_SCHEMA_MAJOR`; the
    # store supplies the WF-005-stamped `insert_audit` / `insert_event` plus the
    # ActorLedgerWriters execution/result/idempotency writers.
    module CrawlLedger
      def write_execution(store, command, ctx, org, id, target_id, actor, request_sha256, key_digest, now, action)
        store.insert_command_execution(
          id:, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
          command_id: command.command_id, idempotency_key_digest: key_digest,
          command_type: command.command_type, command_schema_version: command.schema_version,
          actor_id: actor.account_id, organization_id: org, target_type: self.class::TARGET_TYPE,
          target_id:, action:, requested_at: iso(command.requested_at_utc),
          authorization_check_at: iso(now), policy_versions: policy_versions_json,
          canonical_payload: JSON.generate({ "command_type" => command.command_type }), request_sha256:
        )
      end

      def write_authorization_decision(auth_store, id, ctx, command, actor, decision, now, resource_id, action)
        auth_store.insert_authorization_decision(
          id:, created_at: iso(now), organization_id: actor.organization_id, correlation_id: ctx.correlation_id,
          causation_id: ctx.correlation_id, command_id: command.command_id, subject_id: actor.account_id,
          action:, resource_type: self.class::TARGET_TYPE, resource_id:,
          decision: decision.allowed? ? "allow" : "deny", reason_code: decision.reason,
          organization_epoch: decision.organization_epoch,
          membership_snapshot: JSON.generate({ "status" => decision.allowed? ? "active" : "no_active_grant" }),
          role_assignment_versions: JSON.generate(decision.role_assignment_versions),
          policy_snapshot_id: decision.policy_snapshot_id, decided_at: iso(now)
        )
      end

      def write_audit(store, id, org, ctx, command, entity_id, actor, to_state:, outcome:, reason_code:, payload:, now:)
        store.insert_audit(
          id:, occurred_at: iso(now), partition_month: month(now), organization_id: org,
          actor_id: actor.account_id, correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
          command_id: command.command_id, entity_type: self.class::TARGET_TYPE, entity_id:, to_state:,
          outcome:, reason_code:, payload: JSON.generate(payload),
          content_sha256: Platform::CanonicalJson.digest(payload)
        )
      end

      # One canonically-encoded WF-005 event envelope on the command's target aggregate.
      def write_event(store, ids, org, ctx, command, actor, now, aggregate_version, aggregate_id,
                      request_sha256, key_digest, type, profile, extra = {})
        envelope = {
          "account_id" => actor.account_id, "actor_id" => actor.account_id,
          "affected_entity_id" => aggregate_id, "affected_entity_type" => self.class::TARGET_TYPE,
          "aggregate_version" => aggregate_version, "audit_record_id" => ids[:audit],
          "causation_id" => ctx.correlation_id, "command_id" => command.command_id,
          "correlation_id" => ctx.correlation_id, "event_id" => ids[:event], "event_profile" => profile,
          "event_type" => type, "idempotency_identity_hash" => hex(key_digest),
          "input_hash" => hex(request_sha256), "occurred_at_utc" => now.iso8601(6),
          "organization_epoch" => actor.authorization_epoch, "organization_id" => org,
          "outcome" => "success", "project_id" => extra["project_id"], "reason_code" => nil,
          "requester_account_id" => actor.account_id, "schema_version" => "1.0",
          "service_identity_id" => nil, "state_version" => aggregate_version, "workflow_id" => "WF-005"
        }.merge(extra)
        bytes = Platform::CanonicalJson.encode(envelope)
        store.insert_event(
          id: ids[:event], created_at: iso(now), event_type: type, event_profile: profile,
          occurred_at: iso(now), organization_id: org, aggregate_type: self.class::TARGET_TYPE,
          aggregate_id:, aggregate_version:, partition_month: month(now),
          correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
          command_id: command.command_id, audit_record_id: ids[:audit],
          event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
        )
      end

      def write_result_success(store, ids, command, ctx, org, actor, now, payload, target_id)
        store.insert_command_result(
          id: ids[:result], created_at: iso(now), correlation_id: ctx.correlation_id,
          causation_id: ctx.correlation_id, command_id: command.command_id,
          command_execution_id: ids[:execution], outcome: "success", organization_id: org,
          actor_id: actor.account_id, completed_at: iso(now), authorization_check_at: iso(now),
          target_refs: JSON.generate({ self.class::TARGET_TYPE => target_id }),
          governing_policy_versions: policy_versions_json, failure: nil,
          authorized_payload: JSON.generate(payload), audit_record_id: ids[:audit]
        )
      end

      def write_result_failure(store, result_id, execution_id, command, ctx, org, actor, audit_id, failure, now)
        store.insert_command_result(
          id: result_id, created_at: iso(now), correlation_id: ctx.correlation_id,
          causation_id: ctx.correlation_id, command_id: command.command_id,
          command_execution_id: execution_id, outcome: "failure", organization_id: org,
          actor_id: actor.account_id, completed_at: iso(now), authorization_check_at: iso(now),
          target_refs: JSON.generate({}), governing_policy_versions: policy_versions_json, failure:,
          authorized_payload: JSON.generate({}), audit_record_id: audit_id
        )
      end

      def write_idempotency(store, id, org, command, target_id, key_digest, request_sha256, execution_id, result_id, now)
        store.insert_idempotency(
          id:, created_at: iso(now), organization_id: org, command_type: command.command_type,
          target_type: self.class::TARGET_TYPE, target_id:, key_digest:, request_sha256:,
          command_execution_id: execution_id, command_result_id: result_id,
          retain_until: iso(now + (30 * 24 * 3600))
        )
      end

      # An audited no-mutation outcome for an authenticated actor: execution, authorization
      # decision, audit and result, no aggregate row and no event.
      def deny(command:, ctx:, store:, auth_store:, actor:, decision:, org:, now:, request_sha256:,
               resource_id:, outward:, internal:)
        ids = %i[execution audit result decision].to_h { |k| [k, ctx.generate_id] }
        key_digest = Digest::SHA256.digest(command.idempotency_key)

        write_execution(store, command, ctx, org, ids[:execution], nil, actor, request_sha256,
                        key_digest, now, self.class::ACTION)
        write_authorization_decision(auth_store, ids[:decision], ctx, command, actor, decision, now,
                                     resource_id, self.class::ACTION)
        write_audit(store, ids[:audit], org, ctx, command, command.command_id, actor,
                    to_state: nil, outcome: "failure", reason_code: internal,
                    payload: { "outcome" => "failure", "internal_reason" => internal,
                               "outward_reason" => outward, "organization_id" => org }, now:)
        failure = Platform::ErrorCatalog.failure(outward, support_reference: ctx.correlation_id)
        write_result_failure(store, ids[:result], ids[:execution], command, ctx, org, actor, ids[:audit],
                             failure, now)
        Platform::CommandResult.failure(result_id: ids[:result], command_type: command.command_type,
                                        failure:, audit_record_id: ids[:audit],
                                        correlation_id: ctx.correlation_id)
      end

      def schema_failure(command, ctx) = in_memory_failure(command, ctx, "command_schema_unsupported")

      def in_memory_failure(command, ctx, reason)
        failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
        Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                        failure:, audit_record_id: ctx.generate_id,
                                        correlation_id: ctx.correlation_id)
      end

      def policy_versions_json = JSON.generate({ "permission_baseline" => Platform::PermissionBaseline::VERSION })
      def iso(time) = time&.getutc&.iso8601(6)
      def month(time) = Date.new(time.year, time.month, 1).iso8601
      def hex(bytes) = bytes.unpack1("H*")
    end
  end
end
