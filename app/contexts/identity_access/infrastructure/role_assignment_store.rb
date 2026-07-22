# frozen_string_literal: true

require "json"

module IdentityAccess
  module Infrastructure
    # Persistence for the WF-013 Role Assignment lifecycle, written in the caller's
    # unit of work inside the actor's proved Organization context.
    #
    # The grant content and the approved protected allowlist are written ONCE, at
    # insert, and the lifecycle trigger refuses to change either afterwards — so
    # this store deliberately offers no way to edit them. Activation is the only
    # write that sets an allowlist, and it does so on a row that has none.
    class RoleAssignmentStore
      include ActorLedgerWriters

      def initialize(pg_connection)
        @pg = pg_connection
      end

      # The same advisory-lock convention the Invitation and Organization
      # transitions use, so revoke, decide and expiry serialize per Assignment.
      def lock_role_assignment(id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["role_assignment:#{id}"])
      end

      # Serialize authority-changing transitions on the Organization, which is the
      # ratified serialization point for effective access (:331).
      def lock_organization(organization_id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["organization:#{organization_id}"])
      end

      def read(id)
        sql = <<~SQL
          SELECT id, account_id, organization_id, canonical_role, permission_mode, persona, status,
                 state_version, requester_account_id, requested_at, approval_due_at, effective_at,
                 expires_at, encode(scope_sha256,'hex') AS scope_hex, protected_permission_allowlist,
                 bootstrap_admin_exception
          FROM role_assignments WHERE id = $1::uuid
        SQL
        exec(sql, [id]).to_a.first
      end

      def account(account_id)
        exec("SELECT id, status FROM accounts WHERE id = $1::uuid", [account_id]).to_a.first
      end

      def organization_epoch(organization_id)
        exec("SELECT authorization_epoch FROM organizations WHERE id = $1::uuid",
             [organization_id]).values.dig(0, 0).to_i
      end

      # ":331 Policy/Assignment mutation atomically validates and advances the
      # Organization authorization version." Guarded on the expected epoch so a
      # command that raced another observes zero rows changed.
      def advance_authorization_epoch(organization_id, expected_epoch, now)
        exec(<<~SQL, [organization_id, expected_epoch, iso(now)]).cmd_tuples
          UPDATE organizations
          SET authorization_epoch = authorization_epoch + 1, state_version = state_version + 1,
              updated_at = $3::timestamptz
          WHERE id = $1::uuid AND authorization_epoch = $2
        SQL
      end

      def insert(row)
        params = [
          row[:id], row[:created_at], row[:correlation_id], row[:organization_id], row[:account_id],
          row[:canonical_role], row[:permission_mode], row[:persona],
          (row[:scope_sha256] ? bytea(row[:scope_sha256]) : nil), row[:status], row[:effective_at],
          row[:expires_at], row[:requester_account_id], row[:requested_at], row[:approval_due_at],
          row[:reason], row[:decision_authorization_epoch], bytea(row[:idempotency_key_digest]),
          row[:fulfilled_invitation_id], JSON.generate(row[:protected_permission_allowlist] || [])
        ]
        exec(<<~SQL, params)
          INSERT INTO role_assignments
            (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
             account_id, canonical_role, permission_mode, persona, scope_sha256, status, effective_at,
             expires_at, requester_account_id, requested_at, approval_due_at, reason,
             decision_authorization_epoch, idempotency_key_digest, fulfilled_invitation_id,
             protected_permission_allowlist)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6,$7,$8,$9,$10,
                  $11::timestamptz,$12::timestamptz,$13::uuid,$14::timestamptz,$15::timestamptz,$16,$17,$18,
                  $19::uuid,$20::jsonb)
        SQL
      end

      # Guarded pending -> active. The allowlist is set here because this is the
      # moment the grant becomes effective, and it is frozen from then on.
      def activate(id, expected_version, now, expires_at, epoch, allowlist)
        params = [id, expected_version, iso(now), iso(expires_at), epoch, JSON.generate(allowlist)]
        exec(<<~SQL, params).cmd_tuples
          UPDATE role_assignments
          SET status = 'active', effective_at = $3::timestamptz, expires_at = $4::timestamptz,
              decision_authorization_epoch = $5, protected_permission_allowlist = $6::jsonb,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND status = 'pending' AND state_version = $2
        SQL
      end

      def reject(id, expected_version, now, reason, epoch)
        params = [id, expected_version, iso(now), reason, epoch]
        exec(<<~SQL, params).cmd_tuples
          UPDATE role_assignments
          SET status = 'rejected', terminated_at = $3::timestamptz, reason = $4,
              transition_reason_code = 'role_assignment_rejected', decision_authorization_epoch = $5,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND status = 'pending' AND state_version = $2
        SQL
      end

      # ":314 ordered immutable approval records"; the unique indexes make a
      # duplicate approver and an out-of-order sequence impossible.
      def insert_approval(row)
        params = [
          row[:id], row[:created_at], row[:organization_id], row[:role_assignment_id],
          row[:sequence_number], row[:approver_account_id], row[:authority], row[:decision],
          row[:reason], row[:decided_at], row[:policy_version], row[:separation_result],
          row[:correlation_id]
        ]
        exec(<<~SQL, params)
          INSERT INTO role_assignment_approvals
            (id, schema_version, created_at, organization_id, role_assignment_id, sequence_number,
             approver_account_id, authority, decision, reason, decided_at, policy_version,
             separation_result, correlation_id)
          VALUES ($1,'1.0',$2::timestamptz,$3::uuid,$4::uuid,$5,$6::uuid,$7,$8,$9,$10::timestamptz,$11,$12,$13::uuid)
        SQL
      end

      def approval_count(role_assignment_id)
        exec("SELECT count(*) FROM role_assignment_approvals WHERE role_assignment_id = $1::uuid",
             [role_assignment_id]).values.dig(0, 0).to_i
      end

      private

      def exec(sql, params) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      def iso(time) = time&.getutc&.iso8601(6)
    end
  end
end
