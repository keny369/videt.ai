# frozen_string_literal: true

require "rails_helper"

# WF-013 DecideInvitation — the protected branch's activation
# (WORKFLOW_SPECIFICATIONS.md :242 "A different SecurityOperator holding
# `invitation.approve` may activate it"; :333 "approval within 24 hours by a
# SecurityOperator other than the requester … rejection or expiry grants
# nothing").
#
# Approval runs through the SAME activation routine CreateInvitation uses, so
# the pending → active transition and its expiry timer are one transaction.
RSpec.describe "WF-013 decide invitation", type: :acceptance,
               acceptance_ids: ["AC-CAP-013", "AC-WF-013"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def requested_at = fixed_now - 3600

  let(:org) { TenantSeeder.create_organization }
  let(:requester) do
    TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                subject: "requester-#{SecureRandom.hex(6)}")
  end

  def ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(fixed_now),
                                               ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)

  # A SecurityOperator whose Assignment carries the protected explicit grant.
  def approver(allowlist: ["invitation.approve"], account_id: nil)
    account = account_id || TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                                        subject: "approver-#{SecureRandom.hex(6)}")
    assignment = TenantSeeder.create_role_assignment(organization_id: org, account_id: account,
                                                     canonical_role: "SecurityOperator")
    DbInspector.connection.exec_params(
      "UPDATE role_assignments SET protected_permission_allowlist = $2::jsonb WHERE id = $1::uuid",
      [assignment, JSON.generate(allowlist)]
    )
    TenantSeeder.create_access_policy(organization_id: org) if DbInspector.count("access_policies").zero?
    session = TenantSeeder.create_session(organization_id: org, account_id: account, issued_at: fixed_now - 900)
    { account_id: account, session_id: session }
  end

  # A pending-approval Invitation whose approval window is still open.
  def pending(requester_account_id: nil)
    inv = TenantSeeder.create_invitation(organization_id: org, state: "pending_approval",
                                         canonical_role: "OrganizationAdmin",
                                         requester_account_id: requester_account_id || requester)
    DbInspector.connection.exec_params(<<~SQL, [inv[:invitation_id], requested_at.iso8601(6)])
      UPDATE invitations SET requested_at = $2::timestamptz, approval_due_at = $2::timestamptz + interval '24 hours'
      WHERE id = $1::uuid
    SQL
    inv
  end

  def decide(inv, actor, decision: "approve", key: "dec-1", version: 0, reason: nil)
    cmd = Workflows::Wf013::Commands::DecideInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      session_id: actor[:session_id], invitation_id: inv[:invitation_id], expected_state_version: version,
      decision:, reason:, requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::DecideInvitation.new.call(command: cmd, request_context: ctx)
  end

  def invitation = DbInspector.one("SELECT * FROM invitations")
  def actions = DbInspector.all("SELECT * FROM scheduled_actions")
  def events = DbInspector.all("SELECT event_type FROM event_registry").map { |r| r["event_type"] }

  describe "approval activates and schedules expiry in one transaction" do
    it "takes the Invitation pending_approval -> active with exactly one expiry timer" do
      inv = pending
      result = decide(inv, approver)

      expect(result).to be_success
      row = invitation
      expect(row["state"]).to eq("active")
      expect(Time.parse(row["activated_at"]).getutc).to eq(fixed_now)
      expect(Time.parse(row["expires_at"]).getutc).to eq(fixed_now + (7 * 24 * 3600))
      expect(row["state_version"].to_i).to eq(1)

      expect(actions.size).to eq(1)
      expect(actions.first["target_id"]).to eq(inv[:invitation_id])
      expect(Time.parse(actions.first["due_at"]).getutc).to eq(Time.parse(row["expires_at"]).getutc)
    end

    it "emits one InvitationActivated state-transition event and records the approver" do
      inv = pending
      decide(inv, approver)

      expect(events).to eq(["InvitationActivated"])
      body = JSON.parse(DbInspector.one("SELECT convert_from(event_bytes,'UTF8') AS b FROM event_registry")["b"])
      expect(body["event_profile"]).to eq("state_transition")
      expect(body["from_state"]).to eq("pending_approval")
      expect(body["to_state"]).to eq("active")
      expect(body["requester_account_id"]).to eq(requester)
      expect(invitation["security_approver_account_id"]).not_to be_nil
      expect(invitation["security_approver_account_id"]).not_to eq(requester)
    end

    it "publishes the reference so the public resolver resolves it only after approval" do
      inv = pending
      before = DbInspector.all("SELECT * FROM f1_resolve_invitation_reference($1)",
                               [{ value: inv[:reference_digest], format: 1 }])
      expect(before).to be_empty

      decide(inv, approver)
      after = DbInspector.all("SELECT * FROM f1_resolve_invitation_reference($1)",
                              [{ value: inv[:reference_digest], format: 1 }])
      expect(after.size).to eq(1)
    end
  end

  describe "rejection is terminal and grants nothing" do
    it "takes pending_approval -> rejected, emits InvitationRejected and creates no timer" do
      inv = pending
      result = decide(inv, approver, decision: "reject", reason: "not appropriate for this organization")

      expect(result).to be_success
      expect(invitation["state"]).to eq("rejected")
      expect(invitation["transition_reason_code"]).to eq("invitation_rejected")
      expect(actions).to be_empty
      expect(events).to eq(["InvitationRejected"])
      expect(DbInspector.one("SELECT invitation_state FROM invitation_reference_registry")["invitation_state"])
        .to eq("rejected")
    end

    it "requires a 20-2,000 character reason to reject" do
      inv = pending
      expect(decide(inv, approver, decision: "reject", reason: "no").reason_code).to eq("invitation_reason_invalid")
      expect(invitation["state"]).to eq("pending_approval")
    end
  end

  describe "authority" do
    it "denies a SecurityOperator without the protected explicit grant" do
      inv = pending
      result = decide(inv, approver(allowlist: []))

      expect(result).to be_failure
      expect(result.reason_code).to eq("missing_authority")
      expect(invitation["state"]).to eq("pending_approval")
      expect(actions).to be_empty
      expect(DbInspector.one("SELECT reason_code FROM audit_record_registry")["reason_code"])
        .to eq("protected_grant_required")
    end

    it "denies an OrganizationAdmin, whose baseline cell for invitation.approve is deny" do
      inv = pending
      TenantSeeder.create_access_policy(organization_id: org) if DbInspector.count("access_policies").zero?
      admin = TenantSeeder.seed_authorized_admin(organization_id: org, with_policy: false, issued_at: fixed_now - 900)
      result = decide(inv, admin)

      expect(result.reason_code).to eq("missing_authority")
      expect(invitation["state"]).to eq("pending_approval")
    end

    it "refuses an approver who is the requester (separation of duty)" do
      security = approver
      inv = pending(requester_account_id: security[:account_id])
      result = decide(inv, security)

      expect(result.reason_code).to eq("invitation_approver_conflict")
      expect(invitation["state"]).to eq("pending_approval")
      expect(actions).to be_empty
    end
  end

  describe "the approval window" do
    it "refuses a decision at or after the 24-hour due instant, where expiry wins" do
      inv = pending
      # The 24-hour window is a CHECK on the pair, so the request instant moves with it.
      DbInspector.connection.exec_params(<<~SQL, [inv[:invitation_id], (fixed_now - (24 * 3600)).iso8601(6)])
        UPDATE invitations
        SET requested_at = $2::timestamptz, approval_due_at = $2::timestamptz + interval '24 hours'
        WHERE id = $1::uuid
      SQL
      result = decide(inv, approver)

      expect(result.reason_code).to eq("invitation_not_active")
      expect(invitation["state"]).to eq("pending_approval")
      expect(actions).to be_empty
    end
  end

  describe "idempotency and state" do
    it "returns the stored result on exact replay, creating no second timer or event" do
      inv = pending
      security = approver
      first = decide(inv, security, key: "same")
      replay = decide(inv, security, key: "same")

      expect(replay.replayed).to be(true)
      expect(replay.payload).to eq(first.payload)
      expect(actions.size).to eq(1)
      expect(events).to eq(["InvitationActivated"])
    end

    it "refuses a stale expected state version" do
      inv = pending
      expect(decide(inv, approver, version: 7).reason_code).to eq("stale_state_version")
      expect(invitation["state"]).to eq("pending_approval")
    end

    it "refuses to decide an Invitation that is no longer pending approval" do
      inv = pending
      security = approver
      expect(decide(inv, security, key: "a")).to be_success
      expect(decide(inv, security, key: "b", version: 1).reason_code).to eq("invitation_not_active")
      expect(actions.size).to eq(1)
      expect(events).to eq(["InvitationActivated"])
    end
  end
end
