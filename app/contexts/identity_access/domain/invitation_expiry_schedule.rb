# frozen_string_literal: true

module IdentityAccess
  module Domain
    # The canonical creation point of an Invitation's expiry timer.
    #
    # WORKFLOW_SPECIFICATIONS.md :242 fixes the boundary: "Active expiry is
    # exactly seven days after activation", i.e. `expires_at_utc =
    # activated_at_utc + 7 days` (:240), enforced by the
    # `invitation_active_expiry_is_seven_days` CHECK. The timer that effects it is
    # a `scheduled_action`, because `scheduled_actions` is the sole physical timer
    # authority and a domain column "MUST NOT be independently polled"
    # (BACKGROUND_PROCESSING.md :90).
    #
    # So the canonical creation point is the ACTIVATION transaction: the same
    # atomic commit that sets `activated_at`/`expires_at` and takes the Invitation
    # to `active` — a nonprotected Invitation's creation, or a protected
    # Invitation's approval (:242). This operation is that step, and it is called
    # with the activating transaction's connection so the timer and the activation
    # commit or roll back together: an Invitation can never become active without
    # its expiry timer, and a rolled-back creation leaves no orphan timer.
    #
    # ESCALATION: the ratified callers `Workflows::Wf013::CreateInvitation` and
    # `DecideInvitation` (contracts/S-23.json) are not implemented in this slice,
    # so nothing in app/ activates an Invitation yet. This operation is the
    # boundary they must call; until they exist the acceptance suite arranges the
    # precondition through it, exactly as it already arranges Invitations
    # themselves.
    #
    # The action is scheduled exactly once per (Organization, Invitation,
    # expiry boundary): the identity preimage carries all three, so a duplicate
    # scheduling attempt is an exact creation replay that returns the existing row
    # and writes nothing (BACKGROUND_PROCESSING.md :106). A changed expiry
    # boundary is not an update — `due_at` is immutable — but a new action at the
    # next `schedule_generation`, which is why reissue (a new Invitation) and any
    # future re-activation both remain expressible without mutating a timer.
    module InvitationExpirySchedule
      module_function

      ACTION_KIND = "invitation_expire"
      ACTION_SCHEMA_VERSION = "1.0"
      TARGET_TYPE = "invitation"

      # Create (or exactly replay) the expiry timer for one activated Invitation.
      # `store` is a Platform::ScheduledActions::Store on the activating
      # transaction's connection, already inside the Invitation's Organization
      # context. Returns the Store result ({ id:, replayed:, collision_ordinal: }).
      def schedule(store:, organization_id:, invitation_id:, expires_at:, now:,
                   correlation_id:, causation_id: nil, command_id: nil,
                   state_version: 0, schedule_generation: 1, action_id: nil)
        store.create(
          id: action_id || Platform::Ids.system.generate,
          action_kind: ACTION_KIND, action_schema_version: ACTION_SCHEMA_VERSION,
          organization_id:, target_type: TARGET_TYPE, target_id: invitation_id,
          # The Invitation's state version at activation is the owning product
          # record's generation for this timer (BACKGROUND_PROCESSING.md :80).
          product_generation: state_version, schedule_generation:,
          due_at: expires_at, now:, correlation_id:, causation_id: causation_id || correlation_id,
          command_id:, executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor
        )
      end
    end
  end
end
