# frozen_string_literal: true

# S-07-004 review hardening (ADR-026 contract lens). Two schema corrections without which the
# ratified selection rules are structurally unimplementable.
#
#   1. THE COMPOSITE PROJECT FK RULE, again. schemas/POSTGRESQL_SCHEMA.md :128 requires every
#      Project-owned child-to-parent foreign key to carry all three of
#      (organization_id, project_id, id). `crawl_frontier_entries_scope_policy_fk` was created with
#      TWO columns against `source_scope_policies`, which carries `project_id NOT NULL` and is
#      therefore Project-owned — so a frontier entry in Project A could name a scope policy from
#      Project B of the same Organization, with only application discipline preventing it. That is
#      exactly what :128 says must not be relied on. Same defect class as the S-07-003 review's CB5.
#
#   2. A CANDIDATE'S FRONTIER POSITION MUST BE IMPROVABLE UNTIL IT IS CLAIMED.
#      WORKFLOW_SPECIFICATIONS.md :454 fixes two rules the original guard made impossible:
#        * "Deduplication retains the first candidate in this order" — the retained candidate is the
#          LOWEST-ORDERED one, not the first offered. Those genuinely diverge: :440 puts both
#          sitemap-discovered URLs and root-followed links at depth 1, where `origin_rank` (not the
#          URL) decides parent order, so a sitemap page can be dequeued before a link page whose own
#          URL sorts lower — and their children, ordered by discovering-document URL, then arrive in
#          the wrong relative order. Committing in dequeue sequence does not repair it, because
#          parent order is not child order.
#        * "retain the lowest 20,000 by this order and record all later candidates as
#          `queue_limit_discarded`" — a selection over a SET, which requires evicting a
#          higher-ordered admitted candidate when a lower-ordered one arrives at the bound.
#      Both need a committed entry's position to change, or an admitted entry to be discarded. The
#      original guard froze the ordering tuple for life and permitted no `queued -> discarded` edge.
#      The relaxation is exactly scoped: the position fields and the admit/evict edges are mutable
#      ONLY while the entry is still `discovered` or `queued` — that is, until a worker CLAIMS it.
#      From `in_progress` onward everything stays frozen, because from that moment the frontier
#      position has been acted on and reordering it would rewrite history.
class HardenCrawlFrontier < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE source_scope_policies ADD CONSTRAINT source_scope_policies_org_project_id_unique
        UNIQUE (organization_id, project_id, id);
      ALTER TABLE crawl_frontier_entries DROP CONSTRAINT crawl_frontier_entries_scope_policy_fk;
      ALTER TABLE crawl_frontier_entries ADD CONSTRAINT crawl_frontier_entries_scope_policy_fk
        FOREIGN KEY (organization_id, project_id, scope_policy_id)
        REFERENCES source_scope_policies (organization_id, project_id, id);

      -- 3. The two per-offer bookkeeping reads were sequential scans of the WHOLE table, executed
      --    inside the exclusive per-Crawl admission lock on the hot path of a workflow with a hard
      --    60-minute wall clock. Measured at ~19k rows: 2.5 ms each, and offer cost degraded 8.8x
      --    (0.62 -> 5.43 ms) between an empty and a near-bound frontier — and the scan is over the
      --    whole table, so it worsens with total platform volume rather than this Crawl's. The
      --    dequeue itself was already an index scan (0.006 ms); these make its two companions match.
      CREATE INDEX crawl_frontier_entries_crawl_state ON crawl_frontier_entries
        (organization_id, crawl_id, state);
      CREATE INDEX crawl_frontier_entries_enqueue ON crawl_frontier_entries
        (organization_id, crawl_id, enqueue_order DESC);
    SQL
    replace_guard
  end

  def down
    execute <<~SQL
      DROP INDEX IF EXISTS crawl_frontier_entries_enqueue;
      DROP INDEX IF EXISTS crawl_frontier_entries_crawl_state;
      ALTER TABLE crawl_frontier_entries DROP CONSTRAINT crawl_frontier_entries_scope_policy_fk;
      ALTER TABLE crawl_frontier_entries ADD CONSTRAINT crawl_frontier_entries_scope_policy_fk
        FOREIGN KEY (organization_id, scope_policy_id)
        REFERENCES source_scope_policies (organization_id, id);
      ALTER TABLE source_scope_policies DROP CONSTRAINT source_scope_policies_org_project_id_unique;
    SQL
    restore_original_guard
  end

  private

  # The identity (which candidate this is) stays frozen for life. The POSITION (where it sits in the
  # frontier) is frozen only from the claim onward.
  def replace_guard
    execute <<~SQL
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
          IF NOT ((OLD.state = 'discovered' AND NEW.state IN ('queued','discarded'))
                  OR (OLD.state = 'queued' AND NEW.state IN ('in_progress','discarded'))) THEN
            RAISE EXCEPTION 'crawl_frontier_transition_unavailable % -> %', OLD.state, NEW.state
              USING ERRCODE = 'raise_exception';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;
    SQL
  end

  def restore_original_guard
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_crawl_frontier_entries_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'crawl_frontier_entry_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.dequeue_key IS DISTINCT FROM OLD.dequeue_key
           OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
          RAISE EXCEPTION 'crawl_frontier_entry_facts_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.state IS DISTINCT FROM OLD.state THEN
          IF NOT ((OLD.state = 'discovered' AND NEW.state IN ('queued','discarded'))
                  OR (OLD.state = 'queued' AND NEW.state = 'in_progress')) THEN
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
