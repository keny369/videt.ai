# frozen_string_literal: true

# F-02 Envelope Encryption — rotation & retirement (FOUNDATION-002 §Rotation semantics).
#
# Adds the owner-only `retire` mutation, extends the record read to expose the AAD identity
# (so a rewrap can rebuild the binding without the consumer), and adds a concurrency-guarded
# `rewrap` update. Rewrap re-wraps the DEK under the active wrapping key WITHOUT rewriting
# the payload ciphertext; the guard on the expected current version makes it idempotent and
# safe under concurrency (a second rewrap of the same record finds the version already
# advanced and no-ops).
class AddKeyRingRotation < ActiveRecord::Migration[8.1]
  def up
    # Owner-only: retire a version so it can no longer encrypt; historical envelopes under
    # it still decrypt. A destroyed version cannot be retired.
    execute <<~SQL
      CREATE FUNCTION f1_encryption_retire_version(p_provider text, p_version text)
      RETURNS text
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_state text;
      BEGIN
        SELECT state INTO v_state FROM f1_encryption_key_versions
          WHERE provider = p_provider AND version = p_version;
        IF v_state IS NULL THEN RETURN 'unknown'; END IF;
        IF v_state = 'destroyed' THEN RAISE EXCEPTION 'a destroyed key version cannot be retired'; END IF;
        IF v_state = 'retired' THEN RETURN 'already_retired'; END IF;
        UPDATE f1_encryption_key_versions
          SET state = 'retired', retired_at = now()
          WHERE provider = p_provider AND version = p_version;
        RETURN 'retired';
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_encryption_retire_version(text, text) FROM PUBLIC;
    SQL

    # Recreate the record read to also return the AAD identity (non-secret), so a rewrap
    # can reconstruct the binding. Signature (uuid) unchanged, so central grants still apply.
    execute <<~SQL
      DROP FUNCTION IF EXISTS f1_encrypted_record_get(uuid);
      CREATE FUNCTION f1_encrypted_record_get(p_id uuid)
      RETURNS TABLE (
        envelope_hex text, state text, content_digest_hex text,
        key_provider text, wrapping_key_version text,
        application text, record_type text, record_id text, purpose text, tenant text,
        aad_schema_version text)
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
        SELECT encode(envelope, 'hex'), state, encode(content_digest, 'hex'),
               key_provider, wrapping_key_version,
               application, record_type, record_id, purpose, tenant, aad_schema_version
        FROM f1_encrypted_records
        WHERE p_id IS NOT NULL AND id = p_id;
      $$;
      REVOKE ALL ON FUNCTION f1_encrypted_record_get(uuid) FROM PUBLIC;
    SQL

    # Concurrency-guarded rewrap: swap in the re-wrapped envelope ONLY if the record is
    # still active at the expected wrapping-key version. Returns 'rewrapped', 'stale'
    # (version already advanced — the idempotent/concurrent no-op) or 'unknown'.
    execute <<~SQL
      CREATE FUNCTION f1_encrypted_record_rewrap(
        p_id uuid, p_expected_version text, p_new_version text, p_new_envelope bytea)
      RETURNS text
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_rows int;
      BEGIN
        IF p_new_envelope IS NULL OR octet_length(p_new_envelope) = 0 THEN
          RAISE EXCEPTION 'new envelope is required';
        END IF;
        UPDATE f1_encrypted_records
          SET envelope = p_new_envelope, wrapping_key_version = p_new_version
          WHERE id = p_id AND state = 'active' AND wrapping_key_version = p_expected_version;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows = 1 THEN RETURN 'rewrapped'; END IF;
        IF EXISTS (SELECT 1 FROM f1_encrypted_records WHERE id = p_id) THEN RETURN 'stale'; END IF;
        RETURN 'unknown';
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_encrypted_record_rewrap(uuid, text, text, bytea) FROM PUBLIC;
    SQL
  end

  def down
    execute <<~SQL
      DROP FUNCTION IF EXISTS f1_encrypted_record_rewrap(uuid, text, text, bytea);
      DROP FUNCTION IF EXISTS f1_encryption_retire_version(text, text);
      DROP FUNCTION IF EXISTS f1_encrypted_record_get(uuid);
      CREATE FUNCTION f1_encrypted_record_get(p_id uuid)
      RETURNS TABLE (envelope_hex text, state text, content_digest_hex text, wrapping_key_version text, key_provider text)
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
        SELECT encode(envelope, 'hex'), state, encode(content_digest, 'hex'), wrapping_key_version, key_provider
        FROM f1_encrypted_records WHERE p_id IS NOT NULL AND id = p_id;
      $$;
      REVOKE ALL ON FUNCTION f1_encrypted_record_get(uuid) FROM PUBLIC;
    SQL
  end
end
