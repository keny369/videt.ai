# frozen_string_literal: true

require "rails_helper"

# WF-004 RegisterSource atomicity (contracts/S-04.json transaction_boundary;
# AC-CAP-004). A real trigger aborts the transaction at a precise production
# write, proving the whole registration is one unit: after any injected abort no
# Source, no event and no success ledger row survives, and — because no idempotency
# record survived — the correct retry then succeeds.
RSpec.describe "WF-004 register source atomicity", type: :acceptance,
               acceptance_ids: ["AC-CAP-004"], test_types: %w[TYP-INT TYP-DATA] do
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

  def register(g, key: "rs-#{SecureRandom.hex(6)}")
    Workflows::Wf004::Handlers::RegisterSource.new.call(
      command: Workflows::Wf004::Commands::RegisterSource.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
        registration_schema_version: "source-registration-v1", submitted_root_uri: "https://atomic.example",
        expected_state_version: 0, requested_at_utc: act_now
      ),
      request_context: Platform::RequestContext.for_actor(
        clock: Platform::Clock.fixed(act_now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
      )
    )
  end

  def source_count = DbInspector.count("sources")
  def registered_events = DbInspector.all("SELECT id FROM event_registry WHERE event_type = 'SourceRegistered'").size
  def success_results = DbInspector.all("SELECT id FROM command_results WHERE command_id IN (SELECT command_id FROM command_executions WHERE command_type = 'wf004.register_source') AND outcome = 'success'").size

  [
    ["sources", "INSERT", "AFTER"],
    ["audit_record_registry", "INSERT", "AFTER"],
    ["event_registry", "INSERT", "AFTER"],
    ["command_results", "INSERT", "BEFORE"]
  ].each do |table, event, timing|
    it "leaves no Source, event or success ledger row when aborted at #{timing} #{event} on #{table}" do
      g = bootstrap
      FailureInjector.abort_on(table, event, timing:) do
        FailureInjector.expect_abort { register(g) }
      end

      expect(source_count).to eq(0)
      expect(registered_events).to eq(0)
      expect(success_results).to eq(0)
    end
  end

  it "permits the correct retry after an injected abort, since no idempotency record survived" do
    g = bootstrap
    FailureInjector.abort_on("sources", "INSERT", timing: "AFTER") do
      FailureInjector.expect_abort { register(g, key: "retry") }
    end
    expect(source_count).to eq(0)

    retried = register(g, key: "retry")
    expect(retried).to be_success
    expect(retried.replayed).to be(false)
    expect(source_count).to eq(1)
  end
end
