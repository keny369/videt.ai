# frozen_string_literal: true

module Platform
  module ScheduledActions
    # THE LEASE-AWARE EXECUTION CONTEXT. Set by the Worker around one handler invocation and cleared after,
    # so a workflow reaches its own delivery's lease without being handed one through every constructor and
    # without any workflow implementing lease logic of its own.
    #
    # Fiber-local rather than thread-local: it must not leak between concurrently executing deliveries, and
    # it must be absent — not stale — for every caller that is not a worker delivery. `current` is nil in
    # specs and in any direct invocation, and every consumer treats nil as "no lease to keep", which is why
    # `owned?` and `pace` are safe to call unconditionally.
    module Lease
      module_function

      KEY = :f1_scheduled_action_lease

      # THE ONE SPELLING OF "THIS DELIVERY NO LONGER OWNS ITS ACTION". It is the Worker's dispatch key for
      # releasing rather than settling a claim, so a workflow that reports it and a Worker that reads it
      # MUST agree; as two independent string literals they silently did not have to, and renaming either
      # would have restored the settle-instead-of-release defect with nothing failing. Deliberately outside
      # `Platform::ErrorCatalog` — it never reaches a customer, because the delivery reporting it has no
      # standing to speak for the action at all.
      LOST_REASON = "scheduled_action_lease_lost"

      def current = Thread.current[KEY]

      def with(keeper)
        previous = Thread.current[KEY]
        Thread.current[KEY] = keeper
        yield
      ensure
        Thread.current[KEY] = previous
      end

      # DOES THIS DELIVERY STILL OWN ITS ACTION? Authoritative: it renews if the cadence is due and then
      # answers, so the answer is never older than one interval.
      #
      # It used to read a cached flag, and that was the defect at the heart of the first heartbeat: a pass
      # whose lease had already lapsed and been swept still saw `true` at every guard, because nothing had
      # asked the database. Elapsed-time cadence is what keeps this cheap — asking at every boundary does
      # not write at every boundary — so the guard can be authoritative without becoming a poll.
      #
      # True when there is no lease to keep, so a direct caller is never blocked by infrastructure that
      # does not apply to it.
      def owned?
        keeper = current
        return true if keeper.nil?

        keeper.renew_if_due
        keeper.owned?
      end

      # Renew if the cadence is due. A no-op without a lease.
      def renew_if_due = current&.renew_if_due

      # THE BOUNDARY INSIDE ONE `Outbound.fetch`, which is NOT one bounded request.
      #
      # F-01 follows up to the ratified 10-redirect budget, and it takes a FRESH deadline per hop — so a
      # single call is up to eleven connections at the 15-second hard timeout, ~165 seconds of request time
      # (more, because the per-hop resolver timeout is taken outside that deadline) with no return to the
      # caller. A renewal placed only BEFORE the call therefore covers the first hop and nothing else, and a
      # 30-second lease lapses under a live worker in the middle of a perfectly ordinary apex->www->CDN
      # chain. That was measured: two robots/sitemap fetches, 165 seconds, ZERO heartbeat writes, and the
      # sweep reclaiming the action underneath them.
      #
      # `redirect_guard` is the one seam F-01 already consults between two hops, so it is where the boundary
      # belongs. It is ONE implementation for every work type, per FU-24's "do not create separate heartbeat
      # implementations" — callers with their own per-hop policy compose it through the block rather than
      # writing their own lease handling.
      #
      # A CONFIRMED TRANSFER REFUSES THE NEXT HOP. The platform must not keep requesting on behalf of a
      # delivery the database has already given away. The caller is responsible for not converting that
      # refusal into a product outcome — see `EnsureRobots#call` and `DiscoverSitemaps#call`, both of which
      # relinquish rather than decide.
      def redirect_guard(&policy)
        lambda do |uri|
          next false if renew_if_due == LeaseKeeper::LOST

          policy.nil? || policy.call(uri)
        end
      end

      # The pacer product code injects where it must wait. With a lease it is an interruptible,
      # heartbeating wait; without one it is an ordinary sleep, so nothing outside a worker changes
      # behaviour.
      def pacer
        lambda do |milliseconds|
          keeper = current
          next keeper.wait(milliseconds) if keeper

          sleep(milliseconds.to_i / 1000.0)
        end
      end
    end
  end
end
