# frozen_string_literal: true

# S-07-005 host gate + robots (fail-closed) + per-host rate (schemas/POSTGRESQL_SCHEMA.md :296;
# WORKFLOW_SPECIFICATIONS.md :442 rate/concurrency and :448 robots; SEARCH_CRAWL_RETRIEVAL.md
# § Robots And Sitemap Processing and the run/per-host gate paragraph; contracts/S-07.json MTX-030).
#
# One row per `(crawl_id, canonical_host)`. It carries BOTH host-level concerns, because both are
# decided under the same row lock:
#
#   * THE ROBOTS RECORD — attempts, normalized rules, selected agent group, crawl delay, ordered
#     sitemap candidates, source digest and terminal reason. "Content dispatch is blocked until that
#     record is terminal", so the state is the gate every content fetch waits behind.
#   * THE RATE/CONCURRENCY GATE — `next_allowed_start_at`, the rolling start instants, the active
#     connection count and a lease version. SEARCH_CRAWL_RETRIEVAL is explicit that "the run and
#     per-host gates use PostgreSQL `clock_timestamp()` and row locks. A worker cannot start merely
#     because Redis granted a token."
#
# The robots terminal decision fields are WRITE-ONCE (schema :296). A run resolves robots for a host
# exactly once: re-deciding mid-run would let a host that failed closed become fetchable, which is
# precisely the fail-open the contract forbids. The guard enforces that, not the application.
class CreateCrawlHostGates < ActiveRecord::Migration[8.1]
  # WORKFLOW :448 — the robots outcomes, and only these.
  ROBOTS_STATES = %w[pending in_progress rules_applied no_restrictions unavailable].freeze
  TERMINAL_STATES = %w[rules_applied no_restrictions unavailable].freeze

  def up
    execute <<~SQL
      CREATE TABLE crawl_host_gates (
        id                        uuid PRIMARY KEY,
        state_version             bigint NOT NULL DEFAULT 0,
        created_at                timestamptz(6) NOT NULL,
        updated_at                timestamptz(6) NOT NULL,
        correlation_id            uuid NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        crawl_id                  uuid NOT NULL,
        -- Canonical host identity. The digest is the unique key; the plaintext host is retained
        -- beside it because it is the customer-visible identity and a digest alone cannot be audited.
        canonical_host            text NOT NULL,
        canonical_host_sha256     bytea NOT NULL CHECK (octet_length(canonical_host_sha256) = 32),

        -- ---- the robots record (terminal fields write-once) ----
        robots_state              text NOT NULL DEFAULT 'pending'
                                    CHECK (robots_state IN #{sql_list(ROBOTS_STATES)}),
        robots_generation         bigint NOT NULL DEFAULT 0,
        robots_attempt_count      integer NOT NULL DEFAULT 0 CHECK (robots_attempt_count >= 0),
        robots_rules              jsonb,
        robots_rules_schema       text,
        robots_agent_group        text,
        robots_crawl_delay_ms     integer CHECK (robots_crawl_delay_ms IS NULL OR robots_crawl_delay_ms >= 0),
        robots_sitemap_candidates jsonb NOT NULL DEFAULT '[]',
        robots_source_sha256      bytea CHECK (robots_source_sha256 IS NULL OR octet_length(robots_source_sha256) = 32),
        robots_http_status        integer,
        robots_terminal_reason    text,
        robots_terminal_at        timestamptz(6),
        -- Exactly the terminal states carry a terminal instant, and only they may carry rules.
        CONSTRAINT crawl_host_gates_robots_terminal_shape CHECK (
          (robots_state IN #{sql_list(TERMINAL_STATES)}) = (robots_terminal_at IS NOT NULL)),
        CONSTRAINT crawl_host_gates_robots_rules_shape CHECK (
          (robots_rules IS NULL) OR (robots_state = 'rules_applied')),
        -- A fail-closed outcome always names why (:448 `robots_unavailable_fail_closed`).
        CONSTRAINT crawl_host_gates_robots_unavailable_reason CHECK (
          (robots_state <> 'unavailable') OR (robots_terminal_reason IS NOT NULL)),

        -- ---- the rate / concurrency gate ----
        -- `next_allowed_start_at` is the crawl-delay floor; `recent_start_instants` is the rolling
        -- window the (start-1s, start] predicate counts (:442). Both are advanced under the row lock.
        next_allowed_start_at     timestamptz(6),
        recent_start_instants     timestamptz(6)[] NOT NULL DEFAULT ARRAY[]::timestamptz(6)[],
        active_connection_count   integer NOT NULL DEFAULT 0 CHECK (active_connection_count >= 0),
        lease_version             bigint NOT NULL DEFAULT 0,

        CONSTRAINT crawl_host_gates_host_unique UNIQUE (crawl_id, canonical_host_sha256),
        CONSTRAINT crawl_host_gates_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT crawl_host_gates_org_project_id_unique UNIQUE (organization_id, project_id, id),
        CONSTRAINT crawl_host_gates_crawl_fk FOREIGN KEY (organization_id, project_id, crawl_id)
          REFERENCES crawls (organization_id, project_id, id)
      );
      CREATE INDEX crawl_host_gates_crawl ON crawl_host_gates (organization_id, crawl_id);
    SQL
    force_rls("crawl_host_gates")
    create_guard
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS crawl_host_gates_guard ON crawl_host_gates;
      DROP FUNCTION IF EXISTS f1_crawl_host_gates_guard();
      DROP TABLE IF EXISTS crawl_host_gates;
    SQL
  end

  private

  def sql_list(values) = "(#{values.map { |v| "'#{v}'" }.join(',')})"

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

  # Identity frozen for life; the robots TERMINAL decision write-once; the robots state machine
  # confined to its forward edges. The rate/concurrency columns stay mutable — they are the gate's
  # working state and change on every claim and release.
  def create_guard
    execute <<~SQL
      CREATE FUNCTION f1_crawl_host_gates_guard() RETURNS trigger
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
        -- The robots terminal decision is WRITE-ONCE (schema :296). Once a host has failed closed it
        -- can never become fetchable within the run, and once rules are applied they cannot be
        -- swapped for different ones.
        IF OLD.robots_state IN #{sql_list(TERMINAL_STATES)} THEN
          IF NEW.robots_state IS DISTINCT FROM OLD.robots_state
             OR NEW.robots_rules IS DISTINCT FROM OLD.robots_rules
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
                  OR (OLD.robots_state = 'in_progress' AND NEW.robots_state IN #{sql_list(TERMINAL_STATES)})
                  -- a retryable attempt returns to pending for the next attempt (:444 schedule)
                  OR (OLD.robots_state = 'in_progress' AND NEW.robots_state = 'pending')) THEN
            RAISE EXCEPTION 'crawl_host_gate_robots_transition_unavailable % -> %',
              OLD.robots_state, NEW.robots_state USING ERRCODE = 'raise_exception';
          END IF;
        END IF;
        -- Every mutation advances the version by exactly one: it is the CAS defence for the claim.
        IF NEW.state_version IS DISTINCT FROM OLD.state_version + 1 THEN
          RAISE EXCEPTION 'crawl_host_gate_version_invalid' USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER crawl_host_gates_guard BEFORE UPDATE OR DELETE ON crawl_host_gates
        FOR EACH ROW EXECUTE FUNCTION f1_crawl_host_gates_guard();
    SQL
  end
end
