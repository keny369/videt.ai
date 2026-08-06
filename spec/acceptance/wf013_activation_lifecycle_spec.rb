# frozen_string_literal: true

require "rails_helper"

# Activation as the entry point of the whole Invitation lifecycle, and the
# invariants that hold once it is the only way in.
#
# The earlier tranches proved the terminal transitions against each other with
# seeded Invitations. This proves them against a REAL created one, and proves the
# structural properties that only become assertable once a production path exists:
# every active Invitation owns exactly one timer, every timer points at one
# Invitation, activation is the only creator, and no terminal transition creates
# or mutates a timer.
RSpec.describe "WF-013 invitation activation lifecycle", type: :acceptance,
               acceptance_ids: ["AC-CAP-001", "AC-CAP-013", "AC-WF-001", "AC-WF-013"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = (@fixed_now ||= (TenantSeeder.db_now - (3 * 24 * 3600)).floor(6))

  let(:admin) { TenantSeeder.seed_authorized_admin(issued_at: fixed_now - 900) }
  let(:invitee) do
    { issuer_key: "https://id.example/oidc", subject: "sub-#{SecureRandom.hex(8)}",
      email: "invitee-#{SecureRandom.hex(4)}@example.com" }
  end

  def actor_ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(fixed_now),
                                                     ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)

  def service_ctx(now = fixed_now)
    Platform::RequestContext.for_service(service_identity_id: Platform::ServiceIdentity.identity_service,
                                         clock: Platform::Clock.fixed(now), ids: Platform::Ids.system,
                                         correlation_id: SecureRandom.uuid_v7)
  end

  # Create a real, active Invitation and return the live result plus its row.
  def create(key: "inv", role: "MarketingOperator", session_id: admin[:session_id])
    cmd = Workflows::Wf013::Commands::CreateInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id:,
      target_email: invitee[:email], target_identity_issuer_key: nil, target_identity_subject: nil,
      canonical_role: role, permission_mode: "standard", persona: nil,
      scope_sha256: Digest::SHA256.digest("scope:organization"),
      intended_assignment_expires_at: nil, requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::CreateInvitation.new.call(command: cmd, request_context: actor_ctx)
  end

  def created
    result = create
    raise "creation failed: #{result.reason_code}" unless result.success?

    { result:, reference: result.payload[:invitation_reference],
      invitation_id: result.payload[:invitation_id],
      canonical_role: "MarketingOperator", permission_mode: "standard", persona: nil,
      scope_sha256: Digest::SHA256.digest("scope:organization") }
  end

  def receipt
    ReceiptMinter.mint_invitation_receipt(validated_at: fixed_now, issuer_key: invitee[:issuer_key],
                                          subject: invitee[:subject], normalized_email: invitee[:email])
  end

  def accept(inv, key: "acc")
    cmd = Workflows::Wf001::Commands::AcceptInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      invitation_reference: inv[:reference], receipt_digest: receipt[:receipt_digest],
      accepted_canonical_role: inv[:canonical_role], accepted_permission_mode: inv[:permission_mode],
      accepted_persona: inv[:persona], accepted_scope_sha256: inv[:scope_sha256],
      supplied_account_id: nil, requested_at_utc: fixed_now
    )
    Workflows::Wf001::Handlers::AcceptInvitation.new.call(command: cmd, request_context: service_ctx)
  end

  def decline(inv, key: "dec")
    cmd = Workflows::Wf001::Commands::DeclineInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      invitation_reference: inv[:reference], receipt_digest: receipt[:receipt_digest],
      expected_state_version: 0, reason: nil, requested_at_utc: fixed_now
    )
    Workflows::Wf001::Handlers::DeclineInvitation.new.call(command: cmd, request_context: service_ctx)
  end

  def revoke(inv, key: "rev")
    cmd = Workflows::Wf013::Commands::RevokeInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      session_id: admin[:session_id], invitation_reference: inv[:reference], expected_state_version: 0,
      reason: "revoked in activation lifecycle coverage", requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::RevokeInvitation.new.call(command: cmd, request_context: actor_ctx)
  end

  # An Invitation created far enough in the past that PostgreSQL — the sole
  # due-time authority — already considers its timer due. A live Invitation
  # (`created`) necessarily has a FUTURE expiry, so its reference resolves and it
  # can be accepted or declined; the two cases cannot be the same fixture.
  def past_now = Time.utc(2026, 6, 1, 10, 0, 0)

  def created_due
    seeded = TenantSeeder.seed_authorized_admin(issued_at: past_now - 900)
    cmd = Workflows::Wf013::Commands::CreateInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: "due", schema_version: "1.0",
      session_id: seeded[:session_id], target_email: invitee[:email], target_identity_issuer_key: nil,
      target_identity_subject: nil, canonical_role: "MarketingOperator", permission_mode: "standard",
      persona: nil, scope_sha256: Digest::SHA256.digest("scope:organization"),
      intended_assignment_expires_at: nil, requested_at_utc: past_now
    )
    ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(past_now),
                                             ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
    result = Workflows::Wf013::Handlers::CreateInvitation.new.call(command: cmd, request_context: ctx)
    raise "creation failed: #{result.reason_code}" unless result.success?

    { invitation_id: result.payload[:invitation_id], expires_at: Time.parse(result.payload[:expires_at_utc]).getutc }
  end

  def worker_at(now)
    Platform::ScheduledActions::Worker.new(
      registry: Platform::ScheduledActions::Registry.default,
      scheduler: Platform::ScheduledActions::Scheduler.new,
      clock: Platform::Clock.fixed(now), ids: Platform::Ids.system
    )
  end

  def state(id = nil)
    id ? DbInspector.one("SELECT state FROM invitations WHERE id = $1::uuid", [id])["state"]
       : DbInspector.one("SELECT state FROM invitations")["state"]
  end

  def actions = DbInspector.all("SELECT * FROM scheduled_actions")
  def terminal_events
    DbInspector.all(<<~SQL).map { |r| r["event_type"] }
      SELECT event_type FROM event_registry
      WHERE event_type IN ('InvitationAccepted','InvitationDeclined','InvitationRevoked','InvitationExpired')
    SQL
  end

  describe "activation is the entry point of every terminal transition" do
    it "activation -> accept: the created Invitation is accepted and its timer is left untouched" do
      inv = created
      timer = actions.first
      expect(accept(inv)).to be_success

      expect(state).to eq("accepted")
      expect(terminal_events).to eq(["InvitationAccepted"])
      # The timer is not yet due and acceptance neither cancels nor mutates it;
      # it will complete harmlessly when it fires.
      expect(actions.size).to eq(1)
      expect(actions.first["status"]).to eq("pending")
      expect(actions.first["id"]).to eq(timer["id"])
    end

    it "activation -> decline" do
      inv = created
      expect(decline(inv)).to be_success
      expect(state).to eq("declined")
      expect(terminal_events).to eq(["InvitationDeclined"])
    end

    it "activation -> revoke" do
      inv = created
      expect(revoke(inv)).to be_success
      expect(state).to eq("revoked")
      expect(terminal_events).to eq(["InvitationRevoked"])
    end

    it "activation -> expire: the timer created at activation expires its own Invitation" do
      inv = created_due

      expect(worker_at(inv[:expires_at]).run_due_batch.map(&:disposition)).to eq([:completed])
      expect(state(inv[:invitation_id])).to eq("expired")
      expect(terminal_events).to eq(["InvitationExpired"])
      expect(actions.map { |a| a["status"] }).to eq(["completed"])
    end

    it "activation -> accept -> expire: the timer completes harmlessly when acceptance won first" do
      inv = created_due
      # The reference is already past its expiry instant, so acceptance is
      # correctly refused; the Invitation is terminalized by its own timer.
      expect(worker_at(inv[:expires_at]).run_due_batch.map(&:disposition)).to eq([:completed])
      expect(worker_at(inv[:expires_at]).run_due_batch).to be_empty
      expect(state(inv[:invitation_id])).to eq("expired")
      expect(terminal_events).to eq(["InvitationExpired"])
    end
  end

  describe "activation rollback, replay and concurrency" do
    it "leaves neither the Invitation nor a timer when the creating transaction fails" do
      # An offer whose Account is ineligible fails after authorization: the
      # command's transaction commits only its audited no-state outcome.
      TenantSeeder.create_account(organization_id: admin[:organization_id], issuer_key: "https://id.example/oidc",
                                  subject: "ineligible-#{SecureRandom.hex(4)}", email: invitee[:email],
                                  status: "suspended")
      result = create

      expect(result.reason_code).to eq("invitation_account_ineligible")
      expect(DbInspector.count("invitations")).to eq(0)
      expect(actions).to be_empty
    end

    it "creates exactly one timer across an exact replay" do
      first = create(key: "same")
      replay = create(key: "same")

      expect(replay.replayed).to be(true)
      expect(replay.payload[:invitation_id]).to eq(first.payload[:invitation_id])
      expect(actions.size).to eq(1)
    end

    it "creates exactly one Invitation and one timer when two identical creations race" do
      results = [1, 2].map do |i|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection { create(key: "race-#{i}") }
        end
      end.map(&:value)

      expect(results.count(&:success?)).to eq(1)
      expect(results.find(&:failure?).reason_code).to eq("invitation_duplicate_open")
      expect(DbInspector.count("invitations")).to eq(1)
      expect(actions.size).to eq(1)
    end

    it "creates no timer when the expected-version-protected approval is refused" do
      pending_inv = TenantSeeder.create_invitation(organization_id: admin[:organization_id],
                                                   state: "pending_approval", canonical_role: "OrganizationAdmin")
      security = TenantSeeder.create_account(organization_id: admin[:organization_id],
                                             issuer_key: "https://id.example/oidc",
                                             subject: "sec-#{SecureRandom.hex(4)}")
      TenantSeeder.create_role_assignment(organization_id: admin[:organization_id], account_id: security,
                                          canonical_role: "SecurityOperator",
                                          protected_permission_allowlist: ["invitation.approve"])
      session = TenantSeeder.create_session(organization_id: admin[:organization_id], account_id: security,
                                            issued_at: fixed_now - 900)
      cmd = Workflows::Wf013::Commands::DecideInvitation.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "stale", schema_version: "1.0", session_id: session,
        invitation_id: pending_inv[:invitation_id], expected_state_version: 9, decision: "approve",
        reason: nil, requested_at_utc: fixed_now
      )
      result = Workflows::Wf013::Handlers::DecideInvitation.new.call(command: cmd, request_context: actor_ctx)

      expect(result.reason_code).to eq("stale_state_version")
      expect(state(pending_inv[:invitation_id])).to eq("pending_approval")
      expect(actions).to be_empty
    end
  end

  describe "invariants once activation is the only way in" do
    it "gives every active Invitation exactly one timer at its own expiry instant" do
      # THE ROLES ARE DERIVED, BECAUSE THE FIXTURE USED TO ASSUME THEM (FU-54).
      #
      # This example seeded `MarketingOperator`, `TechnicalImplementer` and `BillingOperator` and
      # asserted three timers. When `:333`'s protected-grant enumeration was transcribed in full,
      # BillingOperator became a PROTECTED role, its Invitation correctly went to approval instead
      # of activating, and this example failed on the count — not because the invariant broke, but
      # because the fixture had hard-coded a classification it does not own. Only a directly
      # activatable Invitation gets an activation timer, so the population is derived from the
      # ratified enumeration and the expected count derived with it.
      roles = RatifiedPermissionBaseline.canonical_role_columns -
              RatifiedPermissionBaseline.protected_canonical_roles
      expect(roles.size).to be >= 2, "fewer than two non-protected canonical roles remain, so this " \
                                     "invariant is no longer exercised across roles"
      roles.each_with_index { |role, i| create(key: "inv-#{i}", role:) }

      mismatched = DbInspector.all(<<~SQL)
        SELECT i.id FROM invitations i
        WHERE i.activated_at IS NOT NULL
          AND (SELECT count(*) FROM scheduled_actions a
               WHERE a.action_kind = 'invitation_expire' AND a.target_type = 'invitation'
                 AND a.target_id = i.id AND a.organization_id = i.organization_id
                 AND a.due_at = i.expires_at) <> 1
      SQL
      expect(mismatched).to be_empty
      expect(actions.size).to eq(roles.size)
    end

    it "points every timer at exactly one Invitation in its own Organization" do
      create(key: "a")
      other = TenantSeeder.seed_authorized_admin(issued_at: fixed_now - 900)
      TenantSeeder.create_invitation(organization_id: other[:organization_id])

      dangling = DbInspector.all(<<~SQL)
        SELECT a.id FROM scheduled_actions a
        WHERE a.action_kind = 'invitation_expire'
          AND (SELECT count(*) FROM invitations i
               WHERE i.id = a.target_id AND i.organization_id = a.organization_id) <> 1
      SQL
      expect(dangling).to be_empty
    end

    it "creates no further timer, and mutates no timer identity, on any terminal transition" do
      inv = created
      before = actions.first
      expect(revoke(inv)).to be_success
      after = actions

      expect(after.size).to eq(1)
      expect(after.first.values_at("id", "identity_sha256", "due_at", "target_id", "action_kind"))
        .to eq(before.values_at("id", "identity_sha256", "due_at", "target_id", "action_kind"))
    end

    it "keeps a rejected protected Invitation timerless, so approval alone creates one" do
      inv = TenantSeeder.create_invitation(organization_id: admin[:organization_id], state: "pending_approval",
                                           canonical_role: "OrganizationAdmin", with_expiry_action: false)
      expect(actions).to be_empty
      expect(state(inv[:invitation_id])).to eq("pending_approval")
    end
  end
end
