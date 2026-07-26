# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf003
    module Handlers
      # WF-003 ObserveAutomatedSlot — the service-only automated observation behind a
      # ratified `verification_observation_slot` ScheduledAction that
      # IssueVerificationChallenge schedules (SCORE_EVIDENCE_MODEL.md :151-160;
      # contracts/S-05.json MTX-028 background_job/retry_policy; WORKFLOW_SPECIFICATIONS.md
      # § WF-003). One slot, resolved to exactly one of five outcomes under the per-Request
      # advisory lock:
      #
      #   * REBUILD — a prior execution already recorded this slot's skip (idempotent by
      #     the action identity), so it is replayed and nothing new is written.
      #   * RESUME — a prior execution already reserved (and perhaps completed) this slot's
      #     attempt, so the same attempt is completed rather than a second one reserved
      #     (the `one_automated_per_slot` index is the database backstop, so no slot is
      #     ever double-counted).
      #   * VOID — the Request is already terminal, so the slot records NOTHING: no
      #     attempt, no observation, no skip. This is how a terminal Request "cancels all
      #     remaining slots without skipped events" — the ratified harmless-terminal-
      #     execution pattern (the Invitation / expiry precedent), not a proactive cancel.
      #   * SKIP — the slot's half-open window has closed (now >= issued_at + next offset),
      #     so it is recorded once as `observation_slot_skipped` (a scheduler record, not a
      #     domain event and not fabricated Evidence) and never runs late.
      #   * OBSERVE — in window and pending: reserve one automated attempt (attempt_count +
      #     1, no on-demand counter or marker) and complete it through the S-05-005/006
      #     CompleteVerificationAttempt engine (its own provider-call-outside-the-
      #     transaction phasing; a matched observation before expiry commits the success).
      #
      # Service-executed: authority was established at Request creation (MTX-051 — the
      # automated schedule is the lifecycle service's own timer), so there is no Session
      # and no human actor. The slot's due offset is recovered as `due_at - issued_at`;
      # a due time that is not one of the ten ratified offsets is a malformed action and
      # quarantines as `scheduled_action_target_mismatch`.
      class ObserveAutomatedSlot
        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "verification_request"
        ACTION = "verification.observe"
        POLICY_VERSION = "permission-baseline-v1"
        WORKFLOW_ID = "WF-003"
        # The scheduler record for a slot whose window closed before it started
        # (contracts/S-05.json :41: "not a domain event and not fabricated Evidence").
        SKIP_REASON = "observation_slot_skipped"

        def call(command:, request_context:, outbound: Platform::Outbound)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)
          return in_memory_failure(command, ctx, "scheduled_action_target_mismatch") unless command.target_type == TARGET_TYPE

          # Phase 1 — resolve the slot under the per-Request lock. Returns either a
          # terminal :result (rebuild / void / skip / mismatch) or the :attempt_id to run.
          prep = Platform::UnitOfWork.run { |conn| reserve_or_resolve(conn.raw_connection, command, ctx) }
          return prep[:result] if prep[:result]

          # Phase 2 — run and record the observation under the reserved attempt. The
          # completion engine does its own read-reveal / provider-call / commit phases and
          # is idempotent by the attempt identity.
          complete(command, ctx, prep[:attempt_id], outbound)
        end

        private

        def reserve_or_resolve(pg, command, ctx)
          now = ctx.now_utc.floor(6)
          store = IdentityAccess::Infrastructure::VerificationObservationStore.new(pg)
          org = command.organization_id
          store.enter_org_context(org:, correlation_id: ctx.correlation_id)
          store.lock_verification_request(command.verification_request_id)

          row = store.read_request_for_slot(command.verification_request_id)
          d = { store:, command:, ctx:, org:, now: }
          # Not visible under the action's Organization context: the action and its target
          # disagree, which a correctly created action cannot do.
          return { result: deny(**d, reason: "scheduled_action_target_mismatch") } if row.nil?

          offset = slot_offset(command, row)
          # A due time that is not one of the ten ratified slot offsets: a malformed action.
          return { result: deny(**d, reason: "scheduled_action_target_mismatch") } if offset.nil?

          # A prior execution already recorded this slot's skip (idempotent by the action
          # identity): replay it and write nothing.
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org:, command_type: command.command_type, target_type: TARGET_TYPE,
                                            target_id: command.verification_request_id, key_digest:)
          return { result: rebuild(store, existing, command) } if existing

          # A prior execution already reserved (and perhaps completed) this slot's attempt:
          # resume it, never reserve a second one.
          attempt = store.find_automated_attempt(command.verification_request_id, offset)
          return { attempt_id: attempt["id"] } if attempt

          # A terminal Request voids its remaining slots without a skipped event.
          return { result: void_terminal(**d) } unless row["request_status"] == "pending"

          # The half-open window has closed: record the slot skipped once, never late.
          return { result: skip(**d, offset:) } if window_closed?(row, offset, now)

          # In window and pending: reserve the automated attempt, then complete it.
          { attempt_id: reserve(**d, row:, offset:) }
        end

        # The slot's due offset in minutes, recovered as due_at - issued_at. nil unless it
        # divides evenly into minutes AND is one of the ten ratified offsets.
        def slot_offset(command, row)
          issued_at = to_time(row["issued_at_utc"])
          seconds = (command.due_at.getutc - issued_at).round
          return nil unless (seconds % 60).zero?

          minutes = seconds / 60
          AutomatedObservationSlots.slot?(minutes) ? minutes : nil
        end

        # Half-open: the window closes at issued_at + the next offset (or expiry for the
        # last slot). At the exact boundary the window is closed and the later slot is
        # eligible, so `now >= window_end` is a skip.
        def window_closed?(row, offset, now)
          issued_at = to_time(row["issued_at_utc"])
          window_end = issued_at + (AutomatedObservationSlots.window_end_minutes(offset) * 60)
          now >= window_end
        end

        # Reserve one automated attempt (attempt_count + 1), guarded on the expected
        # Request state version under the lock. Returns the attempt id.
        def reserve(store:, command:, ctx:, org:, now:, row:, offset:)
          attempt_id = ctx.generate_id
          attempt_number = row["attempt_count"].to_i + 1
          store.insert_automated_attempt(
            id: attempt_id, now:, correlation_id: ctx.correlation_id, organization_id: org,
            project_id: row["project_id"], verification_request_id: command.verification_request_id,
            source_id: row["source_id"], attempt_number:, automated_slot_offset_minutes: offset
          )
          if store.reserve_automated_on_request(command.verification_request_id, row["state_version"].to_i, now).to_i.zero?
            raise LostRace
          end

          attempt_id
        rescue LostRace
          raise Platform::InvariantViolation, "verification request reserved concurrently"
        end

        # Run the reserved attempt through the S-05-005/006 completion engine. A new
        # command_id per invocation; idempotency is by the reserved attempt identity, so a
        # retry rebuilds rather than double-observing.
        def complete(command, ctx, attempt_id, outbound)
          complete_command = Commands::CompleteVerificationAttempt.new(
            command_id: ctx.generate_id, schema_version: command.schema_version,
            organization_id: command.organization_id, verification_request_id: command.verification_request_id,
            verification_attempt_id: attempt_id, requested_at_utc: command.requested_at_utc
          )
          Handlers::CompleteVerificationAttempt.new.call(command: complete_command, request_context: ctx, outbound:)
        end

        # ---- terminal outcomes ---------------------------------------------------

        # Harmless terminal execution: the Request is already terminal, so this slot
        # records nothing — no attempt, no observation, and (critically) no skip event.
        # A retry re-evaluates and voids again, changing nothing.
        def void_terminal(store:, command:, ctx:, org:, now:)
          Platform::CommandResult.success(
            result_id: ctx.generate_id, command_type: command.command_type,
            audit_record_id: ctx.generate_id, correlation_id: ctx.correlation_id,
            payload: { verification_request_id: command.verification_request_id,
                       request_status: "terminal", observation: "voided" }
          )
        end

        # Record the slot skipped exactly once (idempotent by the action identity), a
        # scheduler decision with no attempt, no Evidence and no domain event.
        def skip(store:, command:, ctx:, org:, now:, offset:)
          ids = %i[execution audit result idem].to_h { |k| [k, ctx.generate_id] }
          request_sha256 = request_hash(command, ctx)
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          payload = { "verification_request_id" => command.verification_request_id, "organization_id" => org,
                      "automated_slot_offset_minutes" => offset, "outcome" => "skipped",
                      "reason_code" => SKIP_REASON, "scheduled_action_id" => command.action_id }
          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          write_audit(store, ids[:audit], org, ctx, command, command.verification_request_id,
                      to_state: nil, outcome: "success", reason_code: SKIP_REASON, payload:, now:)
          write_result(store, ids, command, ctx, org, now, payload)
          write_idempotency(store, ids[:idem], org, command, key_digest, request_sha256, ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        # A transport-integrity deviation (the action does not match its target): a
        # failure the worker quarantines (QUARANTINE_REASONS), recorded in the service
        # ledger for the decision trail.
        def deny(store:, command:, ctx:, org:, now:, reason:)
          ids = %i[execution audit result].to_h { |k| [k, ctx.generate_id] }
          request_sha256 = request_hash(command, ctx)
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          write_audit(store, ids[:audit], org, ctx, command, command.verification_request_id, to_state: nil,
                      outcome: "failure", reason_code: reason,
                      payload: { "verification_request_id" => command.verification_request_id,
                                 "organization_id" => org, "internal_reason" => reason,
                                 "scheduled_action_id" => command.action_id }, now:)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          write_result(store, ids, command, ctx, org, now, {}, failure:)
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

        # ---- writers (service-attributed, via VerificationObservationStore) ------

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

        def schema_failure(command, ctx) = in_memory_failure(command, ctx, "command_schema_unsupported")

        def in_memory_failure(command, ctx, reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                          failure:, audit_record_id: ctx.generate_id, correlation_id: ctx.correlation_id)
        end

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
        def iso(time) = time&.getutc&.iso8601(6)
        def month(time) = Date.new(time.year, time.month, 1).iso8601
        def hex(bytes) = bytes.unpack1("H*")
        def to_time(value) = value.respond_to?(:getutc) ? value.getutc : Time.parse(value).getutc

        class LostRace < StandardError; end
      end
    end
  end
end
