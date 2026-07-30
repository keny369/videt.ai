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
      # What one pass did. `fetch` is the `FetchContent::Result` when a request was made.
      Pass = Data.define(:outcome, :reason_code, :entry, :fetch, :reenter_at) do
        def fetched? = outcome == CrawlDriver::FETCHED
        # Link the run forward to whatever is next.
        def advances? = [CrawlDriver::FETCHED, CrawlDriver::SUPERSEDED].include?(outcome)
        # Come back to THIS entry: nothing was decided and nothing was spent.
        def reenters? = outcome == CrawlDriver::DEFERRED
      end

      FETCHED = "fetched"
      DEFERRED = "deferred"
      # The run may not start another request: a limit, the wall clock, or an authorization denial.
      # None of them links, because :442's rule at a hard limit is to "stop scheduling affected work".
      HALTED = "halted"
      # The named entry was not the frontier's next candidate, so this pass claims nothing and hands
      # the run on. Reachable only through a redelivery whose original pass was lost after claiming.
      SUPERSEDED = "superseded"

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
      def advance(organization_id:, entry:, now:)
        crawl_id = entry["crawl_id"]
        crawl = load_crawl(organization_id, crawl_id)
        # The entry's composite foreign key REQUIRES its Crawl, so absence is corruption rather than a
        # domain outcome, and guessing at it would hand a worker unauthorized work.
        raise Platform::InvariantViolation, "crawl_fetch_due entry has no Crawl" if crawl.nil?

        return halted(admission_reason(organization_id, crawl_id, entry, now)) unless startable?(crawl, now)

        host = FetchAuthorization.host_of(entry["canonical_url"])
        # A frontier entry's URL was canonicalized by the predicate that admitted it, so an unparseable
        # host is corruption of a frozen column, not an input this pass may interpret.
        raise Platform::InvariantViolation, "crawl_fetch_due entry has no parseable host" if host.nil?

        gate = ensure_gate(organization_id, entry, crawl, host, now)
        robots = resolve_robots(organization_id, crawl_id, host, now)
        return robots_outcome(robots, entry, now) unless robots.fetchable?

        discovery = discover(organization_id, crawl_id, entry, host, now)
        if discovery.rescheduled?
          return deferred(DiscoverSitemaps::CONTENDED, entry:, at: instant(discovery.retry_after))
        end

        ready = host_ready_at(organization_id, gate, now)
        return deferred(HOST_PACED, entry:, at: ready) if ready

        admit_and_fetch(organization_id, crawl, entry, gate, now)
      end

      private

      def admit_and_fetch(organization_id, crawl, entry, gate, now)
        decision = admission.claim_entry(organization_id:, crawl_id: crawl["id"],
                                         entry_id: entry["id"], now:)
        # ":442 — a lost compare-and-update on the run's byte counter is NOT a limit." The entry was
        # peeked and not claimed, so it is exactly where it was; come back.
        return deferred(Admission::CONTENDED, entry:, at: nil) if decision.reason_code == Admission::CONTENDED
        return halted(decision.reason_code, entry:) if decision.limited?
        return superseded(entry) unless decision.admitted?

        result = fetch_content.call(organization_id:, crawl_id: crawl["id"], entry: decision.entry,
                                    gate_id: gate["id"], now:, reserved_bytes: decision.reserved_bytes)
        Pass.new(outcome: FETCHED, reason_code: result.reason_code, entry: decision.entry,
                 fetch: result, reenter_at: nil)
      end

      # :442's wall clock and the Crawl's own state, read together because both make a request
      # impermissible rather than merely unwise.
      def startable?(crawl, now)
        return false unless crawl["state"] == "running"

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
        admission.claim_entry(organization_id:, crawl_id:, entry_id: entry["id"], now:).reason_code ||
          RUN_NOT_RUNNING
      end

      # :448 — the robots record is a precondition of every request against the host. `EnsureRobots`
      # makes at most one attempt per call and reports the :444 delay before the next; this is the
      # caller that honours it. A robots record that is terminal but not fetchable is fail-closed: no
      # request may be made against the host at all, so the pass halts rather than linking, and the
      # entry stays `queued` — unfetched and still in :452's denominator, which is the truth.
      def robots_outcome(robots, entry, now)
        return halted(robots.reason_code || ROBOTS_FAIL_CLOSED, entry:) if robots.terminal?

        deferred(ROBOTS_RESOLVING, entry:, at: retry_instant(robots.retry_after_ms, now))
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
      def fetch_content = @fetch_content ||= service(FetchContent)

      # `pacer` is how the in-process :444 waits are taken. It is injectable for the same reason
      # `FetchContent` and `DiscoverSitemaps` make it injectable — so a test can simulate elapsed time
      # instead of spending it — and omitted in production, where each service uses its own default.
      def service(klass)
        args = { outbound: @outbound, ids: @ids, correlation_id: @correlation_id }
        args[:pacer] = @pacer if @pacer
        klass.new(**args)
      end

      def instant(value) = value && Time.parse(value.to_s).utc

      def deferred(reason, entry:, at:)
        Pass.new(outcome: DEFERRED, reason_code: reason, entry:, fetch: nil, reenter_at: at)
      end

      def halted(reason, entry: nil)
        Pass.new(outcome: HALTED, reason_code: reason, entry:, fetch: nil, reenter_at: nil)
      end

      def superseded(entry)
        Pass.new(outcome: SUPERSEDED, reason_code: nil, entry:, fetch: nil, reenter_at: nil)
      end
    end
  end
end
