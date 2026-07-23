# frozen_string_literal: true

module Workflows
  module Wf002
    module Commands
      # WF-002 CreateProject (WORKFLOW_SPECIFICATIONS.md :648-659; CAP-003 MTX-003;
      # PRULE-003 MTX-054; API_CONTRACTS.md ATTR-CreateProject :434). The command
      # that creates one draft Project inside the caller's active Organization from
      # a complete `project-profile-v1` body.
      #
      # The caller supplies only semantic input: the Session it acts through, the
      # Organization it intends to act in (checked against the Session, never
      # trusted as authority), the raw ProjectProfile, and the transport envelope
      # fields. It never supplies the generated Project id, the draft state, the
      # state version, the profile content hash, the committed time, or any
      # lifecycle or authorization outcome — those are the commit's own.
      #
      # This is CreateProject only. Project activation (WF-002 draft->active) is a
      # distinct, later command whose prerequisite is at least one active
      # same-Project Source (CAP-003), owned by S-04/S-05/S-06 and not built here.
      CreateProject = Data.define(
        :command_id, :idempotency_key, :schema_version, :session_id, :organization_id,
        :profile, :requested_at_utc
      )

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class CreateProject
        TYPE = "wf002.create_project"

        def command_type = TYPE
      end
    end
  end
end
