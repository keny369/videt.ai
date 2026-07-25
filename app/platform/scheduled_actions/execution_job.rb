# frozen_string_literal: true

require "sidekiq"

module Platform
  module ScheduledActions
    # The Sidekiq worker job (BACKGROUND_PROCESSING.md :119). It is a transport DELIVERY,
    # not a product attempt: on receipt it parses the scalar 8-field envelope and resolves the
    # authorised target THROUGH the Work Dispatch Binding named by `work_id` (:243). The
    # binding-mediated compare-and-swap transfers the action from the scheduler to this worker
    # at the envelope's exact claim generation, renews the lease, runs the registered handler
    # in its own unit of work under the envelope's lineage, and settles. Any unknown binding,
    # other owner, wrong generation, terminal state or reclaimed generation makes the CAS
    # return no row and the worker exit without product work — so a duplicate or stale delivery
    # is a no-op. The worker never scans a domain/attempt table.
    #
    # Sidekiq retry and Dead are disabled: PostgreSQL owns retry (the infrastructure schedule
    # via lease expiry + re-enqueue, and the dispatch-retry ceiling) and quarantine. A raised
    # handler releases the claim for recomputation under the same action identity; a process
    # crash loses only the lease, which the expiry sweep recovers.
    class ExecutionJob
      include Sidekiq::Job

      sidekiq_options retry: false, dead: false

      # The closed dispatch registry this job resolves handlers from. Defaults to the
      # singleton the initializer populates; injectable so the acceptance harness can drive
      # a generic executor without touching the production registration.
      class << self
        attr_writer :registry

        def registry = @registry || Registry.default
      end

      def perform(args)
        envelope = Envelope.parse(args)
        return if envelope.nil? # malformed transport message: exit, claim no work

        Worker.new(registry: self.class.registry).execute_delivery(
          work_id: envelope.work_id, expected_generation: envelope.claim_generation,
          correlation_id: envelope.correlation_id, causation_id: envelope.causation_id
        )
      end
    end
  end
end
