# frozen_string_literal: true

module Workflows
  module Wf004
    module Commands
      # WF-004 RemoveSource (S-06-006; PRULE-006 / contracts/S-06.json MTX-057). Transitions a
      # disabled Source to removed (removal is allowed ONLY from disabled), guarded by the
      # expected Source state version, with an optional 1-2,000 character reason. Re-registration
      # never attaches to the removed lineage (the non-removed host uniqueness index frees the
      # host on removal). The affected-run decision record is degenerate (empty) pre-S-07.
      RemoveSource = Data.define(:command_id, :idempotency_key, :schema_version, :session_id,
                                 :organization_id, :project_id, :source_id, :expected_state_version,
                                 :lifecycle_reason, :requested_at_utc)

      class RemoveSource
        TYPE = "wf004.remove_source"

        def command_type = TYPE
      end
    end
  end
end
