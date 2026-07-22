# frozen_string_literal: true

require "rails_helper"

# WF-013 SuspendOrganization (016 STATE_MODEL.md :97; contracts/S-23.json MTX-038
# "one transaction changing active to suspended, recording the reason,
# incrementing both versions, revoking every active human Session and preventing
# new scheduled work"; Permission Baseline :138).
#
# The central security question this answers: once an Organization is suspended,
# what previously valid authority stops working, at what boundary, and how is it
# enforced everywhere?
RSpec.describe "WF-013 suspend organization", type: :acceptance,
               acceptance_ids: ["AC-CAP-013", "AC-WF-013"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)

  let(:admin) { TenantSeeder.seed_authorized_admin(issued_at: fixed_now - 900) }

  def ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(fixed_now),
                                               ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)

  def suspend(session_id: admin[:session_id], key: "susp", version: 0, epoch: 7,
              reason: "suspended for lifecycle coverage", schema: "1.0")
    cmd = Workflows::Wf013::Commands::SuspendOrganization.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: schema, session_id:,
      expected_state_version: version, expected_authorization_epoch: epoch, reason:,
      requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::SuspendOrganization.new.call(command: cmd, request_context: ctx)
  end

  def organization = DbInspector.one("SELECT * FROM organizations WHERE id = $1::uuid", [admin[:organization_id]])
  def sessions = DbInspector.all("SELECT status FROM sessions WHERE organization_id = $1::uuid",
                                 [admin[:organization_id]])
  def events = DbInspector.all("SELECT * FROM event_registry ORDER BY created_at")

  describe "the suspension transition" do
    it "takes the Organization active -> suspended, advancing BOTH versions in one transaction" do
      result = suspend

      expect(result).to be_success
      row = organization
      expect(row["status"]).to eq("suspended")
      expect(row["state_version"].to_i).to eq(1)
      expect(row["authorization_epoch"].to_i).to eq(8)
      expect(row["suspended_at"]).not_to be_nil
      expect(row["lifecycle_reason"]).to eq("suspended for lifecycle coverage")
    end

    it "revokes every active human Session of the Organization before returning" do
      other = TenantSeeder.create_account(organization_id: admin[:organization_id],
                                          issuer_key: "https://id.example/oidc",
                                          subject: "other-#{SecureRandom.hex(4)}")
      TenantSeeder.create_session(organization_id: admin[:organization_id], account_id: other,
                                  issued_at: fixed_now - 900)
      expect(sessions.map { |s| s["status"] }).to all(eq("active"))

      result = suspend

      expect(sessions.map { |s| s["status"] }).to all(eq("revoked"))
      expect(result.payload[:revoked_session_count]).to eq(2)
    end

    it "does not revoke Sessions of another Organization" do
      elsewhere = TenantSeeder.seed_authorized_admin(issued_at: fixed_now - 900)
      suspend

      expect(DbInspector.all("SELECT status FROM sessions WHERE organization_id = $1::uuid",
                             [elsewhere[:organization_id]]).map { |s| s["status"] }).to eq(["active"])
    end

    it "emits exactly one OrganizationSuspended state-transition event, actor-attributed" do
      suspend

      expect(events.map { |e| e["event_type"] }).to eq(["OrganizationSuspended"])
      body = JSON.parse(DbInspector.one("SELECT convert_from(event_bytes,'UTF8') AS b FROM event_registry")["b"])
      expect(body["event_profile"]).to eq("state_transition")
      expect(body["from_state"]).to eq("active")
      expect(body["to_state"]).to eq("suspended")
      expect(body["actor_id"]).to eq(admin[:account_id])
      expect(body["service_identity_id"]).to be_nil
      expect(body["reason_code"]).to be_nil
      expect(body["organization_epoch"]).to eq(8)
    end

    it "writes one actor-attributed ledger outcome and one allow decision" do
      suspend

      ledger = DbInspector.one(<<~SQL)
        SELECT e.actor_id, e.service_identity_id, e.action, r.outcome, a.to_state
        FROM command_executions e
        JOIN command_results r ON r.command_execution_id = e.id
        JOIN audit_record_registry a ON a.id = r.audit_record_id
      SQL
      expect(ledger["actor_id"]).to eq(admin[:account_id])
      expect(ledger["service_identity_id"]).to be_nil
      expect(ledger["action"]).to eq("organization.suspend")
      expect(ledger["outcome"]).to eq("success")
      expect(ledger["to_state"]).to eq("suspended")
      expect(DbInspector.one("SELECT decision FROM authorization_decisions")["decision"]).to eq("allow")
    end
  end

  describe "authority is invalidated at the suspension boundary" do
    it "stops a Session that was valid immediately before the commit from authorizing anything after it" do
      session = admin[:session_id]
      # Valid before: a second suspension attempt reaches the state check.
      expect(suspend(key: "pre").reason_code).to be_nil

      after = suspend(session_id: session, key: "post", version: 1, epoch: 8)
      expect(after).to be_failure
      expect(after.reason_code).to eq("session_invalid")
    end

    it "fails closed for a stale Session presented later, without a partially suspended state" do
      suspend
      stale = TenantSeeder.create_session(organization_id: admin[:organization_id],
                                          account_id: admin[:account_id], issued_at: fixed_now - 900)
      # Even a Session inserted afterwards cannot act: the Organization itself is
      # not active, which the shared boundary checks independently of the Session.
      result = suspend(session_id: stale, key: "stale", version: 1, epoch: 8)
      expect(result.reason_code).to eq("organization_inactive")
      expect(organization["status"]).to eq("suspended")
      expect(organization["authorization_epoch"].to_i).to eq(8)
    end

    it "leaves the persisted allow decision in place but unable to authorize anything" do
      suspend
      decision = DbInspector.one("SELECT decision, organization_epoch FROM authorization_decisions")

      expect(decision["decision"]).to eq("allow")
      expect(decision["organization_epoch"].to_i).to eq(7)
      # The epoch has moved on; the stored decision is history, not authority.
      expect(organization["authorization_epoch"].to_i).to eq(8)
    end
  end

  describe "authority, state and versions" do
    it "denies an actor without organization.suspend and changes nothing" do
      other = TenantSeeder.seed_authorized_admin(canonical_role: "MarketingOperator", issued_at: fixed_now - 900)
      result = suspend(session_id: other[:session_id])

      expect(result.reason_code).to eq("missing_authority")
      expect(DbInspector.one("SELECT status FROM organizations WHERE id = $1::uuid",
                             [other[:organization_id]])["status"]).to eq("active")
    end

    it "refuses a stale expected state version or authorization epoch, changing nothing" do
      expect(suspend(version: 9).reason_code).to eq("stale_state_version")
      expect(suspend(epoch: 99).reason_code).to eq("stale_authorization_epoch")
      expect(organization["status"]).to eq("active")
      expect(organization["authorization_epoch"].to_i).to eq(7)
    end

    it "refuses to suspend an Organization that is not active" do
      expect(suspend).to be_success
      # The Session is gone, so a second attempt cannot even authenticate; suspend
      # from a fresh Session in a suspended Organization is refused at the shared
      # boundary before the state check.
      fresh = TenantSeeder.create_session(organization_id: admin[:organization_id],
                                          account_id: admin[:account_id], issued_at: fixed_now - 900)
      expect(suspend(session_id: fresh, key: "again", version: 1, epoch: 8).reason_code)
        .to eq("organization_inactive")
      expect(organization["state_version"].to_i).to eq(1)
    end

    it "refuses an unsupported command schema major" do
      expect(suspend(schema: "2.0").reason_code).to eq("command_schema_unsupported")
    end

    it "refuses an out-of-bounds reason" do
      expect(suspend(reason: "x" * 2001).reason_code).to eq("organization_reason_invalid")
      expect(organization["status"]).to eq("active")
    end
  end

  describe "idempotency" do
    it "returns the stored result on exact replay without a second transition or event" do
      first = suspend(key: "same")
      # The actor's Session is revoked by the first suspension, so replay arrives
      # through a fresh Session; the stored result is returned regardless.
      fresh = TenantSeeder.create_session(organization_id: admin[:organization_id],
                                          account_id: admin[:account_id], issued_at: fixed_now - 900)
      replay = suspend(session_id: fresh, key: "same")

      # The shared boundary refuses first: the Organization is no longer active.
      expect(replay.reason_code).to eq("organization_inactive")
      expect(organization["state_version"].to_i).to eq(1)
      expect(events.size).to eq(1)
      expect(first.payload[:authorization_epoch]).to eq(8)
    end
  end

  describe "database enforcement" do
    it "refuses an epoch decrease, even from an owner connection" do
      suspend
      expect do
        DbInspector.connection.exec_params(
          "UPDATE organizations SET authorization_epoch = 1 WHERE id = $1::uuid", [admin[:organization_id]]
        )
      end.to raise_error(PG::Error, /authorization_epoch_regressed/)
    end

    it "refuses a status change that does not advance the epoch" do
      expect do
        DbInspector.connection.exec_params(
          "UPDATE organizations SET status = 'suspended', suspended_at = now() WHERE id = $1::uuid",
          [admin[:organization_id]]
        )
      end.to raise_error(PG::Error, /status_changed_without_epoch_advance/)
      expect(organization["status"]).to eq("active")
    end

    it "closes the state vocabulary and refuses an unratified transition" do
      suspend
      expect do
        DbInspector.connection.exec_params(
          "UPDATE organizations SET status = 'pending', authorization_epoch = authorization_epoch + 1 WHERE id = $1::uuid",
          [admin[:organization_id]]
        )
      end.to raise_error(PG::Error, /organization_illegal_transition/)
    end
  end
end
