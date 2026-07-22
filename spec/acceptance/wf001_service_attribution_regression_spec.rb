# frozen_string_literal: true

require "rails_helper"

# Cross-workflow regression coverage for the two corrections that necessarily
# touched already-accepted infrastructure: Service Identity referential integrity
# across the shared ledgers, and PostgreSQL as the authority for invitation
# reference resolution.
#
# The point is not to re-test those workflows — each has its own acceptance
# suite — but to prove that the two corrections changed attribution and clock
# authority WITHOUT changing who each workflow is attributed to, what it emits,
# or what it refuses.
RSpec.describe "invitation workflow attribution and expiry regressions", type: :acceptance,
               acceptance_ids: ["AC-CAP-001", "AC-WF-001", "AC-WF-013"],
               test_types: %w[TYP-INT TYP-SEC TYP-DATA] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)

  let(:invitee) do
    { issuer_key: "https://id.example/oidc", subject: "sub-#{SecureRandom.hex(8)}",
      email: "invitee-#{SecureRandom.hex(4)}@example.com" }
  end

  def service_context
    Platform::RequestContext.for_service(
      service_identity_id: Platform::ServiceIdentity.identity_service,
      clock: Platform::Clock.fixed(fixed_now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
    )
  end

  def actor_context
    Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(fixed_now), ids: Platform::Ids.system,
                                       correlation_id: SecureRandom.uuid_v7)
  end

  def seed
    admin = TenantSeeder.seed_authorized_admin(issued_at: fixed_now - 900)
    inv = TenantSeeder.create_invitation(organization_id: admin[:organization_id], target_email: invitee[:email],
                                         requester_account_id: admin[:account_id])
    [admin, inv]
  end

  def receipt = ReceiptMinter.mint_invitation_receipt(validated_at: fixed_now, issuer_key: invitee[:issuer_key],
                                                      subject: invitee[:subject], normalized_email: invitee[:email])

  def accept(inv, key: "acc", receipt_digest: nil)
    cmd = Workflows::Wf001::Commands::AcceptInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      invitation_reference: inv[:reference], receipt_digest: receipt_digest || receipt[:receipt_digest],
      accepted_canonical_role: inv[:canonical_role], accepted_permission_mode: inv[:permission_mode],
      accepted_persona: inv[:persona], accepted_scope_sha256: inv[:scope_sha256],
      supplied_account_id: nil, requested_at_utc: fixed_now
    )
    Workflows::Wf001::Handlers::AcceptInvitation.new.call(command: cmd, request_context: service_context)
  end

  def decline(inv, key: "dec", receipt_digest: nil)
    cmd = Workflows::Wf001::Commands::DeclineInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      invitation_reference: inv[:reference], receipt_digest: receipt_digest || receipt[:receipt_digest],
      expected_state_version: 0, reason: nil, requested_at_utc: fixed_now
    )
    Workflows::Wf001::Handlers::DeclineInvitation.new.call(command: cmd, request_context: service_context)
  end

  def revoke(admin, inv, key: "rev")
    cmd = Workflows::Wf013::Commands::RevokeInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
      session_id: admin[:session_id], invitation_reference: inv[:reference],
      expected_state_version: 0, reason: "revoked for attribution regression coverage",
      requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::RevokeInvitation.new.call(command: cmd, request_context: actor_context)
  end

  def attribution
    DbInspector.all(<<~SQL)
      SELECT command_type, actor_id, service_identity_id FROM command_executions ORDER BY created_at
    SQL
  end

  def events = DbInspector.all("SELECT event_type FROM event_registry").map { |r| r["event_type"] }

  describe "attribution is unchanged, and now provably real" do
    it "keeps AcceptInvitation attributed to the registered identity service, never an actor" do
      _admin, inv = seed
      expect(accept(inv)).to be_success

      rows = attribution
      expect(rows.map { |r| r["command_type"] }).to eq(["wf001.accept_invitation"])
      expect(rows.first["service_identity_id"]).to eq(Platform::ServiceIdentity.identity_service)
      expect(rows.first["actor_id"]).to be_nil
      expect(events).to include("InvitationAccepted", "SessionCreated")
    end

    it "keeps DeclineInvitation attributed to the registered identity service" do
      _admin, inv = seed
      expect(decline(inv)).to be_success

      expect(attribution.first["service_identity_id"]).to eq(Platform::ServiceIdentity.identity_service)
      expect(attribution.first["actor_id"]).to be_nil
      expect(events).to eq(["InvitationDeclined"])
    end

    it "keeps RevokeInvitation attributed to the human org actor, with no Service Identity at all" do
      admin, inv = seed
      expect(revoke(admin, inv)).to be_success

      row = attribution.first
      expect(row["command_type"]).to eq("wf013.revoke_invitation")
      expect(row["actor_id"]).to eq(admin[:account_id])
      expect(row["service_identity_id"]).to be_nil
      expect(events).to eq(["InvitationRevoked"])
      # A human workflow was not silently converted into service attribution.
      expect(DbInspector.count("authorization_decisions")).to eq(1)
    end

    it "keeps ExpireInvitation attributed to the persisted ScheduledAction executor" do
      admin = TenantSeeder.seed_authorized_admin
      inv = TenantSeeder.create_invitation(organization_id: admin[:organization_id],
                                           activated_at: Time.utc(2026, 6, 1, 10, 0, 0),
                                           requester_account_id: admin[:account_id])
      worker = Platform::ScheduledActions::Worker.new(
        registry: Platform::ScheduledActions::Registry.default,
        scheduler: Platform::ScheduledActions::Scheduler.new,
        clock: Platform::Clock.fixed(inv[:expires_at]), ids: Platform::Ids.system
      )
      expect(worker.run_due_batch.map(&:disposition)).to eq([:completed])

      row = attribution.first
      expect(row["command_type"]).to eq("wf001.expire_invitation")
      expect(row["service_identity_id"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)
      expect(row["actor_id"]).to be_nil
      expect(events).to eq(["InvitationExpired"])
    end

    it "attributes every ledger row to an identity that actually exists" do
      admin, inv = seed
      accept(inv)
      _admin2, inv2 = seed
      revoke(admin, inv2) if inv2[:organization_id] == admin[:organization_id]

      dangling = DbInspector.all(<<~SQL)
        SELECT 'command_executions' AS t FROM command_executions e
          WHERE e.service_identity_id IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM service_identities s WHERE s.id = e.service_identity_id)
        UNION ALL
        SELECT 'command_results' FROM command_results r
          WHERE r.service_identity_id IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM service_identities s WHERE s.id = r.service_identity_id)
        UNION ALL
        SELECT 'audit_record_registry' FROM audit_record_registry a
          WHERE a.service_identity_id IS NOT NULL
            AND NOT EXISTS (SELECT 1 FROM service_identities s WHERE s.id = a.service_identity_id)
      SQL
      expect(dangling).to be_empty
    end
  end

  describe "resolution behaviour is unchanged for every workflow that depends on it" do
    it "still resolves a live reference for acceptance, decline and revocation" do
      admin, inv = seed
      expect(accept(inv)).to be_success

      _a2, inv2 = seed
      expect(decline(inv2)).to be_success

      admin3, inv3 = seed
      expect(revoke(admin3, inv3)).to be_success
      expect(admin[:organization_id]).not_to be_nil
    end

    it "refuses acceptance and decline of an already-expired reference, and creates nothing" do
      admin = TenantSeeder.seed_authorized_admin(issued_at: fixed_now - 900)
      inv = TenantSeeder.create_invitation(organization_id: admin[:organization_id],
                                           target_email: invitee[:email],
                                           activated_at: Time.utc(2026, 6, 1, 10, 0, 0))
      accounts = DbInspector.count("accounts")

      [accept(inv), decline(inv, key: "d2")].each do |result|
        expect(result).to be_failure
        expect(result.reason_code).to eq("invitation_not_active")
      end
      expect(DbInspector.count("accounts")).to eq(accounts)
      expect(DbInspector.count("sessions")).to eq(1)   # the admin's only
      expect(events).to be_empty
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("active")
    end

    it "keeps the wrong-identity protection: the Invitation stays active, the nonce is bound, no event" do
      _admin, inv = seed
      stranger = ReceiptMinter.mint_invitation_receipt(
        validated_at: fixed_now, issuer_key: invitee[:issuer_key],
        subject: "other-#{SecureRandom.hex(6)}", normalized_email: "other-#{SecureRandom.hex(4)}@example.com"
      )

      result = decline(inv, receipt_digest: stranger[:receipt_digest])

      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_target_mismatch")
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("active")
      expect(events).to be_empty
      expect(DbInspector.count("identity_receipt_consumptions")).to eq(1)
    end

    it "keeps exact replay working through the ledger after the Invitation is terminal" do
      _admin, inv = seed
      bound = receipt
      first = accept(inv, key: "same", receipt_digest: bound[:receipt_digest])
      expect(first).to be_success

      replay = accept(inv, key: "same", receipt_digest: bound[:receipt_digest])
      expect(replay.replayed).to be(true)
      expect(replay.payload).to eq(first.payload)
      expect(events.count("InvitationAccepted")).to eq(1)
    end

    it "keeps terminal references non-resolving and terminal Invitations non-reopening" do
      admin, inv = seed
      expect(revoke(admin, inv)).to be_success

      expect(accept(inv)).to be_failure
      expect(decline(inv, key: "d3")).to be_failure
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("revoked")
      expect(events).to eq(["InvitationRevoked"])
    end
  end

  describe "row level security and non-disclosure are intact" do
    it "gives the runtime no visibility of tenant rows outside a proved context" do
      _admin, inv = seed
      expect(accept(inv)).to be_success

      conn = ActiveRecord::Base.connection
      %w[invitations accounts sessions role_assignments command_executions audit_record_registry].each do |table|
        expect(conn.select_value("SELECT count(*) FROM #{table}")).to eq(0), "#{table} leaked outside context"
      end
      expect(DbInspector.count("invitations")).to eq(1)
    end

    # The resolver deliberately takes no Organization argument: it is the
    # pre-context locator, and a reference resolves to its OWN Organization or to
    # nothing (POSTGRESQL_SCHEMA.md :179). Non-disclosure is the property that an
    # unknown reference and a reference the caller has no business with produce the
    # same generic outcome and reveal no target, role or Organization detail.
    it "returns the same generic outcome for an unknown reference and another Organization's terminal one" do
      _admin, mine = seed
      other = TenantSeeder.seed_authorized_admin
      theirs = TenantSeeder.create_invitation(organization_id: other[:organization_id], state: "revoked",
                                              target_email: "someone-#{SecureRandom.hex(4)}@example.com")
      unknown = { reference: SecureRandom.random_bytes(32) }

      cross = decline(theirs, key: "x1")
      absent = decline(unknown, key: "x2")

      expect(cross.reason_code).to eq("invitation_not_active")
      expect(absent.reason_code).to eq(cross.reason_code)
      expect(cross.payload).to be_nil
      expect(DbInspector.one("SELECT state FROM invitations WHERE id = $1::uuid",
                             [mine[:invitation_id]])["state"]).to eq("active")
    end
  end
end
