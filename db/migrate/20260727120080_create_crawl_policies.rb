# frozen_string_literal: true

# S-07-001 Crawl Policy (contracts/S-07.json MTX-030 policy limb / MTX-059 PRULE-008;
# WORKFLOW_SPECIFICATIONS.md § Interim Crawl Policy crawl-policy-v1 :423-458; DECISIONS
# ADR-068 owner D1: a DEDICATED immutable versioned policy table, continuing the
# access_policies / source_scope_policies convention rather than the deferred generic
# policy_artifacts framework).
#
# `crawl_policies` holds Organization- and Project-scoped NARROWED crawl policy versions.
# The global safety ceiling is the frozen `crawl-policy-v1` constant (Workflows::Wf005::
# CrawlPolicy::GLOBAL_CEILING), owner-approved as the interim (HD-S07-D1); Org/Project rows
# may only narrow it. Content (the normalized bounds + digest + scope/version/actor) is
# immutable once written; the only mutation permitted is the single active -> superseded
# lifecycle edge at the activation of a newer version (the policy_artifacts supersession
# shape). Semantic narrowing validation (completeness, soft<=hard, at-or-below parent+global)
# is the ActivateCrawlPolicy handler's job and is asserted by its specs; the DB enforces
# structure, one-active-per-scope, immutability, and RLS.
class CreateCrawlPolicies < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE crawl_policies (
        id                       uuid PRIMARY KEY,
        state_version            bigint NOT NULL DEFAULT 0,
        created_at               timestamptz(6) NOT NULL,
        updated_at               timestamptz(6) NOT NULL,
        correlation_id           uuid NOT NULL,
        schema_version           text NOT NULL CHECK (schema_version = 'crawl-policy-v1'),
        organization_id          uuid NOT NULL,
        project_id               uuid,
        scope                    text NOT NULL CHECK (scope IN ('organization','project')),
        policy_version           text NOT NULL,
        state                    text NOT NULL CHECK (state IN ('active','superseded')),
        supersedes_id            uuid,
        activated_by_account_id  uuid NOT NULL,
        normalized_bounds        jsonb NOT NULL CHECK (jsonb_typeof(normalized_bounds) = 'object'),
        content_sha256           bytea NOT NULL CHECK (octet_length(content_sha256) = 32),
        superseded_at            timestamptz(6),
        CONSTRAINT crawl_policies_scope_project_agreement CHECK (
          (scope = 'organization' AND project_id IS NULL) OR
          (scope = 'project' AND project_id IS NOT NULL)
        ),
        CONSTRAINT crawl_policies_terminal_shape CHECK (
          (state = 'active' AND superseded_at IS NULL) OR
          (state = 'superseded' AND superseded_at IS NOT NULL)
        ),
        CONSTRAINT crawl_policies_project_fk FOREIGN KEY (organization_id, project_id)
          REFERENCES projects (organization_id, id)
      );
      -- Exactly one active crawl policy per (Organization, scope, Project); org-scope rows
      -- (project_id NULL) collapse to the zero-uuid sentinel so one active org policy exists.
      CREATE UNIQUE INDEX crawl_policies_active_unique ON crawl_policies
        (organization_id, scope, COALESCE(project_id, '00000000-0000-0000-0000-000000000000'::uuid))
        WHERE state = 'active';
      CREATE UNIQUE INDEX crawl_policies_version_unique ON crawl_policies
        (organization_id, scope, COALESCE(project_id, '00000000-0000-0000-0000-000000000000'::uuid), policy_version);
      CREATE INDEX crawl_policies_org_scope ON crawl_policies (organization_id, scope, project_id);
    SQL

    force_rls("crawl_policies", using: "organization_id = f1_current_context_org()")
    create_lifecycle_guard
  end

  def down
    execute "DROP TRIGGER IF EXISTS crawl_policies_guard ON crawl_policies;"
    execute "DROP FUNCTION IF EXISTS f1_crawl_policies_guard();"
    execute "DROP TABLE IF EXISTS crawl_policies;"
  end

  private

  def force_rls(table, using:, check: nil)
    execute <<~SQL
      ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
      ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;
      CREATE POLICY #{table}_context ON #{table}
        USING (#{using}) WITH CHECK (#{check || using});
      REVOKE ALL ON #{table} FROM PUBLIC;
    SQL
  end

  # T-MUT with immutable content: the only permitted change to an active row is the single
  # active -> superseded lifecycle edge (stamping superseded_at); every content column is
  # frozen, a superseded row is terminal, and DELETE is refused.
  def create_lifecycle_guard
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_crawl_policies_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'crawl_policy_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        -- A superseded policy version is terminal: no field may change once it leaves active.
        IF OLD.state <> 'active' THEN
          RAISE EXCEPTION 'crawl_policy_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.schema_version IS DISTINCT FROM OLD.schema_version
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.scope IS DISTINCT FROM OLD.scope
           OR NEW.policy_version IS DISTINCT FROM OLD.policy_version
           OR NEW.supersedes_id IS DISTINCT FROM OLD.supersedes_id
           OR NEW.activated_by_account_id IS DISTINCT FROM OLD.activated_by_account_id
           OR NEW.normalized_bounds IS DISTINCT FROM OLD.normalized_bounds
           OR NEW.content_sha256 IS DISTINCT FROM OLD.content_sha256
           OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id
           OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
          RAISE EXCEPTION 'crawl_policy_facts_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        -- The only permitted transition of an active row is to superseded.
        IF NEW.state <> 'superseded' THEN
          RAISE EXCEPTION 'crawl_policy_transition_unavailable % -> %', OLD.state, NEW.state
            USING ERRCODE = 'raise_exception';
        END IF;

        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER crawl_policies_guard
        BEFORE UPDATE OR DELETE ON crawl_policies
        FOR EACH ROW EXECUTE FUNCTION f1_crawl_policies_guard();
    SQL
  end
end
