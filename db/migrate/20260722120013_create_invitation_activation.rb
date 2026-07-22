# frozen_string_literal: true

# Schema for WF-013 Invitation creation, approval and activation
# (WORKFLOW_SPECIFICATIONS.md :240 the Invitation record, :242 the activation
# rule, :244 creation authority and open-invitation uniqueness, :314 the Role
# Assignment protected allowlist; contracts/S-23.json MTX-038).
#
# The Invitation table already carried the fields the terminal transitions
# needed. This adds the fields creation and approval need, all named by :240:
# `requested_at_utc`, `approval_due_at_utc` for protected invitations, the
# nullable security approver, the intended Role Assignment expiry, the
# request/approval policy versions, the creating idempotency key, and the
# open-invitation uniqueness digest.
#
# The uniqueness rule is enforced by the database, not by a read-then-write:
# ":244 At most one pending-approval or active Invitation exists for that full
# preimage" is a partial unique index over exactly the open states, so two
# concurrent creations of the same offer cannot both commit.
#
# `role_assignments.protected_permission_allowlist` is the ":314 sorted explicit
# protected-permission allowlist". `invitation.approve` reads "protected explicit
# grant" in the Permission Baseline, so an approver must carry it in that
# allowlist; the workflow that POPULATES an allowlist is the Role Assignment
# lifecycle, which is a later block.
class CreateInvitationActivation < ActiveRecord::Migration[8.1]
  def up
    extend_invitations
    extend_role_assignments
  end

  def down
    execute "DROP INDEX IF EXISTS one_open_invitation_per_preimage;"
    execute "ALTER TABLE role_assignments DROP COLUMN IF EXISTS protected_permission_allowlist;"
    %w[requested_at approval_due_at security_approver_account_id intended_assignment_expires_at
       open_uniqueness_sha256 creation_idempotency_key_digest request_policy_version
       approval_policy_version].each do |column|
      execute "ALTER TABLE invitations DROP COLUMN IF EXISTS #{column};"
    end
  end

  private

  def extend_invitations
    execute <<~SQL
      ALTER TABLE invitations
        ADD COLUMN requested_at                    timestamptz(6),
        ADD COLUMN approval_due_at                 timestamptz(6),
        ADD COLUMN security_approver_account_id    uuid,
        ADD COLUMN intended_assignment_expires_at  timestamptz(6),
        ADD COLUMN open_uniqueness_sha256          bytea
          CHECK (open_uniqueness_sha256 IS NULL OR octet_length(open_uniqueness_sha256) = 32),
        ADD COLUMN creation_idempotency_key_digest bytea
          CHECK (creation_idempotency_key_digest IS NULL OR octet_length(creation_idempotency_key_digest) = 32),
        ADD COLUMN request_policy_version          text,
        ADD COLUMN approval_policy_version         text;
    SQL
    execute <<~SQL
      -- ":240 `approval_due_at_utc=requested_at_utc+24 hours` for protected
      -- invitations": a pending-approval Invitation always has its due instant,
      -- and that instant is exactly 24 hours after the request.
      ALTER TABLE invitations
        ADD CONSTRAINT invitation_pending_approval_has_due_instant CHECK (
          state <> 'pending_approval' OR approval_due_at IS NOT NULL
        ),
        ADD CONSTRAINT invitation_approval_due_is_24_hours CHECK (
          approval_due_at IS NULL OR requested_at IS NULL
            OR approval_due_at = requested_at + interval '24 hours'
        ),
        -- An approver is recorded only once one has decided.
        ADD CONSTRAINT invitation_approver_only_after_decision CHECK (
          security_approver_account_id IS NULL OR state <> 'pending_approval'
        );
    SQL
    execute <<~SQL
      -- ":244 At most one pending-approval or active Invitation exists for that
      -- full preimage." Enforced at the database boundary so two concurrent
      -- creations of the same offer cannot both commit; a terminal Invitation
      -- leaves the preimage free again, which is what reissue relies on.
      CREATE UNIQUE INDEX one_open_invitation_per_preimage
        ON invitations (organization_id, open_uniqueness_sha256)
        WHERE state IN ('pending_approval','active');
    SQL
  end

  def extend_role_assignments
    execute <<~SQL
      ALTER TABLE role_assignments
        ADD COLUMN protected_permission_allowlist jsonb NOT NULL DEFAULT '[]'::jsonb
          CHECK (jsonb_typeof(protected_permission_allowlist) = 'array');
    SQL
  end
end
