# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf013
    module Handlers
      # WF-013 RequestRoleAssignment (WORKFLOW_SPECIFICATIONS.md :314, :316, :333;
      # contracts/S-23.json MTX-038). The real grant path: the first way an
      # Assignment — and therefore any protected authority — can come into
      # existence outside the WF-001 bootstrap.
      #
      # The requester states the grant, never the branch. A nonprotected grant
      # becomes ACTIVE in this transaction, advancing the Organization
      # authorization epoch and scheduling its expiry timer if it has one. A
      # protected grant becomes PENDING, "confers no permission while pending"
      # (:316), carries `approval_due_at = requested_at + 24 hours`, advances no
      # epoch, and waits for a distinct SecurityOperator.
      #
      # The bootstrap exception does NOT change that. It lets the first
      # OrganizationAdmin USE protected permissions (step 4); it does not let
      # anyone GRANT protected authority without approval, which is the ":244
      # cannot bypass protected approval" clause.
      class RequestRoleAssignment
        include InvitationLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "role_assignment"
        ACTION = "role.manage"
        CAPABILITY = "role.manage"
        APPROVAL_WINDOW_SECONDS = 24 * 3600
        MAX_PROTECTED_LIFETIME_SECONDS = 30 * 24 * 3600

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)
          unless InvitationOffer.valid_tuple?(canonical_role: command.canonical_role,
                                              permission_mode: command.permission_mode,
                                              persona: command.persona)
            return in_memory_failure(command, ctx, "role_mode_invalid")
          end

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

            protected_grant = Platform::PermissionBaseline.protected_role?(command.canonical_role)
            # ":244 the requester can offer only a role/scope/permission set it may
            # grant". A protected grant is not a direct grant — it goes to approval
            # — so only the role and scope limbs apply to it.
            grant = IdentityAccess::Authorization::GrantAuthority.evaluate(
              authorizer: auth, actor:, now:, canonical_role: command.canonical_role,
              scope_hex: command.scope_sha256&.unpack1("H*"), direct: !protected_grant
            )
            unless grant.allowed?
              return deny(**d, invitation_id: nil, outward: grant.reason, internal: grant.reason)
            end

            process(**d, protected_grant:)
          end
        end

        private

        def process(command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer:, protected_grant:)
          d = { command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer: }
          store.lock_organization(org)

          # Exact replay first: a committed grant must return its stored result
          # even though its own success advanced the epoch the caller quoted.
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          request_sha256 = request_hash(command, ctx, actor)
          existing = store.find_idempotency(org:, command_type: command.command_type,
                                            target_type: TARGET_TYPE, target_id: command.account_id,
                                            key_digest:)
          if existing
            return replay(store, command, existing) if existing["request_hex"] == hex(request_sha256)

            return deny(**d, invitation_id: nil, outward: "idempotency_conflict",
                        internal: "idempotency_conflict")
          end

          unless command.expected_authorization_epoch == store.organization_epoch(org)
            return deny(**d, invitation_id: nil, outward: "stale_authorization_epoch",
                        internal: "stale_authorization_epoch")
          end

          target = store.account(command.account_id)
          if target.nil? || target["status"] != "active"
            return deny(**d, invitation_id: nil, outward: "invitation_account_ineligible",
                        internal: "role_target_account_ineligible")
          end

          expiry = expiry_reason(command, protected_grant, now)
          return deny(**d, invitation_id: nil, outward: expiry, internal: expiry) if expiry

          commit(**d, protected_grant:, key_digest:, request_sha256:)
        end

        # ":316 Its active expiry is mandatory and no later than 30 days after
        # effectiveness" for a protected Assignment; a nonprotected one may have
        # none.
        def expiry_reason(command, protected_grant, now)
          return "role_expiry_required" if protected_grant && command.expires_at.nil?
          return nil if command.expires_at.nil?
          return "role_expiry_invalid" if command.expires_at <= now
          return "role_expiry_invalid" if protected_grant && command.expires_at > now + MAX_PROTECTED_LIFETIME_SECONDS

          nil
        end

        def commit(command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer:,
                   protected_grant:, key_digest:, request_sha256:)
          ids = %i[assignment execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          epoch = store.organization_epoch(org)

          write_execution(store, command, ctx, org, ids[:execution], ids[:assignment], actor,
                          request_sha256, key_digest, now, ACTION)
          write_authorization_decision(auth_store, ids[:decision], ctx, command, actor, decision, now,
                                       ids[:assignment], ACTION)

          store.insert(
            id: ids[:assignment], created_at: iso(now), correlation_id: ctx.correlation_id,
            organization_id: org, account_id: command.account_id, canonical_role: command.canonical_role,
            permission_mode: command.permission_mode, persona: command.persona,
            scope_sha256: command.scope_sha256, status: protected_grant ? "pending" : "active",
            effective_at: protected_grant ? nil : iso(now), expires_at: iso(command.expires_at),
            requester_account_id: actor.account_id, requested_at: iso(now),
            approval_due_at: protected_grant ? iso(now + APPROVAL_WINDOW_SECONDS) : nil,
            reason: command.reason, decision_authorization_epoch: protected_grant ? nil : epoch + 1,
            idempotency_key_digest: key_digest, fulfilled_invitation_id: nil,
            # Nothing is approved yet, and a nonprotected grant carries none by
            # definition; the allowlist is written only by approval.
            protected_permission_allowlist: []
          )

          activation = protected_grant ? nil : activate_now(pg:, store:, org:, ids:, command:, ctx:, now:, epoch:)

          payload = { "role_assignment_id" => ids[:assignment], "organization_id" => org,
                      "account_id" => command.account_id, "canonical_role" => command.canonical_role,
                      "status" => protected_grant ? "pending" : "active",
                      "approval_due_at_utc" => protected_grant ? (now + APPROVAL_WINDOW_SECONDS).iso8601(6) : nil,
                      "expires_at_utc" => command.expires_at&.getutc&.iso8601(6),
                      "scheduled_action_id" => activation }
          write_audit(store, ids[:audit], org, ctx, command, ids[:assignment], actor,
                      to_state: protected_grant ? "pending" : "active", outcome: "success",
                      reason_code: nil, payload:, now:)
          write_event(store, ids, org, ctx, command, actor, now, 0, ids[:assignment], request_sha256,
                      key_digest, actor.account_id,
                      protected_grant ? "RoleAssignmentRequested" : "RoleGranted", "created",
                      { "to_state" => protected_grant ? "pending" : "active",
                        "organization_epoch" => protected_grant ? epoch : epoch + 1 })
          write_result_success(store, ids, command, ctx, org, actor, now, payload, ids[:assignment])
          write_idempotency(store, ids[:idem], org, command, command.account_id, key_digest,
                            request_sha256, ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        # A nonprotected grant is effective immediately, so its epoch advance and
        # its expiry timer belong to this same transaction.
        def activate_now(pg:, store:, org:, ids:, command:, ctx:, now:, epoch:)
          changed = store.advance_authorization_epoch(org, epoch, now)
          raise LostRace if changed.to_i.zero?

          return nil if command.expires_at.nil?

          RoleAssignmentExpirySchedule.schedule(
            pg:, organization_id: org, role_assignment_id: ids[:assignment],
            expires_at: command.expires_at, now:, state_version: 0,
            correlation_id: ctx.correlation_id, command_id: command.command_id
          )
        rescue LostRace
          raise Platform::InvariantViolation, "organization authorization epoch advanced concurrently"
        end

        def replay(store, command, existing)
          stored = store.load_command_result(existing["command_result_id"])
          payload = JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym)
          Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type,
                                          payload:, audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end

        def request_hash(command, ctx, actor)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "actor_id" => actor.account_id,
            "organization_id" => actor.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => command.account_id, "project_id" => nil,
            "expected_authorization_epoch" => command.expected_authorization_epoch,
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => {
              "canonical_role" => command.canonical_role, "permission_mode" => command.permission_mode,
              "persona" => command.persona, "scope_sha256" => command.scope_sha256&.unpack1("H*"),
              "expires_at" => command.expires_at&.getutc&.floor(6)&.iso8601(6)
            }
          })
        end

        def canonical_payload_json(command)
          JSON.generate({ "canonical_role" => command.canonical_role,
                          "permission_mode" => command.permission_mode })
        end

        class LostRace < StandardError; end
      end
    end
  end
end
