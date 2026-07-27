# frozen_string_literal: true

module Workflows
  module Wf004
    module Handlers
      # WF-004 DisableSource — the active -> disabled lifecycle transition (S-06-006; PRULE-006 /
      # contracts/S-06.json MTX-057). Records the (degenerate pre-S-07) affected-running-Crawl
      # decision record. All behaviour is the shared SourceLifecycleTransition.
      class DisableSource
        ACTION = "source.disable"
        CAPABILITY = "source.lifecycle.manage"
        FROM_STATE = "active"
        TO_STATE = "disabled"
        EVENT_TYPE = "SourceDisabled"
        TIMESTAMP_COLUMN = "disabled_at"

        include Wf004::Handlers::SourceLifecycleTransition
      end
    end
  end
end
