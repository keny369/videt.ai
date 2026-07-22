# frozen_string_literal: true

module Workflows
  module Wf013
    module Commands
      # WF-013 RevokeRoleAssignment — the canonical human-commanded removal of an
      # active Role Assignment (:316 "active to revoked or expired. Revoked …
      # terminal"; :936 "A Role Assignment revoke … that removes effective
      # OrganizationAdmin authority atomically validates the Organization
      # authorization epoch and the same last-admin invariant as an Account
      # action").
      #
      # It carries BOTH expected versions because it changes effective access:
      # ":930 every command on an existing record includes its expected record
      # state version and expected Organization authorization epoch when effective
      # access could change."
      RevokeRoleAssignment = Data.define(:command_id, :idempotency_key, :schema_version, :session_id,
                                         :role_assignment_id, :expected_state_version,
                                         :expected_authorization_epoch, :reason, :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class RevokeRoleAssignment
        TYPE = "wf013.revoke_role_assignment"

        def command_type = TYPE
      end
    end
  end
end
