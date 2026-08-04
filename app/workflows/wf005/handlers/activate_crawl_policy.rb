# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf005
    module Handlers
      # WF-005 ActivateCrawlPolicy (S-07-001; contracts/S-07.json MTX-030 policy limb, MTX-059
      # PRULE-008; WORKFLOW_SPECIFICATIONS.md § policy subflow :732).
      #
      # Activates a more restrictive immutable crawl policy version at Organization scope (an
      # OrganizationAdmin) or Project scope (a MarketingOperator). The frozen crawl-policy-v1
      # global ceiling (owner interim, DECISIONS ADR-068) is the outermost bound; an
      # Organization policy narrows the global; a Project policy narrows the active Organization
      # policy (or the global if none). Narrowing-only and complete: every proposed value at or
      # below the resolved parent AND global, soft <= hard, all twelve dimensions present. A
      # stale expected version (current, parent, or global), a broader/incomplete proposal, or
      # an unauthorized/mis-scoped actor changes nothing. Idempotent by the command's key.
      class ActivateCrawlPolicy
        include Wf005::CrawlLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "crawl_policy"
        ACTION = "policy.crawl.manage"
        CAPABILITY = "policy.crawl.manage"
        WORKFLOW_ID = "WF-005"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
            auth = IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
            store = IdentityAccess::Infrastructure::CrawlPolicyStore.new(pg)

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

          return denied(d, "tenant_mismatch") unless command.organization_id == actor.organization_id
          return denied(d, "crawl_policy_scope_invalid") unless valid_scope_shape?(command)

          decision = auth.authorize(actor:, capability: CAPABILITY, now:)
          d = d.merge(decision:)
          unless decision.allowed? && authorized_for_scope?(command.scope, decision)
            return deny(**denial_args(d), resource_id: scope_resource(command),
                        outward: "crawl_policy_unauthorized", internal: "crawl_policy_unauthorized")
          end

          return denied(d, "crawl_policy_incomplete") unless CrawlPolicy.complete?(command.proposed_bounds)
          return denied(d, "crawl_policy_soft_exceeds_hard") unless CrawlPolicy.soft_le_hard?(command.proposed_bounds)
          return denied(d, "crawl_policy_unavailable") unless command.expected_global_version == CrawlPolicy::GLOBAL_VERSION

          store.lock_organization(d[:org])

          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org: d[:org], command_type: command.command_type,
                                            target_type: TARGET_TYPE, target_id: scope_resource(command), key_digest:)
          return replay(d, existing) if existing && existing["request_hex"] == hex(d[:request_sha256])
          return denied(d, "idempotency_conflict") if existing

          # Under the per-scope lock: the version being superseded and the parent baseline must
          # match what the caller expected (a stale value changes nothing), then narrow.
          current = store.active_policy(d[:org], command.scope, command.project_id)
          return denied(d, "crawl_policy_stale_version") unless (current && current["policy_version"]) == command.expected_current_policy_version

          parent = resolve_parent(store, d[:org], command.scope)
          return denied(d, "crawl_policy_stale_version") unless parent[:version] == command.expected_parent_policy_version
          unless CrawlPolicy.narrows?(command.proposed_bounds, parent[:bounds]) &&
                 CrawlPolicy.narrows?(command.proposed_bounds, CrawlPolicy::GLOBAL_CEILING)
            return denied(d, "crawl_policy_not_narrowing")
          end


          # AUTHORITY RE-READ AFTER THE WAIT, IMMEDIATELY BEFORE THE IRREVERSIBLE ACT (round 7,
          # SEC-B1; :331/:333/:335, SEC-REQ-004/005). `pg_advisory_xact_lock` above is a BLOCKING wait:
          # this transaction can sit behind another for as long as that one holds the key, and a
          # revocation, suspension or policy change can commit inside that window.
          #
          # ADR-120 RULING 1 DRAWS ITS LINE AT "CAN WAIT", NOT AT "WAITS LONG". Round 6 repaired
          # `CancelCrawl` on exactly that reasoning and left this handler alone; round 7 reproduced the
          # consequence here on real PostgreSQL, advancing the Organization's authorization epoch under
          # an observed ungranted waiter and watching this command commit anyway. The platform-wide
          # deferral recorded at ADR-063/S-06-006 continues to cover handlers that authorize and act
          # with NO wait between the two; this is not one of them.
          attestation = Wf005::PostWaitDecision.new(d[:pg], entered_with: d[:now])
                                               .authority_attestation(auth_store: d[:auth_store], actor:)
          if attestation.nil?
            return deny(**denial_args(d), resource_id: scope_resource(command),
                        outward: "crawl_policy_unauthorized", internal: "crawl_policy_unauthorized")
          end

          commit(d, current, key_digest, attestation:)
        rescue LostRace
          raise Platform::InvariantViolation, "crawl policy superseded concurrently"
        end

        def commit(d, current, key_digest, attestation:)
          # THE WRITE IS WHAT REFUSES (round 9, R9-3). No Boolean arrangement of the guard above can
          # reach this line with proof of a post-wait recheck it did not perform.
          Wf005::AuthorityAttestation.require!(attestation, connection: d[:pg], actor: d[:actor])
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]
          actor = d[:actor]
          request_sha256 = d[:request_sha256]

          ids = %i[policy execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          ordinal = store.version_count(org, command.scope, command.project_id) + 1
          policy_version = "crawl-policy-#{command.scope}-v#{ordinal}"
          normalized = CrawlPolicy.normalize(command.proposed_bounds)
          digest = Platform::CanonicalJson.digest({ "scope" => command.scope, "bounds" => normalized })

          write_execution(store, command, ctx, org, ids[:execution], ids[:policy], actor, request_sha256,
                          key_digest, now, ACTION)
          write_authorization_decision(d[:auth_store], ids[:decision], ctx, command, actor, d[:decision], now,
                                       ids[:policy], ACTION)
          # Supersede the prior active version BEFORE inserting the new one, so the
          # one-active-per-scope partial-unique index never sees two active rows at once.
          if current
            raise LostRace if store.supersede(current["id"], current["state_version"].to_i, now).to_i.zero?
          end
          store.insert_policy_version(
            id: ids[:policy], now:, correlation_id: ctx.correlation_id, organization_id: org,
            project_id: command.project_id, scope: command.scope, policy_version:,
            supersedes_id: current && current["id"], activated_by_account_id: actor.account_id,
            normalized_bounds: normalized, content_sha256: digest
          )

          payload = {
            "crawl_policy_id" => ids[:policy], "organization_id" => org, "project_id" => command.project_id,
            "scope" => command.scope, "policy_version" => policy_version,
            "superseded_policy_version" => current && current["policy_version"], "normalized_bounds" => normalized
          }
          write_audit(store, ids[:audit], org, ctx, command, ids[:policy], actor,
                      to_state: "active", outcome: "success", reason_code: nil, payload:, now:)
          write_event(store, ids, org, ctx, command, actor, now, 0, ids[:policy], request_sha256, key_digest,
                      "CrawlPolicyActivated", "policy_activation",
                      { "project_id" => command.project_id, "scope" => command.scope,
                        "policy_version" => policy_version,
                        "superseded_policy_version" => current && current["policy_version"] })
          write_result_success(store, ids, command, ctx, org, actor, now, payload, ids[:policy])
          write_idempotency(store, ids[:idem], org, command, scope_resource(command), key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        # ---- resolution + authorization -----------------------------------------

        # The parent baseline the proposal must narrow: an Organization policy narrows the frozen
        # global ceiling; a Project policy narrows the active Organization policy, or the global
        # ceiling when the Organization has none.
        def resolve_parent(store, org, scope)
          if scope == "project"
            org_policy = store.active_policy(org, "organization", nil)
            return { version: org_policy["policy_version"], bounds: symbolize_bounds(org_policy["normalized_bounds"]) } if org_policy
          end
          { version: CrawlPolicy::GLOBAL_VERSION, bounds: CrawlPolicy::GLOBAL_CEILING }
        end

        # Org scope requires an OrganizationAdmin grant; Project scope requires a MarketingOperator
        # grant (WORKFLOW_SPECIFICATIONS.md :173 / MTX-030 permission_checks — each role narrows
        # exactly its scope).
        def authorized_for_scope?(scope, decision)
          roles = decision.granting.map { |a| a["canonical_role"] }
          case scope
          when "organization" then roles.include?("OrganizationAdmin")
          when "project"      then roles.include?("MarketingOperator")
          else false
          end
        end

        def valid_scope_shape?(command)
          (command.scope == "organization" && command.project_id.nil?) ||
            (command.scope == "project" && !command.project_id.nil?)
        end

        def scope_resource(command) = command.project_id || command.organization_id

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
          deny(**denial_args(d.merge(decision:)), resource_id: scope_resource(d[:command]), outward: reason, internal: reason)
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
            "target_id" => scope_resource(command), "scope" => command.scope,
            "project_id" => command.project_id, "expected_version" => command.expected_current_policy_version,
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => {
              "scope" => command.scope,
              "expected_current_policy_version" => command.expected_current_policy_version,
              "expected_parent_policy_version" => command.expected_parent_policy_version,
              "expected_global_version" => command.expected_global_version,
              "proposed_bounds" => CrawlPolicy.complete?(command.proposed_bounds) ? CrawlPolicy.normalize(command.proposed_bounds) : command.proposed_bounds
            }
          })
        end

        def symbolize_bounds(raw)
          raw.is_a?(::String) ? JSON.parse(raw) : raw
        end

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR

        class LostRace < StandardError; end
      end
    end
  end
end
