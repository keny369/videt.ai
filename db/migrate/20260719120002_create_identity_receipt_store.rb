# frozen_string_literal: true

# Restricted identity-receipt store (schemas/POSTGRESQL_SCHEMA.md § restricted
# mixed-scope locators). The Identity Validation Receipt (onboarding-interim-v1,
# WORKFLOW_SPECIFICATIONS.md § onboarding-interim-v1) is the only identity proof
# WF-001 accepts. It is minted by the approved identity service; F1 never stores
# raw credentials or factor values.
#
# These tables carry NO runtime table grant. RLS is enabled (defence in depth)
# but not forced, so the SECURITY DEFINER context function reads a receipt as the
# owner to establish proved context — the one read that must precede context.
class CreateIdentityReceiptStore < ActiveRecord::Migration[8.1]
  PURPOSES = %w[bootstrap_grant_request self_service_bootstrap invitation_response
                existing_account_sign_in organization_reactivation].freeze

  def up
    execute <<~SQL
      CREATE TABLE identity_receipt_nonces (
        id                        uuid PRIMARY KEY,
        schema_version            text NOT NULL,
        created_at                timestamptz(6) NOT NULL,
        receipt_digest            bytea NOT NULL UNIQUE CHECK (octet_length(receipt_digest) = 32),
        receipt_schema_version    text NOT NULL,
        issuer_key                text NOT NULL,
        issuer_subject            text NOT NULL,
        normalized_email          text NOT NULL,
        normalized_email_sha256   bytea NOT NULL CHECK (octet_length(normalized_email_sha256) = 32),
        display_name              text NOT NULL,
        email_verified            boolean NOT NULL CHECK (email_verified),
        purpose                   text NOT NULL CHECK (purpose IN (#{PURPOSES.map { |p| "'#{p}'" }.join(',')})),
        validated_at              timestamptz(6) NOT NULL,
        expires_at                timestamptz(6) NOT NULL,
        nonce_sha256              bytea NOT NULL UNIQUE CHECK (octet_length(nonce_sha256) = 32),
        identity_principal_digest bytea NOT NULL CHECK (octet_length(identity_principal_digest) = 32),
        bootstrap_principal_digest bytea CHECK (bootstrap_principal_digest IS NULL OR octet_length(bootstrap_principal_digest) = 32),
        assurance_version         text,
        mfa_satisfied             boolean,
        retention_class           text NOT NULL CHECK (retention_class = 'security_audit'),
        -- Receipt lifetime is exactly 10 minutes (onboarding-interim-v1).
        CONSTRAINT receipt_expiry_is_ten_minutes CHECK (expires_at = validated_at + interval '10 minutes'),
        -- bootstrap_principal_digest equals identity_principal_digest exactly for
        -- the bootstrap-grant and self-service purposes, and is null otherwise.
        CONSTRAINT bootstrap_digest_only_for_bootstrap_purposes CHECK (
          (purpose IN ('bootstrap_grant_request','self_service_bootstrap')
             AND bootstrap_principal_digest = identity_principal_digest)
          OR
          (purpose NOT IN ('bootstrap_grant_request','self_service_bootstrap')
             AND bootstrap_principal_digest IS NULL)
        ),
        -- Assurance fields are present exactly for the sign-in / reactivation family.
        CONSTRAINT assurance_only_for_signin_family CHECK (
          (purpose IN ('existing_account_sign_in','organization_reactivation')
             AND assurance_version IS NOT NULL AND mfa_satisfied IS NOT NULL)
          OR
          (purpose NOT IN ('existing_account_sign_in','organization_reactivation')
             AND assurance_version IS NULL AND mfa_satisfied IS NULL)
        )
      );
      ALTER TABLE identity_receipt_nonces ENABLE ROW LEVEL SECURITY;
      CREATE POLICY receipt_by_principal ON identity_receipt_nonces
        USING (bootstrap_principal_digest = f1_current_bootstrap_principal());
      REVOKE ALL ON identity_receipt_nonces FROM PUBLIC;
    SQL

    execute <<~SQL
      CREATE TABLE identity_receipt_consumptions (
        id                   uuid PRIMARY KEY,
        schema_version       text NOT NULL,
        created_at           timestamptz(6) NOT NULL,
        receipt_id           uuid NOT NULL UNIQUE REFERENCES identity_receipt_nonces(id),
        receipt_digest       bytea NOT NULL CHECK (octet_length(receipt_digest) = 32),
        command_execution_id uuid NOT NULL,
        consumed_at          timestamptz(6) NOT NULL,
        outcome              text NOT NULL CHECK (outcome IN ('consumed','rejected')),
        reason_code          text,
        CONSTRAINT reason_null_only_when_consumed CHECK (
          (outcome = 'consumed' AND reason_code IS NULL) OR
          (outcome = 'rejected' AND reason_code IS NOT NULL)
        )
      );
      -- One successful (consumed) binding per receipt; a rejected attempt binds the
      -- nonce to its denied command so a retry needs a fresh receipt.
      CREATE UNIQUE INDEX one_consumed_per_receipt ON identity_receipt_consumptions (receipt_id)
        WHERE outcome = 'consumed';
      CREATE UNIQUE INDEX one_consumption_per_command ON identity_receipt_consumptions (command_execution_id);
      ALTER TABLE identity_receipt_consumptions ENABLE ROW LEVEL SECURITY;
      REVOKE ALL ON identity_receipt_consumptions FROM PUBLIC;
    SQL

    # Context establishment: resolve the receipt (as owner, before any context
    # exists), establish the proved bootstrap-principal context, and return the
    # non-secret fields the application validates. Returns zero rows when the
    # receipt digest does not resolve. Sets no context on a miss.
    execute <<~SQL
      CREATE FUNCTION f1_enter_bootstrap_context(p_receipt_digest bytea, p_correlation_id uuid)
      RETURNS TABLE (
        receipt_id                 uuid,
        purpose                    text,
        validated_at               timestamptz(6),
        expires_at                 timestamptz(6),
        email_verified             boolean,
        issuer_key                 text,
        receipt_schema_version     text,
        bootstrap_principal_digest bytea,
        context_org                uuid
      )
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE r identity_receipt_nonces%ROWTYPE;
              v_principal bytea; v_hex text; v_org uuid; v_proof text;
      BEGIN
        SELECT * INTO r FROM identity_receipt_nonces WHERE receipt_digest = p_receipt_digest;
        IF NOT FOUND THEN RETURN; END IF;

        v_principal := coalesce(r.bootstrap_principal_digest, r.identity_principal_digest);
        v_hex := encode(v_principal, 'hex');
        v_org := f1_bootstrap_principal_uuid(v_principal);
        v_proof := f1_context_proof(v_hex, v_org::text);
        PERFORM set_config('app.bootstrap_principal_digest', v_hex, true);
        PERFORM set_config('app.context_org', v_org::text, true);
        PERFORM set_config('app.f1_proof', v_proof, true);

        RETURN QUERY SELECT r.id, r.purpose, r.validated_at, r.expires_at, r.email_verified,
                            r.issuer_key, r.receipt_schema_version, r.bootstrap_principal_digest, v_org;
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_enter_bootstrap_context(bytea, uuid) FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION f1_enter_bootstrap_context(bytea, uuid) TO f1_runtime;
    SQL

    # Single-use nonce consumption, recorded atomically inside the caller's unit
    # of work. Returns the outcome actually stored: a second 'consumed' attempt
    # loses the unique race and reports the existing binding.
    execute <<~SQL
      CREATE FUNCTION f1_consume_receipt_nonce(
        p_id uuid, p_created_at timestamptz(6), p_receipt_id uuid, p_receipt_digest bytea,
        p_command_execution_id uuid, p_consumed_at timestamptz(6), p_outcome text, p_reason_code text)
      RETURNS text
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      BEGIN
        INSERT INTO identity_receipt_consumptions
          (id, schema_version, created_at, receipt_id, receipt_digest,
           command_execution_id, consumed_at, outcome, reason_code)
        VALUES
          (p_id, '1.0', p_created_at, p_receipt_id, p_receipt_digest,
           p_command_execution_id, p_consumed_at, p_outcome, p_reason_code);
        RETURN p_outcome;
      EXCEPTION WHEN unique_violation THEN
        RETURN 'already_consumed';
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_consume_receipt_nonce(uuid, timestamptz, uuid, bytea, uuid, timestamptz, text, text) FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION f1_consume_receipt_nonce(uuid, timestamptz, uuid, bytea, uuid, timestamptz, text, text) TO f1_runtime;
    SQL
  end

  def down
    execute <<~SQL
      DROP FUNCTION IF EXISTS f1_consume_receipt_nonce(uuid, timestamptz, uuid, bytea, uuid, timestamptz, text, text);
      DROP FUNCTION IF EXISTS f1_enter_bootstrap_context(bytea, uuid);
      DROP TABLE IF EXISTS identity_receipt_consumptions;
      DROP TABLE IF EXISTS identity_receipt_nonces;
    SQL
  end
end
