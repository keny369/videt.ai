# frozen_string_literal: true

# S-06-003 source_scope_change_requests + ProposeSourceScopeChange (pending path).
#
# The Source Scope Change Request aggregate (schemas/POSTGRESQL_SCHEMA.md :289;
# WORKFLOW_SPECIFICATIONS.md § Source Scope Change Contract :414; contracts/S-06.json
# MTX-029). A request carries the Organization/Project/Source, the requester, the
# EXPECTED active policy version and its content hash, the PROPOSED normalized
# host/path/query rules and their content hash, a 20-2,000 character request reason,
# `requested_at_utc`, `due_at_utc = requested_at_utc + 24h`, the state
# (`pending`/`approved`/`rejected`/`canceled`/`expired`), nullable decision
# actor/time/reason and activated policy version, the idempotency key digest, and the
# state version. Every terminal request is immutable.
#
# This tranche (S-06-003) creates PENDING requests only. The lifecycle guard therefore
# refuses EVERY state transition and freezes the tenant identity, the proposed rules and
# the issuance facts once written; S-06-004 (Decide + atomic contraction) and S-06-005
# (Expire) relax exactly the edges they own, the same single-edge discipline the
# verification_requests guard uses.
class CreateSourceScopeChangeRequests < ActiveRecord::Migration[8.1]
  def up
    create_table_sql
    force_rls
    create_lifecycle_guard("FALSE")
  end

  def down
    execute "DROP TRIGGER IF EXISTS source_scope_change_requests_guard ON source_scope_change_requests;"
    execute "DROP FUNCTION IF EXISTS f1_source_scope_change_requests_guard();"
    execute "DROP TABLE IF EXISTS source_scope_change_requests;"
  end

  private

  def create_table_sql
    execute <<~SQL
      CREATE TABLE source_scope_change_requests (
        id                          uuid PRIMARY KEY,
        state_version               bigint NOT NULL DEFAULT 0,
        created_at                  timestamptz(6) NOT NULL,
        updated_at                  timestamptz(6) NOT NULL,
        correlation_id              uuid NOT NULL,
        schema_version              text NOT NULL
          CHECK (schema_version = 'source-scope-change-request-v1'),
        organization_id             uuid NOT NULL,
        project_id                  uuid NOT NULL,
        source_id                   uuid NOT NULL,
        requester_account_id        uuid NOT NULL,
        -- The current active Source Scope Policy the proposal is made against.
        expected_active_policy_version text NOT NULL,
        current_content_sha256      bytea NOT NULL
          CHECK (octet_length(current_content_sha256) = 32),
        -- The proposed normalized rules (canonical Source Scope Policy shape) + their hash.
        proposed_canonical_host     text NOT NULL,
        proposed_allowed_schemes    text[] NOT NULL
          CHECK (cardinality(proposed_allowed_schemes) >= 1),
        proposed_allowed_ports      integer[] NOT NULL
          CHECK (cardinality(proposed_allowed_ports) >= 1),
        proposed_include_prefixes   text[] NOT NULL
          CHECK (cardinality(proposed_include_prefixes) >= 1),
        proposed_exclude_prefixes   text[] NOT NULL DEFAULT '{}',
        proposed_query_handling     text NOT NULL,
        proposed_content_sha256     bytea NOT NULL
          CHECK (octet_length(proposed_content_sha256) = 32),
        request_reason              text NOT NULL
          CHECK (char_length(request_reason) BETWEEN 20 AND 2000),
        requested_at_utc            timestamptz(6) NOT NULL,
        due_at_utc                  timestamptz(6) NOT NULL,
        state                       text NOT NULL DEFAULT 'pending'
          CHECK (state IN ('pending','approved','rejected','canceled','expired')),
        -- Terminal decision facts, null until a later tranche transitions the request.
        decision_actor_id           uuid,
        decided_at_utc              timestamptz(6),
        decision_reason             text,
        activated_policy_version    text,
        terminal_at_utc             timestamptz(6),
        idempotency_key_digest      bytea NOT NULL
          CHECK (octet_length(idempotency_key_digest) = 32),
        CONSTRAINT source_scope_change_requests_org_id_unique UNIQUE (organization_id, id),
        -- due_at is exactly 24h after requested_at (asserted at insert; frozen by the guard).
        CONSTRAINT source_scope_change_requests_source_fk
          FOREIGN KEY (organization_id, project_id, source_id)
          REFERENCES sources (organization_id, project_id, id)
      );
      CREATE INDEX source_scope_change_requests_source_state
        ON source_scope_change_requests (organization_id, source_id, state);
      CREATE INDEX source_scope_change_requests_due
        ON source_scope_change_requests (due_at_utc) WHERE state = 'pending';
    SQL
  end

  def force_rls
    execute <<~SQL
      ALTER TABLE source_scope_change_requests ENABLE ROW LEVEL SECURITY;
      ALTER TABLE source_scope_change_requests FORCE ROW LEVEL SECURITY;
      CREATE POLICY source_scope_change_requests_context ON source_scope_change_requests
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
      REVOKE ALL ON source_scope_change_requests FROM PUBLIC;
    SQL
  end

  # The lifecycle guard freezes the tenant/Project/Source identity, the requester, the
  # proposed rules and hashes, and the issuance facts (requested/due/reason); and refuses
  # every state transition (`allowed_edges` = FALSE in this tranche). Later tranches
  # relax exactly the edges they own.
  def create_lifecycle_guard(allowed_edges)
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_source_scope_change_requests_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'source_scope_change_request_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.source_id IS DISTINCT FROM OLD.source_id THEN
          RAISE EXCEPTION 'source_scope_change_request_tenant_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        IF NEW.schema_version IS DISTINCT FROM OLD.schema_version
           OR NEW.requester_account_id IS DISTINCT FROM OLD.requester_account_id
           OR NEW.expected_active_policy_version IS DISTINCT FROM OLD.expected_active_policy_version
           OR NEW.current_content_sha256 IS DISTINCT FROM OLD.current_content_sha256
           OR NEW.proposed_canonical_host IS DISTINCT FROM OLD.proposed_canonical_host
           OR NEW.proposed_allowed_schemes IS DISTINCT FROM OLD.proposed_allowed_schemes
           OR NEW.proposed_allowed_ports IS DISTINCT FROM OLD.proposed_allowed_ports
           OR NEW.proposed_include_prefixes IS DISTINCT FROM OLD.proposed_include_prefixes
           OR NEW.proposed_exclude_prefixes IS DISTINCT FROM OLD.proposed_exclude_prefixes
           OR NEW.proposed_query_handling IS DISTINCT FROM OLD.proposed_query_handling
           OR NEW.proposed_content_sha256 IS DISTINCT FROM OLD.proposed_content_sha256
           OR NEW.request_reason IS DISTINCT FROM OLD.request_reason
           OR NEW.requested_at_utc IS DISTINCT FROM OLD.requested_at_utc
           OR NEW.due_at_utc IS DISTINCT FROM OLD.due_at_utc
           OR NEW.idempotency_key_digest IS DISTINCT FROM OLD.idempotency_key_digest THEN
          RAISE EXCEPTION 'source_scope_change_request_facts_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        IF NEW.state IS DISTINCT FROM OLD.state THEN
        IF NOT #{allowed_edges} THEN
          RAISE EXCEPTION 'source_scope_change_request_transition_unavailable % -> %', OLD.state, NEW.state
            USING ERRCODE = 'raise_exception';
        END IF;
      END IF;

        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER source_scope_change_requests_guard
        BEFORE UPDATE OR DELETE ON source_scope_change_requests
        FOR EACH ROW EXECUTE FUNCTION f1_source_scope_change_requests_guard();
    SQL
  end
end
