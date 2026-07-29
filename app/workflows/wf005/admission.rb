# frozen_string_literal: true

require "securerandom"

module Workflows
  module Wf005
    # The scheduler's admission step (S-07-008; WORKFLOW_SPECIFICATIONS.md :442/:456).
    #
    # WHY CLAIMING AND RESERVING ARE ONE TRANSACTION. :442 says "THE SCHEDULER reserves up to the
    # per-URL maximum from the remaining run-wide budget IN THAT ORDER", and :456 says "All run-wide
    # byte, page, and queue admission accounting is also applied IN DEQUEUE SEQUENCE" and, above it,
    # "Selection under every finite bound is DETERMINISTIC."
    #
    # S-07-007 claimed the entry in one transaction and reserved in another. The sum bound held, but
    # the ORDER did not: two workers claiming adjacent entries could reserve in either order, so
    # which URL received the last of the run's budget depended on thread scheduling. The ADR-026
    # contract lens demonstrated it — five workers, 25 MiB bound, a different pair granted each run.
    #
    # Joining them under the frontier's own advisory lock fixes it at the root rather than repairing
    # it afterwards: the lock already serialises dequeue, so a reservation taken inside it is taken
    # in dequeue order by construction. There is no coordinator to fall behind and no pending queue
    # to drain, because the decision that needs ordering — ADMISSION — is made where the order
    # already exists.
    #
    # (The `fetched_pending_commit` machinery :456 also describes is about committing DISCOVERIES in
    # dequeue order — the outgoing links of a fetched document. Link extraction is S-07-010's, so
    # that limb belongs with it; this class deliberately does not pre-empt it.)
    #
    # THE WALL CLOCK LIVES HERE TOO, because :442 states it as an admission rule: "At 60 elapsed
    # minutes, NO NEW REQUEST STARTS and incomplete requests are canceled." The first half is a
    # decision about whether to hand a worker any work at all, which is exactly this decision.
    class Admission
      # What the scheduler decided. `entry` is nil when there is nothing to admit; `reserved_bytes`
      # is nil when there was work but the run cannot pay for it.
      Decision = Data.define(:entry, :reserved_bytes, :reserved_total, :reason_code) do
        def admitted? = !entry.nil? && !reserved_bytes.nil?
        def idle? = entry.nil? && reason_code.nil?
        def limited? = !reason_code.nil?
      end

      EXHAUSTED = "run_byte_budget_exhausted"
      WALL_CLOCK = "wall_clock_exhausted"

      # The two dimensions this class is the observation point for. Everything else is observed
      # where it happens — per-URL bytes and request time at the fetch, rate and concurrency at the
      # host gate, queue and depth at the frontier, sitemaps at discovery.
      BYTES = "accounted_response_body_bytes_per_run"
      WALL_CLOCK_DIMENSION = "wall_clock_run_duration"

      def initialize(ids: Platform::Ids.system, correlation_id: nil, limit_decisions: nil)
        @ids = ids
        @correlation_id = correlation_id || SecureRandom.uuid_v7
        @limits = limit_decisions || LimitDecisions.new(ids: @ids, correlation_id: @correlation_id)
      end

      # Claim the next frontier entry AND its byte reservation, atomically and in dequeue order.
      def claim_next(organization_id:, crawl_id:, now:)
        Platform::UnitOfWork.run do |conn|
          raw = conn.raw_connection
          gates = IdentityAccess::Infrastructure::CrawlHostGateStore.new(raw)
          gates.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          crawl = gates.crawl(organization_id, crawl_id)
          next idle if crawl.nil?

          bounds = EffectiveLimits.resolve(gates.active_crawl_policies(organization_id, crawl["project_id"]))

          # :442 — "At 60 elapsed minutes, no new request starts." Checked BEFORE the entry is
          # claimed, so an expired run does not take work out of the frontier only to refuse it.
          next limited(WALL_CLOCK) if wall_clock(raw, organization_id, crawl, crawl_id, bounds, now)

          frontier = IdentityAccess::Infrastructure::CrawlFrontierStore.new(raw)
          # The same advisory lock the dequeue already takes. Holding it across the reservation is
          # what makes admission order equal dequeue order.
          frontier.lock_frontier(crawl_id)
          entry = frontier.claim_next(organization_id, crawl_id, now)
          next idle if entry.nil?

          reserve(raw, organization_id, crawl, crawl_id, entry, bounds, now)
        end
      end

      private

      def idle = Decision.new(entry: nil, reserved_bytes: nil, reserved_total: nil, reason_code: nil)

      def limited(reason, entry: nil)
        Decision.new(entry:, reserved_bytes: nil, reserved_total: nil, reason_code: reason)
      end

      def reserve(raw, organization_id, crawl, crawl_id, entry, limits, now)
        bounds = limits.byte_bounds
        budget = IdentityAccess::Infrastructure::CrawlBudgetStore.new(raw)
        budget.ensure_counters(id: @ids.generate, now:, correlation_id: @correlation_id,
                               organization_id:, project_id: crawl["project_id"], crawl_id:)
        row = budget.counters(organization_id, crawl_id)
        remaining = bounds.per_run - row["reserved_response_bytes"].to_i
        want = ByteAccounting.reservation(remaining:, per_url: bounds.per_url)
        return exhausted(raw, organization_id, crawl, crawl_id, entry, limits, row, now) if want.zero?

        granted = budget.reserve_bytes(organization_id, crawl_id, want, bounds.per_run, now)
        # Under the frontier lock no other admission can be in flight for this Crawl, so a refusal
        # here means the budget genuinely moved (a concurrent COMMIT), not that a race was lost.
        return exhausted(raw, organization_id, crawl, crawl_id, entry, limits, row, now) if granted.nil?

        # ":442 — a soft event fires when the observed OR RESERVED value first equals the soft
        # limit." The reserved peak is what the statement just produced: a peak that is later
        # released is invisible in the stored row but visible here, to the caller that caused it.
        peak = granted["reserved_response_bytes"].to_i
        observe(raw, organization_id, crawl, crawl_id, BYTES, LimitDimensions::SOFT, peak, limits, now) if peak >= bounds.per_run_target

        Decision.new(entry:, reserved_bytes: want, reserved_total: peak, reason_code: nil)
      end

      # ":442 — a capacity hard-limit event fires BEFORE an action would exceed the maximum; the
      # exceeding page, URL, or accounted bytes are not accepted." The entry is returned to the
      # caller unreserved, so nothing is fetched on a budget the run does not have.
      def exhausted(raw, organization_id, crawl, crawl_id, entry, limits, row, now)
        observe(raw, organization_id, crawl, crawl_id, BYTES, LimitDimensions::HARD,
                row["reserved_response_bytes"].to_i, limits, now)
        limited(EXHAUSTED, entry:)
      end

      # :442 — "Wall-clock duration starts at the atomic `Crawl.Queued -> Crawl.Running`
      # transition." `crawls.deadline_at` is written by StartCrawl from that instant, so it is the
      # authority rather than a duration recomputed here. The SOFT crossing has no deadline column
      # of its own and is measured from `started_at` against the resolved soft bound, which is the
      # same instant read a different way.
      def wall_clock(raw, organization_id, crawl, crawl_id, limits, now)
        elapsed = elapsed_minutes(crawl, now)
        deadline = crawl["deadline_at"]
        expired = !deadline.nil? && Time.parse(deadline.to_s).utc <= now.utc

        threshold = if expired
                      LimitDimensions::HARD
                    elsif elapsed && elapsed >= limits.configured(WALL_CLOCK_DIMENSION, LimitDimensions::SOFT)
                      LimitDimensions::SOFT
                    end
        observe(raw, organization_id, crawl, crawl_id, WALL_CLOCK_DIMENSION, threshold, elapsed.to_i, limits, now) if threshold
        expired
      end

      def elapsed_minutes(crawl, now)
        started = crawl["started_at"]
        return nil if started.nil?

        ((now.utc - Time.parse(started.to_s).utc) / 60).floor
      end

      def observe(raw, organization_id, crawl, crawl_id, dimension, threshold, observed, limits, now)
        @limits.observe(raw, organization_id:, project_id: crawl["project_id"],
                        crawl_id:, dimension:, threshold:, observed:, limits:, now:)
      end
    end
  end
end
