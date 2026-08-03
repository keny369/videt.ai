# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"

module Workflows
  module Wf005
    module Handlers
      # WF-005 THE TERMINAL CHECKPOINT (S-07-009) — the service execution behind the ratified
      # `crawl_terminal_deadline` ScheduledAction (BACKGROUND_PROCESSING.md :139/:199/:377;
      # WORKFLOW_SPECIFICATIONS.md :450, :452, :453, :458; contracts/S-07.json MTX-030).
      #
      # ":458 — Terminal selection occurs ONCE at a serialized checkpoint." The serialization is a `FOR
      # UPDATE` lock on the Crawl row, taken before anything is read, so a second delivery blocks, then
      # sees the first one's decision and finds the Crawl terminal. Everything the selection needs is
      # then counted in ONE statement under that lock: eight separate reads would let the run change
      # between them and produce a selection no single state of the database ever justified.
      #
      # ONE JOB, TWO OF :377's OPERATIONS. ":377 — `StartCrawl`, `CompleteCrawl`, `FailCrawl`, or
      # `CancelCrawl`, SELECTED SOLELY FROM PERSISTED CRAWL/DEADLINE STATE." This selects between
      # `CompleteCrawl` and `FailCrawl` from `Wf005::TerminalSelection`, which is a pure function over
      # the counted facts; the audit record and the event both say which it made. `CancelCrawl` is not
      # selected here — :458 settles cancellation by ORDER OF COMMIT ("a cancellation committed strictly
      # before that checkpoint yields `Crawl.Canceled`"), so a cancelled Crawl is already terminal when
      # this arrives and this writes nothing.
      #
      # THREE THINGS HAPPEN IN THE ONE TRANSACTION, and the order is the specification's:
      #
      #   1. THE COUNT, in one statement (`CrawlStartStore#terminal_facts`).
      #   2. THE SELECTION AND THE TRANSITION — :458's state, its single completion reason and, for a
      #      completed run, its coverage status.
      #   3. THE RESERVATION, committed or released EXACTLY ONCE (MTX-030 transaction_boundary; :551).
      #      `entitlement-interim-v1` names the durable commit point
      #      `crawl_completed_with_valid_document`, so a completed run commits and a failed one
      #      releases — and `Service#commit` itself releases instead if the lease has expired, which
      #      FU-31 is what keeps from being the only outcome.
      #
      # THE ONE INTERIM BOUNDARY, STATED RATHER THAN HIDDEN. :453's "zero valid Documents" is counted
      # over `crawl_terminal_outcomes.outcome = 'document_created'`, because nothing creates a
      # `documents` row yet — S-07-010 owns them, and the accepted `crawl_terminal_outcomes` migration
      # already ratified `document_created` with `document_id` NULL as the record of a fetch that did
      # everything :436 asks of an accepted page. S-07-010 must confirm it against the artifact; until
      # that artifact exists there is nothing truer to read, and inventing a stricter test would make
      # every run fail for a reason that is about this build rather than about the customer's site.
      class CompleteCrawl
        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "crawl"
        ACTION = "crawl.terminal_checkpoint"
        POLICY_VERSION = "permission-baseline-v1"
        WORKFLOW_ID = "WF-005"

        # `entitlement-interim-v1`'s durable commit point for `crawl.start`, and the durable output it
        # binds to. The Crawl IS the output: MTX-030 names the commit point
        # "crawl_completed_with_valid_document", and the artifact that carries it is this run.
        DURABLE_OUTPUT_TYPE = "crawl"
        COMMIT_REASON = "durable_commit_point_reached"
        RELEASE_REASON = "crawl_terminal_without_durable_output"

        class LostRace < StandardError; end

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
            # An action naming an Organization that does not exist is a transport-integrity deviation,
            # not a domain outcome: fail closed BEFORE any ledger row is written.
            next in_memory_failure(command, ctx, "scheduled_action_target_mismatch") if store.organization(org).nil?

            process(store:, entitlement: Platform::Entitlement::Service.new(pg), pg:, command:, ctx:,
                    org:, now:, key_digest:)
          end
        end

        private

        def process(store:, entitlement:, pg:, command:, ctx:, org:, now:, key_digest:)
          request_sha256 = request_hash(command, ctx)
          d = { store:, entitlement:, pg:, command:, ctx:, org:, now:, key_digest:, request_sha256: }

          # THE SERIALIZATION, IN TWO PARTS AND IN THIS ORDER (DECISIONS ADR-105).
          #
          # 1. THE FRONTIER ADVISORY LOCK, which fences an in-flight RETIREMENT. `CrawlDriver#retire`
          #    holds `crawl-frontier:<crawl>` for its whole transaction — the frontier terminalize AND
          #    the `crawl_terminal_outcomes` INSERT — so taking it here means no pass can be part-way
          #    through retiring an entry while this counts. Without it the checkpoint counted a snapshot
          #    the pass invalidated a moment later, and a run that fetched a valid Document was recorded
          #    `failed` with its reservation RELEASED while `crawl_terminal_outcomes` said
          #    `document_created / covered`. Reproduced at natural timing, 10/10, and IRREVERSIBLE:
          #    `f1_crawls_guard` refuses every UPDATE of a terminal row, so nothing can correct it.
          #
          # 2. THE CRAWL ROW LOCK, which is :458's "once" — a concurrent checkpoint or cancellation
          #    blocks here and then finds the Crawl terminal rather than deriving a second opinion.
          #
          # THE ORDER IS THE SUBSYSTEM'S, NOT A CHOICE MADE HERE. `Admission#claim` takes the frontier
          # advisory lock and then writes `crawl_budget_counters`, whose FK to `crawls` takes `FOR KEY
          # SHARE` on that row; `retire` does the same through the outcome row's FK. Frontier THEN crawls
          # is therefore already established, and the checkpoint conforms to it. Taking them the other
          # way round — the obvious fix, and the one the review's own concurrency lens proposed for the
          # driver — would invert the order against `Admission` and is how a deadlock is built.
          IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg).lock_frontier(command.crawl_id)
          crawl = store.lock_crawl(org, command.crawl_id)
          return mismatch(d) if crawl.nil?

          # THE WAIT IS OVER, SO THE DECISION INSTANT IS RE-READ (owner ruling 1, round 6 R6-6;
          # `Wf005::PostWaitDecision` states the rule). Both locks above block for as long as an
          # in-flight retirement or a concurrent delivery holds them.
          #
          # THE ENTITLEMENT SETTLEMENT IS WHY THIS MATTERS MOST. `settle_reservation` hands this value
          # to `Entitlement::Service#commit`, which chooses commit versus release from it alone —
          # `now >= effective_deadline(r)` releases, anything earlier commits. :551 makes expiry win
          # at equality and requires the commit point to be STRICTLY BEFORE expiry, and the commit
          # point is the durable terminal transition this transaction is about to make, not the
          # instant the delivery arrived. On the pre-wait value a reservation whose lease expired
          # while this handler queued was still COMMITTED, so the customer was metered for a run whose
          # entitlement had already lapsed.
          #
          # It is the same value the wall-clock observation, the terminal row and every ledger row
          # below use, so the record says when the checkpoint actually happened.
          post_wait = PostWaitDecision.new(pg, entered_with: now)
          now = post_wait.now
          d = d.merge(now:)

          # Idempotency BEFORE the domain preconditions, as every other WF-005 handler orders it: a
          # duplicate delivery returns its stored result faithfully, whether that was the terminal
          # decision or a recorded refusal.
          existing = store.find_idempotency(org:, command_type: command.command_type,
                                            target_type: TARGET_TYPE, target_id: command.crawl_id, key_digest:)
          if existing
            return rebuild(store, existing, command) if existing["request_hex"] == hex(request_sha256)

            return deny(**d, crawl:, outward: "idempotency_conflict", internal: "idempotency_conflict",
                        replayable: false)
          end
          if now < command.due_at
            return deny(**d, crawl:, outward: "scheduled_action_not_due", internal: "scheduled_action_not_due",
                        replayable: false)
          end

          # THE CANONICAL HARMLESS TERMINAL EXECUTION. A Crawl already `completed`, `failed` or
          # `canceled` has had its one selection — :458's "once" — and this delivery has nothing to
          # decide. A `queued` Crawl never started, so it has no run to terminalize either; its own
          # `crawl_dispatch` owns that outcome.
          unless crawl["state"] == "running"
            reason = post_wait.terminal?(crawl) ? "crawl_already_terminal" : "crawl_not_running"
            return deny(**d, crawl:, outward: reason, internal: reason)
          end

          checkpoint(d, crawl)
        end

        # ---- the checkpoint --------------------------------------------------------

        def checkpoint(d, crawl)
          store = d[:store]
          ctx = d[:ctx]
          org = d[:org]
          now = d[:now]
          command = d[:command]
          pid = crawl["project_id"]
          ids = %i[execution audit event result idem commit_intent].to_h { |k| [k, ctx.generate_id] }
          new_version = crawl["state_version"].to_i + 1

          write_execution(store, command, ctx, org, ids[:execution], d[:request_sha256], d[:key_digest], now)

          wall_clock = observe_wall_clock(d, crawl)
          facts = count_facts(store, org, crawl, pid)
          selection = TerminalSelection.derive(facts)

          raise LostRace if store.terminalize(crawl["id"], crawl["state_version"].to_i, now,
                                              state: selection.state,
                                              completion_reason: selection.completion_reason,
                                              coverage_status: selection.coverage_status).to_i.zero?

          metering = settle_reservation(d, crawl, selection, ids)

          payload = {
            "crawl_id" => crawl["id"], "organization_id" => org, "project_id" => pid,
            "state" => selection.state, "completion_reason" => selection.completion_reason,
            "coverage_status" => selection.coverage_status,
            "terminal_at_utc" => now.iso8601(6),
            # THE COUNTS THE SELECTION WAS MADE FROM, not a restatement of the selection. MTX-030's
            # audit requirement is "the complete failed subset with counts and reasons; the derived
            # coverage and completion", so a reader can re-derive the decision rather than trust it.
            "documents" => facts.documents, "source_roots" => facts.roots_total,
            "source_roots_succeeded" => facts.roots_succeeded,
            "source_root_failures" => facts.root_failures,
            "content_fetch_failures" => facts.fetch_failures,
            "uncovered_candidates" => facts.uncovered, "unevaluated_candidates" => facts.unevaluated,
            "unresolved_discovery" => facts.unresolved_discovery,
            # :458's not-evaluated limb for sitemap discovery, reported separately from :450's
            # `sitemap_unavailable` so a reader can tell "we never asked" from "we asked and failed".
            "unattempted_discovery" => facts.unattempted_discovery,
            "hard_limit_decisions" => facts.hard_limit_decisions,
            "terminal_forcing_limit_decisions" => facts.terminal_limit_decisions,
            "sitemap_terminal_limit_facts" => facts.sitemap_limit_facts,
            "entitlement_reservation_id" => crawl["entitlement_reservation_id"],
            "entitlement_outcome" => metering
          }
          write_audit(store, ids[:audit], org, ctx, command, crawl["id"], to_state: selection.state,
                      outcome: "success", reason_code: selection.completion_reason, payload:, now:)
          write_event(store, ids[:event], ids[:audit], org, ctx, command, now, new_version, pid,
                      d[:request_sha256], d[:key_digest], event_type(selection), "state_transition",
                      TARGET_TYPE, crawl["id"],
                      terminal_envelope(selection, crawl, facts))
          write_result(store, ids, command, ctx, org, now, payload, target_id: crawl["id"])
          write_idempotency(store, ids[:idem], org, command, d[:key_digest], d[:request_sha256],
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        rescue LostRace
          raise Platform::InvariantViolation, "crawl terminal checkpoint lost its serialized transition"
        end

        # THE `crawl_terminal` EXTRA SCHEMA IS THREE MEMBERS, NOT TWO (ADR-110). API_CONTRACTS.md :956:
        # "`coverage_status` …, `completion_reason` …, AND `accepted_document_count: uint53`; values are
        # null/zero before terminal derivation." The count was computed two lines earlier and discarded.
        #
        # AND THE REASON THE CATALOGUE ASKS FOR. :808 gives `CrawlFailed` and `CrawlCanceled` the reason
        # source `transition`; :938 then requires the `state_transition` base member
        # `transition_reason_code`, and that root `reason_code` "equals it exactly when the catalogue
        # source is `transition`". Both were absent, while WF-005's OWN pre-execution `CrawlFailed` in
        # `Handlers::StartCrawl` set the root reason — two producers of one event type disagreeing, and
        # `CrawlStartStore`'s own comment asserting the machine reason "is retained where the contract
        # puts it — the `CrawlFailed` envelope". `CrawlCompleted` keeps both null: :807 gives it the
        # source `none`, and :938 says a `none` source requires null.
        def terminal_envelope(selection, crawl, facts)
          # `transition_reason_code` IS A BASE MEMBER OF EVERY `state_transition`, INCLUDING THIS ONE
          # (round 4, R4-7). :938 lists it among the base members and says "it is NULL where the
          # catalogue source is `none`" — null, which is a value, not absent. :807 gives `CrawlCompleted`
          # the source `none`, so it carries the member as null; the early return below omitted it
          # entirely and only the two `transition`-sourced siblings had it.
          #
          # THE SAME ABSENT-VERSUS-NULL DISTINCTION R3-3 WAS RAISED ON, in the same envelope builder and
          # one member along. :938's consumer rule REJECTS a missing required member and DEFINES a null
          # one, so the two are different bytes and different outcomes for a consumer.
          base = { "from_state" => "running", "to_state" => selection.state,
                   "crawl_id" => crawl["id"], "completion_reason" => selection.completion_reason,
                   "coverage_status" => selection.coverage_status,
                   "accepted_document_count" => facts.documents,
                   "transition_reason_code" => nil }
          return base if selection.state == TerminalSelection::COMPLETED

          base.merge("reason_code" => selection.completion_reason,
                     "transition_reason_code" => selection.completion_reason)
        end

        # :453's two events. `CrawlCompleted` and `CrawlFailed` are both `crawl_terminal` profile rows in
        # API_CONTRACTS.md :807-808; which one fires is the selection, never a separate judgement.
        def event_type(selection)
          selection.state == TerminalSelection::FAILED ? "CrawlFailed" : "CrawlCompleted"
        end

        # THE CHECKPOINT DERIVES NO SITEMAP OUTCOME, AND FU-9's TRANSFER IS WITHDRAWN (owner ruling 3;
        # round-6 blocker R6-4). What used to live here is recorded rather than deleted, because the
        # reasoning it replaced was ratified twice and the correction is the point.
        #
        # WHAT IT DID. `resolve_pending_sitemaps` claimed every `pending` non-robots-failed gate and
        # wrote `sitemap_unavailable`, on the argument that at the terminal checkpoint "no candidate can
        # ever succeed, so the premise is satisfied for the run as a whole."
        #
        # WHY THAT WAS WRONG, and Volume I :450 is the authority: "IF A DECLARED SITEMAP EXISTS, or the
        # default returns a non-404/410 response, AND NO SITEMAP CANDIDATE SUCCEEDS after
        # retries/validation, record `sitemap_unavailable`." The sentence has an ANTECEDENT and a
        # consequent, and the argument above established only the consequent. A gate the run never
        # attempted has neither a declared sitemap that was tried nor a default response to have
        # observed, so :450 authorises no outcome for it at all. PROOF 67 itself used allow-all robots
        # with no declared sitemap and no default fetch and then REQUIRED `sitemap_unavailable`, which
        # is the invented observation stated as an expectation. The repository's own record said so:
        # BUILD_STATE's FU-9 note reads ":450 conditions `sitemap_unavailable` on 'no candidate succeeds
        # AFTER retries/validation'; a candidate the rate limiter never released has had neither, so
        # nothing is recorded" — and the closure field of the same item transferred the opposite
        # obligation to this block.
        #
        # WHAT REPLACES IT IS NOT NOTHING. The old code reached a true COVERAGE answer by a false route:
        # an unattempted host should indeed stop a run being `full`. :458 says that directly — "any
        # in-scope candidate NOT EVALUATED ... makes coverage partial" — so the gate is left exactly as
        # the run left it and counted as `unattempted_discovery`, which lowers coverage and does not
        # touch :452's completion reason. Nothing is written to the customer's record about a host
        # nobody contacted.
        #
        # AND THE GATE IS LEFT ALONE ON PURPOSE. A `pending` gate on a terminal Crawl is now inert: it
        # is closed against late writes by `f1_crawl_child_fact_closed` and read only as a count. It
        # needs no sweep, and giving it one here would be the ad hoc stranded-claim substitute the
        # programme forbids; FU-22 under S-07-011 owns that.

        # :442's WALL CLOCK, OBSERVED WHERE IT ACTUALLY ENDS THE RUN (DECISIONS ADR-107).
        #
        # `Admission` records this crossing when a PASS arrives past the deadline. But the case this
        # action exists for is the one where no pass ever does — FU-22's pinned run, and any run whose
        # chain simply stopped — so the run that was ended BY its own sixty minutes recorded nothing
        # about them. :458 requires that "any in-scope candidate not evaluated because of … wall-clock
        # bound makes coverage partial AND RECORDS ITS EXACT LIMIT REASON", and the reason has to exist
        # somewhere to be recorded.
        #
        # THE DECISION TABLE IS THE IDEMPOTENCE. `crawl_limit_decisions` is unique on
        # `(crawl_id, limit_dimension, threshold_kind)`, so a pass that already observed the crossing
        # makes this a no-op returning `replayed`, and `CrawlLimitReached` still fires exactly once per
        # dimension and run. Nothing here counts or decides — the count below reads the decision table
        # like any other, so the selection is derived from one source whether a pass or this recorded it.
        #
        # Both thresholds, independently, for the reason `Admission#wall_clock` already records: a run
        # that crossed the hard bound genuinely crossed the soft one on the way past it, and gating the
        # soft limb behind the hard one loses it permanently for a run whose only crossing was the hard.
        #
        # THE PREDICATE IS WHETHER THE DEADLINE PREVENTED AN EVALUATION, NOT WHETHER THIS HANDLER
        # ARRIVED AFTER IT (DECISIONS ADR-114, FU-35). The first version of this method compared only
        # `now` with `deadline_at`, which is the CHECKPOINT'S DELIVERY INSTANT — so a run that fetched
        # every in-scope candidate and drained at minute five was recorded `limit_reached` / `partial`
        # with a hard decision affecting ZERO URLs and zero Sources, and emitted a real
        # `CrawlLimitReached` for a dimension that bounded nothing. Transport latency alone decided a
        # customer's coverage verdict, and `f1_crawls_guard` made it permanent.
        #
        # :458 conditions the whole rule on there being something to condition it on — "ANY IN-SCOPE
        # CANDIDATE NOT EVALUATED because of … wall-clock bound makes coverage partial and records its
        # exact limit reason" — and :442's own record is "dimension, configured value, observed value,
        # AFFECTED SOURCE AND URL COUNTS". A decision whose affected counts are zero is a decision that
        # nothing was affected by, which is not a limit hit; it is the absence of one.
        #
        # BOTH LIMBS ARE GATED, not only the hard one. A soft event for a run that finished its work
        # forty minutes earlier is the same false statement in a quieter voice, and `elapsed` here is
        # measured to the checkpoint's arrival rather than to the end of the run's work, so on a drained
        # run it is not the run's working duration at all.
        def observe_wall_clock(d, crawl)
          deadline = crawl["deadline_at"]
          return false if deadline.nil? || d[:now] < Platform::PgInstant.utc(deadline)

          # Read FIRST, because it is the predicate and not merely a field of the record.
          affected = affected_by_wall_clock(d, crawl)
          return false if affected.urls.zero?

          # AND THE CANDIDATES MUST BE THE CLOCK'S. A prior decision suppresses this one only when the
          # classifier says that dimension stopped the UNSELECTED frontier. Local URL/depth decisions do
          # not own unrelated queued rows; accepted-page and run-byte exhaustion do.
          #
          # :442 at a hard limit is "stop scheduling affected work", so those candidates were abandoned
          # by THAT dimension and the clock merely arrived afterwards to find them. Attributing them
          # here writes an immutable hard `wall_clock_run_duration` decision and spends the run's
          # once-per-run `CrawlLimitReached` on a dimension that bounded nothing — byte for byte the harm
          # R3-1 exists to prevent, and uncorrectable because `f1_crawls_guard` refuses every UPDATE of a
          # terminal row.
          #
          return false if d[:store].unselected_frontier_already_stopped?(
            d[:org], crawl["id"], LimitSemantics::UNSELECTED_FRONTIER_STOP_DIMENSIONS
          )

          limits = EffectiveLimits.resolve(d[:store].active_crawl_policies(d[:org], crawl["project_id"]))
          observer = LimitDecisions.new(ids: d[:ctx].ids, correlation_id: d[:ctx].correlation_id)
                                   .for(d[:pg], organization_id: d[:org], project_id: crawl["project_id"],
                                        crawl_id: crawl["id"], limits:)
          elapsed = elapsed_minutes(crawl, d[:now])
          soft = limits.configured(Admission::WALL_CLOCK_DIMENSION, LimitDimensions::SOFT)
          observer.soft(Admission::WALL_CLOCK_DIMENSION, elapsed, now: d[:now]) if elapsed >= soft
          # ":442 — record dimension, configured value, observed value, AFFECTED SOURCE AND URL COUNTS."
          observer.hard(Admission::WALL_CLOCK_DIMENSION, elapsed, now: d[:now], affected:)
          true
        end

        def elapsed_minutes(crawl, now)
          started = crawl["started_at"]
          return 0 if started.nil?

          Platform::PgInstant.elapsed_minutes(started, now)
        end

        # The candidates the deadline prevented from being evaluated: the ones the run never reached,
        # plus the ones whose REQUEST :442's own cancellation ended (ADR-113). Both are read from the
        # database rather than assumed, and the same value is the predicate and the record.
        def affected_by_wall_clock(d, crawl)
          row = d[:store].unevaluated_reach(d[:org], crawl["id"], FetchContent::REASONS[:wall_clock])
          LimitDecisions::Affected.new(sources: row["sources"].to_i, urls: row["urls"].to_i)
        end

        def count_facts(store, org, crawl, project_id)
          row = store.terminal_facts(org, crawl["id"], project_id)
          hard_dimensions = JSON.parse(row["hard_limit_dimensions"].to_s)
          TerminalSelection::Facts.new(
            documents: row["documents"].to_i, roots_total: row["roots_total"].to_i,
            roots_succeeded: row["roots_succeeded"].to_i, fetch_failures: row["fetch_failures"].to_i,
            unresolved_discovery: row["unresolved"].to_i,
            unattempted_discovery: row["unattempted"].to_i,
            hard_limit_decisions: hard_dimensions.size,
            terminal_limit_decisions: hard_dimensions.count do |dimension|
              LimitSemantics.terminal_forcing_decision?(dimension)
            end,
            sitemap_limit_facts: row["sitemap_limit_facts"].to_i,
            uncovered: row["uncovered"].to_i, unevaluated: row["unevaluated"].to_i
          )
        end

        # MTX-030 — "committing or releasing the root reservation EXACTLY ONCE" at the Crawl's durable
        # point. `entitlement-interim-v1` names that point `crawl_completed_with_valid_document`, and
        # :453 makes `completed` mean at least one valid Document by construction (a run with none is
        # `failed`), so the state IS the test. A run that never started one — a Crawl whose reservation
        # column is NULL — has nothing to settle and says so rather than guessing.
        def settle_reservation(d, crawl, selection, ids)
          reservation_id = crawl["entitlement_reservation_id"]
          return "none" if reservation_id.nil?

          if selection.state == TerminalSelection::FAILED
            return d[:entitlement].release(organization_id: d[:org], reservation_id:,
                                           reason: RELEASE_REASON, now: d[:now]).to_s
          end

          d[:entitlement].commit(organization_id: d[:org], reservation_id:,
                                 durable_output: { type: DURABLE_OUTPUT_TYPE, id: crawl["id"], sha256: nil },
                                 now: d[:now], ids: { commit_intent: ids[:commit_intent] },
                                 reason: COMMIT_REASON).to_s
        end

        # ---- audited no-state outcome ----------------------------------------------

        def mismatch(d)
          deny(**d, crawl: nil, outward: "scheduled_action_target_mismatch",
               internal: "scheduled_action_target_mismatch", replayable: false)
        end

        # `**_rest` absorbs the context keys the callers splat in that an audited no-state outcome has
        # no use for, so no parameter is declared and left dead.
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

        # ---- writers ---------------------------------------------------------------

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

        def hex(bytes) = bytes.unpack1("H*")
        def iso(time) = time.getutc.floor(6).iso8601(6)
        def month(time) = Date.new(time.year, time.month, 1)
        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
      end
    end
  end
end
