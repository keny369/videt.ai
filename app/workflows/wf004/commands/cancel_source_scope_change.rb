# frozen_string_literal: true

module Workflows
  module Wf004
    module Commands
      # WF-004 CancelSourceScopeChange (S-06-004; WORKFLOW_SPECIFICATIONS.md § Source Scope
      # Change Contract :421; contracts/S-06.json MTX-029). The requester or an
      # OrganizationAdmin cancels a PENDING request, guarded by the expected request state
      # version, with a 20-2,000 character reason. Cancellation changes no policy or Source
      # state and emits SourceScopeChangeCanceled.
      CancelSourceScopeChange = Data.define(
        :command_id, :idempotency_key, :schema_version, :session_id, :organization_id, :project_id,
        :source_id, :request_id, :expected_request_state_version, :cancel_reason, :requested_at_utc
      )

      class CancelSourceScopeChange
        TYPE = "wf004.cancel_source_scope_change"

        def command_type = TYPE
      end
    end
  end
end
