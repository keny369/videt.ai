# frozen_string_literal: true

require "rails_helper"

# What a suspension actually stops, proved against every workflow this build has.
#
# ":931 Organization is active, except that Organization reactivation/closure
# lifecycle and protected Legal Hold/deletion execution are admitted in
# suspended/closed state exactly as their contracts require." The gate is the
# SHARED authorization boundary — `CommandAuthorizer#authenticate` rejects a
# non-active Session and a non-active Organization — so no handler carries an
# `organization.suspended?` test of its own, and the matrix below is a
# consequence of that one boundary rather than of scattered checks.
RSpec.describe "WF-013 behaviour while an Organization is suspended", type: :acceptance,
               acceptance_ids: ["AC-CAP-001", "AC-CAP-013", "AC-WF-001", "AC-WF-013"],
               test_types: %w[TYP-SEC TYP-INT TYP-DATA] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)

  let(:invitee) do
    { issuer_key: "https://id.example/oidc", subject: "sub-#{SecureRandom.hex(8)}",
      email: "invitee-#{SecureRandom.hex(4)}@example.com" }
  end

  def actor_ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(fixed_now),
                                                     ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)

  def service_ctx = Platform::RequestContext.for_service(
    service_identity_id: Platform::ServiceIdentity.identity_service,
    clock: Platform::Clock.fixed(fixed_now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
  )

  # An Organization with an admin, a live Invitation and a second Session, then
  # suspended. Returns everything a suspended-state probe needs.
  def suspended_world
    admin = TenantSeeder.seed_authorized_admin(issued_at: fixed_now - 900)
    inv = create_invitation(admin)
    second = TenantSeeder.create_session(organization_id: admin[:organization_id],
                                         account_id: admin[:account_id], issued_at: fixed_now - 900)
    suspend(admin)
    { admin:, invitation: inv, second_session: second }
  end

  def create_invitation(admin, key: "inv")
    cmd = Workflows::Wf013::Commands::CreateInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      session_id: admin[:session_id], target_email: invitee[:email], target_identity_issuer_key: nil,
      target_identity_subject: nil, canonical_role: "MarketingOperator", permission_mode: "standard",
      persona: nil, scope_sha256: Digest::SHA256.digest("scope:organization"),
      intended_assignment_expires_at: nil, requested_at_utc: fixed_now
    )
    result = Workflows::Wf013::Handlers::CreateInvitation.new.call(command: cmd, request_context: actor_ctx)
    return result unless result.success?

    { result:, reference: result.payload[:invitation_reference], invitation_id: result.payload[:invitation_id] }
  end

  def suspend(admin, version: 0, epoch: 7)
    cmd = Workflows::Wf013::Commands::SuspendOrganization.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: "susp-#{SecureRandom.hex(4)}", schema_version: "1.0",
      session_id: admin[:session_id], expected_state_version: version, expected_authorization_epoch: epoch,
      reason: "suspended for suspended-state coverage", requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::SuspendOrganization.new.call(command: cmd, request_context: actor_ctx)
  end

  def receipt
    ReceiptMinter.mint_invitation_receipt(validated_at: fixed_now, issuer_key: invitee[:issuer_key],
                                          subject: invitee[:subject], normalized_email: invitee[:email])
  end

  def accept(inv)
    cmd = Workflows::Wf001::Commands::AcceptInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: "acc", schema_version: "1.0",
      invitation_reference: inv[:reference], receipt_digest: receipt[:receipt_digest],
      accepted_canonical_role: "MarketingOperator", accepted_permission_mode: "standard",
      accepted_persona: nil, accepted_scope_sha256: Digest::SHA256.digest("scope:organization"),
      supplied_account_id: nil, requested_at_utc: fixed_now
    )
    Workflows::Wf001::Handlers::AcceptInvitation.new.call(command: cmd, request_context: service_ctx)
  end

  def decline(inv)
    cmd = Workflows::Wf001::Commands::DeclineInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: "dec", schema_version: "1.0",
      invitation_reference: inv[:reference], receipt_digest: receipt[:receipt_digest],
      expected_state_version: 0, reason: nil, requested_at_utc: fixed_now
    )
    Workflows::Wf001::Handlers::DeclineInvitation.new.call(command: cmd, request_context: service_ctx)
  end

  def revoke(admin, inv, session_id: nil)
    cmd = Workflows::Wf013::Commands::RevokeInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: "rev", schema_version: "1.0",
      session_id: session_id || admin[:session_id], invitation_reference: inv[:reference],
      expected_state_version: 0, reason: "revoked while suspended for coverage", requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::RevokeInvitation.new.call(command: cmd, request_context: actor_ctx)
  end

  def invitation_state = DbInspector.one("SELECT state FROM invitations")["state"]

  describe "Session-authenticated administration is blocked at the shared boundary" do
    it "blocks CreateInvitation with a Session revoked by the suspension" do
      world = suspended_world
      result = create_invitation(world[:admin], key: "after")

      expect(result).to be_failure
      expect(result.reason_code).to eq("session_invalid")
      expect(DbInspector.count("invitations")).to eq(1)
    end

    it "blocks RevokeInvitation, including from a Session created after the suspension" do
      world = suspended_world
      fresh = TenantSeeder.create_session(organization_id: world[:admin][:organization_id],
                                          account_id: world[:admin][:account_id], issued_at: fixed_now - 900)

      expect(revoke(world[:admin], world[:invitation]).reason_code).to eq("session_invalid")
      expect(revoke(world[:admin], world[:invitation], session_id: fresh).reason_code)
        .to eq("organization_inactive")
      expect(invitation_state).to eq("active")
    end

    it "blocks DecideInvitation for the same reason" do
      admin = TenantSeeder.seed_authorized_admin(issued_at: fixed_now - 900)
      protected_inv = TenantSeeder.create_invitation(organization_id: admin[:organization_id],
                                                     state: "pending_approval", canonical_role: "OrganizationAdmin")
      suspend(admin)
      fresh = TenantSeeder.create_session(organization_id: admin[:organization_id],
                                          account_id: admin[:account_id], issued_at: fixed_now - 900)
      cmd = Workflows::Wf013::Commands::DecideInvitation.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "dec", schema_version: "1.0", session_id: fresh,
        invitation_id: protected_inv[:invitation_id], expected_state_version: 0, decision: "approve",
        reason: nil, requested_at_utc: fixed_now
      )
      result = Workflows::Wf013::Handlers::DecideInvitation.new.call(command: cmd, request_context: actor_ctx)

      expect(result.reason_code).to eq("organization_inactive")
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("pending_approval")
    end

    it "blocks a second SuspendOrganization" do
      world = suspended_world
      fresh = TenantSeeder.create_session(organization_id: world[:admin][:organization_id],
                                          account_id: world[:admin][:account_id], issued_at: fixed_now - 900)
      expect(suspend(world[:admin].merge(session_id: fresh), version: 1, epoch: 8).reason_code)
        .to eq("organization_inactive")
    end
  end

  describe "Invitations themselves are not cancelled by suspension" do
    it "leaves an active Invitation active, with its reference still resolving and its timer intact" do
      world = suspended_world

      expect(invitation_state).to eq("active")
      expect(DbInspector.one("SELECT invitation_state FROM invitation_reference_registry")["invitation_state"])
        .to eq("active")
      resolved = DbInspector.all("SELECT * FROM f1_resolve_invitation_reference($1)",
                                 [{ value: Digest::SHA256.digest(world[:invitation][:reference]), format: 1 }])
      expect(resolved.size).to eq(1)
      expect(DbInspector.all("SELECT status FROM scheduled_actions").map { |a| a["status"] }).to eq(["pending"])
    end

    it "preserves a pending-approval Invitation unchanged" do
      admin = TenantSeeder.seed_authorized_admin(issued_at: fixed_now - 900)
      inv = TenantSeeder.create_invitation(organization_id: admin[:organization_id], state: "pending_approval",
                                           canonical_role: "OrganizationAdmin")
      suspend(admin)

      row = DbInspector.one("SELECT state, approval_due_at FROM invitations WHERE id = $1::uuid",
                            [inv[:invitation_id]])
      expect(row["state"]).to eq("pending_approval")
      expect(row["approval_due_at"]).not_to be_nil
    end

    # The receipt-bound recipient responses are executed by the approved identity
    # service, not by a Session actor, and their contracts state no
    # Organization-active predicate. They therefore remain available; suspension
    # is not invitation cancellation, and the contracts nowhere invent one.
    it "still permits the recipient to accept, because acceptance is receipt-bound and not Session-authorized" do
      world = suspended_world
      expect(accept(world[:invitation])).to be_success
      expect(invitation_state).to eq("accepted")
    end

    it "still permits the recipient to decline" do
      world = suspended_world
      expect(decline(world[:invitation])).to be_success
      expect(invitation_state).to eq("declined")
    end
  end

  describe "ScheduledAction transport and the expiry handler" do
    it "keeps claiming and executing the expiry of a suspended Organization's Invitation" do
      admin = TenantSeeder.seed_authorized_admin(issued_at: Time.utc(2026, 6, 1, 9, 45, 0))
      past = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(Time.utc(2026, 6, 1, 10, 0, 0)),
                                                ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
      cmd = Workflows::Wf013::Commands::CreateInvitation.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "due", schema_version: "1.0",
        session_id: admin[:session_id], target_email: invitee[:email], target_identity_issuer_key: nil,
        target_identity_subject: nil, canonical_role: "MarketingOperator", permission_mode: "standard",
        persona: nil, scope_sha256: Digest::SHA256.digest("scope:organization"),
        intended_assignment_expires_at: nil, requested_at_utc: Time.utc(2026, 6, 1, 10, 0, 0)
      )
      created = Workflows::Wf013::Handlers::CreateInvitation.new.call(command: cmd, request_context: past)
      expires = Time.parse(created.payload[:expires_at_utc]).getutc

      susp = Workflows::Wf013::Commands::SuspendOrganization.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "s", schema_version: "1.0",
        session_id: admin[:session_id], expected_state_version: 0, expected_authorization_epoch: 7,
        reason: nil, requested_at_utc: Time.utc(2026, 6, 1, 10, 0, 0)
      )
      expect(Workflows::Wf013::Handlers::SuspendOrganization.new.call(command: susp, request_context: past))
        .to be_success

      # Expiry is a service lifecycle transition, not a Session-authorized command:
      # the timer is transport authority, and ":242 Active expiry is exactly seven
      # days after activation" has no suspension exception. Stopping it would leave
      # the Invitation active past its ratified boundary.
      worker = Platform::ScheduledActions::Worker.new(
        registry: Platform::ScheduledActions::Registry.default,
        scheduler: Platform::ScheduledActions::Scheduler.new,
        clock: Platform::Clock.fixed(expires), ids: Platform::Ids.system
      )
      expect(worker.run_due_batch.map(&:disposition)).to eq([:completed])
      expect(invitation_state).to eq("expired")
      expect(DbInspector.all("SELECT event_type FROM event_registry").map { |e| e["event_type"] })
        .to include("InvitationExpired")
    end

    it "gives the platform worker no tenant read authority of its own" do
      suspended_world
      expect do
        ScheduledActionHarness.as_role("f1_platform_worker") { |pg| pg.exec("SELECT count(*) FROM invitations") }
      end.to raise_error(PG::InsufficientPrivilege, /permission denied/i)
      expect do
        ScheduledActionHarness.as_role("f1_platform_worker") { |pg| pg.exec("SELECT count(*) FROM organizations") }
      end.to raise_error(PG::InsufficientPrivilege, /permission denied/i)
    end
  end

  describe "suspension does not rewrite grants" do
    it "leaves Accounts and Role Assignments untouched" do
      world = suspended_world

      expect(DbInspector.all("SELECT status FROM accounts").map { |a| a["status"] }).to all(eq("active"))
      expect(DbInspector.all("SELECT status FROM role_assignments").map { |r| r["status"] }).to all(eq("active"))
      expect(world[:admin][:account_id]).not_to be_nil
    end

    it "keeps historical command, event and audit records queryable" do
      suspended_world

      expect(DbInspector.count("command_executions")).to be >= 2
      expect(DbInspector.count("command_results")).to be >= 2
      expect(DbInspector.count("audit_record_registry")).to be >= 2
      expect(DbInspector.count("authorization_decisions")).to be >= 2
    end
  end
end
