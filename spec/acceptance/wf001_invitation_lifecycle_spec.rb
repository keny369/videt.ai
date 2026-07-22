# frozen_string_literal: true

require "rails_helper"

# Cross-workflow invitation lifecycle coverage for the receipt-bound recipient
# terminal transitions (accept and decline). Revoke (WF-013) is now implemented and
# has its own cross-workflow lifecycle spec (wf013_revoke_invitation_lifecycle_spec);
# expire remains deferred to the ScheduledAction subsystem. Verifies the state-model invariants
# (WORKFLOW_SPECIFICATIONS.md :242,:250,:965): only one terminal transition wins under
# concurrency; exactly one terminal event; acceptance side effects exist only when
# accept wins; terminal Invitations never reopen and stay non-disclosing; and the
# winner replays exactly while the loser cannot replay as the winner's result.
RSpec.describe "WF-001 invitation lifecycle (accept vs decline)", type: :acceptance,
               acceptance_ids: ["AC-CAP-001", "AC-WF-001"],
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

  def context
    Platform::RequestContext.for_service(
      service_identity_id: service_id, clock: Platform::Clock.fixed(fixed_now),
      ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
    )
  end

  def seed_invitation(org:, **opts)
    TenantSeeder.create_invitation(organization_id: org, target_email: invitee[:email], **opts)
  end

  def receipt_for
    ReceiptMinter.mint_invitation_receipt(validated_at: fixed_now, issuer_key: invitee[:issuer_key],
                                          subject: invitee[:subject], normalized_email: invitee[:email])
  end

  def accept(inv, receipt, key: "acc", ctx: context)
    cmd = Workflows::Wf001::Commands::AcceptInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      invitation_reference: inv[:reference], receipt_digest: receipt[:receipt_digest],
      accepted_canonical_role: inv[:canonical_role], accepted_permission_mode: inv[:permission_mode],
      accepted_persona: inv[:persona], accepted_scope_sha256: inv[:scope_sha256],
      supplied_account_id: nil, requested_at_utc: fixed_now
    )
    Workflows::Wf001::Handlers::AcceptInvitation.new.call(command: cmd, request_context: ctx)
  end

  def decline(inv, receipt, key: "dec", ctx: context)
    cmd = Workflows::Wf001::Commands::DeclineInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      invitation_reference: inv[:reference], receipt_digest: receipt[:receipt_digest],
      expected_state_version: 0, reason: nil, requested_at_utc: fixed_now
    )
    Workflows::Wf001::Handlers::DeclineInvitation.new.call(command: cmd, request_context: ctx)
  end

  def invitation_state = DbInspector.one("SELECT state FROM invitations")["state"]
  def event_types = DbInspector.all("SELECT event_type FROM event_registry").map { |r| r["event_type"] }

  describe "concurrency — one winner" do
    it "concurrent accept and decline commit exactly one terminal transition with matching side effects" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      acc_receipt = receipt_for
      dec_receipt = receipt_for

      results = [
        Thread.new { ActiveRecord::Base.connection_pool.with_connection { accept(inv, acc_receipt) } },
        Thread.new { ActiveRecord::Base.connection_pool.with_connection { decline(inv, dec_receipt) } }
      ].map(&:value)

      expect(results.count(&:success?)).to eq(1)
      state = invitation_state
      expect(state).to be_in(%w[accepted declined])

      # exactly one terminal Invitation event, matching the winning transition
      terminal = event_types & %w[InvitationAccepted InvitationDeclined]
      expect(terminal).to eq([state == "accepted" ? "InvitationAccepted" : "InvitationDeclined"])

      # acceptance side effects exist only when accept wins
      if state == "accepted"
        expect(DbInspector.count("accounts")).to eq(1)
        expect(DbInspector.count("role_assignments")).to eq(1)
        expect(DbInspector.count("sessions")).to eq(1)
      else
        expect(DbInspector.count("accounts")).to eq(0)
        expect(DbInspector.count("role_assignments")).to eq(0)
        expect(DbInspector.count("sessions")).to eq(0)
      end

      expect(results.find(&:failure?).reason_code).to eq("invitation_not_active")
    end
  end

  describe "terminal states never reopen" do
    it "decline after a successful accept is invitation_not_active; the Invitation stays accepted" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      expect(accept(inv, receipt_for)).to be_success

      result = decline(inv, receipt_for)
      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_not_active")
      expect(invitation_state).to eq("accepted")
      expect(event_types).not_to include("InvitationDeclined")
    end

    it "accept after a successful decline is invitation_not_active; no Account or Session is created" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      expect(decline(inv, receipt_for)).to be_success

      result = accept(inv, receipt_for)
      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_not_active")
      expect(invitation_state).to eq("declined")
      expect(DbInspector.count("accounts")).to eq(0)
      expect(DbInspector.count("sessions")).to eq(0)
      expect(event_types).not_to include("InvitationAccepted")
    end
  end

  describe "replay isolation across workflows" do
    it "the winner replays exactly while the loser cannot replay as the winner's result" do
      org = TenantSeeder.create_organization
      inv = seed_invitation(org:)
      dec_receipt = receipt_for
      first = decline(inv, dec_receipt, key: "dec")
      expect(first).to be_success

      # exact replay of the decline winner returns its own terminal result
      replay = decline(inv, dec_receipt, key: "dec")
      expect(replay.replayed).to be(true)
      expect(replay.payload).to eq(first.payload)

      # the accept loser (different command type + key) does not recover the decline's result
      loser = accept(inv, receipt_for, key: "acc")
      expect(loser).to be_failure
      expect(loser.reason_code).to eq("invitation_not_active")
      expect(invitation_state).to eq("declined")
    end
  end
end
