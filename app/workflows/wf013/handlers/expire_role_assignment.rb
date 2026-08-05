# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf013
    module Handlers
      # WF-013 ExpireRoleAssignment — the service-only timed expiry behind the
      # ratified `role_assignment_expire` ScheduledAction (BACKGROUND_PROCESSING.md
      # :132, :192, :406; WORKFLOW_SPECIFICATIONS.md :316, :343-351).
      #
      # Two branches, and the contract names both:
      #
      #   ORDINARY   an active Assignment past its expiry instant becomes `expired`,
      #              advancing the Organization authorization epoch in the same
      #              transaction and emitting `RoleExpired`.
      #   BLOCKED    ":316 Before an expiry that would remove the last effective
      #              OrganizationAdmin, the lifecycle service serializes on the
      #              Organization authorization epoch and leaves the Assignment
      #              active with `expiry_blocked_last_admin`, emits
      #              `RoleExpiryBlocked`, and … never silently strands the tenant."
      #
      # The blocked branch writes a durable immutable `RoleExpiryBlockDecision`
      # BEFORE the event that names it as its affected entity (:348), keyed
      # idempotently on (role_assignment_id, authorization_epoch) (:350) so a retry
      # inside an unchanged epoch writes no second decision and emits no second
      # event. It advances no epoch: no authority changed.
      #
      # Authority is not checked here and there is none to check — expiry is the
      # role-expiry lifecycle service's own timer, so no Permission Baseline, no
      # Session, no human actor. The ledger is service-attributed with a null
      # actor.
      class ExpireRoleAssignment
        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "role_assignment"
        ACTION = "role.expire"
        POLICY_VERSION = "permission-baseline-v1"
        BLOCK_REASON = "expiry_blocked_last_admin"
        TRANSITION_REASON_CODE = "role_assignment_expired"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)
          return in_memory_failure(command, ctx, "scheduled_action_target_mismatch") unless command.target_type == TARGET_TYPE

          key_digest = Digest::SHA256.digest(command.action_identity_sha256)

          Platform::UnitOfWork.run do |conn|
            now = ctx.now_utc.floor(6)
            store = IdentityAccess::Infrastructure::RoleExpiryStore.new(conn.raw_connection)
            org = command.organization_id

            store.enter_org_context(org:, correlation_id: ctx.correlation_id)
            # The epoch is the ratified serialization point for effective access,
            # and the Assignment lock is the one revoke also takes.
            store.lock_organization(org)
            store.lock_role_assignment(command.role_assignment_id)

            process(store:, command:, ctx:, org:, now:, key_digest:)
          end
        end

        private

        def process(store:, command:, ctx:, org:, now:, key_digest:)
          request_sha256 = request_hash(command, ctx)
          d = { store:, command:, ctx:, org:, now:, key_digest:, request_sha256: }

          row = store.read(command.role_assignment_id)
          # Not visible under the action's Organization context: the action and its
          # target disagree, which a correctly created action cannot do.
          if row.nil?
            return deny(**d, outward: "scheduled_action_target_mismatch",
                        internal: "scheduled_action_target_mismatch", replayable: false)
          end

          existing = store.find_idempotency(org:, command_type: command.command_type, target_type: TARGET_TYPE,
                                            target_id: command.role_assignment_id, key_digest:)
          if existing
            return rebuild(store, existing, command) if existing["request_hex"] == hex(request_sha256)

            return deny(**d, outward: "idempotency_conflict", internal: "idempotency_conflict", replayable: false)
          end

          expires_at = row["expires_at"] && to_time(row["expires_at"])
          if expires_at.nil? || command.due_at != expires_at
            return deny(**d, outward: "scheduled_action_target_mismatch",
                        internal: "scheduled_action_target_mismatch", replayable: false)
          end
          if now < expires_at
            return deny(**d, outward: "scheduled_action_not_due", internal: "scheduled_action_not_due",
                        replayable: false)
          end

          # ":316 revoked, rejected and expired are terminal." A timer arriving
          # after another transition is the canonical harmless completion.
          unless row["status"] == "active"
            return deny(**d, outward: "role_assignment_not_active", internal: "role_assignment_not_active")
          end

          if blocks_last_admin?(store, row, now)
            return block(**d, row:)
          end

          expire(**d, row:)
        end

        # ":344 the expiry is blocked when committing it would leave the
        # Organization with no OTHER Account holding an active, in-scope Role
        # Assignment conferring effective OrganizationAdmin authority."
        def blocks_last_admin?(store, row, now)
          return false unless row["canonical_role"] == "OrganizationAdmin"

          store.other_effective_admins(role_assignment_id: row["id"], account_id: row["account_id"],
                                       now:).zero?
        end

        # ---- ordinary expiry -----------------------------------------------------

        def expire(store:, command:, ctx:, org:, now:, key_digest:, request_sha256:, row:)
          ids = %i[execution audit event result idem].to_h { |k| [k, ctx.generate_id] }
          epoch = store.organization_epoch(org)
          new_version = row["state_version"].to_i + 1

          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          # THE EPOCH ADVANCE COMES FIRST — one lock order for the two authority rows, everywhere
          # (round-15 concurrency finding R15-CONC-1; see `RevokeRoleAssignment` for the cycle this
          # closes). A timed expiry is the same shape as a revocation: it takes an active grant's row
          # and then the Organization's, which is the reverse of the order every WF-005 protected
          # write takes them in.
          raise LostRace if store.advance_authorization_epoch(org, epoch, now).to_i.zero?
          raise LostRace if store.expire(command.role_assignment_id, row["state_version"].to_i, now).to_i.zero?

          payload = { "role_assignment_id" => command.role_assignment_id, "organization_id" => org,
                      "account_id" => row["account_id"], "status" => "expired",
                      "authorization_epoch" => epoch + 1 }
          write_audit(store, ids[:audit], org, ctx, command, command.role_assignment_id,
                      to_state: "expired", outcome: "success", reason_code: TRANSITION_REASON_CODE,
                      payload:, now:)
          write_event(store, ids, org, ctx, command, now, new_version, command.role_assignment_id,
                      request_sha256, key_digest, "RoleExpired", "state_transition", TARGET_TYPE,
                      { "from_state" => "active", "to_state" => "expired",
                        "organization_epoch" => epoch + 1,
                        "transition_reason_code" => TRANSITION_REASON_CODE,
                        "reason_code" => TRANSITION_REASON_CODE })
          write_result(store, ids, command, ctx, org, now, payload)
          write_idempotency(store, ids[:idem], org, command, key_digest, request_sha256, ids[:execution],
                            ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        rescue LostRace
          raise Platform::InvariantViolation, "role assignment transitioned concurrently"
        end

        # ---- blocked expiry ------------------------------------------------------

        # The Assignment stays ACTIVE and effective past its expiry instant, the
        # immutable decision is persisted, and `RoleExpiryBlocked` names it. No
        # authority changed, so no epoch advance.
        def block(store:, command:, ctx:, org:, now:, key_digest:, request_sha256:, row:)
          ids = %i[execution audit event result idem].to_h { |k| [k, ctx.generate_id] }
          epoch = store.organization_epoch(org)

          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          decision = store.record_block_decision(
            id: ctx.generate_id, created_at: iso(now), organization_id: org,
            role_assignment_id: command.role_assignment_id,
            assignment_expires_at: iso(to_time(row["expires_at"])), authorization_epoch: epoch,
            predicate_result: { "other_effective_organization_admins" => 0,
                                "evaluated_at_utc" => now.iso8601(6) },
            decided_at: iso(now), correlation_id: ctx.correlation_id
          )

          payload = { "role_assignment_id" => command.role_assignment_id, "organization_id" => org,
                      "account_id" => row["account_id"], "status" => "active",
                      "block_reason" => BLOCK_REASON, "authorization_epoch" => epoch,
                      "role_expiry_block_decision_id" => decision[:id] }
          write_audit(store, ids[:audit], org, ctx, command, command.role_assignment_id,
                      to_state: nil, outcome: "failure", reason_code: BLOCK_REASON, payload:, now:)

          # ":350 Re-evaluating the same Assignment within an unchanged epoch writes
          # no second decision and emits no second `RoleExpiryBlocked`."
          unless decision[:replayed]
            write_event(store, ids, org, ctx, command, now, 0, decision[:id], request_sha256, key_digest,
                        "RoleExpiryBlocked", "decision", "role_expiry_block_decision",
                        { "decision_id" => decision[:id], "role_assignment_id" => command.role_assignment_id,
                          "expires_at_utc" => to_time(row["expires_at"]).iso8601(6),
                          "organization_epoch" => epoch, "decision_reason_code" => BLOCK_REASON,
                          "reason_code" => BLOCK_REASON })
          end
          write_result(store, ids, command, ctx, org, now, payload)
          write_idempotency(store, ids[:idem], org, command, key_digest, request_sha256, ids[:execution],
                            ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        # ---- audited no-state outcome --------------------------------------------

        def deny(store:, command:, ctx:, org:, now:, key_digest:, request_sha256:, outward:, internal:,
                 replayable: true)
          ids = %i[execution audit result idem].to_h { |k| [k, ctx.generate_id] }
          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          write_audit(store, ids[:audit], org, ctx, command, command.role_assignment_id, to_state: nil,
                      outcome: "failure", reason_code: internal,
                      payload: { "role_assignment_id" => command.role_assignment_id,
                                 "organization_id" => org, "internal_reason" => internal,
                                 "outward_reason" => outward,
                                 "scheduled_action_id" => command.action_id }, now:)
          failure = Platform::ErrorCatalog.failure(outward, support_reference: ctx.correlation_id)
          write_result(store, ids, command, ctx, org, now, {}, failure:)
          if replayable
            write_idempotency(store, ids[:idem], org, command, key_digest, request_sha256,
                              ids[:execution], ids[:result], now)
          end
          Platform::CommandResult.failure(result_id: ids[:result], command_type: command.command_type,
                                          failure:, audit_record_id: ids[:audit],
                                          correlation_id: ctx.correlation_id)
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
            target_id: command.role_assignment_id, action: ACTION,
            requested_at: iso(command.requested_at_utc), authorization_check_at: iso(now),
            policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            canonical_payload: JSON.generate({ "scheduled_action_id" => command.action_id }),
            request_sha256:
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

        def write_event(store, ids, org, ctx, command, now, aggregate_version, aggregate_id, request_sha256,
                        key_digest, type, profile, aggregate_type, extra)
          envelope = {
            "account_id" => nil, "actor_id" => nil, "affected_entity_id" => aggregate_id,
            "affected_entity_type" => aggregate_type, "aggregate_version" => aggregate_version,
            "audit_record_id" => ids[:audit], "causation_id" => ctx.correlation_id,
            "command_id" => command.command_id, "correlation_id" => ctx.correlation_id,
            "event_id" => ids[:event], "event_profile" => profile, "event_type" => type,
            "idempotency_identity_hash" => hex(key_digest), "input_hash" => hex(request_sha256),
            "occurred_at_utc" => now.iso8601(6), "organization_id" => org, "outcome" => "success",
            "project_id" => nil, "schema_version" => "1.0",
            "scheduled_action_id" => command.action_id,
            "service_identity_id" => ctx.service_identity_id, "workflow_id" => "WF-013"
          }.merge(extra)
          bytes = Platform::CanonicalJson.encode(envelope)
          store.insert_event(
            id: ids[:event], created_at: iso(now), event_type: type, event_profile: profile,
            occurred_at: iso(now), organization_id: org, aggregate_type:, aggregate_id:,
            aggregate_version:, partition_month: month(now), correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id,
            audit_record_id: ids[:audit], event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
          )
        end

        def write_result(store, ids, command, ctx, org, now, payload, failure: nil)
          store.insert_command_result(
            id: ids[:result], created_at: iso(now), correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id,
            command_execution_id: ids[:execution], outcome: failure ? "failure" : "success",
            organization_id: org, service_identity_id: ctx.service_identity_id, completed_at: iso(now),
            authorization_check_at: iso(now),
            target_refs: JSON.generate(failure ? {} : { "role_assignment" => command.role_assignment_id }),
            governing_policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            failure:, authorized_payload: JSON.generate(payload), audit_record_id: ids[:audit]
          )
        end

        def write_idempotency(store, id, org, command, key_digest, request_sha256, execution_id, result_id, now)
          store.insert_idempotency(
            id:, created_at: iso(now), organization_id: org, command_type: command.command_type,
            target_type: TARGET_TYPE, target_id: command.role_assignment_id, key_digest:, request_sha256:,
            command_execution_id: execution_id, command_result_id: result_id,
            retain_until: iso(now + (30 * 24 * 3600))
          )
        end

        def schema_failure(command, ctx) = in_memory_failure(command, ctx, "command_schema_unsupported")

        def in_memory_failure(command, ctx, reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                          failure:, audit_record_id: ctx.generate_id,
                                          correlation_id: ctx.correlation_id)
        end

        def request_hash(command, ctx)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version,
            "service_identity_id" => ctx.service_identity_id,
            "organization_id" => command.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => command.role_assignment_id, "project_id" => nil,
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
