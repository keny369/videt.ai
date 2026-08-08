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
        receipt_digest: receipt[:receipt_digest], expected_grant_version: 0, organization_display_name: "Acme", first_project: GenesisProjectProfile.body("Genesis"), access_policy_content_sha256: bc.access_policy_sha256, entitlement_policy_content_sha256: bc.entitlement_policy_sha256,
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

  # A DELIBERATELY ILLEGAL transition, issued as raw SQL so the assertion is about the DATABASE guard
  # and not about a store method declining to offer the edge. The store has no such method, which is
  # the point: the refusal must hold against any writer.
  def revert_to_queued(id)
    DbInspector.connection.exec_params(
      "UPDATE crawl_frontier_entries SET state = 'queued', state_version = state_version + 1 WHERE id = $1::uuid",
      [id])
  end

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

    it "refuses to hand out a candidate whose Source was disabled AFTER the start" do
      # The owner's requirement is "no longer active AT EXECUTION TIME", and the dequeue is execution
      # time. Seeding excludes Sources inactive at the START commit; this covers a Source the
      # customer disables mid-run, which seeding alone cannot.
      q = queued(%w[https://alpha.acme.example https://beta.acme.example])
      expect(start(q[:crawl_id]).success?).to be(true)
      expect(entries(q[:crawl_id]).size).to eq(2)

      # Disable the Source whose root sorts FIRST, so a dequeue that ignored Source state would
      # hand it out before the other.
      first_entry = entries(q[:crawl_id]).first
      victim = DbInspector.one("SELECT id FROM sources WHERE id = $1::uuid", [first_entry["source_id"]])["id"]
      expect(disable_source(q[:g], victim).success?).to be(true)

      claimed = in_frontier(q[:g][:organization_id]) do |frontier, _s|
        [frontier.claim_next(organization_id: q[:g][:organization_id], crawl_id: q[:crawl_id], now: start_now),
         frontier.claim_next(organization_id: q[:g][:organization_id], crawl_id: q[:crawl_id], now: start_now)]
      end
      expect(claimed.compact.map { |c| c["source_id"] }).not_to include(victim)
      expect(claimed.compact.size).to eq(1)
      # The disabled Source's entry is left `queued`, never claimed — it is skipped, not destroyed.
      expect(entries(q[:crawl_id]).find { |r| r["source_id"] == victim }["state"]).to eq("queued")
    end

    it "orders sitemap before link within one depth" do
      # :440 — the Source root is depth 0; a sitemap-discovered content URL and a root-followed link
      # are both depth 1, so that is where the origin rank actually decides order.
      q = queued(%w[https://alpha.acme.example])
      start(q[:crawl_id])
      org = q[:g][:organization_id]
      root = entries(q[:crawl_id]).first
      in_frontier(org) do |frontier, _s|
        %w[link sitemap].each_with_index do |origin, i|
          frontier.offer(organization_id: org, project_id: q[:g][:project_id], crawl_id: q[:crawl_id],
                         source_id: root["source_id"], canonical_url: "https://alpha.acme.example/p#{i}",
                         origin:, depth: 1, now: start_now,
                         discovering_document_url: origin == "link" ? "https://alpha.acme.example/" : "",
                         link_position: origin == "link" ? 1 : 0, parent_entry_id: root["id"],
                         scope_policy_id: root["scope_policy_id"], scope_policy_version: root["scope_policy_version"])
        end
      end
      expect(entries(q[:crawl_id]).map { |r| r["origin"] }).to eq(%w[root sitemap link])
    end

    it "SEALS each depth: a deeper candidate is not selectable while a shallower one is in flight" do
      # :454 "all depth d discoveries are SEALED before any depth d+1 candidate is SELECTED".
      # Ordering alone does not deliver this — once the depth-1 entry is claimed (in_progress) and
      # nothing at depth 1 remains `queued`, a naive dequeue would hand out the depth-2 candidate.
      q = queued(%w[https://alpha.acme.example])
      start(q[:crawl_id])
      org = q[:g][:organization_id]
      root = entries(q[:crawl_id]).first

      claimed_root, next_claim = in_frontier(org) do |frontier, _s|
        [1, 2].each do |d|
          frontier.offer(organization_id: org, project_id: q[:g][:project_id], crawl_id: q[:crawl_id],
                         source_id: root["source_id"], canonical_url: "https://alpha.acme.example/d#{d}",
                         origin: "link", depth: d, now: start_now,
                         discovering_document_url: "https://alpha.acme.example/", link_position: d,
                         parent_entry_id: root["id"], scope_policy_id: root["scope_policy_id"],
                         scope_policy_version: root["scope_policy_version"])
        end
        [frontier.claim_next(organization_id: org, crawl_id: q[:crawl_id], now: start_now),
         frontier.claim_next(organization_id: org, crawl_id: q[:crawl_id], now: start_now)]
      end

      expect(claimed_root["depth"].to_i).to eq(0)
      # The depth-1 candidate is `queued` and is the lowest-ordered queued row — a dequeue ordering
      # by key ALONE would hand it out here. It is not selectable, because the depth-0 root is still
      # `in_progress`: depth 0 is not yet SEALED.
      expect(next_claim).to be_nil
      states = entries(q[:crawl_id]).to_h { |r| [r["depth"].to_i, r["state"]] }
      expect(states[0]).to eq("in_progress")
      expect(states[1]).to eq("queued")
      expect(states[2]).to eq("queued")
    end

    it "RELEASES the seal when the claimed depth goes terminal, and one depth at a time" do
      # The other half of :454's seal, delivered by S-07-012's run driver: the depth that has been
      # acted on stops holding the frontier. Without this edge `sealed_depth` — MIN(depth) over
      # ('queued','in_progress','fetched_pending_commit') — pins at the claimed depth for the rest of
      # the run, so a Crawl whose sitemap admitted depth-1 URLs (:440) would fetch its roots and then
      # stall with work queued. (The comment this replaced recorded the edge as S-07-009's, which
      # predates S-07-012 existing at all; the seal release is the run driver's, because the driver is
      # the only component that knows a fetch has been decided.)
      q = queued(%w[https://alpha.acme.example])
      start(q[:crawl_id])
      org = q[:g][:organization_id]
      root = entries(q[:crawl_id]).first

      claimed, after_claim, after_release, second = in_frontier(org) do |frontier, store|
        [1, 2].each do |d|
          frontier.offer(organization_id: org, project_id: q[:g][:project_id], crawl_id: q[:crawl_id],
                         source_id: root["source_id"], canonical_url: "https://alpha.acme.example/d#{d}",
                         origin: "link", depth: d, now: start_now,
                         discovering_document_url: "https://alpha.acme.example/", link_position: d,
                         parent_entry_id: root["id"], scope_policy_id: root["scope_policy_id"],
                         scope_policy_version: root["scope_policy_version"])
        end
        claimed = store.claim_next(org, q[:crawl_id], start_now)
        blocked = store.peek_next(org, q[:crawl_id])
        released = store.terminalize(org, claimed["id"], claimed["state_version"].to_i, start_now)
        [claimed, blocked, released, store.peek_next(org, q[:crawl_id])]
      end

      expect(claimed["depth"].to_i).to eq(0)
      # `claim_next` reports the POST-CLAIM version, so the release below is a compare-and-set on
      # exactly this claim rather than on a value re-read after another writer moved it.
      expect(claimed["state_version"].to_i).to eq(root["state_version"].to_i + 1)
      expect(after_claim).to be_nil
      expect(after_release).to eq(1)
      # Depth 1 is now selectable, and depth 2 still is not: the seal moved by exactly one depth.
      expect(second["depth"].to_i).to eq(1)
      states = entries(q[:crawl_id]).to_h { |r| [r["depth"].to_i, r["state"]] }
      expect(states[0]).to eq("terminal")
      # `terminal` is not `discarded`: the candidate WAS acted on, so :452 keeps it in the coverage
      # denominator, and the discard-reason CHECK requires it to carry no reason.
      expect(entries(q[:crawl_id]).first["reason"]).to be_nil
    end

    it "refuses the seal release on a stale version, on an unclaimed entry, and never reverses it" do
      # The release is a compare-and-set, not an assignment: a redelivered action whose entry has
      # already been retired must learn that rather than rewrite a decision, and no other transition
      # out of `terminal` exists.
      q = queued(%w[https://alpha.acme.example])
      start(q[:crawl_id])
      org = q[:g][:organization_id]
      root = entries(q[:crawl_id]).first

      # An entry still `queued` cannot be retired: only a CLAIMED entry has been acted on.
      expect(in_frontier(org) { |_f, store| store.terminalize(org, root["id"], root["state_version"].to_i, start_now) }).to eq(0)

      claimed = in_frontier(org) { |_f, store| store.claim_next(org, q[:crawl_id], start_now) }
      version = claimed["state_version"].to_i
      expect(in_frontier(org) { |_f, store| store.terminalize(org, claimed["id"], version - 1, start_now) }).to eq(0)
      expect(in_frontier(org) { |_f, store| store.terminalize(org, claimed["id"], version, start_now) }).to eq(1)
      # The second delivery of the same release matches zero rows rather than advancing the version.
      expect(in_frontier(org) { |_f, store| store.terminalize(org, claimed["id"], version + 1, start_now) }).to eq(0)
      # AND IT NAMES THE ORGANIZATION, so the isolation is local to the statement rather than resting on
      # every caller having entered the tenant context first.
      expect(in_frontier(org) { |_f, store| store.terminalize(SecureRandom.uuid_v7, claimed["id"], version, start_now) }).to eq(0)

      # And the guard refuses every edge OUT of `terminal`, so coverage cannot be rewritten later.
      expect { in_frontier(org) { |_f, _s| revert_to_queued(claimed["id"]) } }
        .to raise_error(PG::RaiseException, /crawl_frontier_transition_unavailable terminal -> queued/)
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
      # The second discovery sorts HIGHER (same URL and document, later link position), so the
      # retained entry keeps its position and the newcomer is the occurrence.
      expect(second.repositioned).to be(false)
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

    it "REPOSITIONS the retained entry when a later discovery of it sorts LOWER" do
      # :454 "Deduplication retains the first candidate in THIS ORDER" — the lowest-ordered
      # discovery, not the first offered. Reachable because :440 puts sitemap URLs and root-followed
      # links both at depth 1, where origin rank (not the URL) decides parent order, so a sitemap
      # page can be dequeued before a link page whose own URL sorts lower.
      q = queued(%w[https://alpha.acme.example])
      start(q[:crawl_id])
      org = q[:g][:organization_id]
      root = entries(q[:crawl_id]).first
      url = "https://alpha.acme.example/shared"

      def offer_from(frontier, q, root, url, discovering)
        frontier.offer(organization_id: q[:g][:organization_id], project_id: q[:g][:project_id],
                       crawl_id: q[:crawl_id], source_id: root["source_id"], canonical_url: url,
                       origin: "link", depth: 2, now: Time.utc(2026, 7, 27, 10, 1, 30),
                       discovering_document_url: discovering, link_position: 1,
                       parent_entry_id: root["id"], scope_policy_id: root["scope_policy_id"],
                       scope_policy_version: root["scope_policy_version"])
      end

      high, low = in_frontier(org) do |frontier, _s|
        # Discovered first from the HIGHER-sorting parent, then from the LOWER-sorting one.
        [offer_from(frontier, q, root, url, "https://alpha.acme.example/zzz"),
         offer_from(frontier, q, root, url, "https://alpha.acme.example/aaa")]
      end

      expect(high.admitted?).to be(true)
      expect(low.duplicate?).to be(true)
      expect(low.repositioned).to be(true)
      # Still exactly ONE retained candidate — it simply now sits at the lower position.
      retained = entries(q[:crawl_id]).find { |r| r["canonical_url"] == url }
      expect(retained["discovering_document_url"]).to eq("https://alpha.acme.example/aaa")
      # ...and the SUPERSEDED position is what was recorded as the occurrence.
      expect(occurrences(q[:crawl_id]).map { |o| o["discovering_document_url"] })
        .to eq(["https://alpha.acme.example/zzz"])
    end

    it "keeps the lowest-ordered candidates at the discovered-queue bound, evicting a higher one" do
      # :454 "retain the LOWEST 20,000 by this order and record all later candidates as
      # queue_limit_discarded" — a selection over a SET, so a lower-ordered late arrival displaces a
      # higher-ordered admitted candidate rather than being dropped itself.
      q = queued(%w[https://alpha.acme.example])
      start(q[:crawl_id])
      org = q[:g][:organization_id]
      root = entries(q[:crawl_id]).first

      stub_const("Workflows::Wf005::Frontier::DISCOVERED_QUEUE_HARD", 3)
      results = in_frontier(org) do |frontier, _s|
        %w[m z a].map do |slug|   # admitted, admitted (at the bound), then a LOWER-sorting arrival
          frontier.offer(organization_id: org, project_id: q[:g][:project_id], crawl_id: q[:crawl_id],
                         source_id: root["source_id"], canonical_url: "https://alpha.acme.example/#{slug}",
                         origin: "link", depth: 1, now: start_now,
                         discovering_document_url: "https://alpha.acme.example/", link_position: 1,
                         parent_entry_id: root["id"], scope_policy_id: root["scope_policy_id"],
                         scope_policy_version: root["scope_policy_version"])
        end
      end

      expect(results.map(&:disposition)).to eq(%i[admitted admitted admitted])
      expect(results.last.evicted_entry_id).to be_present
      by_url = entries(q[:crawl_id]).to_h { |r| [r["canonical_url"], r] }
      # `/z` sorted highest, so it is the one evicted; `/a` and `/m` are retained.
      expect(by_url["https://alpha.acme.example/z"]["state"]).to eq("discarded")
      expect(by_url["https://alpha.acme.example/z"]["reason"]).to eq("queue_limit_discarded")
      expect(by_url["https://alpha.acme.example/a"]["state"]).to eq("queued")
      expect(by_url["https://alpha.acme.example/m"]["state"]).to eq("queued")
    end

    it "discards the newcomer when it sorts HIGHER than everything admitted at the bound" do
      q = queued(%w[https://alpha.acme.example])
      start(q[:crawl_id])
      org = q[:g][:organization_id]
      root = entries(q[:crawl_id]).first
      stub_const("Workflows::Wf005::Frontier::DISCOVERED_QUEUE_HARD", 3)
      results = in_frontier(org) do |frontier, _s|
        %w[a m z].map do |slug|
          frontier.offer(organization_id: org, project_id: q[:g][:project_id], crawl_id: q[:crawl_id],
                         source_id: root["source_id"], canonical_url: "https://alpha.acme.example/#{slug}",
                         origin: "link", depth: 1, now: start_now,
                         discovering_document_url: "https://alpha.acme.example/", link_position: 1,
                         parent_entry_id: root["id"], scope_policy_id: root["scope_policy_id"],
                         scope_policy_version: root["scope_policy_version"])
        end
      end
      expect(results.map(&:disposition)).to eq(%i[admitted admitted discarded])
      expect(results.last.reason).to eq("queue_limit_discarded")
      expect(results.last.evicted_entry_id).to be_nil
      # The discarded candidate is RETAINED as a row, so the coverage denominator can account for it.
      expect(entries(q[:crawl_id]).find { |r| r["canonical_url"].end_with?("/z") }["state"]).to eq("discarded")
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
