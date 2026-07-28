# frozen_string_literal: true

require "rails_helper"

# WF-005 crawl frontier + deterministic dequeue (S-07-004; WORKFLOW_SPECIFICATIONS.md :454;
# SEARCH_CRAWL_RETRIEVAL.md § Crawl Admission And Snapshot step 6 and § Frontier And Deterministic
# Selection; contracts/S-07.json MTX-030 concurrency/persistence_model).
#
# Exercised over the PRODUCTION-REAL chain (owner D5): genesis -> registered + verified + activated
# Source(s) -> ActivateProject -> QueueCrawl -> StartCrawl, which seeds the root frontier in its own
# accepted-start commit. No fabricated Crawl or Source fixtures.
#
# The load-bearing requirement, restated by the owner in HD-S07-FU4-FU5: the frontier MUST exclude
# any pinned Source that is no longer active at execution time. `crawl_sources` is T-IMM and records
# queue-time membership, so seeding from it alone would crawl a disabled or removed Source on
# queue-time authority.
RSpec.describe "WF-005 crawl frontier", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-E2E TYP-DATA TYP-SEC] do
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

  # `expected_state_version` is the PROJECT's, so a Source registered after ActivateProject must
  # carry the activated version rather than 0.
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

  def queue_crawl(g)
    Workflows::Wf005::Handlers::QueueCrawl.new.call(
      command: Workflows::Wf005::Commands::QueueCrawl.new(command_id: SecureRandom.uuid_v7, idempotency_key: "qc-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
        requested_at_utc: act_now), request_context: act_ctx)
  end

  def start(crawl_id, at: start_now)
    a = DbInspector.one("SELECT * FROM scheduled_actions WHERE action_kind = 'crawl_dispatch' AND target_id = $1::uuid", [crawl_id])
    Workflows::Wf005::Handlers::StartCrawl.new.call(
      command: Workflows::Wf005::Commands::StartCrawl.new(
        command_id: SecureRandom.uuid_v7, schema_version: a["action_schema_version"], organization_id: a["organization_id"],
        target_type: a["target_type"], crawl_id: a["target_id"], due_at: Time.parse(a["due_at"]).getutc, action_id: a["id"],
        action_identity_sha256: [a["identity_sha256"].sub(/\A\\x/, "")].pack("H*"), requested_at_utc: at),
      request_context: executor_ctx(at))
  end

  # Chain to a queued Crawl over `hosts` active Sources, registered in the given order.
  def queued(hosts)
    g = bootstrap
    ids = hosts.map { |h| register_source(g, h).tap { |sid| verify(g, sid) } }
    ids.each { |sid| activate_source(g, sid) }
    raise "activation failed" unless activate_project(g).success?

    result = queue_crawl(g)
    raise "queue failed" unless result.success?

    { g:, crawl_id: result.payload[:crawl_id], source_ids: ids }
  end

  def project_row(pid) = DbInspector.one("SELECT * FROM projects WHERE id = $1::uuid", [pid])
  def source_row(sid) = DbInspector.one("SELECT * FROM sources WHERE id = $1::uuid", [sid])
  def crawl_row(cid) = DbInspector.one("SELECT * FROM crawls WHERE id = $1::uuid", [cid])
  def entries(cid) = DbInspector.all("SELECT * FROM crawl_frontier_entries WHERE crawl_id = $1::uuid ORDER BY dequeue_key", [cid])
  def occurrences(cid) = DbInspector.all("SELECT * FROM crawl_frontier_occurrences WHERE crawl_id = $1::uuid ORDER BY occurrence_order", [cid])
  def pinned(cid) = DbInspector.all("SELECT * FROM crawl_sources WHERE crawl_id = $1::uuid ORDER BY source_order", [cid])

  # Run a block against the real frontier surface inside a proved-Organization unit of work.
  def in_frontier(org)
    Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      store = IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg)
      store.enter_org_context(org:, correlation_id: SecureRandom.uuid_v7)
      yield Workflows::Wf005::Frontier.new(store, ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7), store
    end
  end

  describe "root seeding at the accepted start" do
    it "seeds exactly one queued root entry per active pinned Source, in canonical root order" do
      q = queued(%w[https://zeta.acme.example https://alpha.acme.example])
      expect(start(q[:crawl_id]).success?).to be(true)

      rows = entries(q[:crawl_id])
      expect(rows.size).to eq(2)
      expect(rows.map { |r| r["origin"] }.uniq).to eq(["root"])
      expect(rows.map { |r| r["depth"] }.uniq).to eq(["0"])
      expect(rows.map { |r| r["state"] }.uniq).to eq(["queued"])
      # :454 — "Source roots are ordered by canonical root URL UTF-8 bytes and then Source ID", so
      # alpha precedes zeta even though zeta was registered (and pinned) first.
      expect(rows.map { |r| r["canonical_url"] })
        .to eq(["https://alpha.acme.example/", "https://zeta.acme.example/"])
      expect(pinned(q[:crawl_id]).map { |r| r["canonical_root_uri"] })
        .to eq(["https://zeta.acme.example/", "https://alpha.acme.example/"])
      # Each entry records the scope policy that admitted it and the canonicalization contract.
      expect(rows.map { |r| r["scope_policy_id"] }.compact.size).to eq(2)
      expect(rows.map { |r| r["canonicalization_version"] }.uniq).to eq(["source-scope-interim-v1"])
      expect(rows.map { |r| r["enqueue_order"] }).to eq(%w[0 1])
    end

    it "EXCLUDES a pinned Source disabled between queueing and execution" do
      # The owner's named requirement (HD-S07-FU4-FU5): a disabled Source is never crawled on
      # queue-time authority, even though it remains in the immutable pinned set.
      q = queued(%w[https://alpha.acme.example https://beta.acme.example])
      disabled = q[:source_ids].last
      expect(disable_source(q[:g], disabled).success?).to be(true)

      result = start(q[:crawl_id])
      expect(result.success?).to be(true)
      expect(result.payload[:pinned_source_count]).to eq(2)
      expect(result.payload[:frontier_root_count]).to eq(1)
      expect(result.payload[:excluded_inactive_source_count]).to eq(1)

      rows = entries(q[:crawl_id])
      expect(rows.size).to eq(1)
      expect(rows.first["source_id"]).not_to eq(disabled)
      # The pinned set itself is untouched — it is T-IMM and still records queue-time membership.
      expect(pinned(q[:crawl_id]).size).to eq(2)
    end

    it "EXCLUDES a pinned Source removed between queueing and execution" do
      q = queued(%w[https://alpha.acme.example https://beta.acme.example])
      removed = q[:source_ids].last
      expect(disable_source(q[:g], removed).success?).to be(true)
      expect(Workflows::Wf004::Handlers::RemoveSource.new.call(
        command: Workflows::Wf004::Commands::RemoveSource.new(command_id: SecureRandom.uuid_v7, idempotency_key: "rm-#{SecureRandom.hex(6)}",
          schema_version: "1.0", session_id: q[:g][:session_id], organization_id: q[:g][:organization_id],
          project_id: q[:g][:project_id], source_id: removed, expected_state_version: source_row(removed)["state_version"].to_i,
          lifecycle_reason: "owner_requested_removal", requested_at_utc: act_now), request_context: act_ctx).success?).to be(true)

      result = start(q[:crawl_id])
      expect(result.payload[:frontier_root_count]).to eq(1)
      expect(entries(q[:crawl_id]).map { |r| r["source_id"] }).not_to include(removed)
    end

    it "refuses the start outright when EVERY pinned Source has left active" do
      # Not merely an empty frontier: a run that can crawl nothing must never reach `running`.
      q = queued(%w[https://alpha.acme.example])
      expect(disable_source(q[:g], q[:source_ids].first).success?).to be(true)
      result = start(q[:crawl_id])
      expect(result.failure.reason_code).to eq("crawl_no_active_source")
      expect(crawl_row(q[:crawl_id])["state"]).to eq("failed")
      expect(entries(q[:crawl_id])).to be_empty
    end

    it "refuses the start when the Project has a new active Source but every PINNED one is inactive" do
      # The precondition is over the pinned set, not the Project at large: only pinned Sources can
      # be crawled, so a fresh Source activated after queueing cannot rescue this run.
      q = queued(%w[https://alpha.acme.example])
      expect(disable_source(q[:g], q[:source_ids].first).success?).to be(true)
      fresh = register_source(q[:g], "https://gamma.acme.example")
      verify(q[:g], fresh)
      expect(activate_source(q[:g], fresh).success?).to be(true)

      result = start(q[:crawl_id])
      expect(result.failure.reason_code).to eq("crawl_no_active_source")
      expect(entries(q[:crawl_id])).to be_empty
    end
  end

  describe "the deterministic dequeue" do
    it "claims candidates in canonical dequeue order, never in insertion order" do
      q = queued(%w[https://zeta.acme.example https://alpha.acme.example])
      start(q[:crawl_id])
      claimed = in_frontier(q[:g][:organization_id]) do |frontier, _store|
        [frontier.claim_next(organization_id: q[:g][:organization_id], crawl_id: q[:crawl_id], now: start_now),
         frontier.claim_next(organization_id: q[:g][:organization_id], crawl_id: q[:crawl_id], now: start_now),
         frontier.claim_next(organization_id: q[:g][:organization_id], crawl_id: q[:crawl_id], now: start_now)]
      end
      expect(claimed[0]["canonical_url"]).to eq("https://alpha.acme.example/")
      expect(claimed[1]["canonical_url"]).to eq("https://zeta.acme.example/")
      expect(claimed[2]).to be_nil    # drained
      expect(entries(q[:crawl_id]).map { |r| r["state"] }.uniq).to eq(["in_progress"])
    end

    it "orders breadth-first: every depth-d candidate precedes any depth-d+1 candidate" do
      q = queued(%w[https://alpha.acme.example])
      start(q[:crawl_id])
      org = q[:g][:organization_id]
      root = entries(q[:crawl_id]).first

      in_frontier(org) do |frontier, _s|
        # A depth-2 candidate whose URL sorts BEFORE the depth-1 one; depth must still win.
        frontier.offer(organization_id: org, project_id: q[:g][:project_id], crawl_id: q[:crawl_id],
                       source_id: root["source_id"], canonical_url: "https://alpha.acme.example/aaa",
                       origin: "link", depth: 2, now: start_now, discovering_document_url: "https://alpha.acme.example/",
                       link_position: 1, parent_entry_id: root["id"], scope_policy_id: root["scope_policy_id"],
                       scope_policy_version: root["scope_policy_version"])
        frontier.offer(organization_id: org, project_id: q[:g][:project_id], crawl_id: q[:crawl_id],
                       source_id: root["source_id"], canonical_url: "https://alpha.acme.example/zzz",
                       origin: "link", depth: 1, now: start_now, discovering_document_url: "https://alpha.acme.example/",
                       link_position: 2, parent_entry_id: root["id"], scope_policy_id: root["scope_policy_id"],
                       scope_policy_version: root["scope_policy_version"])
      end
      expect(entries(q[:crawl_id]).map { |r| [r["depth"], r["canonical_url"]] })
        .to eq([["0", "https://alpha.acme.example/"],
                ["1", "https://alpha.acme.example/zzz"],
                ["2", "https://alpha.acme.example/aaa"]])
    end

    it "orders root before sitemap before link within one depth" do
      q = queued(%w[https://alpha.acme.example])
      start(q[:crawl_id])
      org = q[:g][:organization_id]
      root = entries(q[:crawl_id]).first
      in_frontier(org) do |frontier, _s|
        %w[link sitemap].each_with_index do |origin, i|
          frontier.offer(organization_id: org, project_id: q[:g][:project_id], crawl_id: q[:crawl_id],
                         source_id: root["source_id"], canonical_url: "https://alpha.acme.example/p#{i}",
                         origin:, depth: 0, now: start_now,
                         discovering_document_url: origin == "link" ? "https://alpha.acme.example/" : "",
                         link_position: origin == "link" ? 1 : 0, parent_entry_id: root["id"],
                         scope_policy_id: root["scope_policy_id"], scope_policy_version: root["scope_policy_version"])
        end
      end
      expect(entries(q[:crawl_id]).map { |r| r["origin"] }).to eq(%w[root sitemap link])
    end
  end

  describe "deduplication and occurrences" do
    it "retains the first candidate and records a later identical discovery as an occurrence" do
      q = queued(%w[https://alpha.acme.example])
      start(q[:crawl_id])
      org = q[:g][:organization_id]
      root = entries(q[:crawl_id]).first
      url = "https://alpha.acme.example/dup"

      first, second = in_frontier(org) do |frontier, _s|
        [1, 2].map do |position|
          frontier.offer(organization_id: org, project_id: q[:g][:project_id], crawl_id: q[:crawl_id],
                         source_id: root["source_id"], canonical_url: url, origin: "link", depth: 1,
                         now: start_now, discovering_document_url: "https://alpha.acme.example/",
                         link_position: position, parent_entry_id: root["id"],
                         scope_policy_id: root["scope_policy_id"], scope_policy_version: root["scope_policy_version"])
        end
      end

      expect(first.admitted?).to be(true)
      expect(second.duplicate?).to be(true)
      expect(second.entry_id).to eq(first.entry_id)
      # One retained candidate, and the duplicate kept for audit "without becoming another candidate".
      expect(entries(q[:crawl_id]).count { |r| r["canonical_url"] == url }).to eq(1)
      occ = occurrences(q[:crawl_id])
      expect(occ.size).to eq(1)
      expect(occ.first["frontier_entry_id"]).to eq(first.entry_id)
      expect(occ.first["link_position"]).to eq("2")
      expect(occ.first["duplicate_reason"]).to eq("duplicate_discovery")
      expect(occ.first["referrer_entry_id"]).to eq(root["id"])
    end

    it "retains both candidates and never merges them when preimages differ" do
      q = queued(%w[https://alpha.acme.example])
      start(q[:crawl_id])
      org = q[:g][:organization_id]
      root = entries(q[:crawl_id]).first
      a, b = in_frontier(org) do |frontier, _s|
        %w[https://alpha.acme.example/one https://alpha.acme.example/two].map do |url|
          frontier.offer(organization_id: org, project_id: q[:g][:project_id], crawl_id: q[:crawl_id],
                         source_id: root["source_id"], canonical_url: url, origin: "link", depth: 1,
                         now: start_now, discovering_document_url: "https://alpha.acme.example/",
                         link_position: 1, parent_entry_id: root["id"],
                         scope_policy_id: root["scope_policy_id"], scope_policy_version: root["scope_policy_version"])
        end
      end
      expect(a.admitted? && b.admitted?).to be(true)
      expect(a.entry_id).not_to eq(b.entry_id)
      expect(entries(q[:crawl_id]).size).to eq(3)
      expect(occurrences(q[:crawl_id])).to be_empty
    end

    it "retains the full canonical preimage beside the digest on every entry" do
      q = queued(%w[https://alpha.acme.example])
      start(q[:crawl_id])
      row = entries(q[:crawl_id]).first
      preimage = DbInspector.one("SELECT convert_from(canonical_url_preimage,'UTF8') AS p, encode(canonical_url_sha256,'hex') AS d FROM crawl_frontier_entries WHERE id = $1::uuid", [row["id"]])
      expect(preimage["p"]).to eq("https://alpha.acme.example/")
      expect(preimage["d"]).to eq(Digest::SHA256.hexdigest("https://alpha.acme.example/"))
      expect(row["collision_ordinal"]).to eq("0")
    end
  end
end
