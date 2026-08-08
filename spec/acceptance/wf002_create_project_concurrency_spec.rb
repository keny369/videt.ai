# frozen_string_literal: true

require "rails_helper"

# WF-002 CreateProject under concurrency (contracts/S-03.json MTX-027 concurrency;
# AC-WF-002). Determinism comes from the same per-Organization advisory lock the
# command takes, not from timing: both creations reach `lock_organization`, block,
# and are released together, so exactly one winner is provable.
RSpec.describe "WF-002 create project concurrency", type: :acceptance,
               acceptance_ids: ["AC-CAP-003", "AC-WF-002"], test_types: %w[TYP-DATA TYP-INT] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def create_now = fixed_now + 60
  def bc = Platform::BaselineContent

  let(:identity) { { issuer_key: "https://id.example/oidc", subject: "founder-#{SecureRandom.hex(8)}" } }

  def service_ctx(at)
    Platform::RequestContext.for_service(
      service_identity_id: Platform::ServiceIdentity::IDENTITY_SERVICE,
      clock: Platform::Clock.fixed(at), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
    )
  end

  def bootstrap
    grant = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: fixed_now - 60, **identity)
    Workflows::Wf001::Handlers::RequestBootstrapGrant.new.call(
      command: Workflows::Wf001::Commands::RequestBootstrapGrant.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "grant-#{SecureRandom.hex(4)}",
        schema_version: "1.0", receipt_digest: grant[:receipt_digest], requested_at_utc: fixed_now - 60
      ), request_context: service_ctx(fixed_now - 60)
    )
    receipt = ReceiptMinter.mint_self_service_receipt(validated_at: fixed_now, **identity)
    Workflows::Wf001::Handlers::BootstrapOrganization.new.call(
      command: Workflows::Wf001::Commands::BootstrapOrganization.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "boot-#{SecureRandom.hex(4)}", schema_version: "1.0",
        receipt_digest: receipt[:receipt_digest], expected_grant_version: 0,
        organization_display_name: "Acme Discoverability", first_project: GenesisProjectProfile.body("Genesis Site"), access_policy_content_sha256: bc.access_policy_sha256,
        entitlement_policy_content_sha256: bc.entitlement_policy_sha256, plan_content_sha256: bc.plan_sha256,
        requested_at_utc: fixed_now
      ), request_context: service_ctx(fixed_now)
    ).payload
  end

  def profile(display_name: "Concurrent Project")
    {
      "project_profile_schema_version" => "project-profile-v1", "display_name" => display_name,
      "default_locale" => "en-AU", "reporting_time_zone" => "UTC", "objective" => "discoverability_assessment",
      "local_presence_applicable" => false,
      "local_presence_reason" => "This program operates entirely online across the country.",
      "local_business_profile" => nil
    }
  end

  def thunk(session_id:, organization_id:, key:, display_name: "Concurrent Project")
    lambda do
      Workflows::Wf002::Handlers::CreateProject.new.call(
        command: Workflows::Wf002::Commands::CreateProject.new(
          command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
          session_id:, organization_id:, profile: profile(display_name:), requested_at_utc: create_now
        ),
        request_context: Platform::RequestContext.for_actor(
          clock: Platform::Clock.fixed(create_now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
        )
      )
    end
  end

  def project_count(org) = DbInspector.all("SELECT id FROM projects WHERE organization_id = $1::uuid", [org]).size
  def created_events(org)
    DbInspector.all(<<~SQL, [org]).size
      SELECT id FROM event_registry
      WHERE workflow_id = 'WF-002' AND event_type = 'ProjectCreated' AND organization_id = $1::uuid
    SQL
  end

  it "resolves two identical activations into one winner and one replay across five seeds" do
    5.times do |seed|
      g = bootstrap
      key = "same-#{seed}"
      results = RaceHarness.contend(
        RaceHarness.organization_key(g[:organization_id]),
        thunk(session_id: g[:session_id], organization_id: g[:organization_id], key:),
        thunk(session_id: g[:session_id], organization_id: g[:organization_id], key:)
      )
      results.each { |r| raise r if r.is_a?(Exception) }

      expect(results.count(&:success?)).to eq(2)          # a replay is also a success result
      expect(results.count { |r| r.replayed }).to eq(1)   # exactly one is the stored replay
      expect(results.map { |r| r.payload[:project_id] }.uniq.size).to eq(1)
      expect(project_count(g[:organization_id])).to eq(2) # genesis + one
      expect(created_events(g[:organization_id])).to eq(1)
      ReceiptMinter.truncate_all
    end
  end

  it "resolves same-key conflicting payloads into one create and one idempotency_conflict" do
    g = bootstrap
    results = RaceHarness.contend(
      RaceHarness.organization_key(g[:organization_id]),
      thunk(session_id: g[:session_id], organization_id: g[:organization_id], key: "k", display_name: "Name A"),
      thunk(session_id: g[:session_id], organization_id: g[:organization_id], key: "k", display_name: "Name B")
    )
    results.each { |r| raise r if r.is_a?(Exception) }

    expect(results.count(&:success?)).to eq(1)
    expect(results.count { |r| r.reason_code == "idempotency_conflict" }).to eq(1)
    expect(project_count(g[:organization_id])).to eq(2) # genesis + one
    expect(created_events(g[:organization_id])).to eq(1)
  end

  it "creates two distinct Projects for two distinct idempotency keys racing on one Organization" do
    g = bootstrap
    results = RaceHarness.contend(
      RaceHarness.organization_key(g[:organization_id]),
      thunk(session_id: g[:session_id], organization_id: g[:organization_id], key: "a"),
      thunk(session_id: g[:session_id], organization_id: g[:organization_id], key: "b")
    )
    results.each { |r| raise r if r.is_a?(Exception) }

    expect(results.count(&:success?)).to eq(2)
    expect(results.none? { |r| r.replayed }).to be(true)
    expect(results.map { |r| r.payload[:project_id] }.uniq.size).to eq(2)
    expect(project_count(g[:organization_id])).to eq(3) # genesis + two
    expect(created_events(g[:organization_id])).to eq(2)
  end
end
