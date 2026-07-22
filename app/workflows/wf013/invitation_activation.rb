# frozen_string_literal: true

module Workflows
  module Wf013
    # The single activation routine, shared by the two ratified paths that make an
    # Invitation active: creation of a nonprotected offer, and approval of a
    # protected one (WORKFLOW_SPECIFICATIONS.md :242 "A nonprotected invitation is
    # created directly active; a protected invitation starts pending approval …
    # A different SecurityOperator holding `invitation.approve` may activate it").
    #
    # It exists so that activation and its expiry timer cannot come apart. The
    # expiry boundary is computed here and nowhere else (":242 Active expiry is
    # exactly seven days after activation"), and the timer is created through the
    # canonical `IdentityAccess::Domain::InvitationExpirySchedule` on the SAME
    # connection the caller is already writing the Invitation with — so it joins
    # the activation transaction, and activation and timer commit or roll back
    # together. There is no second scheduler, no alternative expiry arithmetic and
    # no post-commit hook.
    module InvitationActivation
      module_function

      # ":240 `expires_at_utc=activated_at_utc+7 days`", the same window the
      # `invitation_active_expiry_is_seven_days` CHECK enforces on the row.
      ACTIVE_WINDOW_SECONDS = 7 * 24 * 3600

      Result = Data.define(:expires_at, :scheduled_action_id, :timer_replayed)

      def expires_at(activated_at) = activated_at + ACTIVE_WINDOW_SECONDS

      # Create the Invitation's expiry timer inside the caller's activation
      # transaction. `state_version` is the Invitation's version AS ACTIVATED, so
      # the timer's product generation names the generation it was scheduled for.
      def schedule_expiry(pg:, organization_id:, invitation_id:, activated_at:, state_version:,
                          correlation_id:, causation_id: nil, command_id: nil)
        scheduled = IdentityAccess::Domain::InvitationExpirySchedule.schedule(
          store: Platform::ScheduledActions::Store.new(pg),
          organization_id:, invitation_id:, expires_at: expires_at(activated_at),
          now: activated_at, correlation_id:, causation_id:, command_id:, state_version:
        )
        Result.new(expires_at: expires_at(activated_at), scheduled_action_id: scheduled[:id],
                   timer_replayed: scheduled[:replayed])
      end
    end
  end
end
