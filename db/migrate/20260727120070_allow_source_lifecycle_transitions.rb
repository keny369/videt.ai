# frozen_string_literal: true

# S-06-006 Source lifecycle (PRULE-006). The sources guard (S-05-006, 20260726120032)
# permits exactly `proposed -> verified` and refuses every other state change. This migration
# relaxes it to also permit the four ratified lifecycle edges — `verified -> active`,
# `active -> disabled`, `disabled -> active`, `disabled -> removed` (contracts/S-06.json
# MTX-057 test_contracts) — while every UNLISTED transition (direct `active -> removed`,
# `active -> verified`, `proposed -> active`, `removed -> *`, etc.) still raises
# `source_lifecycle_transition_unavailable`, and the tenant identity + registration
# provenance freezes are preserved verbatim. The runtime role already holds UPDATE on
# `sources` (S-04). Purely a guard widening; no column, grant, or data change.
class AllowSourceLifecycleTransitions < ActiveRecord::Migration[8.1]
  ALLOWED = <<~SQL.strip
    (OLD.state = 'proposed' AND NEW.state = 'verified')
    OR (OLD.state = 'verified' AND NEW.state = 'active')
    OR (OLD.state = 'active'   AND NEW.state = 'disabled')
    OR (OLD.state = 'disabled' AND NEW.state = 'active')
    OR (OLD.state = 'disabled' AND NEW.state = 'removed')
  SQL

  def up
    write_guard(ALLOWED)
  end

  def down
    # Restore the S-05-006 form: only proposed -> verified permitted.
    write_guard("(OLD.state = 'proposed' AND NEW.state = 'verified')")
  end

  private

  def write_guard(allowed_edge)
    execute <<~SQL
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
        -- S-06-006 permits the four PRULE-006 lifecycle edges in addition to the S-05-006
        -- proposed -> verified edge; every other transition is refused and audited by the caller.
        IF NOT (#{allowed_edge}) THEN
          RAISE EXCEPTION 'source_lifecycle_transition_unavailable % -> %', OLD.state, NEW.state
            USING ERRCODE = 'raise_exception';
        END IF;
      END IF;

        RETURN NEW;
      END;
      $$;
    SQL
  end
end
