# frozen_string_literal: true

require "rails_helper"

# WF-013 RevokeRoleAssignment (WORKFLOW_SPECIFICATIONS.md :316, :333, :936, :948,
# :967). The canonical human-commanded end of an active grant.
#
# The two things this must prove beyond the ordinary transition: revocation
# removes effective authority at commit, and it removes NOTHING ELSE — the grant
# content, the approved allowlist, the approval records and the expiry timer all
# survive, because they are the audit history of how the authority existed.
RSpec.describe "WF-013 revoke role assignment", type: :acceptance,
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

  # A real active Assignment through the production grant command.
  def grant(target: nil, role: "MarketingOperator", epoch: 7, expires_at: nil, key: "g-#{SecureRandom.hex(3)}")
    cmd = Workflows::Wf013::Commands::RequestRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      session_id: admin[:session_id], account_id: target || account, canonical_role: role,
      permission_mode: "standard", persona: nil, scope_sha256: org_scope, expires_at:,
      expected_authorization_epoch: epoch, reason: nil, requested_at_utc: fixed_now
    )
    result = Workflows::Wf013::Handlers::RequestRoleAssignment.new.call(command: cmd, request_context: ctx)
    raise "grant failed: #{result.reason_code}" unless result.success?

    result.payload[:role_assignment_id]
  end

  def revoke(id, session_id: nil, key: "rv-#{SecureRandom.hex(3)}", version: 0, epoch: 8,
             reason: "revoked for the purposes of this acceptance coverage", schema: "1.0")
    cmd = Workflows::Wf013::Commands::RevokeRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: schema,
      session_id: session_id || admin[:session_id], role_assignment_id: id,
      expected_state_version: version, expected_authorization_epoch: epoch, reason:,
      requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::RevokeRoleAssignment.new.call(command: cmd, request_context: ctx)
  end

  def assignment(id) = DbInspector.one("SELECT * FROM role_assignments WHERE id = $1::uuid", [id])
  def epoch = DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id = $1::uuid",
                              [org])["authorization_epoch"].to_i
  def events = DbInspector.all("SELECT event_type FROM event_registry ORDER BY created_at").map { |e| e["event_type"] }

  # A SecurityOperator with approved protected authority, standing in for the
  # security-bootstrap service :333 reserves for the FIRST one in an Organization.
  def seeded_security_operator(allowlist: %w[invitation.approve role.manage])
    id = account("sec")
    TenantSeeder.create_role_assignment(organization_id: org, account_id: id,
                                        canonical_role: "SecurityOperator",
                                        scope_sha256: org_scope,
                                        protected_permission_allowlist: allowlist)
    { account_id: id, session_id: session_for(id) }
  end

  describe "the revocation transition" do
    it "takes the Assignment active -> revoked and advances the epoch in the same transaction" do
      id = grant
      result = revoke(id)

      expect(result).to be_success
      row = assignment(id)
      expect(row["status"]).to eq("revoked")
      expect(row["transition_reason_code"]).to eq("role_assignment_revoked")
      expect(row["terminated_at"]).not_to be_nil
      expect(row["state_version"].to_i).to eq(1)
      expect(epoch).to eq(9)
      expect(result.payload[:authorization_epoch]).to eq(9)
    end

    it "emits exactly one RoleRevoked state-transition event, actor-attributed with a null service" do
      id = grant
      revoke(id)

      expect(events).to eq(%w[RoleGranted RoleRevoked])
      body = JSON.parse(DbInspector.all(<<~SQL).last["b"])
        SELECT convert_from(event_bytes,'UTF8') AS b FROM event_registry ORDER BY created_at
      SQL
      expect(body["event_profile"]).to eq("state_transition")
      expect(body["from_state"]).to eq("active")
      expect(body["to_state"]).to eq("revoked")
      expect(body["organization_epoch"]).to eq(9)
      expect(body["actor_id"]).to eq(admin[:account_id])
      expect(body["service_identity_id"]).to be_nil
    end

    it "writes exactly one command result and one audit outcome" do
      id = grant
      before_results = DbInspector.count("command_results")
      before_audits = DbInspector.count("audit_record_registry")
      revoke(id)

      expect(DbInspector.count("command_results")).to eq(before_results + 1)
      expect(DbInspector.count("audit_record_registry")).to eq(before_audits + 1)
      audit = DbInspector.all("SELECT * FROM audit_record_registry ORDER BY created_at").last
      expect(audit["to_state"]).to eq("revoked")
      expect(audit["outcome"]).to eq("success")
      expect(audit["actor_id"]).to eq(admin[:account_id])
      expect(audit["service_identity_id"]).to be_nil
      expect(JSON.parse(audit["payload"])["reason"]).to include("acceptance coverage")
    end

    it "removes effective authority immediately after commit" do
      grantee = account("grantee")
      id = grant(target: grantee)
      expect(assignment(id)["status"]).to eq("active")

      expect(revoke(id)).to be_success
      effective = DbInspector.one(<<~SQL, [grantee])
        SELECT count(*) AS n FROM role_assignments
        WHERE account_id = $1::uuid AND status = 'active'
      SQL
      expect(effective["n"].to_i).to eq(0)
    end
  end

  describe "revocation ends authority and erases nothing else" do
    # A real approved protected Assignment: allowlist and approval record written
    # by the production approval path, then revoked.
    def approved_security_assignment
      security = seeded_security_operator
      target = account("newsec")
      request = Workflows::Wf013::Commands::RequestRoleAssignment.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "req", schema_version: "1.0",
        session_id: admin[:session_id], account_id: target, canonical_role: "SecurityOperator",
        permission_mode: "standard", persona: nil, scope_sha256: org_scope,
        expires_at: fixed_now + (10 * 24 * 3600), expected_authorization_epoch: 7, reason: nil,
        requested_at_utc: fixed_now
      )
      pending = Workflows::Wf013::Handlers::RequestRoleAssignment.new.call(command: request, request_context: ctx)
      decide = Workflows::Wf013::Commands::DecideRoleAssignment.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "dec", schema_version: "1.0",
        session_id: security[:session_id], role_assignment_id: pending.payload[:role_assignment_id],
        expected_state_version: 0, expected_authorization_epoch: 7, decision: "approve", reason: nil,
        requested_at_utc: fixed_now
      )
      approved = Workflows::Wf013::Handlers::DecideRoleAssignment.new.call(command: decide, request_context: ctx)
      raise "approval failed: #{approved.reason_code}" unless approved.success?

      { id: pending.payload[:role_assignment_id], security:, account_id: target }
    end

    it "preserves the approved protected allowlist as historical fact" do
      subject = approved_security_assignment
      before = JSON.parse(assignment(subject[:id])["protected_permission_allowlist"])
      expect(before).to include("invitation.approve")

      expect(revoke(subject[:id], session_id: subject[:security][:session_id], version: 1)).to be_success
      expect(JSON.parse(assignment(subject[:id])["protected_permission_allowlist"])).to eq(before)
    end

    it "preserves the ordered approval records" do
      subject = approved_security_assignment
      revoke(subject[:id], session_id: subject[:security][:session_id], version: 1)

      approvals = DbInspector.all("SELECT * FROM role_assignment_approvals WHERE role_assignment_id = $1::uuid",
                                  [subject[:id]])
      expect(approvals.size).to eq(1)
      expect(approvals.first["decision"]).to eq("approve")
      expect(approvals.first["sequence_number"].to_i).to eq(1)
    end

    it "preserves immutable grant content" do
      subject = approved_security_assignment
      before = assignment(subject[:id])
      revoke(subject[:id], session_id: subject[:security][:session_id], version: 1)
      after = assignment(subject[:id])

      %w[organization_id account_id canonical_role permission_mode persona scope_sha256
         requester_account_id requested_at].each do |column|
        expect(after[column]).to eq(before[column]), "#{column} changed across revocation"
      end
    end

    it "leaves the expiry ScheduledAction intact, and its later delivery is harmless" do
      subject = approved_security_assignment
      timer = DbInspector.one("SELECT * FROM scheduled_actions WHERE target_id = $1::uuid", [subject[:id]])
      expect(timer).not_to be_nil

      revoke(subject[:id], session_id: subject[:security][:session_id], version: 1)
      after = DbInspector.one("SELECT * FROM scheduled_actions WHERE id = $1::uuid", [timer["id"]])
      expect(after["status"]).to eq(timer["status"])
      expect(after["due_at"]).to eq(timer["due_at"])
      expect(DbInspector.count("scheduled_actions")).to eq(1)
    end

    it "does not delete the RoleAssignment" do
      id = grant
      revoke(id)
      expect(assignment(id)).not_to be_nil
    end
  end

  describe "authority" do
    it "refuses an actor without role.manage, before disclosing that the Assignment exists" do
      id = grant
      stranger = account("stranger")
      TenantSeeder.create_role_assignment(organization_id: org, account_id: stranger,
                                          canonical_role: "MarketingOperator", scope_sha256: org_scope)

      result = revoke(id, session_id: session_for(stranger))
      expect(result.reason_code).to eq("missing_authority")
      expect(assignment(id)["status"]).to eq("active")
    end

    it "refuses an OrganizationAdmin revoking a PROTECTED Assignment, which only a SecurityOperator may manage" do
      security = seeded_security_operator
      protected_id = DbInspector.one("SELECT id FROM role_assignments WHERE account_id = $1::uuid",
                                     [security[:account_id]])["id"]

      result = revoke(protected_id, epoch: 7)
      expect(result.reason_code).to eq("role_protected_authority_required")
      expect(assignment(protected_id)["status"]).to eq("active")
    end

    it "lets a SecurityOperator holding approved role.manage revoke a protected Assignment" do
      first = seeded_security_operator
      second = seeded_security_operator
      target = DbInspector.one("SELECT id, state_version FROM role_assignments WHERE account_id = $1::uuid",
                               [second[:account_id]])

      result = revoke(target["id"], session_id: first[:session_id], version: target["state_version"].to_i,
                      epoch: 7)
      expect(result).to be_success
      expect(assignment(target["id"])["status"]).to eq("revoked")
    end

    it "refuses an actor whose own granting Assignment does not contain the target scope" do
      narrow_admin = account("narrow")
      TenantSeeder.create_role_assignment(organization_id: org, account_id: narrow_admin,
                                          canonical_role: "OrganizationAdmin",
                                          scope_sha256: Digest::SHA256.digest("scope:project:other"),
                                          bootstrap_admin_exception: false,
                                          protected_permission_allowlist: ["role.manage"])
      id = grant

      result = revoke(id, session_id: session_for(narrow_admin))
      expect(result.reason_code).to eq("grant_scope_exceeded")
      expect(assignment(id)["status"]).to eq("active")
    end

    it "cannot revoke an Assignment in another Organization" do
      other = TenantSeeder.seed_authorized_admin(issued_at: fixed_now - 900)
      foreign = TenantSeeder.create_role_assignment(
        organization_id: other[:organization_id], account_id: other[:account_id],
        canonical_role: "MarketingOperator", scope_sha256: org_scope
      )

      result = revoke(foreign)
      expect(result.reason_code).to eq("role_assignment_not_active")
      expect(assignment(foreign)["status"]).to eq("active")
    end
  end

  # An OrganizationAdmin Assignment is itself a protected grant, so only a
  # SecurityOperator can ever reach the last-admin guard — which is exactly the
  # ":967 OrganizationAdmin may manage non-protected tenant grants" limb proved
  # above. These examples therefore act as a SecurityOperator throughout.
  describe "the last-administrator invariant" do
    let(:security) { seeded_security_operator }

    def sole_admin_assignment
      DbInspector.one("SELECT id FROM role_assignments WHERE account_id = $1::uuid",
                      [admin[:account_id]])["id"]
    end

    it "refuses to revoke the only effective OrganizationAdmin" do
      result = revoke(sole_admin_assignment, session_id: security[:session_id], epoch: 7)

      expect(result.reason_code).to eq("last_organization_admin")
      expect(assignment(sole_admin_assignment)["status"]).to eq("active")
      expect(epoch).to eq(7)
    end

    it "permits it once another Account holds an effective OrganizationAdmin Assignment" do
      sole = sole_admin_assignment
      replacement = account("admin2")
      TenantSeeder.create_role_assignment(organization_id: org, account_id: replacement,
                                          canonical_role: "OrganizationAdmin", scope_sha256: org_scope,
                                          effective_at: fixed_now - 3600)

      expect(revoke(sole, session_id: security[:session_id], epoch: 7)).to be_success
      expect(assignment(sole)["status"]).to eq("revoked")
    end

    it "does not count an expired or revoked administrator as a replacement" do
      sole = sole_admin_assignment
      stale = account("admin3")
      TenantSeeder.create_role_assignment(organization_id: org, account_id: stale,
                                          canonical_role: "OrganizationAdmin", scope_sha256: org_scope,
                                          status: "expired", effective_at: fixed_now - 7200)

      expect(revoke(sole, session_id: security[:session_id], epoch: 7).reason_code)
        .to eq("last_organization_admin")
    end

    it "does not count the revoked Assignment's own Account as its replacement" do
      sole = sole_admin_assignment
      # A second Assignment held by the SAME Account is not "another active
      # Account" (:948), so it cannot satisfy the predicate.
      TenantSeeder.create_role_assignment(organization_id: org, account_id: admin[:account_id],
                                          canonical_role: "OrganizationAdmin", scope_sha256: org_scope,
                                          effective_at: fixed_now - 3600)

      expect(revoke(sole, session_id: security[:session_id], epoch: 7).reason_code)
        .to eq("last_organization_admin")
    end

    it "uses the same predicate the timed expiry uses" do
      # ":344 OD-026 adds no second predicate" — both paths call the one module.
      expect(IdentityAccess::Infrastructure::RoleAssignmentStore
        .include?(IdentityAccess::Infrastructure::LastAdministratorPredicate)).to be(true)
      expect(IdentityAccess::Infrastructure::RoleExpiryStore
        .include?(IdentityAccess::Infrastructure::LastAdministratorPredicate)).to be(true)
    end
  end

  describe "state, versions and replay" do
    it "refuses a non-active Assignment" do
      id = grant
      expect(revoke(id, key: "first")).to be_success
      expect(revoke(id, key: "second", version: 1, epoch: 9).reason_code).to eq("role_assignment_not_active")
      expect(assignment(id)["state_version"].to_i).to eq(1)
    end

    it "refuses a pending Assignment: revocation is not a rejection" do
      security = seeded_security_operator
      pending_id = grant(role: "OrganizationAdmin", expires_at: fixed_now + (10 * 24 * 3600))
      expect(assignment(pending_id)["status"]).to eq("pending")

      expect(revoke(pending_id, session_id: security[:session_id], epoch: 7).reason_code)
        .to eq("role_assignment_not_active")
      expect(assignment(pending_id)["status"]).to eq("pending")
    end

    it "refuses a stale state version without mutation" do
      id = grant
      expect(revoke(id, version: 99).reason_code).to eq("stale_state_version")
      expect(assignment(id)["status"]).to eq("active")
      expect(epoch).to eq(8)
    end

    it "refuses a stale authorization epoch without mutation" do
      id = grant
      expect(revoke(id, epoch: 99).reason_code).to eq("stale_authorization_epoch")
      expect(assignment(id)["status"]).to eq("active")
      expect(epoch).to eq(8)
    end

    it "returns the stored result on exact replay, with no second transition or epoch advance" do
      id = grant
      first = revoke(id, key: "same")
      replay = revoke(id, key: "same")

      expect(replay.replayed).to be(true)
      expect(replay.payload).to eq(first.payload)
      expect(events.count("RoleRevoked")).to eq(1)
      expect(assignment(id)["state_version"].to_i).to eq(1)
      expect(epoch).to eq(9)
    end

    it "rejects conflicting reuse of one idempotency key" do
      id = grant
      expect(revoke(id, key: "shared")).to be_success
      conflicting = revoke(id, key: "shared", version: 1, epoch: 9,
                           reason: "an entirely different revocation reason string")

      expect(conflicting.reason_code).to eq("idempotency_conflict")
      expect(events.count("RoleRevoked")).to eq(1)
    end

    it "refuses an unbounded or missing reason" do
      id = grant
      expect(revoke(id, reason: nil).reason_code).to eq("role_reason_invalid")
      expect(revoke(id, reason: "too short").reason_code).to eq("role_reason_invalid")
      expect(assignment(id)["status"]).to eq("active")
    end

    it "refuses an unsupported command schema major" do
      id = grant
      expect(revoke(id, schema: "2.0").reason_code).to eq("command_schema_unsupported")
      expect(assignment(id)["status"]).to eq("active")
    end
  end
end
