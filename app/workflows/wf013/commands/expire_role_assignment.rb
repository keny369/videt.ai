# frozen_string_literal: true

module Workflows
  module Wf013
    module Commands
      # WF-013 ExpireRoleAssignment — the service-only timed transition behind the
      # ratified `role_assignment_expire` ScheduledAction
      # (BACKGROUND_PROCESSING.md :132, :192, :406; WORKFLOW_SPECIFICATIONS.md
      # :316). Built only from a claimed action; scalar identifiers only, and the
      # handler reloads every product value from PostgreSQL.
      ExpireRoleAssignment = Data.define(:command_id, :schema_version, :organization_id, :target_type,
                                         :role_assignment_id, :due_at, :action_id,
                                         :action_identity_sha256, :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class ExpireRoleAssignment
        TYPE = "wf013.expire_role_assignment"

        def self.from_scheduled_action(action:, command_id:, requested_at_utc:)
          new(command_id:, schema_version: action.action_schema_version,
              organization_id: action.organization_id, target_type: action.target_type,
              role_assignment_id: action.target_id, due_at: action.due_at, action_id: action.id,
              action_identity_sha256: action.identity_sha256, requested_at_utc:)
        end

        def command_type = TYPE
        def idempotency_key = action_identity_sha256
      end
    end
  end
end
