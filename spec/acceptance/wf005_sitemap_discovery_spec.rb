# frozen_string_literal: true

require "rails_helper"

# WF-005 sitemap discovery (S-07-006; WORKFLOW_SPECIFICATIONS.md :450/:454; SEARCH_CRAWL_RETRIEVAL.md
# § Robots And Sitemap Processing — "A sitemap item only creates a frontier candidate after
# canonicalization, same-host scope, destination and queue admission checks").
#
# Discovery runs through the SAME gates a content fetch does: the host gate's rate/concurrency claim
# and execution-time authorization. The three requirements the S-07-005 review handed to this tranche
# are asserted directly: candidates are sorted into :454 order, the robots-declared list is treated as
# UNFILTERED, and the discovering sitemap URL is retained on every occurrence record.
#
# Exercised over the PRODUCTION-REAL chain: genesis -> registered + verified + activated Source ->
# ActivateProject -> QueueCrawl -> StartCrawl (which seeds the frontier). The outbound surface is
# the ONLY thing stubbed, and it is stubbed at the frozen F-01 façade rather than inside the service.
RSpec.describe "WF-005 sitemap discovery", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-E2E TYP-SEC TYP-DATA] do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def fixed_now = Time.utc(2026, 7, 27, 10, 0, 0)
  def act_now = fixed_now + 60
  def start_now = act_now + 30
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

  # ---- the production-real chain ---------------------------------------------

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
        submitted_root_uri: uri, expected_state_version: project_row(g[:project_id])["state_version"].to_i,
        requested_at_utc: fixed_now), request_context: act_ctx).payload[:source_id]
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

  def suspend_organization(g)
    org = DbInspector.one("SELECT state_version, authorization_epoch FROM organizations WHERE id = $1::uuid", [g[:organization_id]])
    Workflows::Wf013::Handlers::SuspendOrganization.new.call(
      command: Workflows::Wf013::Commands::SuspendOrganization.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "sus-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], expected_state_version: org["state_version"].to_i,
        expected_authorization_epoch: org["authorization_epoch"].to_i, reason: "billing_hold",
        requested_at_utc: act_now), request_context: act_ctx)
  end

  def running_crawl(host: "shop.acme.example")
    g = bootstrap
    sid = register_source(g, "https://#{host}")
    verify(g, sid)
    activate_source(g, sid)
    raise "activation failed" unless activate_project(g).success?

    crawl_id = Workflows::Wf005::Handlers::QueueCrawl.new.call(
      command: Workflows::Wf005::Commands::QueueCrawl.new(command_id: SecureRandom.uuid_v7, idempotency_key: "qc-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
        requested_at_utc: act_now), request_context: act_ctx).payload[:crawl_id]
    a = DbInspector.one("SELECT * FROM scheduled_actions WHERE action_kind='crawl_dispatch' AND target_id=$1::uuid", [crawl_id])
    Workflows::Wf005::Handlers::StartCrawl.new.call(
      command: Workflows::Wf005::Commands::StartCrawl.new(
        command_id: SecureRandom.uuid_v7, schema_version: a["action_schema_version"], organization_id: a["organization_id"],
        target_type: a["target_type"], crawl_id: a["target_id"], due_at: Time.parse(a["due_at"]).getutc, action_id: a["id"],
        action_identity_sha256: [a["identity_sha256"].sub(/\A\\x/, "")].pack("H*"), requested_at_utc: start_now),
      request_context: executor_ctx(start_now))
    { g:, crawl_id:, source_id: sid, host: }
  end

  # ---- harness ---------------------------------------------------------------

  def project_row(pid) = DbInspector.one("SELECT * FROM projects WHERE id = $1::uuid", [pid])
  def source_row(sid) = DbInspector.one("SELECT * FROM sources WHERE id = $1::uuid", [sid])
  def gate_row(cid) = DbInspector.one("SELECT * FROM crawl_host_gates WHERE crawl_id = $1::uuid", [cid])

  # A stub of the FROZEN F-01 façade — the service is never reached into.
  def outbound_returning(*outcomes)
    queue = outcomes.dup
    Object.new.tap do |o|
      o.define_singleton_method(:fetch) { |*_a, **_k| queue.length > 1 ? queue.shift : queue.first }
    end
  end

  def response(status:, body: "", truncated: false, headers: {})
    Platform::Outbound::Outcome.response(
      status:, headers:, body:, byte_count: body.bytesize, truncated:,
      canonical_host: "shop.acme.example", port: 443, pinned_address: "198.51.100.7",
      final_url: "https://shop.acme.example/robots.txt", redirect_count: 0, latency_ms: 5)
  end

  def timeout_outcome = Platform::Outbound::Outcome.timeout(canonical_host: "shop.acme.example")

  # Run a block against the real host-gate surface inside a proved-Organization unit of work.
  def in_gate(org)
    Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      store = IdentityAccess::Infrastructure::CrawlHostGateStore.new(pg)
      store.enter_org_context(org:, correlation_id: SecureRandom.uuid_v7)
      yield store, Workflows::Wf005::HostGate.new(store, ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
    end
  end

  # Seed `count` live leases, keeping the derived counter in agreement (the database now enforces
  # that they match, so a test cannot fabricate one without the other).
  def seed_leases(id, count, at: start_now)
    leases = Array.new(count) { { token: SecureRandom.uuid_v7, claimed_at: at.utc.iso8601(6) } }
    DbInspector.connection.exec_params(
      "UPDATE crawl_host_gates SET active_leases = $2::jsonb, active_connection_count = $3,
         state_version = state_version + 1 WHERE id = $1::uuid",
      [id, JSON.generate(leases), count])
  end

  def clear_rate_window(id)
    DbInspector.connection.exec_params(
      "UPDATE crawl_host_gates SET recent_start_instants = ARRAY[]::timestamptz(6)[],
         next_allowed_start_at = NULL, state_version = state_version + 1 WHERE id = $1::uuid", [id])
  end

  def ensure_gate(ctx)
    in_gate(ctx[:g][:organization_id]) do |_s, gate|
      gate.ensure_gate(organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
                       crawl_id: ctx[:crawl_id], canonical_host: ctx[:host], now: start_now)
    end
  end

  # EnsureRobots owns its own transactions (claim / fetch outside any transaction / record), so it
  # is invoked WITHOUT a surrounding unit of work — which is itself part of what this asserts.
  def resolve_robots(ctx, outbound)
    Workflows::Wf005::EnsureRobots.new(outbound:).call(
      organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id],
      canonical_host: ctx[:host], now: start_now)
  end

  def authorize(ctx, url: nil, kind: "content", source_id: nil)
    in_gate(ctx[:g][:organization_id]) do |store, _gate|
      row = store.gate(ctx[:g][:organization_id], ctx[:crawl_id], ctx[:host])
      Workflows::Wf005::FetchAuthorization.new(store).authorize(
        organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id],
        source_id: source_id || ctx[:source_id], canonical_url: url || "https://#{ctx[:host]}/",
        gate: row, now: start_now, kind:)
    end
  end

  # ---- sitemap harness --------------------------------------------------------

  def resolve_robots_with(ctx, body)
    resolve_robots(ctx, outbound_returning(response(status: 200, body:)))
  end

  # An outbound stub keyed by URL, so one run can serve robots, an index and its children.
  def outbound_map(map)
    Object.new.tap do |o|
      o.define_singleton_method(:fetch) do |url, **_k|
        entry = map[url]
        next Platform::Outbound::Outcome.response(status: 404, headers: {}, body: "", byte_count: 0,
                                                  truncated: false, canonical_host: "shop.acme.example",
                                                  port: 443, pinned_address: "198.51.100.7",
                                                  final_url: url, redirect_count: 0, latency_ms: 1) if entry.nil?

        Platform::Outbound::Outcome.response(
          status: entry.fetch(:status, 200), headers: { "content-type" => entry.fetch(:type, "application/xml") },
          body: entry.fetch(:body, ""), byte_count: entry.fetch(:body, "").bytesize, truncated: false,
          canonical_host: "shop.acme.example", port: 443, pinned_address: "198.51.100.7",
          final_url: url, redirect_count: 0, latency_ms: 1)
      end
    end
  end

  def urlset(*locs)
    entries = locs.map { |l| "<url><loc>#{l}</loc></url>" }.join
    %(<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{entries}</urlset>)
  end

  def sitemapindex(*locs)
    entries = locs.map { |l| "<sitemap><loc>#{l}</loc></sitemap>" }.join
    %(<?xml version="1.0" encoding="UTF-8"?><sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{entries}</sitemapindex>)
  end

  # The pacer simulates elapsed real time instead of spending it: the host gate's rolling window is
  # measured with clock_timestamp(), so clearing it is exactly what a second of waiting does.
  def pacer_for(ctx)
    lambda do |_ms|
      DbInspector.connection.exec_params(
        "UPDATE crawl_host_gates SET recent_start_instants = ARRAY[]::timestamptz(6)[],
           next_allowed_start_at = NULL, state_version = state_version + 1
         WHERE crawl_id = $1::uuid", [ctx[:crawl_id]])
    end
  end

  def discover(ctx, outbound)
    Workflows::Wf005::DiscoverSitemaps.new(outbound:, pacer: pacer_for(ctx)).call(
      organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id],
      canonical_host: ctx[:host], source_id: ctx[:source_id], project_id: ctx[:g][:project_id],
      now: start_now)
  end

  def frontier_entries(cid) = DbInspector.all("SELECT * FROM crawl_frontier_entries WHERE crawl_id=$1::uuid ORDER BY dequeue_key", [cid])
  def occurrences(cid) = DbInspector.all("SELECT * FROM crawl_frontier_occurrences WHERE crawl_id=$1::uuid ORDER BY occurrence_order", [cid])

  # A running crawl whose robots is resolved and declares the given sitemaps.
  def with_robots(sitemaps: [])
    ctx = running_crawl
    ensure_gate(ctx)
    body = (["User-agent: *", "Disallow: /private"] + sitemaps.map { |s| "Sitemap: #{s}" }).join("\n") + "\n"
    resolve_robots_with(ctx, body)
    ctx
  end

  describe "candidate construction (the robots list is UNFILTERED input)" do
    it "admits same-host declared sitemaps plus the default, and REJECTS a cross-host declaration" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/a.xml", "https://evil.example/b.xml"])
      # S-07-005 stores what was DECLARED, verbatim and unfiltered — both entries, in file order.
      declared = JSON.parse(gate_row(ctx[:crawl_id])["robots_sitemap_candidates"])
      expect(declared).to eq(["https://shop.acme.example/a.xml", "https://evil.example/b.xml"])

      discover(ctx, outbound_map("https://shop.acme.example/a.xml" => { body: urlset("https://shop.acme.example/p1") }))
      admitted = JSON.parse(gate_row(ctx[:crawl_id])["sitemap_candidates"]).map { |c| c["url"] }
      # The cross-host declaration is never admitted; the default always is.
      expect(admitted).to include("https://shop.acme.example/a.xml", "https://shop.acme.example/sitemap.xml")
      expect(admitted).not_to include("https://evil.example/b.xml")
    end

    it "stores the admitted candidates in :454 order, not the robots file order" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/z.xml", "https://shop.acme.example/a.xml"])
      discover(ctx, outbound_map({}))
      admitted = JSON.parse(gate_row(ctx[:crawl_id])["sitemap_candidates"]).map { |c| c["url"] }
      expect(admitted).to eq(admitted.sort)
      expect(admitted.first).to eq("https://shop.acme.example/a.xml")
    end
  end

  describe "content URLs reach the frontier" do
    it "offers each in-scope URL as a depth-1 sitemap candidate" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/s.xml"])
      result = discover(ctx, outbound_map(
        "https://shop.acme.example/s.xml" => { body: urlset("https://shop.acme.example/p1", "https://shop.acme.example/p2") }))
      expect(result.succeeded?).to be(true)
      expect(result.urls_offered).to eq(2)

      sitemap_entries = frontier_entries(ctx[:crawl_id]).select { |e| e["origin"] == "sitemap" }
      expect(sitemap_entries.map { |e| e["canonical_url"] })
        .to contain_exactly("https://shop.acme.example/p1", "https://shop.acme.example/p2")
      # :440 — a sitemap-discovered content URL starts at depth 1.
      expect(sitemap_entries.map { |e| e["depth"] }.uniq).to eq(["1"])
      # :454 forces the entry tuple to ('', 0) for a sitemap candidate.
      expect(sitemap_entries.map { |e| e["discovering_document_url"] }.uniq).to eq([""])
    end

    it "REFUSES a URL the current scope policy excludes" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/s.xml"])
      result = discover(ctx, outbound_map(
        "https://shop.acme.example/s.xml" => { body: urlset("https://other.example/x", "https://shop.acme.example/ok") }))
      expect(result.urls_offered).to eq(1)
      expect(frontier_entries(ctx[:crawl_id]).map { |e| e["canonical_url"] })
        .not_to include("https://other.example/x")
    end

    it "RETAINS the discovering sitemap URL on the occurrence when a URL is discovered twice" do
      # The inherited requirement: the entry tuple has no room for it (:454 forces ('',0)), so without
      # the occurrence carrying it, the provenance of a duplicate sitemap discovery would be lost.
      ctx = with_robots(sitemaps: ["https://shop.acme.example/a.xml", "https://shop.acme.example/b.xml"])
      discover(ctx, outbound_map(
        "https://shop.acme.example/a.xml" => { body: urlset("https://shop.acme.example/same") },
        "https://shop.acme.example/b.xml" => { body: urlset("https://shop.acme.example/same") }))

      expect(frontier_entries(ctx[:crawl_id]).count { |e| e["canonical_url"] == "https://shop.acme.example/same" }).to eq(1)
      occ = occurrences(ctx[:crawl_id])
      expect(occ.size).to eq(1)
      expect(occ.first["discovering_document_url"]).to eq("https://shop.acme.example/b.xml")
      expect(occ.first["duplicate_reason"]).to eq("duplicate_discovery")
    end
  end

  describe "sitemap indexes (:450 — three edges from an initial sitemap)" do
    it "follows an index to its children and records the depth reached" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/index.xml"])
      result = discover(ctx, outbound_map(
        "https://shop.acme.example/index.xml" => { body: sitemapindex("https://shop.acme.example/c1.xml") },
        "https://shop.acme.example/c1.xml" => { body: urlset("https://shop.acme.example/deep") }))
      expect(result.succeeded?).to be(true)
      expect(result.max_index_depth).to eq(1)
      expect(frontier_entries(ctx[:crawl_id]).map { |e| e["canonical_url"] }).to include("https://shop.acme.example/deep")
    end

    it "does NOT follow an index edge beyond the ratified depth" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/i0.xml"])
      chain = (0..4).to_h do |d|
        ["https://shop.acme.example/i#{d}.xml",
         { body: d < 4 ? sitemapindex("https://shop.acme.example/i#{d + 1}.xml") : urlset("https://shop.acme.example/toodeep") }]
      end
      result = discover(ctx, outbound_map(chain))
      expect(result.max_index_depth).to be <= Workflows::Wf005::SitemapCandidates::MAX_INDEX_DEPTH
      expect(frontier_entries(ctx[:crawl_id]).map { |e| e["canonical_url"] })
        .not_to include("https://shop.acme.example/toodeep")
    end

    it "never follows a cross-host child of an index" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/index.xml"])
      discover(ctx, outbound_map(
        "https://shop.acme.example/index.xml" => { body: sitemapindex("https://evil.example/child.xml") },
        "https://evil.example/child.xml" => { body: urlset("https://evil.example/pwned") }))
      expect(frontier_entries(ctx[:crawl_id]).map { |e| e["canonical_url"] }).not_to include("https://evil.example/pwned")
    end
  end

  describe "the :450 outcome table" do
    it "records ABSENT when robots declares none and the default is 404 (coverage NOT reduced)" do
      ctx = with_robots(sitemaps: [])
      result = discover(ctx, outbound_map({}))
      expect(result.state).to eq("absent")
      expect(result.reason_code).to eq("sitemap_absent")
      expect(result.reduces_coverage?).to be(false)
      expect(gate_row(ctx[:crawl_id])["sitemap_state"]).to eq("absent")
    end

    it "records UNAVAILABLE when a declared sitemap exists and none succeeds (coverage partial)" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/gone.xml"])
      result = discover(ctx, outbound_map("https://shop.acme.example/gone.xml" => { status: 500 }))
      expect(result.state).to eq("unavailable")
      expect(result.reason_code).to eq("sitemap_unavailable")
      expect(result.reduces_coverage?).to be(true)
    end

    it "records SUCCEEDED when at least one candidate parses, other failures being telemetry only" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/bad.xml", "https://shop.acme.example/good.xml"])
      result = discover(ctx, outbound_map(
        "https://shop.acme.example/bad.xml" => { status: 500 },
        "https://shop.acme.example/good.xml" => { body: urlset("https://shop.acme.example/p") }))
      expect(result.state).to eq("succeeded")
      expect(result.reduces_coverage?).to be(false)
    end

    it "treats an XXE-bearing sitemap as a failed candidate, never as content" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/evil.xml"])
      body = %(<?xml version="1.0"?><!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]>) +
             "<urlset><url><loc>&x;</loc></url></urlset>"
      result = discover(ctx, outbound_map("https://shop.acme.example/evil.xml" => { body: }))
      expect(result.state).to eq("unavailable")
      expect(frontier_entries(ctx[:crawl_id]).select { |e| e["origin"] == "sitemap" }).to be_empty
    end

    it "refuses a sitemap served with an unsupported media type" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/s.xml"])
      result = discover(ctx, outbound_map(
        "https://shop.acme.example/s.xml" => { body: urlset("https://shop.acme.example/p"), type: "text/html" }))
      expect(result.state).to eq("unavailable")
    end

    it "is write-once: a second discovery returns the frozen outcome without re-fetching" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/s.xml"])
      discover(ctx, outbound_map("https://shop.acme.example/s.xml" => { body: urlset("https://shop.acme.example/p") }))
      exploding = Object.new.tap { |o| o.define_singleton_method(:fetch) { |*_a, **_k| raise "must not refetch" } }
      again = discover(ctx, exploding)
      expect(again.state).to eq("succeeded")
      expect(frontier_entries(ctx[:crawl_id]).count { |e| e["origin"] == "sitemap" }).to eq(1)
    end
  end

  describe "discovery obeys the same gates as a content fetch" do
    it "refuses to run while robots is unresolved" do
      ctx = running_crawl
      ensure_gate(ctx)
      result = discover(ctx, outbound_map({}))
      expect(result.state).to eq("pending")
      expect(result.reason_code).to eq("robots_not_resolved")
    end

    it "offers nothing once the Source has been disabled mid-run" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/s.xml"])
      expect(disable_source(ctx[:g], ctx[:source_id]).success?).to be(true)
      result = discover(ctx, outbound_map(
        "https://shop.acme.example/s.xml" => { body: urlset("https://shop.acme.example/p") }))
      expect(result.urls_offered).to eq(0)
      expect(frontier_entries(ctx[:crawl_id]).select { |e| e["origin"] == "sitemap" }).to be_empty
    end
  end
end
