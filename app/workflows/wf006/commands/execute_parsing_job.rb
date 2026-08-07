# frozen_string_literal: true

module Workflows
  module Wf006
    module Commands
      # WF-006 ExecuteParsingJob — one attempt of one ParsingJob, behind the ratified
      # `parsing_attempt_due` ScheduledAction (WORKFLOW_SPECIFICATIONS.md :474-484).
      #
      # Service-only: "tenant-scoped parsing/evaluation/indexing service identities execute
      # and retry". Scalar identifiers only; the handler reloads every product value from
      # PostgreSQL and reveals the input bytes behind F-02.
      ExecuteParsingJob = Data.define(:command_id, :schema_version, :organization_id, :target_type,
                                      :parsing_job_id, :due_at, :action_id, :action_identity_sha256,
                                      :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class ExecuteParsingJob
        TYPE = "wf006.execute_parsing_job"

        def self.from_scheduled_action(action:, command_id:, requested_at_utc:)
          new(command_id:, schema_version: action.action_schema_version,
              organization_id: action.organization_id, target_type: action.target_type,
              parsing_job_id: action.target_id, due_at: action.due_at, action_id: action.id,
              action_identity_sha256: action.identity_sha256, requested_at_utc:)
        end

        def command_type = TYPE
        def idempotency_key = action_identity_sha256
      end
    end
  end
end
