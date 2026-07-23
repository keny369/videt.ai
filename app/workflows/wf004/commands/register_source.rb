# frozen_string_literal: true

module Workflows
  module Wf004
    module Commands
      # WF-004 RegisterSource (WORKFLOW_SPECIFICATIONS.md :398-408 the
      # `source-registration-v1` contract, :704 the WF-004 registration step;
      # CAP-004 MTX-004; contracts/S-04.json). The command that registers exactly
      # one proposed Source against a Project from one absolute HTTPS root URI.
      #
      # The caller supplies only semantic input: the Session it acts through, the
      # intended Organization (checked against the Session, never trusted as
      # authority), the target Project and its expected state version, the
      # `source-registration-v1` declaration, the submitted root URI, and the
      # transport envelope. The registration provenance — origin, registering
      # Account, command id, idempotency key, authorization-decision id, registered
      # time and correlation id — is DERIVED from the command and the authorization
      # decision, never supplied, so every Source carries proof of the decision
      # that created it.
      #
      # Registration only proposes a Source. It never verifies, activates, crawls
      # or creates Evidence; each is a separate command in a later slice
      # (S-05/S-06).
      RegisterSource = Data.define(
        :command_id, :idempotency_key, :schema_version, :session_id, :organization_id,
        :project_id, :registration_schema_version, :submitted_root_uri, :expected_state_version,
        :requested_at_utc
      )

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class RegisterSource
        TYPE = "wf004.register_source"

        def command_type = TYPE
      end
    end
  end
end
