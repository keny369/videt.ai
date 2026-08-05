# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf013
    module Handlers
      # WF-013 RevokeRoleAssignment — the canonical human-commanded end of an
      # active grant (WORKFLOW_SPECIFICATIONS.md :316, :333, :936, :948, :967).
      #
      # Revocation is the mirror of approval, and it is deliberately NOT the
      # mirror of deletion. ":316 active to revoked … revoked is terminal" ends
      # the authority; the grant content, the approved allowlist and the ordered
      # approval records all survive untouched, because they are the historical
      # record of how the authority was obtained and step 4 of the
      # effective-permission algorithm must be auditable after the fact.
      #
      # Two authority questions, in this order:
      #
      #   CAPABILITY  `role.manage` through the shared gate — which, because
      #               `role.manage` is itself a protected permission (:333),
      #               already enforces step 4's approved-allowlist requirement.
      #               Evaluated BEFORE the target is read, so an unauthorized
      #               actor learns nothing about which Assignments exist.
      #   SUBJECT     the actor's own granting Assignment must contain the target
      #               Assignment's scope (:327), and a PROTECTED Assignment is
      #               revocable only by a SecurityOperator — ":967 OrganizationAdmin
      #               may manage non-protected tenant grants …; SecurityOperator may
      #               manage … protected grants."
      #
      # Then the last-administrator invariant. ":948 Account suspend/revoke/delete
      # and every Role Assignment revoke/reject/expiry/scope change that removes
      # effective OrganizationAdmin authority serialize on the Organization
      # authorization epoch. The mutation is rejected as `last_organization_admin`
      # unless another active Account already has an active, in-scope, unexpired
      # OrganizationAdmin Assignment." A human command is REJECTED here; only the
      # timed expiry writes the OD-026 block decision instead (:339). Both ask the
      # identical question through `LastAdministratorPredicate` — ":344 OD-026 adds
      # no second predicate."
      #
      # The Assignment's expiry ScheduledAction is left exactly as it is. It is a
      # historical fact about the grant, not a live obligation, and the ratified
      # terminal-state rule already makes its later delivery harmless: expiry sees
      # a non-active Assignment and completes with `role_assignment_not_active`,
      # changing nothing and advancing no epoch.
      class RevokeRoleAssignment
        include InvitationLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "role_assignment"
        ACTION = "role.manage"
        CAPABILITY = "role.manage"
        PROTECTED_AUTHORITY_ROLE = "SecurityOperator"
        REASON_MIN = 20
        REASON_MAX = 2000

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          reason = normalize_reason(command.reason)
          return in_memory_failure(command, ctx, "role_reason_invalid") if reason == :invalid

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
            auth = IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
            store = IdentityAccess::Infrastructure::RoleAssignmentStore.new(pg)

            actor = auth.authenticate(session_id: command.session_id, now:, correlation_id: ctx.correlation_id)
            return in_memory_failure(command, ctx, actor.to_s) if actor.is_a?(Symbol)

            decision = auth.authorize(actor:, capability: CAPABILITY, now:)
            d = { command:, ctx:, pg:, store:, auth_store:, actor:, decision:,
                  org: actor.organization_id, now:, offer: nil }
            unless decision.allowed?
              return deny(**d, invitation_id: nil, outward: decision.reason, internal: decision.reason)
            end

            process(**d, reason:)
          end
        end

        private

        def process(command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer:, reason:)
          d = { command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer: }
          # The Organization epoch is the ratified serialization point for
          # effective access (:948); the Assignment lock is the one expiry takes.
          store.lock_organization(org)
          store.lock_role_assignment(command.role_assignment_id)

          # Read under the actor's proved Organization context: a cross-Organization
          # reference is simply not visible, and is answered exactly as an already
          # terminal one.
          row = store.read(command.role_assignment_id)
          if row.nil?
            return deny(**d, invitation_id: nil, outward: "role_assignment_not_active",
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

          subject = subject_authority_reason(decision, row)
          if subject
            return deny(**d, invitation_id: command.role_assignment_id, outward: subject, internal: subject)
          end

          unless row["status"] == "active"
            return deny(**d, invitation_id: command.role_assignment_id,
                        outward: "role_assignment_not_active", internal: "role_assignment_not_active")
          end

          unless command.expected_state_version == row["state_version"].to_i
            return deny(**d, invitation_id: command.role_assignment_id, outward: "stale_state_version",
                        internal: "stale_state_version")
          end
          unless command.expected_authorization_epoch == store.organization_epoch(org)
            return deny(**d, invitation_id: command.role_assignment_id,
                        outward: "stale_authorization_epoch", internal: "stale_authorization_epoch")
          end

          if strands_organization?(store, row, now)
            return deny(**d, invitation_id: command.role_assignment_id,
                        outward: "last_organization_admin", internal: "last_organization_admin")
          end

          commit(**d, row:, reason:, key_digest:, request_sha256:)
        end

        # ":244 scope containment" plus ":967 OrganizationAdmin may manage
        # non-protected tenant grants; SecurityOperator may manage protected
        # grants." Returns a reason code, or nil when the actor may act on THIS
        # Assignment.
        def subject_authority_reason(decision, row)
          unless IdentityAccess::Authorization::GrantAuthority.contains_scope?(decision.granting, row["scope_hex"])
            return "grant_scope_exceeded"
          end
          return nil unless Platform::PermissionBaseline.protected_role?(row["canonical_role"])
          return nil if decision.granting.any? { |a| a["canonical_role"] == PROTECTED_AUTHORITY_ROLE }

          "role_protected_authority_required"
        end

        # ":948 rejected as `last_organization_admin` unless another active Account
        # already has an active, in-scope, unexpired OrganizationAdmin Assignment."
        def strands_organization?(store, row, now)
          return false unless row["canonical_role"] == "OrganizationAdmin"

          store.other_effective_admins(role_assignment_id: row["id"], account_id: row["account_id"],
                                       now:).zero?
        end

        def commit(command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer:,
                   row:, reason:, key_digest:, request_sha256:)
          ids = %i[execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          epoch = store.organization_epoch(org)
          new_version = row["state_version"].to_i + 1

          write_execution(store, command, ctx, org, ids[:execution], command.role_assignment_id, actor,
                          request_sha256, key_digest, now, ACTION)
          write_authorization_decision(auth_store, ids[:decision], ctx, command, actor, decision, now,
                                       command.role_assignment_id, ACTION)

          # ":936 Every accepted effective-access mutation increments that epoch
          # once" — in this same transaction, so authority cannot outlive the
          # commit that removed it.
          #
          # THE EPOCH ADVANCE COMES FIRST, AND THE ORDER IS THE POINT (round-15 concurrency finding
          # R15-CONC-1). Since FU-48 every WF-005 protected write locks `organizations` and THEN
          # `role_assignments`, both inside one statement. This transaction locked them the other way
          # round, so revoking the grant a concurrent Crawl command was spending closed a CYCLE:
          # PostgreSQL aborted one side with SQLSTATE 40P01, nothing on either path rescued it, and
          # WHICH side died was the deadlock detector's choice — either a customer command raising
          # `PG::TRDeadlockDetected` instead of returning the `Platform::CommandResult` ADR-103
          # guarantees, or this revocation failing to land while reporting an error. Both outcomes
          # were measured, 28 times. Both writes stay in this transaction, both keep their guards and
          # both still raise `LostRace` on zero rows: only which row this transaction holds first
          # changes. PROOF 262/263.
          raise LostRace if store.advance_authorization_epoch(org, epoch, now).to_i.zero?
          raise LostRace if store.revoke(command.role_assignment_id, row["state_version"].to_i, now,
                                         reason, epoch + 1).to_i.zero?

          payload = { "role_assignment_id" => command.role_assignment_id, "organization_id" => org,
                      "account_id" => row["account_id"], "status" => "revoked",
                      "canonical_role" => row["canonical_role"], "authorization_epoch" => epoch + 1 }
          write_audit(store, ids[:audit], org, ctx, command, command.role_assignment_id, actor,
                      to_state: "revoked", outcome: "success", reason_code: "role_assignment_revoked",
                      payload: payload.merge("reason" => reason,
                                             "requester_account_id" => row["requester_account_id"]), now:)
          write_event(store, ids, org, ctx, command, actor, now, new_version, command.role_assignment_id,
                      request_sha256, key_digest, row["requester_account_id"], "RoleRevoked",
                      "state_transition",
                      { "from_state" => "active", "to_state" => "revoked",
                        "organization_epoch" => epoch + 1, "reason" => reason,
                        "transition_reason_code" => "role_assignment_revoked" })
          write_result_success(store, ids, command, ctx, org, actor, now, payload, command.role_assignment_id)
          write_idempotency(store, ids[:idem], org, command, command.role_assignment_id, key_digest,
                            request_sha256, ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        rescue LostRace
          raise Platform::InvariantViolation, "role assignment transitioned concurrently"
        end

        def replay(store, command, existing)
          stored = store.load_command_result(existing["command_result_id"])
          payload = JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym)
          Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type,
                                          payload:, audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end

        # Revocation is an accountable act, so its reason is mandatory and bounded
        # exactly as every other WF-013 revocation reason is.
        def normalize_reason(raw)
          return :invalid if raw.nil?

          trimmed = raw.to_s.strip
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
            "command_payload" => { "reason" => reason }
          })
        end

        def canonical_payload_json(command)
          JSON.generate({ "reason_length" => command.reason.to_s.strip.length })
        end

        class LostRace < StandardError; end
      end
    end
  end
end
