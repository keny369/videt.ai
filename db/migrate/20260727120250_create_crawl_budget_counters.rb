# frozen_string_literal: true

# S-07-007 run-wide budget accounting.
#
# CANONICAL AUTHORITY IS `schemas/POSTGRESQL_SCHEMA.md` :298, not the summary sentence in
# SEARCH_CRAWL_RETRIEVAL.md § Frontier And Deterministic Selection. The first draft of this table was
# built from the prose and the ADR-026 schema lens caught the divergence; :298 is stricter and names
# more:
#
#   | `crawl_budget_counters` | `T-MUT` | Crawl ID UNIQUE, reserved/committed page, queue,
#     received/expanded/accounted-byte, sitemap, redirect and request counters plus per-dimension
#     soft/hard event bits |
#
# So there are THREE byte dimensions, not one. :436 defines
# `accounted_response_bytes_i = max(received_after_transfer_coding, expanded_after_content_decoding)`
# and SEARCH_CRAWL_RETRIEVAL § Destination And HTTP Safety step 8 requires the connector to "stream
# through SEPARATE transfer-decoded and content-decoded bounded counters". Keeping all three lets the
# `max` be audited rather than asserted — with one counter, a defect in the formula is undetectable
# after the fact.
#
# WHY A RESERVE/COMMIT PROTOCOL RATHER THAN A COUNTER. :442:
#
#   "Before body reading, the scheduler RESERVES up to the per-URL maximum from the remaining
#    run-wide budget in that order; CONCURRENT RESERVATIONS MUST NOT SUM ABOVE the run-wide
#    maximum, unused bytes are RELEASED in the same order, and an attempt cannot add accounted
#    bytes BEYOND ITS RESERVATION."
#
# A plain "add bytes after reading" counter cannot satisfy that: N workers each reading a 10 MiB body
# would collectively pass the 1,250 MiB run bound before any of them incremented anything. The
# reservation is what makes the bound hold under concurrency, and it must be taken BEFORE the body is
# read. Every bound is therefore expressed IN THE STATEMENT'S OWN PREDICATE — reviewed under eight
# genuinely simultaneous workers, three were granted and the sum stayed under the ceiling.
#
# ORDERING IS NOT ENFORCED HERE, DELIBERATELY. :456 — "one coordinator commits discoveries and budget
# effects in increasing dequeue key. A completion with a later key waits in `fetched_pending_commit`"
# — makes ordered admission a SCHEDULER function, and no dispatcher exists until S-07-008. This
# tranche enforces the SUM and records `dequeue_key` on every attempt so the coordinator can enforce
# the ORDER without re-deriving it. Registered as an explicit obligation, not left implicit.
class CreateCrawlBudgetCounters < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE crawl_budget_counters (
        id                        uuid PRIMARY KEY,
        state_version             bigint NOT NULL DEFAULT 0,
        lock_version              bigint NOT NULL DEFAULT 0,
        created_at                timestamptz(6) NOT NULL,
        updated_at                timestamptz(6) NOT NULL,
        correlation_id            uuid NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        crawl_id                  uuid NOT NULL,

        -- :298's three byte dimensions. `accounted` is :436's max() of the other two and is the one
        -- the run bound is enforced against; `received` and `expanded` are kept so the formula is
        -- auditable rather than merely asserted.
        reserved_response_bytes   bigint NOT NULL DEFAULT 0 CHECK (reserved_response_bytes >= 0),
        committed_response_bytes  bigint NOT NULL DEFAULT 0 CHECK (committed_response_bytes >= 0),
        received_response_bytes   bigint NOT NULL DEFAULT 0 CHECK (received_response_bytes >= 0),
        expanded_response_bytes   bigint NOT NULL DEFAULT 0 CHECK (expanded_response_bytes >= 0),
        -- ":442 — limit_probe_bytes are detection telemetry, not accepted/accounted capacity", so
        -- they are counted apart and never enter any byte total.
        limit_probe_bytes         bigint NOT NULL DEFAULT 0 CHECK (limit_probe_bytes >= 0),

        reserved_pages            bigint NOT NULL DEFAULT 0 CHECK (reserved_pages >= 0),
        committed_pages           bigint NOT NULL DEFAULT 0 CHECK (committed_pages >= 0),
        queue_entries             bigint NOT NULL DEFAULT 0 CHECK (queue_entries >= 0),
        sitemap_documents         bigint NOT NULL DEFAULT 0 CHECK (sitemap_documents >= 0),
        redirects_followed        bigint NOT NULL DEFAULT 0 CHECK (redirects_followed >= 0),
        requests_made             bigint NOT NULL DEFAULT 0 CHECK (requests_made >= 0),

        -- ":442 — Soft-limit crossing emits CrawlSoftLimitApproaching ONCE PER DIMENSION AND RUN",
        -- and a hard limit "emits CrawlLimitReached EXACTLY ONCE per dimension and run". The bits
        -- record which dimensions have already fired; the guard below makes them ADD-ONLY, because a
        -- bit that can be erased cannot enforce "once". S-07-008 owns the emission that reads them.
        soft_limit_events         jsonb NOT NULL DEFAULT '{}',
        hard_limit_events         jsonb NOT NULL DEFAULT '{}',

        CONSTRAINT crawl_budget_counters_bytes_committed_within_reserved
          CHECK (committed_response_bytes <= reserved_response_bytes),
        CONSTRAINT crawl_budget_counters_pages_committed_within_reserved
          CHECK (committed_pages <= reserved_pages),
        CONSTRAINT crawl_budget_counters_crawl_unique UNIQUE (crawl_id),
        CONSTRAINT crawl_budget_counters_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT crawl_budget_counters_org_project_id_unique UNIQUE (organization_id, project_id, id),
        -- POSTGRESQL_SCHEMA :128 — every Project-owned child carries ALL THREE of
        -- (organization_id, project_id, id) into its parent, so a same-Organization cross-Project
        -- link is impossible at the database rather than merely unlikely.
        CONSTRAINT crawl_budget_counters_crawl_fk
          FOREIGN KEY (organization_id, project_id, crawl_id)
          REFERENCES crawls (organization_id, project_id, id)
      );

      ALTER TABLE crawl_budget_counters ENABLE ROW LEVEL SECURITY;
      ALTER TABLE crawl_budget_counters FORCE ROW LEVEL SECURITY;
      CREATE POLICY crawl_budget_counters_context ON crawl_budget_counters
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
    SQL

    add_guard
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS crawl_budget_counters_guard ON crawl_budget_counters;
      DROP FUNCTION IF EXISTS f1_crawl_budget_counters_guard();
      DROP TABLE IF EXISTS crawl_budget_counters;
    SQL
  end

  private

  # Identity is frozen and every RUN TOTAL is monotonic. `reserved_*` is the one exception in each
  # pair, because release depends on it falling — and it cannot be abused to erase accounting,
  # because `committed <= reserved` is a CHECK, so driving `reserved` down below what was committed
  # raises.
  MONOTONIC = %w[
    committed_response_bytes received_response_bytes expanded_response_bytes limit_probe_bytes
    committed_pages queue_entries sitemap_documents redirects_followed requests_made
  ].freeze

  IDENTITY = %w[id organization_id project_id crawl_id correlation_id created_at].freeze

  def add_guard
    identity = IDENTITY.map { |c| "NEW.#{c} IS DISTINCT FROM OLD.#{c}" }.join("\n           OR ")
    monotonic = MONOTONIC.map { |c| "NEW.#{c} < OLD.#{c}" }.join("\n           OR ")
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_crawl_budget_counters_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'crawl_budget_counters_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF #{identity} THEN
          RAISE EXCEPTION 'crawl_budget_counters_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.state_version <> OLD.state_version + 1 THEN
          RAISE EXCEPTION 'crawl_budget_counters_version_invalid' USING ERRCODE = 'raise_exception';
        END IF;
        IF #{monotonic} THEN
          RAISE EXCEPTION 'crawl_budget_counters_not_monotonic' USING ERRCODE = 'raise_exception';
        END IF;
        -- ":442 — once per dimension and run". A bit that can be cleared cannot enforce once, so the
        -- event maps are ADD-ONLY: every key already present must still be present and unchanged.
        IF NOT (NEW.soft_limit_events @> OLD.soft_limit_events
                AND NEW.hard_limit_events @> OLD.hard_limit_events) THEN
          RAISE EXCEPTION 'crawl_budget_counters_limit_events_not_add_only' USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER crawl_budget_counters_guard BEFORE DELETE OR UPDATE ON crawl_budget_counters
        FOR EACH ROW EXECUTE FUNCTION f1_crawl_budget_counters_guard();
    SQL
  end
end
