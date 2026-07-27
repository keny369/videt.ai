# frozen_string_literal: true

module Workflows
  module Wf004
    module Commands
      # WF-004 ActivateSource (S-06-006; PRULE-006 / contracts/S-06.json MTX-057). Transitions
      # a verified Source to active, guarded by the expected Source state version. Activation of
      # an unverified Source is denied.
      ActivateSource = Data.define(:command_id, :idempotency_key, :schema_version, :session_id,
                                   :organization_id, :project_id, :source_id, :expected_state_version,
                                   :requested_at_utc)

      class ActivateSource
        TYPE = "wf004.activate_source"

        def command_type = TYPE
      end
    end
  end
end
