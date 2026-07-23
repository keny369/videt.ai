# frozen_string_literal: true

# S-03 Project Setup profile schema (WORKFLOW_SPECIFICATIONS.md :657 the WF-002
# creation body; specification/volume-ii/API_CONTRACTS.md :371-372 the
# `ProjectProfile`/`LocalBusinessProfile` DTOs; schemas/POSTGRESQL_SCHEMA.md :283
# "local-applicability/profile fields"; contracts/S-03.json MTX-027, MTX-054).
#
# S-02 genesis created the `projects` table as the "draft-capable minimum" and
# deliberately deferred the local-applicability/profile fields to this slice
# (see 20260723120019_create_organization_genesis.rb :239-241). This migration
# adds exactly those fields for `Workflows::Wf002::CreateProject`, and NOTHING
# for the OD-014 withheld limb: the `state` CHECK already recognizes `paused`
# and `archived` for reading, and this migration adds no path that enters them.
#
# The columns are NULLABLE by design: the WF-001 self-service first Project is a
# reduced body (display name + objective only) and carries none of them, so the
# genesis INSERT — which lists its columns explicitly — is unchanged and its
# rows validate with every new column NULL. The XOR shape CHECK admits exactly
# three row shapes: the reduced genesis body (all profile fields NULL), a full
# ProjectProfile with a Local Business Profile, or a full ProjectProfile with a
# local-presence reason.
#
# The whole creation profile is immutable (WORKFLOW_SPECIFICATIONS.md :671
# "a changed address, telephone, service-area set, or Organization display name
# requires a new Project"), and — because the WF-002 draft->active transition is
# gated on at least one active same-Project Source (CAP-003/PRULE-004), whose
# Source aggregate is owned by S-04/S-05/S-06 and is not built — no path may
# change a Project's `state` in this baseline. Both facts are enforced by a
# BEFORE UPDATE guard so they are properties of the database, not of one handler.
class CreateProjectSetupProfile < ActiveRecord::Migration[8.1]
  def up
    add_profile_columns
    add_profile_shape_check
    create_lifecycle_guard
  end

  def down
    execute "DROP TRIGGER IF EXISTS projects_lifecycle_guard ON projects;"
    execute "DROP FUNCTION IF EXISTS f1_projects_lifecycle_guard();"
    execute "ALTER TABLE projects DROP CONSTRAINT IF EXISTS projects_local_profile_shape;"
    execute <<~SQL
      ALTER TABLE projects
        DROP COLUMN IF EXISTS project_profile_schema_version,
        DROP COLUMN IF EXISTS local_presence_applicable,
        DROP COLUMN IF EXISTS local_presence_reason,
        DROP COLUMN IF EXISTS local_business_profile,
        DROP COLUMN IF EXISTS local_business_profile_content_sha256,
        DROP COLUMN IF EXISTS profile_attesting_account_id,
        DROP COLUMN IF EXISTS profile_committed_at;
    SQL
  end

  private

  # The immutable ProjectProfile (`project-profile-v1`). The Local Business
  # Profile body is stored as its canonical `local-business-profile-v1` object in
  # `jsonb`, mirroring how `organizations.profile` stores `organization-profile-v1`;
  # its 32-byte canonical-content SHA-256 is stored relationally for integrity.
  # `profile_attesting_account_id` and `profile_committed_at` record who attested
  # the profile and the server commit time (WORKFLOW_SPECIFICATIONS.md :657).
  def add_profile_columns
    execute <<~SQL
      ALTER TABLE projects
        ADD COLUMN project_profile_schema_version text
          CHECK (project_profile_schema_version IS NULL OR project_profile_schema_version = 'project-profile-v1'),
        ADD COLUMN local_presence_applicable boolean,
        ADD COLUMN local_presence_reason text
          CHECK (local_presence_reason IS NULL OR char_length(local_presence_reason) BETWEEN 20 AND 500),
        ADD COLUMN local_business_profile jsonb,
        ADD COLUMN local_business_profile_content_sha256 bytea
          CHECK (local_business_profile_content_sha256 IS NULL
                 OR octet_length(local_business_profile_content_sha256) = 32),
        ADD COLUMN profile_attesting_account_id uuid,
        ADD COLUMN profile_committed_at timestamptz(6);
    SQL
  end

  # The exact WF-002 applicability contract (WORKFLOW_SPECIFICATIONS.md :657):
  # applicable true requires a Local Business Profile and null reason; applicable
  # false requires a reason and null profile; both require the profile metadata.
  # A Project whose `local_presence_applicable` is NULL is the reduced genesis
  # body and carries no profile metadata at all.
  def add_profile_shape_check
    execute <<~SQL
      ALTER TABLE projects
        ADD CONSTRAINT projects_local_profile_shape CHECK (
          (
            local_presence_applicable IS NULL
            AND local_presence_reason IS NULL
            AND local_business_profile IS NULL
            AND local_business_profile_content_sha256 IS NULL
            AND project_profile_schema_version IS NULL
            AND profile_attesting_account_id IS NULL
            AND profile_committed_at IS NULL
          )
          OR (
            local_presence_applicable = true
            AND project_profile_schema_version IS NOT NULL
            AND profile_attesting_account_id IS NOT NULL
            AND profile_committed_at IS NOT NULL
            AND local_presence_reason IS NULL
            AND local_business_profile IS NOT NULL
            AND local_business_profile_content_sha256 IS NOT NULL
          )
          OR (
            local_presence_applicable = false
            AND project_profile_schema_version IS NOT NULL
            AND profile_attesting_account_id IS NOT NULL
            AND profile_committed_at IS NOT NULL
            AND local_presence_reason IS NOT NULL
            AND local_business_profile IS NULL
            AND local_business_profile_content_sha256 IS NULL
          )
        );
    SQL
  end

  def create_lifecycle_guard
    execute <<~SQL
      CREATE FUNCTION f1_projects_lifecycle_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        -- DM-REQ (011 DOMAIN_MODEL.md :118) "Project MUST belong to exactly one
        -- Organization": a Project's Organization and identity are fixed for life.
        IF NEW.organization_id IS DISTINCT FROM OLD.organization_id THEN
          RAISE EXCEPTION 'project_organization_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        -- WF-002 State Transitions define Project.Draft -> Project.Active only, and
        -- that transition is gated on >=1 active same-Project Source (CAP-003,
        -- PRULE-004). The Source aggregate is owned by S-04/S-05/S-06 and is not
        -- built, so activation is not implementable in this baseline; Project
        -- pause/resume/archive are withheld under OD-014. No path may change a
        -- Project's state here. The activation slice will relax this guard to
        -- permit the single draft->active edge under its ratified prerequisites.
        IF NEW.state IS DISTINCT FROM OLD.state THEN
          RAISE EXCEPTION 'project_lifecycle_transition_unavailable % -> %', OLD.state, NEW.state
            USING ERRCODE = 'raise_exception';
        END IF;

        -- ":671 The baseline Local Business Profile is immutable with the Project
        -- creation profile ... requires a new Project." The whole creation profile
        -- is frozen at creation.
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
      CREATE TRIGGER projects_lifecycle_guard BEFORE UPDATE ON projects
        FOR EACH ROW EXECUTE FUNCTION f1_projects_lifecycle_guard();
    SQL
  end
end
