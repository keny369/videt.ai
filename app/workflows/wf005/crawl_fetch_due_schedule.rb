# frozen_string_literal: true

module Workflows
  module Wf005
    # The creation point of every `crawl_fetch_due` action (BACKGROUND_PROCESSING.md :138, :198,
    # :378), which is the run's only forward link. It is always created on the CALLER'S transaction:
    # :378 says "its terminal transaction creates the exact ingestion or next-frontier action", so a
    # pass that commits its result and a pass that schedules the next one are the same commit. There
    # is no fire-and-forget after commit, and a rolled-back pass leaves no link to claim.
    #
    # THE TARGET IS THE SELECTED FRONTIER ENTRY (DECISIONS ADR-085, owner ruling on FU-16). Admission
    # happens at EXECUTION, so at scheduling time no `fetch_attempts` row exists yet and inventing one
    # would make the scheduler a second producer of attempt rows and hold a byte reservation across
    # the whole scheduling latency. The frontier entry is a genuine claim owner — `queued ->
    # in_progress` under the frontier's own advisory lock IS the claim — and the durable idempotency
    # authority is unchanged: it is the attempt identity `(crawl_host_gate_id, request_kind,
    # crawl_frontier_entry_id, attempt_number)` under its `ON CONFLICT`, which the admitting execution
    # derives from this entry. FU-17 carries the catalogue-prose reconciliation.
    module CrawlFetchDueSchedule
      module_function

      ACTION_KIND = "crawl_fetch_due"
      ACTION_SCHEMA_VERSION = "1.0"
      TARGET_TYPE = "crawl_frontier_entry"

      # THE SHORTEST RE-ENTRY INTERVAL, in seconds. :442 paces host starts over a rolling ONE SECOND
      # window, so a re-entry sooner than that cannot accomplish anything the current pass could not:
      # it would return, find the same gate refusing, and schedule again. It is a floor and never a
      # replacement — every caller that knows a real instant (a robots `Retry-After`, the sitemap
      # release's `next_allowed_start`) passes it, and this only stops a nil or past instant from
      # becoming a spin. Each re-entry is therefore at least one second later than the pass that
      # created it, which is also what keeps the ScheduledAction identity distinct: the ratified
      # identity preimage includes `due_at`, so an identical instant would REPLAY the existing action
      # rather than create the next link, and the chain would stop.
      REENTRY_FLOOR_S = 1

      # The next-frontier link: the run's next candidate, at the instant the host gate says it may
      # start. Returns {} when the frontier has nothing selectable, which is the drained run.
      #
      # WHY THE DUE INSTANT COMES FROM THE GATE. :442 paces starts per canonical host, and
      # `FetchContent` classifies a refused host-gate claim as `host_gate_deferred` with
      # `retryable: false` — so linking the next pass at `now` on a paced host would DISCARD every
      # candidate after the first at the rate limit, turning politeness into data loss. The gate
      # already publishes the exact instant (`next_allowed_start_at`, the max of the base interval and
      # any robots `Crawl-delay`), so the link waits exactly as long as the host requires and no
      # longer. A candidate whose host has no gate row yet has nothing to wait for.
      def link_next(pg:, organization_id:, project_id:, crawl_id:, now:, correlation_id:,
                    causation_id: nil, command_id: nil, not_before: nil)
        candidate = IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg)
                                                                     .peek_next(organization_id, crawl_id)
        return {} if candidate.nil?

        at = [now, not_before, host_ready_at(pg, organization_id, crawl_id, candidate, now)].compact.max
        link(pg:, organization_id:, project_id:, entry_id: candidate["id"], due_at: at, now:,
             correlation_id:, causation_id:, command_id:)
      end

      # A re-entry against the SAME entry, for a pass that decided nothing and left the frontier
      # exactly as it found it: robots still resolving under :444's schedule, sitemap discovery handed
      # back by FU-9's release, or `Admission`'s `run_byte_budget_contended`, which is a "come back"
      # and not a limit. The entry is still `queued`, so the next pass claims it exactly as this one
      # would have.
      def reenter(pg:, organization_id:, project_id:, entry_id:, at:, now:, correlation_id:,
                  causation_id: nil, command_id: nil)
        link(pg:, organization_id:, project_id:, entry_id:, now:, correlation_id:, causation_id:,
             command_id:, due_at: [at, now + REENTRY_FLOOR_S].compact.max)
      end

      def link(pg:, organization_id:, project_id:, entry_id:, due_at:, now:, correlation_id:,
               causation_id: nil, command_id: nil)
        created = Platform::ScheduledActions::Store.new(pg).create(
          id: Platform::Ids.system.generate, action_kind: ACTION_KIND,
          action_schema_version: ACTION_SCHEMA_VERSION, organization_id:, project_id:,
          target_type: TARGET_TYPE, target_id: entry_id, product_generation: 0,
          schedule_generation: 1, due_at:, now:, correlation_id:,
          causation_id: causation_id || correlation_id, command_id:,
          executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor
        )
        { entry_id:, due_at:, action_id: created[:id], replayed: created[:replayed] }
      end

      # The candidate's own host gate, which may be a DIFFERENT host from the one just fetched: a
      # Crawl covers every active Source in its Project, and each carries its own pacing. A candidate
      # whose host has no gate row yet has nothing to wait for.
      #
      # The wait is read as a REMAINDER and added to the caller's clock, never taken as the gate's
      # absolute instant: the floor is written from `clock_timestamp()` and the caller decides against
      # its own injected clock, so adding the remainder keeps one time base instead of mixing two.
      def host_ready_at(pg, organization_id, crawl_id, candidate, now)
        host = FetchAuthorization.host_of(candidate["canonical_url"])
        return nil if host.nil?

        gates = IdentityAccess::Infrastructure::CrawlHostGateStore.new(pg)
        gate = gates.gate(organization_id, crawl_id, host)
        return nil if gate.nil?

        remaining = gates.pacing_remaining_ms(organization_id, gate["id"]).to_i
        now + (remaining / 1000.0) if remaining.positive?
      end
    end
  end
end
