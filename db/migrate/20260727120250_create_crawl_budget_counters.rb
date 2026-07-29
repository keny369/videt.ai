# frozen_string_literal: true

# S-07-007 run-wide budget accounting (SEARCH_CRAWL_RETRIEVAL.md § Frontier And Deterministic
# Selection — "`crawl_budget_counters`: reserved/committed pages, queue entries, accounted bytes,
# sitemap documents, redirects and limit-event bits"; WORKFLOW_SPECIFICATIONS.md :436/:442).
#
# WHY A RESERVE/COMMIT PROTOCOL RATHER THAN A COUNTER. :442 is unusually specific:
#
#   "Before body reading, the scheduler RESERVES up to the per-URL maximum from the remaining
#    run-wide budget in that order; CONCURRENT RESERVATIONS MUST NOT SUM ABOVE the run-wide
#    maximum, unused bytes are RELEASED in the same order, and an attempt cannot add accounted
#    bytes BEYOND ITS RESERVATION."
#
# A plain "add bytes after reading" counter cannot satisfy that: N workers each reading a 10 MiB
# body would collectively pass the 1,250 MiB run bound before any of them incremented anything. The
# reservation is what makes the bound hold under concurrency, and it must be taken BEFORE the body
# is read — which is also why the released remainder matters: an attempt that reserved 10 MiB and
# received 4 KiB must hand back the difference or the run's budget evaporates.
#
# `reserved_*` is the sum of live reservations plus everything committed; `committed_*` is what was
# actually consumed. The invariant `committed <= reserved` is a CHECK, not a convention.
#
# ONE ROW PER CRAWL, so the reservation is a single-row UPDATE with the bound IN THE PREDICATE —
# two concurrent reservations serialise on the row and the second sees the first's committed state.
# Schema :298 assigns these run-wide counters here, which also gives the sitemap-document counter
# S-07-006 put on `crawls.limit_counters` its ratified home; it is migrated across so there is ONE
# canonical place a run-wide bound is read, not two.
class CreateCrawlBudgetCounters < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE crawl_budget_counters (
        id                        uuid PRIMARY KEY,
        state_version             bigint NOT NULL DEFAULT 0,
        created_at                timestamptz(6) NOT NULL,
        updated_at                timestamptz(6) NOT NULL,
        correlation_id            uuid NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        crawl_id                  uuid NOT NULL,

        -- :442's byte dimensions. Reserved includes committed; the difference is what is live.
        reserved_response_bytes   bigint NOT NULL DEFAULT 0 CHECK (reserved_response_bytes >= 0),
        committed_response_bytes  bigint NOT NULL DEFAULT 0 CHECK (committed_response_bytes >= 0),
        -- ":442 — limit_probe_bytes are detection telemetry, not accepted/accounted capacity",
        -- so they are counted SEPARATELY and never enter either byte counter.
        limit_probe_bytes         bigint NOT NULL DEFAULT 0 CHECK (limit_probe_bytes >= 0),

        -- :436's page and queue dimensions, and the sitemap/redirect counters schema :298 names.
        reserved_pages            bigint NOT NULL DEFAULT 0 CHECK (reserved_pages >= 0),
        committed_pages           bigint NOT NULL DEFAULT 0 CHECK (committed_pages >= 0),
        queue_entries             bigint NOT NULL DEFAULT 0 CHECK (queue_entries >= 0),
        sitemap_documents         bigint NOT NULL DEFAULT 0 CHECK (sitemap_documents >= 0),
        redirects_followed        bigint NOT NULL DEFAULT 0 CHECK (redirects_followed >= 0),

        -- ":442 — Soft-limit crossing emits CrawlSoftLimitApproaching ONCE PER DIMENSION AND RUN",
        -- and a hard limit "emits CrawlLimitReached EXACTLY ONCE per dimension and run". The bits
        -- are what make "once" enforceable; S-07-008 owns the emission that reads them.
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
        -- (organization_id, project_id, id) into its parent, so a same-Organization
        -- cross-Project link is impossible at the database rather than merely unlikely.
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
    migrate_sitemap_counter
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS crawl_budget_counters_guard ON crawl_budget_counters;
      DROP FUNCTION IF EXISTS f1_crawl_budget_counters_guard();
      DROP TABLE IF EXISTS crawl_budget_counters;
    SQL
  end

  private

  # T-MUT with monotonic counters. Every one of these dimensions is a RUN TOTAL: it may rise, and a
  # reservation may be released, but a counter must never be rewritten to an arbitrary value and the
  # identity of the row it belongs to must never change. Committed totals are strictly monotonic —
  # bytes already accounted cannot be un-accounted, which is what makes :442's "in dequeue/attempt
  # order" sum reproducible.
  def add_guard
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_crawl_budget_counters_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'crawl_budget_counters_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.crawl_id IS DISTINCT FROM OLD.crawl_id
           OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
          RAISE EXCEPTION 'crawl_budget_counters_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.state_version <> OLD.state_version + 1 THEN
          RAISE EXCEPTION 'crawl_budget_counters_version_invalid' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.committed_response_bytes < OLD.committed_response_bytes
           OR NEW.committed_pages < OLD.committed_pages
           OR NEW.limit_probe_bytes < OLD.limit_probe_bytes
           OR NEW.sitemap_documents < OLD.sitemap_documents
           OR NEW.redirects_followed < OLD.redirects_followed THEN
          RAISE EXCEPTION 'crawl_budget_counters_not_monotonic' USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER crawl_budget_counters_guard BEFORE DELETE OR UPDATE ON crawl_budget_counters
        FOR EACH ROW EXECUTE FUNCTION f1_crawl_budget_counters_guard();
    SQL
  end

  # S-07-006 put the run-wide sitemap-document count on `crawls.limit_counters` because this table
  # did not yet exist. Schema :298 assigns it here, so it moves — with its value — rather than
  # leaving two places a reader might look for the same bound.
  def migrate_sitemap_counter
    execute <<~SQL
      INSERT INTO crawl_budget_counters
        (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id,
         crawl_id, sitemap_documents)
      SELECT gen_random_uuid(), 0, now(), now(), c.correlation_id, c.organization_id, c.project_id,
             c.id, COALESCE((c.limit_counters->>'sitemap_documents')::bigint, 0)
      FROM crawls c
      WHERE c.limit_counters ? 'sitemap_documents'
      ON CONFLICT (crawl_id) DO NOTHING;
    SQL
  end
end
