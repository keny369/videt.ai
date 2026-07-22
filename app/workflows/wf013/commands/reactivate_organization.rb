# frozen_string_literal: true

module Workflows
  module Wf013
    module Commands
      # WF-013 ReactivateOrganization under the ratified `reactivation-proof-v1`
      # decision (WORKFLOW_SPECIFICATIONS.md :270-289).
      #
      # Deliberately NOT Session-bound. Suspension revoked every human Session, so
      # there is none to authenticate with; reactivation is proved by a fresh
      # purpose-bound Identity Validation Receipt carrying `mfa_satisfied=true` and
      # binding exactly one target Organization. "Session: the command creates no
      # Session. Reactivation is not authentication."
      #
      # The acting Account is resolved from the receipt's issuer/subject inside the
      # bound Organization, and must hold `organization.reactivate`.
      ReactivateOrganization = Data.define(:command_id, :idempotency_key, :schema_version,
                                           :organization_id, :receipt_digest,
                                           :expected_state_version, :expected_authorization_epoch,
                                           :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class ReactivateOrganization
        TYPE = "wf013.reactivate_organization"

        def command_type = TYPE
      end
    end
  end
end
