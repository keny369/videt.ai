# frozen_string_literal: true

module Workflows
  module Wf004
    module Handlers
      # WF-004 ActivateSource — the verified -> active lifecycle transition (S-06-006; PRULE-006 /
      # contracts/S-06.json MTX-057). All behaviour is the shared SourceLifecycleTransition;
      # this class only names the edge.
      class ActivateSource
        ACTION = "source.activate"
        CAPABILITY = "source.lifecycle.manage"
        FROM_STATE = "verified"
        TO_STATE = "active"
        EVENT_TYPE = "SourceActivated"
        TIMESTAMP_COLUMN = "activated_at"

        include Wf004::Handlers::SourceLifecycleTransition
      end
    end
  end
end
