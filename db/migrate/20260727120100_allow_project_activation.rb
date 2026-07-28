# frozen_string_literal: true

# S-03 ActivateProject (contracts/S-03.json MTX-027 activation limb; WORKFLOW_SPECIFICATIONS.md
# § WF-002 :651-666; DECISIONS ADR-072 owner D3). The projects lifecycle guard
# (20260723120020) refused EVERY Project state change with an explicit note that "the activation
# slice will relax this guard to permit the single draft->active edge under its ratified
# prerequisites"; those prerequisites (the Source aggregate — an active same-Project Source) are
# now satisfiable since S-06-006. This migration relaxes the guard to permit EXACTLY the
# `draft -> active` edge; the Organization-identity and creation-profile freezes are preserved
# verbatim, and pause/resume/archive remain refused (withheld under OD-014). No table or column
# is added (contract migration row: "No schema object is added").
class AllowProjectActivation < ActiveRecord::Migration[8.1]
  def up
    write_guard("(OLD.state = 'draft' AND NEW.state = 'active')")
  end

  def down
    # Restore the pre-S-03 form: no Project state change permitted.
    write_guard("FALSE")
  end

  private

  def write_guard(allowed_edge)
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_projects_lifecycle_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
          RAISE EXCEPTION 'project_organization_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        -- S-03 permits exactly Project.Draft -> Project.Active (gated by the ActivateProject
        -- handler on >=1 active same-Project Source); pause/resume/archive remain refused
        -- (OD-014 pending).
        IF NEW.state IS DISTINCT FROM OLD.state THEN
        IF NOT #{allowed_edge} THEN
          RAISE EXCEPTION 'project_lifecycle_transition_unavailable % -> %', OLD.state, NEW.state
            USING ERRCODE = 'raise_exception';
        END IF;
      END IF;

        IF NEW.display_name IS DISTINCT FROM OLD.display_name
           OR NEW.locale IS DISTINCT FROM OLD.locale
           OR NEW.time_zone IS DISTINCT FROM OLD.time_zone
           OR NEW.objective IS DISTINCT FROM OLD.objective
           OR NEW.project_profile_schema_version IS DISTINCT FROM OLD.project_profile_schema_version
           OR NEW.local_presence_applicable IS DISTINCT FROM OLD.local_presence_applicable
           OR NEW.local_presence_reason IS DISTINCT FROM OLD.local_presence_reason
           OR NEW.local_business_profile IS DISTINCT FROM OLD.local_business_profile
           OR NEW.local_business_profile_content_sha256 IS DISTINCT FROM OLD.local_business_profile_content_sha256
           OR NEW.profile_attesting_account_id IS DISTINCT FROM OLD.profile_attesting_account_id
           OR NEW.profile_committed_at IS DISTINCT FROM OLD.profile_committed_at THEN
          RAISE EXCEPTION 'project_profile_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        RETURN NEW;
      END;
      $$;
    SQL
  end
end
