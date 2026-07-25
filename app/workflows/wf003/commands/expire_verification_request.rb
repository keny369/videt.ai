# frozen_string_literal: true

module Workflows
  module Wf003
    module Commands
      # WF-003 ExpireVerificationRequest — the service-only timed transition behind the
      # ratified `verification_request_expire` ScheduledAction that
      # IssueVerificationChallenge schedules (SCORE_EVIDENCE_MODEL.md § Attempts,
      # Expiry, And Evidence; contracts/S-05.json MTX-028/005 background_job/terminal).
      # Built only from a claimed action; scalar identifiers only, and the handler
      # reloads every product value from PostgreSQL.
      ExpireVerificationRequest = Data.define(:command_id, :schema_version, :organization_id, :target_type,
                                              :verification_request_id, :due_at, :action_id,
                                              :action_identity_sha256, :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class ExpireVerificationRequest
        TYPE = "wf003.expire_verification_request"

        def self.from_scheduled_action(action:, command_id:, requested_at_utc:)
          new(command_id:, schema_version: action.action_schema_version,
              organization_id: action.organization_id, target_type: action.target_type,
              verification_request_id: action.target_id, due_at: action.due_at, action_id: action.id,
              action_identity_sha256: action.identity_sha256, requested_at_utc:)
        end

        def command_type = TYPE
        def idempotency_key = action_identity_sha256
      end
    end
  end
end
