# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"

module Workflows
  module Wf013
    module Handlers
      # WF-013 CreateInvitation (WORKFLOW_SPECIFICATIONS.md :242, :244;
      # APPLICATION_LAYER.md WF-013; contracts/S-23.json MTX-038). The first
      # production path that brings an Invitation into existence, and therefore
      # the first that makes the timed expiry reachable.
      #
      # It composes the platform rather than extending it: Session authentication
      # and Session-derived organization authority through `CommandAuthorizer`,
      # the `invitation.create` capability through the Permission Baseline, the
      # actor-attributed command/audit/event ledger, canonical request digests,
      # the reference registry, and — for a nonprotected offer — the
      # ScheduledAction subsystem, inside this command's own transaction.
      #
      # Branch (:242, and the caller does not choose): the offered canonical role
      # decides. A grant containing no protected permission is created directly
      # ACTIVE and emits `InvitationActivated`; a grant containing one starts
      # PENDING APPROVAL, grants nothing, carries `approval_due_at = requested_at
      # + 24 hours`, and emits `InvitationApprovalRequested`.
      #
      # Order (first match): schema; offer shape and role/mode/persona tuple;
      # authenticate; authorize `invitation.create`; resolve the target Account;
      # already-effective grant; ineligible Account; open-invitation uniqueness
      # (exact replay, or `invitation_duplicate_open`); then the commit.
      class CreateInvitation
        include InvitationLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "invitation"
        ACTION = "invitation.create"
        CAPABILITY = "invitation.create"
        POLICY_VERSION = "onboarding-interim-v1"
        APPROVAL_WINDOW_SECONDS = 24 * 3600

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          email = InvitationOffer.normalize_email(command.target_email)
          return in_memory_failure(command, ctx, "identity_email_invalid") if email.nil?
          unless InvitationOffer.valid_tuple?(canonical_role: command.canonical_role,
                                              permission_mode: command.permission_mode,
                                              persona: command.persona)
            return in_memory_failure(command, ctx, "role_mode_invalid")
          end

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            auth = IdentityAccess::Authorization::CommandAuthorizer.new(
              IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
            )
            store = IdentityAccess::Infrastructure::InvitationAdminStore.new(pg)

            actor = auth.authenticate(session_id: command.session_id, now:, correlation_id: ctx.correlation_id)
            return in_memory_failure(command, ctx, actor.to_s) if actor.is_a?(Symbol)

            decision = auth.authorize(actor:, capability: CAPABILITY, now:)
            offer = build_offer(command, email, actor.organization_id)
            d = { command:, ctx:, pg:, store:,
                  auth_store: IdentityAccess::Infrastructure::AuthorizationStore.new(pg),
                  actor:, decision:, org: actor.organization_id, now:, offer: }

            unless decision.allowed?
              # Denied before the Organization's Invitations are read at all.
              return deny(**d, invitation_id: nil, outward: decision.reason, internal: decision.reason)
            end

            # ":244 the requester can offer only a role/scope/permission set it may
            # grant". Creating an Invitation is not itself a direct grant — a
            # protected offer goes to approval — so grant authority is evaluated
            # with `direct: false` and only the role/scope limbs apply.
            grant = IdentityAccess::Authorization::GrantAuthority.evaluate(
              authorizer: auth, actor:, now:, canonical_role: command.canonical_role,
              scope_hex: offer[:scope_sha256]&.unpack1("H*"), direct: false
            )
            unless grant.allowed?
              return deny(**d, invitation_id: nil, outward: grant.reason, internal: grant.reason)
            end

            process(**d)
          end
        rescue ActiveRecord::RecordNotUnique, PG::UniqueViolation => e
          # Two identical creations raced past the uniqueness read and the database
          # decided it: `one_open_invitation_per_preimage` admitted exactly one.
          # The loser's transaction rolled back entirely, so it changed nothing and
          # returns the ratified duplicate reason (:244) rather than an exception.
          raise unless e.message.include?("one_open_invitation_per_preimage")

          in_memory_failure(command, ctx, "invitation_duplicate_open")
        end

        private

        # ---- offer ---------------------------------------------------------------

        def build_offer(command, email, org)
          preview = InvitationOffer.protected_permission_preview(command.canonical_role)
          email_sha256 = Digest::SHA256.digest(email)
          {
            email:, email_sha256:, preview:,
            protected: preview.any?,
            issuer_key: norm(command.target_identity_issuer_key),
            subject: norm(command.target_identity_subject),
            scope_sha256: command.scope_sha256,
            uniqueness: InvitationOffer.uniqueness_digest(
              organization_id: org, target_email_sha256: email_sha256,
              target_identity_issuer_key: norm(command.target_identity_issuer_key),
              target_identity_subject: norm(command.target_identity_subject),
              canonical_role: command.canonical_role, permission_mode: command.permission_mode,
              persona: command.persona, scope_sha256: command.scope_sha256,
              intended_assignment_expires_at: command.intended_assignment_expires_at
            )
          }
        end

        # ---- first-match resolution ----------------------------------------------

        def process(command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer:)
          d = { command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer: }

          account = store.find_target_account(email_sha256: offer[:email_sha256],
                                              issuer_key: offer[:issuer_key], subject: offer[:subject])
          if account && %w[suspended revoked].include?(account["status"])
            return deny(**d, invitation_id: nil, outward: "invitation_account_ineligible",
                        internal: "invitation_account_ineligible")
          end

          if account && account["status"] == "active" && effective_grant?(store, account["id"], command, offer, now)
            return deny(**d, invitation_id: nil, outward: "invitation_grant_already_active",
                        internal: "invitation_grant_already_active")
          end

          # Open-invitation uniqueness: exact creation replay returns the existing
          # Invitation; a different key for the same offer is a duplicate (:244).
          existing = store.find_open_by_uniqueness(offer[:uniqueness])
          if existing
            key_hex = Digest::SHA256.hexdigest(command.idempotency_key)
            return replay(store, command, existing, org) if existing["creation_key_hex"] == key_hex

            return deny(**d, invitation_id: existing["id"], outward: "invitation_duplicate_open",
                        internal: "invitation_duplicate_open")
          end

          # The durable checkpoint (:333). Creating an Invitation confers a future
          # grant, so it stops here if the creator's own authority changed between
          # the authorization read and this write.
          unless IdentityAccess::Authorization::CommandAuthorizer.authority_current?(store: auth_store, actor:)
            return deny(**d, invitation_id: nil, outward: "stale_authorization_epoch",
                        internal: "authority_changed_before_commit")
          end

          succeed(**d)
        end

        def effective_grant?(store, account_id, command, offer, now)
          !store.find_effective_assignment(
            account_id:, canonical_role: command.canonical_role, permission_mode: command.permission_mode,
            persona: command.persona, scope_hex: offer[:scope_sha256]&.unpack1("H*"), now:
          ).nil?
        end

        # ---- commit ---------------------------------------------------------------

        def succeed(command:, ctx:, pg:, store:, auth_store:, actor:, decision:, org:, now:, offer:)
          ids = %i[invitation execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          request_sha256 = request_hash(command:, ctx:, actor:, offer:)
          # ":240 an opaque invitation ID with at least 128 bits of cryptographic
          # entropy"; only its digest is ever persisted or logged.
          reference = SecureRandom.random_bytes(32)
          reference_digest = Digest::SHA256.digest(reference)
          activated = offer[:protected] ? nil : now

          write_execution(store, command, ctx, org, ids[:execution], ids[:invitation], actor,
                          request_sha256, key_digest, now, ACTION)
          write_authorization_decision(auth_store, ids[:decision], ctx, command, actor, decision, now,
                                       ids[:invitation], ACTION)

          store.insert_invitation(
            id: ids[:invitation], created_at: iso(now), correlation_id: ctx.correlation_id, organization_id: org,
            opaque_reference_sha256: reference_digest, target_email: offer[:email],
            target_email_sha256: offer[:email_sha256], target_identity_issuer_key: offer[:issuer_key],
            target_identity_subject: offer[:subject], canonical_role: command.canonical_role,
            permission_mode: command.permission_mode, persona: command.persona,
            scope_sha256: offer[:scope_sha256], protected_permission_preview: JSON.generate(offer[:preview]),
            state: offer[:protected] ? "pending_approval" : "active", requester_account_id: actor.account_id,
            requested_at: iso(now), approval_due_at: offer[:protected] ? iso(now + APPROVAL_WINDOW_SECONDS) : nil,
            activated_at: iso(activated), expires_at: nil,
            intended_assignment_expires_at: iso(command.intended_assignment_expires_at),
            open_uniqueness_sha256: offer[:uniqueness], creation_idempotency_key_digest: key_digest,
            request_policy_version: Platform::PermissionBaseline::VERSION
          )

          activation = activate_if_nonprotected(pg:, store:, org:, ids:, offer:, now:, ctx:, command:,
                                                reference_digest:)

          payload = result_payload(ids[:invitation], org, offer, activation)
          write_audit(store, ids[:audit], org, ctx, command, ids[:invitation], actor,
                      to_state: offer[:protected] ? "pending_approval" : "active", outcome: "success",
                      reason_code: nil, payload: payload.merge("branch" => branch(offer)), now:)
          write_activation_event(store, ids, org, ctx, command, actor, now, offer, activation, request_sha256,
                                 key_digest)
          write_result_success(store, ids, command, ctx, org, actor, now, payload, ids[:invitation])
          write_idempotency(store, ids[:idem], org, command, ids[:invitation], key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          # The raw reference is returned to the authorized requester in memory and
          # is NEVER persisted (":240 logs, list views, events, and provider
          # telemetry use its digest"), so a replay legitimately cannot return it.
          Platform::CommandResult.success(
            result_id: ids[:result], command_type: command.command_type, audit_record_id: ids[:audit],
            correlation_id: ctx.correlation_id,
            payload: payload.transform_keys(&:to_sym).merge(invitation_reference: reference)
          )
        end

        # THE integration point. A nonprotected offer is active the moment it is
        # created, so its expiry timer is created here — in this same transaction,
        # through the canonical scheduler. Rollback loses both; commit keeps both.
        def activate_if_nonprotected(pg:, store:, org:, ids:, offer:, now:, ctx:, command:, reference_digest:)
          unless offer[:protected]
            activation = InvitationActivation.schedule_expiry(
              pg:, organization_id: org, invitation_id: ids[:invitation], activated_at: now,
              state_version: 0, correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
              command_id: command.command_id
            )
            # The Invitation row and its global locator both carry the activation
            # routine's expiry instant; no command computes it independently.
            store.set_expiry(ids[:invitation], activation.expires_at, now)
            store.insert_registry(opaque_reference_sha256: reference_digest, created_at: iso(now),
                                  organization_id: org, invitation_id: ids[:invitation],
                                  invitation_state: "active", activated_at: iso(now),
                                  expires_at: iso(activation.expires_at))
            return activation
          end

          store.insert_registry(opaque_reference_sha256: reference_digest, created_at: iso(now),
                                organization_id: org, invitation_id: ids[:invitation],
                                invitation_state: "pending_approval", activated_at: nil, expires_at: nil)
          nil
        end

        # ---- events ---------------------------------------------------------------

        # `InvitationActivated` and `InvitationApprovalRequested` are both `created`
        # here (API_CONTRACTS.md :862-863 — `C` for a created aggregate, `ST` only
        # for a transition from a prior state), and both have reason source `none`,
        # so `reason_code` is null.
        def write_activation_event(store, ids, org, ctx, command, actor, now, offer, activation, request_sha256, key_digest)
          type = offer[:protected] ? "InvitationApprovalRequested" : "InvitationActivated"
          extra = if offer[:protected]
                    { "approval_due_at_utc" => (now + APPROVAL_WINDOW_SECONDS).iso8601(6), "to_state" => "pending_approval" }
                  else
                    { "expires_at_utc" => activation.expires_at.iso8601(6), "to_state" => "active",
                      "scheduled_action_id" => activation.scheduled_action_id }
                  end
          write_event(store, ids, org, ctx, command, actor, now, 0, ids[:invitation], request_sha256,
                      key_digest, actor.account_id, type, "created", extra)
        end

        def result_payload(invitation_id, org, offer, activation)
          {
            "invitation_id" => invitation_id, "organization_id" => org,
            "state" => offer[:protected] ? "pending_approval" : "active",
            "protected_permission_preview" => offer[:preview],
            "expires_at_utc" => activation&.expires_at&.iso8601(6),
            "scheduled_action_id" => activation&.scheduled_action_id
          }
        end

        def replay(store, command, existing, org)
          record = store.find_idempotency(org:, command_type: command.command_type, target_type: TARGET_TYPE,
                                          target_id: existing["id"],
                                          key_digest: Digest::SHA256.digest(command.idempotency_key))
          return nil if record.nil?

          stored = store.load_command_result(record["command_result_id"])
          payload = JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym)
          Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type, payload:,
                                          audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end

        # ---- helpers ---------------------------------------------------------------

        def branch(offer) = offer[:protected] ? "invitation_create_protected" : "invitation_create_active"

        def request_hash(command:, ctx:, actor:, offer:)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "actor_id" => actor.account_id,
            "organization_id" => actor.organization_id, "target_type" => TARGET_TYPE, "target_id" => nil,
            "project_id" => nil, "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => { "open_uniqueness_sha256" => offer[:uniqueness].unpack1("H*") }
          })
        end

        def canonical_payload_json(command)
          JSON.generate({ "canonical_role" => command.canonical_role,
                          "permission_mode" => command.permission_mode })
        end

        def norm(value) = (value.nil? || value == "") ? nil : value
      end
    end
  end
end
