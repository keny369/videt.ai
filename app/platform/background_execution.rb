# frozen_string_literal: true

module Platform
  # Background Execution (F-04, FOUNDATION-004) — FROZEN operational contract.
  #
  # The production-reachable, durable, idempotent asynchronous execution foundation: PostgreSQL
  # is the sole timer/lease/idempotency authority and Sidekiq is transport ONLY. This module is
  # the single named front door for the deployment's singleton `scheduler` process (not a Sidekiq
  # worker): it acquires the leader lease ONCE and holds it for the process lifetime while looping
  # scheduler passes — recover expired leases, then enqueue due, committed actions (one scalar
  # 8-field envelope per action, work_id = a durable Work Dispatch Binding) to each action's fixed
  # queue. Execution itself is ScheduledActions::ExecutionJob, which resolves the action THROUGH
  # the binding and runs the registered handler under the envelope's lineage.
  #
  # SCHEDULING and HANDLER REGISTRATION remain the ScheduledActions core's own established
  # surface (Store#create inside a product transaction; Registry at boot). F-04 does not re-wrap
  # them; it makes the substrate production-reachable and freezes the transport boundary.
  #
  # spec/architecture/background_execution_single_surface_spec.rb freezes that boundary: the
  # ExecutionJob is the only Sidekiq::Job, the Dispatcher is the only enqueue path, every job
  # disables Sidekiq retry and the Dead set, and the transport Envelope is identifiers only.
  #
  # DEFERRED (recorded with enforceable triggers in the F-04 freeze report and DECISIONS.md):
  # the queue-health gate + automatic recovery of `redis_dispatch_exhausted` records (G5), and
  # the full renewable leader-election lease with heartbeat/failover (G6). Until G6, a SECOND
  # scheduler process cannot acquire the held lease and does not dispatch — so no committed
  # configuration runs more than one EFFECTIVE scheduler.
  module BackgroundExecution
    module_function

    POLL_INTERVAL_SECONDS = 1

    # Run the singleton scheduler. Acquire the leader lease ONCE on a persistent transport
    # connection and HOLD it for the whole run while looping passes, so a second scheduler process
    # returns :not_leader without dispatching (the enforceable single-scheduler control while G6 is
    # deferred). `running` is checked before each pass (default: forever); `pace` runs between
    # passes (default: sleep the poll interval); `on_pass` observes each pass result. Returns the
    # last pass result, or :not_leader if another scheduler already leads.
    def run_scheduler(dispatcher: ScheduledActions::Dispatcher.new,
                      running: -> { true }, pace: -> { sleep(POLL_INTERVAL_SECONDS) }, on_pass: nil)
      ScheduledActions::TransportConnection.with do |pg|
        return :not_leader unless ScheduledActions::SchedulerLease.acquire?(pg)

        begin
          last = nil
          while running.call
            recovered = dispatcher.recover_expired_leases
            dispatched = dispatcher.dispatch_due
            last = { recovered:, dispatched: dispatched.size }
            on_pass&.call(last)
            pace.call
          end
          last
        ensure
          ScheduledActions::SchedulerLease.release(pg)
        end
      end
    end
  end
end
