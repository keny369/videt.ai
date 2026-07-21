# frozen_string_literal: true

module IdentityAccess
  module Infrastructure
    # Persistence for the WF-013 RevokeInvitation command, written in the caller's
    # unit of work AFTER the Session actor has been authenticated and authorized
    # (AuthorizationStore/CommandAuthorizer) and the Organization context entered. It
    # reads the target Invitation by its opaque reference under the actor's proved
    # Organization context (a cross-Organization reference is not visible), performs
    # the guarded active->revoked transition, mirrors the terminal state into the
    # reference registry, and writes the actor-attributed command/audit/event/
    # idempotency ledger (actor_id, never service_identity_id — this is a human
    # organization actor, not the identity service).
    class RevokeInvitationStore
      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Read the Invitation by its opaque reference in the current Organization
      # context; RLS confines it to the actor's Organization, so an unknown or
      # cross-Organization reference resolves to nil.
      def read_invitation_by_reference(reference_digest)
        sql = <<~SQL
          SELECT id, state, state_version, requester_account_id
          FROM invitations WHERE opaque_reference_sha256 = $1
        SQL
        exec(sql, [bytea(reference_digest)]).to_a.first
      end

      # Guarded active->revoked transition; returns rows changed (0 => lost the race
      # or stale version).
      def revoke_invitation(invitation_id, expected_version, now, reason)
        exec(<<~SQL, [invitation_id, expected_version, iso(now), reason]).cmd_tuples
          UPDATE invitations
          SET state = 'revoked', terminated_at = $3::timestamptz, reason = $4,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state = 'active' AND state_version = $2
        SQL
      end

      def update_registry_terminal(invitation_id, state, now)
        exec(<<~SQL, [invitation_id, state, iso(now)])
          UPDATE invitation_reference_registry
          SET invitation_state = $2, terminal_at = $3::timestamptz, updated_at = $3::timestamptz
          WHERE invitation_id = $1::uuid
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

      # ---- actor-attributed ledger writers ------------------------------------

      def insert_command_execution(row)
        params = [
          row[:id], row[:created_at], row[:correlation_id], row[:causation_id], row[:command_id],
          bytea(row[:idempotency_key_digest]), row[:command_type], row[:command_schema_version],
          row[:actor_id], row[:organization_id], row[:target_type], row[:target_id],
          row[:action], row[:requested_at], row[:authorization_check_at], row[:policy_versions],
          row[:canonical_payload], bytea(row[:request_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO command_executions
            (id, schema_version, created_at, correlation_id, causation_id, command_id,
             idempotency_key_digest, content_sha256, command_type, command_schema_version,
             actor_id, organization_id, target_type, target_id, action,
             requested_at, authorization_check_at, policy_versions, canonical_payload, request_sha256)
          VALUES ($1,'1.0',$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6,NULL,$7,$8,$9::uuid,$10::uuid,$11,$12::uuid,$13,
                  $14::timestamptz,$15::timestamptz,$16::jsonb,$17::jsonb,$18)
        SQL
      end

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
          VALUES ($1,'1.0',$2::timestamptz,$2::timestamptz,$3::date,$4::uuid,'WF-013',
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
          VALUES ($1,'1.0',$2::timestamptz,$3,'1.0','WF-013',$4,
                  $5::timestamptz,$6::uuid,$7,$8::uuid,$9,$10::date,
                  $11::uuid,$12::uuid,$13::uuid,$14::uuid,$15,$16,$17)
        SQL
      end

      def insert_command_result(row)
        failure = row[:failure]
        params = [
          row[:id], row[:created_at], row[:correlation_id], row[:causation_id], row[:command_id],
          row[:command_execution_id], row[:outcome], row[:organization_id], row[:actor_id],
          row[:completed_at], row[:authorization_check_at], row[:target_refs], row[:governing_policy_versions],
          failure&.error_class, failure&.error_code, failure&.reason_code, failure&.severity,
          failure&.retryable, failure&.recovery_action, failure&.support_reference,
          row[:authorized_payload], row[:audit_record_id]
        ]
        exec(<<~SQL, params)
          INSERT INTO command_results
            (id, schema_version, created_at, correlation_id, causation_id, command_id, command_execution_id,
             result_schema_version, outcome, organization_id, actor_id, completed_at,
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

      # Serialize concurrent terminal transitions on one Invitation (the same
      # advisory lock the receipt-bound terminal commands take).
      def lock_invitation(invitation_id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["invitation:#{invitation_id}"])
      end

      private

      def exec(sql, params) = @pg.exec_params(sql, params)
      def bytea(bytes) = { value: bytes, format: 1 }
      def iso(time) = time.getutc.iso8601(6)
    end
  end
end
