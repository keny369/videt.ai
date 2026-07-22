# frozen_string_literal: true

require "securerandom"

module Platform
  module ScheduledActions
    # Executes claimed due actions (BACKGROUND_PROCESSING.md § Durable Scheduling
    # :119; Job Catalogue `scheduled_action_dispatch` "execute one claimed due
    # action", idempotency authority "scheduled-action full identity").
    #
    # One action, four bounded steps, each in its own transaction so no database
    # lock is held across unrelated work:
    #
    #   1. compare-and-swap the claim from the scheduler to this worker. Any other
    #      owner, generation, pending state, terminal state or expired-and-
    #      reclaimed generation returns no row and the worker exits without
    #      product work — this is what makes duplicate delivery a no-op.
    #   2. resolve the registered handler for the exact (action_kind,
    #      action_schema_version). An unmapped kind or an unsupported schema
    #      version quarantines and performs no product work (:245, :421).
    #   3. run the handler in its own unit of work under a service RequestContext
    #      carrying the action's executing Service Identity. No Session is created,
    #      authenticated or fabricated anywhere on this path.
    #   4. terminalize: `completed` for a committed or harmlessly-terminal result,
    #      `quarantined` for a transport-integrity deviation.
    #
    # If the handler raises, or the process dies, the action is NOT stranded: the
    # claim is released back to `pending` (explicitly here, or by the expired-lease
    # sweep after process loss) and the same action identity is recomputed, which
    # is the ratified recovery for a pure deterministic computation with no
    # committed terminal result (:297). Because the handler is idempotent under
    # the action identity, recomputation after a *committed* result is a duplicate
    # no-op that simply completes the action.
    class Worker
      Outcome = Data.define(:action_id, :action_kind, :disposition, :reason, :result, :error)

      # Transport-integrity deviations: the action does not match its target at
      # transaction time, so it must fail closed rather than be replayed
      # (BACKGROUND_PROCESSING.md :245).
      QUARANTINE_REASONS = %w[scheduled_action_target_mismatch scheduled_action_not_due].freeze

      WORKER_LEASE_SECONDS = 30

      attr_reader :owner, :scheduler

      def initialize(registry: Registry.default, scheduler: Scheduler.new,
                     clock: Platform::Clock.system, ids: Platform::Ids.system,
                     owner: SecureRandom.uuid_v7)
        @registry = registry
        @scheduler = scheduler
        @clock = clock
        @ids = ids
        @owner = owner
      end

      # Claim and execute one bounded due batch. Returns the ordered Outcomes.
      def run_due_batch(limit: Scheduler::BATCH_LIMIT, now: nil)
        scheduler.claim_due(limit:, now:).map { |action| execute(action, now:) }
      end

      # Execute one already-claimed action.
      def execute(action, now: nil)
        dispatched = transfer(action, now:)
        return outcome(action, :skipped, "claim_not_transferable") if dispatched.nil?

        entry = @registry.resolve(action_kind: dispatched.action_kind,
                                  action_schema_version: dispatched.action_schema_version)
        return quarantine(dispatched, unmapped_reason(dispatched), now:) if entry.nil?

        run_handler(dispatched, entry, now:)
      end

      private

      def transfer(action, now:)
        Platform::UnitOfWork.run do |conn|
          Store.new(conn.raw_connection).dispatch(
            action_id: action.id, expected_owner: scheduler.owner,
            expected_generation: action.claim_generation, worker_owner: owner,
            lease_seconds: WORKER_LEASE_SECONDS, now:
          )
        end
      end

      def run_handler(action, entry, now:)
        result = invoke(action, entry)
        if result.failure? && QUARANTINE_REASONS.include?(result.reason_code)
          quarantine(action, result.reason_code, now:, result:)
        else
          settle(action, "completed", result.reason_code, now:, result:)
        end
      rescue StandardError => e
        # No committed terminal result: release the transport claim so the same
        # action identity is recomputed (:297). Only a bounded classification
        # token is persisted — never the exception message or backtrace.
        release(action, "scheduled_action_execution_failed", now:, error: e)
      end

      def invoke(action, entry)
        ctx = Platform::RequestContext.for_service(
          service_identity_id: action.executing_service_identity_id,
          clock: @clock, ids: @ids, correlation_id: action.correlation_id
        )
        command = entry.command.from_scheduled_action(
          action:, command_id: ctx.generate_id, requested_at_utc: ctx.now_utc
        )
        entry.handler.new.call(command:, request_context: ctx)
      end

      def unmapped_reason(action)
        return "scheduled_action_schema_unsupported" if @registry.kind_registered?(action.action_kind)

        "scheduled_work_mapping_mismatch"
      end

      def quarantine(action, reason, now:, result: nil)
        settle(action, "quarantined", reason, now:, result:)
      end

      def settle(action, status, reason, now:, result:)
        Platform::UnitOfWork.run do |conn|
          Store.new(conn.raw_connection).settle(
            action_id: action.id, owner:, generation: action.claim_generation, status:, reason:, now:
          )
        end
        outcome(action, status.to_sym, reason, result:)
      end

      def release(action, reason, now:, error:)
        Platform::UnitOfWork.run do |conn|
          Store.new(conn.raw_connection).release_claim(
            action_id: action.id, owner:, generation: action.claim_generation, reason:, now:
          )
        end
        outcome(action, :released, reason, error: error.class.name)
      end

      def outcome(action, disposition, reason, result: nil, error: nil)
        Outcome.new(action_id: action.id, action_kind: action.action_kind, disposition:, reason:, result:, error:)
      end
    end
  end
end
