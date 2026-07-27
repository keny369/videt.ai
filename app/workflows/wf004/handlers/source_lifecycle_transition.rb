# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf004
    module Handlers
      # The shared WF-004 Source lifecycle transition (S-06-006; PRULE-006 /
      # contracts/S-06.json MTX-057). ActivateSource, DisableSource, ReactivateSource and
      # RemoveSource are identical except for the (FROM_STATE -> TO_STATE) edge, the emitted
      # event, and the lifecycle timestamp column; each including class supplies those as
      # constants and this module is the whole handler.
      #
      # It authenticates, refuses a cross-tenant or missing Source, authorizes
      # `source.lifecycle.manage` (OrganizationAdmin or MarketingOperator only — a
      # TechnicalImplementer is refused), then — guarded by the expected Source state version
      # AND the current state being exactly FROM_STATE (the DB trigger independently refuses any
      # unlisted edge) — transitions the Source in one transaction, pinning the active policy
      # version and emitting the lifecycle event once. An unlisted or stale transition is denied
      # AND audited, changing nothing. Idempotent by the command's key.
      #
      # Including handlers MUST define ACTION, CAPABILITY, FROM_STATE, TO_STATE, EVENT_TYPE and
      # TIMESTAMP_COLUMN (and inherit TARGET_TYPE/SUPPORTED_SCHEMA_MAJOR/WORKFLOW_ID below).
      module SourceLifecycleTransition
        def self.included(base)
          base.include(Wf004::SourceLedger)
          base.const_set(:TARGET_TYPE, "source") unless base.const_defined?(:TARGET_TYPE, false)
          base.const_set(:SUPPORTED_SCHEMA_MAJOR, "1") unless base.const_defined?(:SUPPORTED_SCHEMA_MAJOR, false)
          base.const_set(:WORKFLOW_ID, "WF-004") unless base.const_defined?(:WORKFLOW_ID, false)
        end

        # Source states whose transition records the (degenerate pre-S-07) affected-running-Crawl
        # decision record — an empty list until S-07 builds crawls.
        AFFECTED_RUN_STATES = %w[disabled removed].freeze

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
            auth = IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
            store = IdentityAccess::Infrastructure::SourceLifecycleStore.new(pg)

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

          source = store.source(command.source_id)
          return denied(d, "tenant_mismatch") if source.nil? || source["organization_id"] != actor.organization_id
          return denied(d, "tenant_mismatch") unless command.organization_id == actor.organization_id
          return denied(d, "tenant_mismatch") unless command.project_id == source["project_id"]

          decision = auth.authorize(actor:, capability: self.class::CAPABILITY, now:)
          d = d.merge(decision:)
          unless decision.allowed?
            return deny(**denial_args(d), resource_id: command.source_id,
                        outward: "source_lifecycle_unauthorized", internal: "source_lifecycle_unauthorized")
          end

          reason = lifecycle_reason(command)
          return denied(d, "source_lifecycle_reason_invalid") if reason && !valid_reason?(reason)

          store.lock_source(command.source_id)

          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org: d[:org], command_type: command.command_type,
                                            target_type: self.class::TARGET_TYPE, target_id: command.source_id, key_digest:)
          return replay(d, existing) if existing && existing["request_hex"] == hex(d[:request_sha256])
          return denied(d, "idempotency_conflict") if existing

          # Re-read under the lock. The state must be exactly the FROM state (an unlisted
          # transition — including a repeat from the new state — is denied and audited) and the
          # version must match (a stale version rejects with no side effect).
          source = store.source(command.source_id)
          return denied(d, "source_lifecycle_transition_invalid") unless source["state"] == self.class::FROM_STATE
          return denied(d, "stale_state_version") unless source["state_version"].to_i == command.expected_state_version

          commit(d, source, reason, key_digest)
        rescue LostRace
          raise Platform::InvariantViolation, "source lifecycle transitioned concurrently"
        end

        def commit(d, source, reason, key_digest)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]
          actor = d[:actor]
          request_sha256 = d[:request_sha256]

          ids = %i[execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          new_version = source["state_version"].to_i + 1
          raise LostRace if store.transition(
            command.source_id, self.class::FROM_STATE, self.class::TO_STATE, command.expected_state_version,
            self.class::TIMESTAMP_COLUMN, reason, now
          ).to_i.zero?

          extra = { "from_state" => self.class::FROM_STATE, "to_state" => self.class::TO_STATE,
                    "pinned_policy_version" => source["pinned_policy_version"] }
          extra["affected_running_crawls"] = [] if AFFECTED_RUN_STATES.include?(self.class::TO_STATE)
          payload = {
            "source_id" => command.source_id, "organization_id" => org, "project_id" => command.project_id,
            "state" => self.class::TO_STATE, "state_version" => new_version,
            "pinned_policy_version" => source["pinned_policy_version"], "lifecycle_reason" => reason
          }
          payload["affected_running_crawls"] = [] if AFFECTED_RUN_STATES.include?(self.class::TO_STATE)

          write_execution(store, command, ctx, org, ids[:execution], command.source_id, actor, request_sha256,
                          key_digest, now, self.class::ACTION)
          write_authorization_decision(d[:auth_store], ids[:decision], ctx, command, actor, d[:decision], now,
                                       command.source_id, self.class::ACTION)
          write_audit(store, ids[:audit], org, ctx, command, command.source_id, actor,
                      to_state: self.class::TO_STATE, outcome: "success", reason_code: nil, payload:, now:)
          write_event(store, ids, org, ctx, command, actor, now, new_version, command.source_id, request_sha256,
                      key_digest, self.class::EVENT_TYPE, "state_transition", extra)
          write_result_success(store, ids, command, ctx, org, actor, now, payload, command.source_id)
          write_idempotency(store, ids[:idem], org, command, command.source_id, key_digest, request_sha256,
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
          deny(**denial_args(d.merge(decision:)), resource_id: d[:command].source_id, outward: reason, internal: reason)
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
            "action" => self.class::ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "actor_id" => actor.account_id,
            "organization_id" => actor.organization_id, "target_type" => self.class::TARGET_TYPE,
            "target_id" => command.source_id, "project_id" => command.project_id,
            "source_id" => command.source_id, "expected_version" => command.expected_state_version,
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => { "expected_state_version" => command.expected_state_version,
                                   "lifecycle_reason" => lifecycle_reason(command) }
          })
        end

        def lifecycle_reason(command) = command.respond_to?(:lifecycle_reason) ? command.lifecycle_reason : nil
        def valid_reason?(reason) = reason.is_a?(::String) && reason.length.between?(1, 2000)
        def supported_schema?(version) = version.to_s.split(".").first == self.class::SUPPORTED_SCHEMA_MAJOR

        class LostRace < StandardError; end
      end
    end
  end
end
