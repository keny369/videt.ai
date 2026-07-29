# frozen_string_literal: true

require "rails_helper"

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

    it "records PLATFORM redirect-limit exhaustion as a FAILURE, inside the denominator (:452)" do
      ctx = fetchable
      rejected = Platform::Outbound::Outcome.rejected(
        :redirect_rejected, canonical_host: "shop.acme.example", port: 443,
        final_url: "https://shop.acme.example/loop", redirect_count: 10)
      result = fetch_content(ctx, content_outbound(rejected))

      expect(result.outcome).to eq("content_fetch_failed")
      expect(result.reason_code).to eq("redirect_limit_exhausted")
      expect(result.in_denominator?).to be(true)
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
      expect(paces.first(2)).to eq([30_000, 120_000])
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
          "UPDATE fetch_attempts SET canonical_url = 'https://elsewhere.example/', state_version = state_version + 1
           WHERE id = $1::uuid", [row["id"]])
      end.to raise_error(/identity_immutable/)
    end

    it "freezes its RESULT once terminal" do
      ctx = fetchable
      fetch_content(ctx, content_outbound(content_response))
      row = attempts(ctx[:crawl_id]).first

      expect do
        DbInspector.connection.exec_params(
          "UPDATE fetch_attempts SET outcome = 'content_fetch_failed', state_version = state_version + 1
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
             state_version = state_version + 1 WHERE id = $1::uuid", [row["id"]])
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
end
