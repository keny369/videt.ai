# frozen_string_literal: true

# S-07-008 limit decisions (schemas/POSTGRESQL_SCHEMA.md :300; WORKFLOW_SPECIFICATIONS.md :442;
# API_CONTRACTS.md `crawl_limit_decision`).
#
# :442 is precise about what a limit hit must produce:
#
#   "Soft-limit crossing emits `CrawlSoftLimitApproaching` ONCE PER DIMENSION AND RUN. ... At any
#    other hard limit, stop scheduling affected work, preserve successful artifacts, RECORD
#    DIMENSION, CONFIGURED VALUE, OBSERVED VALUE, AFFECTED SOURCE AND URL COUNTS, set
#    `coverage_status=partial` and `completion_reason=limit_reached`, and emit `CrawlLimitReached`
#    EXACTLY ONCE PER DIMENSION AND RUN."
#
# "Exactly once per dimension and run" is `UNIQUE (crawl_id, limit_dimension, threshold_kind)`, and
# it is the whole reason this is a table rather than a counter: the uniqueness constraint IS the
# once-ness, so a replayed or raced emission collides instead of duplicating an event that customers
# see. `crawl_budget_counters`' event bits are the fast path that avoids the write; this row is the
# authority.
#
# T-IMM: a limit observation is a fact about a moment. It is never updated and never deleted — the
# observed value that triggered it does not become untrue when the run continues.
class CreateCrawlLimitDecisions < ActiveRecord::Migration[8.1]
  # :300's enum, exactly, in its order. Deliberately duplicated from `Wf005::LimitDimensions` rather
  # than generated: the database is the authority a future reader will trust, and a CHECK that
  # derives itself from application code is not a constraint on the application code.
  DIMENSIONS = %w[
    accepted_pages_per_run discovered_url_queue crawl_depth_from_source_root
    accounted_response_body_bytes_per_run response_body_per_url wall_clock_run_duration
    redirects_per_url request_rate_per_canonical_host concurrent_requests_per_canonical_host
    connection_plus_response_time_per_request sitemap_documents_per_run sitemap_index_nesting_depth
  ].freeze

  def up
    execute <<~SQL
      CREATE TABLE crawl_limit_decisions (
        id                       uuid PRIMARY KEY,
        schema_version           text NOT NULL,
        created_at               timestamptz(6) NOT NULL,

        -- LINEAGE (:116).
        correlation_id           uuid NOT NULL,
        causation_id             uuid NOT NULL,
        command_id               uuid,
        idempotency_key_digest   bytea CHECK (idempotency_key_digest IS NULL OR octet_length(idempotency_key_digest) = 32),
        content_sha256           bytea CHECK (content_sha256 IS NULL OR octet_length(content_sha256) = 32),

        organization_id          uuid NOT NULL,
        project_id               uuid NOT NULL,
        crawl_id                 uuid NOT NULL,

        limit_dimension          text NOT NULL CHECK (limit_dimension IN #{list(DIMENSIONS)}),
        threshold_kind           text NOT NULL CHECK (threshold_kind IN ('soft','hard')),
        -- :442 — "record dimension, CONFIGURED VALUE, OBSERVED VALUE, AFFECTED SOURCE AND URL COUNTS".
        configured_value         bigint NOT NULL CHECK (configured_value >= 0),
        observed_value           bigint NOT NULL CHECK (observed_value >= 0),
        affected_source_count    bigint NOT NULL CHECK (affected_source_count >= 0),
        affected_url_count       bigint NOT NULL CHECK (affected_url_count >= 0),

        decision_type            text NOT NULL CHECK (decision_type = 'crawl_limit_observation'),
        decision_value           text NOT NULL CHECK (decision_value IN ('soft_reached','hard_reached')),
        decision_status          text NOT NULL CHECK (decision_status = 'final'),
        decision_reason_code     text,
        -- The crawler Service Identity that observed it. A limit decision has an author.
        decided_by_service_identity_id uuid NOT NULL,
        -- "exact nonempty sorted-unique `definition_versions jsonb` containing the pinned
        -- global/Organization/Project Crawl Policy artifacts" (:300).
        definition_versions      jsonb NOT NULL,
        input_sha256             bytea NOT NULL CHECK (octet_length(input_sha256) = 32),
        output_sha256            bytea NOT NULL CHECK (octet_length(output_sha256) = 32),
        decided_at               timestamptz(6) NOT NULL,

        -- :300 — "A row check requires soft/soft_reached/null reason or hard/hard_reached/
        -- `limit_reached`". Written as one biconditional rather than three loose checks, so no
        -- combination can be assembled that satisfies each part and contradicts the whole.
        CONSTRAINT crawl_limit_decisions_threshold_agreement CHECK (
          (threshold_kind = 'soft' AND decision_value = 'soft_reached' AND decision_reason_code IS NULL)
          OR
          (threshold_kind = 'hard' AND decision_value = 'hard_reached' AND decision_reason_code = 'limit_reached')
        ),
        -- "exact nonempty sorted-unique" — nonempty and an array is enforceable here; sortedness and
        -- uniqueness are asserted by the writer and verified in its spec.
        CONSTRAINT crawl_limit_decisions_definition_versions_shape CHECK (
          jsonb_typeof(definition_versions) = 'array' AND jsonb_array_length(definition_versions) > 0
        ),
        -- :442's "exactly once per dimension and run", as a constraint rather than a convention.
        CONSTRAINT crawl_limit_decisions_once UNIQUE (crawl_id, limit_dimension, threshold_kind),
        CONSTRAINT crawl_limit_decisions_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT crawl_limit_decisions_org_project_id_unique UNIQUE (organization_id, project_id, id),
        -- POSTGRESQL_SCHEMA :128 — all three columns on every Project-owned link.
        CONSTRAINT crawl_limit_decisions_crawl_fk
          FOREIGN KEY (organization_id, project_id, crawl_id)
          REFERENCES crawls (organization_id, project_id, id)
      );

      CREATE INDEX crawl_limit_decisions_crawl ON crawl_limit_decisions (organization_id, crawl_id, decided_at);

      ALTER TABLE crawl_limit_decisions ENABLE ROW LEVEL SECURITY;
      ALTER TABLE crawl_limit_decisions FORCE ROW LEVEL SECURITY;
      CREATE POLICY crawl_limit_decisions_context ON crawl_limit_decisions
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
    SQL
    add_guard
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS crawl_limit_decisions_guard ON crawl_limit_decisions;
      DROP FUNCTION IF EXISTS f1_crawl_limit_decisions_guard();
      DROP TABLE IF EXISTS crawl_limit_decisions;
    SQL
  end

  private

  def list(values) = "(#{values.map { |v| "'#{v}'" }.join(',')})"

  # T-IMM: no UPDATE, no DELETE, ever. There is no frozen-column list to get wrong here because
  # nothing is mutable — which is the correct shape for an observation.
  def add_guard
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_crawl_limit_decisions_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        RAISE EXCEPTION 'crawl_limit_decision_immutable' USING ERRCODE = 'raise_exception';
      END;
      $$;
      CREATE TRIGGER crawl_limit_decisions_guard BEFORE DELETE OR UPDATE ON crawl_limit_decisions
        FOR EACH ROW EXECUTE FUNCTION f1_crawl_limit_decisions_guard();
    SQL
  end
end
