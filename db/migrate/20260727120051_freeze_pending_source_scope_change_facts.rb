# frozen_string_literal: true

# S-06-004 defense-in-depth (ADR-063; independent ADR-026 schema-lens finding). The
# decision guard from 20260727120050 relaxed pending -> {approved,rejected,canceled} and
# granted the runtime role UPDATE. It freezes the tenant identity and the proposed/issuance
# facts, and makes a terminal request fully immutable — but a pending -> pending UPDATE
# (state unchanged) slipped past the transition check, so the decision facts
# (decision_actor_id, decided_at_utc, decision_reason, activated_policy_version,
# terminal_at_utc) and provenance (created_at, correlation_id, state_version) were writable
# on a still-pending row. No application path does this — the sole UPDATE writer,
# SourceScopeChangeStore#transition_request, always moves to a terminal state guarded on
# state = 'pending' — but the DB backstop should enforce it directly.
#
# This makes the decision-edge requirement UNCONDITIONAL for a pending row: the ONLY
# permitted change to a pending request is a transition to a permitted terminal state, so
# the decision facts can be written exactly once (atomically, during that transition) and
# are frozen thereafter. A pending -> pending UPDATE now raises. Fail-closed, and the
# same single-edge discipline the sibling guards use.
class FreezePendingSourceScopeChangeFacts < ActiveRecord::Migration[8.1]
  def up
    write_guard("NEW.state IN ('approved','rejected','canceled')")
  end

  def down
    # Restore the 20260727120050 form (decision edges permitted only on a state change).
    write_guard("(NEW.state IS NOT DISTINCT FROM OLD.state) OR (NEW.state IN ('approved','rejected','canceled'))")
  end

  private

  # `permitted` is evaluated for every UPDATE of a still-pending row (a terminal row and a
  # DELETE are already refused above). The `up` form admits ONLY a transition to a terminal
  # decision state, so it also refuses pending -> pending and pending -> expired.
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

        -- The only permitted change to a pending request is a transition to a terminal
        -- decision state; pending -> pending and pending -> expired are refused.
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
