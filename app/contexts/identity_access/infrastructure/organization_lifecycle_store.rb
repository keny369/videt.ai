# frozen_string_literal: true

module IdentityAccess
  module Infrastructure
    # Persistence for the WF-013 Organization lifecycle transitions.
    #
    # Both transitions are guarded compare-and-swap updates on BOTH versions the
    # ratified contract names (016 STATE_MODEL.md :97 "activation/suspension/
    # closure commands use expected state and authorization versions"), so a
    # command that raced another observes zero rows changed rather than
    # overwriting it.
    #
    # Suspension revokes every active human Session of the Organization in the
    # SAME statement set as the state change (contracts/S-23.json MTX-038: "one
    # transaction changing active to suspended, recording the reason, incrementing
    # both versions, revoking every active human Session"). Reactivation
    # deliberately revokes nothing and restores nothing: a revoked Session is
    # terminal (016 STATE_MODEL.md :96 "revoked and expired are terminal").
    class OrganizationLifecycleStore
      include ActorLedgerWriters

      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Serialize competing lifecycle commands for one Organization, the same
      # advisory-lock convention the Invitation transitions use.
      def lock_organization(organization_id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["organization:#{organization_id}"])
      end

      def read_organization(organization_id)
        sql = <<~SQL
          SELECT id, status, state_version, authorization_epoch, suspended_at, reactivated_at
          FROM organizations WHERE id = $1::uuid
        SQL
        exec(sql, [organization_id]).to_a.first
      end

      # Read an Organization WITHOUT a proved tenant context, for the receipt-bound
      # reactivation path: the Organization is suspended, so no Session exists to
      # establish context from, and the receipt names its own bound Organization.
      # Returns the minimum lifecycle projection and nothing else.
      def organization_status(organization_id)
        exec("SELECT status FROM organizations WHERE id = $1::uuid", [organization_id]).values.dig(0, 0)
      end

      def active_access_policy(organization_id)
        sql = "SELECT id FROM access_policies WHERE organization_id = $1::uuid AND status = 'active'"
        rows = exec(sql, [organization_id]).to_a
        rows.size == 1 ? rows.first["id"] : nil
      end

      # The Account bound to the reactivation receipt's identity, and whether it
      # holds an effective OrganizationAdmin Assignment.
      def account_by_identity(issuer_key:, subject:)
        sql = <<~SQL
          SELECT id, status FROM accounts
          WHERE identity_issuer_key = $1 AND identity_subject = $2 LIMIT 1
        SQL
        exec(sql, [issuer_key, subject]).to_a.first
      end

      def effective_role_assignments(account_id:, now:)
        # `permission_mode` IS SELECTED BECAUSE THE BASELINE ROW HAS A CELL FOR IT (FU-62). Without
        # it the only decision this reader can support is the role limb, which is precisely how
        # `ReactivateOrganization` came to apply half the baseline: a reader that does not select
        # what the decision needs makes the partial decision the ONLY one available.
        sql = <<~SQL
          SELECT id, canonical_role, permission_mode, state_version FROM role_assignments
          WHERE account_id = $1::uuid AND status = 'active'
            AND effective_at IS NOT NULL AND effective_at <= $2::timestamptz
            AND (expires_at IS NULL OR $2::timestamptz < expires_at)
        SQL
        exec(sql, [account_id, iso(now)]).to_a
      end

      # active -> suspended, advancing BOTH versions. Returns rows changed.
      def suspend(organization_id, expected_version, expected_epoch, now, reason)
        params = [organization_id, expected_version, expected_epoch, iso(now), reason]
        exec(<<~SQL, params).cmd_tuples
          UPDATE organizations
          SET status = 'suspended', suspended_at = $4::timestamptz, lifecycle_reason = $5,
              state_version = state_version + 1, authorization_epoch = authorization_epoch + 1,
              updated_at = $4::timestamptz
          WHERE id = $1::uuid AND status = 'active'
            AND state_version = $2 AND authorization_epoch = $3
        SQL
      end

      # suspended -> active, advancing BOTH versions. Returns rows changed.
      def reactivate(organization_id, expected_version, expected_epoch, now)
        params = [organization_id, expected_version, expected_epoch, iso(now)]
        exec(<<~SQL, params).cmd_tuples
          UPDATE organizations
          SET status = 'active', reactivated_at = $4::timestamptz, lifecycle_reason = NULL,
              state_version = state_version + 1, authorization_epoch = authorization_epoch + 1,
              updated_at = $4::timestamptz
          WHERE id = $1::uuid AND status = 'suspended'
            AND state_version = $2 AND authorization_epoch = $3
        SQL
      end

      # Revoke every active human Session of the Organization, in the suspension
      # transaction. Returns the number revoked.
      def revoke_active_sessions(organization_id, now)
        exec(<<~SQL, [organization_id, iso(now)]).cmd_tuples
          UPDATE sessions
          SET status = 'revoked', terminated_at = $2::timestamptz,
              state_version = state_version + 1, updated_at = $2::timestamptz
          WHERE organization_id = $1::uuid AND status = 'active'
        SQL
      end

      # ---- receipt-bound reactivation -----------------------------------------

      # Read the reactivation receipt and enter the bound Organization's context.
      def enter_context(receipt_digest:, org:, correlation_id:)
        sql = <<~SQL
          SELECT receipt_found, receipt_id, purpose, validated_at, expires_at, email_verified,
                 issuer_key, issuer_subject, assurance_version, mfa_satisfied, context_org
          FROM f1_enter_context($1, $2::uuid, $3::uuid)
        SQL
        exec(sql, [bytea(receipt_digest), org, correlation_id]).to_a.first
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

      private

      def exec(sql, params) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      def iso(time) = time&.getutc&.iso8601(6)
    end
  end
end
