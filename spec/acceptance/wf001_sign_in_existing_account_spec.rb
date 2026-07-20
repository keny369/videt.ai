# frozen_string_literal: true

require "rails_helper"

# Direct oracle for the WF-001 existing-account sign-in branch of AC-CAP-001 /
# AC-WF-001 (WORKFLOW_SPECIFICATIONS.md § existing-account sign-in): one Session
# or none; the exact SessionCreated event with a real tenant organization_id
# (OD-013 does not apply); the seven exhaustive outward failures with the
# first-match order; invalid-receipt reasons normalized to authentication_failed
# outward while the exact internal reason is retained in the restricted audit;
# the organization_home / access_unavailable destination; concurrent Sessions
# with no revocation; and exact replay.
RSpec.describe "WF-001 SignInExistingAccount", type: :acceptance,
               acceptance_ids: ["AC-CAP-001", "AC-WF-001"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA TYP-OBS] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  let(:service_id) { SecureRandom.uuid_v7 }
  let(:principal) { { issuer_key: "https://id.example/oidc", subject: "sub-#{SecureRandom.hex(8)}" } }

  def context(clock_now: fixed_now)
    Platform::RequestContext.for_service(
      service_identity_id: service_id, clock: Platform::Clock.fixed(clock_now),
      ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
    )
  end

  def receipt_for(validated_at: fixed_now, **opts)
    ReceiptMinter.mint_sign_in_receipt(
      validated_at:, issuer_key: principal[:issuer_key], subject: principal[:subject], **opts
    )
  end

  def seed(**opts)
    TenantSeeder.seed_signed_in_ready(issuer_key: principal[:issuer_key], subject: principal[:subject], **opts)
  end

  def command_for(receipt, org:, key: "idem-#{SecureRandom.hex(4)}", schema: "1.0")
    Workflows::Wf001::Commands::SignInExistingAccount.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: schema,
      organization_id: org, receipt_digest: receipt[:receipt_digest], requested_at_utc: fixed_now
    )
  end

  def sign_in(receipt, org:, key: "idem-#{SecureRandom.hex(4)}", ctx: context)
    Workflows::Wf001::Handlers::SignInExistingAccount.new.call(
      command: command_for(receipt, org:, key:), request_context: ctx
    )
  end

  describe "success" do
    it "creates one active Session, emits one SessionCreated, consumes the nonce, changes no Account/Organization state" do
      seeded = seed
      org = seeded[:organization_id]

      result = sign_in(receipt_for, org:)

      expect(result).to be_success
      expect(result.payload[:session_id]).to be_present
      expect(result.payload[:destination]).to eq("organization_home")
      expect(result.payload[:idle_expires_at_utc]).to eq((fixed_now + (30 * 60)).iso8601(6))
      expect(result.payload[:absolute_expires_at_utc]).to eq((fixed_now + (12 * 60 * 60)).iso8601(6))

      expect(DbInspector.count("sessions")).to eq(1)
      s = DbInspector.one("SELECT status, organization_id, account_id, creation_reason FROM sessions")
      expect(s["status"]).to eq("active")
      expect(s["organization_id"]).to eq(org)
      expect(s["account_id"]).to eq(seeded[:account_id])
      expect(s["creation_reason"]).to eq("existing_account_sign_in")

      expect(DbInspector.count("event_registry")).to eq(1)
      e = DbInspector.one("SELECT event_type, workflow_id, organization_id FROM event_registry")
      expect(e["event_type"]).to eq("SessionCreated")
      expect(e["workflow_id"]).to eq("WF-001")
      expect(e["organization_id"]).to eq(org) # real tenant org; OD-013 substitution does not apply

      expect(DbInspector.count("identity_receipt_consumptions")).to eq(1)
      expect(DbInspector.one("SELECT outcome FROM identity_receipt_consumptions")["outcome"]).to eq("consumed")

      # No Account or Organization mutation.
      expect(DbInspector.one("SELECT status FROM accounts")["status"]).to eq("active")
      expect(DbInspector.one("SELECT status FROM organizations")["status"]).to eq("active")
    end

    it "produces event_bytes whose sha256 the database recomputes and accepts" do
      org = seed[:organization_id]
      sign_in(receipt_for, org:)
      row = DbInspector.one("SELECT (event_sha256 = public.digest(event_bytes,'sha256')) AS ok FROM event_registry")
      expect(row["ok"]).to eq("t")
    end

    it "gives a deny-by-default Session with destination access_unavailable when the Account has no effective Role Assignment" do
      org = seed(with_role: false)[:organization_id]
      result = sign_in(receipt_for, org:)

      expect(result).to be_success
      expect(result.payload[:destination]).to eq("access_unavailable")
      expect(DbInspector.count("sessions")).to eq(1)
      expect(DbInspector.one("SELECT status FROM sessions")["status"]).to eq("active")
    end

    it "signs in a non-administrative (read_only MarketingOperator) context without MFA" do
      org = seed(canonical_role: "MarketingOperator", permission_mode: "read_only", persona: "executive_buyer")[:organization_id]
      result = sign_in(receipt_for(mfa_satisfied: false), org:)

      expect(result).to be_success
      expect(result.payload[:destination]).to eq("organization_home")
    end
  end

  describe "replay and idempotency" do
    it "returns the same Session on exact replay, emitting no second event and consuming no second nonce" do
      org = seed[:organization_id]
      receipt = receipt_for
      first = sign_in(receipt, org:, key: "idem-1")
      second = sign_in(receipt, org:, key: "idem-1")

      expect(second).to be_success
      expect(second.replayed).to be(true)
      expect(second.payload[:session_id]).to eq(first.payload[:session_id])
      expect(DbInspector.count("sessions")).to eq(1)
      expect(DbInspector.count("event_registry")).to eq(1)
      expect(DbInspector.count("identity_receipt_consumptions")).to eq(1)
    end

    it "rejects an altered command under the same idempotency identity (F1-DOMAIN-409 idempotency_conflict)" do
      org = seed[:organization_id]
      sign_in(receipt_for, org:, key: "idem-1")
      # A second, distinct valid receipt for the same Account under the same key is
      # a different canonical command: it conflicts only after every earlier check passes.
      result = sign_in(receipt_for, org:, key: "idem-1")

      expect(result).to be_failure
      expect(result.reason_code).to eq("idempotency_conflict")
      expect(result.failure.error_code).to eq("F1-DOMAIN-409")
      expect(DbInspector.count("sessions")).to eq(1)
    end
  end

  describe "receipt and identity failures (normalized outward, exact internal reason retained)" do
    it "rejects an unresolved receipt digest as authentication_failed, writing no Session or event" do
      org = seed[:organization_id]
      bogus = { receipt_digest: Digest::SHA256.digest("no-such-receipt") }
      result = sign_in(bogus, org:)

      expect(result).to be_failure
      expect(result.reason_code).to eq("authentication_failed")
      expect(result.failure.error_code).to eq("F1-AUTHN-401")
      expect(DbInspector.count("sessions")).to eq(0)
      expect(DbInspector.count("event_registry")).to eq(0)
      a = DbInspector.one("SELECT reason_code FROM audit_record_registry WHERE outcome='failure'")
      expect(a["reason_code"]).to eq("identity_receipt_invalid")
    end

    it "normalizes an expired receipt to authentication_failed but retains identity_receipt_expired internally" do
      org = seed[:organization_id]
      result = sign_in(receipt_for(validated_at: fixed_now - (11 * 60)), org:)

      expect(result).to be_failure
      expect(result.reason_code).to eq("authentication_failed")
      a = DbInspector.one("SELECT reason_code FROM audit_record_registry WHERE outcome='failure'")
      expect(a["reason_code"]).to eq("identity_receipt_expired")
      expect(DbInspector.count("sessions")).to eq(0)
    end

    it "rejects a valid receipt with no matching Account as authentication_failed" do
      org = TenantSeeder.create_organization
      TenantSeeder.create_access_policy(organization_id: org)
      result = sign_in(receipt_for, org:)

      expect(result).to be_failure
      expect(result.reason_code).to eq("authentication_failed")
      expect(DbInspector.count("sessions")).to eq(0)
    end

    it "rejects a revoked Account as authentication_failed (exact internal account_revoked)" do
      org = seed(account_status: "revoked")[:organization_id]
      result = sign_in(receipt_for, org:)

      expect(result).to be_failure
      expect(result.reason_code).to eq("authentication_failed")
      a = DbInspector.one("SELECT reason_code FROM audit_record_registry WHERE outcome='failure'")
      expect(a["reason_code"]).to eq("account_revoked")
    end
  end

  describe "state and policy failures" do
    it "rejects a suspended Account as account_suspended (F1-AUTH-403), leaving the Account suspended and unchanged" do
      org = seed(account_status: "suspended")[:organization_id]
      result = sign_in(receipt_for, org:)

      expect(result).to be_failure
      expect(result.reason_code).to eq("account_suspended")
      expect(result.failure.error_code).to eq("F1-AUTH-403")
      expect(DbInspector.count("sessions")).to eq(0)
      # No automatic lockout or failed-attempt state transition.
      expect(DbInspector.one("SELECT status FROM accounts")["status"]).to eq("suspended")
    end

    it "rejects an inactive Organization as organization_inactive (F1-AUTH-403)" do
      org = seed(org_status: "suspended")[:organization_id]
      result = sign_in(receipt_for, org:)

      expect(result).to be_failure
      expect(result.reason_code).to eq("organization_inactive")
      expect(result.failure.error_code).to eq("F1-AUTH-403")
      expect(DbInspector.count("sessions")).to eq(0)
    end

    it "rejects insufficient MFA for an administrative-role-capable context as identity_assurance_failed" do
      org = seed(canonical_role: "OrganizationAdmin")[:organization_id]
      result = sign_in(receipt_for(mfa_satisfied: false), org:)

      expect(result).to be_failure
      expect(result.reason_code).to eq("identity_assurance_failed")
      expect(result.failure.error_code).to eq("F1-AUTHN-401")
      expect(DbInspector.count("sessions")).to eq(0)
    end

    it "rejects a resolution with no active Access Policy as policy_unavailable (F1-DOMAIN-409)" do
      org = seed(with_policy: false)[:organization_id]
      result = sign_in(receipt_for, org:)

      expect(result).to be_failure
      expect(result.reason_code).to eq("policy_unavailable")
      expect(result.failure.error_code).to eq("F1-DOMAIN-409")
      expect(DbInspector.count("sessions")).to eq(0)
    end

    it "rejects an unsupported command schema major (F1-VALIDATION-400)" do
      org = seed[:organization_id]
      result = Workflows::Wf001::Handlers::SignInExistingAccount.new.call(
        command: command_for(receipt_for, org:, schema: "2.0"), request_context: context
      )

      expect(result).to be_failure
      expect(result.reason_code).to eq("command_schema_unsupported")
      expect(result.failure.error_code).to eq("F1-VALIDATION-400")
    end
  end

  describe "concurrent Sessions" do
    it "creates two concurrent Sessions for distinct valid receipts and revokes neither" do
      org = seed[:organization_id]
      receipts = [receipt_for, receipt_for] # distinct receipts, same Account

      results = receipts.each_with_index.map do |r, i|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            sign_in(r, org:, key: "k#{i}")
          end
        end
      end.map(&:value)

      expect(results.count(&:success?)).to eq(2)
      expect(DbInspector.count("sessions")).to eq(2)
      expect(DbInspector.all("SELECT status FROM sessions").map { |row| row["status"] }).to all(eq("active"))
    end
  end
end
