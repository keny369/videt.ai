# frozen_string_literal: true

require "rails_helper"

# The genesis is production-reachable end to end (AC-CAP-002; user Scope L). An
# Organization created ONLY by BootstrapOrganization — no fixture writes its
# authority, its policy or its Session — yields an administrator who can perform
# an ordinary authorized command through the shared authorization boundary, and
# who cannot use the bootstrap exception to bypass protected approval.
RSpec.describe "WF-001 bootstrap reachability", type: :acceptance,
               acceptance_ids: ["AC-CAP-002", "AC-WF-001"],
               test_types: %w[TYP-E2E TYP-SEC TYP-INT] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def bc = Platform::BaselineContent

  let(:identity) { { issuer_key: "https://id.example/oidc", subject: "founder-#{SecureRandom.hex(8)}" } }

  def service_ctx(now)
    Platform::RequestContext.for_service(
      service_identity_id: Platform::ServiceIdentity::IDENTITY_SERVICE,
      clock: Platform::Clock.fixed(now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
    )
  end

  def actor_ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(fixed_now),
                                                     ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)

  # Genesis through production commands only: request grant, then bootstrap.
  let(:tenant) do
    receipt = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: fixed_now - 60, **identity)
    grant_cmd = Workflows::Wf001::Commands::RequestBootstrapGrant.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: "g", schema_version: "1.0",
      receipt_digest: receipt[:receipt_digest], requested_at_utc: fixed_now - 60
    )
    raise "grant failed" unless Workflows::Wf001::Handlers::RequestBootstrapGrant.new
      .call(command: grant_cmd, request_context: service_ctx(fixed_now - 60)).success?

    boot_receipt = ReceiptMinter.mint_self_service_receipt(validated_at: fixed_now, **identity)
    boot = Workflows::Wf001::Commands::BootstrapOrganization.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: "b", schema_version: "1.0",
      receipt_digest: boot_receipt[:receipt_digest], expected_grant_version: 0,
      organization_display_name: "Genesis Co", project_display_name: "Genesis Site", project_objective: nil,
      access_policy_content_sha256: bc.access_policy_sha256,
      entitlement_policy_content_sha256: bc.entitlement_policy_sha256, plan_content_sha256: bc.plan_sha256,
      requested_at_utc: fixed_now
    )
    result = Workflows::Wf001::Handlers::BootstrapOrganization.new.call(command: boot, request_context: service_ctx(fixed_now))
    raise "bootstrap failed: #{result.reason_code}" unless result.success?

    result.payload
  end

  def account(subject = "target")
    TenantSeeder.create_account(organization_id: tenant[:organization_id], issuer_key: "https://id.example/oidc",
                                subject: "#{subject}-#{SecureRandom.hex(6)}")
  end

  it "lets the bootstrap administrator authenticate on the genesis Session and create an Invitation" do
    # The Session the genesis minted is a real, current Session under epoch 1.
    session = DbInspector.one("SELECT * FROM sessions WHERE id = $1::uuid", [tenant[:session_id]])
    expect(session["status"]).to eq("active")
    expect(session["authorization_context_version"].to_i).to eq(1)

    cmd = Workflows::Wf013::Commands::CreateInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: "inv", schema_version: "1.0",
      session_id: tenant[:session_id], target_email: "invitee-#{SecureRandom.hex(4)}@example.com",
      target_identity_issuer_key: nil, target_identity_subject: nil, canonical_role: "MarketingOperator",
      permission_mode: "standard", persona: nil, scope_sha256: Digest::SHA256.digest("scope:organization"),
      intended_assignment_expires_at: nil, requested_at_utc: fixed_now
    )
    result = Workflows::Wf013::Handlers::CreateInvitation.new.call(command: cmd, request_context: actor_ctx)

    expect(result).to be_success
    expect(DbInspector.count("invitations")).to eq(1)
  end

  it "does not let the bootstrap exception bypass protected approval for a new protected grant" do
    # The admin holds role.manage through the genesis allowlist, but a direct
    # OrganizationAdmin grant is protected and must still go to approval.
    target = account("newadmin")
    cmd = Workflows::Wf013::Commands::RequestRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: "req", schema_version: "1.0",
      session_id: tenant[:session_id], account_id: target, canonical_role: "OrganizationAdmin",
      permission_mode: "standard", persona: nil, scope_sha256: Digest::SHA256.digest("scope:organization"),
      expires_at: fixed_now + (10 * 24 * 3600), expected_authorization_epoch: 1, reason: nil,
      requested_at_utc: fixed_now
    )
    result = Workflows::Wf013::Handlers::RequestRoleAssignment.new.call(command: cmd, request_context: actor_ctx)

    expect(result).to be_success
    expect(DbInspector.one("SELECT status FROM role_assignments WHERE id = $1::uuid",
                           [result.payload[:role_assignment_id]])["status"]).to eq("pending")
  end

  it "grants the genesis admin exactly the bootstrap authority, no protected grant it did not obtain" do
    admin = DbInspector.one("SELECT * FROM role_assignments WHERE account_id = $1::uuid", [tenant[:account_id]])
    # It is the bootstrap exception (which lets it USE protected permissions), and
    # its own allowlist is the OrganizationAdmin preview — obtained by the genesis,
    # not by any test writing it.
    expect(admin["bootstrap_admin_exception"]).to eq("t")
    expect(JSON.parse(admin["protected_permission_allowlist"]))
      .to eq(Platform::PermissionBaseline.protected_permission_preview("OrganizationAdmin"))
  end
end
