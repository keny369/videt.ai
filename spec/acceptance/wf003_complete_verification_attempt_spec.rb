# frozen_string_literal: true

require "rails_helper"
require "digest"

# WF-003 CompleteVerificationAttempt (APPLICATION_LAYER.md § WF-003; CAP-005
# MTX-028/051/056; SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And Evidence;
# contracts/S-05.json).
#
# The observation-recording limb of S-05: the verification lifecycle service runs a
# reserved attempt's observation (the S-05-003 engine, provider call injected) and
# records exactly one restricted verification_observation Evidence (F-03), one
# SourceVerificationObserved, the attempt reserved -> completed, and the Request
# last-observed/marker update — atomically, idempotently. A matched observation is
# RECORDED but the Source is LEFT proposed and the Request pending: the matched success
# commit is S-05-006, proved unreachable here. The chain is production-real: genesis, a
# registered Source, an issued challenge and a reserved on-demand attempt.
RSpec.describe "WF-003 complete verification attempt", type: :acceptance,
               acceptance_ids: ["AC-CAP-005", "AC-WF-003"], test_types: %w[TYP-E2E TYP-INT TYP-SEC TYP-DATA TYP-OBS] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def act_now = fixed_now + 60
  def bc = Platform::BaselineContent
  def conn = DbInspector.connection

  let(:identity) { { issuer_key: "https://id.example/oidc", subject: "founder-#{SecureRandom.hex(8)}" } }

  def service_ctx(at)
    Platform::RequestContext.for_service(service_identity_id: Platform::ServiceIdentity::IDENTITY_SERVICE,
                                         clock: Platform::Clock.fixed(at), ids: Platform::Ids.system,
                                         correlation_id: SecureRandom.uuid_v7)
  end

  def act_ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(act_now), ids: Platform::Ids.system,
                                                   correlation_id: SecureRandom.uuid_v7)

  # The verification lifecycle service running the observation (a null human actor).
  def observer_ctx(at = act_now)
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
        organization_display_name: "Acme", first_project: GenesisProjectProfile.body("Genesis"),
        access_policy_content_sha256: bc.access_policy_sha256, entitlement_policy_content_sha256: bc.entitlement_policy_sha256,
        plan_content_sha256: bc.plan_sha256, requested_at_utc: fixed_now
      ), request_context: service_ctx(fixed_now)
    ).payload
  end

  def register_source(g, uri = "https://shop.acme.example")
    Workflows::Wf004::Handlers::RegisterSource.new.call(
      command: Workflows::Wf004::Commands::RegisterSource.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "rs-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
        registration_schema_version: "source-registration-v1", submitted_root_uri: uri,
        expected_state_version: 0, requested_at_utc: fixed_now
      ), request_context: act_ctx
    ).payload[:source_id]
  end

  def issue(g, sid)
    Workflows::Wf003::Handlers::IssueVerificationChallenge.new.call(
      command: Workflows::Wf003::Commands::IssueVerificationChallenge.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "vc-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
        source_id: sid, method: "dns_txt", expected_state_version: 0, requested_at_utc: act_now
      ), request_context: act_ctx
    )
  end

  def reserve(g, vid, expected: 0)
    Workflows::Wf003::Handlers::ReserveVerificationAttempt.new.call(
      command: Workflows::Wf003::Commands::ReserveVerificationAttempt.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "rv-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
        verification_request_id: vid, expected_state_version: expected, requested_at_utc: act_now
      ), request_context: act_ctx
    )
  end

  def complete(org:, vid:, aid:, outbound:, ctx: observer_ctx)
    Workflows::Wf003::Handlers::CompleteVerificationAttempt.new.call(
      command: Workflows::Wf003::Commands::CompleteVerificationAttempt.new(
        command_id: SecureRandom.uuid_v7, schema_version: "1.0", organization_id: org,
        verification_request_id: vid, verification_attempt_id: aid, requested_at_utc: act_now
      ), request_context: ctx, outbound:
    )
  end

  # A registered proposed Source, an issued pending Request and a reserved on-demand
  # attempt — the precondition for recording an observation.
  def reserved_attempt(uri: "https://shop.acme.example")
    g = bootstrap
    sid = register_source(g, uri)
    r = issue(g, sid)
    token = r.payload[:challenge_token]
    vid = r.payload[:verification_request_id]
    aid = reserve(g, vid).payload[:verification_attempt_id]
    { g:, org: g[:organization_id], source_id: sid, vid:, aid:, token: }
  end

  # ---- injected F-01 observation outcomes (duck-typed; never the real network) ----
  def obj(**methods)
    o = Object.new
    methods.each { |name, value| o.define_singleton_method(name) { value } }
    o
  end

  def outbound_dns(answer)
    fake = Object.new
    fake.define_singleton_method(:fetch_dns_txt) { |*_a, **_k| answer }
    fake
  end

  def matched(token) = outbound_dns(obj(refused?: false, records: [["f1-verification=#{token}"]]))
  def mismatch = outbound_dns(obj(refused?: false, records: [["f1-verification=not-the-token"]]))
  def dns_timeout = outbound_dns(obj(refused?: true, reason: :resolver_timeout))

  # ---- inspectors ----
  def vr(id) = DbInspector.one("SELECT * FROM verification_requests WHERE id = $1::uuid", [id])
  def va(id) = DbInspector.one("SELECT * FROM verification_attempts WHERE id = $1::uuid", [id])
  def evidence_for(aid) = DbInspector.all("SELECT * FROM evidence WHERE producer_id = 'wf003.verification_observation' AND attempt_id = $1", [aid])
  def observed_events(vid) = DbInspector.all("SELECT * FROM event_registry WHERE event_type = 'SourceVerificationObserved' AND aggregate_id = $1::uuid", [vid])

  # ------------------------------------------------------------------------

  # A matched observation now also VERIFIES (S-05-006); this spec keeps the recording
  # assertions and the atomic success commit is proved in detail in
  # spec/acceptance/wf003_source_verification_success_spec.rb.
  describe "records a matched observation (and, since S-05-006, verifies the Source)" do
    it "completes the attempt, produces one restricted Evidence and one SourceVerificationObserved" do
      s = reserved_attempt
      result = complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: matched(s[:token]))

      expect(result).to be_success
      expect(result.payload[:match_decision]).to eq("matched")
      expect(result.payload[:attempt_state]).to eq("completed")
      expect(result.payload[:request_status]).to eq("verified")

      a = va(s[:aid])
      expect(a["state"]).to eq("completed")
      expect(a["match_decision"]).to eq("matched")
      expect(a["reason_code"]).to eq("matched")
      expect(a["network_outcome"]).to eq("response")
      expect(a["started_at_utc"]).not_to be_nil
      expect(a["completed_at_utc"]).not_to be_nil
      expect(a["observed_value_sha256"]).not_to be_nil

      ev = evidence_for(s[:aid])
      expect(ev.size).to eq(1)
      expect(ev.first["evidence_type"]).to eq("verification_observation")
      expect(ev.first["data_classification"]).to eq("restricted")
      expect(ev.first["id"]).to eq(result.payload[:evidence_id])

      events = observed_events(s[:vid])
      expect(events.size).to eq(1)
      body = JSON.parse(DbInspector.one("SELECT convert_from(event_bytes,'UTF8') AS b FROM event_registry WHERE id = $1::uuid", [events.first["id"]])["b"])
      expect(body["evidence_id"]).to eq(result.payload[:evidence_id])
      expect(body["match_decision"]).to eq("matched")
      expect(body["service_identity_id"]).not_to be_nil
      expect(body["actor_id"]).to be_nil
    end

    it "verifies the Request and Source on a match and emits SourceVerified (S-05-006)" do
      s = reserved_attempt
      complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: matched(s[:token]))

      expect(vr(s[:vid])["request_status"]).to eq("verified")
      expect(DbInspector.one("SELECT state FROM sources WHERE id = $1::uuid", [s[:source_id]])["state"]).to eq("verified")
      expect(DbInspector.all("SELECT id FROM event_registry WHERE event_type = 'SourceVerified'").size).to eq(1)
    end

    it "clears the in-progress marker and records the last-observed / last-on-demand-completed instants without a second count" do
      s = reserved_attempt
      expect(vr(s[:vid])["on_demand_in_progress_attempt_id"]).to eq(s[:aid])
      complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: matched(s[:token]))

      row = vr(s[:vid])
      expect(row["on_demand_in_progress_attempt_id"]).to be_nil
      expect(row["last_observed_at_utc"]).not_to be_nil
      expect(row["last_on_demand_completed_at_utc"]).not_to be_nil
      # attempt_count was incremented at reservation, never here.
      expect(row["attempt_count"].to_i).to eq(1)
      expect(row["on_demand_observation_count"].to_i).to eq(1)
    end
  end

  describe "non-verifying outcomes are recorded and leave the Source proposed" do
    it "records a content mismatch as not_matched" do
      s = reserved_attempt
      result = complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: mismatch)
      expect(result.payload[:match_decision]).to eq("not_matched")
      expect(result.payload[:reason_code]).to eq("dns_value_mismatch")
      expect(va(s[:aid])["state"]).to eq("completed")
      expect(evidence_for(s[:aid]).size).to eq(1)
      expect(vr(s[:vid])["request_status"]).to eq("pending")
    end

    it "records a resolver timeout as indeterminate and still persists Evidence" do
      s = reserved_attempt
      result = complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: dns_timeout)
      expect(result.payload[:match_decision]).to eq("indeterminate")
      expect(result.payload[:reason_code]).to eq("dns_timeout")
      expect(evidence_for(s[:aid]).size).to eq(1)
      expect(vr(s[:vid])["request_status"]).to eq("pending")
      expect(DbInspector.one("SELECT state FROM sources WHERE id = $1::uuid", [s[:source_id]])["state"]).to eq("proposed")
    end
  end

  describe "the challenge token and raw observation never appear at rest" do
    it "keeps the token out of the Evidence row, the attempt row, the event and the audit" do
      s = reserved_attempt
      result = complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: matched(s[:token]))
      token = s[:token]

      ev_row = DbInspector.one("SELECT * FROM evidence WHERE id = $1::uuid", [result.payload[:evidence_id]])
      expect(ev_row.values.compact.map(&:to_s).join(" ")).not_to include(token)
      # The payload is behind an F-02 reference; the digest is a hash, not the token.
      expect(ev_row["payload_reference"]).to match(/\A[0-9a-f-]{36}\z/)

      expect(va(s[:aid]).values.compact.map(&:to_s).join(" ")).not_to include(token)
      event_bytes = DbInspector.one("SELECT convert_from(event_bytes,'UTF8') AS b FROM event_registry WHERE aggregate_id = $1::uuid AND event_type = 'SourceVerificationObserved'", [s[:vid]])["b"]
      expect(event_bytes).not_to include(token)
      audit = DbInspector.one("SELECT payload::text AS p FROM audit_record_registry WHERE entity_id = $1::uuid AND workflow_id = 'WF-003' AND to_state = 'completed'", [s[:aid]])["p"]
      expect(audit).not_to include(token)
    end
  end

  describe "idempotent by the reserved attempt identity" do
    it "returns the same recorded result on retry, producing no second Evidence or event" do
      s = reserved_attempt
      first = complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: matched(s[:token]))
      replay = complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: matched(s[:token]))

      expect(first).to be_success
      expect(replay.replayed).to be(true)
      expect(replay.payload[:evidence_id]).to eq(first.payload[:evidence_id])
      expect(evidence_for(s[:aid]).size).to eq(1)
      expect(observed_events(s[:vid]).size).to eq(1)
      expect(va(s[:aid])["state"]).to eq("completed")
    end
  end

  describe "preconditions" do
    it "rejects a completion for an attempt on a terminal Request as verification_request_not_pending" do
      s = reserved_attempt
      # Expire the Request through the one guard-legal edge (pending -> expired).
      conn.exec_params(<<~SQL, [s[:vid]])
        UPDATE verification_requests
        SET request_status = 'expired', decision_reason_code = 'challenge_expired',
            challenge_ciphertext_reference = NULL, challenge_key_id = NULL
        WHERE id = $1::uuid
      SQL
      result = complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: matched(s[:token]))
      expect(result.reason_code).to eq("verification_request_not_pending")
      expect(va(s[:aid])["state"]).to eq("reserved")
      expect(evidence_for(s[:aid])).to be_empty
    end

    it "rejects a completion whose attempt does not belong to the named Request as target mismatch" do
      s = reserved_attempt
      result = complete(org: s[:org], vid: s[:vid], aid: SecureRandom.uuid_v7, outbound: matched(s[:token]))
      expect(result.reason_code).to eq("verification_attempt_target_mismatch")
    end
  end
end
