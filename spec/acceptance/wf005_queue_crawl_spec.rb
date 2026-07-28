# frozen_string_literal: true

require "rails_helper"

# WF-005 QueueCrawl (S-07-002; contracts/S-07.json MTX-030 queue limb, MTX-058 PRULE-007;
# WORKFLOW_SPECIFICATIONS.md § WF-005 :725-728, :734). Creates a single root queued Crawl,
# pinning the request-time crawl-policy (Project else Organization active version, else the
# frozen global ceiling) and entitlement-policy versions and the active Source set; it reserves
# NO usage and creates NO Evaluation (those are StartCrawl + F-05, S-07-003).
#
# Exercised over a PRODUCTION-REAL chain (owner D5, no fabricated active-Project fixtures):
# genesis (draft Project) -> registered + verified + activated Source -> ActivateProject
# (S-03, real draft->active) -> QueueCrawl.
RSpec.describe "WF-005 queue crawl", type: :acceptance,
               acceptance_ids: ["AC-CAP-005", "AC-WF-005"], test_types: %w[TYP-E2E TYP-DATA TYP-SEC TYP-INT] do
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

  def disable_source(g, sid)
    Workflows::Wf004::Handlers::DisableSource.new.call(
      command: Workflows::Wf004::Commands::DisableSource.new(command_id: SecureRandom.uuid_v7, idempotency_key: "ds-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id], source_id: sid,
        expected_state_version: source_row(sid)["state_version"].to_i, lifecycle_reason: "owner_requested_pause", requested_at_utc: act_now), request_context: act_ctx)
  end

  def activate_project(g)
    proj = project_row(g[:project_id])
    Workflows::Wf002::Handlers::ActivateProject.new.call(
      command: Workflows::Wf002::Commands::ActivateProject.new(command_id: SecureRandom.uuid_v7, idempotency_key: "ap-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
        expected_state_version: proj["state_version"].to_i, expected_source_membership_version: proj["source_set_version"].to_i,
        requested_at_utc: act_now), request_context: act_ctx)
  end

  def activate_org_crawl_policy(g, overrides = {})
    b = gceil.to_h { |d, v| [d, v.dup] }
    overrides.each { |d, o| b[d] = b[d].merge(o) }
    Workflows::Wf005::Handlers::ActivateCrawlPolicy.new.call(
      command: Workflows::Wf005::Commands::ActivateCrawlPolicy.new(command_id: SecureRandom.uuid_v7, idempotency_key: "acp-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], scope: "organization", project_id: nil,
        expected_current_policy_version: nil, expected_parent_policy_version: gver, expected_global_version: gver,
        proposed_bounds: b, requested_at_utc: act_now), request_context: act_ctx)
  end

  # An Organization with an ACTIVE genesis Project carrying one active Source (the full real chain).
  def org_with_active_project(sources: 1)
    g = bootstrap
    sources.times { |i| activate_source(g, tap_verified(g, "https://shop#{i}.acme.example")) }
    raise "activation failed" unless activate_project(g).success?
    g
  end

  def tap_verified(g, uri)
    sid = register_source(g, uri)
    verify(g, sid)
    sid
  end

  def ti_session(org)
    TenantSeeder.seed_authorized_admin(organization_id: org, canonical_role: "TechnicalImplementer",
                                       with_policy: false, issued_at: fixed_now - 300)[:session_id]
  end
  def second_marketing_session(org)
    TenantSeeder.seed_authorized_admin(organization_id: org, canonical_role: "MarketingOperator",
                                       with_policy: false, issued_at: fixed_now - 300)[:session_id]
  end
  # Retire the org's active Entitlement Policy (no lifecycle path deactivates it in-app yet), so the
  # request-time entitlement resolution returns nil.
  def deactivate_entitlement(g)
    DbInspector.connection.exec_params(
      "UPDATE entitlement_policies SET status = 'superseded' WHERE organization_id = $1::uuid AND status = 'active'",
      [g[:organization_id]])
  end

  def project_row(pid) = DbInspector.one("SELECT * FROM projects WHERE id = $1::uuid", [pid])
  def source_row(sid) = DbInspector.one("SELECT * FROM sources WHERE id = $1::uuid", [sid])
  def crawls_for(pid) = DbInspector.all("SELECT * FROM crawls WHERE project_id = $1::uuid ORDER BY created_at", [pid])
  def crawl_sources_for(cid) = DbInspector.all("SELECT * FROM crawl_sources WHERE crawl_id = $1::uuid ORDER BY source_order", [cid])
  def events(type, aggregate_id) = DbInspector.all("SELECT * FROM event_registry WHERE event_type = $1 AND aggregate_id = $2::uuid", [type, aggregate_id])

  # Drive the real S-07-003 StartCrawl from the persisted `crawl_dispatch` action QueueCrawl created.
  def start_crawl(crawl_id, at: act_now + 30)
    a = DbInspector.one("SELECT * FROM scheduled_actions WHERE action_kind = 'crawl_dispatch' AND target_id = $1::uuid", [crawl_id])
    Workflows::Wf005::Handlers::StartCrawl.new.call(
      command: Workflows::Wf005::Commands::StartCrawl.new(
        command_id: SecureRandom.uuid_v7, schema_version: a["action_schema_version"],
        organization_id: a["organization_id"], target_type: a["target_type"], crawl_id: a["target_id"],
        due_at: Time.parse(a["due_at"]).getutc, action_id: a["id"],
        action_identity_sha256: [a["identity_sha256"].sub(/\A\\x/, "")].pack("H*"), requested_at_utc: at),
      request_context: Platform::RequestContext.for_service(
        service_identity_id: Platform::ServiceIdentity.scheduled_action_executor,
        clock: Platform::Clock.fixed(at), ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7))
  end

  def queue_crawl(g, project_id: nil, session: nil, key: "qc-#{SecureRandom.hex(6)}")
    Workflows::Wf005::Handlers::QueueCrawl.new.call(
      command: Workflows::Wf005::Commands::QueueCrawl.new(command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
        session_id: session || g[:session_id], organization_id: g[:organization_id], project_id: project_id || g[:project_id],
        requested_at_utc: act_now), request_context: act_ctx)
  end

  describe "queuing a root Crawl (active Project, active Source, active Entitlement Policy)" do
    it "queues a root Crawl pinning the active Source set and the request-time policy versions, emitting CrawlQueued" do
      g = org_with_active_project
      result = queue_crawl(g)
      expect(result.success?).to be(true)
      expect(result.payload[:kind]).to eq("root")
      expect(result.payload[:state]).to eq("queued")
      expect(result.payload[:source_count]).to eq(1)
      expect(result.payload[:requested_entitlement_policy_version]).to be_present
      # No Org/Project crawl policy is active, so the request pins the global ceiling (nil version).
      expect(result.payload[:requested_crawl_policy_version]).to be_nil

      rows = crawls_for(g[:project_id])
      expect(rows.size).to eq(1)
      expect(rows.first["kind"]).to eq("root")
      expect(rows.first["state"]).to eq("queued")
      expect(rows.first["requested_crawl_policy_id"]).to be_nil
      expect(rows.first["requested_entitlement_policy_id"]).to be_present
      expect(rows.first["entitlement_decision_id"]).to be_nil     # PRULE-007: reserves no usage
      expect(rows.first["entitlement_reservation_id"]).to be_nil

      cs = crawl_sources_for(rows.first["id"])
      expect(cs.size).to eq(1)
      expect(cs.first["source_order"]).to eq("0")
      expect(cs.first["scope_policy_id"]).to be_present
      expect(events("CrawlQueued", rows.first["id"]).size).to eq(1)
      # PRULE-007: no Evaluation is created by QueueCrawl.
      expect(DbInspector.count("evaluations")).to eq(0)
    end

    it "pins the active Organization-scope crawl policy version when one is active" do
      g = org_with_active_project
      expect(activate_org_crawl_policy(g, "accepted_pages" => { "soft" => 5_000, "hard" => 6_000 }).success?).to be(true)
      result = queue_crawl(g)
      expect(result.success?).to be(true)
      expect(result.payload[:requested_crawl_policy_version]).to eq("crawl-policy-organization-v1")
      expect(crawls_for(g[:project_id]).first["requested_crawl_policy_id"]).to be_present
    end

    it "pins all active Sources in registration order for a multi-Source Project" do
      g = org_with_active_project(sources: 2)
      result = queue_crawl(g)
      expect(result.payload[:source_count]).to eq(2)
      cs = crawl_sources_for(crawls_for(g[:project_id]).first["id"])
      expect(cs.map { |r| r["source_order"] }).to eq(%w[0 1])
      expect(cs.map { |r| r["source_id"] }.uniq.size).to eq(2)
    end
  end

  describe "preconditions (first-match order)" do
    it "refuses a draft Project as crawl_project_not_active" do
      g = bootstrap
      activate_source(g, tap_verified(g, "https://shop.acme.example")) # active Source, but Project left draft
      result = queue_crawl(g)
      expect(result.failure.reason_code).to eq("crawl_project_not_active")
      expect(crawls_for(g[:project_id])).to be_empty
    end

    it "refuses an active Project with no active Source as crawl_no_active_source" do
      g = bootstrap
      sid = tap_verified(g, "https://shop.acme.example")
      activate_source(g, sid)
      expect(activate_project(g).success?).to be(true)
      expect(disable_source(g, sid).success?).to be(true) # active Project, now zero active Sources
      result = queue_crawl(g)
      expect(result.failure.reason_code).to eq("crawl_no_active_source")
      expect(crawls_for(g[:project_id])).to be_empty
    end

    it "refuses when no active Entitlement Policy resolves as crawl_entitlement_unavailable" do
      g = org_with_active_project
      deactivate_entitlement(g)
      result = queue_crawl(g)
      expect(result.failure.reason_code).to eq("crawl_entitlement_unavailable")
      expect(crawls_for(g[:project_id])).to be_empty
    end

    it "applies the precondition order Project -> Source -> Entitlement (Source wins over Entitlement)" do
      # An active Project whose sole Source is disabled AND whose Entitlement Policy is retired: with
      # two failing preconditions, crawl_no_active_source (checked first) is returned, not entitlement.
      g = bootstrap
      sid = tap_verified(g, "https://shop.acme.example")
      activate_source(g, sid)
      expect(activate_project(g).success?).to be(true)
      expect(disable_source(g, sid).success?).to be(true)
      deactivate_entitlement(g)
      result = queue_crawl(g)
      expect(result.failure.reason_code).to eq("crawl_no_active_source")
    end

    it "denies a Technical Implementer (no crawl.trigger) as crawl_trigger_unauthorized" do
      g = org_with_active_project
      result = queue_crawl(g, session: ti_session(g[:organization_id]))
      expect(result.failure.reason_code).to eq("crawl_trigger_unauthorized")
      expect(crawls_for(g[:project_id])).to be_empty
    end

    it "refuses a Project outside the actor's tenant as tenant_mismatch" do
      g = org_with_active_project
      result = queue_crawl(g, project_id: SecureRandom.uuid_v7)
      expect(result.failure.reason_code).to eq("tenant_mismatch")
    end
  end

  describe "OD-018 single-initial-orchestration guard" do
    it "refuses a second root request while an initial Evaluation is pending/running" do
      g = org_with_active_project
      # S-07-003 built the real producer, so the in-flight Evaluation is now created by the real
      # chain (QueueCrawl -> StartCrawl) rather than inserted by hand.
      first = queue_crawl(g)
      expect(first.success?).to be(true)
      expect(start_crawl(first.payload[:crawl_id]).success?).to be(true)

      result = queue_crawl(g)
      expect(result.failure.reason_code).to eq("initial_evaluation_already_running")
      # MTX-030 error_contract / WORKFLOW_SPECIFICATIONS.md :734: this OD-018 warning carries the
      # await-the-running-Evaluation recovery, not the generic F1-DOMAIN-409 re-read default.
      expect(result.failure.recovery_action).to eq("await_running_initial_evaluation_or_submit_new_command")
      expect(result.failure.retryable).to be(false)
      # Only the first Crawl exists; the refused request created none.
      expect(crawls_for(g[:project_id]).size).to eq(1)
    end
  end

  describe "idempotency and tenant isolation" do
    it "replays an exact QueueCrawl by its key and does not queue twice" do
      g = org_with_active_project
      first = queue_crawl(g, key: "same")
      second = queue_crawl(g, key: "same")
      expect(second.replayed).to be(true)
      expect(second.payload[:crawl_id]).to eq(first.payload[:crawl_id])
      expect(crawls_for(g[:project_id]).size).to eq(1)
    end

    it "replays the stored result even after a precondition ceases to hold (idempotency before preconditions)" do
      # Queue succeeds, then the sole Source is disabled (a precondition — crawl_no_active_source —
      # now fails). An exact replay must still return the stored success, not the new rejection.
      g = bootstrap
      sid = tap_verified(g, "https://shop.acme.example")
      activate_source(g, sid)
      expect(activate_project(g).success?).to be(true)
      first = queue_crawl(g, key: "k")
      expect(first.success?).to be(true)
      expect(disable_source(g, sid).success?).to be(true)
      replay = queue_crawl(g, key: "k")
      expect(replay.replayed).to be(true)
      expect(replay.payload[:crawl_id]).to eq(first.payload[:crawl_id])
      expect(crawls_for(g[:project_id]).size).to eq(1)
    end

    it "rejects a different request under the same key as idempotency_conflict" do
      g = org_with_active_project
      queue_crawl(g, key: "shared")
      # A different actor (distinct account) reusing the same key against the same Project yields a
      # different request digest -> idempotency_conflict (never a wrong-actor queue).
      conflict = queue_crawl(g, key: "shared", session: second_marketing_session(g[:organization_id]))
      expect(conflict.failure.reason_code).to eq("idempotency_conflict")
    end
  end

  # Guard behaviour asserted against REAL rows produced by QueueCrawl (the crawl_sources FK requires a
  # real Source, so these are exercised end-to-end rather than by fabricated inserts).
  describe "the Crawl aggregate database guards (on a real queued Crawl)" do
    def conn = DbInspector.connection

    it "freezes the queued Crawl: no DELETE, no pinned-fact edit, and only the start edges" do
      g = org_with_active_project
      cid = queue_crawl(g).payload[:crawl_id]
      expect { conn.exec_params("DELETE FROM crawls WHERE id = $1::uuid", [cid]) }
        .to raise_error(PG::RaiseException, /crawl_immutable/)
      expect { conn.exec_params("UPDATE crawls SET requested_entitlement_policy_version = 'x' WHERE id = $1::uuid", [cid]) }
        .to raise_error(PG::RaiseException, /crawl_facts_immutable/)
      # S-07-003 relaxed the guard to permit exactly queued->running and queued->failed; queued->canceled
      # (and every other edge) is still refused until later tranches relax it.
      expect { conn.exec_params("UPDATE crawls SET state = 'canceled', terminal_at = now() WHERE id = $1::uuid", [cid]) }
        .to raise_error(PG::RaiseException, /crawl_transition_unavailable/)
    end

    it "makes crawl_sources fully immutable (T-IMM): no UPDATE, no DELETE" do
      g = org_with_active_project
      cid = queue_crawl(g).payload[:crawl_id]
      csid = crawl_sources_for(cid).first["id"]
      expect { conn.exec_params("UPDATE crawl_sources SET source_order = 9 WHERE id = $1::uuid", [csid]) }
        .to raise_error(PG::RaiseException, /crawl_source_immutable/)
      expect { conn.exec_params("DELETE FROM crawl_sources WHERE id = $1::uuid", [csid]) }
        .to raise_error(PG::RaiseException, /crawl_source_immutable/)
    end
  end
end
