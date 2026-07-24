# frozen_string_literal: true

# F-02 Envelope Encryption — the encrypted-record STORAGE boundary (FOUNDATION-002).
#
# The database persists the encrypted envelope and NON-secret lifecycle metadata; it
# never holds plaintext, a plaintext DEK, or a wrapping key. The table is owner-only
# (like f1_context_keys / the receipt store) and reached only through SECURITY DEFINER
# functions with a fixed safe search_path and explicit validation; the runtime holds
# EXECUTE on put/get/destroy and cannot touch the table. The returned id is an unguessable
# reference (a capability): a consumer stores only {ciphertext_reference, key_id,
# content_digest} on its own RLS-protected row. The content_digest is a non-secret
# integrity anchor that survives record destruction.
class CreateEncryptedRecords < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE f1_encrypted_records (
        id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
        application          text        NOT NULL,
        record_type          text        NOT NULL,
        record_id            text        NOT NULL,
        purpose              text        NOT NULL,
        tenant               text,
        aad_schema_version   text        NOT NULL,
        key_provider         text        NOT NULL,
        wrapping_key_version text        NOT NULL,
        envelope             bytea,
        content_digest       bytea       NOT NULL,
        state                text        NOT NULL DEFAULT 'active',
        created_at           timestamptz NOT NULL DEFAULT now(),
        destroyed_at         timestamptz,
        CONSTRAINT f1_encrypted_record_state_valid CHECK (state IN ('active','destroyed')),
        CONSTRAINT f1_encrypted_record_digest_len CHECK (octet_length(content_digest) = 32),
        -- destroyed => no envelope (cryptographic erasure); active => has an envelope
        CONSTRAINT f1_encrypted_record_destroyed_no_envelope CHECK (state <> 'destroyed' OR envelope IS NULL),
        CONSTRAINT f1_encrypted_record_active_has_envelope   CHECK (state <> 'active' OR envelope IS NOT NULL)
      );
      REVOKE ALL ON f1_encrypted_records FROM PUBLIC;
      -- lifecycle queries by wrapping-key version (rewrap/version-destruction), active only
      CREATE INDEX f1_encrypted_records_by_wrapping_version
        ON f1_encrypted_records (key_provider, wrapping_key_version) WHERE state = 'active';
    SQL

    execute <<~SQL
      CREATE FUNCTION f1_encrypted_record_put(
        p_application text, p_record_type text, p_record_id text, p_purpose text, p_tenant text,
        p_aad_schema_version text, p_key_provider text, p_wrapping_key_version text,
        p_envelope bytea, p_content_digest bytea)
      RETURNS uuid
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_id uuid;
      BEGIN
        IF p_envelope IS NULL OR octet_length(p_envelope) = 0 THEN
          RAISE EXCEPTION 'envelope is required';
        END IF;
        IF p_content_digest IS NULL OR octet_length(p_content_digest) <> 32 THEN
          RAISE EXCEPTION 'content_digest must be 32 bytes';
        END IF;
        INSERT INTO f1_encrypted_records
          (application, record_type, record_id, purpose, tenant, aad_schema_version,
           key_provider, wrapping_key_version, envelope, content_digest, state)
        VALUES (p_application, p_record_type, p_record_id, p_purpose, p_tenant, p_aad_schema_version,
           p_key_provider, p_wrapping_key_version, p_envelope, p_content_digest, 'active')
        RETURNING id INTO v_id;
        RETURN v_id;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_encrypted_record_put(text, text, text, text, text, text, text, text, bytea, bytea) FROM PUBLIC;

      CREATE FUNCTION f1_encrypted_record_get(p_id uuid)
      RETURNS TABLE (envelope_hex text, state text, content_digest_hex text, wrapping_key_version text, key_provider text)
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
        SELECT encode(envelope, 'hex'), state, encode(content_digest, 'hex'), wrapping_key_version, key_provider
        FROM f1_encrypted_records
        WHERE p_id IS NOT NULL AND id = p_id;
      $$;
      REVOKE ALL ON FUNCTION f1_encrypted_record_get(uuid) FROM PUBLIC;

      -- Record-level cryptographic erasure: null the envelope so the payload is
      -- unrecoverable, keep the content digest and audit. Idempotent.
      CREATE FUNCTION f1_encrypted_record_destroy(p_id uuid)
      RETURNS text
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_state text;
      BEGIN
        UPDATE f1_encrypted_records
          SET envelope = NULL, state = 'destroyed', destroyed_at = now()
          WHERE id = p_id AND state = 'active'
          RETURNING state INTO v_state;
        IF v_state IS NOT NULL THEN
          RETURN 'destroyed';
        END IF;
        SELECT state INTO v_state FROM f1_encrypted_records WHERE id = p_id;
        RETURN CASE WHEN v_state = 'destroyed' THEN 'already_destroyed' ELSE 'unknown' END;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_encrypted_record_destroy(uuid) FROM PUBLIC;
    SQL
  end

  def down
    execute <<~SQL
      DROP FUNCTION IF EXISTS f1_encrypted_record_destroy(uuid);
      DROP FUNCTION IF EXISTS f1_encrypted_record_get(uuid);
      DROP FUNCTION IF EXISTS f1_encrypted_record_put(text, text, text, text, text, text, text, text, bytea, bytea);
      DROP TABLE IF EXISTS f1_encrypted_records;
    SQL
  end
end
