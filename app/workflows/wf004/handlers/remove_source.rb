# frozen_string_literal: true

module Workflows
  module Wf004
    module Handlers
      # WF-004 RemoveSource — the disabled -> removed lifecycle transition (S-06-006; PRULE-006 /
      # contracts/S-06.json MTX-057). Removal is allowed ONLY from disabled; the non-removed host
      # uniqueness index frees the canonical host so a later registration starts a fresh lineage.
      # Records the (degenerate pre-S-07) affected-running-Crawl decision record. All behaviour is
      # the shared SourceLifecycleTransition.
      class RemoveSource
        ACTION = "source.remove"
        CAPABILITY = "source.lifecycle.manage"
        FROM_STATE = "disabled"
        TO_STATE = "removed"
        EVENT_TYPE = "SourceRemoved"
        TIMESTAMP_COLUMN = "removed_at"

        include Wf004::Handlers::SourceLifecycleTransition
      end
    end
  end
end
