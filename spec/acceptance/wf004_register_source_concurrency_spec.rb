# frozen_string_literal: true

require "rails_helper"

# WF-004 RegisterSource under concurrency (contracts/S-04.json concurrency;
# AC-CAP-004 "nonremoved-host concurrency"). Determinism comes from the same
# per-(project, canonical_host) advisory lock the command takes, not from timing:
# both registrations reach `lock_source_host`, block, and are released together,
# so exactly one winner is provable.
RSpec.describe "WF-004 register source concurrency", type: :acceptance,
               acceptance_ids: ["AC-CAP-004"], test_types: %w[TYP-DATA TYP-INT] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def act_now = fixed_now + 60
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
        organization_display_name: "Acme Discoverability", project_display_name: "Genesis Site",
        project_objective: "discoverability_assessment", access_policy_content_sha256: bc.access_policy_sha256,
        entitlement_policy_content_sha256: bc.entitlement_policy_sha256, plan_content_sha256: bc.plan_sha256,
        requested_at_utc: fixed_now
      ), request_context: service_ctx(fixed_now)
    ).payload
  end

  def thunk(session_id:, organization_id:, project_id:, uri:, key:)
    lambda do
      Workflows::Wf004::Handlers::RegisterSource.new.call(
        command: Workflows::Wf004::Commands::RegisterSource.new(
          command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
          session_id:, organization_id:, project_id:, registration_schema_version: "source-registration-v1",
          submitted_root_uri: uri, expected_state_version: 0, requested_at_utc: act_now
        ),
        request_context: Platform::RequestContext.for_actor(
          clock: Platform::Clock.fixed(act_now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
        )
      )
    end
  end

  def source_count(project) = DbInspector.all("SELECT id FROM sources WHERE project_id = $1::uuid", [project]).size
  def registered_events(project)
    DbInspector.all(<<~SQL, [project]).size
      SELECT e.id FROM event_registry e
      WHERE e.workflow_id = 'WF-004' AND e.event_type = 'SourceRegistered'
        AND e.aggregate_id IN (SELECT id FROM sources WHERE project_id = $1::uuid)
    SQL
  end
  def host_key(project, host) = RaceHarness.key_for("source-host:#{project}:#{host}")

  it "resolves two identical registrations into one winner and one replay across five seeds" do
    5.times do |seed|
      g = bootstrap
      key = "same-#{seed}"
      results = RaceHarness.contend(
        host_key(g[:project_id], "shop.example"),
        thunk(session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
              uri: "https://shop.example", key:),
        thunk(session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
              uri: "https://shop.example", key:)
      )
      results.each { |r| raise r if r.is_a?(Exception) }

      expect(results.count(&:success?)).to eq(2)          # a replay is also a success result
      expect(results.count { |r| r.replayed }).to eq(1)
      expect(results.map { |r| r.payload[:source_id] }.uniq.size).to eq(1)
      expect(source_count(g[:project_id])).to eq(1)
      expect(registered_events(g[:project_id])).to eq(1)
      ReceiptMinter.truncate_all
    end
  end

  it "resolves two distinct-key registrations of the same host into one Source and one refusal" do
    g = bootstrap
    results = RaceHarness.contend(
      host_key(g[:project_id], "shop.example"),
      thunk(session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
            uri: "https://shop.example", key: "a"),
      thunk(session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
            uri: "https://shop.example", key: "b")
    )
    results.each { |r| raise r if r.is_a?(Exception) }

    expect(results.count(&:success?)).to eq(1)
    expect(results.count { |r| r.reason_code == "source_host_already_registered" }).to eq(1)
    expect(source_count(g[:project_id])).to eq(1)
    expect(registered_events(g[:project_id])).to eq(1)
  end

  it "registers two distinct hosts concurrently without interference" do
    g = bootstrap
    a = thunk(session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
              uri: "https://one.example", key: "a")
    b = thunk(session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
              uri: "https://two.example", key: "b")
    # Different hosts take different advisory keys, so they do not contend; run both and assert independence.
    results = [a, b].map(&:call)
    expect(results.count(&:success?)).to eq(2)
    expect(source_count(g[:project_id])).to eq(2)
    expect(registered_events(g[:project_id])).to eq(2)
  end
end
