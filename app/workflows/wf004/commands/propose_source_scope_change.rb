# frozen_string_literal: true

module Workflows
  module Wf004
    module Commands
      # WF-004 ProposeSourceScopeChange (WORKFLOW_SPECIFICATIONS.md § Source Scope Change
      # Contract :414, :705; APPLICATION_LAYER.md § WF-004; contracts/S-06.json MTX-029).
      # Proposes a Source Scope Change against a verified Source's current active policy.
      #
      # The caller supplies the Session it acts through, the intended Organization
      # (checked against the Session, never trusted as authority), the Project and Source,
      # the EXPECTED active policy version, the PROPOSED normalized scope rules (schemes,
      # ports, include/exclude path prefixes, query handling) and a 20-2,000 character
      # request reason. The Source's verified `canonical_host` is authoritative and is NOT
      # a command input: a scope change never changes the host (a new host is a new Source
      # through WF-003), so the host is always the Source's verified host.
      #
      # S-06-003 creates a PENDING request only. Classification (S-06-002) rejects boundary
      # violations; a contraction otherwise remains pending here (the fail-closed interim),
      # and atomic contraction activation / decision are S-06-004.
      ProposeSourceScopeChange = Data.define(
        :command_id, :idempotency_key, :schema_version, :session_id, :organization_id,
        :project_id, :source_id, :expected_active_policy_version,
        :proposed_allowed_schemes, :proposed_allowed_ports, :proposed_include_prefixes,
        :proposed_exclude_prefixes, :proposed_query_handling, :request_reason, :requested_at_utc
      )

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class ProposeSourceScopeChange
        TYPE = "wf004.propose_source_scope_change"

        def command_type = TYPE
      end
    end
  end
end
