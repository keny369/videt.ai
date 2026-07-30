# frozen_string_literal: true

# The production-real WF-005 chain, shared by every S-07 acceptance spec.
#
# Extracted in S-07-008 because it had been copied verbatim into three spec files, and the ADR-026
# architecture lens was right that the copies were already drifting: the sitemap spec's helpers were
# reachable from the content-fetch spec where nothing called them, which is why its host-gate
# deferral path went untested. CLAUDE.md's standard is one canonical source of truth, and that
# applies to test scaffolding too — a harness that disagrees with itself makes tests that disagree
# about what the system does.
#
# Nothing here is a double. It bootstraps a real Organization, registers and verifies and activates
# a real Source, activates the Project, queues a Crawl and starts it through the real handler. Only
# the outbound surface is ever stubbed, and only at the frozen F-01 facade.
module Wf005CrawlChain
  def fixed_now = Time.utc(2026, 7, 27, 10, 0, 0)
  def act_now = fixed_now + 60
  def start_now = act_now + 30
  def bc = Platform::BaselineContent

  # Memoized per EXAMPLE, not per call: one bootstrap needs the same identity throughout, and two
  # bootstraps in one example need different ones — which is why several specs here deliberately use
  # one example per parameterized value rather than looping.
  def identity
    @identity ||= { issuer_key: "https://id.example/oidc", subject: "founder-#{SecureRandom.hex(8)}" }
  end

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

  # A started Crawl over one Source, or over SEVERAL when `hosts` is given — which the run driver
  # needs, because a single-root frontier has nowhere for its next-frontier link to go and so cannot
  # distinguish "drained" from "advancing".
  def running_crawl(host: "shop.acme.example", hosts: [host])
    g = bootstrap
    ids = hosts.map { |h| register_source(g, "https://#{h}").tap { |sid| verify(g, sid) } }
    ids.each { |sid| activate_source(g, sid) }
    sid = ids.first
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
    { g:, crawl_id:, source_id: sid, source_ids: ids, host: hosts.first }
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

  # Sitemap discovery for the context's host, driven exactly as the run driver drives it. Robots must
  # already be terminal, which is :450's own precondition.
  def resolve_sitemaps(ctx, outbound)
    Workflows::Wf005::DiscoverSitemaps.new(outbound:, pacer: pacer_for(ctx)).call(
      organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id],
      canonical_host: ctx[:host], source_id: ctx[:source_id], now: start_now)
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


  # ---- simulated elapsed time -------------------------------------------------
  #
  # The host gate paces starts at 1/second (:442), so any spec that fetches more than once must let
  # that second pass. It ADVANCES THE CLOCK by moving every recorded instant that far into the past
  # rather than clearing the columns, so the gate's own predicates still decide whether enough time
  # has elapsed — a `Crawl-delay` longer than the pace still refuses. Extracted here because three
  # specs had grown their own copy, which is how the harness drift this file exists to end begins.
  def paces = (@paces ||= [])

  def pacer_for(ctx)
    sink = paces
    lambda do |ms|
      sink << ms.to_i
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

  # Let the gate's rolling second elapse between two fetches in one example.
  def advance_gate(ctx, ms = 2_000) = pacer_for(ctx).call(ms)

  # ---- a REAL delivery lease (F-04 FU-24) -------------------------------------
  #
  # A workflow that must stop when its lease moves can only be proven against a genuine one: a real
  # `scheduled_actions` row, claimed and dispatched through the restricted transport connection, kept by a
  # real `LeaseKeeper`. A double here would prove that the double stops.

  def dispatched_delivery(org, worker_owner: SecureRandom.uuid_v7)
    created = ScheduledActionHarness.create(organization_id: org, target_id: SecureRandom.uuid_v7,
                                            due_at: Time.now.utc - 60, now: Time.now.utc)
    Platform::ScheduledActions::TransportConnection.with do |pg|
      store = Platform::ScheduledActions::Store.new(pg)
      lease = Platform::ScheduledActions::Worker::WORKER_LEASE_SECONDS
      claimed = store.claim_due(owner: SecureRandom.uuid_v7, limit: 25, lease_seconds: lease)
                     .find { |a| a.id == created[:id] }
      raise "action was not claimed" if claimed.nil?

      dispatched = store.dispatch(work_id: claimed.work_id, expected_generation: claimed.claim_generation,
                                  worker_owner:, lease_seconds: lease)
      raise "action was not dispatched" if dispatched.nil?

      Platform::ScheduledActions::LeaseKeeper.new(action_id: dispatched.id, owner: worker_owner,
                                                  generation: dispatched.claim_generation,
                                                  lease_seconds: lease)
    end
  end

  # Take the action away for real — lapse the lease and let the RATIFIED sweep reclaim it — so the next
  # boundary gets a confirmed transfer from the database rather than a flag someone set.
  def steal_delivery(keeper)
    DbInspector.connection.exec_params(
      "UPDATE scheduled_actions SET lease_expires_at = now() - interval '1 second',
         state_version = state_version + 1 WHERE id = $1::uuid", [keeper.action_id])
    Platform::ScheduledActions::TransportConnection.with do |pg|
      Platform::ScheduledActions::Store.new(pg).release_expired_leases(limit: 10)
    end
    # The cadence must be due, or an authoritative guard would answer from its last renewal.
    keeper.instance_variable_set(:@renewed_at, keeper.send(:monotonic) - (keeper.interval * 2))
  end
end
