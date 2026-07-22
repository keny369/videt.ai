# frozen_string_literal: true

module Workflows
  module Wf013
    module Commands
      # WF-013 DecideRoleAssignment — approval or rejection of a pending protected
      # Role Assignment (:316, :333 "approval within 24 hours by a SecurityOperator
      # other than the requester … rejection or expiry grants nothing").
      DecideRoleAssignment = Data.define(:command_id, :idempotency_key, :schema_version, :session_id,
                                         :role_assignment_id, :expected_state_version,
                                         :expected_authorization_epoch, :decision, :reason,
                                         :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class DecideRoleAssignment
        TYPE = "wf013.decide_role_assignment"

        def command_type = TYPE
      end
    end
  end
end
