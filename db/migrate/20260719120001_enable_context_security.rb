# frozen_string_literal: true

# Platform security foundation (schemas/POSTGRESQL_SCHEMA.md § Tenant Isolation
# And Database Roles). Establishes proof-validated transaction-local context so
# that application code cannot make tenant/principal context authoritative by a
# raw SET/set_config: the proof is an HMAC over (txid, principal, org) keyed by a
# secret only the schema owner can read, so a forged app.* setting yields NULL
# from the context accessors and matches no RLS row.
class EnableContextSecurity < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE EXTENSION IF NOT EXISTS pgcrypto;
    SQL

    # Owner-only secret. No grants: only SECURITY DEFINER functions running as the
    # owner can read it, so f1_web can never compute a proof for a forged context.
    execute <<~SQL
      CREATE TABLE f1_context_keys (
        key_name  text PRIMARY KEY,
        key_bytes bytea NOT NULL CHECK (octet_length(key_bytes) = 32)
      );
      REVOKE ALL ON f1_context_keys FROM PUBLIC;
      INSERT INTO f1_context_keys (key_name, key_bytes)
        VALUES ('context_proof', gen_random_bytes(32));
    SQL

    # Internal proof computation (owner-only). Binds the proof to the current
    # transaction id so a proof cannot be replayed into another transaction, and
    # to the exact principal/org values so neither can be swapped after the fact.
    execute <<~SQL
      CREATE FUNCTION f1_context_proof(p_principal_hex text, p_org text)
      RETURNS text
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
        SELECT encode(
          hmac(
            convert_to(txid_current()::text || '|' || coalesce(p_principal_hex, '') || '|' || coalesce(p_org, ''), 'UTF8'),
            (SELECT key_bytes FROM f1_context_keys WHERE key_name = 'context_proof'),
            'sha256'
          ), 'hex');
      $$;
      REVOKE ALL ON FUNCTION f1_context_proof(text, text) FROM PUBLIC;
    SQL

    # Deterministic per-principal UUIDv8 (RFC 9562 §5.8) from the first 128 bits
    # of the 32-byte principal digest. This is the physical form of the OD-013
    # substitution: BootstrapGrantIssued/BootstrapGrantExpired carry it in
    # organization_id (see the od-013 representation note). Stable, immutable,
    # never a sentinel or platform tenant.
    execute <<~SQL
      CREATE FUNCTION f1_bootstrap_principal_uuid(p_digest bytea)
      RETURNS uuid
      LANGUAGE plpgsql IMMUTABLE
      AS $$
      DECLARE b bytea;
      BEGIN
        IF p_digest IS NULL OR octet_length(p_digest) <> 32 THEN
          RAISE EXCEPTION 'bootstrap principal digest must be 32 bytes';
        END IF;
        b := substring(p_digest FROM 1 FOR 16);
        b := set_byte(b, 6, (get_byte(b, 6) & 15) | 128);  -- version 8
        b := set_byte(b, 8, (get_byte(b, 8) & 63) | 128);  -- variant 10xx
        RETURN encode(b, 'hex')::uuid;
      END;
      $$;
    SQL

    # Proof-validated accessors used by every RLS policy. They return the context
    # value only when app.f1_proof matches the recomputed proof for the current
    # transaction; a missing, blank, raw-set or mismatched context returns NULL
    # and therefore matches no row and never raises.
    execute <<~SQL
      CREATE FUNCTION f1_current_bootstrap_principal()
      RETURNS bytea
      LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_hex text; v_org text; v_proof text;
      BEGIN
        v_hex   := current_setting('app.bootstrap_principal_digest', true);
        v_org   := current_setting('app.context_org', true);
        v_proof := current_setting('app.f1_proof', true);
        IF v_hex IS NULL OR v_hex = '' OR v_proof IS NULL OR v_proof = '' THEN
          RETURN NULL;
        END IF;
        IF v_proof <> f1_context_proof(v_hex, v_org) THEN RETURN NULL; END IF;
        RETURN decode(v_hex, 'hex');
      EXCEPTION WHEN others THEN RETURN NULL;
      END;
      $$;

      CREATE FUNCTION f1_current_context_org()
      RETURNS uuid
      LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE v_hex text; v_org text; v_proof text;
      BEGIN
        v_hex   := current_setting('app.bootstrap_principal_digest', true);
        v_org   := current_setting('app.context_org', true);
        v_proof := current_setting('app.f1_proof', true);
        IF v_org IS NULL OR v_org = '' OR v_proof IS NULL OR v_proof = '' THEN
          RETURN NULL;
        END IF;
        IF v_proof <> f1_context_proof(v_hex, v_org) THEN RETURN NULL; END IF;
        RETURN v_org::uuid;
      EXCEPTION WHEN others THEN RETURN NULL;
      END;
      $$;
    SQL

    # Runtime EXECUTE on the proof-validated accessors (RLS uses them) — but never
    # on f1_context_proof or the key — is granted centrally from the single source
    # F1::RuntimeGrants (lib/tasks/f1_db.rake), applied after both schema load and
    # migrate so the two build paths converge on one grant state.
  end

  def down
    execute <<~SQL
      DROP FUNCTION IF EXISTS f1_current_context_org();
      DROP FUNCTION IF EXISTS f1_current_bootstrap_principal();
      DROP FUNCTION IF EXISTS f1_bootstrap_principal_uuid(bytea);
      DROP FUNCTION IF EXISTS f1_context_proof(text, text);
      DROP TABLE IF EXISTS f1_context_keys;
    SQL
  end
end
