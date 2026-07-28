# frozen_string_literal: true

# S-07-002 review hardening (ADR-026 schema lens; DECISIONS ADR-073b). Makes the OD-018 "one
# initial Evaluation per Crawl" DB backstop self-sufficient. The partial-unique index
# `evaluations_initial_per_crawl_unique` (20260727120090) is ON (organization_id, project_id,
# crawl_id) WHERE kind='initial'; because crawl_id is nullable and btree treats NULLs as distinct,
# two kind='initial' rows with a NULL crawl_id would both insert, silently voiding the backstop.
# StartCrawl (S-07-003) always inserts the initial Evaluation WITH its crawl_id and the evaluations
# guard freezes crawl_id, so this is defence-in-depth — but the CHECK removes the reliance on the
# application layer so the invariant is guaranteed by the database itself.
class EvaluationsInitialRequiresCrawl < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE evaluations
        ADD CONSTRAINT evaluations_initial_requires_crawl
        CHECK (kind <> 'initial' OR crawl_id IS NOT NULL);
    SQL
  end

  def down
    execute "ALTER TABLE evaluations DROP CONSTRAINT evaluations_initial_requires_crawl;"
  end
end
