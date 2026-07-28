# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf005
    module Handlers
      # WF-005 StartCrawl (S-07-003) — the service-only `Crawl.Queued -> Crawl.Running` commit
      # behind the ratified `crawl_dispatch` ScheduledAction that QueueCrawl schedules
      # (contracts/S-07.json MTX-030 start limb, MTX-058 PRULE-007; WORKFLOW_SPECIFICATIONS.md
      # § WF-005 :725-728, :734, :736; SEARCH_CRAWL_RETRIEVAL.md § Crawl Admission And Snapshot;
      # DECISIONS OD-018).
      #
      # The gate is HERE, not at queueing. Queueing persisted an authorized no-usage Crawl; this
      # commit re-resolves everything and, in ONE transaction, either accepts the start or fails
      # the queued Crawl at the exact pre-execution gate. Under the SAME per-Project advisory lock
      # QueueCrawl takes, and in this first-match order:
      #
      #   1. the Crawl is still `queued` (otherwise a harmless terminal execution),
      #   2. the Project is still active,
      #   3. at least one Source is still active,
      #   4. OD-018 — no pending/running initial Evaluation for the Project on ANOTHER Crawl,
      #   5. the CURRENT crawl policy resolves (global ceiling ∧ Organization ∧ Project — a new
      #      restriction affects queued work immediately, so it is re-resolved, never the pinned
      #      version), and
      #   6. the root `crawl.start` Entitlement Decision/reservation is obtained atomically (F-05).
      #
      # 2-6 are the "current-policy or Entitlement Block before start": each transitions the queued
      # Crawl to `failed` with its exact reason and NO fetch, provider side effect, reservation or
      # Evaluation (:734). An accepted start stamps the Decision/reservation, `started_at` (the
      # wall-clock origin — :736 "wall clock starts at the Queued -> Running transition") and the
      # resolved wall-clock deadline; creates EXACTLY ONE pending Evaluation keyed by
      # `(crawl_id, kind=initial)` plus its immutable orchestration context; and emits
      # `CrawlStarted` + `EvaluationPending`.
      #
      # Authority is not re-checked as a permission here and there is none to check: the human
      # `crawl.trigger` authorization was established, audited and frozen at queue time, and this
      # is the orchestration service's own dispatch (MTX-030 command: "service, at the
      # Queued -> Running commit"). What IS re-resolved is every *domain* precondition above,
      # which is what "a queue-time result is never trusted at execution time" requires.
      #
      # Scope boundaries, recorded rather than silently assumed:
      #   * ROOT ONLY. The reassessment-child limb ("names its already-running parent Evaluation
      #     and reservation") is WF-011's and is deferred (DECISIONS ADR-067/071); QueueCrawl
      #     creates no child Crawl, so a non-root target here is a transport-integrity deviation
      #     and quarantines rather than being guessed at.
      #   * NO FRONTIER. SEARCH_CRAWL_RETRIEVAL step 6 ("creates ordered root frontier entries")
      #     and the post-commit dispatch of the first fetch belong to S-07-004; this tranche
      #     commits the start and nothing outbound. No network call exists on this path.
      #   * NO WF-015 ENTITLEMENT EVENTS. `EntitlementReserved` / `EntitlementExecutionStarted` /
      #     `EntitlementLeaseRenewed` are WF-015 events on the `entitlement_reservation` aggregate
      #     (API_CONTRACTS.md :907-910), owned by S-22 — not among the seventeen events MTX-030
      #     makes `Workflows::Wf005` "the sole producer of". The durable Decision/reservation rows
      #     are written by F-05 and the entitlement outcome is carried in this command's WF-005
      #     audit record, which is exactly what MTX-030 audit_record requires.
      class StartCrawl
        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "crawl"
        ACTION = "crawl.start"
        POLICY_VERSION = "permission-baseline-v1"
        WORKFLOW_ID = "WF-005"
        # The root high-cost operation this start meters (WORKFLOW_SPECIFICATIONS.md :521).
        ENTITLEMENT_OPERATION = "crawl.start"
        ENTITLEMENT_UNITS = 1
        EVALUATION_KIND = "initial"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)
          return in_memory_failure(command, ctx, "scheduled_action_target_mismatch") unless command.target_type == TARGET_TYPE

          key_digest = Digest::SHA256.digest(command.action_identity_sha256)

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            store = IdentityAccess::Infrastructure::CrawlStartStore.new(pg)
            org = command.organization_id

            store.enter_org_context(org:, correlation_id: ctx.correlation_id)
            # An action naming an Organization that does not exist is a transport-integrity
            # deviation, not a domain outcome: fail closed BEFORE any ledger row is written, so a
            # forged/ghost organization_id cannot mint audit, execution or result records under it.
            organization = store.organization(org)
            next in_memory_failure(command, ctx, "scheduled_action_target_mismatch") if organization.nil?

            frontier_store = IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg)
            process(store:, entitlement: Platform::Entitlement::Service.new(pg), organization:,
                    frontier_store:,
                    frontier: Wf005::Frontier.new(frontier_store, ids: ctx.ids, correlation_id: ctx.correlation_id),
                    command:, ctx:, org:, now:, key_digest:)
          end
        end

        private

        def process(store:, entitlement:, organization:, frontier_store:, frontier:, command:, ctx:, org:, now:, key_digest:)
          request_sha256 = request_hash(command, ctx)
          d = { store:, entitlement:, frontier_store:, frontier:, command:, ctx:, org:, now:, key_digest:, request_sha256: }

          # First read resolves the Project for the lock; then lock and re-read authoritatively. This
          # pre-lock read decides only `mismatch`, which cannot go stale: `f1_crawls_guard` refuses
          # DELETE and freezes `project_id`/`kind`, and the `crawl_dispatch` action commits in the
          # SAME transaction as its Crawl, so a dispatch can never be delivered before its Crawl row
          # is visible. Every outcome-bearing read below is taken again under the lock.
          crawl = store.crawl(org, command.crawl_id)
          return mismatch(d) if crawl.nil? || crawl["kind"] != "root"

          store.lock_project(org, crawl["project_id"])
          crawl = store.crawl(org, command.crawl_id)
          return mismatch(d) if crawl.nil?

          # Idempotency BEFORE the domain preconditions (the QueueCrawl/ActivateProject order): a
          # duplicate delivery of this action must faithfully return its stored result, whether
          # that was the accepted start or the recorded pre-execution failure.
          existing = store.find_idempotency(org:, command_type: command.command_type,
                                            target_type: TARGET_TYPE, target_id: command.crawl_id, key_digest:)
          if existing
            return rebuild(store, existing, command) if existing["request_hex"] == hex(request_sha256)

            # Not replayable, and safe to be so: `request_hash` is a pure function of the action
            # identity that keys the record, so a digest mismatch under the same key cannot arise
            # from this handler. The two transport denials below are likewise non-replayable because
            # `Worker::QUARANTINE_REASONS` makes them terminal — they are never redelivered.
            return deny(**d, crawl:, outward: "idempotency_conflict", internal: "idempotency_conflict", replayable: false)
          end

          if now < command.due_at
            return deny(**d, crawl:, outward: "scheduled_action_not_due", internal: "scheduled_action_not_due",
                        replayable: false)
          end

          # A dispatch arriving after the Crawl already left `queued` (a completed start, a
          # cancellation, an earlier terminal) is the canonical harmless terminal execution.
          unless crawl["state"] == "queued"
            return deny(**d, crawl:, outward: "crawl_not_queued", internal: "crawl_not_queued")
          end

          gate(d, crawl, organization)
        end

        # The pre-execution gate in first-match order. Each failure transitions the queued Crawl to
        # `failed` and reserves nothing. Authority for that disposition is MTX-030 `terminal_failure`
        # ("a nonrecoverable policy or integrity error ... before useful output") and CAP-007, EXCEPT
        # for the entitlement limb, which is :734's "current-policy or Entitlement Block before
        # start". :736 closes the transition set to Running / Failed / Canceled, and `Canceled`
        # requires a `CancelCrawl` command holding `crawl.cancel`, so it is unavailable to a service
        # dispatch; leaving the Crawl `queued` would strand it (its one `crawl_dispatch` action is
        # consumed). `crawl.recover` then creates a NEW linked attempt (:735), which is the correct
        # customer affordance for every reason below.
        #
        # Organization first: WORKFLOW_SPECIFICATIONS.md :541 fixes `organization_inactive` as the
        # highest-precedence entitlement short circuit, and SEARCH_CRAWL_RETRIEVAL.md § Crawl
        # Admission And Snapshot step 1 names the Organization first in "reauthorizes current
        # Organization/Project/Source state". Without it a suspended tenant — every Session revoked —
        # would still start protected work and burn a metered `crawl.start` unit on queue-time
        # authority, which MTX-030 `authorization_entry_point` forbids in terms ("an authorization
        # ... established at queue time is never trusted at execution time").
        def gate(d, crawl, organization)
          store = d[:store]
          org = d[:org]
          pid = crawl["project_id"]

          return fail_crawl(d, crawl, "crawl_organization_not_active") unless organization["status"] == "active"

          project = store.project(org, pid)
          return fail_crawl(d, crawl, "crawl_project_not_active") unless project && project["state"] == "active"
          # The precondition is evaluated over the PINNED set intersected with what is still active,
          # not over the Project's Sources at large. Only pinned Sources can be crawled — the set is
          # T-IMM — so a run whose every pinned Source has been disabled or removed can produce
          # nothing, and admitting it would strand a running Crawl with an empty frontier. This is
          # the same intersection S-07-004 seeds the frontier from (owner HD-S07-FU4-FU5).
          return fail_crawl(d, crawl, "crawl_no_active_source") if d[:frontier_store].active_pinned_sources(org, crawl["id"]).empty?
          if store.initial_evaluation_elsewhere?(org, pid, crawl["id"])
            return fail_crawl(d, crawl, "initial_evaluation_already_running")
          end
          # MTX-030 idempotency/error_contract: the pending Evaluation is keyed by
          # `(crawl_id, kind=initial)` and a concurrent ALTERED creation is
          # `evaluation_creation_conflict` — a REQUEST REJECTION, so it changes no state and is
          # checked here, before anything is reserved or transitioned. Unreachable through the
          # per-Project lock plus the `crawl_not_queued` guard (this handler creates the Evaluation
          # in the same commit that leaves `queued`), and doubly backstopped by
          # `evaluations_initial_per_crawl_unique`; checked explicitly so the contract's reason is
          # returned cleanly rather than the transaction aborting on a raw unique violation.
          if store.initial_evaluation_for_crawl?(org, pid, crawl["id"])
            return deny(**d, crawl:, outward: "evaluation_creation_conflict",
                        internal: "evaluation_creation_conflict")
          end

          policy = resolve_crawl_policy(store, org, pid)
          return fail_crawl(d, crawl, "crawl_policy_unavailable") if policy.nil?

          decision = reserve(d, crawl)
          if decision.blocked?
            return fail_crawl(d, crawl, decision.reason_code, decision_id: decision.decision_id)
          end

          accept(d, crawl, policy, decision)
        end

        # The CURRENT effective bounds: the most restrictive of the frozen global ceiling and every
        # active Organization/Project crawl policy. Returns { version:, versions:, bounds: }, or nil
        # when a stored policy is malformed — the ":734 current-policy Block". That is defence in
        # depth, not a live path: the sole writer (ActivateCrawlPolicy) already refuses an
        # incomplete or soft-above-hard candidate (`crawl_policy_incomplete` /
        # `crawl_policy_soft_exceeds_hard`), so nothing here is ever guessed at.
        #
        # `version` labels the run with the MOST SPECIFIC active policy (Project else Organization
        # else the frozen ceiling) — `crawl_policies_active_unique` admits at most one active row per
        # scope, so `rows` is at most [organization, project] and `last` is deterministic. The
        # effective bounds can nevertheless be a per-dimension MIX of both, which no single version
        # names, so `versions` carries every contributing version and the caller records the resolved
        # bounds themselves in the audit record (WF-005 Audit: "all policy versions and effective
        # limits").
        def resolve_crawl_policy(store, org, project_id)
          rows = store.active_crawl_policies(org, project_id)
          sets = rows.map { |r| JSON.parse(r["normalized_bounds"]) }
          return nil unless sets.all? { |s| Wf005::CrawlPolicy.complete?(s) }

          bounds = Wf005::CrawlPolicy.most_restrictive(Wf005::CrawlPolicy::GLOBAL_CEILING, *sets)
          # `complete?` is guaranteed by construction from complete inputs; soft <= hard is not
          # (a stored set may carry soft > hard on a dimension), so it is the load-bearing check.
          return nil unless Wf005::CrawlPolicy.soft_le_hard?(bounds)

          versions = [Wf005::CrawlPolicy::GLOBAL_VERSION] + rows.map { |r| r["policy_version"] }
          { version: versions.last, versions:, bounds: }
        end

        # The atomic root `crawl.start` Decision + reservation (F-05, entitlement-interim-v1).
        def reserve(d, crawl)
          ids = { decision: d[:ctx].generate_id, reservation: d[:ctx].generate_id, window: d[:ctx].generate_id }
          d[:entitlement].reserve(
            operation: ENTITLEMENT_OPERATION, organization_id: d[:org],
            subject: { account_id: crawl["triggered_by_account_id"],
                       service_identity_id: crawl["triggered_by_account_id"] ? nil : d[:ctx].service_identity_id },
            requested_units: ENTITLEMENT_UNITS, correlation_id: d[:ctx].correlation_id, now: d[:now],
            ids:, idempotency_key_digest: d[:key_digest]
          )
        end

        # ---- accepted start ------------------------------------------------------

        def accept(d, crawl, policy, decision)
          store = d[:store]
          ctx = d[:ctx]
          org = d[:org]
          now = d[:now]
          command = d[:command]
          pid = crawl["project_id"]
          ids = %i[execution audit crawl_event evaluation_event result idem evaluation context].to_h { |k| [k, ctx.generate_id] }
          new_version = crawl["state_version"].to_i + 1
          deadline = now + (policy[:bounds]["wall_clock_minutes"]["hard"] * 60)

          write_execution(store, command, ctx, org, ids[:execution], d[:request_sha256], d[:key_digest], now)

          # reserved -> executing: the start commit IS the reservation's first side effect, so the
          # executing lease (and with it the maximum-execution ceiling) begins here.
          started = d[:entitlement].start_execution(organization_id: org, reservation_id: decision.reservation_id, now:)
          raise LostRace unless started == :executing
          raise LostRace if store.start(crawl["id"], crawl["state_version"].to_i, now, deadline,
                                        decision.decision_id, decision.reservation_id).to_i.zero?

          store.insert_evaluation(id: ids[:evaluation], now:, correlation_id: ctx.correlation_id,
                                  organization_id: org, project_id: pid, crawl_id: crawl["id"])
          store.insert_orchestration_context(
            id: ids[:context], now:, correlation_id: ctx.correlation_id, organization_id: org, project_id: pid,
            evaluation_id: ids[:evaluation], crawl_id: crawl["id"], crawl_policy_version: policy[:version],
            # The version the Decision itself resolved and stamped — never a second read, so the
            # Decision row, this context and the event can never name different resolutions.
            entitlement_policy_version: decision.policy_version,
            root_entitlement_decision_id: decision.decision_id,
            root_entitlement_reservation_id: decision.reservation_id,
            publication_preconditions: {}
          )

          # S-07-004, the last limb of the accepted-start commit (SEARCH_CRAWL_RETRIEVAL.md § Crawl
          # Admission And Snapshot step 6): the ordered ROOT frontier, seeded ONLY from pinned
          # Sources that are still active. The gate above guarantees at least one.
          seeded = d[:frontier].seed_roots(organization_id: org, project_id: pid, crawl_id: crawl["id"], now:)
          raise LostRace if seeded.admitted.zero?

          payload = {
            "crawl_id" => crawl["id"], "organization_id" => org, "project_id" => pid, "state" => "running",
            "evaluation_id" => ids[:evaluation], "evaluation_kind" => EVALUATION_KIND, "evaluation_state" => "pending",
            "crawl_policy_version" => policy[:version], "started_at_utc" => now.iso8601(6),
            "deadline_at_utc" => deadline.iso8601(6), "entitlement_decision_id" => decision.decision_id,
            "entitlement_reservation_id" => decision.reservation_id,
            "entitlement_decision" => decision.decision,
            "frontier_root_count" => seeded.admitted,
            "pinned_source_count" => seeded.pinned_total,
            "excluded_inactive_source_count" => seeded.excluded_inactive
          }
          # WF-005 Audit and Observability requires "all policy versions AND effective limits". The
          # resolved bounds are a per-dimension minimum that no single policy version labels, so the
          # audit record carries the contributing versions and the effective limits themselves.
          write_audit(store, ids[:audit], org, ctx, command, crawl["id"], to_state: "running", outcome: "success",
                      reason_code: decision.warning? ? decision.reason_code : nil, now:,
                      payload: payload.merge("entitlement_policy_version" => decision.policy_version,
                                             "contributing_crawl_policy_versions" => policy[:versions],
                                             "effective_crawl_policy_bounds" => policy[:bounds]))
          write_event(store, ids[:crawl_event], ids[:audit], org, ctx, command, now, new_version, pid,
                      d[:request_sha256], d[:key_digest], "CrawlStarted", "state_transition", TARGET_TYPE, crawl["id"],
                      { "from_state" => "queued", "to_state" => "running", "crawl_id" => crawl["id"],
                        "crawl_policy_version" => policy[:version],
                        "entitlement_policy_version" => decision.policy_version,
                        "deadline_at_utc" => deadline.iso8601(6),
                        # Per-Source root counts, which CAP-007 observability requires and which make
                        # a queue-time/execution-time Source-set divergence visible in the stream.
                        "frontier_root_count" => seeded.admitted,
                        "excluded_inactive_source_count" => seeded.excluded_inactive })
          write_event(store, ids[:evaluation_event], ids[:audit], org, ctx, command, now, 0, pid,
                      d[:request_sha256], d[:key_digest], "EvaluationPending", "created", "evaluation", ids[:evaluation],
                      { "evaluation_id" => ids[:evaluation], "crawl_id" => crawl["id"], "kind" => EVALUATION_KIND,
                        "state" => "pending" })
          write_result(store, ids, command, ctx, org, now, payload, target_id: crawl["id"])
          write_idempotency(store, ids[:idem], org, command, d[:key_digest], d[:request_sha256],
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        rescue LostRace
          raise Platform::InvariantViolation, "crawl start lost its serialized transition"
        end

        # ---- the pre-execution gate failure --------------------------------------

        # queued -> failed, no side effect. `completion_reason` is the closed CompletionReason enum
        # member `failed` (WORKFLOW_SPECIFICATIONS.md :456); the exact machine reason is retained in
        # the restricted audit record and on the `CrawlFailed` envelope, which is where :734's "its
        # exact reason" and MTX-030 `audit_record` put it. A blocked Entitlement Decision is already
        # durable (F-05 wrote it) and is named in the audit payload — not on the Crawl row, whose
        # entitlement columns are "NULL until start" (POSTGRESQL_SCHEMA.md :338) and this Crawl
        # never started. No reservation exists.
        def fail_crawl(d, crawl, reason, decision_id: nil)
          store = d[:store]
          ctx = d[:ctx]
          org = d[:org]
          now = d[:now]
          command = d[:command]
          ids = %i[execution audit event result idem].to_h { |k| [k, ctx.generate_id] }
          new_version = crawl["state_version"].to_i + 1

          write_execution(store, command, ctx, org, ids[:execution], d[:request_sha256], d[:key_digest], now)
          raise LostRace if store.fail(crawl["id"], crawl["state_version"].to_i, now).to_i.zero?

          payload = { "crawl_id" => crawl["id"], "organization_id" => org, "project_id" => crawl["project_id"],
                      "state" => "failed", "reason_code" => reason,
                      "completion_reason" => IdentityAccess::Infrastructure::CrawlStartStore::COMPLETION_REASON_FAILED,
                      "entitlement_decision_id" => decision_id }
          write_audit(store, ids[:audit], org, ctx, command, crawl["id"], to_state: "failed", outcome: "failure",
                      reason_code: reason, payload:, now:)
          write_event(store, ids[:event], ids[:audit], org, ctx, command, now, new_version, crawl["project_id"],
                      d[:request_sha256], d[:key_digest], "CrawlFailed", "state_transition", TARGET_TYPE, crawl["id"],
                      { "from_state" => "queued", "to_state" => "failed", "crawl_id" => crawl["id"],
                        "reason_code" => reason, "outcome" => "failure" })
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          write_result(store, ids, command, ctx, org, now, {}, failure:)
          write_idempotency(store, ids[:idem], org, command, d[:key_digest], d[:request_sha256],
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.failure(result_id: ids[:result], command_type: command.command_type,
                                          failure:, audit_record_id: ids[:audit], correlation_id: ctx.correlation_id)
        rescue LostRace
          raise Platform::InvariantViolation, "crawl start lost its serialized transition"
        end

        # ---- audited no-state outcome --------------------------------------------

        def mismatch(d)
          deny(**d, crawl: nil, outward: "scheduled_action_target_mismatch",
               internal: "scheduled_action_target_mismatch", replayable: false)
        end

        # `**_rest` absorbs the context keys the callers splat in (`entitlement:`) that an audited
        # no-state outcome has no use for, so no parameter is declared and left dead.
        def deny(store:, command:, ctx:, org:, now:, key_digest:, request_sha256:, crawl:,
                 outward:, internal:, replayable: true, **_rest)
          ids = %i[execution audit result idem].to_h { |k| [k, ctx.generate_id] }
          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          write_audit(store, ids[:audit], org, ctx, command, command.crawl_id, to_state: nil, outcome: "failure",
                      reason_code: internal,
                      payload: { "crawl_id" => command.crawl_id, "organization_id" => org,
                                 "project_id" => crawl && crawl["project_id"], "internal_reason" => internal,
                                 "outward_reason" => outward, "scheduled_action_id" => command.action_id }, now:)
          failure = Platform::ErrorCatalog.failure(outward, support_reference: ctx.correlation_id)
          write_result(store, ids, command, ctx, org, now, {}, failure:)
          if replayable
            write_idempotency(store, ids[:idem], org, command, key_digest, request_sha256, ids[:execution],
                              ids[:result], now)
          end
          Platform::CommandResult.failure(result_id: ids[:result], command_type: command.command_type,
                                          failure:, audit_record_id: ids[:audit], correlation_id: ctx.correlation_id)
        end

        def rebuild(store, existing, command)
          stored = store.load_command_result(existing["command_result_id"])
          if stored["outcome"] == "success"
            Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type,
                                            payload: JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym),
                                            audit_record_id: stored["audit_record_id"],
                                            correlation_id: stored["correlation_id"], replayed: true)
          else
            failure = Platform::Failure.new(
              error_class: stored["error_class"], error_code: stored["error_code"],
              reason_code: stored["reason_code"], severity: stored["severity"],
              retryable: stored["retryable"] == "t" || stored["retryable"] == true,
              recovery_action: stored["recovery_action"], support_reference: stored["support_reference"]
            )
            Platform::CommandResult.failure(result_id: stored["id"], command_type: command.command_type,
                                            failure:, audit_record_id: stored["audit_record_id"],
                                            correlation_id: stored["correlation_id"], replayed: true)
          end
        end

        # ---- writers -------------------------------------------------------------

        def write_execution(store, command, ctx, org, id, request_sha256, key_digest, now)
          store.insert_command_execution(
            id:, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, idempotency_key_digest: key_digest,
            command_type: command.command_type, command_schema_version: command.schema_version,
            service_identity_id: ctx.service_identity_id, organization_id: org, target_type: TARGET_TYPE,
            target_id: command.crawl_id, action: ACTION,
            requested_at: iso(command.requested_at_utc), authorization_check_at: iso(now),
            policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            canonical_payload: JSON.generate({ "scheduled_action_id" => command.action_id }), request_sha256:
          )
        end

        def write_audit(store, id, org, ctx, command, entity_id, to_state:, outcome:, reason_code:, payload:, now:)
          store.insert_audit(
            id:, occurred_at: iso(now), partition_month: month(now), organization_id: org,
            service_identity_id: ctx.service_identity_id, correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id, entity_type: TARGET_TYPE,
            entity_id:, to_state:, outcome:, reason_code:, payload: JSON.generate(payload),
            content_sha256: Platform::CanonicalJson.digest(payload)
          )
        end

        # One canonically-encoded WF-005 envelope on the named aggregate. Service-attributed:
        # `actor_id`/`account_id` are null and `service_identity_id` names the executing service.
        def write_event(store, event_id, audit_id, org, ctx, command, now, aggregate_version, project_id,
                        request_sha256, key_digest, type, profile, aggregate_type, aggregate_id, extra)
          envelope = {
            "account_id" => nil, "actor_id" => nil, "affected_entity_id" => aggregate_id,
            "affected_entity_type" => aggregate_type, "aggregate_version" => aggregate_version,
            "audit_record_id" => audit_id, "causation_id" => ctx.correlation_id,
            "command_id" => command.command_id, "correlation_id" => ctx.correlation_id,
            "event_id" => event_id, "event_profile" => profile, "event_type" => type,
            "idempotency_identity_hash" => hex(key_digest), "input_hash" => hex(request_sha256),
            "occurred_at_utc" => now.iso8601(6), "organization_id" => org, "outcome" => "success",
            "project_id" => project_id, "reason_code" => nil, "schema_version" => "1.0",
            "scheduled_action_id" => command.action_id, "service_identity_id" => ctx.service_identity_id,
            "state_version" => aggregate_version, "workflow_id" => WORKFLOW_ID
          }.merge(extra)
          bytes = Platform::CanonicalJson.encode(envelope)
          store.insert_event(
            id: event_id, created_at: iso(now), event_type: type, event_profile: profile,
            occurred_at: iso(now), organization_id: org, aggregate_type:, aggregate_id:,
            aggregate_version:, partition_month: month(now), correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id, audit_record_id: audit_id,
            event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
          )
        end

        def write_result(store, ids, command, ctx, org, now, payload, failure: nil, target_id: nil)
          store.insert_command_result(
            id: ids[:result], created_at: iso(now), correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id,
            command_execution_id: ids[:execution], outcome: failure ? "failure" : "success",
            organization_id: org, service_identity_id: ctx.service_identity_id, completed_at: iso(now),
            authorization_check_at: iso(now),
            target_refs: JSON.generate(failure ? {} : { TARGET_TYPE => target_id }),
            governing_policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            failure:, authorized_payload: JSON.generate(payload), audit_record_id: ids[:audit]
          )
        end

        def write_idempotency(store, id, org, command, key_digest, request_sha256, execution_id, result_id, now)
          store.insert_idempotency(
            id:, created_at: iso(now), organization_id: org, command_type: command.command_type,
            target_type: TARGET_TYPE, target_id: command.crawl_id, key_digest:, request_sha256:,
            command_execution_id: execution_id, command_result_id: result_id,
            retain_until: iso(now + (30 * 24 * 3600))
          )
        end

        def schema_failure(command, ctx) = in_memory_failure(command, ctx, "command_schema_unsupported")

        def in_memory_failure(command, ctx, reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                          failure:, audit_record_id: ctx.generate_id, correlation_id: ctx.correlation_id)
        end

        def request_hash(command, ctx)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "service_identity_id" => ctx.service_identity_id,
            "organization_id" => command.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => command.crawl_id, "project_id" => nil,
            "policy_versions" => [POLICY_VERSION],
            "command_payload" => { "scheduled_action_identity_sha256" => hex(command.action_identity_sha256),
                                   "due_at" => command.due_at.getutc.iso8601(6) }
          })
        end

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
        def iso(time) = time&.getutc&.iso8601(6)
        def month(time) = Date.new(time.year, time.month, 1).iso8601
        def hex(bytes) = bytes.unpack1("H*")

        class LostRace < StandardError; end
      end
    end
  end
end
