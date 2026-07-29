# frozen_string_literal: true

# The run-wide sitemap-document budget needs a DURABLE identity, not an in-memory one
# (WORKFLOW_SPECIFICATIONS.md :437 — "sitemap documents per RUN | 40 | 50 | **distinct canonical
# sitemap URLs**").
#
# S-07-008 charged the budget once per distinct URL using a Ruby hash on the traversal object. That
# is correct within one pass and meaningless across passes: a `Traversal` is constructed fresh on
# every `DiscoverSitemaps#call`, so FU-9's re-entry re-charged every URL that had already reached
# the network and failed. Four of the five ADR-026 lenses reached it. A host with one failing
# candidate and one paced candidate re-enters indefinitely and spends the whole run-wide 50 on two
# distinct URLs, then emits a hard `CrawlLimitReached` for `sitemap_documents_per_run` — the false
# limit event the FU-9 repair existed to remove, reached by a different route.
#
# ":437's unit is DISTINCT URLs" is therefore `UNIQUE (crawl_id, canonical_url_sha256)`, adjudicated
# by the database, exactly as `crawl_limit_decisions` makes ":442's once per dimension and run" a
# unique key rather than a counter.
#
# THIS TABLE IS THE ONLY AUTHORITY. The bound is `COUNT(*) < ceiling` over these rows, evaluated
# under the per-Crawl `crawl_budget_counters` row lock that serialises charges.
# `crawl_budget_counters.sitemap_documents` is a DECLARED PROJECTION recomputed from this table in
# the same statement that inserts into it — never incremented, so the two cannot disagree, and there
# is no second enforcement site connected to this one only by convention.
#
# T-IMM: a charge is a fact about an attempt that was made. It is never updated and never deleted —
# releasing one would let a URL be charged twice, which is the defect this table exists to prevent.
class CreateCrawlSitemapDocumentCharges < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE crawl_sitemap_document_charges (
        id                     uuid PRIMARY KEY,
        schema_version         text NOT NULL,
        created_at             timestamptz(6) NOT NULL,
        correlation_id         uuid NOT NULL,

        organization_id        uuid NOT NULL,
        project_id             uuid NOT NULL,
        crawl_id               uuid NOT NULL,

        canonical_url          text NOT NULL CHECK (length(canonical_url) BETWEEN 1 AND 8192),
        canonical_url_sha256   bytea NOT NULL CHECK (octet_length(canonical_url_sha256) = 32),
        charged_at             timestamptz(6) NOT NULL,

        -- :437's unit, as a constraint rather than a convention.
        CONSTRAINT crawl_sitemap_document_charges_once UNIQUE (crawl_id, canonical_url_sha256),
        CONSTRAINT crawl_sitemap_document_charges_org_id_unique UNIQUE (organization_id, id),
        -- POSTGRESQL_SCHEMA :128 — all three columns on every Project-owned link.
        CONSTRAINT crawl_sitemap_document_charges_crawl_fk
          FOREIGN KEY (organization_id, project_id, crawl_id)
          REFERENCES crawls (organization_id, project_id, id)
      );

      CREATE INDEX crawl_sitemap_document_charges_crawl
        ON crawl_sitemap_document_charges (organization_id, crawl_id, charged_at);

      ALTER TABLE crawl_sitemap_document_charges ENABLE ROW LEVEL SECURITY;
      ALTER TABLE crawl_sitemap_document_charges FORCE ROW LEVEL SECURITY;
      CREATE POLICY crawl_sitemap_document_charges_context ON crawl_sitemap_document_charges
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());

      CREATE OR REPLACE FUNCTION f1_crawl_sitemap_document_charges_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        RAISE EXCEPTION 'crawl_sitemap_document_charge_immutable' USING ERRCODE = 'raise_exception';
      END;
      $$;
      CREATE TRIGGER crawl_sitemap_document_charges_guard
        BEFORE DELETE OR UPDATE ON crawl_sitemap_document_charges
        FOR EACH ROW EXECUTE FUNCTION f1_crawl_sitemap_document_charges_guard();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS crawl_sitemap_document_charges_guard ON crawl_sitemap_document_charges;
      DROP FUNCTION IF EXISTS f1_crawl_sitemap_document_charges_guard();
      DROP TABLE IF EXISTS crawl_sitemap_document_charges;
    SQL
  end
end
