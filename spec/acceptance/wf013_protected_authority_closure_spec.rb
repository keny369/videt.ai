# frozen_string_literal: true

require "rails_helper"

# The protected-authority path end to end, through production commands only.
#
# One narrative: a bootstrap OrganizationAdmin requests protected SecurityOperator
# authority, a distinct SecurityOperator approves it, the new SecurityOperator
# signs in under the new epoch and approves a real Invitation with authority it
# obtained entirely through the workflow — then that authority is taken away,
# twice over: once by revocation and once by the timer.
#
# No fixture writes or edits an allowlist for any principal under test. The single
# seeded SecurityOperator is the security-bootstrap service, which :333 expressly
# reserves for the FIRST SecurityOperator in an Organization and which is not
# built in this slice; every other grant here comes from Request + Decide.
RSpec.describe "WF-013 protected authority closure", type: :acceptance,
               acceptance_ids: ["AC-CAP-013", "AC-CAP-025", "AC-WF-013"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def t0 = Time.utc(2026, 6, 1, 10, 0, 0)
  def t1 = t0 + (10 * 24 * 3600)
  def org_scope = Digest::SHA256.digest("scope:organization")

  let(:admin) { TenantSeeder.seed_authorized_admin(issued_at: t0 - 900) }
  let(:org) { admin[:organization_id] }

  def ctx(now = t0)
    Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(now), ids: Platform::Ids.system,
                                       correlation_id: SecureRandom.uuid_v7)
  end

  def account(subject = "person")
    TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                subject: "#{subject}-#{SecureRandom.hex(6)}")
  end

  def session_for(account_id, at: t0)
    TenantSeeder.create_session(organization_id: org, account_id:, issued_at: at - 900,
                                last_activity_at: at,
                                authorization_context_version: current_epoch)
  end

  def current_epoch = DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id = $1::uuid",
                                      [org])["authorization_epoch"].to_i

  def assignment(id) = DbInspector.one("SELECT * FROM role_assignments WHERE id = $1::uuid", [id])
  def events = DbInspector.all("SELECT event_type FROM event_registry ORDER BY created_at").map { |e| e["event_type"] }

  # ---- production commands --------------------------------------------------

  def request_grant(target, role:, expires_at:, session_id:, epoch:, at: t0, key: "req-#{SecureRandom.hex(3)}")
    cmd = Workflows::Wf013::Commands::RequestRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id:,
      account_id: target, canonical_role: role, permission_mode: "standard", persona: nil,
      scope_sha256: org_scope, expires_at:, expected_authorization_epoch: epoch, reason: nil,
      requested_at_utc: at
    )
    Workflows::Wf013::Handlers::RequestRoleAssignment.new.call(command: cmd, request_context: ctx(at))
  end

  def decide_grant(id, session_id, epoch:, version: 0, at: t0, key: "dec-#{SecureRandom.hex(3)}")
    cmd = Workflows::Wf013::Commands::DecideRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id:,
      role_assignment_id: id, expected_state_version: version, expected_authorization_epoch: epoch,
      decision: "approve", reason: nil, requested_at_utc: at
    )
    Workflows::Wf013::Handlers::DecideRoleAssignment.new.call(command: cmd, request_context: ctx(at))
  end

  def revoke_grant(id, session_id:, epoch:, version:, at: t0, key: "rv-#{SecureRandom.hex(3)}")
    cmd = Workflows::Wf013::Commands::RevokeRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id:,
      role_assignment_id: id, expected_state_version: version, expected_authorization_epoch: epoch,
      reason: "authority withdrawn at the close of the protected path", requested_at_utc: at
    )
    Workflows::Wf013::Handlers::RevokeRoleAssignment.new.call(command: cmd, request_context: ctx(at))
  end

  def decide_invitation(invitation_id, session_id, at: t0, key: "iv-#{SecureRandom.hex(3)}")
    cmd = Workflows::Wf013::Commands::DecideInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id:,
      invitation_id:, expected_state_version: 0, decision: "approve", reason: nil, requested_at_utc: at
    )
    Workflows::Wf013::Handlers::DecideInvitation.new.call(command: cmd, request_context: ctx(at))
  end

  def worker(now = t1)
    Platform::ScheduledActions::Worker.new(
      registry: Platform::ScheduledActions::Registry.default,
      scheduler: Platform::ScheduledActions::Scheduler.new,
      clock: Platform::Clock.fixed(now), ids: Platform::Ids.system
    )
  end

  # ---- preconditions --------------------------------------------------------

  # ":333 The first SecurityOperator Assignment in an Organization … requires two
  # distinct pre-provisioned platform security identities through the
  # security-bootstrap service." That service is a later slice, so its single
  # output is arranged here and nothing else in this file is.
  def bootstrap_security_operator
    @bootstrap_security_operator ||= begin
      id = account("bootstrap-sec")
      {
        account_id: id,
        assignment_id: TenantSeeder.create_role_assignment(
          organization_id: org, account_id: id, canonical_role: "SecurityOperator",
          scope_sha256: org_scope, effective_at: t0,
          protected_permission_allowlist:
            Platform::PermissionBaseline.protected_permission_preview("SecurityOperator")
        ),
        session_id: session_for(id)
      }
    end
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

  # The whole grant-and-use path, returned so the revoke and expiry narratives can
  # continue from exactly the state it leaves behind.
  def granted_security_operator(expires_at: t1)
    bootstrap = bootstrap_security_operator
    grantee = account("newsec")

    # 1. the bootstrap OrganizationAdmin requests protected SecurityOperator authority
    requested = request_grant(grantee, role: "SecurityOperator", expires_at:,
                              session_id: admin[:session_id], epoch: 7)
    raise "request failed: #{requested.reason_code}" unless requested.success?

    id = requested.payload[:role_assignment_id]

    # 3. a distinct authorized SecurityOperator approves it
    approved = decide_grant(id, bootstrap[:session_id], epoch: 7)
    raise "approval failed: #{approved.reason_code}" unless approved.success?

    { assignment_id: id, account_id: grantee, bootstrap:, session_id: session_for(grantee) }
  end

  # ===========================================================================
  describe "grant and use" do
    it "carries protected authority from request to real use, through production commands only" do
      bootstrap = bootstrap_security_operator
      grantee = account("newsec")

      # 1. request
      requested = request_grant(grantee, role: "SecurityOperator", expires_at: t1,
                                session_id: admin[:session_id], epoch: 7)
      expect(requested).to be_success
      id = requested.payload[:role_assignment_id]

      # 2. the bootstrap exception permits the request to be EVALUATED, but the
      # grant is still pending: it does not bypass approval.
      expect(assignment(id)["status"]).to eq("pending")
      expect(JSON.parse(assignment(id)["protected_permission_allowlist"])).to eq([])
      expect(current_epoch).to eq(7)
      expect(DbInspector.one("SELECT bootstrap_admin_exception FROM role_assignments WHERE account_id = $1::uuid",
                             [admin[:account_id]])["bootstrap_admin_exception"]).to eq("t")

      # 3-4. an authorized SecurityOperator approves; the Assignment activates
      expect(decide_grant(id, bootstrap[:session_id], epoch: 7)).to be_success
      expect(assignment(id)["status"]).to eq("active")

      # 5. the allowlist carries invitation.approve, written by the approval
      expect(JSON.parse(assignment(id)["protected_permission_allowlist"])).to include("invitation.approve")

      # 6. the Organization epoch advanced
      expect(current_epoch).to eq(8)

      # 7. the new SecurityOperator authenticates under the new epoch
      grantee_session = session_for(grantee)
      expect(DbInspector.one("SELECT authorization_context_version FROM sessions WHERE id = $1::uuid",
                             [grantee_session])["authorization_context_version"].to_i).to eq(8)

      # 8. and approves an Invitation with authority it obtained entirely here
      invitation = pending_invitation
      expect(decide_invitation(invitation, grantee_session)).to be_success
      expect(DbInspector.one("SELECT state FROM invitations WHERE id = $1::uuid", [invitation])["state"])
        .to eq("active")

      expect(events).to eq(%w[RoleAssignmentRequested RoleGranted InvitationActivated])
    end

    it "never lets any fixture in this file write an allowlist for the principal under test" do
      subject = granted_security_operator
      approval = DbInspector.one("SELECT * FROM role_assignment_approvals WHERE role_assignment_id = $1::uuid",
                                 [subject[:assignment_id]])

      expect(approval).not_to be_nil
      expect(approval["approver_account_id"]).to eq(subject[:bootstrap][:account_id])
      expect(JSON.parse(assignment(subject[:assignment_id])["protected_permission_allowlist"]))
        .to eq(Platform::PermissionBaseline.protected_permission_preview("SecurityOperator"))
    end
  end

  # ===========================================================================
  describe "revoke" do
    it "withdraws the authority, keeps the history and leaves the timer to complete harmlessly" do
      subject = granted_security_operator
      id = subject[:assignment_id]
      grantee_session = subject[:session_id]
      timer = DbInspector.one("SELECT * FROM scheduled_actions WHERE target_id = $1::uuid", [id])
      approvals_before = DbInspector.all("SELECT * FROM role_assignment_approvals ORDER BY sequence_number")
      allowlist_before = JSON.parse(assignment(id)["protected_permission_allowlist"])

      # It is still real authority right up to the revocation.
      first = pending_invitation
      expect(decide_invitation(first, grantee_session)).to be_success

      # 1-2. revoked by the distinct SecurityOperator, epoch advanced atomically
      result = revoke_grant(id, session_id: subject[:bootstrap][:session_id], epoch: 8, version: 1)
      expect(result).to be_success
      expect(assignment(id)["status"]).to eq("revoked")
      expect(current_epoch).to eq(9)
      expect(result.payload[:authorization_epoch]).to eq(9)

      # 3. grant and approval history preserved
      expect(JSON.parse(assignment(id)["protected_permission_allowlist"])).to eq(allowlist_before)
      expect(DbInspector.all("SELECT * FROM role_assignment_approvals ORDER BY sequence_number"))
        .to eq(approvals_before)

      # 4. the timer is untouched
      after_timer = DbInspector.one("SELECT * FROM scheduled_actions WHERE id = $1::uuid", [timer["id"]])
      expect(after_timer).to eq(timer)

      # 5. the existing Session is behind the epoch it was issued under
      session = DbInspector.one("SELECT * FROM sessions WHERE id = $1::uuid", [grantee_session])
      expect(session["authorization_context_version"].to_i).to be < current_epoch
      expect(session["status"]).to eq("active") # a grant revocation is not a Session revocation

      # 6. a further DecideInvitation is refused
      second = pending_invitation
      expect(decide_invitation(second, grantee_session).reason_code).to eq("missing_authority")
      expect(DbInspector.one("SELECT state FROM invitations WHERE id = $1::uuid", [second])["state"])
        .to eq("pending_approval")

      # 7-8. the old timer is delivered later and completes harmlessly. The batch
      # also carries the expiry of the Invitation this authority activated, so the
      # Assignment's own outcome is picked out by its action.
      epoch_before_timer = current_epoch
      outcomes = worker.run_due_batch
      expect(outcomes.map(&:disposition).uniq).to eq([:completed])
      role_outcome = outcomes.find { |o| o.action_id == timer["id"] }
      expect(role_outcome.reason).to eq("role_assignment_not_active")
      expect(assignment(id)["status"]).to eq("revoked")
      expect(assignment(id)["state_version"].to_i).to eq(2)
      expect(current_epoch).to eq(epoch_before_timer)
      expect(events).not_to include("RoleExpired")
    end
  end

  # ===========================================================================
  describe "expiry" do
    it "expires the granted authority at its due instant and advances the epoch once" do
      subject = granted_security_operator
      id = subject[:assignment_id]
      before = current_epoch

      # 1. the active expiring Assignment reaches its due instant
      expect(assignment(id)["status"]).to eq("active")
      outcomes = worker.run_due_batch

      # 2-3. ordinary expiry
      expect(outcomes.map(&:disposition)).to eq([:completed])
      expect(assignment(id)["status"]).to eq("expired")
      expect(assignment(id)["transition_reason_code"]).to eq("role_assignment_expired")
      expect(current_epoch).to eq(before + 1)
      expect(events).to include("RoleExpired")
      expect(DbInspector.count("role_expiry_block_decisions")).to eq(0)

      # 8. the Session that held the authority is itself long past its absolute
      # deadline by now, and is refused as authentication before authority is
      # even considered.
      invitation = pending_invitation
      expect(decide_invitation(invitation, subject[:session_id], at: t1).reason_code)
        .to eq("session_invalid")

      # 7. and a Session minted right now, which authenticates perfectly, still
      # confers nothing: it is the AUTHORITY that expired, not the Session.
      fresh = session_for(subject[:account_id], at: t1)
      expect(decide_invitation(invitation, fresh, at: t1).reason_code).to eq("missing_authority")
      expect(DbInspector.one("SELECT state FROM invitations WHERE id = $1::uuid", [invitation])["state"])
        .to eq("pending_approval")
    end

    it "blocks the last administrator's expiry, writing one immutable decision and advancing no epoch" do
      # The bootstrap admin's own Assignment is the Organization's only effective
      # OrganizationAdmin authority, and it is given an expiry so the timer exists.
      admin_assignment = DbInspector.one("SELECT id FROM role_assignments WHERE account_id = $1::uuid",
                                         [admin[:account_id]])["id"]
      DbInspector.connection.exec_params(<<~SQL, [admin_assignment, t1.iso8601(6)])
        UPDATE role_assignments SET expires_at = $2::timestamptz WHERE id = $1::uuid
      SQL
      ScheduledActionHarness.in_context(org) do |_store, correlation_id|
        Workflows::Wf013::RoleAssignmentExpirySchedule.schedule(
          pg: ActiveRecord::Base.connection.raw_connection, organization_id: org,
          role_assignment_id: admin_assignment, expires_at: t1, now: t0, correlation_id:
        )
      end
      before = current_epoch

      # 2. the predicate is evaluated from current database state at the due instant
      expect(worker.run_due_batch.map(&:disposition)).to eq([:completed])

      # 4. one immutable block decision
      decisions = DbInspector.all("SELECT * FROM role_expiry_block_decisions")
      expect(decisions.size).to eq(1)
      expect(decisions.first["block_reason"]).to eq("expiry_blocked_last_admin")
      expect(decisions.first["role_assignment_id"]).to eq(admin_assignment)
      expect(decisions.first["authorization_epoch"].to_i).to eq(before)
      expect(JSON.parse(decisions.first["predicate_result"])["other_effective_organization_admins"]).to eq(0)

      # ":346 the Assignment remains active and remains effective past expires_at"
      expect(assignment(admin_assignment)["status"]).to eq("active")

      # 5. no epoch advance: no authority changed
      expect(current_epoch).to eq(before)
      expect(events).to include("RoleExpiryBlocked")
      expect(events).not_to include("RoleExpired")

      # 6. duplicate delivery creates no second decision or event
      redeliver(admin_assignment)
      expect(DbInspector.count("role_expiry_block_decisions")).to eq(1)
      expect(events.count("RoleExpiryBlocked")).to eq(1)
      expect(current_epoch).to eq(before)
    end

    # ":425 the guard is re-evaluated on each Organization authorization-epoch
    # advance rather than replayed from a transport queue, and that background
    # exposure remains intentionally deferred until the Volume II baseline."
    # So the blocked action COMPLETES and the decision persists; there is
    # deliberately no re-scheduling loop here, and none may be invented.
    it "records the Volume II deferral rather than rescheduling the blocked evaluation" do
      admin_assignment = DbInspector.one("SELECT id FROM role_assignments WHERE account_id = $1::uuid",
                                         [admin[:account_id]])["id"]
      DbInspector.connection.exec_params(<<~SQL, [admin_assignment, t1.iso8601(6)])
        UPDATE role_assignments SET expires_at = $2::timestamptz WHERE id = $1::uuid
      SQL
      ScheduledActionHarness.in_context(org) do |_store, correlation_id|
        Workflows::Wf013::RoleAssignmentExpirySchedule.schedule(
          pg: ActiveRecord::Base.connection.raw_connection, organization_id: org,
          role_assignment_id: admin_assignment, expires_at: t1, now: t0, correlation_id:
        )
      end

      worker.run_due_batch

      # Exactly one action, completed. No successor was scheduled.
      actions = DbInspector.all("SELECT * FROM scheduled_actions")
      expect(actions.size).to eq(1)
      expect(actions.first["status"]).to eq("completed")
      expect(worker(t1 + 3600).run_due_batch).to be_empty
    end

    # The exact command a duplicate transport delivery presents to the handler.
    def redeliver(role_assignment_id)
      row = ScheduledActionHarness.row(
        DbInspector.one("SELECT id FROM scheduled_actions WHERE target_id = $1::uuid",
                        [role_assignment_id])["id"]
      )
      command = Workflows::Wf013::Commands::ExpireRoleAssignment.new(
        command_id: SecureRandom.uuid_v7, schema_version: "1.0", organization_id: org,
        target_type: "role_assignment", role_assignment_id:,
        due_at: Time.parse(row["due_at"]).getutc, action_id: row["id"],
        action_identity_sha256: [row["identity_sha256"].delete_prefix("\\x")].pack("H*"),
        requested_at_utc: t1
      )
      service = Platform::RequestContext.for_service(
        service_identity_id: Platform::ServiceIdentity.scheduled_action_executor,
        clock: Platform::Clock.fixed(t1), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
      )
      Workflows::Wf013::Handlers::ExpireRoleAssignment.new.call(command:, request_context: service)
    end
  end
end
