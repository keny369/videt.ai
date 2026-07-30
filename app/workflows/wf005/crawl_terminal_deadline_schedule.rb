# frozen_string_literal: true

module Workflows
  module Wf005
    # The canonical creation point of a running Crawl's terminal checkpoint
    # (BACKGROUND_PROCESSING.md :139 — `crawl_terminal_deadline` on the `crawl` queue owns the "exact
    # 60-minute terminal checkpoint"; :199 it enqueues `crawl_orchestrate` against the "`work_executions`
    # Crawl/deadline identity"; :377 whose permitted operations are `StartCrawl`, `CompleteCrawl`,
    # `FailCrawl` or `CancelCrawl` "selected solely from persisted Crawl/deadline state").
    #
    # NOTHING CREATED THIS ACTION UNTIL NOW, which FU-22 recorded as S-07-009's: ":442's 60-minute wall
    # clock bounds a stranded claim in the meantime, and note that nothing yet SCHEDULES
    # `crawl_terminal_deadline`, so the bound is not currently enforced by anything either." A run whose
    # frontier stopped advancing stayed `running` for ever, because the chain only links forward from a
    # pass and a run with nothing to pass over creates no link.
    #
    # ON THE ACCEPTED-START TRANSACTION, so the checkpoint and the run it bounds commit together. This is
    # the same rule :378 applies to the fetch chain and the same one `CrawlDispatchSchedule` applies to
    # the start: a rolled-back start leaves no action to claim, and an accepted start cannot commit
    # without its terminal checkpoint. The alternative — creating it after the commit — has the failure
    # mode the whole subsystem is built to avoid: a `running` Crawl with no terminal action at all.
    #
    # TWO CALLERS, TWO INSTANTS, ONE KIND (DECISIONS ADR-101).
    #
    #   * THE ACCEPTED START passes `crawls.deadline_at` — :139's "exact 60-minute terminal checkpoint",
    #     and the run's OWN resolved deadline rather than a second derivation of sixty minutes, because
    #     the effective policy bounds may be narrower and every other reader uses the column.
    #   * A PASS THAT DRAINS THE FRONTIER passes its own instant, because a run that has finished its
    #     work must reach its checkpoint NOW. That is not a latency preference: it was forced by
    #     evidence. :551 caps the entitlement lease at fifteen minutes since the last heartbeat, and
    #     `Entitlement::Service#commit` RELEASES rather than commits at or after that instant — so with
    #     a deadline-only checkpoint, every run that finished its work before minute forty-five (which
    #     is every ordinary run) released its reservation, and `crawl.start` could never be committed
    #     against a customer's entitlement at all. Demonstrated by PROOF 60 before the second caller
    #     existed.
    #
    # The two are DISTINCT IDENTITIES — `Identity.preimage` includes `due_at` — so both exist and both
    # fire. That is safe by construction rather than by luck: :458 makes terminal selection happen once,
    # the handler takes the Crawl row lock, and whichever arrives second finds the Crawl terminal and
    # records `crawl_already_terminal` without deciding anything.
    module CrawlTerminalDeadlineSchedule
      module_function

      ACTION_KIND = "crawl_terminal_deadline"
      ACTION_SCHEMA_VERSION = "1.0"
      TARGET_TYPE = "crawl"

      def schedule(pg:, organization_id:, project_id:, crawl_id:, due_at:, now:, correlation_id:,
                   causation_id: nil, command_id: nil, product_generation: 0, schedule_generation: 1)
        Platform::ScheduledActions::Store.new(pg).create(
          id: Platform::Ids.system.generate, action_kind: ACTION_KIND,
          action_schema_version: ACTION_SCHEMA_VERSION, organization_id:, project_id:,
          target_type: TARGET_TYPE, target_id: crawl_id,
          product_generation:, schedule_generation:,
          due_at:, now:, correlation_id:, causation_id: causation_id || correlation_id,
          command_id:, executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor
        )[:id]
      end
    end
  end
end
