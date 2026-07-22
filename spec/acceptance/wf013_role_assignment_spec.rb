# frozen_string_literal: true

require "rails_helper"

# WF-013 Role Assignment grant and approval (WORKFLOW_SPECIFICATIONS.md :314,
# :316, :333). The real grant path, and therefore the first way protected
# authority can exist outside the WF-001 bootstrap.
#
# The closing example is the one that matters most: a SecurityOperator obtains
# `invitation.approve` through Request + Decide ONLY, and then approves an
# Invitation. No fixture writes an allowlist.
RSpec.describe "WF-013 role assignment lifecycle", type: :acceptance,
               acceptance_ids: ["AC-CAP-013", "AC-WF-013"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def org_scope = Digest::SHA256.digest("scope:organization")

  let(:admin) { TenantSeeder.seed_authorized_admin(issued_at: fixed_now - 900) }
  let(:org) { admin[:organization_id] }

  def ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(fixed_now),
                                               ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)

  def account(subject = "target")
    TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                subject: "#{subject}-#{SecureRandom.hex(6)}")
  end

  def session_for(account_id) = TenantSeeder.create_session(organization_id: org, account_id:,
                                                            issued_at: fixed_now - 900)

  def request_grant(target, role: "MarketingOperator", key: "req-#{SecureRandom.hex(3)}", epoch: 7,
                    expires_at: nil, session_id: nil, scope: org_scope)
    cmd = Workflows::Wf013::Commands::RequestRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      session_id: session_id || admin[:session_id], account_id: target, canonical_role: role,
      permission_mode: "standard", persona: nil, scope_sha256: scope, expires_at:,
      expected_authorization_epoch: epoch, reason: nil, requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::RequestRoleAssignment.new.call(command: cmd, request_context: ctx)
  end

  def decide(assignment_id, session_id, decision: "approve", key: "dec-#{SecureRandom.hex(3)}",
             version: 0, epoch: 7, reason: nil)
    cmd = Workflows::Wf013::Commands::DecideRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id:,
      role_assignment_id: assignment_id, expected_state_version: version,
      expected_authorization_epoch: epoch, decision:, reason:, requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::DecideRoleAssignment.new.call(command: cmd, request_context: ctx)
  end

  def assignment(id) = DbInspector.one("SELECT * FROM role_assignments WHERE id = $1::uuid", [id])
  def epoch = DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id = $1::uuid",
                              [org])["authorization_epoch"].to_i
  def events = DbInspector.all("SELECT event_type FROM event_registry ORDER BY created_at").map { |e| e["event_type"] }

  describe "a nonprotected grant becomes active directly" do
    it "creates an active Assignment and advances the authorization epoch in one transaction" do
      target = account
      result = request_grant(target)

      expect(result).to be_success
      row = assignment(result.payload[:role_assignment_id])
      expect(row["status"]).to eq("active")
      expect(row["effective_at"]).not_to be_nil
      expect(row["requester_account_id"]).to eq(admin[:account_id])
      expect(JSON.parse(row["protected_permission_allowlist"])).to eq([])
      expect(epoch).to eq(8)
      expect(events).to eq(["RoleGranted"])
    end

    it "schedules exactly one expiry timer when the grant expires, and none when it does not" do
      with_expiry = request_grant(account, expires_at: fixed_now + (10 * 24 * 3600))
      expect(DbInspector.count("scheduled_actions")).to eq(1)
      action = DbInspector.one("SELECT * FROM scheduled_actions")
      expect(action["action_kind"]).to eq("role_assignment_expire")
      expect(action["target_id"]).to eq(with_expiry.payload[:role_assignment_id])

      request_grant(account, key: "second", epoch: 8)
      expect(DbInspector.count("scheduled_actions")).to eq(1)
    end

    it "returns the stored result on exact replay, creating no second Assignment or epoch advance" do
      target = account
      first = request_grant(target, key: "same")
      replay = request_grant(target, key: "same")

      expect(replay.replayed).to be(true)
      expect(replay.payload[:role_assignment_id]).to eq(first.payload[:role_assignment_id])
      expect(DbInspector.count("role_assignments")).to eq(2) # the bootstrap admin plus this one
      expect(epoch).to eq(8)
    end

    it "refuses a stale authorization epoch and changes nothing" do
      expect(request_grant(account, epoch: 99).reason_code).to eq("stale_authorization_epoch")
      expect(epoch).to eq(7)
    end
  end

  describe "a protected grant waits for approval and confers nothing meanwhile" do
    it "creates a pending Assignment with a 24-hour window, no epoch advance and no timer" do
      result = request_grant(account, role: "OrganizationAdmin", expires_at: fixed_now + (10 * 24 * 3600))

      expect(result).to be_success
      row = assignment(result.payload[:role_assignment_id])
      expect(row["status"]).to eq("pending")
      expect(row["effective_at"]).to be_nil
      expect(JSON.parse(row["protected_permission_allowlist"])).to eq([])
      expect(Time.parse(row["approval_due_at"]).getutc).to eq(fixed_now + (24 * 3600))
      expect(epoch).to eq(7)
      expect(DbInspector.count("scheduled_actions")).to eq(0)
      expect(events).to eq(["RoleAssignmentRequested"])
    end

    it "requires an expiry for a protected grant" do
      expect(request_grant(account, role: "OrganizationAdmin").reason_code).to eq("role_expiry_required")
      expect(DbInspector.count("role_assignments")).to eq(1)
    end

    it "refuses a protected expiry beyond the 30-day bound" do
      expect(request_grant(account, role: "OrganizationAdmin", expires_at: fixed_now + (31 * 24 * 3600)).reason_code)
        .to eq("role_expiry_invalid")
    end

    it "does not let the bootstrap administrator grant protected authority directly" do
      # The bootstrap exception lets the first admin USE protected permissions; it
      # is not a bypass of protected approval.
      result = request_grant(account, role: "OrganizationAdmin", expires_at: fixed_now + (10 * 24 * 3600))
      expect(assignment(result.payload[:role_assignment_id])["status"]).to eq("pending")
    end
  end

  # An approver must itself hold approved `role.manage`, which only approval can
  # confer — so the first SecurityOperator is deliberately unreachable here and is
  # seeded once, exactly as the security-bootstrap service would.
  def seeded_security_operator(allowlist: %w[invitation.approve role.manage])
    id = account("sec")
    TenantSeeder.create_role_assignment(organization_id: org, account_id: id,
                                        canonical_role: "SecurityOperator",
                                        protected_permission_allowlist: allowlist)
    { account_id: id, session_id: session_for(id) }
  end

  describe "approval populates the immutable allowlist and activates" do
    it "writes the approved protected subset, activates, advances the epoch and schedules expiry" do
      security = seeded_security_operator
      target = account
      pending = request_grant(target, role: "OrganizationAdmin", expires_at: fixed_now + (10 * 24 * 3600))

      result = decide(pending.payload[:role_assignment_id], security[:session_id])

      expect(result).to be_success
      row = assignment(pending.payload[:role_assignment_id])
      expect(row["status"]).to eq("active")
      expect(JSON.parse(row["protected_permission_allowlist"]))
        .to eq(Platform::PermissionBaseline.protected_permission_preview("OrganizationAdmin"))
      expect(epoch).to eq(8)
      expect(DbInspector.count("scheduled_actions")).to eq(1)
      expect(events).to eq(%w[RoleAssignmentRequested RoleGranted])
    end

    it "writes one immutable, ordered approval record" do
      security = seeded_security_operator
      pending = request_grant(account, role: "OrganizationAdmin", expires_at: fixed_now + (10 * 24 * 3600))
      decide(pending.payload[:role_assignment_id], security[:session_id])

      approval = DbInspector.one("SELECT * FROM role_assignment_approvals")
      expect(approval["sequence_number"].to_i).to eq(1)
      expect(approval["approver_account_id"]).to eq(security[:account_id])
      expect(approval["decision"]).to eq("approve")
      expect(approval["separation_result"]).to eq("distinct")
      expect(DbInspector.one("SELECT has_table_privilege('f1_web','role_assignment_approvals','UPDATE') AS u")["u"])
        .to eq("f")
    end

    it "rejects terminally, conferring nothing and advancing no epoch" do
      security = seeded_security_operator
      pending = request_grant(account, role: "OrganizationAdmin", expires_at: fixed_now + (10 * 24 * 3600))

      result = decide(pending.payload[:role_assignment_id], security[:session_id],
                      decision: "reject", reason: "not appropriate for this organization")

      expect(result).to be_success
      row = assignment(pending.payload[:role_assignment_id])
      expect(row["status"]).to eq("rejected")
      expect(JSON.parse(row["protected_permission_allowlist"])).to eq([])
      expect(epoch).to eq(7)
      expect(DbInspector.count("scheduled_actions")).to eq(0)
      expect(events).to eq(%w[RoleAssignmentRequested RoleRejected])
    end

    it "refuses an approver who is the requester" do
      security = seeded_security_operator
      pending = request_grant(account, role: "OrganizationAdmin", expires_at: fixed_now + (10 * 24 * 3600),
                              session_id: security[:session_id])
      expect(decide(pending.payload[:role_assignment_id], security[:session_id]).reason_code)
        .to eq("role_approver_conflict")
      expect(assignment(pending.payload[:role_assignment_id])["status"]).to eq("pending")
    end

    it "refuses a SecurityOperator whose approved allowlist omits role.manage" do
      security = seeded_security_operator(allowlist: ["security.investigate"])
      pending = request_grant(account, role: "OrganizationAdmin", expires_at: fixed_now + (10 * 24 * 3600))

      expect(decide(pending.payload[:role_assignment_id], security[:session_id]).reason_code)
        .to eq("missing_authority")
      expect(assignment(pending.payload[:role_assignment_id])["status"]).to eq("pending")
    end

    it "refuses an OrganizationAdmin as approver, whose baseline is limited to non-protected grants" do
      pending = request_grant(account, role: "OrganizationAdmin", expires_at: fixed_now + (10 * 24 * 3600))
      expect(decide(pending.payload[:role_assignment_id], admin[:session_id]).reason_code)
        .to eq("missing_authority")
    end

    it "refuses a decision at or after the 24-hour window, where expiry wins" do
      security = seeded_security_operator
      # The request is made a day earlier, so its window has closed by `fixed_now`.
      # The grant content is immutable, so the window is arranged by requesting in
      # the past rather than by editing the row.
      earlier = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(fixed_now - (24 * 3600)),
                                                   ids: Platform::Ids.system,
                                                   correlation_id: SecureRandom.uuid_v7)
      cmd = Workflows::Wf013::Commands::RequestRoleAssignment.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "old", schema_version: "1.0",
        session_id: admin[:session_id], account_id: account, canonical_role: "OrganizationAdmin",
        permission_mode: "standard", persona: nil, scope_sha256: org_scope,
        expires_at: fixed_now + (10 * 24 * 3600), expected_authorization_epoch: 7, reason: nil,
        requested_at_utc: fixed_now - (24 * 3600)
      )
      pending = Workflows::Wf013::Handlers::RequestRoleAssignment.new.call(command: cmd, request_context: earlier)
      id = pending.payload[:role_assignment_id]

      expect(decide(id, security[:session_id]).reason_code).to eq("role_assignment_not_pending")
      expect(assignment(id)["status"]).to eq("pending")
    end

    it "returns the stored result on exact replay, with no second approval or epoch advance" do
      security = seeded_security_operator
      pending = request_grant(account, role: "OrganizationAdmin", expires_at: fixed_now + (10 * 24 * 3600))
      id = pending.payload[:role_assignment_id]

      first = decide(id, security[:session_id], key: "same")
      replay = decide(id, security[:session_id], key: "same")

      expect(replay.replayed).to be(true)
      expect(replay.payload).to eq(first.payload)
      expect(DbInspector.count("role_assignment_approvals")).to eq(1)
      expect(epoch).to eq(8)
    end
  end

  # THE deferral this block exists to close.
  describe "invitation approval is production-reachable" do
    it "grants invitation.approve through Request + Decide only, then approves an Invitation with it" do
      # One seeded SecurityOperator stands in for the security-bootstrap service,
      # which :333 reserves for the FIRST SecurityOperator in an Organization.
      bootstrap_security = seeded_security_operator

      # 1-3: a real protected grant, approved by a distinct SecurityOperator.
      grantee = account("newsec")
      pending = request_grant(grantee, role: "SecurityOperator", expires_at: fixed_now + (10 * 24 * 3600))
      approved = decide(pending.payload[:role_assignment_id], bootstrap_security[:session_id])
      expect(approved).to be_success

      # 4: its allowlist carries invitation.approve, written by the approval.
      row = assignment(pending.payload[:role_assignment_id])
      expect(row["status"]).to eq("active")
      expect(JSON.parse(row["protected_permission_allowlist"])).to include("invitation.approve")

      # 5: a Session under the CURRENT epoch.
      grantee_session = session_for(grantee)

      # 6: DecideInvitation succeeds through CommandAuthorizer, with no fixture
      # ever writing an allowlist for this principal.
      invitation = TenantSeeder.create_invitation(organization_id: org, state: "pending_approval",
                                                  canonical_role: "OrganizationAdmin")
      DbInspector.connection.exec_params(<<~SQL, [invitation[:invitation_id], (fixed_now - 3600).iso8601(6)])
        UPDATE invitations SET requested_at = $2::timestamptz,
               approval_due_at = $2::timestamptz + interval '24 hours' WHERE id = $1::uuid
      SQL
      cmd = Workflows::Wf013::Commands::DecideInvitation.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "inv", schema_version: "1.0",
        session_id: grantee_session, invitation_id: invitation[:invitation_id],
        expected_state_version: 0, decision: "approve", reason: nil, requested_at_utc: fixed_now
      )
      result = Workflows::Wf013::Handlers::DecideInvitation.new.call(command: cmd, request_context: ctx)

      expect(result).to be_success
      expect(DbInspector.one("SELECT state FROM invitations WHERE id = $1::uuid",
                             [invitation[:invitation_id]])["state"]).to eq("active")
    end

    it "does not let a PENDING protected Assignment approve an Invitation" do
      grantee = account("pending-sec")
      request_grant(grantee, role: "SecurityOperator", expires_at: fixed_now + (10 * 24 * 3600))
      grantee_session = session_for(grantee)

      invitation = TenantSeeder.create_invitation(organization_id: org, state: "pending_approval",
                                                  canonical_role: "OrganizationAdmin")
      cmd = Workflows::Wf013::Commands::DecideInvitation.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "inv", schema_version: "1.0",
        session_id: grantee_session, invitation_id: invitation[:invitation_id],
        expected_state_version: 0, decision: "approve", reason: nil, requested_at_utc: fixed_now
      )
      result = Workflows::Wf013::Handlers::DecideInvitation.new.call(command: cmd, request_context: ctx)

      expect(result.reason_code).to eq("missing_authority")
      expect(DbInspector.one("SELECT state FROM invitations WHERE id = $1::uuid",
                             [invitation[:invitation_id]])["state"]).to eq("pending_approval")
    end
  end
end
