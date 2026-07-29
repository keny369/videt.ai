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

      def initialize(ids: Platform::Ids.system, correlation_id: nil)
        @ids = ids
        @correlation_id = correlation_id || SecureRandom.uuid_v7
      end

      # Claim the next frontier entry AND its byte reservation, atomically and in dequeue order.
      def claim_next(organization_id:, crawl_id:, now:)
        Platform::UnitOfWork.run do |conn|
          raw = conn.raw_connection
          gates = IdentityAccess::Infrastructure::CrawlHostGateStore.new(raw)
          gates.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          crawl = gates.crawl(organization_id, crawl_id)
          next idle if crawl.nil?

          # :442 — "At 60 elapsed minutes, no new request starts." Checked BEFORE the entry is
          # claimed, so an expired run does not take work out of the frontier only to refuse it.
          next limited(WALL_CLOCK) if expired?(gates, crawl, crawl_id, now)

          frontier = IdentityAccess::Infrastructure::CrawlFrontierStore.new(raw)
          # The same advisory lock the dequeue already takes. Holding it across the reservation is
          # what makes admission order equal dequeue order.
          frontier.lock_frontier(crawl_id)
          entry = frontier.claim_next(organization_id, crawl_id, now)
          next idle if entry.nil?

          reserve(raw, organization_id, crawl, crawl_id, entry, now)
        end
      end

      private

      def idle = Decision.new(entry: nil, reserved_bytes: nil, reserved_total: nil, reason_code: nil)

      def limited(reason, entry: nil)
        Decision.new(entry:, reserved_bytes: nil, reserved_total: nil, reason_code: reason)
      end

      def reserve(raw, organization_id, crawl, crawl_id, entry, now)
        bounds = effective_bounds(raw, organization_id, crawl["project_id"])
        budget = IdentityAccess::Infrastructure::CrawlBudgetStore.new(raw)
        budget.ensure_counters(id: @ids.generate, now:, correlation_id: @correlation_id,
                               organization_id:, project_id: crawl["project_id"], crawl_id:)
        row = budget.counters(organization_id, crawl_id)
        remaining = bounds.per_run - row["reserved_response_bytes"].to_i
        want = ByteAccounting.reservation(remaining:, per_url: bounds.per_url)
        return limited(EXHAUSTED, entry:) if want.zero?

        granted = budget.reserve_bytes(organization_id, crawl_id, want, bounds.per_run, now)
        # Under the frontier lock no other admission can be in flight for this Crawl, so a refusal
        # here means the budget genuinely moved (a concurrent COMMIT), not that a race was lost.
        return limited(EXHAUSTED, entry:) if granted.nil?

        Decision.new(entry:, reserved_bytes: want,
                     reserved_total: granted["reserved_response_bytes"].to_i, reason_code: nil)
      end

      # :442 — "Wall-clock duration starts at the atomic `Crawl.Queued -> Crawl.Running` transition."
      # `crawls.deadline_at` is written by StartCrawl from that instant, so it is the authority
      # rather than a duration recomputed here.
      def expired?(_gates, crawl, _crawl_id, now)
        deadline = crawl["deadline_at"]
        return false if deadline.nil?

        Time.parse(deadline.to_s).utc <= now.utc
      end

      def effective_bounds(raw, organization_id, project_id)
        gates = IdentityAccess::Infrastructure::CrawlHostGateStore.new(raw)
        rows = gates.active_crawl_policies(organization_id, project_id)
        sets = rows.map { |r| JSON.parse(r["normalized_bounds"]) }.select { |s| CrawlPolicy.complete?(s) }
        ByteAccounting.bounds_from(CrawlPolicy.most_restrictive(CrawlPolicy::GLOBAL_CEILING, *sets))
      rescue JSON::ParserError, KeyError
        ByteAccounting::GLOBAL_BOUNDS
      end
    end
  end
end
