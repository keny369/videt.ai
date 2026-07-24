# frozen_string_literal: true

# F-02 Envelope Encryption key-ring METADATA boundary (FOUNDATION-002).
#
# This table NEVER stores wrapping-key material. The actual key-encryption keys are
# resolved out of band from the deployment-controlled source by (provider, version); the
# database holds only version identity, lifecycle state, a NON-secret key fingerprint
# (SHA-256 of the material, for misconfiguration detection), a non-secret deployment
# locator, and timestamps. It is owner-only (like f1_context_keys) and reached only
# through SECURITY DEFINER functions with a fixed safe search_path and least-privilege
# grants; the runtime may READ the boundary but never register or destroy a version
# (that would enable bulk cryptographic erasure through an ordinary command).
class CreateEncryptionKeyRing < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE f1_encryption_key_versions (
        provider        text        NOT NULL,
        version         text        NOT NULL,
        state           text        NOT NULL,
        key_fingerprint bytea,
        key_reference   text,
        created_at      timestamptz NOT NULL DEFAULT now(),
        activated_at    timestamptz,
        retired_at      timestamptz,
        destroyed_at    timestamptz,
        PRIMARY KEY (provider, version),
        CONSTRAINT f1_encryption_key_state_valid CHECK (state IN ('active','retired','destroyed')),
        CONSTRAINT f1_encryption_key_fingerprint_len
          CHECK (key_fingerprint IS NULL OR octet_length(key_fingerprint) = 32),
        -- a destroyed version keeps its metadata and audit but never its fingerprint
        CONSTRAINT f1_encryption_key_destroyed_no_fingerprint
          CHECK (state <> 'destroyed' OR key_fingerprint IS NULL),
        -- a usable (active) version must carry a fingerprint so the resolved key can be verified
        CONSTRAINT f1_encryption_key_active_has_fingerprint
          CHECK (state <> 'active' OR key_fingerprint IS NOT NULL)
      );
      REVOKE ALL ON f1_encryption_key_versions FROM PUBLIC;
      -- at most one active version per provider
      CREATE UNIQUE INDEX f1_one_active_encryption_key_per_provider
        ON f1_encryption_key_versions (provider) WHERE state = 'active';
    SQL

    # Read boundary (granted to the runtime centrally via F1::RuntimeGrants): the active
    # version, and one version's state + fingerprint. STABLE, fixed safe search_path,
    # explicit null/blank caller validation, no dynamic SQL.
    execute <<~SQL
      CREATE FUNCTION f1_encryption_active_version(p_provider text)
      RETURNS text
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
        SELECT version FROM f1_encryption_key_versions
        WHERE p_provider IS NOT NULL AND p_provider <> ''
          AND provider = p_provider AND state = 'active'
        LIMIT 1;
      $$;
      REVOKE ALL ON FUNCTION f1_encryption_active_version(text) FROM PUBLIC;

      CREATE FUNCTION f1_encryption_describe_version(p_provider text, p_version text)
      RETURNS TABLE (state text, fingerprint_hex text)
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
        SELECT state, encode(key_fingerprint, 'hex')
        FROM f1_encryption_key_versions
        WHERE p_provider IS NOT NULL AND p_provider <> ''
          AND p_version IS NOT NULL AND p_version <> ''
          AND provider = p_provider AND version = p_version;
      $$;
      REVOKE ALL ON FUNCTION f1_encryption_describe_version(text, text) FROM PUBLIC;
    SQL

    # Owner-only lifecycle registration: provision/activate a version. Demotes the current
    # active version to retired and installs the new one as active, atomically. NOT granted
    # to the runtime. A destroyed version can never be resurrected. Explicit validation.
    execute <<~SQL
      CREATE FUNCTION f1_encryption_register_active_version(
        p_provider text, p_version text, p_fingerprint bytea, p_reference text)
      RETURNS void
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_state text;
      BEGIN
        IF p_provider IS NULL OR p_provider = '' OR p_version IS NULL OR p_version = '' THEN
          RAISE EXCEPTION 'provider and version are required';
        END IF;
        IF p_fingerprint IS NULL OR octet_length(p_fingerprint) <> 32 THEN
          RAISE EXCEPTION 'fingerprint must be 32 bytes';
        END IF;

        SELECT state INTO v_state FROM f1_encryption_key_versions
          WHERE provider = p_provider AND version = p_version;
        IF v_state = 'destroyed' THEN
          RAISE EXCEPTION 'a destroyed key version cannot be reactivated';
        END IF;

        UPDATE f1_encryption_key_versions
          SET state = 'retired', retired_at = now()
          WHERE provider = p_provider AND state = 'active' AND version <> p_version;

        INSERT INTO f1_encryption_key_versions
            (provider, version, state, key_fingerprint, key_reference, activated_at)
          VALUES (p_provider, p_version, 'active', p_fingerprint, p_reference, now())
          ON CONFLICT (provider, version) DO UPDATE
            SET state = 'active', key_fingerprint = EXCLUDED.key_fingerprint,
                key_reference = EXCLUDED.key_reference, activated_at = now(), retired_at = NULL;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_encryption_register_active_version(text, text, bytea, text) FROM PUBLIC;
    SQL
  end

  def down
    execute <<~SQL
      DROP FUNCTION IF EXISTS f1_encryption_register_active_version(text, text, bytea, text);
      DROP FUNCTION IF EXISTS f1_encryption_describe_version(text, text);
      DROP FUNCTION IF EXISTS f1_encryption_active_version(text);
      DROP TABLE IF EXISTS f1_encryption_key_versions;
    SQL
  end
end
