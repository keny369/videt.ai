# frozen_string_literal: true

require "rails_helper"

# WF-005 host gate + robots (fail-closed) + per-host rate + EXECUTION-TIME AUTHORIZATION
# (S-07-005; WORKFLOW_SPECIFICATIONS.md :442/:444/:448; SEARCH_CRAWL_RETRIEVAL.md § Robots And
# Sitemap Processing and the run/per-host gate paragraph; contracts/S-07.json MTX-030
# authorization_entry_point).
#
# Exercised over the PRODUCTION-REAL chain: genesis -> registered + verified + activated Source ->
# ActivateProject -> QueueCrawl -> StartCrawl (which seeds the frontier). The outbound surface is
# the ONLY thing stubbed, and it is stubbed at the frozen F-01 façade rather than inside the service.
RSpec.describe "WF-005 host gate and robots", type: :acceptance,
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

  # ---------------------------------------------------------------------------

  describe "the canonical host gate" do
    it "creates exactly one gate per (crawl, canonical host) and is idempotent" do
      ctx = running_crawl
      2.times { ensure_gate(ctx) }
      rows = DbInspector.all("SELECT * FROM crawl_host_gates WHERE crawl_id = $1::uuid", [ctx[:crawl_id]])
      expect(rows.size).to eq(1)
      expect(rows.first["canonical_host"]).to eq(ctx[:host])
      expect(rows.first["robots_state"]).to eq("pending")
      expect(rows.first["active_connection_count"]).to eq("0")
      # The digest is the unique key; the plaintext host is retained beside it for audit.
      expect(rows.first["canonical_host_sha256"].sub(/\A\\x/, "")).to eq(Digest::SHA256.hexdigest(ctx[:host]))
    end

    it "blocks CONTENT dispatch until the robots record is terminal" do
      ctx = running_crawl
      ensure_gate(ctx)
      decision = in_gate(ctx[:g][:organization_id]) do |store, gate|
        gate.claim(organization_id: ctx[:g][:organization_id], now: start_now,
                   gate_id: store.gate(ctx[:g][:organization_id], ctx[:crawl_id], ctx[:host])["id"])
      end
      expect(decision.granted?).to be(false)
      expect(decision.reason_code).to eq("robots_not_resolved")
    end

    it "admits the ROBOTS fetch itself while the record is unresolved" do
      ctx = running_crawl
      ensure_gate(ctx)
      decision = in_gate(ctx[:g][:organization_id]) do |store, gate|
        gate.claim(organization_id: ctx[:g][:organization_id], kind: "robots", now: start_now,
                   gate_id: store.gate(ctx[:g][:organization_id], ctx[:crawl_id], ctx[:host])["id"])
      end
      expect(decision.granted?).to be(true)
      expect(gate_row(ctx[:crawl_id])["active_connection_count"]).to eq("1")
    end
  end

  describe "per-host rate and concurrency (deterministic, ceilings nonexceedable)" do
    def claim(ctx, gate_id, store, gate) = gate.claim(organization_id: ctx[:g][:organization_id], gate_id:, now: start_now, kind: "robots")

    it "refuses a second start inside the rolling one-second window (target 1/sec)" do
      ctx = running_crawl
      ensure_gate(ctx)
      first, second = in_gate(ctx[:g][:organization_id]) do |store, gate|
        id = store.gate(ctx[:g][:organization_id], ctx[:crawl_id], ctx[:host])["id"]
        [claim(ctx, id, store, gate), claim(ctx, id, store, gate)]
      end
      expect(first.granted?).to be(true)
      expect(second.granted?).to be(false)
      expect(second.reason_code).to eq("host_rate_limited")
      expect(second.retry_after_ms).to be_positive
    end

    it "refuses beyond the concurrency target and never reaches the ceiling" do
      ctx = running_crawl
      ensure_gate(ctx)
      # Drive the live connection count to the target without consuming the rate window.
      id = gate_row(ctx[:crawl_id])["id"]
      seed_leases(id, Workflows::Wf005::HostGate::CONCURRENCY_TARGET)
      decision = in_gate(ctx[:g][:organization_id]) { |s, gate| claim(ctx, id, s, gate) }
      expect(decision.granted?).to be(false)
      expect(decision.reason_code).to eq("host_concurrency_limited")
      expect(Workflows::Wf005::HostGate::CONCURRENCY_TARGET).to be < Workflows::Wf005::HostGate::CONCURRENCY_CEILING
    end

    it "asserts the nonexceedable ceilings ahead of the scheduling targets" do
      ctx = running_crawl
      ensure_gate(ctx)
      id = gate_row(ctx[:crawl_id])["id"]
      seed_leases(id, Workflows::Wf005::HostGate::CONCURRENCY_CEILING)
      decision = in_gate(ctx[:g][:organization_id]) { |s, gate| claim(ctx, id, s, gate) }
      expect(decision.reason_code).to eq("host_concurrency_ceiling")
    end

    it "releases exactly the slot a token holds, and a repeated release is a no-op" do
      # The review's defect: an unguarded release let one worker drop a slot it did not hold, and
      # GREATEST(count-1,0) turned that into a SILENTLY WIDENED nonexceedable ceiling.
      ctx = running_crawl
      ensure_gate(ctx)
      id = gate_row(ctx[:crawl_id])["id"]
      first = in_gate(ctx[:g][:organization_id]) { |s, gate| claim(ctx, id, s, gate) }
      # A second live claim, made possible by clearing only the rate window.
      clear_rate_window(id)
      second = in_gate(ctx[:g][:organization_id]) { |s, gate| claim(ctx, id, s, gate) }
      expect([first.granted?, second.granted?]).to eq([true, true])
      expect(first.lease_token).not_to eq(second.lease_token)
      expect(gate_row(ctx[:crawl_id])["active_connection_count"]).to eq("2")

      # Releasing the FIRST claim three times drops exactly one slot — the second holder keeps its own.
      3.times do
        in_gate(ctx[:g][:organization_id]) { |_s, gate| gate.release(gate_id: id, lease_token: first.lease_token, now: start_now) }
      end
      expect(gate_row(ctx[:crawl_id])["active_connection_count"]).to eq("1")
      in_gate(ctx[:g][:organization_id]) { |_s, gate| gate.release(gate_id: id, lease_token: second.lease_token, now: start_now) }
      expect(gate_row(ctx[:crawl_id])["active_connection_count"]).to eq("0")
    end

    it "RECLAIMS a slot lost with its worker, instead of closing the host for the rest of the run" do
      # SEARCH_CRAWL_RETRIEVAL :82 — "Process loss after claim is repaired by the lease sweeper".
      # Without reclamation, two lost workers sat the host at its concurrency target and every later
      # claim was refused, which :452 turns into content_fetch_failed and partial coverage.
      ctx = running_crawl
      ensure_gate(ctx)
      id = gate_row(ctx[:crawl_id])["id"]
      in_gate(ctx[:g][:organization_id]) { |s, gate| claim(ctx, id, s, gate) }
      clear_rate_window(id)
      in_gate(ctx[:g][:organization_id]) { |s, gate| claim(ctx, id, s, gate) }
      expect(gate_row(ctx[:crawl_id])["active_connection_count"]).to eq("2")

      # Both workers vanish. A later claim, past the stale bound, repairs the accounting itself.
      later = start_now + IdentityAccess::Infrastructure::CrawlHostGateStore::LEASE_STALE_SECONDS + 60
      swept = in_gate(ctx[:g][:organization_id]) { |_s, gate| gate.sweep(gate_id: id, now: later) }
      expect(swept["active_connection_count"].to_i).to eq(0)

      clear_rate_window(id)
      revived = in_gate(ctx[:g][:organization_id]) do |_s, gate|
        gate.claim(organization_id: ctx[:g][:organization_id], gate_id: id, now: later, kind: "robots")
      end
      expect(revived.granted?).to be(true)
    end

    it "keeps the derived connection count and the lease set in agreement at the database" do
      ctx = running_crawl
      ensure_gate(ctx)
      id = gate_row(ctx[:crawl_id])["id"]
      in_gate(ctx[:g][:organization_id]) { |s, gate| claim(ctx, id, s, gate) }
      expect { DbInspector.connection.exec_params(
        "UPDATE crawl_host_gates SET active_connection_count = 0, state_version = state_version + 1 WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::CheckViolation, /crawl_host_gates_lease_count_agrees/)
    end

    it "honours a robots crawl-delay as a floor on the next permitted start" do
      ctx = running_crawl
      ensure_gate(ctx)
      resolve_robots(ctx, outbound_returning(response(status: 200, body: "User-agent: *\nCrawl-delay: 30\n")))
      id = gate_row(ctx[:crawl_id])["id"]
      in_gate(ctx[:g][:organization_id]) do |store, gate|
        gate.claim(organization_id: ctx[:g][:organization_id], gate_id: id, now: start_now)
      end
      row = gate_row(ctx[:crawl_id])
      # 30s delay pushes the next permitted start far beyond the 1s policy interval.
      expect(Time.parse(row["next_allowed_start_at"]) - Time.parse(row["updated_at"])).to be > 25
      expect(row["robots_crawl_delay_ms"]).to eq("30000")
    end
  end

  describe "robots resolution, fail-closed (:448)" do
    def resolve(ctx, outcome) = resolve_robots(ctx, outbound_returning(outcome))

    it "applies parsed rules on a valid 2xx body and records the source digest" do
      ctx = running_crawl
      ensure_gate(ctx)
      body = "User-agent: *\nDisallow: /private\nSitemap: https://shop.acme.example/sitemap.xml\n"
      result = resolve(ctx, response(status: 200, body:))
      expect(result.state).to eq("rules_applied")
      expect(result.terminal?).to be(true)

      row = gate_row(ctx[:crawl_id])
      expect(row["robots_agent_group"]).to eq("*")
      expect(JSON.parse(row["robots_sitemap_candidates"])).to eq(["https://shop.acme.example/sitemap.xml"])
      expect(row["robots_source_sha256"].sub(/\A\\x/, "")).to eq(Digest::SHA256.hexdigest(body))
      expect(row["robots_rules_schema"]).to eq("robots-rules-v1")
      expect(row["robots_terminal_at"]).to be_present
    end

    # One example per status: each needs its own bootstrapped tenant, and the identity is memoized
    # per example.
    [404, 410].each do |status|
      it "treats #{status} as NO RESTRICTIONS" do
        ctx = running_crawl
        ensure_gate(ctx)
        expect(resolve(ctx, response(status:)).state).to eq("no_restrictions")
        expect(gate_row(ctx[:crawl_id])["robots_terminal_reason"]).to eq("robots_absent")
      end
    end

    [401, 403].each do |status|
      it "FAILS CLOSED on #{status}" do
        ctx = running_crawl
        ensure_gate(ctx)
        result = resolve(ctx, response(status:))
        expect(result.state).to eq("unavailable")
        expect(result.reason_code).to eq("robots_unavailable_fail_closed")
      end
    end

    it "FAILS CLOSED on a body over 1 MiB" do
      ctx = running_crawl
      ensure_gate(ctx)
      oversize = "a" * (Workflows::Wf005::RobotsPolicy::MAX_BODY_BYTES + 1)
      expect(resolve(ctx, response(status: 200, body: oversize)).state).to eq("unavailable")
    end

    it "FAILS CLOSED on an unexpected status rather than reading it as permission" do
      ctx = running_crawl
      ensure_gate(ctx)
      expect(resolve(ctx, response(status: 418)).state).to eq("unavailable")
    end

    it "RETRIES a timeout under the fixed schedule, then fails closed on exhaustion" do
      ctx = running_crawl
      ensure_gate(ctx)
      out = outbound_returning(timeout_outcome)
      results = Array.new(Workflows::Wf005::EnsureRobots::MAX_ATTEMPTS) { resolve_robots(ctx, out) }
      expect(results[0..-2].map(&:terminal?)).to all(be(false))
      expect(results[0].retryable).to be(true)
      expect(results.last.state).to eq("unavailable")
      expect(results.last.reason_code).to eq("robots_unavailable_fail_closed")
      expect(gate_row(ctx[:crawl_id])["robots_attempt_count"]).to eq(Workflows::Wf005::EnsureRobots::MAX_ATTEMPTS.to_s)
    end

    it "applies the :444 retry DELAYS — 30s after the first failure, 120s after the second" do
      ctx = running_crawl
      ensure_gate(ctx)
      out = outbound_returning(timeout_outcome)
      first = resolve_robots(ctx, out)
      second = resolve_robots(ctx, out)
      expect(first.retry_after_ms).to eq(30_000)
      expect(second.retry_after_ms).to eq(120_000)
    end

    # :444 — "A valid integer `Retry-After` from 1 through 120 seconds replaces that retry's delay;
    # every other value is ignored." One example per value: each needs its own bootstrapped tenant.
    { "45" => 45_000, "120" => 120_000, "1" => 1000 }.each do |header, expected|
      it "lets Retry-After: #{header} REPLACE the schedule delay" do
        ctx = running_crawl
        ensure_gate(ctx)
        result = resolve_robots(ctx, outbound_returning(response(status: 503, headers: { "Retry-After" => header })))
        expect(result.retry_after_ms).to eq(expected)
      end
    end

    %w[0 121 soon -5].each do |header|
      it "ignores Retry-After: #{header} and keeps the fixed 30s schedule" do
        ctx = running_crawl
        ensure_gate(ctx)
        result = resolve_robots(ctx, outbound_returning(response(status: 503, headers: { "Retry-After" => header })))
        expect(result.retry_after_ms).to eq(30_000)
      end
    end

    it "performs the network fetch OUTSIDE any database transaction" do
      # MTX-030 transaction_boundary — "No external call sits inside a database transaction." A robots
      # fetch can block for the full request timeout; holding the gate's row lock across it would
      # stall every other worker on that host.
      ctx = running_crawl
      ensure_gate(ctx)
      observed = nil
      probe = Object.new.tap do |o|
        o.define_singleton_method(:fetch) do |*_a, **_k|
          observed = ActiveRecord::Base.connection.transaction_open?
          Platform::Outbound::Outcome.response(status: 200, headers: {}, body: "User-agent: *\nDisallow: /x\n",
                                               byte_count: 30, truncated: false, canonical_host: "shop.acme.example",
                                               port: 443, pinned_address: "198.51.100.7",
                                               final_url: "https://shop.acme.example/robots.txt",
                                               redirect_count: 0, latency_ms: 1)
        end
      end
      resolve_robots(ctx, probe)
      expect(observed).to be(false)
      expect(gate_row(ctx[:crawl_id])["robots_state"]).to eq("rules_applied")
    end

    it "is DETERMINISTIC: a second resolve returns the frozen decision without re-fetching" do
      ctx = running_crawl
      ensure_gate(ctx)
      resolve(ctx, response(status: 403))
      # An outbound that would raise if called proves the second resolve performs no network work.
      exploding = Object.new.tap { |o| o.define_singleton_method(:fetch) { |*_a, **_k| raise "must not refetch" } }
      again = resolve_robots(ctx, exploding)
      expect(again.state).to eq("unavailable")
      expect(again.terminal?).to be(true)
      expect(gate_row(ctx[:crawl_id])["robots_attempt_count"]).to eq("1")
    end

    it "makes the terminal robots decision WRITE-ONCE at the database" do
      ctx = running_crawl
      ensure_gate(ctx)
      resolve(ctx, response(status: 403))
      id = gate_row(ctx[:crawl_id])["id"]
      expect {
        DbInspector.connection.exec_params(
          "UPDATE crawl_host_gates SET robots_state='no_restrictions', state_version=state_version+1 WHERE id=$1::uuid", [id])
      }.to raise_error(PG::RaiseException, /crawl_host_gate_robots_decision_frozen/)
    end

    it "blocks every content claim on the host for the rest of the run once it has failed closed" do
      ctx = running_crawl
      ensure_gate(ctx)
      resolve(ctx, response(status: 403))
      decision = in_gate(ctx[:g][:organization_id]) do |store, gate|
        gate.claim(organization_id: ctx[:g][:organization_id], now: start_now,
                   gate_id: store.gate(ctx[:g][:organization_id], ctx[:crawl_id], ctx[:host])["id"])
      end
      expect(decision.granted?).to be(false)
      expect(decision.reason_code).to eq("robots_unavailable_fail_closed")
    end
  end

  describe "EXECUTION-TIME authorization before every fetch" do
    def allowed_ctx
      ctx = running_crawl
      ensure_gate(ctx)
      resolve_robots(ctx, outbound_returning(response(status: 200, body: "User-agent: *\nDisallow: /private\n")))
      ctx
    end

    it "allows a URL that passes every current check" do
      verdict = authorize(allowed_ctx, url: "https://shop.acme.example/public")
      expect(verdict.reason_code).to be_nil
      expect(verdict.allowed?).to be(true)
      expect(verdict.scope_policy_id).to be_present
    end

    it "REFUSES a URL whose Source was disabled after queueing" do
      ctx = allowed_ctx
      expect(disable_source(ctx[:g], ctx[:source_id]).success?).to be(true)
      verdict = authorize(ctx, url: "https://shop.acme.example/public")
      expect(verdict.allowed?).to be(false)
      expect(verdict.reason_code).to eq("fetch_source_not_active")
    end

    it "REFUSES a URL whose Source was removed after queueing" do
      ctx = allowed_ctx
      expect(disable_source(ctx[:g], ctx[:source_id]).success?).to be(true)
      Workflows::Wf004::Handlers::RemoveSource.new.call(
        command: Workflows::Wf004::Commands::RemoveSource.new(command_id: SecureRandom.uuid_v7, idempotency_key: "rm-#{SecureRandom.hex(6)}",
          schema_version: "1.0", session_id: ctx[:g][:session_id], organization_id: ctx[:g][:organization_id],
          project_id: ctx[:g][:project_id], source_id: ctx[:source_id],
          expected_state_version: source_row(ctx[:source_id])["state_version"].to_i,
          lifecycle_reason: "owner_requested_removal", requested_at_utc: act_now), request_context: act_ctx)
      expect(authorize(ctx, url: "https://shop.acme.example/public").reason_code).to eq("fetch_source_not_active")
    end

    it "REFUSES every fetch once the Organization is suspended" do
      ctx = allowed_ctx
      expect(suspend_organization(ctx[:g]).success?).to be(true)
      verdict = authorize(ctx, url: "https://shop.acme.example/public")
      expect(verdict.allowed?).to be(false)
      expect(verdict.reason_code).to eq("fetch_organization_inactive")
    end

    it "REFUSES a URL outside the CURRENT restrictive scope" do
      ctx = allowed_ctx
      expect(authorize(ctx, url: "https://other.example/x").reason_code).to eq("fetch_url_out_of_scope")
    end

    it "REFUSES a URL robots disallows, without touching the Source" do
      ctx = allowed_ctx
      expect(authorize(ctx, url: "https://shop.acme.example/private/x").reason_code).to eq("fetch_robots_disallowed")
      expect(authorize(ctx, url: "https://shop.acme.example/public").allowed?).to be(true)
    end

    it "distinguishes robots UNRESOLVED (retryable) from robots FAILED CLOSED (terminal)" do
      ctx = running_crawl
      ensure_gate(ctx)
      # Still in flight: a SCHEDULING condition. Collapsing it into the fail-closed reason would
      # terminally fail URLs on hosts seconds from resolving, and :452 makes fail-closed a FAILED
      # Source root with partial coverage — a penalty this host has not earned.
      unresolved = authorize(ctx)
      expect(unresolved.reason_code).to eq("fetch_robots_not_resolved")
      expect(unresolved.retryable?).to be(true)

      resolve_robots(ctx, outbound_returning(response(status: 403)))
      failed = authorize(ctx)
      expect(failed.reason_code).to eq("fetch_robots_unavailable")
      expect(failed.retryable?).to be(false)
    end

    it "exempts ONLY the host's own robots.txt from robots, never an arbitrary URL" do
      # The exemption exists so a host can be resolved at all. Unbounded, `kind: "robots"` would
      # authorize any URL on a host that had already failed closed — the whole gate undone by a
      # caller-supplied string.
      ctx = running_crawl
      ensure_gate(ctx)
      resolve_robots(ctx, outbound_returning(response(status: 403)))
      expect(authorize(ctx, kind: "robots", url: "https://#{ctx[:host]}/robots.txt").allowed?).to be(true)
      expect(authorize(ctx, kind: "robots", url: "https://#{ctx[:host]}/").reason_code)
        .to eq("fetch_robots_disallowed")
      expect(authorize(ctx, kind: "robots", url: "https://#{ctx[:host]}/private/secret").reason_code)
        .to eq("fetch_robots_disallowed")
    end

    it "applies robots to the NORMALIZED path, so percent-encoding and dot segments cannot bypass it" do
      # The scope predicate percent-decodes unreserved octets and removes dot segments. Judging scope
      # on the normalized path and robots on the raw one would let either spelling walk past a
      # `Disallow: /private` — no caller mistake required.
      ctx = allowed_ctx
      %w[
        https://shop.acme.example/private/secret
        https://shop.acme.example/%70rivate/secret
        https://shop.acme.example/a/../private/secret
        https://shop.acme.example/./private/secret
      ].each do |url|
        expect(authorize(ctx, url:).reason_code).to eq("fetch_robots_disallowed"), url
      end
    end

    it "refuses a gate belonging to another host, Crawl or Organization" do
      ctx = allowed_ctx
      foreign = { "organization_id" => ctx[:g][:organization_id], "crawl_id" => ctx[:crawl_id],
                  "canonical_host" => "cdn.other.example", "robots_state" => "no_restrictions",
                  "robots_rules" => nil }
      verdict = in_gate(ctx[:g][:organization_id]) do |store, _gate|
        Workflows::Wf005::FetchAuthorization.new(store).authorize(
          organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id], source_id: ctx[:source_id],
          canonical_url: "https://shop.acme.example/private/secret", gate: foreign, now: start_now)
      end
      # A permissive gate for a DIFFERENT host must not license this URL.
      expect(verdict.allowed?).to be(false)
      expect(verdict.reason_code).to eq("fetch_robots_not_resolved")
    end

    it "refuses a Source belonging to another Project of the same Organization" do
      # POSTGRESQL_SCHEMA :128's rule expressed in the read path, where no FK can enforce it: a Crawl
      # in one Project must never be authorized against another Project's Source — or, worse, that
      # Source's scope policy, which would silently substitute a different scope for this run.
      ctx = allowed_ctx
      other_project = DbInspector.one(<<~SQL, [ctx[:g][:organization_id]])["id"]
        INSERT INTO projects
          (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
           display_name, locale, time_zone, objective, state, source_set_version)
        VALUES (gen_random_uuid(),0,0,now(),now(),gen_random_uuid(),$1::uuid,
                'Second','en-AU','UTC','discoverability_assessment','draft',0)
        RETURNING id
      SQL
      foreign_source = DbInspector.one(<<~SQL, [ctx[:g][:organization_id], other_project])["id"]
        INSERT INTO sources
          (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id,
           submitted_root_uri, canonical_root_uri, canonical_host, registration_schema_version,
           host_normalization_version, registration_origin, registering_account_id,
           registration_command_id, registration_idempotency_key_digest,
           registration_authorization_decision_id, registered_at, state)
        VALUES (gen_random_uuid(),0,now(),now(),gen_random_uuid(),$1::uuid,$2::uuid,
                'https://shop.acme.example','https://shop.acme.example/','shop.acme.example',
                'source-registration-v1','ascii-host-v1','human_command',gen_random_uuid(),
                gen_random_uuid(),sha256('k'),gen_random_uuid(),now(),'active')
        RETURNING id
      SQL

      verdict = authorize(ctx, url: "https://shop.acme.example/public", source_id: foreign_source)
      expect(verdict.allowed?).to be(false)
      expect(verdict.reason_code).to eq("fetch_source_not_active")
    end
  end
end
