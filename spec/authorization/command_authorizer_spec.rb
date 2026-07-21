# frozen_string_literal: true

require "rails_helper"

# Permission Baseline capability evaluation + Session-based organization-actor
# authorization (WORKFLOW_SPECIFICATIONS.md § effective authorization :322-329,
# Permission Baseline :140; SECURITY_PERFORMANCE.md PRULE-044). The evaluator
# authenticates a Session (deriving the actor+Organization from the record),
# resolves the active Access Policy and the actor's active effective Role
# Assignments, and reads the ratified baseline cell for a capability.
RSpec.describe "Permission Baseline + CommandAuthorizer", type: :authorization do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)

  # authenticate + authorize inside one unit of work; returns {auth: sym} on an
  # authentication/actor-context failure, else {actor:, decision:}.
  def evaluate(session_id, capability: "invitation.revoke", now: fixed_now)
    out = nil
    Platform::UnitOfWork.run do |conn|
      store = IdentityAccess::Infrastructure::AuthorizationStore.new(conn.raw_connection)
      authz = IdentityAccess::Authorization::CommandAuthorizer.new(store)
      actor = authz.authenticate(session_id:, now:, correlation_id: SecureRandom.uuid_v7)
      out = actor.is_a?(Symbol) ? { auth: actor } : { actor:, decision: authz.authorize(actor:, capability:, now:) }
    end
    out
  end

  describe "Platform::PermissionBaseline (permission-baseline-v1)" do
    it "allows invitation.revoke only for OrganizationAdmin" do
      expect(Platform::PermissionBaseline.permits?("invitation.revoke", ["OrganizationAdmin"])).to be(true)
      expect(Platform::PermissionBaseline.permits?("invitation.revoke", %w[MarketingOperator SecurityOperator TechnicalImplementer BillingOperator])).to be(false)
      expect(Platform::PermissionBaseline.permits?("invitation.revoke", [])).to be(false)
    end

    it "raises on an unmapped capability rather than silently deciding" do
      expect { Platform::PermissionBaseline.permits?("invitation.approve", ["OrganizationAdmin"]) }
        .to raise_error(Platform::InvariantViolation)
    end
  end

  describe "authorize(invitation.revoke)" do
    it "allows an OrganizationAdmin and records the decision evidence" do
      admin = TenantSeeder.seed_authorized_admin
      out = evaluate(admin[:session_id])

      expect(out[:actor].account_id).to eq(admin[:account_id])
      expect(out[:actor].organization_id).to eq(admin[:organization_id])
      d = out[:decision]
      expect(d.allowed?).to be(true)
      expect(d.reason).to eq("authorized")
      expect(d.policy_snapshot_id).to be_present
      expect(d.role_assignment_versions.size).to eq(1)
      expect(d.organization_epoch).to eq(7)
    end

    it "denies a non-admin role with missing_authority" do
      admin = TenantSeeder.seed_authorized_admin(canonical_role: "MarketingOperator")
      d = evaluate(admin[:session_id])[:decision]
      expect(d.allowed?).to be(false)
      expect(d.reason).to eq("missing_authority")
    end

    it "denies an actor with no effective Role Assignment" do
      admin = TenantSeeder.seed_authorized_admin(canonical_role: nil)
      expect(evaluate(admin[:session_id])[:decision].reason).to eq("missing_authority")
    end

    it "does not authorize from a cross-Organization OrganizationAdmin assignment" do
      admin = TenantSeeder.seed_authorized_admin(canonical_role: nil)
      other_org = TenantSeeder.create_organization
      TenantSeeder.create_role_assignment(organization_id: other_org, account_id: admin[:account_id],
                                          canonical_role: "OrganizationAdmin")
      expect(evaluate(admin[:session_id])[:decision].allowed?).to be(false)
    end

    it "denies an expired OrganizationAdmin assignment" do
      admin = TenantSeeder.seed_authorized_admin(canonical_role: nil)
      TenantSeeder.create_role_assignment(organization_id: admin[:organization_id], account_id: admin[:account_id],
                                          canonical_role: "OrganizationAdmin", expires_at: fixed_now - 3600)
      expect(evaluate(admin[:session_id])[:decision].allowed?).to be(false)
    end

    it "denies a revoked OrganizationAdmin assignment" do
      admin = TenantSeeder.seed_authorized_admin(canonical_role: nil)
      TenantSeeder.create_role_assignment(organization_id: admin[:organization_id], account_id: admin[:account_id],
                                          canonical_role: "OrganizationAdmin", status: "revoked")
      expect(evaluate(admin[:session_id])[:decision].allowed?).to be(false)
    end

    it "returns policy_unavailable when no active Access Policy exists" do
      admin = TenantSeeder.seed_authorized_admin(with_policy: false)
      d = evaluate(admin[:session_id])[:decision]
      expect(d.allowed?).to be(false)
      expect(d.reason).to eq("policy_unavailable")
    end
  end

  describe "authentication / actor-context failures" do
    it "rejects an unknown Session" do
      expect(evaluate(SecureRandom.uuid_v7)[:auth]).to eq(:session_invalid)
    end

    it "rejects a revoked Session" do
      admin = TenantSeeder.seed_authorized_admin(session_status: "revoked")
      expect(evaluate(admin[:session_id])[:auth]).to eq(:session_invalid)
    end

    it "rejects an idle-expired Session (now >= idle_expires_at)" do
      admin = TenantSeeder.seed_authorized_admin(issued_at: Time.utc(2026, 7, 20, 9, 0, 0))
      expect(evaluate(admin[:session_id])[:auth]).to eq(:session_invalid)
    end

    it "rejects an inactive Account before assignment evaluation" do
      admin = TenantSeeder.seed_authorized_admin(account_status: "suspended")
      expect(evaluate(admin[:session_id])[:auth]).to eq(:account_inactive)
    end

    it "rejects an inactive Organization" do
      org = TenantSeeder.create_organization(status: "suspended")
      admin = TenantSeeder.seed_authorized_admin(organization_id: org)
      expect(evaluate(admin[:session_id])[:auth]).to eq(:organization_inactive)
    end
  end
end
