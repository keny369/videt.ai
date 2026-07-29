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

  # Every request the stub sees, WITH its keyword arguments. The stub used to discard them
  # (`**_k`), so the ratified per-fetch bounds — timeout, byte cap, redirect budget, user agent —
  # had no coverage at all and any of them could have been deleted with the suite still green.
  def requests = (@requests ||= [])

  # An outbound stub keyed by URL, so one run can serve robots, an index and its children.
  def outbound_map(map)
    sink = requests
    Object.new.tap do |o|
      o.define_singleton_method(:fetch) do |url, **kwargs|
        sink << kwargs.merge(url:)
        entry = map[url]
        next Platform::Outbound::Outcome.response(status: 404, headers: {}, body: "", byte_count: 0,
                                                  truncated: false, canonical_host: "shop.acme.example",
                                                  port: 443, pinned_address: "198.51.100.7",
                                                  final_url: url, redirect_count: 0, latency_ms: 1) if entry.nil?

        headers = entry.key?(:type) && entry[:type].nil? ? {} : { "content-type" => entry.fetch(:type, "application/xml") }
        Platform::Outbound::Outcome.response(
          status: entry.fetch(:status, 200), headers:,
          body: entry.fetch(:body, ""), byte_count: entry.fetch(:body, "").bytesize,
          truncated: entry.fetch(:truncated, false),
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

  # The pacer simulates elapsed real time instead of spending it. It ADVANCES THE CLOCK BY THE
  # REQUESTED INTERVAL rather than clearing the gate outright: `recent_start_instants` is a rolling
  # one-second window and `next_allowed_start_at` is an arbitrary interval — `max(base, robots
  # Crawl-delay, ...)` — so nulling the second one made the very first retry succeed whatever the
  # configured delay, and no test could ever exhaust the deferral bound. Every pace is recorded, so
  # a test can assert the traversal waited the length the HOST asked for.
  def paces = (@paces ||= [])

  def pacer_for(ctx)
    sink = paces
    lambda do |ms|
      sink << ms.to_i
      # `ms` of real time passing IS every recorded instant moving `ms` further into the past. Doing
      # it that way — rather than clearing the columns — means the gate's own predicates decide
      # whether enough time has elapsed, so a `Crawl-delay` longer than the pace still refuses.
      DbInspector.connection.exec_params(
        "UPDATE crawl_host_gates
         SET recent_start_instants =
               (SELECT COALESCE(array_agg(s - ($2 || ' milliseconds')::interval),
                                ARRAY[]::timestamptz(6)[])
                FROM unnest(recent_start_instants) AS s),
             next_allowed_start_at = next_allowed_start_at - ($2 || ' milliseconds')::interval,
             state_version = state_version + 1
         WHERE crawl_id = $1::uuid", [ctx[:crawl_id], ms.to_i])
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
  def with_robots(sitemaps: [], crawl_delay: nil)
    ctx = running_crawl
    ensure_gate(ctx)
    lines = ["User-agent: *", "Disallow: /private"]
    lines << "Crawl-delay: #{crawl_delay}" if crawl_delay
    body = (lines + sitemaps.map { |s| "Sitemap: #{s}" }).join("\n") + "\n"
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
    it "records ABSENT only when robots declares none AND the default is 404/410 (coverage NOT reduced)" do
      ctx = with_robots(sitemaps: [])
      # outbound_map returns 404 for anything unmapped, so the default answers 404 here.
      result = discover(ctx, outbound_map({}))
      expect(result.state).to eq("absent")
      expect(result.reason_code).to eq("sitemap_absent")
      expect(result.reduces_coverage?).to be(false)
      expect(gate_row(ctx[:crawl_id])["sitemap_state"]).to eq("absent")
    end

    it "records UNAVAILABLE when robots declares none but the DEFAULT answers non-404/410" do
      # :450 requires BOTH limbs for `absent`: "robots declares no sitemap AND the default sitemap
      # returns 404 or 410". A default answering 500 is an unavailable host, not an absent one, and
      # the difference is whether that Source root's coverage is reduced.
      ctx = with_robots(sitemaps: [])
      result = discover(ctx, outbound_map("https://shop.acme.example/sitemap.xml" => { status: 503 }))
      expect(result.state).to eq("unavailable")
      expect(result.reduces_coverage?).to be(true)
    end

    it "RETRIES a transient failure before recording unavailable (:450 'after retries')" do
      # Recording a host unavailable on one 503 would reduce its coverage on a transient failure.
      ctx = with_robots(sitemaps: ["https://shop.acme.example/s.xml"])
      attempts = 0
      flaky = Object.new.tap do |o|
        o.define_singleton_method(:fetch) do |url, **_k|
          body = ""
          status = 500
          if url.end_with?("/s.xml")
            attempts += 1
            if attempts >= 2
              status = 200
              body = %(<?xml version="1.0"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">) +
                     "<url><loc>https://shop.acme.example/p</loc></url></urlset>"
            end
          else
            status = 404
          end
          Platform::Outbound::Outcome.response(status:, headers: { "content-type" => "application/xml" },
                                               body:, byte_count: body.bytesize, truncated: false,
                                               canonical_host: "shop.acme.example", port: 443,
                                               pinned_address: "198.51.100.7", final_url: url,
                                               redirect_count: 0, latency_ms: 1)
        end
      end
      result = Workflows::Wf005::DiscoverSitemaps.new(outbound: flaky, pacer: pacer_for(ctx)).call(
        organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id], canonical_host: ctx[:host],
        source_id: ctx[:source_id], project_id: ctx[:g][:project_id], now: start_now)
      expect(attempts).to be >= 2
      expect(result.state).to eq("succeeded")
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
  # ---- the ratified per-fetch bounds, asserted on the REQUEST ------------------
  #
  # :450 requires a sitemap to "pass Source Scope, destination safety, robots, redirect, request,
  # retry and 10 MiB received-body limits". Four of those are request PARAMETERS, and the outbound
  # stub used to discard its keyword arguments — so every one of them could have been deleted or
  # transposed with the suite still green.
  describe "every sitemap fetch carries the ratified bounds (:437/:450)" do
    it "sends the hard request timeout, the 10 MiB byte cap, the redirect budget and the agent token" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/s.xml"])
      discover(ctx, outbound_map("https://shop.acme.example/s.xml" => { body: urlset("https://shop.acme.example/p") }))

      sitemap_request = requests.find { |r| r[:url] == "https://shop.acme.example/s.xml" }
      expect(sitemap_request).not_to be_nil
      expect(sitemap_request[:timeout_s]).to eq(Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING
                                                  .fetch("request_timeout_seconds").fetch("hard"))
      expect(sitemap_request[:byte_cap]).to eq(10 * 1024 * 1024)
      expect(sitemap_request[:max_redirects]).to eq(Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING
                                                      .fetch("redirects_per_url").fetch("hard"))
      expect(sitemap_request[:user_agent]).to eq("F1DiscoverabilityBot")
    end

    it "treats a body stopped AT the cap as a LIMIT, not as malformed XML" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/big.xml"])
      result = discover(ctx, outbound_map("https://shop.acme.example/big.xml" =>
                                            { body: urlset("https://shop.acme.example/p"), truncated: true }))
      expect(result.skipped.map { |x| x["reason"] }).to include("sitemap_xml_limit")
      expect(result.limit_reached?).to be(true)
    end

    it "refuses a sitemap served without a media type (the allowlist fails CLOSED)" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/s.xml"])
      result = discover(ctx, outbound_map("https://shop.acme.example/s.xml" =>
                                            { body: urlset("https://shop.acme.example/p"), type: nil }))
      expect(result.state).to eq("unavailable")
      expect(result.skipped.map { |x| x["reason"] }).to include("sitemap_unsupported_media_type")
      expect(frontier_entries(ctx[:crawl_id]).select { |e| e["origin"] == "sitemap" }).to be_empty
    end
  end

  # ---- pacing is a DELAY, never a candidate failure (:442) ---------------------
  describe "a host declaring a long Crawl-delay is paced, not dropped" do
    it "waits the interval the HOST asked for rather than a fixed constant" do
      # :448 — "a positive robots crawl-delay makes the request rate more restrictive than policy".
      # Ten seconds is far longer than the old 250 ms retry constant, which is what silently turned
      # a paced candidate into `sitemap_unavailable` for a perfectly reachable host.
      ctx = with_robots(sitemaps: ["https://shop.acme.example/a.xml", "https://shop.acme.example/b.xml"],
                        crawl_delay: 10)
      result = discover(ctx, outbound_map(
        "https://shop.acme.example/a.xml" => { body: urlset("https://shop.acme.example/p1") },
        "https://shop.acme.example/b.xml" => { body: urlset("https://shop.acme.example/p2") }))

      expect(result.state).to eq("succeeded")
      expect(result.documents_fetched).to eq(2)
      # The wait actually taken is the gate's remaining interval, which for a 10 s crawl-delay is
      # seconds — not the refusal constant.
      expect(paces.max).to be > Workflows::Wf005::HostGate::REFUSAL_RETRY_MS
      expect(result.skipped.map { |x| x["reason"] }).not_to include("sitemap_gate_deferred")
    end
  end

  # ---- the 50-document bound is PER RUN and counts ATTEMPTS (:437) -------------
  describe "the sitemap-document ceiling" do
    it "applies :454 SELECTION to index children — the lowest by the tuple, not the first named" do
      # Retention was applied to the declared set only; index children were appended unbounded, so
      # WHICH children got fetched was decided by the attacker's document order rather than by :454.
      # The index names its children in DESCENDING order, so document order and canonical order
      # disagree on every element — if selection were by arrival, the highest URLs would be fetched.
      children = (1..120).map { |i| format("https://shop.acme.example/c%03d.xml", i) }
      ctx = with_robots(sitemaps: ["https://shop.acme.example/i.xml"])
      map = { "https://shop.acme.example/i.xml" => { body: sitemapindex(*children.reverse) } }
      children.each { |c| map[c] = { status: 404 } }

      result = discover(ctx, outbound_map(map))
      fetched = requests.map { |r| r[:url] }.select { |u| u.include?("/c") }.sort

      # One slot of the run budget went to the index itself, so the children take the rest — and
      # they are the LOWEST by canonical URL bytes, whatever order the document named them in.
      expect(fetched).to eq(children.first(fetched.size))
      expect(fetched.size).to be < children.size
      expect(result.limit_reasons).to include("sitemap_documents_limit")
      # The candidates that lost the selection are recorded, not silently dropped (:450).
      expect(result.skipped.map { |x| x["url"] }).to include(children.last)
    end

    it "spends ONE run-wide budget across hosts, not fifty per host" do
      # :437's unit is "distinct canonical sitemap URLs" per RUN. A per-host counter let a Crawl with
      # ten Sources on ten hosts fetch ten times the ratified maximum.
      ctx = with_robots(sitemaps: (1..60).map { |i| format("https://shop.acme.example/s%03d.xml", i) })
      map = {}
      (1..60).each { |i| map[format("https://shop.acme.example/s%03d.xml", i)] = { status: 404 } }
      discover(ctx, outbound_map(map))

      spent = DbInspector.all("SELECT limit_counters FROM crawls WHERE id=$1::uuid", [ctx[:crawl_id]])
                         .first["limit_counters"]
      expect(JSON.parse(spent)["sitemap_documents"])
        .to eq(Workflows::Wf005::SitemapCandidates::DOCUMENT_LIMIT)
    end
  end

  # ---- one worker owns one discovery (MTX-030 concurrency) ---------------------
  describe "concurrent discovery of the same host" do
    it "lets only the CLAIM HOLDER traverse, and only the claim holder terminalize" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/s.xml"])
      map = { "https://shop.acme.example/s.xml" => { body: urlset("https://shop.acme.example/p") } }

      first = discover(ctx, outbound_map(map))
      expect(first.state).to eq("succeeded")

      # A second worker arriving after the decision reads it back rather than re-deciding: the
      # terminal record is write-once, and re-running the traversal would double the request volume
      # against the host the whole subsystem exists to pace.
      before = requests.size
      second = discover(ctx, outbound_map(map))
      expect(second.state).to eq("succeeded")
      expect(requests.size).to eq(before)
      expect(second.retained).to eq(first.retained)
    end

    it "stands a losing worker down instead of running the traversal twice" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/s.xml"])
      # Simulate a live attempt owned by another worker.
      DbInspector.connection.exec_params(
        "UPDATE crawl_host_gates SET sitemap_state='in_progress', sitemap_claim_token=gen_random_uuid(),
           sitemap_attempt_started_at=clock_timestamp(), state_version = state_version + 1
         WHERE crawl_id=$1::uuid", [ctx[:crawl_id]])

      result = discover(ctx, outbound_map("https://shop.acme.example/s.xml" => { body: urlset("https://shop.acme.example/p") }))
      expect(result.state).to eq("pending")
      expect(result.reason_code).to eq("sitemap_discovery_contended")
      expect(requests.select { |r| r[:url].end_with?("s.xml") }).to be_empty
    end
  end

  # ---- every skip is RECORDED with its reason (:450) ---------------------------
  describe "skipped and failed candidates are recorded, not silently dropped" do
    it "records each :450 reason on the gate, separating the LIMIT subset" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/evil.xml",
                                   "https://shop.acme.example/dead.xml",
                                   "https://shop.acme.example/ok.xml"])
      evil = %(<?xml version="1.0"?><!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]><urlset/>)
      result = discover(ctx, outbound_map(
        "https://shop.acme.example/evil.xml" => { body: evil },
        "https://shop.acme.example/dead.xml" => { status: 404 },
        "https://shop.acme.example/ok.xml" => { body: urlset("https://shop.acme.example/p") }))

      expect(result.state).to eq("succeeded")
      reasons = result.skipped.map { |x| x["reason"] }
      expect(reasons).to include("sitemap_xml_unsafe")
      expect(reasons).to include("sitemap_fetch_failed")
      # A non-limit failure alongside a success is telemetry only (:450).
      expect(result.limit_reached?).to be(false)

      row = gate_row(ctx[:crawl_id])
      expect(JSON.parse(row["sitemap_skipped"]).map { |x| x["reason"] }).to include("sitemap_xml_unsafe")
      expect(JSON.parse(row["sitemap_limit_reasons"])).to be_empty
    end

    it "keeps the terminal decision write-once, including its OBSERVED values" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/s.xml"])
      discover(ctx, outbound_map("https://shop.acme.example/s.xml" => { body: urlset("https://shop.acme.example/p") }))

      # `sitemap_documents_fetched` and `sitemap_max_index_depth` ARE the observed values :442
      # requires a limit decision to record, and they were rewritable after terminalisation.
      expect do
        DbInspector.connection.exec_params(
          "UPDATE crawl_host_gates SET sitemap_documents_fetched = 999, state_version = state_version + 1
           WHERE crawl_id=$1::uuid", [ctx[:crawl_id]])
      end.to raise_error(/sitemap_decision_frozen/)
    end
  end

end
