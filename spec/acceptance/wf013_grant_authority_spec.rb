# frozen_string_literal: true

require "rails_helper"

# Effective grant authority and protected authority, replacing the structural
# approximation the invitation blocks deferred.
#
# ":244 the requester can offer only a role/scope/permission set it may grant
# under the effective-permission algorithm and cannot use invitation creation to
# bypass protected approval"; ":329 step 4 … require any protected permission to
# appear in the Assignment's approved protected allowlist or in the expressly
# defined first-admin/bootstrap exception".
RSpec.describe "WF-013 grant authority and protected authority", type: :acceptance,
               acceptance_ids: ["AC-CAP-013", "AC-WF-013"],
               test_types: %w[TYP-SEC TYP-DATA] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def org_scope = Digest::SHA256.digest("scope:organization")

  let(:org) { TenantSeeder.create_organization }

  def ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(fixed_now),
                                               ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)

  # An actor with an OrganizationAdmin Assignment shaped exactly as asked.
  def admin(allowlist: [], bootstrap: false, scope: org_scope)
    account = TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                          subject: "admin-#{SecureRandom.hex(6)}")
    TenantSeeder.create_role_assignment(organization_id: org, account_id: account,
                                        canonical_role: "OrganizationAdmin", scope_sha256: scope,
                                        protected_permission_allowlist: allowlist,
                                        bootstrap_admin_exception: bootstrap)
    TenantSeeder.create_access_policy(organization_id: org) if DbInspector.count("access_policies").zero?
    { account_id: account,
      session_id: TenantSeeder.create_session(organization_id: org, account_id: account,
                                              issued_at: fixed_now - 900) }
  end

  def create(actor, role: "MarketingOperator", scope: org_scope, key: "g-#{SecureRandom.hex(3)}")
    cmd = Workflows::Wf013::Commands::CreateInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      session_id: actor[:session_id], target_email: "t-#{SecureRandom.hex(4)}@example.com",
      target_identity_issuer_key: nil, target_identity_subject: nil, canonical_role: role,
      permission_mode: "standard", persona: nil, scope_sha256: scope,
      intended_assignment_expires_at: nil, requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::CreateInvitation.new.call(command: cmd, request_context: ctx)
  end

  describe "a requester cannot grant authority it does not hold" do
    it "refuses an OrganizationAdmin with no approved role.manage and no bootstrap exception" do
      result = create(admin)

      expect(result).to be_failure
      expect(result.reason_code).to eq("missing_authority")
      expect(DbInspector.count("invitations")).to eq(0)
    end

    it "permits an OrganizationAdmin whose Assignment carries approved role.manage" do
      expect(create(admin(allowlist: ["role.manage"]))).to be_success
    end

    it "permits the bootstrap first OrganizationAdmin, the sole ratified exception" do
      expect(create(admin(bootstrap: true))).to be_success
    end

    it "refuses an offer whose scope the requester's own Assignment does not contain" do
      narrow = admin(allowlist: ["role.manage"], scope: Digest::SHA256.digest("scope:project:alpha"))
      result = create(narrow, scope: Digest::SHA256.digest("scope:project:beta"))

      expect(result).to be_failure
      expect(result.reason_code).to eq("grant_scope_exceeded")
      expect(DbInspector.count("invitations")).to eq(0)
    end

    it "permits an exactly matching narrower scope" do
      scope = Digest::SHA256.digest("scope:project:alpha")
      expect(create(admin(allowlist: ["role.manage"], scope:), scope:)).to be_success
    end
  end

  describe "protected authority cannot be conferred without approval" do
    it "still routes a protected offer to approval rather than granting it directly" do
      result = create(admin(bootstrap: true), role: "OrganizationAdmin")

      expect(result).to be_success
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("pending_approval")
      expect(DbInspector.count("scheduled_actions")).to eq(0)
    end

    it "refuses a protected capability to an Assignment whose allowlist omits it" do
      security = TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                             subject: "sec-#{SecureRandom.hex(6)}")
      TenantSeeder.create_role_assignment(organization_id: org, account_id: security,
                                          canonical_role: "SecurityOperator",
                                          protected_permission_allowlist: ["security.investigate"])
      TenantSeeder.create_access_policy(organization_id: org) if DbInspector.count("access_policies").zero?
      session = TenantSeeder.create_session(organization_id: org, account_id: security, issued_at: fixed_now - 900)

      inv = TenantSeeder.create_invitation(organization_id: org, state: "pending_approval",
                                           canonical_role: "OrganizationAdmin")
      cmd = Workflows::Wf013::Commands::DecideInvitation.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "d", schema_version: "1.0", session_id: session,
        invitation_id: inv[:invitation_id], expected_state_version: 0, decision: "approve",
        reason: nil, requested_at_utc: fixed_now
      )
      result = Workflows::Wf013::Handlers::DecideInvitation.new.call(command: cmd, request_context: ctx)

      # It holds a protected allowlist, just not the one this action needs.
      expect(result.reason_code).to eq("missing_authority")
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("pending_approval")
    end
  end

  describe "the allowlist is an immutable historical fact" do
    it "refuses to edit an approved allowlist, even from an owner connection" do
      actor = admin(allowlist: ["role.manage"])
      assignment = DbInspector.one("SELECT id FROM role_assignments WHERE account_id = $1::uuid",
                                   [actor[:account_id]])["id"]

      expect do
        DbInspector.connection.exec_params(
          "UPDATE role_assignments SET protected_permission_allowlist = $2::jsonb WHERE id = $1::uuid",
          [assignment, JSON.generate(%w[role.manage account.delete])]
        )
      end.to raise_error(PG::Error, /allowlist_immutable/)
    end

    it "refuses to grant the bootstrap exception to a later Assignment" do
      actor = admin(bootstrap: true)
      assignment = DbInspector.one("SELECT id FROM role_assignments WHERE account_id = $1::uuid",
                                   [actor[:account_id]])["id"]

      expect do
        DbInspector.connection.exec_params(
          "UPDATE role_assignments SET bootstrap_admin_exception = false WHERE id = $1::uuid", [assignment]
        )
      end.to raise_error(PG::Error, /bootstrap_exception_immutable/)
    end

    it "admits at most one bootstrap OrganizationAdmin per Organization" do
      admin(bootstrap: true)
      second = TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                           subject: "second-#{SecureRandom.hex(6)}")
      expect do
        TenantSeeder.create_role_assignment(organization_id: org, account_id: second,
                                            canonical_role: "OrganizationAdmin", bootstrap_admin_exception: true)
      end.to raise_error(PG::UniqueViolation, /one_bootstrap_admin_per_organization/)
    end

    it "refuses the bootstrap exception on a non-administrator role" do
      account = TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                            subject: "mo-#{SecureRandom.hex(6)}")
      expect do
        TenantSeeder.create_role_assignment(organization_id: org, account_id: account,
                                            canonical_role: "MarketingOperator", bootstrap_admin_exception: true)
      end.to raise_error(PG::CheckViolation, /bootstrap_exception_is_admin/)
    end
  end

  describe "revoked or expired Assignments confer nothing" do
    it "refuses a requester whose Assignment has been revoked" do
      actor = admin(allowlist: ["role.manage"])
      DbInspector.connection.exec_params(
        "UPDATE role_assignments SET status = 'revoked', terminated_at = now() WHERE account_id = $1::uuid",
        [actor[:account_id]]
      )
      expect(create(actor).reason_code).to eq("missing_authority")
    end

    it "refuses a requester whose Assignment has expired, with equality belonging to expiry" do
      account = TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                            subject: "exp-#{SecureRandom.hex(6)}")
      TenantSeeder.create_role_assignment(organization_id: org, account_id: account,
                                          canonical_role: "OrganizationAdmin", scope_sha256: org_scope,
                                          protected_permission_allowlist: ["role.manage"],
                                          # A protected Assignment's expiry is within 30 days of
                                          # effectiveness (:316), and equality belongs to expiry.
                                          effective_at: fixed_now - (10 * 24 * 3600), expires_at: fixed_now)
      TenantSeeder.create_access_policy(organization_id: org) if DbInspector.count("access_policies").zero?
      session = TenantSeeder.create_session(organization_id: org, account_id: account, issued_at: fixed_now - 900)

      expect(create({ account_id: account, session_id: session }).reason_code).to eq("missing_authority")
    end
  end
end
