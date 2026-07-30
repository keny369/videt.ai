# frozen_string_literal: true

require "digest"

module Workflows
  module Wf005
    # The per-host gate (S-07-005; WORKFLOW_SPECIFICATIONS.md :442; SEARCH_CRAWL_RETRIEVAL.md — "The
    # run and per-host gates use PostgreSQL `clock_timestamp()` and row locks. A worker cannot start
    # merely because Redis granted a token. It claims a host slot only when the rolling-start and
    # concurrency predicates pass, records the start, then connects.").
    #
    # Two ceilings and two targets, all from `crawl-policy-v1`:
    #
    #   request_rate_per_host   soft 1 / hard 2 per rolling second
    #   concurrency_per_host    soft 2 / hard 4 concurrent
    #
    # Volume I :442 is precise about what these mean: "The baseline scheduler TARGETS at most 1 start
    # in that interval and at most 2 concurrent requests; 2 starts per rolling second and 4 concurrent
    # requests are NONEXCEEDABLE SAFETY CEILINGS, not normal scheduling targets." So the gate
    # schedules to the SOFT value and treats the hard value as an invariant that must hold even if the
    # soft logic were wrong — which is also the owner's direction to prefer determinism over
    # throughput. A claim is refused rather than queued: the caller retries, and refusing keeps the
    # decision a pure function of committed state.
    class HostGate
      # `lease_token` identifies THIS claim. It must be presented to `release`, so a worker can only
      # ever release the slot it holds — releasing twice, or releasing someone else's, is a no-op
      # rather than a silent widening of the nonexceedable concurrency ceiling.
      Decision = Data.define(:granted, :reason_code, :gate_id, :lease_version, :lease_token,
                             :retry_after_ms) do
        def granted? = granted
      end

      # The GLOBAL ceiling is only ever the outermost clamp. WORKFLOW_SPECIFICATIONS.md :390 —
      # "Global safety bounds cannot be weakened. EFFECTIVE crawl and capacity limits are the most
      # restrictive of global safety, approved entitlement, Organization, and Project limits" — so
      # the operative numbers are resolved PER CRAWL at the claim, from the currently active
      # Organization and Project policies. Binding the class to the global row would silently ignore
      # a Project that had narrowed its per-host rate or concurrency, which is the exact inversion of
      # :390, and MTX-030 requires a new restriction to bind "running work at the next checkpoint" —
      # the per-host claim IS that checkpoint.
      RATE_TARGET = CrawlPolicy::GLOBAL_CEILING.fetch("request_rate_per_host").fetch("soft")
      RATE_CEILING = CrawlPolicy::GLOBAL_CEILING.fetch("request_rate_per_host").fetch("hard")
      CONCURRENCY_TARGET = CrawlPolicy::GLOBAL_CEILING.fetch("concurrency_per_host").fetch("soft")
      CONCURRENCY_CEILING = CrawlPolicy::GLOBAL_CEILING.fetch("concurrency_per_host").fetch("hard")

      # The rolling window is one second (:442), so the baseline interval between starts is that
      # window divided by the per-second target.
      WINDOW_MS = 1000
      BASE_INTERVAL_MS = WINDOW_MS / RATE_TARGET

      # The effective per-host limits for one Crawl: the most restrictive of the frozen global
      # ceiling and every active Organization/Project crawl policy.
      Limits = Data.define(:rate_target, :rate_ceiling, :concurrency_target, :concurrency_ceiling,
                           :base_interval_ms)

      def self.limits_from(bounds)
        rate = bounds.fetch("request_rate_per_host")
        concurrency = bounds.fetch("concurrency_per_host")
        target = [rate["soft"].to_i, 1].max
        Limits.new(rate_target: target, rate_ceiling: rate["hard"].to_i,
                   concurrency_target: [concurrency["soft"].to_i, 1].max,
                   concurrency_ceiling: concurrency["hard"].to_i,
                   base_interval_ms: WINDOW_MS / target)
      end

      # (The global fallback constant that used to live here is gone with the local rescue it
      # served: `EffectiveLimits` owns the malformed-policy fallback for every execution-time
      # consumer, so there is one place that decides what happens when a stored policy cannot be
      # read, not three that happen to agree.)

      REFUSAL_RETRY_MS = 250

      def initialize(store, ids:, correlation_id:)
        @store = store
        @ids = ids
        @correlation_id = correlation_id
      end

      # Ensure the gate row for a canonical host exists. Idempotent, so concurrent workers
      # discovering the same host converge on one row rather than racing to create two.
      def ensure_gate(organization_id:, project_id:, crawl_id:, canonical_host:, now:)
        @store.ensure_gate(id: @ids.generate, now:, correlation_id: @correlation_id, organization_id:,
                           project_id:, crawl_id:, canonical_host:)
      end

      # Claim a host slot, or refuse with the reason. The row is LOCKED for the whole decision, so
      # two workers contending for one host serialize and the second sees the first's committed
      # start — the rolling window can never be read stale.
      #
      # `kind` distinguishes the robots fetch from everything else: robots must be able to proceed
      # while the robots record is still unresolved, or no host could ever become fetchable.
      def claim(organization_id:, gate_id:, now:, kind: "content", crawl_delay_ms: nil)
        locked = @store.lock_gate(organization_id, gate_id)
        return refuse("host_gate_missing", gate_id) if locked.nil?

        blocked = robots_block(locked, kind)
        return refuse(blocked, gate_id) if blocked

        limits = effective_limits(organization_id, locked)
        starts = locked["window_starts"].to_i
        active = locked["active_connection_count"].to_i
        # Both ceilings are asserted before the targets, so a defect in the target logic still cannot
        # exceed the nonexceedable bound.
        return refuse("host_rate_ceiling", gate_id) if starts >= limits.rate_ceiling
        return refuse("host_concurrency_ceiling", gate_id) if active >= limits.concurrency_ceiling
        return refuse("host_rate_limited", gate_id) if starts >= limits.rate_target
        return refuse("host_concurrency_limited", gate_id) if active >= limits.concurrency_target
        # A pacing refusal reports the REAL remaining wait, so the caller sleeps once for as long as
        # the host actually requires instead of spinning a fixed constant that a robots `Crawl-delay`
        # above it can outlast — which silently turned "delayed" (:442) into a dropped candidate.
        unless truthy?(locked["delay_elapsed"])
          return refuse("host_delay_pending", gate_id, retry_after_ms: locked["delay_remaining_ms"].to_i)
        end

        # A stored crawl-delay and a caller-supplied one may only ever make the interval LONGER
        # (:448 "never increases rate"), so the maximum is taken over all three rather than letting
        # either override the other — a caller passing 0 must not discard a stored delay.
        interval = [limits.base_interval_ms, crawl_delay_ms.to_i,
                    locked["robots_crawl_delay_ms"].to_i].max
        token = @ids.generate
        claimed = @store.claim_slot(gate_id, locked["state_version"].to_i, interval, token, now)
        return refuse("host_gate_contended", gate_id) if claimed.nil?

        Decision.new(granted: true, reason_code: nil, gate_id:, lease_token: token,
                     lease_version: claimed["lease_version"].to_i, retry_after_ms: nil)
      end

      # Release the slot this token holds, when the attempt terminates however it terminates. A
      # caller that raises must still reach this — but a leak is no longer permanent: every claim
      # sweeps leases older than the stale bound, so a slot lost with its worker is reclaimed rather
      # than closing the host for the rest of the run (SEARCH_CRAWL_RETRIEVAL :82).
      def release(gate_id:, lease_token:, now:)
        @store.release_slot(gate_id, lease_token, now)
      end

      # Reclaim stale leases without claiming — for a sweeper or a health check on a host no worker
      # is currently claiming against.
      def sweep(gate_id:, now:)
        @store.sweep_leases(gate_id, now)
      end

      private

      # The most restrictive of the frozen global ceiling and every active Organization/Project
      # crawl policy, resolved at the claim from the gate's own Crawl (:390). A malformed stored
      # policy is ignored rather than guessed at — its own activation command already refuses one,
      # so falling back to the global clamp is strictly safe.
      def effective_limits(organization_id, locked)
        self.class.limits_from(EffectiveLimits.resolve(
                                 @store.active_crawl_policies(organization_id, locked["project_id"])
                               ).bounds)
      end

      # Content and sitemap dispatch is blocked until the robots record is TERMINAL, and permanently
      # once it is `unavailable` (:448 fail-closed denies ALL content fetching for the host for the
      # run). The robots fetch itself is exempt — it is what resolves the record.
      def robots_block(gate, kind)
        return nil if kind == "robots"
        return "robots_unavailable_fail_closed" if gate["robots_state"] == "unavailable"
        return "robots_not_resolved" unless %w[rules_applied no_restrictions].include?(gate["robots_state"])

        nil
      end

      def refuse(reason, gate_id, retry_after_ms: REFUSAL_RETRY_MS)
        Decision.new(granted: false, reason_code: reason, gate_id:, lease_version: nil,
                     lease_token: nil, retry_after_ms: [retry_after_ms.to_i, REFUSAL_RETRY_MS].max)
      end

      def truthy?(value) = value == true || value == "t"
    end
  end
end
