# frozen_string_literal: true

module IdentityAccess
  module Infrastructure
    # All persistence for the WF-001 existing-account sign-in branch, written
    # inside the caller's unit of work on its proved connection. It enters the
    # command's Organization context, performs the read-only resolution the
    # first-match order requires (Account, Organization, effective Role
    # Assignments, active Access Policy), and writes the atomic ledger set plus at
    # most one Session. Every table is FORCE-RLS, so a row can only be read or
    # written in the Organization context f1_enter_context established.
    class TenantSignInStore
      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Enter the command's Organization context and return the sign-in receipt
      # fields. The context is set whether or not the receipt resolves, so a
      # denial can be audited in that Organization. `receipt_found` distinguishes
      # an unresolved digest.
      def enter_context(receipt_digest:, org:, correlation_id:)
        sql = <<~SQL
          SELECT receipt_found, receipt_id, purpose, validated_at, expires_at, email_verified,
                 issuer_key, issuer_subject, receipt_schema_version, assurance_version, mfa_satisfied,
                 encode(identity_principal_digest,'hex') AS principal_hex, context_org
          FROM f1_enter_context($1, $2::uuid, $3::uuid)
        SQL
        exec(sql, [bytea(receipt_digest), org, correlation_id]).to_a.first
      end

      # Serialize concurrent requests that share one idempotency identity so exact
      # replay is decided one at a time; distinct receipts are not serialized and
      # create concurrent Sessions.
      def lock_idempotency(org, key_digest)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
             ["signin-idem:#{org}:#{hex(key_digest)}"])
      end

      def find_idempotency(org:, command_type:, target_type:, key_digest:)
        sql = <<~SQL
          SELECT encode(request_sha256,'hex') AS request_hex, command_result_id
          FROM idempotency_records
          WHERE scope_kind = 'organization' AND organization_id = $1::uuid
            AND command_type = $2 AND target_type = $3 AND key_digest = $4
          LIMIT 1
        SQL
        exec(sql, [org, command_type, target_type, bytea(key_digest)]).to_a.first
      end

      def load_command_result(id)
        sql = <<~SQL
          SELECT id, outcome, authorized_payload, audit_record_id, correlation_id,
                 error_class, error_code, reason_code, severity, retryable, recovery_action, support_reference
          FROM command_results WHERE id = $1::uuid
        SQL
        exec(sql, [id]).to_a.first
      end

      # ---- first-match resolution (read-only, in Organization context) ---------

      def resolve_account(issuer_key:, subject:)
        sql = <<~SQL
          SELECT id, status, state_version
          FROM accounts
          WHERE identity_issuer_key = $1 AND identity_subject = $2
          LIMIT 1
        SQL
        exec(sql, [issuer_key, subject]).to_a.first
      end

      def organization(org)
        exec("SELECT status, authorization_epoch FROM organizations WHERE id = $1::uuid", [org]).to_a.first
      end

      # Canonical roles of the Account's currently effective Role Assignments
      # (active, effective_at reached, not expired). Feeds the admin-role-capable
      # MFA gate and the organization_home/access_unavailable destination.
      # `now` is normalized to microsecond ISO 8601 first. A Ruby `Time` handed to
      # `exec_params` is stringified by `to_s`, which truncates to whole SECONDS, so an
      # Assignment made effective at 10:00:00.106825 was not yet effective to any sign-in
      # in the rest of that second. The visible symptom was the worst kind: an
      # administrator who had just bootstrapped their Organization signed in and was sent
      # to `access_unavailable`, told they hold no access, seconds after being granted it.
      def effective_roles(account_id:, now:)
        sql = <<~SQL
          SELECT canonical_role
          FROM role_assignments
          WHERE account_id = $1::uuid AND status = 'active'
            AND effective_at IS NOT NULL AND effective_at <= $2::timestamptz
            AND (expires_at IS NULL OR $2::timestamptz < expires_at)
        SQL
        exec(sql, [account_id, timestamp(now)]).to_a.map { |r| r["canonical_role"] }
      end

      def active_access_policy_version(org)
        sql = <<~SQL
          SELECT semantic_version FROM access_policies
          WHERE organization_id = $1::uuid AND policy_type = 'access' AND status = 'active'
          LIMIT 1
        SQL
        exec(sql, [org]).values.dig(0, 0)
      end

      # ---- ledger writers ------------------------------------------------------

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

      def consume_nonce(row)
        params = [
          row[:id], row[:created_at], row[:receipt_id], bytea(row[:receipt_digest]),
          row[:command_execution_id], row[:consumed_at], row[:outcome], row[:reason_code]
        ]
        exec(<<~SQL, params).values.dig(0, 0)
          SELECT f1_consume_receipt_nonce($1::uuid,$2::timestamptz,$3::uuid,$4,$5::uuid,$6::timestamptz,$7,$8)
        SQL
      end

      def insert_session(row)
        params = [
          row[:id], row[:created_at], row[:correlation_id], row[:organization_id], row[:account_id],
          bytea(row[:identity_receipt_digest]), row[:authorization_context_version], row[:creation_reason],
          row[:issued_at], row[:last_activity_at], row[:idle_expires_at], row[:absolute_expires_at],
          bytea(row[:token_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO sessions
            (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id, account_id,
             identity_receipt_digest, authorization_context_version, creation_reason,
             issued_at, last_activity_at, idle_expires_at, absolute_expires_at, status, token_sha256)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6,$7,$8,
                  $9::timestamptz,$10::timestamptz,$11::timestamptz,$12::timestamptz,'active',$13)
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

      def exec(sql, params)
        @pg.exec_params(sql, params)
      end

      def bytea(bytes) = { value: bytes, format: 1 }
      def hex(bytes) = bytes.unpack1("H*")

      # Full microsecond precision, whatever the caller passed. An already-formatted ISO
      # string passes through unchanged.
      def timestamp(value) = value.respond_to?(:getutc) ? value.getutc.iso8601(6) : value
    end
  end
end
