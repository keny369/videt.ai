# frozen_string_literal: true

require "rails_helper"

# BootstrapOrganization under genuine concurrency (user Scope J). Two commits for
# one bootstrap principal serialize on the tier-zero principal advisory lock the
# grant path already uses, so the contested state is decided one at a time. The
# race is real — RaceHarness holds that exact lock and releases only once both
# operations are observably blocked on it — and the invariant is that one
# principal yields exactly one Organization, one consumed grant, one baseline
# BillingEntity and one bootstrap administrator, whatever the interleaving.
RSpec.describe "WF-001 bootstrap concurrency", type: :acceptance,
               acceptance_ids: ["AC-CAP-002", "AC-WF-001", "AC-PRULE-002"],
               test_types: %w[TYP-SEC TYP-DATA] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def bc = Platform::BaselineContent

  let(:identity) { { issuer_key: "https://id.example/oidc", subject: "founder-#{SecureRandom.hex(8)}" } }
  let(:principal_hex) { Digest::SHA256.hexdigest("#{identity[:issuer_key]}\n#{identity[:subject]}") }
  let(:principal_key) { RaceHarness.key_for("bootstrap-principal:#{principal_hex}") }

  def service_ctx(now)
    Platform::RequestContext.for_service(
      service_identity_id: Platform::ServiceIdentity::IDENTITY_SERVICE,
      clock: Platform::Clock.fixed(now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
    )
  end

  def issue_grant
    receipt = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: fixed_now - 60, **identity)
    cmd = Workflows::Wf001::Commands::RequestBootstrapGrant.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: "g", schema_version: "1.0",
      receipt_digest: receipt[:receipt_digest], requested_at_utc: fixed_now - 60
    )
    raise "grant failed" unless Workflows::Wf001::Handlers::RequestBootstrapGrant.new
      .call(command: cmd, request_context: service_ctx(fixed_now - 60)).success?
  end

  # A bootstrap thunk with its own fresh self-service receipt (one nonce each).
  def bootstrap_thunk(key:, display: "Race Co")
    receipt = ReceiptMinter.mint_self_service_receipt(validated_at: fixed_now, **identity)
    cmd = Workflows::Wf001::Commands::BootstrapOrganization.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      receipt_digest: receipt[:receipt_digest], expected_grant_version: 0,
      organization_display_name: display, project_display_name: "Site", project_objective: nil,
      access_policy_content_sha256: bc.access_policy_sha256,
      entitlement_policy_content_sha256: bc.entitlement_policy_sha256, plan_content_sha256: bc.plan_sha256,
      requested_at_utc: fixed_now
    )
    -> { Workflows::Wf001::Handlers::BootstrapOrganization.new.call(command: cmd, request_context: service_ctx(fixed_now)) }
  end

  def succeeded(results) = results.select { |r| r.respond_to?(:success?) && r.success? }
  def reasons(results) = results.map { |r| r.respond_to?(:reason_code) ? r.reason_code : r.class.name }

  it "identical bootstrap x identical bootstrap: one Organization, the loser replays" do
    issue_grant
    results, = RaceHarness.interleave(
      principal_key, gated: [bootstrap_thunk(key: "same"), bootstrap_thunk(key: "same")]
    )

    expect(succeeded(results).size).to eq(2)
    expect(results.count(&:replayed)).to eq(1)
    expect(DbInspector.count("organizations")).to eq(1)
    expect(DbInspector.count("billing_entities")).to eq(1)
  end

  it "same key x conflicting payload: one commits, the other is an idempotency conflict" do
    issue_grant
    results, = RaceHarness.interleave(
      principal_key,
      gated: [bootstrap_thunk(key: "shared", display: "Alpha Co"),
              bootstrap_thunk(key: "shared", display: "Beta Co")]
    )

    expect(succeeded(results).size).to eq(1)
    expect(reasons(results)).to include("idempotency_conflict")
    expect(DbInspector.count("organizations")).to eq(1)
  end

  it "different keys: one consumes the grant, the other is refused as consumed" do
    issue_grant
    results, = RaceHarness.interleave(
      principal_key, gated: [bootstrap_thunk(key: "a"), bootstrap_thunk(key: "b")]
    )

    expect(succeeded(results).size).to eq(1)
    expect(reasons(results)).to include("bootstrap_grant_consumed")
    expect(DbInspector.count("organizations")).to eq(1)
    expect(DbInspector.all("SELECT state FROM bootstrap_grants").map { |g| g["state"] }).to eq(["consumed"])
  end

  it "produces no duplicate BillingEntity, Plan Assignment or bootstrap administrator under any interleaving" do
    issue_grant
    RaceHarness.interleave(principal_key, gated: [bootstrap_thunk(key: "a"), bootstrap_thunk(key: "b")])

    org = DbInspector.one("SELECT id FROM organizations")["id"]
    expect(DbInspector.one("SELECT count(*) AS n FROM billing_entities WHERE organization_id = $1::uuid AND state <> 'closed'", [org])["n"].to_i).to eq(1)
    expect(DbInspector.one("SELECT count(*) AS n FROM plan_assignments WHERE organization_id = $1::uuid AND state = 'active'", [org])["n"].to_i).to eq(1)
    expect(DbInspector.one("SELECT count(*) AS n FROM role_assignments WHERE organization_id = $1::uuid AND bootstrap_admin_exception", [org])["n"].to_i).to eq(1)
  end

  it "bootstrap x replay of the committed result: the replay returns the stored Organization" do
    issue_grant
    first = bootstrap_thunk(key: "same").call
    expect(first).to be_success

    results, = RaceHarness.interleave(
      principal_key, gated: [bootstrap_thunk(key: "same"), bootstrap_thunk(key: "same")]
    )
    expect(results.all?(&:replayed)).to be(true)
    expect(results.map { |r| r.payload[:organization_id] }.uniq).to eq([first.payload[:organization_id]])
    expect(DbInspector.count("organizations")).to eq(1)
  end
end
