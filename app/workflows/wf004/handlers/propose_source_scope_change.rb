# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf004
    module Handlers
      # WF-004 ProposeSourceScopeChange (WORKFLOW_SPECIFICATIONS.md § Source Scope Change
      # Contract :414, :705; APPLICATION_LAYER.md § WF-004; contracts/S-06.json MTX-029).
      # S-06-003, the pending-request path.
      #
      # It authenticates the actor, refuses a cross-tenant or missing Source, authorizes
      # `source.scope.propose`, validates the request shape (20-2,000 char reason; a
      # well-formed proposal), reads the Source's current active Source Scope Policy and
      # checks the expected active-policy version, classifies the change through the S-06-002
      # classifier (rejecting a boundary violation through the failure path), and then either
      # activates atomically or opens a pending request.
      #
      # S-06-004 fast-path (contract MTX-029 aggregate_boundary / transaction_boundary): a
      # CONTRACTION proposed by any `policy.source_scope.manage` holder (OrganizationAdmin or
      # MarketingOperator), or an EXPANSION proposed by an OrganizationAdmin, is created,
      # self-approved and activated in this one transaction — the request row and the new
      # immutable policy version commit together, emitting SourceScopeChangeRequested then
      # SourceScopeChangeApproved, with no 24-hour expiry timer. Every other authorized
      # proposal (a non-manage holder's contraction, a non-admin's expansion) creates exactly
      # one PENDING request with its 24-hour expiry timer (F-04) and a single
      # SourceScopeChangeRequested event, awaiting DecideSourceScopeChange. Idempotent either
      # way. A boundary violation is refused; the host is never a proposal input.
      class ProposeSourceScopeChange
        include Wf004::SourceLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "source_scope_change_request"
        ACTION = "source.scope.propose"
        CAPABILITY = "source.scope.propose"
        MANAGE_CAPABILITY = "policy.source_scope.manage"
        WORKFLOW_ID = "WF-004"
        SCHEMA_VERSION = "source-scope-change-request-v1"
        EXPIRY_HOURS = 24

        # The verified boundary a proposal may never exceed: HTTPS, its default port,
        # include "/", no exclude, retain_all — on the Source's verified canonical host
        # (the source-scope-interim-v1 shape).
        BOUNDARY_SCHEMES = ["https"].freeze
        BOUNDARY_PORTS = [443].freeze
        BOUNDARY_INCLUDES = ["/"].freeze

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
            auth = IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
            store = IdentityAccess::Infrastructure::SourceScopeChangeStore.new(pg)

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

          source = store.source(command.source_id)
          return denied(d, "tenant_mismatch") if source.nil? || source["organization_id"] != actor.organization_id
          return denied(d, "tenant_mismatch") unless command.organization_id == actor.organization_id
          return denied(d, "tenant_mismatch") unless command.project_id == source["project_id"]

          decision = auth.authorize(actor:, capability: CAPABILITY, now:)
          d = d.merge(decision:)
          unless decision.allowed?
            outward = decision.reason == "missing_authority" ? "source_scope_unauthorized" : decision.reason
            return deny(**denial_args(d), resource_id: command.source_id, outward:, internal: outward)
          end

          # Request-shape validation (envelope precedence: after authorization).
          return denied(d, "source_scope_reason_invalid") unless valid_reason?(command.request_reason)
          return denied(d, "source_scope_proposal_invalid") unless well_formed_proposal?(command)

          # The idempotency check precedes the active-policy-version check: the fast-path moves
          # the active version, so an exact replay of an auto-activating proposal (same key, same
          # original expected version) must return the stored result rather than be rejected as
          # stale. The per-Source advisory lock serializes concurrent proposals.
          store.lock_source(command.source_id)
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org: d[:org], command_type: command.command_type,
                                            target_type: TARGET_TYPE, target_id: command.source_id, key_digest:)
          return replay(d, existing) if existing && existing["request_hex"] == hex(d[:request_sha256])
          return denied(d, "idempotency_conflict") if existing

          # Re-read the Source UNDER the lock: a concurrent activation may have repointed it
          # since the pre-lock read, so its current pointer (the repoint guard) must be live.
          # This makes the stale-version precheck, the classification and the repoint guard all
          # agree, and a losing race returns a clean stale_active_policy_version rather than a
          # repoint LostRace.
          source = store.source(command.source_id)
          active = store.active_scope_policy(source["current_scope_policy_id"])
          return denied(d, "source_not_verified") if active.nil?
          return denied(d, "stale_active_policy_version") unless active["policy_version"] == command.expected_active_policy_version

          classification = classify(source, active, command)
          if classification.boundary_violation?
            outward = boundary_outward(classification.reason)
            return deny(**denial_args(d), resource_id: command.source_id, outward:, internal: outward)
          end

          # Fast-path eligibility (S-06-004): a contraction by any policy.source_scope.manage
          # holder, or an expansion by an OrganizationAdmin, activates atomically; every other
          # authorized proposal opens a pending request.
          manage = auth.authorize(actor:, capability: MANAGE_CAPABILITY, now:)
          admin = manage.allowed? && manage.granting.any? { |a| a["canonical_role"] == "OrganizationAdmin" }
          auto = (classification.contraction? && manage.allowed?) || (classification.expansion? && admin)

          return commit_fast_path(d.merge(manage:), source, active, key_digest) if auto

          commit(d, source, active, key_digest)
        rescue Wf004::SourceScopePolicyActivation::LostRace
          raise Platform::InvariantViolation, "source scope activated concurrently"
        end

        def commit(d, source, active, key_digest)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]
          actor = d[:actor]
          request_sha256 = d[:request_sha256]

          ids = %i[request execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          requested_at = now
          due_at = now + (EXPIRY_HOURS * 3600)
          proposed = normalized_proposed(source, command)
          proposed_digest = content_digest(proposed)

          write_execution(store, command, ctx, org, ids[:execution], ids[:request], actor, request_sha256,
                          key_digest, now, ACTION)
          write_authorization_decision(d[:auth_store], ids[:decision], ctx, command, actor, d[:decision], now,
                                       command.source_id, ACTION)
          store.insert_source_scope_change_request(
            id: ids[:request], now:, correlation_id: ctx.correlation_id, organization_id: org,
            project_id: command.project_id, source_id: command.source_id,
            requester_account_id: actor.account_id,
            expected_active_policy_version: command.expected_active_policy_version,
            current_content_sha256: unhex_bytea(active["content_sha256"]),
            proposed_canonical_host: proposed[:canonical_host], proposed_allowed_schemes: proposed[:allowed_schemes],
            proposed_allowed_ports: proposed[:allowed_ports], proposed_include_prefixes: proposed[:include_prefixes],
            proposed_exclude_prefixes: proposed[:exclude_prefixes], proposed_query_handling: proposed[:query_handling],
            proposed_content_sha256: proposed_digest, request_reason: command.request_reason,
            requested_at:, due_at:, idempotency_key_digest: key_digest
          )

          # The 24-hour expiry timer, scheduled on the same transaction through F-04.
          SourceScopeChangeExpirySchedule.schedule(
            pg: d[:pg], organization_id: org, project_id: command.project_id, request_id: ids[:request],
            due_at:, now:, correlation_id: ctx.correlation_id, command_id: command.command_id
          )

          payload = {
            "source_scope_change_request_id" => ids[:request], "source_id" => command.source_id,
            "project_id" => command.project_id, "organization_id" => org, "state" => "pending",
            "expected_active_policy_version" => command.expected_active_policy_version,
            "requested_at_utc" => iso(requested_at), "due_at_utc" => iso(due_at)
          }
          write_audit(store, ids[:audit], org, ctx, command, ids[:request], actor,
                      to_state: "pending", outcome: "success", reason_code: nil, payload:, now:)
          write_event(store, ids, org, ctx, command, actor, now, 0, ids[:request], request_sha256, key_digest,
                      "SourceScopeChangeRequested", "created",
                      { "source_id" => command.source_id, "source_scope_change_request_id" => ids[:request],
                        "affected_entity_id" => ids[:request], "state" => "pending",
                        "expected_active_policy_version" => command.expected_active_policy_version,
                        "proposed_content_sha256" => hex(proposed_digest),
                        "requested_at_utc" => iso(requested_at), "due_at_utc" => iso(due_at) })
          write_result_success(store, ids, command, ctx, org, actor, now, payload, ids[:request])
          write_idempotency(store, ids[:idem], org, command, command.source_id, key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        # The atomic fast-path: create the request, activate one new immutable policy version
        # and self-approve — all in this transaction — emitting SourceScopeChangeRequested (v0)
        # then SourceScopeChangeApproved (v1). No 24-hour expiry timer: the request is terminal.
        def commit_fast_path(d, source, active, key_digest)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]
          actor = d[:actor]
          request_sha256 = d[:request_sha256]

          ids = %i[request execution audit requested approved result propose_decision manage_decision idem]
                .to_h { |k| [k, ctx.generate_id] }
          requested_at = now
          proposed = normalized_proposed(source, command)
          proposed_digest = content_digest(proposed)

          write_execution(store, command, ctx, org, ids[:execution], ids[:request], actor, request_sha256,
                          key_digest, now, ACTION)
          write_authorization_decision(d[:auth_store], ids[:propose_decision], ctx, command, actor, d[:decision],
                                       now, command.source_id, ACTION)
          write_authorization_decision(d[:auth_store], ids[:manage_decision], ctx, command, actor, d[:manage],
                                       now, command.source_id, MANAGE_CAPABILITY)
          store.insert_source_scope_change_request(
            id: ids[:request], now:, correlation_id: ctx.correlation_id, organization_id: org,
            project_id: command.project_id, source_id: command.source_id, requester_account_id: actor.account_id,
            expected_active_policy_version: command.expected_active_policy_version,
            current_content_sha256: unhex_bytea(active["content_sha256"]),
            proposed_canonical_host: proposed[:canonical_host], proposed_allowed_schemes: proposed[:allowed_schemes],
            proposed_allowed_ports: proposed[:allowed_ports], proposed_include_prefixes: proposed[:include_prefixes],
            proposed_exclude_prefixes: proposed[:exclude_prefixes], proposed_query_handling: proposed[:query_handling],
            proposed_content_sha256: proposed_digest, request_reason: command.request_reason,
            requested_at:, due_at: now + (EXPIRY_HOURS * 3600), idempotency_key_digest: key_digest
          )

          write_event(store, ids.merge(event: ids[:requested]), org, ctx, command, actor, now, 0, ids[:request],
                      request_sha256, key_digest, "SourceScopeChangeRequested", "created",
                      { "source_id" => command.source_id, "source_scope_change_request_id" => ids[:request],
                        "affected_entity_id" => ids[:request], "state" => "pending",
                        "expected_active_policy_version" => command.expected_active_policy_version,
                        "proposed_content_sha256" => hex(proposed_digest), "requested_at_utc" => iso(requested_at) })

          activation = SourceScopePolicyActivation.activate(
            store:, ctx:, org:, project_id: command.project_id, source_id: command.source_id,
            proposed: proposed.merge(content_sha256: proposed_digest), current_policy_id: active["id"], now:
          )
          raise Wf004::SourceScopePolicyActivation::LostRace if store.transition_request(
            ids[:request], 0, "approved", decision_actor_id: actor.account_id, decision_reason: nil,
            activated_policy_version: activation[:policy_version], now:
          ).to_i.zero?

          payload = {
            "source_scope_change_request_id" => ids[:request], "source_id" => command.source_id,
            "project_id" => command.project_id, "organization_id" => org, "state" => "approved",
            "activated_policy_version" => activation[:policy_version],
            "expected_active_policy_version" => command.expected_active_policy_version,
            "requested_at_utc" => iso(requested_at)
          }
          # One audit row for the whole command, recording the terminal state it reached.
          write_audit(store, ids[:audit], org, ctx, command, ids[:request], actor,
                      to_state: "approved", outcome: "success", reason_code: nil, payload:, now:)
          write_event(store, ids.merge(event: ids[:approved]), org, ctx, command, actor, now, 1, ids[:request],
                      request_sha256, key_digest, "SourceScopeChangeApproved", "state_transition",
                      { "source_id" => command.source_id, "affected_entity_id" => ids[:request],
                        "from_state" => "pending", "to_state" => "approved",
                        "activated_policy_version" => activation[:policy_version] })
          write_result_success(store, ids, command, ctx, org, actor, now, payload, ids[:request])
          write_idempotency(store, ids[:idem], org, command, command.source_id, key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        # ---- classification ------------------------------------------------------

        # Build the current, proposed and boundary policies (all on the Source's verified
        # canonical host — a scope change never changes the host) and classify via S-06-002.
        def classify(source, active, command)
          host = source["canonical_host"]
          Wf004::ScopeChangeClassification.classify(
            current: policy_from_row(active, host),
            proposed: proposed_policy(source, command),
            boundary: SourceScopePredicate::Policy.new(
              canonical_host: host, allowed_schemes: BOUNDARY_SCHEMES, allowed_ports: BOUNDARY_PORTS,
              include_prefixes: BOUNDARY_INCLUDES, exclude_prefixes: [], query_handling: SourceScopePredicate::RETAIN_ALL
            )
          )
        end

        def policy_from_row(row, host)
          SourceScopePredicate::Policy.new(
            canonical_host: host, allowed_schemes: pg_array(row["allowed_schemes"]),
            allowed_ports: pg_array(row["allowed_ports"]).map(&:to_i),
            include_prefixes: pg_array(row["include_prefixes"]), exclude_prefixes: pg_array(row["exclude_prefixes"]),
            query_handling: row["query_handling"]
          )
        end

        def proposed_policy(source, command)
          p = normalized_proposed(source, command)
          SourceScopePredicate::Policy.new(
            canonical_host: p[:canonical_host], allowed_schemes: p[:allowed_schemes], allowed_ports: p[:allowed_ports],
            include_prefixes: p[:include_prefixes], exclude_prefixes: p[:exclude_prefixes],
            query_handling: p[:query_handling]
          )
        end

        # The proposed rules in normalized (sorted, de-duplicated) canonical form on the
        # verified host. Query handling stays "retain_all" or a sorted retained-key allowlist.
        def normalized_proposed(source, command)
          qh = command.proposed_query_handling
          {
            canonical_host: source["canonical_host"],
            allowed_schemes: command.proposed_allowed_schemes.map { |s| s.to_s.downcase }.uniq.sort,
            allowed_ports: command.proposed_allowed_ports.map(&:to_i).uniq.sort,
            include_prefixes: command.proposed_include_prefixes.map(&:to_s).uniq.sort,
            exclude_prefixes: command.proposed_exclude_prefixes.map(&:to_s).uniq.sort,
            query_handling: qh == SourceScopePredicate::RETAIN_ALL ? qh : Array(qh).map(&:to_s).uniq.sort
          }
        end

        def content_digest(proposed)
          Platform::CanonicalJson.digest({
            "canonical_host" => proposed[:canonical_host], "allowed_schemes" => proposed[:allowed_schemes],
            "allowed_ports" => proposed[:allowed_ports], "include_prefixes" => proposed[:include_prefixes],
            "exclude_prefixes" => proposed[:exclude_prefixes],
            "query_handling" => proposed[:query_handling]
          })
        end

        def boundary_outward(reason)
          case reason
          when "unsupported_source_scheme" then "unsupported_source_scheme"
          when "cross_host_expansion" then "cross_host_expansion"
          else "source_scope_boundary_violation"
          end
        end

        # ---- validation ----------------------------------------------------------

        def valid_reason?(reason)
          reason.is_a?(::String) && reason.strip.length.positive? && reason.length.between?(20, 2000)
        end

        def well_formed_proposal?(command)
          array_of_nonblank?(command.proposed_include_prefixes) &&
            array_of_nonblank?(command.proposed_allowed_schemes) &&
            !Array(command.proposed_allowed_ports).empty? &&
            Array(command.proposed_allowed_ports).all? { |p| p.to_s.match?(/\A\d+\z/) } &&
            valid_query_handling?(command.proposed_query_handling) &&
            command.proposed_exclude_prefixes.is_a?(::Array)
        end

        def array_of_nonblank?(value)
          value.is_a?(::Array) && !value.empty? && value.all? { |v| v.is_a?(::String) && !v.strip.empty? }
        end

        def valid_query_handling?(value)
          value == SourceScopePredicate::RETAIN_ALL ||
            (value.is_a?(::Array) && value.all? { |k| k.is_a?(::String) && !k.strip.empty? })
        end

        # ---- idempotent replay + denial ------------------------------------------

        def replay(d, existing)
          store = d[:store]
          command = d[:command]
          stored = store.load_command_result(existing["command_result_id"])
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

        # ---- hashing / helpers ---------------------------------------------------

        def request_hash(command, actor)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "actor_id" => actor.account_id,
            "organization_id" => actor.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => command.source_id, "project_id" => command.project_id,
            "source_id" => command.source_id, "expected_version" => command.expected_active_policy_version,
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => {
              "expected_active_policy_version" => command.expected_active_policy_version,
              "request_reason" => command.request_reason,
              "proposed_allowed_schemes" => Array(command.proposed_allowed_schemes).map { |s| s.to_s.downcase }.uniq.sort,
              "proposed_allowed_ports" => Array(command.proposed_allowed_ports).map(&:to_i).uniq.sort,
              "proposed_include_prefixes" => Array(command.proposed_include_prefixes).map(&:to_s).uniq.sort,
              "proposed_exclude_prefixes" => Array(command.proposed_exclude_prefixes).map(&:to_s).uniq.sort,
              "proposed_query_handling" => query_handling_for_hash(command.proposed_query_handling)
            }
          })
        end

        def query_handling_for_hash(value)
          value == SourceScopePredicate::RETAIN_ALL ? value : Array(value).map(&:to_s).uniq.sort
        end

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR

        # Parse a PostgreSQL text/int array literal (e.g. "{https}", "{443}", "{/a,/b}").
        def pg_array(literal)
          return literal if literal.is_a?(::Array)
          return [] if literal.nil? || literal == "{}"

          literal.to_s.gsub(/\A\{|\}\z/, "").scan(/"(?:[^"\\]|\\.)*"|[^,]+/).map do |element|
            element.start_with?('"') ? element[1..-2].gsub(/\\(.)/, '\1') : element
          end
        end

        # content_sha256 arrives from PG as a hex-escaped bytea string ("\\x…"); the store
        # writes bytea, so convert back to raw bytes for re-insert on the request row.
        def unhex_bytea(value)
          return value unless value.is_a?(::String) && value.start_with?("\\x")

          [value[2..]].pack("H*")
        end
      end
    end
  end
end
