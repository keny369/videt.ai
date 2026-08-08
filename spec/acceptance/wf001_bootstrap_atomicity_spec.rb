# frozen_string_literal: true

require "rails_helper"

# The genesis is one atomic unit (AC-CAP-002; user Scope I). A failure at any
# point exposes no tenant record — proved by aborting the real transaction at a
# precise production write with a database trigger, so the rollback is the
# database's, not the application remembering to undo.
RSpec.describe "WF-001 bootstrap atomicity", type: :acceptance,
               acceptance_ids: ["AC-CAP-002", "AC-WF-001"],
               test_types: %w[TYP-DATA TYP-SEC] do
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

  def issue_grant
    receipt = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: fixed_now - 60, **identity)
    cmd = Workflows::Wf001::Commands::RequestBootstrapGrant.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: "g", schema_version: "1.0",
      receipt_digest: receipt[:receipt_digest], requested_at_utc: fixed_now - 60
    )
    raise "grant failed" unless Workflows::Wf001::Handlers::RequestBootstrapGrant.new
      .call(command: cmd, request_context: service_ctx(fixed_now - 60)).success?
  end

  def run_bootstrap
    receipt = ReceiptMinter.mint_self_service_receipt(validated_at: fixed_now, **identity)
    cmd = Workflows::Wf001::Commands::BootstrapOrganization.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: "b", schema_version: "1.0",
      receipt_digest: receipt[:receipt_digest], expected_grant_version: 0,
      organization_display_name: "Atomic Co", first_project: GenesisProjectProfile.body("Site"),
      access_policy_content_sha256: bc.access_policy_sha256,
      entitlement_policy_content_sha256: bc.entitlement_policy_sha256, plan_content_sha256: bc.plan_sha256,
      requested_at_utc: fixed_now
    )
    Workflows::Wf001::Handlers::BootstrapOrganization.new.call(command: cmd, request_context: service_ctx(fixed_now))
  end

  def tenant_counts
    %w[organizations accounts billing_entities plan_assignments entitlement_policies access_policies
       role_assignments projects sessions].to_h { |t| [t, DbInspector.count(t)] }
  end

  # Each abort point is a precise production write inside the genesis. After the
  # forced abort, no tenant row of any kind exists and the grant is not consumed.
  {
    "after Organization insert"   => %w[organizations INSERT],
    "after BillingEntity insert"  => %w[billing_entities INSERT],
    "after the admin assignment"  => %w[role_assignments INSERT],
    "after Plan Assignment insert" => %w[plan_assignments INSERT],
    "during policy population"    => %w[entitlement_policies INSERT],
    "after the draft Project"     => %w[projects INSERT],
    "during Session creation"     => %w[sessions INSERT],
    "during event emission"       => %w[event_registry INSERT],
    "before result persistence"   => %w[command_results INSERT]
  }.each do |label, (table, event)|
    it "rolls the whole genesis back when it fails #{label}, leaving no tenant record" do
      issue_grant

      FailureInjector.abort_on(table, event) do
        FailureInjector.expect_abort { run_bootstrap }
      end

      expect(tenant_counts.values).to all(eq(0))
      # The grant survives, unconsumed, so a corrected retry can still use it.
      expect(DbInspector.one("SELECT state FROM bootstrap_grants")["state"]).to eq("issued")
      # The receipt nonce was not consumed by the aborted attempt.
      expect(DbInspector.count("identity_receipt_consumptions")).to eq(1) # only grant issuance
    end
  end

  it "commits the complete genesis when nothing aborts it" do
    issue_grant
    expect(run_bootstrap).to be_success
    expect(tenant_counts.values).to all(eq(1))
  end
end
