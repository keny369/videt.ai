# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf013
    module Handlers
      # WF-013 SuspendOrganization — the transition that changes what every
      # Session and every authorization decision in the Organization means.
      #
      # ONE transaction does all of it (contracts/S-23.json MTX-038): "changing
      # active to suspended, recording the reason, incrementing both versions,
      # revoking every active human Session and preventing new scheduled work."
      # There is no eventual cleanup and no second pass — the state change, the
      # authorization-epoch advance and the Session revocations commit together or
      # not at all, and a database trigger refuses a status change that does not
      # advance the epoch, so the two cannot come apart even by mistake.
      #
      # Authority invalidation is therefore doubly enforced afterwards, by the
      # SHARED boundary rather than by scattered checks: `CommandAuthorizer#authenticate`
      # already rejects a non-active Session (`session_invalid`) and a non-active
      # Organization (`organization_inactive`), so every Session-authenticated
      # command in the Organization fails closed without a single new
      # `organization.suspended?` test in any handler.
      class SuspendOrganization
        include InvitationLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "organization"
        ACTION = "organization.suspend"
        CAPABILITY = "organization.suspend"
        REASON_MAX = 2000

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          reason = normalize_reason(command.reason)
          return in_memory_failure(command, ctx, "organization_reason_invalid") if reason == :invalid

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
            auth = IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
            store = IdentityAccess::Infrastructure::OrganizationLifecycleStore.new(pg)

            actor = auth.authenticate(session_id: command.session_id, now:, correlation_id: ctx.correlation_id)
            return in_memory_failure(command, ctx, actor.to_s) if actor.is_a?(Symbol)

            decision = auth.authorize(actor:, capability: CAPABILITY, now:)
            d = { command:, ctx:, pg:, store:, auth_store:, actor:, decision:,
                  org: actor.organization_id, now:, offer: nil }

            unless decision.allowed?
              return deny(**d, invitation_id: actor.organization_id, outward: decision.reason,
                          internal: decision.reason)
            end

            process(**d, reason:)
          end
        end

        private

        def process(command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer:, reason:)
          d = { command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer: }
          store.lock_organization(org)
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          request_sha256 = request_hash(command, ctx, actor, reason)

          existing = store.find_idempotency(org:, command_type: command.command_type, target_type: TARGET_TYPE,
                                            target_id: org, key_digest:)
          if existing
            return replay(store, command, existing) if existing["request_hex"] == hex(request_sha256)

            return deny(**d, invitation_id: org, outward: "idempotency_conflict", internal: "idempotency_conflict")
          end

          row = store.read_organization(org)
          unless row && row["status"] == "active"
            return deny(**d, invitation_id: org, outward: "organization_state_invalid",
                        internal: "organization_state_invalid")
          end
          unless command.expected_state_version == row["state_version"].to_i
            return deny(**d, invitation_id: org, outward: "stale_state_version", internal: "stale_state_version")
          end
          unless command.expected_authorization_epoch == row["authorization_epoch"].to_i
            return deny(**d, invitation_id: org, outward: "stale_authorization_epoch",
                        internal: "stale_authorization_epoch")
          end

          commit(**d, row:, reason:, key_digest:, request_sha256:)
        end

        def commit(command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer:,
                   row:, reason:, key_digest:, request_sha256:)
          ids = %i[execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          new_version = row["state_version"].to_i + 1
          new_epoch = row["authorization_epoch"].to_i + 1

          write_execution(store, command, ctx, org, ids[:execution], org, actor, request_sha256, key_digest,
                          now, ACTION)
          write_authorization_decision(auth_store, ids[:decision], ctx, command, actor, decision, now, org, ACTION)

          changed = store.suspend(org, row["state_version"].to_i, row["authorization_epoch"].to_i, now, reason)
          raise LostRace if changed.to_i.zero?

          # Same transaction, not a follow-up: every human Session of this
          # Organization is revoked before this command can return.
          revoked = store.revoke_active_sessions(org, now)

          payload = { "organization_id" => org, "state" => "suspended", "state_version" => new_version,
                      "authorization_epoch" => new_epoch, "revoked_session_count" => revoked }
          write_audit(store, ids[:audit], org, ctx, command, org, actor, to_state: "suspended",
                      outcome: "success", reason_code: nil,
                      payload: payload.merge("reason" => reason), now:)
          write_event(store, ids, org, ctx, command, actor, now, new_version, org, request_sha256, key_digest,
                      actor.account_id, "OrganizationSuspended", "state_transition",
                      { "from_state" => "active", "to_state" => "suspended",
                        "organization_epoch" => new_epoch, "reason" => reason,
                        "revoked_session_count" => revoked })
          write_result_success(store, ids, command, ctx, org, actor, now, payload, org)
          write_idempotency(store, ids[:idem], org, command, org, key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        rescue LostRace
          raise Platform::InvariantViolation, "organization transitioned concurrently"
        end

        def replay(store, command, existing)
          stored = store.load_command_result(existing["command_result_id"])
          payload = JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym)
          Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type, payload:,
                                          audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end

        # ":230 nullable lifecycle reason" — a reason is recorded when supplied and
        # is bounded, but the record does not require one.
        def normalize_reason(raw)
          return nil if raw.nil?

          trimmed = raw.to_s.strip
          return :invalid if trimmed.empty? || trimmed.length > REASON_MAX

          trimmed
        end

        def request_hash(command, ctx, actor, reason)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "actor_id" => actor.account_id,
            "organization_id" => actor.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => actor.organization_id, "project_id" => nil,
            "expected_version" => command.expected_state_version,
            "expected_authorization_epoch" => command.expected_authorization_epoch,
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => { "reason" => reason }
          })
        end

        def canonical_payload_json(command)
          JSON.generate({ "expected_state_version" => command.expected_state_version,
                          "expected_authorization_epoch" => command.expected_authorization_epoch })
        end

        class LostRace < StandardError; end
      end
    end
  end
end
