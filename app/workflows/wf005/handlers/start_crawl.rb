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
        # The canonical harmless terminal execution: a dispatch whose Crawl has already left `queued`.
        # The SAME token this handler uses when it observes the transition before it acts, because it is
        # the same fact — see `classify_lost_transition`.
        CONCURRENT_TRANSITION_REASON = "crawl_not_queued"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)
          return in_memory_failure(command, ctx, "scheduled_action_target_mismatch") unless command.target_type == TARGET_TYPE

          key_digest = Digest::SHA256.digest(command.action_identity_sha256)

          begin
            attempt(command, ctx, key_digest)
          rescue ConcurrentTransition => e
            # The Crawl left `queued` underneath this transaction. The whole attempt has rolled back;
            # the denial is written against what the winner committed.
            refuse_after_rollback(command, ctx, key_digest, e.message)
          end
        end

        private

        def attempt(command, ctx, key_digest)
          # THE HANDLER TRANSLATES TOO (round 9, R9-1). Round 9 wrapped the PASS and then classified
          # the two command handlers as exceptions "because the closure cannot fire under their row
          # lock". The reasoning was correct and the mechanism was still a hand-written list of two,
          # and the review found a THIRD producer under this very handler that the list did not
          # contain. A list of exceptions is a list. There are now no exceptions: every WF-005 unit
          # of work translates, so a producer nobody enumerated is covered by WHERE IT RUNS rather
          # than by whether someone remembered it.
          Wf005::ClosedFactSet.translate do
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
                      frontier_store:, pg:,
                      frontier: Wf005::Frontier.new(frontier_store, ids: ctx.ids, correlation_id: ctx.correlation_id),
                      command:, ctx:, org:, now:, key_digest:)
            end
          end
        end

        def process(store:, entitlement:, organization:, frontier_store:, frontier:, pg:, command:, ctx:, org:, now:, key_digest:)
          request_sha256 = request_hash(command, ctx)
          d = { store:, entitlement:, frontier_store:, frontier:, pg:, command:, ctx:, org:, now:, key_digest:, request_sha256: }

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

          # THE FRONTIER LOCK IS TAKEN BEFORE ANYTHING LOCKS THE `crawls` ROW (round 4, R4-2; FU-38).
          #
          # THIS HANDLER WAS THE SUBSYSTEM'S ONLY LOCK-ORDER INVERSION, and R3-6 turned it from latent
          # into reachable. Every other path takes `crawl-frontier:<crawl>` and THEN the `crawls` row:
          # `Admission#claim`, `CrawlDriver#retire`, `CrawlFetchDueSchedule.link_next`,
          # `Handlers::CompleteCrawl` and — since R3-6 — `Handlers::CancelCrawl`. This one took the ROW
          # first, because `store.start` is a bare UPDATE that holds an exclusive row lock to commit,
          # and only reached the frontier lock later, inside `seed_roots`.
          #
          # ADR-116 O1 recorded the inversion and FU-38 tolerated it on ONE ground: "no reachable
          # interleaving exists — a `crawl_terminal_deadline` action cannot exist until that StartCrawl
          # transaction commits". That reasoning covers `CompleteCrawl` and NOTHING ELSE. `CancelCrawl`
          # is a CUSTOMER COMMAND that depends on no prior commit, and :736 makes a `queued` Crawl
          # cancellable — so after R3-6 the cycle was ordinary rather than exotic:
          #
          #   StartCrawl  holds crawls row (store.start), waits for crawl-frontier (seed_roots)
          #   CancelCrawl holds crawl-frontier (lock_frontier), waits for crawls row (lock_crawl)
          #
          # PostgreSQL resolves that by aborting one side with SQLSTATE 40P01, and `Handlers::CancelCrawl`
          # has no rescue of any kind, so `PG::TRDeadlockDetected` would leave a customer command as a
          # raw exception instead of the `Platform::CommandResult` ADR-103 exists to guarantee — and
          # WHICH side died would be chosen by the deadlock detector, so timing would once again decide
          # whether an ordinary race is a domain refusal or a crash.
          #
          # THE FIX IS HERE RATHER THAN IN `CancelCrawl` because the order the rest of the subsystem
          # already uses is frontier-then-crawls, and ADR-105 chose it deliberately: reversing
          # `CancelCrawl` would invert it against `Admission`, `retire` and `CompleteCrawl` instead —
          # three inversions in place of one. `pg_advisory_xact_lock` is re-entrant within a
          # transaction, so `seed_roots`' own call below is now a no-op re-acquire and its guarantee is
          # unchanged.
          # PLACED IMMEDIATELY BEFORE `store.start`, WHICH IS THE FIRST STATEMENT IN THIS HANDLER THAT
          # LOCKS THE `crawls` ROW AT ALL. `command_executions` and `entitlement_reservations` carry no
          # foreign key to `crawls` (checked against `pg_constraint`), so nothing above holds even a
          # `FOR KEY SHARE` on it — which is also why PROOF 88, gated at the `command_executions`
          # INSERT, still runs its cancellation to completion underneath a start that holds NEITHER
          # object. Taking this lock any earlier would block that cancellation on the frontier and
          # break the window PROOF 88 exists to prove.
          d[:frontier_store].lock_frontier(crawl["id"])

          if store.start(crawl["id"], crawl["state_version"].to_i, now, deadline,
                         decision.decision_id, decision.reservation_id).to_i.zero?
            classify_lost_transition(store, org, crawl)
          end

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
          # The observer carries the run's RESOLVED bounds, so a root refused for the discovered-queue
          # ceiling records the same decision an offered candidate would.
          seeded = d[:frontier].seed_roots(
            organization_id: org, project_id: pid, crawl_id: crawl["id"], now:,
            observer: Wf005::LimitDecisions.new(ids: ctx.ids, correlation_id: ctx.correlation_id)
                                           .for(d[:pg], organization_id: org, project_id: pid,
                                                crawl_id: crawl["id"],
                                                limits: Wf005::EffectiveLimits.resolve(
                                                  store.active_crawl_policies(org, pid)))
          )
          raise LostRace if seeded.admitted.zero?

          # THE FIRST HANDOFF (S-07-012; DECISIONS ADR-085, owner ruling on FU-16). :138 makes
          # `crawl_fetch_due` carry "one selected persisted fetch attempt, INCLUDING AN IMMEDIATE FIRST
          # ATTEMPT", and until now that first link did not exist: the accepted start seeded the
          # frontier and scheduled nothing, so no run ever advanced.
          #
          # It is SELECTION ONLY. The action names the frontier entry `peek_next` selects under the
          # frontier's own advisory lock, and nothing else happens here: no attempt row, no byte
          # reservation, no `queued -> in_progress` claim. ADMISSION HAPPENS AT EXECUTION, which is what
          # keeps this commit's accepted shape intact — the root entry is still `queued` and this path
          # is still outbound-silent — and what keeps the fetch path the sole producer of
          # `fetch_attempts`. The alternative was built and withdrawn: pre-admitting here holds a
          # reservation and an `in_progress` entry across the whole scheduling latency, makes StartCrawl
          # a second producer, and (because `FetchContent`'s own loop would then start at attempt #2)
          # silently costs :444 one of its two proven retries.
          #
          # In the SAME transaction as the `queued -> running` transition, deliberately: :378 has each
          # link created by the terminal transaction of the step before it, so a rolled-back start
          # leaves no link to claim and an accepted start cannot commit without one.
          handoff = Wf005::CrawlFetchDueSchedule.link_next(
            pg: d[:pg], organization_id: org, project_id: pid, crawl_id: crawl["id"], now:,
            correlation_id: ctx.correlation_id, command_id: command.command_id
          )
          # FAIL CLOSED IF THE SELECTION COMES BACK EMPTY, because a start that committed without its
          # first link would leave a `running` Crawl that nothing can advance — the exact condition this
          # tranche exists to remove.
          #
          # Not merely defensive: the window is a READ COMMITTED visibility race INSIDE this
          # transaction. `active_pinned_sources` was read at the gate, and `peek_next` re-reads
          # `sources.state = 'active'` for itself, so a `DisableSource` that commits between the two is
          # invisible to the first and visible to the second. NO FIXTURE REACHES IT — reproducing it
          # needs a second connection committing between two statements of one transaction — so this is
          # recorded as an uncovered guard rather than claimed as tested coverage. What IS proven is that
          # the empty selection is producible: `CrawlFetchDueSchedule.link_next` returns `{}` on a
          # frontier with nothing selectable, asserted in the run-driver spec's drained-frontier example.
          raise LostRace if handoff[:entry_id].nil?

          # THE RUN'S TERMINAL CHECKPOINT, on this same transaction (FU-22, S-07-009). Nothing created
          # this action until now, so a run whose frontier stopped advancing stayed `running` for ever:
          # the chain only links forward FROM a pass, and a run with no pass to make creates no link.
          # BACKGROUND_PROCESSING.md :139 makes `crawl_terminal_deadline` the "exact 60-minute terminal
          # checkpoint" and :199 keys it to the "Crawl/deadline identity", so it is created once, here,
          # against the deadline this commit has just resolved — never a second derivation of it.
          terminal = Wf005::CrawlTerminalDeadlineSchedule.schedule(
            pg: d[:pg], organization_id: org, project_id: pid, crawl_id: crawl["id"],
            due_at: deadline, now:, correlation_id: ctx.correlation_id, command_id: command.command_id
          )

          payload = {
            "crawl_id" => crawl["id"], "organization_id" => org, "project_id" => pid, "state" => "running",
            "evaluation_id" => ids[:evaluation], "evaluation_kind" => EVALUATION_KIND, "evaluation_state" => "pending",
            "crawl_policy_version" => policy[:version], "started_at_utc" => now.iso8601(6),
            "deadline_at_utc" => deadline.iso8601(6), "entitlement_decision_id" => decision.decision_id,
            "entitlement_reservation_id" => decision.reservation_id,
            "entitlement_decision" => decision.decision,
            "frontier_root_count" => seeded.admitted,
            "pinned_source_count" => seeded.pinned_total,
            "excluded_inactive_source_count" => seeded.excluded_inactive,
            "first_fetch_frontier_entry_id" => handoff[:entry_id],
            "first_fetch_action_id" => handoff[:action_id],
            "first_fetch_due_at_utc" => handoff[:due_at]&.getutc&.iso8601(6),
            # The checkpoint that bounds this run, reported so a reader can see that the Crawl and the
            # thing that will terminalize it committed together rather than having to infer it.
            "terminal_checkpoint_action_id" => terminal
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
                      # THE CLOSED `state_transition` PROFILE PLUS `crawl_terminal`, EXACTLY (FU-33/FU-67,
                      # ADR-146). Six of the eight members this envelope used to carry are admitted by
                      # neither: `crawl_id` duplicates the root `affected_entity_id`, and the two policy
                      # versions, `deadline_at_utc` and the two per-Source root counts are not members of
                      # any closed schema. :933 admits no extension object to put them in.
                      #
                      # THE TWO CAP-007 COUNTS ARE RE-HOMED, NOT DELETED, and the owner's decision says
                      # so. They were added deliberately, because CAP-007 observability requires them and
                      # because they "make a queue-time/execution-time Source-set divergence visible".
                      # They remain in the AUDIT RECORD this same commit writes, alongside
                      # `pinned_source_count`, and in the command result — and the audit record is where
                      # WF-005's Audit and Observability obligation actually places "per-Source root
                      # status". Nothing that could be read before can stop being read.
                      #
                      # `prior_aggregate_version` IS `new_version - 1` AND NOT A SECOND DERIVATION. :938
                      # requires "committed version equals root aggregate version and prior is lower";
                      # `new_version` is the version this transition committed, which the root envelope
                      # already carries, so the pair is that value and its predecessor.
                      { "from_state" => "queued", "to_state" => "running",
                        "prior_aggregate_version" => new_version - 1,
                        "committed_aggregate_version" => new_version,
                        # :807 gives `CrawlStarted` the reason source `none`, and :938 says the member is
                        # null where the source is `none` — null, which is a value, not an omission.
                        "transition_reason_code" => nil,
                        "coverage_status" => nil, "completion_reason" => nil,
                        "accepted_document_count" => 0 })
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
          classify_lost_transition(store, org, crawl) if store.fail(crawl["id"], crawl["state_version"].to_i, now).to_i.zero?

          payload = { "crawl_id" => crawl["id"], "organization_id" => org, "project_id" => crawl["project_id"],
                      "state" => "failed", "reason_code" => reason,
                      "completion_reason" => IdentityAccess::Infrastructure::CrawlStartStore::COMPLETION_REASON_FAILED,
                      "entitlement_decision_id" => decision_id }
          write_audit(store, ids[:audit], org, ctx, command, crawl["id"], to_state: "failed", outcome: "failure",
                      reason_code: reason, payload:, now:)
          write_event(store, ids[:event], ids[:audit], org, ctx, command, now, new_version, crawl["project_id"],
                      d[:request_sha256], d[:key_digest], "CrawlFailed", "state_transition", TARGET_TYPE, crawl["id"],
                      # WF-005's SECOND PRODUCER OF `CrawlFailed`, BROUGHT TO THE SAME SHAPE AS THE FIRST
                      # (FU-33/FU-67, ADR-146). `CompleteCrawl` emits this event type too, and until now
                      # the two producers disagreed about its members — the defect class ADR-110 was
                      # written about, one event type along. This envelope carried neither the
                      # `crawl_terminal` members nor `transition_reason_code`, and carried `crawl_id`,
                      # which duplicates the root `affected_entity_id`.
                      #
                      # `reason_code` AND `outcome` ARE ROOT MEMBERS, NOT PAYLOAD, so they stay: :703
                      # lists both on the event root, and `CrawlLedger#write_event` defaults `outcome` to
                      # `success`, which a pre-execution failure must override. :808 gives `CrawlFailed`
                      # the reason source `transition`, so :938 requires root `reason_code` to equal
                      # `transition_reason_code` exactly — they are set from the one value.
                      { "from_state" => "queued", "to_state" => "failed",
                        "prior_aggregate_version" => new_version - 1,
                        "committed_aggregate_version" => new_version,
                        "transition_reason_code" => reason,
                        # The run never started, so no coverage was measured and nothing was accepted.
                        "coverage_status" => nil,
                        "completion_reason" =>
                          IdentityAccess::Infrastructure::CrawlStartStore::COMPLETION_REASON_FAILED,
                        "accepted_document_count" => 0,
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

        # WHY A LOST COMPARE-AND-SET IS NOT AUTOMATICALLY AN INVARIANT FAILURE (DECISIONS ADR-103).
        #
        # `store.start` and `store.fail` are guarded on `state = 'queued' AND state_version = $2`, and
        # this handler serializes on the per-Project ADVISORY lock while `CancelCrawl` serializes on the
        # Crawl ROW lock — two different objects, so a cancellation can commit in the window between the
        # authoritative read above and the compare-and-set below. Before this, the SAME cancellation
        # produced `crawl_not_queued` when it landed a moment earlier and a `Platform::InvariantViolation`
        # when it landed a moment later. Timing decided whether an ordinary race was a domain refusal or
        # an invariant failure, and that is the defect.
        #
        # THE CLASSIFICATION IS A RE-READ, NOT A BLANKET RESCUE. Rescuing every lost CAS as
        # `crawl_not_queued` would swallow the other way it can fail: a writer that bumps `state_version`
        # while LEAVING the state `queued` (the guard permits non-state updates on a non-terminal row).
        # Nothing in production does that, which is exactly why it must still escalate — a lost race
        # nobody can name is not the same fact as a cancellation, and only one of them is ordinary.
        #
        # The re-read is authoritative. The CAS blocked on the row lock until the other transaction
        # committed and then matched zero rows, so a fresh SELECT at READ COMMITTED sees that committed
        # state rather than this transaction's older snapshot.
        def classify_lost_transition(store, org, crawl)
          current = store.crawl(org, crawl["id"])
          # `f1_crawls_guard` refuses DELETE, so a row that was here a moment ago and is gone now is
          # corruption rather than a race.
          raise LostRace if current.nil?
          # Still `queued`: the state did not move, so something else moved the version. Unattributable,
          # and escalated rather than reported as a cancellation that did not happen.
          raise LostRace if current["state"] == "queued"

          # The Crawl left `queued` underneath this transaction. That is the canonical harmless terminal
          # execution — the same fact, and the same reason code, this handler reports when it observes
          # the transition a moment earlier.
          raise ConcurrentTransition, current["state"]
        end

        # THE REFUSAL IS WRITTEN IN A SECOND TRANSACTION, AND THAT IS THE POINT OF RAISING AT ALL.
        #
        # By the time the compare-and-set fails, this transaction has already written a command
        # execution and moved the entitlement reservation `reserved -> executing`. Reporting the denial
        # inline would commit BOTH of those beside it: an execution record for a start that did not
        # happen, and a reservation left `executing` for a run that never ran, which nothing would ever
        # commit or release. Raising out of `Platform::UnitOfWork.run` rolls the whole attempt back —
        # the reservation, the Decision, the execution row — and the denial is then written cleanly
        # against the state the winner left. The frontier seeding never ran; it comes after the CAS.
        def refuse_after_rollback(command, ctx, key_digest, observed_state)
          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            store = IdentityAccess::Infrastructure::CrawlStartStore.new(pg)
            org = command.organization_id
            store.enter_org_context(org:, correlation_id: ctx.correlation_id)
            crawl = store.crawl(org, command.crawl_id)
            deny(store:, command:, ctx:, org:, now:, key_digest:,
                 request_sha256: request_hash(command, ctx), crawl:,
                 outward: CONCURRENT_TRANSITION_REASON, internal: CONCURRENT_TRANSITION_REASON,
                 observed_state:)
          end
        end

        # ---- audited no-state outcome --------------------------------------------

        def mismatch(d)
          deny(**d, crawl: nil, outward: "scheduled_action_target_mismatch",
               internal: "scheduled_action_target_mismatch", replayable: false)
        end

        # `**_rest` absorbs the context keys the callers splat in (`entitlement:`) that an audited
        # no-state outcome has no use for, so no parameter is declared and left dead.
        # `observed_state` is set only on the concurrent-transition path, where the audit record should
        # say WHAT the winner committed rather than only that this delivery lost. Absent everywhere else,
        # so an ordinary denial's payload keeps the shape it has always had.
        def deny(store:, command:, ctx:, org:, now:, key_digest:, request_sha256:, crawl:,
                 outward:, internal:, replayable: true, observed_state: nil, **_rest)
          ids = %i[execution audit result idem].to_h { |k| [k, ctx.generate_id] }
          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          payload = { "crawl_id" => command.crawl_id, "organization_id" => org,
                      "project_id" => crawl && crawl["project_id"], "internal_reason" => internal,
                      "outward_reason" => outward, "scheduled_action_id" => command.action_id }
          payload["observed_state"] = observed_state if observed_state
          write_audit(store, ids[:audit], org, ctx, command, command.crawl_id, to_state: nil, outcome: "failure",
                      reason_code: internal, payload:, now:)
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

        # The Crawl left `queued` underneath this transaction. Carries the state the winner committed,
        # so the audit record can say what actually happened rather than only that something did.
        class ConcurrentTransition < StandardError; end
      end
    end
  end
end
