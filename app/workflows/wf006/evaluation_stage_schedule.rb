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
    # THE GATE IS VISITED MORE THAN ONCE, AND THE VISITS MUST NOT COLLIDE. The action identity
    # preimage is `(kind, schema, organization, project, target_type, target_id,
    # product_generation, schedule_generation, due_at)` — it carries no payload. The terminal
    # checkpoint schedules the first visit and the last ParsingJob schedules the second, both
    # against the same Crawl, and both at instants that can be identical. So the two visits are
    # told apart by `schedule_generation`, and by nothing else.
    #
    # An earlier version passed the CRAWL'S `state_version` as `product_generation` for the
    # first visit and the JOB COUNT for the second. Those are unrelated quantities sharing one
    # slot, and when they coincided — a two-Document crawl whose Crawl had advanced twice — the
    # second schedule found a byte-equal preimage, returned the FIRST action as a replay and
    # created nothing. The snapshot was then never sealed and the Evaluation stayed pending for
    # ever: the same latch this gate exists to release, reached by a different route.
    # `product_generation` is now the ratified stage ORDINAL, constant for this stage, and the
    # visit is the `schedule_generation`.
    module EvaluationStageSchedule
      module_function

      ACTION_KIND = "evaluation_stage_advance"
      ACTION_SCHEMA_VERSION = "1.0"
      TARGET_TYPE = "crawl"

      # `seal_input_snapshot` is ordinal 1 of the ratified Evaluation stage registry
      # (BACKGROUND_PROCESSING.md :439-444).
      STAGE_ORDINAL = 1
      # The two visits this stage receives. Naming them is the point: a third caller has to add
      # a name here rather than pick a number and hope it is free.
      VISIT_CRAWL_TERMINAL = 1
      VISIT_PARSING_COMPLETE = 2

      def schedule(pg:, organization_id:, project_id:, crawl_id:, terminal_at:, now:,
                   correlation_id:, causation_id: nil, command_id: nil,
                   state_version: STAGE_ORDINAL, schedule_generation: VISIT_CRAWL_TERMINAL)
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
