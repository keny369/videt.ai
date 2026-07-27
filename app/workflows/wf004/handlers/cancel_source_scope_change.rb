# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf004
    module Handlers
      # WF-004 CancelSourceScopeChange (S-06-004; WORKFLOW_SPECIFICATIONS.md § Source Scope
      # Change Contract :421; contracts/S-06.json MTX-029). Cancels a PENDING Source Scope
      # Change Request from pending only, guarded on the expected request state version, with a
      # 20-2,000 character reason. It changes no policy and no Source state and emits
      # SourceScopeChangeCanceled. Idempotent by the command's idempotency key.
      #
      # Cancellation is identity-authorized rather than capability-authorized: the requester
      # may cancel their own request, and an OrganizationAdmin may cancel any request in the
      # tenant. No other role — including a MarketingOperator who is not the requester — may
      # cancel, so the check is on the actor's Account and effective OrganizationAdmin role,
      # not on policy.source_scope.manage.
      class CancelSourceScopeChange
        include Wf004::SourceLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "source_scope_change_request"
        ACTION = "source.scope.cancel"
        WORKFLOW_ID = "WF-004"

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
            process(d, auth_store)
          end
        end

        private

        def process(d, auth_store)
          command = d[:command]
          store = d[:store]
          actor = d[:actor]
          now = d[:now]

          request = store.read_request(command.request_id)
          return denied(d, "tenant_mismatch") if request.nil? || request["organization_id"] != actor.organization_id
          return denied(d, "tenant_mismatch") unless command.organization_id == actor.organization_id
          return denied(d, "tenant_mismatch") unless command.project_id == request["project_id"]
          return denied(d, "tenant_mismatch") unless command.source_id == request["source_id"]

          decision = cancel_decision(auth_store, actor, request, now)
          d = d.merge(decision:)
          unless decision.allowed?
            return deny(**denial_args(d), resource_id: command.request_id,
                        outward: "source_scope_cancel_unauthorized", internal: "source_scope_cancel_unauthorized")
          end

          # The idempotency check precedes the request-state and version checks: a successful
          # cancel moves the request out of pending and advances its version, so an exact replay
          # must return the stored result rather than be rejected as not-pending or stale.
          store.lock_source(request["source_id"])
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org: d[:org], command_type: command.command_type,
                                            target_type: TARGET_TYPE, target_id: command.request_id, key_digest:)
          return replay(d, existing) if existing && existing["request_hex"] == hex(d[:request_sha256])
          return denied(d, "idempotency_conflict") if existing

          # Re-read under the lock: a concurrent decision or expiry may have won.
          request = store.read_request(command.request_id)
          return denied(d, "source_scope_request_not_pending") unless request["state"] == "pending"
          return denied(d, "stale_request_version") unless request["state_version"].to_i == command.expected_request_state_version
          # At or after due_at the expiry transition wins over a cancellation (MTX-029 concurrency).
          return denied(d, "source_scope_request_expired") if expiry_due?(request, now)
          return denied(d, "source_scope_reason_invalid") unless valid_reason?(command.cancel_reason)

          commit(d, request, key_digest)
        rescue LostRace
          raise Platform::InvariantViolation, "source scope change decided concurrently"
        end

        def commit(d, request, key_digest)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]
          actor = d[:actor]
          request_sha256 = d[:request_sha256]

          ids = %i[execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          expected = command.expected_request_state_version
          raise LostRace if store.transition_request(
            command.request_id, expected, "canceled",
            decision_actor_id: actor.account_id, decision_reason: command.cancel_reason,
            activated_policy_version: nil, now:
          ).to_i.zero?

          payload = {
            "source_scope_change_request_id" => command.request_id, "source_id" => command.source_id,
            "project_id" => command.project_id, "organization_id" => org, "state" => "canceled",
            "decision_reason" => command.cancel_reason
          }
          write_execution(store, command, ctx, org, ids[:execution], command.request_id, actor, request_sha256,
                          key_digest, now, ACTION)
          write_authorization_decision(d[:auth_store], ids[:decision], ctx, command, actor, d[:decision], now,
                                       command.request_id, ACTION)
          write_audit(store, ids[:audit], org, ctx, command, command.request_id, actor,
                      to_state: "canceled", outcome: "success", reason_code: nil, payload:, now:)
          write_event(store, ids, org, ctx, command, actor, now, request["state_version"].to_i + 1,
                      command.request_id, request_sha256, key_digest, "SourceScopeChangeCanceled", "state_transition",
                      { "source_id" => command.source_id, "affected_entity_id" => command.request_id,
                        "from_state" => "pending", "to_state" => "canceled",
                        "decision_reason" => command.cancel_reason })
          write_result_success(store, ids, command, ctx, org, actor, now, payload, command.request_id)
          write_idempotency(store, ids[:idem], org, command, command.request_id, key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        # A synthesized authorization Decision for the identity-based cancel rule: the requester
        # (self-cancel) or an OrganizationAdmin (any request in the tenant). Recorded on the
        # authorization ledger exactly like a capability decision.
        def cancel_decision(auth_store, actor, request, now)
          requester = actor.account_id == request["requester_account_id"]
          assignments = auth_store.effective_role_assignments(account_id: actor.account_id, now:)
          admin = assignments.select { |a| a["canonical_role"] == "OrganizationAdmin" }
          versions = assignments.map { |a| { "id" => a["id"], "state_version" => a["state_version"].to_i } }
          allowed = requester || !admin.empty?
          IdentityAccess::Authorization::Decision.new(
            allowed:, reason: allowed ? (requester ? "cancel_requester" : "cancel_admin") : "missing_authority",
            organization_epoch: actor.authorization_epoch, policy_snapshot_id: nil,
            role_assignment_versions: versions, granting_assignments: (requester ? [] : admin)
          )
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
              "expected_request_state_version" => command.expected_request_state_version,
              "cancel_reason" => command.cancel_reason
            }
          })
        end

        def valid_reason?(reason)
          reason.is_a?(::String) && reason.strip.length.positive? && reason.length.between?(20, 2000)
        end

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR

        # True once the request is at or past its expiry instant: expiry wins over a cancel.
        def expiry_due?(request, now)
          due = request["due_at_utc"]
          due && now >= (due.respond_to?(:getutc) ? due.getutc : Time.parse(due).getutc)
        end

        class LostRace < StandardError; end
      end
    end
  end
end
