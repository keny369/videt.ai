# frozen_string_literal: true

module Workflows
  module Wf004
    module Commands
      # WF-004 ReactivateSource (S-06-006; PRULE-006 / contracts/S-06.json MTX-057). Transitions
      # a disabled Source back to active, guarded by the expected Source state version.
      ReactivateSource = Data.define(:command_id, :idempotency_key, :schema_version, :session_id,
                                     :organization_id, :project_id, :source_id, :expected_state_version,
                                     :requested_at_utc)

      class ReactivateSource
        TYPE = "wf004.reactivate_source"

        def command_type = TYPE
      end
    end
  end
end
