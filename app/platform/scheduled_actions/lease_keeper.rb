# frozen_string_literal: true

module Platform
  module ScheduledActions
    # THE LIVE WORKER'S SIDE OF THE LEASE (F-04, FU-24; DECISIONS ADR-091).
    #
    # `Worker::WORKER_LEASE_SECONDS` is deliberately short so a genuinely dead worker is recovered
    # promptly. Legitimate work can nevertheless exceed it — one content attempt is bounded PER HOP, so the
    # initial request plus the ratified 10-redirect budget is 11 connections at the 15-second hard timeout,
    # and sitemap discovery paces :444's 30 and 120 seconds between candidates. Without renewal the lease
    # expired under a LIVE worker, the sweep returned the action to `pending`, and the ordinary path
    # executed twice. This keeps the lease alive while the worker genuinely owns the work, and gives up the
    # moment it does not.
    #
    # IT IS OWNERSHIP INFRASTRUCTURE, NOT A PRODUCT CONCERN. One implementation serves every work type;
    # workflows never reproduce lease logic. They reach it through `Lease.current` at the boundaries they
    # already have — the pacer they inject, the redirect guard F-01 already calls per hop, and an
    # `owned?` check before each irreversible step.
    #
    # THREE PROPERTIES IT MUST HAVE, and the reasons they are not optional:
    #
    #   * BOUNDED CADENCE. Renewal is driven by ELAPSED TIME, never by loop iterations, so heartbeat writes
    #     are bounded by how long the work takes and not by how many redirects, sitemap candidates or
    #     fetches it performs. A heartbeat per inner-loop step would trade a lease problem for write
    #     amplification proportional to crawler activity, which is the next scalability problem rather than
    #     a fix for this one.
    #   * FAIL CLOSED, BUT ONLY ON A CONFIRMED ANSWER. A renewal that returns false is the database saying
    #     ownership has moved; the worker stops. A renewal that RAISES is a transport failure and says
    #     nothing about ownership — treating it as loss would abandon work the worker still holds, and
    #     treating it as success would ignore a real transfer, so it is neither: the state stays `held`, the
    #     failure is counted, and the lease's own expiry remains the backstop. That is the existing
    #     repository semantic for the transport, which fails closed on a lost CONNECTION and not on a lost
    #     query.
    #   * NO UNINTERRUPTIBLE GAP. A 30- or 120-second product wait cannot be one `sleep` while the lease
    #     silently lapses, so `wait` divides it at heartbeat deadlines. THE PRODUCT INSTANT IS NOT MOVED:
    #     the total slept is exactly what the caller asked for, computed against a monotonic deadline so
    #     that wake-ups neither shorten nor lengthen it.
    class LeaseKeeper
      # :288, RATIFIED AND NOT INVENTED: "Heartbeat interval is one third of the lease duration, rounded
      # down to whole seconds and bounded from 5 through 30 seconds." A third means two consecutive
      # renewals may fail before the lease is at risk; the floor keeps a short lease from producing a
      # renewal storm, and the ceiling keeps a long one from leaving a wide unguarded gap. This originally
      # implemented only the fraction, which is the sort of near-miss that reads as compliance.
      RENEWAL_FRACTION = 3
      MIN_INTERVAL_SECONDS = 5
      MAX_INTERVAL_SECONDS = 30

      HELD = :held
      LOST = :lost

      attr_reader :action_id, :owner, :generation, :lease_seconds

      # MONOTONIC, never wall clock: cadence and the wait deadline must be immune to a clock step, and a
      # lease renewed against a wall clock that jumps backwards would be renewed too late. Injected for the
      # same reason `Platform::Clock` is — so a test can advance time instead of spending it — and defaulted
      # to the process monotonic source everywhere else.
      def initialize(action_id:, owner:, generation:, lease_seconds:,
                     monotonic: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                     sleeper: ->(s) { sleep(s) })
        @action_id = action_id
        @owner = owner
        @generation = generation
        @lease_seconds = lease_seconds
        @monotonic = monotonic
        @sleeper = sleeper
        @state = HELD
        @renewed_at = @monotonic.call
        @transport_failures = 0
      end

      def owned? = @state == HELD
      def lost? = @state == LOST

      # :288's interval, in whole seconds. A lease of 30 renews every 10.
      def interval
        (lease_seconds.to_i / RENEWAL_FRACTION).floor.clamp(MIN_INTERVAL_SECONDS, MAX_INTERVAL_SECONDS)
      end

      # Renew IF the interval has elapsed. Cheap and safe to call at every boundary — the elapsed-time test
      # is what makes the write rate independent of how often callers ask.
      def renew_if_due
        return @state unless owned?
        return @state if monotonic - @renewed_at < interval

        renew
      end

      # Renew now, whatever the interval. Returns :held or :lost.
      def renew
        return @state unless owned?

        renewed = TransportConnection.with do |pg|
          Store.new(pg).heartbeat(action_id:, owner:, generation:, lease_seconds:)
        end
        @renewed_at = monotonic
        @transport_failures = 0
        @state = renewed ? HELD : LOST
      rescue StandardError
        # A TRANSPORT FAILURE IS NOT AN ANSWER ABOUT OWNERSHIP. Counted so it is visible, not converted
        # into a verdict. The lease's own expiry remains the backstop: if the database stays unreachable the
        # lease lapses on its own and the sweep recovers the action, which is the correct outcome.
        @transport_failures += 1
        @state
      end

      attr_reader :transport_failures

      # Wait `milliseconds` of PRODUCT time, renewing across it, and report whether ownership survived.
      #
      # The deadline is monotonic and fixed before the first sleep, so heartbeat wake-ups cannot shorten or
      # lengthen the wait: whatever the renewals cost, the method returns when the caller's own interval has
      # elapsed. A confirmed ownership loss ends the wait early — there is no purpose in serving out a delay
      # for work this worker may no longer perform.
      def wait(milliseconds)
        remaining = milliseconds.to_i / 1000.0
        return @state if remaining <= 0

        deadline = monotonic + remaining
        while (left = deadline - monotonic).positive?
          @sleeper.call([left, interval].min)
          renew_if_due
          return @state if lost?
        end
        @state
      end

      private

      def monotonic = @monotonic.call
    end
  end
end
