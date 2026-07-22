# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf013
    module Handlers
      # WF-013 DecideInvitation — the protected branch's activation
      # (WORKFLOW_SPECIFICATIONS.md :242 "A different SecurityOperator holding
      # `invitation.approve` may activate it"; :333 "They require approval within
      # 24 hours by a SecurityOperator other than the requester and an active
      # expiry under the rule above. Unapproved requests expire; rejection or
      # expiry grants nothing").
      #
      # Authority is three separate predicates, not one:
      #   1. the Permission Baseline allow for `invitation.approve` (SecurityOperator);
      #   2. the PROTECTED EXPLICIT GRANT its baseline cell demands — the capability
      #      must appear in the deciding Assignment's approved protected allowlist
      #      (:314), because a baseline allow alone is not a protected grant; and
      #   3. separation of duty — the approver must not be the requester.
      #
      # Approval activates through the same `InvitationActivation` routine
      # CreateInvitation uses, so the expiry timer is created in this transaction
      # and the two commit or roll back together. Rejection is terminal, emits
      # `InvitationRejected`, and creates no timer.
      class DecideInvitation
        include InvitationLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "invitation"
        ACTION = "invitation.approve"
        CAPABILITY = "invitation.approve"
        APPROVER_ROLE = "SecurityOperator"
        REASON_MIN = 20
        REASON_MAX = 2000

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)
          return in_memory_failure(command, ctx, "command_schema_unsupported") unless %w[approve reject].include?(command.decision)

          reason = normalize_reason(command)
          return in_memory_failure(command, ctx, "invitation_reason_invalid") if reason == :invalid

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
            auth = IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
            store = IdentityAccess::Infrastructure::InvitationAdminStore.new(pg)

            actor = auth.authenticate(session_id: command.session_id, now:, correlation_id: ctx.correlation_id)
            return in_memory_failure(command, ctx, actor.to_s) if actor.is_a?(Symbol)

            decision = auth.authorize(actor:, capability: CAPABILITY, now:)
            d = { command:, ctx:, pg:, store:, auth_store:, actor:, decision:,
                  org: actor.organization_id, now:, offer: nil }

            unless decision.allowed?
              return deny(**d, invitation_id: nil, outward: decision.reason, internal: decision.reason)
            end

            # The protected explicit grant, checked before the target is read.
            allowlist = store.protected_allowlist(account_id: actor.account_id, canonical_role: APPROVER_ROLE)
            unless Platform::PermissionBaseline.protected_grant?(CAPABILITY, allowlist)
              return deny(**d, invitation_id: nil, outward: "missing_authority", internal: "protected_grant_required")
            end

            process(**d, reason:)
          end
        end

        private

        def process(command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer:, reason:)
          d = { command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer: }

          store.lock_invitation(command.invitation_id)
          inv = store.read_invitation(command.invitation_id)
          # Not visible under the actor's Organization context: the non-disclosing
          # outcome, and nothing further is read.
          if inv.nil?
            return deny(**d, invitation_id: nil, outward: "invitation_not_active",
                        internal: "invitation_not_active")
          end

          # Exact replay is recognized BEFORE the state check, because a decided
          # Invitation is no longer pending and its own replay must still return the
          # stored result rather than the generic terminal outcome.
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org:, command_type: command.command_type, target_type: TARGET_TYPE,
                                            target_id: command.invitation_id, key_digest:)
          if existing
            return replay(store, command, existing) if existing["request_hex"] == hex(request_hash(command, ctx, actor, reason))

            return deny(**d, invitation_id: command.invitation_id, outward: "idempotency_conflict",
                        internal: "idempotency_conflict")
          end

          if inv["state"] != "pending_approval"
            return deny(**d, invitation_id: command.invitation_id, outward: "invitation_not_active",
                        internal: "invitation_not_active")
          end

          # ":333 approval … by a SecurityOperator other than the requester".
          if inv["requester_account_id"] == actor.account_id
            return deny(**d, invitation_id: command.invitation_id, outward: "invitation_approver_conflict",
                        internal: "approver_is_requester")
          end

          # ":242 At the approval due instant, expiry wins."
          if now >= to_time(inv["approval_due_at"])
            return deny(**d, invitation_id: command.invitation_id, outward: "invitation_not_active",
                        internal: "invitation_approval_window_elapsed")
          end

          unless command.expected_state_version == inv["state_version"].to_i
            return deny(**d, invitation_id: command.invitation_id, outward: "stale_state_version",
                        internal: "stale_state_version")
          end

          commit(**d, inv:, reason:, key_digest:)
        end

        def commit(command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer:, inv:, reason:, key_digest:)
          ids = %i[execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          request_sha256 = request_hash(command, ctx, actor, reason)
          approve = command.decision == "approve"
          new_version = inv["state_version"].to_i + 1

          write_execution(store, command, ctx, org, ids[:execution], command.invitation_id, actor,
                          request_sha256, key_digest, now, ACTION)
          write_authorization_decision(auth_store, ids[:decision], ctx, command, actor, decision, now,
                                       command.invitation_id, ACTION)

          activation = approve ? activate(pg, store, command, ctx, org, actor, inv, now) : nil
          unless approve
            changed = store.reject_invitation(command.invitation_id, inv["state_version"].to_i, now, reason,
                                              actor.account_id)
            raise LostRace if changed.to_i.zero?

            store.update_registry_terminal(command.invitation_id, "rejected", now)
          end

          payload = { "invitation_id" => command.invitation_id, "organization_id" => org,
                      "state" => approve ? "active" : "rejected",
                      "expires_at_utc" => activation&.expires_at&.iso8601(6),
                      "scheduled_action_id" => activation&.scheduled_action_id }
          write_audit(store, ids[:audit], org, ctx, command, command.invitation_id, actor,
                      to_state: approve ? "active" : "rejected", outcome: "success",
                      reason_code: approve ? nil : "invitation_rejected",
                      payload: payload.merge("approver_account_id" => actor.account_id), now:)
          extra = if approve
                    { "from_state" => "pending_approval", "to_state" => "active",
                      "expires_at_utc" => activation.expires_at.iso8601(6),
                      "scheduled_action_id" => activation.scheduled_action_id }
                  else
                    { "from_state" => "pending_approval", "to_state" => "rejected", "reason" => reason }
                  end
          write_event(store, ids, org, ctx, command, actor, now, new_version, command.invitation_id,
                      request_sha256, key_digest, inv["requester_account_id"],
                      approve ? "InvitationActivated" : "InvitationRejected", "state_transition", extra)
          write_result_success(store, ids, command, ctx, org, actor, now, payload, command.invitation_id)
          write_idempotency(store, ids[:idem], org, command, command.invitation_id, key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        rescue LostRace
          raise Platform::InvariantViolation, "invitation transitioned concurrently"
        end

        # Approval activates through the one shared routine, so the expiry timer is
        # created here, in this transaction, from the same boundary arithmetic.
        def activate(pg, store, command, ctx, org, actor, inv, now)
          activation = InvitationActivation.schedule_expiry(
            pg:, organization_id: org, invitation_id: command.invitation_id, activated_at: now,
            state_version: inv["state_version"].to_i + 1, correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id
          )
          changed = store.activate_invitation(command.invitation_id, inv["state_version"].to_i, now,
                                              activation.expires_at, actor.account_id)
          raise LostRace if changed.to_i.zero?

          store.update_registry_active(command.invitation_id, now, activation.expires_at)
          activation
        end

        def replay(store, command, existing)
          stored = store.load_command_result(existing["command_result_id"])
          payload = JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym)
          Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type, payload:,
                                          audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end

        # A rejection carries a mandatory 20-2,000 character reason, as revocation
        # does; an approval carries none.
        def normalize_reason(command)
          return nil if command.decision == "approve"

          trimmed = command.reason.to_s.strip
          return :invalid unless (REASON_MIN..REASON_MAX).cover?(trimmed.length)

          trimmed
        end

        def request_hash(command, ctx, actor, reason)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "actor_id" => actor.account_id,
            "organization_id" => actor.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => command.invitation_id, "project_id" => nil,
            "expected_version" => command.expected_state_version,
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => { "decision" => command.decision, "reason" => reason }
          })
        end

        def canonical_payload_json(command) = JSON.generate({ "decision" => command.decision })
        def to_time(value) = value.respond_to?(:getutc) ? value.getutc : Time.parse(value).getutc

        class LostRace < StandardError; end
      end
    end
  end
end
