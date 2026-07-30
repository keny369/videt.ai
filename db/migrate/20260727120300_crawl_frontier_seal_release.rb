# frozen_string_literal: true

# S-07-012, the run driver. THE FRONTIER SEAL RELEASE: `in_progress -> terminal`.
#
# WHY THIS BLOCKS THE DRIVER'S OWN REQUIRED LOOP. `crawl_frontier_entries` already declares
# `terminal` in its ratified state CHECK, but the guard permitted only
# `discovered -> queued|discarded` and `queued -> in_progress|discarded`, so nothing could leave
# `in_progress`. `CrawlFrontierStore#peek_next`/`#claim_next` select at
# `sealed_depth = MIN(depth) WHERE state IN ('queued','in_progress','fetched_pending_commit')` —
# WORKFLOW_SPECIFICATIONS.md :454's "all depth d discoveries are SEALED before any depth d+1
# candidate is SELECTED". A claimed entry that can never leave `in_progress` therefore pins
# `sealed_depth` at its own depth for the rest of the run, and every deeper candidate becomes
# permanently unselectable. Sitemap discovery admits content URLs at depth 1 (:440), so a Crawl with
# any usable sitemap would fetch its roots and then stall with work queued — which is exactly the
# "loop that admits, fetches and discovers UNTIL THE FRONTIER DRAINS" BUILD_PLAN assigns to S-07-012.
#
# OWNERSHIP, REASSIGNED IN THE OPEN. `spec/acceptance/wf005_crawl_frontier_spec.rb` recorded this
# edge as "S-07-009's" in a comment. That was written before S-07-012 existed — S-07-012 is the block
# the ADR-026 architecture and concurrency lenses named at S-07-008 acceptance, and at the time the
# comment was written S-07-009 was simply the next tranche after the fetch surfaces. The seal release
# is a property of the RUN DRIVER: it is the commit point of a fetched entry, and the driver is the
# only component that knows a fetch has finished. S-07-009 computes coverage and completion from what
# the driver recorded; it does not dequeue. The comment is corrected in the same commit as this
# migration rather than left to disagree with the guard.
#
# EXACTLY ONE EDGE IS ADDED. `fetched_pending_commit` — :456's "a completion with a later key waits
# in `fetched_pending_commit`; it cannot change selection" — belongs with CONCURRENT fetching and the
# coordinator that commits DISCOVERIES in increasing dequeue key. Link extraction is S-07-010's, and
# `Wf005::Admission` already declined to pre-empt that limb for the same reason. This driver advances
# one entry per pass, so there is no later-key completion to hold and no discovery to order; adding
# the state's edges here would add vocabulary nothing writes. `commit_order` is left NULL for the
# same reason: it is the coordinator's sequence, not the dequeue's.
#
# WHAT STAYS FROZEN. Everything. The added edge only widens the state machine; identity, provenance,
# the ordering tuple, the single-step `state_version` advance and the write-once discard reason are
# all re-emitted byte-identically below. A terminal entry carries `reason IS NULL`, which
# `crawl_frontier_entries_discard_reason` already requires of every non-discarded state.
class CrawlFrontierSealRelease < ActiveRecord::Migration[8.1]
  def up = execute(guard(terminal: true))
  def down = execute(guard(terminal: false))

  private

  def guard(terminal:)
    edges = if terminal
              <<~EDGES.chomp
                IF NOT ((OLD.state = 'discovered' AND NEW.state IN ('queued','discarded'))
                            OR (OLD.state = 'queued' AND NEW.state IN ('in_progress','discarded'))
                            -- The seal release: a claimed entry whose fetch has been decided.
                            OR (OLD.state = 'in_progress' AND NEW.state = 'terminal')) THEN
              EDGES
            else
              <<~EDGES.chomp
                IF NOT ((OLD.state = 'discovered' AND NEW.state IN ('queued','discarded'))
                            OR (OLD.state = 'queued' AND NEW.state IN ('in_progress','discarded'))) THEN
              EDGES
            end

    <<~SQL
      CREATE OR REPLACE FUNCTION f1_crawl_frontier_entries_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      DECLARE
        unclaimed boolean := OLD.state IN ('discovered','queued');
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'crawl_frontier_entry_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        -- Identity and provenance: frozen for the life of the entry, in every state.
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.crawl_id IS DISTINCT FROM OLD.crawl_id
           OR NEW.source_id IS DISTINCT FROM OLD.source_id
           OR NEW.canonical_url IS DISTINCT FROM OLD.canonical_url
           OR NEW.canonical_url_preimage IS DISTINCT FROM OLD.canonical_url_preimage
           OR NEW.canonical_url_sha256 IS DISTINCT FROM OLD.canonical_url_sha256
           OR NEW.collision_ordinal IS DISTINCT FROM OLD.collision_ordinal
           OR NEW.canonicalization_version IS DISTINCT FROM OLD.canonicalization_version
           OR NEW.scope_policy_id IS DISTINCT FROM OLD.scope_policy_id
           OR NEW.scope_policy_version IS DISTINCT FROM OLD.scope_policy_version
           OR NEW.enqueue_order IS DISTINCT FROM OLD.enqueue_order
           OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id
           OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
          RAISE EXCEPTION 'crawl_frontier_entry_facts_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        -- `state_version` is the ONLY defence the admit/discard/reposition compare-and-swaps have,
        -- so it may only ever advance by one. A free rewrite would let a stale-version guard succeed.
        IF NEW.state_version IS DISTINCT FROM OLD.state_version + 1 THEN
          RAISE EXCEPTION 'crawl_frontier_entry_version_invalid' USING ERRCODE = 'raise_exception';
        END IF;
        -- A discard reason is written once, with the discard, and never rewritten: it is load-bearing
        -- for coverage (:452 puts every limit-discarded in-scope candidate in the denominator).
        IF OLD.reason IS NOT NULL AND NEW.reason IS DISTINCT FROM OLD.reason THEN
          RAISE EXCEPTION 'crawl_frontier_entry_reason_frozen' USING ERRCODE = 'raise_exception';
        END IF;
        -- Position: mutable only while unclaimed, so deduplication can keep the LOWEST-ordered
        -- discovery of a candidate and the queue bound can evict a higher-ordered one (:454).
        IF NOT unclaimed AND (
             NEW.origin IS DISTINCT FROM OLD.origin
             OR NEW.depth IS DISTINCT FROM OLD.depth
             OR NEW.discovering_document_url IS DISTINCT FROM OLD.discovering_document_url
             OR NEW.link_position IS DISTINCT FROM OLD.link_position
             OR NEW.dequeue_key IS DISTINCT FROM OLD.dequeue_key
             OR NEW.parent_entry_id IS DISTINCT FROM OLD.parent_entry_id) THEN
          RAISE EXCEPTION 'crawl_frontier_entry_position_frozen' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.state IS DISTINCT FROM OLD.state THEN
          #{edges}
            RAISE EXCEPTION 'crawl_frontier_transition_unavailable % -> %', OLD.state, NEW.state
              USING ERRCODE = 'raise_exception';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;
    SQL
  end
end
