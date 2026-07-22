# frozen_string_literal: true

# Correction to the Role Assignment lifecycle guard added in 7527763.
#
# That guard froze `protected_permission_allowlist` against ANY update, which is
# one step too strong: ":314 sorted explicit protected-permission allowlist" is
# populated at the moment the grant becomes effective, and :333 makes that moment
# the approval. Freezing it from insert made the ratified activation
# unexpressible — a pending Assignment necessarily carries an empty allowlist,
# because nothing is approved yet.
#
# The correct invariant is narrower and stronger where it matters: the allowlist
# may be written EXACTLY ONCE, on the pending -> active transition, and never
# afterwards. An active, rejected, revoked or expired Assignment's approved
# authority is immutable history, and a pending Assignment cannot be given
# authority without a decision.
class AllowAllowlistWriteAtActivation < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_role_assignments_lifecycle_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      DECLARE allowed text[];
      BEGIN
        -- The approved protected authority is written once, by the transition that
        -- makes the grant effective, and is immutable from then on. Step 4 of the
        -- effective-permission algorithm reads it, so a later edit would silently
        -- re-authorize history.
        IF NEW.protected_permission_allowlist IS DISTINCT FROM OLD.protected_permission_allowlist THEN
          IF NOT (OLD.status = 'pending' AND NEW.status = 'active') THEN
            RAISE EXCEPTION 'role_assignment_allowlist_immutable' USING ERRCODE = 'raise_exception';
          END IF;
          IF jsonb_array_length(OLD.protected_permission_allowlist) <> 0 THEN
            RAISE EXCEPTION 'role_assignment_allowlist_immutable' USING ERRCODE = 'raise_exception';
          END IF;
        END IF;

        -- A pending Assignment "confers no permission while pending" (:316), so it
        -- may never carry approved protected authority.
        IF NEW.status = 'pending' AND jsonb_array_length(NEW.protected_permission_allowlist) <> 0 THEN
          RAISE EXCEPTION 'role_assignment_pending_confers_nothing' USING ERRCODE = 'raise_exception';
        END IF;

        IF NEW.bootstrap_admin_exception IS DISTINCT FROM OLD.bootstrap_admin_exception THEN
          RAISE EXCEPTION 'role_assignment_bootstrap_exception_immutable' USING ERRCODE = 'raise_exception';
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
    SQL
    # A pending Assignment may not be inserted carrying approved authority either.
    execute <<~SQL
      ALTER TABLE role_assignments
        ADD CONSTRAINT role_assignment_pending_has_no_allowlist CHECK (
          status <> 'pending' OR jsonb_array_length(protected_permission_allowlist) = 0
        );
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "restoring the insert-time allowlist freeze would make the ratified activation unexpressible"
  end
end
