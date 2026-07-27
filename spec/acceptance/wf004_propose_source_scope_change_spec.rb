# frozen_string_literal: true

require "rails_helper"

# WF-004 ProposeSourceScopeChange (S-06-003, the pending-request path;
# WORKFLOW_SPECIFICATIONS.md § Source Scope Change Contract :414; contracts/S-06.json
# MTX-029). End to end over a production-real chain: genesis, a registered Source, a
# matched ownership verification (which pins source-scope-interim-v1), then a proposed
# scope change. This tranche creates PENDING requests only and rejects boundary
# violations; classification (S-06-002) decides contraction/expansion but both remain
# pending here (the fail-closed interim).
RSpec.describe "WF-004 propose source scope change", type: :acceptance,
               acceptance_ids: ["AC-CAP-006", "AC-WF-004"], test_types: %w[TYP-E2E TYP-INT TYP-DATA TYP-SEC] do
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

  # A verified Source carrying source-scope-interim-v1, ready for a scope change.
  def verified_source
    g = bootstrap
    sid = register_source(g)
    r = issue(g, sid)
    aid = reserve(g, r.payload[:verification_request_id])
    complete_match(g[:organization_id], r.payload[:verification_request_id], aid, r.payload[:challenge_token])
    { g:, org: g[:organization_id], project_id: g[:project_id], source_id: sid }
  end

  def propose(v, reason: "narrow the crawl scope to the shop section only",
              schemes: ["https"], ports: [443], includes: ["/shop"], excludes: [], query: "retain_all",
              expected: "source-scope-interim-v1", key: "prop-#{SecureRandom.hex(6)}", source_id: nil, ctx: act_ctx)
    Workflows::Wf004::Handlers::ProposeSourceScopeChange.new.call(
      command: Workflows::Wf004::Commands::ProposeSourceScopeChange.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
        session_id: v[:g][:session_id], organization_id: v[:org], project_id: v[:project_id],
        source_id: source_id || v[:source_id], expected_active_policy_version: expected,
        proposed_allowed_schemes: schemes, proposed_allowed_ports: ports, proposed_include_prefixes: includes,
        proposed_exclude_prefixes: excludes, proposed_query_handling: query, request_reason: reason,
        requested_at_utc: act_now), request_context: ctx)
  end

  def requests(sid) = DbInspector.all("SELECT * FROM source_scope_change_requests WHERE source_id = $1::uuid", [sid])
  def events(type) = DbInspector.all("SELECT * FROM event_registry WHERE event_type = $1", [type])
  def expiry_actions(rid) = DbInspector.all("SELECT * FROM scheduled_actions WHERE action_kind = 'source_scope_request_expire' AND target_id = $1::uuid", [rid])

  describe "a contraction creates a pending request" do
    it "persists one pending request with the proposed rules, a SourceScopeChangeRequested event and a 24h expiry timer" do
      v = verified_source
      result = propose(v)
      expect(result.success?).to be(true)
      rid = result.payload[:source_scope_change_request_id]

      rows = requests(v[:source_id])
      expect(rows.size).to eq(1)
      row = rows.first
      expect(row["state"]).to eq("pending")
      expect(row["expected_active_policy_version"]).to eq("source-scope-interim-v1")
      expect(row["proposed_include_prefixes"]).to eq("{/shop}")
      expect(row["requester_account_id"]).to eq(v[:g][:account_id])
      # due_at is exactly 24h after requested_at
      gap = DbInspector.one("SELECT EXTRACT(EPOCH FROM (due_at_utc - requested_at_utc)) AS s FROM source_scope_change_requests WHERE id = $1::uuid", [rid])["s"].to_f
      expect(gap).to eq(86_400.0)

      ev = events("SourceScopeChangeRequested")
      expect(ev.size).to eq(1)
      expect(ev.first["aggregate_id"]).to eq(rid)

      expect(expiry_actions(rid).size).to eq(1)
      expect(expiry_actions(rid).first["target_type"]).to eq("source_scope_change_request")
    end

    it "records the full command ledger (execution, authorization decision, audit, result, idempotency)" do
      v = verified_source
      result = propose(v)
      cmd = result.payload[:source_scope_change_request_id]
      expect(DbInspector.all("SELECT id FROM command_executions WHERE target_id = $1::uuid", [cmd])).not_to be_empty
      expect(DbInspector.all("SELECT id FROM authorization_decisions WHERE resource_id = $1::uuid AND action = 'source.scope.propose'", [v[:source_id]])).not_to be_empty
      expect(DbInspector.all("SELECT id FROM audit_record_registry WHERE entity_id = $1::uuid AND outcome = 'success'", [cmd])).not_to be_empty
    end
  end

  describe "boundary violations are rejected through the failure path" do
    it "rejects a non-HTTPS scheme and writes no request" do
      v = verified_source
      result = propose(v, schemes: %w[https http])
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("unsupported_source_scheme")
      expect(requests(v[:source_id])).to be_empty
    end

    it "rejects a non-default port and writes no request" do
      v = verified_source
      result = propose(v, ports: [443, 8443])
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("source_scope_boundary_violation")
      expect(requests(v[:source_id])).to be_empty
    end
  end

  describe "idempotency" do
    it "an exact replay returns the stored request and creates no second row" do
      v = verified_source
      first = propose(v, key: "same-key")
      second = propose(v, key: "same-key")
      expect(second.payload[:source_scope_change_request_id]).to eq(first.payload[:source_scope_change_request_id])
      expect(requests(v[:source_id]).size).to eq(1)
    end

    it "changed content under the same key is idempotency_conflict" do
      v = verified_source
      propose(v, key: "same-key", includes: ["/shop"])
      conflict = propose(v, key: "same-key", includes: ["/blog"])
      expect(conflict.success?).to be(false)
      expect(conflict.failure.reason_code).to eq("idempotency_conflict")
      expect(requests(v[:source_id]).size).to eq(1)
    end
  end

  describe "request-shape and precondition failures" do
    it "rejects a reason shorter than 20 characters" do
      v = verified_source
      result = propose(v, reason: "too short")
      expect(result.failure.reason_code).to eq("source_scope_reason_invalid")
      expect(requests(v[:source_id])).to be_empty
    end

    it "rejects a stale expected active-policy version" do
      v = verified_source
      result = propose(v, expected: "source-scope-interim-v0")
      expect(result.failure.reason_code).to eq("stale_active_policy_version")
      expect(requests(v[:source_id])).to be_empty
    end

    it "rejects a proposal against an unverified Source (no active policy)" do
      g = bootstrap
      sid = register_source(g) # proposed, never verified -> no current_scope_policy_id
      v = { g:, org: g[:organization_id], project_id: g[:project_id], source_id: sid }
      result = propose(v)
      expect(result.failure.reason_code).to eq("source_not_verified")
      expect(requests(sid)).to be_empty
    end

    it "refuses a Source outside the actor's tenant" do
      v = verified_source
      result = propose(v, source_id: SecureRandom.uuid_v7)
      expect(result.failure.reason_code).to eq("tenant_mismatch")
    end
  end
end
