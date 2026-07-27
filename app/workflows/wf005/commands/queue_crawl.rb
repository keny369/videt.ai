# frozen_string_literal: true

module Workflows
  module Wf005
    module Commands
      # WF-005 QueueCrawl (S-07-002; contracts/S-07.json MTX-030 queue limb, MTX-058 PRULE-007;
      # WORKFLOW_SPECIFICATIONS.md § WF-005 :725-728). Creates a root ('initial-assessment')
      # queued Crawl pinning the request-time crawl-policy + entitlement-policy versions and the
      # active Source set; it reserves NO usage and creates NO Evaluation. The reassessment-child
      # branch is deferred to the WF-011 slice (DECISIONS ADR-067 D4), so this command always
      # queues a root Crawl.
      QueueCrawl = Data.define(:command_id, :idempotency_key, :schema_version, :session_id,
                               :organization_id, :project_id, :requested_at_utc)

      class QueueCrawl
        TYPE = "wf005.queue_crawl"

        def command_type = TYPE
      end
    end
  end
end
