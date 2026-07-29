# frozen_string_literal: true

require "digest"

module IdentityAccess
  module Infrastructure
    # Persistence for the S-07-007 attempt record (SEARCH_CRAWL_RETRIEVAL.md § Frontier And
    # Deterministic Selection; WORKFLOW_SPECIFICATIONS.md :442/:444/:452).
    #
    # THE ROW IS CREATED BEFORE THE CONNECTION, not after it. SEARCH_CRAWL_RETRIEVAL :82 — "Process
    # loss after claim is repaired by the lease sweeper; the same attempt identity is completed or
    # timed out, NEVER REPLACED BY AN UNACCOUNTED REQUEST." A record written only on success would
    # make a lost worker's request invisible: its bytes were reserved and its host-gate slot was
    # spent, and nothing would show either.
    class FetchAttemptStore
      def initialize(pg_connection)
        @pg = pg_connection
      end

      def enter_org_context(org:, correlation_id:)
        query("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, correlation_id]).values.dig(0, 0)
      end

      # Claim the attempt. The unique key `(crawl_id, frontier_entry_id, kind, attempt_number)` makes
      # a replay of the same attempt a no-op rather than a second request — which is what :444's
      # "one initial attempt plus at most two retries" means when a worker is retried by the queue
      # rather than by the retry loop.
      def claim(row)
        preimage = row[:canonical_url].to_s.unicode_normalize(:nfc).b
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id],
                  row[:project_id], row[:crawl_id], row[:source_id], row[:frontier_entry_id],
                  row[:kind], row[:attempt_number], row[:canonical_url], bytea(preimage),
                  bytea(Digest::SHA256.digest(preimage)), row[:canonical_host], row[:depth],
                  row[:scope_policy_id], row[:scope_policy_version], row[:crawl_policy_id],
                  row[:crawl_policy_version], row[:reserved_bytes]]
        query(<<~SQL, params).to_a.first
          INSERT INTO fetch_attempts
            (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id,
             crawl_id, source_id, frontier_entry_id, kind, attempt_number, canonical_url,
             canonical_url_preimage, canonical_url_sha256, canonical_host, depth,
             scope_policy_id, scope_policy_version, crawl_policy_id, crawl_policy_version,
             reserved_bytes, started_at)
          VALUES ($1::uuid, 0, $2::timestamptz, $2::timestamptz, $3::uuid, $4::uuid, $5::uuid,
                  $6::uuid, $7::uuid, $8::uuid, $9, $10, $11, $12, $13, $14, $15,
                  $16::uuid, $17, $18::uuid, $19, $20, $2::timestamptz)
          ON CONFLICT (crawl_id, frontier_entry_id, kind, attempt_number) DO NOTHING
          RETURNING id, state_version, reserved_bytes
        SQL
      end

      def attempt(organization_id, id)
        query("SELECT * FROM fetch_attempts WHERE organization_id = $1::uuid AND id = $2::uuid",
              [organization_id, id]).to_a.first
      end

      # Write the write-once result. Guarded on `outcome IS NULL` as well as the expected version, so
      # a replayed terminalisation cannot overwrite a decision :452's coverage classification may
      # already have read.
      def terminalize(id, expected_version, now, result)
        params = [id, expected_version, iso(now), result[:outcome], result[:reason_code],
                  result[:http_status], result[:accounted_response_bytes], result[:received_body_bytes],
                  result[:expanded_body_bytes], result[:limit_probe_bytes].to_i, result[:media_type],
                  result[:redirect_count], result[:final_url],
                  result[:body_sha256] && bytea(result[:body_sha256]), result[:retryable],
                  result[:latency_ms]]
        query(<<~SQL, params).cmd_tuples
          UPDATE fetch_attempts
          SET outcome = $4, reason_code = $5, http_status = $6, accounted_response_bytes = $7,
              received_body_bytes = $8, expanded_body_bytes = $9, limit_probe_bytes = $10,
              media_type = $11, redirect_count = $12, final_url = $13, body_sha256 = $14,
              retryable = $15, latency_ms = $16, terminal_at = $3::timestamptz,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state_version = $2 AND outcome IS NULL
        SQL
      end

      # Every attempt of a run, in :442's canonical order — "run-wide accounted response-body bytes
      # are exactly sum(accounted_response_bytes_i) IN CANONICAL DEQUEUE/ATTEMPT ORDER".
      def attempts_for(organization_id, crawl_id)
        query(<<~SQL, [organization_id, crawl_id]).to_a
          SELECT * FROM fetch_attempts
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
          ORDER BY started_at, id
        SQL
      end

      # How many attempts this frontier entry has already had, so :444's bound is read from
      # committed state rather than carried in a worker's memory across a process loss.
      def attempt_count(organization_id, crawl_id, frontier_entry_id, kind)
        query(<<~SQL, [organization_id, crawl_id, frontier_entry_id, kind]).to_a.first["count"].to_i
          SELECT COUNT(*) AS count FROM fetch_attempts
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
            AND frontier_entry_id = $3::uuid AND kind = $4
        SQL
      end

      private

      def query(sql, params = []) = @pg.exec_params(sql, params)
      def bytea(binary) = { value: binary, format: 1, type: 17 }
      def iso(time) = time.utc.iso8601(6)
    end
  end
end
