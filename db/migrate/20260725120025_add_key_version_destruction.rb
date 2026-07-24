# frozen_string_literal: true

# F-02 Envelope Encryption — key-version cryptographic erasure (FOUNDATION-002 §Cryptographic
# erasure). Destroying a wrapping-key version makes EVERY envelope dependent on it
# irrecoverable at once: the provider can no longer unwrap those DEKs. This is the bulk
# erasure path and is therefore OWNER-ONLY — it is never reachable through an ordinary
# application command, so no request can accidentally erase a whole version's data. It
# nulls the non-secret fingerprint and records destroyed_at; the deployment separately
# removes the out-of-band key material. A destroyed version can never be reactivated
# (enforced by the register mutation from 2/n).
#
# Record-level erasure (one value) is the destroy from 4/n; this is the version-level
# counterpart, and the two are the exact, distinct destruction boundaries.
class AddKeyVersionDestruction < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION f1_encryption_destroy_version(p_provider text, p_version text)
      RETURNS text
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_state text;
      BEGIN
        SELECT state INTO v_state FROM f1_encryption_key_versions
          WHERE provider = p_provider AND version = p_version;
        IF v_state IS NULL THEN RETURN 'unknown'; END IF;
        IF v_state = 'destroyed' THEN RETURN 'already_destroyed'; END IF;
        UPDATE f1_encryption_key_versions
          SET state = 'destroyed', key_fingerprint = NULL, destroyed_at = now()
          WHERE provider = p_provider AND version = p_version;
        RETURN 'destroyed';
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_encryption_destroy_version(text, text) FROM PUBLIC;
    SQL
  end

  def down
    execute "DROP FUNCTION IF EXISTS f1_encryption_destroy_version(text, text);"
  end
end
