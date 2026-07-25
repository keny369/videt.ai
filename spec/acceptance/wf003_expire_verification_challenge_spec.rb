# frozen_string_literal: true

require "rails_helper"

# WF-003 ExpireVerificationRequest (SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And
# Evidence; contracts/S-05.json MTX-028/005/051; AC-CAP-005, AC-WF-003).
#
# The expiry limb of S-05: the verification lifecycle service, running the due
# `verification_request_expire` ScheduledAction that IssueVerificationChallenge
# scheduled, transitions a still-pending Request to `expired`/`challenge_expired`,
# cryptographically destroys the challenge material (F-02), emits
# `SourceVerificationExpired` and leaves the Source `proposed`. The handler is driven
# with the command the worker builds from the claimed action and a service context
# for the ScheduledAction executor (a null human actor).
RSpec.describe "WF-003 expire verification challenge", type: :acceptance,
               acceptance_ids: ["AC-CAP-005", "AC-WF-003"], test_types: %w[TYP-E2E TYP-SEC TYP-DATA TYP-OBS] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def act_now = fixed_now + 60
  def expires_at = act_now + (24 * 3600)
  def bc = Platform::BaselineContent

  let(:identity) { { issuer_key: "https://id.example/oidc", subject: "founder-#{SecureRandom.hex(8)}" } }

  def service_ctx(at)
    Platform::RequestContext.for_service(service_identity_id: Platform::ServiceIdentity::IDENTITY_SERVICE,
                                         clock: Platform::Clock.fixed(at), ids: Platform::Ids.system,
                                         correlation_id: SecureRandom.uuid_v7)
  end

  def act_ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(act_now), ids: Platform::Ids.system,
                                                   correlation_id: SecureRandom.uuid_v7)

  # The service context of the ScheduledAction executor (null human actor).
  def executor_ctx(at = expires_at)
    Platform::RequestContext.for_service(service_identity_id: Platform::ServiceIdentity.scheduled_action_executor,
                                         clock: Platform::Clock.fixed(at), ids: Platform::Ids.system,
                                         correlation_id: SecureRandom.uuid_v7)
  end

  def bootstrap
    grant = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: fixed_now - 60, **identity)
    Workflows::Wf001::Handlers::RequestBootstrapGrant.new.call(
      command: Workflows::Wf001::Commands::RequestBootstrapGrant.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "grant-#{SecureRandom.hex(4)}",
        schema_version: "1.0", receipt_digest: grant[:receipt_digest], requested_at_utc: fixed_now - 60
      ), request_context: service_ctx(fixed_now - 60)
    )
    receipt = ReceiptMinter.mint_self_service_receipt(validated_at: fixed_now, **identity)
    Workflows::Wf001::Handlers::BootstrapOrganization.new.call(
      command: Workflows::Wf001::Commands::BootstrapOrganization.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "boot-#{SecureRandom.hex(4)}", schema_version: "1.0",
        receipt_digest: receipt[:receipt_digest], expected_grant_version: 0,
        organization_display_name: "Acme", project_display_name: "Genesis", project_objective: "discoverability_assessment",
        access_policy_content_sha256: bc.access_policy_sha256, entitlement_policy_content_sha256: bc.entitlement_policy_sha256,
        plan_content_sha256: bc.plan_sha256, requested_at_utc: fixed_now
      ), request_context: service_ctx(fixed_now)
    ).payload
  end

  def register_source(g, uri)
    Workflows::Wf004::Handlers::RegisterSource.new.call(
      command: Workflows::Wf004::Commands::RegisterSource.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "rs-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
        registration_schema_version: "source-registration-v1", submitted_root_uri: uri,
        expected_state_version: 0, requested_at_utc: fixed_now
      ), request_context: act_ctx
    ).payload[:source_id]
  end

  def issue(g, sid, key = "vc-#{SecureRandom.hex(6)}")
    Workflows::Wf003::Handlers::IssueVerificationChallenge.new.call(
      command: Workflows::Wf003::Commands::IssueVerificationChallenge.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
        source_id: sid, method: "dns_txt", expected_state_version: 0, requested_at_utc: act_now
      ), request_context: act_ctx
    )
  end

  # Genesis + a registered proposed Source + an issued pending Verification Request.
  def issued_challenge(uri: "https://shop.acme.example")
    g = bootstrap
    sid = register_source(g, uri)
    r = issue(g, sid)
    { g:, source_id: sid, vid: r.payload[:verification_request_id], token: r.payload[:challenge_token] }
  end

  # The command the worker builds from the due action, with overridable fields.
  def expire_command(vid, org, due_at: expires_at, action_id: SecureRandom.uuid_v7,
                     identity: SecureRandom.random_bytes(32), target_type: "verification_request", schema: "1.0")
    Workflows::Wf003::Commands::ExpireVerificationRequest.new(
      command_id: SecureRandom.uuid_v7, schema_version: schema, organization_id: org, target_type:,
      verification_request_id: vid, due_at:, action_id:, action_identity_sha256: identity, requested_at_utc: due_at
    )
  end

  def expire(vid, org, ctx: executor_ctx, **over)
    Workflows::Wf003::Handlers::ExpireVerificationRequest.new.call(command: expire_command(vid, org, **over), request_context: ctx)
  end

  def vr(id) = DbInspector.one("SELECT * FROM verification_requests WHERE id = $1::uuid", [id])
  def wf003_events(type) = DbInspector.all("SELECT * FROM event_registry WHERE workflow_id='WF-003' AND event_type='#{type}' ORDER BY occurred_at, id")

  # ------------------------------------------------------------------------

  describe "the due timer expires a pending Request" do
    it "transitions pending -> expired/challenge_expired, leaves the Source proposed, emits one event" do
      c = issued_challenge
      result = expire(c[:vid], c[:g][:organization_id])

      expect(result).to be_success
      row = vr(c[:vid])
      expect(row["request_status"]).to eq("expired")
      expect(row["decision_reason_code"]).to eq("challenge_expired")
      expect(row["state_version"].to_i).to eq(1)
      expect(DbInspector.one("SELECT state FROM sources WHERE id = $1::uuid", [c[:source_id]])["state"]).to eq("proposed")

      events = wf003_events("SourceVerificationExpired")
      expect(events.size).to eq(1)
      body = JSON.parse(DbInspector.one("SELECT convert_from(event_bytes,'UTF8') AS b FROM event_registry WHERE id=$1::uuid", [events.first["id"]])["b"])
      expect(body["verification_request_id"]).to eq(c[:vid])
      expect(body["source_id"]).to eq(c[:source_id])
      expect(body["to_state"]).to eq("expired")
      expect(body["reason_code"]).to eq("challenge_expired")
      # service-attributed, null human actor
      expect(body["service_identity_id"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)
      expect(body["actor_id"]).to be_nil
      expect(body["account_id"]).to be_nil
    end

    it "cryptographically destroys the challenge material and makes redelivery unavailable" do
      c = issued_challenge
      reference = vr(c[:vid])["challenge_ciphertext_reference"]
      expect(reference).not_to be_nil

      expire(c[:vid], c[:g][:organization_id])

      row = vr(c[:vid])
      expect(row["challenge_ciphertext_reference"]).to be_nil
      expect(row["challenge_key_id"]).to be_nil
      # The F-02 record is erased: a reveal under the correct AAD now returns nil.
      aad = Platform::Encryption::Aad.for(application: "verification", record_type: "verification_request",
                                          record_id: c[:vid], purpose: "challenge_token", tenant: c[:g][:organization_id])
      expect(Platform::Encryption.reveal(reference, aad:)).to be_nil
      # The immutable challenge digest survives.
      expect(DbInspector.one("SELECT challenge_token_sha256 FROM verification_requests WHERE id=$1::uuid", [c[:vid]])["challenge_token_sha256"]).not_to be_nil
    end

    it "attributes the expiry to the Service Identity with a null actor" do
      c = issued_challenge
      expire(c[:vid], c[:g][:organization_id])
      execution = DbInspector.one("SELECT * FROM command_executions WHERE command_type='wf003.expire_verification_request'")
      expect(execution["service_identity_id"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)
      expect(execution["actor_id"]).to be_nil
      audit = DbInspector.one("SELECT * FROM audit_record_registry WHERE entity_id=$1::uuid AND reason_code='challenge_expired'", [c[:vid]])
      expect(audit["service_identity_id"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)
      expect(audit["actor_id"]).to be_nil
      expect(audit["to_state"]).to eq("expired")
    end

    it "makes redelivery unavailable through the issuance path once expired" do
      g = bootstrap
      sid = register_source(g, "https://redeliver.example")
      first = issue(g, sid, "redeliver-key")
      vid = first.payload[:verification_request_id]
      expect(first.payload[:challenge_token]).to be_a(String)

      expire(vid, g[:organization_id])

      # An exact re-issue by the original actor now finds the Request terminal (expired):
      # identifiers and status only, never challenge material.
      replay = issue(g, sid, "redeliver-key")
      expect(replay.replayed).to be(true)
      expect(replay.payload[:challenge_token]).to be_nil
    end
  end

  describe "the timer changes nothing when it must not fire" do
    it "at exactly expires_at, expiry wins (equality is due)" do
      c = issued_challenge
      expect(expire(c[:vid], c[:g][:organization_id], ctx: executor_ctx(expires_at))).to be_success
      expect(vr(c[:vid])["request_status"]).to eq("expired")
    end

    it "rejects a timer arriving before the expiry instant as scheduled_action_not_due" do
      c = issued_challenge
      result = expire(c[:vid], c[:g][:organization_id], ctx: executor_ctx(expires_at - 1))
      expect(result.reason_code).to eq("scheduled_action_not_due")
      expect(vr(c[:vid])["request_status"]).to eq("pending")
    end

    it "rejects a due instant that disagrees with the target as scheduled_action_target_mismatch" do
      c = issued_challenge
      result = expire(c[:vid], c[:g][:organization_id], due_at: expires_at + 60)
      expect(result.reason_code).to eq("scheduled_action_target_mismatch")
      expect(vr(c[:vid])["request_status"]).to eq("pending")
    end

    it "rejects a mismatched target_type before touching the database" do
      c = issued_challenge
      result = expire(c[:vid], c[:g][:organization_id], target_type: "role_assignment")
      expect(result.reason_code).to eq("scheduled_action_target_mismatch")
    end

    it "refuses a target the service cannot see as scheduled_action_target_mismatch" do
      c = issued_challenge
      # A Request id that does not exist in the action's Organization context is
      # invisible under RLS — a correctly created action can never do this.
      result = expire(SecureRandom.uuid_v7, c[:g][:organization_id])
      expect(result.reason_code).to eq("scheduled_action_target_mismatch")
    end

    it "rejects an unsupported schema" do
      c = issued_challenge
      expect(expire(c[:vid], c[:g][:organization_id], schema: "2.0").reason_code).to eq("command_schema_unsupported")
    end

    it "refuses an already-terminal Request as verification_request_not_pending" do
      c = issued_challenge
      expire(c[:vid], c[:g][:organization_id]) # first expiry
      # A distinct action (different identity) firing again finds the Request expired.
      result = expire(c[:vid], c[:g][:organization_id])
      expect(result.reason_code).to eq("verification_request_not_pending")
      expect(vr(c[:vid])["state_version"].to_i).to eq(1) # unchanged since the first expiry
    end

    it "is idempotent on an exact action replay: same result, no second event" do
      c = issued_challenge
      ident = SecureRandom.random_bytes(32)
      aid = SecureRandom.uuid_v7
      first = expire(c[:vid], c[:g][:organization_id], identity: ident, action_id: aid)
      replay = expire(c[:vid], c[:g][:organization_id], identity: ident, action_id: aid)
      expect(first).to be_success
      expect(replay.replayed).to be(true)
      expect(wf003_events("SourceVerificationExpired").size).to eq(1)
    end
  end

  describe "dispatch wiring" do
    it "resolves the verification_request_expire kind to the ExpireVerificationRequest handler" do
      entry = Platform::ScheduledActions::Registry.default.resolve(action_kind: "verification_request_expire", action_schema_version: "1.0")
      expect(entry.handler).to eq(Workflows::Wf003::Handlers::ExpireVerificationRequest)
      expect(entry.command).to eq(Workflows::Wf003::Commands::ExpireVerificationRequest)
      expect(entry.operation).to eq("ExpireVerificationRequest")
    end
  end
end
