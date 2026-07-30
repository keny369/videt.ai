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
