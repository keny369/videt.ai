# frozen_string_literal: true

module IdentityAccess
  module Infrastructure
    # Persistence for the WF-013 administrator commands that CREATE and APPROVE
    # Invitations, written in the caller's unit of work after the Session actor has
    # been authenticated and authorized and the Organization context entered.
    #
    # Every read and write below happens inside that proved context, so the
    # forced-RLS `invitations` table and the Organization-scoped reference registry
    # confine them to the actor's Organization without a single explicit
    # `organization_id` predicate in a WHERE clause.
    #
    # The ledger writers are the shared actor-attributed ones: `actor_id` set,
    # `service_identity_id` null. A created Invitation is a human administrator's
    # act, never the identity service's.
    class InvitationAdminStore
      include ActorLedgerWriters

      def initialize(pg_connection)
        @pg = pg_connection
      end

      # ---- reads ---------------------------------------------------------------

      # The open (pending-approval or active) Invitation for this exact offer, if
      # one exists. The partial unique index guarantees at most one.
      def find_open_by_uniqueness(uniqueness_digest)
        sql = <<~SQL
          SELECT id, state, state_version, expires_at,
                 encode(creation_idempotency_key_digest,'hex') AS creation_key_hex
          FROM invitations
          WHERE open_uniqueness_sha256 = $1 AND state IN ('pending_approval','active')
        SQL
        exec(sql, [bytea(uniqueness_digest)]).to_a.first
      end

      def read_invitation(invitation_id)
        sql = <<~SQL
          SELECT id, state, state_version, requester_account_id, approval_due_at, canonical_role,
                 permission_mode, persona, expires_at
          FROM invitations WHERE id = $1::uuid
        SQL
        exec(sql, [invitation_id]).to_a.first
      end

      # The same advisory lock every Invitation transition takes, so approval
      # serializes against accept, decline, revoke and expire.
      def lock_invitation(invitation_id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["invitation:#{invitation_id}"])
      end

      # An Account in this Organization matching the invitation target, by bound
      # identity when the offer names one, otherwise by normalized email digest.
      def find_target_account(email_sha256:, issuer_key:, subject:)
        if issuer_key && subject
          sql = "SELECT id, status FROM accounts WHERE identity_issuer_key = $1 AND identity_subject = $2 LIMIT 1"
          exec(sql, [issuer_key, subject]).to_a.first
        else
          exec("SELECT id, status FROM accounts WHERE normalized_email_sha256 = $1 LIMIT 1",
               [bytea(email_sha256)]).to_a.first
        end
      end

      # An already-effective Assignment for the exact offered tuple
      # (":244 Creation returns `invitation_grant_already_active` … when a
      # same-Organization active Account already has an exact effective Assignment
      # for the offered tuple").
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
        exec(sql, [account_id, canonical_role, permission_mode, persona, scope_hex, iso(now)]).values.dig(0, 0)
      end

      def organization_epoch(org)
        exec("SELECT authorization_epoch FROM organizations WHERE id = $1::uuid", [org]).values.dig(0, 0)
      end

      # The acting Assignment's approved protected allowlist, for a capability
      # whose Permission Baseline cell reads "protected explicit grant".
      def protected_allowlist(account_id:, canonical_role:)
        sql = <<~SQL
          SELECT protected_permission_allowlist FROM role_assignments
          WHERE account_id = $1::uuid AND canonical_role = $2 AND status = 'active'
          LIMIT 1
        SQL
        raw = exec(sql, [account_id, canonical_role]).values.dig(0, 0)
        raw ? JSON.parse(raw) : []
      end

      # ---- writes --------------------------------------------------------------

      def insert_invitation(row)
        params = [
          row[:id], row[:created_at], row[:correlation_id], row[:organization_id],
          bytea(row[:opaque_reference_sha256]), row[:target_email], bytea(row[:target_email_sha256]),
          row[:target_identity_issuer_key], row[:target_identity_subject], row[:canonical_role],
          row[:permission_mode], row[:persona], (row[:scope_sha256] ? bytea(row[:scope_sha256]) : nil),
          row[:protected_permission_preview], row[:state], row[:requester_account_id],
          row[:requested_at], row[:approval_due_at], row[:activated_at], row[:expires_at],
          row[:intended_assignment_expires_at], bytea(row[:open_uniqueness_sha256]),
          bytea(row[:creation_idempotency_key_digest]), row[:request_policy_version]
        ]
        exec(<<~SQL, params)
          INSERT INTO invitations
            (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
             opaque_reference_sha256, target_email, target_email_sha256, target_identity_issuer_key,
             target_identity_subject, canonical_role, permission_mode, persona, scope_sha256,
             protected_permission_preview, state, requester_account_id, requested_at, approval_due_at,
             activated_at, expires_at, intended_assignment_expires_at, open_uniqueness_sha256,
             creation_idempotency_key_digest, request_policy_version)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,
                  $5,$6,$7,$8,$9,$10,$11,$12,$13,$14::jsonb,$15,$16::uuid,$17::timestamptz,$18::timestamptz,
                  $19::timestamptz,$20::timestamptz,$21::timestamptz,$22,$23,$24)
        SQL
      end

      def insert_registry(row)
        params = [
          bytea(row[:opaque_reference_sha256]), row[:created_at], row[:organization_id], row[:invitation_id],
          row[:invitation_state], row[:activated_at], row[:expires_at]
        ]
        exec(<<~SQL, params)
          INSERT INTO invitation_reference_registry
            (opaque_reference_sha256, created_at, updated_at, organization_id, invitation_id,
             invitation_state, activated_at, expires_at, retention_class)
          VALUES ($1,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5,$6::timestamptz,$7::timestamptz,
                  'identity_commercial')
        SQL
      end

      # Guarded pending_approval -> active. Returns rows changed (0 => another
      # terminal transition won under the lock).
      def activate_invitation(invitation_id, expected_version, now, expires_at, approver_account_id)
        params = [invitation_id, expected_version, iso(now), iso(expires_at), approver_account_id]
        exec(<<~SQL, params).cmd_tuples
          UPDATE invitations
          SET state = 'active', activated_at = $3::timestamptz, expires_at = $4::timestamptz,
              security_approver_account_id = $5::uuid, state_version = state_version + 1,
              updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state = 'pending_approval' AND state_version = $2
        SQL
      end

      # Guarded pending_approval -> rejected.
      def reject_invitation(invitation_id, expected_version, now, reason, approver_account_id)
        params = [invitation_id, expected_version, iso(now), reason, approver_account_id]
        exec(<<~SQL, params).cmd_tuples
          UPDATE invitations
          SET state = 'rejected', terminated_at = $3::timestamptz, reason = $4,
              transition_reason_code = 'invitation_rejected', security_approver_account_id = $5::uuid,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state = 'pending_approval' AND state_version = $2
        SQL
      end

      # The Invitation's expiry instant, written only from the activation routine's
      # computed value so no command performs its own expiry arithmetic.
      def set_expiry(invitation_id, expires_at, now)
        exec(<<~SQL, [invitation_id, iso(expires_at), iso(now)])
          UPDATE invitations SET expires_at = $2::timestamptz, updated_at = $3::timestamptz
          WHERE id = $1::uuid
        SQL
      end

      def update_registry_active(invitation_id, activated_at, expires_at)
        params = [invitation_id, iso(activated_at), iso(expires_at)]
        exec(<<~SQL, params)
          UPDATE invitation_reference_registry
          SET invitation_state = 'active', activated_at = $2::timestamptz, expires_at = $3::timestamptz,
              updated_at = $2::timestamptz
          WHERE invitation_id = $1::uuid
        SQL
      end

      def update_registry_terminal(invitation_id, state, now)
        exec(<<~SQL, [invitation_id, state, iso(now)])
          UPDATE invitation_reference_registry
          SET invitation_state = $2, terminal_at = $3::timestamptz, updated_at = $3::timestamptz
          WHERE invitation_id = $1::uuid
        SQL
      end

      private

      def exec(sql, params) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      def iso(time) = time&.getutc&.iso8601(6)
    end
  end
end
