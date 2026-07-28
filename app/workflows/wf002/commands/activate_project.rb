# frozen_string_literal: true

module Workflows
  module Wf002
    module Commands
      # WF-002 ActivateProject (S-03; contracts/S-03.json MTX-027 activation limb;
      # WORKFLOW_SPECIFICATIONS.md § WF-002 :651-666). A distinct command — never a continuation
      # of creation — transitioning a draft Project to active exactly once, gated on >=1 active
      # same-Project Source, and version-checked on the Project state version AND the
      # Source-membership version.
      ActivateProject = Data.define(:command_id, :idempotency_key, :schema_version, :session_id,
                                    :organization_id, :project_id, :expected_state_version,
                                    :expected_source_membership_version, :requested_at_utc)

      class ActivateProject
        TYPE = "wf002.activate_project"

        def command_type = TYPE
      end
    end
  end
end
