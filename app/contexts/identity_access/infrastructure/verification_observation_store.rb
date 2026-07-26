# frozen_string_literal: true

require "json"

module IdentityAccess
  module Infrastructure
    # Persistence for the WF-003 service-executed observation completion (S-05-005
    # CompleteVerificationAttempt), written in the worker's unit of work under the
    # Request's Organization context.
    #
    # Service-attributed throughout: `service_identity_id` is set and `actor_id` stays
    # null. Running a reserved observation and recording its outcome is the verification
    # lifecycle service's act, not a human's (contracts/S-05.json MTX-051: the transition
    # is a consequence of a matched predicate, not of an actor's permission). This is the
    # VerificationExpiryStore shape specialized to the attempt-completion writes. The
    # service-attributed five-writer set is duplicated here rather than shared: this is
    # now the THIRD structural copy (RoleExpiryStore, VerificationExpiryStore, and this),
    # so extracting a `ServiceLedgerWriters` module — mirroring `ActorLedgerWriters` — is
    # a warranted follow-up; it is deferred here because it would edit the already-merged
    # expiry stores and is not required to complete this tranche.
    class VerificationObservationStore
      def initialize(pg_connection)
        @pg = pg_connection
      end

      def enter_org_context(org:, correlation_id:)
        exec("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, correlation_id]).values.dig(0, 0)
      end

      def lock_verification_request(id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["verification-request:#{id}"])
      end

      # The Request as the completion needs it — status and lifecycle counters, plus the
      # inputs the observation runs from (method, canonical host, the F-02 challenge
      # reference). Invisible under RLS for another Organization (handled as not-found).
      def read_request(id)
        exec(<<~SQL, [id]).to_a.first
          SELECT id, organization_id, project_id, source_id, request_status, state_version,
                 method, canonical_host, challenge_ciphertext_reference,
                 on_demand_in_progress_attempt_id, expires_at_utc
          FROM verification_requests WHERE id = $1::uuid
        SQL
      end

      # The reserved attempt (or an already-completed one, for an idempotent rebuild):
      # its lineage plus the recorded outcome columns.
      def read_attempt(id)
        exec(<<~SQL, [id]).to_a.first
          SELECT id, organization_id, project_id, verification_request_id, source_id, state, state_version,
                 attempt_number, origin, automated_slot_offset_minutes,
                 started_at_utc, completed_at_utc, network_outcome, http_status, dns_response_code,
                 received_byte_count, encode(observed_value_sha256,'hex') AS observed_value_hex,
                 match_decision, reason_code
          FROM verification_attempts WHERE id = $1::uuid
        SQL
      end

      # Transition exactly one reserved attempt to completed, recording the observation
      # outcome, guarded on the expected attempt state version. Returns the row count.
      def complete_attempt(id, expected_version, row)
        params = [
          id, expected_version, row[:started_at], row[:completed_at], row[:network_outcome],
          row[:http_status], row[:dns_response_code], row[:received_byte_count],
          bytea(row[:observed_value_sha256]), row[:match_decision], row[:reason_code], iso(row[:now])
        ]
        exec(<<~SQL, params).cmd_tuples
          UPDATE verification_attempts
          SET state = 'completed', started_at_utc = $3::timestamptz, completed_at_utc = $4::timestamptz,
              network_outcome = $5, http_status = $6, dns_response_code = $7, received_byte_count = $8,
              observed_value_sha256 = $9, match_decision = $10, reason_code = $11,
              state_version = state_version + 1, updated_at = $12::timestamptz
          WHERE id = $1::uuid AND state = 'reserved' AND state_version = $2
        SQL
      end

      # Record the observation on the Request: update the last-observed instant, and for
      # an on-demand attempt clear the in-progress marker and set the last on-demand
      # completion (the rate-limit clock). The request_status is unchanged (a matched
      # success commit is S-05-006), so the verification_requests lifecycle guard permits
      # it. Guarded on the expected Request state version.
      def record_observation_on_request(id, expected_version, on_demand:, now:)
        marker = on_demand ? "NULL" : "on_demand_in_progress_attempt_id"
        last_on_demand = on_demand ? "$3::timestamptz" : "last_on_demand_completed_at_utc"
        exec(<<~SQL, [id, expected_version, iso(now)]).cmd_tuples
          UPDATE verification_requests
          SET last_observed_at_utc = $3::timestamptz,
              on_demand_in_progress_attempt_id = #{marker},
              last_on_demand_completed_at_utc = #{last_on_demand},
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND request_status = 'pending' AND state_version = $2
        SQL
      end

      # ---- S-05-006 matched success commit -------------------------------------

      # The Source as the success commit needs it, for the proposed -> verified guard.
      def read_source(source_id)
        exec(<<~SQL, [source_id]).to_a.first
          SELECT id, state, state_version, canonical_host FROM sources WHERE id = $1::uuid
        SQL
      end

      # The matched terminal update of the Request: pending -> verified/matched with the
      # challenge material erased (redelivery disablement), plus the same last-observed /
      # on-demand marker update the recording path makes. Guarded on pending + the
      # expected state version. Returns the row count.
      def verify_request_on_match(id, expected_version, on_demand:, now:)
        marker = on_demand ? "NULL" : "on_demand_in_progress_attempt_id"
        last_on_demand = on_demand ? "$3::timestamptz" : "last_on_demand_completed_at_utc"
        exec(<<~SQL, [id, expected_version, iso(now)]).cmd_tuples
          UPDATE verification_requests
          SET request_status = 'verified', decision_reason_code = 'matched',
              challenge_ciphertext_reference = NULL, challenge_key_id = NULL,
              last_observed_at_utc = $3::timestamptz,
              on_demand_in_progress_attempt_id = #{marker},
              last_on_demand_completed_at_utc = #{last_on_demand},
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND request_status = 'pending' AND state_version = $2
        SQL
      end

      # Source proposed -> verified with its active scope policy pinned, guarded on
      # proposed + the expected Source state version (so concurrent matched completions
      # transition once and a stale version rejects with no side effect). Returns the
      # row count.
      def verify_source(source_id, expected_version, policy_id, now:)
        exec(<<~SQL, [source_id, expected_version, policy_id, iso(now)]).cmd_tuples
          UPDATE sources
          SET state = 'verified', current_scope_policy_id = $3::uuid, verified_at = $4::timestamptz,
              state_version = state_version + 1, updated_at = $4::timestamptz
          WHERE id = $1::uuid AND state = 'proposed' AND state_version = $2
        SQL
      end

      # Materialize one immutable Source Scope Policy version (the interim policy).
      def insert_source_scope_policy(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:project_id],
          row[:source_id], row[:policy_version], row[:scope], row[:canonical_host],
          pg_text_array(row[:allowed_schemes]), pg_int_array(row[:allowed_ports]),
          pg_text_array(row[:include_prefixes]), pg_text_array(row[:exclude_prefixes]),
          row[:query_handling], bytea(row[:content_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO source_scope_policies
            (id, created_at, correlation_id, schema_version, organization_id, project_id, source_id,
             policy_version, scope, canonical_host, allowed_schemes, allowed_ports,
             include_prefixes, exclude_prefixes, query_handling, content_sha256)
          VALUES ($1,$2::timestamptz,$3::uuid,'source-scope-policy-v1',$4::uuid,$5::uuid,$6::uuid,
                  $7,$8,$9,$10::text[],$11::integer[],$12::text[],$13::text[],$14,$15)
        SQL
      end

      def find_idempotency(org:, command_type:, target_type:, target_id:, key_digest:)
        sql = <<~SQL
          SELECT encode(request_sha256,'hex') AS request_hex, command_result_id
          FROM idempotency_records
          WHERE scope_kind = 'organization' AND organization_id = $1::uuid
            AND command_type = $2 AND target_type = $3 AND target_id = $4::uuid AND key_digest = $5
          LIMIT 1
        SQL
        exec(sql, [org, command_type, target_type, target_id, bytea(key_digest)]).to_a.first
      end

      def load_command_result(id)
        sql = <<~SQL
          SELECT id, outcome, authorized_payload, audit_record_id, correlation_id,
                 error_class, error_code, reason_code, severity, retryable, recovery_action, support_reference
          FROM command_results WHERE id = $1::uuid
        SQL
        exec(sql, [id]).to_a.first
      end

      # ---- service-attributed ledger writers -----------------------------------

      def insert_command_execution(row)
        params = [
          row[:id], row[:created_at], row[:correlation_id], row[:causation_id], row[:command_id],
          bytea(row[:idempotency_key_digest]), row[:command_type], row[:command_schema_version],
          row[:service_identity_id], row[:organization_id], row[:target_type], row[:target_id],
          row[:action], row[:requested_at], row[:authorization_check_at], row[:policy_versions],
          row[:canonical_payload], bytea(row[:request_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO command_executions
            (id, schema_version, created_at, correlation_id, causation_id, command_id,
             idempotency_key_digest, content_sha256, command_type, command_schema_version,
             service_identity_id, organization_id, target_type, target_id, action,
             requested_at, authorization_check_at, policy_versions, canonical_payload, request_sha256)
          VALUES ($1,'1.0',$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6,NULL,$7,$8,$9::uuid,$10::uuid,$11,$12::uuid,$13,
                  $14::timestamptz,$15::timestamptz,$16::jsonb,$17::jsonb,$18)
        SQL
      end

      def insert_audit(row)
        params = [
          row[:id], row[:occurred_at], row[:partition_month], row[:organization_id], row[:service_identity_id],
          row[:correlation_id], row[:causation_id], row[:command_id], row[:entity_type], row[:entity_id],
          row[:to_state], row[:outcome], row[:reason_code], row[:payload], bytea(row[:content_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO audit_record_registry
            (id, schema_version, created_at, occurred_at, partition_month, organization_id, workflow_id,
             service_identity_id, correlation_id, causation_id, command_id, entity_type, entity_id,
             to_state, outcome, reason_code, classification, payload, content_sha256, retention_class)
          VALUES ($1,'1.0',$2::timestamptz,$2::timestamptz,$3::date,$4::uuid,'WF-003',
                  $5::uuid,$6::uuid,$7::uuid,$8::uuid,$9,$10::uuid,$11,$12,$13,'restricted',$14::jsonb,$15,'security_audit')
        SQL
      end

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

      def insert_command_result(row)
        failure = row[:failure]
        params = [
          row[:id], row[:created_at], row[:correlation_id], row[:causation_id], row[:command_id],
          row[:command_execution_id], row[:outcome], row[:organization_id], row[:service_identity_id],
          row[:completed_at], row[:authorization_check_at], row[:target_refs], row[:governing_policy_versions],
          failure&.error_class, failure&.error_code, failure&.reason_code, failure&.severity,
          failure&.retryable, failure&.recovery_action, failure&.support_reference,
          row[:authorized_payload], row[:audit_record_id]
        ]
        exec(<<~SQL, params)
          INSERT INTO command_results
            (id, schema_version, created_at, correlation_id, causation_id, command_id, command_execution_id,
             result_schema_version, outcome, organization_id, service_identity_id, completed_at,
             authorization_check_at, target_refs, governing_policy_versions,
             error_class, error_code, reason_code, severity, retryable, recovery_action, support_reference,
             authorized_payload, audit_record_id)
          VALUES ($1,'1.0',$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,'1.0',$7,$8::uuid,$9::uuid,
                  $10::timestamptz,$11::timestamptz,$12::jsonb,$13::jsonb,
                  $14,$15,$16,$17,$18,$19,$20,$21::jsonb,$22::uuid)
        SQL
      end

      def insert_idempotency(row)
        params = [
          row[:id], row[:created_at], row[:organization_id], row[:command_type], row[:target_type],
          row[:target_id], bytea(row[:key_digest]), bytea(row[:request_sha256]),
          row[:command_execution_id], row[:command_result_id], row[:retain_until]
        ]
        exec(<<~SQL, params)
          INSERT INTO idempotency_records
            (id, state_version, lock_version, created_at, updated_at, scope_kind, organization_id,
             command_type, target_type, target_id, key_digest, request_sha256,
             command_execution_id, command_result_id, retain_until)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,'organization',$3::uuid,
                  $4,$5,$6::uuid,$7,$8,$9::uuid,$10::uuid,$11::timestamptz)
        SQL
      end

      private

      def exec(sql, params) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      def iso(time) = time&.getutc&.iso8601(6)

      # PostgreSQL array literals. Text elements are double-quoted with backslash/quote
      # escaped; integers are emitted bare. An empty array is `{}`.
      def pg_text_array(arr)
        "{#{Array(arr).map { |e| %("#{e.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}") }.join(',')}}"
      end

      def pg_int_array(arr) = "{#{Array(arr).map(&:to_i).join(',')}}"
    end
  end
end
