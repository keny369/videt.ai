# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf007
    # The service-attributed ledger every WF-007 stage writes: one command execution, one
    # audit record, the stage's domain events, one command result and one idempotency record.
    #
    # It is a module rather than a fourth hand-copied set of private methods. WF-006's
    # `SealEvaluationInputs` records that these writers are already on their fourth structural
    # copy and that the extraction is deferred; WF-007 adds two more stages, so copying again
    # would make six. Extracting here does not retro-fit the earlier four — that is a separate
    # change to merged code — but it stops the count rising.
    #
    # SERVICE-ATTRIBUTED, ALWAYS. `service_identity_id` is set and `actor_id` stays null: no
    # human principal executes a Check, and no principal permission gates catalog validation,
    # applicability sealing, key materialization or Issue derivation.
    module StageLedger
      POLICY_VERSION = "permission-baseline-v1"
      WORKFLOW_ID = "WF-007"
      AGGREGATE_TYPE = "evaluation"

      private

      def ledger_ids(ctx, *extra)
        (%i[execution audit result idem] + extra).to_h { |k| [k, ctx.generate_id] }
      end

      # The whole ledger for one stage visit, in one call, so a stage cannot record three
      # quarters of its own execution.
      def write_ledger(d, ids, key_digest, entity_id:, to_state:, outcome:, reason_code:, payload:,
                       failure: nil)
        command = d[:command]
        ctx = d[:ctx]
        store = d[:store]
        org = d[:org]
        now = d[:now]
        request_sha256 = request_hash(command, ctx)

        write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
        write_audit(store, ids[:audit], org, ctx, command, entity_id, to_state:, outcome:, reason_code:,
                    payload:, now:)
        write_result(store, ids, command, ctx, org, now, payload, failure:)
        write_idempotency(store, ids[:idem], org, command, key_digest, request_sha256,
                          ids[:execution], ids[:result], now)
      end

      def succeeded(d, ids, payload)
        Platform::CommandResult.success(result_id: ids[:result], command_type: d[:command].command_type,
                                        audit_record_id: ids[:audit], correlation_id: d[:ctx].correlation_id,
                                        payload: payload.transform_keys(&:to_sym))
      end

      def write_execution(store, command, ctx, org, id, request_sha256, key_digest, now)
        store.insert_command_execution(
          id:, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
          command_id: command.command_id, idempotency_key_digest: key_digest,
          command_type: command.command_type, command_schema_version: command.schema_version,
          service_identity_id: ctx.service_identity_id, organization_id: org,
          target_type: self.class::TARGET_TYPE, target_id: target_id_of(command), action: self.class::ACTION,
          requested_at: iso(command.requested_at_utc), authorization_check_at: iso(now),
          policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
          canonical_payload: JSON.generate({ "stage" => self.class::STAGE }), request_sha256:
        )
      end

      def write_audit(store, id, org, ctx, command, entity_id, to_state:, outcome:, reason_code:, payload:, now:)
        store.insert_audit(
          id:, occurred_at: iso(now), partition_month: month(now), organization_id: org,
          service_identity_id: ctx.service_identity_id, correlation_id: ctx.correlation_id,
          causation_id: ctx.correlation_id, command_id: command.command_id, entity_type: AGGREGATE_TYPE,
          entity_id:, to_state:, outcome:, reason_code:, payload: JSON.generate(payload),
          content_sha256: Platform::CanonicalJson.digest(payload)
        )
      end

      def write_result(store, ids, command, ctx, org, now, payload, failure: nil)
        store.insert_command_result(
          id: ids[:result], created_at: iso(now), correlation_id: ctx.correlation_id,
          causation_id: ctx.correlation_id, command_id: command.command_id,
          command_execution_id: ids[:execution], outcome: failure ? "failure" : "success",
          organization_id: org, service_identity_id: ctx.service_identity_id, completed_at: iso(now),
          authorization_check_at: iso(now),
          target_refs: JSON.generate(failure ? {} : { self.class::TARGET_TYPE => target_id_of(command) }),
          governing_policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
          failure:, authorized_payload: JSON.generate(payload), audit_record_id: ids[:audit]
        )
      end

      def write_idempotency(store, id, org, command, key_digest, request_sha256, execution_id, result_id, now)
        store.insert_idempotency(
          id:, created_at: iso(now), organization_id: org, command_type: command.command_type,
          target_type: self.class::TARGET_TYPE, target_id: target_id_of(command), key_digest:, request_sha256:,
          command_execution_id: execution_id, command_result_id: result_id,
          retain_until: iso(now + (30 * 24 * 3600))
        )
      end

      def emit(store, ids, org, ctx, command, now, id:, event_type:, profile:, aggregate_type:,
               aggregate_id:, aggregate_version:, extra:)
        envelope = {
          "account_id" => nil, "actor_id" => nil, "affected_entity_id" => aggregate_id,
          "affected_entity_type" => aggregate_type, "aggregate_version" => aggregate_version,
          "audit_record_id" => ids[:audit], "causation_id" => ctx.correlation_id,
          "command_id" => command.command_id, "correlation_id" => ctx.correlation_id,
          "event_id" => id, "event_profile" => profile, "event_type" => event_type,
          "occurred_at_utc" => now.iso8601(6), "organization_id" => org,
          "schema_version" => "1.0", "service_identity_id" => ctx.service_identity_id,
          "workflow_id" => WORKFLOW_ID
        }.merge(extra)
        bytes = Platform::CanonicalJson.encode(envelope)
        store.insert_event(
          id:, created_at: iso(now), event_type:, event_profile: profile, occurred_at: iso(now),
          organization_id: org, aggregate_type:, aggregate_id:, aggregate_version:,
          partition_month: month(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
          command_id: command.command_id, audit_record_id: ids[:audit],
          event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
        )
      end

      def request_hash(command, ctx)
        Platform::CanonicalJson.digest({
                                         "action" => self.class::ACTION, "command_type" => command.command_type,
                                         "command_schema_version" => command.schema_version,
                                         "service_identity_id" => ctx.service_identity_id,
                                         "organization_id" => command.organization_id,
                                         "target_type" => self.class::TARGET_TYPE,
                                         "target_id" => target_id_of(command),
                                         "policy_versions" => [POLICY_VERSION],
                                         "command_payload" => { "stage" => self.class::STAGE }
                                       })
      end

      def rebuild(store, existing, command)
        stored = store.load_command_result(existing["command_result_id"])
        if stored["outcome"] == "success"
          Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type,
                                          payload: JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym),
                                          audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        else
          failure = Platform::Failure.new(
            error_class: stored["error_class"], error_code: stored["error_code"],
            reason_code: stored["reason_code"], severity: stored["severity"],
            retryable: stored["retryable"] == "t" || stored["retryable"] == true,
            recovery_action: stored["recovery_action"], support_reference: stored["support_reference"]
          )
          Platform::CommandResult.failure(result_id: stored["id"], command_type: command.command_type,
                                          failure:, audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end
      end

      def deny(d, reason)
        ids = ledger_ids(d[:ctx])
        key_digest = Digest::SHA256.digest(d[:command].idempotency_key)
        failure = Platform::ErrorCatalog.failure(reason, support_reference: d[:ctx].correlation_id)
        write_ledger(d, ids, key_digest, entity_id: target_id_of(d[:command]), to_state: nil,
                     outcome: "failure", reason_code: reason,
                     payload: { "outcome" => "failure", "internal_reason" => reason }, failure:)
        Platform::CommandResult.failure(result_id: ids[:result], command_type: d[:command].command_type,
                                        failure:, audit_record_id: ids[:audit],
                                        correlation_id: d[:ctx].correlation_id)
      end

      def in_memory_failure(command, ctx, reason)
        failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
        Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                        failure:, audit_record_id: ctx.generate_id,
                                        correlation_id: ctx.correlation_id)
      end

      def supported_schema?(version) = version.to_s.split(".").first == "1"
      def iso(time) = time&.getutc&.iso8601(6)
      def month(time) = Date.new(time.year, time.month, 1).iso8601
    end
  end
end
