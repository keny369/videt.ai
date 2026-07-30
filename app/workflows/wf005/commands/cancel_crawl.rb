# frozen_string_literal: true

module Workflows
  module Wf005
    module Commands
      # WF-005 CancelCrawl (S-07-009; WORKFLOW_SPECIFICATIONS.md :736, :738, :458;
      # API_CONTRACTS.md :279; APPLICATION_LAYER.md § WF-005).
      #
      # An ACTOR command, not a scheduled action, and that is what :458's boundary rests on: "a
      # cancellation committed strictly BEFORE that checkpoint yields `Crawl.Canceled`; a cancellation
      # at or after the checkpoint is rejected as `crawl_already_terminal`." The order is decided by
      # which transaction commits first, so the cancellation has to be a command a person issues rather
      # than an outcome the checkpoint derives.
      #
      # `expected_state_version` is MTX-030's request schema for this command ("Cancel: Crawl ID,
      # expected state version"), and it is the second half of the same boundary: a cancellation
      # holding a version the run has since moved past is refused rather than applied to a Crawl its
      # sender was not looking at.
      CancelCrawl = Data.define(:command_id, :idempotency_key, :schema_version, :session_id,
                                :organization_id, :project_id, :crawl_id, :expected_state_version,
                                :requested_at_utc)

      class CancelCrawl
        TYPE = "wf005.cancel_crawl"

        def command_type = TYPE
      end
    end
  end
end
