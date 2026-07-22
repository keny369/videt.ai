# frozen_string_literal: true

module Workflows
  module Wf013
    module Commands
      # WF-013 DecideInvitation (WORKFLOW_SPECIFICATIONS.md :242 "A different
      # SecurityOperator holding `invitation.approve` may activate it"; :333 the
      # protected-grant rules and "approval within 24 hours by a SecurityOperator
      # other than the requester"). Approving a pending-approval Invitation
      # activates it; rejecting it is terminal and grants nothing.
      #
      # Authority derives from `session_id`; the deciding Account and Organization
      # are resolved FROM the Session. `decision` is `approve` or `reject`, and a
      # rejection carries the same 20-2,000 character reason a revocation does.
      DecideInvitation = Data.define(:command_id, :idempotency_key, :schema_version, :session_id,
                                     :invitation_id, :expected_state_version, :decision, :reason,
                                     :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class DecideInvitation
        TYPE = "wf013.decide_invitation"

        def command_type = TYPE
      end
    end
  end
end
