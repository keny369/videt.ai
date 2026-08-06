# frozen_string_literal: true

module Workflows
  module Wf005
    module Commands
      # WF-005 RunIngestionJob — the service-only ingestion attempt behind the ratified
      # `ingestion_attempt_due` ScheduledAction (BACKGROUND_PROCESSING.md :140/:200/:378;
      # WORKFLOW_SPECIFICATIONS.md :464, :466).
      #
      # The action names the INGESTION JOB rather than the attempt, for the reason
      # `Wf005::IngestionAttemptDueSchedule` records: an attempt row created at scheduling time would
      # consume one of :466's three attempts without ever running, and would make the scheduler a
      # second producer of attempt rows.
      RunIngestionJob = Data.define(:command_id, :schema_version, :organization_id, :target_type,
                                    :ingestion_job_id, :due_at, :action_id, :action_identity_sha256,
                                    :requested_at_utc)

      class RunIngestionJob
        TYPE = "wf005.run_ingestion_job"

        def self.from_scheduled_action(action:, command_id:, requested_at_utc:)
          new(command_id:, schema_version: action.action_schema_version,
              organization_id: action.organization_id, target_type: action.target_type,
              ingestion_job_id: action.target_id, due_at: action.due_at, action_id: action.id,
              action_identity_sha256: action.identity_sha256, requested_at_utc:)
        end

        def command_type = TYPE
        def idempotency_key = action_identity_sha256
      end
    end
  end
end
