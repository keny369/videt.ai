# frozen_string_literal: true

require "rails_helper"

# WF-005 ActivateCrawlPolicy (S-07-001; contracts/S-07.json MTX-030 policy limb, MTX-059
# PRULE-008; WORKFLOW_SPECIFICATIONS.md § Interim Crawl Policy crawl-policy-v1 / policy subflow
# :732; DECISIONS ADR-068 owner D1 — dedicated crawl_policies table, frozen global ceiling).
#
# Narrowing-only crawl policy activation: an OrganizationAdmin narrows the Organization scope
# (parent = the frozen global ceiling), a MarketingOperator narrows a Project scope (parent =
# the active Organization policy, or global). Every value at or below parent AND global,
# soft <= hard, all twelve dimensions; a stale/broader/incomplete/unauthorized/mis-scoped
# activation changes nothing; activation supersedes the prior version; idempotent by key.
RSpec.describe "WF-005 activate crawl policy", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-E2E TYP-DATA TYP-SEC] do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 27, 10, 0, 0)
  def act_now = fixed_now + 60
  def bc = Platform::BaselineContent
  def gceil = Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING
  def gver = Workflows::Wf005::CrawlPolicy::GLOBAL_VERSION

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

  def marketing_session(org)
    TenantSeeder.seed_authorized_admin(organization_id: org, canonical_role: "MarketingOperator",
                                       with_policy: false, issued_at: fixed_now - 300)[:session_id]
  end
  def ti_session(org)
    TenantSeeder.seed_authorized_admin(organization_id: org, canonical_role: "TechnicalImplementer",
                                       with_policy: false, issued_at: fixed_now - 300)[:session_id]
  end

  # The global ceiling as a plain string-keyed hash, deep-copied, with optional per-dimension
  # overrides (each override merges into that dimension's {soft,hard}).
  def bounds(overrides = {})
    b = gceil.to_h { |d, v| [d, v.dup] }
    overrides.each { |d, o| b[d] = b[d].merge(o) }
    b
  end

  def activate(session:, org:, scope:, bounds:, project_id: nil, expected_current: nil,
               expected_parent: gver, expected_global: gver, key: "acp-#{SecureRandom.hex(6)}")
    Workflows::Wf005::Handlers::ActivateCrawlPolicy.new.call(
      command: Workflows::Wf005::Commands::ActivateCrawlPolicy.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0", session_id: session,
        organization_id: org, scope:, project_id:, expected_current_policy_version: expected_current,
        expected_parent_policy_version: expected_parent, expected_global_version: expected_global,
        proposed_bounds: bounds, requested_at_utc: act_now), request_context: act_ctx)
  end

  def policies(org) = DbInspector.all("SELECT * FROM crawl_policies WHERE organization_id = $1::uuid ORDER BY created_at", [org])
  def events(type) = DbInspector.all("SELECT * FROM event_registry WHERE event_type = $1", [type])

  describe "Organization-scope narrowing by an OrganizationAdmin" do
    it "activates a more restrictive version at or below the global ceiling and emits CrawlPolicyActivated" do
      g = bootstrap
      result = activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                        bounds: bounds("accepted_pages" => { "soft" => 5_000, "hard" => 6_000 }))
      expect(result.success?).to be(true)
      expect(result.payload[:scope]).to eq("organization")
      expect(result.payload[:policy_version]).to eq("crawl-policy-organization-v1")

      rows = policies(g[:organization_id])
      expect(rows.size).to eq(1)
      expect(rows.first["state"]).to eq("active")
      expect(rows.first["project_id"]).to be_nil
      expect(JSON.parse(rows.first["normalized_bounds"])["accepted_pages"]).to eq("soft" => 5_000, "hard" => 6_000)
      expect(events("CrawlPolicyActivated").size).to eq(1)
    end

    it "supersedes the prior active version on a second activation (guarded by expected current version)" do
      g = bootstrap
      activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
               bounds: bounds("crawl_depth" => { "soft" => 6, "hard" => 8 }))
      second = activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                        bounds: bounds("crawl_depth" => { "soft" => 4, "hard" => 5 }),
                        expected_current: "crawl-policy-organization-v1")
      expect(second.success?).to be(true)
      expect(second.payload[:policy_version]).to eq("crawl-policy-organization-v2")
      expect(second.payload[:superseded_policy_version]).to eq("crawl-policy-organization-v1")

      states = policies(g[:organization_id]).to_h { |r| [r["policy_version"], r["state"]] }
      expect(states).to eq("crawl-policy-organization-v1" => "superseded", "crawl-policy-organization-v2" => "active")
    end
  end

  describe "Project-scope narrowing by a MarketingOperator" do
    it "narrows the active Organization policy (parent)" do
      g = bootstrap
      activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
               bounds: bounds("accepted_pages" => { "soft" => 5_000, "hard" => 6_000 }))
      result = activate(session: marketing_session(g[:organization_id]), org: g[:organization_id], scope: "project",
                        project_id: g[:project_id], bounds: bounds("accepted_pages" => { "soft" => 1_000, "hard" => 2_000 }),
                        expected_parent: "crawl-policy-organization-v1")
      expect(result.success?).to be(true)
      expect(result.payload[:scope]).to eq("project")
      expect(result.payload[:policy_version]).to eq("crawl-policy-project-v1")
    end

    it "rejects a project value broader than the active Organization parent" do
      g = bootstrap
      activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
               bounds: bounds("accepted_pages" => { "soft" => 5_000, "hard" => 6_000 }))
      result = activate(session: marketing_session(g[:organization_id]), org: g[:organization_id], scope: "project",
                        project_id: g[:project_id], bounds: bounds("accepted_pages" => { "soft" => 5_000, "hard" => 8_000 }),
                        expected_parent: "crawl-policy-organization-v1")
      expect(result.failure.reason_code).to eq("crawl_policy_not_narrowing")
    end
  end

  describe "narrowing, completeness and version rejections change nothing" do
    it "rejects a value above the global hard ceiling as not narrowing" do
      g = bootstrap
      result = activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                        bounds: bounds("accepted_pages" => { "soft" => 8_000, "hard" => 11_000 }))
      expect(result.failure.reason_code).to eq("crawl_policy_not_narrowing")
      expect(policies(g[:organization_id])).to be_empty
    end

    it "rejects soft above hard" do
      g = bootstrap
      result = activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                        bounds: bounds("crawl_depth" => { "soft" => 9, "hard" => 8 }))
      expect(result.failure.reason_code).to eq("crawl_policy_soft_exceeds_hard")
    end

    it "rejects an incomplete proposal (a missing dimension)" do
      g = bootstrap
      b = bounds
      b.delete("sitemap_documents")
      result = activate(session: g[:session_id], org: g[:organization_id], scope: "organization", bounds: b)
      expect(result.failure.reason_code).to eq("crawl_policy_incomplete")
    end

    it "rejects a stale expected current version" do
      g = bootstrap
      activate(session: g[:session_id], org: g[:organization_id], scope: "organization", bounds: bounds)
      stale = activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                       bounds: bounds("crawl_depth" => { "soft" => 4, "hard" => 5 }), expected_current: nil)
      expect(stale.failure.reason_code).to eq("crawl_policy_stale_version")
      expect(policies(g[:organization_id]).count { |r| r["state"] == "active" }).to eq(1)
    end

    it "rejects a stale expected global version" do
      g = bootstrap
      result = activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                        bounds: bounds, expected_global: "crawl-policy-v0-global")
      expect(result.failure.reason_code).to eq("crawl_policy_unavailable")
    end
  end

  describe "authorization and scope" do
    it "denies a TechnicalImplementer (no policy.crawl.manage)" do
      g = bootstrap
      result = activate(session: ti_session(g[:organization_id]), org: g[:organization_id], scope: "organization", bounds: bounds)
      expect(result.failure.reason_code).to eq("crawl_policy_unauthorized")
    end

    it "denies a MarketingOperator at Organization scope (Marketing narrows Project only)" do
      g = bootstrap
      result = activate(session: marketing_session(g[:organization_id]), org: g[:organization_id], scope: "organization", bounds: bounds)
      expect(result.failure.reason_code).to eq("crawl_policy_unauthorized")
    end

    it "denies an OrganizationAdmin at Project scope (Admin narrows Organization only)" do
      g = bootstrap
      result = activate(session: g[:session_id], org: g[:organization_id], scope: "project",
                        project_id: g[:project_id], bounds: bounds)
      expect(result.failure.reason_code).to eq("crawl_policy_unauthorized")
    end
  end

  describe "idempotency and tenant isolation" do
    it "replays an exact activation by its key and creates no second version" do
      g = bootstrap
      first = activate(session: g[:session_id], org: g[:organization_id], scope: "organization", bounds: bounds, key: "same")
      second = activate(session: g[:session_id], org: g[:organization_id], scope: "organization", bounds: bounds, key: "same")
      expect(second.replayed).to be(true)
      expect(second.payload[:policy_version]).to eq(first.payload[:policy_version])
      expect(policies(g[:organization_id]).size).to eq(1)
    end

    it "refuses a command whose organization_id is not the actor's" do
      g = bootstrap
      result = activate(session: g[:session_id], org: SecureRandom.uuid_v7, scope: "organization", bounds: bounds)
      expect(result.failure.reason_code).to eq("tenant_mismatch")
    end

    it "refuses (and audits) a scope/project_id mismatch as crawl_policy_scope_invalid" do
      g = bootstrap
      result = activate(session: g[:session_id], org: g[:organization_id], scope: "organization",
                        project_id: g[:project_id], bounds: bounds)
      expect(result.failure.reason_code).to eq("crawl_policy_scope_invalid")
      audited = DbInspector.all("SELECT id FROM audit_record_registry WHERE reason_code='crawl_policy_scope_invalid' AND outcome='failure'")
      expect(audited).not_to be_empty
    end
  end
end
