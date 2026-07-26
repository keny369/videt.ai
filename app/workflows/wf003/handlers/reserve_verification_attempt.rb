# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf003
    module Handlers
      # WF-003 ReserveVerificationAttempt (APPLICATION_LAYER.md § WF-003; CAP-005
      # MTX-028; SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And Evidence;
      # contracts/S-05.json). The on-demand reservation limb: an authorized Organization
      # actor requests one on-demand observation of a pending Verification Request, and
      # the accepted command reserves the next attempt slot ATOMICALLY — it assigns the
      # attempt ID, increments the total and on-demand attempt counts and stores the
      # in-progress marker — before any provider call, so concurrent commands cannot
      # reserve the same slot.
      #
      # The order of outcomes: the envelope-schema rejection (from input alone), the
      # authentication reasons, then — under the per-Request advisory lock — the
      # tenant checks (`tenant_mismatch`), the capability (`source_verify_unauthorized`),
      # the exact idempotent replay (checked BEFORE the version so a legitimate retry is
      # never mis-flagged stale, since a successful reserve advances the state version),
      # `stale_state_version`, and finally the acceptance or one of the on-demand
      # denials: `verification_request_not_pending` (a terminal Request),
      # `on_demand_limit_reached` (count = 10), `on_demand_observation_in_progress`
      # (marker set), `on_demand_rate_limited` (within 5 minutes of the last completion;
      # equality at the boundary is allowed), and `idempotency_conflict` (the same key
      # reused with different canonical content). A denied command writes NO attempt and
      # never increments `attempt_count` (contracts/S-05.json idempotency: "a rejected
      # ... request never increments it").
      #
      # This limb only RESERVES. It never runs DNS/HTTP, produces Evidence, emits
      # `SourceVerificationObserved`, completes or quarantines the attempt, or
      # transitions the Request or Source; each is a later WF-003 limb. No domain event
      # is emitted on reservation.
      class ReserveVerificationAttempt
        include VerificationLedger

        TARGET_TYPE = "verification_request"
        ACTION = "source.verify"
        CAPABILITY = "source.verify"
        WORKFLOW_ID = "WF-003"

        ATTEMPT_SCHEMA_VERSION = "verification-attempt-v1"
        ORIGIN = "on_demand"
        ON_DEMAND_LIMIT = 10
        RATE_LIMIT_SECONDS = 5 * 60

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless VerificationChallenge.supported_schema?(command.schema_version)

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
            auth = IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
            store = IdentityAccess::Infrastructure::VerificationRequestStore.new(pg)

            actor = auth.authenticate(session_id: command.session_id, now:, correlation_id: ctx.correlation_id)
            return in_memory_failure(command, ctx, actor.to_s) if actor.is_a?(Symbol)

            request_sha256 = request_hash(command, actor)
            d = { command:, ctx:, store:, auth_store:, actor:, org: actor.organization_id, now:, request_sha256: }
            process(d, auth)
          end
        end

        private

        def process(d, auth)
          command = d[:command]
          store = d[:store]
          actor = d[:actor]
          now = d[:now]

          # Serialize on the Request before reading it, so the guard reads and the
          # count/marker update are one critical section.
          store.lock_verification_request(command.verification_request_id)
          row = store.read_verification_request_for_reserve(command.verification_request_id)

          # Not found in the actor's proved context: another Organization's or
          # nonexistent, refused without disclosure.
          return denied(d, "tenant_mismatch", source_id: nil) if row.nil? || row["organization_id"] != actor.organization_id
          return denied(d, "tenant_mismatch", source_id: row["source_id"]) unless command.organization_id == actor.organization_id
          return denied(d, "tenant_mismatch", source_id: row["source_id"]) unless command.project_id == row["project_id"]

          decision = auth.authorize(actor:, capability: CAPABILITY, now:)
          d = d.merge(decision:, row:)
          unless decision.allowed?
            outward = decision.reason == "missing_authority" ? "source_verify_unauthorized" : decision.reason
            return deny(**denial_args(d), resource_id: row["source_id"], outward:, internal: outward)
          end

          # Idempotency FIRST: an exact replay must return the same reserved attempt
          # even though a successful reserve advances the Request's state_version, so
          # the version check below must not turn a legitimate retry into a stale error.
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org: d[:org], command_type: command.command_type,
                                            target_type: TARGET_TYPE, target_id: command.verification_request_id,
                                            key_digest:)
          return replay(d, existing) if existing && existing["request_hex"] == hex(d[:request_sha256])

          # On-demand requires the expected Request state version (MTX-028 concurrency).
          unless row["state_version"].to_i == command.expected_state_version
            return denied(d, "stale_state_version", source_id: row["source_id"])
          end

          # A terminal Request cannot reserve a new observation.
          unless row["request_status"] == "pending"
            return denied(d, "verification_request_not_pending", source_id: row["source_id"])
          end
          # The three on-demand denials, in the error_contract's stated order. None
          # writes an attempt or increments any count.
          if row["on_demand_observation_count"].to_i >= ON_DEMAND_LIMIT
            return denied(d, "on_demand_limit_reached", source_id: row["source_id"])
          end
          unless row["on_demand_in_progress_attempt_id"].nil?
            return denied(d, "on_demand_observation_in_progress", source_id: row["source_id"])
          end
          return denied(d, "on_demand_rate_limited", source_id: row["source_id"]) if rate_limited?(row, now)
          # Same idempotency key, different canonical content.
          return denied(d, "idempotency_conflict", source_id: row["source_id"]) if existing

          reserve(d, row, key_digest)
        end

        def reserve(d, row, key_digest)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]
          actor = d[:actor]
          request_sha256 = d[:request_sha256]

          ids = %i[execution attempt audit result decision idem].to_h { |k| [k, ctx.generate_id] }
          attempt_id = ids[:attempt]
          attempt_number = row["attempt_count"].to_i + 1

          write_execution(store, command, ctx, org, ids[:execution], command.verification_request_id, actor,
                          request_sha256, key_digest, now, ACTION)
          write_authorization_decision(d[:auth_store], ids[:decision], ctx, command, actor, d[:decision], now,
                                       row["source_id"], ACTION)
          store.insert_verification_attempt(
            id: attempt_id, now:, correlation_id: ctx.correlation_id, schema_version: ATTEMPT_SCHEMA_VERSION,
            organization_id: org, project_id: row["project_id"],
            verification_request_id: command.verification_request_id, source_id: row["source_id"],
            attempt_number:, origin: ORIGIN
          )
          # The atomic count/marker update, guarded on the state version read under the
          # lock. A zero row count is a Request that changed underneath us — a lost race.
          affected = store.reserve_on_request(command.verification_request_id, row["state_version"].to_i, attempt_id, now)
          raise LostRace if affected.to_i.zero?

          payload = {
            "verification_request_id" => command.verification_request_id, "verification_attempt_id" => attempt_id,
            "attempt_number" => attempt_number, "origin" => ORIGIN, "request_status" => "pending",
            "state_version" => row["state_version"].to_i + 1, "attempt_count" => attempt_number,
            "on_demand_observation_count" => row["on_demand_observation_count"].to_i + 1
          }
          write_audit(store, ids[:audit], org, ctx, command, command.verification_request_id, actor,
                      to_state: "pending", outcome: "success", reason_code: nil, payload:, now:)
          write_result_success(store, ids, command, ctx, org, actor, now, payload, command.verification_request_id)
          write_idempotency(store, ids[:idem], org, command, command.verification_request_id, key_digest,
                            request_sha256, ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        rescue LostRace
          raise Platform::InvariantViolation, "verification request reserved concurrently"
        end

        # An exact idempotent replay: the reservation already committed for this key, so
        # rebuild and return its recorded result without reserving a second attempt.
        def replay(d, existing)
          store = d[:store]
          command = d[:command]
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

        # A denial whose authorization decision is an allow (a tenant/state/duplicate/
        # rate refusal of an authorized actor) or precedes the capability evaluation,
        # with the real (or synthesized not-yet-evaluated) decision recorded.
        def denied(d, reason, source_id:)
          decision = d[:decision] || pre_authorization_decision(d[:actor])
          deny(**denial_args(d.merge(decision:)), resource_id: source_id, outward: reason, internal: reason)
        end

        # An audited no-attempt outcome for an authenticated actor: execution,
        # authorization decision, audit and result, no attempt and no counter change.
        # This is the WF-003 shared `deny` (VerificationLedger) specialized to the
        # reserve command, whose target is the Verification Request (it carries no
        # source_id of its own; `resource_id` names the Source for the authorization
        # decision). No idempotency record is written, so a denied command re-evaluates
        # on retry and never increments attempt_count.
        def deny(command:, ctx:, store:, auth_store:, actor:, decision:, org:, now:, request_sha256:,
                 resource_id:, outward:, internal:)
          ids = %i[execution audit result decision].to_h { |k| [k, ctx.generate_id] }
          key_digest = Digest::SHA256.digest(command.idempotency_key)

          write_execution(store, command, ctx, org, ids[:execution], command.verification_request_id, actor,
                          request_sha256, key_digest, now, ACTION)
          write_authorization_decision(auth_store, ids[:decision], ctx, command, actor, decision, now,
                                       resource_id, ACTION)
          write_audit(store, ids[:audit], org, ctx, command, command.verification_request_id, actor,
                      to_state: nil, outcome: "failure", reason_code: internal,
                      payload: { "outcome" => "failure", "internal_reason" => internal, "outward_reason" => outward,
                                 "organization_id" => org, "project_id" => command.project_id,
                                 "verification_request_id" => command.verification_request_id }, now:)
          failure = Platform::ErrorCatalog.failure(outward, support_reference: ctx.correlation_id)
          write_result_failure(store, ids[:result], ids[:execution], command, ctx, org, actor, ids[:audit],
                               failure, now)
          Platform::CommandResult.failure(result_id: ids[:result], command_type: command.command_type,
                                          failure:, audit_record_id: ids[:audit], correlation_id: ctx.correlation_id)
        end

        def denial_args(d)
          { command: d[:command], ctx: d[:ctx], store: d[:store], auth_store: d[:auth_store], actor: d[:actor],
            decision: d[:decision], org: d[:org], now: d[:now], request_sha256: d[:request_sha256] }
        end

        def pre_authorization_decision(actor)
          IdentityAccess::Authorization::Decision.new(
            allowed: false, reason: "not_evaluated", organization_epoch: actor.authorization_epoch,
            policy_snapshot_id: nil, role_assignment_versions: [], granting_assignments: []
          )
        end

        # Within 5 minutes of the last completed on-demand observation. Equality at
        # exactly 5 minutes is allowed (now < boundary is false at the boundary).
        def rate_limited?(row, now)
          last = row["last_on_demand_completed_at_utc"]
          return false if last.nil?

          now < to_time(last) + RATE_LIMIT_SECONDS
        end

        # The canonical request hash: the shared envelope with the Request as target and
        # the expected Request version in the expected-version slot. Generated
        # identifiers, the idempotency key, the requested time and transport metadata
        # are excluded, so a replay under a new command_id is still a replay and a
        # different Request or expected version under the same key is a conflict.
        def request_hash(command, actor)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "actor_id" => actor.account_id,
            "organization_id" => actor.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => command.verification_request_id, "project_id" => command.project_id,
            "expected_version" => command.expected_state_version,
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => { "origin" => ORIGIN }
          })
        end

        def to_time(value) = value.respond_to?(:getutc) ? value.getutc : Time.parse(value).getutc

        class LostRace < StandardError; end
      end
    end
  end
end
