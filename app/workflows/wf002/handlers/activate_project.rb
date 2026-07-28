# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf002
    module Handlers
      # WF-002 ActivateProject (S-03; contracts/S-03.json MTX-027 activation limb;
      # WORKFLOW_SPECIFICATIONS.md § WF-002 :651-666; owner D3, DECISIONS ADR-072).
      #
      # Authenticates the actor, refuses a cross-tenant/missing Project, authorizes
      # `project.activate` (distinct from `project.create` — holding create never implies
      # activate), then — under the per-Project lock and idempotently — validates the expected
      # Project state version (stale_state_version) and the expected Source-membership version
      # (source_membership_changed), requires the Project to be draft (project_not_draft) and at
      # least one active same-Project Source (active_source_required), and transitions
      # draft -> active exactly once, emitting `ProjectActivated`. It changes no other state.
      #
      # First-match failure order (MTX-027 error_contract, normative — "the order is normative, not
      # advisory"): schema -> tenant -> authorization -> project_not_draft -> active_source_required ->
      # source_membership_changed -> stale_state_version. A stale/changed version or an already-active
      # Project changes nothing (naturally idempotent by the state guard; exact replay returns the
      # stored result).
      #
      # LIMITATION (owner D5, DECISIONS ADR-073 / FU-3): the active-Source precondition is enforced by
      # count and `source_membership_changed` compares `expected_source_membership_version` against
      # `projects.source_set_version`. The canonical immutable source-set SEALING subsystem
      # (`source_set_versions`/`source_set_memberships`, POSTGRESQL_SCHEMA.md :287-288) that would make a
      # concurrent Source-membership change detectable and record the sealed Source set is NOT yet built
      # — a pre-existing shared-infrastructure gap (also consumed by WF-011 reassessment). Until it
      # exists, membership-change detection and selected-Source sealing are NOT fully enforceable here;
      # no immutable source-set sealing is implemented in this tranche. Behaviour is deliberately left
      # as-is (no in-tranche digest / no partial substitute) per D5; tracked as follow-up FU-3.
      class ActivateProject
        include Wf002::ProjectLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "project"
        ACTION = "project.activate"
        CAPABILITY = "project.activate"
        WORKFLOW_ID = "WF-002"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
            auth = IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
            store = IdentityAccess::Infrastructure::ProjectStore.new(pg)

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

          project = store.project(d[:org], command.project_id)
          return denied(d, "tenant_mismatch") if project.nil? || command.organization_id != actor.organization_id

          decision = auth.authorize(actor:, capability: CAPABILITY, now:)
          d = d.merge(decision:)
          unless decision.allowed?
            return deny(**denial_args(d), outward: "project_activate_unauthorized", internal: "project_activate_unauthorized")
          end

          store.lock_project(d[:org], command.project_id)

          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org: d[:org], command_type: command.command_type,
                                            target_type: TARGET_TYPE, target_id: command.project_id, key_digest:)
          return replay(d, existing) if existing && existing["request_hex"] == hex(d[:request_sha256])
          return denied(d, "idempotency_conflict") if existing

          # Re-read under the lock and apply the MTX-027 normative first-match order:
          # project_not_draft -> active_source_required -> source_membership_changed -> stale_state_version.
          project = store.project(d[:org], command.project_id)
          return denied(d, "project_not_draft") unless project["state"] == "draft"
          return denied(d, "active_source_required") if store.active_source_count(d[:org], command.project_id).zero?
          return denied(d, "source_membership_changed") unless project["source_set_version"].to_i == command.expected_source_membership_version
          return denied(d, "stale_state_version") unless project["state_version"].to_i == command.expected_state_version

          commit(d, project, key_digest)
        rescue LostRace
          raise Platform::InvariantViolation, "project activated concurrently"
        end

        def commit(d, project, key_digest)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]
          actor = d[:actor]
          request_sha256 = d[:request_sha256]

          ids = %i[execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          new_version = project["state_version"].to_i + 1
          raise LostRace if store.activate_project(org, command.project_id, command.expected_state_version, now).to_i.zero?

          payload = { "project_id" => command.project_id, "organization_id" => org, "state" => "active",
                      "state_version" => new_version }
          write_execution(store, command, ctx, org, ids[:execution], command.project_id, actor, request_sha256,
                          key_digest, now, ACTION)
          write_authorization_decision(d[:auth_store], ids[:decision], ctx, command, actor, d[:decision], now,
                                       command.project_id, ACTION)
          write_audit(store, ids[:audit], org, ctx, command, command.project_id, actor,
                      to_state: "active", outcome: "success", reason_code: nil, payload:, now:)
          write_event(store, ids, org, ctx, command, actor, now, new_version, command.project_id, request_sha256,
                      key_digest, "ProjectActivated", "state_transition", { "from_state" => "draft", "to_state" => "active" })
          write_result_success(store, ids, command, ctx, org, actor, now, payload, command.project_id)
          write_idempotency(store, ids[:idem], org, command, command.project_id, key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        # ---- replay + denial + helpers -------------------------------------------

        def replay(d, existing)
          stored = d[:store].load_command_result(existing["command_result_id"])
          command = d[:command]
          Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type,
                                          payload: JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym),
                                          audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end

        def denied(d, reason)
          decision = d[:decision] || pre_authorization_decision(d[:actor])
          deny(**denial_args(d.merge(decision:)), outward: reason, internal: reason)
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

        def request_hash(command, actor)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "actor_id" => actor.account_id,
            "organization_id" => actor.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => command.project_id, "project_id" => command.project_id,
            "expected_version" => command.expected_state_version,
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => { "expected_state_version" => command.expected_state_version,
                                   "expected_source_membership_version" => command.expected_source_membership_version }
          })
        end

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR

        class LostRace < StandardError; end
      end
    end
  end
end
