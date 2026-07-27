# frozen_string_literal: true

# S-06-004 atomic contraction activation + Decide + Cancel.
#
# S-06-003 created source_scope_change_requests with the transition guard refusing EVERY
# state change (allowed_edges = FALSE) and granted the runtime role SELECT/INSERT only.
# This migration relaxes exactly the decision edges this tranche owns —
# `pending -> approved`, `pending -> rejected`, `pending -> canceled` — and grants the
# runtime role UPDATE so a decision (and the atomic contraction fast-path on
# ProposeSourceScopeChange) can transition a pending request. The tenant identity, the
# proposed rules and the issuance facts stay frozen; once a request is terminal it is
# fully immutable, so the decision facts a transition writes are frozen thereafter. The
# `pending -> expired` edge remains refused (S-06-005). The same single-edge discipline
# S-05-002/S-05-006 use on verification_requests.
class AllowSourceScopeChangeDecisions < ActiveRecord::Migration[8.1]
  def up
    grant_runtime_update
    relax_guard("(OLD.state = 'pending' AND NEW.state IN ('approved','rejected','canceled'))")
  end

  def down
    revoke_runtime_update
    relax_guard("FALSE")
  end

  private

  def grant_runtime_update
    execute "GRANT UPDATE ON source_scope_change_requests TO f1_runtime;"
  end

  def revoke_runtime_update
    execute "REVOKE UPDATE ON source_scope_change_requests FROM f1_runtime;"
  end

  # The guard with exactly the decision edges permitted; a terminal request is fully
  # immutable, and the tenant/proposed/issuance facts are frozen verbatim.
  def relax_guard(allowed_edges)
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_source_scope_change_requests_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'source_scope_change_request_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        -- A terminal request is immutable: no field may change once it leaves pending.
        IF OLD.state <> 'pending' THEN
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
    SQL
  end
end
