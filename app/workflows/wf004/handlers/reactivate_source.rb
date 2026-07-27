# frozen_string_literal: true

module Workflows
  module Wf004
    module Handlers
      # WF-004 ReactivateSource — the disabled -> active lifecycle transition (S-06-006; PRULE-006 /
      # contracts/S-06.json MTX-057). Emits SourceActivated (the contract names three lifecycle
      # events; reactivation is the disabled -> active edge). All behaviour is the shared
      # SourceLifecycleTransition.
      class ReactivateSource
        ACTION = "source.reactivate"
        CAPABILITY = "source.lifecycle.manage"
        FROM_STATE = "disabled"
        TO_STATE = "active"
        EVENT_TYPE = "SourceActivated"
        TIMESTAMP_COLUMN = "activated_at"

        include Wf004::Handlers::SourceLifecycleTransition
      end
    end
  end
end
