# frozen_string_literal: true

module Workflows
  module Wf005
    module Commands
      # WF-005 ActivateCrawlPolicy (S-07-001; contracts/S-07.json MTX-030 policy limb, MTX-059
      # PRULE-008; WORKFLOW_SPECIFICATIONS.md § policy subflow :732). Activates a more
      # restrictive immutable crawl policy version at Organization scope (OrganizationAdmin) or
      # Project scope (MarketingOperator). Narrowing-only: every proposed dimension value must be
      # at or below the resolved parent and the frozen global safety ceiling, and soft <= hard.
      # A stale, broader, incomplete or unauthorized version changes nothing.
      #
      # `scope` is "organization" (project_id null) or "project" (project_id set).
      # `expected_current_policy_version` is the active version being superseded for this scope,
      # or null for the first activation. `expected_parent_policy_version` and
      # `expected_global_version` pin the validation baseline (the active Organization policy /
      # the frozen crawl-policy-v1 global ceiling). `proposed_bounds` is the complete twelve-
      # dimension {dimension => {"soft"=>Integer, "hard"=>Integer}} map.
      ActivateCrawlPolicy = Data.define(
        :command_id, :idempotency_key, :schema_version, :session_id, :organization_id, :scope,
        :project_id, :expected_current_policy_version, :expected_parent_policy_version,
        :expected_global_version, :proposed_bounds, :requested_at_utc
      )

      class ActivateCrawlPolicy
        TYPE = "wf005.activate_crawl_policy"

        def command_type = TYPE
      end
    end
  end
end
