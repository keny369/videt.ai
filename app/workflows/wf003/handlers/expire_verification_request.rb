# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf003
    module Handlers
      # WF-003 ExpireVerificationRequest — the service-only timed transition behind the
      # ratified `verification_request_expire` ScheduledAction that
      # IssueVerificationChallenge schedules (SCORE_EVIDENCE_MODEL.md § Attempts,
      # Expiry, And Evidence; contracts/S-05.json MTX-028/005/051).
      #
      # At `expires_at_utc` a still-pending Request becomes `expired` with reason
      # `challenge_expired`, the challenge material is cryptographically destroyed
      # (F-02 erase) and redelivery becomes unavailable, `SourceVerificationExpired`
      # is emitted exactly once, and the Source is left `proposed`. The immutable
      # challenge digest and the audit survive the deletion. A timer arriving before
      # the expiry instant, for a target whose expiry disagrees with the action, or for
      # an already-terminal Request, changes nothing.
      #
      # Authority is not checked here and there is none to check — expiry is the
      # verification lifecycle service's own timer, so no Permission Baseline, no
      # Session, no human actor. The ledger is service-attributed with a null actor.
      class ExpireVerificationRequest
        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "verification_request"
        ACTION = "verification.expire"
        POLICY_VERSION = "permission-baseline-v1"
        WORKFLOW_ID = "WF-003"
        DECISION_REASON = "challenge_expired"

        # F-02 AAD binding (must match IssueVerificationChallenge) — unused for erase,
        # kept for provenance and any future reveal-before-destroy check.
        AAD_APPLICATION = "verification"
        AAD_PURPOSE = "challenge_token"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)
          return in_memory_failure(command, ctx, "scheduled_action_target_mismatch") unless command.target_type == TARGET_TYPE

          key_digest = Digest::SHA256.digest(command.action_identity_sha256)

          Platform::UnitOfWork.run do |conn|
            now = ctx.now_utc.floor(6)
            store = IdentityAccess::Infrastructure::VerificationExpiryStore.new(conn.raw_connection)
            org = command.organization_id

            store.enter_org_context(org:, correlation_id: ctx.correlation_id)
            store.lock_verification_request(command.verification_request_id)

            process(store:, command:, ctx:, org:, now:, key_digest:)
          end
        end

        private

        def process(store:, command:, ctx:, org:, now:, key_digest:)
          request_sha256 = request_hash(command, ctx)
          d = { store:, command:, ctx:, org:, now:, key_digest:, request_sha256: }

          row = store.read(command.verification_request_id)
          # Not visible under the action's Organization context: the action and its
          # target disagree, which a correctly created action cannot do.
          return deny(**d, outward: "scheduled_action_target_mismatch", internal: "scheduled_action_target_mismatch", replayable: false) if row.nil?

          existing = store.find_idempotency(org:, command_type: command.command_type, target_type: TARGET_TYPE,
                                            target_id: command.verification_request_id, key_digest:)
          if existing
            return rebuild(store, existing, command) if existing["request_hex"] == hex(request_sha256)

            return deny(**d, outward: "idempotency_conflict", internal: "idempotency_conflict", replayable: false)
          end

          expires_at = row["expires_at_utc"] && to_time(row["expires_at_utc"])
          if expires_at.nil? || command.due_at != expires_at
            return deny(**d, outward: "scheduled_action_target_mismatch", internal: "scheduled_action_target_mismatch", replayable: false)
          end
          return deny(**d, outward: "scheduled_action_not_due", internal: "scheduled_action_not_due", replayable: false) if now < expires_at

          # A timer arriving after another terminal transition is the canonical
          # harmless completion; it changes nothing.
          unless row["request_status"] == "pending"
            return deny(**d, outward: "verification_request_not_pending", internal: "verification_request_not_pending")
          end

          expire(**d, row:)
        end

        def expire(store:, command:, ctx:, org:, now:, key_digest:, request_sha256:, row:)
          ids = %i[execution audit event result idem].to_h { |k| [k, ctx.generate_id] }
          new_version = row["state_version"].to_i + 1

          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          raise LostRace if store.expire(command.verification_request_id, row["state_version"].to_i, now).to_i.zero?

          # Cryptographic deletion of the challenge material (F-02), atomic with the
          # expiry: the ciphertext is erased and its column nulled, so redelivery is
          # unavailable; the immutable digest and the audit remain.
          reference = row["challenge_ciphertext_reference"]
          Platform::Encryption.erase(reference) if reference

          payload = { "verification_request_id" => command.verification_request_id, "organization_id" => org,
                      "project_id" => row["project_id"], "source_id" => row["source_id"],
                      "request_status" => "expired", "decision_reason_code" => DECISION_REASON }
          write_audit(store, ids[:audit], org, ctx, command, command.verification_request_id,
                      to_state: "expired", outcome: "success", reason_code: DECISION_REASON, payload:, now:)
          write_event(store, ids, org, ctx, command, now, new_version, row, request_sha256, key_digest,
                      "SourceVerificationExpired", "state_transition",
                      { "from_state" => "pending", "to_state" => "expired", "source_id" => row["source_id"],
                        "decision_reason_code" => DECISION_REASON, "reason_code" => DECISION_REASON })
          write_result(store, ids, command, ctx, org, now, payload)
          write_idempotency(store, ids[:idem], org, command, key_digest, request_sha256, ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        rescue LostRace
          raise Platform::InvariantViolation, "verification request transitioned concurrently"
        end

        # ---- audited no-state outcome --------------------------------------------

        def deny(store:, command:, ctx:, org:, now:, key_digest:, request_sha256:, outward:, internal:, replayable: true)
          ids = %i[execution audit result idem].to_h { |k| [k, ctx.generate_id] }
          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          write_audit(store, ids[:audit], org, ctx, command, command.verification_request_id, to_state: nil,
                      outcome: "failure", reason_code: internal,
                      payload: { "verification_request_id" => command.verification_request_id,
                                 "organization_id" => org, "internal_reason" => internal,
                                 "outward_reason" => outward, "scheduled_action_id" => command.action_id }, now:)
          failure = Platform::ErrorCatalog.failure(outward, support_reference: ctx.correlation_id)
          write_result(store, ids, command, ctx, org, now, {}, failure:)
          if replayable
            write_idempotency(store, ids[:idem], org, command, key_digest, request_sha256, ids[:execution], ids[:result], now)
          end
          Platform::CommandResult.failure(result_id: ids[:result], command_type: command.command_type,
                                          failure:, audit_record_id: ids[:audit], correlation_id: ctx.correlation_id)
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

        # ---- writers -------------------------------------------------------------

        def write_execution(store, command, ctx, org, id, request_sha256, key_digest, now)
          store.insert_command_execution(
            id:, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, idempotency_key_digest: key_digest,
            command_type: command.command_type, command_schema_version: command.schema_version,
            service_identity_id: ctx.service_identity_id, organization_id: org, target_type: TARGET_TYPE,
            target_id: command.verification_request_id, action: ACTION,
            requested_at: iso(command.requested_at_utc), authorization_check_at: iso(now),
            policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            canonical_payload: JSON.generate({ "scheduled_action_id" => command.action_id }), request_sha256:
          )
        end

        def write_audit(store, id, org, ctx, command, entity_id, to_state:, outcome:, reason_code:, payload:, now:)
          store.insert_audit(
            id:, occurred_at: iso(now), partition_month: month(now), organization_id: org,
            service_identity_id: ctx.service_identity_id, correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id, entity_type: TARGET_TYPE,
            entity_id:, to_state:, outcome:, reason_code:, payload: JSON.generate(payload),
            content_sha256: Platform::CanonicalJson.digest(payload)
          )
        end

        def write_event(store, ids, org, ctx, command, now, aggregate_version, row, request_sha256, key_digest,
                        type, profile, extra)
          envelope = {
            "account_id" => nil, "actor_id" => nil, "affected_entity_id" => command.verification_request_id,
            "affected_entity_type" => TARGET_TYPE, "aggregate_version" => aggregate_version,
            "audit_record_id" => ids[:audit], "causation_id" => ctx.correlation_id,
            "command_id" => command.command_id, "correlation_id" => ctx.correlation_id,
            "event_id" => ids[:event], "event_profile" => profile, "event_type" => type,
            "idempotency_identity_hash" => hex(key_digest), "input_hash" => hex(request_sha256),
            "occurred_at_utc" => now.iso8601(6), "organization_id" => org, "outcome" => "success",
            "project_id" => row["project_id"], "schema_version" => "1.0",
            "scheduled_action_id" => command.action_id, "service_identity_id" => ctx.service_identity_id,
            "verification_request_id" => command.verification_request_id, "workflow_id" => WORKFLOW_ID
          }.merge(extra)
          bytes = Platform::CanonicalJson.encode(envelope)
          store.insert_event(
            id: ids[:event], created_at: iso(now), event_type: type, event_profile: profile,
            occurred_at: iso(now), organization_id: org, aggregate_type: TARGET_TYPE,
            aggregate_id: command.verification_request_id, aggregate_version:, partition_month: month(now),
            correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, audit_record_id: ids[:audit],
            event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
          )
        end

        def write_result(store, ids, command, ctx, org, now, payload, failure: nil)
          store.insert_command_result(
            id: ids[:result], created_at: iso(now), correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id,
            command_execution_id: ids[:execution], outcome: failure ? "failure" : "success",
            organization_id: org, service_identity_id: ctx.service_identity_id, completed_at: iso(now),
            authorization_check_at: iso(now),
            target_refs: JSON.generate(failure ? {} : { TARGET_TYPE => command.verification_request_id }),
            governing_policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            failure:, authorized_payload: JSON.generate(payload), audit_record_id: ids[:audit]
          )
        end

        def write_idempotency(store, id, org, command, key_digest, request_sha256, execution_id, result_id, now)
          store.insert_idempotency(
            id:, created_at: iso(now), organization_id: org, command_type: command.command_type,
            target_type: TARGET_TYPE, target_id: command.verification_request_id, key_digest:, request_sha256:,
            command_execution_id: execution_id, command_result_id: result_id,
            retain_until: iso(now + (30 * 24 * 3600))
          )
        end

        def schema_failure(command, ctx) = in_memory_failure(command, ctx, "command_schema_unsupported")

        def in_memory_failure(command, ctx, reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                          failure:, audit_record_id: ctx.generate_id, correlation_id: ctx.correlation_id)
        end

        def request_hash(command, ctx)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "service_identity_id" => ctx.service_identity_id,
            "organization_id" => command.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => command.verification_request_id, "project_id" => nil,
            "policy_versions" => [POLICY_VERSION],
            "command_payload" => { "scheduled_action_identity_sha256" => hex(command.action_identity_sha256),
                                   "due_at" => command.due_at.getutc.iso8601(6) }
          })
        end

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
        def to_time(value) = value.respond_to?(:getutc) ? value.getutc : Time.parse(value).getutc
        def iso(time) = time&.getutc&.iso8601(6)
        def month(time) = Date.new(time.year, time.month, 1).iso8601
        def hex(bytes) = bytes.unpack1("H*")

        class LostRace < StandardError; end
      end
    end
  end
end
