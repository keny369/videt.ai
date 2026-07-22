# frozen_string_literal: true

module IdentityAccess
  module Infrastructure
    # Persistence for the WF-001 service-only ExpireInvitation transition, written
    # in the caller's unit of work.
    #
    # It enters the Organization context named by the claimed ScheduledAction —
    # the only tenant selector on this path, since a timer has no Session and no
    # receipt — using the same `f1_enter_org_context` the Session-authenticated
    # WF-013 commands use. Everything afterwards is read and written under row
    # level security, so an action whose target belongs to another Organization
    # simply resolves to nothing and discloses no existence.
    #
    # The Invitation is re-read under the SAME per-invitation advisory lock that
    # AcceptInvitation, DeclineInvitation and RevokeInvitation take, so all four
    # terminal transitions serialize against one another and exactly one wins.
    #
    # The ledger is attributed to `service_identity_id`, never `actor_id`: this is
    # the identity service's timer, not a human organization actor, and
    # `command_executions`, `command_results` and `audit_record_registry` each
    # enforce `exactly_one_actor_or_service`.
    class ExpireInvitationStore
      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Enter the action's Organization context. No receipt is read and no nonce
      # is touched; entering context is data scoping, not authorization.
      def enter_org_context(org:, correlation_id:)
        exec("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, correlation_id]).values.dig(0, 0)
      end

      # The same advisory lock key the receipt-bound and Session-authenticated
      # terminal commands take.
      def lock_invitation(invitation_id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["invitation:#{invitation_id}"])
      end

      # Visible only inside the current Organization context; a cross-Organization
      # id resolves to nil.
      def read_invitation(invitation_id)
        sql = <<~SQL
          SELECT id, state, state_version, expires_at, requester_account_id
          FROM invitations WHERE id = $1::uuid
        SQL
        exec(sql, [invitation_id]).to_a.first
      end

      def organization_epoch(org)
        exec("SELECT authorization_epoch FROM organizations WHERE id = $1::uuid", [org]).values.dig(0, 0)
      end

      # Guarded active->expired transition, recording the terminal time and the
      # retained machine transition reason. Returns rows changed (0 => another
      # terminal transition won the race under the lock).
      def expire_invitation(invitation_id, expected_version, now, reason_code)
        exec(<<~SQL, [invitation_id, expected_version, iso(now), reason_code]).cmd_tuples
          UPDATE invitations
          SET state = 'expired', terminated_at = $3::timestamptz, transition_reason_code = $4,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state = 'active' AND state_version = $2
        SQL
      end

      # Mirror the terminal state into the global locator in the same transaction,
      # so the non-disclosing public resolver stops resolving the reference.
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

      # ---- service-attributed ledger writers ----------------------------------

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

      def exec(sql, params) = @pg.exec_params(sql, params)
      def bytea(bytes) = { value: bytes, format: 1 }
      def iso(time) = time.getutc.iso8601(6)
    end
  end
end
