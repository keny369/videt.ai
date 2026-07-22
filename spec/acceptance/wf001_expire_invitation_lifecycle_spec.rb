# frozen_string_literal: true

require "rails_helper"

# Cross-workflow Invitation-lifecycle coverage for the timed expiry transition
# against the other three terminal transitions — receipt-bound acceptance and
# decline (WF-001) and the Session-authenticated administrator revoke (WF-013) —
# plus the ScheduledAction recovery paths that carry it.
#
# Volume I fixes the shape: "Decline, rejection, revocation, expiry, and
# acceptance are terminal" and "concurrent accept/decline/expiry has one winner
# under current state, with expiry winning at equality"
# (WORKFLOW_SPECIFICATIONS.md :242,:250). All four commands serialize on the same
# per-invitation advisory lock, so the winner is decided by current state under
# that lock and never by arrival order at a queue.
#
# The races here are the real ones: a recipient or administrator acting a
# microsecond before the boundary against the timer firing at it. At the boundary
# itself the reference resolver already refuses to resolve, so expiry wins at
# equality without a race at all — that is asserted separately.
#
# Time is controlled throughout; nothing sleeps.
RSpec.describe "WF-001 expire invitation lifecycle (expire vs accept/decline/revoke)", type: :acceptance,
               acceptance_ids: ["AC-CAP-001", "AC-WF-001", "AC-WF-013"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def activated_at = Time.utc(2026, 7, 18, 10, 0, 0)
  def expires_at = activated_at + (7 * 24 * 3600)   # 2026-07-25 10:00:00Z
  def just_before = expires_at - Rational(1, 1_000_000)

  let(:service_id) { SecureRandom.uuid_v7 }
  let(:invitee) do
    { issuer_key: "https://id.example/oidc", subject: "sub-#{SecureRandom.hex(8)}",
      email: "invitee-#{SecureRandom.hex(4)}@example.com" }
  end

  # An authorized admin whose Session is live a microsecond before the boundary,
  # plus an active Invitation targeted at `invitee` with its expiry timer.
  def seed
    admin = TenantSeeder.seed_authorized_admin(issued_at: expires_at - 900)
    inv = TenantSeeder.create_invitation(organization_id: admin[:organization_id], activated_at:,
                                         target_email: invitee[:email], requester_account_id: admin[:account_id])
    [admin, inv]
  end

  def receipt_for(validated_at: just_before)
    ReceiptMinter.mint_invitation_receipt(validated_at:, issuer_key: invitee[:issuer_key],
                                          subject: invitee[:subject], normalized_email: invitee[:email])
  end

  def service_context(now)
    Platform::RequestContext.for_service(service_identity_id: service_id, clock: Platform::Clock.fixed(now),
                                         ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
  end

  def actor_context(now)
    Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(now), ids: Platform::Ids.system,
                                       correlation_id: SecureRandom.uuid_v7)
  end

  def accept(inv, receipt, key: "acc", now: just_before)
    cmd = Workflows::Wf001::Commands::AcceptInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      invitation_reference: inv[:reference], receipt_digest: receipt[:receipt_digest],
      accepted_canonical_role: inv[:canonical_role], accepted_permission_mode: inv[:permission_mode],
      accepted_persona: inv[:persona], accepted_scope_sha256: inv[:scope_sha256],
      supplied_account_id: nil, requested_at_utc: now
    )
    Workflows::Wf001::Handlers::AcceptInvitation.new.call(command: cmd, request_context: service_context(now))
  end

  def decline(inv, receipt, key: "dec", now: just_before)
    cmd = Workflows::Wf001::Commands::DeclineInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      invitation_reference: inv[:reference], receipt_digest: receipt[:receipt_digest],
      expected_state_version: 0, reason: nil, requested_at_utc: now
    )
    Workflows::Wf001::Handlers::DeclineInvitation.new.call(command: cmd, request_context: service_context(now))
  end

  def revoke(admin, inv, key: "rev", now: just_before)
    cmd = Workflows::Wf013::Commands::RevokeInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      session_id: admin[:session_id], invitation_reference: inv[:reference],
      expected_state_version: 0, reason: "revoked for lifecycle coverage", requested_at_utc: now
    )
    Workflows::Wf013::Handlers::RevokeInvitation.new.call(command: cmd, request_context: actor_context(now))
  end

  def new_worker(now: expires_at)
    Platform::ScheduledActions::Worker.new(
      registry: Platform::ScheduledActions::Registry.default,
      scheduler: Platform::ScheduledActions::Scheduler.new,
      clock: Platform::Clock.fixed(now), ids: Platform::Ids.system
    )
  end

  def expire(now: expires_at, worker: new_worker(now:)) = worker.run_due_batch(now:)

  def invitation_state = DbInspector.one("SELECT state FROM invitations")["state"]
  def action_status(id) = ScheduledActionHarness.row(id)["status"]

  def terminal_events
    DbInspector.all(<<~SQL).map { |r| r["event_type"] }
      SELECT event_type FROM event_registry
      WHERE event_type IN ('InvitationAccepted','InvitationDeclined','InvitationRevoked','InvitationExpired')
    SQL
  end

  # Two commands, concurrently, on separate pooled connections.
  def race(first, second)
    [Thread.new { ActiveRecord::Base.connection_pool.with_connection { first.call } },
     Thread.new { ActiveRecord::Base.connection_pool.with_connection { second.call } }].map(&:value)
  end

  describe "concurrency — exactly one terminal transition wins" do
    it "expire vs expire: two workers over one due batch expire once and emit one event" do
      _admin, inv = seed
      a = new_worker
      b = new_worker

      outcomes = race(-> { a.run_due_batch(now: expires_at) }, -> { b.run_due_batch(now: expires_at) }).flatten

      expect(outcomes.count { |o| o.disposition == :completed }).to eq(1)
      expect(invitation_state).to eq("expired")
      expect(terminal_events).to eq(["InvitationExpired"])
      expect(action_status(inv[:scheduled_action_id])).to eq("completed")
    end

    it "expire vs expire: a duplicate delivery of the same action replays the stored result and emits nothing new" do
      _admin, inv = seed
      digest = Platform::ScheduledActions::Identity.digest(action_identity(inv))
      command = expire_command(inv, digest)

      results = race(-> { run_expire_handler(command) }, -> { run_expire_handler(command) })

      expect(results.count(&:success?)).to eq(2)          # one commit, one exact replay
      expect(results.count { |r| r.replayed }).to eq(1)
      expect(terminal_events).to eq(["InvitationExpired"])
      expect(DbInspector.count("command_executions")).to eq(1)
    end

    it "expire vs accept: one terminal transition, with acceptance side effects only when accept wins" do
      _admin, inv = seed
      receipt = receipt_for
      accounts_before = DbInspector.count("accounts")
      sessions_before = DbInspector.count("sessions")

      expire_outcomes, accepted = race(-> { expire }, -> { accept(inv, receipt) })

      state = invitation_state
      if state == "accepted"
        expect(accepted).to be_success
        expect(expire_outcomes.first.reason).to eq("invitation_not_active")
      else
        expect(accepted).to be_failure
        expect(accepted.reason_code).to eq("invitation_not_active")
        expect(expire_outcomes.first.reason).to be_nil
      end
      expect(state).to be_in(%w[expired accepted])
      expect(terminal_events).to eq([state == "accepted" ? "InvitationAccepted" : "InvitationExpired"])

      if state == "accepted"
        expect(DbInspector.count("accounts")).to eq(accounts_before + 1)
        expect(DbInspector.count("sessions")).to eq(sessions_before + 1)
        expect(DbInspector.count("role_assignments")).to eq(2)   # admin + invitee
      else
        expect(DbInspector.count("accounts")).to eq(accounts_before)
        expect(DbInspector.count("sessions")).to eq(sessions_before)
        expect(DbInspector.count("role_assignments")).to eq(1)   # admin only
      end
      expect(action_status(inv[:scheduled_action_id])).to eq("completed")
    end

    it "expire vs decline: one terminal transition and one event" do
      _admin, inv = seed
      receipt = receipt_for

      race(-> { expire }, -> { decline(inv, receipt) })

      state = invitation_state
      expect(state).to be_in(%w[expired declined])
      expect(terminal_events).to eq([state == "declined" ? "InvitationDeclined" : "InvitationExpired"])
      expect(action_status(inv[:scheduled_action_id])).to eq("completed")
    end

    it "expire vs revoke: one terminal transition and one event" do
      admin, inv = seed

      race(-> { expire }, -> { revoke(admin, inv) })

      state = invitation_state
      expect(state).to be_in(%w[expired revoked])
      expect(terminal_events).to eq([state == "revoked" ? "InvitationRevoked" : "InvitationExpired"])
      expect(action_status(inv[:scheduled_action_id])).to eq("completed")
    end
  end

  describe "expiry wins at equality" do
    it "refuses acceptance and decline at the exact expiry instant, before the timer has even run" do
      _admin, inv = seed
      receipt = receipt_for(validated_at: expires_at)

      accepted = accept(inv, receipt, now: expires_at)
      declined = decline(inv, receipt, key: "dec2", now: expires_at)

      expect(accepted).to be_failure
      expect(accepted.reason_code).to eq("invitation_not_active")
      expect(declined).to be_failure
      expect(declined.reason_code).to eq("invitation_not_active")
      expect(invitation_state).to eq("active")
      expect(terminal_events).to be_empty

      expect(expire.map(&:disposition)).to eq([:completed])
      expect(invitation_state).to eq("expired")
      expect(terminal_events).to eq(["InvitationExpired"])
    end
  end

  describe "a terminal Invitation never reopens" do
    it "accept, decline and revoke after expiry all return invitation_not_active and change nothing" do
      admin, inv = seed
      expect(expire.map(&:disposition)).to eq([:completed])
      accounts = DbInspector.count("accounts")
      sessions = DbInspector.count("sessions")

      [accept(inv, receipt_for), decline(inv, receipt_for, key: "d2"), revoke(admin, inv)].each do |result|
        expect(result).to be_failure
        expect(result.reason_code).to eq("invitation_not_active")
      end

      expect(invitation_state).to eq("expired")
      expect(terminal_events).to eq(["InvitationExpired"])
      expect(DbInspector.count("accounts")).to eq(accounts)
      expect(DbInspector.count("sessions")).to eq(sessions)
    end

    it "expiry after a winning accept, decline or revoke completes harmlessly without a second event" do
      [:accept, :decline, :revoke].each do |winner|
        ReceiptMinter.truncate_all
        admin, inv = seed
        first = case winner
                when :accept then accept(inv, receipt_for)
                when :decline then decline(inv, receipt_for)
                else revoke(admin, inv)
                end
        expect(first).to be_success, "#{winner} should have won"
        events_after_winner = terminal_events

        outcomes = expire

        expect(outcomes.map(&:disposition)).to eq([:completed])
        expect(terminal_events).to eq(events_after_winner)
        expect(invitation_state).not_to eq("expired")
        expect(action_status(inv[:scheduled_action_id])).to eq("completed")
      end
    end
  end

  describe "ScheduledAction recovery around the real transition" do
    it "recovers a worker lost after claiming, then expires exactly once" do
      _admin, inv = seed
      scheduler = Platform::ScheduledActions::Scheduler.new
      scheduler.claim_due(now: expires_at)              # the process dies here
      expect(invitation_state).to eq("active")

      expect(scheduler.recover_expired_leases(now: expires_at + 31)).to eq(1)
      expect(expire(now: expires_at + 31).map(&:disposition)).to eq([:completed])
      expect(terminal_events).to eq(["InvitationExpired"])
      expect(action_status(inv[:scheduled_action_id])).to eq("completed")
    end

    it "recovers a worker lost after the expiry committed, and the re-execution emits nothing new" do
      _admin, inv = seed
      scheduler = Platform::ScheduledActions::Scheduler.new
      worker = Platform::ScheduledActions::Worker.new(
        registry: Platform::ScheduledActions::Registry.default, scheduler:,
        clock: Platform::Clock.fixed(expires_at), ids: Platform::Ids.system
      )
      action = scheduler.claim_due(now: expires_at).first
      ScheduledActionHarness.transport_store do |store|
        store.dispatch(action_id: action.id, expected_owner: scheduler.owner,
                       expected_generation: action.claim_generation, worker_owner: worker.owner,
                       now: expires_at)
      end
      # The product effect commits; the process dies before recording completion.
      run_expire_handler(expire_command(inv, Platform::ScheduledActions::Identity.digest(action_identity(inv))))
      expect(invitation_state).to eq("expired")
      expect(action_status(inv[:scheduled_action_id])).to eq("dispatched")

      expect(scheduler.recover_expired_leases(now: expires_at + 31)).to eq(1)
      expect(expire(now: expires_at + 31).map(&:disposition)).to eq([:completed])

      expect(terminal_events).to eq(["InvitationExpired"])
      expect(DbInspector.count("command_executions")).to eq(1)
      expect(action_status(inv[:scheduled_action_id])).to eq("completed")
    end

    it "releases the claim after a transient handler failure and expires exactly once on the retry" do
      _admin, inv = seed
      attempts = 0
      flaky = Class.new do
        define_method(:call) do |command:, request_context:|
          attempts += 1
          raise "transient dependency failure" if attempts == 1

          Workflows::Wf001::Handlers::ExpireInvitation.new.call(command:, request_context:)
        end
      end
      registry = Platform::ScheduledActions::Registry.new.register(
        action_kind: "invitation_expire", action_schema_version: "1.0", operation: "ExpireInvitation",
        handler: flaky, command: Workflows::Wf001::Commands::ExpireInvitation
      )
      worker = Platform::ScheduledActions::Worker.new(
        registry:, scheduler: Platform::ScheduledActions::Scheduler.new,
        clock: Platform::Clock.fixed(expires_at), ids: Platform::Ids.system
      )

      expect(worker.run_due_batch(now: expires_at).map(&:disposition)).to eq([:released])
      expect(invitation_state).to eq("active")
      expect(terminal_events).to be_empty
      released = ScheduledActionHarness.row(inv[:scheduled_action_id])
      expect(released.values_at("status", "reason")).to eq(%w[pending scheduled_action_execution_failed])

      expect(worker.run_due_batch(now: expires_at).map(&:disposition)).to eq([:completed])
      expect(invitation_state).to eq("expired")
      expect(terminal_events).to eq(["InvitationExpired"])
      expect(attempts).to eq(2)
    end

    it "leaves the Invitation untouched when the action is quarantined for an unregistered kind" do
      _admin, inv = seed
      empty_registry = Platform::ScheduledActions::Registry.new
      worker = Platform::ScheduledActions::Worker.new(
        registry: empty_registry, scheduler: Platform::ScheduledActions::Scheduler.new,
        clock: Platform::Clock.fixed(expires_at), ids: Platform::Ids.system
      )

      outcomes = worker.run_due_batch(now: expires_at)

      expect(outcomes.map(&:reason)).to eq(["scheduled_work_mapping_mismatch"])
      expect(invitation_state).to eq("active")
      expect(terminal_events).to be_empty
      expect(action_status(inv[:scheduled_action_id])).to eq("quarantined")
    end
  end

  describe "cross-Organization isolation" do
    it "expires only the Organization whose action is due, and neither reveals nor touches the other" do
      _admin_a, inv_a = seed
      org_b = TenantSeeder.create_organization
      inv_b = TenantSeeder.create_invitation(organization_id: org_b, activated_at: activated_at + 3600)

      expect(expire.map(&:disposition)).to eq([:completed])

      states = DbInspector.all("SELECT id, state FROM invitations").to_h { |r| [r["id"], r["state"]] }
      expect(states[inv_a[:invitation_id]]).to eq("expired")
      expect(states[inv_b[:invitation_id]]).to eq("active")
      expect(action_status(inv_b[:scheduled_action_id])).to eq("pending")
      expect(DbInspector.all("SELECT organization_id FROM event_registry").map { |r| r["organization_id"] })
        .to eq([inv_a[:organization_id]])
    end
  end

  # ---- helpers --------------------------------------------------------------

  def action_identity(inv)
    Platform::ScheduledActions::Identity.preimage(
      action_kind: "invitation_expire", action_schema_version: "1.0",
      organization_id: inv[:organization_id], project_id: nil, target_type: "invitation",
      target_id: inv[:invitation_id], product_generation: 0, schedule_generation: 1, due_at: inv[:expires_at]
    )
  end

  def expire_command(inv, digest)
    Workflows::Wf001::Commands::ExpireInvitation.new(
      command_id: SecureRandom.uuid_v7, schema_version: "1.0", organization_id: inv[:organization_id],
      target_type: "invitation", invitation_id: inv[:invitation_id], due_at: inv[:expires_at],
      action_id: inv[:scheduled_action_id], action_identity_sha256: digest, requested_at_utc: expires_at
    )
  end

  def run_expire_handler(command, now: expires_at)
    ctx = Platform::RequestContext.for_service(
      service_identity_id: Platform::ServiceIdentity.scheduled_action_executor,
      clock: Platform::Clock.fixed(now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
    )
    Workflows::Wf001::Handlers::ExpireInvitation.new.call(command:, request_context: ctx)
  end
end
