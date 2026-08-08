# frozen_string_literal: true

module Workflows
  module Wf007
    module Commands
      # WF-007 ExecuteCheckAttempt — one attempt of one materialized expected key, behind the
      # ratified `check_attempt_due` ScheduledAction whose target is the Check Result SLOT.
      #
      # The Slot rather than the Result, deliberately: the Slot exists before execution and
      # carries the preallocated Check Result identity, so a crashed attempt has something to
      # return to. Targeting a Result would mean naming a row that does not exist yet.
      ExecuteCheckAttempt = Data.define(:command_id, :schema_version, :organization_id, :target_type,
                                        :slot_id, :attempt_number, :due_at, :action_id,
                                        :action_identity_sha256, :requested_at_utc)

      class ExecuteCheckAttempt
        TYPE = "wf007.execute_check_attempt"

        def self.from_scheduled_action(action:, command_id:, requested_at_utc:)
          new(command_id:, schema_version: action.action_schema_version,
              organization_id: action.organization_id, target_type: action.target_type,
              slot_id: action.target_id, attempt_number: action.product_generation.to_i,
              due_at: action.due_at, action_id: action.id,
              action_identity_sha256: action.identity_sha256, requested_at_utc:)
        end

        def command_type = TYPE
        def idempotency_key = action_identity_sha256
      end
    end
  end
end
