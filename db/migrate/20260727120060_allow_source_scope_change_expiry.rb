# frozen_string_literal: true

# S-06-005 ExpireSourceScopeChange. The decision guard (20260727120050, hardened by
# 20260727120051) permits pending -> {approved,rejected,canceled} and refuses everything
# else, including pending -> expired (deferred to this tranche). This migration adds
# `expired` to the permitted terminal set so the source-scope lifecycle service can expire a
# still-pending request at `due_at_utc`. Every other invariant is preserved verbatim: DELETE
# refused, a terminal row fully immutable, the tenant identity and proposed/issuance facts
# frozen (including created_at/correlation_id), pending -> pending refused. No grant change —
# UPDATE was granted in 20260727120050.
class AllowSourceScopeChangeExpiry < ActiveRecord::Migration[8.1]
  def up
    write_guard("NEW.state IN ('approved','rejected','canceled','expired')")
  end

  def down
    # Restore the 20260727120051 form (expiry not yet permitted).
    write_guard("NEW.state IN ('approved','rejected','canceled')")
  end

  private

  def write_guard(permitted)
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
           OR NEW.created_at IS DISTINCT FROM OLD.created_at
           OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id
           OR NEW.idempotency_key_digest IS DISTINCT FROM OLD.idempotency_key_digest THEN
          RAISE EXCEPTION 'source_scope_change_request_facts_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        -- The only permitted change to a pending request is a transition to a terminal state
        -- (a decision or, from this tranche, an expiry); pending -> pending is refused.
        IF NOT (#{permitted}) THEN
          RAISE EXCEPTION 'source_scope_change_request_transition_unavailable % -> %', OLD.state, NEW.state
            USING ERRCODE = 'raise_exception';
        END IF;

        RETURN NEW;
      END;
      $$;
    SQL
  end
end
