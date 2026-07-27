# frozen_string_literal: true

require "rails_helper"

# WF-004 ProposeSourceScopeChange (WORKFLOW_SPECIFICATIONS.md § Source Scope Change Contract
# :414; contracts/S-06.json MTX-029). End to end over a production-real chain: genesis, a
# registered Source, a matched ownership verification (which pins source-scope-interim-v1),
# then a proposed scope change.
#
# S-06-004 fast-path: a contraction by any policy.source_scope.manage holder
# (OrganizationAdmin or MarketingOperator), or an expansion by an OrganizationAdmin, is
# created, self-approved and activated in the one transaction (SourceScopeChangeRequested +
# SourceScopeChangeApproved, one new immutable policy version, no expiry timer). Every other
# authorized proposal — a non-manage holder's contraction, a non-admin's expansion — creates
# a single PENDING request with a 24-hour expiry timer, awaiting DecideSourceScopeChange.
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

  # A verified Source (OrganizationAdmin actor `g`) carrying source-scope-interim-v1.
  def verified_source
    g = bootstrap
    sid = register_source(g)
    r = issue(g, sid)
    aid = reserve(g, r.payload[:verification_request_id])
    complete_match(g[:organization_id], r.payload[:verification_request_id], aid, r.payload[:challenge_token])
    { g:, org: g[:organization_id], project_id: g[:project_id], source_id: sid }
  end

  # A second same-Organization actor with a chosen non-admin role and a Session valid at the
  # fixed clock (no second Access Policy — the bootstrap one stays the sole active policy).
  def seeded_actor(v, role)
    a = TenantSeeder.seed_authorized_admin(organization_id: v[:org], canonical_role: role,
                                           with_policy: false, issued_at: fixed_now - 300)
    { g: { session_id: a[:session_id], organization_id: v[:org], project_id: v[:project_id], account_id: a[:account_id] },
      org: v[:org], project_id: v[:project_id], source_id: v[:source_id] }
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
  def policies(sid) = DbInspector.all("SELECT * FROM source_scope_policies WHERE source_id = $1::uuid ORDER BY created_at", [sid])
  def source_row(sid) = DbInspector.one("SELECT * FROM sources WHERE id = $1::uuid", [sid])
  def events(type) = DbInspector.all("SELECT * FROM event_registry WHERE event_type = $1", [type])
  def expiry_actions(rid) = DbInspector.all("SELECT * FROM scheduled_actions WHERE action_kind = 'source_scope_request_expire' AND target_id = $1::uuid", [rid])

  describe "the atomic fast-path (contract MTX-029 aggregate_boundary / transaction_boundary)" do
    it "activates an OrganizationAdmin's contraction in one transaction: approved request, one new policy version, repointed Source, Requested+Approved events, no expiry timer" do
      v = verified_source
      result = propose(v)
      expect(result.success?).to be(true)
      rid = result.payload[:source_scope_change_request_id]
      expect(result.payload[:state]).to eq("approved")
      expect(result.payload[:activated_policy_version]).to eq("source-scope-v2")

      row = requests(v[:source_id]).first
      expect(row["state"]).to eq("approved")
      expect(row["activated_policy_version"]).to eq("source-scope-v2")
      expect(row["decision_actor_id"]).to eq(v[:g][:account_id])

      pols = policies(v[:source_id])
      expect(pols.map { |p| p["policy_version"] }).to eq(%w[source-scope-interim-v1 source-scope-v2])
      expect(pols.last["include_prefixes"]).to eq("{/shop}")
      expect(source_row(v[:source_id])["current_scope_policy_id"]).to eq(pols.last["id"])

      expect(events("SourceScopeChangeRequested").select { |e| e["aggregate_id"] == rid }.size).to eq(1)
      approved = events("SourceScopeChangeApproved").select { |e| e["aggregate_id"] == rid }
      expect(approved.size).to eq(1)
      expect(approved.first["aggregate_version"].to_i).to eq(1)

      expect(expiry_actions(rid)).to be_empty
    end

    it "activates a MarketingOperator's contraction (manage holder, no dual control needed)" do
      v = verified_source
      mkt = seeded_actor(v, "MarketingOperator")
      result = propose(mkt)
      expect(result.success?).to be(true)
      expect(result.payload[:state]).to eq("approved")
      expect(policies(v[:source_id]).map { |p| p["policy_version"] }).to eq(%w[source-scope-interim-v1 source-scope-v2])
    end

    it "records both authorization decisions (source.scope.propose AND policy.source_scope.manage)" do
      v = verified_source
      propose(v)
      actions = DbInspector.all("SELECT action FROM authorization_decisions WHERE resource_id = $1::uuid", [v[:source_id]]).map { |r| r["action"] }
      expect(actions).to include("source.scope.propose", "policy.source_scope.manage")
    end

    it "activates an OrganizationAdmin's OWN expansion atomically (TYP-SEC self-approval fast-path)" do
      v = verified_source
      propose(v) # admin contraction /shop -> source-scope-v2 (active is now narrower than the boundary)
      result = propose(v, includes: ["/shop", "/blog"], expected: "source-scope-v2",
                       reason: "restore blog coverage alongside the shop section")
      expect(result.success?).to be(true)
      expect(result.payload[:state]).to eq("approved")
      expect(result.payload[:activated_policy_version]).to eq("source-scope-v3")
      pols = policies(v[:source_id])
      expect(pols.map { |p| p["policy_version"] }).to eq(%w[source-scope-interim-v1 source-scope-v2 source-scope-v3])
      expect(pols.last["include_prefixes"]).to eq("{/blog,/shop}")
    end
  end

  describe "the pending path (a proposer who cannot self-activate)" do
    it "keeps a Technical Implementer's contraction pending with a 24h expiry timer and no policy activation" do
      v = verified_source
      ti = seeded_actor(v, "TechnicalImplementer")
      result = propose(ti)
      expect(result.success?).to be(true)
      rid = result.payload[:source_scope_change_request_id]
      expect(result.payload[:state]).to eq("pending")

      row = requests(v[:source_id]).first
      expect(row["state"]).to eq("pending")
      expect(row["requester_account_id"]).to eq(ti[:g][:account_id])
      expect(policies(v[:source_id]).size).to eq(1) # only the interim; no activation

      gap = DbInspector.one("SELECT EXTRACT(EPOCH FROM (due_at_utc - requested_at_utc)) AS s FROM source_scope_change_requests WHERE id = $1::uuid", [rid])["s"].to_f
      expect(gap).to eq(86_400.0)
      expect(events("SourceScopeChangeRequested").select { |e| e["aggregate_id"] == rid }.size).to eq(1)
      expect(events("SourceScopeChangeApproved").select { |e| e["aggregate_id"] == rid }).to be_empty
      expect(expiry_actions(rid).size).to eq(1)
    end
  end

  describe "boundary violations are rejected through the failure path" do
    it "rejects a non-HTTPS scheme and writes no request or policy" do
      v = verified_source
      result = propose(v, schemes: %w[https http])
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("unsupported_source_scheme")
      expect(requests(v[:source_id])).to be_empty
      expect(policies(v[:source_id]).size).to eq(1)
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
    it "an exact replay of an auto-activating proposal returns the stored result and activates no second version" do
      v = verified_source
      first = propose(v, key: "same-key")
      second = propose(v, key: "same-key")
      expect(second.replayed).to be(true)
      expect(second.payload[:source_scope_change_request_id]).to eq(first.payload[:source_scope_change_request_id])
      expect(policies(v[:source_id]).map { |p| p["policy_version"] }).to eq(%w[source-scope-interim-v1 source-scope-v2])
    end

    it "an exact replay on the pending path returns the stored request and creates no second row" do
      v = verified_source
      ti = seeded_actor(v, "TechnicalImplementer")
      first = propose(ti, key: "same-key")
      second = propose(ti, key: "same-key")
      expect(second.payload[:source_scope_change_request_id]).to eq(first.payload[:source_scope_change_request_id])
      expect(requests(v[:source_id]).size).to eq(1)
    end

    it "changed content under the same key is idempotency_conflict" do
      v = verified_source
      ti = seeded_actor(v, "TechnicalImplementer")
      propose(ti, key: "same-key", includes: ["/shop"])
      conflict = propose(ti, key: "same-key", includes: ["/blog"])
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
