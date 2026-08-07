# frozen_string_literal: true

module Workflows
  module Wf006
    # One `parsing_attempt_due` ScheduledAction per ParsingJob attempt (the ratified kind,
    # queue `pipeline`, work type `parse`). Created on the transaction that queues or
    # requeues the job, so the job and the timer that will run it commit together.
    #
    # The action identity preimage includes `due_at`, so a retry at +30s is a DISTINCT action
    # from the first attempt and the two cannot collide; a duplicate delivery of the same
    # attempt is resolved by the handler's idempotency record.
    module ParsingAttemptSchedule
      module_function

      ACTION_KIND = "parsing_attempt_due"
      ACTION_SCHEMA_VERSION = "1.0"
      TARGET_TYPE = "parsing_job"

      def schedule(pg:, organization_id:, project_id:, parsing_job_id:, due_at:, now:,
                   correlation_id:, causation_id: nil, command_id: nil, state_version: 0,
                   schedule_generation: 1)
        Platform::ScheduledActions::Store.new(pg).create(
          id: Platform::Ids.system.generate, action_kind: ACTION_KIND,
          action_schema_version: ACTION_SCHEMA_VERSION, organization_id:, project_id:,
          target_type: TARGET_TYPE, target_id: parsing_job_id,
          product_generation: state_version, schedule_generation:,
          due_at:, now:, correlation_id:, causation_id: causation_id || correlation_id,
          command_id:, executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor
        )[:id]
      end
    end
  end
end
