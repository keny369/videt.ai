# frozen_string_literal: true

require "digest"

module IdentityAccess
  module Infrastructure
    # Persistence for the S-07-007 attempt record (schemas/POSTGRESQL_SCHEMA.md :298;
    # WORKFLOW_SPECIFICATIONS.md :442/:444/:452).
    #
    # THE ROW IS CREATED BEFORE THE CONNECTION, not after it. SEARCH_CRAWL_RETRIEVAL :82 — "Process
    # loss after claim is repaired by the lease sweeper; the same attempt identity is completed OR
    # TIMED OUT, never replaced by an unaccounted request." A record written only on success would
    # make a lost worker's request invisible: its bytes were reserved and its host-gate slot was
    # spent, and nothing would show either.
    #
    # THE CLAIM CARRIES A LEASE, which is the half the first draft omitted. Without it "or timed out"
    # had no physical representation: the ADR-026 concurrency lens killed three workers on one
    # frontier entry and the entry was retired for the rest of the run, each loss also retiring 10 MiB
    # — 0.8% — of the run's byte budget with no way to reclaim it. `sweep_expired` is the repair, and
    # it returns the reservations it reclaimed so the caller can hand them back to the run.
    class FetchAttemptStore
      # Generously longer than the worst legitimate attempt: 11 connections (initial + the hard
      # redirect budget) at the 15-second hard request timeout is 165 s, so a live attempt is never
      # reclaimed out from under itself.
      LEASE_SECONDS = 300

      def initialize(pg_connection)
        @pg = pg_connection
      end

      def enter_org_context(org:, correlation_id:)
        query("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, correlation_id]).values.dig(0, 0)
      end

      # Claim the attempt, taking a lease. The key `(crawl_host_gate_id, request_kind,
      # crawl_frontier_entry_id, attempt_number)` is `UNIQUE NULLS NOT DISTINCT`, so a replay of the
      # same attempt is a no-op rather than a second request — including for robots attempts, whose
      # frontier entry is NULL and which a plain UNIQUE would not have constrained at all.
      def claim(row)
        preimage = row[:canonical_url].to_s.unicode_normalize(:nfc).b
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:causation_id],
                  row[:organization_id], row[:project_id], row[:crawl_id], row[:crawl_host_gate_id],
                  row[:source_id], row[:frontier_entry_id], row[:kind], row[:attempt_number],
                  row[:canonical_url], bytea(preimage), bytea(Digest::SHA256.digest(preimage)),
                  row[:canonical_host], row[:depth], row[:dequeue_key] && bytea(row[:dequeue_key]),
                  row[:scope_policy_id], row[:scope_policy_version], row[:crawl_policy_id],
                  row[:crawl_policy_version], row[:reserved_bytes], row[:claim_owner],
                  LEASE_SECONDS, iso(row[:deadline_at])]
        query(<<~SQL, params).to_a.first
          INSERT INTO fetch_attempts
            (id, checkpoint_version, lock_version, schema_version, created_at, updated_at,
             correlation_id, causation_id, organization_id, project_id, crawl_id,
             crawl_host_gate_id, source_id, crawl_frontier_entry_id, request_kind, attempt_number,
             canonical_url, canonical_url_preimage, canonical_url_sha256, canonical_host, depth,
             dequeue_key, scope_policy_id, scope_policy_version, crawl_policy_id,
             crawl_policy_version, reserved_bytes,
             claim_owner, claim_generation, claimed_at, lease_expires_at,
             prepared_at, deadline_at)
          VALUES ($1::uuid, 0, 0, 'fetch-attempt-v1', $2::timestamptz, $2::timestamptz,
                  $3::uuid, $4::uuid, $5::uuid, $6::uuid, $7::uuid,
                  $8::uuid, $9::uuid, $10::uuid, $11, $12,
                  $13, $14, $15, $16, $17,
                  $18, $19::uuid, $20, $21::uuid,
                  $22, $23,
                  $24::uuid, 1, $2::timestamptz, $2::timestamptz + ($25 || ' seconds')::interval,
                  $2::timestamptz, $26::timestamptz)
          ON CONFLICT (crawl_host_gate_id, request_kind, crawl_frontier_entry_id, attempt_number)
            DO NOTHING
          RETURNING id, checkpoint_version, reserved_bytes, attempt_number
        SQL
      end

      def submission_started(id, expected_version, now)
        query(<<~SQL, [id, expected_version, iso(now)]).cmd_tuples
          UPDATE fetch_attempts
          SET submission_started_at = $3::timestamptz, last_heartbeat_at = $3::timestamptz,
              checkpoint_version = checkpoint_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND checkpoint_version = $2 AND submission_started_at IS NULL
        SQL
      end

      # Write the write-once result. Guarded on `outcome IS NULL` as well as the expected version, so
      # a replayed terminalisation cannot overwrite a decision :452's coverage classification may
      # already have read. Releases the lease in the same statement — a terminal attempt is not
      # claimed.
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
              completed_at = $3::timestamptz,
              claim_owner = NULL, claimed_at = NULL, lease_expires_at = NULL,
              checkpoint_version = checkpoint_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND checkpoint_version = $2 AND outcome IS NULL
        SQL
      end

      # Reclaim every attempt whose lease has expired without terminalising, and RETURN what each was
      # holding. SEARCH_CRAWL_RETRIEVAL :82's "or timed out" is this statement: without it a lost
      # worker retires both its frontier entry and its byte reservation for the rest of the run.
      #
      # `timed_out` is a terminal outcome, so the row becomes write-once here rather than being left
      # for a second sweeper to find. The caller releases the returned `reserved_bytes` back to the
      # run's budget.
      def sweep_expired(organization_id, crawl_id, now)
        query(<<~SQL, [organization_id, crawl_id, iso(now)]).to_a
          UPDATE fetch_attempts
          SET outcome = 'timed_out', reason_code = 'attempt_lease_expired',
              terminal_at = $3::timestamptz, completed_at = $3::timestamptz, retryable = true,
              accounted_response_bytes = 0, limit_probe_bytes = 0,
              claim_owner = NULL, claimed_at = NULL, lease_expires_at = NULL,
              checkpoint_version = checkpoint_version + 1, updated_at = $3::timestamptz
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
            AND outcome IS NULL AND lease_expires_at IS NOT NULL
            AND lease_expires_at < $3::timestamptz
          RETURNING id, reserved_bytes, crawl_frontier_entry_id, attempt_number
        SQL
      end

      def attempt(organization_id, id)
        query("SELECT * FROM fetch_attempts WHERE organization_id = $1::uuid AND id = $2::uuid",
              [organization_id, id]).to_a.first
      end

      # Every attempt of a run in :456's canonical order — "all run-wide byte, page, and queue
      # admission accounting is also applied in dequeue sequence". `dequeue_key` is materialized on
      # the row precisely so this order is the ratified one rather than completion order.
      def attempts_for(organization_id, crawl_id)
        query(<<~SQL, [organization_id, crawl_id]).to_a
          SELECT * FROM fetch_attempts
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
          ORDER BY dequeue_key NULLS FIRST, attempt_number, id
        SQL
      end

      # How many attempts this frontier entry has already had, so :444's bound is read from committed
      # state rather than carried in a worker's memory across a process loss.
      #
      # A TIMED-OUT ATTEMPT COUNTS. :444 gives "one initial attempt plus at most two retries", and a
      # worker lost after claiming may well have issued its request — the run cannot know. Refunding
      # the attempt would let a host that kills workers be retried without bound, so the fail-closed
      # reading is that the identity was consumed. What reclamation returns is the BYTE RESERVATION
      # and a terminal record; the entry then exhausts its attempts honestly as
      # `content_fetch_failed` inside the coverage denominator, rather than hanging as `contended`
      # outside it. Recovering such an entry is a new run's job (:444 — "A Crawl retry after terminal
      # failure is a new attempt linked to the prior run and uses a new Crawl ID").
      def attempt_count(organization_id, crawl_id, frontier_entry_id, kind)
        params = [organization_id, crawl_id, frontier_entry_id, kind]
        query(<<~SQL, params).to_a.first["count"].to_i
          SELECT COUNT(*) AS count FROM fetch_attempts
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
            AND crawl_frontier_entry_id IS NOT DISTINCT FROM $3::uuid AND request_kind = $4
        SQL
      end

      private

      def query(sql, params = []) = @pg.exec_params(sql, params)
      def bytea(binary) = { value: binary, format: 1, type: 17 }
      def iso(time) = time.utc.iso8601(6)
    end
  end
end
