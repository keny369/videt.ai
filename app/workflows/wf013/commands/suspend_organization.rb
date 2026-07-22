# frozen_string_literal: true

module Workflows
  module Wf013
    module Commands
      # WF-013 SuspendOrganization (016 STATE_MODEL.md :97 the Organization row;
      # contracts/S-23.json MTX-038 transaction boundary; Permission Baseline :138
      # `organization.suspend` "allow for own Organization").
      #
      # Authority derives from `session_id`; the acting Account and the target
      # Organization are resolved FROM the Session, so an actor cannot name another
      # Organization. Both the expected state version and the expected authorization
      # epoch are carried, exactly as :97 requires.
      SuspendOrganization = Data.define(:command_id, :idempotency_key, :schema_version, :session_id,
                                        :expected_state_version, :expected_authorization_epoch,
                                        :reason, :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class SuspendOrganization
        TYPE = "wf013.suspend_organization"

        def command_type = TYPE
      end
    end
  end
end
