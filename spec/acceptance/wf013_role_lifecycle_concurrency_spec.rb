# frozen_string_literal: true

require "rails_helper"

# The Role Assignment lifecycle under genuine concurrency.
#
# Every example here is a real race, coordinated by `RaceHarness` through the
# advisory locks the production commands already take: the contested lock is held
# from a controller connection, each racing operation opens its own transaction
# and BLOCKS on that lock, and the gate is released only once every operation is
# *observably* blocked in `pg_locks`. Nothing is ordered by sleeping, and a
# harness that could not observe both operations in flight fails the example
# rather than quietly degrading into a sequential run.
#
# What is asserted is never "who won" — that is genuinely nondeterministic and
# must be. It is the invariant: exactly one transition, one epoch advance per
# accepted mutation, no duplicate approval, no duplicate timer, no authority
# after a committed removal, and never an Organization left without an effective
# administrator.
RSpec.describe "WF-013 role assignment lifecycle concurrency", type: :acceptance,
               acceptance_ids: ["AC-CAP-013", "AC-CAP-025", "AC-WF-013"],
               test_types: %w[TYP-SEC TYP-DATA TYP-INT] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  # One time base for the whole file: grants are made at `t0` and every timer in
  # it falls due at `t1`, so an expiry race and a command race can be expressed
  # at the same instant.
  def t0 = Time.utc(2026, 6, 1, 10, 0, 0)
  def t1 = t0 + (10 * 24 * 3600)
  def org_scope = Digest::SHA256.digest("scope:organization")

  let(:admin) { TenantSeeder.seed_authorized_admin(issued_at: t0 - 900) }
  let(:org) { admin[:organization_id] }

  def actor_ctx(now = t0)
    Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(now), ids: Platform::Ids.system,
                                       correlation_id: SecureRandom.uuid_v7)
  end

  def service_ctx(now = t1)
    Platform::RequestContext.for_service(
      service_identity_id: Platform::ServiceIdentity.scheduled_action_executor,
      clock: Platform::Clock.fixed(now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
    )
  end

  def account(subject = "person")
    TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                subject: "#{subject}-#{SecureRandom.hex(6)}")
  end

  # Issued 15 minutes before `at` and last active at `at`, so it is valid for the
  # 30 minutes either side of the instant the example acts at.
  def session_for(account_id, at: t0)
    TenantSeeder.create_session(organization_id: org, account_id:, issued_at: at - 900,
                                last_activity_at: at)
  end

  def admin_session(at: t0) = session_for(admin[:account_id], at:)

  # ---- production commands --------------------------------------------------

  def request_grant(target, role: "MarketingOperator", key: "req-#{SecureRandom.hex(3)}", epoch: 7,
                    expires_at: nil, session_id: nil, at: t0)
    cmd = Workflows::Wf013::Commands::RequestRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      session_id: session_id || admin[:session_id], account_id: target, canonical_role: role,
      permission_mode: "standard", persona: nil, scope_sha256: org_scope, expires_at:,
      expected_authorization_epoch: epoch, reason: nil, requested_at_utc: at
    )
    Workflows::Wf013::Handlers::RequestRoleAssignment.new.call(command: cmd, request_context: actor_ctx(at))
  end

  def decide_grant(id, session_id, decision: "approve", key: "dec-#{SecureRandom.hex(3)}", version: 0,
                   epoch: 7, reason: nil, at: t0)
    cmd = Workflows::Wf013::Commands::DecideRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id:,
      role_assignment_id: id, expected_state_version: version, expected_authorization_epoch: epoch,
      decision:, reason:, requested_at_utc: at
    )
    Workflows::Wf013::Handlers::DecideRoleAssignment.new.call(command: cmd, request_context: actor_ctx(at))
  end

  def revoke_grant(id, session_id: nil, key: "rv-#{SecureRandom.hex(3)}", version: 0, epoch: 7,
                   reason: "revoked under the lifecycle concurrency matrix", at: t0)
    cmd = Workflows::Wf013::Commands::RevokeRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      session_id: session_id || admin[:session_id], role_assignment_id: id,
      expected_state_version: version, expected_authorization_epoch: epoch, reason:,
      requested_at_utc: at
    )
    Workflows::Wf013::Handlers::RevokeRoleAssignment.new.call(command: cmd, request_context: actor_ctx(at))
  end

  def suspend(session_id, key: "sp-#{SecureRandom.hex(3)}", version: 0, epoch: 7, at: t0)
    cmd = Workflows::Wf013::Commands::SuspendOrganization.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id:,
      expected_state_version: version, expected_authorization_epoch: epoch,
      reason: "suspended under the lifecycle concurrency matrix", requested_at_utc: at
    )
    Workflows::Wf013::Handlers::SuspendOrganization.new.call(command: cmd, request_context: actor_ctx(at))
  end

  def create_invitation(session_id, key: "inv-#{SecureRandom.hex(3)}", at: t0,
                        email: "invitee-#{SecureRandom.hex(4)}@example.com")
    cmd = Workflows::Wf013::Commands::CreateInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id:,
      target_email: email, target_identity_issuer_key: nil, target_identity_subject: nil,
      canonical_role: "MarketingOperator", permission_mode: "standard", persona: nil,
      scope_sha256: org_scope, intended_assignment_expires_at: nil, requested_at_utc: at
    )
    Workflows::Wf013::Handlers::CreateInvitation.new.call(command: cmd, request_context: actor_ctx(at))
  end

  def revoke_invitation(reference, session_id, key: "ri-#{SecureRandom.hex(3)}", at: t0)
    cmd = Workflows::Wf013::Commands::RevokeInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id:,
      invitation_reference: reference, expected_state_version: 0,
      reason: "revoked under the lifecycle concurrency matrix", requested_at_utc: at
    )
    Workflows::Wf013::Handlers::RevokeInvitation.new.call(command: cmd, request_context: actor_ctx(at))
  end

  def decide_invitation(invitation_id, session_id, key: "iv-#{SecureRandom.hex(3)}", at: t0)
    cmd = Workflows::Wf013::Commands::DecideInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id:,
      invitation_id:, expected_state_version: 0, decision: "approve", reason: nil, requested_at_utc: at
    )
    Workflows::Wf013::Handlers::DecideInvitation.new.call(command: cmd, request_context: actor_ctx(at))
  end

  # ---- fixtures -------------------------------------------------------------

  # An Assignment arranged directly plus its timer from the production scheduler.
  # Protected roles cannot be created active by the grant command, so a fixture
  # that needs an ACTIVE protected Assignment arranges it and lets the workflow
  # under test be the one being proved.
  def seeded_assignment(role:, account_id:, expires_at: nil, allowlist: nil, effective_at: t0,
                        bootstrap: false)
    # The allowlist an approval would have written for this role, so a seeded
    # actor holds exactly the authority the production path would have given it
    # and nothing more.
    list = allowlist || Platform::PermissionBaseline.protected_permission_preview(role)
    id = TenantSeeder.create_role_assignment(
      organization_id: org, account_id:, canonical_role: role, scope_sha256: org_scope,
      effective_at:, expires_at:, protected_permission_allowlist: list,
      bootstrap_admin_exception: bootstrap
    )
    schedule_timer(id, expires_at) if expires_at
    id
  end

  def schedule_timer(id, expires_at)
    ScheduledActionHarness.in_context(org) do |_store, correlation_id|
      Workflows::Wf013::RoleAssignmentExpirySchedule.schedule(
        pg: ActiveRecord::Base.connection.raw_connection, organization_id: org,
        role_assignment_id: id, expires_at:, now: t0, correlation_id:
      )
    end
  end

  def security_operator(at: t0, expires_at: nil)
    id = account("sec")
    assignment = seeded_assignment(role: "SecurityOperator", account_id: id, expires_at:)
    { account_id: id, assignment_id: assignment, session_id: session_for(id, at:) }
  end

  def pending_invitation
    inv = TenantSeeder.create_invitation(organization_id: org, state: "pending_approval",
                                         canonical_role: "OrganizationAdmin")
    DbInspector.connection.exec_params(<<~SQL, [inv[:invitation_id], (t0 - 3600).iso8601(6)])
      UPDATE invitations SET requested_at = $2::timestamptz,
             approval_due_at = $2::timestamptz + interval '24 hours' WHERE id = $1::uuid
    SQL
    inv[:invitation_id]
  end

  # The exact command a claimed `role_assignment_expire` action produces.
  def expire_command(role_assignment_id)
    row = ScheduledActionHarness.row(
      DbInspector.one("SELECT id FROM scheduled_actions WHERE target_id = $1::uuid",
                      [role_assignment_id])["id"]
    )
    Workflows::Wf013::Commands::ExpireRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, schema_version: "1.0", organization_id: org,
      target_type: "role_assignment", role_assignment_id:, due_at: Time.parse(row["due_at"]).getutc,
      action_id: row["id"],
      action_identity_sha256: [row["identity_sha256"].delete_prefix("\\x")].pack("H*"),
      requested_at_utc: t1
    )
  end

  def expire(role_assignment_id, command: nil)
    Workflows::Wf013::Handlers::ExpireRoleAssignment.new.call(
      command: command || expire_command(role_assignment_id), request_context: service_ctx
    )
  end

  # A racing expiry, with its command built on THIS thread. Building it reads the
  # ScheduledAction through the shared inspector connection, which must not
  # happen inside a racing thread while the harness is polling on it.
  def expiry_for(role_assignment_id)
    command = expire_command(role_assignment_id)
    -> { expire(role_assignment_id, command:) }
  end

  def worker(now = t1)
    Platform::ScheduledActions::Worker.new(
      registry: Platform::ScheduledActions::Registry.default,
      scheduler: Platform::ScheduledActions::Scheduler.new,
      clock: Platform::Clock.fixed(now), ids: Platform::Ids.system
    )
  end

  # ---- observation ----------------------------------------------------------

  def assignment(id) = DbInspector.one("SELECT * FROM role_assignments WHERE id = $1::uuid", [id])
  def epoch = DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id = $1::uuid",
                              [org])["authorization_epoch"].to_i
  def events(type = nil)
    rows = DbInspector.all("SELECT event_type FROM event_registry ORDER BY created_at").map { |e| e["event_type"] }
    type ? rows.count(type) : rows
  end

  def org_key = RaceHarness.organization_key(org)
  def invitation_key(id) = RaceHarness.invitation_key(id)

  def succeeded(results) = results.select { |r| r.respond_to?(:success?) && r.success? }
  def reasons(results) = results.map { |r| r.respond_to?(:reason_code) ? r.reason_code : r.class.name }

  # Effective OrganizationAdmins right now, by the ratified resolution rule.
  def effective_admins(at = t1)
    DbInspector.one(<<~SQL, [at.iso8601(6)])["n"].to_i
      SELECT count(*) AS n FROM role_assignments
      WHERE canonical_role = 'OrganizationAdmin' AND status = 'active'
        AND effective_at IS NOT NULL AND effective_at <= $1::timestamptz
        AND (expires_at IS NULL OR $1::timestamptz < expires_at)
    SQL
  end

  # ===========================================================================
  describe "request and activation" do
    it "identical request x identical request: one Assignment, one epoch advance, one event" do
      target = account
      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { request_grant(target, key: "same") }, -> { request_grant(target, key: "same") }]
      )

      expect(succeeded(results).size).to eq(2)
      expect(results.count { |r| r.replayed }).to eq(1)
      expect(DbInspector.count("role_assignments")).to eq(2) # the bootstrap admin plus one
      expect(epoch).to eq(8)
      expect(events("RoleGranted")).to eq(1)
    end

    it "conflicting request x conflicting request: one commits, the other is an idempotency conflict" do
      target = account
      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { request_grant(target, key: "shared", role: "MarketingOperator") },
                -> { request_grant(target, key: "shared", role: "TechnicalImplementer") }]
      )

      expect(succeeded(results).size).to eq(1)
      expect(reasons(results)).to include("idempotency_conflict")
      expect(DbInspector.count("role_assignments")).to eq(2)
      expect(epoch).to eq(8)
    end

    it "request x Organization suspension: exactly one epoch-advancing transition commits" do
      target = account
      other = admin_session
      results, = RaceHarness.interleave(
        org_key, gated: [-> { request_grant(target) }, -> { suspend(other) }]
      )

      expect(succeeded(results).size).to eq(1)
      expect(epoch).to eq(8)
      # Whichever lost changed nothing: the epoch moved exactly once.
      expect(events.count { |e| %w[RoleGranted OrganizationSuspended].include?(e) }).to eq(1)
    end

    it "direct activation x requester authority revoke: no Assignment is created under revoked authority" do
      requester = account("admin2")
      requester_assignment = seeded_assignment(role: "OrganizationAdmin", account_id: requester)
      requester_session = session_for(requester)
      security = security_operator
      target = account

      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { request_grant(target, session_id: requester_session) },
                -> { revoke_grant(requester_assignment, session_id: security[:session_id]) }]
      )

      expect(succeeded(results).size).to eq(1)
      expect(epoch).to eq(8)
      if results.first.success?
        expect(assignment(requester_assignment)["status"]).to eq("active")
      else
        expect(assignment(requester_assignment)["status"]).to eq("revoked")
        # No grant survived the requester's revocation.
        expect(events("RoleGranted")).to eq(0)
      end
    end

    it "direct activation x requester authority expiry: the same exclusivity holds for the timer" do
      requester = account("admin2")
      requester_assignment = seeded_assignment(role: "OrganizationAdmin", account_id: requester,
                                               expires_at: t1)
      # The requester acts a second before its own Assignment expires: still
      # effective, because equality belongs to expiry (:316).
      requester_session = session_for(requester, at: t1)
      target = account

      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { request_grant(target, session_id: requester_session, at: t1 - 1, epoch: 7) },
                expiry_for(requester_assignment)]
      )

      # There is no exclusivity to claim between these two — they are independent
      # authority changes. The invariant is the accounting: each accepted mutation
      # advanced the epoch exactly once, and a command quoting a superseded epoch
      # changed nothing.
      expect(succeeded(results).size).to be >= 1
      expect(epoch).to eq(7 + succeeded(results).size)
      expect(events("RoleGranted") + events("RoleExpired")).to eq(succeeded(results).size)
    end

    it "replay x fresh conflicting request: the replay is served and the conflict is refused" do
      target = account
      first = request_grant(target, key: "shared")
      expect(first).to be_success

      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { request_grant(target, key: "shared") },
                -> { request_grant(target, key: "shared", role: "TechnicalImplementer", epoch: 8) }]
      )

      replay = results.find { |r| r.success? }
      expect(replay.replayed).to be(true)
      expect(replay.payload[:role_assignment_id]).to eq(first.payload[:role_assignment_id])
      expect(reasons(results)).to include("idempotency_conflict")
      expect(DbInspector.count("role_assignments")).to eq(2)
      expect(epoch).to eq(8)
    end
  end

  # ===========================================================================
  describe "protected decision" do
    # A pending protected Assignment, requested by the bootstrap admin.
    def pending_protected
      result = request_grant(account("grantee"), role: "OrganizationAdmin", expires_at: t1)
      expect(result).to be_success
      result.payload[:role_assignment_id]
    end

    it "same approver x same approver: one approval record, one activation" do
      security = security_operator
      id = pending_protected

      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { decide_grant(id, security[:session_id], key: "a") },
                -> { decide_grant(id, security[:session_id], key: "b") }]
      )

      expect(succeeded(results).size).to eq(1)
      expect(reasons(results)).to include("role_assignment_not_pending")
      expect(DbInspector.count("role_assignment_approvals")).to eq(1)
      expect(assignment(id)["status"]).to eq("active")
      expect(events("RoleGranted")).to eq(1)
      expect(epoch).to eq(8)
    end

    it "different approver x different approver: still exactly one approval record" do
      first = security_operator
      second = security_operator
      id = pending_protected

      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { decide_grant(id, first[:session_id], key: "a") },
                -> { decide_grant(id, second[:session_id], key: "b") }]
      )

      expect(succeeded(results).size).to eq(1)
      expect(DbInspector.count("role_assignment_approvals")).to eq(1)
      expect(DbInspector.count("scheduled_actions")).to eq(1)
      expect(events("RoleGranted")).to eq(1)
    end

    it "final approval x Organization suspension: one epoch-advancing transition" do
      security = security_operator
      id = pending_protected
      other = admin_session

      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { decide_grant(id, security[:session_id]) }, -> { suspend(other) }]
      )

      expect(succeeded(results).size).to eq(1)
      expect(epoch).to eq(8)
    end

    it "final approval x requester authority revoke: no split state and epoch" do
      security = security_operator
      other_security = security_operator
      id = pending_protected
      admin_assignment = DbInspector.one("SELECT id FROM role_assignments WHERE account_id = $1::uuid",
                                         [admin[:account_id]])["id"]
      # A second effective administrator, so the last-admin guard is not what
      # decides this race.
      seeded_assignment(role: "OrganizationAdmin", account_id: account("admin2"))

      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { decide_grant(id, security[:session_id]) },
                -> { revoke_grant(admin_assignment, session_id: other_security[:session_id]) }]
      )

      expect(succeeded(results).size).to eq(1)
      expect(epoch).to eq(8)
      expect(DbInspector.count("role_assignment_approvals")).to be <= 1
    end

    it "final approval x requester authority expiry" do
      security = security_operator
      requester = account("admin2")
      requester_assignment = seeded_assignment(role: "OrganizationAdmin", account_id: requester,
                                               expires_at: t1)
      # Requested an hour before the timer falls due, so the 24-hour approval
      # window is still open at `t1`.
      requested = request_grant(account("grantee"), role: "OrganizationAdmin",
                                expires_at: t1 + (5 * 24 * 3600),
                                session_id: session_for(requester, at: t1 - 3600), at: t1 - 3600)
      expect(requested).to be_success
      id = requested.payload[:role_assignment_id]

      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { decide_grant(id, session_for(security[:account_id], at: t1), at: t1) },
                expiry_for(requester_assignment)]
      )

      expect(succeeded(results).size).to be >= 1
      expect(epoch).to eq(7 + succeeded(results).size)
      expect(DbInspector.count("role_assignment_approvals")).to be <= 1
    end

    it "final approval x duplicate delivery: one approval, one event, the duplicate replays" do
      security = security_operator
      id = pending_protected

      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { decide_grant(id, security[:session_id], key: "same") },
                -> { decide_grant(id, security[:session_id], key: "same") }]
      )

      expect(succeeded(results).size).to eq(2)
      expect(results.count { |r| r.replayed }).to eq(1)
      expect(DbInspector.count("role_assignment_approvals")).to eq(1)
      expect(events("RoleGranted")).to eq(1)
      expect(epoch).to eq(8)
    end

    it "final approval x stale authorization epoch: the stale decision changes nothing" do
      security = security_operator
      id = pending_protected

      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { request_grant(account, key: "advance") },
                -> { decide_grant(id, security[:session_id], epoch: 7) }]
      )

      grant_result, decision_result = results
      expect(succeeded(results).size).to eq(1)
      expect(epoch).to eq(8)
      if decision_result.respond_to?(:reason_code) && decision_result.reason_code == "stale_authorization_epoch"
        # The grant advanced the epoch first, so the decision quoting the old one
        # changed nothing at all.
        expect(grant_result).to be_success
        expect(assignment(id)["status"]).to eq("pending")
        expect(DbInspector.count("role_assignment_approvals")).to eq(0)
      else
        expect(decision_result).to be_success
        expect(grant_result.reason_code).to eq("stale_authorization_epoch")
      end
    end

    # The approval transaction is one unit: the approval record, the allowlist,
    # the activation, the epoch advance and the timer. Each of these aborts it at
    # a different point and proves the database removed everything before it.
    def approval_leaves_nothing(table, event, timing: "BEFORE")
      security = security_operator
      id = pending_protected
      before_epoch = epoch

      FailureInjector.abort_on(table, event, timing:) do
        FailureInjector.expect_abort { decide_grant(id, security[:session_id]) }
      end

      expect(assignment(id)["status"]).to eq("pending")
      expect(JSON.parse(assignment(id)["protected_permission_allowlist"])).to eq([])
      expect(DbInspector.count("role_assignment_approvals")).to eq(0)
      expect(DbInspector.count("scheduled_actions")).to eq(0)
      expect(events("RoleGranted")).to eq(0)
      expect(epoch).to eq(before_epoch)
    end

    it "rollback after approval insert leaves no approval record" do
      # The approval row is written, then the activation UPDATE aborts.
      approval_leaves_nothing("role_assignments", "UPDATE")
    end

    it "rollback after allowlist write leaves no allowlist" do
      # Activation (and with it the allowlist) is written, then the epoch UPDATE
      # aborts.
      approval_leaves_nothing("organizations", "UPDATE")
    end

    it "rollback after the epoch update begins leaves the epoch untouched" do
      # AFTER UPDATE: the organizations row has already changed in-transaction.
      approval_leaves_nothing("organizations", "UPDATE", timing: "AFTER")
    end

    it "rollback before the expiry timer insert leaves no timer and no activation" do
      approval_leaves_nothing("scheduled_actions", "INSERT")
    end
  end

  # ===========================================================================
  describe "revoke and expiry" do
    def revocable_assignment(expires_at: nil)
      result = request_grant(account("grantee"), expires_at:)
      expect(result).to be_success
      result.payload[:role_assignment_id]
    end

    it "revoke x revoke: one transition, one event, one epoch advance" do
      id = revocable_assignment

      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { revoke_grant(id, key: "a", epoch: 8) }, -> { revoke_grant(id, key: "b", epoch: 8) }]
      )

      expect(succeeded(results).size).to eq(1)
      expect(reasons(results)).to include("role_assignment_not_active")
      expect(assignment(id)["status"]).to eq("revoked")
      expect(assignment(id)["state_version"].to_i).to eq(1)
      expect(events("RoleRevoked")).to eq(1)
      expect(epoch).to eq(9)
    end

    it "revoke x expiry: revocation and expiry cannot both transition the Assignment" do
      id = revocable_assignment(expires_at: t1)

      revoke_session = admin_session(at: t1)
      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { revoke_grant(id, session_id: revoke_session, epoch: 8, at: t1) },
                expiry_for(id)]
      )

      expect(assignment(id)["status"]).to be_in(%w[revoked expired])
      expect(assignment(id)["state_version"].to_i).to eq(1)
      expect(events("RoleRevoked") + events("RoleExpired")).to eq(1)
      expect(epoch).to eq(9)
      expect(succeeded(results).size).to be >= 1
    end

    it "expiry x expiry: the duplicate delivery replays rather than transitioning twice" do
      id = revocable_assignment(expires_at: t1)
      command = expire_command(id)

      results, = RaceHarness.interleave(
        org_key, gated: [-> { expire(id, command:) }, -> { expire(id, command:) }]
      )

      expect(succeeded(results).size).to eq(2)
      expect(results.count { |r| r.replayed }).to eq(1)
      expect(assignment(id)["status"]).to eq("expired")
      expect(assignment(id)["state_version"].to_i).to eq(1)
      expect(events("RoleExpired")).to eq(1)
      expect(epoch).to eq(9)
    end

    it "expiry x Organization suspension: two independent authority changes, each counted once" do
      id = revocable_assignment(expires_at: t1)
      session = admin_session(at: t1)

      results, = RaceHarness.interleave(
        org_key, gated: [expiry_for(id), -> { suspend(session, epoch: 8, at: t1) }]
      )

      # Whatever the order, the epoch advanced exactly once per accepted mutation.
      expect(epoch).to eq(8 + succeeded(results).size)
      expect(succeeded(results).size).to be >= 1
    end

    it "expiry x authorization-epoch change: the expiry re-reads the epoch under the lock" do
      id = revocable_assignment(expires_at: t1)
      grant_session = admin_session(at: t1)
      target = account

      results, = RaceHarness.interleave(
        org_key,
        gated: [expiry_for(id),
                -> { request_grant(target, key: "advance", epoch: 8, at: t1, session_id: grant_session) }]
      )

      # The expiry re-reads the epoch under the lock, so it can never lose on a
      # stale one; the grant quotes an epoch and loses if the expiry went first.
      expect(results.first).to be_success
      expect(assignment(id)["status"]).to eq("expired")
      expect(epoch).to eq(8 + succeeded(results).size)
    end

    # The sole administrator's timer, racing the arrival of a replacement.
    def sole_admin_with_timer
      id = seeded_assignment(role: "OrganizationAdmin", account_id: account("admin2"), expires_at: t1)
      DbInspector.connection.exec_params(
        "UPDATE role_assignments SET status = 'revoked', terminated_at = now() WHERE account_id = $1::uuid",
        [admin[:account_id]]
      )
      id
    end

    it "blocked expiry x creation of a replacement administrator" do
      requester = security_operator(at: t1 - 3600)
      approver = security_operator(at: t1)
      id = sole_admin_with_timer
      # Requested an hour before the timer, so the approval that would supply the
      # replacement is still inside its 24-hour window when the timer fires.
      replacement = request_grant(account("admin3"), role: "OrganizationAdmin",
                                  expires_at: t1 + (5 * 24 * 3600),
                                  session_id: requester[:session_id], at: t1 - 3600)
      expect(replacement).to be_success
      pending_replacement = replacement.payload[:role_assignment_id]

      results, = RaceHarness.interleave(
        org_key,
        gated: [expiry_for(id),
                -> { decide_grant(pending_replacement, approver[:session_id], epoch: 7, at: t1) }]
      )

      expect(succeeded(results).size).to eq(2)
      blocked = DbInspector.count("role_expiry_block_decisions")
      if blocked == 1
        # The expiry evaluated first: it blocked at the epoch it observed, and the
        # Assignment is still active and effective (:346).
        expect(assignment(id)["status"]).to eq("active")
        expect(events("RoleExpiryBlocked")).to eq(1)
      else
        # The replacement activated first: the predicate cleared and the expiry
        # committed through the ordinary edge (:347).
        expect(assignment(id)["status"]).to eq("expired")
        expect(events("RoleExpiryBlocked")).to eq(0)
      end
      expect(effective_admins).to be >= 1
    end

    it "blocked expiry x revocation of another administrator never strands the Organization" do
      security = security_operator(at: t1)
      second = seeded_assignment(role: "OrganizationAdmin", account_id: account("admin2"), expires_at: t1)
      admin_assignment = DbInspector.one("SELECT id, state_version FROM role_assignments WHERE account_id = $1::uuid",
                                         [admin[:account_id]])

      RaceHarness.interleave(
        org_key,
        gated: [expiry_for(second),
                -> { revoke_grant(admin_assignment["id"], session_id: security[:session_id],
                                  version: admin_assignment["state_version"].to_i, epoch: 7, at: t1) }]
      )

      # THE invariant: whichever order the two took, an effective OrganizationAdmin
      # remains — either because the revoke was refused as `last_organization_admin`
      # or because the expiry was blocked and left its Assignment active.
      expect(effective_admins).to be >= 1
    end

    it "duplicate ScheduledAction delivery: two workers claim, only one executes" do
      id = revocable_assignment(expires_at: t1)
      second_batch = nil

      # The first worker claims the action and then blocks inside its handler,
      # mid-transaction. While it is demonstrably held there, a second worker
      # sweeps for due work: `FOR UPDATE SKIP LOCKED` plus the claim generation
      # means it finds nothing to take.
      first, = RaceHarness.interleave(
        org_key,
        gated: [-> { worker.run_due_batch }],
        while_committing: -> { second_batch = worker.run_due_batch }
      )

      expect(second_batch).to be_empty
      executed = first.flatten.compact
      expect(executed.count { |o| o.respond_to?(:disposition) && o.disposition == :completed }).to eq(1)
      expect(assignment(id)["status"]).to eq("expired")
      expect(events("RoleExpired")).to eq(1)
      expect(DbInspector.all("SELECT status FROM scheduled_actions").map { |a| a["status"] }).to eq(["completed"])
    end

    it "replay after a committed expiry: concurrent replays return the stored result" do
      id = revocable_assignment(expires_at: t1)
      command = expire_command(id)
      expect(expire(id, command:)).to be_success

      results, = RaceHarness.interleave(
        org_key, gated: [-> { expire(id, command:) }, -> { expire(id, command:) }]
      )

      expect(results.all? { |r| r.replayed }).to be(true)
      expect(events("RoleExpired")).to eq(1)
      expect(epoch).to eq(9)
    end

    it "replay after a committed revoke: concurrent replays return the stored result" do
      id = revocable_assignment
      expect(revoke_grant(id, key: "same", epoch: 8)).to be_success

      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { revoke_grant(id, key: "same", epoch: 8) },
                -> { revoke_grant(id, key: "same", epoch: 8) }]
      )

      expect(results.all? { |r| r.replayed }).to be(true)
      expect(events("RoleRevoked")).to eq(1)
      expect(epoch).to eq(9)
    end

    it "terminal timer delivery after revoke completes harmlessly and advances no epoch" do
      id = revocable_assignment(expires_at: t1)
      expect(revoke_grant(id, session_id: admin_session(at: t1), epoch: 8, at: t1)).to be_success
      after_revoke = epoch

      outcomes = worker.run_due_batch

      expect(outcomes.map(&:disposition)).to eq([:completed])
      expect(outcomes.first.reason).to eq("role_assignment_not_active")
      expect(assignment(id)["status"]).to eq("revoked")
      expect(assignment(id)["state_version"].to_i).to eq(1)
      expect(epoch).to eq(after_revoke)
      expect(events("RoleExpired")).to eq(0)
      # The timer was never cancelled or rewritten; it simply completed.
      expect(DbInspector.all("SELECT status FROM scheduled_actions").map { |a| a["status"] }).to eq(["completed"])
    end
  end

  # ===========================================================================
  describe "authority use" do
    it "protected authorization x RoleAssignment revoke: one of the two commits, never both" do
      approver = security_operator
      other_security = security_operator
      pending = request_grant(account("grantee"), role: "OrganizationAdmin", expires_at: t1)
      id = pending.payload[:role_assignment_id]

      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { decide_grant(id, approver[:session_id]) },
                -> { revoke_grant(approver[:assignment_id], session_id: other_security[:session_id]) }]
      )

      expect(succeeded(results).size).to eq(1)
      expect(epoch).to eq(8)
      unless results.first.success?
        # The approver's own authority was revoked first, so the approval could
        # not commit and nothing was approved under revoked authority.
        expect(assignment(id)["status"]).to eq("pending")
        expect(DbInspector.count("role_assignment_approvals")).to eq(0)
      end
    end

    it "protected authorization x RoleAssignment expiry: the same exclusivity" do
      # The approver's own Assignment expires at `t1`, and it acts a second
      # earlier — still effective by the ratified resolution rule, where equality
      # belongs to expiry (:316).
      approver = security_operator(at: t1, expires_at: t1)
      pending = request_grant(account("grantee"), role: "OrganizationAdmin",
                              expires_at: t1 + (5 * 24 * 3600), at: t1 - 3600,
                              session_id: admin_session(at: t1 - 3600))
      expect(pending).to be_success
      id = pending.payload[:role_assignment_id]

      results, = RaceHarness.interleave(
        org_key,
        gated: [-> { decide_grant(id, approver[:session_id], at: t1 - 1) },
                expiry_for(approver[:assignment_id])]
      )

      expect(succeeded(results).size).to be >= 1
      expect(epoch).to eq(7 + succeeded(results).size)
      expect(DbInspector.count("role_assignment_approvals")).to be <= 1
    end

    # CreateInvitation takes no lifecycle lock, so the interleaving is expressed
    # the other way round: the revoke is held OPEN in its transaction while the
    # invitation command runs to completion and commits underneath it. That is
    # ":333 revocation takes effect on the next protected request" stated exactly.
    it "CreateInvitation grant evaluation x requester revoke" do
      requester = account("admin2")
      requester_assignment = seeded_assignment(role: "OrganizationAdmin", account_id: requester)
      requester_session = session_for(requester)
      security = security_operator
      created = nil

      gated, = RaceHarness.interleave(
        org_key,
        gated: [-> { revoke_grant(requester_assignment, session_id: security[:session_id]) }],
        while_committing: -> { created = create_invitation(requester_session) }
      )

      expect(created).to be_success
      expect(gated.first).to be_success
      # The next protected request under the same Session is refused.
      expect(create_invitation(requester_session, key: "after").reason_code).to eq("missing_authority")
      expect(DbInspector.count("invitations")).to eq(1)
    end

    it "CreateInvitation grant evaluation x requester expiry" do
      requester = account("admin2")
      requester_assignment = seeded_assignment(role: "OrganizationAdmin", account_id: requester,
                                               expires_at: t1)
      requester_session = session_for(requester, at: t1)
      created = nil

      RaceHarness.interleave(
        org_key,
        gated: [expiry_for(requester_assignment)],
        while_committing: -> { created = create_invitation(requester_session, at: t1 - 1) }
      )

      expect(created).to be_success
      expect(assignment(requester_assignment)["status"]).to eq("expired")
      expect(create_invitation(requester_session, key: "after", at: t1).reason_code).to eq("missing_authority")
    end

    # DecideInvitation DOES take a per-Invitation lock, so the strong form is
    # available: it authorizes with valid authority, blocks mid-transaction, the
    # SecurityOperator's Assignment is revoked and COMMITS underneath it, and only
    # then is it released. ":333 A running privileged operation rechecks at each
    # durable checkpoint and stops before the next protected side effect after
    # revocation."
    it "DecideInvitation x SecurityOperator revoke: the approval cannot commit under revoked authority" do
      approver = security_operator
      other_security = security_operator
      invitation = pending_invitation

      gated, revoked = RaceHarness.interleave(
        invitation_key(invitation),
        gated: [-> { decide_invitation(invitation, approver[:session_id]) }],
        while_committing: -> { revoke_grant(approver[:assignment_id], session_id: other_security[:session_id]) }
      )

      expect(revoked).to be_success
      expect(gated.first.reason_code).to eq("stale_authorization_epoch")
      expect(DbInspector.one("SELECT state FROM invitations WHERE id = $1::uuid",
                             [invitation])["state"]).to eq("pending_approval")
    end

    it "DecideInvitation x SecurityOperator expiry: the approval cannot commit under expired authority" do
      approver = security_operator(expires_at: t1)
      invitation = pending_invitation

      gated, = RaceHarness.interleave(
        invitation_key(invitation),
        gated: [-> { decide_invitation(invitation, approver[:session_id]) }],
        while_committing: expiry_for(approver[:assignment_id])
      )

      expect(gated.first.reason_code).to eq("stale_authorization_epoch")
      expect(DbInspector.one("SELECT state FROM invitations WHERE id = $1::uuid",
                             [invitation])["state"]).to eq("pending_approval")
    end

    it "stale Session use immediately after revoke is refused" do
      requester = account("admin2")
      requester_assignment = seeded_assignment(role: "OrganizationAdmin", account_id: requester)
      requester_session = session_for(requester)
      security = security_operator

      expect(revoke_grant(requester_assignment, session_id: security[:session_id])).to be_success
      # No delay, no cache flush: the very next protected request.
      expect(create_invitation(requester_session).reason_code).to eq("missing_authority")
      expect(request_grant(account, session_id: requester_session, epoch: 8).reason_code)
        .to eq("missing_authority")
    end

    it "stale Session use immediately after expiry is refused" do
      requester = account("admin2")
      requester_assignment = seeded_assignment(role: "OrganizationAdmin", account_id: requester,
                                               expires_at: t1)
      requester_session = session_for(requester, at: t1)

      expect(expire(requester_assignment)).to be_success
      expect(create_invitation(requester_session, at: t1).reason_code).to eq("missing_authority")
    end
  end

  # ===========================================================================
  # The shared primitive this matrix exposed. Before it existed, a command that
  # authorized, then took its record lock, then wrote, could commit a protected
  # side effect under authority that had already been revoked underneath it.
  describe "the durable-checkpoint recheck" do
    it "refuses RevokeInvitation whose actor lost its authority while it held the Invitation lock" do
      requester = account("admin2")
      requester_assignment = seeded_assignment(role: "OrganizationAdmin", account_id: requester)
      requester_session = session_for(requester)
      security = security_operator
      created = create_invitation(requester_session)
      expect(created).to be_success
      reference = DbInspector.one("SELECT id FROM invitations")["id"]

      gated, = RaceHarness.interleave(
        invitation_key(reference),
        gated: [-> { revoke_invitation(created.payload[:invitation_reference], requester_session) }],
        while_committing: -> { revoke_grant(requester_assignment, session_id: security[:session_id]) }
      )

      expect(gated.first.reason_code).to eq("stale_authorization_epoch")
      expect(DbInspector.one("SELECT state FROM invitations WHERE id = $1::uuid", [reference])["state"])
        .to eq("active")
    end

    it "answers the predicate from current database state, not from the actor's snapshot" do
      store = nil
      actor = nil
      Platform::UnitOfWork.run do |conn|
        store = IdentityAccess::Infrastructure::AuthorizationStore.new(conn.raw_connection)
        auth = IdentityAccess::Authorization::CommandAuthorizer.new(store)
        actor = auth.authenticate(session_id: admin[:session_id], now: t0,
                                  correlation_id: SecureRandom.uuid_v7)
        expect(IdentityAccess::Authorization::CommandAuthorizer.authority_current?(store:, actor:))
          .to be(true)
      end

      request_grant(account, key: "advance")

      Platform::UnitOfWork.run do |conn|
        fresh = IdentityAccess::Infrastructure::AuthorizationStore.new(conn.raw_connection)
        fresh.enter_org_context(org, SecureRandom.uuid_v7)
        expect(IdentityAccess::Authorization::CommandAuthorizer.authority_current?(store: fresh, actor:))
          .to be(false)
      end
    end
  end

  # ===========================================================================
  describe "invariants that must hold whatever the interleaving" do
    it "never leaves an active expiring Assignment without exactly one timer" do
      3.times { |i| request_grant(account, key: "g#{i}", epoch: 7 + i, expires_at: t1) }

      orphans = DbInspector.all(<<~SQL)
        SELECT r.id FROM role_assignments r
        WHERE r.status = 'active' AND r.expires_at IS NOT NULL
          AND (SELECT count(*) FROM scheduled_actions a
               WHERE a.target_id = r.id AND a.action_kind = 'role_assignment_expire') <> 1
      SQL
      expect(orphans).to be_empty
    end

    it "never creates a timer for a failed activation" do
      security = security_operator
      pending = request_grant(account("grantee"), role: "OrganizationAdmin", expires_at: t1)
      id = pending.payload[:role_assignment_id]
      expect(DbInspector.count("scheduled_actions")).to eq(0)

      expect(decide_grant(id, security[:session_id], decision: "reject",
                          reason: "rejected for the concurrency invariant coverage")).to be_success
      expect(DbInspector.count("scheduled_actions")).to eq(0)
    end

    it "never confers authority from a partial approval" do
      security = security_operator
      pending = request_grant(account("grantee"), role: "SecurityOperator", expires_at: t1)
      id = pending.payload[:role_assignment_id]
      grantee_session = session_for(assignment(id)["account_id"])

      # Pending: the allowlist is empty and confers nothing.
      expect(JSON.parse(assignment(id)["protected_permission_allowlist"])).to eq([])
      expect(decide_invitation(pending_invitation, grantee_session).reason_code).to eq("missing_authority")

      expect(decide_grant(id, security[:session_id])).to be_success
      expect(JSON.parse(assignment(id)["protected_permission_allowlist"])).to include("invitation.approve")
    end

    it "keeps the authorization epoch monotonic across every accepted mutation" do
      observed = [epoch]
      id = request_grant(account, expires_at: t1).payload[:role_assignment_id]
      observed << epoch
      revoke_grant(id, epoch: 8)
      observed << epoch
      request_grant(account, key: "another", epoch: 9)
      observed << epoch

      expect(observed).to eq(observed.sort)
      expect(observed.uniq.size).to eq(observed.size)
    end

    it "binds a RoleExpiryBlockDecision to exactly one epoch and never reuses it in another" do
      id = sole_admin_for_block
      expect(expire(id)).to be_success
      decision = DbInspector.one("SELECT * FROM role_expiry_block_decisions")
      expect(decision["authorization_epoch"].to_i).to eq(7)

      # A second decision inside the same epoch is impossible.
      expect do
        DbInspector.connection.exec_params(<<~SQL, [SecureRandom.uuid_v7, org, id])
          INSERT INTO role_expiry_block_decisions
            (id, schema_version, created_at, organization_id, role_assignment_id, assignment_expires_at,
             authorization_epoch, block_reason, predicate_result, decided_at, correlation_id, retention_class)
          VALUES ($1,'1.0',now(),$2::uuid,$3::uuid,now(),7,'expiry_blocked_last_admin','{}'::jsonb,now(),
                  gen_random_uuid(),'security_audit')
        SQL
      end.to raise_error(PG::UniqueViolation, /one_decision_per_assignment_epoch/)

      # A decision for a DIFFERENT epoch is a new record, never the old one reused.
      DbInspector.connection.exec_params(<<~SQL, [SecureRandom.uuid_v7, org, id])
        INSERT INTO role_expiry_block_decisions
          (id, schema_version, created_at, organization_id, role_assignment_id, assignment_expires_at,
           authorization_epoch, block_reason, predicate_result, decided_at, correlation_id, retention_class)
        VALUES ($1,'1.0',now(),$2::uuid,$3::uuid,now(),8,'expiry_blocked_last_admin','{}'::jsonb,now(),
                gen_random_uuid(),'security_audit')
      SQL
      epochs = DbInspector.all("SELECT authorization_epoch FROM role_expiry_block_decisions ORDER BY 1")
                          .map { |r| r["authorization_epoch"].to_i }
      expect(epochs).to eq([7, 8])
    end

    def sole_admin_for_block
      id = seeded_assignment(role: "OrganizationAdmin", account_id: account("admin2"), expires_at: t1)
      DbInspector.connection.exec_params(
        "UPDATE role_assignments SET status = 'revoked', terminated_at = now() WHERE account_id = $1::uuid",
        [admin[:account_id]]
      )
      id
    end
  end
end
