# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf005
    module Handlers
      # WF-005 QueueCrawl (S-07-002; contracts/S-07.json MTX-030 queue limb, MTX-058 PRULE-007;
      # WORKFLOW_SPECIFICATIONS.md § WF-005 :725-728, :734).
      #
      # Authenticates the actor, refuses a cross-tenant/missing Project, authorizes
      # `crawl.trigger`, requires an active Project, at least one active Source, and a resolvable
      # active Entitlement Policy, then — under the per-Project lock and idempotently — creates a
      # single root queued Crawl pinning the request-time crawl-policy (Project else Organization
      # active version, else the frozen global ceiling) and entitlement-policy versions, plus the
      # active Source set (each Source's state version + active Source Scope Policy id/version).
      # It reserves NO usage and creates NO Evaluation (those are StartCrawl + F-05, S-07-003).
      # The OD-018 guard refuses a root request while an initial Evaluation is pending/running.
      #
      # reassessment_required (a promoted Evaluation/Issue-set/ScoreSnapshot pair exists) is
      # governed by `current_score_projections`, an S-09 table not yet built: no Project can hold
      # a promoted pair before S-09, so the guard is vacuously satisfied here and every request is
      # a root initial-assessment Crawl. Its query is wired when S-09 builds promotion (interim
      # recorded, DECISIONS ADR-071).
      class QueueCrawl
        include Wf005::CrawlLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "crawl"
        ACTION = "crawl.queue"
        CAPABILITY = "crawl.trigger"
        WORKFLOW_ID = "WF-005"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
            auth = IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
            store = IdentityAccess::Infrastructure::CrawlStore.new(pg)

            actor = auth.authenticate(session_id: command.session_id, now:, correlation_id: ctx.correlation_id)
            return in_memory_failure(command, ctx, actor.to_s) if actor.is_a?(Symbol)

            request_sha256 = request_hash(command, actor)
            d = { command:, ctx:, store:, auth_store:, actor:, org: actor.organization_id, now:, request_sha256:, pg: }
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
            return deny(**denial_args(d), resource_id: command.project_id,
                        outward: "crawl_trigger_unauthorized", internal: "crawl_trigger_unauthorized")
          end

          return denied(d, "crawl_project_not_active") unless project["state"] == "active"
          entitlement = store.active_entitlement_policy(d[:org])
          return denied(d, "crawl_entitlement_unavailable") if entitlement.nil?
          sources = store.active_sources(d[:org], command.project_id)
          return denied(d, "crawl_no_active_source") if sources.empty?
          # reassessment_required: vacuously satisfied — no promotion mechanism exists yet (S-09).

          store.lock_project(d[:org], command.project_id)
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org: d[:org], command_type: command.command_type,
                                            target_type: TARGET_TYPE, target_id: command.project_id, key_digest:)
          return replay(d, existing) if existing && existing["request_hex"] == hex(d[:request_sha256])
          return denied(d, "idempotency_conflict") if existing

          # OD-018 queue-time guard, under the lock (re-checked at Queued->Running in S-07-003).
          return denied(d, "initial_evaluation_already_running") if store.running_initial_evaluation?(d[:org], command.project_id)

          commit(d, entitlement, sources, store.active_crawl_policy(d[:org], command.project_id), key_digest)
        end

        def commit(d, entitlement, sources, crawl_policy, key_digest)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]
          actor = d[:actor]
          request_sha256 = d[:request_sha256]

          ids = %i[crawl execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }

          store.insert_crawl(
            id: ids[:crawl], now:, correlation_id: ctx.correlation_id, organization_id: org,
            project_id: command.project_id, kind: "root",
            requested_crawl_policy_id: crawl_policy && crawl_policy["id"],
            requested_crawl_policy_version: crawl_policy && crawl_policy["policy_version"],
            requested_entitlement_policy_id: entitlement["id"],
            requested_entitlement_policy_version: entitlement["semantic_version"],
            trigger_kind: "manual", triggered_by_account_id: actor.account_id, idempotency_key_digest: key_digest
          )
          sources.each_with_index do |s, i|
            store.insert_crawl_source(
              id: ctx.generate_id, now:, correlation_id: ctx.correlation_id, organization_id: org,
              project_id: command.project_id, crawl_id: ids[:crawl], source_id: s["id"],
              source_state_version: s["state_version"].to_i, scope_policy_id: s["current_scope_policy_id"],
              scope_policy_version: s["scope_policy_version"], canonical_root_uri: s["canonical_root_uri"], source_order: i
            )
          end

          payload = {
            "crawl_id" => ids[:crawl], "organization_id" => org, "project_id" => command.project_id,
            "kind" => "root", "state" => "queued", "source_count" => sources.size,
            "requested_crawl_policy_version" => crawl_policy && crawl_policy["policy_version"],
            "requested_entitlement_policy_version" => entitlement["semantic_version"]
          }
          write_execution(store, command, ctx, org, ids[:execution], ids[:crawl], actor, request_sha256,
                          key_digest, now, ACTION)
          write_authorization_decision(d[:auth_store], ids[:decision], ctx, command, actor, d[:decision], now,
                                       ids[:crawl], ACTION)
          write_audit(store, ids[:audit], org, ctx, command, ids[:crawl], actor,
                      to_state: "queued", outcome: "success", reason_code: nil, payload:, now:)
          write_event(store, ids, org, ctx, command, actor, now, 0, ids[:crawl], request_sha256, key_digest,
                      "CrawlQueued", "created",
                      { "project_id" => command.project_id, "crawl_id" => ids[:crawl], "kind" => "root",
                        "state" => "queued", "source_count" => sources.size })
          write_result_success(store, ids, command, ctx, org, actor, now, payload, ids[:crawl])
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
          deny(**denial_args(d.merge(decision:)), resource_id: d[:command].project_id, outward: reason, internal: reason)
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
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => { "project_id" => command.project_id, "kind" => "root" }
          })
        end

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
      end
    end
  end
end
