# frozen_string_literal: true

require "rails_helper"

# WF-004 ExpireSourceScopeChange (S-06-005; WORKFLOW_SPECIFICATIONS.md § Source Scope Change
# Contract :419; contracts/S-06.json MTX-029 domain_events/transaction_boundary/concurrency).
# The service-only timed transition behind the ratified `source_scope_request_expire`
# ScheduledAction that ProposeSourceScopeChange schedules on a PENDING request. Executed by
# the ScheduledAction executor (a null human actor).
#
# Covers the MTX-029 expiry contract: at exactly `due_at_utc` the expiry transition wins over
# a decision or cancellation, emits `SourceScopeChangeExpired` once, and changes no policy or
# Source state; a timer before the instant is not due; an already-terminal request is a
# harmless no-op; the transition is idempotent by the action identity.
RSpec.describe "WF-004 expire source scope change", type: :acceptance,
               acceptance_ids: ["AC-CAP-006", "AC-WF-004"], test_types: %w[TYP-E2E TYP-OBS TYP-DATA TYP-SEC] do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 27, 10, 0, 0)
  def act_now = fixed_now + 60
  def due_at = act_now + (24 * 3600)
  def bc = Platform::BaselineContent

  let(:identity) { { issuer_key: "https://id.example/oidc", subject: "founder-#{SecureRandom.hex(8)}" } }

  def service_ctx(at)
    Platform::RequestContext.for_service(service_identity_id: Platform::ServiceIdentity::IDENTITY_SERVICE,
                                         clock: Platform::Clock.fixed(at), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
  end
  def act_ctx = Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(act_now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
  def executor_ctx(at)
    Platform::RequestContext.for_service(service_identity_id: Platform::ServiceIdentity.scheduled_action_executor,
                                         clock: Platform::Clock.fixed(at), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
  end

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

  # A PENDING contraction (proposed by a Technical Implementer, who cannot self-activate),
  # carrying a 24-hour expiry timer.
  def pending_request
    v = verified_source
    ti = seeded_actor(v, "TechnicalImplementer")
    rid = Workflows::Wf004::Handlers::ProposeSourceScopeChange.new.call(
      command: Workflows::Wf004::Commands::ProposeSourceScopeChange.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "prop-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: ti[:g][:session_id], organization_id: v[:org], project_id: v[:project_id],
        source_id: v[:source_id], expected_active_policy_version: "source-scope-interim-v1",
        proposed_allowed_schemes: ["https"], proposed_allowed_ports: [443], proposed_include_prefixes: ["/shop"],
        proposed_exclude_prefixes: [], proposed_query_handling: "retain_all", request_reason: "narrow to the shop section only",
        requested_at_utc: act_now), request_context: act_ctx).payload[:source_scope_change_request_id]
    { v:, ti:, admin: v, rid: }
  end

  def expire(rid, org, at:, action_due: due_at, action_id: SecureRandom.uuid_v7,
             action_identity: Digest::SHA256.digest("ssce:#{rid}"))
    cmd = Workflows::Wf004::Commands::ExpireSourceScopeChange.new(
      command_id: SecureRandom.uuid_v7, schema_version: "1.0", organization_id: org,
      target_type: "source_scope_change_request", request_id: rid, due_at: action_due, action_id:,
      action_identity_sha256: action_identity, requested_at_utc: action_due)
    Workflows::Wf004::Handlers::ExpireSourceScopeChange.new.call(command: cmd, request_context: executor_ctx(at))
  end

  def decide(actor, rid, decision:, exp_pol:, at:, exp_req: 0, reason: nil)
    Workflows::Wf004::Handlers::DecideSourceScopeChange.new.call(
      command: Workflows::Wf004::Commands::DecideSourceScopeChange.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "dec-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: actor[:g][:session_id], organization_id: actor[:org], project_id: actor[:project_id],
        source_id: actor[:source_id], request_id: rid, decision:, expected_request_state_version: exp_req,
        expected_active_policy_version: exp_pol, decision_reason: reason, requested_at_utc: at),
      request_context: Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(at), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7))
  end

  def cancel(actor, rid, reason:, at:, exp_req: 0)
    Workflows::Wf004::Handlers::CancelSourceScopeChange.new.call(
      command: Workflows::Wf004::Commands::CancelSourceScopeChange.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "can-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: actor[:g][:session_id], organization_id: actor[:org], project_id: actor[:project_id],
        source_id: actor[:source_id], request_id: rid, expected_request_state_version: exp_req,
        cancel_reason: reason, requested_at_utc: at),
      request_context: Platform::RequestContext.for_actor(clock: Platform::Clock.fixed(at), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7))
  end

  # The bootstrap OrganizationAdmin with a Session freshly valid at `at` (the built-in
  # Sessions expire 12h after issue, so a decision ~24h later needs a fresh one). Same
  # Account/role — no second bootstrap-admin exception.
  def admin_at(v, at)
    sid = TenantSeeder.create_session(organization_id: v[:org], account_id: v[:g][:account_id], issued_at: at - 300)
    { g: { session_id: sid, organization_id: v[:org], project_id: v[:project_id], account_id: v[:g][:account_id] },
      org: v[:org], project_id: v[:project_id], source_id: v[:source_id] }
  end

  def request_row(rid) = DbInspector.one("SELECT * FROM source_scope_change_requests WHERE id = $1::uuid", [rid])
  def policies(sid) = DbInspector.all("SELECT * FROM source_scope_policies WHERE source_id = $1::uuid", [sid])
  def source_row(sid) = DbInspector.one("SELECT * FROM sources WHERE id = $1::uuid", [sid])
  def expired_events(rid) = DbInspector.all("SELECT * FROM event_registry WHERE event_type = 'SourceScopeChangeExpired' AND aggregate_id = $1::uuid", [rid])
  def reason20 = "a fully sufficient decision rationale for the audit trail"

  describe "the 24-hour expiry race (before / at exactly / after due_at_utc)" do
    it "expires a still-pending request at exactly due_at, emitting SourceScopeChangeExpired once and changing no policy or Source state" do
      s = pending_request
      before = source_row(s[:v][:source_id])["current_scope_policy_id"]
      result = expire(s[:rid], s[:v][:org], at: due_at)
      expect(result.success?).to be(true)

      row = request_row(s[:rid])
      expect(row["state"]).to eq("expired")
      expect(row["terminal_at_utc"]).not_to be_nil
      expect(row["decision_actor_id"]).to be_nil
      expect(row["activated_policy_version"]).to be_nil

      expect(policies(s[:v][:source_id]).size).to eq(1) # only the interim; no activation
      expect(source_row(s[:v][:source_id])["current_scope_policy_id"]).to eq(before)
      expect(expired_events(s[:rid]).size).to eq(1)
    end

    it "is not due before due_at and changes nothing" do
      s = pending_request
      result = expire(s[:rid], s[:v][:org], at: due_at - 60)
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("scheduled_action_not_due")
      expect(request_row(s[:rid])["state"]).to eq("pending")
    end

    it "expires after due_at" do
      s = pending_request
      expect(expire(s[:rid], s[:v][:org], at: due_at + 3600).success?).to be(true)
      expect(request_row(s[:rid])["state"]).to eq("expired")
    end
  end

  describe "idempotency and harmless late arrival" do
    it "replays an exact re-fire by the action identity and expires only once" do
      s = pending_request
      ident = Digest::SHA256.digest("fixed-action")
      first = expire(s[:rid], s[:v][:org], at: due_at, action_identity: ident)
      second = expire(s[:rid], s[:v][:org], at: due_at, action_identity: ident)
      expect(first.success?).to be(true)
      expect(second.replayed).to be(true)
      expect(expired_events(s[:rid]).size).to eq(1)
    end

    it "is a harmless no-op for an already-terminal (approved) request" do
      s = pending_request
      decide(s[:admin], s[:rid], decision: "approve", exp_pol: "source-scope-interim-v1", at: act_now)
      result = expire(s[:rid], s[:v][:org], at: due_at)
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("source_scope_request_not_pending")
      expect(request_row(s[:rid])["state"]).to eq("approved")
    end

    it "rejects a timer whose due_at disagrees with the request" do
      s = pending_request
      result = expire(s[:rid], s[:v][:org], at: due_at, action_due: due_at + 1)
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("scheduled_action_target_mismatch")
    end
  end

  describe "expiry wins over a decision or cancellation at due_at (MTX-029 concurrency)" do
    it "refuses an approval at exactly due_at with source_scope_request_expired and activates nothing" do
      s = pending_request
      result = decide(admin_at(s[:v], due_at), s[:rid], decision: "approve", exp_pol: "source-scope-interim-v1", at: due_at)
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("source_scope_request_expired")
      expect(request_row(s[:rid])["state"]).to eq("pending")
      expect(policies(s[:v][:source_id]).size).to eq(1)
    end

    it "refuses a rejection at exactly due_at with source_scope_request_expired" do
      s = pending_request
      result = decide(admin_at(s[:v], due_at), s[:rid], decision: "reject", exp_pol: "source-scope-interim-v1", reason: reason20, at: due_at)
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("source_scope_request_expired")
      expect(request_row(s[:rid])["state"]).to eq("pending")
    end

    it "refuses a cancellation at exactly due_at with source_scope_request_expired" do
      s = pending_request
      result = cancel(admin_at(s[:v], due_at), s[:rid], reason: reason20, at: due_at)
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("source_scope_request_expired")
      expect(request_row(s[:rid])["state"]).to eq("pending")
    end

    it "leaves an already-expired request unchanged when a later decision arrives" do
      s = pending_request
      expire(s[:rid], s[:v][:org], at: due_at)
      result = decide(admin_at(s[:v], due_at + 3600), s[:rid], decision: "approve", exp_pol: "source-scope-interim-v1", at: due_at + 3600)
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("source_scope_request_not_pending")
      expect(request_row(s[:rid])["state"]).to eq("expired")
      expect(policies(s[:v][:source_id]).size).to eq(1)
    end

    it "still allows a decision strictly before due_at" do
      s = pending_request
      result = decide(admin_at(s[:v], due_at - 60), s[:rid], decision: "approve", exp_pol: "source-scope-interim-v1", at: due_at - 60)
      expect(result.success?).to be(true)
      expect(request_row(s[:rid])["state"]).to eq("approved")
    end
  end

  describe "dispatch registration" do
    it "resolves the source_scope_request_expire kind to the ExpireSourceScopeChange handler" do
      entry = Platform::ScheduledActions::Registry.default.resolve(action_kind: "source_scope_request_expire", action_schema_version: "1.0")
      expect(entry.handler).to eq(Workflows::Wf004::Handlers::ExpireSourceScopeChange)
      expect(entry.command).to eq(Workflows::Wf004::Commands::ExpireSourceScopeChange)
      expect(entry.operation).to eq("ExpireSourceScopeChange")
    end
  end
end
