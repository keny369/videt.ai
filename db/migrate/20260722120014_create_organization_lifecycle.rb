# frozen_string_literal: true

# Schema for the WF-013 Organization lifecycle (WORKFLOW_SPECIFICATIONS.md :230
# the Organization record, :270-289 the ratified `reactivation-proof-v1` decision;
# 016 STATE_MODEL.md :97 the Organization row; contracts/S-23.json MTX-038
# "Organization suspension: one transaction changing active to suspended,
# recording the reason, incrementing both versions, revoking every active human
# Session and preventing new scheduled work").
#
# Two fields :230 names and the table lacked: the reactivation timestamp and the
# nullable lifecycle reason.
#
# The rest is enforcement. The authorization epoch is "monotonically increasing"
# (:230) and is THE serialization point for effective access
# (contracts/S-23.json concurrency), so a trigger refuses any decrease — including
# from an owner connection — and refuses to let the lifecycle status change
# without the epoch advancing. Those two facts are what make "authority
# invalidated at the suspension boundary" a property of the database rather than
# a property of one handler remembering to do both.
class CreateOrganizationLifecycle < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE organizations
        ADD COLUMN reactivated_at   timestamptz(6),
        ADD COLUMN lifecycle_reason text
          CHECK (lifecycle_reason IS NULL OR char_length(lifecycle_reason) BETWEEN 1 AND 2000);
    SQL
    execute <<~SQL
      ALTER TABLE organizations
        ADD CONSTRAINT organization_suspended_has_time CHECK (
          status <> 'suspended' OR suspended_at IS NOT NULL
        );
    SQL
    create_guard_trigger
  end

  def down
    execute "DROP TRIGGER IF EXISTS organizations_lifecycle_guard ON organizations;"
    execute "DROP FUNCTION IF EXISTS f1_organizations_lifecycle_guard();"
    execute "ALTER TABLE organizations DROP CONSTRAINT IF EXISTS organization_suspended_has_time;"
    execute "ALTER TABLE organizations DROP COLUMN IF EXISTS reactivated_at;"
    execute "ALTER TABLE organizations DROP COLUMN IF EXISTS lifecycle_reason;"
  end

  private

  def create_guard_trigger
    execute <<~SQL
      CREATE FUNCTION f1_organizations_lifecycle_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      DECLARE allowed text[];
      BEGIN
        -- ":230 monotonically increasing authorization epoch". An epoch that could
        -- go backwards would let a previously issued authority become current
        -- again, so no path may decrease it.
        IF NEW.authorization_epoch < OLD.authorization_epoch THEN
          RAISE EXCEPTION 'organization_authorization_epoch_regressed' USING ERRCODE = 'raise_exception';
        END IF;

        -- The lifecycle status and the epoch move together. Suspension that did not
        -- advance the epoch, or an epoch advance that silently changed the status,
        -- would be exactly the split-brain result the transaction boundary forbids.
        IF NEW.status IS DISTINCT FROM OLD.status
           AND NEW.authorization_epoch = OLD.authorization_epoch THEN
          RAISE EXCEPTION 'organization_status_changed_without_epoch_advance' USING ERRCODE = 'raise_exception';
        END IF;

        -- 016 STATE_MODEL.md :97: pending to active; active to suspended; suspended
        -- to active; active to closed; suspended to closed. Nothing else, and
        -- closed never reopens.
        allowed := CASE OLD.status
                     WHEN 'pending'   THEN ARRAY['pending','active']
                     WHEN 'active'    THEN ARRAY['active','suspended','closed']
                     WHEN 'suspended' THEN ARRAY['suspended','active','closed']
                     ELSE ARRAY[OLD.status]
                   END;
        IF NOT (NEW.status = ANY (allowed)) THEN
          RAISE EXCEPTION 'organization_illegal_transition % -> %', OLD.status, NEW.status
            USING ERRCODE = 'raise_exception';
        END IF;

        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER organizations_lifecycle_guard BEFORE UPDATE ON organizations
        FOR EACH ROW EXECUTE FUNCTION f1_organizations_lifecycle_guard();
    SQL
  end
end
