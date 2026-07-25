# frozen_string_literal: true

module Platform
  module ScheduledActions
    # The single-scheduler control primitive (BACKGROUND_PROCESSING.md :67 "A PostgreSQL singleton
    # lease, not process count, prevents two active scheduler leaders").
    #
    # A PostgreSQL session-level advisory lock: only one connection can hold it at a time, and it
    # auto-releases if the holding connection dies. Enforcement of "only one EFFECTIVE scheduler"
    # comes from HOLDING the lease for the whole scheduler run — `BackgroundExecution.run_scheduler`
    # acquires it once and keeps it while it loops, so a second scheduler process cannot acquire it
    # and does not dispatch. (A bare acquire/release around a single pass would only serialise
    # concurrent passes, not prevent two schedulers interleaving across time — so the scheduler is
    # a long-lived process that holds the lease, never a per-pass cron.)
    #
    # It is deliberately NOT the full G6 lease: there is no renewable 15-second term, no heartbeat,
    # no `scheduler_leases` row and no queue-health integration (:112, :315). Those land with G6,
    # which is mandatory before more than one scheduler process may be deployed.
    module SchedulerLease
      module_function

      # Fixed two-int advisory-lock coordinates. PostgreSQL keeps the two-argument advisory-lock
      # space SEPARATE from the single-argument (bigint) space that the id-derived
      # `hashtextextended(...)` per-aggregate locks elsewhere use, so there is zero collision risk
      # with those locks. (class, object) = (F1 background-execution namespace, the F-04 scheduler).
      LOCK_CLASS = 20_260_725
      LOCK_OBJECT = 4

      # True iff this connection now holds the singleton lease. Non-blocking (never waits behind
      # another scheduler).
      def acquire?(pg)
        pg.exec_params("SELECT pg_try_advisory_lock($1, $2)", [LOCK_CLASS, LOCK_OBJECT]).getvalue(0, 0) == "t"
      end

      def release(pg)
        pg.exec_params("SELECT pg_advisory_unlock($1, $2)", [LOCK_CLASS, LOCK_OBJECT])
        nil
      end

      # Run the block ONLY as the singleton scheduler leader. A second concurrent holder is
      # refused: returns :not_leader without running the block. Otherwise returns the block's
      # value and releases the lease afterwards.
      def as_leader(pg)
        return :not_leader unless acquire?(pg)

        begin
          yield
        ensure
          release(pg)
        end
      end
    end
  end
end
