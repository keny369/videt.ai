# frozen_string_literal: true

require "rails_helper"

# WF-005 StartCrawl (S-07-003; contracts/S-07.json MTX-030 start limb, MTX-058 PRULE-007;
# WORKFLOW_SPECIFICATIONS.md § WF-005 :725-728, :734, :736; SEARCH_CRAWL_RETRIEVAL.md § Crawl
# Admission And Snapshot; DECISIONS OD-018). The service-only `Crawl.Queued -> Crawl.Running`
# commit behind the ratified `crawl_dispatch` ScheduledAction that QueueCrawl schedules.
#
# Exercised over a PRODUCTION-REAL chain (owner D5, no fabricated fixtures): genesis (draft
# Project) -> registered + verified + activated Source -> ActivateProject (S-03) -> QueueCrawl
# (S-07-002, which creates the real `crawl_dispatch` action) -> StartCrawl driven from THAT
# action's own persisted identity.
RSpec.describe "WF-005 start crawl", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-E2E TYP-DATA TYP-SEC TYP-OBS TYP-INT] do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 27, 10, 0, 0)
  def act_now = fixed_now + 60
  def start_now = act_now + 30
  def bc = Platform::BaselineContent
  def gceil = Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING
  def gver = Workflows::Wf005::CrawlPolicy::GLOBAL_VERSION

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

  # ---- the production-real chain up to a queued Crawl -------------------------

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

  def register_source(g, uri)
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
      request_context: executor_ctx(act_now), outbound:)
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

  def queue_crawl(g, key: "qc-#{SecureRandom.hex(6)}")
    Workflows::Wf005::Handlers::QueueCrawl.new.call(
      command: Workflows::Wf005::Commands::QueueCrawl.new(command_id: SecureRandom.uuid_v7, idempotency_key: key, schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
        requested_at_utc: act_now), request_context: act_ctx)
  end

  # An Organization with an ACTIVE Project carrying `sources` active Sources, and one queued Crawl.
  def queued(sources: 1)
    g = bootstrap
    sources.times { |i| activate_source(g, tap_verified(g, "https://shop#{i}.acme.example")) }
    raise "activation failed" unless activate_project(g).success?

    result = queue_crawl(g)
    raise "queue failed" unless result.success?

    { g:, crawl_id: result.payload[:crawl_id] }
  end

  def tap_verified(g, uri)
    sid = register_source(g, uri)
    verify(g, sid)
    sid
  end

  # ---- driving StartCrawl from the REAL crawl_dispatch action ------------------

  def dispatch_action(crawl_id)
    DbInspector.one("SELECT * FROM scheduled_actions WHERE action_kind = 'crawl_dispatch' AND target_id = $1::uuid", [crawl_id])
  end

  # Build the StartCrawl command exactly as the transport does — from the persisted action's own
  # identity — and run the registered handler under the executing Service Identity.
  def start(crawl_id, at: start_now, action: nil, organization_id: nil)
    a = action || dispatch_action(crawl_id)
    cmd = Workflows::Wf005::Commands::StartCrawl.new(
      command_id: SecureRandom.uuid_v7, schema_version: a["action_schema_version"],
      organization_id: organization_id || a["organization_id"], target_type: a["target_type"],
      crawl_id: a["target_id"], due_at: Time.parse(a["due_at"]).getutc, action_id: a["id"],
      action_identity_sha256: [a["identity_sha256"].sub(/\A\\x/, "")].pack("H*"),
      requested_at_utc: at
    )
    Workflows::Wf005::Handlers::StartCrawl.new.call(command: cmd, request_context: executor_ctx(at))
  end

  # ---- readers ---------------------------------------------------------------

  def project_row(pid) = DbInspector.one("SELECT * FROM projects WHERE id = $1::uuid", [pid])
  def source_row(sid) = DbInspector.one("SELECT * FROM sources WHERE id = $1::uuid", [sid])
  def crawl_row(cid) = DbInspector.one("SELECT * FROM crawls WHERE id = $1::uuid", [cid])
  def evaluations_for(pid) = DbInspector.all("SELECT * FROM evaluations WHERE project_id = $1::uuid ORDER BY created_at", [pid])
  def contexts_for(pid) = DbInspector.all("SELECT * FROM evaluation_orchestration_contexts WHERE project_id = $1::uuid", [pid])
  def events(type, aggregate_id) = DbInspector.all("SELECT * FROM event_registry WHERE event_type = $1 AND aggregate_id = $2::uuid", [type, aggregate_id])
  def event_body(id) = JSON.parse(DbInspector.one("SELECT convert_from(event_bytes,'UTF8') AS b FROM event_registry WHERE id = $1::uuid", [id])["b"])
  def decisions(org) = DbInspector.all("SELECT * FROM entitlement_decisions WHERE organization_id = $1::uuid ORDER BY created_at", [org])
  def reservations(org) = DbInspector.all("SELECT * FROM entitlement_reservations WHERE organization_id = $1::uuid ORDER BY created_at", [org])
  def audits(org) = DbInspector.all("SELECT * FROM audit_record_registry WHERE organization_id = $1::uuid ORDER BY occurred_at", [org])
  # Consume `units` of the org's crawl.start day window through the real F-05 reserve surface.
  def consume_crawl_start_units(org, units)
    Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, SecureRandom.uuid_v7])
      service = Platform::Entitlement::Service.new(pg)
      units.times do
        service.reserve(operation: "crawl.start", organization_id: org, subject: { account_id: nil, service_identity_id: Platform::ServiceIdentity.scheduled_action_executor },
                        requested_units: 1, correlation_id: SecureRandom.uuid_v7, now: start_now,
                        ids: { decision: SecureRandom.uuid_v7, reservation: SecureRandom.uuid_v7, window: SecureRandom.uuid_v7 },
                        idempotency_key_digest: Digest::SHA256.digest(SecureRandom.hex(8)))
      end
    end
  end

  # Suspend the Organization through the real WF-013 command (no fabricated status update).
  def suspend_organization(g)
    org = DbInspector.one("SELECT state_version, authorization_epoch FROM organizations WHERE id = $1::uuid", [g[:organization_id]])
    Workflows::Wf013::Handlers::SuspendOrganization.new.call(
      command: Workflows::Wf013::Commands::SuspendOrganization.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "sus-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], expected_state_version: org["state_version"].to_i,
        expected_authorization_epoch: org["authorization_epoch"].to_i,
        reason: "billing_hold", requested_at_utc: act_now), request_context: act_ctx)
  end

  def deactivate_entitlement(g)
    DbInspector.connection.exec_params(
      "UPDATE entitlement_policies SET status = 'superseded' WHERE organization_id = $1::uuid AND status = 'active'",
      [g[:organization_id]])
  end

  # ---------------------------------------------------------------------------

  describe "QueueCrawl schedules the ratified crawl_dispatch action" do
    it "creates exactly one crawl_dispatch action on the crawl queue, due at the queue instant" do
      q = queued
      a = dispatch_action(q[:crawl_id])
      expect(a).to be_present
      expect(a["action_kind"]).to eq("crawl_dispatch")
      expect(a["target_type"]).to eq("crawl")
      expect(a["status"]).to eq("pending")
      expect(a["organization_id"]).to eq(q[:g][:organization_id])
      expect(a["project_id"]).to eq(q[:g][:project_id])
      expect(Platform::ScheduledActions::Catalogue.queue_for("crawl_dispatch")).to eq("crawl")
      expect(Platform::ScheduledActions::Catalogue.work_type_for("crawl_dispatch")).to eq("crawl_orchestrate")
    end

    it "registers StartCrawl as the crawl_dispatch handler at schema version 1.0" do
      entry = Platform::ScheduledActions::Registry.default.resolve(action_kind: "crawl_dispatch", action_schema_version: "1.0")
      expect(entry.operation).to eq("StartCrawl")
      expect(entry.handler).to eq(Workflows::Wf005::Handlers::StartCrawl)
      expect(entry.command).to eq(Workflows::Wf005::Commands::StartCrawl)
    end

    it "rolls the dispatch back with the Crawl when queueing is refused" do
      g = bootstrap
      activate_source(g, tap_verified(g, "https://shop.acme.example")) # Project left draft
      expect(queue_crawl(g).failure.reason_code).to eq("crawl_project_not_active")
      expect(DbInspector.all("SELECT id FROM scheduled_actions WHERE action_kind = 'crawl_dispatch'")).to be_empty
    end
  end

  describe "the accepted root start (Queued -> Running)" do
    it "transitions the Crawl to running, reserves crawl.start, and creates exactly one pending initial Evaluation" do
      q = queued
      result = start(q[:crawl_id])
      expect(result.success?).to be(true)
      expect(result.payload[:state]).to eq("running")
      expect(result.payload[:evaluation_kind]).to eq("initial")
      expect(result.payload[:evaluation_state]).to eq("pending")
      expect(result.payload[:entitlement_decision]).to eq("allow")

      crawl = crawl_row(q[:crawl_id])
      expect(crawl["state"]).to eq("running")
      expect(crawl["state_version"]).to eq("1")
      expect(crawl["started_at"]).to be_present
      expect(crawl["terminal_at"]).to be_nil
      expect(crawl["entitlement_decision_id"]).to be_present
      expect(crawl["entitlement_reservation_id"]).to be_present

      evs = evaluations_for(q[:g][:project_id])
      expect(evs.size).to eq(1)
      expect(evs.first["kind"]).to eq("initial")
      expect(evs.first["state"]).to eq("pending")
      expect(evs.first["crawl_id"]).to eq(q[:crawl_id])
      expect(evs.first["started_at"]).to be_nil
      # POSTGRESQL_SCHEMA.md :340 — the orchestration slot is the WF-011 reassessment/retry
      # single-flight; an INITIAL Evaluation never takes it.
      expect(evs.first["orchestration_slot_active"]).to eq("f")
    end

    it "stamps the wall-clock origin and the 60-minute deadline from the CURRENT resolved policy" do
      q = queued
      start(q[:crawl_id])
      crawl = crawl_row(q[:crawl_id])
      started = Time.parse(crawl["started_at"]).getutc
      expect(started).to eq(start_now)
      # crawl-policy-v1 wall clock hard bound = 60 minutes, measured from Queued -> Running.
      expect(Time.parse(crawl["deadline_at"]).getutc - started).to eq(60 * 60)
    end

    it "re-resolves the CURRENT crawl policy at start rather than the version pinned at queue time" do
      q = queued
      # A narrowing Organization policy activated AFTER queueing must govern the run immediately
      # (WORKFLOW_SPECIFICATIONS.md :732), so the wall clock comes from it, not the pinned ceiling.
      expect(activate_org_crawl_policy(q[:g], "wall_clock_minutes" => { "soft" => 20, "hard" => 30 }).success?).to be(true)
      expect(crawl_row(q[:crawl_id])["requested_crawl_policy_version"]).to be_nil # pinned: global ceiling
      result = start(q[:crawl_id])
      expect(result.payload[:crawl_policy_version]).to eq("crawl-policy-organization-v1")
      crawl = crawl_row(q[:crawl_id])
      expect(Time.parse(crawl["deadline_at"]).getutc - Time.parse(crawl["started_at"]).getutc).to eq(30 * 60)
      expect(contexts_for(q[:g][:project_id]).first["crawl_policy_version"]).to eq("crawl-policy-organization-v1")
    end

    it "writes the immutable orchestration context bound to the root Decision and reservation" do
      q = queued
      result = start(q[:crawl_id])
      ctxs = contexts_for(q[:g][:project_id])
      expect(ctxs.size).to eq(1)
      c = ctxs.first
      expect(c["evaluation_id"]).to eq(result.payload[:evaluation_id])
      expect(c["crawl_id"]).to eq(q[:crawl_id])
      expect(c["root_entitlement_decision_id"]).to eq(result.payload[:entitlement_decision_id])
      expect(c["root_entitlement_reservation_id"]).to eq(result.payload[:entitlement_reservation_id])
      expect(c["entitlement_policy_version"]).to be_present
      # An INITIAL assessment has no prior promoted pair to point at.
      expect(c["prior_evaluation_id"]).to be_nil
      expect(c["prior_issue_set_id"]).to be_nil
      expect(c["prior_score_snapshot_id"]).to be_nil
      # FU-3: the sealed source-set / scope identity is unbuilt, so these stay NULL rather than
      # carrying a locally invented substitute (DECISIONS ADR-073).
      expect(c["source_set_hash"]).to be_nil
      expect(c["normalized_scope_hash"]).to be_nil
    end

    it "moves the reservation reserved -> executing and accrues exactly one crawl.start unit" do
      q = queued
      start(q[:crawl_id])
      org = q[:g][:organization_id]
      ds = decisions(org)
      expect(ds.size).to eq(1)
      expect(ds.first["operation"]).to eq("crawl.start")
      expect(ds.first["decision"]).to eq("allow")
      expect(ds.first["requested_units"]).to eq("1")
      expect(ds.first["account_id"]).to be_present       # the queueing actor is the metered subject
      expect(ds.first["service_identity_id"]).to be_nil

      rs = reservations(org)
      expect(rs.size).to eq(1)
      expect(rs.first["state"]).to eq("executing")
      expect(rs.first["started_at"]).to be_present
      window = DbInspector.one("SELECT * FROM entitlement_counter_windows WHERE organization_id = $1::uuid", [org])
      expect(window["reserved_units"]).to eq("1")
      expect(window["committed_units"]).to eq("0")
    end

    it "emits CrawlStarted and EvaluationPending, service-attributed with a null human actor" do
      q = queued
      result = start(q[:crawl_id])
      started = events("CrawlStarted", q[:crawl_id])
      expect(started.size).to eq(1)
      expect(started.first["aggregate_type"]).to eq("crawl")
      expect(started.first["event_profile"]).to eq("state_transition")
      expect(started.first["aggregate_version"]).to eq("1")

      pending = events("EvaluationPending", result.payload[:evaluation_id])
      expect(pending.size).to eq(1)
      expect(pending.first["aggregate_type"]).to eq("evaluation")
      expect(pending.first["event_profile"]).to eq("created")

      body = JSON.parse(DbInspector.one("SELECT convert_from(event_bytes,'UTF8') AS b FROM event_registry WHERE id = $1::uuid", [started.first["id"]])["b"])
      expect(body["actor_id"]).to be_nil
      expect(body["service_identity_id"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)
      expect(body["from_state"]).to eq("queued")
      expect(body["to_state"]).to eq("running")

      audit = audits(q[:g][:organization_id]).last
      expect(audit["actor_id"]).to be_nil
      expect(audit["service_identity_id"]).to eq(Platform::ServiceIdentity.scheduled_action_executor)
      expect(audit["to_state"]).to eq("running")
    end

    it "performs no outbound work and creates no frontier record (S-07-004 owns the frontier)" do
      q = queued
      expect(start(q[:crawl_id]).success?).to be(true)
      expect(DbInspector.connection.exec("SELECT to_regclass('crawl_frontier_entries') AS t").getvalue(0, 0)).to be_nil
    end
  end

  describe "the exact pre-execution gate (queued -> failed, no side effect)" do
    def expect_pre_execution_failure(q, reason)
      result = start(q[:crawl_id])
      expect(result.failure.reason_code).to eq(reason)
      crawl = crawl_row(q[:crawl_id])
      expect(crawl["state"]).to eq("failed")
      # WORKFLOW_SPECIFICATIONS.md :456 closes CompletionReason to five values, so a pre-execution
      # failure records exactly `failed`; the exact machine reason is retained in the restricted
      # audit record and on the CrawlFailed envelope, never in this column.
      expect(crawl["completion_reason"]).to eq("failed")
      expect(crawl["terminal_at"]).to be_present
      expect(crawl["coverage_status"]).to be_nil
      expect(crawl["started_at"]).to be_nil
      # POSTGRESQL_SCHEMA.md :338 — both entitlement columns are "NULL until start", and this Crawl
      # never started.
      expect(crawl["entitlement_decision_id"]).to be_nil
      expect(crawl["entitlement_reservation_id"]).to be_nil
      expect(evaluations_for(q[:g][:project_id])).to be_empty
      expect(contexts_for(q[:g][:project_id])).to be_empty
      failed = events("CrawlFailed", q[:crawl_id])
      expect(failed.size).to eq(1)
      expect(event_body(failed.first["id"])["reason_code"]).to eq(reason)
      expect(audits(q[:g][:organization_id]).last["reason_code"]).to eq(reason)
      expect(events("CrawlStarted", q[:crawl_id])).to be_empty
      result
    end

    # The Project limb of the gate is defence in depth, not dead code: WF-005 and
    # SEARCH_CRAWL_RETRIEVAL.md both require StartCrawl to reauthorize current Project state. It is
    # UNREACHABLE today because OD-014 is pending and `f1_projects_lifecycle_guard` permits exactly
    # draft -> active, so no active Project can leave `active`. This asserts that unreachability
    # rather than pretending to exercise a path the database forbids; the pause/archive tranche
    # that relaxes the guard makes it live, and it is checked before any Entitlement is consumed.
    it "cannot be reached while OD-014 is pending — an active Project cannot leave active" do
      q = queued
      expect { DbInspector.connection.exec_params("UPDATE projects SET state = 'paused' WHERE id = $1::uuid", [q[:g][:project_id]]) }
        .to raise_error(PG::RaiseException, /project_lifecycle_transition_unavailable active -> paused/)
      expect(crawl_row(q[:crawl_id])["state"]).to eq("queued")
    end

    it "fails the queued Crawl when every Source has left active" do
      q = queued
      sid = DbInspector.one("SELECT source_id FROM crawl_sources WHERE crawl_id = $1::uuid", [q[:crawl_id]])["source_id"]
      expect(disable_source(q[:g], sid).success?).to be(true)
      expect_pre_execution_failure(q, "crawl_no_active_source")
      expect(reservations(q[:g][:organization_id])).to be_empty
    end

    it "fails the queued Crawl with the Entitlement Block reason when no policy resolves" do
      q = queued
      deactivate_entitlement(q[:g])
      result = expect_pre_execution_failure(q, "entitlement_inactive")
      # WORKFLOW_SPECIFICATIONS.md :541 fixes the mapping: "inactive entitlement -> upgrade_plan".
      expect(result.failure.recovery_action).to eq("upgrade_plan")
      expect(result.failure.retryable).to be(false)
      # WORKFLOW :734 — the Block leaves a durable Decision but NO reservation.
      expect(decisions(q[:g][:organization_id]).size).to eq(1)
      expect(decisions(q[:g][:organization_id]).first["decision"]).to eq("block")
      expect(reservations(q[:g][:organization_id])).to be_empty
      # The blocked Decision is recorded in the audit record, not on a Crawl that never started.
      expect(JSON.parse(audits(q[:g][:organization_id]).last["payload"])["entitlement_decision_id"])
        .to eq(decisions(q[:g][:organization_id]).first["id"])
    end

    it "fails the queued Crawl when the hard crawl.start limit is already consumed" do
      q = queued
      org = q[:g][:organization_id]
      # entitlement-interim-v1 crawl.start: soft 3 / hard 4 per UTC day. Consume the window to the
      # hard bound through the REAL F-05 surface (no fabricated counter row), so this request's
      # single unit would exceed it.
      consume_crawl_start_units(org, 4)
      result = expect_pre_execution_failure(q, "hard_limit_exceeded")
      expect(result.failure.recovery_action).to eq("wait_for_window")
      # The blocked request adds a Decision but no fifth reservation.
      expect(reservations(org).size).to eq(4)
      expect(decisions(org).map { |r| r["decision"] }).to eq(%w[allow allow allow_with_warning allow_with_warning block])
      # The blocked Decision is named in the restricted audit record, not on the Crawl row.
      expect(JSON.parse(audits(org).last["payload"])["entitlement_decision_id"]).to eq(decisions(org).last["id"])
    end

    it "fails the queued Crawl when the Organization has been suspended since queueing" do
      # MTX-030 authorization_entry_point: "an authorization ... established at queue time is never
      # trusted at execution time"; SEARCH_CRAWL_RETRIEVAL.md step 1 reauthorizes current
      # ORGANIZATION state first. Without this a suspended tenant — every Session revoked — would
      # still start protected work and burn a metered crawl.start unit.
      q = queued
      expect(suspend_organization(q[:g]).success?).to be(true)
      result = expect_pre_execution_failure(q, "crawl_organization_not_active")
      # WORKFLOW_SPECIFICATIONS.md :541: "Organization -> reactivate_organization".
      expect(result.failure.recovery_action).to eq("reactivate_organization")
      # Checked before the entitlement limb, so a suspended tenant consumes nothing.
      expect(decisions(q[:g][:organization_id])).to be_empty
      expect(reservations(q[:g][:organization_id])).to be_empty
    end

    it "refuses a start whose (crawl_id, kind=initial) key is already taken as evaluation_creation_conflict" do
      q = queued
      # The key taken out of band while the Crawl is still queued — the only way to reach the
      # contract's concurrent-altered-creation reason, since the handler otherwise creates the
      # Evaluation in the same commit that leaves `queued`.
      DbInspector.connection.exec_params(<<~SQL, [SecureRandom.uuid_v7, q[:g][:organization_id], q[:g][:project_id], q[:crawl_id]])
        INSERT INTO evaluations (id, created_at, updated_at, correlation_id, organization_id, project_id, kind, crawl_id, state)
        VALUES ($1::uuid, now(), now(), gen_random_uuid(), $2::uuid, $3::uuid, 'initial', $4::uuid, 'completed')
      SQL
      result = start(q[:crawl_id])
      expect(result.failure.reason_code).to eq("evaluation_creation_conflict")
      # A request rejection: no state change, no reservation, no second Evaluation.
      expect(crawl_row(q[:crawl_id])["state"]).to eq("queued")
      expect(evaluations_for(q[:g][:project_id]).size).to eq(1)
      expect(reservations(q[:g][:organization_id])).to be_empty
    end

    it "fails the losing Crawl under the OD-018 guard when another initial Evaluation is in flight" do
      # Two queued root Crawls for one Project is intended (S-07-002); single-flight is enforced
      # HERE. The first start wins; the second is refused and its Crawl fails.
      q = queued
      first = queue_crawl(q[:g], key: "first-#{SecureRandom.hex(4)}")
      second_id = first.payload[:crawl_id]
      expect(start(q[:crawl_id]).success?).to be(true)

      result = start(second_id)
      expect(result.failure.reason_code).to eq("initial_evaluation_already_running")
      expect(result.failure.recovery_action).to eq("await_running_initial_evaluation_or_submit_new_command")
      expect(crawl_row(second_id)["state"]).to eq("failed")
      expect(crawl_row(second_id)["completion_reason"]).to eq("failed")
      expect(event_body(events("CrawlFailed", second_id).first["id"])["reason_code"])
        .to eq("initial_evaluation_already_running")
      # Exactly one initial Evaluation, one reservation, one orchestration context for the Project.
      expect(evaluations_for(q[:g][:project_id]).size).to eq(1)
      expect(contexts_for(q[:g][:project_id]).size).to eq(1)
      expect(reservations(q[:g][:organization_id]).size).to eq(1)
    end
  end

  describe "transport integrity and idempotency" do
    it "replays the accepted start by the action identity and starts nothing twice" do
      q = queued
      first = start(q[:crawl_id])
      replay = start(q[:crawl_id])
      expect(replay.replayed).to be(true)
      expect(replay.payload[:evaluation_id]).to eq(first.payload[:evaluation_id])
      expect(evaluations_for(q[:g][:project_id]).size).to eq(1)
      expect(reservations(q[:g][:organization_id]).size).to eq(1)
      expect(events("CrawlStarted", q[:crawl_id]).size).to eq(1)
    end

    it "replays a recorded pre-execution failure rather than re-failing the Crawl" do
      q = queued
      sid = DbInspector.one("SELECT source_id FROM crawl_sources WHERE crawl_id = $1::uuid", [q[:crawl_id]])["source_id"]
      expect(disable_source(q[:g], sid).success?).to be(true)
      first = start(q[:crawl_id])
      expect(first.failure.reason_code).to eq("crawl_no_active_source")
      replay = start(q[:crawl_id])
      expect(replay.replayed).to be(true)
      expect(replay.failure.reason_code).to eq("crawl_no_active_source")
      expect(events("CrawlFailed", q[:crawl_id]).size).to eq(1)
    end

    it "treats a dispatch for a Crawl that already left queued as a harmless terminal execution" do
      q = queued
      expect(start(q[:crawl_id]).success?).to be(true)
      # A different action identity for the same, now-running Crawl: not a replay, no state change.
      other = dispatch_action(q[:crawl_id]).merge("identity_sha256" => "\\x#{Digest::SHA256.hexdigest('other')}")
      result = start(q[:crawl_id], action: other)
      expect(result.failure.reason_code).to eq("crawl_not_queued")
      expect(crawl_row(q[:crawl_id])["state_version"]).to eq("1")
      expect(evaluations_for(q[:g][:project_id]).size).to eq(1)
    end

    it "quarantines a dispatch naming an unknown Crawl as scheduled_action_target_mismatch" do
      q = queued
      unknown = dispatch_action(q[:crawl_id]).merge("target_id" => SecureRandom.uuid_v7)
      result = start(q[:crawl_id], action: unknown)
      expect(result.failure.reason_code).to eq("scheduled_action_target_mismatch")
      expect(Platform::ScheduledActions::Worker::QUARANTINE_REASONS).to include("scheduled_action_target_mismatch")
      expect(crawl_row(q[:crawl_id])["state"]).to eq("queued")
    end

    it "refuses a dispatch delivered before its due instant" do
      q = queued
      result = start(q[:crawl_id], at: act_now - 3600)
      expect(result.failure.reason_code).to eq("scheduled_action_not_due")
      expect(crawl_row(q[:crawl_id])["state"]).to eq("queued")
    end

    it "refuses a target_type that is not a crawl without touching the database" do
      q = queued
      wrong = dispatch_action(q[:crawl_id]).merge("target_type" => "invitation")
      result = start(q[:crawl_id], action: wrong)
      expect(result.failure.reason_code).to eq("scheduled_action_target_mismatch")
      expect(crawl_row(q[:crawl_id])["state"]).to eq("queued")
    end

    it "cannot start another Organization's Crawl through a forged organization_id" do
      q = queued
      other = TenantSeeder.create_organization(display_name: "Rival Org")
      # The handler enters the FORGED Organization's context, so RLS hides the Crawl entirely:
      # the composite tenant read returns nothing and the start fails closed with no state change.
      result = start(q[:crawl_id], organization_id: other)
      expect(result.failure.reason_code).to eq("scheduled_action_target_mismatch")
      expect(crawl_row(q[:crawl_id])["state"]).to eq("queued")
      expect(evaluations_for(q[:g][:project_id])).to be_empty
    end
  end
end
