# frozen_string_literal: true

module Workflows
  module Wf013
    module Commands
      # The logical command for WF-013 RevokeInvitation (WORKFLOW_SPECIFICATIONS.md
      # § invitation :246; APPLICATION_LAYER.md WF-013; slice S-23). An authenticated
      # Organization actor holding invitation.revoke revokes an active Invitation
      # belonging to its Organization. Authority derives from `session_id` (the
      # authenticated Session — the actor Account and Organization are resolved FROM
      # the Session record, never from caller input); no receipt or nonce is used.
      # `invitation_reference` is the opaque reference the authorized administrator
      # holds. A 20-2,000 trimmed-Unicode `reason` is mandatory, plus the expected
      # Invitation state version. Immutable, canonicalized values only.
      RevokeInvitation = Data.define(:command_id, :idempotency_key, :schema_version,
                                     :session_id, :invitation_reference, :expected_state_version,
                                     :reason, :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class RevokeInvitation
        TYPE = "wf013.revoke_invitation"

        def command_type = TYPE
      end
    end
  end
end
