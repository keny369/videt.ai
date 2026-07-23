# frozen_string_literal: true

# S-04 Source Onboarding schema (schemas/POSTGRESQL_SCHEMA.md :284 the canonical
# `sources` table; WORKFLOW_SPECIFICATIONS.md :398-408 the `source-registration-v1`
# contract; CAP-004 CAPABILITY_MODEL.md :86-106; contracts/S-04.json MTX-004).
#
# `sources` is the first Project-owned table: per the tenancy rule
# (POSTGRESQL_SCHEMA.md :128) a Project-owned parent carries `project_id NOT NULL`,
# exposes `UNIQUE (organization_id, project_id, id)`, and its direct Project
# reference is the composite `(organization_id, project_id) -> projects
# (organization_id, id)` — so a same-Organization cross-Project link is prevented
# by the database rather than an application assertion.
#
# A Source is its own aggregate root, not a child of Project (S-04.json
# aggregate_boundary). Registration creates exactly one Source in `proposed` with
# its immutable provenance and the ratified `(organization_id, project_id,
# canonical_host)` uniqueness over every Source not `removed`; a committed
# `removed` Source never blocks re-registration, which is why that uniqueness is a
# partial index rather than a plain constraint.
#
# This migration adds NOTHING beyond registration. The Source state CHECK
# recognizes `verified`, `active`, `disabled` and `removed` because the state
# model defines them, but no path enters them here: verification (proposed ->
# verified) is S-05/WF-003 and scope/lifecycle (verified -> active, active ->
# disabled, disabled -> active/removed) is S-06/WF-004. Registration "never
# verifies, activates, crawls or creates Evidence" (APPLICATION_LAYER.md :612), so
# the lifecycle guard freezes the registration facts and refuses every state
# transition until those slices land and relax exactly their ratified edges. The
# Source-set/membership machinery (`source_set_versions`, `source_set_memberships`)
# and the verification/scope tables are S-05/S-06 and are NOT created here.
class CreateSourceOnboarding < ActiveRecord::Migration[8.1]
  def up
    create_sources
    create_lifecycle_guard
  end

  def down
    execute "DROP TRIGGER IF EXISTS sources_lifecycle_guard ON sources;"
    execute "DROP FUNCTION IF EXISTS f1_sources_lifecycle_guard();"
    execute "DROP TABLE IF EXISTS sources;"
  end

  private

  def create_sources
    execute <<~SQL
      CREATE TABLE sources (
        id                                     uuid PRIMARY KEY,
        state_version                          bigint NOT NULL DEFAULT 0,
        lock_version                           bigint NOT NULL DEFAULT 0,
        created_at                             timestamptz(6) NOT NULL,
        updated_at                             timestamptz(6) NOT NULL,
        correlation_id                         uuid NOT NULL,
        organization_id                        uuid NOT NULL,
        project_id                             uuid NOT NULL,
        submitted_root_uri                     text NOT NULL,
        canonical_root_uri                     text NOT NULL,
        canonical_host                         text NOT NULL,
        registration_schema_version            text NOT NULL
          CHECK (registration_schema_version = 'source-registration-v1'),
        host_normalization_version             text NOT NULL
          CHECK (host_normalization_version = 'ascii-host-v1'),
        registration_origin                    text NOT NULL
          CHECK (registration_origin = 'human_command'),
        registering_account_id                 uuid NOT NULL,
        registration_command_id                uuid NOT NULL,
        registration_idempotency_key_digest    bytea NOT NULL
          CHECK (octet_length(registration_idempotency_key_digest) = 32),
        registration_authorization_decision_id uuid NOT NULL,
        registered_at                          timestamptz(6) NOT NULL,
        state                                  text NOT NULL
          CHECK (state IN ('proposed','verified','active','disabled','removed')),
        current_scope_policy_id                uuid,
        verified_at                            timestamptz(6),
        activated_at                           timestamptz(6),
        disabled_at                            timestamptz(6),
        removed_at                             timestamptz(6),
        lifecycle_reason                       text
          CHECK (lifecycle_reason IS NULL OR char_length(lifecycle_reason) BETWEEN 1 AND 2000),
        CONSTRAINT sources_org_project_id_unique UNIQUE (organization_id, project_id, id),
        CONSTRAINT sources_project_fk FOREIGN KEY (organization_id, project_id)
          REFERENCES projects (organization_id, id)
      );
      CREATE UNIQUE INDEX sources_nonremoved_host_unique
        ON sources (organization_id, project_id, canonical_host) WHERE state <> 'removed';
    SQL
    force_rls("sources", using: "organization_id = f1_current_context_org()")
  end

  # The registration facts are the Source's immutable provenance, and no state
  # transition exists in this baseline. Both are database properties.
  def create_lifecycle_guard
    execute <<~SQL
      CREATE FUNCTION f1_sources_lifecycle_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        -- 011 DOMAIN_MODEL.md :119 "Source MUST belong to exactly one Project":
        -- the tenant/Project identity is fixed for life.
        IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id THEN
          RAISE EXCEPTION 'source_tenant_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        -- ":402 immutable registration provenance". The submitted/canonical URIs,
        -- canonical host, registration and normalization versions, and the seven
        -- provenance fields are frozen at registration.
        IF NEW.submitted_root_uri IS DISTINCT FROM OLD.submitted_root_uri
           OR NEW.canonical_root_uri IS DISTINCT FROM OLD.canonical_root_uri
           OR NEW.canonical_host IS DISTINCT FROM OLD.canonical_host
           OR NEW.registration_schema_version IS DISTINCT FROM OLD.registration_schema_version
           OR NEW.host_normalization_version IS DISTINCT FROM OLD.host_normalization_version
           OR NEW.registration_origin IS DISTINCT FROM OLD.registration_origin
           OR NEW.registering_account_id IS DISTINCT FROM OLD.registering_account_id
           OR NEW.registration_command_id IS DISTINCT FROM OLD.registration_command_id
           OR NEW.registration_idempotency_key_digest IS DISTINCT FROM OLD.registration_idempotency_key_digest
           OR NEW.registration_authorization_decision_id IS DISTINCT FROM OLD.registration_authorization_decision_id
           OR NEW.registered_at IS DISTINCT FROM OLD.registered_at THEN
          RAISE EXCEPTION 'source_registration_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        -- Source lifecycle transitions are owned by S-05 (proposed -> verified) and
        -- S-06 (verified -> active; active -> disabled; disabled -> active/removed),
        -- neither built. No path may change a Source's state in this baseline; each
        -- of those slices will relax exactly its ratified edge.
        IF NEW.state IS DISTINCT FROM OLD.state THEN
          RAISE EXCEPTION 'source_lifecycle_transition_unavailable % -> %', OLD.state, NEW.state
            USING ERRCODE = 'raise_exception';
        END IF;

        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER sources_lifecycle_guard BEFORE UPDATE ON sources
        FOR EACH ROW EXECUTE FUNCTION f1_sources_lifecycle_guard();
    SQL
  end

  def force_rls(table, using:, check: nil)
    execute <<~SQL
      ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
      ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;
      CREATE POLICY #{table}_context ON #{table}
        USING (#{using}) WITH CHECK (#{check || using});
      REVOKE ALL ON #{table} FROM PUBLIC;
    SQL
  end
end
