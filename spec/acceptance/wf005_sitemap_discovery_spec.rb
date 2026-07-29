# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

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

  include Wf005CrawlChain

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



  def discover(ctx, outbound)
    Workflows::Wf005::DiscoverSitemaps.new(outbound:, pacer: pacer_for(ctx)).call(
      organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id],
      canonical_host: ctx[:host], source_id: ctx[:source_id], now: start_now)
  end

  def frontier_entries(cid) = DbInspector.all("SELECT * FROM crawl_frontier_entries WHERE crawl_id=$1::uuid ORDER BY dequeue_key", [cid])
  def occurrences(cid) = DbInspector.all("SELECT * FROM crawl_frontier_occurrences WHERE crawl_id=$1::uuid ORDER BY occurrence_order", [cid])

  # Activate a Project policy narrowing the run-wide sitemap-document bound. `crawl_policies` rows
  # are immutable, so a narrower policy is ACTIVATED rather than edited, and :390 resolves it at
  # execution time — which is why this works on an already-running Crawl.
  def narrow_documents(ctx, hard)
    bounds = JSON.parse(JSON.generate(Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING))
                 .merge("sitemap_documents" => { "soft" => hard, "hard" => hard })
    DbInspector.connection.exec_params(
      "INSERT INTO crawl_policies (id, state_version, created_at, updated_at, correlation_id,
         schema_version, organization_id, project_id, scope, policy_version, state,
         normalized_bounds, content_sha256, activated_by_account_id)
       VALUES (gen_random_uuid(), 0, now(), now(), gen_random_uuid(), 'crawl-policy-v1', $1::uuid, $2::uuid,
               'project', 'crawl-policy-v1-docs', 'active', $3::jsonb,
               sha256(convert_to($3::text, 'UTF8')), $4::uuid)",
      [ctx[:g][:organization_id], ctx[:g][:project_id], JSON.generate(bounds), ctx[:g][:account_id]])
  end

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
        source_id: ctx[:source_id], now: start_now)
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

  # ---- FU-9: sustained contention is not an outcome ----------------------------
  #
  # ADR-081's open follow-up, closed here. A host under sustained contention could exhaust the
  # traversal's deferral budget and then be terminalized `sitemap_unavailable` — WRITE-ONCE,
  # coverage permanently partial — having made zero network attempts. S-07-006 mitigated the trigger
  # but left the failure mode reachable; S-07-008 owns run scheduling and owes the re-entry.
  describe "a host the rate limiter never released" do
    # Hold every concurrency slot with live leases, so the gate refuses every start for the whole
    # traversal. A no-op pacer means no simulated time passes, so the refusal never clears — which
    # is exactly the sustained-contention shape, produced by the gate's own predicates rather than
    # by a stub.
    def contended(ctx)
      # :438's nonexceedable per-host concurrency ceiling, all of it held.
      seed_leases(gate_row(ctx[:crawl_id])["id"],
                  Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING.fetch("concurrency_per_host").fetch("hard"))
      Workflows::Wf005::DiscoverSitemaps.new(outbound: outbound_map(
        "https://shop.acme.example/a.xml" => { body: urlset("https://shop.acme.example/p1") }
      ), pacer: ->(_ms) {}).call(
        organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id],
        canonical_host: ctx[:host], source_id: ctx[:source_id], now: start_now)
    end

    it "does NOT record `sitemap_unavailable` for a host it never reached" do
      # ":450 — if a declared sitemap exists ... and no sitemap candidate succeeds AFTER
      # RETRIES/VALIDATION, record `sitemap_unavailable`." A candidate the rate limiter never
      # released has had neither, so the premise of that sentence is unmet.
      ctx = with_robots(sitemaps: ["https://shop.acme.example/a.xml"])
      result = contended(ctx)

      expect(result.state).to eq("pending")
      expect(result.reason_code).to eq(Workflows::Wf005::DiscoverSitemaps::CONTENDED)
      expect(result.rescheduled?).to be(true)
      expect(gate_row(ctx[:crawl_id])["sitemap_outcome_reason"]).to be_nil
    end

    it "hands the claim BACK, so the gate is exactly as claimable as before" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/a.xml"])
      contended(ctx)

      gate = gate_row(ctx[:crawl_id])
      expect(gate["sitemap_state"]).to eq("pending")
      expect(gate["sitemap_claim_token"]).to be_nil
      expect(gate["sitemap_terminal_at"]).to be_nil
    end

    it "rolls back its limit decisions when the terminal claim was taken over" do
      # The atomicity regression this tranche introduced: the zero-row guard sat OUTSIDE the unit of
      # work, so a worker whose claim had been stolen still committed an immutable, once-per-run
      # `CrawlLimitReached` for a traversal whose outcome was discarded — and the legitimate worker
      # then collided and emitted nothing. Simulated by rotating the claim token underneath a
      # traversal that has a limit to report.
      ctx = with_robots(sitemaps: %w[https://shop.acme.example/a.xml https://shop.acme.example/b.xml])
      narrow_documents(ctx, 1)

      service = Workflows::Wf005::DiscoverSitemaps.new(
        outbound: outbound_map("https://shop.acme.example/a.xml" => { body: urlset("https://shop.acme.example/p1") }),
        pacer: pacer_for(ctx))
      # Steal the claim at the moment the traversal finishes, before it terminalizes. `bounded` is
      # called once by `begin_discovery` and once by `terminalize`; the second is the one that runs
      # after the traversal, which is exactly where a stale-attempt takeover would land.
      calls = 0
      service.define_singleton_method(:bounded) do |entries, key|
        calls += 1
        if calls == 2
          DbInspector.connection.exec_params(
            "UPDATE crawl_host_gates SET sitemap_claim_token = gen_random_uuid(),
               state_version = state_version + 1 WHERE crawl_id = $1::uuid", [ctx[:crawl_id]])
        end
        super(entries, key)
      end

      expect do
        service.call(organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id],
                     canonical_host: ctx[:host], source_id: ctx[:source_id], now: start_now)
      end.to raise_error(Platform::InvariantViolation, /sitemap terminal decision lost/)

      # Neither the outcome nor the decisions it would have explained survived. The SOFT crossing
      # written by the reservation earlier is deliberately not asserted away: it belongs to a
      # different transaction, one whose effect (a document genuinely charged and fetched) did
      # commit. Only the terminalize-time decisions roll back with the terminalize.
      expect(gate_row(ctx[:crawl_id])["sitemap_terminal_at"]).to be_nil
      expect(DbInspector.all(
        "SELECT id FROM crawl_limit_decisions WHERE crawl_id=$1::uuid AND threshold_kind='hard'",
        [ctx[:crawl_id]])).to be_empty
      expect(DbInspector.all(
        "SELECT id FROM event_registry WHERE aggregate_id=$1::uuid AND event_type='CrawlLimitReached'",
        [ctx[:crawl_id]])).to be_empty
    end

    def documents_spent(ctx)
      DbInspector.one("SELECT sitemap_documents FROM crawl_budget_counters WHERE crawl_id=$1::uuid",
                      [ctx[:crawl_id]])&.fetch("sitemap_documents").to_i
    end

    it "spends NO run-wide document budget on a pass that made no network attempt" do
      # The defect the concurrency, security and architecture lenses each reached independently. The
      # budget was charged in the traversal loop, BEFORE the gate was consulted, and
      # `reserve_sitemap_document` only ever increments — so a paced candidate cost the run a
      # document it never fetched, and nothing gave it back.
      ctx = with_robots(sitemaps: ["https://shop.acme.example/a.xml"])
      contended(ctx)

      expect(documents_spent(ctx)).to eq(0)
    end

    it "survives REPEATED re-entry — the budget is not monotonically consumed by pacing" do
      # Bounding this by the budget rather than by the clock is what made the old code converge on
      # `sitemap_unavailable` with zero attempts: pass k found every reservation refused, recorded
      # `sitemap_documents_limit` instead of a deferral, and terminalized. Thirty passes here is far
      # past the 50-document run-wide ceiling under the old arithmetic.
      ctx = with_robots(sitemaps: ["https://shop.acme.example/a.xml"])
      30.times { contended(ctx) }

      expect(documents_spent(ctx)).to eq(0)
      gate = gate_row(ctx[:crawl_id])
      expect(gate["sitemap_state"]).to eq("pending")
      expect(gate["sitemap_outcome_reason"]).to be_nil
      # And no limit decision was invented for a host nothing was ever requested from.
      expect(DbInspector.all("SELECT limit_dimension FROM crawl_limit_decisions WHERE crawl_id=$1::uuid",
                             [ctx[:crawl_id]])).to be_empty
    end

    it "charges ONE document per distinct URL however many times :444 retries it" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/a.xml"])
      # Two transient failures then a success: three attempts, one distinct URL.
      attempts = 0
      flaky = Object.new
      flaky.define_singleton_method(:fetch) do |url, **_k|
        next Platform::Outbound::Outcome.response(
          status: 404, headers: {}, body: "", byte_count: 0, truncated: false,
          canonical_host: "shop.acme.example", port: 443, pinned_address: "198.51.100.7",
          final_url: url, redirect_count: 0, latency_ms: 1) unless url.end_with?("a.xml")

        attempts += 1
        next Platform::Outbound::Outcome.timeout(canonical_host: "shop.acme.example") if attempts < 3

        Platform::Outbound::Outcome.response(
          status: 200, headers: { "content-type" => "application/xml" },
          body: urlset("https://shop.acme.example/p1"),
          byte_count: urlset("https://shop.acme.example/p1").bytesize, truncated: false,
          canonical_host: "shop.acme.example", port: 443, pinned_address: "198.51.100.7",
          final_url: url, redirect_count: 0, latency_ms: 1)
      end

      Workflows::Wf005::DiscoverSitemaps.new(outbound: flaky, pacer: pacer_for(ctx)).call(
        organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id],
        canonical_host: ctx[:host], source_id: ctx[:source_id], now: start_now)

      expect(attempts).to eq(3)
      # `a.xml` once; the default `/sitemap.xml` once. Not five.
      expect(documents_spent(ctx)).to eq(2)
    end

    # ---- the MIXED case: one candidate reaches the network and fails, another is paced ----------
    #
    # Four of the five delta lenses found that the in-memory `@charged` memo could only mean "once
    # per traversal". A `Traversal` is rebuilt on every `call`, so a candidate that reached the
    # network and FAILED was re-charged on every re-entry — and the pure-contention fixture above
    # cannot see it, because there nothing is ever charged at all.
    def attempt_pass(ctx)
      Workflows::Wf005::DiscoverSitemaps.new(outbound: outbound_map(
        "https://shop.acme.example/a.xml" => { status: 404 }
      ), pacer: ->(_ms) {}).call(
        organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id],
        canonical_host: ctx[:host], source_id: ctx[:source_id], now: start_now)
    end

    # THE MIXED CASE, produced by the gate's own predicates and deterministic without any seeded
    # state. With a no-op pacer no simulated time passes, so :442's 1-start-per-rolling-second rate
    # limit refuses every candidate after the first: `a.xml` is claimed and 404s (charged, and
    # `@succeeded` stays false because a 404 parses nothing), the default `/sitemap.xml` is deferred
    # 20 times, `gate_deferred?` is true, and FU-9 hands the claim back. Nothing terminalizes — the
    # gate guard rightly forbids un-terminalizing, so a rescheduled pass is the ONLY way a run
    # re-enters, and it is exactly the path that used to re-charge.

    def ensure_counter_row(ctx)
      Platform::UnitOfWork.run do |conn|
        store = IdentityAccess::Infrastructure::CrawlBudgetStore.new(conn.raw_connection)
        store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
        store.ensure_counters(id: Platform::Ids.system.generate, now: start_now,
                              correlation_id: SecureRandom.uuid_v7,
                              organization_id: ctx[:g][:organization_id],
                              project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id])
      end
    end

    def charges(ctx) = DbInspector.all(
      "SELECT canonical_url FROM crawl_sitemap_document_charges WHERE crawl_id=$1::uuid", [ctx[:crawl_id]]
    ).map { |r| r["canonical_url"] }

    it "charges a URL that REACHED THE NETWORK exactly once, however many passes re-enter" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/a.xml"])
      expect(attempt_pass(ctx).rescheduled?).to be(true)
      first = charges(ctx).sort
      expect(first).not_to be_empty                      # something genuinely reached the network

      # The rolling rate window is cleared between passes so `a.xml` is genuinely RE-ATTEMPTED each
      # time — otherwise every later pass defers before reaching the charge and the test proves
      # nothing. This is what makes it a re-charge test rather than a no-op test.
      20.times do
        clear_rate_window(gate_row(ctx[:crawl_id])["id"])
        expect(attempt_pass(ctx).rescheduled?).to be(true)
      end

      # The ledger is unchanged: the same distinct URLs, charged once each.
      expect(charges(ctx).sort).to eq(first)
      expect(documents_spent(ctx)).to eq(first.size)
      expect(gate_row(ctx[:crawl_id])["sitemap_state"]).to eq("pending")
      # And no limit was invented for a run that attempted one distinct URL against a bound of 50.
      expect(DbInspector.all("SELECT limit_dimension FROM crawl_limit_decisions WHERE crawl_id=$1::uuid",
                             [ctx[:crawl_id]])).to be_empty
    end

    # Six independent logins, so the transactions genuinely overlap rather than queueing behind the
    # five-slot pool. `gate` is an optional controller connection already holding the counter row:
    # every worker then piles up behind it and is RELEASED TOGETHER, so the overlap is observed
    # rather than hoped for. Six threads left to their own devices did not overlap at all — the
    # first version of this test passed with the row lock removed.
    def charging_threads(ctx, urls, ceiling:)
      cfg = ActiveRecord::Base.connection_db_config.configuration_hash
      urls.map do |url|
        Thread.new do
          conn = PG.connect(host: cfg[:host], port: cfg[:port], dbname: cfg[:database],
                            user: cfg[:username], password: cfg[:password].presence)
          begin
            conn.exec("BEGIN")
            store = IdentityAccess::Infrastructure::CrawlBudgetStore.new(conn)
            store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
            store.ensure_counters(id: Platform::Ids.system.generate, now: start_now,
                                  correlation_id: SecureRandom.uuid_v7,
                                  organization_id: ctx[:g][:organization_id],
                                  project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id])
            r = store.charge_sitemap_document(
              organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
              crawl_id: ctx[:crawl_id], canonical_url: url, ceiling:,
              id: Platform::Ids.system.generate, correlation_id: SecureRandom.uuid_v7, now: start_now)
            conn.exec("COMMIT")
            r
          rescue StandardError => e
            e
          ensure
            conn.close
          end
        end
      end.map(&:value)
    end


    it "never charges past the ceiling when workers race on DIFFERENT urls" do
      # What the `FOR UPDATE` on the counter row is for. The unique index adjudicates IDENTITY (one
      # charge per URL); it says nothing about the BOUND, because two workers charging two different
      # URLs conflict on nothing. Without the row lock both read `sitemap_documents = 0`, both pass
      # `< 1`, and the run fetches two documents against a ceiling of one.
      ctx = with_robots(sitemaps: ["https://shop.acme.example/a.xml"])
      urls = Array.new(6) { |i| "https://shop.acme.example/s#{i}.xml" }

      outcomes = charging_threads(ctx, urls, ceiling: 1)

      expect(outcomes.count(:granted)).to eq(1)
      expect(outcomes.count(:exhausted)).to eq(5)
      expect(charges(ctx).size).to eq(1)
      expect(documents_spent(ctx)).to eq(1)
    end

    it "cannot be charged twice for one URL by two workers at once" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/a.xml"])
      url = "https://shop.acme.example/a.xml"
      ensure_counter_row(ctx)

      outcomes = charging_threads(ctx, [url] * 6, ceiling: 50)

      # Exactly one paid; the rest found it already paid for, and none raised.
      #
      # HONEST LIMIT OF THIS TEST: six threads on six connections did not reliably overlap here, so
      # what is proved is the OUTCOME, not the interleaving. The `UNIQUE (crawl_id,
      # canonical_url_sha256)` in the migration is what makes a second charge impossible under any
      # interleaving, and `spec/persistence` asserts that constraint directly. The counter-row
      # `FOR UPDATE` additionally makes a concurrent same-URL charge resolve to `:already` rather
      # than to a unique violation — that is a real property and it is NOT proved here.
      expect(outcomes.grep(StandardError)).to be_empty
      expect(outcomes.count(:granted)).to eq(1)
      expect(outcomes.count(:already)).to eq(5)
      expect(charges(ctx)).to eq([url])
      expect(documents_spent(ctx)).to eq(1)
    end

    it "RE-ENTERS and succeeds once the contention clears" do
      # The property that makes this a re-entry rather than a retry loop: a later pass, with no
      # special knowledge that an earlier one was deferred, claims the gate exactly as the first did.
      ctx = with_robots(sitemaps: ["https://shop.acme.example/a.xml"])
      contended(ctx)

      seed_leases(gate_row(ctx[:crawl_id])["id"], 0)
      clear_rate_window(gate_row(ctx[:crawl_id])["id"])
      result = discover(ctx, outbound_map(
        "https://shop.acme.example/a.xml" => { body: urlset("https://shop.acme.example/p1") }))

      expect(result.state).to eq("succeeded")
      expect(result.documents_fetched).to eq(1)
      expect(frontier_entries(ctx[:crawl_id]).map { |e| e["canonical_url"] })
        .to include("https://shop.acme.example/p1")
    end

    it "TERMINALIZES honestly once the run's wall clock has passed" do
      # The bound on re-entry is the run's own deadline (:442 — "at 60 elapsed minutes, no new
      # request starts"). Past it no candidate can ever be attempted, so the coverage reduction is
      # true rather than premature — and the run already carries a `wall_clock_run_duration`
      # decision explaining it. Without this limb the release would be unbounded.
      ctx = with_robots(sitemaps: ["https://shop.acme.example/a.xml"])
      DbInspector.connection.exec_params(
        "UPDATE crawls SET deadline_at = $2::timestamptz, state_version = state_version + 1
         WHERE id = $1::uuid", [ctx[:crawl_id], start_now - 1])

      result = contended(ctx)

      expect(result.state).to eq("unavailable")
      expect(gate_row(ctx[:crawl_id])["sitemap_state"]).to eq("unavailable")
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

      # The counter's one home is `crawl_budget_counters` (schema :298). This assertion used to read
      # `crawls.limit_counters`, which is where S-07-006 had to put it before that table existed —
      # and asserting the old location is what let S-07-007 create a SECOND home without any test
      # noticing.
      spent = DbInspector.one("SELECT sitemap_documents FROM crawl_budget_counters WHERE crawl_id=$1::uuid",
                              [ctx[:crawl_id]])
      expect(spent["sitemap_documents"].to_i)
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
