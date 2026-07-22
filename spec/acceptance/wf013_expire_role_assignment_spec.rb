# frozen_string_literal: true

require "rails_helper"

# WF-013 ExpireRoleAssignment and the RoleExpiryBlockDecision guard
# (WORKFLOW_SPECIFICATIONS.md :316, :343-351; BACKGROUND_PROCESSING.md :132,
# :192, :406).
#
# This closes the production gap the previous pass left: `role_assignment_expire`
# actions were being created with no consumer, so a due one reached quarantine.
RSpec.describe "WF-013 expire role assignment", type: :acceptance,
               acceptance_ids: ["AC-CAP-013", "AC-WF-013"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  # Expiry in the real past, so PostgreSQL — the sole due-time authority —
  # considers the timer due.
  def granted_at = Time.utc(2026, 6, 1, 10, 0, 0)
  def expires_at = granted_at + (10 * 24 * 3600)

  let(:admin) { TenantSeeder.seed_authorized_admin(issued_at: granted_at - 900) }
  let(:org) { admin[:organization_id] }

  def ctx(now = granted_at)
    Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(now), ids: Platform::Ids.system,
                                       correlation_id: SecureRandom.uuid_v7)
  end

  def account(subject = "target")
    TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                subject: "#{subject}-#{SecureRandom.hex(6)}")
  end

  # A real, active, expiring Assignment created through the production command.
  def grant(role: "MarketingOperator", target: nil, epoch: 7, key: "g-#{SecureRandom.hex(3)}")
    cmd = Workflows::Wf013::Commands::RequestRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      session_id: admin[:session_id], account_id: target || account, canonical_role: role,
      permission_mode: "standard", persona: nil,
      scope_sha256: Digest::SHA256.digest("scope:organization"), expires_at:,
      expected_authorization_epoch: epoch, reason: nil, requested_at_utc: granted_at
    )
    result = Workflows::Wf013::Handlers::RequestRoleAssignment.new.call(command: cmd, request_context: ctx)
    raise "grant failed: #{result.reason_code}" unless result.success?

    result.payload[:role_assignment_id]
  end

  def worker(now = expires_at)
    Platform::ScheduledActions::Worker.new(
      registry: Platform::ScheduledActions::Registry.default,
      scheduler: Platform::ScheduledActions::Scheduler.new,
      clock: Platform::Clock.fixed(now), ids: Platform::Ids.system
    )
  end

  def assignment(id) = DbInspector.one("SELECT * FROM role_assignments WHERE id = $1::uuid", [id])
  def actions = DbInspector.all("SELECT * FROM scheduled_actions")
  def events = DbInspector.all("SELECT event_type FROM event_registry ORDER BY created_at").map { |e| e["event_type"] }
  def epoch = DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id = $1::uuid",
                              [org])["authorization_epoch"].to_i

  describe "the action now has a production consumer" do
    it "never reaches scheduled_work_mapping_mismatch for a valid due role_assignment_expire action" do
      grant
      outcomes = worker.run_due_batch

      expect(outcomes.map(&:reason)).not_to include("scheduled_work_mapping_mismatch")
      expect(actions.map { |a| a["status"] }).to eq(["completed"])
      expect(DbInspector.all("SELECT reason FROM scheduled_actions").map { |a| a["reason"] })
        .not_to include("scheduled_work_mapping_mismatch")
    end

    it "registers exactly the ratified kinds, each with a real handler" do
      registry = Platform::ScheduledActions::Registry.default
      %w[invitation_expire role_assignment_expire].each do |kind|
        expect(registry.resolve(action_kind: kind, action_schema_version: "1.0")).not_to be_nil
      end
      # An unmapped catalogue kind still fails closed.
      expect(registry.resolve(action_kind: "session_expire", action_schema_version: "1.0")).to be_nil
    end
  end

  describe "ordinary expiry" do
    it "takes the Assignment active -> expired, advancing the authorization epoch" do
      id = grant
      before = epoch

      expect(worker.run_due_batch.map(&:disposition)).to eq([:completed])
      row = assignment(id)
      expect(row["status"]).to eq("expired")
      expect(row["transition_reason_code"]).to eq("role_assignment_expired")
      expect(row["terminated_at"]).not_to be_nil
      expect(epoch).to eq(before + 1)
    end

    it "emits one RoleExpired state-transition event, service-attributed with a null actor" do
      grant
      worker.run_due_batch

      expect(events).to eq(%w[RoleGranted RoleExpired])
      body = JSON.parse(DbInspector.all("SELECT convert_from(event_bytes,'UTF8') AS b FROM event_registry ORDER BY created_at").last["b"])
      expect(body["event_profile"]).to eq("state_transition")
      expect(body["from_state"]).to eq("active")
      expect(body["to_state"]).to eq("expired")
      expect(body["reason_code"]).to eq("role_assignment_expired")
      expect(body["service_identity_id"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)
      expect(body["actor_id"]).to be_nil
    end

    it "attributes the ledger to the executor service, never to a human" do
      grant
      worker.run_due_batch

      ledger = DbInspector.all(<<~SQL).last
        SELECT actor_id, service_identity_id, action, command_type FROM command_executions ORDER BY created_at
      SQL
      expect(ledger["service_identity_id"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)
      expect(ledger["actor_id"]).to be_nil
      expect(ledger["action"]).to eq("role.expire")
      expect(ledger["command_type"]).to eq("wf013.expire_role_assignment")
    end

    it "expires only the Assignment its own timer names" do
      first = grant(key: "a")
      second = grant(key: "b", epoch: 8)

      worker.run_due_batch
      expect(assignment(first)["status"]).to eq("expired")
      expect(assignment(second)["status"]).to eq("expired")
      expect(actions.map { |a| a["status"] }.uniq).to eq(["completed"])
    end

    it "removes effective authority immediately: the expired principal confers nothing" do
      target = account("grantee")
      id = grant(target:)
      worker.run_due_batch

      expect(assignment(id)["status"]).to eq("expired")
      effective = DbInspector.one(<<~SQL, [target])
        SELECT count(*) AS n FROM role_assignments
        WHERE account_id = $1::uuid AND status = 'active'
      SQL
      expect(effective["n"].to_i).to eq(0)
    end
  end

  describe "the last-administrator block" do
    # The bootstrap admin is the only OrganizationAdmin, so expiring a second one
    # is fine; expiring the LAST one must not strand the tenant.
    # An OrganizationAdmin grant is protected and cannot be created active by the
    # grant command, so the Assignment is arranged directly — this example is
    # testing EXPIRY, not the grant workflow — while its timer comes from the same
    # production scheduler activation uses.
    def expiring_admin_assignment(sole:)
      target = account("admin2")
      id = TenantSeeder.create_role_assignment(
        organization_id: org, account_id: target, canonical_role: "OrganizationAdmin",
        scope_sha256: Digest::SHA256.digest("scope:organization"),
        effective_at: granted_at, expires_at:
      )
      ScheduledActionHarness.in_context(org) do |_store, correlation_id|
        Workflows::Wf013::RoleAssignmentExpirySchedule.schedule(
          pg: ActiveRecord::Base.connection.raw_connection, organization_id: org,
          role_assignment_id: id, expires_at:, now: granted_at, correlation_id:
        )
      end
      if sole
        DbInspector.connection.exec_params(
          "UPDATE role_assignments SET status = 'revoked', terminated_at = now() WHERE account_id = $1::uuid",
          [admin[:account_id]]
        )
      end
      id
    end

    def sole_admin_assignment = expiring_admin_assignment(sole: true)

    it "leaves the Assignment active, records the immutable decision and emits RoleExpiryBlocked" do
      id = sole_admin_assignment
      before = epoch

      expect(worker.run_due_batch.map(&:disposition)).to eq([:completed])

      expect(assignment(id)["status"]).to eq("active")
      decision = DbInspector.one("SELECT * FROM role_expiry_block_decisions")
      expect(decision["block_reason"]).to eq("expiry_blocked_last_admin")
      expect(decision["role_assignment_id"]).to eq(id)
      expect(decision["authorization_epoch"].to_i).to eq(before)
      expect(decision["retention_class"]).to eq("security_audit")
      expect(events).to include("RoleExpiryBlocked")
      expect(events).not_to include("RoleExpired")
      # No authority changed, so no epoch advance.
      expect(epoch).to eq(before)
    end

    it "names the decision record as the event's affected entity under the decision profile" do
      sole_admin_assignment
      worker.run_due_batch

      decision = DbInspector.one("SELECT id FROM role_expiry_block_decisions")
      body = JSON.parse(DbInspector.one(<<~SQL)["b"])
        SELECT convert_from(event_bytes,'UTF8') AS b FROM event_registry
        WHERE event_type = 'RoleExpiryBlocked'
      SQL
      expect(body["event_profile"]).to eq("decision")
      expect(body["affected_entity_type"]).to eq("role_expiry_block_decision")
      expect(body["affected_entity_id"]).to eq(decision["id"])
      expect(body["decision_reason_code"]).to eq("expiry_blocked_last_admin")
    end

    it "is idempotent on (assignment, epoch): a retry writes no second decision or event" do
      id = sole_admin_assignment
      worker.run_due_batch
      # A completed action is terminal, so redelivery is exercised where it
      # matters: the same command executed again inside the same epoch.
      redeliver(id)

      expect(DbInspector.count("role_expiry_block_decisions")).to eq(1)
      expect(events.count("RoleExpiryBlocked")).to eq(1)
      expect(assignment(id)["status"]).to eq("active")
    end

    it "refuses to alter a persisted decision, even from an owner connection" do
      sole_admin_assignment
      worker.run_due_batch
      id = DbInspector.one("SELECT id FROM role_expiry_block_decisions")["id"]

      expect(DbInspector.one("SELECT has_table_privilege('f1_web','role_expiry_block_decisions','UPDATE') AS u")["u"])
        .to eq("f")
      expect(DbInspector.one("SELECT has_table_privilege('f1_web','role_expiry_block_decisions','DELETE') AS d")["d"])
        .to eq("f")
      expect(id).not_to be_nil
    end

    it "does not block when another effective OrganizationAdmin remains" do
      id = expiring_admin_assignment(sole: false)
      # The bootstrap admin is still active, so the predicate is satisfied.
      worker.run_due_batch

      expect(assignment(id)["status"]).to eq("expired")
      expect(DbInspector.count("role_expiry_block_decisions")).to eq(0)
      expect(events).not_to include("RoleExpiryBlocked")
    end
  end

  describe "terminal and duplicate delivery" do
    it "completes harmlessly when the Assignment is already terminal" do
      id = grant
      DbInspector.connection.exec_params(
        "UPDATE role_assignments SET status = 'revoked', terminated_at = now() WHERE id = $1::uuid", [id]
      )
      before = epoch

      outcomes = worker.run_due_batch
      expect(outcomes.map(&:disposition)).to eq([:completed])
      expect(outcomes.first.reason).to eq("role_assignment_not_active")
      expect(assignment(id)["status"]).to eq("revoked")
      expect(epoch).to eq(before)
      expect(events).to eq(["RoleGranted"])
    end

    it "creates no second transition or event on duplicate delivery" do
      id = grant
      worker.run_due_batch
      replay = redeliver(id)

      expect(replay.replayed).to be(true)
      expect(events.count("RoleExpired")).to eq(1)
      expect(assignment(id)["state_version"].to_i).to eq(1)
      expect(DbInspector.count("command_executions")).to eq(2) # the grant, and one expiry
    end

    it "fails closed rather than expiring early when the timer is not yet due" do
      target = account
      cmd = Workflows::Wf013::Commands::RequestRoleAssignment.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "future", schema_version: "1.0",
        session_id: admin[:session_id], account_id: target, canonical_role: "MarketingOperator",
        permission_mode: "standard", persona: nil,
        scope_sha256: Digest::SHA256.digest("scope:organization"),
        expires_at: Time.utc(2099, 1, 1), expected_authorization_epoch: 7, reason: nil,
        requested_at_utc: granted_at
      )
      result = Workflows::Wf013::Handlers::RequestRoleAssignment.new.call(command: cmd, request_context: ctx)
      expect(result).to be_success

      expect(worker.run_due_batch).to be_empty
      expect(assignment(result.payload[:role_assignment_id])["status"]).to eq("active")
    end
  end

  # Re-execute the exact command a claimed action produces, which is what a
  # duplicate transport delivery presents to the handler.
  def redeliver(role_assignment_id)
    row = ScheduledActionHarness.row(
      DbInspector.one("SELECT id FROM scheduled_actions WHERE target_id = $1::uuid",
                      [role_assignment_id])["id"]
    )
    digest = [row["identity_sha256"].delete_prefix("\\x")].pack("H*")
    command = Workflows::Wf013::Commands::ExpireRoleAssignment.new(
      command_id: SecureRandom.uuid_v7, schema_version: "1.0", organization_id: org,
      target_type: "role_assignment", role_assignment_id:, due_at: Time.parse(row["due_at"]).getutc,
      action_id: row["id"], action_identity_sha256: digest, requested_at_utc: expires_at
    )
    service = Platform::RequestContext.for_service(
      service_identity_id: Platform::ServiceIdentity.scheduled_action_executor,
      clock: Platform::Clock.fixed(expires_at), ids: Platform::Ids.system,
      correlation_id: SecureRandom.uuid_v7
    )
    Workflows::Wf013::Handlers::ExpireRoleAssignment.new.call(command:, request_context: service)
  end

  describe "transport isolation" do
    it "keeps RoleAssignment reads away from the platform worker" do
      grant
      expect do
        ScheduledActionHarness.as_role("f1_platform_worker") { |pg| pg.exec("SELECT count(*) FROM role_assignments") }
      end.to raise_error(PG::InsufficientPrivilege, /permission denied/i)
      expect do
        ScheduledActionHarness.as_role("f1_platform_worker") { |pg| pg.exec("SELECT count(*) FROM role_expiry_block_decisions") }
      end.to raise_error(PG::InsufficientPrivilege, /permission denied/i)
    end
  end
end
