# frozen_string_literal: true

module IdentityAccess
  module Infrastructure
    # Data access for Session-based organization-actor authorization (the
    # effective-permission checkpoint, WORKFLOW_SPECIFICATIONS.md :322-329). It
    # authenticates a Session pre-context (owner read via f1_authenticate_session),
    # enters the proved Organization context, then resolves — under FORCE row level
    # security — the Account and Organization status, the one active Access Policy,
    # and the actor's active effective Role Assignments, and persists the immutable
    # authorization_decisions record in-transaction (SECURITY_PERFORMANCE.md
    # PRULE-044). It never derives the actor Account or Organization from caller input.
    class AuthorizationStore
      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Pre-context: resolve the Session as the owner and return the fields the
      # caller validates. nil when the Session id does not resolve.
      def authenticate_session(session_id)
        sql = <<~SQL
          SELECT account_id, organization_id, status, idle_expires_at, absolute_expires_at,
                 authorization_context_version
          FROM f1_authenticate_session($1::uuid)
        SQL
        exec(sql, [session_id]).to_a.first
      end

      def enter_org_context(org, correlation_id)
        exec("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, correlation_id])
      end

      def account(account_id)
        exec("SELECT id, status FROM accounts WHERE id = $1::uuid", [account_id]).to_a.first
      end

      def organization(org)
        exec("SELECT status, authorization_epoch FROM organizations WHERE id = $1::uuid", [org]).to_a.first
      end

      # Step 2 (:325): exactly one active Organization Access Policy, or nil.
      def active_access_policy(org)
        sql = <<~SQL
          SELECT id, semantic_version FROM access_policies
          WHERE organization_id = $1::uuid AND policy_type = 'access' AND status = 'active'
          LIMIT 1
        SQL
        exec(sql, [org]).to_a.first
      end

      # Step 3 (:326, :316): the Account's active, effective, unexpired Role
      # Assignments in the current Organization context.
      def effective_role_assignments(account_id:, now:)
        sql = <<~SQL
          SELECT id, canonical_role, state_version, permission_mode, persona,
                 encode(scope_sha256,'hex') AS scope_hex, protected_permission_allowlist,
                 bootstrap_admin_exception
          FROM role_assignments
          WHERE account_id = $1::uuid AND status = 'active'
            AND effective_at IS NOT NULL AND effective_at <= $2::timestamptz
            AND (expires_at IS NULL OR $2::timestamptz < expires_at)
        SQL
        exec(sql, [account_id, now]).to_a
      end

      # The durable, immutable authorization decision (PG § authorization_decisions),
      # written on allow AND deny, in the command's transaction.
      def insert_authorization_decision(row)
        params = [
          row[:id], row[:created_at], row[:organization_id], row[:correlation_id], row[:causation_id],
          row[:command_id], row[:subject_id], row[:action], row[:resource_type], row[:resource_id],
          row[:decision], row[:reason_code], row[:organization_epoch], row[:membership_snapshot],
          row[:role_assignment_versions], row[:policy_snapshot_id], row[:decided_at]
        ]
        exec(<<~SQL, params)
          INSERT INTO authorization_decisions
            (id, schema_version, created_at, organization_id, correlation_id, causation_id, command_id,
             subject_type, subject_id, action, resource_type, resource_id, decision, reason_code,
             organization_epoch, membership_snapshot, role_assignment_versions, policy_snapshot_id,
             decided_at, retention_class)
          VALUES ($1,'1.0',$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,'account',$7::uuid,$8,$9,$10::uuid,
                  $11,$12,$13,$14::jsonb,$15::jsonb,$16::uuid,$17::timestamptz,'security_audit')
        SQL
      end

      private

      def exec(sql, params) = @pg.exec_params(sql, params)
    end
  end
end
