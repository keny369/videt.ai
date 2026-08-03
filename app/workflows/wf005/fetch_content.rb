# frozen_string_literal: true

require "digest"
require "securerandom"

module Workflows
  module Wf005
    # Content fetch for one frontier entry (S-07-007; WORKFLOW_SPECIFICATIONS.md :436, :442, :444,
    # :446, :448, :452; SEARCH_CRAWL_RETRIEVAL.md § Destination And HTTP Safety).
    #
    # The order of operations is the specification, not a convenience:
    #
    #   1. CLAIM the host slot (:442's rolling-rate and concurrency predicates, under a row lock).
    #   2. AUTHORIZE at execution time — Organization, Crawl, Project, Source, reservation, current
    #      Source Scope, robots. Never queue-time authority: S-07-004's dequeue check is necessary
    #      and not sufficient, and the owner's direction on this block is explicit.
    #   3. CONSUME the run-wide bytes Admission reserved BEFORE the body is read (:442).
    #   4. CLAIM the attempt row, so a worker lost mid-request leaves a record rather than a hole.
    #   5. FETCH, with the caller's redirect guard rechecking robots and Source Scope on every hop
    #      before it is followed (:448) — the platform owns destination safety, the caller owns
    #      policy, and neither can be inferred from the other.
    #   6. MEASURE against :442's max-of-two-paths formula and the sentinel rule.
    #   7. COMMIT the accounted bytes and RELEASE the unused remainder, in one statement.
    #   8. TERMINALISE the attempt write-once, and RELEASE the host slot however it ended.
    #
    # NO TRANSACTION SPANS THE NETWORK CALL (MTX-030), which is the property that matters: a fetch
    # holding the gate row would serialise every other worker on that host behind a round trip.
    # Reviewed by instrumentation, and stated precisely rather than approximately: one fetch opens
    # about a dozen short transactions, and the REDIRECT GUARD OPENS ONE PER HOP FROM INSIDE step 5.
    # That guard transaction is the price of :448's per-hop recheck — the policies it evaluates live
    # in the database and the connector cannot know them — and it is safe because it holds nothing
    # while it waits, so it can only ever be a victim of contention, never a cause of deadlock.
    #
    # Step 7 and step 8 are ONE transaction. The run's byte counter and the attempt record describe
    # the same event; committing them separately left the counter advanced and the record blank
    # whenever the second failed, and nothing could reconcile them afterwards.
    class FetchContent
      # NOTE: no per-fetch bound is a class constant. :390 makes the operative limits "the most
      # restrictive of global safety, approved entitlement, Organization, and Project limits", and a
      # constant cannot vary per Crawl — a Project that narrowed `request_timeout_seconds` or
      # `redirects_per_url` was silently ignored. They are resolved with the byte bounds, per Crawl,
      # at the moment of the fetch.
      USER_AGENT = RobotsPolicy::AGENT_TOKEN
      MAX_ATTEMPTS = FetchRetryPolicy::MAX_ATTEMPTS

      # :436 — "has a media type before parameters of `text/html` or `application/xhtml+xml`".
      DOCUMENT_MEDIA_TYPES = %w[text/html application/xhtml+xml].freeze

      # :452's exhaustive vocabulary for one admitted content URL.
      DOCUMENT_CREATED = "document_created"
      CONTENT_ABSENT = "content_absent"
      FETCH_FAILED = "content_fetch_failed"
      POLICY_EXCLUDED = "policy_excluded"
      LIMIT_DISCARDED = "limit_discarded"

      # Reasons, kept as constants because :452 and :456 both read them by name.
      REASONS = {
        gate_deferred: "host_gate_deferred",
        unauthorized: "fetch_not_authorized",
        budget_exhausted: "run_byte_budget_exhausted",
        over_limit: ByteAccounting::OVER_LIMIT,
        unsupported_media: "unsupported_media_type",
        redirect_policy: "redirect_policy_denied",
        redirect_limit: "redirect_limit_exhausted",
        unreachable: "content_unreachable",
        http_error: "content_http_error",
        contended: "attempt_contended",
        attempts_exhausted: "content_fetch_attempts_exhausted",
        # :454 requires "its EXACT limit reason", and F-01 emits one rejection for six distinct
        # conditions. A redirect to `http://` is not an eleventh-redirect limit hit, and :452
        # classifies the two differently, so they carry different reasons.
        redirect_loop: "redirect_loop_detected",
        redirect_target: "redirect_target_invalid",
        guard_error: "redirect_check_unavailable",
        # :442's SECOND HALF — "at 60 elapsed minutes, no new request starts AND INCOMPLETE REQUESTS
        # ARE CANCELED" (DECISIONS ADR-113, FU-34). BOUND TO `Admission::WALL_CLOCK` rather than
        # spelled again: the run's clock ending a request and the run's clock refusing to start one
        # are the same fact, :454 asks for ONE exact limit reason, and two literals would drift.
        wall_clock: Admission::WALL_CLOCK
      }.freeze

      # F-01's rejection reasons, mapped to :454's exact limit reasons. `redirect_budget_exhausted`
      # and `redirect_loop_detected` are LIMIT conditions on this URL; `redirect_target_invalid` is
      # the target failing the platform's own shape checks (non-HTTPS, userinfo, port, malformed).
      PLATFORM_REDIRECT_REASONS = {
        redirect_budget_exhausted: :redirect_limit,
        redirect_loop: :redirect_loop,
        redirect_rejected: :redirect_target
      }.freeze

      Result = Data.define(:outcome, :reason_code, :attempt_id, :http_status, :accounted_bytes,
                           :probe_bytes, :media_type, :body, :final_url, :redirect_count, :retryable) do
        def document? = outcome == DOCUMENT_CREATED
        # :452 — an admitted URL is `covered` only when it creates a valid Document, or returns a
        # terminal 404/410 and creates a valid body-free observation.
        def covered? = [DOCUMENT_CREATED, CONTENT_ABSENT].include?(outcome)
        # :452 — "`content_fetch_failed` ... REMAINS IN THE DENOMINATOR and makes coverage partial".
        def reduces_coverage? = outcome == FETCH_FAILED
        # :452 — robots-disallowed URLs, unsupported media types and redirect targets rejected by
        # current scope are "recorded as `policy_excluded` and are OUTSIDE the denominator".
        def in_denominator? = outcome != POLICY_EXCLUDED
      end

      # WHAT ONE EXECUTION DID (DECISIONS ADR-089, the owner's ruling on FU-19). `retry_after_ms` is
      # :444's delay when another attempt is owed and nil when it is not; `completed_at` is the instant
      # :444 measures that delay FROM, read back from the committed attempt row rather than taken from
      # this worker's clock. `remaining_reserved` is what is still held of the admission's reservation,
      # and nil once nothing is.
      Execution = Data.define(:result, :attempt_number, :completed_at, :remaining_reserved,
                              :retry_after_ms, :performed) do
        def initialize(performed: false, **) = super
        def retry_owed? = !retry_after_ms.nil?
        # DID THIS EXECUTION TERMINALIZE AN ATTEMPT OF ITS OWN? False when the host gate refused, when
        # execution-time authorization refused, and when another delivery had already claimed this attempt
        # number. The caller must not retire the entry, release the reservation or release the depth seal
        # on the strength of a pass that decided NOTHING: under one-attempt-per-execution two deliveries of
        # one action can both be in flight, and the one that made no request was retiring the other one's
        # entry and handing back the other one's reservation mid-fetch. Demonstrated by review, twice.
        def performed? = performed
      end

      # `monotonic` is a seam in the shape `Platform::ScheduledActions::LeaseKeeper` already
      # establishes, and it exists so R3-4's defect can be PROVED without a `sleep`: the wall clock
      # that matters here is elapsed real time, and a test that cannot advance it can only assert the
      # zero case. Production passes the process clock.
      def initialize(outbound: Platform::Outbound, ids: Platform::Ids.system, correlation_id: nil,
                     limit_decisions: nil, monotonic: nil)
        @outbound = outbound
        @ids = ids
        @correlation_id = correlation_id || SecureRandom.uuid_v7
        @limit_decisions = limit_decisions || LimitDecisions.new(ids: @ids, correlation_id: @correlation_id)
        @monotonic = monotonic || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      end

      def monotonic = @monotonic.call

      # PERFORM AT MOST ONE ATTEMPT for this frontier entry, and report whether :444 owes another.
      #
      # ONE EXECUTION IS ONE ATTEMPT (DECISIONS ADR-089, the owner's ruling on FU-19). This method used
      # to run the whole :444 loop in-process, sleeping 30 then 120 seconds between attempts — which made
      # a single pass outlive the transport's 30-second worker lease by six times, so the lease was
      # recovered mid-fetch and the ORDINARY retry path executed twice. The scheduler owns waiting now;
      # the worker owns one bounded attempt. :444's bound and its exact delays are unchanged, and the
      # attempt NUMBER still comes from committed state, so neither a process loss nor a redelivery can
      # reset it.
      #
      # `reserved_bytes`, when present, is what remains of Admission's reservation for this entry —
      # supplied fresh by an admission, or carried forward across a retry from the previous attempt's
      # committed row. It is never re-taken per attempt.
      # `entered_monotonic` is the instant `now` WAS TRUE, supplied by the caller when the caller is the
      # one that observed it. `CrawlDriver#advance` reads its `now` once and then performs the robots
      # fetch and sitemap discovery — both real network calls — BEFORE reaching here, so anchoring at
      # this method's own entry would make that elapsed time invisible and hand the request a budget
      # measured from an instant already minutes in the past (round 4, R4-5). A direct caller that has
      # no earlier instant to offer passes nothing and gets this method's entry, which is correct for it.
      def call(organization_id:, crawl_id:, entry:, gate_id:, now:, reserved_bytes: nil,
               entered_monotonic: nil)
        crawl = load_crawl(organization_id, crawl_id)
        return execution(excluded(REASONS[:unauthorized]), nil, nil, nil) if crawl.nil?

        context = {
          organization_id:, crawl_id:, gate_id:, now:,
          project_id: crawl["project_id"], source_id: entry["source_id"],
          entry_id: entry["id"], canonical_url: entry["canonical_url"],
          canonical_host: host_of(entry["canonical_url"]), depth: entry["depth"].to_i,
          # :442's wall clock, carried to the request itself. See `request_budget`.
          deadline_at: crawl["deadline_at"] && Time.parse(crawl["deadline_at"].to_s).utc,
          # THE INSTANT `now` WAS TRUE, so the request's budget can be computed from the instant the
          # REQUEST starts rather than from the instant the pass was delivered (R3-4). Taken from the
          # CALLER when the caller observed `now` earlier than this method did (R4-5).
          entered_monotonic: entered_monotonic || monotonic
        }
        one_pass(context, entry, reserved_bytes:)
      end

      private

      def one_pass(context, entry, reserved_bytes:)
        number = next_attempt_number(context)
        # :452 — "Exhausted timeout/408/429/5xx ... is `content_fetch_failed`, REMAINS IN THE
        # DENOMINATOR, and makes coverage partial." Returning `policy_excluded` here made a URL that had
        # been fetched three times and failed VANISH from the measure, so a run could report `full`
        # coverage for a URL it never retrieved.
        if number > MAX_ATTEMPTS
          release_and(context, reserved_bytes, nil) if reserved_bytes.to_i.positive?
          return execution(failed(REASONS[:attempts_exhausted]), number - 1, nil, nil)
        end

        # NAMED EXPLICITLY, never `remaining_reserved:`. Ruby hoists the local being assigned on the left of
        # this very statement, so the shorthand would pass nil — silently dropping the carried reservation
        # and taking a SECOND run-wide one. The accepted S-07-012 (1/n) examples caught it.
        last, remaining_reserved, performed = one_attempt(context, entry, number,
                                                          remaining_reserved: reserved_bytes)
        # A PASS THAT PERFORMED NOTHING DECIDES NOTHING. It carries the reservation back untouched and owes
        # no retry: the caller re-enters, and the delivery that IS performing this attempt keeps its claim,
        # its reservation and the depth seal.
        return execution(last, number, nil, remaining_reserved) unless performed

        settled = terminal_attempt(context)

        # :444 gives "one initial attempt plus AT MOST TWO RETRIES", so the third attempt owes no delay:
        # scheduling one would place a re-entry that finds the bound already spent and can only burn
        # 120 s of the 60-minute wall clock ahead of a request that never comes.
        unless last.retryable && number < MAX_ATTEMPTS
          # ":442 — UNUSED BYTES ARE RELEASED." The exhausted path is the one that used to strand them:
          # every retryable settle deliberately KEEPS the reservation, which is right between attempts and
          # wrong at the end. Three timeouts (:452's ordinary `content_fetch_failed`) left the whole
          # reservation held with nothing accounted, permanently — `sweep_expired` cannot reclaim it
          # because `terminalize` nulls the lease the sweep requires — and ~125 such URLs falsely
          # exhausted a run and fired an IMMUTABLE customer-visible hard limit. Found independently by
          # three reviewers. The AMOUNT is belt-and-braces: `release_bytes` floors at
          # `GREATEST(committed_response_bytes, ...)`, so the control is that it releases at all.
          release_and(context, remaining_reserved, nil) if remaining_reserved.to_i.positive?
          return execution(last, number, settled && settled["completed_at"], nil, performed: true)
        end
        execution(last, number, settled && settled["completed_at"], remaining_reserved,
                  FetchRetryPolicy.delay_ms(number, @last_outcome), performed: true)
      end

      def execution(result, number, completed_at, remaining, retry_after_ms = nil, performed: false)
        Execution.new(result:, attempt_number: number, completed_at:, remaining_reserved: remaining,
                      retry_after_ms:, performed:)
      end

      # The row this pass just terminalized, re-read so `completed_at` comes from COMMITTED state. :444
      # measures its delays from "completion of the ... failed attempt", and deriving the retry instant
      # from the row rather than from this worker's clock is what makes two deliveries of one action
      # compute the SAME instant — and therefore the same ScheduledAction identity, which collapses the
      # duplicate instead of durably linking a second retry.
      def terminal_attempt(context)
        attempt_unit(context[:organization_id]) do |store|
          store.latest_attempt(context[:organization_id], context[:crawl_id], context[:entry_id], "content")
        end
      end


      def one_attempt(context, entry, number, remaining_reserved:)
        if !remaining_reserved.nil? && remaining_reserved <= 0
          return [limit_discarded(REASONS[:budget_exhausted]), nil, false]
        end

        claim = claim_slot(context)
        unless claim&.granted?
          result = deferred(claim)
          # A CARRIED RESERVATION IS NOT THIS PASS'S TO HAND BACK. It belongs to the admission that took it,
          # and another delivery of this same action may be spending it right now: releasing it lowered the
          # in-flight winner's headroom and made its `commit_bytes` violate `committed <= reserved`, so a
          # `PG::CheckViolation` escaped the workflow and real bytes that left the platform went unaccounted.
          # Demonstrated by the concurrency lens. A genuinely lost holder is reclaimed by `sweep_expired`.
          return [result, remaining_reserved, false] unless remaining_reserved.nil?

          return [result, nil, false]
        end

        begin
          unless authorized?(context)
            result = excluded(REASONS[:unauthorized])
            return [result, remaining_reserved, false] unless remaining_reserved.nil?

            return [result, nil, false]
          end

          # SEARCH_CRAWL_RETRIEVAL :82 — "the same attempt identity is completed OR TIMED OUT, never
          # replaced by an unaccounted request." Every claim sweeps the run's expired attempt leases
          # first and hands their reservations back, so reclamation needs no separate scheduled job
          # and cannot itself be lost. Without it a lost worker retired 10 MiB of the run's budget
          # permanently and, after three losses, the frontier entry with it.
          reclaim_expired(context)

          # Resolved ONCE per attempt and carried down, so the bound the fetch enforces and the
          # `configured_value` a limit decision records are the same resolution (:390).
          limits = effective_limits(context)
          bounds = limits.byte_bounds
          reserved = remaining_reserved
          reserved ||= reserve_bytes(context, bounds)
          return [limit_discarded(REASONS[:budget_exhausted]), nil, false] if reserved.nil?

          attempt = claim_attempt(context, entry, number, reserved, bounds)
          # A LOST RACE FOR THIS ATTEMPT NUMBER RELEASES NOTHING WHEN THE RESERVATION WAS CARRIED IN.
          #
          # The `ON CONFLICT (crawl_host_gate_id, request_kind, crawl_frontier_entry_id, attempt_number)`
          # absorbs exactly one case, and under one-attempt-per-execution it is the case that matters:
          # two deliveries of the same `crawl_fetch_due` reaching the same attempt number. The winner
          # holds the admission's reservation and is about to spend it, so the loser must not hand it
          # back — `release_bytes` floors at committed bytes, but lowering the winner's headroom mid-flight
          # is how `commit_bytes` comes to violate `committed <= reserved` and raise out of the workflow.
          # A reservation whose holder is genuinely lost is reclaimed by `sweep_expired`, which exists for
          # precisely that. When this call took its OWN reservation there is no other holder, so it
          # releases as before.
          if attempt.nil?
            return [excluded(REASONS[:contended]), remaining_reserved, false] unless remaining_reserved.nil?

            return [release_and(context, reserved, excluded(REASONS[:contended])), nil, false]
          end

          perform(context, attempt, reserved, limits, hold_reservation: !remaining_reserved.nil?)
        ensure
          release_slot(context, claim.lease_token)
        end
      end

      # The network call, and everything that depends on its result. No transaction is open here.
      #
      # The byte commit and the terminal decision are ONE transaction. Splitting them left the run
      # counter advanced and the attempt row blank whenever the second failed, so :442's "run-wide
      # accounted response-body bytes are EXACTLY sum(accounted_response_bytes_i)" was not
      # reproducible from the record and nothing could reconcile the two. They describe the same
      # event; they commit together.
      def perform(context, attempt, reserved, limits, hold_reservation:)
        bounds = limits.byte_bounds
        budget = request_budget(context, bounds)
        outcome = fetch(context, reserved, bounds, budget)
        @last_outcome = outcome
        measurement = measure(outcome, reserved)
        result = classify(outcome, measurement, context, reserved, bounds, budget)
        release_unused = !hold_reservation || !result.retryable
        settle(context, attempt, reserved, result, outcome, measurement, limits, release_unused:)
        remaining_reserved = hold_reservation && result.retryable ? reserved - measurement&.accounted.to_i : nil
        [result, remaining_reserved, true]
      end

      # ---- the fetch -------------------------------------------------------------

      # The redirect guard is :448's "redirects are rechecked against robots and Source Scope Policy
      # BEFORE FOLLOWING", expressed where the connector can act on it. Retrospective validation of
      # the final URL would not satisfy the sentence: the disallowed intermediate would already have
      # been requested, which is both a robots violation and a request the run cannot account for.
      def fetch(context, reserved, bounds, budget)
        # ":442 — At 60 elapsed minutes, NO NEW REQUEST STARTS." Reaching here past the deadline is a
        # race — `CrawlDriver#advance` and `Admission#authorize_run` both refuse first — and the
        # honest answer to a race is not to make the request. No network call, no outbound bytes.
        return Platform::Outbound::Outcome.timeout(canonical_host: context[:canonical_host]) if budget.expired?

        guard = redirect_guard(context)
        @outbound.fetch(context[:canonical_url], timeout_s: budget.seconds, byte_cap: reserved,
                        max_redirects: bounds.max_redirects, user_agent: USER_AGENT,
                        redirect_guard: guard)
      rescue StandardError
        Platform::Outbound::Outcome.failure(:connection_failure, reason: :adapter_error, retryable: true)
      end

      # ":442 — AT 60 ELAPSED MINUTES, NO NEW REQUEST STARTS AND INCOMPLETE REQUESTS ARE CANCELED"
      # (DECISIONS ADR-113, FU-34). Only the first half was implemented, and `Admission`'s own comment
      # said so. The second half is enforced HERE, at the one place the platform can enforce it: the
      # request's own budget.
      #
      # THE REQUEST IS CANCELLED, NOT DISCARDED AFTER THE FACT. F-01's frozen façade takes `timeout_s`
      # and states that "a caller may ask for tighter, never wider", so bounding a request by the run's
      # remaining wall clock needs no change to F-01 and no second way to reach the network. A request
      # that would still be in flight at `deadline_at` is ended AT `deadline_at` — the customer's site
      # is not still being read by a run that is over, and the bytes are never received.
      #
      # AND A REQUEST THAT COMPLETED IS NOT CANCELLED. The clamp only ever shortens; a response that
      # arrives inside the budget is classified exactly as it always was. ":442 — incomplete requests"
      # is a statement about requests still running at the boundary, and `bounded` is what distinguishes
      # a timeout that hit the RUN's clock from one that hit the per-request ceiling — which :452
      # classifies differently, retries differently, and reports to the customer differently.
      WallClockBudget = Data.define(:seconds, :bounded) do
        def bounded? = bounded
        def expired? = bounded && seconds <= 0
      end

      # THE INSTANT THE REQUEST STARTS, WHICH IS NOT THE INSTANT THE PASS ARRIVED (R3-4).
      #
      # `context[:now]` is the pass's DELIVERY instant, fixed once in `call`. By the time the content
      # request is made, the same pass has already fetched robots (a network call) and attempted
      # sitemap discovery (another), and has taken its admission — so real wall-clock time has passed
      # that `now` cannot see. Computing the remaining budget from `now` therefore OVERSTATES it by
      # exactly that much, and the request the deadline was supposed to bound runs past `deadline_at`.
      #
      # Anchored to `now` and advanced by MEASURED elapsed time, which is the same construction
      # `completion_instant` already uses in this file: the durable columns keep recording the
      # ratified instant, and only the budget arithmetic sees the advance. Nothing is falsified —
      # `now` is not overwritten anywhere.
      #
      # Monotonic, never a second `Time.now`: this is a DURATION, and a wall-clock reading that a
      # clock adjustment moved backwards would hand the request a budget larger than the run has.
      def request_start(context)
        context[:now].utc + (monotonic - context[:entered_monotonic])
      end

      def request_budget(context, bounds)
        deadline = context[:deadline_at]
        return WallClockBudget.new(seconds: bounds.timeout_s, bounded: false) if deadline.nil?

        remaining = deadline - request_start(context)
        return WallClockBudget.new(seconds: bounds.timeout_s, bounded: false) if remaining > bounds.timeout_s

        WallClockBudget.new(seconds: remaining, bounded: true)
      end

      # RENEW BETWEEN HOPS (F-04 FU-24), then apply :448's per-hop policy. `Lease.redirect_guard` is the
      # single implementation of the first half — it renews on cadence and refuses the next hop outright
      # after a confirmed transfer — and this composes the authorization decision through it, so the content
      # path, the robots path and the sitemap path share one piece of lease handling rather than three.
      def redirect_guard(context)
        Platform::ScheduledActions::Lease.redirect_guard do |uri|
          in_unit(context[:organization_id]) do |store|
            gate = store.lock_gate(context[:organization_id], context[:gate_id])
            next false if gate.nil?

            FetchAuthorization.new(store).authorize(
              organization_id: context[:organization_id], crawl_id: context[:crawl_id],
              source_id: context[:source_id], canonical_url: uri.to_s, gate:,
              now: context[:now], kind: "content"
            ).allowed?
          end
        rescue StandardError
          # Fail closed — an error deciding whether a hop is permitted is not permission — but
          # RECORD that the guard failed rather than decided, so the outcome is classified as an
          # infrastructure failure inside the coverage denominator rather than as a policy exclusion
          # outside it.
          @guard_failed = true
          false
        end
      end

      # ---- measurement and classification ---------------------------------------

      # Measured against the RESERVATION, not the per-URL ceiling. The body was capped at what was
      # reserved, and :442 says "an attempt cannot add accounted bytes BEYOND ITS RESERVATION" — so
      # a body stopped at reservation+1 is over ITS bound even when that bound is below the per-URL
      # maximum, which happens whenever the run's remaining budget is the tighter of the two.
      def measure(outcome, reserved)
        return nil unless outcome.respond_to?(:response?) && outcome.response?

        ByteAccounting.measure(received: outcome.byte_count, ceiling: reserved)
      end

      # :436's accepted-page definition and :452's exhaustive outcome table, in the order the
      # specification states them — a URL that fails an earlier test never reaches a later one.
      def classify(outcome, measurement, context, reserved, bounds, budget)
        unless outcome.respond_to?(:response?) && outcome.response?
          # THE RUN'S CLOCK ENDED THIS REQUEST, NOT THE SITE (:442, DECISIONS ADR-113). Classified
          # apart from an ordinary timeout because the two are different facts and :452 treats them
          # differently: an exhausted timeout is `content_fetch_failed`, a failure of the URL, and it
          # is RETRYABLE; a request the run's own sixty minutes cancelled is :458's "in-scope candidate
          # NOT EVALUATED because of … wall-clock bound", which is `limit_discarded` carrying "its exact
          # limit reason", in the denominator, and owed no retry — ":442 — stop scheduling affected
          # work." Filing it as `content_fetch_failed` would blame the customer's site for the run's
          # clock and would schedule two more requests a run that is over may not make.
          return limit_discarded(REASONS[:wall_clock], outcome:) if wall_clock_cancelled?(outcome, budget)

          return transport_outcome(outcome)
        end

        status = outcome.status.to_i
        # :452 — "returns terminal 404/410 and creates a valid body-free crawl_observation with
        # reason content_absent" is COVERED, not a failure.
        return absent(outcome) if [404, 410].include?(status)
        return failed(REASONS[:http_error], outcome, retryable: FetchRetryPolicy.retryable?(outcome)) unless (200..299).cover?(status)
        # :442 — "observing a sentinel byte FAILS THAT URL as over-limit". A body at exactly the
        # maximum is fine; one byte past it is not.
        #
        # WHICH bound it exceeded decides the outcome, and the two are genuinely different. Over the
        # PER-URL maximum is a property of the response: :452 makes it `content_fetch_failed`, in
        # the denominator, coverage partial. Over a reservation that was smaller only because the
        # RUN's byte budget was nearly spent is a run-limit hit: :442 says to "stop scheduling
        # affected work" and record the dimension, which is a limit discard, not a failure of this
        # URL. Collapsing them would blame the site for the run's budget.
        if measurement&.over_limit?
          return failed(REASONS[:over_limit], outcome, measurement:) if reserved >= bounds.per_url

          return limit_discarded(REASONS[:budget_exhausted], outcome:, measurement:)
        end

        media = media_type_of(outcome)
        # :452 — "unsupported media types ... are recorded as `policy_excluded` and are OUTSIDE the
        # denominator", which is why this is not a failure.
        unless DOCUMENT_MEDIA_TYPES.include?(media)
          return excluded(REASONS[:unsupported_media], outcome:, measurement:, media:)
        end
        # :436 — the accepted page must also still be in scope at its FINAL url; a redirect that
        # stayed safe and passed every hop guard can still land somewhere current scope excludes.
        return excluded(REASONS[:redirect_policy], outcome:, measurement:, media:) unless final_in_scope?(context, outcome)

        Result.new(outcome: DOCUMENT_CREATED, reason_code: nil, attempt_id: nil, http_status: status,
                   accounted_bytes: measurement&.accounted.to_i, probe_bytes: measurement&.probe_bytes.to_i,
                   media_type: media, body: outcome.body, final_url: outcome.final_url,
                   redirect_count: outcome.redirect_count.to_i, retryable: false)
      end

      # :452 — "Exhausted timeout/408/429/5xx, DNS/TLS/connection failure, other 4xx, redirect-limit
      # exhaustion ... is `content_fetch_failed`". A caller-policy redirect denial is different: the
      # target was excluded by policy, not by failure, so :452 puts it outside the denominator.
      def transport_outcome(outcome)
        if outcome.respond_to?(:rejected?) && outcome.rejected?
          # A hop the CALLER refused is a policy exclusion (:452 puts scope-rejected redirect targets
          # outside the denominator) — but only when the guard actually DECIDED. A guard that could
          # not decide, because the database was unavailable to it, is not a policy fact: recording
          # it as one removes the URL from the coverage measure and makes coverage read better than
          # reality. It is a retryable failure, in the denominator.
          if outcome.reason == :redirect_policy_denied
            return failed(REASONS[:guard_error], outcome, retryable: true) if @guard_failed

            # A HOP REFUSED BECAUSE THE LEASE MOVED IS NOT A POLICY FACT EITHER, and it arrives here
            # wearing the same reason code as one that is. `Lease.redirect_guard` refuses the hop before
            # the authorization limb runs, so `@guard_failed` is false and this URL was being filed as
            # `policy_excluded` — permanently OUTSIDE :452's denominator, on the strength of a decision
            # this delivery had no standing to make. Demonstrated: one committed attempt row,
            # `policy_excluded / redirect_policy_denied / retryable = f`, for a URL nothing had refused.
            # `LeaseKeeper::LOST` is sticky, so asking after the fetch is the same answer the guard got.
            unless Platform::ScheduledActions::Lease.owned?
              return failed(REASONS[:guard_error], outcome, retryable: true)
            end

            return excluded(REASONS[:redirect_policy], outcome:)
          end

          mapped = PLATFORM_REDIRECT_REASONS[outcome.reason]
          return failed(REASONS.fetch(mapped), outcome) if mapped

          return failed(outcome.reason.to_s, outcome)
        end

        failed(REASONS[:unreachable], outcome, retryable: FetchRetryPolicy.retryable?(outcome))
      end

      # A timeout under a budget the RUN's wall clock tightened. Both conjuncts are load-bearing: a
      # timeout under the ordinary per-request ceiling is :452's `content_fetch_failed` and stays one,
      # and a response that arrived inside a tightened budget completed and is not cancelled.
      def wall_clock_cancelled?(outcome, budget)
        budget.bounded? && outcome.respond_to?(:kind) && outcome.kind == :timeout
      end

      def absent(outcome)
        Result.new(outcome: CONTENT_ABSENT, reason_code: CONTENT_ABSENT, attempt_id: nil,
                   http_status: outcome.status.to_i, accounted_bytes: 0, probe_bytes: 0,
                   media_type: nil, body: nil, final_url: outcome.final_url,
                   redirect_count: outcome.redirect_count.to_i, retryable: false)
      end

      def failed(reason, outcome = nil, retryable: false, measurement: nil)
        build(FETCH_FAILED, reason, outcome, measurement, retryable:)
      end

      def excluded(reason, outcome: nil, measurement: nil, media: nil)
        build(POLICY_EXCLUDED, reason, outcome, measurement, media:)
      end

      def limit_discarded(reason, outcome: nil, measurement: nil, media: nil)
        build(LIMIT_DISCARDED, reason, outcome, measurement, media:)
      end

      def build(outcome_name, reason, outcome, measurement, retryable: false, media: nil)
        Result.new(outcome: outcome_name, reason_code: reason, attempt_id: nil,
                   http_status: outcome&.status&.to_i, accounted_bytes: measurement&.accounted.to_i,
                   probe_bytes: measurement&.probe_bytes.to_i, media_type: media, body: nil,
                   final_url: outcome&.final_url, redirect_count: outcome&.redirect_count.to_i,
                   retryable:)
      end

      def deferred(claim)
        Result.new(outcome: LIMIT_DISCARDED, reason_code: REASONS[:gate_deferred], attempt_id: nil,
                   http_status: nil, accounted_bytes: 0, probe_bytes: 0, media_type: nil, body: nil,
                   final_url: nil, redirect_count: 0, retryable: false)
      end

      def media_type_of(outcome)
        headers = outcome.headers
        return nil unless headers.is_a?(::Hash)

        raw = headers.find { |k, _v| k.to_s.downcase == "content-type" }&.last
        raw.to_s.split(";").first.to_s.strip.downcase.presence
      end

      # The canonical parser, not a second one. A naive `URI.parse(...).host` DIVERGES from
      # `FetchAuthorization`'s — it keeps userinfo, mishandles IPv6 brackets and raises on inputs the
      # careful one absorbs — and the value it produced was written into the IMMUTABLE
      # `fetch_attempts.canonical_host`. Two host parsers in one workflow is one too many.
      def host_of(url) = FetchAuthorization.host_of(url)

      # ---- transactions ----------------------------------------------------------

      def in_unit(organization_id)
        Platform::UnitOfWork.run do |conn|
          raw = conn.raw_connection
          store = IdentityAccess::Infrastructure::CrawlHostGateStore.new(raw)
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          yield store, raw
        end
      end

      def budget_unit(organization_id)
        Platform::UnitOfWork.run do |conn|
          store = IdentityAccess::Infrastructure::CrawlBudgetStore.new(conn.raw_connection)
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          yield store
        end
      end

      def attempt_unit(organization_id)
        Platform::UnitOfWork.run do |conn|
          store = IdentityAccess::Infrastructure::FetchAttemptStore.new(conn.raw_connection)
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          yield store
        end
      end

      def load_crawl(organization_id, crawl_id)
        in_unit(organization_id) { |store| store.crawl(organization_id, crawl_id) }
      end

      def claim_slot(context)
        in_unit(context[:organization_id]) do |store|
          HostGate.new(store, ids: @ids, correlation_id: @correlation_id)
                  .claim(organization_id: context[:organization_id], gate_id: context[:gate_id],
                         now: context[:now], kind: "content")
        end
      end

      def release_slot(context, lease_token)
        in_unit(context[:organization_id]) { |store| store.release_slot(context[:gate_id], lease_token, context[:now]) }
      end

      def authorized?(context)
        in_unit(context[:organization_id]) do |store|
          gate = store.lock_gate(context[:organization_id], context[:gate_id])
          FetchAuthorization.new(store).authorize(
            organization_id: context[:organization_id], crawl_id: context[:crawl_id],
            source_id: context[:source_id], canonical_url: context[:canonical_url], gate:,
            now: context[:now], kind: "content"
          ).allowed?
        end
      end

      def final_in_scope?(context, outcome)
        final = outcome.final_url
        return true if final.nil? || final == context[:canonical_url]

        in_unit(context[:organization_id]) do |store|
          gate = store.lock_gate(context[:organization_id], context[:gate_id])
          next false if gate.nil?

          FetchAuthorization.new(store).authorize(
            organization_id: context[:organization_id], crawl_id: context[:crawl_id],
            source_id: context[:source_id], canonical_url: final, gate:,
            now: context[:now], kind: "content"
          ).allowed?
        end
      end

      # :390 — the operative bounds are the most restrictive of global safety and every active
      # Organization/Project policy, resolved HERE rather than carried from queue time.
      def effective_bounds(context) = effective_limits(context).byte_bounds

      def effective_limits(context)
        rows = in_unit(context[:organization_id]) do |store|
          store.active_crawl_policies(context[:organization_id], context[:project_id])
        end
        EffectiveLimits.resolve(rows)
      end

      # ---- honest boundaries -----------------------------------------------------
      #
      # `document_created` names the outcome :436 defines — a 2xx, within the response maximum, of a
      # Document media type, in scope at its final URL. IT DOES NOT CREATE A DOCUMENT: `documents`
      # and the ingestion transaction are S-07-010's, and this tranche must not pretend otherwise.
      # `covered?` is therefore CANDIDATE coverage — the fetch did everything :452 asks of it — and
      # S-07-009 confirms it against the artifact before computing `coverage_status`.

      # :442 — reserve BEFORE the body is read, sized from what the run has left, only when the
      # caller has not already supplied Admission's reservation for this entry. A shrinking
      # reservation is retried down to nothing rather than abandoned on the first loss, because
      # another worker committing between the read and the write is normal, not exceptional.
      # RETURNS THE RESERVED AMOUNT, OR NIL. The `nil` is load-bearing and was the tranche's worst
      # defect: `Integer#times` returns its RECEIVER when no `break` fires, so three consecutive lost
      # races returned the integer 3 — truthy — and the caller's `if reserved.nil?` never fired. The
      # run then made a real request with `byte_cap: 3` holding NO reservation, and `commit_bytes`
      # violated `committed <= reserved` so a `PG::CheckViolation` escaped the workflow. Reviewed at
      # 0/120 reproductions on a loopback database and 120/120 with 5 ms of added latency — the local
      # suite could not have seen it, which is why the loop now says what it means.
      RESERVE_ATTEMPTS = 3

      def reserve_bytes(context, bounds)
        budget_unit(context[:organization_id]) do |store|
          ensure_counters(store, context)
          reserved = nil
          RESERVE_ATTEMPTS.times do
            row = store.counters(context[:organization_id], context[:crawl_id])
            remaining = bounds.per_run - row["reserved_response_bytes"].to_i
            want = ByteAccounting.reservation(remaining:, per_url: bounds.per_url)
            break if want.zero?

            if store.reserve_bytes(context[:organization_id], context[:crawl_id], want,
                                   bounds.per_run, context[:now])
              reserved = want
              break
            end
          end
          reserved
        end
      end

      def ensure_counters(store, context)
        store.ensure_counters(id: @ids.generate, now: context[:now], correlation_id: @correlation_id,
                              organization_id: context[:organization_id], project_id: context[:project_id],
                              crawl_id: context[:crawl_id])
      end

      # One transaction: the run counter and the attempt record describe the same event, so they
      # commit together or neither does.
      def settle(context, attempt, reserved, result, outcome, measurement, limits, release_unused:)
        Platform::UnitOfWork.run do |conn|
          raw = conn.raw_connection
          budget = IdentityAccess::Infrastructure::CrawlBudgetStore.new(raw)
          budget.enter_org_context(org: context[:organization_id], correlation_id: @correlation_id)
          budget.commit_bytes(context[:organization_id], context[:crawl_id],
                              { reserved:, accounted: measurement&.accounted.to_i,
                                probe_bytes: measurement&.probe_bytes.to_i,
                                received: measurement&.received.to_i,
                                expanded: measurement&.expanded.to_i }, context[:now],
                             release_unused:)
          budget.count_redirects(context[:organization_id], context[:crawl_id],
                                 result.redirect_count.to_i, context[:now])

          attempts = IdentityAccess::Infrastructure::FetchAttemptStore.new(raw)
          moved = attempts.terminalize(attempt["id"], attempt["checkpoint_version"].to_i, context[:now],
                                       outcome: result.outcome, reason_code: result.reason_code,
                                       http_status: result.http_status,
                                       accounted_response_bytes: measurement&.accounted,
                                       received_body_bytes: measurement&.received,
                                       expanded_body_bytes: measurement&.expanded,
                                       limit_probe_bytes: measurement&.probe_bytes.to_i,
                                       media_type: result.media_type,
                                       redirect_count: result.redirect_count,
                                       final_url: result.final_url,
                                       body_sha256: result.body && Digest::SHA256.digest(result.body),
                                       retryable: result.retryable,
                                       latency_ms: outcome.respond_to?(:latency_ms) ? outcome.latency_ms : nil,
                                       # THE ATTEMPT'S OWN COMPLETION, not the pass's start instant. Every
                                       # other timestamp in this workflow is stamped from the injected clock
                                       # captured before the pass began, which was harmless while nothing
                                       # read `completed_at` — and wrong the moment :444's retry instant was
                                       # measured from it, because a hard-timeout attempt then came due up to
                                       # a full request timeout EARLY. :444 says "completion of the failed
                                       # attempt", so the recorded latency is added to make the column mean
                                       # what its name says. Still derived from committed inputs, so two
                                       # deliveries computing the retry instant still agree.
                                       completed_at: completion_instant(context, outcome, limits.byte_bounds))
          raise Platform::InvariantViolation, "fetch attempt terminal decision lost" if moved.to_i.zero?

          # The per-URL bounds are observed on the SAME transaction as the attempt they describe.
          observe_fetch_limits(raw, context, attempt, result, outcome, measurement, limits)
        end
      end

      # WHEN THE ATTEMPT ACTUALLY FINISHED, which is what :444 measures its retry delays from.
      #
      # Every other timestamp in this workflow is stamped from the injected clock captured before the pass
      # began. That was harmless while nothing read `completed_at`, and wrong the moment a persisted `due_at`
      # was derived from it: the retry came due up to a full request timeout EARLY.
      #
      # A TIMED-OUT ATTEMPT RAN TO THE HARD BOUND BY DEFINITION — the rule `observe_request_time` already
      # states for the same reason — and it reports no latency, so the bound is the honest measure. Every
      # other outcome reports the latency it took. Both are derived from committed inputs, so two parties
      # computing the retry instant from the stored row still agree.
      def completion_instant(context, outcome, bounds)
        elapsed =
          if outcome.respond_to?(:kind) && outcome.kind == :timeout
            bounds.timeout_s
          else
            (outcome.respond_to?(:latency_ms) ? outcome.latency_ms.to_i : 0) / 1000.0
          end
        context[:now] + elapsed
      end

      # The three per-fetch dimensions of the ratified twelve (:425-438).
      BODY_DIMENSION = "response_body_per_url"
      REQUEST_TIME_DIMENSION = "connection_plus_response_time_per_request"
      REDIRECTS_DIMENSION = "redirects_per_url"

      # WHY THESE ARE ONCE PER RUN AND NOT ONCE PER URL. :442 says `CrawlLimitReached` fires
      # "exactly once per dimension and run", and these are per-URL BOUNDS observed run-wide: the
      # hundredth oversized body on a run is the same fact as the first, and the decision table's
      # unique key says so without this code counting anything.
      #
      # The affected counts are 1 and 1 because a per-URL bound costs exactly the URL that hit it —
      # unlike a run-wide bound, which abandons everything still queued.
      def observe_fetch_limits(pg, context, attempt, result, outcome, measurement, limits)
        observer = @limit_decisions.for(pg, organization_id: context[:organization_id],
                                        project_id: context[:project_id],
                                        crawl_id: context[:crawl_id], limits:)
        one = LimitDecisions::Affected.new(sources: 1, urls: 1)
        now = context[:now]

        observe_body(observer, result, measurement, one, now)
        observe_request_time(observer, attempt, outcome, one, now)
        observe_redirects(observer, result, one, now)
      end

      # AN OBSERVATION IS NOT A DISPOSITION. Each soft limb below is independent of its hard limb:
      # a run that crosses the hard bound genuinely reached the soft value on the way past it, and
      # because the decision is once-per-run, gating soft behind `elsif` lost the soft event
      # permanently for any run whose only crossing was the hard one. The frontier learned this
      # first; these four are the same rule applied where it was still missing.
      def observe_body(observer, result, measurement, one, now)
        return if measurement.nil?

        observer.soft(BODY_DIMENSION, measurement.accounted, now:) if
          measurement.accounted >= observer.soft_bound(BODY_DIMENSION)
        return unless result.reason_code == ByteAccounting::OVER_LIMIT

        # The exact size is UNKNOWABLE: the reader stopped one sentinel byte past the maximum and
        # never retained it (:442 "never parsed or retained"). :442 allows one sentinel PER
        # ACCOUNTING PATH, so a two-path response could observe `ceiling + 2` — but no single path
        # measured that, and the recorded value must be one a path actually saw.
        observer.hard(BODY_DIMENSION, measurement.accounted + 1, now:, affected: one)
      end

      # ONE TIMED-OUT ATTEMPT IS NOT A LIMIT HIT. :444 gives a timeout "one initial attempt plus at
      # most two retries", and :452 makes only the EXHAUSTED case `content_fetch_failed`. Firing per
      # attempt meant the first transient timeout in any run wrote a permanent
      # `CrawlLimitReached` — so a run that retried once, succeeded, and evaluated every candidate
      # was still labelled `limit_reached` with partial coverage by the terminal checkpoint.
      def observe_request_time(observer, attempt, outcome, one, now)
        hard = observer.hard_bound(REQUEST_TIME_DIMENSION)
        timed_out = outcome.respond_to?(:kind) && outcome.kind == :timeout
        # A timed-out attempt ran to the hard bound by definition, so it crossed the soft bound
        # whatever happens to the retry. Measured latency carries the ordinary case.
        seconds = timed_out ? hard : (outcome.respond_to?(:latency_ms) ? outcome.latency_ms.to_i : 0) / 1000
        observer.soft(REQUEST_TIME_DIMENSION, seconds, now:) if
          seconds >= observer.soft_bound(REQUEST_TIME_DIMENSION)

        # ONE TIMED-OUT ATTEMPT IS NOT A LIMIT HIT. :444 gives a timeout "one initial attempt plus at
        # most two retries", and :452 makes only the EXHAUSTED case `content_fetch_failed`.
        return unless timed_out && attempt["attempt_number"].to_i >= MAX_ATTEMPTS

        observer.hard(REQUEST_TIME_DIMENSION, hard, now:, affected: one)
      end

      def observe_redirects(observer, result, one, now)
        exhausted = result.reason_code == REASONS[:redirect_limit]
        followed = exhausted ? observer.hard_bound(REDIRECTS_DIMENSION) + 1 : result.redirect_count.to_i
        observer.soft(REDIRECTS_DIMENSION, followed, now:) if
          followed >= observer.soft_bound(REDIRECTS_DIMENSION)
        return unless exhausted

        observer.hard(REDIRECTS_DIMENSION, followed, now:, affected: one)
      end

      # Reclaim the run's expired attempt leases and hand their reservations back. Every claim does
      # this, so reclamation cannot itself be lost — the same construction the host gate uses.
      def reclaim_expired(context)
        Platform::UnitOfWork.run do |conn|
          raw = conn.raw_connection
          attempts = IdentityAccess::Infrastructure::FetchAttemptStore.new(raw)
          attempts.enter_org_context(org: context[:organization_id], correlation_id: @correlation_id)
          expired = attempts.sweep_expired(context[:organization_id], context[:crawl_id], context[:now])
          next 0 if expired.empty?

          budget = IdentityAccess::Infrastructure::CrawlBudgetStore.new(raw)
          expired.each do |row|
            budget.release_bytes(context[:organization_id], context[:crawl_id],
                                 row["reserved_bytes"].to_i, context[:now])
          end
          expired.size
        end
      end

      def release_and(context, reserved, result)
        budget_unit(context[:organization_id]) do |store|
          store.release_bytes(context[:organization_id], context[:crawl_id], reserved, context[:now])
        end
        result
      end

      def next_attempt_number(context)
        attempt_unit(context[:organization_id]) do |store|
          store.attempt_count(context[:organization_id], context[:crawl_id], context[:entry_id], "content") + 1
        end
      end

      def claim_attempt(context, entry, number, reserved, bounds)
        attempt_unit(context[:organization_id]) do |store|
          store.claim(id: @ids.generate, now: context[:now], correlation_id: @correlation_id,
                      causation_id: context[:crawl_id], organization_id: context[:organization_id],
                      project_id: context[:project_id], crawl_id: context[:crawl_id],
                      crawl_host_gate_id: context[:gate_id], source_id: context[:source_id],
                      frontier_entry_id: context[:entry_id], kind: "content", attempt_number: number,
                      canonical_url: context[:canonical_url], canonical_host: context[:canonical_host],
                      depth: context[:depth],
                      # :456's ordering tuple, materialized so the S-07-008 coordinator can apply
                      # budget effects "in increasing dequeue key" without re-deriving it.
                      dequeue_key: entry["dequeue_key"] && unhex(entry["dequeue_key"]),
                      scope_policy_id: entry["scope_policy_id"],
                      scope_policy_version: entry["scope_policy_version"],
                      crawl_policy_id: context[:crawl_policy_id],
                      crawl_policy_version: context[:crawl_policy_version],
                      reserved_bytes: reserved, claim_owner: @ids.generate,
                      # The attempt's own deadline: the per-request bound this Crawl is subject to.
                      deadline_at: context[:now] + bounds.timeout_s)
        end
      end

      def unhex(value) = value.to_s.sub(/\A\\x/, "").then { |h| [h].pack("H*") }
    end
  end
end
