# frozen_string_literal: true

# S-05-006 matched success commit + source-scope-interim-v1 materialization.
#
# On the first MATCHED ownership observation, CompleteVerificationAttempt commits, in
# one transaction, the multi-root success (contracts/S-05.json MTX-028/051; SCORE_
# EVIDENCE_MODEL.md :155; WORKFLOW_SPECIFICATIONS.md § WF-003): Verification Request
# `pending -> verified`/`matched` with the challenge material erased, `SourceVerified`,
# `Source.proposed -> verified` with its active scope policy pinned, and the atomic
# materialization of `source-scope-interim-v1`. None may appear without the others.
#
# This migration provides exactly what that commit needs, no more (owner Option A,
# ADR-042):
#
# 1. `source_scope_policies` — the MINIMAL, canonical-shaped Source Scope Policy table
#    (schemas/POSTGRESQL_SCHEMA.md; contracts/S-06.json MTX-029: one exact canonical
#    host, allowed schemes, allowed port set, included/excluded path prefixes, query
#    handling, policy version and scope; each version immutable, a new version inserted
#    rather than updated). It is modelled to the canonical schema so the S-06 Source
#    Scope sub-system (source_set_versions / source_set_memberships /
#    source_scope_change_requests) EXTENDS it rather than migrating it; the S-06
#    change-request/source-set machinery is NOT built here. `source_id` is nullable so
#    later Organization/Project-scope policies fit; the interim policy is source-scoped.
# 2. Relax the `sources` lifecycle guard for exactly `proposed -> verified` (its own
#    comment reserves that edge for S-05); every other Source transition stays refused.
# 3. Relax the `verification_requests` lifecycle guard to add `pending -> verified`
#    alongside the S-05-002 `pending -> expired` edge; every other transition stays
#    refused.
#
# The same single-edge discipline S-05-002 and S-05-005 use.
class CreateSourceScopePoliciesAndVerifyEdges < ActiveRecord::Migration[8.1]
  def up
    create_source_scope_policies
    relax_sources_guard
    relax_verification_requests_guard
  end

  def down
    execute "DROP TRIGGER IF EXISTS source_scope_policies_immutable ON source_scope_policies;"
    execute "DROP FUNCTION IF EXISTS f1_source_scope_policies_immutable();"
    execute "DROP TABLE IF EXISTS source_scope_policies;"
    restore_sources_guard
    restore_verification_requests_guard
  end

  private

  def create_source_scope_policies
    execute <<~SQL
      CREATE TABLE source_scope_policies (
        id                 uuid PRIMARY KEY,
        created_at         timestamptz(6) NOT NULL,
        correlation_id     uuid NOT NULL,
        schema_version     text NOT NULL
          CHECK (schema_version = 'source-scope-policy-v1'),
        organization_id    uuid NOT NULL,
        project_id         uuid NOT NULL,
        -- Nullable so later Organization/Project-scope policies fit the canonical
        -- shape; the interim policy is source-scoped (enforced below).
        source_id          uuid,
        policy_version     text NOT NULL,
        scope              text NOT NULL
          CHECK (scope IN ('organization','project','source')),
        canonical_host     text NOT NULL,
        -- cardinality (not array_length) so an empty array fails the CHECK: array_length
        -- of an empty array is NULL, and a NULL CHECK predicate passes.
        allowed_schemes    text[] NOT NULL
          CHECK (cardinality(allowed_schemes) >= 1),
        allowed_ports      integer[] NOT NULL
          CHECK (cardinality(allowed_ports) >= 1),
        include_prefixes   text[] NOT NULL
          CHECK (cardinality(include_prefixes) >= 1),
        exclude_prefixes   text[] NOT NULL DEFAULT '{}',
        -- 'retain_all' or an explicit retained-key allowlist (contracts/S-06.json
        -- MTX-029); the interim policy is 'retain_all'.
        query_handling     text NOT NULL,
        content_sha256     bytea NOT NULL
          CHECK (octet_length(content_sha256) = 32),
        -- A source-scoped policy names its Source; an org/project-scope policy does not.
        CONSTRAINT source_scope_policies_scope_source_agreement
          CHECK ((scope = 'source' AND source_id IS NOT NULL)
                 OR (scope <> 'source' AND source_id IS NULL)),
        CONSTRAINT source_scope_policies_org_id_unique UNIQUE (organization_id, id),
        -- One policy row per (Source, version): each version is immutable and a new
        -- version is inserted, so the success commit materializes the interim exactly
        -- once per Source.
        CONSTRAINT source_scope_policies_source_version_unique
          UNIQUE (organization_id, project_id, source_id, policy_version),
        -- The composite Source FK is enforced only when source_id is present
        -- (MATCH SIMPLE), preventing a cross-tenant or cross-Project link.
        CONSTRAINT source_scope_policies_source_fk
          FOREIGN KEY (organization_id, project_id, source_id)
          REFERENCES sources (organization_id, project_id, id)
      );
    SQL
    force_rls("source_scope_policies", using: "organization_id = f1_current_context_org()")
    create_immutability_guard
  end

  # T-IMM: a Source Scope Policy version is immutable once written; a correction is a
  # new version, never an edit. Defence in depth alongside the SELECT/INSERT-only grant.
  def create_immutability_guard
    execute <<~SQL
      CREATE FUNCTION f1_source_scope_policies_immutable() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        RAISE EXCEPTION 'source_scope_policy_immutable' USING ERRCODE = 'raise_exception';
      END;
      $$;
      CREATE TRIGGER source_scope_policies_immutable BEFORE UPDATE OR DELETE ON source_scope_policies
        FOR EACH ROW EXECUTE FUNCTION f1_source_scope_policies_immutable();
    SQL
  end

  def relax_sources_guard
    execute sources_guard("(OLD.state = 'proposed' AND NEW.state = 'verified')")
  end

  def restore_sources_guard
    execute sources_guard("FALSE")
  end

  # The sources guard with exactly the S-05 proposed -> verified edge permitted; the
  # tenant/Project identity and registration-provenance freezes are preserved verbatim.
  def sources_guard(allowed_edge)
    <<~SQL
      CREATE OR REPLACE FUNCTION f1_sources_lifecycle_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id THEN
          RAISE EXCEPTION 'source_tenant_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;

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

        IF NEW.state IS DISTINCT FROM OLD.state THEN
        -- S-05-006 relaxes exactly the proposed -> verified edge (matched success
        -- commit); the S-06 verified -> active/disabled/removed edges remain refused.
        IF NOT #{allowed_edge} THEN
          RAISE EXCEPTION 'source_lifecycle_transition_unavailable % -> %', OLD.state, NEW.state
            USING ERRCODE = 'raise_exception';
        END IF;
      END IF;

        RETURN NEW;
      END;
      $$;
    SQL
  end

  def relax_verification_requests_guard
    execute verification_requests_guard(
      "(OLD.request_status = 'pending' AND NEW.request_status IN ('expired','verified'))"
    )
  end

  def restore_verification_requests_guard
    execute verification_requests_guard("(OLD.request_status = 'pending' AND NEW.request_status = 'expired')")
  end

  # The verification_requests guard with the pending -> {expired, verified} edges
  # permitted; the tenant identity and issuance-facts freezes are preserved verbatim.
  def verification_requests_guard(allowed_edges)
    <<~SQL
      CREATE OR REPLACE FUNCTION f1_verification_requests_lifecycle_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.source_id IS DISTINCT FROM OLD.source_id THEN
          RAISE EXCEPTION 'verification_request_tenant_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        IF NEW.schema_version IS DISTINCT FROM OLD.schema_version
           OR NEW.request_initiator_account_id IS DISTINCT FROM OLD.request_initiator_account_id
           OR NEW.method IS DISTINCT FROM OLD.method
           OR NEW.canonical_host IS DISTINCT FROM OLD.canonical_host
           OR NEW.challenge_token_sha256 IS DISTINCT FROM OLD.challenge_token_sha256
           OR NEW.idempotency_key_digest IS DISTINCT FROM OLD.idempotency_key_digest
           OR NEW.initial_challenge_delivered_at_utc IS DISTINCT FROM OLD.initial_challenge_delivered_at_utc
           OR NEW.issued_at_utc IS DISTINCT FROM OLD.issued_at_utc
           OR NEW.expires_at_utc IS DISTINCT FROM OLD.expires_at_utc THEN
          RAISE EXCEPTION 'verification_request_issuance_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        IF NEW.request_status IS DISTINCT FROM OLD.request_status THEN
        -- S-05-002 relaxed pending -> expired; S-05-006 adds pending -> verified
        -- (matched success). Every other transition remains unavailable.
        IF NOT #{allowed_edges} THEN
          RAISE EXCEPTION 'verification_request_transition_unavailable % -> %', OLD.request_status, NEW.request_status
            USING ERRCODE = 'raise_exception';
        END IF;
      END IF;

        RETURN NEW;
      END;
      $$;
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
