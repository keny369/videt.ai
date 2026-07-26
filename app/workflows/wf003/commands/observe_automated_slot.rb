# frozen_string_literal: true

module Workflows
  module Wf003
    module Commands
      # WF-003 ObserveAutomatedSlot — the service-only automated observation behind a
      # ratified `verification_observation_slot` ScheduledAction that
      # IssueVerificationChallenge schedules (SCORE_EVIDENCE_MODEL.md :151;
      # contracts/S-05.json MTX-028 background_job/retry_policy). Built only from a
      # claimed action; scalar identifiers only, and the handler reloads every product
      # value from PostgreSQL. The slot's due offset is recovered as `due_at - issued_at`.
      ObserveAutomatedSlot = Data.define(:command_id, :schema_version, :organization_id, :target_type,
                                         :verification_request_id, :due_at, :action_id,
                                         :action_identity_sha256, :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class ObserveAutomatedSlot
        TYPE = "wf003.observe_automated_slot"

        def self.from_scheduled_action(action:, command_id:, requested_at_utc:)
          new(command_id:, schema_version: action.action_schema_version,
              organization_id: action.organization_id, target_type: action.target_type,
              verification_request_id: action.target_id, due_at: action.due_at, action_id: action.id,
              action_identity_sha256: action.identity_sha256, requested_at_utc:)
        end

        def command_type = TYPE
        # The slot's skip / terminal-void records are idempotent by the action identity
        # (as ExpireVerificationRequest is). A started observation is instead idempotent
        # by its reserved attempt identity, inside CompleteVerificationAttempt.
        def idempotency_key = action_identity_sha256
      end
    end
  end
end
