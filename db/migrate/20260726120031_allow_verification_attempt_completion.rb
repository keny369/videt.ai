# frozen_string_literal: true

# S-05-005 CompleteVerificationAttempt (observation recording). The reservation limb
# (S-05-004) created `verification_attempts` with a lifecycle guard that freezes the
# reservation and refuses EVERY state transition. This migration relaxes exactly the
# `reserved -> completed` edge — the observation-recording transition — and nothing
# else, the same discipline S-05-002 used to relax `pending -> expired` on
# `verification_requests`. `running` and `quarantined` transitions remain unavailable
# until their slices land.
#
# The outcome columns (started/completed times, network outcome/status/code, byte
# count, digest, match decision, reason code) already exist; the `reserved_has_no_outcome`
# CHECK only constrains a `reserved` row, so a `completed` row may carry them. The guard
# does not freeze those columns, so the completion transaction may set them together
# with the state on this one relaxed edge. No table, column, index or grant changes.
class AllowVerificationAttemptCompletion < ActiveRecord::Migration[8.1]
  def up
    execute(guard_body("(OLD.state = 'reserved' AND NEW.state = 'completed')"))
  end

  def down
    # Restore the always-freeze guard (no transition permitted).
    execute(guard_body("FALSE"))
  end

  def guard_body(allowed_edge)
    <<~SQL
      CREATE OR REPLACE FUNCTION f1_verification_attempts_lifecycle_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.verification_request_id IS DISTINCT FROM OLD.verification_request_id
           OR NEW.source_id IS DISTINCT FROM OLD.source_id THEN
          RAISE EXCEPTION 'verification_attempt_tenant_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        IF NEW.schema_version IS DISTINCT FROM OLD.schema_version
           OR NEW.attempt_number IS DISTINCT FROM OLD.attempt_number
           OR NEW.origin IS DISTINCT FROM OLD.origin
           OR NEW.automated_slot_offset_minutes IS DISTINCT FROM OLD.automated_slot_offset_minutes
           OR NEW.reserved_at_utc IS DISTINCT FROM OLD.reserved_at_utc THEN
          RAISE EXCEPTION 'verification_attempt_reservation_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        IF NEW.state IS DISTINCT FROM OLD.state THEN
        -- S-05-005 relaxes exactly the reserved -> completed edge (observation
        -- recording); every other transition remains unavailable until its slice lands.
        IF NOT #{allowed_edge} THEN
          RAISE EXCEPTION 'verification_attempt_transition_unavailable % -> %', OLD.state, NEW.state
            USING ERRCODE = 'raise_exception';
        END IF;
      END IF;

        RETURN NEW;
      END;
      $$;
    SQL
  end
end
