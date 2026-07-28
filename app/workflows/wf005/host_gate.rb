# frozen_string_literal: true

require "digest"

module Workflows
  module Wf005
    # The per-host gate (S-07-005; WORKFLOW_SPECIFICATIONS.md :442; SEARCH_CRAWL_RETRIEVAL.md — "The
    # run and per-host gates use PostgreSQL `clock_timestamp()` and row locks. A worker cannot start
    # merely because Redis granted a token. It claims a host slot only when the rolling-start and
    # concurrency predicates pass, commits `submission_started`, then connects.").
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
      Decision = Data.define(:granted, :reason_code, :gate_id, :lease_version, :retry_after_ms) do
        def granted? = granted
      end

      # `crawl-policy-v1` (:425-438). Soft is the scheduling target, hard the nonexceedable ceiling.
      RATE_TARGET = CrawlPolicy::GLOBAL_CEILING.fetch("request_rate_per_host").fetch("soft")
      RATE_CEILING = CrawlPolicy::GLOBAL_CEILING.fetch("request_rate_per_host").fetch("hard")
      CONCURRENCY_TARGET = CrawlPolicy::GLOBAL_CEILING.fetch("concurrency_per_host").fetch("soft")
      CONCURRENCY_CEILING = CrawlPolicy::GLOBAL_CEILING.fetch("concurrency_per_host").fetch("hard")

      # The rolling window is one second (:442), so the baseline interval between starts is that
      # window divided by the per-second target.
      WINDOW_MS = 1000
      BASE_INTERVAL_MS = WINDOW_MS / RATE_TARGET

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
      def claim(organization_id:, gate_id:, kind: "content", crawl_delay_ms: nil)
        locked = @store.lock_gate(organization_id, gate_id)
        return refuse("host_gate_missing", gate_id) if locked.nil?

        blocked = robots_block(locked, kind)
        return refuse(blocked, gate_id) if blocked

        starts = locked["window_starts"].to_i
        active = locked["active_connection_count"].to_i
        # Both ceilings are asserted before the targets, so a defect in the target logic still cannot
        # exceed the nonexceedable bound.
        return refuse("host_rate_ceiling", gate_id) if starts >= RATE_CEILING
        return refuse("host_concurrency_ceiling", gate_id) if active >= CONCURRENCY_CEILING
        return refuse("host_rate_limited", gate_id) if starts >= RATE_TARGET
        return refuse("host_concurrency_limited", gate_id) if active >= CONCURRENCY_TARGET
        return refuse("host_delay_pending", gate_id) unless truthy?(locked["delay_elapsed"])

        interval = RobotsPolicy.effective_interval_ms(BASE_INTERVAL_MS,
                                                      crawl_delay_ms || locked["robots_crawl_delay_ms"].to_i)
        claimed = @store.claim_slot(gate_id, locked["state_version"].to_i, interval)
        return refuse("host_gate_contended", gate_id) if claimed.nil?

        Decision.new(granted: true, reason_code: nil, gate_id:,
                     lease_version: claimed["lease_version"].to_i, retry_after_ms: nil)
      end

      # Release the slot when the attempt terminates, however it terminates. A caller that raises
      # must still reach this, or the host's concurrency count leaks and the gate slowly closes.
      def release(gate_id:, now:)
        @store.release_slot(gate_id, now)
      end

      private

      # Content and sitemap dispatch is blocked until the robots record is TERMINAL, and permanently
      # once it is `unavailable` (:448 fail-closed denies ALL content fetching for the host for the
      # run). The robots fetch itself is exempt — it is what resolves the record.
      def robots_block(gate, kind)
        return nil if kind == "robots"
        return "robots_unavailable_fail_closed" if gate["robots_state"] == "unavailable"
        return "robots_not_resolved" unless %w[rules_applied no_restrictions].include?(gate["robots_state"])

        nil
      end

      def refuse(reason, gate_id)
        Decision.new(granted: false, reason_code: reason, gate_id:, lease_version: nil,
                     retry_after_ms: REFUSAL_RETRY_MS)
      end

      def truthy?(value) = value == true || value == "t"
    end
  end
end
