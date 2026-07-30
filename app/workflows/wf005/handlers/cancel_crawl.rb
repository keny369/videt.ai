# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf005
    module Handlers
      # WF-005 CancelCrawl (S-07-009; WORKFLOW_SPECIFICATIONS.md :736, :738, :458, :551;
      # API_CONTRACTS.md :279; contracts/S-07.json MTX-030).
      #
      # Authenticates the actor, refuses a cross-tenant or missing Project, authorizes `crawl.cancel`
      # (:738 — "cancellation requires `crawl.cancel`", a permission separate from `crawl.trigger` even
      # though :147 gives them the same cells), and then, under the CRAWL ROW LOCK, moves a `queued` or
      # `running` Crawl to `canceled` with :456's `canceled` completion reason, releases its entitlement
      # reservation, and emits `CrawlCanceled`.
      #
      # :458'S BOUNDARY IS COMMIT ORDER, AND THE ROW LOCK IS WHAT MAKES IT A FACT. "A cancellation
      # committed STRICTLY BEFORE that checkpoint yields `Crawl.Canceled`; a cancellation at or after
      # the checkpoint is rejected as `crawl_already_terminal`." Both sides take `SELECT ... FOR UPDATE`
      # on the same row, so one of them commits first and the other sees it: this handler finds a
      # terminal Crawl and refuses with exactly the token :458 names, and the checkpoint finds a
      # cancelled one and derives nothing. Neither side implements the other's rule — `f1_crawls_guard`
      # refuses every edge out of a terminal state, so the losing party could not write even if it tried.
      #
      # THE RESERVATION IS RELEASED, NEVER COMMITTED. ":551 — Cancellation or any terminal failure
      # before the listed commit point RELEASES exactly once even when intermediate Documents or other
      # partial artifacts exist; those artifacts remain governed by their workflow but are NOT a usage
      # commitment." A cancelled run is never `crawl_completed_with_valid_document`, whatever it managed
      # to fetch first, so the customer is not charged for it.
      #
      # NO COVERAGE STATUS. `crawls_terminal_shape` requires it only of `completed` (ADR-097), and a
      # cancelled run's coverage is not a number anyone should read: the run was stopped, not measured.
      class CancelCrawl
        include Wf005::CrawlLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "crawl"
        ACTION = "crawl.cancel"
        CAPABILITY = "crawl.cancel"
        WORKFLOW_ID = "WF-005"
        COMPLETION_REASON = "canceled"
        RELEASE_REASON = "crawl_canceled"

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
            d = { command:, ctx:, store:, auth_store:, actor:, org: actor.organization_id, now:,
                  request_sha256:, pg:,
                  crawls: IdentityAccess::Infrastructure::CrawlStartStore.new(pg) }
            process(d, auth)
          end
        end

        private

        def process(d, auth)
          command = d[:command]
          actor = d[:actor]

          project = d[:store].project(d[:org], command.project_id)
          return denied(d, "tenant_mismatch") if project.nil? || command.organization_id != actor.organization_id

          decision = auth.authorize(actor:, capability: CAPABILITY, now: d[:now])
          d = d.merge(decision:)
          unless decision.allowed?
            return deny(**denial_args(d), resource_id: command.crawl_id,
                        outward: "crawl_cancel_unauthorized", internal: "crawl_cancel_unauthorized")
          end

          # THE SERIALIZATION AGAINST THE TERMINAL CHECKPOINT, taken before anything is read that
          # decides. Whichever of the two transactions reaches this row first wins :458's ordering, and
          # the other one then reads the winner's committed state rather than its own stale view.
          crawl = d[:crawls].lock_crawl(d[:org], command.crawl_id)
          return denied(d, "tenant_mismatch") if crawl.nil? || crawl["project_id"] != command.project_id

          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = d[:store].find_idempotency(org: d[:org], command_type: command.command_type,
                                                target_type: TARGET_TYPE, target_id: command.crawl_id,
                                                key_digest:)
          return replay(d, existing) if existing && existing["request_hex"] == hex(d[:request_sha256])
          return denied(d, "idempotency_conflict") if existing

          # :458's own token, for the run that had its one terminal selection first.
          if %w[completed failed canceled].include?(crawl["state"])
            return denied(d, "crawl_already_terminal")
          end
          # MTX-030's request schema carries the expected state version; a cancellation holding a
          # version the run has moved past is refused rather than applied to a Crawl its sender was not
          # looking at.
          return denied(d, "stale_state_version") if command.expected_state_version != crawl["state_version"].to_i

          commit(d, crawl, key_digest)
        end

        def commit(d, crawl, key_digest)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]
          actor = d[:actor]
          ids = %i[execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          from_state = crawl["state"]
          new_version = crawl["state_version"].to_i + 1

          # Guarded on the state AND the version, so a race that got past the read above still writes
          # nothing. Zero rows here would mean the lock did not hold, which is corruption rather than a
          # domain outcome.
          moved = d[:crawls].cancel(crawl["id"], crawl["state_version"].to_i, now)
          raise Platform::InvariantViolation, "crawl cancellation lost its serialized transition" if moved.to_i.zero?

          metering = release_reservation(d, crawl)

          payload = {
            "crawl_id" => crawl["id"], "organization_id" => org, "project_id" => command.project_id,
            "from_state" => from_state, "state" => "canceled", "completion_reason" => COMPLETION_REASON,
            "coverage_status" => nil, "terminal_at_utc" => now.iso8601(6),
            "entitlement_reservation_id" => crawl["entitlement_reservation_id"],
            "entitlement_outcome" => metering
          }
          write_execution(store, command, ctx, org, ids[:execution], crawl["id"], actor, d[:request_sha256],
                          key_digest, now, ACTION)
          write_authorization_decision(d[:auth_store], ids[:decision], ctx, command, actor, d[:decision], now,
                                       crawl["id"], ACTION)
          write_audit(store, ids[:audit], org, ctx, command, crawl["id"], actor,
                      to_state: "canceled", outcome: "success", reason_code: COMPLETION_REASON, payload:, now:)
          write_event(store, ids, org, ctx, command, actor, now, new_version, crawl["id"], d[:request_sha256],
                      key_digest, "CrawlCanceled", "state_transition",
                      { "project_id" => command.project_id, "crawl_id" => crawl["id"],
                        "from_state" => from_state, "to_state" => "canceled",
                        "completion_reason" => COMPLETION_REASON })
          write_result_success(store, ids, command, ctx, org, actor, now, payload, crawl["id"])
          write_idempotency(store, ids[:idem], org, command, crawl["id"], key_digest, d[:request_sha256],
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        # :551 — cancellation RELEASES exactly once, never commits, "even when intermediate Documents or
        # other partial artifacts exist". A `queued` Crawl has no reservation at all (POSTGRESQL_SCHEMA
        # :338 — "NULL until start"), and says so rather than guessing.
        def release_reservation(d, crawl)
          reservation_id = crawl["entitlement_reservation_id"]
          return "none" if reservation_id.nil?

          Platform::Entitlement::Service.new(d[:pg])
                                        .release(organization_id: d[:org], reservation_id:,
                                                 reason: RELEASE_REASON, now: d[:now]).to_s
        end

        # ---- replay + denial + helpers ---------------------------------------------

        def replay(d, existing)
          stored = d[:store].load_command_result(existing["command_result_id"])
          Platform::CommandResult.success(result_id: stored["id"], command_type: d[:command].command_type,
                                          payload: JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym),
                                          audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end

        def denied(d, reason)
          decision = d[:decision] || pre_authorization_decision(d[:actor])
          deny(**denial_args(d.merge(decision:)), resource_id: d[:command].crawl_id,
               outward: reason, internal: reason)
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
            "target_id" => command.crawl_id, "project_id" => command.project_id,
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => { "crawl_id" => command.crawl_id,
                                   "expected_state_version" => command.expected_state_version }
          })
        end

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
      end
    end
  end
end
