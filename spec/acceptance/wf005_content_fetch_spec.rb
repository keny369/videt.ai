# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# WF-005 content fetch (S-07-007; WORKFLOW_SPECIFICATIONS.md :436, :442, :444, :448, :452;
# SEARCH_CRAWL_RETRIEVAL.md § Destination And HTTP Safety).
#
# Four properties are load-bearing and are asserted against the PRODUCTION-REAL chain rather than
# against a double:
#
#   * every fetch passes the host gate AND execution-time authorization, never queue-time authority;
#   * bytes are RESERVED before the body is read, committed at what was consumed, and the remainder
#     released — so N concurrent attempts cannot sum past the run bound (:442);
#   * a redirect is rechecked against robots and Source Scope BEFORE it is followed (:448), not
#     after, because a disallowed intermediate that was fetched has already been fetched;
#   * :452's outcome vocabulary is applied exactly, including which outcomes stay in the coverage
#     denominator and which do not.
#
# The outbound surface is the ONLY thing stubbed, and it is stubbed at the frozen F-01 façade.
RSpec.describe "WF-005 content fetch", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-E2E TYP-SEC TYP-DATA] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  # ---- content-fetch harness --------------------------------------------------

  # Every request the stub saw, WITH its keyword arguments, so the ratified per-fetch bounds are
  # asserted on the REQUEST rather than assumed.
  def requests = (@requests ||= [])
  def paces = (@paces ||= [])

  def content_outbound(*outcomes)
    queue = outcomes.dup
    sink = requests
    Object.new.tap do |o|
      o.define_singleton_method(:fetch) do |url, **kwargs|
        sink << kwargs.merge(url:)
        result = queue.length > 1 ? queue.shift : queue.first
        result.respond_to?(:call) ? result.call(url, **kwargs) : result
      end
    end
  end

  def content_response(status: 200, body: "<html><title>t</title></html>", type: "text/html",
                       final_url: nil, redirect_count: 0, truncated: false, byte_count: nil)
    headers = type.nil? ? {} : { "content-type" => type }
    Platform::Outbound::Outcome.response(
      status:, headers:, body:, byte_count: byte_count || body.bytesize, truncated:,
      canonical_host: "shop.acme.example", port: 443, pinned_address: "198.51.100.7",
      final_url: final_url || "https://shop.acme.example/p1", redirect_count:, latency_ms: 5)
  end

  # A crawl whose robots is resolved and whose frontier holds the seeded root entry.
  def fetchable(robots: "User-agent: *\nAllow: /\n")
    ctx = running_crawl
    ensure_gate(ctx)
    resolve_robots(ctx, outbound_returning(response(status: 200, body: robots)))
    ctx[:gate_id] = gate_row(ctx[:crawl_id])["id"]
    ctx
  end

  def root_entry(ctx)
    DbInspector.one("SELECT * FROM crawl_frontier_entries WHERE crawl_id=$1::uuid ORDER BY dequeue_key LIMIT 1",
                    [ctx[:crawl_id]])
  end

  # The pacer advances simulated time so the gate's own predicates decide whether enough elapsed;
  # clearing the columns outright would make every retry succeed regardless of the configured delay.
  def pacer_for(ctx)
    sink = paces
    lambda do |ms|
      sink << ms.to_i
      DbInspector.connection.exec_params(
        "UPDATE crawl_host_gates
         SET recent_start_instants =
               (SELECT COALESCE(array_agg(s - ($2 || \' milliseconds\')::interval),
                                ARRAY[]::timestamptz(6)[])
                FROM unnest(recent_start_instants) AS s),
             next_allowed_start_at = next_allowed_start_at - ($2 || \' milliseconds\')::interval,
             state_version = state_version + 1
         WHERE crawl_id = $1::uuid", [ctx[:crawl_id], ms.to_i])
    end
  end

  def fetch_content(ctx, outbound, entry: nil)
    Workflows::Wf005::FetchContent.new(outbound:, pacer: pacer_for(ctx)).call(
      organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id],
      entry: entry || root_entry(ctx), gate_id: ctx[:gate_id], now: start_now)
  end

  # The host gate paces starts at 1/second (:442). A test that fetches twice must let that second
  # pass, and it does so by moving the recorded instants into the past — the same simulation the
  # pacer uses, so the gate's own predicates still decide.
  def advance_gate(ctx, ms = 2_000) = pacer_for(ctx).call(ms)

  def counters(cid) = DbInspector.one("SELECT * FROM crawl_budget_counters WHERE crawl_id=$1::uuid", [cid])

  # Create the counter row through the production store, so a test that needs to manipulate the
  # budget is manipulating the same row the service will read rather than one it invented.
  def ensure_counters(ctx)
    Platform::UnitOfWork.run do |conn|
      store = IdentityAccess::Infrastructure::CrawlBudgetStore.new(conn.raw_connection)
      store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
      store.ensure_counters(id: Platform::Ids.system.generate, now: start_now,
                            correlation_id: SecureRandom.uuid_v7,
                            organization_id: ctx[:g][:organization_id],
                            project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id])
    end
  end
  def attempts(cid) = DbInspector.all("SELECT * FROM fetch_attempts WHERE crawl_id=$1::uuid ORDER BY attempt_number", [cid])

  # ---- the happy path and what it records -------------------------------------

  describe "an accepted page (:436)" do
    it "creates a document outcome, records the attempt, and accounts the bytes" do
      ctx = fetchable
      body = "<html><title>Home</title></html>"
      result = fetch_content(ctx, content_outbound(content_response(body:)))

      expect(result.outcome).to eq("document_created")
      expect(result.document?).to be(true)
      expect(result.covered?).to be(true)
      expect(result.media_type).to eq("text/html")

      row = attempts(ctx[:crawl_id]).first
      expect(row["outcome"]).to eq("document_created")
      expect(row["accounted_response_bytes"].to_i).to eq(body.bytesize)
      expect(row["limit_probe_bytes"].to_i).to eq(0)
      expect(row["terminal_at"]).not_to be_nil
      expect(row["attempt_number"].to_i).to eq(1)
    end

    it "sends the ratified per-fetch bounds on the REQUEST" do
      ctx = fetchable
      fetch_content(ctx, content_outbound(content_response))

      req = requests.last
      expect(req[:timeout_s]).to eq(15)
      expect(req[:max_redirects]).to eq(10)
      expect(req[:user_agent]).to eq("F1DiscoverabilityBot")
      # The byte cap is the RESERVATION, so a run with less budget left reads less.
      expect(req[:byte_cap]).to eq(10 * 1024 * 1024)
      expect(req[:redirect_guard]).to respond_to(:call)
    end

    it "accepts application/xhtml+xml as well as text/html, before parameters" do
      ctx = fetchable
      result = fetch_content(ctx, content_outbound(content_response(type: "application/xhtml+xml; charset=utf-8")))
      expect(result.outcome).to eq("document_created")
      expect(result.media_type).to eq("application/xhtml+xml")
    end
  end

  # ---- :442's reserve / commit / release protocol ------------------------------

  describe "byte accounting reserves before reading and releases the remainder (:442)" do
    it "commits only what was consumed and hands the rest back" do
      ctx = fetchable
      body = "<html>" + ("x" * 500) + "</html>"
      fetch_content(ctx, content_outbound(content_response(body:)))

      row = counters(ctx[:crawl_id])
      expect(row["committed_response_bytes"].to_i).to eq(body.bytesize)
      # The reservation was 10 MiB; everything unused is back in the run's budget, so reserved and
      # committed agree once the attempt is done. Without the release, one attempt would retire
      # 10 MiB of a 1,250 MiB run.
      expect(row["reserved_response_bytes"].to_i).to eq(body.bytesize)
    end

    it "keeps committed within reserved, which the database also enforces" do
      ctx = fetchable
      fetch_content(ctx, content_outbound(content_response))
      row = counters(ctx[:crawl_id])
      expect(row["committed_response_bytes"].to_i).to be <= row["reserved_response_bytes"].to_i

      expect do
        DbInspector.connection.exec_params(
          "UPDATE crawl_budget_counters SET committed_response_bytes = reserved_response_bytes + 1,
             state_version = state_version + 1 WHERE crawl_id = $1::uuid", [ctx[:crawl_id]])
      end.to raise_error(/committed_within_reserved/)
    end

    it "FAILS the URL on a body one byte past the per-URL maximum, and counts the probe apart" do
      ctx = fetchable
      cap = Workflows::Wf005::ByteAccounting::PER_URL_CEILING
      # F-01 reads cap + 1 precisely so the caller can tell exact-maximum from over-limit.
      over = content_response(body: "x", byte_count: cap + 1, truncated: true)
      result = fetch_content(ctx, content_outbound(over))

      expect(result.outcome).to eq("content_fetch_failed")
      expect(result.reason_code).to eq("response_body_limit_exceeded")
      expect(result.reduces_coverage?).to be(true)

      row = counters(ctx[:crawl_id])
      expect(row["limit_probe_bytes"].to_i).to eq(1)
      # ":442 — limit_probe_bytes are detection telemetry, not accepted/accounted capacity."
      expect(row["committed_response_bytes"].to_i).to eq(cap)
    end

    it "ALLOWS a body of exactly the per-URL maximum" do
      ctx = fetchable
      cap = Workflows::Wf005::ByteAccounting::PER_URL_CEILING
      result = fetch_content(ctx, content_outbound(content_response(body: "x", byte_count: cap)))
      expect(result.outcome).to eq("document_created")
      expect(counters(ctx[:crawl_id])["limit_probe_bytes"].to_i).to eq(0)
    end

    it "stops reserving once the run-wide budget is spent, without blaming the site" do
      ctx = fetchable
      ensure_counters(ctx)
      # Retire the whole run budget, as concurrent attempts would have.
      DbInspector.connection.exec_params(
        "UPDATE crawl_budget_counters SET reserved_response_bytes = $2, committed_response_bytes = $2,
           state_version = state_version + 1 WHERE crawl_id = $1::uuid",
        [ctx[:crawl_id], Workflows::Wf005::ByteAccounting::RUN_CEILING])

      result = fetch_content(ctx, content_outbound(content_response))
      expect(result.outcome).to eq("limit_discarded")
      expect(result.reason_code).to eq("run_byte_budget_exhausted")
      # The request was never made: a run with no budget does not spend the host's rate limit.
      expect(requests).to be_empty
    end
  end

  # ---- :448's redirect recheck -------------------------------------------------

  describe "redirects are rechecked BEFORE they are followed (:448)" do
    it "hands the connector a guard that denies an out-of-scope hop" do
      ctx = fetchable
      guard = nil
      out = content_outbound(->(_url, **kwargs) { guard = kwargs[:redirect_guard]; content_response })
      fetch_content(ctx, out)

      expect(guard).not_to be_nil
      expect(guard.call(URI.parse("https://shop.acme.example/other"))).to be(true)
      # A different host is out of Source Scope, whatever the platform thinks of its address.
      expect(guard.call(URI.parse("https://evil.example/x"))).to be(false)
    end

    it "denies every hop once the Source is disabled mid-run" do
      ctx = fetchable
      guard = nil
      fetch_content(ctx, content_outbound(->(_u, **k) { guard = k[:redirect_guard]; content_response }))
      expect(guard.call(URI.parse("https://shop.acme.example/ok"))).to be(true)

      disable_source(ctx[:g], ctx[:source_id])
      expect(guard.call(URI.parse("https://shop.acme.example/ok"))).to be(false)
    end

    it "FAILS CLOSED when the guard cannot decide" do
      ctx = fetchable
      guard = nil
      fetch_content(ctx, content_outbound(->(_u, **k) { guard = k[:redirect_guard]; content_response }))

      # A target with no host is not a permitted target.
      expect(guard.call(URI.parse("https://"))).to be(false)

      # And a target the guard cannot even READ is not permitted either. An error while deciding
      # whether a hop is allowed is not permission — the alternative is that a transient database
      # failure mid-redirect silently widens what the crawler will fetch.
      hostile = Object.new.tap { |o| o.define_singleton_method(:to_s) { raise "unreadable target" } }
      expect(guard.call(hostile)).to be(false)
    end

    it "records a caller-denied redirect OUTSIDE the coverage denominator (:452)" do
      ctx = fetchable
      denied = Platform::Outbound::Outcome.rejected(
        :redirect_policy_denied, canonical_host: "shop.acme.example", port: 443,
        final_url: "https://shop.acme.example/denied", redirect_count: 1)
      result = fetch_content(ctx, content_outbound(denied))

      expect(result.outcome).to eq("policy_excluded")
      expect(result.in_denominator?).to be(false)
      expect(result.reduces_coverage?).to be(false)
    end

    # :454 requires "its EXACT limit reason", and F-01 used to emit ONE rejection for six distinct
    # conditions — so a redirect to `http://` was filed as an eleventh-redirect limit hit. One
    # example per value: each needs its own bootstrapped tenant, and the host gate's rate window
    # would refuse a second fetch in the same example anyway.
    {
      redirect_budget_exhausted: "redirect_limit_exhausted",
      redirect_loop: "redirect_loop_detected",
      redirect_rejected: "redirect_target_invalid"
    }.each do |platform_reason, expected|
      it "records #{platform_reason} as a FAILURE inside the denominator, under its own reason (:452)" do
        ctx = fetchable
        rejected = Platform::Outbound::Outcome.rejected(
          platform_reason, canonical_host: "shop.acme.example", port: 443,
          final_url: "https://shop.acme.example/x", redirect_count: 10)
        result = fetch_content(ctx, content_outbound(rejected))

        expect(result.outcome).to eq("content_fetch_failed")
        expect(result.reason_code).to eq(expected)
        expect(result.in_denominator?).to be(true)
      end
    end
  end

  # ---- :452's outcome vocabulary ----------------------------------------------

  describe "outcome classification is exhaustive (:452)" do
    it "treats a terminal 404 as COVERED, not as a failure" do
      ctx = fetchable
      result = fetch_content(ctx, content_outbound(content_response(status: 404, body: "")))
      expect(result.outcome).to eq("content_absent")
      expect(result.covered?).to be(true)
      expect(result.reduces_coverage?).to be(false)
    end

    it "treats an unsupported media type as POLICY EXCLUDED, outside the denominator" do
      ctx = fetchable
      result = fetch_content(ctx, content_outbound(content_response(type: "application/pdf")))
      expect(result.outcome).to eq("policy_excluded")
      expect(result.in_denominator?).to be(false)
    end

    it "treats a 4xx other than 404/410 as a failure that stays in the denominator" do
      ctx = fetchable
      result = fetch_content(ctx, content_outbound(content_response(status: 403, body: "")))
      expect(result.outcome).to eq("content_fetch_failed")
      expect(result.reduces_coverage?).to be(true)
    end

    it "treats a connection failure as a failure and marks it retryable (:444)" do
      ctx = fetchable
      result = fetch_content(ctx, content_outbound(Platform::Outbound::Outcome.timeout(canonical_host: "shop.acme.example")))
      expect(result.outcome).to eq("content_fetch_failed")
      expect(result.reduces_coverage?).to be(true)
    end
  end

  # ---- execution-time authorization -------------------------------------------

  describe "authorization is re-evaluated at execution time, never taken from the queue" do
    it "refuses to fetch a URL whose Source was disabled after it was queued" do
      ctx = fetchable
      entry = root_entry(ctx)
      disable_source(ctx[:g], ctx[:source_id])

      result = fetch_content(ctx, content_outbound(content_response), entry:)
      expect(result.outcome).to eq("policy_excluded")
      expect(result.reason_code).to eq("fetch_not_authorized")
      expect(requests).to be_empty
    end

    it "refuses to fetch once the Organization is suspended" do
      ctx = fetchable
      entry = root_entry(ctx)
      suspend_organization(ctx[:g])

      result = fetch_content(ctx, content_outbound(content_response), entry:)
      expect(result.outcome).to eq("policy_excluded")
      expect(requests).to be_empty
    end
  end

  # ---- :444 retries ------------------------------------------------------------

  describe "retry schedule (:444)" do
    it "retries a transient failure up to the ratified bound and records EVERY attempt" do
      ctx = fetchable
      timeout = Platform::Outbound::Outcome.timeout(canonical_host: "shop.acme.example")
      result = fetch_content(ctx, content_outbound(timeout))

      expect(result.outcome).to eq("content_fetch_failed")
      rows = attempts(ctx[:crawl_id])
      expect(rows.size).to eq(Workflows::Wf005::FetchContent::MAX_ATTEMPTS)
      expect(rows.map { |r| r["attempt_number"].to_i }).to eq([1, 2, 3])
      # A record exists for every request that was made, including the ones that failed —
      # SEARCH_CRAWL_RETRIEVAL :82, "never replaced by an unaccounted request".
      expect(rows.map { |r| r["outcome"] }.uniq).to eq(["content_fetch_failed"])
    end

    it "waits :444's fixed schedule — 30s then 120s — not an ad-hoc constant" do
      ctx = fetchable
      fetch_content(ctx, content_outbound(Platform::Outbound::Outcome.timeout(canonical_host: "shop.acme.example")))
      # EXACTLY two delays, not `first(2)`. :444 gives one initial attempt plus at most two retries,
      # so a third delay precedes no request — and asserting a prefix is blind to it by construction,
      # which is how the third delay survived review.
      expect(paces).to eq([30_000, 120_000])
    end

    it "does not retry a nonretryable status" do
      ctx = fetchable
      fetch_content(ctx, content_outbound(content_response(status: 403, body: "")))
      expect(attempts(ctx[:crawl_id]).size).to eq(1)
    end
  end

  # ---- the attempt record is write-once ---------------------------------------

  describe "the attempt record" do
    it "freezes its identity from insert" do
      ctx = fetchable
      fetch_content(ctx, content_outbound(content_response))
      row = attempts(ctx[:crawl_id]).first

      expect do
        DbInspector.connection.exec_params(
          "UPDATE fetch_attempts SET canonical_url = 'https://elsewhere.example/', checkpoint_version = checkpoint_version + 1
           WHERE id = $1::uuid", [row["id"]])
      end.to raise_error(/identity_immutable/)
    end

    it "freezes its RESULT once terminal" do
      ctx = fetchable
      fetch_content(ctx, content_outbound(content_response))
      row = attempts(ctx[:crawl_id]).first

      expect do
        DbInspector.connection.exec_params(
          "UPDATE fetch_attempts SET outcome = 'content_fetch_failed', checkpoint_version = checkpoint_version + 1
           WHERE id = $1::uuid", [row["id"]])
      end.to raise_error(/result_frozen/)
    end

    it "cannot record accounted bytes beyond its reservation (:442)" do
      ctx = fetchable
      fetch_content(ctx, content_outbound(content_response))
      row = attempts(ctx[:crawl_id]).first

      expect do
        DbInspector.connection.exec_params(
          "UPDATE fetch_attempts SET accounted_response_bytes = reserved_bytes + 1,
             checkpoint_version = checkpoint_version + 1 WHERE id = $1::uuid", [row["id"]])
      end.to raise_error(/within_reservation|result_frozen/)
    end

    it "is never deletable" do
      ctx = fetchable
      fetch_content(ctx, content_outbound(content_response))
      row = attempts(ctx[:crawl_id]).first
      expect do
        DbInspector.connection.exec_params("DELETE FROM fetch_attempts WHERE id = $1::uuid", [row["id"]])
      end.to raise_error(/fetch_attempt_immutable|permission denied/)
    end
  end

  # ---- the branches the ADR-026 architecture lens found UNCOVERED ---------------
  #
  # All four passed with their fix reverted. Two of them were the defects the previous commit
  # headlined as "found by writing the tests" — which is exactly the shape of claim that needs a
  # test rather than a sentence.

  describe "a reservation smaller than the per-URL ceiling (the run budget is the tighter bound)" do
    # Every other example runs with a full run budget, so `reserved == bounds.per_url` always held
    # and this whole branch was unreachable.
    def with_remaining(ctx, bytes)
      ensure_counters(ctx)
      DbInspector.connection.exec_params(
        "UPDATE crawl_budget_counters
         SET reserved_response_bytes = $2, committed_response_bytes = $2,
             state_version = state_version + 1 WHERE crawl_id = $1::uuid",
        [ctx[:crawl_id], Workflows::Wf005::ByteAccounting::RUN_CEILING - bytes])
    end

    it "caps the read at what REMAINS, not at the per-URL maximum" do
      ctx = fetchable
      with_remaining(ctx, 4096)
      fetch_content(ctx, content_outbound(content_response))
      expect(requests.last[:byte_cap]).to eq(4096)
    end

    it "blames the RUN's budget, not the site, when a body overruns that smaller reservation" do
      # Over the per-URL maximum is the site's response -> content_fetch_failed, in the denominator.
      # Over a reservation that is smaller only because the run is nearly spent is a limit discard.
      ctx = fetchable
      with_remaining(ctx, 4096)
      over = content_response(body: "x", byte_count: 4097, truncated: true)
      result = fetch_content(ctx, content_outbound(over))

      expect(result.outcome).to eq("limit_discarded")
      expect(result.reason_code).to eq("run_byte_budget_exhausted")
      expect(result.reduces_coverage?).to be(false)
    end

    it "measures against the RESERVATION, so a small body under it is still accepted" do
      ctx = fetchable
      with_remaining(ctx, 4096)
      result = fetch_content(ctx, content_outbound(content_response(body: "<html>ok</html>")))
      expect(result.outcome).to eq("document_created")
      expect(counters(ctx[:crawl_id])["limit_probe_bytes"].to_i).to eq(0)
    end
  end

  describe ":436's final-URL scope recheck" do
    it "EXCLUDES a page whose final URL current scope no longer admits" do
      # Every hop passed the redirect guard, the platform allowed each one, and the response is a
      # perfectly good document — but the URL it actually came from is out of scope now.
      ctx = fetchable
      landed = content_response(final_url: "https://other.example/landed")
      result = fetch_content(ctx, content_outbound(landed))

      expect(result.outcome).to eq("policy_excluded")
      expect(result.in_denominator?).to be(false)
    end

    it "admits a page that redirected WITHIN scope" do
      ctx = fetchable
      landed = content_response(final_url: "https://shop.acme.example/moved", redirect_count: 1)
      expect(fetch_content(ctx, content_outbound(landed)).outcome).to eq("document_created")
    end
  end

  # ---- reclamation: ":82 — completed OR TIMED OUT" ------------------------------

  describe "a lost worker's attempt and its reservation are reclaimed" do
    it "times out an expired attempt lease and hands its bytes back to the run" do
      ctx = fetchable
      fetch_content(ctx, content_outbound(content_response))

      # A worker that claimed, reserved, and died: a non-terminal attempt holding 10 MiB.
      ensure_counters(ctx)
      # The counter is advanced by LESS than the attempt holds. That asymmetry is what a crash
      # between reserve and commit actually leaves behind, and it is why the release floor is
      # `committed_response_bytes` rather than zero: clamping to zero drives reserved below
      # committed and raises `PG::CheckViolation` inside the sweeper.
      DbInspector.connection.exec_params(
        "UPDATE crawl_budget_counters SET reserved_response_bytes = reserved_response_bytes + 4096,
           state_version = state_version + 1 WHERE crawl_id = $1::uuid", [ctx[:crawl_id]])
      DbInspector.connection.exec_params(
        "INSERT INTO fetch_attempts (id, checkpoint_version, lock_version, schema_version, created_at,
           updated_at, correlation_id, causation_id, organization_id, project_id, crawl_id,
           crawl_host_gate_id, source_id, crawl_frontier_entry_id, request_kind, attempt_number,
           canonical_url, canonical_url_preimage, canonical_url_sha256, canonical_host, depth,
           reserved_bytes, claim_owner, claim_generation, claimed_at, lease_expires_at,
           prepared_at, deadline_at)
         SELECT gen_random_uuid(), 0, 0, 'fetch-attempt-v1', now(), now(), gen_random_uuid(),
                gen_random_uuid(), a.organization_id, a.project_id, a.crawl_id, a.crawl_host_gate_id,
                a.source_id, a.crawl_frontier_entry_id, 'content', 2, a.canonical_url,
                a.canonical_url_preimage, a.canonical_url_sha256, a.canonical_host, a.depth,
                10485760, gen_random_uuid(), 1, $2::timestamptz - interval '1 hour',
                $2::timestamptz - interval '30 minutes', $2::timestamptz - interval '1 hour', $2::timestamptz
         FROM fetch_attempts a WHERE a.crawl_id = $1::uuid LIMIT 1",
        [ctx[:crawl_id], start_now])

      before = counters(ctx[:crawl_id])
      expect(before["reserved_response_bytes"].to_i - before["committed_response_bytes"].to_i).to eq(4096)

      # The next fetch sweeps first: every claim repairs the accounting it is about to rely on.
      advance_gate(ctx)
      fetch_content(ctx, content_outbound(content_response))

      swept = DbInspector.one("SELECT outcome, reason_code FROM fetch_attempts
                               WHERE crawl_id=$1::uuid AND attempt_number=2", [ctx[:crawl_id]])
      expect(swept["outcome"]).to eq("timed_out")
      expect(swept["reason_code"]).to eq("attempt_lease_expired")

      after = counters(ctx[:crawl_id])
      expect(after["reserved_response_bytes"].to_i - after["committed_response_bytes"].to_i).to eq(0)
    end

    it "COUNTS a timed-out attempt against :444's bound, and exhausts honestly" do
      # A worker lost after claiming may already have issued its request; the run cannot know. So
      # the identity is consumed — refunding it would let a host that kills workers be retried
      # without bound — and the entry exhausts as `content_fetch_failed` INSIDE the coverage
      # denominator rather than hanging as `contended` outside it.
      ctx = fetchable
      3.times do |i|
        DbInspector.connection.exec_params(
          "INSERT INTO fetch_attempts (id, checkpoint_version, lock_version, schema_version,
             created_at, updated_at, correlation_id, causation_id, organization_id, project_id,
             crawl_id, crawl_host_gate_id, source_id, crawl_frontier_entry_id, request_kind,
             attempt_number, canonical_url, canonical_url_preimage, canonical_url_sha256,
             canonical_host, depth, reserved_bytes, prepared_at, deadline_at,
             outcome, reason_code, terminal_at, completed_at, retryable, accounted_response_bytes)
           VALUES (gen_random_uuid(), 0, 0, 'fetch-attempt-v1', now(), now(), gen_random_uuid(),
                   gen_random_uuid(), $1::uuid, $2::uuid, $3::uuid, $4::uuid, $5::uuid, $6::uuid,
                   'content', $7, $8, convert_to($8,'UTF8'), sha256(convert_to($8,'UTF8')),
                   'shop.acme.example', 0, 0, now(), now(),
                   'timed_out', 'attempt_lease_expired', now(), now(), true, 0)",
          [ctx[:g][:organization_id], ctx[:g][:project_id], ctx[:crawl_id], ctx[:gate_id],
           ctx[:source_id], root_entry(ctx)["id"], i + 1, root_entry(ctx)["canonical_url"]])
      end

      result = fetch_content(ctx, content_outbound(content_response))
      expect(result.outcome).to eq("content_fetch_failed")
      expect(result.reason_code).to eq("content_fetch_attempts_exhausted")
      expect(result.in_denominator?).to be(true)
      expect(requests).to be_empty
    end
  end

  # ---- a guard that could not DECIDE is not a policy fact -----------------------

  describe "an infrastructure failure inside the redirect guard" do
    it "is a retryable FAILURE in the denominator, not a policy exclusion outside it" do
      # A transient database error mid-redirect must not look like a robots denial: `policy_excluded`
      # is the one :452 outcome that leaves the coverage denominator, so misfiling it makes coverage
      # read better than reality, silently.
      ctx = fetchable
      denied = Platform::Outbound::Outcome.rejected(
        :redirect_policy_denied, canonical_host: "shop.acme.example", port: 443,
        final_url: "https://shop.acme.example/hop", redirect_count: 1)
      out = content_outbound(lambda do |_url, **kwargs|
        kwargs[:redirect_guard].call(Object.new.tap { |o| o.define_singleton_method(:to_s) { raise "db down" } })
        denied
      end)

      result = fetch_content(ctx, out)
      expect(result.outcome).to eq("content_fetch_failed")
      expect(result.reason_code).to eq("redirect_check_unavailable")
      expect(result.in_denominator?).to be(true)
    end
  end

  # ---- :390 applies to every per-fetch bound, not only bytes --------------------

  describe "effective bounds are resolved per Crawl (:390)" do
    it "narrows the request timeout and redirect budget from an active Project policy" do
      ctx = fetchable
      # `crawl_policies` rows are immutable, so a narrower policy is ACTIVATED rather than edited.
      narrowed = JSON.parse(JSON.generate(Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING))
                     .merge("request_timeout_seconds" => { "soft" => 3, "hard" => 4 },
                            "redirects_per_url" => { "soft" => 1, "hard" => 2 })
      DbInspector.connection.exec_params(
        "INSERT INTO crawl_policies (id, state_version, created_at, updated_at, correlation_id,
           schema_version, organization_id, project_id, scope, policy_version, state,
           normalized_bounds, content_sha256, activated_by_account_id)
         VALUES (gen_random_uuid(), 0, now(), now(), gen_random_uuid(), 'crawl-policy-v1', $1::uuid, $2::uuid,
                 'project', 'crawl-policy-v1-narrowed', 'active', $3::jsonb,
                 sha256(convert_to($3::text, 'UTF8')), $4::uuid)",
        [ctx[:g][:organization_id], ctx[:g][:project_id], JSON.generate(narrowed), ctx[:g][:account_id]])

      fetch_content(ctx, content_outbound(content_response))
      # These were class constants, so a Project that narrowed them was silently ignored.
      expect(requests.last[:timeout_s]).to eq(4)
      expect(requests.last[:max_redirects]).to eq(2)
    end
  end

  # ---- the remaining properties the mutation sweep found uncovered -------------

  describe "a lost terminal decision is an invariant violation, not a silent divergence" do
    it "raises rather than leaving the byte counter advanced and the attempt blank" do
      # The counter and the attempt record describe the same event. If the record cannot be written,
      # the bytes must not be counted either — :442's "run-wide accounted bytes are EXACTLY
      # sum(accounted_response_bytes_i)" has to remain reproducible from the record.
      ctx = fetchable
      out = content_outbound(lambda do |_url, **_k|
        # Terminalise the attempt out-of-band, between the claim and the settle, so the service's
        # own write matches zero rows — exactly what a replayed or raced terminalisation does.
        DbInspector.connection.exec_params(
          "UPDATE fetch_attempts SET outcome='content_fetch_failed', reason_code='raced',
             terminal_at=now(), completed_at=now(), retryable=false,
             claim_owner=NULL, claimed_at=NULL, lease_expires_at=NULL,
             checkpoint_version = checkpoint_version + 1
           WHERE crawl_id=$1::uuid AND outcome IS NULL", [ctx[:crawl_id]])
        content_response
      end)

      expect { fetch_content(ctx, out) }.to raise_error(Platform::InvariantViolation, /terminal decision lost/)
    end
  end
end
