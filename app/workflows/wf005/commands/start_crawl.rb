# frozen_string_literal: true

module Workflows
  module Wf005
    module Commands
      # WF-005 StartCrawl — the service-only `Queued -> Running` commit behind the ratified
      # `crawl_dispatch` ScheduledAction that QueueCrawl schedules on the admitted queued Crawl
      # (contracts/S-07.json MTX-030: "`Workflows::Wf005::StartCrawl` (service, at the
      # Queued -> Running commit)"; BACKGROUND_PROCESSING.md :137/:197/:377).
      #
      # Built only from a claimed action; scalar identifiers only, and the handler reloads every
      # product value from PostgreSQL — an authorization or policy result established at queue
      # time is never carried here and never trusted at execution time (MTX-030
      # authorization_entry_point).
      StartCrawl = Data.define(:command_id, :schema_version, :organization_id, :target_type,
                               :crawl_id, :due_at, :action_id, :action_identity_sha256,
                               :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class StartCrawl
        TYPE = "wf005.start_crawl"

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
