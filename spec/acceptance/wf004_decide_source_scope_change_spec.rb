# frozen_string_literal: true

require "rails_helper"

# WF-004 DecideSourceScopeChange + CancelSourceScopeChange (S-06-004;
# WORKFLOW_SPECIFICATIONS.md § Source Scope Change Contract :420-421; contracts/S-06.json
# MTX-029). End to end over a production-real chain: a verified Source carrying
# source-scope-interim-v1, a PENDING request opened by a proposer who cannot self-activate,
# then an approval / rejection / cancellation.
#
# Covers the MTX-029 dual-control and concurrency contract: a contraction needs no second
# party; an expansion may be approved only by an OrganizationAdmin who is a different Account
# from the non-admin requester; approval activates exactly one new immutable policy version
# under the expected request AND active-policy versions; rejection and cancellation change no
# scope; every terminal request is immutable; decisions are idempotent by their key.
RSpec.describe "WF-004 decide source scope change", type: :acceptance,
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
        receipt_digest: receipt[:receipt_digest], expected_grant_version: 0, organization_display_name: "Acme", first_project: GenesisProjectProfile.body("Genesis"), access_policy_content_sha256: bc.access_policy_sha256, entitlement_policy_content_sha256: bc.entitlement_policy_sha256,
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

  def verified_source
    g = bootstrap
    sid = register_source(g)
    r = issue(g, sid)
    aid = reserve(g, r.payload[:verification_request_id])
    complete_match(g[:organization_id], r.payload[:verification_request_id], aid, r.payload[:challenge_token])
    { g:, org: g[:organization_id], project_id: g[:project_id], source_id: sid }
  end

  def seeded_actor(v, role)
    a = TenantSeeder.seed_authorized_admin(organization_id: v[:org], canonical_role: role,
                                           with_policy: false, issued_at: fixed_now - 300)
    { g: { session_id: a[:session_id], organization_id: v[:org], project_id: v[:project_id], account_id: a[:account_id] },
      org: v[:org], project_id: v[:project_id], source_id: v[:source_id] }
  end

  def propose(v, reason: "narrow the crawl scope to the shop section only",
              includes: ["/shop"], expected: "source-scope-interim-v1", key: "prop-#{SecureRandom.hex(6)}")
    Workflows::Wf004::Handlers::ProposeSourceScopeChange.new.call(
      command: Workflows::Wf004::Commands::ProposeSourceScopeChange.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
        session_id: v[:g][:session_id], organization_id: v[:org], project_id: v[:project_id],
        source_id: v[:source_id], expected_active_policy_version: expected,
        proposed_allowed_schemes: ["https"], proposed_allowed_ports: [443], proposed_include_prefixes: includes,
        proposed_exclude_prefixes: [], proposed_query_handling: "retain_all", request_reason: reason,
        requested_at_utc: act_now), request_context: act_ctx)
  end

  def decide(actor, rid, decision:, exp_pol:, exp_req: 0, reason: nil, key: "dec-#{SecureRandom.hex(6)}")
    Workflows::Wf004::Handlers::DecideSourceScopeChange.new.call(
      command: Workflows::Wf004::Commands::DecideSourceScopeChange.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
        session_id: actor[:g][:session_id], organization_id: actor[:org], project_id: actor[:project_id],
        source_id: actor[:source_id], request_id: rid, decision:, expected_request_state_version: exp_req,
        expected_active_policy_version: exp_pol, decision_reason: reason, requested_at_utc: act_now),
      request_context: act_ctx)
  end

  def cancel(actor, rid, reason:, exp_req: 0, key: "can-#{SecureRandom.hex(6)}")
    Workflows::Wf004::Handlers::CancelSourceScopeChange.new.call(
      command: Workflows::Wf004::Commands::CancelSourceScopeChange.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
        session_id: actor[:g][:session_id], organization_id: actor[:org], project_id: actor[:project_id],
        source_id: actor[:source_id], request_id: rid, expected_request_state_version: exp_req,
        cancel_reason: reason, requested_at_utc: act_now), request_context: act_ctx)
  end

  def request_row(rid) = DbInspector.one("SELECT * FROM source_scope_change_requests WHERE id = $1::uuid", [rid])
  def policies(sid) = DbInspector.all("SELECT * FROM source_scope_policies WHERE source_id = $1::uuid ORDER BY created_at", [sid])
  def source_row(sid) = DbInspector.one("SELECT * FROM sources WHERE id = $1::uuid", [sid])
  def events(type, rid) = DbInspector.all("SELECT * FROM event_registry WHERE event_type = $1 AND aggregate_id = $2::uuid", [type, rid])
  def reason20 = "a fully sufficient decision rationale for the audit trail"

  # A pending contraction opened by a Technical Implementer (no policy.source_scope.manage).
  def pending_contraction
    v = verified_source
    ti = seeded_actor(v, "TechnicalImplementer")
    rid = propose(ti).payload[:source_scope_change_request_id]
    { v:, ti:, admin: v, rid: }
  end

  # A pending expansion opened by a MarketingOperator (manage holder, not admin) against an
  # already-contracted active policy (source-scope-v2, include {/shop}).
  def pending_expansion
    v = verified_source
    propose(v) # admin contraction /shop -> auto-activates source-scope-v2
    mkt = seeded_actor(v, "MarketingOperator")
    rid = propose(mkt, includes: ["/shop", "/blog"], expected: "source-scope-v2",
                  reason: "restore blog coverage alongside the shop section").payload[:source_scope_change_request_id]
    { v:, mkt:, admin: v, rid: }
  end

  describe "approval activates exactly one new immutable policy version" do
    it "approves a pending contraction (no dual control) and repoints the Source" do
      s = pending_contraction
      result = decide(s[:admin], s[:rid], decision: "approve", exp_pol: "source-scope-interim-v1")
      expect(result.success?).to be(true)
      expect(result.payload[:activated_policy_version]).to eq("source-scope-v2")

      row = request_row(s[:rid])
      expect(row["state"]).to eq("approved")
      expect(row["activated_policy_version"]).to eq("source-scope-v2")
      expect(row["decision_actor_id"]).to eq(s[:admin][:g][:account_id])

      pols = policies(s[:v][:source_id])
      expect(pols.map { |p| p["policy_version"] }).to eq(%w[source-scope-interim-v1 source-scope-v2])
      expect(pols.last["include_prefixes"]).to eq("{/shop}")
      expect(source_row(s[:v][:source_id])["current_scope_policy_id"]).to eq(pols.last["id"])
      expect(events("SourceScopeChangeApproved", s[:rid]).size).to eq(1)
    end

    it "approves a pending expansion by a different-Account OrganizationAdmin (dual control satisfied)" do
      s = pending_expansion
      result = decide(s[:admin], s[:rid], decision: "approve", exp_pol: "source-scope-v2")
      expect(result.success?).to be(true)
      expect(result.payload[:activated_policy_version]).to eq("source-scope-v3")
      pols = policies(s[:v][:source_id])
      expect(pols.map { |p| p["policy_version"] }).to eq(%w[source-scope-interim-v1 source-scope-v2 source-scope-v3])
      expect(pols.last["include_prefixes"]).to eq("{/blog,/shop}")
    end
  end

  describe "dual control on an expansion (contract MTX-029 authorization_entry_point)" do
    it "refuses an expansion approval by the non-admin requester itself" do
      s = pending_expansion
      result = decide(s[:mkt], s[:rid], decision: "approve", exp_pol: "source-scope-v2")
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("source_scope_decision_unauthorized")
      expect(request_row(s[:rid])["state"]).to eq("pending")
      expect(policies(s[:v][:source_id]).size).to eq(2) # interim + the admin's v2; no v3
    end

    it "refuses a decision by a Technical Implementer (no policy.source_scope.manage)" do
      s = pending_contraction
      result = decide(s[:ti], s[:rid], decision: "approve", exp_pol: "source-scope-interim-v1")
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("source_scope_decision_unauthorized")
      expect(request_row(s[:rid])["state"]).to eq("pending")
    end
  end

  describe "rejection changes no scope and requires a 20-2,000 character reason" do
    it "rejects a pending contraction and activates no policy" do
      s = pending_contraction
      result = decide(s[:admin], s[:rid], decision: "reject", exp_pol: "source-scope-interim-v1", reason: reason20)
      expect(result.success?).to be(true)
      row = request_row(s[:rid])
      expect(row["state"]).to eq("rejected")
      expect(row["decision_reason"]).to eq(reason20)
      expect(row["activated_policy_version"]).to be_nil
      expect(policies(s[:v][:source_id]).size).to eq(1) # only the interim
      expect(events("SourceScopeChangeRejected", s[:rid]).size).to eq(1)
    end

    it "refuses a rejection whose reason is shorter than 20 characters" do
      s = pending_contraction
      result = decide(s[:admin], s[:rid], decision: "reject", exp_pol: "source-scope-interim-v1", reason: "too short")
      expect(result.failure.reason_code).to eq("source_scope_reason_invalid")
      expect(request_row(s[:rid])["state"]).to eq("pending")
    end
  end

  describe "concurrency guards (both the request AND the active-policy version)" do
    it "rejects a stale expected request state version with no side effect" do
      s = pending_contraction
      result = decide(s[:admin], s[:rid], decision: "approve", exp_req: 5, exp_pol: "source-scope-interim-v1")
      expect(result.failure.reason_code).to eq("stale_request_version")
      expect(request_row(s[:rid])["state"]).to eq("pending")
    end

    it "rejects a stale expected active-policy version with no side effect" do
      s = pending_contraction
      result = decide(s[:admin], s[:rid], decision: "approve", exp_pol: "source-scope-interim-v0")
      expect(result.failure.reason_code).to eq("stale_active_policy_version")
      expect(request_row(s[:rid])["state"]).to eq("pending")
    end
  end

  describe "terminal-request immutability and idempotency" do
    it "refuses a second, distinct decision on an already-approved request" do
      s = pending_contraction
      decide(s[:admin], s[:rid], decision: "approve", exp_pol: "source-scope-interim-v1")
      again = decide(s[:admin], s[:rid], decision: "approve", exp_pol: "source-scope-v2")
      expect(again.success?).to be(false)
      expect(again.failure.reason_code).to eq("source_scope_request_not_pending")
      expect(policies(s[:v][:source_id]).size).to eq(2)
    end

    it "replays an exact approval by its idempotency key and activates no second version" do
      s = pending_contraction
      first = decide(s[:admin], s[:rid], decision: "approve", exp_pol: "source-scope-interim-v1", key: "same")
      second = decide(s[:admin], s[:rid], decision: "approve", exp_pol: "source-scope-interim-v1", key: "same")
      expect(second.replayed).to be(true)
      expect(second.payload[:activated_policy_version]).to eq(first.payload[:activated_policy_version])
      expect(policies(s[:v][:source_id]).size).to eq(2)
    end
  end

  describe "cancellation from pending only, by the requester or an OrganizationAdmin" do
    it "lets the requester cancel their own pending request with a reason and no scope change" do
      s = pending_contraction
      result = cancel(s[:ti], s[:rid], reason: reason20)
      expect(result.success?).to be(true)
      row = request_row(s[:rid])
      expect(row["state"]).to eq("canceled")
      expect(row["decision_reason"]).to eq(reason20)
      expect(policies(s[:v][:source_id]).size).to eq(1)
      expect(events("SourceScopeChangeCanceled", s[:rid]).size).to eq(1)
    end

    it "lets an OrganizationAdmin cancel another actor's pending request" do
      s = pending_expansion
      result = cancel(s[:admin], s[:rid], reason: reason20)
      expect(result.success?).to be(true)
      expect(request_row(s[:rid])["state"]).to eq("canceled")
    end

    it "refuses cancellation by a non-requester who is not an OrganizationAdmin" do
      s = pending_contraction
      other = seeded_actor(s[:v], "TechnicalImplementer")
      result = cancel(other, s[:rid], reason: reason20)
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("source_scope_cancel_unauthorized")
      expect(request_row(s[:rid])["state"]).to eq("pending")
    end

    it "refuses a cancellation whose reason is shorter than 20 characters" do
      s = pending_contraction
      result = cancel(s[:ti], s[:rid], reason: "too short")
      expect(result.failure.reason_code).to eq("source_scope_reason_invalid")
      expect(request_row(s[:rid])["state"]).to eq("pending")
    end
  end

  describe "tenant isolation" do
    it "refuses a decision on a request that is not visible in the actor's tenant" do
      s = pending_contraction
      result = decide(s[:admin], SecureRandom.uuid_v7, decision: "approve", exp_pol: "source-scope-interim-v1")
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("tenant_mismatch")
    end
  end
end
