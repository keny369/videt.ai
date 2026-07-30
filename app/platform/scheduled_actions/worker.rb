# frozen_string_literal: true

require "securerandom"

module Platform
  module ScheduledActions
    # Executes claimed due actions (BACKGROUND_PROCESSING.md § Durable Scheduling
    # :119; Job Catalogue `scheduled_action_dispatch` "execute one claimed due
    # action", idempotency authority "scheduled-action full identity").
    #
    # One action, four bounded steps. The three transport steps are single
    # restricted statements on the platform-worker transport connection, so each
    # is its own transaction and no lock is held across the handler's work; the
    # handler runs on the ordinary runtime connection in its own unit of work.
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

      # Claim and execute one bounded due batch (in-process path). Returns the
      # ordered Outcomes. The claimed row carries its binding work_id and lineage.
      def run_due_batch(limit: Scheduler::BATCH_LIMIT)
        scheduler.claim_due(limit:).map { |action| execute(action) }
      end

      # Execute one already-claimed action: transfer the claim through its binding,
      # then run under the action's own lineage.
      def execute(action)
        dispatched = transfer(work_id: action.work_id, expected_generation: action.claim_generation)
        return outcome(action, :skipped, "claim_not_transferable") if dispatched.nil?

        run_resolved(dispatched, correlation_id: action.correlation_id, causation_id: action.causation_id)
      end

      # Execute one transport delivery resolved ONLY by its Work Dispatch Binding
      # (the Sidekiq path, :243). The envelope carries the lineage (:81-84); the
      # binding resolves the action; a non-transferable binding is a no-op.
      def execute_delivery(work_id:, expected_generation:, correlation_id:, causation_id:)
        dispatched = transfer(work_id:, expected_generation:)
        return delivery_skipped if dispatched.nil?

        run_resolved(dispatched, correlation_id:, causation_id:)
      end

      private

      def run_resolved(action, correlation_id:, causation_id:)
        entry = @registry.resolve(action_kind: action.action_kind,
                                  action_schema_version: action.action_schema_version)
        return quarantine(action, unmapped_reason(action)) if entry.nil?

        run_handler(action, entry, correlation_id:, causation_id:)
      end

      def transfer(work_id:, expected_generation:)
        TransportConnection.with do |pg|
          Store.new(pg).dispatch(
            work_id:, expected_generation:, worker_owner: owner, lease_seconds: WORKER_LEASE_SECONDS
          )
        end
      end

      # A delivery that CONFIRMED it lost its lease did no product work and has no standing to terminalize
      # the action. Releasing the claim is :297's ratified recovery — "release the transport claim and
      # recompute the same product attempt identity" — and it is fenced on owner and generation, so a
      # genuinely transferred action matches zero rows while a lapsed-but-unswept one correctly returns to
      # `pending`.
      #
      # THIS WAS A REAL DEFECT AND ITS ABSENCE WAS RECORDED AS A FEATURE. ADR-091 asserted "the action is
      # not settled either, and need not be — a stale worker's settle matches zero rows". False:
      # `f1_settle_scheduled_action` carries NO lease predicate, so in the window between the lease lapsing
      # and the sweep running, the row is still `dispatched` under this owner and generation and the settle
      # MATCHES. A relinquished delivery therefore completed the action having done nothing, with no
      # attempt, no ledger and no successor, and the crawl hung `running`.
      #
      # ONE SPELLING, NOT TWO. This is the lease's own vocabulary, so it is DEFINED by the lease and merely
      # named here: as independent literals on both sides of the dispatch, renaming either would have
      # silently restored the settle-instead-of-release defect with no test to notice.
      LEASE_LOST_REASON = Lease::LOST_REASON

      def run_handler(action, entry, correlation_id:, causation_id:)
        result = invoke(action, entry, correlation_id:, causation_id:)
        if result.failure? && result.reason_code == LEASE_LOST_REASON
          release(action, LEASE_LOST_REASON)
        elsif result.failure? && QUARANTINE_REASONS.include?(result.reason_code)
          quarantine(action, result.reason_code, result:)
        else
          settle(action, "completed", result.reason_code, result:)
        end
      rescue StandardError => e
        # No committed terminal result: release the transport claim so the same
        # action identity is recomputed (:297). Only a bounded classification
        # token is persisted — never the exception message or backtrace.
        release(action, "scheduled_action_execution_failed", error: e)
      end

      # The envelope's correlation is installed into the execution RequestContext
      # directly (:81); causation reaches the command via the reloaded action, which
      # is byte-identical to the envelope value — both are copied from the persisted
      # work at claim time (:82). So every execution runs under the envelope's lineage.
      def invoke(action, entry, correlation_id:, causation_id:)
        ctx = Platform::RequestContext.for_service(
          service_identity_id: action.executing_service_identity_id,
          clock: @clock, ids: @ids, correlation_id: correlation_id
        )
        command = entry.command.from_scheduled_action(
          action:, command_id: ctx.generate_id, requested_at_utc: ctx.now_utc
        )
        # THE LEASE IS KEPT FOR THE WHOLE HANDLER, by infrastructure, once (F-04 FU-24, ADR-091). A handler
        # whose legitimate work outruns `WORKER_LEASE_SECONDS` — a redirect chain at the per-hop timeout,
        # :444's pacing — used to have its lease expire underneath it, so the sweep returned the action to
        # `pending` and it was executed twice. The keeper renews on elapsed time at the boundaries the
        # workflow already has, and reports a CONFIRMED transfer so the workflow can stop; no workflow
        # implements any of that itself.
        Lease.with(lease_keeper_for(action)) do
          entry.handler.new.call(command:, request_context: ctx)
        end
      end

      def lease_keeper_for(action)
        LeaseKeeper.new(action_id: action.id, owner:, generation: action.claim_generation,
                        lease_seconds: WORKER_LEASE_SECONDS)
      end

      def delivery_skipped
        Outcome.new(action_id: nil, action_kind: nil, disposition: :skipped,
                    reason: "claim_not_transferable", result: nil, error: nil)
      end

      def unmapped_reason(action)
        return "scheduled_action_schema_unsupported" if @registry.kind_registered?(action.action_kind)

        "scheduled_work_mapping_mismatch"
      end

      def quarantine(action, reason, result: nil)
        settle(action, "quarantined", reason, result:)
      end

      def settle(action, status, reason, result:)
        TransportConnection.with do |pg|
          Store.new(pg).settle(
            action_id: action.id, owner:, generation: action.claim_generation, status:, reason:
          )
        end
        outcome(action, status.to_sym, reason, result:)
      end

      def release(action, reason, error: nil)
        TransportConnection.with do |pg|
          Store.new(pg).release_claim(
            action_id: action.id, owner:, generation: action.claim_generation, reason:
          )
        end
        outcome(action, :released, reason, error: error&.class&.name)
      end

      def outcome(action, disposition, reason, result: nil, error: nil)
        Outcome.new(action_id: action.id, action_kind: action.action_kind, disposition:, reason:, result:, error:)
      end
    end
  end
end
