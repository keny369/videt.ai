# frozen_string_literal: true

module Workflows
  module Wf005
    module Commands
      # WF-005 RecordFetchAttempt — the service-only content-fetch pass behind the ratified
      # `crawl_fetch_due` ScheduledAction (BACKGROUND_PROCESSING.md :138/:198/:378).
      #
      # The action names the SELECTED FRONTIER ENTRY, not a fetch attempt (DECISIONS ADR-085): under
      # admission-at-execution no attempt row exists when the action is created, and creating one
      # would make the scheduler a second producer of `fetch_attempts`.
      RecordFetchAttempt = Data.define(:command_id, :schema_version, :organization_id, :target_type,
                                       :frontier_entry_id, :due_at, :action_id, :action_identity_sha256,
                                       :requested_at_utc)

      class RecordFetchAttempt
        TYPE = "wf005.record_fetch_attempt"

        def self.from_scheduled_action(action:, command_id:, requested_at_utc:)
          new(command_id:, schema_version: action.action_schema_version,
              organization_id: action.organization_id, target_type: action.target_type,
              frontier_entry_id: action.target_id, due_at: action.due_at, action_id: action.id,
              action_identity_sha256: action.identity_sha256, requested_at_utc:)
        end

        def command_type = TYPE
        def idempotency_key = action_identity_sha256
      end
    end
  end
end
