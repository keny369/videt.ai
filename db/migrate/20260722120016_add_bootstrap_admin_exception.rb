# frozen_string_literal: true

# The expressly defined first-admin/bootstrap exception
# (WORKFLOW_SPECIFICATIONS.md :329 step 4 "require any protected permission to
# appear in the Assignment's approved protected allowlist OR IN THE EXPRESSLY
# DEFINED FIRST-ADMIN/BOOTSTRAP EXCEPTION"; :333 "The one first OrganizationAdmin
# Assignment and `access-policy-v1` activation created atomically by WF-001 under
# a valid unconsumed Bootstrap Grant are the sole tenant-bootstrap exceptions").
#
# Without this marker the exception is unrepresentable, and a freshly bootstrapped
# tenant would have no Account able to grant anything: `role.manage` is protected,
# a protected permission needs an approved allowlist, and the only approver able
# to approve one would itself need a grant nobody can make. The marker is the
# ratified way out of that circle, and it is deliberately narrow — one Assignment
# per Organization, OrganizationAdmin only, and never settable on a later grant.
class AddBootstrapAdminException < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE role_assignments
        ADD COLUMN bootstrap_admin_exception boolean NOT NULL DEFAULT false,
        ADD CONSTRAINT role_assignment_bootstrap_exception_is_admin CHECK (
          bootstrap_admin_exception = false OR canonical_role = 'OrganizationAdmin'
        );
      -- ":333 The ONE first OrganizationAdmin Assignment".
      CREATE UNIQUE INDEX one_bootstrap_admin_per_organization
        ON role_assignments (organization_id) WHERE bootstrap_admin_exception;
    SQL
    # The marker is set at creation and never afterwards: it is a fact about how
    # the Assignment came into existence.
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_role_assignments_lifecycle_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      DECLARE allowed text[];
      BEGIN
        IF NEW.protected_permission_allowlist IS DISTINCT FROM OLD.protected_permission_allowlist THEN
          RAISE EXCEPTION 'role_assignment_allowlist_immutable' USING ERRCODE = 'raise_exception';
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
  end

  def down
    execute "DROP INDEX IF EXISTS one_bootstrap_admin_per_organization;"
    execute "ALTER TABLE role_assignments DROP COLUMN IF EXISTS bootstrap_admin_exception;"
  end
end
