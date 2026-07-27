# frozen_string_literal: true

module Workflows
  module Wf004
    module Commands
      # WF-004 ExpireSourceScopeChange — the service-only timed transition behind the
      # ratified `source_scope_request_expire` ScheduledAction that ProposeSourceScopeChange
      # schedules on a PENDING request (WORKFLOW_SPECIFICATIONS.md § Source Scope Change
      # Contract :419; contracts/S-06.json MTX-029 domain_events/transaction_boundary). Built
      # only from a claimed action; scalar identifiers only, and the handler reloads every
      # product value from PostgreSQL.
      ExpireSourceScopeChange = Data.define(:command_id, :schema_version, :organization_id, :target_type,
                                            :request_id, :due_at, :action_id,
                                            :action_identity_sha256, :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class ExpireSourceScopeChange
        TYPE = "wf004.expire_source_scope_change"

        def self.from_scheduled_action(action:, command_id:, requested_at_utc:)
          new(command_id:, schema_version: action.action_schema_version,
              organization_id: action.organization_id, target_type: action.target_type,
              request_id: action.target_id, due_at: action.due_at, action_id: action.id,
              action_identity_sha256: action.identity_sha256, requested_at_utc:)
        end

        def command_type = TYPE
        def idempotency_key = action_identity_sha256
      end
    end
  end
end
