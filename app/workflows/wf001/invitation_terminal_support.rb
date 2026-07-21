# frozen_string_literal: true

require "digest"
require "time"
require "json"

module Workflows
  module Wf001
    # Shared machinery for the WF-001 receipt-bound invitation terminal transitions
    # (currently AcceptInvitation and DeclineInvitation). It carries ONLY the generic
    # plumbing that is identical across those workflows — context bootstrap, restricted
    # exact-replay recognition, the command/audit/event/idempotency ledger writers, the
    # request-digest skeleton, and normalized failures. Every workflow-specific
    # decision — which proof and authorization, which state transition, which events,
    # which reauthorization on replay — stays visible in each handler.
    #
    # Included handlers MUST define the constant ACTION and MAY override
    # reauthorize_replay (default: no reauthorization). Handler constants ACTION are
    # read via self.class::ACTION; the invitation target_type, supported schema major
    # and onboarding policy version are shared here.
    module InvitationTerminalSupport
      SUPPORTED_SCHEMA_MAJOR = "1"
      POLICY_VERSION = "onboarding-interim-v1"
      TARGET_TYPE = "invitation"

      # Concurrent-commit signals: the nonce was consumed, or the guarded terminal
      # transition lost the race, after rows were written — roll back and surface an
      # invariant violation (the winner recorded the authoritative outcome).
      class Consumed < StandardError; end
      class LostRace < StandardError; end

      # ---- restricted exact replay --------------------------------------------

      # Recognizes an exact replay BEFORE ordinary active-only resolution, so a prior
      # command (success or failure) replays through the existing command/result ledger
      # even when the non-disclosing resolver refuses the now-terminal Invitation. It
      # bootstraps context from the any-state registry (never the public resolver),
      # reads the restricted idempotency/command-result ledger IN-CONTEXT, requires
      # exact command-digest equality, and lets the workflow reauthorize a replayed
      # success against current state. No events, no domain writes. Returns a
      # CommandResult, or nil when this is not a replay.
      def try_exact_replay(store, pg, command, ctx, reference_digest, key_digest, request_sha256)
        org_binding = IdentityAccess::Infrastructure::InvitationResolver.new(pg).resolve_org(reference_digest:)
        return nil if org_binding.nil?

        org = org_binding[:organization_id]
        store.enter_context(receipt_digest: command.receipt_digest, org:, correlation_id: ctx.correlation_id)
        existing = store.find_idempotency(org:, command_type: command.command_type, target_type: TARGET_TYPE,
                                          target_id: org_binding[:invitation_id], key_digest:)
        return nil if existing.nil?

        return in_memory_failure(command, ctx, "idempotency_conflict") unless existing["request_hex"] == hex(request_sha256)

        stored = store.load_command_result(existing["command_result_id"])
        denied = reauthorize_replay(store, stored)
        return in_memory_failure(command, ctx, denied) if denied

        rebuild_stored_result(stored, command)
      end

      # Default: a replayed result is returned as stored, with no current-state
      # reauthorization. Workflows whose success confers ongoing authority override this
      # to return a reason (e.g. "reauthorization_denied") when it no longer holds.
      def reauthorize_replay(_store, _stored) = nil

      def rebuild_stored_result(stored, command)
        if stored["outcome"] == "success"
          payload = JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym)
          Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type, payload:,
                                          audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        else
          failure = Platform::Failure.new(
            error_class: stored["error_class"], error_code: stored["error_code"], reason_code: stored["reason_code"],
            severity: stored["severity"], retryable: stored["retryable"] == "t" || stored["retryable"] == true,
            recovery_action: stored["recovery_action"], support_reference: stored["support_reference"]
          )
          Platform::CommandResult.failure(result_id: stored["id"], command_type: command.command_type, failure:,
                                          audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end
      end

      # ---- denials ------------------------------------------------------------

      # A still-active-Invitation denial: records the command outcome so an exact
      # replay (recognized upstream) returns the same stored failure.
      def deny(store:, command:, ctx:, now:, org:, invitation_id:, request_sha256:, key_digest:, outward:, internal:, account_id:)
        execution_id = ctx.generate_id
        audit_id = ctx.generate_id
        result_id = ctx.generate_id
        causation = ctx.correlation_id

        write_execution(store, command, ctx, org, execution_id, invitation_id, request_sha256, key_digest, now, causation)
        write_audit(store, audit_id, org, ctx, causation, command, invitation_id, entity_type: "invitation",
                    to_state: nil, outcome: "failure", reason_code: internal,
                    payload: denial_audit_payload(internal, outward, account_id, invitation_id, org), now:)
        failure = Platform::ErrorCatalog.failure(outward, support_reference: ctx.correlation_id)
        write_result_failure(store, result_id, execution_id, command, ctx, org, audit_id, failure, now)
        write_idempotency(store, ctx.generate_id, org, command, invitation_id, key_digest, request_sha256, execution_id, result_id, now)
        Platform::CommandResult.failure(result_id:, command_type: command.command_type, failure:,
                                        audit_record_id: audit_id, correlation_id: ctx.correlation_id)
      end

      # A valid receipt whose target does not match: the Invitation stays active, the
      # nonce binds to this denied command, no Invitation event is emitted, and the
      # audit reveals neither the intended email nor identity (:248).
      def wrong_identity(store:, command:, ctx:, now:, org:, invitation_id:, request_sha256:, key_digest:, receipt:)
        execution_id = ctx.generate_id
        audit_id = ctx.generate_id
        result_id = ctx.generate_id
        causation = ctx.correlation_id

        write_execution(store, command, ctx, org, execution_id, invitation_id, request_sha256, key_digest, now, causation)
        store.consume_nonce(id: ctx.generate_id, created_at: iso(now), receipt_id: receipt["receipt_id"],
                            receipt_digest: command.receipt_digest, command_execution_id: execution_id,
                            consumed_at: iso(now), outcome: "rejected", reason_code: "invitation_target_mismatch")
        write_audit(store, audit_id, org, ctx, causation, command, invitation_id, entity_type: "invitation",
                    to_state: nil, outcome: "failure", reason_code: "invitation_target_mismatch",
                    payload: { "branch" => branch, "outcome" => "failure",
                               "internal_reason" => "invitation_target_mismatch",
                               "outward_reason" => "invitation_target_mismatch",
                               "invitation_id" => invitation_id, "organization_id" => org }, now:)
        failure = Platform::ErrorCatalog.failure("invitation_target_mismatch", support_reference: ctx.correlation_id)
        write_result_failure(store, result_id, execution_id, command, ctx, org, audit_id, failure, now)
        write_idempotency(store, ctx.generate_id, org, command, invitation_id, key_digest, request_sha256, execution_id, result_id, now)
        Platform::CommandResult.failure(result_id:, command_type: command.command_type, failure:,
                                        audit_record_id: audit_id, correlation_id: ctx.correlation_id)
      end

      # ---- ledger writers -----------------------------------------------------

      def write_execution(store, command, ctx, org, id, invitation_id, request_sha256, key_digest, now, causation)
        store.insert_command_execution(
          id:, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: causation,
          command_id: command.command_id, idempotency_key_digest: key_digest, command_type: command.command_type,
          command_schema_version: command.schema_version, service_identity_id: ctx.service_identity_id,
          organization_id: org, target_type: TARGET_TYPE, target_id: invitation_id, action: self.class::ACTION,
          requested_at: iso(command.requested_at_utc), authorization_check_at: iso(now),
          policy_versions: policy_versions_json, canonical_payload: canonical_payload_json(command), request_sha256:
        )
      end

      def write_audit(store, id, org, ctx, causation, command, entity_id, entity_type:, to_state:, outcome:, reason_code:, payload:, now:)
        store.insert_audit(
          id:, occurred_at: iso(now), partition_month: month(now), organization_id: org,
          service_identity_id: ctx.service_identity_id, correlation_id: ctx.correlation_id, causation_id: causation,
          command_id: command.command_id, entity_type:, entity_id:, to_state:, outcome:, reason_code:,
          payload: JSON.generate(payload), content_sha256: Platform::CanonicalJson.digest(payload)
        )
      end

      # Persists each event with a deterministic causal order: same logical occurred_at
      # (fixed commit instant); created_at carries the causal index.
      def write_events(store, events, org, ctx, causation, command, now, audit_id, account_id, invitation_id, request_sha256, key_digest)
        events.each_with_index do |e, index|
          event_id = ctx.generate_id
          created = now + (index * 0.000001)
          envelope = {
            "account_id" => account_id, "affected_entity_id" => e[:aggregate_id],
            "affected_entity_type" => e[:aggregate_type], "aggregate_version" => e[:aggregate_version],
            "audit_record_id" => audit_id, "causation_id" => causation, "command_id" => command.command_id,
            "correlation_id" => ctx.correlation_id, "event_id" => event_id, "event_profile" => e[:profile],
            "event_type" => e[:type], "from_state" => e[:from_state], "idempotency_identity_hash" => hex(key_digest),
            "input_hash" => hex(request_sha256), "invitation_id" => invitation_id, "occurred_at_utc" => now.iso8601(6),
            "organization_id" => org, "outcome" => "success", "project_id" => nil, "reason_code" => nil,
            "schema_version" => "1.0", "service_identity_id" => ctx.service_identity_id, "to_state" => e[:to_state],
            "workflow_id" => "WF-001"
          }.merge(e[:extra] || {})
          bytes = Platform::CanonicalJson.encode(envelope)
          store.insert_event(
            id: event_id, created_at: iso(created), event_type: e[:type], event_profile: e[:profile], occurred_at: iso(now),
            organization_id: org, aggregate_type: e[:aggregate_type], aggregate_id: e[:aggregate_id],
            aggregate_version: e[:aggregate_version], partition_month: month(now), correlation_id: ctx.correlation_id,
            causation_id: causation, command_id: command.command_id, audit_record_id: audit_id,
            event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
          )
        end
      end

      def write_result_success(store, result_id, execution_id, audit_id, command, ctx, org, now, payload, target_refs)
        store.insert_command_result(
          id: result_id, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
          command_id: command.command_id, command_execution_id: execution_id, outcome: "success",
          organization_id: org, service_identity_id: ctx.service_identity_id, completed_at: iso(now),
          authorization_check_at: iso(now), target_refs: JSON.generate(target_refs),
          governing_policy_versions: policy_versions_json, failure: nil,
          authorized_payload: JSON.generate(payload), audit_record_id: audit_id
        )
      end

      def write_result_failure(store, result_id, execution_id, command, ctx, org, audit_id, failure, now)
        store.insert_command_result(
          id: result_id, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
          command_id: command.command_id, command_execution_id: execution_id, outcome: "failure",
          organization_id: org, service_identity_id: ctx.service_identity_id, completed_at: iso(now),
          authorization_check_at: iso(now), target_refs: JSON.generate({}),
          governing_policy_versions: policy_versions_json, failure:,
          authorized_payload: JSON.generate({}), audit_record_id: audit_id
        )
      end

      def write_idempotency(store, id, org, command, invitation_id, key_digest, request_sha256, execution_id, result_id, now)
        store.insert_idempotency(
          id:, created_at: iso(now), organization_id: org, command_type: command.command_type,
          target_type: TARGET_TYPE, target_id: invitation_id, key_digest:, request_sha256:,
          command_execution_id: execution_id, command_result_id: result_id, retain_until: iso(now + (30 * 24 * 3600))
        )
      end

      # ---- normalized failures ------------------------------------------------

      def schema_failure(command, ctx) = in_memory_failure(command, ctx, "command_schema_unsupported")
      def invitation_not_active_in_memory(command, ctx) = in_memory_failure(command, ctx, "invitation_not_active")

      def in_memory_failure(command, ctx, reason)
        failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
        Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                        failure:, audit_record_id: ctx.generate_id, correlation_id: ctx.correlation_id)
      end

      # ---- shared payloads / helpers ------------------------------------------

      def denial_audit_payload(internal, outward, account_id, invitation_id, org)
        { "branch" => branch, "outcome" => "failure", "internal_reason" => internal,
          "outward_reason" => outward, "account_id" => account_id, "invitation_id" => invitation_id,
          "organization_id" => org }
      end

      def event_spec(type, profile, aggregate_type, aggregate_id, aggregate_version, from_state, to_state, extra = nil)
        { type:, profile:, aggregate_type:, aggregate_id:, aggregate_version:, from_state:, to_state:, extra: }
      end

      def receipt_invalid_reason(receipt, now)
        return "identity_receipt_invalid" unless truthy(receipt["receipt_found"])
        return "identity_receipt_purpose_mismatch" unless receipt["purpose"] == "invitation_response"
        return "identity_email_unverified" unless truthy(receipt["email_verified"])
        return "identity_receipt_expired" if now >= to_time(receipt["expires_at"])

        nil
      end

      def target_matches?(receipt, inv)
        return false unless receipt["email_hex"] == inv["target_email_hex"]
        return true if inv["target_identity_issuer_key"].nil?

        receipt["issuer_key"] == inv["target_identity_issuer_key"] &&
          receipt["issuer_subject"] == inv["target_identity_subject"]
      end

      # The canonical pre-resolution command digest: computed from the command alone
      # (Organization and Invitation are implied by the immutable opaque-reference
      # digest), so it identifies the command both before resolution (restricted
      # replay) and after (in-context idempotency). Each workflow supplies its
      # semantic command_payload fields; the idempotency key stays separate.
      def request_digest(command, ctx, reference_digest, command_payload)
        Platform::CanonicalJson.digest({
          "action" => self.class::ACTION, "command_type" => command.command_type,
          "command_schema_version" => command.schema_version, "target_type" => TARGET_TYPE,
          "policy_versions" => [POLICY_VERSION], "service_identity_id" => ctx.service_identity_id, "project_id" => nil,
          "command_payload" => { "invitation_reference_sha256" => hex(reference_digest),
                                 "receipt_digest" => hex(command.receipt_digest) }.merge(command_payload)
        })
      end

      def to_time(value)
        return value.getutc if value.respond_to?(:getutc)

        Time.parse(value).getutc
      end

      def norm(value) = (value.nil? || value == "") ? nil : value
      def truthy(value) = value == true || value == "t"
      def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
      def policy_versions_json = JSON.generate({ "onboarding" => POLICY_VERSION })
      def canonical_payload_json(command) = JSON.generate({ "receipt_digest" => hex(command.receipt_digest) })
      def iso(time) = time.getutc.iso8601(6)
      def month(time) = Date.new(time.year, time.month, 1).iso8601
      def hex(bytes) = bytes.unpack1("H*")
      def unhex(hex_string) = [hex_string].pack("H*")
    end
  end
end
