# frozen_string_literal: true

require "rails_helper"

# WF-013 CreateInvitation (WORKFLOW_SPECIFICATIONS.md :242, :244;
# contracts/S-23.json MTX-038) — the first production path that brings an
# Invitation into existence, and therefore the first consumer of the whole
# platform at once: Session authentication, Session-derived organization
# authority, the Permission Baseline, the actor-attributed command/audit/event
# ledger, request digests, idempotency, the reference registry and — for a
# nonprotected offer — the ScheduledAction subsystem inside the same transaction.
RSpec.describe "WF-013 create invitation", type: :acceptance,
               acceptance_ids: ["AC-CAP-013", "AC-WF-013"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA TYP-OBS] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)

  let(:admin) { TenantSeeder.seed_authorized_admin(issued_at: fixed_now - 900) }
  let(:target_email) { "invitee-#{SecureRandom.hex(4)}@example.com" }

  def ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(fixed_now),
                                               ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)

  def create(key: "inv-1", role: "MarketingOperator", mode: "standard", persona: nil,
             email: target_email, session_id: admin[:session_id], scope: Digest::SHA256.digest("scope:organization"),
             issuer: nil, subject: nil, assignment_expiry: nil, schema: "1.0")
    cmd = Workflows::Wf013::Commands::CreateInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: schema,
      session_id:, target_email: email, target_identity_issuer_key: issuer, target_identity_subject: subject,
      canonical_role: role, permission_mode: mode, persona:, scope_sha256: scope,
      intended_assignment_expires_at: assignment_expiry, requested_at_utc: fixed_now
    )
    Workflows::Wf013::Handlers::CreateInvitation.new.call(command: cmd, request_context: ctx)
  end

  def invitation = DbInspector.one("SELECT * FROM invitations")
  def registry = DbInspector.one("SELECT * FROM invitation_reference_registry")
  def actions = DbInspector.all("SELECT * FROM scheduled_actions")
  def events = DbInspector.all("SELECT * FROM event_registry ORDER BY created_at")
  def event_body = JSON.parse(DbInspector.one("SELECT convert_from(event_bytes,'UTF8') AS body FROM event_registry")["body"])

  describe "a nonprotected offer is created directly active" do
    it "creates the Invitation active, seven days to expiry, with exactly one expiry timer" do
      result = create

      expect(result).to be_success
      row = invitation
      expect(row["state"]).to eq("active")
      expect(row["requester_account_id"]).to eq(admin[:account_id])
      expect(Time.parse(row["activated_at"]).getutc).to eq(fixed_now)
      expect(Time.parse(row["expires_at"]).getutc).to eq(fixed_now + (7 * 24 * 3600))
      expect(row["approval_due_at"]).to be_nil
      expect(JSON.parse(row["protected_permission_preview"])).to eq([])

      expect(actions.size).to eq(1)
      action = actions.first
      expect(action["action_kind"]).to eq("invitation_expire")
      expect(action["target_id"]).to eq(row["id"])
      expect(action["status"]).to eq("pending")
      expect(Time.parse(action["due_at"]).getutc).to eq(Time.parse(row["expires_at"]).getutc)
    end

    it "emits exactly one InvitationActivated created event, actor-attributed" do
      create

      expect(events.map { |e| e["event_type"] }).to eq(["InvitationActivated"])
      expect(events.first["event_profile"]).to eq("created")
      body = event_body
      expect(body["to_state"]).to eq("active")
      expect(body["actor_id"]).to eq(admin[:account_id])
      expect(body["requester_account_id"]).to eq(admin[:account_id])
      expect(body["service_identity_id"]).to be_nil
      expect(body["reason_code"]).to be_nil
      expect(body["organization_epoch"]).to eq(7)
      expect(body["scheduled_action_id"]).to eq(actions.first["id"])
    end

    it "returns the raw acceptance reference to the requester and persists only its digest" do
      result = create

      reference = result.payload[:invitation_reference]
      expect(reference.bytesize).to eq(32)
      expect(registry["opaque_reference_sha256"].delete_prefix("\\x"))
        .to eq(Digest::SHA256.hexdigest(reference))
      stored = DbInspector.one("SELECT authorized_payload FROM command_results")["authorized_payload"]
      expect(stored).not_to include(reference.unpack1("H*"))
      expect(JSON.parse(stored)).not_to have_key("invitation_reference")
    end

    it "publishes the reference through the registry so the public resolver resolves it" do
      result = create

      resolved = DbInspector.all("SELECT * FROM f1_resolve_invitation_reference($1)",
                                 [{ value: Digest::SHA256.digest(result.payload[:invitation_reference]), format: 1 }])
      expect(resolved.size).to eq(1)
      expect(resolved.first["organization_id"]).to eq(admin[:organization_id])
    end

    it "records the actor-attributed ledger and one allow authorization decision" do
      create

      ledger = DbInspector.one(<<~SQL)
        SELECT e.actor_id, e.service_identity_id, e.action, e.command_type, r.outcome, a.to_state
        FROM command_executions e
        JOIN command_results r ON r.command_execution_id = e.id
        JOIN audit_record_registry a ON a.id = r.audit_record_id
      SQL
      expect(ledger["actor_id"]).to eq(admin[:account_id])
      expect(ledger["service_identity_id"]).to be_nil
      expect(ledger["action"]).to eq("invitation.create")
      expect(ledger["command_type"]).to eq("wf013.create_invitation")
      expect(ledger["outcome"]).to eq("success")
      expect(ledger["to_state"]).to eq("active")

      decision = DbInspector.one("SELECT * FROM authorization_decisions")
      expect(decision["decision"]).to eq("allow")
      expect(decision["action"]).to eq("invitation.create")
    end
  end

  describe "a protected offer starts pending approval and grants nothing" do
    %w[OrganizationAdmin SecurityOperator].each do |role|
      it "creates a #{role} offer pending approval, with no timer and no active reference" do
        result = create(role: role)

        expect(result).to be_success
        row = invitation
        expect(row["state"]).to eq("pending_approval")
        expect(row["activated_at"]).to be_nil
        expect(row["expires_at"]).to be_nil
        expect(Time.parse(row["approval_due_at"]).getutc).to eq(fixed_now + (24 * 3600))
        expect(JSON.parse(row["protected_permission_preview"])).not_to be_empty

        expect(actions).to be_empty
        expect(events.map { |e| e["event_type"] }).to eq(["InvitationApprovalRequested"])
        expect(registry["invitation_state"]).to eq("pending_approval")
      end
    end

    it "does not resolve a pending-approval reference through the public resolver" do
      result = create(role: "OrganizationAdmin")
      resolved = DbInspector.all("SELECT * FROM f1_resolve_invitation_reference($1)",
                                 [{ value: Digest::SHA256.digest(result.payload[:invitation_reference]), format: 1 }])
      expect(resolved).to be_empty
    end
  end

  describe "authority" do
    it "denies an actor without invitation.create and creates nothing" do
      other = TenantSeeder.seed_authorized_admin(canonical_role: "MarketingOperator", issued_at: fixed_now - 900)
      result = create(session_id: other[:session_id])

      expect(result).to be_failure
      expect(result.reason_code).to eq("missing_authority")
      expect(DbInspector.count("invitations")).to eq(0)
      expect(actions).to be_empty
      expect(DbInspector.one("SELECT decision FROM authorization_decisions")["decision"]).to eq("deny")
    end

    it "rejects an invalid Session before anything is read" do
      result = create(session_id: SecureRandom.uuid_v7)
      expect(result.reason_code).to eq("session_invalid")
      expect(DbInspector.count("invitations")).to eq(0)
    end
  end

  describe "offer validation" do
    it "refuses a malformed target email" do
      expect(create(email: "not-an-email").reason_code).to eq("identity_email_invalid")
      expect(DbInspector.count("invitations")).to eq(0)
    end

    it "refuses a role/mode/persona tuple the ratified rule forbids" do
      expect(create(role: "SecurityOperator", mode: "read_only").reason_code).to eq("role_mode_invalid")
      expect(create(role: "BillingOperator", mode: "standard", persona: "consultant").reason_code)
        .to eq("role_mode_invalid")
      expect(create(role: "NotARole").reason_code).to eq("role_mode_invalid")
      expect(DbInspector.count("invitations")).to eq(0)
    end

    it "accepts the ratified read_only executive buyer tuple" do
      expect(create(role: "MarketingOperator", mode: "read_only", persona: "executive_buyer")).to be_success
    end

    it "refuses an unsupported command schema major" do
      expect(create(schema: "2.0").reason_code).to eq("command_schema_unsupported")
    end
  end

  describe "open-invitation uniqueness" do
    it "returns the existing Invitation for an exact creation replay, creating no second timer" do
      first = create(key: "same")
      replay = create(key: "same")

      expect(replay.replayed).to be(true)
      expect(replay.payload[:invitation_id]).to eq(first.payload[:invitation_id])
      expect(DbInspector.count("invitations")).to eq(1)
      expect(actions.size).to eq(1)
      expect(events.size).to eq(1)
    end

    it "returns invitation_duplicate_open with the Invitation id for a different key on the same offer" do
      first = create(key: "k1")
      duplicate = create(key: "k2")

      expect(duplicate).to be_failure
      expect(duplicate.reason_code).to eq("invitation_duplicate_open")
      expect(DbInspector.count("invitations")).to eq(1)
      expect(actions.size).to eq(1)
      audit = DbInspector.all("SELECT payload FROM audit_record_registry ORDER BY created_at").last
      expect(JSON.parse(audit["payload"])["invitation_id"]).to eq(first.payload[:invitation_id])
    end

    it "permits a separate Invitation for different grant content" do
      create(key: "k1", role: "MarketingOperator")
      expect(create(key: "k2", role: "TechnicalImplementer")).to be_success
      expect(DbInspector.count("invitations")).to eq(2)
      expect(actions.size).to eq(2)
    end

    it "frees the preimage again once the predecessor is terminal" do
      first = create(key: "k1")
      DbInspector.connection.exec_params(
        "UPDATE invitations SET state = 'revoked', terminated_at = now() WHERE id = $1::uuid",
        [first.payload[:invitation_id]]
      )
      expect(create(key: "k2")).to be_success
      expect(DbInspector.count("invitations")).to eq(2)
    end
  end

  describe "target eligibility" do
    it "creates nothing when the matching Account is suspended or revoked" do
      %w[suspended revoked].each do |status|
        ReceiptMinter.truncate_all
        seeded = TenantSeeder.seed_authorized_admin(issued_at: fixed_now - 900)
        TenantSeeder.create_account(organization_id: seeded[:organization_id], issuer_key: "https://id.example/oidc",
                                    subject: "target-#{SecureRandom.hex(4)}", email: target_email, status:)
        cmd = Workflows::Wf013::Commands::CreateInvitation.new(
          command_id: SecureRandom.uuid_v7, idempotency_key: "elig", schema_version: "1.0",
          session_id: seeded[:session_id], target_email:, target_identity_issuer_key: nil,
          target_identity_subject: nil, canonical_role: "MarketingOperator", permission_mode: "standard",
          persona: nil, scope_sha256: Digest::SHA256.digest("scope:organization"),
          intended_assignment_expires_at: nil, requested_at_utc: fixed_now
        )
        result = Workflows::Wf013::Handlers::CreateInvitation.new.call(command: cmd, request_context: ctx)

        expect(result.reason_code).to eq("invitation_account_ineligible"), status
        expect(DbInspector.count("invitations")).to eq(0)
      end
    end

    it "creates nothing when an active Account already holds the exact offered grant" do
      scope = Digest::SHA256.digest("scope:organization")
      account = TenantSeeder.create_account(organization_id: admin[:organization_id],
                                            issuer_key: "https://id.example/oidc",
                                            subject: "held-#{SecureRandom.hex(4)}", email: target_email)
      TenantSeeder.create_role_assignment(organization_id: admin[:organization_id], account_id: account,
                                          canonical_role: "MarketingOperator", scope_sha256: scope)

      result = create(scope: scope)

      expect(result.reason_code).to eq("invitation_grant_already_active")
      expect(DbInspector.count("invitations")).to eq(0)
      expect(actions).to be_empty
    end
  end
end
