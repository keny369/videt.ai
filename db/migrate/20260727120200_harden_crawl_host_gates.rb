# frozen_string_literal: true

# S-07-005 review hardening (ADR-026 schema lens).
#
#   1. `robots_rules_schema` was NOT in the guard's frozen list, so the terminal robots decision was
#      not fully write-once: the tag saying HOW the frozen `robots_rules` are to be interpreted could
#      be rewritten or erased, by the runtime role, after the decision was sealed. Schema :296 is
#      categorical — "normalized robots rules/schema ... robots terminal decision fields are
#      write-once" — and the schema is named in the same breath as the rules it describes. The
#      reviewer demonstrated both a rewrite and a NULL-out as `f1_web`.
#
#   2. `rules_applied` must CARRY its rules and their schema. The original CHECK was one-directional
#      (rules only on `rules_applied`), which permitted `rules_applied` with NULL rules — a shape
#      that reads as "robots resolved, nothing disallowed" and therefore fails OPEN.
#
#   3. A robots attempt could wedge permanently in `in_progress`. The claim commits in its own
#      transaction (it must — no external call may sit inside a database transaction), so a process
#      lost between the claim and the outcome left the row `in_progress` with nothing to reclaim it:
#      the host would never resolve, never fail closed, and every content fetch on it would be
#      refused for the life of the run. `robots_attempt_started_at` is the reclaim clock, and it is
#      not a terminal decision field, so it stays mutable.
class HardenCrawlHostGates < ActiveRecord::Migration[8.1]
  TERMINAL = "('rules_applied','no_restrictions','unavailable')"

  def up
    execute <<~SQL
      ALTER TABLE crawl_host_gates ADD COLUMN robots_attempt_started_at timestamptz(6);
      ALTER TABLE crawl_host_gates DROP CONSTRAINT crawl_host_gates_robots_rules_shape;
      ALTER TABLE crawl_host_gates ADD CONSTRAINT crawl_host_gates_robots_rules_shape
        CHECK ((robots_state = 'rules_applied')
               = (robots_rules IS NOT NULL AND robots_rules_schema IS NOT NULL));
    SQL
    replace_guard(freeze_schema: true)
  end

  def down
    execute <<~SQL
      ALTER TABLE crawl_host_gates DROP CONSTRAINT crawl_host_gates_robots_rules_shape;
      ALTER TABLE crawl_host_gates ADD CONSTRAINT crawl_host_gates_robots_rules_shape
        CHECK ((robots_rules IS NULL) OR (robots_state = 'rules_applied'));
      ALTER TABLE crawl_host_gates DROP COLUMN robots_attempt_started_at;
    SQL
    replace_guard(freeze_schema: false)
  end

  private

  def replace_guard(freeze_schema:)
    schema_clause = freeze_schema ? "OR NEW.robots_rules_schema IS DISTINCT FROM OLD.robots_rules_schema" : ""
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_crawl_host_gates_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'crawl_host_gate_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.crawl_id IS DISTINCT FROM OLD.crawl_id
           OR NEW.canonical_host IS DISTINCT FROM OLD.canonical_host
           OR NEW.canonical_host_sha256 IS DISTINCT FROM OLD.canonical_host_sha256
           OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id
           OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
          RAISE EXCEPTION 'crawl_host_gate_facts_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF OLD.robots_state IN #{TERMINAL} THEN
          IF NEW.robots_state IS DISTINCT FROM OLD.robots_state
             OR NEW.robots_rules IS DISTINCT FROM OLD.robots_rules
             #{schema_clause}
             OR NEW.robots_agent_group IS DISTINCT FROM OLD.robots_agent_group
             OR NEW.robots_crawl_delay_ms IS DISTINCT FROM OLD.robots_crawl_delay_ms
             OR NEW.robots_sitemap_candidates IS DISTINCT FROM OLD.robots_sitemap_candidates
             OR NEW.robots_source_sha256 IS DISTINCT FROM OLD.robots_source_sha256
             OR NEW.robots_terminal_reason IS DISTINCT FROM OLD.robots_terminal_reason
             OR NEW.robots_terminal_at IS DISTINCT FROM OLD.robots_terminal_at
             OR NEW.robots_http_status IS DISTINCT FROM OLD.robots_http_status THEN
            RAISE EXCEPTION 'crawl_host_gate_robots_decision_frozen' USING ERRCODE = 'raise_exception';
          END IF;
        END IF;
        IF NEW.robots_state IS DISTINCT FROM OLD.robots_state THEN
          IF NOT ((OLD.robots_state = 'pending' AND NEW.robots_state = 'in_progress')
                  OR (OLD.robots_state = 'in_progress' AND NEW.robots_state IN #{TERMINAL})
                  OR (OLD.robots_state = 'in_progress' AND NEW.robots_state = 'pending')) THEN
            RAISE EXCEPTION 'crawl_host_gate_robots_transition_unavailable % -> %',
              OLD.robots_state, NEW.robots_state USING ERRCODE = 'raise_exception';
          END IF;
        END IF;
        IF NEW.state_version IS DISTINCT FROM OLD.state_version + 1 THEN
          RAISE EXCEPTION 'crawl_host_gate_version_invalid' USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END;
      $$;
    SQL
  end
end
