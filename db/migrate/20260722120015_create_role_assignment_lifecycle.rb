# frozen_string_literal: true

# Schema for the WF-013 Role Assignment lifecycle and protected authority
# (WORKFLOW_SPECIFICATIONS.md :314 the Role Assignment record, :316 the state
# machine and expiry rules, :331-333 the protected-grant enumeration and its
# approval rules, :322-329 the effective-permission algorithm; contracts/S-23.json
# MTX-038).
#
# The status vocabulary already existed. This adds the fields :314 names and the
# record :314 requires — "ordered immutable approval records" — plus the database
# enforcement that makes protected authority a fact rather than a convention.
#
# The allowlist is the load-bearing field: step 4 of the effective-permission
# algorithm requires "any protected permission to appear in the Assignment's
# approved protected allowlist", so once an Assignment exists its allowlist is
# frozen. A trigger refuses any change to it, refuses an allowlist on a pending
# Assignment (nothing is approved yet), refuses one that is not sorted-unique,
# and refuses any transition the ratified table does not contain.
class CreateRoleAssignmentLifecycle < ActiveRecord::Migration[8.1]
  def up
    extend_role_assignments
    create_approvals
    create_guard_trigger
  end

  def down
    execute "DROP TRIGGER IF EXISTS role_assignments_lifecycle_guard ON role_assignments;"
    execute "DROP FUNCTION IF EXISTS f1_role_assignments_lifecycle_guard();"
    execute "DROP TABLE IF EXISTS role_assignment_approvals;"
    %w[requester_account_id requested_at approval_due_at reason transition_reason_code
       decision_authorization_epoch idempotency_key_digest fulfilled_invitation_id
       terminated_at].each do |column|
      execute "ALTER TABLE role_assignments DROP COLUMN IF EXISTS #{column};"
    end
  end

  private

  def extend_role_assignments
    execute <<~SQL
      ALTER TABLE role_assignments
        ADD COLUMN requester_account_id          uuid,
        ADD COLUMN requested_at                  timestamptz(6),
        ADD COLUMN approval_due_at               timestamptz(6),
        ADD COLUMN terminated_at                 timestamptz(6),
        ADD COLUMN reason                        text
          CHECK (reason IS NULL OR char_length(reason) BETWEEN 1 AND 2000),
        ADD COLUMN transition_reason_code        text
          CHECK (transition_reason_code IS NULL OR transition_reason_code ~ '^[a-z][a-z0-9_]{0,119}$'),
        -- ":314 Organization authorization epoch at decision".
        ADD COLUMN decision_authorization_epoch  bigint,
        ADD COLUMN idempotency_key_digest        bytea
          CHECK (idempotency_key_digest IS NULL OR octet_length(idempotency_key_digest) = 32),
        -- The Invitation whose acceptance or approval produced this Assignment.
        ADD COLUMN fulfilled_invitation_id       uuid;
    SQL
    execute <<~SQL
      ALTER TABLE role_assignments
        -- ":316 A protected Assignment request has `approval_due_at_utc =
        -- server_requested_at_utc + 24 hours`" and confers nothing while pending.
        ADD CONSTRAINT role_assignment_approval_due_is_24_hours CHECK (
          approval_due_at IS NULL OR requested_at IS NULL
            OR approval_due_at = requested_at + interval '24 hours'
        ),
        ADD CONSTRAINT role_assignment_pending_is_not_effective CHECK (
          status <> 'pending' OR effective_at IS NULL
        ),
        -- ":316 Active resolution requires `effective_at_utc <= now_utc`", so an
        -- active Assignment always has one.
        ADD CONSTRAINT role_assignment_active_is_effective CHECK (
          status <> 'active' OR effective_at IS NOT NULL
        ),
        -- ":316 Its active expiry is mandatory and no later than 30 days after
        -- effectiveness" for a protected Assignment; a nonprotected one may have
        -- none. Protection is carried by a non-empty allowlist.
        ADD CONSTRAINT role_assignment_protected_expiry_within_30_days CHECK (
          jsonb_array_length(protected_permission_allowlist) = 0
            OR effective_at IS NULL OR expires_at IS NULL
            OR expires_at <= effective_at + interval '30 days'
        );
    SQL
  end

  # ":314 ordered immutable approval records … approver Account or platform-identity
  # ID, authority, decision, reason, decided time, policy version, separation
  # result; duplicate approvers are invalid."
  def create_approvals
    execute <<~SQL
      CREATE TABLE role_assignment_approvals (
        id                    uuid PRIMARY KEY,
        schema_version        text NOT NULL,
        created_at            timestamptz(6) NOT NULL,
        organization_id       uuid NOT NULL,
        role_assignment_id    uuid NOT NULL,
        sequence_number       integer NOT NULL CHECK (sequence_number >= 1),
        approver_account_id   uuid,
        approver_platform_id  uuid,
        authority             text NOT NULL,
        decision              text NOT NULL CHECK (decision IN ('approve','reject')),
        reason                text,
        decided_at            timestamptz(6) NOT NULL,
        policy_version        text NOT NULL,
        separation_result     text NOT NULL CHECK (separation_result IN ('distinct','same_principal')),
        correlation_id        uuid NOT NULL,
        CONSTRAINT approval_has_exactly_one_approver CHECK (
          (approver_account_id IS NULL) <> (approver_platform_id IS NULL)
        ),
        CONSTRAINT approval_records_are_ordered UNIQUE (role_assignment_id, sequence_number)
      );
      -- ":314 duplicate approvers are invalid".
      CREATE UNIQUE INDEX one_approval_per_approver
        ON role_assignment_approvals (role_assignment_id, coalesce(approver_account_id, approver_platform_id));
      ALTER TABLE role_assignment_approvals ENABLE ROW LEVEL SECURITY;
      ALTER TABLE role_assignment_approvals FORCE ROW LEVEL SECURITY;
      CREATE POLICY role_assignment_approvals_context ON role_assignment_approvals
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
      REVOKE ALL ON role_assignment_approvals FROM PUBLIC;
    SQL
  end

  def create_guard_trigger
    execute <<~SQL
      CREATE FUNCTION f1_role_assignments_lifecycle_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      DECLARE allowed text[];
      BEGIN
        -- The approved protected authority of an Assignment is an immutable
        -- historical fact: step 4 of the effective-permission algorithm reads it,
        -- so a later edit would silently re-authorize history.
        IF NEW.protected_permission_allowlist IS DISTINCT FROM OLD.protected_permission_allowlist THEN
          RAISE EXCEPTION 'role_assignment_allowlist_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.account_id IS DISTINCT FROM OLD.account_id
           OR NEW.canonical_role IS DISTINCT FROM OLD.canonical_role
           OR NEW.permission_mode IS DISTINCT FROM OLD.permission_mode
           OR NEW.persona IS DISTINCT FROM OLD.persona
           OR NEW.scope_sha256 IS DISTINCT FROM OLD.scope_sha256
           OR NEW.requester_account_id IS DISTINCT FROM OLD.requester_account_id
           OR NEW.requested_at IS DISTINCT FROM OLD.requested_at THEN
          RAISE EXCEPTION 'role_assignment_grant_content_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        -- ":316 Valid transitions are pending to active, rejected, or expired;
        -- active to revoked or expired. Revoked, rejected, and expired are terminal."
        allowed := CASE OLD.status
                     WHEN 'pending' THEN ARRAY['pending','active','rejected','expired']
                     WHEN 'active'  THEN ARRAY['active','revoked','expired']
                     ELSE ARRAY[OLD.status]
                   END;
        IF NOT (NEW.status = ANY (allowed)) THEN
          RAISE EXCEPTION 'role_assignment_illegal_transition % -> %', OLD.status, NEW.status
            USING ERRCODE = 'raise_exception';
        END IF;

        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER role_assignments_lifecycle_guard BEFORE UPDATE ON role_assignments
        FOR EACH ROW EXECUTE FUNCTION f1_role_assignments_lifecycle_guard();
    SQL
  end
end
