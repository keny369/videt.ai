# frozen_string_literal: true

require "json"

module IdentityAccess
  module Infrastructure
    # Persistence for WF-003 IssueVerificationChallenge, written in the caller's unit
    # of work inside the actor's proved Organization context.
    #
    # The Verification Request aggregate belongs to the Intake/Verification context in
    # 011 DOMAIN_MODEL.md, distinct from Identity and Access. Its persistence adapter
    # co-locates here exactly as `SourceStore`, `ProjectStore` and
    # `OrganizationGenesisStore` do — the workflow coordinates the authorization
    # context and this store, and a later context extraction is a mechanical move that
    # carries this adapter with it. It reuses the workflow-agnostic platform ledger
    # writers from `ActorLedgerWriters` and overrides only the two writers that stamp
    # `workflow_id`, so its events and audits are attributed to `WF-003`.
    #
    # The issuance facts are written ONCE, at insert; the verification_requests
    # lifecycle trigger refuses to change them — or the tenant/Project/Source
    # identity, or the request_status — afterwards, so this store deliberately offers
    # no Request update in this limb.
    class VerificationRequestStore
      include ActorLedgerWriters

      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Serialize IssueVerificationChallenge commands contending for the same Source's
      # single pending slot, so the loser observes the winner's committed pending
      # Request and replays or is refused `verification_in_progress` rather than racing
      # the partial unique index into a raw violation.
      def lock_source(source_id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["verification-request:#{source_id}"])
      end

      # The Source precondition read, in the proved Organization context: a not-found
      # Source (another Organization's, or nonexistent) is invisible under RLS and is
      # treated as a tenant boundary failure by the handler.
      def source(source_id)
        exec(<<~SQL, [source_id]).to_a.first
          SELECT id, organization_id, project_id, state, state_version, canonical_host
          FROM sources WHERE id = $1::uuid
        SQL
      end

      # Is there already a pending Verification Request for this Source? The ratified
      # concurrency control is at most one pending Request per Source.
      def pending_exists?(source_id)
        exec(<<~SQL, [source_id]).values.any?
          SELECT 1 FROM verification_requests
          WHERE source_id = $1::uuid AND request_status = 'pending' LIMIT 1
        SQL
      end

      # Insert exactly one pending Verification Request with its immutable issuance
      # provenance. `issued_at`/`initial_challenge_delivered_at` and the row
      # timestamps are the same server commit instant (the injected clock);
      # `expires_at` is exactly 24 hours later.
      def insert_verification_request(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:schema_version], row[:organization_id],
          row[:project_id], row[:source_id], row[:request_initiator_account_id], row[:method],
          row[:canonical_host], bytea(row[:challenge_token_sha256]), row[:challenge_ciphertext_reference],
          row[:challenge_key_id], iso(row[:issued_at]), iso(row[:expires_at]),
          bytea(row[:idempotency_key_digest])
        ]
        exec(<<~SQL, params)
          INSERT INTO verification_requests
            (id, state_version, lock_version, created_at, updated_at, correlation_id, schema_version,
             organization_id, project_id, source_id, request_initiator_account_id, method, canonical_host,
             challenge_token_sha256, challenge_ciphertext_reference, challenge_key_id,
             initial_challenge_delivered_at_utc, issued_at_utc, expires_at_utc, idempotency_key_digest,
             request_status, attempt_count, on_demand_observation_count)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4,
                  $5::uuid,$6::uuid,$7::uuid,$8::uuid,$9,$10,
                  $11,$12::uuid,$13,
                  $2::timestamptz,$14::timestamptz,$15::timestamptz,$16,
                  'pending',0,0)
        SQL
      end

      # The Request as it stands now, for an idempotent creation replay: the fields
      # needed to decide whether the token may be re-decrypted (still pending) and to
      # rebuild the F-02 AAD binding.
      def load_verification_request(id)
        exec(<<~SQL, [id]).to_a.first
          SELECT id, organization_id, request_status, challenge_ciphertext_reference,
                 issued_at_utc, expires_at_utc
          FROM verification_requests WHERE id = $1::uuid
        SQL
      end

      # ---- S-05-004 ReserveVerificationAttempt (the on-demand reservation) ---------

      # Serialize on-demand ReserveVerificationAttempt commands contending for the same
      # Request, so the accepted command's atomic count/marker update is never racy and
      # concurrent commands cannot reserve the same slot (contracts/S-05.json MTX-028
      # concurrency). Same advisory-lock key the expiry service uses on the Request.
      def lock_verification_request(id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["verification-request:#{id}"])
      end

      # The Request as the reservation needs it, in the actor's proved Organization
      # context: a not-found Request (another Organization's, or nonexistent) is
      # invisible under RLS and is treated as a tenant boundary failure by the handler.
      # Carries the guard inputs — status, the counts, the in-progress marker and the
      # last on-demand completion — plus the lineage the attempt row inherits.
      def read_verification_request_for_reserve(id)
        exec(<<~SQL, [id]).to_a.first
          SELECT id, organization_id, project_id, source_id, request_status, state_version,
                 attempt_count, on_demand_observation_count, on_demand_in_progress_attempt_id,
                 last_on_demand_completed_at_utc, expires_at_utc
          FROM verification_requests WHERE id = $1::uuid
        SQL
      end

      # Insert one `reserved` Verification Attempt with its immutable reservation
      # lineage and no outcome (the `reserved_has_no_outcome` CHECK). `attempt_number`
      # is assigned by the handler as attempt_count + 1 under the per-Request lock.
      def insert_verification_attempt(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:schema_version], row[:organization_id],
          row[:project_id], row[:verification_request_id], row[:source_id], row[:attempt_number], row[:origin]
        ]
        exec(<<~SQL, params)
          INSERT INTO verification_attempts
            (id, state_version, lock_version, created_at, updated_at, correlation_id, schema_version,
             organization_id, project_id, verification_request_id, source_id, attempt_number, origin,
             automated_slot_offset_minutes, reserved_at_utc, state)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4,
                  $5::uuid,$6::uuid,$7::uuid,$8::uuid,$9,$10,
                  NULL,$2::timestamptz,'reserved')
        SQL
      end

      # Atomically reserve the slot on the Request: increment the total and on-demand
      # attempt counts and store the in-progress marker, guarded on the expected state
      # version and a still-pending Request (SCORE_EVIDENCE_MODEL.md § Attempts). The
      # request_status is unchanged, so the verification_requests lifecycle guard —
      # which freezes only the tenant identity, the issuance facts and the status —
      # permits it. Returns the affected row count; zero is a lost race or a Request
      # that is no longer pending at this version.
      def reserve_on_request(id, expected_version, marker_id, now)
        exec(<<~SQL, [id, expected_version, marker_id, iso(now)]).cmd_tuples
          UPDATE verification_requests
          SET attempt_count = attempt_count + 1,
              on_demand_observation_count = on_demand_observation_count + 1,
              on_demand_in_progress_attempt_id = $3::uuid,
              state_version = state_version + 1,
              updated_at = $4::timestamptz
          WHERE id = $1::uuid AND request_status = 'pending' AND state_version = $2
        SQL
      end

      # WF-003 audit writer — the ActorLedgerWriters row shape with `workflow_id`
      # stamped 'WF-003' instead of the shared writer's WF-013 default.
      def insert_audit(row)
        params = [
          row[:id], row[:occurred_at], row[:partition_month], row[:organization_id], row[:actor_id],
          row[:correlation_id], row[:causation_id], row[:command_id], row[:entity_type], row[:entity_id],
          row[:to_state], row[:outcome], row[:reason_code], row[:payload], bytea(row[:content_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO audit_record_registry
            (id, schema_version, created_at, occurred_at, partition_month, organization_id, workflow_id,
             actor_id, correlation_id, causation_id, command_id, entity_type, entity_id,
             to_state, outcome, reason_code, classification, payload, content_sha256, retention_class)
          VALUES ($1,'1.0',$2::timestamptz,$2::timestamptz,$3::date,$4::uuid,'WF-003',
                  $5::uuid,$6::uuid,$7::uuid,$8::uuid,$9,$10::uuid,$11,$12,$13,'restricted',$14::jsonb,$15,'security_audit')
        SQL
      end

      # WF-003 event writer — the ActorLedgerWriters row shape with `workflow_id`
      # stamped 'WF-003'. The database re-verifies event_sha256 against event_bytes.
      def insert_event(row)
        params = [
          row[:id], row[:created_at], row[:event_type], row[:event_profile], row[:occurred_at],
          row[:organization_id], row[:aggregate_type], row[:aggregate_id], row[:aggregate_version],
          row[:partition_month], row[:correlation_id], row[:causation_id], row[:command_id],
          row[:audit_record_id], bytea(row[:event_bytes]), row[:event_bytes].bytesize, bytea(row[:event_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO event_registry
            (id, schema_version, created_at, event_type, event_schema_version, workflow_id, event_profile,
             occurred_at, organization_id, aggregate_type, aggregate_id, aggregate_version, partition_month,
             correlation_id, causation_id, command_id, audit_record_id, event_bytes, event_byte_count, event_sha256)
          VALUES ($1,'1.0',$2::timestamptz,$3,'1.0','WF-003',$4,
                  $5::timestamptz,$6::uuid,$7,$8::uuid,$9,$10::date,
                  $11::uuid,$12::uuid,$13::uuid,$14::uuid,$15,$16,$17)
        SQL
      end

      private

      def exec(sql, params) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      def iso(time) = time&.getutc&.iso8601(6)
    end
  end
end
