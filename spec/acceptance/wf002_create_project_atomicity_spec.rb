# frozen_string_literal: true

require "rails_helper"

# WF-002 CreateProject atomicity (contracts/S-03.json MTX-027 transaction_boundary;
# AC-WF-002). A real trigger aborts the transaction at a precise production write,
# proving the whole commit is one unit: after any injected abort no Project, no
# event, no success ledger row survives, and the idempotency state still permits
# the correct retry — because the database removed the writes, not the application.
RSpec.describe "WF-002 create project atomicity", type: :acceptance,
               acceptance_ids: ["AC-CAP-003", "AC-WF-002"], test_types: %w[TYP-INT TYP-DATA] do
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
        organization_display_name: "Acme Discoverability", project_display_name: "Genesis Site",
        project_objective: "discoverability_assessment", access_policy_content_sha256: bc.access_policy_sha256,
        entitlement_policy_content_sha256: bc.entitlement_policy_sha256, plan_content_sha256: bc.plan_sha256,
        requested_at_utc: fixed_now
      ), request_context: service_ctx(fixed_now)
    ).payload
  end

  def profile
    {
      "project_profile_schema_version" => "project-profile-v1", "display_name" => "Atomic Project",
      "default_locale" => "en-AU", "reporting_time_zone" => "UTC", "objective" => "discoverability_assessment",
      "local_presence_applicable" => false,
      "local_presence_reason" => "This program operates entirely online across the country.",
      "local_business_profile" => nil
    }
  end

  def create(session_id:, organization_id:, key: "cp-#{SecureRandom.hex(6)}")
    Workflows::Wf002::Handlers::CreateProject.new.call(
      command: Workflows::Wf002::Commands::CreateProject.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
        session_id:, organization_id:, profile:, requested_at_utc: create_now
      ),
      request_context: Platform::RequestContext.for_actor(
        clock: Platform::Clock.fixed(create_now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
      )
    )
  end

  def project_count(org) = DbInspector.all("SELECT id FROM projects WHERE organization_id = $1::uuid", [org]).size
  def created_events(org)
    DbInspector.all(<<~SQL, [org]).size
      SELECT id FROM event_registry
      WHERE workflow_id = 'WF-002' AND event_type = 'ProjectCreated' AND organization_id = $1::uuid
    SQL
  end
  def success_results = DbInspector.all("SELECT id FROM command_results WHERE command_id IN (SELECT command_id FROM command_executions WHERE command_type = 'wf002.create_project') AND outcome = 'success'").size

  [
    ["projects", "INSERT", "AFTER"],
    ["audit_record_registry", "INSERT", "AFTER"],
    ["event_registry", "INSERT", "AFTER"],
    ["command_results", "INSERT", "BEFORE"]
  ].each do |table, event, timing|
    it "leaves no Project, event or success ledger row when aborted at #{timing} #{event} on #{table}" do
      g = bootstrap
      FailureInjector.abort_on(table, event, timing:) do
        FailureInjector.expect_abort { create(session_id: g[:session_id], organization_id: g[:organization_id]) }
      end

      expect(project_count(g[:organization_id])).to eq(1) # only the genesis Project
      expect(created_events(g[:organization_id])).to eq(0)
      expect(success_results).to eq(0)
    end
  end

  it "permits the correct retry after an injected abort, since no idempotency record survived" do
    g = bootstrap
    FailureInjector.abort_on("projects", "INSERT", timing: "AFTER") do
      FailureInjector.expect_abort { create(session_id: g[:session_id], organization_id: g[:organization_id], key: "retry") }
    end
    expect(project_count(g[:organization_id])).to eq(1)

    retried = create(session_id: g[:session_id], organization_id: g[:organization_id], key: "retry")
    expect(retried).to be_success
    expect(retried.replayed).to be(false)
    expect(project_count(g[:organization_id])).to eq(2)
  end
end
