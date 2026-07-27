# frozen_string_literal: true

require "rails_helper"

# WF-004 Source lifecycle (S-06-006; PRULE-006 / contracts/S-06.json MTX-057; MTX-029 lifecycle
# limb). ActivateSource / DisableSource / ReactivateSource / RemoveSource over a production-real
# chain: genesis, a registered + verified Source (carrying source-scope-interim-v1), then the
# lifecycle transitions.
#
# Covers the PRULE-006 state path: the four allowed edges each succeed exactly once
# (verified->active, active->disabled, disabled->active, disabled->removed); every unlisted or
# stale transition is denied AND audited; a TechnicalImplementer cannot mutate lifecycle; removal
# is allowed only from disabled and frees the host for a fresh lineage; each transition pins the
# active policy version and emits its event once.
RSpec.describe "WF-004 source lifecycle", type: :acceptance,
               acceptance_ids: ["AC-CAP-006", "AC-WF-004"], test_types: %w[TYP-E2E TYP-DATA TYP-SEC TYP-INT] do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 27, 10, 0, 0)
  def act_now = fixed_now + 60
  def bc = Platform::BaselineContent

  let(:identity) { { issuer_key: "https://id.example/oidc", subject: "founder-#{SecureRandom.hex(8)}" } }

  def service_ctx(at)
    Platform::RequestContext.for_service(service_identity_id: Platform::ServiceIdentity::IDENTITY_SERVICE,
                                         clock: Platform::Clock.fixed(at), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
  end
  def act_ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(act_now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)

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

  def complete_match(org, vid, aid, token)
    outbound = Object.new.tap { |o| o.define_singleton_method(:fetch_dns_txt) { |*_a, **_k| Object.new.tap { |a| a.define_singleton_method(:refused?) { false }; a.define_singleton_method(:records) { [["f1-verification=#{token}"]] } } } }
    ctx = Platform::RequestContext.for_service(service_identity_id: Platform::ServiceIdentity.scheduled_action_executor,
                                               clock: Platform::Clock.fixed(act_now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
    Workflows::Wf003::Handlers::CompleteVerificationAttempt.new.call(
      command: Workflows::Wf003::Commands::CompleteVerificationAttempt.new(command_id: SecureRandom.uuid_v7, schema_version: "1.0", organization_id: org,
        verification_request_id: vid, verification_attempt_id: aid, requested_at_utc: act_now), request_context: ctx, outbound:)
  end

  def verified_source(uri = "https://shop.acme.example")
    g = bootstrap
    sid = register_source(g, uri)
    r = issue(g, sid)
    aid = reserve(g, r.payload[:verification_request_id])
    complete_match(g[:organization_id], r.payload[:verification_request_id], aid, r.payload[:challenge_token])
    { g:, org: g[:organization_id], project_id: g[:project_id], source_id: sid }
  end

  def seeded_actor(v, role)
    a = TenantSeeder.seed_authorized_admin(organization_id: v[:org], canonical_role: role,
                                           with_policy: false, issued_at: fixed_now - 300)
    a[:session_id]
  end

  def source_row(sid) = DbInspector.one("SELECT * FROM sources WHERE id = $1::uuid", [sid])
  def sv(sid) = source_row(sid)["state_version"].to_i
  def events(type, sid) = DbInspector.all("SELECT * FROM event_registry WHERE event_type = $1 AND aggregate_id = $2::uuid", [type, sid])
  def audit_failures(reason) = DbInspector.all("SELECT * FROM audit_record_registry WHERE reason_code = $1 AND outcome = 'failure'", [reason])

  def activate(v, expected:, key: "act-#{SecureRandom.hex(4)}", source_id: nil, session: nil)
    Workflows::Wf004::Handlers::ActivateSource.new.call(
      command: Workflows::Wf004::Commands::ActivateSource.new(command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
        session_id: session || v[:g][:session_id], organization_id: v[:org], project_id: v[:project_id],
        source_id: source_id || v[:source_id], expected_state_version: expected, requested_at_utc: act_now), request_context: act_ctx)
  end

  def reactivate(v, expected:, key: "react-#{SecureRandom.hex(4)}")
    Workflows::Wf004::Handlers::ReactivateSource.new.call(
      command: Workflows::Wf004::Commands::ReactivateSource.new(command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
        session_id: v[:g][:session_id], organization_id: v[:org], project_id: v[:project_id],
        source_id: v[:source_id], expected_state_version: expected, requested_at_utc: act_now), request_context: act_ctx)
  end

  def disable(v, expected:, reason: "pausing crawl coverage during a site migration", key: "dis-#{SecureRandom.hex(4)}")
    Workflows::Wf004::Handlers::DisableSource.new.call(
      command: Workflows::Wf004::Commands::DisableSource.new(command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
        session_id: v[:g][:session_id], organization_id: v[:org], project_id: v[:project_id],
        source_id: v[:source_id], expected_state_version: expected, lifecycle_reason: reason, requested_at_utc: act_now), request_context: act_ctx)
  end

  def remove(v, expected:, reason: "decommissioning this source permanently", key: "rem-#{SecureRandom.hex(4)}", source_id: nil)
    Workflows::Wf004::Handlers::RemoveSource.new.call(
      command: Workflows::Wf004::Commands::RemoveSource.new(command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
        session_id: v[:g][:session_id], organization_id: v[:org], project_id: v[:project_id],
        source_id: source_id || v[:source_id], expected_state_version: expected, lifecycle_reason: reason, requested_at_utc: act_now), request_context: act_ctx)
  end

  describe "the allowed edges each succeed exactly once" do
    it "walks verified -> active -> disabled -> active -> disabled -> removed, pinning the policy version and emitting each event once" do
      v = verified_source
      sid = v[:source_id]

      a = activate(v, expected: sv(sid))
      expect(a.success?).to be(true)
      expect(a.payload[:state]).to eq("active")
      expect(a.payload[:pinned_policy_version]).to eq("source-scope-interim-v1")
      expect(source_row(sid)["state"]).to eq("active")
      expect(source_row(sid)["activated_at"]).not_to be_nil

      d = disable(v, expected: sv(sid))
      expect(d.success?).to be(true)
      expect(source_row(sid)["state"]).to eq("disabled")
      expect(d.payload[:affected_running_crawls]).to eq([]) # degenerate pre-S-07

      r = reactivate(v, expected: sv(sid))
      expect(r.success?).to be(true)
      expect(source_row(sid)["state"]).to eq("active")

      disable(v, expected: sv(sid))
      rm = remove(v, expected: sv(sid))
      expect(rm.success?).to be(true)
      expect(source_row(sid)["state"]).to eq("removed")
      expect(source_row(sid)["removed_at"]).not_to be_nil

      expect(events("SourceActivated", sid).size).to eq(2)   # activate + reactivate
      expect(events("SourceDisabled", sid).size).to eq(2)
      expect(events("SourceRemoved", sid).size).to eq(1)
    end
  end

  describe "unlisted transitions are denied and audited" do
    it "denies activating an unverified (proposed) Source" do
      g = bootstrap
      sid = register_source(g) # proposed, never verified
      v = { g:, org: g[:organization_id], project_id: g[:project_id], source_id: sid }
      result = activate(v, expected: sv(sid))
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("source_lifecycle_transition_invalid")
      expect(source_row(sid)["state"]).to eq("proposed")
      expect(audit_failures("source_lifecycle_transition_invalid")).not_to be_empty # denied AND audited
    end

    it "denies a direct active -> removed (removal only from disabled)" do
      v = verified_source
      activate(v, expected: sv(v[:source_id]))
      result = remove(v, expected: sv(v[:source_id]))
      expect(result.failure.reason_code).to eq("source_lifecycle_transition_invalid")
      expect(source_row(v[:source_id])["state"]).to eq("active")
    end

    it "denies any transition from removed" do
      v = verified_source
      activate(v, expected: sv(v[:source_id]))
      disable(v, expected: sv(v[:source_id]))
      remove(v, expected: sv(v[:source_id]))
      result = reactivate(v, expected: sv(v[:source_id]))
      expect(result.failure.reason_code).to eq("source_lifecycle_transition_invalid")
      expect(source_row(v[:source_id])["state"]).to eq("removed")
    end
  end

  describe "concurrency and idempotency" do
    it "denies a stale Source state version with no side effect" do
      v = verified_source
      result = activate(v, expected: sv(v[:source_id]) + 5)
      expect(result.failure.reason_code).to eq("stale_state_version")
      expect(source_row(v[:source_id])["state"]).to eq("verified")
    end

    it "replays an exact activation by its key and a distinct repeat is an invalid transition" do
      v = verified_source
      base = sv(v[:source_id])
      first = activate(v, expected: base, key: "same")
      replay = activate(v, expected: base, key: "same")
      expect(replay.replayed).to be(true)
      expect(replay.payload[:state]).to eq("active")
      distinct = activate(v, expected: base, key: "other")
      expect(distinct.failure.reason_code).to eq("source_lifecycle_transition_invalid")
    end
  end

  describe "authorization" do
    it "refuses a Technical Implementer (no source.lifecycle.manage)" do
      v = verified_source
      ti = seeded_actor(v, "TechnicalImplementer")
      result = activate(v, expected: sv(v[:source_id]), session: ti)
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("source_lifecycle_unauthorized")
      expect(source_row(v[:source_id])["state"]).to eq("verified")
    end

    it "refuses a Source outside the actor's tenant" do
      v = verified_source
      result = activate(v, expected: 0, source_id: SecureRandom.uuid_v7)
      expect(result.failure.reason_code).to eq("tenant_mismatch")
    end

    it "allows a MarketingOperator (the other source.lifecycle.manage holder) to transition" do
      v = verified_source
      mkt = seeded_actor(v, "MarketingOperator")
      result = activate(v, expected: sv(v[:source_id]), session: mkt)
      expect(result.success?).to be(true)
      expect(source_row(v[:source_id])["state"]).to eq("active")
    end
  end

  describe "removal frees the host for a fresh lineage" do
    it "lets the same canonical host be registered again after removal, on a new Source id" do
      v = verified_source
      activate(v, expected: sv(v[:source_id]))
      disable(v, expected: sv(v[:source_id]))
      remove(v, expected: sv(v[:source_id]))

      new_sid = register_source(v[:g], "https://shop.acme.example")
      expect(new_sid).not_to eq(v[:source_id])
      expect(source_row(new_sid)["state"]).to eq("proposed")
    end
  end
end
