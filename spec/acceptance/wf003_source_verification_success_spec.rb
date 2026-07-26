# frozen_string_literal: true

require "rails_helper"

# WF-003 matched success commit + source-scope-interim-v1 (S-05-006) — the atomic
# multi-root success inside CompleteVerificationAttempt (SCORE_EVIDENCE_MODEL.md :155;
# contracts/S-05.json MTX-028/051; WORKFLOW_SPECIFICATIONS.md § WF-003; owner Option A,
# ADR-042).
#
# On a MATCHED observation the completion transaction commits, inseparably: Request
# `verified`/`matched` with the challenge erased, `SourceVerified`, `Source.proposed ->
# verified` with the interim scope policy pinned, and the materialization of
# `source-scope-interim-v1`. None may appear without the others; the transition fires
# exactly once. The chain is production-real: genesis, a registered Source, an issued
# challenge, a reserved on-demand attempt, then a matched completion.
RSpec.describe "WF-003 source verification success commit", type: :acceptance,
               acceptance_ids: ["AC-CAP-005", "AC-WF-003"], test_types: %w[TYP-E2E TYP-INT TYP-DATA TYP-SEC] do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 20, 10, 0, 0)
  def act_now = fixed_now + 60
  def bc = Platform::BaselineContent
  def conn = DbInspector.connection

  let(:identity) { { issuer_key: "https://id.example/oidc", subject: "founder-#{SecureRandom.hex(8)}" } }

  def service_ctx(at)
    Platform::RequestContext.for_service(service_identity_id: Platform::ServiceIdentity::IDENTITY_SERVICE,
                                         clock: Platform::Clock.fixed(at), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
  end
  def act_ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(act_now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
  def observer_ctx = Platform::RequestContext.for_service(service_identity_id: Platform::ServiceIdentity.scheduled_action_executor,
                                                          clock: Platform::Clock.fixed(act_now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)

  def bootstrap
    grant = ReceiptMinter.mint_bootstrap_grant_receipt(validated_at: fixed_now - 60, **identity)
    Workflows::Wf001::Handlers::RequestBootstrapGrant.new.call(
      command: Workflows::Wf001::Commands::RequestBootstrapGrant.new(command_id: SecureRandom.uuid_v7, idempotency_key: "grant-#{SecureRandom.hex(4)}",
        schema_version: "1.0", receipt_digest: grant[:receipt_digest], requested_at_utc: fixed_now - 60), request_context: service_ctx(fixed_now - 60))
    receipt = ReceiptMinter.mint_self_service_receipt(validated_at: fixed_now, **identity)
    Workflows::Wf001::Handlers::BootstrapOrganization.new.call(
      command: Workflows::Wf001::Commands::BootstrapOrganization.new(command_id: SecureRandom.uuid_v7, idempotency_key: "boot-#{SecureRandom.hex(4)}", schema_version: "1.0",
        receipt_digest: receipt[:receipt_digest], expected_grant_version: 0, organization_display_name: "Acme", project_display_name: "Genesis",
        project_objective: "discoverability_assessment", access_policy_content_sha256: bc.access_policy_sha256, entitlement_policy_content_sha256: bc.entitlement_policy_sha256,
        plan_content_sha256: bc.plan_sha256, requested_at_utc: fixed_now), request_context: service_ctx(fixed_now)).payload
  end

  def register_source(g, uri = "https://shop.acme.example")
    Workflows::Wf004::Handlers::RegisterSource.new.call(
      command: Workflows::Wf004::Commands::RegisterSource.new(command_id: SecureRandom.uuid_v7, idempotency_key: "rs-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id], registration_schema_version: "source-registration-v1",
        submitted_root_uri: uri, expected_state_version: 0, requested_at_utc: fixed_now), request_context: act_ctx).payload[:source_id]
  end

  def issue(g, sid)
    Workflows::Wf003::Handlers::IssueVerificationChallenge.new.call(
      command: Workflows::Wf003::Commands::IssueVerificationChallenge.new(command_id: SecureRandom.uuid_v7, idempotency_key: "vc-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id], source_id: sid, method: "dns_txt",
        expected_state_version: 0, requested_at_utc: act_now), request_context: act_ctx)
  end

  def reserve(g, vid)
    Workflows::Wf003::Handlers::ReserveVerificationAttempt.new.call(
      command: Workflows::Wf003::Commands::ReserveVerificationAttempt.new(command_id: SecureRandom.uuid_v7, idempotency_key: "rv-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id], verification_request_id: vid,
        expected_state_version: 0, requested_at_utc: act_now), request_context: act_ctx).payload[:verification_attempt_id]
  end

  def complete(org:, vid:, aid:, outbound:, at: act_now)
    ctx = Platform::RequestContext.for_service(service_identity_id: Platform::ServiceIdentity.scheduled_action_executor,
                                               clock: Platform::Clock.fixed(at), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
    Workflows::Wf003::Handlers::CompleteVerificationAttempt.new.call(
      command: Workflows::Wf003::Commands::CompleteVerificationAttempt.new(command_id: SecureRandom.uuid_v7, schema_version: "1.0", organization_id: org,
        verification_request_id: vid, verification_attempt_id: aid, requested_at_utc: at), request_context: ctx, outbound:)
  end

  def reserved_attempt(uri: "https://shop.acme.example")
    g = bootstrap
    sid = register_source(g, uri)
    r = issue(g, sid)
    { g:, org: g[:organization_id], project_id: g[:project_id], source_id: sid, vid: r.payload[:verification_request_id],
      token: r.payload[:challenge_token], aid: reserve(g, r.payload[:verification_request_id]) }
  end

  def obj(**m) = Object.new.tap { |o| m.each { |k, v| o.define_singleton_method(k) { v } } }
  def outbound_dns(answer) = Object.new.tap { |o| o.define_singleton_method(:fetch_dns_txt) { |*_a, **_k| answer } }
  def matched(token) = outbound_dns(obj(refused?: false, records: [["f1-verification=#{token}"]]))
  def mismatch = outbound_dns(obj(refused?: false, records: [["f1-verification=wrong"]]))

  def vr(id) = DbInspector.one("SELECT * FROM verification_requests WHERE id = $1::uuid", [id])
  def src(id) = DbInspector.one("SELECT * FROM sources WHERE id = $1::uuid", [id])
  def policies(sid) = DbInspector.all("SELECT * FROM source_scope_policies WHERE source_id = $1::uuid", [sid])
  def source_verified_events(sid) = DbInspector.all("SELECT * FROM event_registry WHERE event_type = 'SourceVerified' AND aggregate_id = $1::uuid", [sid])

  # ------------------------------------------------------------------------

  describe "the atomic matched success commit" do
    it "commits the Request verification, Source verification, SourceVerified and interim policy together" do
      s = reserved_attempt
      result = complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: matched(s[:token]))
      expect(result).to be_success
      expect(result.payload[:request_status]).to eq("verified")
      expect(result.payload[:source_state]).to eq("verified")

      request = vr(s[:vid])
      expect(request["request_status"]).to eq("verified")
      expect(request["decision_reason_code"]).to eq("matched")
      # Redelivery disablement: the challenge material is erased; the digest survives.
      expect(request["challenge_ciphertext_reference"]).to be_nil
      expect(request["challenge_key_id"]).to be_nil
      expect(request["challenge_token_sha256"]).not_to be_nil

      source = src(s[:source_id])
      expect(source["state"]).to eq("verified")
      expect(source["verified_at"]).not_to be_nil
      expect(source["current_scope_policy_id"]).to eq(result.payload[:source_scope_policy_id])

      expect(source_verified_events(s[:source_id]).size).to eq(1)
      body = JSON.parse(DbInspector.one("SELECT convert_from(event_bytes,'UTF8') AS b FROM event_registry WHERE id = $1::uuid",
                                        [source_verified_events(s[:source_id]).first["id"]])["b"])
      expect(body["to_state"]).to eq("verified")
      expect(body["reason_code"]).to eq("matched")
      expect(body["source_scope_policy_id"]).to eq(result.payload[:source_scope_policy_id])
    end

    it "materializes exactly the fixed source-scope-interim-v1 policy" do
      s = reserved_attempt(uri: "https://Shop.Acme.Example:443/")
      complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: matched(s[:token]))

      rows = policies(s[:source_id])
      expect(rows.size).to eq(1)
      p = rows.first
      expect(p["policy_version"]).to eq("source-scope-interim-v1")
      expect(p["scope"]).to eq("source")
      expect(p["canonical_host"]).to eq("shop.acme.example")
      expect(p["allowed_schemes"]).to eq("{https}")
      expect(p["allowed_ports"]).to eq("{443}")
      expect(p["include_prefixes"]).to eq("{/}")
      expect(p["exclude_prefixes"]).to eq("{}")
      expect(p["query_handling"]).to eq("retain_all")
      expect(p["content_sha256"]).not_to be_nil
    end
  end

  describe "none may appear without the others (atomicity)" do
    it "rolls the whole completion back when the Source is no longer proposed — no Evidence, no verification, no policy" do
      s = reserved_attempt
      # Simulate a concurrent verification: the Source is no longer proposed when the
      # matched completion reaches its success commit.
      conn.exec_params("UPDATE sources SET state = 'verified', state_version = state_version + 1 WHERE id = $1::uuid", [s[:source_id]])

      expect { complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: matched(s[:token])) }
        .to raise_error(Platform::InvariantViolation)

      # Nothing from the completion committed: the attempt is still reserved, the Request
      # still pending, no Evidence and no policy row exist.
      expect(DbInspector.one("SELECT state FROM verification_attempts WHERE id = $1::uuid", [s[:aid]])["state"]).to eq("reserved")
      expect(vr(s[:vid])["request_status"]).to eq("pending")
      expect(DbInspector.all("SELECT id FROM evidence WHERE attempt_id = $1", [s[:aid]])).to be_empty
      expect(policies(s[:source_id])).to be_empty
    end
  end

  describe "the transition fires exactly once" do
    it "replays a matched completion without re-transitioning or re-emitting or re-materializing" do
      s = reserved_attempt
      first = complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: matched(s[:token]))
      before_version = src(s[:source_id])["state_version"]
      replay = complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: matched(s[:token]))

      expect(replay.replayed).to be(true)
      expect(replay.payload[:source_scope_policy_id]).to eq(first.payload[:source_scope_policy_id])
      expect(policies(s[:source_id]).size).to eq(1)
      expect(source_verified_events(s[:source_id]).size).to eq(1)
      expect(src(s[:source_id])["state_version"]).to eq(before_version) # no re-transition
    end
  end

  describe "expiry wins at the boundary" do
    it "records a matched observation completing at expires_at_utc but does NOT verify (equality: expiry wins)" do
      s = reserved_attempt
      expires = act_now + (24 * 3600) # issued at act_now; the challenge is valid for exactly 24 hours
      result = complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: matched(s[:token]), at: expires)

      expect(result).to be_success
      expect(result.payload[:match_decision]).to eq("matched")
      expect(result.payload[:request_status]).to eq("pending")
      expect(result.payload[:source_state]).to eq("proposed")
      # The Source is not verified, the Request stays pending, and no policy/event appears.
      expect(vr(s[:vid])["request_status"]).to eq("pending")
      expect(src(s[:source_id])["state"]).to eq("proposed")
      expect(policies(s[:source_id])).to be_empty
      expect(source_verified_events(s[:source_id])).to be_empty
      # The observation itself is still recorded as Evidence.
      expect(DbInspector.all("SELECT id FROM evidence WHERE attempt_id = $1", [s[:aid]]).size).to eq(1)
    end

    it "verifies a matched observation completing strictly before expiry" do
      s = reserved_attempt
      before = act_now + (24 * 3600) - 1
      result = complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: matched(s[:token]), at: before)
      expect(result.payload[:request_status]).to eq("verified")
      expect(src(s[:source_id])["state"]).to eq("verified")
    end
  end

  describe "a non-matching outcome leaves the Source proposed and materializes no policy" do
    it "records a mismatch without verifying" do
      s = reserved_attempt
      result = complete(org: s[:org], vid: s[:vid], aid: s[:aid], outbound: mismatch)
      expect(result.payload[:match_decision]).to eq("not_matched")
      expect(vr(s[:vid])["request_status"]).to eq("pending")
      expect(src(s[:source_id])["state"]).to eq("proposed")
      expect(policies(s[:source_id])).to be_empty
      expect(source_verified_events(s[:source_id])).to be_empty
    end
  end
end
