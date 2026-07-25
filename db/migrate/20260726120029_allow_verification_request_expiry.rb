# frozen_string_literal: true

# S-05-002 Ownership Verification — ExpireVerificationRequest (WF-003 expiry limb).
#
# S-05-001 created `verification_requests` with a lifecycle guard that freezes the
# issuance facts and refuses EVERY request_status transition until each later limb
# relaxes exactly its ratified edge (the sources-guard discipline). This migration
# relaxes exactly one edge — `pending -> expired` — for the expiry service, and
# nothing else. Every other transition (verified/canceled/failed) stays unavailable
# until its own slice lands, and the tenant/Source identity and the issuance facts
# remain immutable.
#
# The expiry also cryptographically destroys the challenge material: the guard does
# NOT freeze `challenge_ciphertext_reference`/`challenge_key_id` (they are "nullable
# only after terminal cryptographic deletion", SCORE_EVIDENCE_MODEL.md), so the
# expiry transaction nulls them; the immutable challenge digest and the audit remain.
class AllowVerificationRequestExpiry < ActiveRecord::Migration[8.1]
  def up
    replace_guard(<<~SQL)
      IF NEW.request_status IS DISTINCT FROM OLD.request_status THEN
        -- S-05-002 relaxes exactly the pending -> expired edge; every other
        -- transition remains unavailable until its slice lands.
        IF NOT (OLD.request_status = 'pending' AND NEW.request_status = 'expired') THEN
          RAISE EXCEPTION 'verification_request_transition_unavailable % -> %', OLD.request_status, NEW.request_status
            USING ERRCODE = 'raise_exception';
        END IF;
      END IF;
    SQL
  end

  def down
    replace_guard(<<~SQL)
      IF NEW.request_status IS DISTINCT FROM OLD.request_status THEN
        RAISE EXCEPTION 'verification_request_transition_unavailable % -> %', OLD.request_status, NEW.request_status
          USING ERRCODE = 'raise_exception';
      END IF;
    SQL
  end

  private

  # CREATE OR REPLACE the guard with the same identity/issuance freezes and the given
  # request_status clause. The function signature is unchanged, so the trigger binding
  # is preserved.
  def replace_guard(status_clause)
    execute <<~SQL
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

        #{status_clause}

        RETURN NEW;
      END;
      $$;
    SQL
  end
end
