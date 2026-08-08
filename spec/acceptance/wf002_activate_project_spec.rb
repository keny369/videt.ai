# frozen_string_literal: true

require "rails_helper"

# WF-002 ActivateProject (S-03; contracts/S-03.json MTX-027 activation limb;
# WORKFLOW_SPECIFICATIONS.md § WF-002 :651-666; owner D3, DECISIONS ADR-072). The canonical
# Project.Draft -> Project.Active transition, gated on >=1 active same-Project Source, over a
# production-real chain: genesis (draft Project), a registered + verified + activated Source,
# then Project activation. No fixture fabricates an active Project or bypasses lifecycle rules.
RSpec.describe "WF-002 activate project", type: :acceptance,
               acceptance_ids: ["AC-CAP-003", "AC-WF-002"], test_types: %w[TYP-E2E TYP-DATA TYP-SEC TYP-INT] do
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

  def verify(g, sid)
    r = Workflows::Wf003::Handlers::IssueVerificationChallenge.new.call(
      command: Workflows::Wf003::Commands::IssueVerificationChallenge.new(command_id: SecureRandom.uuid_v7, idempotency_key: "vc-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id], source_id: sid, method: "dns_txt",
        expected_state_version: 0, requested_at_utc: act_now), request_context: act_ctx)
    aid = Workflows::Wf003::Handlers::ReserveVerificationAttempt.new.call(
      command: Workflows::Wf003::Commands::ReserveVerificationAttempt.new(command_id: SecureRandom.uuid_v7, idempotency_key: "rv-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id], verification_request_id: r.payload[:verification_request_id],
        expected_state_version: 0, requested_at_utc: act_now), request_context: act_ctx).payload[:verification_attempt_id]
    outbound = Object.new.tap { |o| o.define_singleton_method(:fetch_dns_txt) { |*_a, **_k| Object.new.tap { |a| a.define_singleton_method(:refused?) { false }; a.define_singleton_method(:records) { [["f1-verification=#{r.payload[:challenge_token]}"]] } } } }
    Workflows::Wf003::Handlers::CompleteVerificationAttempt.new.call(
      command: Workflows::Wf003::Commands::CompleteVerificationAttempt.new(command_id: SecureRandom.uuid_v7, schema_version: "1.0", organization_id: g[:organization_id],
        verification_request_id: r.payload[:verification_request_id], verification_attempt_id: aid, requested_at_utc: act_now),
      request_context: Platform::RequestContext.for_service(service_identity_id: Platform::ServiceIdentity.scheduled_action_executor, clock: Platform::Clock.fixed(act_now), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7), outbound:)
  end

  def activate_source(g, sid)
    Workflows::Wf004::Handlers::ActivateSource.new.call(
      command: Workflows::Wf004::Commands::ActivateSource.new(command_id: SecureRandom.uuid_v7, idempotency_key: "as-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id], source_id: sid,
        expected_state_version: source_row(sid)["state_version"].to_i, requested_at_utc: act_now), request_context: act_ctx)
  end

  # An Organization with a genesis (draft) Project that has one active Source.
  def org_with_active_source
    g = bootstrap
    sid = register_source(g)
    verify(g, sid)
    activate_source(g, sid)
    g
  end

  def ti_session(org)
    TenantSeeder.seed_authorized_admin(organization_id: org, canonical_role: "TechnicalImplementer",
                                       with_policy: false, issued_at: fixed_now - 300)[:session_id]
  end

  def project_row(pid) = DbInspector.one("SELECT * FROM projects WHERE id = $1::uuid", [pid])
  def source_row(sid) = DbInspector.one("SELECT * FROM sources WHERE id = $1::uuid", [sid])
  def events(type, pid) = DbInspector.all("SELECT * FROM event_registry WHERE event_type = $1 AND aggregate_id = $2::uuid", [type, pid])

  def activate_project(g, expected: nil, expected_membership: nil, project_id: nil, session: nil, key: "ap-#{SecureRandom.hex(6)}")
    pid = project_id || g[:project_id]
    proj = project_row(pid) || {}
    Workflows::Wf002::Handlers::ActivateProject.new.call(
      command: Workflows::Wf002::Commands::ActivateProject.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
        session_id: session || g[:session_id], organization_id: g[:organization_id], project_id: pid,
        expected_state_version: expected || proj["state_version"].to_i,
        expected_source_membership_version: expected_membership || proj["source_set_version"].to_i,
        requested_at_utc: act_now), request_context: act_ctx)
  end

  describe "the draft -> active transition (gated on an active Source)" do
    it "activates a draft Project with one active same-Project Source and emits ProjectActivated" do
      g = org_with_active_source
      before = project_row(g[:project_id])
      result = activate_project(g)
      expect(result.success?).to be(true)
      expect(result.payload[:state]).to eq("active")
      expect(result.payload[:state_version]).to eq(before["state_version"].to_i + 1)
      expect(project_row(g[:project_id])["state"]).to eq("active")
      expect(events("ProjectActivated", g[:project_id]).size).to eq(1)
    end

    it "leaves the Project draft with active_source_required when no Source is active" do
      g = bootstrap # draft Project, no active Source
      result = activate_project(g)
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("active_source_required")
      expect(project_row(g[:project_id])["state"]).to eq("draft")
      expect(events("ProjectActivated", g[:project_id])).to be_empty
    end

    it "a Source verified but not activated does not satisfy the prerequisite" do
      g = bootstrap
      sid = register_source(g)
      verify(g, sid) # verified, NOT activated
      result = activate_project(g)
      expect(result.failure.reason_code).to eq("active_source_required")
    end
  end

  describe "authorization and state guards" do
    it "denies a Technical Implementer (no project.activate)" do
      g = org_with_active_source
      result = activate_project(g, session: ti_session(g[:organization_id]))
      expect(result.failure.reason_code).to eq("project_activate_unauthorized")
      expect(project_row(g[:project_id])["state"]).to eq("draft")
    end

    it "refuses an already-active Project as project_not_draft (idempotent by the state guard)" do
      g = org_with_active_source
      activate_project(g)
      again = activate_project(g, expected: 1) # now active at version 1
      expect(again.success?).to be(false)
      expect(again.failure.reason_code).to eq("project_not_draft")
    end

    it "rejects a stale expected Project state version" do
      g = org_with_active_source
      result = activate_project(g, expected: 5)
      expect(result.failure.reason_code).to eq("stale_state_version")
      expect(project_row(g[:project_id])["state"]).to eq("draft")
    end

    it "rejects a changed Source-membership version" do
      g = org_with_active_source
      result = activate_project(g, expected_membership: 7)
      expect(result.failure.reason_code).to eq("source_membership_changed")
      expect(project_row(g[:project_id])["state"]).to eq("draft")
    end

    it "returns active_source_required before source_membership_changed (normative first-match order)" do
      # A draft Project with ZERO active Sources AND a wrong expected Source-membership version.
      # MTX-027's order is normative: active_source_required is second (after project_not_draft), so it
      # must win over the later source_membership_changed guard even though both preconditions fail.
      g = bootstrap
      result = activate_project(g, expected_membership: 7)
      expect(result.failure.reason_code).to eq("active_source_required")
      expect(project_row(g[:project_id])["state"]).to eq("draft")
    end
  end

  describe "idempotency and tenant isolation" do
    it "replays an exact activation by its key and does not transition twice" do
      g = org_with_active_source
      # An exact replay is the IDENTICAL command (same expected versions); pin them so the
      # second call is a true replay rather than a fresh command against the now-active Project.
      first = activate_project(g, key: "same", expected: 0, expected_membership: 0)
      second = activate_project(g, key: "same", expected: 0, expected_membership: 0)
      expect(second.replayed).to be(true)
      expect(second.payload[:state_version]).to eq(first.payload[:state_version])
    end

    it "refuses a Project outside the actor's tenant" do
      g = org_with_active_source
      result = activate_project(g, project_id: SecureRandom.uuid_v7)
      expect(result.failure.reason_code).to eq("tenant_mismatch")
    end
  end
end
