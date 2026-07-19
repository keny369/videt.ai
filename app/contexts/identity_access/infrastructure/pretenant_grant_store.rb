# frozen_string_literal: true

module IdentityAccess
  module Infrastructure
    # All persistence for the WF-001 grant path, written inside the caller's unit
    # of work on its proved connection. It is deliberately specific to this path:
    # a receipt-entry read, the eligibility reads, and the atomic ledger writes.
    # Every write goes through the FORCE-RLS tables, so a row can only be written
    # in the principal context f1_enter_bootstrap_context established.
    class PretenantGrantStore
      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Establish proved context and return the receipt fields, or nil if the
      # receipt digest does not resolve.
      def enter_bootstrap_context(receipt_digest:, correlation_id:)
        sql = <<~SQL
          SELECT receipt_id, purpose, validated_at, expires_at, email_verified,
                 issuer_key, receipt_schema_version, encode(bootstrap_principal_digest,'hex') AS principal_hex,
                 context_org
          FROM f1_enter_bootstrap_context($1, $2::uuid)
        SQL
        exec(sql, [bytea(receipt_digest), correlation_id]).to_a.first
      end

      # Tier-zero serialization on the not-yet-existing bootstrap principal, so
      # concurrent requests for one principal are decided one at a time.
      def lock_principal(principal_hex)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["bootstrap-principal:#{principal_hex}"])
      end

      def issued_grant_id
        exec("SELECT id FROM bootstrap_grants WHERE state = 'issued' LIMIT 1", []).values.dig(0, 0)
      end

      def consumed_grant_exists?
        !exec("SELECT 1 FROM bootstrap_grants WHERE state = 'consumed' LIMIT 1", []).values.empty?
      end

      def find_idempotency(scope_kind:, principal_hex:, command_type:, target_type:, key_digest:)
        sql = <<~SQL
          SELECT encode(request_sha256,'hex') AS request_hex, command_result_id
          FROM idempotency_records
          WHERE scope_kind = $1 AND bootstrap_principal_digest = $2
            AND command_type = $3 AND target_type = $4 AND key_digest = $5
          LIMIT 1
        SQL
        exec(sql, [scope_kind, bytea(hex(principal_hex)), command_type, target_type, bytea(key_digest)]).to_a.first
      end

      def load_command_result(id)
        sql = <<~SQL
          SELECT id, outcome, authorized_payload, audit_record_id, correlation_id,
                 error_class, error_code, reason_code, severity, retryable, recovery_action, support_reference
          FROM command_results WHERE id = $1::uuid
        SQL
        exec(sql, [id]).to_a.first
      end

      def insert_command_execution(row)
        params = [
          row[:id], row[:created_at], row[:correlation_id], row[:causation_id], row[:command_id],
          bytea(row[:idempotency_key_digest]), row[:command_type], row[:command_schema_version],
          row[:service_identity_id], bytea(hex(row[:principal_hex])), row[:target_type], row[:target_id],
          row[:action], row[:requested_at], row[:authorization_check_at], row[:policy_versions],
          row[:canonical_payload], bytea(row[:request_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO command_executions
            (id, schema_version, created_at, correlation_id, causation_id, command_id,
             idempotency_key_digest, content_sha256, command_type, command_schema_version,
             service_identity_id, bootstrap_principal_digest, target_type, target_id, action,
             requested_at, authorization_check_at, policy_versions, canonical_payload, request_sha256)
          VALUES ($1,'1.0',$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6,$18,$7,$8,$9::uuid,$10,$11,$12::uuid,$13,
                  $14::timestamptz,$15::timestamptz,$16::jsonb,$17::jsonb,$18)
        SQL
      end

      def insert_pretenant_authorization(row)
        params = [
          row[:id], row[:created_at], row[:correlation_id], row[:causation_id], row[:command_id],
          bytea(hex(row[:principal_hex])), row[:receipt_id], row[:service_identity_id], row[:action],
          row[:decision], row[:reason_code], row[:policy_versions], row[:decided_at]
        ]
        exec(<<~SQL, params)
          INSERT INTO pretenant_authorization_decisions
            (id, schema_version, created_at, correlation_id, causation_id, command_id,
             bootstrap_principal_digest, receipt_id, subject_service_identity_id, action, resource_type,
             decision, reason_code, policy_versions, decided_at)
          VALUES ($1,'1.0',$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6,$7::uuid,$8::uuid,$9,'bootstrap_grant',
                  $10,$11,$12::jsonb,$13::timestamptz)
        SQL
      end

      def insert_bootstrap_grant(row)
        params = [
          row[:id], row[:created_at], row[:correlation_id], row[:causation_id], row[:command_id],
          bytea(hex(row[:principal_hex])), row[:issuer_service_identity_id], row[:policy_version],
          row[:issued_at], row[:expires_at]
        ]
        exec(<<~SQL, params)
          INSERT INTO bootstrap_grants
            (id, state_version, lock_version, created_at, updated_at, correlation_id, causation_id, command_id,
             bootstrap_principal_digest, allowed_action, issuer_service_identity_id, policy_version,
             issued_at, expires_at, state)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6,'organization.bootstrap',
                  $7::uuid,$8,$9::timestamptz,$10::timestamptz,'issued')
        SQL
      end

      # Single-use nonce consumption; returns the stored outcome or 'already_consumed'.
      def consume_nonce(row)
        params = [
          row[:id], row[:created_at], row[:receipt_id], bytea(row[:receipt_digest]),
          row[:command_execution_id], row[:consumed_at], row[:outcome], row[:reason_code]
        ]
        exec(<<~SQL, params).values.dig(0, 0)
          SELECT f1_consume_receipt_nonce($1::uuid,$2::timestamptz,$3::uuid,$4,$5::uuid,$6::timestamptz,$7,$8)
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
          VALUES ($1,'1.0',$2::timestamptz,$2::timestamptz,$3::date,$4::uuid,'WF-001',
                  $5::uuid,$6::uuid,$7::uuid,$8::uuid,$9,$10::uuid,$11,$12,$13,'restricted',$14::jsonb,$15,'security_audit')
        SQL
      end

      def insert_event(row)
        params = [
          row[:id], row[:created_at], row[:event_type], row[:occurred_at], row[:organization_id],
          row[:aggregate_type], row[:aggregate_id], row[:partition_month], row[:correlation_id],
          row[:causation_id], row[:command_id], row[:audit_record_id], bytea(row[:event_bytes]),
          row[:event_bytes].bytesize, bytea(row[:event_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO event_registry
            (id, schema_version, created_at, event_type, event_schema_version, workflow_id, event_profile,
             occurred_at, organization_id, aggregate_type, aggregate_id, aggregate_version, partition_month,
             correlation_id, causation_id, command_id, audit_record_id, event_bytes, event_byte_count, event_sha256)
          VALUES ($1,'1.0',$2::timestamptz,$3,'1.0','WF-001','created',
                  $4::timestamptz,$5::uuid,$6,$7::uuid,0,$8::date,
                  $9::uuid,$10::uuid,$11::uuid,$12::uuid,$13,$14,$15)
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
          row[:id], row[:created_at], bytea(hex(row[:principal_hex])), row[:command_type], row[:target_type],
          row[:target_id], bytea(row[:key_digest]), bytea(row[:request_sha256]),
          row[:command_execution_id], row[:command_result_id], row[:retain_until]
        ]
        exec(<<~SQL, params)
          INSERT INTO idempotency_records
            (id, state_version, lock_version, created_at, updated_at, scope_kind, bootstrap_principal_digest,
             command_type, target_type, target_id, key_digest, request_sha256,
             command_execution_id, command_result_id, retain_until)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,'bootstrap_principal',$3,
                  $4,$5,$6::uuid,$7,$8,$9::uuid,$10::uuid,$11::timestamptz)
        SQL
      end

      private

      def exec(sql, params)
        @pg.exec_params(sql, params)
      end

      def bytea(bytes) = { value: bytes, format: 1 }
      def hex(hex_string) = [hex_string].pack("H*")
    end
  end
end
