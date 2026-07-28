# frozen_string_literal: true

# S-07-004 deterministic frontier + dequeue (schemas/POSTGRESQL_SCHEMA.md :293-294;
# WORKFLOW_SPECIFICATIONS.md :454; SEARCH_CRAWL_RETRIEVAL.md § Frontier And Deterministic Selection;
# contracts/S-07.json MTX-030 persistence_model).
#
# PostgreSQL is the authority for frontier state; Redis and Sidekiq carry only wake-up identities.
# Both tables are implementation-owned TECHNICAL execution records, not product entities — MTX-030
# is explicit that "the crawl frontier queue, the per-URL attempt record, the worker lease and the
# byte reservation ... MUST NOT be promoted to product entities". They therefore carry no domain
# event and no state version exposed to a customer surface.
#
#   * `crawl_frontier_entries` (T-MUT) — one row per DISTINCT retained candidate, carrying the
#     complete uniqueness preimage and its digest, the Volume I ordering tuple, the materialized
#     `dequeue_key`, and the policy decisions that admitted it.
#   * `crawl_frontier_occurrences` (T-IMM) — every DUPLICATE discovery with its referrer and
#     position, "for audit, without becoming another candidate".
#
# Uniqueness allocation follows SEARCH_CRAWL_RETRIEVAL.md exactly: "All uniqueness allocations
# retain both SHA-256 and full canonical preimage. Hash equality without byte-equal preimage
# allocates a collision ordinal, never merges candidates." Hence the identity is
# `(crawl_id, canonical_url_sha256, collision_ordinal)` WITH the preimage retained beside it, not
# the digest alone.
class CreateCrawlFrontier < ActiveRecord::Migration[8.1]
  def up
    create_entries
    force_rls("crawl_frontier_entries")
    create_entries_guard
    create_occurrences
    force_rls("crawl_frontier_occurrences")
    create_occurrences_guard
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS crawl_frontier_occurrences_guard ON crawl_frontier_occurrences;
      DROP FUNCTION IF EXISTS f1_crawl_frontier_occurrences_guard();
      DROP TABLE IF EXISTS crawl_frontier_occurrences;
      DROP TRIGGER IF EXISTS crawl_frontier_entries_guard ON crawl_frontier_entries;
      DROP FUNCTION IF EXISTS f1_crawl_frontier_entries_guard();
      DROP TABLE IF EXISTS crawl_frontier_entries;
    SQL
  end

  private

  def force_rls(table)
    execute <<~SQL
      ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
      ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;
      CREATE POLICY #{table}_context ON #{table}
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
      REVOKE ALL ON #{table} FROM PUBLIC;
    SQL
  end

  def create_entries
    execute <<~SQL
      CREATE TABLE crawl_frontier_entries (
        id                        uuid PRIMARY KEY,
        state_version             bigint NOT NULL DEFAULT 0,
        created_at                timestamptz(6) NOT NULL,
        updated_at                timestamptz(6) NOT NULL,
        correlation_id            uuid NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        crawl_id                  uuid NOT NULL,
        source_id                 uuid NOT NULL,
        -- the complete retained uniqueness preimage, its digest, and the collision ordinal a
        -- hash collision with a DIFFERENT preimage takes (candidates are never merged)
        canonical_url             text NOT NULL,
        canonical_url_preimage    bytea NOT NULL,
        canonical_url_sha256      bytea NOT NULL CHECK (octet_length(canonical_url_sha256) = 32),
        collision_ordinal         integer NOT NULL DEFAULT 0 CHECK (collision_ordinal >= 0),
        -- the Volume I ordering tuple (:454) and its materialization
        origin                    text NOT NULL CHECK (origin IN ('root','sitemap','link')),
        depth                     integer NOT NULL CHECK (depth >= 0),
        discovering_document_url  text NOT NULL DEFAULT '',
        link_position             integer NOT NULL DEFAULT 0 CHECK (link_position >= 0),
        dequeue_key               bytea NOT NULL,
        parent_entry_id           uuid,
        -- the policy decisions that admitted this candidate (robots is S-07-005, so nullable)
        canonicalization_version  text NOT NULL,
        scope_policy_id           uuid NOT NULL,
        scope_policy_version      text NOT NULL,
        robots_decision_id        uuid,
        robots_policy_version     text,
        -- admission and commit sequencing, both assigned in dequeue order
        enqueue_order             bigint NOT NULL,
        commit_order              bigint,
        state                     text NOT NULL CHECK (state IN
                                    ('discovered','queued','in_progress','fetched_pending_commit','terminal','discarded')),
        reason                    text,
        -- a root or sitemap candidate uses an empty discovering URL and link position zero (:454)
        CONSTRAINT crawl_frontier_entries_origin_shape CHECK (
          (origin = 'link') OR (discovering_document_url = '' AND link_position = 0)),
        -- a root candidate is depth zero (:440 "The Source root is depth 0")
        CONSTRAINT crawl_frontier_entries_root_depth CHECK (origin <> 'root' OR depth = 0),
        -- a discarded entry always names why; every other state carries no discard reason
        CONSTRAINT crawl_frontier_entries_discard_reason CHECK ((state = 'discarded') = (reason IS NOT NULL)),
        CONSTRAINT crawl_frontier_entries_identity_unique UNIQUE (crawl_id, canonical_url_sha256, collision_ordinal),
        CONSTRAINT crawl_frontier_entries_dequeue_unique UNIQUE (crawl_id, dequeue_key),
        CONSTRAINT crawl_frontier_entries_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT crawl_frontier_entries_org_project_id_unique UNIQUE (organization_id, project_id, id),
        CONSTRAINT crawl_frontier_entries_crawl_fk FOREIGN KEY (organization_id, project_id, crawl_id)
          REFERENCES crawls (organization_id, project_id, id),
        CONSTRAINT crawl_frontier_entries_source_fk FOREIGN KEY (organization_id, project_id, source_id)
          REFERENCES sources (organization_id, project_id, id),
        CONSTRAINT crawl_frontier_entries_parent_fk FOREIGN KEY (organization_id, project_id, parent_entry_id)
          REFERENCES crawl_frontier_entries (organization_id, project_id, id),
        CONSTRAINT crawl_frontier_entries_scope_policy_fk FOREIGN KEY (organization_id, scope_policy_id)
          REFERENCES source_scope_policies (organization_id, id)
      );
      -- the dequeue itself: the lowest key among the crawl's admitted candidates
      CREATE INDEX crawl_frontier_entries_dequeue ON crawl_frontier_entries (crawl_id, dequeue_key)
        WHERE state = 'queued';
      -- byte-equality lookup for the collision check (digest match, preimage compare)
      CREATE INDEX crawl_frontier_entries_preimage ON crawl_frontier_entries (crawl_id, canonical_url_sha256);
    SQL
  end

  # T-MUT with a tight lifecycle. Identity, the ordering tuple and the admitting policy decisions are
  # frozen for the life of the entry — the frontier's determinism depends on a committed candidate's
  # position never moving. S-07-004 owns exactly three edges: admission (discovered -> queued), the
  # dequeue claim (queued -> in_progress) and the queue-limit discard (discovered -> discarded).
  # The fetch and terminal edges belong to S-07-007 / S-07-009 and stay refused until then.
  def create_entries_guard
    execute <<~SQL
      CREATE FUNCTION f1_crawl_frontier_entries_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'crawl_frontier_entry_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.crawl_id IS DISTINCT FROM OLD.crawl_id
           OR NEW.source_id IS DISTINCT FROM OLD.source_id
           OR NEW.canonical_url IS DISTINCT FROM OLD.canonical_url
           OR NEW.canonical_url_preimage IS DISTINCT FROM OLD.canonical_url_preimage
           OR NEW.canonical_url_sha256 IS DISTINCT FROM OLD.canonical_url_sha256
           OR NEW.collision_ordinal IS DISTINCT FROM OLD.collision_ordinal
           OR NEW.origin IS DISTINCT FROM OLD.origin
           OR NEW.depth IS DISTINCT FROM OLD.depth
           OR NEW.discovering_document_url IS DISTINCT FROM OLD.discovering_document_url
           OR NEW.link_position IS DISTINCT FROM OLD.link_position
           OR NEW.dequeue_key IS DISTINCT FROM OLD.dequeue_key
           OR NEW.parent_entry_id IS DISTINCT FROM OLD.parent_entry_id
           OR NEW.canonicalization_version IS DISTINCT FROM OLD.canonicalization_version
           OR NEW.scope_policy_id IS DISTINCT FROM OLD.scope_policy_id
           OR NEW.scope_policy_version IS DISTINCT FROM OLD.scope_policy_version
           OR NEW.enqueue_order IS DISTINCT FROM OLD.enqueue_order
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
      CREATE TRIGGER crawl_frontier_entries_guard BEFORE UPDATE OR DELETE ON crawl_frontier_entries
        FOR EACH ROW EXECUTE FUNCTION f1_crawl_frontier_entries_guard();
    SQL
  end

  def create_occurrences
    execute <<~SQL
      CREATE TABLE crawl_frontier_occurrences (
        id                        uuid PRIMARY KEY,
        created_at                timestamptz(6) NOT NULL,
        correlation_id            uuid NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        crawl_id                  uuid NOT NULL,
        frontier_entry_id         uuid NOT NULL,
        source_id                 uuid NOT NULL,
        referrer_entry_id         uuid,
        occurrence_url            text NOT NULL,
        occurrence_url_sha256     bytea NOT NULL CHECK (octet_length(occurrence_url_sha256) = 32),
        discovering_document_url  text NOT NULL DEFAULT '',
        link_position             integer NOT NULL DEFAULT 0 CHECK (link_position >= 0),
        occurrence_order          bigint NOT NULL,
        discovered_at             timestamptz(6) NOT NULL,
        duplicate_reason          text NOT NULL,
        CONSTRAINT crawl_frontier_occurrences_identity_unique
          UNIQUE (crawl_id, frontier_entry_id, discovering_document_url, link_position),
        CONSTRAINT crawl_frontier_occurrences_order_unique UNIQUE (crawl_id, occurrence_order),
        CONSTRAINT crawl_frontier_occurrences_entry_fk FOREIGN KEY (organization_id, project_id, frontier_entry_id)
          REFERENCES crawl_frontier_entries (organization_id, project_id, id),
        CONSTRAINT crawl_frontier_occurrences_referrer_fk FOREIGN KEY (organization_id, project_id, referrer_entry_id)
          REFERENCES crawl_frontier_entries (organization_id, project_id, id),
        CONSTRAINT crawl_frontier_occurrences_crawl_fk FOREIGN KEY (organization_id, project_id, crawl_id)
          REFERENCES crawls (organization_id, project_id, id),
        CONSTRAINT crawl_frontier_occurrences_source_fk FOREIGN KEY (organization_id, project_id, source_id)
          REFERENCES sources (organization_id, project_id, id)
      );
    SQL
  end

  def create_occurrences_guard
    execute <<~SQL
      CREATE FUNCTION f1_crawl_frontier_occurrences_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        RAISE EXCEPTION 'crawl_frontier_occurrence_immutable' USING ERRCODE = 'raise_exception';
      END;
      $$;
      CREATE TRIGGER crawl_frontier_occurrences_guard BEFORE UPDATE OR DELETE ON crawl_frontier_occurrences
        FOR EACH ROW EXECUTE FUNCTION f1_crawl_frontier_occurrences_guard();
    SQL
  end
end
