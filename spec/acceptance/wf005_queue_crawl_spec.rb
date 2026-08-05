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
      # SUPERSEDED AND REPLACED, NOT DELETED. This example asserted `queued -> canceled` was REFUSED,
      # which was true of the guard S-07-003 left and is exactly what S-07-009 changes: :736 names that
      # edge, and `20260727120360_crawls_terminal_transitions` opens it. What is still refused from
      # `queued` is `completed` — :736 gives no such edge, because a Crawl that never ran cannot have
      # completed. The whole cross product is enumerated in
      # `spec/persistence/crawl_start_invariants_spec.rb` PROOF 50; this asserts it on a REAL queued
      # Crawl, which is what this describe block is for.
      expect { conn.exec_params("UPDATE crawls SET state = 'completed', terminal_at = now(), completion_reason = 'completed', coverage_status = 'full' WHERE id = $1::uuid", [cid]) }
        .to raise_error(PG::RaiseException, /crawl_transition_unavailable queued -> completed/)
      expect { conn.exec_params("UPDATE crawls SET state = 'canceled', terminal_at = now(), completion_reason = 'canceled' WHERE id = $1::uuid", [cid]) }
        .not_to raise_error
      # And having cancelled it, the row is FINISHED: no further edit of any kind (:458's "once").
      expect { conn.exec_params("UPDATE crawls SET completion_reason = 'failed' WHERE id = $1::uuid", [cid]) }
        .to raise_error(PG::RaiseException, /crawl_terminal_immutable/)
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

  # ROUND 7, SEC-B1. `QueueCrawl` authorizes `crawl.trigger`, then takes
  # `pg_advisory_xact_lock('crawl-queue:<org>:<project>')` — a BLOCKING wait — and only then commits.
  # ADR-120 Ruling 1 draws its line at "can wait", and round 6 repaired `CancelCrawl` on exactly that
  # reasoning while leaving this handler alone. A queued Crawl is not a small effect: it mints the
  # `crawl_dispatch` action, so a revoked authority goes on to start a metered run that makes outbound
  # requests to the customer's host.
  describe "authority revoked while the command waits on its advisory lock (SEC-B1)" do
    it "PROOF 169 — a queue whose authority is revoked during the wait does not commit" do
      g = org_with_active_project
      key = RaceHarness.key_for("crawl-queue:#{g[:organization_id]}:#{g[:project_id]}")
      controller = RaceHarness.open_connection
      before = DbInspector.one("SELECT count(*) AS n FROM crawls WHERE organization_id=$1::uuid",
                               [g[:organization_id]])["n"].to_i
      result = nil

      begin
        controller.exec_params("SELECT pg_advisory_lock($1)", [key])
        op = RaceHarness.spawn_operation(-> { queue_crawl(g) })
        RaceHarness.wait_until("the queue blocked on its project lock") do
          RaceHarness.blocked_on(key) >= 1
        end
        # COMMITTED UNDERNEATH THE WAITER, which is what makes this a revocation rather than a fixture.
        DbInspector.connection.exec_params(
          "UPDATE organizations SET authorization_epoch = authorization_epoch + 1 WHERE id = $1::uuid",
          [g[:organization_id]]
        )
        expect(RaceHarness.blocked_on(key)).to be >= 1
      ensure
        controller.exec_params("SELECT pg_advisory_unlock_all()")
        result = op&.value
        controller.close
      end

      expect(result).to be_a(Platform::CommandResult), result.inspect
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("crawl_trigger_unauthorized")
      # No Crawl, and therefore no `crawl_dispatch` action to start a metered run.
      expect(DbInspector.one("SELECT count(*) AS n FROM crawls WHERE organization_id=$1::uuid",
                             [g[:organization_id]])["n"].to_i).to eq(before)
      expect(DbInspector.one(<<~SQL, [g[:organization_id]])["n"].to_i).to eq(0)
        SELECT count(*) AS n FROM scheduled_actions
        WHERE organization_id = $1::uuid AND action_kind = 'crawl_dispatch'
      SQL
    end

    it "PROOF 170 — the recheck is not a blanket refusal: an unrevoked wait still commits" do
      # The adversarial half. A handler that refused after every wait would satisfy PROOF 169 and be
      # useless. Same shape, same observed wait, no epoch advance.
      g = org_with_active_project
      key = RaceHarness.key_for("crawl-queue:#{g[:organization_id]}:#{g[:project_id]}")
      controller = RaceHarness.open_connection
      result = nil

      begin
        controller.exec_params("SELECT pg_advisory_lock($1)", [key])
        op = RaceHarness.spawn_operation(-> { queue_crawl(g) })
        RaceHarness.wait_until("the queue blocked on its project lock") do
          RaceHarness.blocked_on(key) >= 1
        end
      ensure
        controller.exec_params("SELECT pg_advisory_unlock_all()")
        result = op&.value
        controller.close
      end

      expect(result).to be_a(Platform::CommandResult), result.inspect
      expect(result.success?).to be(true), result.inspect
    end
  end


  # AUTHORITY IS A CONJUNCT OF THE QUEUE WRITE (D6; supersedes PROOF 193's classification for this
  # handler).
  #
  # WHAT THIS REPLACED. PROOF 193 decided which handlers needed a post-wait authority check by
  # matching source against a lock-name regex and excusing the rest through a maintained list. The
  # property is now owned by the write: `insert_crawl` applies nothing unless the organization's
  # `authorization_epoch` still equals the epoch the actor authenticated with. There is no handler to
  # classify, because there is no handler-level check the safety depends on.
  describe "write-level authority" do
    def revoke!(g)
      DbInspector.one("UPDATE organizations SET authorization_epoch = authorization_epoch + 1 " \
                      "WHERE id = $1::uuid RETURNING authorization_epoch", [g[:organization_id]])
    end

    def crawls_for(g) = DbInspector.all("SELECT * FROM crawls WHERE organization_id = $1::uuid", [g[:organization_id]])

    # A REAL RACER. A one-shot hook fires immediately before the store's insert and performs the
    # revocation on its own connection — a revocation landing in the window between the handler's
    # Ruby recheck and its write, which is the interleaving the invariant exists for. The mechanism
    # under test then runs for real against the state the racer left.
    def revoke_during_lock_wait(g)
      fired = false
      hook = Module.new do
        define_method(:lock_project) do |*args|
          result = super(*args)
          unless fired
            fired = true
            DbInspector.one("UPDATE organizations SET authorization_epoch = authorization_epoch + 1 " \
                            "WHERE id = $1::uuid RETURNING authorization_epoch", [args.first])
          end
          result
        end
      end
      IdentityAccess::Infrastructure::CrawlStore.prepend(hook)
      yield
    ensure
      fired = true
    end

    def revoke_just_before_write(g)
      fired = false
      hook = Module.new do
        define_method(:insert_crawl) do |row|
          unless fired
            fired = true
            DbInspector.one("UPDATE organizations SET authorization_epoch = authorization_epoch + 1 " \
                            "WHERE id = $1::uuid RETURNING authorization_epoch", [g[:organization_id]])
          end
          super(row)
        end
      end
      IdentityAccess::Infrastructure::CrawlStore.prepend(hook)
      yield
    ensure
      fired = true
    end

    it "PROOF 221 — authority current and state eligible: the Crawl is queued" do
      g = org_with_active_project

      expect(queue_crawl(g).success?).to be(true)
      expect(crawls_for(g).length).to eq(1)
    end

    it "PROOF 222 — a revocation BEFORE the command is not a stale epoch, and must not deny" do
      # WORTH STATING BECAUSE THE FIRST VERSION OF THIS PROOF GOT IT WRONG. Revoking before the
      # command runs does not produce a stale actor: the handler authenticates AFTER the revocation
      # and therefore holds the NEW epoch, which is current. The invariant is about a revocation that
      # lands between authentication and the write — PROOF 223 — not about any revocation at all. A
      # proof that expected a denial here would have been asserting the wrong property and would have
      # been satisfied by an over-broad predicate.
      g = org_with_active_project
      revoke!(g)

      result = queue_crawl(g)

      expect(result.success?).to be(true)
      expect(crawls_for(g).length).to eq(1)
    end

    it "PROOF 223 — authority revoked WHILE THE HANDLER WAITS: nothing is queued after the wait" do
      g = org_with_active_project

      result = revoke_during_lock_wait(g) { queue_crawl(g) }

      expect(result).not_to be_success
      expect(result.reason_code).to eq("crawl_trigger_unauthorized")
      expect(crawls_for(g)).to be_empty, "a Crawl was queued on authority revoked during the wait"
      # Scoped to the crawl dispatch this command would have created — the fixture legitimately holds
      # other scheduled actions, and a global count would assert something this proof is not about.
      expect(DbInspector.all("SELECT id FROM scheduled_actions WHERE action_kind = 'crawl_dispatch'"))
        .to be_empty, "a dispatch was scheduled for a Crawl that was never queued"
    end

    it "PROOF 223b — revoked AFTER the handler's own recheck: the WRITE is what refuses" do
      # WHY THIS EXISTS SEPARATELY FROM PROOF 223, and it is the difference between proving the new
      # invariant and proving the old one. PROOF 223's revocation lands during `lock_project`, which
      # is BEFORE the handler's Ruby recheck — so that recheck denies and the write-level predicate is
      # never reached. A mutation deleting the write's outcome check SURVIVED 223 for exactly that
      # reason. Here the revocation lands between the recheck and the write, where only the statement
      # itself can refuse it.
      g = org_with_active_project

      result = revoke_just_before_write(g) { queue_crawl(g) }

      expect(result).not_to be_success
      expect(result.reason_code).to eq("crawl_trigger_unauthorized")
      expect(crawls_for(g)).to be_empty, "a Crawl was queued on authority the write should have refused"
      expect(DbInspector.all("SELECT id FROM scheduled_actions WHERE action_kind = 'crawl_dispatch'"))
        .to be_empty
      expect(DbInspector.all("SELECT id FROM crawl_sources")).to be_empty,
             "follow-on rows were written for a Crawl the write refused to create"
    end

    it "PROOF 224 — the store refuses a stale epoch when invoked DIRECTLY by another caller" do
      # The invariant belongs to the write, so it holds for any production caller — not only for the
      # handler this spec drives.
      g = org_with_active_project
      current = DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id=$1::uuid",
                                [g[:organization_id]])["authorization_epoch"].to_i
      revoke!(g)

      outcome = Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
        pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)",
                       [g[:organization_id], SecureRandom.uuid_v7])
        IdentityAccess::Infrastructure::CrawlStore.new(pg).insert_crawl(
          id: SecureRandom.uuid_v7, now: act_now, correlation_id: SecureRandom.uuid_v7,
          organization_id: g[:organization_id], authorization_epoch: current,
          project_id: g[:project_id], kind: "root", requested_crawl_policy_id: nil,
          requested_crawl_policy_version: nil, requested_entitlement_policy_id: SecureRandom.uuid_v7,
          requested_entitlement_policy_version: "entitlement-interim-v1", trigger_kind: "manual",
          triggered_by_account_id: nil, idempotency_key_digest: "\x00" * 32
        )
      end

      expect(outcome[:authorized]).to be(false)
      expect(outcome[:inserted]).to eq(0)
      expect(crawls_for(g)).to be_empty
    end

    it "PROOF 193 — StartCrawl carries NO human authority, so :335 does not govern it" do
      # WHAT THIS REPLACED. `PROOF 193` used to decide which handlers needed a post-wait authority
      # check by matching source against a lock-name regex, excusing the rest through a maintained
      # `CLASSIFIED_WITHOUT_POST_WAIT` list whose single entry asserted THIS fact in prose. The
      # classification question is dissolved — every protected transition now carries authority as a
      # conjunct of its own write — but the fact itself is real and is kept as behaviour: StartCrawl is
      # executed by the scheduled-action executor against a durable action, with no Session, so there
      # is no human authority in flight for a revocation to invalidate.
      #
      # It is observed through the same runtime signal `AuthoritySentinel` uses to decide the question,
      # rather than by reading the handler's source.
      authenticate = ExecutionProbe.calls("IdentityAccess::Authorization::CommandAuthorizer#authenticate").first
      g = org_with_active_project
      queued = queue_crawl(g)
      expect(queued.success?).to be(true)

      seen = ExecutionProbe.watch([authenticate]) { start_crawl(queued.payload[:crawl_id]) }

      expect(seen).not_to have_evaluated(authenticate),
                          "StartCrawl authenticated a Session; it would then be human-authorized and " \
                          ":335 would govern it"
    end

    it "PROOF 225 — a retry after a committed queue follows the idempotency contract" do
      g = org_with_active_project
      key = "qc-retry-#{SecureRandom.hex(4)}"

      first = queue_crawl(g, key: key)
      second = queue_crawl(g, key: key)

      expect(first.success?).to be(true)
      expect(second.success?).to be(true), "a retry of a committed queue must replay, not fail"
      expect(crawls_for(g).length).to eq(1), "the retry queued a second Crawl"
    end
  end
end
