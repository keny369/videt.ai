# frozen_string_literal: true

module IdentityAccess
  module Infrastructure
    # Persistence for the per-entry terminal record (schemas/POSTGRESQL_SCHEMA.md :301;
    # WORKFLOW_SPECIFICATIONS.md :452, :454, :456), which is FU-21's home.
    #
    # ONE ROW PER RETIRED FRONTIER ENTRY, WRITTEN IN THE TRANSACTION THAT RETIRES IT. The frontier's
    # `terminal` state records only that an entry was acted on and is no longer selectable; it carries
    # no reason (`crawl_frontier_entries_discard_reason` reserves that for `discarded`) and it is not
    # always accompanied by a `fetch_attempts` row, because the fetch path authorizes BEFORE it claims
    # one. This row is what makes a covered URL distinguishable from an unretrieved one.
    #
    # TWO FIELDS ARE DERIVED IN SQL RATHER THAN SUPPLIED BY THE CALLER, and that is the point of them
    # being here rather than in the workflow:
    #
    #   * `commit_order` is the run's retirement sequence — :456's "committed in dequeue sequence" —
    #     taken as `MAX + 1` over the run's existing rows. The caller holds the per-Crawl frontier
    #     advisory lock across this statement, which is the same lock that makes admission happen in
    #     dequeue order, so the sequence this assigns IS the dequeue sequence and two concurrent
    #     retirements cannot compute the same number. `UNIQUE (crawl_id, commit_order)` is the backstop.
    #   * `accounted_response_body_bytes` is summed from the entry's COMMITTED content attempts rather
    #     than from the figure the pass that happens to be retiring the entry is holding. A URL that
    #     took :444's three attempts has three attempt rows and the total is all of them; the last
    #     pass's own number is one attempt's worth and would understate every retried URL. Deriving it
    #     here also means the terminal record cannot disagree with the attempt records it summarises,
    #     which is what makes :442's "run-wide accounted response-body bytes are EXACTLY
    #     sum(accounted_response_bytes_i)" reconcilable against this table.
    #
    # NO `ON CONFLICT`. The caller writes only after its compare-and-set on the frontier claim matched a
    # row, so exactly one pass per entry ever reaches this statement and a conflict on
    # `crawl_terminal_outcomes_entry_once` means something upstream is wrong. Absorbing it would hide
    # exactly the double-retirement the unique constraint exists to catch.
    class CrawlTerminalOutcomeStore
      SCHEMA_VERSION = "1.0"

      def initialize(pg_connection)
        @pg = pg_connection
      end

      def enter_org_context(org:, correlation_id:)
        query("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, correlation_id]).values.dig(0, 0)
      end

      # Record what happened to one frontier entry. Returns the assigned commit order and byte total, so
      # the caller reports what was STORED rather than what it intended to store.
      def record(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:causation_id], row[:command_id],
          row[:organization_id], row[:project_id], row[:crawl_id], row[:entry_id], row[:source_id],
          row[:outcome], row[:reason], row[:coverage_effect], row[:document_id]
        ]
        query(<<~SQL, params).to_a.first
          INSERT INTO crawl_terminal_outcomes
            (id, schema_version, created_at, correlation_id, causation_id, command_id,
             organization_id, project_id, crawl_id, crawl_frontier_entry_id, source_id,
             commit_order, outcome, reason, document_id, accounted_response_body_bytes,
             coverage_effect, decided_at)
          SELECT $1::uuid, '#{SCHEMA_VERSION}', $2::timestamptz, $3::uuid, $4::uuid, $5::uuid,
                 $6::uuid, $7::uuid, $8::uuid, $9::uuid, $10::uuid,
                 COALESCE((SELECT MAX(o.commit_order) FROM crawl_terminal_outcomes o
                           WHERE o.organization_id = $6::uuid AND o.crawl_id = $8::uuid), 0) + 1,
                 $11, $12,
                 -- THE LINK S-07-009 LEFT NULL, NOW SUPPLIED BY THE ARTIFACT ITSELF (S-07-010). It is
                 -- the Document `Wf005::IngestionHandoff` created in THIS transaction, or NULL for
                 -- every other outcome — which `crawl_terminal_outcomes_document_agreement` enforces
                 -- independently, so a non-`document_created` row cannot acquire one.
                 $14::uuid,
                 COALESCE((SELECT SUM(a.accounted_response_bytes) FROM fetch_attempts a
                           WHERE a.organization_id = $6::uuid AND a.crawl_id = $8::uuid
                             AND a.crawl_frontier_entry_id = $9::uuid
                             AND a.request_kind = 'content'), 0)::bigint,
                 $13, $2::timestamptz
          -- What was STORED, not what the caller intended to store: two of these columns were assigned
          -- by the statement itself, and the pass reports the classification from here so its ledger
          -- payload cannot describe a row the CHECK constraints would have refused.
          RETURNING id, commit_order, outcome, reason, coverage_effect, accounted_response_body_bytes,
                    document_id
        SQL
      end

      # Every terminal outcome of a run in :456's commit sequence. The terminal checkpoint reads this to
      # derive `crawls.coverage_status` and `crawls.completion_reason`, so the coverage measure is
      # computed from the recorded classifications rather than re-derived from attempts a second time.
      def outcomes(organization_id, crawl_id)
        query(<<~SQL, [organization_id, crawl_id]).to_a
          SELECT id, crawl_frontier_entry_id, source_id, commit_order, outcome, reason, document_id,
                 accounted_response_body_bytes, coverage_effect, decided_at
          FROM crawl_terminal_outcomes
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
          ORDER BY commit_order
        SQL
      end

      private

      def query(sql, params = []) = @pg.exec_params(sql, params)
      def iso(time) = time&.getutc&.iso8601(6)
    end
  end
end
