# frozen_string_literal: true

require "rails_helper"

# Direct oracle for the WF-001 invitation-acceptance branch of AC-CAP-001 /
# AC-WF-001 (WORKFLOW_SPECIFICATIONS.md § invitation acceptance): one atomic
# multi-root commit that creates or binds the Account, creates or reuses the exact
# offered Role Assignment, transitions the Invitation active->accepted, consumes
# the receipt nonce and creates a Session, with the exact new/existing/reused
# event orders; the non-disclosing invitation_not_active for unresolved/terminal/
# expired references; the wrong-identity denial that binds the nonce and reveals
# nothing; and the ineligibility/identity-conflict/altered-tuple failures.
RSpec.describe "WF-001 AcceptInvitation", type: :acceptance,
               acceptance_ids: ["AC-CAP-001", "AC-WF-001"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA TYP-OBS] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  # The approved identity/bootstrap service is a registered principal, not a
  # value each caller invents (WORKFLOW_SPECIFICATIONS.md § onboarding-interim-v1).
  let(:service_id) { Platform::ServiceIdentity.identity_service }
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

  def command_for(inv, receipt, key: "idem-#{SecureRandom.hex(4)}", schema: "1.0",
                  supplied_account_id: nil, overrides: {})
    Workflows::Wf001::Commands::AcceptInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: schema,
      invitation_reference: inv[:reference], receipt_digest: receipt[:receipt_digest],
      accepted_canonical_role: overrides.fetch(:role, inv[:canonical_role]),
      accepted_permission_mode: overrides.fetch(:mode, inv[:permission_mode]),
      accepted_persona: overrides.fetch(:persona, inv[:persona]),
      accepted_scope_sha256: overrides.fetch(:scope_sha256, inv[:scope_sha256]),
      supplied_account_id:, requested_at_utc: fixed_now
    )
  end

  def accept(inv, receipt, ctx: context, **opts)
    Workflows::Wf001::Handlers::AcceptInvitation.new.call(command: command_for(inv, receipt, **opts), request_context: ctx)
  end

  def event_types = DbInspector.all("SELECT event_type FROM event_registry ORDER BY created_at").map { |r| r["event_type"] }

  describe "success — new Account" do
    it "creates the Account active, one Role Assignment, accepts the Invitation, creates a Session, in causal event order" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)

      result = accept(inv, receipt_for)

      expect(result).to be_success
      expect(result.payload[:account_id]).to be_present
      expect(result.payload[:role_assignment_id]).to be_present
      expect(result.payload[:invitation_id]).to eq(inv[:invitation_id])
      expect(result.payload[:session_id]).to be_present
      expect(result.payload[:organization_id]).to eq(org)

      acct = DbInspector.one("SELECT status, identity_issuer_key, identity_subject, normalized_email FROM accounts")
      expect(acct["status"]).to eq("active")
      expect(acct["identity_issuer_key"]).to eq(invitee[:issuer_key])
      expect(acct["identity_subject"]).to eq(invitee[:subject])
      expect(acct["normalized_email"]).to eq(invitee[:email])

      expect(DbInspector.count("role_assignments")).to eq(1)
      role = DbInspector.one("SELECT canonical_role, status FROM role_assignments")
      expect(role["status"]).to eq("active")
      expect(role["canonical_role"]).to eq(inv[:canonical_role])

      invrow = DbInspector.one("SELECT state, fulfilled_by_role_assignment_id FROM invitations")
      expect(invrow["state"]).to eq("accepted")
      expect(invrow["fulfilled_by_role_assignment_id"]).to eq(result.payload[:role_assignment_id])
      expect(DbInspector.one("SELECT invitation_state FROM invitation_reference_registry")["invitation_state"]).to eq("accepted")

      expect(DbInspector.one("SELECT creation_reason FROM sessions")["creation_reason"]).to eq("invitation_acceptance")
      expect(DbInspector.one("SELECT outcome FROM identity_receipt_consumptions")["outcome"]).to eq("consumed")

      expect(event_types).to eq(%w[AccountProvisionRequested AccountActivated RoleGranted InvitationAccepted SessionCreated])
    end

    it "produces event_bytes whose sha256 the database recomputes and accepts" do
      org = TenantSeeder.create_organization
      accept(seed_invitation(org:), receipt_for)
      oks = DbInspector.all("SELECT (event_sha256 = public.digest(event_bytes,'sha256')) AS ok FROM event_registry")
      expect(oks.map { |r| r["ok"] }).to all(eq("t"))
    end
  end

  describe "success — existing Account" do
    it "binds the existing active Account (no Account events) and creates a new Assignment" do
      org = TenantSeeder.create_organization
      account_id = TenantSeeder.create_account(organization_id: org, issuer_key: invitee[:issuer_key],
                                               subject: invitee[:subject], email: invitee[:email], status: "active")
      inv = seed_invitation(org:)

      result = accept(inv, receipt_for)

      expect(result).to be_success
      expect(result.payload[:account_id]).to eq(account_id)
      expect(DbInspector.count("accounts")).to eq(1) # bound, not created
      expect(event_types).to eq(%w[RoleGranted InvitationAccepted SessionCreated])
    end

    it "reuses an already-effective exact Role Assignment (no RoleGranted event)" do
      org = TenantSeeder.create_organization
      account_id = TenantSeeder.create_account(organization_id: org, issuer_key: invitee[:issuer_key],
                                               subject: invitee[:subject], email: invitee[:email], status: "active")
      inv = seed_invitation(org:)
      existing = TenantSeeder.create_role_assignment(
        organization_id: org, account_id:, canonical_role: inv[:canonical_role],
        permission_mode: inv[:permission_mode], persona: inv[:persona], scope_sha256: inv[:scope_sha256]
      )

      result = accept(inv, receipt_for)

      expect(result).to be_success
      expect(result.payload[:role_assignment_id]).to eq(existing)
      expect(DbInspector.count("role_assignments")).to eq(1) # reused, not created
      expect(event_types).to eq(%w[InvitationAccepted SessionCreated])
      expect(DbInspector.one("SELECT fulfilled_by_role_assignment_id FROM invitations")["fulfilled_by_role_assignment_id"]).to eq(existing)
    end
  end

  describe "denials — changes nothing" do
    it "wrong identity: leaves the Invitation active, binds the nonce, emits no Invitation event, discloses nothing" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      # A receipt whose email does not match the Invitation target.
      result = accept(inv, receipt_for(email: "someone-else-#{SecureRandom.hex(3)}@example.com"))

      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_target_mismatch")
      expect(result.failure.error_code).to eq("F1-DOMAIN-409")
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("active")
      expect(DbInspector.count("accounts")).to eq(0)
      expect(DbInspector.count("sessions")).to eq(0)
      expect(DbInspector.count("event_registry")).to eq(0)
      # nonce bound to the denied command
      expect(DbInspector.one("SELECT outcome, reason_code FROM identity_receipt_consumptions")).to eq(
        { "outcome" => "rejected", "reason_code" => "invitation_target_mismatch" }
      )
      # restricted audit reveals neither the intended email nor identity
      audit = DbInspector.one("SELECT payload::text AS p FROM audit_record_registry WHERE outcome='failure'")
      expect(audit["p"]).not_to include(invitee[:email])
      expect(audit["p"]).not_to include(invitee[:subject])
    end

    it "suspended matching Account: invitation_account_ineligible, changes nothing" do
      org = TenantSeeder.create_organization
      TenantSeeder.create_account(organization_id: org, issuer_key: invitee[:issuer_key],
                                  subject: invitee[:subject], email: invitee[:email], status: "suspended")
      inv = seed_invitation(org:)

      result = accept(inv, receipt_for)
      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_account_ineligible")
      expect(result.failure.error_code).to eq("F1-DOMAIN-409")
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("active")
      expect(DbInspector.one("SELECT status FROM accounts")["status"]).to eq("suspended")
      expect(DbInspector.count("sessions")).to eq(0)
    end

    it "revoked matching Account: invitation_account_ineligible" do
      org = TenantSeeder.create_organization
      TenantSeeder.create_account(organization_id: org, issuer_key: invitee[:issuer_key],
                                  subject: invitee[:subject], email: invitee[:email], status: "revoked")
      result = accept(seed_invitation(org:), receipt_for)
      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_account_ineligible")
    end

    it "supplied Account ID not equal to the identity Account: account_identity_conflict (F1-AUTH-403)" do
      org = TenantSeeder.create_organization
      TenantSeeder.create_account(organization_id: org, issuer_key: invitee[:issuer_key],
                                  subject: invitee[:subject], email: invitee[:email], status: "active")
      other = TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                          subject: "other-#{SecureRandom.hex(6)}", status: "active")
      inv = seed_invitation(org:)

      result = accept(inv, receipt_for, supplied_account_id: other)
      expect(result).to be_failure
      expect(result.reason_code).to eq("account_identity_conflict")
      expect(result.failure.error_code).to eq("F1-AUTH-403")
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("active")
    end

    it "cross-Organization Account id: account_identity_conflict (F1-AUTH-403), not visible in context" do
      other_org = TenantSeeder.create_organization
      cross = TenantSeeder.create_account(organization_id: other_org, issuer_key: invitee[:issuer_key],
                                          subject: invitee[:subject], email: invitee[:email], status: "active")
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)

      result = accept(inv, receipt_for, supplied_account_id: cross)
      expect(result).to be_failure
      expect(result.reason_code).to eq("account_identity_conflict")
      expect(result.failure.error_code).to eq("F1-AUTH-403")
    end

    it "altered role/scope: invitation_role_scope_changed" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:, canonical_role: "MarketingOperator")

      result = accept(inv, receipt_for, overrides: { role: "OrganizationAdmin" })
      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_role_scope_changed")
      expect(result.failure.error_code).to eq("F1-DOMAIN-409")
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("active")
    end
  end

  describe "reference resolution — non-disclosing" do
    it "terminal Invitation: generic invitation_not_active, no context established" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:, state: "revoked")
      result = accept(inv, receipt_for)
      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_not_active")
      expect(result.failure.error_code).to eq("F1-DOMAIN-409")
    end

    it "expired Invitation resolves to the generic invitation_not_active (resolver non-disclosure)" do
      org = TenantSeeder.create_organization
      # Active state, activated 8 days before now -> expires_at one day in the past.
      inv = seed_invitation(org:, state: "active", activated_at: fixed_now - (8 * 24 * 3600))
      result = accept(inv, receipt_for)
      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_not_active")
    end

    it "unknown reference: invitation_not_active" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      bogus = inv.merge(reference: SecureRandom.random_bytes(32))
      result = accept(bogus, receipt_for)
      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_not_active")
    end
  end

  describe "restricted exact replay (through the ledger, not the resolver)" do
    it "exact replay of a successful acceptance returns the same five identifiers and emits no new events" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      receipt = receipt_for
      first = accept(inv, receipt, key: "idem-1")
      expect(first).to be_success
      events_before = DbInspector.count("event_registry")

      second = accept(inv, receipt, key: "idem-1") # exact same command
      expect(second).to be_success
      expect(second.replayed).to be(true)
      expect(second.payload).to eq(first.payload) # the same account/role/invitation/session/organization ids
      expect(DbInspector.count("event_registry")).to eq(events_before) # no new events
      expect(DbInspector.count("accounts")).to eq(1)
      expect(DbInspector.count("sessions")).to eq(1)
      expect(DbInspector.count("role_assignments")).to eq(1)
    end

    it "exact replay denied by current reauthorization returns F1-AUTH-403 with no retained payload" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      receipt = receipt_for
      first = accept(inv, receipt, key: "idem-1")
      expect(first).to be_success
      # Reauthorization fails once the fulfilled Account is no longer active.
      DbInspector.connection.exec_params("UPDATE accounts SET status='suspended' WHERE id=$1", [first.payload[:account_id]])

      second = accept(inv, receipt, key: "idem-1")
      expect(second).to be_failure
      expect(second.reason_code).to eq("reauthorization_denied")
      expect(second.failure.error_code).to eq("F1-AUTH-403")
      expect(second.payload).to be_nil
    end

    it "the same idempotency key with changed input returns idempotency_conflict" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      receipt = receipt_for
      first = accept(inv, receipt, key: "idem-1")
      expect(first).to be_success

      second = accept(inv, receipt, key: "idem-1", overrides: { role: "OrganizationAdmin" })
      expect(second).to be_failure
      expect(second.reason_code).to eq("idempotency_conflict")
      expect(second.failure.error_code).to eq("F1-DOMAIN-409")
    end

    it "an ordinary second response that is not an exact replay still returns invitation_not_active" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      expect(accept(inv, receipt_for, key: "idem-1")).to be_success

      second = accept(inv, receipt_for, key: "a-different-key")
      expect(second).to be_failure
      expect(second.reason_code).to eq("invitation_not_active")
    end

    it "the public resolver never resolves a terminal Invitation" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:, state: "accepted")
      rows = DbInspector.connection.exec_params(
        "SELECT organization_id FROM f1_resolve_invitation_reference($1)",
        [{ value: inv[:reference_digest], format: 1 }]
      ).to_a
      expect(rows).to be_empty
    end
  end

  describe "in-context idempotency" do
    it "exact replay of a still-active failed command returns the stored failure" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      receipt = receipt_for
      first = accept(inv, receipt, key: "idem-9", overrides: { role: "OrganizationAdmin" })
      second = accept(inv, receipt, key: "idem-9", overrides: { role: "OrganizationAdmin" })

      expect(first).to be_failure
      expect(first.reason_code).to eq("invitation_role_scope_changed")
      expect(second).to be_failure
      expect(second.replayed).to be(true)
      expect(second.reason_code).to eq("invitation_role_scope_changed")
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("active")
    end

    it "rejects an unsupported command schema major (F1-VALIDATION-400)" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      result = accept(inv, receipt_for, schema: "2.0")
      expect(result).to be_failure
      expect(result.reason_code).to eq("command_schema_unsupported")
      expect(result.failure.error_code).to eq("F1-VALIDATION-400")
    end
  end

  describe "concurrency" do
    it "concurrent acceptances of one Invitation commit exactly one grant" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      receipts = [receipt_for, receipt_for] # distinct receipts, same invitee

      results = receipts.each_with_index.map do |r, i|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            accept(inv, r, key: "k#{i}")
          end
        end
      end.map(&:value)

      expect(results.count(&:success?)).to eq(1)
      expect(DbInspector.count("accounts")).to eq(1)
      expect(DbInspector.count("sessions")).to eq(1)
      expect(DbInspector.all("SELECT state FROM invitations").map { |r| r["state"] }).to eq(["accepted"])
      expect(results.find(&:failure?).reason_code).to eq("invitation_not_active")
    end
  end
end
