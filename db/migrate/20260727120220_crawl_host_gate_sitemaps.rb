# frozen_string_literal: true

# S-07-006 sitemap discovery (WORKFLOW_SPECIFICATIONS.md :450/:454).
#
# The sitemap limb lives on `crawl_host_gates` because :450's sitemap outcomes are exactly per-host
# per-run — `sitemap_absent` and `sitemap_unavailable` are host-level facts that decide whether that
# Source root's coverage is reduced — and schema :296 already makes this table the one record per
# `(crawl_id, canonical_host)`, carrying "ordered sitemap candidates". No separate sitemap table is
# named anywhere in the canonical schema, and inventing one would promote a technical execution
# record into a product entity, which MTX-030 `persistence_model` forbids.
#
# `robots_sitemap_candidates` (S-07-005) stays exactly what it is: the RAW, UNFILTERED, file-ordered
# list of `Sitemap:` values as declared. `sitemap_candidates` is the resolved set — in-scope, same
# host, ordered by :454's tuple and truncated to the retained bound. Keeping them separate is what
# makes the declared-versus-admitted distinction auditable, and it is one of the requirements the
# S-07-005 review handed to this tranche.
class CrawlHostGateSitemaps < ActiveRecord::Migration[8.1]
  STATES = %w[pending in_progress succeeded absent unavailable].freeze
  TERMINAL = %w[succeeded absent unavailable].freeze

  def up
    execute <<~SQL
      ALTER TABLE crawl_host_gates
        ADD COLUMN sitemap_state text NOT NULL DEFAULT 'pending'
          CHECK (sitemap_state IN #{list(STATES)}),
        ADD COLUMN sitemap_candidates jsonb NOT NULL DEFAULT '[]',
        ADD COLUMN sitemap_discarded jsonb NOT NULL DEFAULT '[]',
        ADD COLUMN sitemap_documents_fetched integer NOT NULL DEFAULT 0
          CHECK (sitemap_documents_fetched >= 0),
        ADD COLUMN sitemap_max_index_depth integer NOT NULL DEFAULT 0
          CHECK (sitemap_max_index_depth >= 0),
        ADD COLUMN sitemap_outcome_reason text,
        ADD COLUMN sitemap_terminal_at timestamptz(6);

      -- Exactly the terminal states carry a terminal instant, mirroring the robots limb.
      ALTER TABLE crawl_host_gates ADD CONSTRAINT crawl_host_gates_sitemap_terminal_shape
        CHECK ((sitemap_state IN #{list(TERMINAL)}) = (sitemap_terminal_at IS NOT NULL));
      -- A non-success terminal always names why (:450 sitemap_absent / sitemap_unavailable).
      ALTER TABLE crawl_host_gates ADD CONSTRAINT crawl_host_gates_sitemap_outcome_reason
        CHECK ((sitemap_state NOT IN ('absent','unavailable')) OR (sitemap_outcome_reason IS NOT NULL));
    SQL
    add_sitemap_guard
  end

  def down
    execute <<~SQL
      ALTER TABLE crawl_host_gates
        DROP CONSTRAINT crawl_host_gates_sitemap_outcome_reason,
        DROP CONSTRAINT crawl_host_gates_sitemap_terminal_shape,
        DROP COLUMN sitemap_terminal_at,
        DROP COLUMN sitemap_outcome_reason,
        DROP COLUMN sitemap_max_index_depth,
        DROP COLUMN sitemap_documents_fetched,
        DROP COLUMN sitemap_discarded,
        DROP COLUMN sitemap_candidates,
        DROP COLUMN sitemap_state;
    SQL
    remove_sitemap_guard
  end

  private

  def list(values) = "(#{values.map { |v| "'#{v}'" }.join(',')})"

  # The sitemap terminal decision is write-once for the same reason the robots one is: a run resolves
  # a host's sitemaps once, and re-deciding mid-run could turn an `unavailable` (which reduces
  # coverage) into a success after the coverage classification had already read it.
  def add_sitemap_guard
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_crawl_host_gates_sitemap_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF OLD.sitemap_state IN #{list(TERMINAL)} THEN
          IF NEW.sitemap_state IS DISTINCT FROM OLD.sitemap_state
             OR NEW.sitemap_outcome_reason IS DISTINCT FROM OLD.sitemap_outcome_reason
             OR NEW.sitemap_terminal_at IS DISTINCT FROM OLD.sitemap_terminal_at
             OR NEW.sitemap_candidates IS DISTINCT FROM OLD.sitemap_candidates THEN
            RAISE EXCEPTION 'crawl_host_gate_sitemap_decision_frozen' USING ERRCODE = 'raise_exception';
          END IF;
        END IF;
        IF NEW.sitemap_state IS DISTINCT FROM OLD.sitemap_state THEN
          IF NOT ((OLD.sitemap_state = 'pending' AND NEW.sitemap_state = 'in_progress')
                  OR (OLD.sitemap_state = 'in_progress' AND NEW.sitemap_state IN #{list(TERMINAL)})
                  OR (OLD.sitemap_state = 'in_progress' AND NEW.sitemap_state = 'pending')) THEN
            RAISE EXCEPTION 'crawl_host_gate_sitemap_transition_unavailable % -> %',
              OLD.sitemap_state, NEW.sitemap_state USING ERRCODE = 'raise_exception';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER crawl_host_gates_sitemap_guard BEFORE UPDATE ON crawl_host_gates
        FOR EACH ROW EXECUTE FUNCTION f1_crawl_host_gates_sitemap_guard();
    SQL
  end

  def remove_sitemap_guard
    execute <<~SQL
      DROP TRIGGER IF EXISTS crawl_host_gates_sitemap_guard ON crawl_host_gates;
      DROP FUNCTION IF EXISTS f1_crawl_host_gates_sitemap_guard();
    SQL
  end
end
