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
      # The compare-and-update lost to another writer of the byte counter rather than the run
      # having no budget. A DIFFERENT outcome, and deliberately not a limit: the caller should come
      # back, and no customer is told a limit was reached.
      CONTENDED = "run_byte_budget_contended"
      # The admission-safe subset of `FetchAuthorization`'s execution-time gate, in its order.
      DENIALS = {
        organization: "admission_organization_inactive",
        crawl: "admission_crawl_not_running",
        project: "admission_project_not_active",
        entitlement: "admission_entitlement_not_executing"
      }.freeze

      # The same bound `FetchContent` uses. Another worker committing between the read and the
      # write is normal on this counter, not exceptional.
      RESERVE_ATTEMPTS = 3

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
        claim(organization_id:, crawl_id:, now:, only: nil)
      end

      # THE RUN-SCOPED LIMBS OF THE EXECUTION-TIME GATE, WITHOUT CLAIMING ANYTHING (S-07-012 repair).
      #
      # MTX-030: "an authorization ... established at queue time is never trusted at execution time."
      # The run driver's FIRST EFFECTS are a `crawl_host_gates` insert, a robots request and a
      # write-once sitemap outcome, and all three used to happen before `claim_entry` reached this gate.
      # Proved, not supposed: with the Organization suspended, and again with the entitlement
      # reservation's lease expired, a pass sent `/robots.txt` to the customer's host and then wrote
      # `sitemap_unavailable` — which is write-once, so :450/:452 made that Source root's coverage
      # permanently partial on the strength of OUR authorization failure rather than anything about the
      # host. That is the exact harm this subsystem's own `release_sitemaps` reasoning forbids.
      #
      # Exposed here so the driver can refuse BEFORE its first effect. It writes nothing, takes no lock
      # and peeks nothing, so refusing costs one short read transaction. `claim_entry` keeps its own call
      # as defence in depth, and both go through the SAME private predicate: one implementation, refusing
      # in :541's order, so the two surfaces can never drift apart.
      def authorize_run(organization_id:, crawl:, now:)
        Platform::UnitOfWork.run do |conn|
          gates = IdentityAccess::Infrastructure::CrawlHostGateStore.new(conn.raw_connection)
          gates.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          authorize(gates, organization_id, crawl, now)
        end
      end

      # Claim EXACTLY the named frontier entry, and only while it is still the next one (S-07-012).
      #
      # A `crawl_fetch_due` action names the entry it was scheduled for, and :185 makes `target_id`
      # the claim owner, so the execution must claim THAT entry or nothing. Claiming whatever happens
      # to be next instead would break two things at once: the ledger would attribute an execution,
      # audit record and result to an entry it did not act on, and a redelivered action whose original
      # claim survived a lost worker would fetch a SECOND, unrelated URL under the first one's
      # identity. Declining is always safe — the caller's next-frontier link then targets whatever is
      # genuinely next, so the run advances rather than repeating.
      #
      # DEQUEUE ORDER IS UNCHANGED, because the test is `peek_next == named`: the entry is claimed only
      # when it IS the frontier's next candidate under the same advisory lock, never out of turn.
      def claim_entry(organization_id:, crawl_id:, entry_id:, now:)
        claim(organization_id:, crawl_id:, now:, only: entry_id)
      end

      private

      def claim(organization_id:, crawl_id:, now:, only:)
        Platform::UnitOfWork.run do |conn|
          raw = conn.raw_connection
          gates = IdentityAccess::Infrastructure::CrawlHostGateStore.new(raw)
          gates.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          crawl = gates.crawl(organization_id, crawl_id)
          next idle if crawl.nil?

          # EXECUTION-TIME AUTHORIZATION, BEFORE ANY EFFECT.
          #
          # Admission reserves run-wide byte budget, claims a frontier entry, and can write an
          # IMMUTABLE limit decision with a customer-visible `CrawlLimitReached`. All three are
          # effects, so they need the same execution-time authority `FetchAuthorization` requires
          # before bytes leave — checking only "does the Crawl exist" meant a suspended tenant, an
          # inactive Project or an unmetered run still got budget reserved and a permanent event
          # written. Nothing cascades a suspension to `crawls.state`, so the Crawl limb alone does
          # not cover it.
          #
          # This is the ADMISSION-SAFE SUBSET of that gate, deliberately not the whole of it: the
          # Source and Source-Scope limbs are PER-URL and belong at the fetch, where the URL is
          # known and where the frontier's own dequeue already re-checks the Source. Every limb here
          # is run-scoped, and every one denies BEFORE the peek, the reservation, the claim and any
          # observation.
          denial = authorize(gates, organization_id, crawl, now)
          next limited(denial) if denial

          bounds = EffectiveLimits.resolve(gates.active_crawl_policies(organization_id, crawl["project_id"]))

          # :442 — "At 60 elapsed minutes, no new request starts." Checked BEFORE the entry is
          # claimed, so an expired run does not take work out of the frontier only to refuse it.
          next limited(WALL_CLOCK) if wall_clock(raw, organization_id, crawl, crawl_id, bounds, now)

          frontier = IdentityAccess::Infrastructure::CrawlFrontierStore.new(raw)
          # The same advisory lock the dequeue already takes. Holding it across the reservation is
          # what makes admission order equal dequeue order.
          frontier.lock_frontier(crawl_id)
          # PEEK, then pay, then claim. `in_progress` has no way back under the frontier guard, so an
          # entry claimed and then refused its bytes is stranded — and `sealed_depth` would pin the
          # run's breadth-first frontier at that depth forever. The lock makes peek-then-claim
          # indivisible against another admission.
          candidate = frontier.peek_next(organization_id, crawl_id)
          next idle if candidate.nil?
          # The named entry is no longer the next one: already claimed by a pass whose worker was
          # lost, already terminal, or overtaken. Nothing is paid for and nothing is claimed.
          next idle if only && candidate["id"] != only

          admit(raw, frontier, organization_id, crawl, crawl_id, candidate, bounds, now)
        end
      end

      def idle = Decision.new(entry: nil, reserved_bytes: nil, reserved_total: nil, reason_code: nil)

      # Returns a denial reason, or nil when the run may be admitted. Order matches
      # `FetchAuthorization#authorize` so the two surfaces refuse in the same sequence.
      def authorize(gates, organization_id, crawl, now)
        org = gates.organization(organization_id)
        return DENIALS[:organization] unless org && org["status"] == "active"
        return DENIALS[:crawl] unless crawl["state"] == "running"

        # DEFENCE IN DEPTH, and currently unreachable: `f1_projects_guard` admits only
        # `draft -> active`, so a Project that has started a Crawl cannot become inactive until the
        # Project lifecycle lands its remaining edges. Kept because `FetchAuthorization` checks it at
        # the same position and admission must not be the looser of the two gates; its spec asserts
        # the unreachability rather than claiming a coverage it cannot have.
        project = gates.project(organization_id, crawl["project_id"])
        return DENIALS[:project] unless project && project["state"] == "active"

        unless gates.reservation_executing?(organization_id, crawl["entitlement_reservation_id"],
                                            FetchAuthorization::MAX_EXECUTION_SECONDS, now)
          return DENIALS[:entitlement]
        end

        nil
      end

      def limited(reason, entry: nil)
        Decision.new(entry:, reserved_bytes: nil, reserved_total: nil, reason_code: reason)
      end

      # Pay for the peeked candidate, then take it.
      #
      # WHY THE RESERVATION RETRIES. The frontier advisory lock serialises ADMISSIONS. It does not
      # serialise the other writers of `crawl_budget_counters.reserved_response_bytes` — the fetch
      # path reserves, commits and releases without ever taking it. The earlier comment here claimed
      # a refusal "means the budget genuinely moved, not that a race was lost", and that was simply
      # false: a lost compare-and-update wrote a hard `CrawlLimitReached` carrying the STALE
      # pre-race figure, for a run whose budget the very next release handed straight back. Reading
      # again and retrying is what `FetchContent` already does on this counter, and for this reason.
      #
      # A LOST RACE IS NOT A LIMIT. Only a re-read showing genuinely nothing left produces a
      # decision; exhausting the retries produces `CONTENDED`, which tells the caller to come back
      # and tells the customer nothing.
      def admit(raw, frontier, organization_id, crawl, crawl_id, candidate, limits, now)
        bounds = limits.byte_bounds
        budget = IdentityAccess::Infrastructure::CrawlBudgetStore.new(raw)
        budget.ensure_counters(id: @ids.generate, now:, correlation_id: @correlation_id,
                               organization_id:, project_id: crawl["project_id"], crawl_id:)

        want = nil
        granted = nil
        observed = nil
        RESERVE_ATTEMPTS.times do
          observed = budget.counters(organization_id, crawl_id)["reserved_response_bytes"].to_i
          want = ByteAccounting.reservation(remaining: bounds.per_run - observed, per_url: bounds.per_url)
          break if want.zero?

          granted = budget.reserve_bytes(organization_id, crawl_id, want, bounds.per_run, now)
          break unless granted.nil?
        end

        # ":442 — a capacity hard-limit event fires BEFORE an action would exceed the maximum; the
        # exceeding page, URL, or accounted bytes are not accepted." The candidate is NOT claimed,
        # so nothing is stranded `in_progress` and the frontier is exactly where it was.
        if want.zero?
          observe(raw, organization_id, crawl, crawl_id, BYTES, LimitDimensions::HARD, observed, limits, now)
          return limited(EXHAUSTED)
        end
        return limited(CONTENDED) if granted.nil?

        entry = frontier.claim_next(organization_id, crawl_id, now)
        # Under the lock the peeked candidate is still the next one. If it is not, the reservation
        # belongs to nobody and must go back rather than retire budget silently.
        if entry.nil?
          budget.release_bytes(organization_id, crawl_id, want, now)
          return idle
        end

        # ":442 — a soft event fires when the observed OR RESERVED value first equals the soft
        # limit." The reserved peak is what the statement just produced: a peak that is later
        # released is invisible in the stored row but visible here, to the caller that caused it.
        peak = granted["reserved_response_bytes"].to_i
        observe(raw, organization_id, crawl, crawl_id, BYTES, LimitDimensions::SOFT, peak, limits, now) if peak >= bounds.per_run_target

        Decision.new(entry:, reserved_bytes: want, reserved_total: peak, reason_code: nil)
      end

      # :442 — "Wall-clock duration starts at the atomic `Crawl.Queued -> Crawl.Running`
      # transition." `crawls.deadline_at` is written by StartCrawl from that instant, so it is the
      # authority rather than a duration recomputed here. The SOFT crossing has no deadline column
      # of its own and is measured from `started_at` against the resolved soft bound, which is the
      # same instant read a different way.
      def wall_clock(raw, organization_id, crawl, crawl_id, limits, now)
        elapsed = elapsed_minutes(crawl, now)
        deadline = crawl["deadline_at"]
        expired = !deadline.nil? && Platform::PgInstant.utc(deadline) <= now.utc

        # SOFT IS INDEPENDENT OF HARD, as at every other observation point. Gating it behind
        # `elsif expired` lost the soft event permanently for any run whose first admission after
        # the soft bound happened to land past the deadline — and after that `claim_next` returns
        # early on every call, so the branch is never re-entered.
        if elapsed && elapsed >= limits.configured(WALL_CLOCK_DIMENSION, LimitDimensions::SOFT)
          observe(raw, organization_id, crawl, crawl_id, WALL_CLOCK_DIMENSION,
                  LimitDimensions::SOFT, elapsed, limits, now)
        end
        if expired
          observe(raw, organization_id, crawl, crawl_id, WALL_CLOCK_DIMENSION,
                  LimitDimensions::HARD, elapsed.to_i, limits, now)
        end
        expired
      end

      def elapsed_minutes(crawl, now)
        started = crawl["started_at"]
        return nil if started.nil?

        Platform::PgInstant.elapsed_minutes(started, now)
      end

      def observe(raw, organization_id, crawl, crawl_id, dimension, threshold, observed, limits, now)
        @limits.observe(raw, organization_id:, project_id: crawl["project_id"],
                        crawl_id:, dimension:, threshold:, observed:, limits:, now:)
      end
    end
  end
end
