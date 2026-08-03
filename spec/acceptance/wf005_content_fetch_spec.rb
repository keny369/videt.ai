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


  # ONE EXECUTION IS ONE ATTEMPT (DECISIONS ADR-089). `FetchContent#call` no longer loops and no longer
  # sleeps: it makes one attempt and REPORTS the :444 delay its caller owes. These helpers therefore split
  # in two — `fetch_content` for the many examples that are about a single attempt's outcome, and
  # `fetch_passes` for the retry schedule, which drives consecutive executions exactly as the run driver
  # drives consecutive `crawl_fetch_due` passes.
  def fetch_once(ctx, outbound, entry: nil, reserved: nil)
    Workflows::Wf005::FetchContent.new(outbound:).call(
      organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id],
      entry: entry || root_entry(ctx), gate_id: ctx[:gate_id], now: start_now, reserved_bytes: reserved)
  end

  def fetch_content(ctx, outbound, entry: nil) = fetch_once(ctx, outbound, entry:).result

  # Consecutive passes over ONE entry, stopping when :444 owes nothing more — the retry loop as it now
  # exists, with the waiting between passes belonging to the scheduler rather than to a worker. The gate is
  # advanced between passes because :442 paces host starts at one per second and each pass makes one.
  def fetch_passes(ctx, outbound, entry: nil, reserved: nil)
    target = entry || root_entry(ctx)
    carried = reserved
    [].tap do |passes|
      loop do
        execution = fetch_once(ctx, outbound, entry: target, reserved: carried)
        passes << execution
        break unless execution.retry_owed?

        carried = execution.remaining_reserved
        advance_gate(ctx)
      end
    end
  end

  def admit_next(ctx)
    Workflows::Wf005::Admission.new.claim_next(
      organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id], now: start_now
    )
  end

  def admitted_fetch_content(ctx, outbound)
    decision = admit_next(ctx)
    raise "expected an admitted entry" unless decision.admitted?

    execution = fetch_once(ctx, outbound, entry: decision.entry, reserved: decision.reserved_bytes)
    [decision, execution.result]
  end


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

  describe "when FetchContent consumes Admission's reservation" do
    it "uses the admitted reservation instead of taking a second run-wide reservation" do
      ctx = fetchable
      body = "<html>" + ("x" * 500) + "</html>"

      decision, result = admitted_fetch_content(ctx, content_outbound(content_response(body:)))

      expect(result.outcome).to eq("document_created")
      expect(requests.last[:byte_cap]).to eq(decision.reserved_bytes)
      expect(attempts(ctx[:crawl_id]).first["reserved_bytes"].to_i).to eq(decision.reserved_bytes)

      row = counters(ctx[:crawl_id])
      expect(row["committed_response_bytes"].to_i).to eq(body.bytesize)
      expect(row["reserved_response_bytes"].to_i).to eq(body.bytesize)
    end

    it "carries one reservation across retries and releases the remainder only at terminal settle" do
      ctx = fetchable
      first_body = "x" * 1024
      second_body = "<html>ok</html>"
      before_second_attempt = nil

      outbound = content_outbound(
        content_response(status: 500, body: first_body, byte_count: first_body.bytesize),
        lambda do |_url, **_kwargs|
          before_second_attempt = counters(ctx[:crawl_id]).slice(
            "reserved_response_bytes", "committed_response_bytes"
          )
          content_response(body: second_body)
        end
      )

      decision = admit_next(ctx)
      raise "expected an admitted entry" unless decision.admitted?

      # TWO PASSES, because one execution is one attempt (ADR-089). The reservation is what makes them one
      # admission: it is carried from the first pass's committed remainder into the second, exactly as the
      # run driver carries it across two `crawl_fetch_due` deliveries.
      passes = fetch_passes(ctx, outbound, entry: decision.entry, reserved: decision.reserved_bytes)
      result = passes.last.result

      expect(passes.size).to eq(2)
      expect(passes.first.retry_after_ms).to eq(30_000)
      expect(result.outcome).to eq("document_created")
      expect(before_second_attempt["reserved_response_bytes"].to_i).to eq(decision.reserved_bytes)
      expect(before_second_attempt["committed_response_bytes"].to_i).to eq(first_body.bytesize)
      expect(requests.map { |r| r[:byte_cap] }).to eq(
        [decision.reserved_bytes, decision.reserved_bytes - first_body.bytesize]
      )

      rows = attempts(ctx[:crawl_id])
      expect(rows.map { |r| r["reserved_bytes"].to_i }).to eq(
        [decision.reserved_bytes, decision.reserved_bytes - first_body.bytesize]
      )

      total = first_body.bytesize + second_body.bytesize
      row = counters(ctx[:crawl_id])
      expect(row["committed_response_bytes"].to_i).to eq(total)
      expect(row["reserved_response_bytes"].to_i).to eq(total)
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
      passes = fetch_passes(ctx, content_outbound(timeout))

      # THE BOUND IS UNCHANGED by moving the waiting to the scheduler: three attempts, no more, with the
      # number read from committed state on every pass so neither a redelivery nor a process loss resets it.
      expect(passes.size).to eq(Workflows::Wf005::FetchContent::MAX_ATTEMPTS)
      expect(passes.last.result.outcome).to eq("content_fetch_failed")
      rows = attempts(ctx[:crawl_id])
      expect(rows.size).to eq(Workflows::Wf005::FetchContent::MAX_ATTEMPTS)
      expect(rows.map { |r| r["attempt_number"].to_i }).to eq([1, 2, 3])
      # A record exists for every request that was made, including the ones that failed —
      # SEARCH_CRAWL_RETRIEVAL :82, "never replaced by an unaccounted request".
      expect(rows.map { |r| r["outcome"] }.uniq).to eq(["content_fetch_failed"])
    end

    it "owes :444's fixed schedule — 30s then 120s, then nothing — not an ad-hoc constant" do
      ctx = fetchable
      passes = fetch_passes(ctx, content_outbound(Platform::Outbound::Outcome.timeout(canonical_host: "shop.acme.example")))

      # EXACTLY two delays and then nil, asserted as the whole sequence rather than a prefix. :444 gives
      # one initial attempt plus at most two retries, so a third delay would precede no request — and a
      # prefix assertion is blind to it by construction, which is how a third delay once survived review.
      # This is the same contract the in-process loop used to satisfy by sleeping; the delay is now
      # REPORTED, and the scheduler waits it out. `retry_owed?` is what the driver branches on.
      expect(passes.map(&:retry_after_ms)).to eq([30_000, 120_000, nil])
      expect(passes.map(&:retry_owed?)).to eq([true, true, false])
      # And each delay is measured from the COMPLETION of the attempt that failed (:444), read back from
      # the committed row rather than from the executing worker's clock.
      expect(passes.first.completed_at).not_to be_nil
    end

    it "does not retry a nonretryable status" do
      ctx = fetchable
      execution = fetch_once(ctx, content_outbound(content_response(status: 403, body: "")))
      expect(execution.retry_owed?).to be(false)
      expect(attempts(ctx[:crawl_id]).size).to eq(1)
    end

    it "NOTHING SLEEPS: an execution that owes a retry returns without waiting it out" do
      # The defect ADR-089 removes. The in-process loop slept 30 s then 120 s, so one pass ran ~195 s
      # against the transport's 30-second worker lease with no heartbeat — the lease was recovered
      # mid-fetch and the ordinary retry path executed twice. A pass is now bounded by its single request.
      ctx = fetchable
      timeout = Platform::Outbound::Outcome.timeout(canonical_host: "shop.acme.example")

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      execution = fetch_once(ctx, content_outbound(timeout))
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - elapsed

      expect(execution.retry_after_ms).to eq(30_000)
      # Generous by three orders of magnitude against the 30 s it used to sleep: this asserts that the
      # delay was not taken, not that the database was fast.
      expect(elapsed).to be < 5.0
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

    it "PROOF 17 — nor is a hop refused because the LEASE MOVED (F-04 FU-24)" do
      # `Lease.redirect_guard` refuses the hop BEFORE the authorization limb runs, so `@guard_failed` is
      # false and F-01's `redirect_policy_denied` looked exactly like a scope denial. A review demonstrated
      # the consequence: a committed attempt row reading `policy_excluded / redirect_policy_denied /
      # retryable = f` for a URL nothing had refused — permanently outside :452's denominator, so coverage
      # reads better than reality, on a decision this delivery had no standing to make.
      ctx = fetchable
      keeper = dispatched_delivery(ctx[:g][:organization_id])
      denied = Platform::Outbound::Outcome.rejected(
        :redirect_policy_denied, canonical_host: "shop.acme.example", port: 443,
        final_url: "https://shop.acme.example/hop", redirect_count: 1)
      steal = -> { steal_delivery(keeper) }
      out = content_outbound(lambda do |_url, **kwargs|
        steal.call
        # The real guard, asked exactly as F-01 asks it — and it must now refuse.
        expect(kwargs[:redirect_guard].call(URI("https://shop.acme.example/hop"))).to be(false)
        denied
      end)

      result = Platform::ScheduledActions::Lease.with(keeper) { fetch_content(ctx, out) }

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

  # :442'S SECOND HALF — "INCOMPLETE REQUESTS ARE CANCELED" (FU-34; DECISIONS ADR-113).
  #
  # Only the first half of the sentence was implemented, and `Admission`'s own comment said so in
  # terms. The acceptance review's round 2 showed what the missing half cost: a request that spanned
  # the run's deadline could commit an immutable `document_created / covered` fact beside a Crawl the
  # terminal checkpoint had already recorded `failed`, with the entitlement released and coverage
  # NULL — and `f1_crawls_guard` refuses every correction.
  #
  # The cancellation is enforced at the REQUEST'S OWN BUDGET, through F-01's frozen façade, which
  # states that a caller "may ask for tighter, never wider". Nothing in F-01 changes and there is no
  # second path to the network.
  describe ":442's wall clock cancels an incomplete request (FU-34)" do
    # THE MONOTONIC SEAM IS SUPPLIED BY EVERY EXAMPLE HERE, and that is deliberate (R3-4).
    #
    # The budget is now computed from the instant the REQUEST starts, which is `now` plus the real
    # time the pass has already spent on robots and sitemap discovery. Left to the process clock that
    # elapsed time is however long this machine took — these examples measured 4.986s against an
    # expected 5s — so an exact assertion would be a flake and a loose one would stop measuring the
    # thing. Injecting the clock makes the elapsed time an INPUT, so a proof can state it exactly.
    #
    # `elapsed:` is the seconds that pass between `call` and the request. Zero is the old behaviour
    # and is what the boundary proofs want; a positive value is the defect R3-4 named.
    def monotonic_advancing_by(elapsed)
      readings = [0.0, elapsed.to_f]
      -> { readings.shift || elapsed.to_f }
    end

    def fetch_at(ctx, outbound, at:, elapsed: 0)
      Workflows::Wf005::FetchContent.new(outbound:, monotonic: monotonic_advancing_by(elapsed)).call(
        organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id],
        entry: root_entry(ctx), gate_id: ctx[:gate_id], now: at)
    end

    def deadline_of(ctx)
      Time.parse(DbInspector.one("SELECT deadline_at FROM crawls WHERE id=$1::uuid",
                                 [ctx[:crawl_id]])["deadline_at"]).getutc
    end

    # The run's clock is advanced the way production advances it — time passing, with :551's lease
    # renewed at its ratified cadence — never by writing `deadline_at` backwards, which FU-30 froze.
    def live_at(ctx, instant)
      age_run_to(ctx, instant)
      clear_rate_window(ctx[:gate_id])
      instant
    end

    it "PROOF 105 — the request is bounded by the run's remaining wall clock, not by the per-request ceiling" do
      ctx = fetchable
      at = live_at(ctx, deadline_of(ctx) - 5)

      fetch_at(ctx, content_outbound(timeout_outcome), at:)

      # :390's resolved per-request ceiling is 15 seconds; five remain. A caller may ask for tighter.
      # Exact, not `be_within`: the pass spends no measured time before the request in this example,
      # so five seconds is the whole of what remains and an approximation would hide the seconds
      # PROOF 121 is about.
      expect(requests.last[:timeout_s]).to eq(5)
      expect(requests.last[:timeout_s]).to be < Workflows::Wf005::ByteAccounting::GLOBAL_BOUNDS.timeout_s
    end

    # R3-4's SECOND HALF, AND THE ONE THAT WAS NOT IMPLEMENTED. ADR-113 computed the budget from
    # `context[:now]` — the pass's DELIVERY instant, fixed once in `call`. By the time the content
    # request is made, that same pass has already fetched robots and attempted sitemap discovery, both
    # real network calls, so the elapsed time between the two instants is real and unbounded by
    # anything here. Computing "how much of the run is left" from the earlier instant OVERSTATES it by
    # exactly that much, and the request the deadline exists to bound is handed a budget that runs
    # past `deadline_at`.
    #
    # The remaining half of R3-4 — F-01 re-arming `timeout_s` per REDIRECT HOP, measured at 11.1x
    # overrun — cannot be repaired here: `app/platform/outbound/` is a frozen foundation and the
    # repository's own classifier makes any edit to it a mandatory human escalation. It is recorded
    # as FU-43 and is NOT claimed closed by this example.
    it "PROOF 121 — the budget is measured from when the REQUEST starts, not from when the pass arrived" do
      ctx = fetchable
      at = live_at(ctx, deadline_of(ctx) - 5)

      # Three of the five remaining seconds are spent inside the pass, before the content request.
      fetch_at(ctx, content_outbound(timeout_outcome), at:, elapsed: 3)

      # Two seconds remain to the run, so two seconds is what the request may have. Against the
      # delivery instant this reads 5 — a request permitted to run three seconds past `deadline_at`.
      expect(requests.last[:timeout_s]).to eq(2)
    end

    # R4-5. PROOF 121 and 122 construct `FetchContent` DIRECTLY, so the clock they inject starts at
    # `FetchContent#call`. A real pass does not: `CrawlDriver#advance` reads `now` once and then runs
    # `EnsureRobots` and `DiscoverSitemaps` — two network calls — before the content request. R3-4(b)
    # anchored at `FetchContent#call`, which is AFTER all of that, so the elapsed time the repair exists
    # to measure was still invisible and a mutation inserting thirty seconds of robots work left every
    # proof green.
    #
    # This drives the WHOLE PASS through the registered handler, which is the path production uses.
    it "PROOF 130 — time the PASS spent before the request comes out of the request's budget" do
      ctx = fetchable
      # Sitemap discovery resolved too, so the pass reaches its CONTENT request. This spec's `fetchable`
      # resolves robots only, and an unresolved sitemap gate makes the driver re-enter discovery instead
      # of fetching — which is correct behaviour and not the property under test.
      resolve_sitemaps(ctx, outbound_returning(response(status: 404, body: "")))
      at = live_at(ctx, deadline_of(ctx) - 5)

      # Linked in its own transaction and read back AFTER it commits — `DbInspector` holds a separate
      # connection and cannot see rows still inside the unit of work.
      action_id = Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
        IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg)
                                                          .enter_org_context(org: ctx[:g][:organization_id],
                                                                             correlation_id: SecureRandom.uuid_v7)
        Workflows::Wf005::CrawlFetchDueSchedule.link_next(
          pg:, organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
          crawl_id: ctx[:crawl_id], now: at, correlation_id: SecureRandom.uuid_v7
        )[:action_id]
      end
      action = DbInspector.one("SELECT * FROM scheduled_actions WHERE id = $1::uuid", [action_id])
      expect(action).not_to be_nil, "the pass was never linked, so this example would prove nothing"

      # Five seconds remain to the run. The pass spends three of them on robots and discovery before it
      # reaches the content request; the clock is an input so the example states that exactly.
      readings = [0.0, 3.0]
      advancing = -> { readings.shift || 3.0 }

      Workflows::Wf005::Handlers::RecordFetchAttempt.new.call(
        command: Workflows::Wf005::Commands::RecordFetchAttempt.new(
          command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
          organization_id: action["organization_id"], target_type: action["target_type"],
          frontier_entry_id: action["target_id"], due_at: Time.parse(action["due_at"]).getutc,
          action_id: action["id"],
          action_identity_sha256: [action["identity_sha256"].sub(/\A\\x/, "")].pack("H*"),
          requested_at_utc: at
        ),
        request_context: executor_ctx(at),
        outbound: content_outbound(timeout_outcome), pacer: pacer_for(ctx), monotonic: advancing
      )

      # THE CONTENT REQUEST SPECIFICALLY. The driver hands this one stub to robots, sitemap discovery
      # and the content fetch alike, so `requests.last` is whichever ran last — the sitemap probe, at
      # the unbounded ceiling. Selecting by URL is what makes this assertion about the fetch.
      content = requests.select { |r| URI.parse(r[:url].to_s).path == "/" }
      expect(content).not_to be_empty, "no content request was made; saw #{requests.map { |r| r[:url] }.inspect}"

      # Two seconds of the run remain when the request starts, so two seconds is what it may have.
      # Anchored at `FetchContent#call` this reads 5 — a request permitted to run three seconds past
      # `deadline_at`, against the customer's site, on a run that is over.
      expect(content.last[:timeout_s]).to eq(2)
    end

    it "PROOF 122 — a pass whose earlier work consumed the whole run makes no request at all" do
      # The same arithmetic at its limit. `budget.expired?` is what stops the request, and against the
      # delivery instant it CANNOT fire while `now` is before the deadline, however long the pass has
      # since spent: the run is over, and a request would still go out.
      ctx = fetchable
      at = live_at(ctx, deadline_of(ctx) - 5)

      execution = fetch_at(ctx, content_outbound(content_response), at:, elapsed: 6)

      expect(requests).to be_empty
      expect(execution.result.outcome).to eq(Workflows::Wf005::FetchContent::LIMIT_DISCARDED)
      expect(execution.result.reason_code).to eq(Workflows::Wf005::Admission::WALL_CLOCK)
      expect(execution.result.retryable).to be(false)
    end

    it "PROOF 106 — a request still in flight at the boundary is CANCELLED, and is not a failure of the URL" do
      # :452 classifies an exhausted timeout as `content_fetch_failed` — a failure of the URL, in the
      # denominator, and RETRYABLE. A request the run's own sixty minutes ended is a different fact:
      # :458's "in-scope candidate NOT EVALUATED because of … wall-clock bound", which is
      # `limit_discarded` carrying "its exact limit reason", and :442's "stop scheduling affected
      # work" means no retry is owed. Filing one as the other blames the site for the run's clock.
      ctx = fetchable
      at = live_at(ctx, deadline_of(ctx) - 5)

      execution = fetch_at(ctx, content_outbound(timeout_outcome), at:)

      expect(execution.result.outcome).to eq(Workflows::Wf005::FetchContent::LIMIT_DISCARDED)
      expect(execution.result.reason_code).to eq(Workflows::Wf005::Admission::WALL_CLOCK)
      expect(execution.result.retryable).to be(false)
      expect(execution.retry_owed?).to be(false)
      # The token is ONE token: the run's clock refusing to start a request and the run's clock ending
      # one are the same fact, and :454 asks for one exact limit reason.
      expect(Workflows::Wf005::FetchContent::REASONS[:wall_clock])
        .to eq(Workflows::Wf005::Admission::WALL_CLOCK)
    end

    it "PROOF 107 — a request that COMPLETED inside the boundary is not cancelled" do
      # The other side of the same instant, and the one that keeps the repair a boundary rather than
      # "requests near the end of a run do not count". :442 cancels INCOMPLETE requests; a response
      # that arrived is complete, and a run's last seconds are ordinary working seconds.
      ctx = fetchable
      at = live_at(ctx, deadline_of(ctx) - 5)

      execution = fetch_at(ctx, content_outbound(content_response), at:)

      expect(requests.last[:timeout_s]).to eq(5)
      expect(execution.result.outcome).to eq(Workflows::Wf005::FetchContent::DOCUMENT_CREATED)
      expect(execution.result.reason_code).to be_nil
      expect(execution.result.http_status).to eq(200)
    end

    it "PROOF 108 — past the boundary NO REQUEST IS MADE AT ALL, and the outcome says why" do
      # ":442 — At 60 elapsed minutes, NO NEW REQUEST STARTS." `CrawlDriver#advance` and
      # `Admission#authorize_run` both refuse before this, so reaching here is a race — and the honest
      # answer to a race is not to make the request.
      #
      # THE INSTRUMENT HAD TO BE REPAIRED BEFORE THIS PROOF MEANT ANYTHING (round 3, R3-8). It used a
      # bespoke stub that never touched `requests`, so `expect(requests).to be_empty` was empty BY
      # CONSTRUCTION and passed under every mutation. Its stated backup — "the stub RAISES if it is
      # called, so this cannot pass by returning a convenient outcome" — was false too: `FetchContent#
      # fetch` wraps the call in `rescue StandardError`, so the raise was swallowed and reclassified.
      # Mutating `fetch` to issue the request past the deadline while still returning the timeout
      # outcome (what a real connector does on a non-positive budget) left this GREEN. That matters
      # concretely: `Ceilings.clamp_positive` returns the platform MAXIMUM for a value <= 0, so a lost
      # `expired?` guard means a full-ceiling request against the customer's site on a run that is over.
      #
      # It now records through the same sink every other example uses, so "no request" is asserted by
      # an instrument that would have SEEN one.
      ctx = fetchable
      at = live_at(ctx, deadline_of(ctx) + 1)
      sink = requests
      refusing = Object.new.tap do |o|
        o.define_singleton_method(:fetch) do |url, **kwargs|
          sink << kwargs.merge(url:)
          raise "a request was made past the wall clock: #{url}"
        end
      end

      execution = fetch_at(ctx, refusing, at:)

      expect(execution.result.outcome).to eq(Workflows::Wf005::FetchContent::LIMIT_DISCARDED)
      expect(execution.result.reason_code).to eq(Workflows::Wf005::Admission::WALL_CLOCK)
      expect(requests).to be_empty
    end

    it "PROOF 109 — an ORDINARY timeout inside the run's clock is still `content_fetch_failed`" do
      # The conjunct that keeps the two apart. Without it every timeout would become a wall-clock
      # cancellation, which removes :452's retryable failure from the vocabulary entirely and hides a
      # genuinely unreachable site behind the run's clock.
      ctx = fetchable

      execution = fetch_once(ctx, content_outbound(timeout_outcome))

      expect(requests.last[:timeout_s]).to eq(Workflows::Wf005::ByteAccounting::GLOBAL_BOUNDS.timeout_s)
      expect(execution.result.outcome).to eq(Workflows::Wf005::FetchContent::FETCH_FAILED)
      expect(execution.result.retryable).to be(true)
    end
  end
end
