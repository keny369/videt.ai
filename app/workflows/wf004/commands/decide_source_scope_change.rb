# frozen_string_literal: true

module Workflows
  module Wf004
    module Commands
      # WF-004 DecideSourceScopeChange (S-06-004; WORKFLOW_SPECIFICATIONS.md § Source Scope
      # Change Contract :420-421; contracts/S-06.json MTX-029). Approves or rejects a pending
      # Source Scope Change Request. `decision` is "approve" or "reject". Approval activates a
      # new immutable policy version and repoints the Source; rejection requires a 20-2,000
      # character reason and changes no scope. Both are guarded by the expected request state
      # version AND the expected active-policy version. Dual control (only an OrganizationAdmin
      # may approve or reject an EXPANSION, and an approving OrganizationAdmin must differ from
      # the non-admin requester) is evaluated in the handler.
      DecideSourceScopeChange = Data.define(
        :command_id, :idempotency_key, :schema_version, :session_id, :organization_id, :project_id,
        :source_id, :request_id, :decision, :expected_request_state_version,
        :expected_active_policy_version, :decision_reason, :requested_at_utc
      )

      class DecideSourceScopeChange
        TYPE = "wf004.decide_source_scope_change"

        def command_type = TYPE
      end
    end
  end
end
