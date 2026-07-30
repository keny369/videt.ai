# frozen_string_literal: true

require "securerandom"

module Workflows
  module Wf005
    # ONE PASS OF THE RUN (S-07-012). The surfaces S-07-004..008 built — `EnsureRobots`,
    # `DiscoverSitemaps`, `Admission`, `FetchContent` — had no production caller at all: the only
    # registered entry point was `crawl_dispatch -> StartCrawl`, which seeded the root frontier and
    # scheduled nothing further. This is what calls them, and it is the reason every claim about a run
    # making progress is now true rather than presupposed.
    #
    # IT IS A CHAIN, NOT A LOOP. BACKGROUND_PROCESSING.md :377 fixes `crawl_orchestrate` to
    # StartCrawl / CompleteCrawl / FailCrawl / CancelCrawl "selected solely from persisted
    # Crawl/deadline state", so the orchestrator cannot drive the frontier. :378 gives
    # `crawl_fetch -> RecordFetchAttempt` and "its terminal transaction creates the exact ingestion or
    # next-frontier action". So one `crawl_fetch_due` action equals one pass, and each pass's terminal
    # transaction creates the next link. The run's own 60-minute wall clock bounds the chain: past the
    # deadline no pass links, so a chain cannot outlive its Crawl.
    #
    # THE ORDER OF OPERATIONS IS THE SPECIFICATION.
    #
    #   1. THE WALL CLOCK, before anything. :442 — "At 60 elapsed minutes, NO NEW REQUEST STARTS."
    #      Robots and sitemap documents are requests too, so it is consulted before the first of the
    #      three and not only at admission. The DECISION is still `Admission`'s, which is the ratified
    #      observation point for `wall_clock_run_duration` and which refuses before it peeks, so
    #      calling it on an expired run records the limit and claims nothing.
    #   2. ROBOTS. :448's fetch is a precondition of every other request against the host, and
    #      `EnsureRobots` performs at most ONE network attempt per call and hands its :444 retry
    #      schedule back to the caller. Nothing was that caller until now, so a host whose robots
    #      failed transiently was simply never resolved. A retryable outcome re-enters at the instant
    #      the result names.
    #   3. SITEMAP DISCOVERY, which is FU-9's re-entry. A gate the release handed back is `pending`
    #      with a `retry_after` instant, and re-entering at exactly that instant is what stops
    #      sustained contention from terminalizing `sitemap_unavailable` with zero network attempts.
    #   4. ADMISSION of the named entry, which is where the byte reservation and the frontier claim
    #      happen together and in dequeue order (FU-10).
    #   5. THE FETCH, through the accepted `FetchContent#call` — its own :444 retry loop, unchanged,
    #      consuming the reservation admission paid for. This is the ruling in ADR-085: the fetch path
    #      is the SOLE producer of `fetch_attempts`, and the retries S-07-007 proved stay in-process.
    #
    # A PASS THAT DECIDES NOTHING RE-ENTERS AGAINST THE SAME ENTRY, and leaves the frontier exactly as
    # it found it. That is the difference between a driver and a poller: robots-still-resolving,
    # sitemap-handed-back and `run_byte_budget_contended` are all "come back", none of them is an
    # outcome, and none of them costs the entry an attempt or the run a byte.
    class CrawlDriver
      # What one pass did. `fetch` is the `FetchContent::Result` when a request was made; `released` is
      # whether this pass retired its claimed entry and so released :454's depth seal.
      Pass = Data.define(:outcome, :reason_code, :entry, :fetch, :reenter_at, :released) do
        def initialize(released: false, **) = super
        def fetched? = outcome == CrawlDriver::FETCHED
        # Link the run forward to whatever is next.
        def advances? = [CrawlDriver::FETCHED, CrawlDriver::SUPERSEDED, CrawlDriver::RETIRED].include?(outcome)
        # Come back to THIS entry: nothing was decided and nothing was spent.
        def reenters? = [CrawlDriver::DEFERRED, CrawlDriver::RETRYING].include?(outcome)
      end

      FETCHED = "fetched"
      DEFERRED = "deferred"
      # The run may not start another request: a limit, the wall clock, or an authorization denial.
      # None of them links, because :442's rule at a hard limit is to "stop scheduling affected work".
      HALTED = "halted"
      # The named entry was not the frontier's next candidate, so this pass claims nothing and hands
      # the run on. Reachable only through a redelivery whose original pass was lost after claiming.
      SUPERSEDED = "superseded"
      # The named entry could not be fetched at all and has been retired unfetched, so the run advances
      # to the next candidate instead of stopping. Today's only producer is :448's fail-closed robots.
      RETIRED = "retired"
      # :444 owes this entry another attempt. The pass re-enters against the SAME entry at the instant the
      # contract names, keeping the claim, the reservation and the depth seal — none of which is a "come
      # back and decide", so it is not `DEFERRED`.
      RETRYING = "retrying"
      # This delivery's lease was CONFIRMED transferred to another worker mid-pass. It stops at the next
      # safe boundary and writes nothing: no terminal frontier state, no link, no ledger. Whatever it had
      # already committed stays governed by the authorities that own it — the attempt identity, the byte
      # counters and the frontier claim — and the delivery that now owns the action continues.
      RELINQUISHED = "relinquished"

      # ONE PASS MAKES AT MOST ONE PACED HOST START, and this is what enforces it.
      #
      # :442 paces starts over a rolling one-second window per canonical host, and sitemap discovery
      # claims the same gate a content fetch does. Without this check a single pass would fetch a
      # sitemap and then, in the same second, have its content claim REFUSED — and `FetchContent`
      # classifies a refused claim as `host_gate_deferred` with `retryable: false`, so the root URL
      # would be recorded `limit_discarded` because the run's own discovery had just been polite. The
      # gate publishes the exact instant it may next be started; the pass comes back then.
      #
      # Deliberately NOT `FetchContent::REASONS[:gate_deferred]`. That reason names a URL :452 has
      # DISCARDED; this one names a pass that decided nothing. Checked BEFORE admission, so no entry is
      # claimed and no byte reserved only to be handed back.
      HOST_PACED = "host_gate_paced"

      ROBOTS_RESOLVING = "robots_resolving"
      # Robots is terminal and NOT fetchable — :448's fail-closed. No request may be made against the
      # host, and the entry stays `queued` rather than being discarded: nothing about it was decided,
      # and discarding it would remove a genuinely unfetched in-scope candidate from :452's coverage
      # denominator, making coverage read better than reality.
      ROBOTS_FAIL_CLOSED = "robots_unavailable_fail_closed"
      # `Admission` refuses in :541's order and reaches the wall clock before it peeks, so it always has a
      # more precise reason than this. Retained as the fail-closed fallback for a decision that declines
      # without one, and named for the run rather than for the clock because that is what would be true.
      RUN_NOT_RUNNING = "crawl_not_running"

      def initialize(outbound: Platform::Outbound, ids: Platform::Ids.system, correlation_id: nil,
                     pacer: nil)
        @outbound = outbound
        @ids = ids
        @correlation_id = correlation_id || SecureRandom.uuid_v7
        @pacer = pacer
      end

      # `entry` is the `crawl_frontier_entries` row the action targets. Every field this reads from it
      # — `crawl_id`, `project_id`, `source_id`, `canonical_url` — is frozen for the life of the entry
      # by `f1_crawl_frontier_entries_guard`, so carrying it across the caller's transaction boundary
      # cannot go stale. Everything MUTABLE is re-read here.
      def advance(organization_id:, entry:, now:, due_at: nil)
        crawl_id = entry["crawl_id"]
        crawl = load_crawl(organization_id, crawl_id)
        # The entry's composite foreign key REQUIRES its Crawl, so absence is corruption rather than a
        # domain outcome, and guessing at it would hand a worker unauthorized work.
        raise Platform::InvariantViolation, "crawl_fetch_due entry has no Crawl" if crawl.nil?

        # STEP ZERO, BEFORE ANY EFFECT. Not merely before the fetch: before the gate row, before the
        # robots request and before the write-once sitemap outcome. See `Admission#authorize_run`.
        denial = admission.authorize_run(organization_id:, crawl:, now:)
        return halted(denial, entry:) if denial

        return halted(admission_reason(organization_id, crawl_id, entry, now)) unless within_wall_clock?(crawl, now)

        host = FetchAuthorization.host_of(entry["canonical_url"])
        # A frontier entry's URL was canonicalized by the predicate that admitted it, so a hostless one is
        # corruption of a frozen column, not an input this pass may interpret. `host_of` returns "" rather
        # than nil for a hostless URL, so an `.nil?` test here was unreachable and would have handed `""`
        # to the gate and to `https:///robots.txt`.
        raise Platform::InvariantViolation, "crawl_fetch_due entry has no parseable host" if host.to_s.empty?

        gate = ensure_gate(organization_id, entry, crawl, host, now)
        robots = resolve_robots(organization_id, crawl_id, host, now)
        return relinquished(entry) unless Platform::ScheduledActions::Lease.owned?
        return robots_outcome(robots, organization_id, crawl, entry, now) unless robots.fetchable?

        discovery = discover(organization_id, crawl_id, entry, host, now)
        # The gate is the authority on when the host may next be started, and it is read as a REMAINDER
        # so the wait composes with this pass's own clock. `DiscoverSitemaps` reports the same fact as an
        # absolute `clock_timestamp()`-derived instant, and taking that would mix two time bases: a worker
        # clock lagging the database by more than the floor makes the re-entry instant a FIXED POINT, and
        # because the ScheduledAction identity includes `due_at` the next link would REPLAY the action
        # that just ran instead of being created — and the chain would stop.
        ready = host_ready_at(organization_id, gate, now)
        return deferred(DiscoverSitemaps::CONTENDED, entry:, at: ready) if discovery.rescheduled?
        return deferred(HOST_PACED, entry:, at: ready) if ready
        # THE LAST BOUNDARY BEFORE ANYTHING IRREVERSIBLE. Past here the pass claims a frontier entry,
        # reserves bytes and sends a request; a delivery whose ownership has moved must do none of them.
        return relinquished(entry) unless Platform::ScheduledActions::Lease.owned?

        admit_or_resume(organization_id, crawl, entry, gate, now, due_at)
      end

      private

      # ADMIT A NEW ENTRY, OR RESUME THE RETRY OF ONE THIS RUN ALREADY CLAIMED.
      #
      # Both are needed because one execution performs one attempt (ADR-089). A first pass admits: it
      # claims the entry and pays for it in dequeue order. A retry pass finds the SAME entry already
      # `in_progress` — its own admission's claim, deliberately still held, because the reservation, the
      # attempt numbering and the depth seal are all continuous across :444's retries. `claim_entry`
      # cannot re-admit it (`peek_next` sees only `queued`), so the retry is recognised from COMMITTED
      # STATE instead: the entry's latest attempt is terminal, was retryable, and left the bound unspent.
      def admit_or_resume(organization_id, crawl, entry, gate, now, due_at)
        decision = admission.claim_entry(organization_id:, crawl_id: crawl["id"],
                                         entry_id: entry["id"], now:)
        # ":442 — a lost compare-and-update on the run's byte counter is NOT a limit." The entry was
        # peeked and not claimed, so it is exactly where it was; come back.
        return deferred(Admission::CONTENDED, entry:, at: nil) if decision.reason_code == Admission::CONTENDED
        return halted(decision.reason_code, entry:) if decision.limited?
        return fetch_and_settle(organization_id, crawl, decision.entry, gate, now,
                                decision.reserved_bytes) if decision.admitted?

        resumable = resumable_retry(organization_id, crawl, entry, due_at)
        return superseded(entry) if resumable.nil?

        fetch_and_settle(organization_id, crawl, resumable[:entry], gate, now, resumable[:reserved])
      end

      # The retry state, or nil when this entry is not this run's to continue. Read once, from the row the
      # previous pass committed: what it reserved minus what it accounted is what remains, and the
      # attempt number and outcome say whether :444 owes another try. A NON-terminal latest attempt means
      # a worker is on it right now, and a claimed entry with no attempt at all belongs to a pass that has
      # not reached its fetch — neither is ours to take, and `sweep_expired` reclaims a genuinely lost one.
      def resumable_retry(organization_id, crawl, entry, due_at)
        current, latest = Platform::UnitOfWork.run do |conn|
          raw = conn.raw_connection
          frontier = IdentityAccess::Infrastructure::CrawlFrontierStore.new(raw)
          frontier.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          attempts = IdentityAccess::Infrastructure::FetchAttemptStore.new(raw)
          [frontier.entry(organization_id, entry["id"]),
           attempts.latest_attempt(organization_id, crawl["id"], entry["id"], "content")]
        end
        return nil unless current && current["state"] == "in_progress"
        return nil unless latest && latest["outcome"] && Platform::PgBool.true?(latest["retryable"])
        return nil unless latest["attempt_number"].to_i < FetchContent::MAX_ATTEMPTS
        # A SWEPT ATTEMPT IS NOT A RESUMABLE ONE. `sweep_expired` terminalizes a lost attempt as
        # `timed_out` / `retryable = true` / `accounted = 0` — which satisfies every condition above — AND
        # has already RELEASED its reservation back to the run. Resuming from it would spend bytes the run
        # no longer holds, against :442's "concurrent reservations MUST NOT sum above the run-wide maximum".
        # The reservation's absence is not representable on the row, so the sweep's own reason code is what
        # distinguishes it; recovering such an entry is FU-22's.
        return nil if latest["reason_code"] == IdentityAccess::Infrastructure::FetchAttemptStore::LEASE_EXPIRED_REASON
        # THE RESUME BELONGS TO THE STAGE IT WAS SCHEDULED FOR. Without this, two deliveries in flight
        # between one pass's settle and its terminal transaction both qualify, then compute DIFFERENT
        # attempt numbers and fetch one URL concurrently on one reservation — which the attempt identity's
        # `ON CONFLICT` cannot catch, because the numbers differ. The action's own `due_at` is :444's instant
        # for exactly one attempt, so requiring them to agree admits exactly one delivery per stage.
        return nil unless due_at && stage_instant(latest) == due_at.getutc

        # `reserved_bytes` minus what was accounted, and ZERO IS LEGITIMATE: a retryable response whose body
        # exactly filled the reservation owes a retry that `one_attempt` will refuse for budget, honestly,
        # rather than being silently converted into a superseded pass that stops the chain.
        remaining = latest["reserved_bytes"].to_i - latest["accounted_response_bytes"].to_i
        return nil if remaining.negative?

        { entry: current, reserved: remaining }
      end

      # :444's instant for the attempt just completed — the same expression `retry_due_at` uses, so the
      # scheduled action and the resume that answers it are derived from one rule rather than two.
      def stage_instant(attempt)
        completed = attempt["completed_at"]
        return nil if completed.nil?

        delay = FetchRetryPolicy::DELAYS_S.fetch(attempt["attempt_number"].to_i,
                                                 FetchRetryPolicy::DELAYS_S.values.last)
        Time.parse(completed.to_s).utc + delay
      end

      # THE FETCH, AND WHAT ITS OUTCOME OWES. Exactly one attempt, then one of two dispositions:
      #
      #   * :444 owes another attempt — the entry stays claimed, the reservation stays held, the seal stays
      #     held, and the pass schedules a re-entry against this same entry at the instant :444 names,
      #     which is `completed_at + 30s` or `+ 120s` measured from the attempt that just failed. The
      #     worker returns immediately; NOTHING SLEEPS. This is the whole of ADR-089.
      #   * nothing more is owed — the remainder is already released, the seal is released, and the run
      #     links forward.
      #
      # A retry that would fall past the run's own deadline is not scheduled at all. :442 ends the run at
      # 60 elapsed minutes, so such a re-entry could only arrive to be refused; treating it as exhaustion
      # instead releases the reservation and the seal now, and strands neither.
      def fetch_and_settle(organization_id, crawl, entry, gate, now, reserved_bytes)
        execution = fetch_content.call(organization_id:, crawl_id: crawl["id"], entry:,
                                       gate_id: gate["id"], now:, reserved_bytes:)
        result = execution.result

        # A PASS THAT PERFORMED NO ATTEMPT DISPOSES OF NOTHING. The host gate refused, or execution-time
        # authorization refused, or another delivery had already claimed this attempt number — in each case
        # this pass made no request and decided nothing, so retiring the entry and releasing the reservation
        # would be taking apart work another delivery is doing. Two reviewers demonstrated both halves of
        # that: a `PG::CheckViolation` escaping the workflow when the winner's headroom was handed back
        # mid-fetch, and an entry retired after 2 of 3 attempts by the pass that fetched nothing.
        unless execution.performed?
          return deferred(result.reason_code || HOST_PACED, entry:,
                          at: host_ready_at(organization_id, gate, now))
        end

        # OWNERSHIP LOST DURING THE FETCH. The attempt itself is already committed and accounted by the
        # authorities that own it, and this pass stops there: it writes no terminal frontier state, creates
        # no link, and lets the delivery that now owns the action carry on.
        return relinquished(entry) unless Platform::ScheduledActions::Lease.owned?

        retry_at = retry_due_at(execution, crawl)
        if retry_at
          return Pass.new(outcome: RETRYING, reason_code: result.reason_code, entry:, fetch: result,
                          reenter_at: retry_at, released: false)
        end

        release_remainder(organization_id, crawl, execution, now)
        Pass.new(outcome: FETCHED, reason_code: result.reason_code, entry:, fetch: result,
                 reenter_at: nil, released: release_seal(organization_id, entry, now))
      end

      # :444's instant, or nil when no retry is owed or the run cannot outlast it.
      def retry_due_at(execution, crawl)
        return nil unless execution.retry_owed? && execution.completed_at

        at = Time.parse(execution.completed_at.to_s).utc + (execution.retry_after_ms.to_i / 1000.0)
        deadline = crawl["deadline_at"] && Time.parse(crawl["deadline_at"].to_s).utc
        return nil if deadline && at > deadline

        at
      end

      # The reservation a retry-that-will-not-happen was still holding. `FetchContent` releases on every
      # path it decides itself; this covers the one the DRIVER decides — a retry refused for the deadline.
      def release_remainder(organization_id, crawl, execution, now)
        remaining = execution.remaining_reserved.to_i
        return unless remaining.positive?

        Platform::UnitOfWork.run do |conn|
          store = IdentityAccess::Infrastructure::CrawlBudgetStore.new(conn.raw_connection)
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          store.release_bytes(organization_id, crawl["id"], remaining, now)
        end
      end

      # THE SEAL RELEASE (DECISIONS ADR-087). The entry this pass claimed has had its fetch decided, so
      # it stops holding :454's depth seal — `sealed_depth` is `MIN(depth)` over
      # ('queued','in_progress','fetched_pending_commit'), and without this the depth a pass has finished
      # with pins the frontier for the rest of the run and no depth-1 candidate is ever selectable.
      #
      # A COMPARE-AND-SET ON THIS PASS'S OWN CLAIM. The version comes from `Admission`'s claim, not from
      # a re-read, so the release binds to the claim that authorised it: a stale version, an entry that
      # was never claimed, and a second delivery each match zero rows rather than retiring an entry this
      # pass does not own. Zero rows is NOT an error — the redelivery path below is exactly where it
      # happens legitimately — so it is reported, not raised.
      #
      # IN ITS OWN TRANSACTION, BEFORE THE LEDGER AND THE NEXT LINK, and that ordering is the ADR's. The
      # tidier alternative — retiring the entry inside the handler's terminal transaction, atomically
      # with the ledger and the link — has the worse failure mode: a process lost between the fetch and
      # the ledger write would leave the entry `in_progress` forever and PERMANENTLY PIN THE DEPTH.
      # Retiring it first means a lost pass leaves the seal RELEASED and no link, and the redelivery then
      # finds the entry terminal, records `superseded`, and links the run on. The chain repairs itself
      # with no new recovery vocabulary, and ledger completeness is identical either way because in both
      # cases the lost transaction is the one carrying the ledger rows.
      def release_seal(organization_id, entry, now)
        Platform::UnitOfWork.run do |conn|
          store = IdentityAccess::Infrastructure::CrawlFrontierStore.new(conn.raw_connection)
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          store.terminalize(organization_id, entry["id"], entry["state_version"].to_i, now).positive?
        end
      end

      # :442's wall clock, and only that: the Crawl's state, the Organization, the Project and the
      # entitlement lease are `authorize_run`'s, which has already refused above. Two readers of one
      # column is deliberate — this one DECIDES whether to start a request, and `Admission#wall_clock`
      # RECORDS the ratified `wall_clock_run_duration` decision.
      def within_wall_clock?(crawl, now)
        deadline = crawl["deadline_at"]
        deadline.nil? || Time.parse(deadline.to_s).utc > now.utc
      end

      # An unstartable run still goes through `Admission`, which is the ratified observation point for
      # `wall_clock_run_duration` and refuses BEFORE the peek — so the ratified soft and hard limit
      # decisions are recorded exactly once, by the component that owns them, and nothing is claimed.
      # `Admission` refuses in :541's order, so its own reason is always the more precise one; the
      # fallback covers only the case where it declines without a reason (an entry that is no longer
      # the next candidate on a run that is also unstartable), where the run state IS the answer.
      def admission_reason(organization_id, crawl_id, entry, now)
        decision = admission.claim_entry(organization_id:, crawl_id:, entry_id: entry["id"], now:)
        # A MUTATION USED AS A QUERY, so it fails closed LOUDLY rather than silently. Reaching here means
        # the wall clock has expired, and `Admission` checks the same deadline before it peeks, so it
        # cannot admit. If it ever did, discarding the Decision would strand the entry `in_progress` with
        # its byte reservation held, no fetch and no link — the exact defect with no crash required.
        raise Platform::InvariantViolation, "admission admitted an entry past the wall clock" if decision.admitted?

        decision.reason_code || RUN_NOT_RUNNING
      end

      # :448 — the robots record is a precondition of every request against the host. `EnsureRobots`
      # makes at most one attempt per call and reports the :444 delay before the next; this is the
      # caller that honours it. A robots record that is terminal but not fetchable is fail-closed: no
      # request may be made against the host at all, so the pass halts rather than linking, and the
      # entry stays `queued` — unfetched and still in :452's denominator, which is the truth.
      def robots_outcome(robots, organization_id, crawl, entry, now)
        return deferred(ROBOTS_RESOLVING, entry:, at: retry_instant(robots.retry_after_ms, now)) unless robots.terminal?

        retire_unfetchable(organization_id, crawl, entry, robots.reason_code || ROBOTS_FAIL_CLOSED, now)
      end

      # A FAIL-CLOSED ROBOTS RECORD RETIRES ITS OWN ENTRY AND THE RUN CARRIES ON.
      #
      # :448 scopes the outcome to ONE HOST — "denies all content fetching FOR THAT HOST for the run" —
      # and :452 to ONE SOURCE ROOT — "makes that Source root failed and coverage partial". MTX-030 fails
      # the whole Crawl only when "every active Source root fails". This used to `halt`, which created no
      # link, so a Project with two Sources and one 403 robots host NEVER REQUESTED THE HEALTHY HOST and
      # left a `running` Crawl with no scheduled work at all.
      #
      # Advancing without retiring the entry does not work and the reason is worth recording: `peek_next`
      # selects the lowest `dequeue_key` among `queued` rows at `sealed_depth`, which is this same
      # unfetchable entry — so the next link would target it again, forever, at the pacing floor. The
      # entry has to LEAVE the selectable set.
      #
      # It leaves through the edge this tranche already built and nothing wider: `queued -> in_progress`
      # under the frontier's own advisory lock, then the `in_progress -> terminal` compare-and-set. No
      # request is made, no attempt row is created and no byte is reserved. `terminal` rather than
      # `discarded` is what :452 needs — a discard leaves the coverage denominator, and this URL was
      # genuinely not retrieved — and the distinguishing fact is durable on the gate itself, whose
      # `robots_terminal_reason` is `robots_unavailable_fail_closed`, which is the token :452 reads.
      def retire_unfetchable(organization_id, crawl, entry, reason, now)
        retired = Platform::UnitOfWork.run do |conn|
          store = IdentityAccess::Infrastructure::CrawlFrontierStore.new(conn.raw_connection)
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          store.lock_frontier(crawl["id"])
          candidate = store.peek_next(organization_id, crawl["id"])
          # Claim ONLY the named entry, for the same reason `claim_entry` does: retiring whatever happened
          # to be next would retire an entry this pass was never given.
          next false unless candidate && candidate["id"] == entry["id"]

          claimed = store.claim_next(organization_id, crawl["id"], now)
          next false unless claimed && claimed["id"] == entry["id"]

          store.terminalize(organization_id, claimed["id"], claimed["state_version"].to_i, now).positive?
        end
        return superseded(entry) unless retired

        Pass.new(outcome: RETIRED, reason_code: reason, entry:, fetch: nil, reenter_at: nil, released: true)
      end

      # The :444 delay the robots result names — the fixed 30s/120s schedule, or a `Retry-After` the
      # response supplied. Nil when another worker holds the attempt, where the floor decides.
      def retry_instant(milliseconds, now)
        milliseconds && now + (milliseconds.to_i / 1000.0)
      end

      def ensure_gate(organization_id, entry, crawl, host, now)
        Platform::UnitOfWork.run do |conn|
          store = IdentityAccess::Infrastructure::CrawlHostGateStore.new(conn.raw_connection)
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          HostGate.new(store, ids: @ids, correlation_id: @correlation_id)
                  .ensure_gate(organization_id:, project_id: entry["project_id"], crawl_id: crawl["id"],
                               canonical_host: host, now:)
        end
      end

      def resolve_robots(organization_id, crawl_id, host, now)
        EnsureRobots.new(outbound: @outbound, correlation_id: @correlation_id)
                    .call(organization_id:, crawl_id:, canonical_host: host, now:)
      end

      def discover(organization_id, crawl_id, entry, host, now)
        service(DiscoverSitemaps).call(organization_id:, crawl_id:, canonical_host: host,
                                       source_id: entry["source_id"], now:)
      end

      # The instant the gate says the host may next be started, or nil when it may start now. Read as a
      # REMAINDER and added to this pass's own clock, never as the gate's absolute instant: the pacing
      # floor is written from `clock_timestamp()` and the pass decides against the clock its request
      # context injected, so adding the remainder keeps one time base instead of mixing two.
      def host_ready_at(organization_id, gate, now)
        remaining = Platform::UnitOfWork.run do |conn|
          store = IdentityAccess::Infrastructure::CrawlHostGateStore.new(conn.raw_connection)
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          store.pacing_remaining_ms(organization_id, gate["id"])
        end
        now + (remaining / 1000.0) if remaining.to_i.positive?
      end

      def load_crawl(organization_id, crawl_id)
        Platform::UnitOfWork.run do |conn|
          store = IdentityAccess::Infrastructure::CrawlHostGateStore.new(conn.raw_connection)
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          store.crawl(organization_id, crawl_id)
        end
      end

      def admission = @admission ||= Admission.new(ids: @ids, correlation_id: @correlation_id)

      # No `pacer:`. Nothing in the fetch path waits any more — the scheduler owns waiting (ADR-089) — so
      # `FetchContent` has no pacer to inject. `DiscoverSitemaps` still does: its host-gate deferrals are
      # sub-second waits inside one traversal, not :444 retries.
      def fetch_content
        @fetch_content ||= FetchContent.new(outbound: @outbound, ids: @ids, correlation_id: @correlation_id)
      end

      # `pacer` is how `DiscoverSitemaps` takes its in-traversal waits; it is injectable so a test can
      # simulate elapsed time instead of spending it, and omitted in production. `FetchContent` has none:
      # since ADR-089 nothing on the fetch path waits.
      # `DiscoverSitemaps` waits in-traversal — :444's 30 and 120 seconds between sitemap candidates, and
      # the host gate's remainder. Those waits are why a pass could outlive its lease even after the content
      # retries moved to the scheduler, so the pacer it gets is the LEASE-AWARE one: the same total wait,
      # divided at heartbeat deadlines, holding no database connection while it waits. Without a lease
      # (a spec, a direct call) it is an ordinary sleep, so nothing outside a worker changes.
      def service(klass)
        args = { outbound: @outbound, ids: @ids, correlation_id: @correlation_id }
        args[:pacer] = @pacer || Platform::ScheduledActions::Lease.pacer
        klass.new(**args)
      end

      def deferred(reason, entry:, at:)
        Pass.new(outcome: DEFERRED, reason_code: reason, entry:, fetch: nil, reenter_at: at)
      end

      def halted(reason, entry: nil)
        Pass.new(outcome: HALTED, reason_code: reason, entry:, fetch: nil, reenter_at: nil)
      end

      def relinquished(entry)
        Pass.new(outcome: RELINQUISHED, reason_code: RELINQUISHED, entry:, fetch: nil,
                 reenter_at: nil, released: false)
      end

      def superseded(entry)
        Pass.new(outcome: SUPERSEDED, reason_code: nil, entry:, fetch: nil, reenter_at: nil)
      end
    end
  end
end
