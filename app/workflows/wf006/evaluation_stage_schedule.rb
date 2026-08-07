# frozen_string_literal: true

module Workflows
  module Wf006
    # Creates the Evaluation's input-gate stage checkpoint on the transaction that
    # TERMINALIZES its Crawl, so the Crawl's terminal state and the checkpoint that will
    # resolve its Evaluation commit or roll back together.
    #
    # WHY HERE AND NOWHERE ELSE. The parse manifest is "the complete set of distinct
    # Documents whose IngestionJobs reached `succeeded` for the selected Crawl"
    # (contracts/S-08.json), and that set is only final once the Crawl is terminal.
    # Scheduling at start would race the run; scheduling from a sweep would need a scan.
    # The terminalizing transaction is the exact moment the inputs stop changing.
    #
    # DUE IMMEDIATELY. `due_at` is the terminal instant itself: the stage is a checkpoint
    # to run, not a timer to wait out. Nothing else can advance the Evaluation, so any
    # delay would only be dead time in which the Project cannot crawl again.
    #
    # The action identity preimage includes `due_at`, so a re-run of a crawl (a new
    # Crawl, a new terminal instant) is a distinct action. A duplicate delivery of the
    # SAME action is resolved by the handler's idempotency record, not by this module.
    module EvaluationStageSchedule
      module_function

      ACTION_KIND = "evaluation_stage_advance"
      ACTION_SCHEMA_VERSION = "1.0"
      TARGET_TYPE = "crawl"

      def schedule(pg:, organization_id:, project_id:, crawl_id:, terminal_at:, now:,
                   correlation_id:, causation_id: nil, command_id: nil, state_version: 0,
                   schedule_generation: 1)
        Platform::ScheduledActions::Store.new(pg).create(
          id: Platform::Ids.system.generate, action_kind: ACTION_KIND,
          action_schema_version: ACTION_SCHEMA_VERSION, organization_id:, project_id:,
          target_type: TARGET_TYPE, target_id: crawl_id,
          product_generation: state_version, schedule_generation:,
          due_at: terminal_at, now:, correlation_id:, causation_id: causation_id || correlation_id,
          command_id:, executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor
        )[:id]
      end
    end
  end
end
