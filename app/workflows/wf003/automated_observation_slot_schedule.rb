# frozen_string_literal: true

module Workflows
  module Wf003
    # Creates the ten automated observation slot timers on the issuing transaction's
    # connection, so the Verification Request and its whole schedule commit or roll back
    # together (SCORE_EVIDENCE_MODEL.md :151; contracts/S-05.json MTX-028 background_job).
    #
    # This is the VerificationRequestExpirySchedule pattern applied to the ratified
    # `verification_observation_slot` action kind: one ScheduledAction per due slot, each
    # due at `issued_at + offset`. The ten share a target Request but have ten distinct
    # action identities because the identity preimage includes `due_at` — so each slot's
    # offset is recoverable at execution time as `due_at - issued_at`, and no per-slot
    # payload is needed. F-04 is consumed only through `ScheduledActions::Store#create`;
    # the `AutomatedObservationSlot` handler that runs when each is due is registered
    # separately.
    module AutomatedObservationSlotSchedule
      module_function

      ACTION_KIND = "verification_observation_slot"
      ACTION_SCHEMA_VERSION = "1.0"
      TARGET_TYPE = "verification_request"

      # Schedule all ten slots on `pg` (the issuing transaction). Each due_at is
      # issued_at + offset minutes. Returns the created action ids in slot order.
      def schedule(pg:, organization_id:, project_id:, verification_request_id:, issued_at:, now:,
                   correlation_id:, causation_id: nil, command_id: nil, state_version: 0, schedule_generation: 1)
        store = Platform::ScheduledActions::Store.new(pg)
        AutomatedObservationSlots.offsets_minutes.map do |offset|
          store.create(
            id: Platform::Ids.system.generate, action_kind: ACTION_KIND,
            action_schema_version: ACTION_SCHEMA_VERSION, organization_id:, project_id:,
            target_type: TARGET_TYPE, target_id: verification_request_id,
            product_generation: state_version, schedule_generation:,
            due_at: issued_at + (offset * 60), now:, correlation_id:,
            causation_id: causation_id || correlation_id, command_id:,
            executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor
          )[:id]
        end
      end
    end
  end
end
