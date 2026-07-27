# frozen_string_literal: true

module Workflows
  module Wf004
    module Commands
      # WF-004 DisableSource (S-06-006; PRULE-006 / contracts/S-06.json MTX-057). Transitions an
      # active Source to disabled, guarded by the expected Source state version, with an optional
      # 1-2,000 character reason. Disable applies the running-Crawl restriction at S-07's next
      # checkpoint; the affected-run decision record is degenerate (empty) pre-S-07.
      DisableSource = Data.define(:command_id, :idempotency_key, :schema_version, :session_id,
                                  :organization_id, :project_id, :source_id, :expected_state_version,
                                  :lifecycle_reason, :requested_at_utc)

      class DisableSource
        TYPE = "wf004.disable_source"

        def command_type = TYPE
      end
    end
  end
end
