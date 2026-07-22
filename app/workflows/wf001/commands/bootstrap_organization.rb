# frozen_string_literal: true

module Workflows
  module Wf001
    module Commands
      # WF-001 self-service BootstrapOrganization (WORKFLOW_SPECIFICATIONS.md :238,
      # :627-629; CAP-002 MTX-002; PRULE-002 MTX-053). The one command that
      # establishes an entire tenant: Organization, Account, BillingEntity, first
      # OrganizationAdmin Assignment, baseline Access and Entitlement policies,
      # BillingEntity-linked Plan Assignment, and the draft Project — atomically,
      # under a valid Bootstrap Grant, with no billing-provider call.
      #
      # The caller states the profile, the first-Project body, the expected grant
      # version and the three baseline content hashes it approves. It never chooses
      # generated identifiers, lifecycle branches, baseline permissions, entitlement
      # contents or genesis sequencing — those are the commit's own.
      BootstrapOrganization = Data.define(
        :command_id, :idempotency_key, :schema_version, :receipt_digest, :expected_grant_version,
        :organization_display_name, :project_display_name, :project_objective,
        :access_policy_content_sha256, :entitlement_policy_content_sha256, :plan_content_sha256,
        :requested_at_utc
      )

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class BootstrapOrganization
        TYPE = "wf001.bootstrap_organization"

        def command_type = TYPE
      end
    end
  end
end
