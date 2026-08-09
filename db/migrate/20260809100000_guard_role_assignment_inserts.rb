# frozen_string_literal: true

# FU-59 (round-19 adversarial finding R-ADV-3, ADR-138). `role_assignments`
# carried exactly one trigger, `role_assignments_lifecycle_guard BEFORE UPDATE FOR
# EACH ROW`. There was no INSERT trigger, and the only CHECK touching the allowlist
# for a non-pending row was the 30-day expiry rule, so an INSERT could mint a row
# with `status='active'` carrying any `protected_permission_allowlist` — including
# all 15 PROTECTED keys — having passed through no approval at all.
#
# The gap was contained but real. It did not reach the protected writes, because
# the capability CTE joins on the carried `g.id = ra.id AND g.state_version =
# ra.state_version` and an INSERT mints a new id; and `f1_runtime` holds no DELETE,
# so delete-and-reinsert was unavailable. What was NOT true is the claim round 19
# rested on: that this guard was an INDEPENDENT ground for the safety of the
# unbound protected limb. It was not. Dual control at INSERT time was enforced in
# Ruby alone — `RoleAssignmentStore#insert` takes the allowlist as a free
# parameter, and only the discipline of its single caller kept it `[]`.
#
# The rule enforced here is the one the UPDATE guard already states, applied to the
# operation that was missing it: the approved protected authority is written
# EXACTLY ONCE, by the `pending -> active` transition that makes the grant
# effective. A row therefore cannot be born holding it. This narrows no ratified
# path — WF-001's genesis OrganizationAdmin and every WF-003 invitation insert an
# empty allowlist, and activation still writes it through the existing guard.
#
# It has to be a trigger. A CHECK cannot distinguish INSERT from UPDATE, so a CHECK
# strong enough to close this would also forbid the ratified activation.
class GuardRoleAssignmentInserts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_role_assignments_insert_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        -- ":314 sorted explicit protected-permission allowlist" is populated at the
        -- moment the grant becomes effective, and :333 makes that moment the
        -- approval. An inserted row has had no approval, whatever its status says.
        IF jsonb_array_length(NEW.protected_permission_allowlist) <> 0 THEN
          RAISE EXCEPTION 'role_assignment_allowlist_requires_activation'
            USING ERRCODE = 'raise_exception';
        END IF;

        RETURN NEW;
      END;
      $$;
    SQL

    execute <<~SQL
      CREATE TRIGGER role_assignments_insert_guard
        BEFORE INSERT ON role_assignments
        FOR EACH ROW EXECUTE FUNCTION f1_role_assignments_insert_guard();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS role_assignments_insert_guard ON role_assignments;"
    execute "DROP FUNCTION IF EXISTS f1_role_assignments_insert_guard();"
  end
end
