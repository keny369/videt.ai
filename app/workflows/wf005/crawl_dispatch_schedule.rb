# frozen_string_literal: true

module Workflows
  module Wf005
    # The canonical creation point of a queued Crawl's start dispatch
    # (BACKGROUND_PROCESSING.md :137 — `crawl_dispatch` on the `crawl` queue owns "admitted queued
    # Crawl start"; :197 it enqueues `crawl_orchestrate`; :377 whose permitted operations are
    # `StartCrawl`, `CompleteCrawl`, `FailCrawl` or `CancelCrawl` "selected solely from persisted
    # Crawl/deadline state").
    #
    # It is the Verification-Request / Source-Scope-Change expiry pattern applied to the crawl
    # action kind, using the same F-04 ScheduledAction platform rather than a second scheduler.
    # Scheduling happens on the queueing transaction's connection, so the queued Crawl and its
    # dispatch commit or roll back together: there is no fire-and-forget after commit, and a
    # rolled-back queue leaves no action to claim.
    #
    # `due_at` is the queue instant — the start is admitted immediately and the gate that decides
    # whether it may run is the `Queued -> Running` commit itself, not a timer.
    module CrawlDispatchSchedule
      module_function

      ACTION_KIND = "crawl_dispatch"
      ACTION_SCHEMA_VERSION = "1.0"
      TARGET_TYPE = "crawl"

      def schedule(pg:, organization_id:, project_id:, crawl_id:, now:, correlation_id:,
                   causation_id: nil, command_id: nil, product_generation: 0, schedule_generation: 1)
        Platform::ScheduledActions::Store.new(pg).create(
          id: Platform::Ids.system.generate, action_kind: ACTION_KIND,
          action_schema_version: ACTION_SCHEMA_VERSION, organization_id:, project_id:,
          target_type: TARGET_TYPE, target_id: crawl_id,
          product_generation:, schedule_generation:,
          due_at: now, now:, correlation_id:, causation_id: causation_id || correlation_id,
          command_id:, executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor
        )[:id]
      end
    end
  end
end
