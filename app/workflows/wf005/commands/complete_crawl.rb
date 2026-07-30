# frozen_string_literal: true

module Workflows
  module Wf005
    module Commands
      # WF-005 CompleteCrawl — the service-only terminal checkpoint behind the ratified
      # `crawl_terminal_deadline` ScheduledAction that the accepted start schedules on the running
      # Crawl (BACKGROUND_PROCESSING.md :139 "exact 60-minute terminal checkpoint", :199
      # `crawl_orchestrate`, :377; WORKFLOW_SPECIFICATIONS.md :458).
      #
      # ONE COMMAND FOR TWO OF :377's FOUR OPERATIONS, and that is the ratified shape rather than a
      # convenience: ":377 — `StartCrawl`, `CompleteCrawl`, `FailCrawl`, or `CancelCrawl`, SELECTED
      # SOLELY FROM PERSISTED CRAWL/DEADLINE STATE." The selection is the handler's, taken from what the
      # run recorded, and the audit record and the event say which of the two it made. `CancelCrawl` is
      # not among them here: it is an actor command with its own permission and its own route
      # (API_CONTRACTS.md :279), and :458 settles it by ORDER OF COMMIT rather than by derivation.
      #
      # Built only from a claimed action; scalar identifiers only, and the handler reloads every product
      # value from PostgreSQL under the Crawl row lock.
      CompleteCrawl = Data.define(:command_id, :schema_version, :organization_id, :target_type,
                                  :crawl_id, :due_at, :action_id, :action_identity_sha256,
                                  :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class CompleteCrawl
        TYPE = "wf005.complete_crawl"

        def self.from_scheduled_action(action:, command_id:, requested_at_utc:)
          new(command_id:, schema_version: action.action_schema_version,
              organization_id: action.organization_id, target_type: action.target_type,
              crawl_id: action.target_id, due_at: action.due_at, action_id: action.id,
              action_identity_sha256: action.identity_sha256, requested_at_utc:)
        end

        def command_type = TYPE
        def idempotency_key = action_identity_sha256
      end
    end
  end
end
