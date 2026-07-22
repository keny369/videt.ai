# frozen_string_literal: true

require "rails_helper"

# Cross-workflow invitation-lifecycle coverage for the revoke terminal transition
# (WF-013) against the receipt-bound recipient transitions accept and decline
# (WF-001). Verifies the shared state-model invariants (WORKFLOW_SPECIFICATIONS.md
# :242,:246,:965) across two different actor models — a Session-authenticated
# Organization actor (revoke) and a receipt-bound recipient (accept/decline) — which
# serialize on the same per-Invitation advisory lock: only one terminal transition
# wins under concurrency; exactly one terminal Invitation event; acceptance side
# effects exist only when accept wins; a terminal Invitation never reopens and stays
# non-disclosing; and the revoke winner replays exactly while a loser of another
# workflow cannot replay as the revoke's result.
RSpec.describe "WF-013 revoke invitation lifecycle (revoke vs accept/decline)", type: :acceptance,
               acceptance_ids: ["AC-CAP-013", "AC-WF-013"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  # The approved identity/bootstrap service is a registered principal, not a
  # value each caller invents (WORKFLOW_SPECIFICATIONS.md § onboarding-interim-v1).
  let(:service_id) { Platform::ServiceIdentity.identity_service }
  let(:invitee) do
    { issuer_key: "https://id.example/oidc", subject: "sub-#{SecureRandom.hex(8)}",
      email: "invitee-#{SecureRandom.hex(4)}@example.com" }
  end

  def actor_context
    Platform::RequestContext.for_actor(
      clock: Platform::Clock.fixed(fixed_now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
    )
  end

  def service_context
    Platform::RequestContext.for_service(
      service_identity_id: service_id, clock: Platform::Clock.fixed(fixed_now),
      ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
    )
  end

  # An authorized admin plus an active Invitation targeted at `invitee`, in one
  # Organization. Returns [admin_hash, invitation_hash].
  def seed
    admin = TenantSeeder.seed_authorized_admin
    inv = TenantSeeder.create_invitation(organization_id: admin[:organization_id],
                                         target_email: invitee[:email], requester_account_id: admin[:account_id])
    [admin, inv]
  end

  def receipt_for
    ReceiptMinter.mint_invitation_receipt(validated_at: fixed_now, issuer_key: invitee[:issuer_key],
                                          subject: invitee[:subject], normalized_email: invitee[:email])
  end

  def revoke(admin, inv, key: "rev", ctx: actor_context)
    cmd = Workflows::Wf013::Commands::RevokeInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      session_id: admin[:session_id], invitation_reference: inv[:reference],
      expected_state_version: 0, reason: "revoked for lifecycle coverage", requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::RevokeInvitation.new.call(command: cmd, request_context: ctx)
  end

  def accept(inv, receipt, key: "acc", ctx: service_context)
    cmd = Workflows::Wf001::Commands::AcceptInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      invitation_reference: inv[:reference], receipt_digest: receipt[:receipt_digest],
      accepted_canonical_role: inv[:canonical_role], accepted_permission_mode: inv[:permission_mode],
      accepted_persona: inv[:persona], accepted_scope_sha256: inv[:scope_sha256],
      supplied_account_id: nil, requested_at_utc: fixed_now
    )
    Workflows::Wf001::Handlers::AcceptInvitation.new.call(command: cmd, request_context: ctx)
  end

  def decline(inv, receipt, key: "dec", ctx: service_context)
    cmd = Workflows::Wf001::Commands::DeclineInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      invitation_reference: inv[:reference], receipt_digest: receipt[:receipt_digest],
      expected_state_version: 0, reason: nil, requested_at_utc: fixed_now
    )
    Workflows::Wf001::Handlers::DeclineInvitation.new.call(command: cmd, request_context: ctx)
  end

  def invitation_state = DbInspector.one("SELECT state FROM invitations")["state"]

  def terminal_events
    DbInspector.all(<<~SQL).map { |r| r["event_type"] }
      SELECT event_type FROM event_registry
      WHERE event_type IN ('InvitationAccepted','InvitationDeclined','InvitationRevoked')
    SQL
  end

  # concurrency runner: two commands, separate pooled connections
  def race(first, second)
    [Thread.new { ActiveRecord::Base.connection_pool.with_connection { first.call } },
     Thread.new { ActiveRecord::Base.connection_pool.with_connection { second.call } }].map(&:value)
  end

  describe "concurrency — exactly one terminal transition wins" do
    it "two concurrent revokes of one Invitation commit exactly one revoke and one event" do
      admin, inv = seed
      results = race(-> { revoke(admin, inv, key: "r0") }, -> { revoke(admin, inv, key: "r1") })

      expect(results.count(&:success?)).to eq(1)
      expect(invitation_state).to eq("revoked")
      expect(terminal_events).to eq(["InvitationRevoked"])
      expect(results.find(&:failure?).reason_code).to eq("invitation_not_active")
    end

    it "concurrent revoke and accept commit exactly one terminal transition with matching side effects" do
      admin, inv = seed
      receipt = receipt_for
      results = race(-> { revoke(admin, inv) }, -> { accept(inv, receipt) })

      expect(results.count(&:success?)).to eq(1)
      state = invitation_state
      expect(state).to be_in(%w[revoked accepted])
      expect(terminal_events).to eq([state == "accepted" ? "InvitationAccepted" : "InvitationRevoked"])

      if state == "accepted"
        expect(DbInspector.count("accounts")).to eq(2)  # admin + newly-bound invitee
        expect(DbInspector.count("sessions")).to eq(2)  # admin + invitee
      else
        expect(DbInspector.count("accounts")).to eq(1)  # admin only
        expect(DbInspector.count("sessions")).to eq(1)  # admin only
      end
      expect(results.find(&:failure?).reason_code).to eq("invitation_not_active")
    end

    it "concurrent revoke and decline commit exactly one terminal transition and one event" do
      admin, inv = seed
      receipt = receipt_for
      results = race(-> { revoke(admin, inv) }, -> { decline(inv, receipt) })

      expect(results.count(&:success?)).to eq(1)
      state = invitation_state
      expect(state).to be_in(%w[revoked declined])
      expect(terminal_events).to eq([state == "declined" ? "InvitationDeclined" : "InvitationRevoked"])
      expect(results.find(&:failure?).reason_code).to eq("invitation_not_active")
    end
  end

  describe "a terminal Invitation never reopens" do
    it "accept after a successful revoke is invitation_not_active; the Invitation stays revoked, no Account/Session" do
      admin, inv = seed
      expect(revoke(admin, inv)).to be_success

      result = accept(inv, receipt_for)
      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_not_active")
      expect(invitation_state).to eq("revoked")
      expect(DbInspector.count("accounts")).to eq(1)  # admin only; no invitee bound
      expect(DbInspector.count("sessions")).to eq(1)
      expect(terminal_events).to eq(["InvitationRevoked"])
    end

    it "decline after a successful revoke is invitation_not_active; the Invitation stays revoked" do
      admin, inv = seed
      expect(revoke(admin, inv)).to be_success

      result = decline(inv, receipt_for)
      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_not_active")
      expect(invitation_state).to eq("revoked")
      expect(terminal_events).to eq(["InvitationRevoked"])
    end

    it "revoke after a successful accept is invitation_not_active; the Invitation stays accepted" do
      admin, inv = seed
      expect(accept(inv, receipt_for)).to be_success

      result = revoke(admin, inv)
      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_not_active")
      expect(invitation_state).to eq("accepted")
      expect(terminal_events).to eq(["InvitationAccepted"])
    end

    it "revoke after a successful decline is invitation_not_active; the Invitation stays declined" do
      admin, inv = seed
      expect(decline(inv, receipt_for)).to be_success

      result = revoke(admin, inv)
      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_not_active")
      expect(invitation_state).to eq("declined")
      expect(terminal_events).to eq(["InvitationDeclined"])
    end
  end

  describe "replay isolation across workflows" do
    it "the revoke winner replays exactly while an accept loser cannot recover the revoke's result" do
      admin, inv = seed
      first = revoke(admin, inv, key: "rev")
      expect(first).to be_success

      replay = revoke(admin, inv, key: "rev")
      expect(replay.replayed).to be(true)
      expect(replay.payload).to eq(first.payload)

      loser = accept(inv, receipt_for, key: "acc")
      expect(loser).to be_failure
      expect(loser.reason_code).to eq("invitation_not_active")
      expect(invitation_state).to eq("revoked")
    end
  end
end
