# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf013
    module Handlers
      # WF-013 DecideRoleAssignment — the approval that turns a pending protected
      # grant into real authority (:316, :333 "They require approval within 24
      # hours by a SecurityOperator other than the requester and an active expiry
      # under the rule above. Unapproved requests expire; rejection or expiry
      # grants nothing").
      #
      # Required cardinality is ONE distinct SecurityOperator. :333 names a single
      # approver ("a SecurityOperator other than the requester"); the two-identity
      # rule it also names applies specifically to the FIRST SecurityOperator
      # Assignment in an Organization, which needs the security-bootstrap service
      # and is refused here rather than approximated.
      #
      # Approval is one transaction: the immutable approval record, the ALLOWLIST
      # written at the moment the grant becomes effective, activation, the
      # Organization authorization-epoch advance, and the expiry timer. The
      # allowlist is the approved protected subset of the granted role, captured
      # now — never reconstructed later from the role or a future Permission
      # Baseline.
      class DecideRoleAssignment
        include InvitationLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "role_assignment"
        ACTION = "role.manage"
        CAPABILITY = "role.manage"
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
            store = IdentityAccess::Infrastructure::RoleAssignmentStore.new(pg)

            actor = auth.authenticate(session_id: command.session_id, now:, correlation_id: ctx.correlation_id)
            return in_memory_failure(command, ctx, actor.to_s) if actor.is_a?(Symbol)

            # The approver's authority runs through the shared gate, which enforces
            # step 4: a SecurityOperator without `role.manage` in its own approved
            # allowlist is not an approver.
            decision = auth.authorize(actor:, capability: CAPABILITY, now:)
            d = { command:, ctx:, pg:, store:, auth_store:, actor:, decision:,
                  org: actor.organization_id, now:, offer: nil }
            unless decision.allowed? && approver_role?(decision)
              return deny(**d, invitation_id: command.role_assignment_id,
                          outward: "missing_authority", internal: decision.reason)
            end

            process(**d, reason:)
          end
        end

        private

        def approver_role?(decision)
          decision.granting.any? { |a| a["canonical_role"] == APPROVER_ROLE }
        end

        def process(command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer:, reason:)
          d = { command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer: }
          store.lock_organization(org)
          store.lock_role_assignment(command.role_assignment_id)

          row = store.read(command.role_assignment_id)
          if row.nil?
            return deny(**d, invitation_id: nil, outward: "role_assignment_not_pending",
                        internal: "role_assignment_not_visible")
          end

          key_digest = Digest::SHA256.digest(command.idempotency_key)
          request_sha256 = request_hash(command, ctx, actor, reason)
          existing = store.find_idempotency(org:, command_type: command.command_type,
                                            target_type: TARGET_TYPE,
                                            target_id: command.role_assignment_id, key_digest:)
          if existing
            return replay(store, command, existing) if existing["request_hex"] == hex(request_sha256)

            return deny(**d, invitation_id: command.role_assignment_id, outward: "idempotency_conflict",
                        internal: "idempotency_conflict")
          end

          unless row["status"] == "pending"
            return deny(**d, invitation_id: command.role_assignment_id,
                        outward: "role_assignment_not_pending", internal: "role_assignment_not_pending")
          end

          # ":333 by a SecurityOperator other than the requester."
          if row["requester_account_id"] == actor.account_id
            return deny(**d, invitation_id: command.role_assignment_id,
                        outward: "role_approver_conflict", internal: "approver_is_requester")
          end

          # The first SecurityOperator Assignment needs two platform identities
          # through the security-bootstrap service (:333); it is not approvable here.
          if row["canonical_role"] == APPROVER_ROLE && !any_active_security_operator?(store, org, now)
            return deny(**d, invitation_id: command.role_assignment_id,
                        outward: "role_approver_conflict", internal: "first_security_operator_requires_bootstrap")
          end

          # ":316 at equality expiry wins" for the approval window.
          if now >= to_time(row["approval_due_at"])
            return deny(**d, invitation_id: command.role_assignment_id,
                        outward: "role_assignment_not_pending", internal: "role_approval_window_elapsed")
          end

          unless command.expected_state_version == row["state_version"].to_i
            return deny(**d, invitation_id: command.role_assignment_id, outward: "stale_state_version",
                        internal: "stale_state_version")
          end
          unless command.expected_authorization_epoch == store.organization_epoch(org)
            return deny(**d, invitation_id: command.role_assignment_id,
                        outward: "stale_authorization_epoch", internal: "stale_authorization_epoch")
          end

          commit(**d, row:, reason:, key_digest:, request_sha256:)
        end

        def any_active_security_operator?(store, _org, _now)
          store.send(:exec, <<~SQL, [APPROVER_ROLE]).values.dig(0, 0).to_i.positive?
            SELECT count(*) FROM role_assignments WHERE canonical_role = $1 AND status = 'active'
          SQL
        end

        def commit(command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer:,
                   row:, reason:, key_digest:, request_sha256:)
          ids = %i[execution audit event result decision idem approval].to_h { |k| [k, ctx.generate_id] }
          approve = command.decision == "approve"
          epoch = store.organization_epoch(org)
          new_version = row["state_version"].to_i + 1

          write_execution(store, command, ctx, org, ids[:execution], command.role_assignment_id, actor,
                          request_sha256, key_digest, now, ACTION)
          write_authorization_decision(auth_store, ids[:decision], ctx, command, actor, decision, now,
                                       command.role_assignment_id, ACTION)

          # ":314 ordered immutable approval records"; the unique index makes a
          # second record by the same approver impossible.
          store.insert_approval(
            id: ids[:approval], created_at: iso(now), organization_id: org,
            role_assignment_id: command.role_assignment_id,
            sequence_number: store.approval_count(command.role_assignment_id) + 1,
            approver_account_id: actor.account_id, authority: APPROVER_ROLE,
            decision: command.decision, reason:, decided_at: iso(now),
            policy_version: Platform::PermissionBaseline::VERSION, separation_result: "distinct",
            correlation_id: ctx.correlation_id
          )

          allowlist = approve ? Platform::PermissionBaseline.protected_permission_preview(row["canonical_role"]) : []
          timer = approve ? activate(store:, pg:, org:, row:, command:, ctx:, now:, epoch:, allowlist:) : reject(store:, row:, command:, now:, reason:, epoch:)

          payload = { "role_assignment_id" => command.role_assignment_id, "organization_id" => org,
                      "account_id" => row["account_id"],
                      "status" => approve ? "active" : "rejected",
                      "protected_permission_allowlist" => allowlist,
                      "authorization_epoch" => approve ? epoch + 1 : epoch,
                      "scheduled_action_id" => timer }
          write_audit(store, ids[:audit], org, ctx, command, command.role_assignment_id, actor,
                      to_state: approve ? "active" : "rejected", outcome: "success",
                      reason_code: approve ? nil : "role_assignment_rejected",
                      payload: payload.merge("approver_account_id" => actor.account_id), now:)
          write_event(store, ids, org, ctx, command, actor, now, new_version, command.role_assignment_id,
                      request_sha256, key_digest, row["requester_account_id"],
                      approve ? "RoleGranted" : "RoleRejected", "state_transition",
                      { "from_state" => "pending", "to_state" => approve ? "active" : "rejected",
                        "organization_epoch" => approve ? epoch + 1 : epoch })
          write_result_success(store, ids, command, ctx, org, actor, now, payload, command.role_assignment_id)
          write_idempotency(store, ids[:idem], org, command, command.role_assignment_id, key_digest,
                            request_sha256, ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        rescue LostRace
          raise Platform::InvariantViolation, "role assignment transitioned concurrently"
        end

        # The approved protected subset is written HERE, at the moment the grant
        # becomes effective, and frozen from then on.
        def activate(store:, pg:, org:, row:, command:, ctx:, now:, epoch:, allowlist:)
          expires_at = row["expires_at"] && to_time(row["expires_at"])
          # THE EPOCH ADVANCE COMES FIRST — one lock order for the two authority rows, everywhere
          # (round-15 concurrency finding R15-CONC-1; see `RevokeRoleAssignment`). This path
          # activates a PENDING grant, which no concurrent WF-005 statement can be holding — its
          # capability CTE requires `status = 'active'`, so the row is filtered out of that
          # statement's snapshot before any lock is asked for, and this handler cannot form the cycle
          # today. It takes the same order anyway: the property is "one order for these two rows",
          # and an exception maintained per handler is the enumeration this tranche exists to remove.
          raise LostRace if store.advance_authorization_epoch(org, epoch, now).to_i.zero?
          changed = store.activate(command.role_assignment_id, row["state_version"].to_i, now,
                                   expires_at, epoch + 1, allowlist)
          raise LostRace if changed.to_i.zero?
          return nil if expires_at.nil?

          RoleAssignmentExpirySchedule.schedule(
            pg:, organization_id: org, role_assignment_id: command.role_assignment_id,
            expires_at:, now:, state_version: row["state_version"].to_i + 1,
            correlation_id: ctx.correlation_id, command_id: command.command_id
          )
        end

        # ":333 rejection or expiry grants nothing" — terminal, no allowlist, no
        # epoch advance, no timer.
        def reject(store:, row:, command:, now:, reason:, epoch:)
          changed = store.reject(command.role_assignment_id, row["state_version"].to_i, now, reason, epoch)
          raise LostRace if changed.to_i.zero?

          nil
        end

        def replay(store, command, existing)
          stored = store.load_command_result(existing["command_result_id"])
          payload = JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym)
          Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type,
                                          payload:, audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end

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
            "target_id" => command.role_assignment_id, "project_id" => nil,
            "expected_version" => command.expected_state_version,
            "expected_authorization_epoch" => command.expected_authorization_epoch,
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
