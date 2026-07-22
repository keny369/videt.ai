# frozen_string_literal: true

module Workflows
  module Wf013
    module Commands
      # WF-013 RequestRoleAssignment (WORKFLOW_SPECIFICATIONS.md :314 the Role
      # Assignment record, :316 the state machine, :333 protected approval;
      # contracts/S-23.json MTX-038).
      #
      # Authority derives from `session_id`; the requester and Organization are
      # resolved FROM the Session. The requester states the grant it wants to make
      # and NOT whether that grant needs approval — the offered role decides,
      # exactly as it does for an Invitation.
      RequestRoleAssignment = Data.define(:command_id, :idempotency_key, :schema_version, :session_id,
                                          :account_id, :canonical_role, :permission_mode, :persona,
                                          :scope_sha256, :expires_at, :expected_authorization_epoch,
                                          :reason, :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class RequestRoleAssignment
        TYPE = "wf013.request_role_assignment"

        def command_type = TYPE
      end
    end
  end
end
