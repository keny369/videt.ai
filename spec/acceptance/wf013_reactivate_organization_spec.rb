# frozen_string_literal: true

require "rails_helper"

# WF-013 ReactivateOrganization under the ratified `reactivation-proof-v1`
# decision (WORKFLOW_SPECIFICATIONS.md :270-289).
#
# Deliberately not Session-authenticated: suspension revoked every human Session,
# so authority is proved by a fresh purpose-bound receipt carrying
# `mfa_satisfied=true` and binding exactly one Organization. It restores the
# Organization's ability to issue NEW authority; it revives nothing suspension
# invalidated.
RSpec.describe "WF-013 reactivate organization", type: :acceptance,
               acceptance_ids: ["AC-CAP-013", "AC-WF-013"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)

  let(:identity) { { issuer_key: "https://id.example/oidc", subject: "admin-#{SecureRandom.hex(8)}" } }

  # A suspended Organization whose OrganizationAdmin is bound to `identity`.
  let(:suspended) do
    org = TenantSeeder.create_organization
    account = TenantSeeder.create_account(organization_id: org, issuer_key: identity[:issuer_key],
                                          subject: identity[:subject])
    TenantSeeder.create_role_assignment(organization_id: org, account_id: account)
    TenantSeeder.create_access_policy(organization_id: org)
    session = TenantSeeder.create_session(organization_id: org, account_id: account, issued_at: fixed_now - 900)
    cmd = Workflows::Wf013::Commands::SuspendOrganization.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: "susp", schema_version: "1.0", session_id: session,
      expected_state_version: 0, expected_authorization_epoch: 7, reason: "suspended for reactivation coverage",
      requested_at_utc: fixed_now
    )
    result = Workflows::Wf013::Handlers::SuspendOrganization.new.call(command: cmd, request_context: ctx)
    raise "suspension failed: #{result.reason_code}" unless result.success?

    { organization_id: org, account_id: account, revoked_session_id: session }
  end

  def ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(fixed_now),
                                               ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)

  def receipt(**overrides)
    ReceiptMinter.mint_reactivation_receipt(validated_at: fixed_now, issuer_key: identity[:issuer_key],
                                            subject: identity[:subject], **overrides)
  end

  def reactivate(org, digest, key: "react", version: 1, epoch: 8, schema: "1.0")
    cmd = Workflows::Wf013::Commands::ReactivateOrganization.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: schema,
      organization_id: org, receipt_digest: digest, expected_state_version: version,
      expected_authorization_epoch: epoch, requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::ReactivateOrganization.new.call(command: cmd, request_context: ctx)
  end

  def organization(org) = DbInspector.one("SELECT * FROM organizations WHERE id = $1::uuid", [org])
  def events = DbInspector.all("SELECT event_type FROM event_registry ORDER BY created_at").map { |e| e["event_type"] }

  describe "the reactivation transition" do
    it "takes the Organization suspended -> active, advancing both versions again" do
      org = suspended[:organization_id]
      result = reactivate(org, receipt[:receipt_digest])

      expect(result).to be_success
      row = organization(org)
      expect(row["status"]).to eq("active")
      expect(row["state_version"].to_i).to eq(2)
      expect(row["authorization_epoch"].to_i).to eq(9)
      expect(row["reactivated_at"]).not_to be_nil
      expect(row["lifecycle_reason"]).to be_nil
    end

    it "emits one OrganizationReactivated state-transition event and creates no Session" do
      org = suspended[:organization_id]
      sessions_before = DbInspector.count("sessions")
      reactivate(org, receipt[:receipt_digest])

      expect(events).to eq(%w[OrganizationSuspended OrganizationReactivated])
      body = JSON.parse(DbInspector.all("SELECT convert_from(event_bytes,'UTF8') AS b FROM event_registry ORDER BY created_at").last["b"])
      expect(body["from_state"]).to eq("suspended")
      expect(body["to_state"]).to eq("active")
      expect(body["organization_epoch"]).to eq(9)
      expect(body["service_identity_id"]).to be_nil
      expect(DbInspector.count("sessions")).to eq(sessions_before)
    end

    it "consumes the receipt nonce exactly once" do
      org = suspended[:organization_id]
      digest = receipt[:receipt_digest]
      expect(reactivate(org, digest)).to be_success
      expect(DbInspector.count("identity_receipt_consumptions")).to eq(1)
    end

    it "records the assurance version and receipt digest in the audit, never the raw receipt" do
      org = suspended[:organization_id]
      minted = receipt
      reactivate(org, minted[:receipt_digest])

      audit = DbInspector.all("SELECT payload, to_state FROM audit_record_registry ORDER BY created_at").last
      payload = JSON.parse(audit["payload"])
      expect(audit["to_state"]).to eq("active")
      expect(payload["assurance_version"]).to eq("assurance-v1")
      expect(payload["receipt_digest"]).to eq(minted[:receipt_digest].unpack1("H*"))
    end
  end

  describe "the reactivation proof" do
    it "refuses a receipt of any other purpose" do
      org = suspended[:organization_id]
      wrong = ReceiptMinter.mint_sign_in_receipt(validated_at: fixed_now, issuer_key: identity[:issuer_key],
                                                 subject: identity[:subject])
      expect(reactivate(org, wrong[:receipt_digest]).reason_code).to eq("identity_receipt_purpose_mismatch")
      expect(organization(org)["status"]).to eq("suspended")
    end

    it "refuses a receipt without satisfied MFA" do
      org = suspended[:organization_id]
      expect(reactivate(org, receipt(mfa_satisfied: false)[:receipt_digest]).reason_code)
        .to eq("identity_assurance_failed")
      expect(organization(org)["status"]).to eq("suspended")
    end

    it "refuses an expired receipt, with expiry winning at equality" do
      org = suspended[:organization_id]
      stale = receipt(validated_at: fixed_now - 600)
      expect(reactivate(org, stale[:receipt_digest]).reason_code).to eq("identity_receipt_expired")
      expect(organization(org)["status"]).to eq("suspended")
    end

    it "refuses an unknown receipt digest" do
      org = suspended[:organization_id]
      expect(reactivate(org, Digest::SHA256.digest("nope")).reason_code).to eq("identity_receipt_invalid")
    end

    it "refuses a receipt whose identity holds no OrganizationAdmin authority in the bound Organization" do
      org = suspended[:organization_id]
      stranger = ReceiptMinter.mint_reactivation_receipt(validated_at: fixed_now,
                                                         issuer_key: identity[:issuer_key],
                                                         subject: "stranger-#{SecureRandom.hex(6)}")
      expect(reactivate(org, stranger[:receipt_digest]).reason_code).to eq("organization_admin_unavailable")
      expect(organization(org)["status"]).to eq("suspended")
    end

    it "refuses when the Organization has no single active Access Policy" do
      org = suspended[:organization_id]
      DbInspector.connection.exec_params("UPDATE access_policies SET status = 'retired' WHERE organization_id = $1::uuid", [org])
      expect(reactivate(org, receipt[:receipt_digest]).reason_code).to eq("access_policy_unavailable")
      expect(organization(org)["status"]).to eq("suspended")
    end
  end

  describe "state, versions and replay" do
    it "refuses to reactivate an Organization that is not suspended" do
      org = suspended[:organization_id]
      expect(reactivate(org, receipt[:receipt_digest])).to be_success
      expect(reactivate(org, receipt[:receipt_digest], key: "again", version: 2, epoch: 9).reason_code)
        .to eq("organization_state_invalid")
      expect(organization(org)["state_version"].to_i).to eq(2)
    end

    it "refuses a stale expected state version or authorization epoch" do
      org = suspended[:organization_id]
      expect(reactivate(org, receipt[:receipt_digest], version: 0).reason_code).to eq("stale_state_version")
      expect(reactivate(org, receipt[:receipt_digest], epoch: 7).reason_code).to eq("stale_authorization_epoch")
      expect(organization(org)["status"]).to eq("suspended")
    end

    it "returns the stored result on exact replay without reusing the receipt" do
      org = suspended[:organization_id]
      digest = receipt[:receipt_digest]
      first = reactivate(org, digest, key: "same")
      replay = reactivate(org, digest, key: "same")

      expect(replay.replayed).to be(true)
      expect(replay.payload).to eq(first.payload)
      expect(DbInspector.count("identity_receipt_consumptions")).to eq(1)
      expect(events.count("OrganizationReactivated")).to eq(1)
      expect(organization(org)["state_version"].to_i).to eq(2)
    end
  end

  describe "reactivation restores the ability to issue authority, not the authority itself" do
    it "does not revive the Session suspension revoked" do
      org = suspended[:organization_id]
      expect(reactivate(org, receipt[:receipt_digest])).to be_success

      revived = DbInspector.one("SELECT status FROM sessions WHERE id = $1::uuid", [suspended[:revoked_session_id]])
      expect(revived["status"]).to eq("revoked")
    end

    it "leaves a revoked Session unable to authorize even though the Organization is active again" do
      org = suspended[:organization_id]
      reactivate(org, receipt[:receipt_digest])

      cmd = Workflows::Wf013::Commands::SuspendOrganization.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "after", schema_version: "1.0",
        session_id: suspended[:revoked_session_id], expected_state_version: 2,
        expected_authorization_epoch: 9, reason: nil, requested_at_utc: fixed_now
      )
      result = Workflows::Wf013::Handlers::SuspendOrganization.new.call(command: cmd, request_context: ctx)
      expect(result.reason_code).to eq("session_invalid")
    end

    it "lets a NEW Session act, and it carries the new authorization epoch" do
      org = suspended[:organization_id]
      reactivate(org, receipt[:receipt_digest])
      fresh = TenantSeeder.create_session(organization_id: org, account_id: suspended[:account_id],
                                          issued_at: fixed_now - 900)

      cmd = Workflows::Wf013::Commands::SuspendOrganization.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "resuspend", schema_version: "1.0",
        session_id: fresh, expected_state_version: 2, expected_authorization_epoch: 9,
        reason: nil, requested_at_utc: fixed_now
      )
      result = Workflows::Wf013::Handlers::SuspendOrganization.new.call(command: cmd, request_context: ctx)

      expect(result).to be_success
      expect(result.payload[:authorization_epoch]).to eq(10)
      expect(organization(org)["authorization_epoch"].to_i).to eq(10)
    end

    it "never restores a prior epoch" do
      org = suspended[:organization_id]
      reactivate(org, receipt[:receipt_digest])
      expect(organization(org)["authorization_epoch"].to_i).to eq(9)
    end
  end
end
