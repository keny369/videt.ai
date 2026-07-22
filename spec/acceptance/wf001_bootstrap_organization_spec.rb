# frozen_string_literal: true

require "rails_helper"

# WF-001 self-service BootstrapOrganization (WORKFLOW_SPECIFICATIONS.md :238,
# :627-641; CAP-002 MTX-002; PRULE-002 MTX-053; AC-CAP-002, AC-WF-001).
#
# The whole tenant genesis in one command: Organization, Account, BillingEntity,
# first OrganizationAdmin Assignment, baseline Access and Entitlement policies,
# BillingEntity-linked Plan Assignment, draft Project and Session, with exactly
# the thirteen ordered events, and nothing at all on failure.
RSpec.describe "WF-001 bootstrap organization", type: :acceptance,
               acceptance_ids: ["AC-CAP-002", "AC-WF-001", "AC-PRULE-002"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA TYP-OBS] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def bc = Platform::BaselineContent

  let(:identity) { { issuer_key: "https://id.example/oidc", subject: "founder-#{SecureRandom.hex(8)}" } }

  def ctx = Platform::RequestContext.for_service(
    service_identity_id: Platform::ServiceIdentity::IDENTITY_SERVICE,
    clock: Platform::Clock.fixed(fixed_now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
  )

  # Issue an unexpired Bootstrap Grant for `identity` the way RequestBootstrapGrant
  # would, so the self-service commit has its precondition. Tolerant of an already
  # issued grant, so a helper that retries a failed bootstrap in one example reuses
  # the standing grant rather than issuing a second.
  def issue_grant
    return if @grant_issued

    receipt = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: fixed_now - 60, **identity)
    cmd = Workflows::Wf001::Commands::RequestBootstrapGrant.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: "grant-#{SecureRandom.hex(4)}",
      schema_version: "1.0", receipt_digest: receipt[:receipt_digest], requested_at_utc: fixed_now - 60
    )
    result = Workflows::Wf001::Handlers::RequestBootstrapGrant.new.call(command: cmd, request_context: grant_ctx)
    unless result.success? || result.reason_code == "bootstrap_grant_already_issued"
      raise "grant issuance failed: #{result.reason_code}"
    end

    @grant_issued = true
  end

  def grant_ctx = Platform::RequestContext.for_service(
    service_identity_id: Platform::ServiceIdentity::IDENTITY_SERVICE,
    clock: Platform::Clock.fixed(fixed_now - 60), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
  )

  def bootstrap(overrides = {})
    issue_grant
    receipt = ReceiptMinter.mint_self_service_receipt(validated_at: fixed_now, **identity)
    cmd = Workflows::Wf001::Commands::BootstrapOrganization.new(**{
      command_id: SecureRandom.uuid_v7, idempotency_key: "boot-#{SecureRandom.hex(4)}", schema_version: "1.0",
      receipt_digest: receipt[:receipt_digest], expected_grant_version: 0,
      organization_display_name: "Acme Discoverability", project_display_name: "Acme Website",
      project_objective: "Improve discoverability", access_policy_content_sha256: bc.access_policy_sha256,
      entitlement_policy_content_sha256: bc.entitlement_policy_sha256, plan_content_sha256: bc.plan_sha256,
      requested_at_utc: fixed_now
    }.merge(overrides))
    Workflows::Wf001::Handlers::BootstrapOrganization.new.call(command: cmd, request_context: ctx)
  end

  # Cross-principal reads from outside any context.
  def org(id) = DbInspector.one("SELECT * FROM organizations WHERE id = $1::uuid", [id])

  # The genesis events in their emitted order, excluding the separate
  # grant-issuance event (BootstrapGrantIssued) from the precondition step.
  def events
    DbInspector.all(<<~SQL).map { |e| e["event_type"] }
      SELECT event_type FROM event_registry
      WHERE event_type <> 'BootstrapGrantIssued' ORDER BY occurred_at, id
    SQL
  end

  describe "the genesis" do
    it "creates an active Organization with its whole tenant set and advances no epoch past 1" do
      result = bootstrap
      expect(result).to be_success
      p = result.payload

      row = org(p[:organization_id])
      expect(row["status"]).to eq("active")
      expect(row["authorization_epoch"].to_i).to eq(1)
      expect(row["creator_account_id"]).to eq(p[:account_id])
      expect(row["default_locale"]).to eq("en-AU")
      expect(row["profile_schema_version"]).to eq("organization-profile-v1")

      expect(DbInspector.one("SELECT status FROM accounts WHERE id = $1::uuid", [p[:account_id]])["status"]).to eq("active")
      expect(DbInspector.one("SELECT state FROM billing_entities WHERE id = $1::uuid", [p[:billing_entity_id]])["state"]).to eq("active")
      expect(DbInspector.one("SELECT status FROM role_assignments WHERE id = $1::uuid", [p[:role_assignment_id]])["status"]).to eq("active")
      expect(DbInspector.one("SELECT state FROM projects WHERE id = $1::uuid", [p[:project_id]])["state"]).to eq("draft")
      expect(DbInspector.one("SELECT status FROM sessions WHERE id = $1::uuid", [p[:session_id]])["status"]).to eq("active")
    end

    it "emits exactly the thirteen ordered events, service-attributed with a null actor" do
      bootstrap
      expect(events).to eq(%w[
        AccountProvisionRequested OrganizationCreated BillingStateChanged RoleGranted
        AccessPolicyActivated PlanAssigned EntitlementPolicyActivated BillingStateChanged
        AccountActivated OrganizationActivated ProjectCreated BootstrapGrantConsumed SessionCreated
      ])

      # Both BillingStateChanged events carry their fixed from/to, in order.
      bodies = DbInspector.all(<<~SQL).map { |e| JSON.parse(e["b"]) }
        SELECT convert_from(event_bytes,'UTF8') AS b FROM event_registry
        WHERE event_type = 'BillingStateChanged' ORDER BY created_at, id
      SQL
      expect(bodies.map { |b| [b["from_state"], b["to_state"]] }).to eq([[nil, "pending"], %w[pending active]])
      bodies.each do |b|
        expect(b["service_identity_id"]).to eq(Platform::ServiceIdentity::IDENTITY_SERVICE)
        expect(b["actor_id"]).to be_nil
      end
    end

    it "carries the created Organization's real id on every event, never the OD-013 substitution" do
      p = bootstrap.payload
      principal_uuid = DbInspector.bootstrap_principal_uuid(Digest::SHA256.digest("#{identity[:issuer_key]}\n#{identity[:subject]}"))

      genesis = DbInspector.all(<<~SQL)
        SELECT organization_id FROM event_registry WHERE workflow_id = 'WF-001' AND event_type <> 'BootstrapGrantIssued'
      SQL
      expect(genesis.map { |e| e["organization_id"] }.uniq).to eq([p[:organization_id]])
      expect(p[:organization_id]).not_to eq(principal_uuid)
    end

    it "consumes the grant and the receipt nonce exactly once" do
      p = bootstrap.payload
      grant = DbInspector.one("SELECT state, organization_id FROM bootstrap_grants")
      expect(grant["state"]).to eq("consumed")
      expect(grant["organization_id"]).to eq(p[:organization_id])
      expect(DbInspector.count("identity_receipt_consumptions")).to eq(2) # grant issuance + this
    end
  end

  describe "PRULE-002 invariants" do
    it "creates exactly one active baseline BillingEntity linked to the same-Organization active Plan Assignment" do
      p = bootstrap.payload
      expect(DbInspector.count("billing_entities")).to eq(1)
      plan = DbInspector.one("SELECT * FROM plan_assignments WHERE organization_id = $1::uuid", [p[:organization_id]])
      expect(plan["state"]).to eq("active")
      expect(plan["billing_entity_id"]).to eq(p[:billing_entity_id])
      billing = DbInspector.one("SELECT * FROM billing_entities WHERE id = $1::uuid", [p[:billing_entity_id]])
      expect(billing["active_plan_assignment_id"]).to eq(plan["id"])
    end

    it "creates exactly one accountable OrganizationAdmin with the bootstrap exception" do
      p = bootstrap.payload
      admin = DbInspector.one("SELECT * FROM role_assignments WHERE id = $1::uuid", [p[:role_assignment_id]])
      expect(admin["canonical_role"]).to eq("OrganizationAdmin")
      expect(admin["bootstrap_admin_exception"]).to eq("t")
      expect(admin["status"]).to eq("active")
      expect(JSON.parse(admin["protected_permission_allowlist"]))
        .to eq(Platform::PermissionBaseline.protected_permission_preview("OrganizationAdmin"))
    end

    it "never enters a reserved billing state and materializes one active Access and Entitlement policy" do
      p = bootstrap.payload
      expect(DbInspector.all("SELECT state FROM billing_entities").map { |b| b["state"] }).to eq(["active"])
      expect(DbInspector.one("SELECT status FROM access_policies WHERE organization_id = $1::uuid", [p[:organization_id]])["status"]).to eq("active")
      expect(DbInspector.one("SELECT status FROM entitlement_policies WHERE organization_id = $1::uuid", [p[:organization_id]])["status"]).to eq("active")
    end
  end

  describe "content-hash validation" do
    it "rejects a mismatched access-policy hash and creates no tenant record" do
      result = bootstrap(access_policy_content_sha256: Digest::SHA256.digest("wrong"))
      expect(result.reason_code).to eq("access_policy_hash_mismatch")
      expect(DbInspector.count("organizations")).to eq(0)
    end

    it "rejects a mismatched entitlement hash and a mismatched plan hash" do
      expect(bootstrap(entitlement_policy_content_sha256: Digest::SHA256.digest("x")).reason_code).to eq("entitlement_policy_hash_mismatch")
      expect(bootstrap(plan_content_sha256: Digest::SHA256.digest("y")).reason_code).to eq("plan_hash_mismatch")
      expect(DbInspector.count("organizations")).to eq(0)
    end

    it "rejects an out-of-bounds organization display name" do
      expect(bootstrap(organization_display_name: "").reason_code).to eq("organization_profile_invalid")
      expect(bootstrap(organization_display_name: "x" * 121).reason_code).to eq("organization_profile_invalid")
      expect(DbInspector.count("organizations")).to eq(0)
    end
  end

  describe "grant and replay" do
    it "refuses to bootstrap without an issued grant" do
      receipt = ReceiptMinter.mint_self_service_receipt(validated_at: fixed_now, **identity)
      cmd = Workflows::Wf001::Commands::BootstrapOrganization.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "nogrant", schema_version: "1.0",
        receipt_digest: receipt[:receipt_digest], expected_grant_version: 0,
        organization_display_name: "No Grant", project_display_name: "P", project_objective: nil,
        access_policy_content_sha256: bc.access_policy_sha256,
        entitlement_policy_content_sha256: bc.entitlement_policy_sha256, plan_content_sha256: bc.plan_sha256,
        requested_at_utc: fixed_now
      )
      result = Workflows::Wf001::Handlers::BootstrapOrganization.new.call(command: cmd, request_context: ctx)
      expect(result.reason_code).to eq("bootstrap_grant_unavailable")
      expect(DbInspector.count("organizations")).to eq(0)
    end

    it "returns the stored result on exact replay, creating no second tenant and emitting no second event set" do
      issue_grant
      receipt = ReceiptMinter.mint_self_service_receipt(validated_at: fixed_now, **identity)
      def cmd_for(receipt) = Workflows::Wf001::Commands::BootstrapOrganization.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "same", schema_version: "1.0",
        receipt_digest: receipt[:receipt_digest], expected_grant_version: 0,
        organization_display_name: "Acme", project_display_name: "Site", project_objective: nil,
        access_policy_content_sha256: Platform::BaselineContent.access_policy_sha256,
        entitlement_policy_content_sha256: Platform::BaselineContent.entitlement_policy_sha256,
        plan_content_sha256: Platform::BaselineContent.plan_sha256, requested_at_utc: fixed_now
      )
      first = Workflows::Wf001::Handlers::BootstrapOrganization.new.call(command: cmd_for(receipt), request_context: ctx)
      replay = Workflows::Wf001::Handlers::BootstrapOrganization.new.call(command: cmd_for(receipt), request_context: ctx)

      expect(first).to be_success
      expect(replay.replayed).to be(true)
      expect(replay.payload[:organization_id]).to eq(first.payload[:organization_id])
      expect(DbInspector.count("organizations")).to eq(1)
      expect(events.count("OrganizationActivated")).to eq(1)
    end

    it "refuses a second bootstrap once the principal's grant is consumed" do
      bootstrap
      # A second grant cannot be issued (bootstrap_already_completed), and a
      # bootstrap attempt with no issued grant is refused.
      receipt = ReceiptMinter.mint_self_service_receipt(validated_at: fixed_now, **identity)
      cmd = Workflows::Wf001::Commands::BootstrapOrganization.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "second", schema_version: "1.0",
        receipt_digest: receipt[:receipt_digest], expected_grant_version: 0,
        organization_display_name: "Second", project_display_name: "P", project_objective: nil,
        access_policy_content_sha256: bc.access_policy_sha256,
        entitlement_policy_content_sha256: bc.entitlement_policy_sha256, plan_content_sha256: bc.plan_sha256,
        requested_at_utc: fixed_now
      )
      result = Workflows::Wf001::Handlers::BootstrapOrganization.new.call(command: cmd, request_context: ctx)
      expect(result.reason_code).to eq("bootstrap_grant_consumed")
      expect(DbInspector.count("organizations")).to eq(1)
    end
  end
end
