# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf013
    module Handlers
      # WF-013 RevokeInvitation (WORKFLOW_SPECIFICATIONS.md § invitation :246;
      # effective-permission checkpoint :322-329; APPLICATION_LAYER.md WF-013; slice
      # S-23). An authenticated Organization actor holding invitation.revoke revokes
      # an active Invitation in its Organization: active -> revoked, one
      # InvitationRevoked state-transition event, no receipt/nonce and no
      # Account/Assignment/Session. Authority is derived from the Session (never
      # caller-supplied), authorized against the Permission Baseline, and the
      # decision is recorded durably in-transaction (PRULE-044).
      #
      # Order: schema + reason-bounds; authenticate Session (enter context);
      # authorize invitation.revoke (record the decision); read the target under the
      # actor's context (a cross-Organization reference is not visible); exact replay
      # (already reauthorized by the fresh authenticate+authorize, APP:4216); active
      # state; expected state version; then the guarded transition. An unauthorized
      # actor is denied before the target is read, disclosing no existence.
      class RevokeInvitation
        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "invitation"
        ACTION = "invitation.revoke"
        CAPABILITY = "invitation.revoke"
        REASON_MIN = 20
        REASON_MAX = 2000

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          reason = normalize_reason(command.reason)
          return in_memory_failure(command, ctx, "invitation_reason_invalid") if reason == :invalid

          reference_digest = Digest::SHA256.digest(command.invitation_reference)
          key_digest = Digest::SHA256.digest(command.idempotency_key)

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            auth = IdentityAccess::Authorization::CommandAuthorizer.new(IdentityAccess::Infrastructure::AuthorizationStore.new(pg))
            auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
            store = IdentityAccess::Infrastructure::RevokeInvitationStore.new(pg)

            # 1. Authenticate the Session (enters the Organization context on success).
            actor = auth.authenticate(session_id: command.session_id, now:, correlation_id: ctx.correlation_id)
            return in_memory_failure(command, ctx, actor.to_s) if actor.is_a?(Symbol)

            # 2. Authorize the capability (records the durable decision below).
            decision = auth.authorize(actor:, capability: CAPABILITY, now:)

            d = { command:, ctx:, auth_store:, store:, actor:, decision:, org: actor.organization_id,
                  now:, key_digest:, reason: }

            unless decision.allowed?
              # missing_authority (F1-AUTH-403) / policy_unavailable (F1-DOMAIN-409),
              # before the target is read: no existence disclosed.
              return deny(**d, outward: decision.reason, internal: decision.reason,
                          invitation_id: nil, request_sha256: request_hash(command:, ctx:, actor:, invitation_id: nil, reason:))
            end

            # 3. Read the target under the actor's context; not visible => not found.
            inv = store.read_invitation_by_reference(reference_digest)
            if inv.nil?
              return deny(**d, outward: "invitation_not_active", internal: "invitation_not_active",
                          invitation_id: nil, request_sha256: request_hash(command:, ctx:, actor:, invitation_id: nil, reason:))
            end

            invitation_id = inv["id"]
            store.lock_invitation(invitation_id)
            inv = store.read_invitation_by_reference(reference_digest)
            request_sha256 = request_hash(command:, ctx:, actor:, invitation_id:, reason:)
            d = d.merge(invitation_id:, request_sha256:)

            # 4. Exact replay / idempotency (post-reauthorization).
            existing = store.find_idempotency(org: actor.organization_id, command_type: command.command_type,
                                              target_type: TARGET_TYPE, target_id: invitation_id, key_digest:)
            if existing
              return rebuild_stored_result(store, existing, command) if existing["request_hex"] == hex(request_sha256)

              return deny(**d, outward: "idempotency_conflict", internal: "idempotency_conflict")
            end

            # 5. State + expected version.
            return deny(**d, outward: "invitation_not_active", internal: "invitation_not_active") unless inv["state"] == "active"
            unless command.expected_state_version == inv["state_version"].to_i
              return deny(**d, outward: "stale_state_version", internal: "stale_state_version")
            end

            succeed(**d, inv:)
          end
        end

        private

        # ---- success ------------------------------------------------------------

        def succeed(command:, ctx:, auth_store:, store:, actor:, decision:, org:, now:, key_digest:, reason:, invitation_id:, request_sha256:, inv:)
          ids = %i[execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          causation = ctx.correlation_id
          new_version = inv["state_version"].to_i + 1

          write_execution(store, command, ctx, org, ids[:execution], invitation_id, actor, request_sha256, key_digest, now, causation)
          write_authorization_decision(auth_store, ids[:decision], ctx, command, actor, decision, now, invitation_id)

          changed = store.revoke_invitation(invitation_id, inv["state_version"].to_i, now, reason)
          raise LostRace if changed.to_i.zero?

          store.update_registry_terminal(invitation_id, "revoked", now)

          payload = { "invitation_id" => invitation_id, "organization_id" => org, "state" => "revoked" }
          write_audit(store, ids[:audit], org, ctx, causation, command, invitation_id, actor,
                      to_state: "revoked", outcome: "success", reason_code: nil,
                      payload: payload.merge("outcome" => "success", "reason" => reason,
                                             "requester_account_id" => inv["requester_account_id"]), now:)
          write_event(store, ids, org, ctx, causation, command, actor, now, new_version, invitation_id,
                      request_sha256, key_digest, reason, inv["requester_account_id"])
          write_result_success(store, ids, command, ctx, org, actor, now, payload, invitation_id)
          write_idempotency(store, ids[:idem], org, command, invitation_id, key_digest, request_sha256, ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        rescue LostRace
          raise Platform::InvariantViolation, "invitation transitioned concurrently"
        end

        # ---- denial (records execution + the authorization decision + audit + result)

        def deny(command:, ctx:, auth_store:, store:, actor:, decision:, org:, now:, key_digest:, reason:,
                 outward:, internal:, invitation_id:, request_sha256:)
          execution_id = ctx.generate_id
          audit_id = ctx.generate_id
          result_id = ctx.generate_id
          decision_id = ctx.generate_id
          causation = ctx.correlation_id

          write_execution(store, command, ctx, org, execution_id, invitation_id, actor, request_sha256, key_digest, now, causation)
          write_authorization_decision(auth_store, decision_id, ctx, command, actor, decision, now, invitation_id)
          write_audit(store, audit_id, org, ctx, causation, command, invitation_id || command.command_id, actor,
                      to_state: nil, outcome: "failure", reason_code: internal,
                      payload: { "outcome" => "failure", "internal_reason" => internal, "outward_reason" => outward,
                                 "invitation_id" => invitation_id, "organization_id" => org }, now:)
          failure = Platform::ErrorCatalog.failure(outward, support_reference: ctx.correlation_id)
          write_result_failure(store, result_id, execution_id, command, ctx, org, actor, audit_id, failure, now)
          Platform::CommandResult.failure(result_id:, command_type: command.command_type, failure:,
                                          audit_record_id: audit_id, correlation_id: ctx.correlation_id)
        end

        def rebuild_stored_result(store, existing, command)
          stored = store.load_command_result(existing["command_result_id"])
          payload = JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym)
          Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type, payload:,
                                          audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end

        # ---- writers ------------------------------------------------------------

        def write_execution(store, command, ctx, org, id, invitation_id, actor, request_sha256, key_digest, now, causation)
          store.insert_command_execution(
            id:, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: causation,
            command_id: command.command_id, idempotency_key_digest: key_digest, command_type: command.command_type,
            command_schema_version: command.schema_version, actor_id: actor.account_id, organization_id: org,
            target_type: TARGET_TYPE, target_id: invitation_id, action: ACTION,
            requested_at: iso(command.requested_at_utc), authorization_check_at: iso(now),
            policy_versions: policy_versions_json, canonical_payload: canonical_payload_json(command), request_sha256:
          )
        end

        def write_authorization_decision(auth_store, id, ctx, command, actor, decision, now, resource_id)
          auth_store.insert_authorization_decision(
            id:, created_at: iso(now), organization_id: actor.organization_id, correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id, subject_id: actor.account_id,
            action: ACTION, resource_type: TARGET_TYPE, resource_id:, decision: decision.allowed? ? "allow" : "deny",
            reason_code: decision.reason, organization_epoch: decision.organization_epoch,
            membership_snapshot: JSON.generate({ "status" => decision.allowed? ? "active" : "no_active_grant" }),
            role_assignment_versions: JSON.generate(decision.role_assignment_versions),
            policy_snapshot_id: decision.policy_snapshot_id, decided_at: iso(now)
          )
        end

        def write_audit(store, id, org, ctx, causation, command, entity_id, actor, to_state:, outcome:, reason_code:, payload:, now:)
          store.insert_audit(
            id:, occurred_at: iso(now), partition_month: month(now), organization_id: org, actor_id: actor.account_id,
            correlation_id: ctx.correlation_id, causation_id: causation, command_id: command.command_id,
            entity_type: "invitation", entity_id:, to_state:, outcome:, reason_code:,
            payload: JSON.generate(payload), content_sha256: Platform::CanonicalJson.digest(payload)
          )
        end

        def write_event(store, ids, org, ctx, causation, command, actor, now, new_version, invitation_id, request_sha256, key_digest, reason, requester)
          envelope = {
            "account_id" => actor.account_id, "actor_id" => actor.account_id, "affected_entity_id" => invitation_id,
            "affected_entity_type" => "invitation", "aggregate_version" => new_version, "audit_record_id" => ids[:audit],
            "causation_id" => causation, "command_id" => command.command_id, "correlation_id" => ctx.correlation_id,
            "event_id" => ids[:event], "event_profile" => "state_transition", "event_type" => "InvitationRevoked",
            "from_state" => "active", "idempotency_identity_hash" => hex(key_digest), "input_hash" => hex(request_sha256),
            "invitation_id" => invitation_id, "occurred_at_utc" => now.iso8601(6), "organization_epoch" => actor.authorization_epoch,
            "organization_id" => org, "outcome" => "success", "project_id" => nil, "reason" => reason,
            "reason_code" => nil, "requester_account_id" => requester, "schema_version" => "1.0",
            "to_state" => "revoked", "workflow_id" => "WF-013"
          }
          bytes = Platform::CanonicalJson.encode(envelope)
          store.insert_event(
            id: ids[:event], created_at: iso(now), event_type: "InvitationRevoked", event_profile: "state_transition",
            occurred_at: iso(now), organization_id: org, aggregate_type: "invitation", aggregate_id: invitation_id,
            aggregate_version: new_version, partition_month: month(now), correlation_id: ctx.correlation_id,
            causation_id: causation, command_id: command.command_id, audit_record_id: ids[:audit],
            event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
          )
        end

        def write_result_success(store, ids, command, ctx, org, actor, now, payload, invitation_id)
          store.insert_command_result(
            id: ids[:result], created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, command_execution_id: ids[:execution], outcome: "success",
            organization_id: org, actor_id: actor.account_id, completed_at: iso(now), authorization_check_at: iso(now),
            target_refs: JSON.generate({ "invitation" => invitation_id }), governing_policy_versions: policy_versions_json,
            failure: nil, authorized_payload: JSON.generate(payload), audit_record_id: ids[:audit]
          )
        end

        def write_result_failure(store, result_id, execution_id, command, ctx, org, actor, audit_id, failure, now)
          store.insert_command_result(
            id: result_id, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, command_execution_id: execution_id, outcome: "failure",
            organization_id: org, actor_id: actor.account_id, completed_at: iso(now), authorization_check_at: iso(now),
            target_refs: JSON.generate({}), governing_policy_versions: policy_versions_json, failure:,
            authorized_payload: JSON.generate({}), audit_record_id: audit_id
          )
        end

        def write_idempotency(store, id, org, command, invitation_id, key_digest, request_sha256, execution_id, result_id, now)
          store.insert_idempotency(
            id:, created_at: iso(now), organization_id: org, command_type: command.command_type,
            target_type: TARGET_TYPE, target_id: invitation_id, key_digest:, request_sha256:,
            command_execution_id: execution_id, command_result_id: result_id, retain_until: iso(now + (30 * 24 * 3600))
          )
        end

        # ---- degenerate / helpers ----------------------------------------------

        def schema_failure(command, ctx) = in_memory_failure(command, ctx, "command_schema_unsupported")

        def in_memory_failure(command, ctx, reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                          failure:, audit_record_id: ctx.generate_id, correlation_id: ctx.correlation_id)
        end

        # nil-or-blank/out-of-bounds => :invalid; else the trimmed 20-2,000 reason
        # (revoke's reason is mandatory, :246).
        def normalize_reason(raw)
          return :invalid if raw.nil?

          trimmed = raw.to_s.strip
          return :invalid unless (REASON_MIN..REASON_MAX).cover?(trimmed.length)

          trimmed
        end

        def request_hash(command:, ctx:, actor:, invitation_id:, reason:)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "actor_id" => actor.account_id,
            "organization_id" => actor.organization_id, "target_type" => TARGET_TYPE, "target_id" => invitation_id,
            "project_id" => nil, "expected_version" => command.expected_state_version,
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => { "reason" => reason }
          })
        end

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
        def policy_versions_json = JSON.generate({ "permission_baseline" => Platform::PermissionBaseline::VERSION })
        def canonical_payload_json(command) = JSON.generate({ "reason_length" => command.reason.to_s.strip.length })
        def iso(time) = time.getutc.iso8601(6)
        def month(time) = Date.new(time.year, time.month, 1).iso8601
        def hex(bytes) = bytes.unpack1("H*")

        class LostRace < StandardError; end
      end
    end
  end
end
