# frozen_string_literal: true

module IdentityAccess
  module Infrastructure
    # Persistence for the IngestionJob and its attempt history (schemas/POSTGRESQL_SCHEMA.md :303,
    # :304; WORKFLOW_SPECIFICATIONS.md :462, :464, :466). MTX-008 names `IngestionJobRepository`.
    #
    # EVERY STATE CHANGE IS A COMPARE-AND-SET ON `state_version` AND ON THE STATE IT LEAVES, and the
    # database refuses the edge independently through `f1_ingestion_jobs_lifecycle_guard`. The two are
    # deliberately redundant: the guard says which edges EXIST, and the compare-and-set says which
    # DELIVERY may take one, so a second delivery of an `ingestion_attempt_due` matches zero rows and
    # changes nothing rather than re-deciding a job another worker has already settled.
    #
    # THE JOB IDENTITY ABSORBS THE FETCH REPLAY. :462 — "exactly one IngestionJob for `(crawl_id,
    # source_id, canonical_url, fetched_body_sha256, ingestion_schema_version)` ... EXACT FETCH REPLAY
    # RETURNS THE SAME JOB." `create` is therefore `ON CONFLICT DO NOTHING` plus a read: a redelivered
    # fetch pass finds the job it made last time, and does not make a second Document either.
    #
    # NO DELETE PATH. :303's replay reuses this row, so a job is never replaced; the runtime role holds
    # SELECT/INSERT/UPDATE on all three tables and nothing more.
    class IngestionJobStore
      SCHEMA_VERSION = "1.0"
      # The ratified `ingestion-interim-v1` literal (WORKFLOW_SPECIFICATIONS.md :462), which the
      # column's own CHECK pins. It lives HERE, at the write site, because `IdentityAccess` may not
      # depend on `Workflows`; `Wf005::IngestionContract` binds to this constant rather than spelling
      # the string a second time, so the transcription and the persisted value cannot drift.
      INGESTION_SCHEMA_VERSION = "ingestion-interim-v1"
      QUEUED = "queued"
      RUNNING = "running"
      SUCCEEDED = "succeeded"
      FAILED = "failed"
      DEAD_LETTER = "dead_letter"

      # The attempt's work lease, in the shape `fetch_attempts` establishes. :466 gives an ingestion
      # attempt a 30-second timeout, so a lease an order of magnitude longer cannot reclaim a live
      # attempt while still bounding a lost one.
      ATTEMPT_LEASE_SECONDS = 300

      def initialize(pg_connection)
        @pg = pg_connection
      end

      def enter_org_context(org:, correlation_id:)
        query("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, correlation_id]).values.dig(0, 0)
      end

      # ---- creation (the fetch commit) -------------------------------------------

      # Create the queued job for one retained successful fetch, or return nothing when :462's
      # identity already exists. The caller reads back with `find_by_identity` either way, so a
      # replayed pass and a first pass follow the same path.
      def create(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:causation_id], row[:command_id],
          row[:organization_id], row[:project_id], row[:source_id], row[:crawl_id], row[:document_id],
          row[:canonical_url], bytea(row[:fetched_body_sha256]), row[:final_http_status],
          row[:media_type], row[:staged_body_reference], iso(row[:staging_expires_at]),
          row[:received_byte_count], row[:response_capture_policy_version], row[:data_classification],
          row[:idempotency_key], iso(row[:next_due_at])
        ]
        query(<<~SQL, params).to_a.first
          INSERT INTO ingestion_jobs
            (id, state_version, lock_version, schema_version, created_at, updated_at,
             correlation_id, causation_id, command_id, organization_id, project_id, source_id,
             crawl_id, document_id, canonical_url, fetched_body_sha256, ingestion_schema_version,
             replay_generation, attempt_count, next_due_at, state, final_http_status, media_type,
             staged_body_reference, staging_expires_at, received_byte_count,
             response_capture_policy_version, data_classification, idempotency_key, queued_at)
          VALUES ($1::uuid, 0, 0, '#{SCHEMA_VERSION}', $2::timestamptz, $2::timestamptz,
                  $3::uuid, $4::uuid, $5::uuid, $6::uuid, $7::uuid, $8::uuid,
                  $9::uuid, $10::uuid, $11, $12, '#{INGESTION_SCHEMA_VERSION}',
                  0, 0, $21::timestamptz, '#{QUEUED}', $13::integer, $14,
                  $15::uuid, $16::timestamptz, $17::bigint,
                  $18, $19, $20, $2::timestamptz)
          ON CONFLICT (crawl_id, source_id, canonical_url, fetched_body_sha256, ingestion_schema_version)
            DO NOTHING
          RETURNING id
        SQL
      end

      # :462's identity. Used by the fetch commit to recognise its own replay.
      def find_by_identity(organization_id:, crawl_id:, source_id:, canonical_url:, fetched_body_sha256:)
        query(<<~SQL, [organization_id, crawl_id, source_id, canonical_url, bytea(fetched_body_sha256)]).to_a.first
          SELECT #{COLUMNS}
          FROM ingestion_jobs
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid AND source_id = $3::uuid
            AND canonical_url = $4 AND fetched_body_sha256 = $5
            AND ingestion_schema_version = '#{INGESTION_SCHEMA_VERSION}'
        SQL
      end

      # ---- the job's own lifecycle -----------------------------------------------

      def lock_job(organization_id, job_id)
        query("SELECT #{COLUMNS} FROM ingestion_jobs WHERE organization_id = $1::uuid AND id = $2::uuid FOR UPDATE",
              [organization_id, job_id]).to_a.first
      end

      def get(organization_id, job_id)
        query("SELECT #{COLUMNS} FROM ingestion_jobs WHERE organization_id = $1::uuid AND id = $2::uuid",
              [organization_id, job_id]).to_a.first
      end

      # `queued -> running`, recording the attempt count this job is now on. ":462 — started time."
      def start(organization_id, job_id, expected_state_version, attempt_number, now)
        query(<<~SQL, [organization_id, job_id, expected_state_version, attempt_number, iso(now)]).cmd_tuples
          UPDATE ingestion_jobs
             SET state = '#{RUNNING}', started_at = $5::timestamptz, updated_at = $5::timestamptz,
                 attempt_count = $4::bigint, next_due_at = NULL, state_version = state_version + 1
           WHERE organization_id = $1::uuid AND id = $2::uuid
             AND state_version = $3::bigint AND state = '#{QUEUED}'
        SQL
      end

      # ":464 — Success atomically ... changes the job to succeeded", carrying the Evidence the same
      # statement records. `ingestion_jobs_succeeded_carries_evidence` refuses the row without it, so
      # a succeeded job with no handoff is unrepresentable rather than merely unwritten.
      def succeed(organization_id, job_id, expected_state_version, evidence_id, now)
        query(<<~SQL, [organization_id, job_id, expected_state_version, evidence_id, iso(now)]).cmd_tuples
          UPDATE ingestion_jobs
             SET state = '#{SUCCEEDED}', evidence_id = $4::uuid, completed_at = $5::timestamptz,
                 updated_at = $5::timestamptz, last_reason_code = NULL, next_due_at = NULL,
                 state_version = state_version + 1
           WHERE organization_id = $1::uuid AND id = $2::uuid
             AND state_version = $3::bigint AND state = '#{RUNNING}'
        SQL
      end

      # `running -> failed`, with :464's exact reason. Whether a retry is owed is the caller's
      # decision under `IngestionContract`; this records only what happened.
      def fail(organization_id, job_id, expected_state_version, reason_code, now)
        query(<<~SQL, [organization_id, job_id, expected_state_version, reason_code, iso(now)]).cmd_tuples
          UPDATE ingestion_jobs
             SET state = '#{FAILED}', last_reason_code = $4, completed_at = $5::timestamptz,
                 updated_at = $5::timestamptz, state_version = state_version + 1
           WHERE organization_id = $1::uuid AND id = $2::uuid
             AND state_version = $3::bigint AND state = '#{RUNNING}'
        SQL
      end

      # ":466 — Only `ingest_timeout` and `ingest_dependency_unavailable` retry": `failed -> queued`
      # at the instant the schedule names. The attempt count is NOT reset — :466's bound is "one
      # initial attempt plus two retries" over the job, not over each requeue.
      def requeue(organization_id, job_id, expected_state_version, next_due_at, now)
        query(<<~SQL, [organization_id, job_id, expected_state_version, iso(next_due_at), iso(now)]).cmd_tuples
          UPDATE ingestion_jobs
             SET state = '#{QUEUED}', next_due_at = $4::timestamptz, completed_at = NULL,
                 updated_at = $5::timestamptz, state_version = state_version + 1
           WHERE organization_id = $1::uuid AND id = $2::uuid
             AND state_version = $3::bigint AND state = '#{FAILED}'
        SQL
      end

      # ":466 — Other failures and exhausted retry move `running -> failed -> dead_letter` AT ONE
      # CHECKPOINT." Both edges are taken in one transaction by the caller; this is the second.
      def dead_letter(organization_id, job_id, expected_state_version, now)
        query(<<~SQL, [organization_id, job_id, expected_state_version, iso(now)]).cmd_tuples
          UPDATE ingestion_jobs
             SET state = '#{DEAD_LETTER}', next_due_at = NULL, updated_at = $4::timestamptz,
                 state_version = state_version + 1
           WHERE organization_id = $1::uuid AND id = $2::uuid
             AND state_version = $3::bigint AND state = '#{FAILED}'
        SQL
      end

      # ":464 — deletes the separate staging reference within 60 seconds"; ":466 — retains ... for at
      # most 24 hours from fetch completion, then destroys them."
      #
      # THE ROW IS THE RECORD OF THE DESTRUCTION, NOT THE DESTRUCTION ITSELF. The bytes live behind an
      # F-02 reference and are destroyed by `Platform::Encryption.erase`; this nulls the capability so
      # nothing can reach them again and stamps when. `ingestion_jobs_staging_shape` keeps "destroyed"
      # and "never staged" distinguishable, which is what makes `staged_body_missing` a real answer.
      # The state version is deliberately NOT advanced: destroying the staging bytes is not a lifecycle
      # transition, and bumping it here would invalidate a concurrent worker's compare-and-set for a
      # change that says nothing about the job's state.
      def destroy_staging(organization_id, job_id, now)
        query(<<~SQL, [organization_id, job_id, iso(now)]).cmd_tuples
          UPDATE ingestion_jobs
             SET staged_body_reference = NULL, staged_body_destroyed_at = $3::timestamptz,
                 updated_at = $3::timestamptz
           WHERE organization_id = $1::uuid AND id = $2::uuid AND staged_body_reference IS NOT NULL
        SQL
      end

      # ---- the attempt history (:304) --------------------------------------------

      # The attempt number this job is owed next, derived from COMMITTED state so neither a process
      # loss nor a redelivery can reset it (the same rule `FetchContent` follows for :444).
      def attempt_count(organization_id, job_id)
        query(<<~SQL, [organization_id, job_id]).to_a.first["count"].to_i
          SELECT COUNT(*) AS count FROM ingestion_attempts
          WHERE organization_id = $1::uuid AND ingestion_job_id = $2::uuid
        SQL
      end

      # Claim one attempt. `UNIQUE (ingestion_job_id, attempt_number)` under `ON CONFLICT DO NOTHING`
      # is what makes two deliveries that computed the same number produce ONE attempt: the loser gets
      # nil and performs no work rather than executing a second ingestion of the same body.
      def claim_attempt(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:causation_id], row[:command_id],
          row[:organization_id], row[:project_id], row[:ingestion_job_id], row[:attempt_number],
          row[:replay_generation], bytea(row[:input_sha256]), row[:claim_owner],
          ATTEMPT_LEASE_SECONDS, iso(row[:deadline_at])
        ]
        query(<<~SQL, params).to_a.first
          INSERT INTO ingestion_attempts
            (id, checkpoint_version, lock_version, schema_version, created_at, updated_at,
             correlation_id, causation_id, command_id, organization_id, project_id,
             ingestion_job_id, attempt_number, replay_generation, input_sha256,
             claim_owner, claim_generation, claimed_at, lease_expires_at, last_heartbeat_at,
             scheduled_at, started_at, deadline_at)
          VALUES ($1::uuid, 0, 0, '#{SCHEMA_VERSION}', $2::timestamptz, $2::timestamptz,
                  $3::uuid, $4::uuid, $5::uuid, $6::uuid, $7::uuid,
                  $8::uuid, $9::integer, $10::bigint, $11,
                  $12::uuid, 1, $2::timestamptz,
                  $2::timestamptz + make_interval(secs => $13::integer), $2::timestamptz,
                  $2::timestamptz, $2::timestamptz, $14::timestamptz)
          ON CONFLICT (ingestion_job_id, attempt_number) DO NOTHING
          RETURNING id, attempt_number, checkpoint_version, deadline_at
        SQL
      end

      # Write-once terminalization of one attempt (T-CHK; `f1_ingestion_attempts_guard` refuses a
      # second). A succeeded attempt carries its output object and digest; a failed one carries its
      # reason. `ingestion_attempts_terminal_shape` refuses every other combination.
      def terminalize_attempt(id, expected_version, now, outcome:, reason_code: nil,
                              output_object_id: nil, output_sha256: nil)
        params = [id, expected_version, iso(now), outcome, reason_code, output_object_id,
                  output_sha256 && bytea(output_sha256)]
        query(<<~SQL, params).cmd_tuples
          UPDATE ingestion_attempts
             SET outcome = $4, reason_code = $5, output_object_id = $6::uuid, output_sha256 = $7,
                 completed_at = $3::timestamptz, updated_at = $3::timestamptz,
                 claim_owner = NULL, lease_expires_at = NULL,
                 checkpoint_version = checkpoint_version + 1
           WHERE id = $1::uuid AND checkpoint_version = $2::bigint AND outcome IS NULL
        SQL
      end

      def latest_attempt(organization_id, job_id)
        query(<<~SQL, [organization_id, job_id]).to_a.first
          SELECT id, attempt_number, replay_generation, checkpoint_version, outcome, reason_code,
                 scheduled_at, started_at, completed_at, deadline_at, lease_expires_at
          FROM ingestion_attempts
          WHERE organization_id = $1::uuid AND ingestion_job_id = $2::uuid
          ORDER BY attempt_number DESC LIMIT 1
        SQL
      end

      COLUMNS = <<~COLS.freeze
        id, organization_id, project_id, source_id, crawl_id, document_id, canonical_url,
        fetched_body_sha256, ingestion_schema_version, replay_generation, attempt_count,
        next_due_at, deadline_at, state, last_reason_code, state_version, final_http_status,
        media_type, staged_body_reference, staged_body_destroyed_at, staging_expires_at,
        received_byte_count, response_capture_policy_version, data_classification, evidence_id,
        idempotency_key, queued_at, started_at, completed_at, correlation_id, causation_id
      COLS

      private

      def query(sql, params = []) = @pg.exec_params(sql, params)
      def iso(time) = time&.getutc&.iso8601(6)
      def bytea(value) = value && { value:, format: 1 }
    end
  end
end
