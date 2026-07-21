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
                             status: "active", effective_at: Time.utc(2026, 1, 1), expires_at: nil,
                             scope_sha256: nil)
    params = [id, organization_id, account_id, canonical_role, permission_mode, persona,
              status, (effective_at ? ts(effective_at) : nil), (expires_at ? ts(expires_at) : nil),
              (scope_sha256 ? bytea(scope_sha256) : nil)]
    conn.exec_params(<<~SQL, params)
      INSERT INTO role_assignments
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id, account_id,
         canonical_role, permission_mode, persona, status, effective_at, expires_at, scope_sha256)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,$3,$4,$5,$6,$7,$8::timestamptz,$9::timestamptz,$10)
    SQL
    id
  end

  # Seeds an active Invitation (WF-001 § invitation) plus its global reference
  # locator, consistently. Invitation creation is a later WF; until then the
  # acceptance suite arranges the precondition directly. `activated_at` drives the
  # 7-day active expiry (CHECK); pass an old activated_at to build an expired one.
  # Returns { invitation_id:, reference: (32 bytes), reference_digest:,
  #           target_email:, target_email_sha256:, canonical_role:, permission_mode:,
  #           persona:, scope_sha256:, organization_id: }.
  def create_invitation(organization_id:, id: SecureRandom.uuid_v7,
                        target_email: "invitee-#{SecureRandom.hex(4)}@example.com",
                        target_identity_issuer_key: nil, target_identity_subject: nil,
                        canonical_role: "MarketingOperator", permission_mode: "standard", persona: nil,
                        scope_sha256: Digest::SHA256.digest("scope:organization"),
                        state: "active", activated_at: Time.utc(2026, 7, 18, 10, 0, 0),
                        requester_account_id: nil)
    reference = SecureRandom.random_bytes(32)
    reference_digest = Digest::SHA256.digest(reference)
    email_sha = Digest::SHA256.digest(target_email)
    activated = %w[active accepted declined rejected revoked expired].include?(state) ? activated_at : nil
    expires = activated ? (activated + (7 * 24 * 3600)) : nil
    terminal = %w[accepted declined rejected revoked expired].include?(state) ? activated_at + (24 * 3600) : nil

    inv_params = [id, organization_id, bytea(reference_digest), target_email, bytea(email_sha),
                  target_identity_issuer_key, target_identity_subject, canonical_role, permission_mode,
                  persona, (scope_sha256 ? bytea(scope_sha256) : nil), state,
                  (activated ? ts(activated) : nil), (expires ? ts(expires) : nil), (terminal ? ts(terminal) : nil),
                  requester_account_id]
    conn.exec_params(<<~SQL, inv_params)
      INSERT INTO invitations
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
         opaque_reference_sha256, target_email, target_email_sha256, target_identity_issuer_key,
         target_identity_subject, canonical_role, permission_mode, persona, scope_sha256, state,
         activated_at, expires_at, terminated_at, requester_account_id)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,
              $13::timestamptz,$14::timestamptz,$15::timestamptz,$16::uuid)
    SQL
    reg_params = [bytea(reference_digest), organization_id, id, state,
                  (activated ? ts(activated) : nil), (expires ? ts(expires) : nil), (terminal ? ts(terminal) : nil)]
    conn.exec_params(<<~SQL, reg_params)
      INSERT INTO invitation_reference_registry
        (opaque_reference_sha256, created_at, updated_at, organization_id, invitation_id, invitation_state,
         activated_at, expires_at, terminal_at, retention_class)
      VALUES ($1,now(),now(),$2,$3,$4,$5::timestamptz,$6::timestamptz,$7::timestamptz,'identity_commercial')
    SQL

    { invitation_id: id, reference: reference, reference_digest: reference_digest,
      target_email: target_email, target_email_sha256: email_sha, canonical_role: canonical_role,
      permission_mode: permission_mode, persona: persona, scope_sha256: scope_sha256,
      organization_id: organization_id }
  end

  # Seeds a Session for an org actor. Defaults are valid at a 2026-07-20 10:00 fixed
  # clock (issued 09:45 -> idle 10:15, absolute 21:45). Pass an old issued/last time
  # or a terminal status to build an expired/revoked Session.
  def create_session(organization_id:, account_id:, id: SecureRandom.uuid_v7, status: "active",
                     issued_at: Time.utc(2026, 7, 20, 9, 45, 0), last_activity_at: nil,
                     authorization_context_version: 7, creation_reason: "existing_account_sign_in")
    last = last_activity_at || issued_at
    idle = last + (30 * 60)
    absolute = issued_at + (12 * 3600)
    terminated = %w[revoked expired].include?(status) ? issued_at : nil
    params = [id, organization_id, account_id, bytea(Digest::SHA256.digest("session:#{id}")),
              authorization_context_version, creation_reason, ts(issued_at), ts(last), ts(idle), ts(absolute),
              status, (terminated ? ts(terminated) : nil)]
    conn.exec_params(<<~SQL, params)
      INSERT INTO sessions
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id, account_id,
         identity_receipt_digest, authorization_context_version, creation_reason, issued_at, last_activity_at,
         idle_expires_at, absolute_expires_at, status, terminated_at)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,$3,$4,$5,$6,$7::timestamptz,$8::timestamptz,$9::timestamptz,
              $10::timestamptz,$11,$12::timestamptz)
    SQL
    id
  end

  # Convenience: an active Organization with an active Account holding an active
  # OrganizationAdmin Role Assignment, an active Access Policy, and an active
  # Session — i.e. an actor authorized for invitation.revoke. Returns
  # { organization_id:, account_id:, session_id: }.
  def seed_authorized_admin(organization_id: nil, canonical_role: "OrganizationAdmin",
                            account_status: "active", session_status: "active", with_policy: true, **session_opts)
    org = organization_id || create_organization
    account_id = create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                subject: "admin-#{SecureRandom.hex(6)}", status: account_status)
    create_role_assignment(organization_id: org, account_id:, canonical_role:) unless canonical_role.nil?
    create_access_policy(organization_id: org) if with_policy
    session_id = create_session(organization_id: org, account_id:, status: session_status, **session_opts)
    { organization_id: org, account_id: account_id, session_id: session_id }
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
