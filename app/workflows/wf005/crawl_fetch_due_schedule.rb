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
        frontier = IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg)
        # UNDER THE FRONTIER'S OWN ADVISORY LOCK, like every other peek in the workflow. Unlocked, two
        # terminal transactions can select the SAME candidate and create two actions for it — distinct
        # `due_at`, so distinct identities, so no replay collapses them — and the run forks into two
        # chains. Harmless with one live chain and latent the moment :456's concurrent fetching lands.
        # Both this and `Admission` take the advisory lock FIRST, so there is no lock-order cycle.
        frontier.lock_frontier(crawl_id)
        candidate = frontier.peek_next(organization_id, crawl_id)
        # NOT DRAINED AND PINNED ARE DIFFERENT FACTS, and `peek_next` returns nil for both. A stranded
        # `in_progress` claim holds `sealed_depth`, so a run with queued work at a deeper depth used to
        # report itself DRAINED — a false statement in a customer-visible payload, and the thing that hid
        # the stranded claim in the first place. Recovering the claim needs a frontier-lease sweep, which
        # is S-07-011's; saying which of the two happened is this tranche's.
        return { pinned: frontier.unfinished?(organization_id, crawl_id) } if candidate.nil?

        at = [now, not_before, host_ready_at(pg, organization_id, crawl_id, candidate, now)].compact.max
        link(pg:, organization_id:, project_id:, entry_id: candidate["id"], due_at: at, now:,
             correlation_id:, causation_id:, command_id:, crawl_id:)
      end

      # A re-entry against the SAME entry, for a pass that decided nothing and left the frontier
      # exactly as it found it: robots still resolving under :444's schedule, sitemap discovery handed
      # back by FU-9's release, or `Admission`'s `run_byte_budget_contended`, which is a "come back"
      # and not a limit. The entry is still `queued`, so the next pass claims it exactly as this one
      # would have.
      def reenter(pg:, organization_id:, project_id:, entry_id:, at:, now:, correlation_id:,
                  causation_id: nil, command_id: nil, crawl_id: nil)
        link(pg:, organization_id:, project_id:, entry_id:, now:, correlation_id:, causation_id:,
             command_id:, crawl_id:, due_at: [at, now + REENTRY_FLOOR_S].compact.max)
      end

      # NEVER PAST THE RUN'S OWN DEADLINE. :442 ends the run at 60 elapsed minutes, and an action due
      # after that can do nothing but write a ledger row against a finished Crawl — a long robots
      # `Crawl-delay` or a contended host is enough to place one there. Clamped rather than refused: an
      # action due exactly at the deadline is the last honest opportunity, and the pass it runs will find
      # the wall clock expired and halt.
      def link(pg:, organization_id:, project_id:, entry_id:, due_at:, now:, correlation_id:,
               causation_id: nil, command_id: nil, crawl_id: nil)
        deadline = crawl_id ? run_deadline(pg, organization_id, crawl_id) : Platform::RunDeadline::NONE
        return { entry_id:, beyond_deadline: true } if deadline.beyond?(now)

        due_at = deadline.not_after(due_at)
        created = Platform::ScheduledActions::Store.new(pg).create(
          id: Platform::Ids.system.generate, action_kind: ACTION_KIND,
          action_schema_version: ACTION_SCHEMA_VERSION, organization_id:, project_id:,
          target_type: TARGET_TYPE, target_id: entry_id, product_generation: 0,
          schedule_generation: 1, due_at:, now:, correlation_id:,
          causation_id: causation_id || correlation_id, command_id:,
          executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor,
          # :288's LEASE DURATION INPUT, stamped by the producer because only the producer knows it.
          # `scheduled_actions` is transport: it must not read `crawls` to discover how long this work may
          # legitimately take, or F-04 would depend on WF-005 and on every future work type. It carries a
          # plain instant and does the arithmetic. The run deadline is the right value because :442 is what
          # bounds this execution — at 60 elapsed minutes no new request starts — and it is ALREADY resolved
          # two lines above to clamp `due_at`, so nothing extra is read.
          #
          # Without it the lease was a flat 30 seconds while ONE ratified redirect hop is up to 30 (F-01
          # takes the 15-second resolver timeout outside the 15-second per-hop deadline), so a single slow
          # hop lapsed the lease under a live worker and the pass could never complete. Demonstrated.
          product_attempt_deadline: deadline.present? ? deadline.instant_for_transport : nil
        )
        { entry_id:, due_at:, action_id: created[:id], replayed: created[:replayed] }
      end

      # THE RUN'S DEADLINE AS A VALUE (round 9, R9-7). It used to be decoded here into a bare instant
      # and compared twice in `link` above, which is a second implementation of :442's boundary living
      # in a scheduler — the exact shape the review defeated the previous single-owner rule with.
      # `Platform::RunDeadline` answers the two questions this method needs and exposes no comparison.
      def run_deadline(pg, organization_id, crawl_id)
        crawl = IdentityAccess::Infrastructure::CrawlHostGateStore.new(pg).crawl(organization_id, crawl_id)
        crawl.nil? ? Platform::RunDeadline::NONE : Platform::RunDeadline.of(crawl)
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
        # `host_of` returns "" and never nil for a hostless URL, so a `.nil?` test here was unreachable —
        # the same defect its twin in the driver had.
        return nil if host.to_s.empty?

        gates = IdentityAccess::Infrastructure::CrawlHostGateStore.new(pg)
        gate = gates.gate(organization_id, crawl_id, host)
        return nil if gate.nil?

        remaining = gates.pacing_remaining_ms(organization_id, gate["id"]).to_i
        now + (remaining / 1000.0) if remaining.positive?
      end
    end
  end
end
