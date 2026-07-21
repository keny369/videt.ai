# frozen_string_literal: true

require "rails_helper"

# Direct oracle for WF-013 RevokeInvitation (WORKFLOW_SPECIFICATIONS.md § invitation
# :246; effective-permission checkpoint :322-329; APPLICATION_LAYER.md WF-013; slice
# S-23). An authenticated Organization actor holding invitation.revoke revokes an
# active Invitation in its Organization: authority is derived from the Session (never
# from caller input or the invitation reference), authorized against the Permission
# Baseline (OrganizationAdmin), and the decision is recorded durably in-transaction.
# active->revoked emits exactly one InvitationRevoked event, consumes no receipt
# nonce, and creates no Account/Assignment/Session. An unauthorized actor is denied
# before the target is read; a cross-Organization reference is not visible; an exact
# replay reauthorizes the current actor and returns the retained result.
RSpec.describe "WF-013 RevokeInvitation", type: :acceptance,
               acceptance_ids: ["AC-CAP-013", "AC-WF-013"],
               test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA TYP-OBS] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def good_reason = "revoked after security review escalation"

  def context(clock_now: fixed_now)
    Platform::RequestContext.for_actor(
      clock: Platform::Clock.fixed(clock_now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7
    )
  end

  def revoke_command(session_id:, reference:, key: "idem-#{SecureRandom.hex(4)}", schema: "1.0",
                     expected_version: 0, reason: good_reason)
    Workflows::Wf013::Commands::RevokeInvitation.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: schema, session_id:,
      invitation_reference: reference, expected_state_version: expected_version, reason:, requested_at_utc: fixed_now
    )
  end

  def revoke(session_id:, reference:, ctx: context, **opts)
    Workflows::Wf013::Handlers::RevokeInvitation.new.call(
      command: revoke_command(session_id:, reference:, **opts), request_context: ctx
    )
  end

  # An authorized admin plus an active Invitation in the same Organization; the admin
  # is recorded as the invitation's requester so the event's requester reference is
  # exercised. Returns [admin_hash, invitation_hash].
  def authorized_admin_with_invitation(**admin_opts)
    admin = TenantSeeder.seed_authorized_admin(**admin_opts)
    inv = TenantSeeder.create_invitation(organization_id: admin[:organization_id],
                                         requester_account_id: admin[:account_id])
    [admin, inv]
  end

  def event_types = DbInspector.all("SELECT event_type FROM event_registry ORDER BY created_at").map { |r| r["event_type"] }
  def decisions = DbInspector.all("SELECT decision, action, subject_id, resource_id, reason_code, organization_epoch, policy_snapshot_id FROM authorization_decisions ORDER BY created_at")

  describe "success" do
    it "an OrganizationAdmin revokes the active Invitation: active->revoked, one event, no domain records, no nonce" do
      admin, inv = authorized_admin_with_invitation

      result = revoke(session_id: admin[:session_id], reference: inv[:reference], reason: good_reason)

      expect(result).to be_success
      expect(result.payload[:invitation_id]).to eq(inv[:invitation_id])
      expect(result.payload[:organization_id]).to eq(admin[:organization_id])
      expect(result.payload[:state]).to eq("revoked")

      row = DbInspector.one("SELECT state, reason, terminated_at, state_version FROM invitations")
      expect(row["state"]).to eq("revoked")
      expect(row["reason"]).to eq(good_reason)
      expect(row["terminated_at"]).not_to be_nil
      expect(row["state_version"]).to eq("1")
      expect(DbInspector.one("SELECT invitation_state FROM invitation_reference_registry")["invitation_state"]).to eq("revoked")

      expect(event_types).to eq(["InvitationRevoked"])
      expect(DbInspector.count("identity_receipt_consumptions")).to eq(0)
      expect(DbInspector.count("sessions")).to eq(1) # the actor's own; none created
      expect(DbInspector.count("role_assignments")).to eq(1) # the actor's own; none created
      expect(DbInspector.count("accounts")).to eq(1) # the actor's own; none created
    end

    it "records exactly one durable authorization_decision (allow) carrying epoch, policy snapshot and subject/resource" do
      admin, inv = authorized_admin_with_invitation
      revoke(session_id: admin[:session_id], reference: inv[:reference])

      d = decisions
      expect(d.size).to eq(1)
      expect(d.first["decision"]).to eq("allow")
      expect(d.first["action"]).to eq("invitation.revoke")
      expect(d.first["subject_id"]).to eq(admin[:account_id])
      expect(d.first["resource_id"]).to eq(inv[:invitation_id])
      expect(d.first["organization_epoch"]).to eq("7")
      expect(d.first["policy_snapshot_id"]).not_to be_nil
    end

    it "emits an InvitationRevoked envelope attributed to the actor (not a service identity), sha256-verifiable" do
      admin, inv = authorized_admin_with_invitation
      revoke(session_id: admin[:session_id], reference: inv[:reference])

      ev = DbInspector.one(<<~SQL)
        SELECT event_type, aggregate_id,
               (event_sha256 = public.digest(event_bytes,'sha256')) AS ok,
               convert_from(event_bytes,'UTF8') AS body
        FROM event_registry
      SQL
      expect(ev["event_type"]).to eq("InvitationRevoked")
      expect(ev["aggregate_id"]).to eq(inv[:invitation_id])
      expect(ev["ok"]).to eq("t")

      body = JSON.parse(ev["body"])
      expect(body["actor_id"]).to eq(admin[:account_id])
      expect(body).not_to have_key("service_identity_id")
      expect(body["from_state"]).to eq("active")
      expect(body["to_state"]).to eq("revoked")
      expect(body["organization_epoch"]).to eq(7)
      expect(body["requester_account_id"]).to eq(admin[:account_id])
      expect(body["reason"]).to eq(good_reason)
    end

    it "writes an actor-attributed command ledger (execution/result carry actor_id, not service_identity_id)" do
      admin, inv = authorized_admin_with_invitation
      revoke(session_id: admin[:session_id], reference: inv[:reference])

      exec_row = DbInspector.one("SELECT actor_id, service_identity_id, action FROM command_executions")
      expect(exec_row["actor_id"]).to eq(admin[:account_id])
      expect(exec_row["service_identity_id"]).to be_nil
      expect(exec_row["action"]).to eq("invitation.revoke")

      res_row = DbInspector.one("SELECT actor_id, service_identity_id, outcome FROM command_results")
      expect(res_row["actor_id"]).to eq(admin[:account_id])
      expect(res_row["service_identity_id"]).to be_nil
      expect(res_row["outcome"]).to eq("success")
    end
  end

  describe "replay and idempotency" do
    it "exact replay reauthorizes and returns the retained result with no new event" do
      admin, inv = authorized_admin_with_invitation
      first = revoke(session_id: admin[:session_id], reference: inv[:reference], key: "k1")
      events_before = DbInspector.count("event_registry")

      second = revoke(session_id: admin[:session_id], reference: inv[:reference], key: "k1")
      expect(second).to be_success
      expect(second.replayed).to be(true)
      expect(second.payload).to eq(first.payload)
      expect(DbInspector.count("event_registry")).to eq(events_before)
    end

    it "the same key with changed input (different reason) is idempotency_conflict (F1-DOMAIN-409)" do
      admin, inv = authorized_admin_with_invitation
      expect(revoke(session_id: admin[:session_id], reference: inv[:reference], key: "k1", reason: good_reason)).to be_success

      second = revoke(session_id: admin[:session_id], reference: inv[:reference], key: "k1",
                      reason: "a completely different justification here")
      expect(second).to be_failure
      expect(second.reason_code).to eq("idempotency_conflict")
      expect(second.failure.error_code).to eq("F1-DOMAIN-409")
    end

    it "a different key after revoke is the non-disclosing invitation_not_active" do
      admin, inv = authorized_admin_with_invitation
      expect(revoke(session_id: admin[:session_id], reference: inv[:reference], key: "k1")).to be_success

      second = revoke(session_id: admin[:session_id], reference: inv[:reference], key: "different-key")
      expect(second).to be_failure
      expect(second.reason_code).to eq("invitation_not_active")
    end

    it "an exact replay by a now-unauthorized actor is denied F1-AUTH-403 and does not return the stored result" do
      admin, inv = authorized_admin_with_invitation
      expect(revoke(session_id: admin[:session_id], reference: inv[:reference], key: "k1")).to be_success

      # The actor loses invitation.revoke authority between the original command and the replay.
      DbInspector.connection.exec_params(
        "UPDATE role_assignments SET status = 'revoked' WHERE account_id = $1::uuid", [admin[:account_id]]
      )

      replay = revoke(session_id: admin[:session_id], reference: inv[:reference], key: "k1")
      expect(replay).to be_failure
      expect(replay.reason_code).to eq("missing_authority")
      expect(replay.failure.error_code).to eq("F1-AUTH-403")
      expect(replay.replayed).to be(false)
    end
  end

  describe "authorization — Session-derived, Permission-Baseline-gated" do
    it "a non-admin actor is denied missing_authority (F1-AUTH-403), the target unread and unchanged" do
      admin, inv = authorized_admin_with_invitation(canonical_role: "MarketingOperator")

      result = revoke(session_id: admin[:session_id], reference: inv[:reference])
      expect(result).to be_failure
      expect(result.reason_code).to eq("missing_authority")
      expect(result.failure.error_code).to eq("F1-AUTH-403")

      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("active")
      expect(DbInspector.count("event_registry")).to eq(0)
      # Denied before the target was read: the recorded decision names no resource.
      d = decisions
      expect(d.size).to eq(1)
      expect(d.first["decision"]).to eq("deny")
      expect(d.first["reason_code"]).to eq("missing_authority")
      expect(d.first["resource_id"]).to be_nil
    end

    it "an actor with no active Access Policy is policy_unavailable (F1-DOMAIN-409)" do
      admin, inv = authorized_admin_with_invitation(with_policy: false)
      result = revoke(session_id: admin[:session_id], reference: inv[:reference])
      expect(result).to be_failure
      expect(result.reason_code).to eq("policy_unavailable")
      expect(result.failure.error_code).to eq("F1-DOMAIN-409")
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("active")
    end
  end

  describe "authentication and actor context" do
    it "an unknown Session id is session_invalid (F1-AUTHN-401), nothing written" do
      org = TenantSeeder.create_organization
      inv = TenantSeeder.create_invitation(organization_id: org)
      result = revoke(session_id: SecureRandom.uuid_v7, reference: inv[:reference])
      expect(result).to be_failure
      expect(result.reason_code).to eq("session_invalid")
      expect(result.failure.error_code).to eq("F1-AUTHN-401")
      expect(DbInspector.count("command_executions")).to eq(0)
      expect(DbInspector.count("authorization_decisions")).to eq(0)
    end

    it "an idle-expired Session is session_invalid" do
      admin, inv = authorized_admin_with_invitation(
        issued_at: Time.utc(2026, 7, 20, 9, 0, 0), last_activity_at: Time.utc(2026, 7, 20, 9, 0, 0)
      )
      result = revoke(session_id: admin[:session_id], reference: inv[:reference])
      expect(result.reason_code).to eq("session_invalid")
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("active")
    end

    it "a revoked Session is session_invalid" do
      admin, inv = authorized_admin_with_invitation(session_status: "revoked")
      result = revoke(session_id: admin[:session_id], reference: inv[:reference])
      expect(result.reason_code).to eq("session_invalid")
    end

    it "a suspended Account is account_inactive (F1-AUTH-403), denied before assignment evaluation" do
      admin, inv = authorized_admin_with_invitation(account_status: "suspended")
      result = revoke(session_id: admin[:session_id], reference: inv[:reference])
      expect(result.reason_code).to eq("account_inactive")
      expect(result.failure.error_code).to eq("F1-AUTH-403")
    end

    it "a suspended Organization is organization_inactive (F1-AUTH-403)" do
      org = TenantSeeder.create_organization(status: "suspended")
      admin = TenantSeeder.seed_authorized_admin(organization_id: org)
      inv = TenantSeeder.create_invitation(organization_id: org)
      result = revoke(session_id: admin[:session_id], reference: inv[:reference])
      expect(result.reason_code).to eq("organization_inactive")
      expect(result.failure.error_code).to eq("F1-AUTH-403")
    end
  end

  describe "isolation and state" do
    it "a cross-Organization reference is not visible: invitation_not_active, the other Organization's Invitation untouched" do
      admin, = authorized_admin_with_invitation # admin in org A
      other = TenantSeeder.create_organization
      foreign = TenantSeeder.create_invitation(organization_id: other)

      result = revoke(session_id: admin[:session_id], reference: foreign[:reference])
      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_not_active")
      expect(DbInspector.one("SELECT state FROM invitations WHERE id = '#{foreign[:invitation_id]}'")["state"]).to eq("active")
    end

    it "a terminal Invitation cannot be revoked (invitation_not_active)" do
      admin = TenantSeeder.seed_authorized_admin
      inv = TenantSeeder.create_invitation(organization_id: admin[:organization_id], state: "accepted")
      result = revoke(session_id: admin[:session_id], reference: inv[:reference])
      expect(result).to be_failure
      expect(result.reason_code).to eq("invitation_not_active")
    end

    it "a stale expected state version is stale_state_version (F1-DOMAIN-409), no transition" do
      admin, inv = authorized_admin_with_invitation
      result = revoke(session_id: admin[:session_id], reference: inv[:reference], expected_version: 5)
      expect(result).to be_failure
      expect(result.reason_code).to eq("stale_state_version")
      expect(result.failure.error_code).to eq("F1-DOMAIN-409")
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("active")
    end
  end

  describe "input shape" do
    it "rejects a missing, blank, too-short or too-long reason as invitation_reason_invalid (F1-VALIDATION-400)" do
      admin, inv = authorized_admin_with_invitation
      [nil, "   ", "short", "x" * 2001].each do |bad|
        result = revoke(session_id: admin[:session_id], reference: inv[:reference], reason: bad)
        expect(result.reason_code).to eq("invitation_reason_invalid")
        expect(result.failure.error_code).to eq("F1-VALIDATION-400")
      end
      expect(DbInspector.one("SELECT state FROM invitations")["state"]).to eq("active")
    end

    it "rejects an unsupported command schema major (F1-VALIDATION-400)" do
      admin, inv = authorized_admin_with_invitation
      result = revoke(session_id: admin[:session_id], reference: inv[:reference], schema: "2.0")
      expect(result.reason_code).to eq("command_schema_unsupported")
      expect(result.failure.error_code).to eq("F1-VALIDATION-400")
    end
  end

  describe "non-disclosure" do
    it "the public resolver returns zero rows after revoke" do
      admin, inv = authorized_admin_with_invitation
      revoke(session_id: admin[:session_id], reference: inv[:reference])
      rows = DbInspector.connection.exec_params(
        "SELECT organization_id FROM f1_resolve_invitation_reference($1, $2::timestamptz)",
        [{ value: inv[:reference_digest], format: 1 }, fixed_now.iso8601(6)]
      ).to_a
      expect(rows).to be_empty
    end
  end
end
