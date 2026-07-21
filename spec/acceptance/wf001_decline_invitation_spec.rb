# frozen_string_literal: true

require "rails_helper"

# Direct oracle for the WF-001 invitation-decline branch (WORKFLOW_SPECIFICATIONS.md
# § invitation decline, :250): the recipient declines an active Invitation via the
# same invitation-bound recipient capability as acceptance; active->declined records
# time+reason and consumes the receipt nonce; creates no Account/Assignment/Session;
# emits exactly one InvitationDeclined; exact replay returns the retained terminal
# result; a reused key with changed input conflicts; a different key after decline is
# the non-disclosing invitation_not_active; the public resolver never resolves the
# terminal reference.
RSpec.describe "WF-001 DeclineInvitation", type: :acceptance,
               acceptance_ids: ["AC-CAP-001", "AC-WF-001"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA TYP-OBS] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  let(:service_id) { SecureRandom.uuid_v7 }
  let(:invitee) do
    { issuer_key: "https://id.example/oidc", subject: "sub-#{SecureRandom.hex(8)}",
      email: "invitee-#{SecureRandom.hex(4)}@example.com" }
  end

  def context(clock_now: fixed_now)
    Platform::RequestContext.for_service(
      service_identity_id: service_id, clock: Platform::Clock.fixed(clock_now),
      ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
    )
  end

  def seed_invitation(org:, **opts)
    TenantSeeder.create_invitation(organization_id: org, target_email: invitee[:email], **opts)
  end

  def receipt_for(email: nil, issuer_key: nil, subject: nil, validated_at: fixed_now)
    ReceiptMinter.mint_invitation_receipt(
      validated_at:, issuer_key: issuer_key || invitee[:issuer_key],
      subject: subject || invitee[:subject], normalized_email: email || invitee[:email]
    )
  end

  def decline_command(inv, receipt, key: "idem-#{SecureRandom.hex(4)}", schema: "1.0", expected_version: 0, reason: nil)
    Workflows::Wf001::Commands::DeclineInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: schema,
      invitation_reference: inv[:reference], receipt_digest: receipt[:receipt_digest],
      expected_state_version: expected_version, reason:, requested_at_utc: fixed_now
    )
  end

  def decline(inv, receipt, ctx: context, **opts)
    Workflows::Wf001::Handlers::DeclineInvitation.new.call(command: decline_command(inv, receipt, **opts), request_context: ctx)
  end

  def event_types = DbInspector.all("SELECT event_type FROM event_registry ORDER BY created_at").map { |r| r["event_type"] }

  describe "success" do
    it "declines the active Invitation, consumes the nonce, emits one InvitationDeclined, creates no domain records" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)

      result = decline(inv, receipt_for, reason: "no longer needed")

      expect(result).to be_success
      expect(result.payload[:invitation_id]).to eq(inv[:invitation_id])
      expect(result.payload[:organization_id]).to eq(org)
      expect(result.payload[:state]).to eq("declined")

      row = DbInspector.one("SELECT state, reason, declined_at FROM invitations")
      expect(row["state"]).to eq("declined")
      expect(row["reason"]).to eq("no longer needed")
      expect(row["declined_at"]).not_to be_nil
      expect(DbInspector.one("SELECT invitation_state FROM invitation_reference_registry")["invitation_state"]).to eq("declined")

      expect(DbInspector.one("SELECT outcome FROM identity_receipt_consumptions")["outcome"]).to eq("consumed")
      expect(event_types).to eq(["InvitationDeclined"])
      expect(DbInspector.count("accounts")).to eq(0)
      expect(DbInspector.count("role_assignments")).to eq(0)
      expect(DbInspector.count("sessions")).to eq(0)
    end

    it "records a null reason when none is supplied and still emits InvitationDeclined" do
      org = TenantSeeder.create_organization
      result = decline(seed_invitation(org:), receipt_for)
      expect(result).to be_success
      expect(DbInspector.one("SELECT reason FROM invitations")["reason"]).to be_nil
      expect(event_types).to eq(["InvitationDeclined"])
    end

    it "produces event_bytes whose sha256 the database recomputes and accepts" do
      org = TenantSeeder.create_organization
      decline(seed_invitation(org:), receipt_for)
      row = DbInspector.one("SELECT (event_sha256 = public.digest(event_bytes,'sha256')) AS ok FROM event_registry")
      expect(row["ok"]).to eq("t")
    end
  end

  describe "replay and idempotency" do
    it "exact replay returns the retained result and emits no new event or writes" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      receipt = receipt_for
      first = decline(inv, receipt, key: "idem-1", reason: "x")
      events_before = DbInspector.count("event_registry")

      second = decline(inv, receipt, key: "idem-1", reason: "x")
      expect(second).to be_success
      expect(second.replayed).to be(true)
      expect(second.payload).to eq(first.payload)
      expect(DbInspector.count("event_registry")).to eq(events_before)
    end

    it "the same idempotency key with changed input (different reason) returns idempotency_conflict" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      receipt = receipt_for
      expect(decline(inv, receipt, key: "idem-1", reason: "first")).to be_success

      second = decline(inv, receipt, key: "idem-1", reason: "second")
      expect(second).to be_failure
      expect(second.reason_code).to eq("idempotency_conflict")
      expect(second.failure.error_code).to eq("F1-DOMAIN-409")
    end

    it "a different idempotency key after decline is the non-disclosing invitation_not_active" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      expect(decline(inv, receipt_for, key: "idem-1")).to be_success

      second = decline(inv, receipt_for, key: "a-different-key")
      expect(second).to be_failure
      expect(second.reason_code).to eq("invitation_not_active")
    end
  end

  describe "failures — the Invitation is unchanged" do
    it "a terminal Invitation cannot be declined (invitation_not_active)" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:, state: "accepted")
      result = decline(inv, receipt_for)
      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_not_active")
    end

    it "a stale expected state version returns stale_state_version (F1-DOMAIN-409), no transition" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      result = decline(inv, receipt_for, expected_version: 5)
      expect(result).to be_failure
      expect(result.reason_code).to eq("stale_state_version")
      expect(result.failure.error_code).to eq("F1-DOMAIN-409")
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("active")
    end

    it "a wrong-identity receipt binds the nonce, emits no event, and leaves the Invitation active" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      result = decline(inv, receipt_for(email: "someone-else-#{SecureRandom.hex(3)}@example.com"))
      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_target_mismatch")
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("active")
      expect(DbInspector.count("event_registry")).to eq(0)
      expect(DbInspector.one("SELECT outcome, reason_code FROM identity_receipt_consumptions")).to eq(
        { "outcome" => "rejected", "reason_code" => "invitation_target_mismatch" }
      )
    end

    it "an invalid receipt produces no domain writes (Invitation active, no event, no Session)" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      result = decline(inv, { receipt_digest: Digest::SHA256.digest("no-such-receipt") })
      expect(result).to be_failure
      expect(result.reason_code).to eq("identity_receipt_invalid")
      expect(result.failure.error_code).to eq("F1-AUTHN-401")
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("active")
      expect(DbInspector.count("event_registry")).to eq(0)
      expect(DbInspector.count("sessions")).to eq(0)
    end

    it "rejects a malformed reason (blank or over 2,000 scalar values) as F1-VALIDATION-400" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      blank = decline(inv, receipt_for, reason: "   ")
      expect(blank.reason_code).to eq("invitation_reason_invalid")
      expect(blank.failure.error_code).to eq("F1-VALIDATION-400")

      oversized = decline(inv, receipt_for, reason: "x" * 2001)
      expect(oversized.reason_code).to eq("invitation_reason_invalid")
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("active")
    end

    it "rejects an unsupported command schema major (F1-VALIDATION-400)" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      result = decline(inv, receipt_for, schema: "2.0")
      expect(result.reason_code).to eq("command_schema_unsupported")
      expect(result.failure.error_code).to eq("F1-VALIDATION-400")
    end
  end

  describe "non-disclosure" do
    it "the public resolver returns zero rows after decline" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      decline(inv, receipt_for)
      rows = DbInspector.connection.exec_params(
        "SELECT organization_id FROM f1_resolve_invitation_reference($1, $2::timestamptz)",
        [{ value: inv[:reference_digest], format: 1 }, fixed_now.iso8601(6)]
      ).to_a
      expect(rows).to be_empty
    end
  end

  describe "concurrency" do
    it "concurrent declines of one Invitation commit exactly one decline and one event" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      receipts = [receipt_for, receipt_for]

      results = receipts.each_with_index.map do |r, i|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection { decline(inv, r, key: "k#{i}") }
        end
      end.map(&:value)

      expect(results.count(&:success?)).to eq(1)
      expect(DbInspector.all("SELECT state FROM invitations").map { |r| r["state"] }).to eq(["declined"])
      expect(results.find(&:failure?).reason_code).to eq("invitation_not_active")
      expect(event_types).to eq(["InvitationDeclined"])
    end
  end
end
