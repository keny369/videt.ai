# frozen_string_literal: true

module Workflows
  module Wf007
    # One `check_attempt_due` per materialized expected key. The Slot is the target, because
    # the Slot is what the attempt terminalizes and what its retry would reuse.
    #
    # IN ITS OWN FILE BECAUSE ZEITWERK CANNOT REACH IT OTHERWISE. It used to live beside
    # `EvaluationStageSchedule` in `evaluation_stage_schedule.rb`, which Zeitwerk maps to that
    # OTHER constant — so `Workflows::Wf007::CheckAttemptSchedule` had no file of its own and
    # could only resolve once something unrelated had already caused that file to load.
    #
    # Every gate passed anyway, which is why this survived. `zeitwerk:check` verifies that each
    # file defines the constant its path implies; it does not report an EXTRA constant that no
    # path implies. The test and production environments eager load, so everything is defined
    # before anything runs. Development does not (`config.eager_load = false`), and that is
    # where it bites.
    #
    # It was found by RUNNING the product: a live evaluation of `xirconhomes.com.au` raised
    # `NameError: uninitialized constant
    # Workflows::Wf007::Handlers::AdvanceEvaluationStage::CheckAttemptSchedule` inside
    # `write_entries_and_slots`, which the ScheduledActions worker swallowed into
    # `scheduled_action_execution_failed` — the token meaning DEFECT — and the released action
    # then succeeded on redelivery, because by then some other reference had loaded the file.
    # A self-healing intermittent failure on the path that materializes every Check Result
    # Slot, invisible to a green suite.
    module CheckAttemptSchedule
      module_function

      ACTION_KIND = "check_attempt_due"
      ACTION_SCHEMA_VERSION = "1.0"
      TARGET_TYPE = "check_result_slot"

      def schedule(pg:, organization_id:, project_id:, slot_id:, due_at:, now:, correlation_id:,
                   causation_id: nil, command_id: nil, attempt_number: 1)
        Platform::ScheduledActions::Store.new(pg).create(
          id: Platform::Ids.system.generate, action_kind: ACTION_KIND,
          action_schema_version: ACTION_SCHEMA_VERSION, organization_id:, project_id:,
          target_type: TARGET_TYPE, target_id: slot_id,
          # The attempt number is the product generation, so the single permitted retry is a
          # DISTINCT action rather than a redelivery of the first.
          product_generation: attempt_number, schedule_generation: 1,
          due_at:, now:, correlation_id:, causation_id: causation_id || correlation_id,
          command_id:, executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor
        )[:id]
      end
    end
  end
end
