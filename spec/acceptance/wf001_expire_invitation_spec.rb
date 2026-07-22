# frozen_string_literal: true

require "rails_helper"

# WF-001 ExpireInvitation — the timed, service-only Invitation expiry
# (WORKFLOW_SPECIFICATIONS.md :242 "Active expiry is exactly seven days after
# activation, and at equality expiry wins over acceptance or decline";
# APPLICATION_LAYER.md :371 and contracts/S-01.json — a ScheduledAction
# transition, not a principal command; BACKGROUND_PROCESSING.md :131, :191, :405).
#
# It runs through the production path: the invitation-activation transaction
# created the `invitation_expire` action, the scheduler claims it at its due
# instant, and the worker transfers the claim and executes the registered
# handler under a service identity. No Session exists anywhere on this path.
RSpec.describe "WF-001 expire invitation", type: :acceptance,
               acceptance_ids: ["AC-CAP-001", "AC-WF-001"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA TYP-OBS] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  # Activation at 2026-06-01 10:00 => expiry exactly seven days later, an instant
  # PostgreSQL already considers past, so the action is genuinely due by database
  # time rather than by a clock the test supplies to the transport.
  def activated_at = Time.utc(2026, 6, 1, 10, 0, 0)
  def expires_at = activated_at + (7 * 24 * 3600)
  # An activation whose expiry PostgreSQL will not consider due for years.
  def not_yet_activated_at = Time.utc(2099, 1, 1, 10, 0, 0)

  let(:org) { TenantSeeder.create_organization }
  let(:requester) do
    TenantSeeder.create_account(organization_id: org, issuer_key: "https://id.example/oidc",
                                subject: "requester-#{SecureRandom.hex(6)}")
  end
  let(:invitation) do
    TenantSeeder.create_invitation(organization_id: org, activated_at:, requester_account_id: requester)
  end

  def worker(now: expires_at)
    Platform::ScheduledActions::Worker.new(
      registry: Platform::ScheduledActions::Registry.default,
      scheduler: Platform::ScheduledActions::Scheduler.new,
      clock: Platform::Clock.fixed(now), ids: Platform::Ids.system
    )
  end

  # Claim and execute whatever PostgreSQL says is due, as the running service
  # would. `now` is the handler-side injected clock only — the transport takes no
  # instant from anyone.
  def run_worker(now: expires_at, worker: worker(now:))
    worker.run_due_batch
  end

  def invitation_row = DbInspector.one("SELECT * FROM invitations")
  def action_row(id) = ScheduledActionHarness.row(id)
  def events = DbInspector.all("SELECT * FROM event_registry ORDER BY created_at")
  def event_body = JSON.parse(DbInspector.one("SELECT convert_from(event_bytes,'UTF8') AS body FROM event_registry")["body"])

  describe "the expiry transition" do
    it "takes the Invitation active -> expired at its exact expiry instant and completes the action" do
      inv = invitation
      outcomes = run_worker

      expect(outcomes.map(&:disposition)).to eq([:completed])
      row = invitation_row
      expect(row["state"]).to eq("expired")
      expect(row["terminated_at"]).not_to be_nil
      expect(row["transition_reason_code"]).to eq("invitation_expired")
      expect(row["state_version"].to_i).to eq(1)
      expect(action_row(inv[:scheduled_action_id])["status"]).to eq("completed")
    end

    it "emits exactly one InvitationExpired state-transition event" do
      invitation
      run_worker

      expect(events.map { |e| e["event_type"] }).to eq(["InvitationExpired"])
      event = events.first
      expect(event["event_profile"]).to eq("state_transition")
      expect(event["aggregate_type"]).to eq("invitation")
      expect(event["aggregate_version"].to_i).to eq(1)
      expect(event["workflow_id"]).to eq("WF-001")
    end

    it "carries the epoch, the state transition, the requester reference and service attribution" do
      inv = invitation
      run_worker
      body = event_body

      expect(body["from_state"]).to eq("active")
      expect(body["to_state"]).to eq("expired")
      expect(body["reason_code"]).to eq("invitation_expired")
      expect(body["transition_reason_code"]).to eq("invitation_expired")
      expect(body["organization_epoch"]).to eq(7)
      expect(body["organization_id"]).to eq(org)
      expect(body["invitation_id"]).to eq(inv[:invitation_id])
      expect(body["requester_account_id"]).to eq(requester)
      expect(body["service_identity_id"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)
      expect(body["actor_id"]).to be_nil
      expect(body["account_id"]).to be_nil
      expect(body["scheduled_action_id"]).to eq(inv[:scheduled_action_id])
    end

    it "produces event_bytes whose sha256 the database recomputes and accepts" do
      invitation
      run_worker

      row = DbInspector.one("SELECT (event_sha256 = public.digest(event_bytes,'sha256')) AS ok FROM event_registry")
      expect(row["ok"]).to eq("t")
    end

    it "attributes the durable command ledger to the service identity and never to an actor" do
      invitation
      run_worker

      ledger = DbInspector.one(<<~SQL)
        SELECT e.service_identity_id AS exec_service, e.actor_id AS exec_actor, e.action, e.command_type,
               r.service_identity_id AS result_service, r.actor_id AS result_actor, r.outcome,
               a.service_identity_id AS audit_service, a.actor_id AS audit_actor, a.to_state, a.reason_code
        FROM command_executions e
        JOIN command_results r ON r.command_execution_id = e.id
        JOIN audit_record_registry a ON a.id = r.audit_record_id
      SQL
      expect(ledger["exec_service"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)
      expect(ledger["result_service"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)
      expect(ledger["audit_service"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)
      expect(ledger.values_at("exec_actor", "result_actor", "audit_actor")).to all(be_nil)
      expect(ledger["action"]).to eq("invitation.expire")
      expect(ledger["command_type"]).to eq("wf001.expire_invitation")
      expect(ledger["outcome"]).to eq("success")
      expect(ledger["to_state"]).to eq("expired")
    end

    it "records no authorization decision: expiry is not a Role permission and uses no Permission Baseline" do
      invitation
      run_worker

      expect(DbInspector.count("authorization_decisions")).to eq(0)
      expect(DbInspector.count("pretenant_authorization_decisions")).to eq(0)
    end
  end

  describe "side effects" do
    it "creates no Account, Role Assignment, Session and consumes no receipt nonce" do
      invitation
      accounts = DbInspector.count("accounts")
      run_worker

      expect(DbInspector.count("accounts")).to eq(accounts)
      expect(DbInspector.count("role_assignments")).to eq(0)
      expect(DbInspector.count("sessions")).to eq(0)
      expect(DbInspector.count("identity_receipt_consumptions")).to eq(0)
    end

    it "mirrors the terminal state into the reference registry so the public resolver stops resolving it" do
      inv = invitation
      run_worker

      registry = DbInspector.one("SELECT * FROM invitation_reference_registry")
      expect(registry["invitation_state"]).to eq("expired")
      expect(registry["terminal_at"]).not_to be_nil

      resolved = DbInspector.all(
        "SELECT * FROM f1_resolve_invitation_reference($1, $2::timestamptz)",
        [{ value: inv[:reference_digest], format: 1 }, expires_at.iso8601(6)]
      )
      expect(resolved).to be_empty
    end
  end

  describe "due-time boundary" do
    it "does not claim or expire an Invitation whose expiry instant PostgreSQL has not reached" do
      inv = TenantSeeder.create_invitation(organization_id: org, activated_at: not_yet_activated_at,
                                           requester_account_id: requester)
      outcomes = run_worker

      expect(outcomes).to be_empty
      expect(invitation_row["state"]).to eq("active")
      expect(action_row(inv[:scheduled_action_id])["status"]).to eq("pending")
      expect(events).to be_empty
    end

    # The handler independently rechecks the product deadline at transaction time
    # (BACKGROUND_PROCESSING.md :121) against its injected clock, so an execution
    # that somehow arrives early still cannot expire anything.
    it "refuses to expire when the handler's transaction time precedes the expiry instant" do
      inv = invitation
      result = execute_directly(inv, now: expires_at - Rational(1, 1_000_000))

      expect(result.reason_code).to eq("scheduled_action_not_due")
      expect(invitation_row["state"]).to eq("active")
      expect(events).to be_empty
    end

    it "expires at equality, so an acceptance attempt at the same instant already sees no active reference" do
      inv = invitation
      resolved_at_boundary = DbInspector.all(
        "SELECT * FROM f1_resolve_invitation_reference($1, $2::timestamptz)",
        [{ value: inv[:reference_digest], format: 1 }, expires_at.iso8601(6)]
      )
      expect(resolved_at_boundary).to be_empty

      expect(run_worker.map(&:disposition)).to eq([:completed])
      expect(invitation_row["state"]).to eq("expired")
    end
  end

  describe "idempotency, independent of scheduler redelivery" do
    it "returns the stored result and emits no second event when the same action is redelivered" do
      inv = invitation
      run_worker

      # Simulate transport redelivery: recover the completed action's identity
      # and execute the handler again with the same command.
      second = execute_directly(inv)

      expect(second.replayed).to be(true)
      expect(second.payload[:state]).to eq("expired")
      expect(events.size).to eq(1)
      expect(DbInspector.count("command_executions")).to eq(1)
      expect(invitation_row["state_version"].to_i).to eq(1)
    end

    it "keeps exactly one idempotency record bound to the scheduled-action identity" do
      inv = invitation
      run_worker

      record = DbInspector.one("SELECT * FROM idempotency_records")
      expect(DbInspector.count("idempotency_records")).to eq(1)
      expect(record["command_type"]).to eq("wf001.expire_invitation")
      expect(record["target_id"]).to eq(inv[:invitation_id])
      # The idempotency key IS the action's immutable identity digest; the key
      # column stores its digest, exactly as a caller-supplied key would be.
      identity_digest = Platform::ScheduledActions::Identity.digest(action_identity(inv))
      expect(record["key_digest"].delete_prefix("\\x"))
        .to eq(Digest::SHA256.hexdigest(identity_digest))
    end
  end

  describe "already-terminal targets produce the canonical harmless result" do
    %w[accepted declined revoked expired].each do |state|
      it "does not re-terminalize or re-emit for an Invitation already #{state}" do
        inv = TenantSeeder.create_invitation(organization_id: org, activated_at:, state:,
                                             requester_account_id: requester)
        outcomes = run_worker

        expect(outcomes.map(&:disposition)).to eq([:completed])
        expect(invitation_row["state"]).to eq(state)
        expect(events).to be_empty
        expect(action_row(inv[:scheduled_action_id])["status"]).to eq("completed")
        expect(DbInspector.one("SELECT outcome, reason_code FROM command_results").values_at("outcome", "reason_code"))
          .to eq(%w[failure invitation_not_active])
      end
    end
  end

  describe "non-disclosure and fail-closed guards" do
    it "discloses nothing and changes nothing when the action names another Organization's Invitation" do
      inv = invitation
      other_org = TenantSeeder.create_organization
      result = execute_directly(inv, organization_id: other_org)

      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_not_active")
      expect(invitation_row["state"]).to eq("active")
      expect(events).to be_empty
      expect(DbInspector.count("command_executions")).to eq(0)
    end

    it "fails closed rather than expiring early when the action's due instant is not the target's expiry instant" do
      inv = invitation
      result = execute_directly(inv, due_at: expires_at - 3600)

      expect(result.reason_code).to eq("scheduled_action_target_mismatch")
      expect(invitation_row["state"]).to eq("active")
      expect(events).to be_empty
    end

    it "refuses an unsupported command schema major" do
      inv = invitation
      result = execute_directly(inv, schema_version: "2.0")

      expect(result.reason_code).to eq("command_schema_unsupported")
      expect(invitation_row["state"]).to eq("active")
    end

    it "refuses an action whose target type is not an invitation" do
      inv = invitation
      result = execute_directly(inv, target_type: "session")

      expect(result.reason_code).to eq("scheduled_action_target_mismatch")
      expect(invitation_row["state"]).to eq("active")
    end
  end

  # ---- helpers --------------------------------------------------------------

  def action_identity(inv)
    Platform::ScheduledActions::Identity.preimage(
      action_kind: "invitation_expire", action_schema_version: "1.0", organization_id: org, project_id: nil,
      target_type: "invitation", target_id: inv[:invitation_id], product_generation: 0,
      schedule_generation: 1, due_at: expires_at
    )
  end

  # Invoke the handler directly with a command built from the seeded action, so a
  # deviation the transport would never produce can still be proved to fail closed.
  def execute_directly(inv, now: expires_at, **overrides)
    digest = Platform::ScheduledActions::Identity.digest(action_identity(inv))
    command = Workflows::Wf001::Commands::ExpireInvitation.new(
      command_id: SecureRandom.uuid_v7, schema_version: "1.0", organization_id: org,
      target_type: "invitation", invitation_id: inv[:invitation_id], due_at: expires_at,
      action_id: inv[:scheduled_action_id], action_identity_sha256: digest, requested_at_utc: now
    ).with(**overrides)
    ctx = Platform::RequestContext.for_service(
      service_identity_id: Platform::ServiceIdentity.scheduled_action_executor,
      clock: Platform::Clock.fixed(now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
    )
    Workflows::Wf001::Handlers::ExpireInvitation.new.call(command:, request_context: ctx)
  end
end
