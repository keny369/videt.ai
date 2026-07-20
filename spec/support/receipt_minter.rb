# frozen_string_literal: true

require "pg"
require "digest"
require "securerandom"

# Mints Identity Validation Receipts the way the approved identity service would,
# using a schema-owner connection because the receipt store carries no runtime
# grant (schemas/POSTGRESQL_SCHEMA.md § restricted locators). Tests use this to
# arrange the precondition WF-001 requires; production minting is the managed
# identity flow, a later slice.
module ReceiptMinter
  module_function

  def owner_connection
    @owner_connection ||= begin
      cfg = ActiveRecord::Base.connection_db_config.configuration_hash
      PG.connect(
        host: cfg[:host], port: cfg[:port], dbname: cfg[:database], user: "f1_schema_owner"
      )
    end
  end

  # Send raw bytes to a bytea column in binary format.
  def bytea(bytes) = { value: bytes, format: 1 }

  def ts(time) = time.getutc.iso8601(6)

  # Returns { receipt_id:, receipt_digest:, nonce_sha256:, principal_digest:,
  #           issuer_key:, subject:, normalized_email:, validated_at:, expires_at: }.
  def mint_bootstrap_grant_receipt(validated_at:, issuer_key: "https://id.example/oidc",
                                   subject: "sub-#{SecureRandom.hex(8)}",
                                   normalized_email: "user-#{SecureRandom.hex(4)}@example.com",
                                   display_name: "Test Principal")
    principal_digest = Digest::SHA256.digest("#{issuer_key}\n#{subject}")
    receipt_digest = Digest::SHA256.digest("jws:#{SecureRandom.hex(24)}")
    nonce_sha256 = Digest::SHA256.digest("nonce:#{SecureRandom.hex(24)}")
    email_sha256 = Digest::SHA256.digest(normalized_email)
    validated = validated_at.getutc.floor(6)
    expires = validated + 600 # exactly 10 minutes

    params = [
      SecureRandom.uuid_v7, "1.0", ts(validated), bytea(receipt_digest), "onboarding-interim-v1",
      issuer_key, subject, normalized_email, bytea(email_sha256), display_name, true,
      "bootstrap_grant_request", ts(validated), ts(expires), bytea(nonce_sha256),
      bytea(principal_digest), bytea(principal_digest), "security_audit"
    ]
    sql = <<~SQL
      INSERT INTO identity_receipt_nonces
        (id, schema_version, created_at, receipt_digest, receipt_schema_version,
         issuer_key, issuer_subject, normalized_email, normalized_email_sha256, display_name, email_verified,
         purpose, validated_at, expires_at, nonce_sha256,
         identity_principal_digest, bootstrap_principal_digest, retention_class)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18)
      RETURNING id
    SQL
    owner_connection.exec_params(sql, params)

    {
      receipt_digest: receipt_digest, nonce_sha256: nonce_sha256, principal_digest: principal_digest,
      issuer_key: issuer_key, subject: subject, normalized_email: normalized_email,
      validated_at: validated, expires_at: expires
    }
  end

  # An existing-account sign-in receipt (purpose existing_account_sign_in,
  # WORKFLOW_SPECIFICATIONS.md § onboarding-interim-v1). It carries the identity
  # authentication-assurance version and mfa_satisfied and, unlike the bootstrap
  # purposes, no bootstrap_principal_digest. The Organization is NOT bound by the
  # receipt; it is supplied by the sign-in command.
  #
  # Returns { receipt_id:, receipt_digest:, nonce_sha256:, principal_digest:,
  #           issuer_key:, subject:, normalized_email:, validated_at:, expires_at:,
  #           assurance_version:, mfa_satisfied: }.
  def mint_sign_in_receipt(validated_at:, issuer_key: "https://id.example/oidc",
                           subject: "sub-#{SecureRandom.hex(8)}",
                           normalized_email: "user-#{SecureRandom.hex(4)}@example.com",
                           display_name: "Test Principal",
                           assurance_version: "assurance-v1", mfa_satisfied: true)
    principal_digest = Digest::SHA256.digest("#{issuer_key}\n#{subject}")
    receipt_digest = Digest::SHA256.digest("jws:#{SecureRandom.hex(24)}")
    nonce_sha256 = Digest::SHA256.digest("nonce:#{SecureRandom.hex(24)}")
    email_sha256 = Digest::SHA256.digest(normalized_email)
    validated = validated_at.getutc.floor(6)
    expires = validated + 600 # exactly 10 minutes

    id = SecureRandom.uuid_v7
    params = [
      id, "1.0", ts(validated), bytea(receipt_digest), "onboarding-interim-v1",
      issuer_key, subject, normalized_email, bytea(email_sha256), display_name, true,
      "existing_account_sign_in", ts(validated), ts(expires), bytea(nonce_sha256),
      bytea(principal_digest), assurance_version, (mfa_satisfied ? "true" : "false"), "security_audit"
    ]
    sql = <<~SQL
      INSERT INTO identity_receipt_nonces
        (id, schema_version, created_at, receipt_digest, receipt_schema_version,
         issuer_key, issuer_subject, normalized_email, normalized_email_sha256, display_name, email_verified,
         purpose, validated_at, expires_at, nonce_sha256,
         identity_principal_digest, bootstrap_principal_digest, assurance_version, mfa_satisfied, retention_class)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,NULL,$17,$18,$19)
      RETURNING id
    SQL
    owner_connection.exec_params(sql, params)

    {
      receipt_id: id, receipt_digest: receipt_digest, nonce_sha256: nonce_sha256, principal_digest: principal_digest,
      issuer_key: issuer_key, subject: subject, normalized_email: normalized_email,
      validated_at: validated, expires_at: expires,
      assurance_version: assurance_version, mfa_satisfied: mfa_satisfied
    }
  end

  # An invitation-response receipt (purpose invitation_response,
  # WORKFLOW_SPECIFICATIONS.md § onboarding-interim-v1). Like sign-in it carries no
  # bootstrap principal; unlike sign-in it carries no assurance/MFA. Acceptance
  # matches its normalized_email_sha256 to the Invitation target and, when the
  # Invitation is identity-bound, its issuer/subject.
  #
  # Returns the same shape as the other minters plus normalized_email_sha256.
  def mint_invitation_receipt(validated_at:, issuer_key: "https://id.example/oidc",
                              subject: "sub-#{SecureRandom.hex(8)}",
                              normalized_email: "invitee-#{SecureRandom.hex(4)}@example.com",
                              display_name: "Invited Principal")
    principal_digest = Digest::SHA256.digest("#{issuer_key}\n#{subject}")
    receipt_digest = Digest::SHA256.digest("jws:#{SecureRandom.hex(24)}")
    nonce_sha256 = Digest::SHA256.digest("nonce:#{SecureRandom.hex(24)}")
    email_sha256 = Digest::SHA256.digest(normalized_email)
    validated = validated_at.getutc.floor(6)
    expires = validated + 600 # exactly 10 minutes

    id = SecureRandom.uuid_v7
    params = [
      id, "1.0", ts(validated), bytea(receipt_digest), "onboarding-interim-v1",
      issuer_key, subject, normalized_email, bytea(email_sha256), display_name, true,
      "invitation_response", ts(validated), ts(expires), bytea(nonce_sha256),
      bytea(principal_digest), "security_audit"
    ]
    sql = <<~SQL
      INSERT INTO identity_receipt_nonces
        (id, schema_version, created_at, receipt_digest, receipt_schema_version,
         issuer_key, issuer_subject, normalized_email, normalized_email_sha256, display_name, email_verified,
         purpose, validated_at, expires_at, nonce_sha256,
         identity_principal_digest, bootstrap_principal_digest, assurance_version, mfa_satisfied, retention_class)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,NULL,NULL,NULL,$17)
      RETURNING id
    SQL
    owner_connection.exec_params(sql, params)

    {
      receipt_id: id, receipt_digest: receipt_digest, nonce_sha256: nonce_sha256, principal_digest: principal_digest,
      issuer_key: issuer_key, subject: subject, normalized_email: normalized_email,
      normalized_email_sha256: email_sha256, validated_at: validated, expires_at: expires
    }
  end

  # Owner-side cleanup for truncation specs that bypass transactional fixtures.
  def truncate_all
    owner_connection.exec(<<~SQL)
      TRUNCATE identity_receipt_nonces, identity_receipt_consumptions, bootstrap_grants,
               command_executions, command_results, idempotency_records,
               pretenant_authorization_decisions, audit_record_registry, event_registry,
               organizations, accounts, role_assignments, access_policies, sessions,
               invitations, invitation_reference_registry
      RESTART IDENTITY CASCADE;
    SQL
  end
end
