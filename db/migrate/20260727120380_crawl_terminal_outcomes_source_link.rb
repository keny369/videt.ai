# frozen_string_literal: true

# B5: `crawl_terminal_outcomes.source_id` is a Project-owned link that carried NO foreign key at all.
#
# `20260727120350` declared `source_id uuid NOT NULL`, constrained `crawl_id` and
# `crawl_frontier_entry_id`, and omitted the third — under a comment invoking POSTGRESQL_SCHEMA.md :128
# and FU-7 BY NAME: "all three columns on every Project-owned link … FU-7 records that this rule has been
# violated silently three times; it is easier to satisfy than to detect." It was the fourth instance, and
# it was asserted-as-satisfied by the very proof written to catch it.
#
# It is the ONLY table in the schema carrying `source_id` without one. Nine siblings have it:
# `crawl_frontier_entries`, `crawl_frontier_occurrences`, `crawl_sources`, `evidence`, `fetch_attempts`,
# `source_scope_policies`, `source_scope_change_requests`, `verification_attempts`,
# `verification_requests`. Probed as `f1_web` before this migration, the table admitted both a
# cross-Project `source_id` and a wholly fabricated UUID.
#
# WHY THE PROOF COULD NOT SEE IT, which is the more important half. PROOF 39 enumerated
# `pg_constraint … contype = 'f'` and asserted arity 3 on each row returned. AN ABSENT FOREIGN KEY HAS NO
# ARITY, so it passed on the two that existed and its own title — "so coverage cannot cross a Project" —
# was false. The proof is rewritten alongside this to assert the expected link SET: every column naming a
# Project-owned parent must be covered by an arity-3 foreign key. A check that reads what is there cannot
# find what is missing.
#
# NOT REACHABLE THROUGH PRODUCTION — `CrawlDriver#record_outcome` passes `entry["source_id"]` read under
# the frontier lock — so this is defence in depth. That is exactly what :128 is: the rule exists because
# the reachable path is not the only path a future tranche will take.
class CrawlTerminalOutcomesSourceLink < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE crawl_terminal_outcomes
        ADD CONSTRAINT crawl_terminal_outcomes_source_fk
        FOREIGN KEY (organization_id, project_id, source_id)
        REFERENCES sources (organization_id, project_id, id);
    SQL
  end

  def down
    execute "ALTER TABLE crawl_terminal_outcomes DROP CONSTRAINT crawl_terminal_outcomes_source_fk;"
  end
end
