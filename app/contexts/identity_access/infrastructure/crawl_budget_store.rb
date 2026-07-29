# frozen_string_literal: true

require "json"

module IdentityAccess
  module Infrastructure
    # Persistence for the S-07-007 run-wide budget counters (schemas/POSTGRESQL_SCHEMA.md :298;
    # WORKFLOW_SPECIFICATIONS.md :436/:442).
    #
    # EVERY BOUND IS TESTED IN THE STATEMENT'S OWN PREDICATE, never read-then-written. :442 requires
    # that "concurrent reservations MUST NOT sum above the run-wide maximum", and a read followed by
    # a write cannot deliver that: N workers each read the same remaining budget and each proceed.
    # Putting the bound in the `WHERE` makes the row lock the serialisation point — the second
    # worker's UPDATE matches no row and it learns the budget is spent, which is exactly the
    # behaviour the sentence describes.
    class CrawlBudgetStore
      def initialize(pg_connection)
        @pg = pg_connection
      end

      def enter_org_context(org:, correlation_id:)
        query("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, correlation_id]).values.dig(0, 0)
      end

      # Create the counter row for a Crawl if it does not exist, and return it. Idempotent under the
      # unique key, so concurrent workers converge on one row rather than racing to create two.
      def ensure_counters(id:, now:, correlation_id:, organization_id:, project_id:, crawl_id:)
        query(<<~SQL, [id, iso(now), correlation_id, organization_id, project_id, crawl_id])
          INSERT INTO crawl_budget_counters
            (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id, crawl_id)
          VALUES ($1::uuid, 0, $2::timestamptz, $2::timestamptz, $3::uuid, $4::uuid, $5::uuid, $6::uuid)
          ON CONFLICT (crawl_id) DO NOTHING
        SQL
        counters(organization_id, crawl_id)
      end

      def counters(organization_id, crawl_id)
        query(<<~SQL, [organization_id, crawl_id]).to_a.first
          SELECT * FROM crawl_budget_counters
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
        SQL
      end

      # Reserve EXACTLY `want` bytes, or nothing. Returns the new reserved total, or nil when the
      # reservation would take the run past its ceiling.
      #
      # The caller sizes `want` from the remaining budget (:442 — "reserves UP TO the per-URL
      # maximum from the REMAINING run-wide budget") and retries with a smaller figure if another
      # worker got there first. The bound is expressed as `reserved + want <= ceiling` IN THE
      # PREDICATE rather than as a read followed by a write, because :442 requires that "concurrent
      # reservations MUST NOT SUM ABOVE the run-wide maximum" — and a read-then-write lets N workers
      # each observe the same headroom and each take it. Here the row lock serialises them and the
      # loser matches no row.
      #
      # An exact reservation rather than a clamped one is deliberate: PostgreSQL 17 cannot return a
      # pre-update value, so a `LEAST(...)`-clamped UPDATE could not tell the caller how much it
      # actually got — and an attempt that does not know its own reservation cannot honour ":442 —
      # an attempt cannot add accounted bytes beyond its reservation".
      # Returns the row AFTER the reservation, so the caller sees the RESERVED PEAK this call
      # produced. That is what :442's "a soft event fires when the observed OR RESERVED value first
      # equals the soft limit" needs: a peak that is later released is unobservable from the stored
      # row, but it is visible right here, to the statement that caused it.
      def reserve_bytes(organization_id, crawl_id, want, ceiling, now)
        return nil if want.to_i <= 0

        params = [organization_id, crawl_id, want.to_i, ceiling.to_i, iso(now)]
        query(<<~SQL, params).to_a.first
          UPDATE crawl_budget_counters
          SET reserved_response_bytes = reserved_response_bytes + $3,
              state_version = state_version + 1, updated_at = $5::timestamptz
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
            AND reserved_response_bytes + $3 <= $4
          RETURNING reserved_response_bytes, committed_response_bytes
        SQL
      end

      # NOTE: there is deliberately no `claim_limit_event` here any more, and nothing reads
      # `soft_limit_events` / `hard_limit_events`. S-07-008 (1/n) added a counter-bit claim as the
      # once-per-run mechanism; 3/n replaced it with `crawl_limit_decisions`, whose
      # `UNIQUE (crawl_id, limit_dimension, threshold_kind)` IS :442's "exactly once per dimension
      # and run" and is the only participant that can adjudicate "first" across processes. The
      # superseded method survived with its rationale intact and no caller — an untested write
      # surface on this row, and three comments elsewhere describing it as a live pre-filter. It is
      # removed rather than left dormant. The columns remain because POSTGRESQL_SCHEMA :299 defines
      # them; if a future tranche wants them as a read-side projection it should say so explicitly.

      # Commit what the attempt actually consumed and RELEASE the unused remainder of its
      # reservation in the same statement (:442 — "unused bytes are released in the same order").
      # Doing both at once is what stops a crash between them from permanently retiring budget that
      # was never spent.
      #
      # `limit_probe_bytes` is added to its own counter, never to either byte total: :442 calls
      # probes "detection telemetry, not accepted/accounted capacity".
      def commit_bytes(organization_id, crawl_id, measurement, now)
        params = [organization_id, crawl_id, measurement.fetch(:reserved).to_i,
                  measurement.fetch(:accounted).to_i, measurement.fetch(:probe_bytes).to_i,
                  measurement.fetch(:received).to_i, measurement.fetch(:expanded).to_i, iso(now)]
        query(<<~SQL, params).to_a.first
          UPDATE crawl_budget_counters
          SET committed_response_bytes = committed_response_bytes + $4,
              received_response_bytes = received_response_bytes + $6,
              expanded_response_bytes = expanded_response_bytes + $7,
              reserved_response_bytes = reserved_response_bytes - ($3 - $4),
              limit_probe_bytes = limit_probe_bytes + $5,
              requests_made = requests_made + 1,
              state_version = state_version + 1, updated_at = $8::timestamptz
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
          RETURNING committed_response_bytes, reserved_response_bytes, limit_probe_bytes
        SQL
      end

      # Release a whole reservation — the attempt never read a body at all (refused, denied,
      # unreachable), so nothing was consumed.
      # The floor is `committed_response_bytes`, not zero. `committed <= reserved` is a CHECK, so
      # clamping to zero raised a `PG::CheckViolation` at the caller the moment a release outran what
      # was still outstanding — which is exactly the shape the reclamation sweeper produces.
      def release_bytes(organization_id, crawl_id, reserved, now)
        params = [organization_id, crawl_id, reserved.to_i, iso(now)]
        query(<<~SQL, params).to_a.first
          UPDATE crawl_budget_counters
          SET reserved_response_bytes =
                GREATEST(committed_response_bytes, reserved_response_bytes - $3),
              state_version = state_version + 1, updated_at = $4::timestamptz
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
          RETURNING reserved_response_bytes
        SQL
      end

      # NOTE: page reservation is deliberately NOT here. :436 retains "the first 10,000 successful
      # DOCUMENTS in dequeue order", and :456 says "concurrent fetch completion does not change
      # discovery order" — so admitting a page at fetch completion, as the first draft did, decides
      # the bound in completion order rather than dequeue order and can never be committed, because
      # the Document it counts is created by S-07-010. The counters exist; the reservation belongs
      # with the Document.

      # :437's run-wide sitemap-document budget. Schema :298 assigns "sitemap documents" to THIS
      # table, so this is its one home; `DiscoverSitemaps` was repointed here and the duplicate on
      # `CrawlHostGateStore` (which wrote `crawls.limit_counters`) is deleted. The first draft added
      # this method and left the workflow calling the old one, which created the second home the
      # migration claimed to eliminate.
      def reserve_sitemap_document(organization_id, crawl_id, ceiling, now)
        params = [organization_id, crawl_id, ceiling.to_i, iso(now)]
        query(<<~SQL, params).to_a.first
          UPDATE crawl_budget_counters
          SET sitemap_documents = sitemap_documents + 1,
              state_version = state_version + 1, updated_at = $4::timestamptz
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid AND sitemap_documents < $3
          RETURNING sitemap_documents
        SQL
      end

      def count_redirects(organization_id, crawl_id, followed, now)
        params = [organization_id, crawl_id, followed.to_i, iso(now)]
        query(<<~SQL, params).to_a.first
          UPDATE crawl_budget_counters
          SET redirects_followed = redirects_followed + $3,
              state_version = state_version + 1, updated_at = $4::timestamptz
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
          RETURNING redirects_followed
        SQL
      end

      private

      # Named `query` rather than `exec` for the reason recorded in `CrawlHostGateStore`: a private
      # `exec` shadows `Kernel#exec` and makes every fragment-interpolating statement read as command
      # execution to a static analyser. Every parameter here is bound, never interpolated.
      def query(sql, params = []) = @pg.exec_params(sql, params)

      def iso(time) = time.utc.iso8601(6)
    end
  end
end
