# frozen_string_literal: true

module Platform
  module ScheduledActions
    # The singleton scheduler's dispatch step (BACKGROUND_PROCESSING.md :67, :116). NOT a
    # Sidekiq worker: it polls PostgreSQL for due, committed actions, claims a bounded batch
    # (FOR UPDATE SKIP LOCKED, so concurrent schedulers take disjoint batches; a single-leader
    # deployment is the enforced posture until the G6 scheduler lease lands), mints one Work
    # Dispatch Binding per claimed action, and enqueues ONE scalar envelope (`work_id` = that
    # binding) per action to that action's fixed queue.
    #
    # Enqueue is transaction-safe by construction: a scheduling transaction that rolled back
    # created no `scheduled_actions` row, so the poll never sees it and nothing is enqueued —
    # there is no fire-and-forget after commit. The worker's binding-mediated claim CAS (not
    # the enqueue) transfers ownership and sets `dispatched`, which eliminates the enqueue/mark
    # race (:119); an action enqueued but never picked up keeps its lease and is recovered by
    # the expiry sweep, which re-enqueues the SAME identity at a new claim generation.
    #
    # A FAILED Redis enqueue (Redis unreachable) is not fire-and-forget either: the still-owned
    # claim is handed to `f1_fail_scheduled_action_dispatch`, which applies the 1/5/30/120/600s
    # infrastructure schedule or, on the sixth failure, quarantines the record with
    # `redis_dispatch_exhausted` and a high alert (:313). The identity is never lost.
    class Dispatcher
      # The disposition of dispatching one claimed action: :enqueued on a successful Redis
      # hand-off, else the transport-failure disposition (:rescheduled | :quarantined | :noop).
      Dispatched = Data.define(:action_id, :work_id, :queue, :outcome, :envelope)

      # BACKGROUND_PROCESSING.md :313 — attempt six is the terminal ceiling.
      RETRY_CEILING = 6

      def initialize(scheduler: Scheduler.new, job: ExecutionJob, alerter: DispatchAlert)
        @scheduler = scheduler
        @job = job
        @alerter = alerter
      end

      attr_reader :scheduler

      # Poll and enqueue one due batch; returns the ordered Dispatched dispositions.
      def dispatch_due(limit: Scheduler::BATCH_LIMIT)
        scheduler.claim_due(limit:).map { |action| enqueue(action) }
      end

      # Return expired claims to pending so the same identity is recomputed and re-enqueued.
      def recover_expired_leases(limit: Scheduler::BATCH_LIMIT)
        scheduler.recover_expired_leases(limit:)
      end

      private

      def enqueue(action)
        # An action whose catalogue work_type is nil (e.g. evaluation_stage_advance, whose type is
        # resolved from the unbuilt stage registry) has no enqueueable envelope; quarantine it
        # rather than emit an unparseable message that would re-enqueue forever.
        return quarantine_unmappable(action) if action.work_type.nil?

        envelope = Envelope.for(action)
        begin
          @job.set(queue: action.queue).perform_async(envelope.to_args)
        rescue StandardError => e
          return fail_enqueue(action, e)
        end
        Dispatched.new(action_id: action.id, work_id: action.work_id, queue: action.queue,
                       outcome: :enqueued, envelope:)
      end

      def quarantine_unmappable(action)
        scheduler.quarantine(action_id: action.id, generation: action.claim_generation,
                             reason: "scheduled_work_mapping_mismatch")
        Dispatched.new(action_id: action.id, work_id: action.work_id, queue: action.queue,
                       outcome: :unmappable, envelope: nil)
      end

      # Redis enqueue failed. Apply the infrastructure dispatch schedule under the claim this
      # scheduler still owns; on terminal exhaustion, raise the high alert (:313).
      def fail_enqueue(action, error)
        disposition = scheduler.fail_dispatch(action_id: action.id, generation: action.claim_generation)
        if disposition == "quarantined"
          @alerter.high(reason: "redis_dispatch_exhausted", action_id: action.id, work_id: action.work_id,
                        attempts: RETRY_CEILING, error_class: error.class.name)
        end
        Dispatched.new(action_id: action.id, work_id: action.work_id, queue: action.queue,
                       outcome: disposition.to_sym, envelope: nil)
      end
    end
  end
end
