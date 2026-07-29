# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# Where each ratified limit dimension is OBSERVED (S-07-008; WORKFLOW_SPECIFICATIONS.md :425-438,
# :442, :456).
#
# `wf005_limit_decisions_spec.rb` proves the emission mechanism. This proves the WIRING: that each
# dimension is watched at the place the bound is actually enforced, and that the number recorded is
# the resolved bound rather than the frozen global constant. Every bound here is narrowed by an
# active Project policy, because a test that only ever sees the global ceiling cannot tell the two
# apart — and telling them apart is the whole point of :390.
RSpec.describe "WF-005 limit observation points", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-E2E TYP-DATA TYP-OBS] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def decisions(cid) = DbInspector.all(
    "SELECT * FROM crawl_limit_decisions WHERE crawl_id=$1::uuid ORDER BY limit_dimension, threshold_kind", [cid]
  )

  def counters(cid) = DbInspector.one("SELECT * FROM crawl_budget_counters WHERE crawl_id=$1::uuid", [cid])

  def decision(cid, dimension, threshold)
    decisions(cid).find { |d| d["limit_dimension"] == dimension && d["threshold_kind"] == threshold }
  end

  def limit_events(cid) = DbInspector.all(
    "SELECT event_type FROM event_registry WHERE aggregate_id=$1::uuid
       AND event_type IN ('CrawlSoftLimitApproaching','CrawlLimitReached')", [cid]
  ).map { |r| r["event_type"] }

  # `crawl_policies` rows are immutable, so a narrower policy is ACTIVATED rather than edited. The
  # execution path resolves policies at fetch time (:390), so activating one on a RUNNING Crawl is
  # the ratified behaviour — "a new restriction affects queued work immediately and running work at
  # the next checkpoint" — not a test convenience.
  def narrow(ctx, **dimensions)
    bounds = JSON.parse(JSON.generate(Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING)).merge(dimensions)
    DbInspector.connection.exec_params(
      "INSERT INTO crawl_policies (id, state_version, created_at, updated_at, correlation_id,
         schema_version, organization_id, project_id, scope, policy_version, state,
         normalized_bounds, content_sha256, activated_by_account_id)
       VALUES (gen_random_uuid(), 0, now(), now(), gen_random_uuid(), 'crawl-policy-v1', $1::uuid, $2::uuid,
               'project', 'crawl-policy-v1-narrowed', 'active', $3::jsonb,
               sha256(convert_to($3::text, 'UTF8')), $4::uuid)",
      [ctx[:g][:organization_id], ctx[:g][:project_id], JSON.generate(bounds), ctx[:g][:account_id]])
  end

  # ---- the frontier's two dimensions -------------------------------------------

  def offer(ctx, url:, depth:)
    Platform::UnitOfWork.run do |conn|
      raw = conn.raw_connection
      store = IdentityAccess::Infrastructure::CrawlFrontierStore.new(raw)
      store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
      # Through the gate store, which is where the production frontier callers resolve it too —
      # `CrawlFrontierStore` does not read policies and no longer pretends to.
      limits = Workflows::Wf005::EffectiveLimits.resolve(
        IdentityAccess::Infrastructure::CrawlHostGateStore.new(raw)
          .active_crawl_policies(ctx[:g][:organization_id], ctx[:g][:project_id])
      )
      observer = Workflows::Wf005::LimitDecisions.new.for(
        raw, organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
        crawl_id: ctx[:crawl_id], limits:
      )
      root = DbInspector.one("SELECT * FROM crawl_frontier_entries WHERE crawl_id=$1::uuid LIMIT 1",
                             [ctx[:crawl_id]])
      Workflows::Wf005::Frontier.new(store, ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
                                .offer(organization_id: ctx[:g][:organization_id],
                                       project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id],
                                       source_id: ctx[:source_id], canonical_url: url, origin: "link",
                                       depth:, now: start_now, observer:,
                                       scope_policy_id: root["scope_policy_id"],
                                       scope_policy_version: root["scope_policy_version"])
    end
  end

  describe "crawl depth from Source root (:438)" do
    it "discards a candidate past the RESOLVED depth bound and records the limit" do
      ctx = running_crawl
      narrow(ctx, "crawl_depth" => { "soft" => 1, "hard" => 2 })

      result = offer(ctx, url: "https://shop.acme.example/deep", depth: 3)

      expect(result.discarded?).to be(true)
      expect(result.reason).to eq("depth_limit_discarded")
      row = decision(ctx[:crawl_id], "crawl_depth_from_source_root", "hard")
      expect(row).not_to be_nil
      # The CONFIGURED value is the Project's 2, not the global ceiling's 10. If this reads 10 the
      # decision is describing a bound that was never applied.
      expect(row["configured_value"].to_i).to eq(2)
      expect(row["observed_value"].to_i).to eq(3)
      expect(limit_events(ctx[:crawl_id])).to include("CrawlLimitReached")
    end

    it "keeps the discarded candidate as a ROW, so coverage can still account for it (:452)" do
      ctx = running_crawl
      narrow(ctx, "crawl_depth" => { "soft" => 1, "hard" => 2 })
      offer(ctx, url: "https://shop.acme.example/deep", depth: 3)

      entry = DbInspector.one(
        "SELECT * FROM crawl_frontier_entries WHERE crawl_id=$1::uuid AND canonical_url=$2",
        [ctx[:crawl_id], "https://shop.acme.example/deep"])
      expect(entry).not_to be_nil
      expect(entry["state"]).to eq("discarded")
    end

    it "admits a candidate AT the bound — limits are inclusive maxima (:442)" do
      ctx = running_crawl
      narrow(ctx, "crawl_depth" => { "soft" => 1, "hard" => 2 })

      expect(offer(ctx, url: "https://shop.acme.example/at", depth: 2).admitted?).to be(true)
      expect(decision(ctx[:crawl_id], "crawl_depth_from_source_root", "hard")).to be_nil
    end

    it "records the SOFT crossing at the depth soft bound, which had no limb at all" do
      ctx = running_crawl
      narrow(ctx, "crawl_depth" => { "soft" => 2, "hard" => 4 })

      expect(offer(ctx, url: "https://shop.acme.example/mid", depth: 2).admitted?).to be(true)
      row = decision(ctx[:crawl_id], "crawl_depth_from_source_root", "soft")
      expect(row).not_to be_nil
      expect(row["configured_value"].to_i).to eq(2)
      expect(row["observed_value"].to_i).to eq(2)
      expect(limit_events(ctx[:crawl_id])).to include("CrawlSoftLimitApproaching")
    end
  end

  describe "the discovered URL queue (:438)" do
    it "records the SOFT crossing when the retained count first reaches the soft bound" do
      ctx = running_crawl                                   # one seeded root is already retained
      narrow(ctx, "discovered_queue" => { "soft" => 2, "hard" => 4 })

      offer(ctx, url: "https://shop.acme.example/a", depth: 1)

      row = decision(ctx[:crawl_id], "discovered_url_queue", "soft")
      expect(row).not_to be_nil
      expect(row["configured_value"].to_i).to eq(2)
      expect(row["observed_value"].to_i).to eq(2)
      expect(limit_events(ctx[:crawl_id])).to include("CrawlSoftLimitApproaching")
    end

    it "records the HARD limit when a candidate is discarded at the retention bound" do
      ctx = running_crawl
      narrow(ctx, "discovered_queue" => { "soft" => 2, "hard" => 2 })

      offer(ctx, url: "https://shop.acme.example/a", depth: 1)   # retained count reaches 2
      result = offer(ctx, url: "https://shop.acme.example/z", depth: 1)

      expect(result.discarded?).to be(true)
      expect(result.reason).to eq("queue_limit_discarded")
      row = decision(ctx[:crawl_id], "discovered_url_queue", "hard")
      expect(row).not_to be_nil
      expect(row["configured_value"].to_i).to eq(2)
      expect(row["observed_value"].to_i).to eq(2)
    end

    it "records the bound as OBSERVED on the EVICTION path too, not one below it" do
      # `admitted_count` excludes discarded rows, so re-reading it after the victim was evicted
      # returned `configured - 1` — telling a customer they hit a maximum of 2 at an observed 1,
      # permanently, since the decision is once-per-run. The lower-sorting newcomer takes the
      # eviction branch.
      ctx = running_crawl
      narrow(ctx, "discovered_queue" => { "soft" => 2, "hard" => 2 })
      offer(ctx, url: "https://shop.acme.example/zzz", depth: 1)

      result = offer(ctx, url: "https://shop.acme.example/aaa", depth: 1)

      expect(result.admitted?).to be(true)
      expect(result.evicted_entry_id).not_to be_nil
      row = decision(ctx[:crawl_id], "discovered_url_queue", "hard")
      expect(row["observed_value"].to_i).to eq(2)
      expect(row["configured_value"].to_i).to eq(2)
    end

    it "records it ONCE however many candidates are later discarded" do
      ctx = running_crawl
      narrow(ctx, "discovered_queue" => { "soft" => 2, "hard" => 2 })
      offer(ctx, url: "https://shop.acme.example/a", depth: 1)
      3.times { |i| offer(ctx, url: "https://shop.acme.example/z#{i}", depth: 1) }

      expect(decisions(ctx[:crawl_id]).count { |d| d["limit_dimension"] == "discovered_url_queue" &&
                                                   d["threshold_kind"] == "hard" }).to eq(1)
      expect(limit_events(ctx[:crawl_id]).count("CrawlLimitReached")).to eq(1)
    end

    it "still enforces the RETENTION BOUND for a candidate at or above the depth soft bound" do
      # The regression all five delta lenses found: the depth-soft observation was written as an
      # `elsif` in the disposition chain, so a candidate in [soft, hard] skipped the queue check
      # entirely — no eviction, no discard, no decision, permanently. An observation must never
      # consume a disposition branch. Mutation: make `observe_depth_soft` an `elsif` again and this
      # fails on every assertion below.
      ctx = running_crawl
      narrow(ctx, "crawl_depth" => { "soft" => 1, "hard" => 9 },
                  "discovered_queue" => { "soft" => 2, "hard" => 2 })

      # Depth 1 is at the soft bound AND the run is at its retention bound.
      offer(ctx, url: "https://shop.acme.example/a", depth: 1)
      result = offer(ctx, url: "https://shop.acme.example/z", depth: 1)

      # The soft depth observation still happens...
      expect(decision(ctx[:crawl_id], "crawl_depth_from_source_root", "soft")).not_to be_nil
      # ...and the retention bound is STILL enforced.
      expect(result.discarded?).to be(true)
      expect(result.reason).to eq("queue_limit_discarded")
      row = decision(ctx[:crawl_id], "discovered_url_queue", "hard")
      expect(row).not_to be_nil
      expect(row["configured_value"].to_i).to eq(2)
      expect(DbInspector.all(
        "SELECT id FROM crawl_frontier_entries WHERE crawl_id=$1::uuid AND state <> 'discarded'",
        [ctx[:crawl_id]]).size).to eq(2)
    end

    it "EVICTS at the retention bound even when the newcomer is at the depth soft bound" do
      ctx = running_crawl
      narrow(ctx, "crawl_depth" => { "soft" => 1, "hard" => 9 },
                  "discovered_queue" => { "soft" => 2, "hard" => 2 })
      offer(ctx, url: "https://shop.acme.example/zzz", depth: 1)

      result = offer(ctx, url: "https://shop.acme.example/aaa", depth: 1)

      expect(result.admitted?).to be(true)
      expect(result.evicted_entry_id).not_to be_nil
      expect(decision(ctx[:crawl_id], "discovered_url_queue", "hard")["observed_value"].to_i).to eq(2)
    end

    it "refuses ENTRY at the bound, so the queue reason wins over depth for a non-member" do
      # ONE POPULATION, ONE BOUND. The queue bound governs ENTRY; depth describes what kind of
      # MEMBER a candidate is. A candidate refused entry never becomes a member, so depth is not
      # consulted and the queue reason is the true one. The inverse precedence let an over-depth
      # candidate join a population it was exempt from and could never be evicted from.
      ctx = running_crawl
      narrow(ctx, "discovered_queue" => { "soft" => 1, "hard" => 1 }, "crawl_depth" => { "soft" => 1, "hard" => 2 })

      result = offer(ctx, url: "https://shop.acme.example/deep", depth: 5)

      expect(result.reason).to eq("queue_limit_discarded")
      expect(decision(ctx[:crawl_id], "discovered_url_queue", "hard")).not_to be_nil
      expect(decision(ctx[:crawl_id], "crawl_depth_from_source_root", "hard")).to be_nil
    end

    it "keeps the population BOUNDED under repeated depth-rejected candidates" do
      # The defect this definition exists to prevent: depth-rejected rows count toward the ceiling,
      # so if they were exempt from enforcement the run would sit N past its own inclusive maximum
      # with only the first crossing ever recorded. Ten of them, a ceiling of two.
      ctx = running_crawl                                    # one seeded root already a member
      narrow(ctx, "discovered_queue" => { "soft" => 2, "hard" => 2 }, "crawl_depth" => { "soft" => 1, "hard" => 2 })

      offer(ctx, url: "https://shop.acme.example/deep0", depth: 9)   # joins as a depth-rejected member
      10.times { |i| offer(ctx, url: "https://shop.acme.example/deep#{i + 1}", depth: 9) }

      population = DbInspector.all(
        "SELECT id FROM crawl_frontier_entries WHERE crawl_id=$1::uuid
           AND (state <> 'discarded' OR reason = 'depth_limit_discarded')", [ctx[:crawl_id]]).size
      expect(population).to eq(2)
      # And the run recorded that it reached its bound, exactly once.
      expect(DbInspector.all(
        "SELECT id FROM crawl_limit_decisions WHERE crawl_id=$1::uuid
           AND limit_dimension='discovered_url_queue' AND threshold_kind='hard'",
        [ctx[:crawl_id]]).size).to eq(1)
    end
  end

  # ---- the fetch's three dimensions ---------------------------------------------

  def content_response(body: "<html><body>ok</body></html>", status: 200, byte_count: nil,
                       truncated: false, redirect_count: 0)
    Platform::Outbound::Outcome.response(
      status:, headers: { "content-type" => "text/html; charset=utf-8" }, body:,
      byte_count: byte_count || body.bytesize, truncated:, canonical_host: "shop.acme.example",
      port: 443, pinned_address: "198.51.100.7", final_url: "https://shop.acme.example/",
      redirect_count:, latency_ms: 5)
  end

  def fetchable
    ctx = running_crawl
    ensure_gate(ctx)
    resolve_robots(ctx, outbound_returning(response(status: 200, body: "User-agent: *\nAllow: /\n")))
    ctx[:gate_id] = gate_row(ctx[:crawl_id])["id"]
    ctx
  end

  def admit_next(ctx)
    Workflows::Wf005::Admission.new.claim_next(
      organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id], now: start_now
    )
  end

  def fetch(ctx, outcome, admitted: false)
    outbound = Object.new.tap { |o| o.define_singleton_method(:fetch) { |*_a, **_k| outcome } }
    decision = admitted ? admit_next(ctx) : nil
    entry = decision&.entry || DbInspector.one(
      "SELECT * FROM crawl_frontier_entries WHERE crawl_id=$1::uuid ORDER BY dequeue_key LIMIT 1",
      [ctx[:crawl_id]]
    )
    Workflows::Wf005::FetchContent.new(outbound:, pacer: pacer_for(ctx)).call(
      organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id], entry:,
      gate_id: ctx[:gate_id], now: start_now, reserved_bytes: decision&.reserved_bytes)
  end

  describe "response body per URL (:438)" do
    it "records the HARD limit when a body overruns the RESOLVED per-URL maximum" do
      ctx = fetchable
      narrow(ctx, "per_url_body_mib" => { "soft" => 1, "hard" => 1 })
      cap = 1024 * 1024

      result = fetch(ctx, content_response(body: "x" * (cap + 1), truncated: true))

      expect(result.reason_code).to eq("response_body_limit_exceeded")
      row = decision(ctx[:crawl_id], "response_body_per_url", "hard")
      expect(row).not_to be_nil
      expect(row["configured_value"].to_i).to eq(cap)
      # The exact size is unknowable — the reader stopped one sentinel byte past the maximum and
      # never retained it — so what is recorded is what was genuinely observed.
      expect(row["observed_value"].to_i).to eq(cap + 1)
      # A per-URL bound costs exactly the URL that hit it.
      expect(row["affected_url_count"].to_i).to eq(1)
      expect(row["affected_source_count"].to_i).to eq(1)
    end

    it "records the hard limit under an admitted reservation without leaving that reservation behind" do
      ctx = fetchable
      narrow(ctx, "per_url_body_mib" => { "soft" => 1, "hard" => 1 })
      cap = 1024 * 1024

      result = fetch(ctx, content_response(body: "x" * (cap + 1), truncated: true), admitted: true)

      expect(result.reason_code).to eq("response_body_limit_exceeded")
      row = decision(ctx[:crawl_id], "response_body_per_url", "hard")
      expect(row).not_to be_nil
      expect(counters(ctx[:crawl_id])["committed_response_bytes"].to_i).to eq(cap)
      expect(counters(ctx[:crawl_id])["reserved_response_bytes"].to_i).to eq(cap)
    end

    it "records the SOFT crossing for a body at or past the soft bound" do
      ctx = fetchable
      narrow(ctx, "per_url_body_mib" => { "soft" => 1, "hard" => 2 })

      fetch(ctx, content_response(body: "x" * (1024 * 1024)))

      row = decision(ctx[:crawl_id], "response_body_per_url", "soft")
      expect(row).not_to be_nil
      expect(row["observed_value"].to_i).to eq(1024 * 1024)
    end

    it "records nothing for an ordinary small body" do
      ctx = fetchable
      fetch(ctx, content_response)
      expect(decisions(ctx[:crawl_id]).map { |d| d["limit_dimension"] })
        .not_to include("response_body_per_url")
    end
  end

  describe "connection plus response time per request (:438)" do
    it "records the HARD limit only once the retries are EXHAUSTED" do
      # :444 gives a timeout "one initial attempt plus at most two retries"; :452 makes only the
      # exhausted case `content_fetch_failed`. Firing per attempt meant the first transient timeout
      # in any run wrote a permanent `CrawlLimitReached`, so a run that retried once, succeeded and
      # evaluated every candidate was still labelled `limit_reached` by the terminal checkpoint.
      ctx = fetchable
      narrow(ctx, "request_timeout_seconds" => { "soft" => 2, "hard" => 3 })

      fetch(ctx, Platform::Outbound::Outcome.timeout(canonical_host: "shop.acme.example"))

      row = decision(ctx[:crawl_id], "connection_plus_response_time_per_request", "hard")
      expect(row).not_to be_nil
      expect(row["configured_value"].to_i).to eq(3)
      expect(row["observed_value"].to_i).to eq(3)
      expect(DbInspector.all("SELECT id FROM fetch_attempts WHERE crawl_id=$1::uuid",
                             [ctx[:crawl_id]]).size).to eq(Workflows::Wf005::FetchContent::MAX_ATTEMPTS)
    end

    it "records the SOFT crossing but NOT the hard one when a timeout is retried and succeeds" do
      # This example previously asserted `limit_events` was EMPTY, which locked in a defect: the
      # timed-out attempt ran to the 3 s hard bound, so it crossed the 2 s soft bound, and :442's
      # soft limb is unconditional. The hard limb is the one :444 defers to exhaustion. An
      # observation is not a disposition — the same rule the frontier learned.
      ctx = fetchable
      narrow(ctx, "request_timeout_seconds" => { "soft" => 2, "hard" => 3 })
      queue = [Platform::Outbound::Outcome.timeout(canonical_host: "shop.acme.example"), content_response]
      outbound = Object.new
      outbound.define_singleton_method(:fetch) { |*_a, **_k| queue.length > 1 ? queue.shift : queue.first }
      entry = DbInspector.one("SELECT * FROM crawl_frontier_entries WHERE crawl_id=$1::uuid ORDER BY dequeue_key LIMIT 1",
                              [ctx[:crawl_id]])

      result = Workflows::Wf005::FetchContent.new(outbound:, pacer: pacer_for(ctx)).call(
        organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id], entry:,
        gate_id: ctx[:gate_id], now: start_now)

      expect(result.document?).to be(true)
      expect(decision(ctx[:crawl_id], "connection_plus_response_time_per_request", "hard")).to be_nil
      soft = decision(ctx[:crawl_id], "connection_plus_response_time_per_request", "soft")
      expect(soft).not_to be_nil
      expect(soft["observed_value"].to_i).to eq(3)
      expect(limit_events(ctx[:crawl_id])).to eq(["CrawlSoftLimitApproaching"])
    end

    it "records nothing for a request that answered inside the bound" do
      ctx = fetchable
      fetch(ctx, content_response)
      expect(decisions(ctx[:crawl_id]).map { |d| d["limit_dimension"] })
        .not_to include("connection_plus_response_time_per_request")
    end
  end

  describe "redirects per URL (:438)" do
    it "records the SOFT crossing from the redirect count the fetch actually followed" do
      ctx = fetchable
      narrow(ctx, "redirects_per_url" => { "soft" => 1, "hard" => 3 })

      fetch(ctx, content_response(redirect_count: 2))

      row = decision(ctx[:crawl_id], "redirects_per_url", "soft")
      expect(row).not_to be_nil
      expect(row["configured_value"].to_i).to eq(1)
      expect(row["observed_value"].to_i).to eq(2)
    end
  end

  # ---- sitemap discovery's two dimensions ---------------------------------------

  def urlset(*locs)
    entries = locs.map { |l| "<url><loc>#{l}</loc></url>" }.join
    %(<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{entries}</urlset>)
  end

  def sitemapindex(*locs)
    entries = locs.map { |l| "<sitemap><loc>#{l}</loc></sitemap>" }.join
    %(<?xml version="1.0" encoding="UTF-8"?><sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{entries}</sitemapindex>)
  end

  def xml_response(body)
    Platform::Outbound::Outcome.response(
      status: 200, headers: { "content-type" => "application/xml" }, body:, byte_count: body.bytesize,
      truncated: false, canonical_host: "shop.acme.example", port: 443, pinned_address: "198.51.100.7",
      final_url: "https://shop.acme.example/sitemap.xml", redirect_count: 0, latency_ms: 5)
  end

  def with_robots(sitemaps: [])
    ctx = running_crawl
    ensure_gate(ctx)
    body = (["User-agent: *", "Allow: /"] + sitemaps.map { |s| "Sitemap: #{s}" }).join("\n") + "\n"
    resolve_robots(ctx, outbound_returning(response(status: 200, body:)))
    ctx
  end

  # Keyed by URL rather than by call order: the traversal interleaves the declared sitemaps with
  # the default `/sitemap.xml` in canonical order, so a positional queue would answer the wrong
  # document and the test would be asserting the stub's shape rather than the traversal's.
  def by_url(map, default: nil)
    Object.new.tap do |o|
      o.define_singleton_method(:fetch) { |url, *_a, **_k| map.fetch(url, default) }
    end
  end

  def not_found
    Platform::Outbound::Outcome.response(
      status: 404, headers: {}, body: "", byte_count: 0, truncated: false,
      canonical_host: "shop.acme.example", port: 443, pinned_address: "198.51.100.7",
      final_url: "https://shop.acme.example/sitemap.xml", redirect_count: 0, latency_ms: 5)
  end

  def discover_urls(ctx, map)
    Workflows::Wf005::DiscoverSitemaps.new(outbound: by_url(map, default: not_found),
                                           pacer: pacer_for(ctx)).call(
      organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id],
      canonical_host: ctx[:host], source_id: ctx[:source_id], now: start_now)
  end

  def discover(ctx, *outcomes)
    Workflows::Wf005::DiscoverSitemaps.new(outbound: outbound_returning(*outcomes), pacer: pacer_for(ctx)).call(
      organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id],
      canonical_host: ctx[:host], source_id: ctx[:source_id], now: start_now)
  end

  describe "sitemap documents per run (:437)" do
    it "enforces and records the RESOLVED bound, not the frozen ceiling" do
      # The ceiling passed to the run-wide reservation was a class constant, so a Project that
      # narrowed `sitemap_documents` was silently ignored — the same defect S-07-007 fixed on the
      # per-fetch bounds, found here by making the decision record the number it enforced.
      ctx = with_robots(sitemaps: %w[https://shop.acme.example/a.xml https://shop.acme.example/b.xml])
      narrow(ctx, "sitemap_documents" => { "soft" => 1, "hard" => 1 })

      discover(ctx, xml_response(urlset("https://shop.acme.example/p1")))

      row = decision(ctx[:crawl_id], "sitemap_documents_per_run", "hard")
      expect(row).not_to be_nil
      expect(row["configured_value"].to_i).to eq(1)
      expect(limit_events(ctx[:crawl_id])).to include("CrawlLimitReached")
      # One document was fetched, and the run stopped there rather than at 50.
      expect(DbInspector.one("SELECT sitemap_documents FROM crawl_budget_counters WHERE crawl_id=$1::uuid",
                             [ctx[:crawl_id]])["sitemap_documents"].to_i).to eq(1)
    end

    it "records the SOFT crossing at the resolved soft bound" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/a.xml"])
      narrow(ctx, "sitemap_documents" => { "soft" => 1, "hard" => 4 })

      discover(ctx, xml_response(urlset("https://shop.acme.example/p1")))

      row = decision(ctx[:crawl_id], "sitemap_documents_per_run", "soft")
      expect(row).not_to be_nil
      expect(row["observed_value"].to_i).to eq(1)
    end
  end

  describe "sitemap index nesting depth (:438)" do
    it "records the HARD limit when an index nests past the resolved bound" do
      ctx = with_robots(sitemaps: ["https://shop.acme.example/i0.xml"])
      narrow(ctx, "sitemap_index_depth" => { "soft" => 1, "hard" => 1 })

      # i0 (index depth 0) names i1 (depth 1), which names i2 (depth 2) — past the bound.
      discover_urls(ctx, {
                      "https://shop.acme.example/i0.xml" =>
                        xml_response(sitemapindex("https://shop.acme.example/i1.xml")),
                      "https://shop.acme.example/i1.xml" =>
                        xml_response(sitemapindex("https://shop.acme.example/i2.xml")),
                      "https://shop.acme.example/i2.xml" =>
                        xml_response(urlset("https://shop.acme.example/p1"))
                    })

      row = decision(ctx[:crawl_id], "sitemap_index_nesting_depth", "hard")
      expect(row).not_to be_nil
      expect(row["configured_value"].to_i).to eq(1)
    end
  end

  # ---- the boundary of this tranche, stated rather than implied -----------------

  describe "dimensions with no observation point yet" do
    it "records nothing for accepted pages, which needs the Documents S-07-010 creates" do
      # :436 retains "the first 10,000 successful DOCUMENTS in dequeue order". The bound counts an
      # artifact this tranche cannot create, so admitting one here would be counting fetches and
      # calling them pages. The dimension stays unobserved until the artifact exists.
      ctx = fetchable
      fetch(ctx, content_response)
      expect(decisions(ctx[:crawl_id]).map { |d| d["limit_dimension"] })
        .not_to include("accepted_pages_per_run")
    end

    it "records nothing for per-host rate or concurrency, which :442 resolves by DELAYING" do
      # ":442 — a start that would make the count exceed 2 is DELAYED", and :456's list of bounds
      # that make a candidate unevaluated is "depth, sitemap, queue, page, byte, response, request,
      # or wall-clock" — rate and concurrency are absent from it. They are pacing parameters the
      # scheduler holds the observation BELOW, not thresholds a run reaches.
      ctx = fetchable
      seed_leases(ctx[:gate_id], 4)
      fetch(ctx, content_response)

      expect(decisions(ctx[:crawl_id]).map { |d| d["limit_dimension"] })
        .not_to include("request_rate_per_canonical_host", "concurrent_requests_per_canonical_host")
    end
  end
end
