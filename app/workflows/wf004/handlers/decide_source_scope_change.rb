# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf004
    module Handlers
      # WF-004 DecideSourceScopeChange (S-06-004; WORKFLOW_SPECIFICATIONS.md § Source Scope
      # Change Contract :420-421; contracts/S-06.json MTX-029; APPLICATION_LAYER.md § WF-004
      # dual control). Approves or rejects a PENDING Source Scope Change Request.
      #
      # Guards (MTX-029 concurrency): the request must still be pending, its state version must
      # equal the expected request state version, AND the Source's current active-policy version
      # must equal the expected active-policy version — a stale value on either rejects with no
      # side effect, so a decision can never activate against a policy that moved underneath it.
      #
      # Dual control (re-classified against the current active policy via the S-06-002
      # classifier): a CONTRACTION needs no second party — any `policy.source_scope.manage`
      # holder (OrganizationAdmin or MarketingOperator) may approve or reject it. An EXPANSION
      # may be approved or rejected only by an OrganizationAdmin, and an approving Admin MUST be
      # a different Account from the requester (a pending expansion always has a non-admin
      # requester, since an Admin's expansion self-activates on Propose).
      #
      # Approval activates one new immutable policy version and repoints the Source
      # (SourceScopePolicyActivation, atomic in this transaction); rejection requires a 20-2,000
      # character reason and changes no scope. Idempotent by the command's idempotency key.
      class DecideSourceScopeChange
        include Wf004::SourceLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "source_scope_change_request"
        ACTION = "source.scope.decide"
        CAPABILITY = "policy.source_scope.manage"
        WORKFLOW_ID = "WF-004"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)
          return in_memory_failure(command, ctx, "source_scope_decision_invalid") unless %w[approve reject].include?(command.decision)

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

          request = store.read_request(command.request_id)
          return denied(d, "tenant_mismatch") if request.nil? || request["organization_id"] != actor.organization_id
          return denied(d, "tenant_mismatch") unless command.organization_id == actor.organization_id
          return denied(d, "tenant_mismatch") unless command.project_id == request["project_id"]
          return denied(d, "tenant_mismatch") unless command.source_id == request["source_id"]

          decision = auth.authorize(actor:, capability: CAPABILITY, now:)
          d = d.merge(decision:)
          unless decision.allowed?
            return deny(**denial_args(d), resource_id: command.request_id,
                        outward: "source_scope_decision_unauthorized", internal: "source_scope_decision_unauthorized")
          end

          # The idempotency check precedes the request-state and version checks: a successful
          # decision moves the request out of pending and advances its version, so an exact
          # replay must return the stored decision rather than be rejected as not-pending or
          # stale. A DIFFERENT command targeting an already-terminal request finds no matching
          # idempotency row and is correctly rejected below.
          store.lock_source(request["source_id"])
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org: d[:org], command_type: command.command_type,
                                            target_type: TARGET_TYPE, target_id: command.request_id, key_digest:)
          return replay(d, existing) if existing && existing["request_hex"] == hex(d[:request_sha256])
          return denied(d, "idempotency_conflict") if existing

          # Re-read under the lock: a concurrent decision may have won.
          request = store.read_request(command.request_id)
          return denied(d, "source_scope_request_not_pending") unless request["state"] == "pending"
          return denied(d, "stale_request_version") unless request["state_version"].to_i == command.expected_request_state_version
          # At or after due_at the expiry transition wins over a decision (MTX-029 concurrency).
          return denied(d, "source_scope_request_expired") if expiry_due?(request, now)

          source = store.source(request["source_id"])
          active = store.active_scope_policy(source && source["current_scope_policy_id"])
          return denied(d, "source_not_verified") if active.nil?
          return denied(d, "stale_active_policy_version") unless active["policy_version"] == command.expected_active_policy_version

          classification = classify(source, active, request)
          return denied(d, "source_scope_boundary_violation") if classification.boundary_violation?

          dual = dual_control_denial(command, actor, decision, request, classification)
          return denied(d, dual) if dual

          return denied(d, "source_scope_reason_invalid") if command.decision == "reject" && !valid_reason?(command.decision_reason)

          commit(d, source, active, request, key_digest)
        rescue Workflows::Wf004::SourceScopePolicyActivation::LostRace, LostRace
          raise Platform::InvariantViolation, "source scope change decided concurrently"
        end

        def commit(d, source, active, request, key_digest)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]
          actor = d[:actor]
          request_sha256 = d[:request_sha256]

          ids = %i[execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          approve = command.decision == "approve"
          activation = approve ? activate(d, source, active, request) : nil

          expected = command.expected_request_state_version
          to_state = approve ? "approved" : "rejected"
          raise LostRace if store.transition_request(
            command.request_id, expected, to_state,
            decision_actor_id: actor.account_id, decision_reason: approve ? nil : command.decision_reason,
            activated_policy_version: activation&.fetch(:policy_version), now:
          ).to_i.zero?

          payload = {
            "source_scope_change_request_id" => command.request_id, "source_id" => command.source_id,
            "project_id" => command.project_id, "organization_id" => org, "state" => to_state,
            "activated_policy_version" => activation&.fetch(:policy_version),
            "decision_reason" => approve ? nil : command.decision_reason
          }
          event_type = approve ? "SourceScopeChangeApproved" : "SourceScopeChangeRejected"
          write_execution(store, command, ctx, org, ids[:execution], command.request_id, actor, request_sha256,
                          key_digest, now, ACTION)
          write_authorization_decision(d[:auth_store], ids[:decision], ctx, command, actor, d[:decision], now,
                                       command.request_id, ACTION)
          write_audit(store, ids[:audit], org, ctx, command, command.request_id, actor,
                      to_state:, outcome: "success", reason_code: nil, payload:, now:)
          write_event(store, ids, org, ctx, command, actor, now, request["state_version"].to_i + 1, command.request_id,
                      request_sha256, key_digest, event_type, "state_transition",
                      { "source_id" => command.source_id, "affected_entity_id" => command.request_id,
                        "from_state" => "pending", "to_state" => to_state,
                        "activated_policy_version" => activation&.fetch(:policy_version),
                        "decision_reason" => approve ? nil : command.decision_reason })
          write_result_success(store, ids, command, ctx, org, actor, now, payload, command.request_id)
          write_idempotency(store, ids[:idem], org, command, command.request_id, key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        # The atomic policy-version activation for an approval, from the request's stored,
        # already-normalized proposed rules, guarded on the current active policy pointer.
        def activate(d, source, active, request)
          Wf004::SourceScopePolicyActivation.activate(
            store: d[:store], ctx: d[:ctx], org: d[:org], project_id: request["project_id"],
            source_id: request["source_id"], current_policy_id: active["id"], now: d[:now],
            proposed: {
              canonical_host: request["proposed_canonical_host"],
              allowed_schemes: pg_array(request["proposed_allowed_schemes"]),
              allowed_ports: pg_array(request["proposed_allowed_ports"]).map(&:to_i),
              include_prefixes: pg_array(request["proposed_include_prefixes"]),
              exclude_prefixes: pg_array(request["proposed_exclude_prefixes"]),
              query_handling: request["proposed_query_handling"],
              content_sha256: unhex_bytea(request["proposed_content_sha256"])
            }
          )
        end

        # ---- classification + dual control ---------------------------------------

        def classify(source, active, request)
          host = source["canonical_host"]
          Wf004::ScopeChangeClassification.classify(
            current: policy_from_row(active, host), proposed: proposed_from_request(request, host),
            boundary: SourceScopePredicate::Policy.new(
              canonical_host: host, allowed_schemes: ["https"], allowed_ports: [443],
              include_prefixes: ["/"], exclude_prefixes: [], query_handling: SourceScopePredicate::RETAIN_ALL
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

        def proposed_from_request(request, host)
          SourceScopePredicate::Policy.new(
            canonical_host: host, allowed_schemes: pg_array(request["proposed_allowed_schemes"]),
            allowed_ports: pg_array(request["proposed_allowed_ports"]).map(&:to_i),
            include_prefixes: pg_array(request["proposed_include_prefixes"]),
            exclude_prefixes: pg_array(request["proposed_exclude_prefixes"]),
            query_handling: request["proposed_query_handling"]
          )
        end

        # nil when authorised; the denial reason otherwise. A contraction needs no dual control
        # (any policy.source_scope.manage holder). An expansion requires an OrganizationAdmin,
        # and an approving Admin must differ from the requester.
        def dual_control_denial(command, actor, decision, request, classification)
          return nil if classification.contraction?

          admin = decision.granting.any? { |a| a["canonical_role"] == "OrganizationAdmin" }
          return "source_scope_decision_unauthorized" unless admin
          if command.decision == "approve" && actor.account_id == request["requester_account_id"]
            return "source_scope_decision_unauthorized"
          end

          nil
        end

        # ---- replay + denial + helpers -------------------------------------------

        # Only a committed success writes an idempotency row (deny does not), so an exact
        # replay always resolves to the stored success.
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
          deny(**denial_args(d.merge(decision:)), resource_id: d[:command].request_id, outward: reason, internal: reason)
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
            "target_id" => command.request_id, "project_id" => command.project_id,
            "source_id" => command.source_id, "expected_version" => command.expected_request_state_version,
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => {
              "decision" => command.decision,
              "expected_request_state_version" => command.expected_request_state_version,
              "expected_active_policy_version" => command.expected_active_policy_version,
              "decision_reason" => command.decision_reason
            }
          })
        end

        def valid_reason?(reason)
          reason.is_a?(::String) && reason.strip.length.positive? && reason.length.between?(20, 2000)
        end

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR

        # True once the request is at or past its expiry instant: expiry wins over a decision.
        def expiry_due?(request, now)
          due = request["due_at_utc"]
          due && now >= (due.respond_to?(:getutc) ? due.getutc : Time.parse(due).getutc)
        end

        def pg_array(literal)
          return literal if literal.is_a?(::Array)
          return [] if literal.nil? || literal == "{}"

          literal.to_s.gsub(/\A\{|\}\z/, "").scan(/"(?:[^"\\]|\\.)*"|[^,]+/).map do |element|
            element.start_with?('"') ? element[1..-2].gsub(/\\(.)/, '\1') : element
          end
        end

        def unhex_bytea(value)
          return value unless value.is_a?(::String) && value.start_with?("\\x")

          [value[2..]].pack("H*")
        end

        class LostRace < StandardError; end
      end
    end
  end
end
