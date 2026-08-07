# frozen_string_literal: true

# Return the receipt's verified email from `f1_enter_self_service_context`.
#
# THE DEFECT. WF-001 self-service bootstrap sets the new Account's `normalized_email`
# from the receipt, and falls back to `user-<receipt_id>@example.com` when the receipt
# carries none:
#
#   def receipt_email(receipt) = receipt["normalized_email"] || "user-#{receipt["receipt_id"]}@example.com"
#
# The fallback was ALWAYS taken, because this function never returned the column. Every
# Organization created through self-service therefore got an Account whose email was a
# synthetic placeholder built from a receipt id, while the real verified address —
# present on the receipt row, and the whole point of verifying it — was discarded.
#
# It stayed invisible because nothing read the Account back by address. The bootstrap
# specs assert the Account is active and correctly linked, not what it is called, and
# there was no sign-in-by-email path and no screen displaying the account. Building both
# surfaced it immediately: the organization home showed a `user-019fda13-…@example.com`
# nobody recognises, and existing-account sign-in could not find the Account at all,
# because the address the person types has no row matching it.
#
# The receipt is the identity proof, so the address it carries is the one the Account
# must have. `normalized_email` is added to the return, and the sibling
# `identity_principal_digest` fallback is preserved exactly as before.
#
# A RETURNS TABLE signature cannot be widened by CREATE OR REPLACE, so the function is
# dropped and recreated. `f1:db:grants` re-applies the runtime EXECUTE grant, which
# `bin/f1db f1:db:grants` does from the single source in F1::RuntimeGrants.
class SelfServiceContextReturnsEmail < ActiveRecord::Migration[8.1]
  def up = redefine(with_email: true)
  def down = redefine(with_email: false)

  private

  def redefine(with_email:)
    execute "DROP FUNCTION IF EXISTS f1_enter_self_service_context(bytea, uuid, uuid);"
    execute <<~SQL
      CREATE FUNCTION f1_enter_self_service_context(p_receipt_digest bytea, p_org_id uuid, p_correlation_id uuid)
      RETURNS TABLE (
        receipt_id                 uuid,
        purpose                    text,
        validated_at               timestamptz(6),
        expires_at                 timestamptz(6),
        email_verified             boolean,
        mfa_satisfied              boolean,
        issuer_key                 text,
        issuer_subject             text,
        receipt_schema_version     text,
        assurance_version          text,
        bootstrap_principal_digest bytea,
        organization_id            uuid#{if with_email
          ",\n        normalized_email           text"
        end}
      )
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, public
      AS $$
      DECLARE r identity_receipt_nonces%ROWTYPE; v_principal bytea; v_hex text; v_proof text;
      BEGIN
        SELECT * INTO r FROM identity_receipt_nonces WHERE receipt_digest = p_receipt_digest;
        IF NOT FOUND THEN RETURN; END IF;

        v_principal := coalesce(r.bootstrap_principal_digest, r.identity_principal_digest);
        v_hex := encode(v_principal, 'hex');
        v_proof := f1_context_proof(v_hex, p_org_id::text);
        PERFORM set_config('app.bootstrap_principal_digest', v_hex, true);
        PERFORM set_config('app.context_org', p_org_id::text, true);
        PERFORM set_config('app.f1_proof', v_proof, true);

        RETURN QUERY SELECT r.id, r.purpose, r.validated_at, r.expires_at, r.email_verified,
                            r.mfa_satisfied, r.issuer_key, r.issuer_subject, r.receipt_schema_version,
                            r.assurance_version, v_principal, p_org_id#{", r.normalized_email" if with_email};
      END;
      $$;
      REVOKE ALL ON FUNCTION f1_enter_self_service_context(bytea, uuid, uuid) FROM PUBLIC;
    SQL
    execute "GRANT EXECUTE ON FUNCTION f1_enter_self_service_context(bytea, uuid, uuid) TO f1_runtime;"
  end
end
