# frozen_string_literal: true

# S-07-009's per-entry terminal record (schemas/POSTGRESQL_SCHEMA.md :301; WORKFLOW_SPECIFICATIONS.md
# :452, :454, :456), and the home FU-21 said this information needed.
#
# FU-21, IN ITS OWN WORDS: "a terminal frontier entry can carry no `fetch_attempts` row, so a covered URL
# is indistinguishable from an unretrieved one." `Workflows::Wf005::FetchContent` authorizes BEFORE it
# claims an attempt row, so several ORDINARY outcomes retire an entry with no attempt at all — a URL
# refused by robots or by current scope, a refused host-gate claim, a lost race for an attempt number.
# The driver must still retire the entry, because the frontier guard admits no `in_progress -> queued`
# and no `in_progress -> discarded`, so a claimed entry that cannot be decided has no legal move but
# `terminal`; not taking it re-creates the permanently pinned depth ADR-087 exists to fix. The result was
# a `terminal` row with `reason` NULL and no attempt, byte-indistinguishable from a fetched covered entry
# and irreversible, because the guard refuses all five edges out of `terminal`.
#
# THE INFORMATION WAS NEVER LOST — it is durable in the WF-005 command result and audit record the pass
# writes — but it was not where the coverage classification would look. This table is where it looks.
#
# :452 IS THE AUTHORITY AND IT IS EXHAUSTIVE. "The content coverage set is every distinct canonical
# in-scope candidate retained by deduplication, PLUS every in-scope candidate discarded by a Crawl limit;
# robots-disallowed URLs, duplicate occurrences, unsupported media types, and redirect targets rejected by
# current scope are recorded as `policy_excluded` and are OUTSIDE the denominator. An admitted content URL
# has a COVERED outcome ONLY when it creates a valid Document, or returns terminal 404/410 and creates a
# valid body-free `crawl_observation` with reason `content_absent`."
#
# So the coverage effect of an outcome is not a judgement the writer gets to make: it is DERIVABLE from
# the outcome, and it is therefore written as a biconditional CHECK rather than left to the application.
# A row that says `document_created` and `not_covered` is not a bug to be found in review; it cannot
# exist. This mirrors `crawl_limit_decisions_threshold_agreement`, and for the same reason: a constraint
# assembled from loose parts can be satisfied part by part and contradicted as a whole.
#
# WHAT IS DELIBERATELY NOT DECIDED HERE. `document_id` is nullable because Documents are S-07-010's and
# nothing creates one yet; :301 says "Document ID NULL" for exactly that reason. `commit_order` is
# assigned per :456's dequeue sequence, and the ordering CONSUMER — the terminal checkpoint that reads
# these rows to derive `crawls.coverage_status` and `crawls.completion_reason` — is the next slice of this
# block, not this migration.
#
# T-IMM: a terminal outcome is a fact about a moment, and :456 makes it irreversible by design ("no edge
# leaves terminal"). It is never updated and never deleted.
class CreateCrawlTerminalOutcomes < ActiveRecord::Migration[8.1]
  # :452's classification, transcribed. COVERED is the closed pair the sentence names with "only when";
  # EXCLUDED is the single token it puts "outside the denominator"; everything else is in the denominator
  # and did not reach a covered outcome, which is what makes coverage partial.
  #
  # `limit_discarded` is NOT_COVERED and not excluded, which is the reading most easily got wrong: :452
  # puts "every in-scope candidate discarded by a Crawl limit" INSIDE the coverage set explicitly, and
  # :456 then requires it to record "its exact limit reason". A limit hit reduces coverage; it does not
  # remove the URL from the question.
  COVERED = %w[document_created content_absent].freeze
  EXCLUDED = %w[policy_excluded].freeze
  NOT_COVERED = %w[content_fetch_failed limit_discarded robots_unavailable_fail_closed].freeze
  OUTCOMES = (COVERED + EXCLUDED + NOT_COVERED).freeze

  EFFECTS = %w[covered not_covered excluded].freeze

  def up
    execute <<~SQL
      CREATE TABLE crawl_terminal_outcomes (
        id                       uuid PRIMARY KEY,
        schema_version           text NOT NULL,
        created_at               timestamptz(6) NOT NULL,

        -- LINEAGE (:116).
        correlation_id           uuid NOT NULL,
        causation_id             uuid NOT NULL,
        command_id               uuid,

        organization_id          uuid NOT NULL,
        project_id               uuid NOT NULL,
        crawl_id                 uuid NOT NULL,
        crawl_frontier_entry_id  uuid NOT NULL,
        source_id                uuid NOT NULL,

        -- :456 — "completed responses are buffered and their outgoing links are canonicalized, sorted,
        -- and committed in dequeue sequence". The order is the run's, so it is unique per run and
        -- strictly positive; zero would be indistinguishable from an unset bigint default.
        commit_order             bigint NOT NULL CHECK (commit_order > 0),

        outcome                  text NOT NULL CHECK (outcome IN #{list(OUTCOMES)}),
        -- :454/:456's "its EXACT limit reason". Free-form against a closed vocabulary the writer owns
        -- (`Workflows::Wf005::FetchContent::REASONS`), not re-enumerated here: this column's contract is
        -- that a discarded or failed entry HAS one, which is the part a CHECK can carry.
        reason                   text,
        -- S-07-010's. NULL until Documents exist (:301, "Document ID NULL").
        document_id              uuid,
        accounted_response_body_bytes bigint NOT NULL CHECK (accounted_response_body_bytes >= 0),

        coverage_effect          text NOT NULL CHECK (coverage_effect IN #{list(EFFECTS)}),
        decided_at               timestamptz(6) NOT NULL,

        -- :452's classification AS A DATABASE FACT. The effect is derivable from the outcome, so the two
        -- cannot disagree. Written as one biconditional over the whole vocabulary rather than three
        -- separate implications, so no combination satisfies each part and contradicts the whole.
        CONSTRAINT crawl_terminal_outcomes_coverage_agreement CHECK (
          (outcome IN #{list(COVERED)}     AND coverage_effect = 'covered')
          OR
          (outcome IN #{list(EXCLUDED)}    AND coverage_effect = 'excluded')
          OR
          (outcome IN #{list(NOT_COVERED)} AND coverage_effect = 'not_covered')
        ),
        -- :456 — "records its EXACT limit reason". An entry that did not reach a covered outcome must
        -- say why; a covered one has nothing to explain.
        CONSTRAINT crawl_terminal_outcomes_reason_presence CHECK (
          (coverage_effect = 'covered' AND reason IS NULL)
          OR
          (coverage_effect <> 'covered' AND reason IS NOT NULL)
        ),
        -- A Document can only belong to the outcome that created one.
        CONSTRAINT crawl_terminal_outcomes_document_agreement CHECK (
          document_id IS NULL OR outcome = 'document_created'
        ),

        -- :301 — "unique frontier entry". One entry retires exactly once, which is also what makes a
        -- redelivery's `superseded` pass write NOTHING rather than a second opinion.
        CONSTRAINT crawl_terminal_outcomes_entry_once UNIQUE (crawl_frontier_entry_id),
        CONSTRAINT crawl_terminal_outcomes_commit_order_once UNIQUE (crawl_id, commit_order),
        CONSTRAINT crawl_terminal_outcomes_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT crawl_terminal_outcomes_org_project_id_unique UNIQUE (organization_id, project_id, id),

        -- POSTGRESQL_SCHEMA :128 — all three columns on every Project-owned link, so a Crawl in Project A
        -- cannot record an outcome against Project B's frontier entry. FU-7 records that this rule has
        -- been violated silently three times; it is easier to satisfy than to detect.
        CONSTRAINT crawl_terminal_outcomes_crawl_fk
          FOREIGN KEY (organization_id, project_id, crawl_id)
          REFERENCES crawls (organization_id, project_id, id),
        CONSTRAINT crawl_terminal_outcomes_entry_fk
          FOREIGN KEY (organization_id, project_id, crawl_frontier_entry_id)
          REFERENCES crawl_frontier_entries (organization_id, project_id, id)
      );

      -- The checkpoint reads a whole run in commit order; that is the only access pattern this table has.
      CREATE INDEX crawl_terminal_outcomes_run ON crawl_terminal_outcomes
        (organization_id, crawl_id, commit_order);

      ALTER TABLE crawl_terminal_outcomes ENABLE ROW LEVEL SECURITY;
      ALTER TABLE crawl_terminal_outcomes FORCE ROW LEVEL SECURITY;
      CREATE POLICY crawl_terminal_outcomes_context ON crawl_terminal_outcomes
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
    SQL
    add_guard

    F1::RuntimeGrants.apply_all(connection)
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS crawl_terminal_outcomes_guard ON crawl_terminal_outcomes;
      DROP FUNCTION IF EXISTS f1_crawl_terminal_outcomes_guard();
      DROP TABLE IF EXISTS crawl_terminal_outcomes;
    SQL
  end

  private

  def list(values) = "(#{values.map { |v| "'#{v}'" }.join(',')})"

  # T-IMM: no UPDATE, no DELETE, ever. There is no frozen-column list to get wrong because nothing is
  # mutable, which is the correct shape for a coverage-bearing decision that :456 makes irreversible.
  def add_guard
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_crawl_terminal_outcomes_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        RAISE EXCEPTION 'crawl_terminal_outcome_immutable' USING ERRCODE = 'raise_exception';
      END;
      $$;
      CREATE TRIGGER crawl_terminal_outcomes_guard BEFORE DELETE OR UPDATE ON crawl_terminal_outcomes
        FOR EACH ROW EXECUTE FUNCTION f1_crawl_terminal_outcomes_guard();
    SQL
  end
end
