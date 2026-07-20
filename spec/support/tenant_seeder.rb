# frozen_string_literal: true

require "digest"
require "securerandom"

# Seeds tenant rows (Organization, Account, Role Assignment, Access Policy) that
# existing-account sign-in requires as preconditions. These are normally created
# by the WF-001 self-service bootstrap_organization branch, which is a later
# slice; until it exists, the acceptance suite arranges them directly.
#
# It writes through the BYPASSRLS superuser connection (the DbInspector
# connection): the tenant tables are FORCE ROW LEVEL SECURITY, so even the schema
# owner cannot insert a row outside a proved context. Reusing the superuser
# connection keeps seeding out of the runtime path entirely.
module TenantSeeder
  module_function

  def conn = DbInspector.connection

  def bytea(bytes) = { value: bytes, format: 1 }
  def ts(time) = time.getutc.iso8601(6)

  def create_organization(id: SecureRandom.uuid_v7, status: "active",
                          authorization_epoch: 7, display_name: "Acme Org")
    conn.exec_params(<<~SQL, [id, status, authorization_epoch, display_name])
      INSERT INTO organizations
        (id, state_version, lock_version, created_at, updated_at, correlation_id,
         status, authorization_epoch, display_name, activated_at, suspended_at, closed_at)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,$3,$4,
              CASE WHEN $2 <> 'pending' THEN now() END,
              CASE WHEN $2 = 'suspended' THEN now() END,
              CASE WHEN $2 = 'closed' THEN now() END)
    SQL
    id
  end

  def create_account(organization_id:, issuer_key:, subject:, id: SecureRandom.uuid_v7,
                     email: "user-#{SecureRandom.hex(4)}@example.com", display_name: "Test Principal",
                     status: "active", receipt_digest: nil)
    email_sha = Digest::SHA256.digest(email)
    params = [id, organization_id, issuer_key, subject, email, bytea(email_sha), display_name,
              status, (receipt_digest ? bytea(receipt_digest) : nil)]
    conn.exec_params(<<~SQL, params)
      INSERT INTO accounts
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
         identity_issuer_key, identity_subject, normalized_email, normalized_email_sha256, display_name,
         status, identity_receipt_digest, activated_at, suspended_at, revoked_at)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,$3,$4,$5,$6,$7,$8,$9,
              CASE WHEN $8 = 'active' THEN now() END,
              CASE WHEN $8 = 'suspended' THEN now() END,
              CASE WHEN $8 = 'revoked' THEN now() END)
    SQL
    id
  end

  # effective_at defaults well before any sign-in fixed clock so the Assignment is
  # effective; pass status/expiry to build an ineffective or expired Assignment.
  def create_role_assignment(organization_id:, account_id:, canonical_role: "OrganizationAdmin",
                             id: SecureRandom.uuid_v7, permission_mode: "standard", persona: nil,
                             status: "active", effective_at: Time.utc(2026, 1, 1), expires_at: nil)
    params = [id, organization_id, account_id, canonical_role, permission_mode, persona,
              status, (effective_at ? ts(effective_at) : nil), (expires_at ? ts(expires_at) : nil)]
    conn.exec_params(<<~SQL, params)
      INSERT INTO role_assignments
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id, account_id,
         canonical_role, permission_mode, persona, status, effective_at, expires_at)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,$3,$4,$5,$6,$7,$8::timestamptz,$9::timestamptz)
    SQL
    id
  end

  def create_access_policy(organization_id:, id: SecureRandom.uuid_v7, status: "active",
                           semantic_version: "access-policy-v1")
    conn.exec_params(<<~SQL, [id, organization_id, status, semantic_version])
      INSERT INTO access_policies
        (id, state_version, created_at, updated_at, correlation_id, organization_id,
         policy_type, semantic_version, status, effective_at)
      VALUES ($1,0,now(),now(),gen_random_uuid(),$2,'access',$4,$3,
              CASE WHEN $3 = 'active' THEN now() END)
    SQL
    id
  end

  # Convenience: an active Organization with an active Account, one active
  # Role Assignment (OrganizationAdmin by default) and an active Access Policy,
  # ready to sign in. Returns { organization_id:, account_id: }.
  def seed_signed_in_ready(issuer_key:, subject:, org_status: "active", account_status: "active",
                           canonical_role: "OrganizationAdmin", with_role: true, with_policy: true,
                           permission_mode: "standard", persona: nil, receipt_digest: nil)
    org_id = create_organization(status: org_status)
    account_id = create_account(organization_id: org_id, issuer_key:, subject:,
                                status: account_status, receipt_digest:)
    if with_role
      create_role_assignment(organization_id: org_id, account_id:, canonical_role:,
                             permission_mode:, persona:)
    end
    create_access_policy(organization_id: org_id) if with_policy
    { organization_id: org_id, account_id: account_id }
  end
end
