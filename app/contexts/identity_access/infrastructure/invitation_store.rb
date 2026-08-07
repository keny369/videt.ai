# frozen_string_literal: true

module IdentityAccess
  module Infrastructure
    # All persistence for the WF-001 invitation-acceptance branch, written inside
    # the caller's unit of work on its proved connection, after InvitationResolver
    # has resolved the Organization. It enters the Organization context (reusing
    # f1_enter_context, which also reads the acceptance receipt), performs the
    # first-match resolution (Invitation, Account uniqueness key, effective
    # Assignment) and the atomic multi-root write set (Account create-or-bind, one
    # created-or-reused Role Assignment, Invitation active->accepted, Session, and
    # the platform ledger). Every table is FORCE-RLS (except the ENABLE-RLS
    # reference registry), so a row can only be read or written in the proved
    # Organization context.
    class InvitationStore
      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Read the acceptance receipt and enter the resolved Organization context
      # (bootstrap principal NULL, real organization_id). Reuses f1_enter_context.
      def enter_context(receipt_digest:, org:, correlation_id:)
        sql = <<~SQL
          SELECT receipt_found, receipt_id, purpose, validated_at, expires_at, email_verified,
                 issuer_key, issuer_subject, encode(normalized_email_sha256,'hex') AS email_hex,
                 normalized_email, display_name, context_org
          FROM f1_enter_context($1, $2::uuid, $3::uuid)
        SQL
        exec(sql, [bytea(receipt_digest), org, correlation_id]).to_a.first
      end

      # Serialize concurrent acceptances of one Invitation so exactly one commits;
      # the loser reads the terminal state under the lock.
      def lock_invitation(invitation_id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["invitation:#{invitation_id}"])
      end

      def read_invitation(invitation_id)
        sql = <<~SQL
          SELECT id, state, state_version, encode(target_email_sha256,'hex') AS target_email_hex,
                 target_identity_issuer_key, target_identity_subject, canonical_role, permission_mode,
                 persona, encode(scope_sha256,'hex') AS scope_hex, expires_at
          FROM invitations WHERE id = $1::uuid
        SQL
        exec(sql, [invitation_id]).to_a.first
      end

      # ---- first-match resolution (in Organization context) --------------------

      def resolve_account(issuer_key:, subject:)
        sql = "SELECT id, status, state_version FROM accounts WHERE identity_issuer_key = $1 AND identity_subject = $2 LIMIT 1"
        exec(sql, [issuer_key, subject]).to_a.first
      end

      # Visible only inside the current Organization context; a cross-Organization
      # id resolves to nil.
      def account_by_id(account_id)
        exec("SELECT id, status FROM accounts WHERE id = $1::uuid", [account_id]).to_a.first
      end

      # The Organization authorization epoch stamped onto the new Session's
      # authorization-context version.
      def organization_epoch(org)
        exec("SELECT authorization_epoch FROM organizations WHERE id = $1::uuid", [org]).values.dig(0, 0)
      end

      def find_effective_assignment(account_id:, canonical_role:, permission_mode:, persona:, scope_hex:, now:)
        sql = <<~SQL
          SELECT id FROM role_assignments
          WHERE account_id = $1::uuid AND status = 'active'
            AND canonical_role = $2 AND permission_mode = $3
            AND coalesce(persona, '') = coalesce($4, '')
            AND coalesce(encode(scope_sha256, 'hex'), '') = coalesce($5, '')
            AND effective_at IS NOT NULL AND effective_at <= $6::timestamptz
            AND (expires_at IS NULL OR $6::timestamptz < expires_at)
          LIMIT 1
        SQL
        # Microsecond precision matters here for the same reason it does in the sign-in
        # and authorization stores: `exec_params` stringifies a Ruby `Time` to whole
        # seconds, and a truncated `now` would hide an Assignment that became effective
        # earlier in the same second — turning this duplicate check into a false negative
        # and admitting the second grant it exists to refuse.
        exec(sql, [account_id, canonical_role, permission_mode, persona, scope_hex, timestamp(now)]).values.dig(0, 0)
      end

      # ---- writers -------------------------------------------------------------

      def insert_account_pending(row)
        params = [
          row[:id], row[:created_at], row[:correlation_id], row[:organization_id], row[:issuer_key],
          row[:subject], row[:normalized_email], bytea(row[:normalized_email_sha256]), row[:display_name],
          bytea(row[:identity_receipt_digest])
        ]
        exec(<<~SQL, params)
          INSERT INTO accounts
            (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
             identity_issuer_key, identity_subject, normalized_email, normalized_email_sha256, display_name,
             status, identity_receipt_digest)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5,$6,$7,$8,$9,'pending',$10)
        SQL
      end

      def activate_account(account_id, now)
        exec(<<~SQL, [account_id, iso(now)])
          UPDATE accounts SET status = 'active', activated_at = $2::timestamptz,
                 state_version = state_version + 1, updated_at = $2::timestamptz
          WHERE id = $1::uuid AND status = 'pending'
        SQL
      end

      def insert_role_assignment(row)
        params = [
          row[:id], row[:created_at], row[:correlation_id], row[:organization_id], row[:account_id],
          row[:canonical_role], row[:permission_mode], row[:persona],
          (row[:scope_sha256] ? bytea(row[:scope_sha256]) : nil), row[:effective_at]
        ]
        exec(<<~SQL, params)
          INSERT INTO role_assignments
            (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id, account_id,
             canonical_role, permission_mode, persona, status, effective_at, scope_sha256)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6,$7,$8,'active',$10::timestamptz,$9)
        SQL
      end

      # Guarded transition: only an active row at the expected version transitions.
      # Returns the number of rows changed (0 means another command won).
      def accept_invitation(invitation_id, expected_version, assignment_id, now)
        exec(<<~SQL, [invitation_id, expected_version, assignment_id, iso(now)]).cmd_tuples
          UPDATE invitations
          SET state = 'accepted', accepted_at = $4::timestamptz, fulfilled_by_role_assignment_id = $3::uuid,
              state_version = state_version + 1, updated_at = $4::timestamptz
          WHERE id = $1::uuid AND state = 'active' AND state_version = $2
        SQL
      end

      # Guarded active->declined transition; returns rows changed (0 => lost the race).
      def decline_invitation(invitation_id, expected_version, now, reason)
        exec(<<~SQL, [invitation_id, expected_version, iso(now), reason]).cmd_tuples
          UPDATE invitations
          SET state = 'declined', declined_at = $3::timestamptz, reason = $4,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state = 'active' AND state_version = $2
        SQL
      end

      # Mirror the winning terminal state into the global reference locator, in the
      # same transaction (schemas/POSTGRESQL_SCHEMA.md § registry lifecycle tuple).
      def update_registry_terminal(invitation_id, state, now)
        exec(<<~SQL, [invitation_id, state, iso(now)])
          UPDATE invitation_reference_registry
          SET invitation_state = $2, terminal_at = $3::timestamptz, updated_at = $3::timestamptz
          WHERE invitation_id = $1::uuid
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

      def consume_nonce(row)
        params = [
          row[:id], row[:created_at], row[:receipt_id], bytea(row[:receipt_digest]),
          row[:command_execution_id], row[:consumed_at], row[:outcome], row[:reason_code]
        ]
        exec(<<~SQL, params).values.dig(0, 0)
          SELECT f1_consume_receipt_nonce($1::uuid,$2::timestamptz,$3::uuid,$4,$5::uuid,$6::timestamptz,$7,$8)
        SQL
      end

      # ---- idempotency + ledger ------------------------------------------------

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
          VALUES ($1,'1.0',$2::timestamptz,$2::timestamptz,$3::date,$4::uuid,'WF-001',
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
          VALUES ($1,'1.0',$2::timestamptz,$3,'1.0','WF-001',$4,
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

      def exec(sql, params)
        @pg.exec_params(sql, params)
      end

      def bytea(bytes) = { value: bytes, format: 1 }
      def iso(time) = time.getutc.iso8601(6)

      # Full microsecond precision, whatever the caller passed. An already-formatted ISO
      # string passes through unchanged.
      def timestamp(value) = value.respond_to?(:getutc) ? iso(value) : value
    end
  end
end
