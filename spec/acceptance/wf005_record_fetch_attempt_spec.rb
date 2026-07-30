# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# WF-005 THE RUN DRIVER (S-07-012) — one `crawl_fetch_due` action is one pass of the run
# (BACKGROUND_PROCESSING.md :138/:198/:378; WORKFLOW_SPECIFICATIONS.md :442/:444/:450/:454).
#
# Until this tranche NOTHING IN PRODUCTION CALLED `EnsureRobots`, `DiscoverSitemaps`, `Admission` or
# `FetchContent`: the only registered entry point seeded the root frontier and scheduled nothing
# further. These examples drive the REAL handler over the PRODUCTION-REAL chain, so every claim about a
# run making progress is exercised rather than presupposed.
#
# Only the frozen F-01 outbound facade is stubbed, and it is stubbed BY REQUEST PATH, because a pass
# may reach robots, a sitemap and a content URL and several of these examples are about WHICH of those
# it actually did — and about which it must not.
#
# The property ADR-085 turns on, asserted rather than argued: THE FETCH PATH IS THE SOLE PRODUCER of
# `fetch_attempts`. The scheduler creates frontier-entry links and never an attempt row, so S-07-007's
# in-process :444 retry loop still owns every retry.
RSpec.describe "WF-005 run driver", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-E2E TYP-DATA TYP-INT] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  ROBOTS_ALLOW_ALL = "User-agent: *\nAllow: /\n"

  # A stub of the frozen F-01 facade dispatching on the request PATH. A path absent from the map is an
  # UNEXPECTED request and fails loudly, which is what makes "this pass made no request" assertable.
  def outbound_by_path(map)
    seen = requests
    Object.new.tap do |o|
      o.define_singleton_method(:fetch) do |url, **_kwargs|
        path = URI.parse(url.to_s).path
        seen << path
        raise "unexpected outbound fetch: #{url}" unless map.key?(path)

        entry = map[path]
        entry.is_a?(Array) ? (entry.length > 1 ? entry.shift : entry.first) : entry
      end
    end
  end

  def requests = (@requests ||= [])

  def html(status: 200, body: "<html><title>t</title></html>", type: "text/html", path: "/")
    Platform::Outbound::Outcome.response(
      status:, headers: type.nil? ? {} : { "content-type" => type }, body:, byte_count: body.bytesize,
      truncated: false, canonical_host: "shop.acme.example", port: 443, pinned_address: "198.51.100.7",
      final_url: "https://shop.acme.example#{path}", redirect_count: 0, latency_ms: 5
    )
  end

  def robots_allow = html(body: ROBOTS_ALLOW_ALL, type: "text/plain", path: "/robots.txt")
  def sitemap_missing = html(status: 404, body: "", type: "text/plain", path: "/sitemap.xml")
  def sitemap_naming(url) = html(type: "application/xml", path: "/sitemap.xml", body: <<~XML)
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <url><loc>#{url}</loc></url>
    </urlset>
  XML

  # A host with a gate but nothing resolved: the pass under test does the robots work itself.
  def gated(hosts: ["shop.acme.example"])
    running_crawl(hosts:).tap { |ctx| ensure_gate(ctx) }
  end

  # A host whose robots AND sitemap records are already terminal and whose rate window is clear, so the
  # pass under test has exactly one thing left to do: fetch. Every example about the FETCH starts here,
  # because :442 paces host starts over a rolling second and ONE PASS MAKES AT MOST ONE START.
  def fetchable(hosts: ["shop.acme.example"])
    ctx = gated(hosts:)
    resolve_robots(ctx, outbound_returning(response(status: 200, body: ROBOTS_ALLOW_ALL)))
    resolve_sitemaps(ctx, outbound_returning(response(status: 404, body: "")))
    clear_rate_window(gate_row(ctx[:crawl_id])["id"])
    ctx
  end

  def entries(cid) = DbInspector.all("SELECT * FROM crawl_frontier_entries WHERE crawl_id=$1::uuid ORDER BY dequeue_key", [cid])
  def attempts(cid) = DbInspector.all("SELECT * FROM fetch_attempts WHERE crawl_id=$1::uuid ORDER BY attempt_number", [cid])
  def counters(cid) = DbInspector.one("SELECT * FROM crawl_budget_counters WHERE crawl_id=$1::uuid", [cid])
  def action_row(id) = DbInspector.one("SELECT * FROM scheduled_actions WHERE id = $1::uuid", [id])

  def fetch_actions(cid)
    DbInspector.all(<<~SQL, [cid])
      SELECT sa.* FROM scheduled_actions sa
      JOIN crawl_frontier_entries e ON e.id = sa.target_id
      WHERE sa.action_kind = 'crawl_fetch_due' AND e.crawl_id = $1::uuid
      ORDER BY sa.due_at, sa.created_at
    SQL
  end

  # The run's first link, created exactly as StartCrawl's handoff and every later pass create it.
  def link_first(ctx, at: start_now)
    Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg)
                                                        .enter_org_context(org: ctx[:g][:organization_id],
                                                                          correlation_id: SecureRandom.uuid_v7)
      Workflows::Wf005::CrawlFetchDueSchedule.link_next(
        pg:, organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
        crawl_id: ctx[:crawl_id], now: at, correlation_id: SecureRandom.uuid_v7
      )
    end
  end

  def first_action(ctx, at: start_now) = action_row(link_first(ctx, at:)[:action_id])

  # Take an action through the real scheduler-to-worker handoff and return a keeper for the resulting
  # lease, which is the state every worker delivery actually runs in.
  def keeper_for_dispatched(action)
    Platform::ScheduledActions::TransportConnection.with do |pg|
      store = Platform::ScheduledActions::Store.new(pg)
      claimed = store.claim_due(owner: SecureRandom.uuid_v7, limit: 50,
                                lease_seconds: Platform::ScheduledActions::Worker::WORKER_LEASE_SECONDS)
                     .find { |a| a.id == action["id"] }
      raise "action was not claimed" if claimed.nil?

      worker_owner = SecureRandom.uuid_v7
      dispatched = store.dispatch(work_id: claimed.work_id, expected_generation: claimed.claim_generation,
                                  worker_owner:,
                                  lease_seconds: Platform::ScheduledActions::Worker::WORKER_LEASE_SECONDS)
      raise "action was not dispatched" if dispatched.nil?

      Platform::ScheduledActions::LeaseKeeper.new(
        action_id: dispatched.id, owner: worker_owner, generation: dispatched.claim_generation,
        lease_seconds: Platform::ScheduledActions::Worker::WORKER_LEASE_SECONDS
      )
    end
  end

  def in_frontier_of(ctx)
    Platform::UnitOfWork.run do |conn|
      store = IdentityAccess::Infrastructure::CrawlFrontierStore.new(conn.raw_connection)
      store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
      yield store
    end
  end

  # A depth-1 candidate, offered exactly as sitemap discovery offers one (:440).
  def offer_depth_one(ctx, root)
    in_frontier_of(ctx) do |store|
      Workflows::Wf005::Frontier.new(store, ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
        .offer(organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
               crawl_id: ctx[:crawl_id], source_id: root["source_id"],
               canonical_url: "https://#{ctx[:host]}/deeper", origin: "sitemap", depth: 1, now: start_now,
               discovering_document_url: "", link_position: 0, parent_entry_id: root["id"],
               scope_policy_id: root["scope_policy_id"], scope_policy_version: root["scope_policy_version"])
    end
  end

  # The pacer advances the gate's recorded instants instead of sleeping, so :444's in-process waits are
  # OBSERVABLE (`paces`) rather than spent.
  def execute(ctx, action, outbound, at: start_now)
    command = Workflows::Wf005::Commands::RecordFetchAttempt.new(
      command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
      organization_id: action["organization_id"], target_type: action["target_type"],
      frontier_entry_id: action["target_id"], due_at: Time.parse(action["due_at"]).getutc,
      action_id: action["id"],
      action_identity_sha256: [action["identity_sha256"].sub(/\A\\x/, "")].pack("H*"),
      requested_at_utc: at
    )
    Workflows::Wf005::Handlers::RecordFetchAttempt.new.call(
      command:, request_context: executor_ctx(at), outbound:, pacer: pacer_for(ctx)
    )
  end

  describe "the registered surface and the link it creates" do
    it "registers RecordFetchAttempt as the crawl_fetch_due handler at schema version 1.0" do
      entry = Platform::ScheduledActions::Registry.default.resolve(action_kind: "crawl_fetch_due",
                                                                   action_schema_version: "1.0")
      expect(entry.operation).to eq("RecordFetchAttempt")
      expect(entry.handler).to eq(Workflows::Wf005::Handlers::RecordFetchAttempt)
      expect(entry.command).to eq(Workflows::Wf005::Commands::RecordFetchAttempt)
    end

    it "targets the SELECTED FRONTIER ENTRY, and creating the link costs the run nothing" do
      # DECISIONS ADR-085. The scheduler names the entry the admission will claim; it does not mint an
      # attempt identity, hold a byte reservation, or touch the frontier.
      ctx = running_crawl
      link = link_first(ctx)
      root = entries(ctx[:crawl_id]).first

      expect(link[:entry_id]).to eq(root["id"])
      action = action_row(link[:action_id])
      expect(action["action_kind"]).to eq("crawl_fetch_due")
      expect(action["target_type"]).to eq("crawl_frontier_entry")
      expect(action["target_id"]).to eq(root["id"])
      expect(action["status"]).to eq("pending")
      expect(Platform::ScheduledActions::Catalogue.work_type_for("crawl_fetch_due")).to eq("crawl_fetch")
      expect(attempts(ctx[:crawl_id])).to be_empty
      expect(root["state"]).to eq("queued")
      expect(DbInspector.all("SELECT id FROM crawl_budget_counters WHERE crawl_id=$1::uuid",
                             [ctx[:crawl_id]])).to be_empty
    end

    it "PROOF 22 — the link stamps :288's product attempt deadline, so the lease is DERIVED not flat" do
      # `scheduled_actions` is transport and must not read `crawls` to find out how long this work may
      # legitimately take — so the PRODUCER stamps the instant and the claim function does the arithmetic.
      # Unstamped, the lease is a flat 30 seconds while ONE ratified redirect hop is up to 30 (F-01 takes
      # the 15-second resolver timeout outside the 15-second per-hop deadline), which lapsed the lease
      # under a live worker with no boundary inside the hop to renew at. Demonstrated before the repair.
      ctx = running_crawl
      action = action_row(link_first(ctx)[:action_id])
      crawl = DbInspector.one("SELECT * FROM crawls WHERE id = $1::uuid", [ctx[:crawl_id]])

      expect(action["product_attempt_deadline"]).not_to be_nil
      expect(Time.parse(action["product_attempt_deadline"].to_s))
        .to be_within(1).of(Time.parse(crawl["deadline_at"].to_s))

      # WHAT THIS EXAMPLE DOES NOT PROVE, said plainly. The chain runs on a FIXED 2026-07-27 clock while
      # :114 makes `transaction_timestamp()` the sole lease authority, so by the time the claim runs the
      # stamped deadline is genuinely in the past and the derived lease correctly falls back to the floor.
      # That is right, not a defect — but it means the CAP and the interior of the rule cannot be shown
      # here. PROOFs 19, 20, 23 and 24 cover them, against real-time deadlines.
      claimed = Platform::ScheduledActions::TransportConnection.with do |pg|
        Platform::ScheduledActions::Store.new(pg).claim_due(owner: SecureRandom.uuid_v7, limit: 50,
                                                            lease_seconds: 30)
        DbInspector.one("SELECT * FROM scheduled_actions WHERE id = $1::uuid", [action["id"]])
      end
      span = Time.parse(claimed["lease_expires_at"].to_s) - Time.parse(claimed["claimed_at"].to_s)
      # :288's floor as corrected by ADR-095, which is 60 rather than the 30 this example first asserted.
      expect(span).to be_within(2).of(60)
    end
  end

  describe "the chain: one paced host start per pass" do
    it "resolves robots and discovers sitemaps in the first pass, then fetches in the next" do
      # :442 paces starts over a rolling second per canonical host, and discovery claims the SAME gate
      # a content fetch does. A pass that fetched a sitemap and then tried to fetch content in the same
      # second would have its claim refused — and `FetchContent` records a refused claim as
      # `host_gate_deferred` with `retryable: false`, so the root URL would be DISCARDED because the
      # run's own discovery had just been polite. The pass comes back instead.
      ctx = gated
      first = execute(ctx, first_action(ctx),
                      outbound_by_path("/robots.txt" => robots_allow,
                                       "/sitemap.xml" => sitemap_naming("https://shop.acme.example/p1")))

      expect(first.payload[:pass_outcome]).to eq("deferred")
      expect(first.payload[:reason_code]).to eq("host_gate_paced")
      expect(requests).to eq(["/robots.txt", "/sitemap.xml"])
      gate = gate_row(ctx[:crawl_id])
      expect(gate["robots_state"]).to eq("rules_applied")
      expect(gate["sitemap_state"]).to eq("succeeded")
      # Discovery admitted the sitemap URL at depth 1 (:440) and cost the root nothing: it is still
      # `queued`, has no attempt, and the re-entry names it again.
      expect(entries(ctx[:crawl_id]).map { |r| [r["depth"].to_i, r["state"]] })
        .to eq([[0, "queued"], [1, "queued"]])
      expect(attempts(ctx[:crawl_id])).to be_empty
      root = entries(ctx[:crawl_id]).first
      reentry = action_row(first.payload[:next_action_id])
      expect(reentry["target_id"]).to eq(root["id"])
      expect(Time.parse(reentry["due_at"]).getutc).to be > start_now

      # THE SECOND PASS, at the instant the gate named: robots and sitemaps are terminal, so the only
      # request left is the content fetch.
      requests.clear
      clear_rate_window(gate["id"])
      second = execute(ctx, reentry, outbound_by_path("/" => html),
                       at: Time.parse(reentry["due_at"]).getutc + 1)

      expect(second.payload[:pass_outcome]).to eq("fetched")
      expect(second.payload[:outcome]).to eq("document_created")
      expect(requests).to eq(["/"])
      expect(attempts(ctx[:crawl_id]).map { |r| r["crawl_frontier_entry_id"] }).to eq([root["id"]])

      # THE SEAL RELEASED, which is what makes the depth-1 candidate reachable at all (ADR-087). Before
      # this edge existed, the root stayed `in_progress` forever, `sealed_depth` — MIN(depth) over
      # ('queued','in_progress','fetched_pending_commit') — stayed 0, and the sitemap URL this run
      # discovered was permanently unselectable. The next link proves it moved.
      expect(second.payload[:frontier_seal_released]).to be(true)
      discovered = entries(ctx[:crawl_id]).last
      expect(entries(ctx[:crawl_id]).map { |r| [r["depth"].to_i, r["state"]] })
        .to eq([[0, "terminal"], [1, "queued"]])
      expect(second.payload[:next_frontier_entry_id]).to eq(discovered["id"])
      expect(second.payload[:frontier_drained]).to be(false)

      # THE THIRD PASS fetches the depth-1 content URL the sitemap named, and the run drains.
      requests.clear
      third_action = action_row(second.payload[:next_action_id])
      clear_rate_window(gate["id"])
      third = execute(ctx, third_action, outbound_by_path("/p1" => html(path: "/p1")),
                      at: Time.parse(third_action["due_at"]).getutc + 1)

      expect(third.payload[:pass_outcome]).to eq("fetched")
      expect(third.payload[:outcome]).to eq("document_created")
      expect(requests).to eq(["/p1"])
      expect(third.payload[:frontier_seal_released]).to be(true)
      expect(third.payload[:frontier_drained]).to be(true)
      expect(entries(ctx[:crawl_id]).map { |r| r["state"] }).to eq(%w[terminal terminal])
      expect(attempts(ctx[:crawl_id]).map { |r| r["canonical_url"] })
        .to eq(["https://shop.acme.example/", "https://shop.acme.example/p1"])
    end

    it "admits at execution: the entry is claimed, the reservation is the fetch's, and #1 is the attempt" do
      ctx = fetchable
      result = execute(ctx, first_action(ctx), outbound_by_path("/" => html))

      expect(result.success?).to be(true)
      expect(result.payload[:pass_outcome]).to eq("fetched")
      root = entries(ctx[:crawl_id]).first
      # `terminal` and not `in_progress`: the pass claimed the entry, decided its fetch, and released
      # :454's seal in the same pass (ADR-087). `in_progress` is the state DURING the fetch, which the
      # attempt row below is the durable record of.
      expect(root["state"]).to eq("terminal")
      expect(result.payload[:frontier_seal_released]).to be(true)
      rows = attempts(ctx[:crawl_id])
      expect(rows.size).to eq(1)
      expect(rows.first["attempt_number"]).to eq("1")
      expect(rows.first["crawl_frontier_entry_id"]).to eq(root["id"])
      expect(rows.first["outcome"]).to eq("document_created")
      expect(rows.first["reserved_bytes"].to_i).to eq(Workflows::Wf005::ByteAccounting::PER_URL_CEILING)
      expect(counters(ctx[:crawl_id])["committed_response_bytes"].to_i).to eq(html.body.bytesize)
      expect(result.payload[:accounted_response_bytes]).to eq(html.body.bytesize)
    end

    it "links the next pass to the next root and reports a drained frontier when there is none" do
      ctx = fetchable(hosts: %w[shop.acme.example zeta.acme.example])
      roots = entries(ctx[:crawl_id])
      expect(roots.size).to eq(2)

      advancing = execute(ctx, first_action(ctx), outbound_by_path("/" => html))

      expect(advancing.payload[:next_frontier_entry_id]).to eq(roots.last["id"])
      expect(advancing.payload[:frontier_drained]).to be(false)
      nxt = action_row(advancing.payload[:next_action_id])
      expect(nxt["target_type"]).to eq("crawl_frontier_entry")
      expect(nxt["target_id"]).to eq(roots.last["id"])
      # A different host with no gate row has no pacing debt, so the link is due immediately.
      expect(Time.parse(nxt["due_at"]).getutc).to eq(start_now)

    end

    it "reports a drained frontier rather than linking to nothing" do
      ctx = fetchable
      result = execute(ctx, first_action(ctx), outbound_by_path("/" => html))

      expect(result.payload[:frontier_drained]).to be(true)
      expect(result.payload[:next_action_id]).to be_nil
      expect(fetch_actions(ctx[:crawl_id]).size).to eq(1)
    end
  end

  # ---- FU-19: the scheduler owns waiting, the worker owns one bounded attempt (ADR-089) ------------

  describe ":444's retries, one attempt per execution" do
    def timeout = Platform::Outbound::Outcome.timeout(canonical_host: "shop.acme.example")

    # The chain as the transport runs it: execute, follow the link the terminal transaction created,
    # execute that at ITS due instant, and so on. `clear_rate_window` between passes stands for the 30 or
    # 120 seconds that genuinely elapse — :442's rolling second is long spent by then.
    def run_chain(ctx, outbound, limit: 5)
      action = first_action(ctx)
      [].tap do |results|
        limit.times do
          results << execute(ctx, action, outbound, at: Time.parse(action["due_at"]).getutc)
          nxt = results.last.success? && results.last.payload[:next_action_id]
          break unless nxt

          clear_rate_window(gate_row(ctx[:crawl_id])["id"])
          action = action_row(nxt)
        end
      end
    end

    it "PROOF 1 — one attempt, its outcome committed, exactly one re-entry at completion + 30s" do
      ctx = fetchable
      action = first_action(ctx)

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = execute(ctx, action, outbound_by_path("/" => timeout))
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - elapsed

      expect(result.payload[:pass_outcome]).to eq("retrying")
      expect(requests).to eq(["/"])
      rows = attempts(ctx[:crawl_id])
      expect(rows.map { |r| r["attempt_number"] }).to eq(["1"])
      expect(rows.first["outcome"]).to eq("content_fetch_failed")
      # EXACTLY ONE re-entry, against the SAME entry, at :444's instant measured from the attempt's own
      # committed completion — not from this worker's clock.
      links = fetch_actions(ctx[:crawl_id])
      expect(links.size).to eq(2)
      reentry = action_row(result.payload[:next_action_id])
      expect(reentry["target_id"]).to eq(rows.first["crawl_frontier_entry_id"])
      expect(Time.parse(reentry["due_at"]).getutc)
        .to eq(Time.parse(rows.first["completed_at"]).getutc + 30)
      # AND `completed_at` IS THE ATTEMPT'S COMPLETION, not the pass's start instant. :444 measures from
      # "completion of the failed attempt", and every other timestamp here comes from the injected clock
      # captured before the pass began — so a hard-timeout attempt used to come due a full request timeout
      # EARLY. The recorded latency is what makes the column mean its name.
      # A timed-out attempt ran to the hard request bound by definition — the rule the limit observer
      # already applies for the same reason — so its completion is the bound, not the pass's start. Before
      # this, the retry came due a full 15 seconds early.
      timeout_s = Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING
                  .fetch("request_timeout_seconds").fetch("hard")
      expect(Time.parse(rows.first["completed_at"]).getutc).to eq(start_now + timeout_s)
      expect(Time.parse(reentry["due_at"]).getutc).to eq(start_now + timeout_s + 30)
      # THE WORKER DID NOT WAIT IT OUT. Generous by three orders of magnitude against the 30 s the
      # in-process loop used to sleep: this asserts the delay was not taken, not that the database is fast.
      expect(elapsed).to be < 5.0
    end

    it "PROOF 2 — the second pass resumes from committed state and owes 120s, without renumbering" do
      ctx = fetchable
      first, second = run_chain(ctx, outbound_by_path("/" => timeout), limit: 2)

      expect(first.payload[:pass_outcome]).to eq("retrying")
      expect(second.payload[:pass_outcome]).to eq("retrying")
      rows = attempts(ctx[:crawl_id])
      expect(rows.map { |r| r["attempt_number"] }).to eq(%w[1 2])
      # The entry was never re-admitted: one claim, one reservation, continuous across both passes.
      expect(entries(ctx[:crawl_id]).first["state"]).to eq("in_progress")
      expect(rows.map { |r| r["reserved_bytes"].to_i }.uniq.size).to eq(1)
      reentry = action_row(second.payload[:next_action_id])
      expect(Time.parse(reentry["due_at"]).getutc)
        .to eq(Time.parse(rows.last["completed_at"]).getutc + 120)
      expect(second.payload[:frontier_seal_released]).to be(false)
    end

    it "PROOF 3 — the third pass creates no retry, releases the whole remainder, and terminalises" do
      ctx = fetchable
      passes = run_chain(ctx, outbound_by_path("/" => timeout))

      expect(passes.size).to eq(3)
      expect(passes.map { |r| r.payload[:pass_outcome] }).to eq(%w[retrying retrying fetched])
      expect(passes.last.payload[:outcome]).to eq("content_fetch_failed")
      expect(attempts(ctx[:crawl_id]).map { |r| r["attempt_number"] }).to eq(%w[1 2 3])
      # :442 — unused bytes are released. Nothing is left reserved beyond what was accounted.
      row = counters(ctx[:crawl_id])
      expect(row["reserved_response_bytes"].to_i).to eq(row["committed_response_bytes"].to_i)
      expect(row["reserved_response_bytes"].to_i).to eq(0)
      # The seal is released only now, at the terminal outcome, and the run advances.
      expect(passes.last.payload[:frontier_seal_released]).to be(true)
      expect(entries(ctx[:crawl_id]).first["state"]).to eq("terminal")
      # THREE passes, THREE actions plus the first link: no retry after the bound.
      expect(fetch_actions(ctx[:crawl_id]).size).to eq(3)
    end

    it "PROOF 4 — retry then success: numbering and pacing preserved, ONE forward link, counters exact" do
      ctx = fetchable(hosts: %w[shop.acme.example zeta.acme.example])
      body = "<html><title>ok</title></html>"
      # Two passes only: the third link this creates targets the OTHER Source, whose robots are unresolved,
      # and that pass is a different property (asserted above).
      passes = run_chain(ctx, outbound_by_path("/" => [timeout, html(body:)]), limit: 2)

      expect(passes.map { |r| r.payload[:pass_outcome] }).to eq(%w[retrying fetched])
      expect(passes.last.payload[:outcome]).to eq("document_created")
      expect(attempts(ctx[:crawl_id]).map { |r| r["attempt_number"] }).to eq(%w[1 2])
      row = counters(ctx[:crawl_id])
      expect(row["committed_response_bytes"].to_i).to eq(body.bytesize)
      expect(row["reserved_response_bytes"].to_i).to eq(body.bytesize)
      # ONE forward link from the successful pass — to the OTHER Source's root, not a second retry.
      expect(passes.last.payload[:next_frontier_entry_id]).to eq(entries(ctx[:crawl_id]).last["id"])
      expect(fetch_actions(ctx[:crawl_id]).size).to eq(3)
    end

    it "PROOF 5 — a duplicate delivery links no second retry and creates no second attempt" do
      ctx = fetchable
      action = first_action(ctx)
      first = execute(ctx, action, outbound_by_path("/" => timeout))
      requests.clear

      replay = execute(ctx, action, outbound_by_path({}))

      expect(replay.replayed).to be(true)
      expect(replay.payload[:next_action_id]).to eq(first.payload[:next_action_id])
      expect(requests).to be_empty
      expect(attempts(ctx[:crawl_id]).size).to eq(1)
      expect(fetch_actions(ctx[:crawl_id]).size).to eq(2)
    end

    it "PROOF 5b — the retry instant is DERIVED, and a re-derivation of it links no second action" do
      # WHAT THIS DOES AND DOES NOT PROVE, stated because the first version of it overclaimed. It proves the
      # instant is a function of committed state, so ANY party deriving it lands on the same
      # ScheduledAction identity and the second link replays. It does NOT prove that two concurrent
      # deliveries race here: review established they cannot, because the attempt identity's `ON CONFLICT`
      # stops the second delivery before it reaches a retry decision. Single-linking is therefore enforced
      # by the attempt identity first and by this determinism second, and both are recorded that way.
      ctx = fetchable
      execute(ctx, first_action(ctx), outbound_by_path("/" => timeout))
      attempt = attempts(ctx[:crawl_id]).first
      # Derived from the row, exactly as the driver derives it — not from any clock this example holds.
      at = Time.parse(attempt["completed_at"]).getutc + 30

      again = Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
        IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg)
          .enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
        Workflows::Wf005::CrawlFetchDueSchedule.reenter(
          pg:, organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
          crawl_id: ctx[:crawl_id], entry_id: attempt["crawl_frontier_entry_id"], at:, now: start_now,
          correlation_id: SecureRandom.uuid_v7
        )
      end

      expect(again[:replayed]).to be(true)
      expect(fetch_actions(ctx[:crawl_id]).size).to eq(2)
    end

    it "PROOF 8 — a pass that performed NO attempt retires nothing and hands back nothing" do
      # Two deliveries of one action can be in flight, and the one whose host-gate claim is refused used to
      # release the in-flight winner's reservation and retire its entry — a `PG::CheckViolation` escaping the
      # workflow and an entry terminal after 2 of 3 attempts. A pass that made no request now decides
      # nothing: no release, no retirement, no seal, and it comes back.
      ctx = fetchable
      action = first_action(ctx)
      # The host gate is at its rate ceiling, so this pass's content claim is refused before any request.
      seed_leases(gate_row(ctx[:crawl_id])["id"], 8)

      result = execute(ctx, action, outbound_by_path({}))

      expect(result.payload[:pass_outcome]).to eq("deferred")
      expect(requests).to be_empty
      expect(attempts(ctx[:crawl_id])).to be_empty
      expect(result.payload[:frontier_seal_released]).to be(false)
      # The entry was admitted by this pass, so it is claimed — but nothing was retired and the reservation
      # it paid for is still the run's to spend on the retry.
      expect(entries(ctx[:crawl_id]).first["state"]).to eq("in_progress")
      row = counters(ctx[:crawl_id])
      expect(row["reserved_response_bytes"].to_i)
        .to eq(Workflows::Wf005::ByteAccounting::PER_URL_CEILING)
      expect(row["committed_response_bytes"].to_i).to eq(0)
      expect(result.payload[:next_action_id]).not_to be_nil
    end

    it "PROOF 9 — every attempt of a retried URL records the scope policy that authorized it" do
      # The T-IMM attempt row is the record of a request that left the platform, and the pinned Source Scope
      # Policy version is part of the input that permitted it. The resume path read the entry through a
      # SELECT that omitted both columns, so attempts 2 and 3 persisted NULL/NULL — silently, because both
      # columns are nullable, and unrewritably, because the row is write-once.
      ctx = fetchable
      run_chain(ctx, outbound_by_path("/" => timeout))

      rows = attempts(ctx[:crawl_id])
      expect(rows.map { |r| r["attempt_number"] }).to eq(%w[1 2 3])
      expect(rows.map { |r| r["scope_policy_id"] }.compact.size).to eq(3)
      expect(rows.map { |r| r["scope_policy_version"] }.uniq).to eq(["source-scope-interim-v1"])
      # And the ordering tuple :456 replays by is on every one of them.
      expect(rows.map { |r| r["dequeue_key"] }.compact.size).to eq(3)
    end

    it "PROOF 10 — a resume is admitted only for the stage it was scheduled for" do
      # Without this, two deliveries in flight between one pass's settle and its terminal transaction both
      # qualify as resumable, then compute DIFFERENT attempt numbers and fetch one URL concurrently on one
      # reservation — which the attempt identity cannot catch, because the numbers differ. The action's own
      # `due_at` is :444's instant for exactly one attempt.
      ctx = fetchable
      first = execute(ctx, first_action(ctx), outbound_by_path("/" => timeout))
      reentry = action_row(first.payload[:next_action_id])
      clear_rate_window(gate_row(ctx[:crawl_id])["id"])
      # An action for the SAME entry at an instant that is not this stage's: it must not resume.
      wrong_stage = action_row(
        Platform::UnitOfWork.run do |conn|
          pg = conn.raw_connection
          IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg)
            .enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
          Workflows::Wf005::CrawlFetchDueSchedule.reenter(
            pg:, organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
            crawl_id: ctx[:crawl_id], entry_id: entries(ctx[:crawl_id]).first["id"],
            at: Time.parse(reentry["due_at"]).getutc + 7, now: start_now,
            correlation_id: SecureRandom.uuid_v7
          )[:action_id]
        end
      )

      requests.clear
      result = execute(ctx, wrong_stage, outbound_by_path({}),
                       at: Time.parse(wrong_stage["due_at"]).getutc)

      expect(result.payload[:pass_outcome]).to eq("superseded")
      expect(requests).to be_empty
      expect(attempts(ctx[:crawl_id]).map { |r| r["attempt_number"] }).to eq(["1"])
    end

    it "PROOF 12 — a duplicate idempotency write LOSES rather than destroying the other delivery" do
      # THE DEFECT THIS CLOSES, demonstrated by the concurrency and security lenses with two connections.
      # `insert_idempotency` was a bare INSERT against `idempotency_scope_key`, so the second delivery to
      # commit did not merely lose — its unique violation ROLLED BACK THE OTHER DELIVERY'S ENTIRE TERMINAL
      # TRANSACTION, and for `crawl_fetch_due` that transaction also carries the run's only forward link.
      # Observed end state was a dead run: entry claimed, the whole per-URL reservation charged with nothing
      # accounted, a real request with no ledger row, and no scheduled action anywhere. Two concurrent
      # deliveries of one action are ORDINARY — the transport recovers an expired worker lease and
      # re-dispatches — and the idempotency record cannot prevent that, because it is written at the END of
      # the work it protects.
      #
      # ASSERTED AT THE STORE, deliberately. The interleaving needs two connections and injected latency;
      # what the repair actually is, is that the second write LOSES QUIETLY instead of raising. That is
      # exactly what this asserts, and it is what the reviewers' reproduction turned on.
      ctx = fetchable
      result = execute(ctx, first_action(ctx), outbound_by_path("/" => timeout))
      expect(result.payload[:pass_outcome]).to eq("retrying")

      row = DbInspector.one(<<~SQL, [ctx[:crawl_id]])
        SELECT i.* FROM idempotency_records i
        JOIN crawl_frontier_entries e ON e.id = i.target_id
        WHERE i.target_type = 'crawl_frontier_entry' AND e.crawl_id = $1::uuid
      SQL
      expect(row).to be_present

      second = Platform::UnitOfWork.run do |conn|
        store = IdentityAccess::Infrastructure::CrawlStartStore.new(conn.raw_connection)
        store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
        store.insert_idempotency(
          id: Platform::Ids.system.generate, created_at: start_now.iso8601(6),
          organization_id: row["organization_id"], command_type: row["command_type"],
          target_type: row["target_type"], target_id: row["target_id"],
          key_digest: [row["key_digest"].sub(/\A\\x/, "")].pack("H*"),
          request_sha256: [row["request_sha256"].sub(/\A\\x/, "")].pack("H*"),
          command_execution_id: row["command_execution_id"], command_result_id: row["command_result_id"],
          retain_until: row["retain_until"]
        )
      end

      # ZERO ROWS, NOT AN EXCEPTION. The losing delivery learns it lost; it does not take the winner with it.
      expect(second).to eq(0)
      expect(DbInspector.all(<<~SQL, [ctx[:crawl_id]]).size).to eq(1)
        SELECT i.id FROM idempotency_records i
        JOIN crawl_frontier_entries e ON e.id = i.target_id
        WHERE i.target_type = 'crawl_frontier_entry' AND e.crawl_id = $1::uuid
      SQL
      # And the winner's forward link is intact, which is the thing the abort used to destroy.
      expect(action_row(result.payload[:next_action_id])["status"]).to eq("pending")
    end

    it "PROOF 11 — the swept-attempt guard matches the reason the sweep actually writes" do
      # WHY THIS IS THE PROVABLE HALF, and what is not. `sweep_expired` terminalizes a lost attempt as
      # `timed_out` / retryable / zero-accounted AND releases its reservation, which satisfies every other
      # resume condition — so `resumable_retry` refuses on the sweep's reason code. Reaching that state
      # through the driver is NOT possible today: the attempt row is write-once (the guard refuses a
      # rewrite, verified), the sweep only runs inside `one_attempt`, and with one live chain no pass can
      # sweep between another's loss and its redelivery. So the refusal itself is untested by construction
      # and recorded in FU-24, like FU-23's latent guards.
      #
      # WHAT IS LOAD-BEARING AND IS TESTED: the guard compares against a constant, and the sweep writes it.
      # If the sweep's reason ever changed, the guard would silently stop matching and the resume would
      # spend released bytes. That coupling is what this asserts.
      ctx = fetchable
      entry = entries(ctx[:crawl_id]).first
      swept = Platform::UnitOfWork.run do |conn|
        raw = conn.raw_connection
        store = IdentityAccess::Infrastructure::FetchAttemptStore.new(raw)
        store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
        gate = gate_row(ctx[:crawl_id])
        # Claimed far enough in the past that its 300-second lease has already expired.
        store.claim(id: Platform::Ids.system.generate, now: start_now - 600,
                    correlation_id: SecureRandom.uuid_v7, causation_id: SecureRandom.uuid_v7,
                    command_id: nil, organization_id: ctx[:g][:organization_id],
                    project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id],
                    crawl_host_gate_id: gate["id"], source_id: entry["source_id"],
                    frontier_entry_id: entry["id"], kind: "content", attempt_number: 1,
                    canonical_url: entry["canonical_url"], canonical_host: ctx[:host], depth: 0,
                    dequeue_key: nil, scope_policy_id: entry["scope_policy_id"],
                    scope_policy_version: entry["scope_policy_version"], crawl_policy_id: nil,
                    crawl_policy_version: nil, reserved_bytes: 1024,
                    claim_owner: Platform::Ids.system.generate, deadline_at: start_now)
        store.sweep_expired(ctx[:g][:organization_id], ctx[:crawl_id], start_now)
      end

      expect(swept.size).to eq(1)
      row = attempts(ctx[:crawl_id]).first
      expect(row["outcome"]).to eq("timed_out")
      expect(row["reason_code"])
        .to eq(IdentityAccess::Infrastructure::FetchAttemptStore::LEASE_EXPIRED_REASON)
      expect(Platform::PgBool.true?(row["retryable"])).to be(true)
      expect(row["accounted_response_bytes"].to_i).to eq(0)
      # And the row is write-once, which is why the state above cannot be fabricated into a resume.
      expect {
        DbInspector.connection.exec_params(
          "UPDATE fetch_attempts SET reason_code = 'other', checkpoint_version = checkpoint_version + 1 WHERE id = $1::uuid",
          [row["id"]])
      }.to raise_error(PG::RaiseException, /fetch_attempt_result_frozen/)
    end
  end

  describe "a pass that decides nothing re-enters against the same entry" do
    it "honours :444's robots schedule and leaves the frontier exactly as it found it" do
      ctx = gated
      result = execute(ctx, first_action(ctx), outbound_by_path("/robots.txt" => html(status: 503, body: "busy", type: "text/plain", path: "/robots.txt")))

      expect(result.success?).to be(true)
      expect(result.payload[:pass_outcome]).to eq("deferred")
      expect(result.payload[:reason_code]).to eq("robots_resolving")
      # ONE network attempt, and neither a sitemap nor the content URL: robots is the precondition of
      # both, and `EnsureRobots` makes at most one attempt per call.
      expect(requests).to eq(["/robots.txt"])
      expect(attempts(ctx[:crawl_id])).to be_empty
      expect(entries(ctx[:crawl_id]).first["state"]).to eq("queued")
      expect(DbInspector.all("SELECT id FROM crawl_budget_counters WHERE crawl_id=$1::uuid",
                             [ctx[:crawl_id]])).to be_empty

      # The re-entry names the SAME entry, 30 seconds out — :444's first delay, read from the result
      # rather than assumed.
      reentry = action_row(result.payload[:next_action_id])
      expect(reentry["target_id"]).to eq(entries(ctx[:crawl_id]).first["id"])
      expect(Time.parse(reentry["due_at"]).getutc).to eq(start_now + 30)
      expect(result.payload[:frontier_seal_released]).to be(false)
    end
  end

  describe "a pass that may not start a request halts the chain" do
    it "records the ratified wall-clock limit and schedules nothing once the run has expired" do
      # :442 — "At 60 elapsed minutes, NO NEW REQUEST STARTS", which binds robots and sitemap requests
      # too, so the wall clock is consulted before the first of the three. The DECISION stays
      # `Admission`'s, which is the ratified observation point and refuses before it peeks.
      ctx = fetchable
      action = first_action(ctx)
      DbInspector.connection.exec_params(
        "UPDATE crawls SET deadline_at = $2::timestamptz, state_version = state_version + 1 WHERE id = $1::uuid",
        [ctx[:crawl_id], (start_now - 1).utc.iso8601(6)])

      result = execute(ctx, action, outbound_by_path({}))

      expect(result.success?).to be(true)
      expect(result.payload[:pass_outcome]).to eq("halted")
      expect(result.payload[:reason_code]).to eq(Workflows::Wf005::Admission::WALL_CLOCK)
      expect(requests).to be_empty
      expect(result.payload[:next_action_id]).to be_nil
      expect(fetch_actions(ctx[:crawl_id]).size).to eq(1)
      expect(DbInspector.one(<<~SQL, [ctx[:crawl_id]])).to be_present
        SELECT id FROM crawl_limit_decisions
        WHERE crawl_id = $1::uuid AND limit_dimension = 'wall_clock_run_duration' AND threshold_kind = 'hard'
      SQL
      expect(entries(ctx[:crawl_id]).first["state"]).to eq("queued")
      expect(attempts(ctx[:crawl_id])).to be_empty
    end

    it "starts NO request past the deadline, not even robots or a sitemap" do
      # The half of :442 that the limit decision alone does not prove. `Admission` refuses an expired
      # run whatever the driver does, so a pass that consulted the wall clock only at admission would
      # still have fetched robots and a sitemap first — two requests against a host whose run is over.
      # Here neither record is resolved and the outbound facade permits NOTHING, so any request fails
      # the example rather than being absorbed.
      ctx = gated
      action = first_action(ctx)
      DbInspector.connection.exec_params(
        "UPDATE crawls SET deadline_at = $2::timestamptz, state_version = state_version + 1 WHERE id = $1::uuid",
        [ctx[:crawl_id], (start_now - 1).utc.iso8601(6)])

      result = execute(ctx, action, outbound_by_path({}))

      expect(result.payload[:pass_outcome]).to eq("halted")
      expect(result.payload[:reason_code]).to eq(Workflows::Wf005::Admission::WALL_CLOCK)
      expect(requests).to be_empty
      expect(gate_row(ctx[:crawl_id])["robots_state"]).to eq("pending")
      expect(result.payload[:next_action_id]).to be_nil
    end

  end

  describe "a fail-closed host does not stop the run (:448, :452)" do
    it "retires only the fail-closed host's entry and carries the run on to the healthy Source" do
      # :448 scopes fail-closed to "that host"; :452 to "that Source root"; MTX-030 fails the Crawl only
      # when EVERY active Source root fails. This pass used to `halt`, which created no link — so a
      # two-Source Project with one 403 robots host never requested the healthy host and left a `running`
      # Crawl with no scheduled work at all. Found by two independent reviewers, reproduced with two
      # Sources.
      ctx = gated(hosts: %w[shop.acme.example zeta.acme.example])
      roots = entries(ctx[:crawl_id])
      expect(roots.map { |r| r["state"] }).to eq(%w[queued queued])
      resolve_robots(ctx, outbound_returning(response(status: 403, body: "no")))
      expect(gate_row(ctx[:crawl_id])["robots_state"]).to eq("unavailable")

      result = execute(ctx, first_action(ctx), outbound_by_path({}))

      expect(result.payload[:pass_outcome]).to eq("retired")
      expect(result.payload[:reason_code]).to eq("robots_unavailable_fail_closed")
      # NO REQUEST, no attempt row, no byte reserved: the host was refused, not tried.
      expect(requests).to be_empty
      expect(attempts(ctx[:crawl_id])).to be_empty
      expect(DbInspector.all("SELECT id FROM crawl_budget_counters WHERE crawl_id=$1::uuid",
                             [ctx[:crawl_id]])).to be_empty

      # The unfetchable entry left the SELECTABLE set through the edge this tranche built, and the run
      # advanced to the other Source. `terminal` and not `discarded`: :452 keeps an unretrieved in-scope
      # candidate in the coverage denominator, and the durable reason lives on the gate.
      expect(entries(ctx[:crawl_id]).map { |r| r["state"] }).to eq(%w[terminal queued])
      expect(entries(ctx[:crawl_id]).first["reason"]).to be_nil
      expect(result.payload[:next_frontier_entry_id]).to eq(roots.last["id"])
      expect(result.payload[:frontier_drained]).to be(false)
      expect(action_row(result.payload[:next_action_id])["target_id"]).to eq(roots.last["id"])
    end

    it "retires ONLY the entry the action named, never whatever happens to be next" do
      # The retirement claims through `peek_next` under the frontier lock, so it must verify the candidate
      # IS the named entry — exactly as `Admission#claim_entry` does. Retiring whatever is next would
      # destroy a different Source's candidate on the strength of THIS host's robots record.
      ctx = gated(hosts: %w[shop.acme.example zeta.acme.example])
      roots = entries(ctx[:crawl_id])
      action = first_action(ctx)
      resolve_robots(ctx, outbound_returning(response(status: 403, body: "no")))
      # Another pass claimed the fail-closed root and was lost, so `peek_next` now returns the OTHER root.
      Platform::UnitOfWork.run do |conn|
        store = IdentityAccess::Infrastructure::CrawlFrontierStore.new(conn.raw_connection)
        store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
        store.lock_frontier(ctx[:crawl_id])
        store.claim_next(ctx[:g][:organization_id], ctx[:crawl_id], start_now)
      end

      result = execute(ctx, action, outbound_by_path({}))

      expect(result.payload[:pass_outcome]).to eq("superseded")
      # The healthy Source's root is untouched — still `queued`, still selectable.
      expect(entries(ctx[:crawl_id]).map { |r| r["state"] }).to eq(%w[in_progress queued])
      expect(result.payload[:next_frontier_entry_id]).to eq(roots.last["id"])
    end

    it "reports a PINNED frontier as pinned, never as drained" do
      # `peek_next` returns nil for two different facts: nothing left to do, and work left that is not
      # SELECTABLE because a stranded `in_progress` claim holds `sealed_depth`. Reporting the second as
      # `frontier_drained` told a reader the crawl had finished when it had silently stopped. Recovering
      # the stranded claim is S-07-011's; telling the two apart is this tranche's.
      ctx = fetchable
      root = entries(ctx[:crawl_id]).first
      action = first_action(ctx)
      in_frontier_of(ctx) do |store|
        # A deeper candidate exists, then the root is claimed and its pass is lost: depth 0 is pinned, so
        # the depth-1 entry is unreachable even though it is `queued`.
        store.lock_frontier(ctx[:crawl_id])
        store.claim_next(ctx[:g][:organization_id], ctx[:crawl_id], start_now)
      end
      offer_depth_one(ctx, root)

      result = execute(ctx, action, outbound_by_path({}))

      expect(result.payload[:pass_outcome]).to eq("superseded")
      expect(result.payload[:frontier_pinned]).to be(true)
      expect(result.payload[:frontier_drained]).to be(false)
      expect(result.payload[:next_action_id]).to be_nil
      expect(entries(ctx[:crawl_id]).map { |r| r["state"] }).to eq(%w[in_progress queued])
    end

    it "retires the LAST unfetchable entry and then reports a genuinely drained frontier" do
      ctx = gated
      resolve_robots(ctx, outbound_returning(response(status: 403, body: "no")))

      result = execute(ctx, first_action(ctx), outbound_by_path({}))

      expect(result.payload[:pass_outcome]).to eq("retired")
      expect(result.payload[:frontier_drained]).to be(true)
      expect(result.payload[:frontier_pinned]).to be(false)
      expect(result.payload[:next_action_id]).to be_nil
      expect(entries(ctx[:crawl_id]).map { |r| r["state"] }).to eq(["terminal"])
    end
  end

  describe "run-scoped authorization is the FIRST effectful boundary (MTX-030)" do
    # "An authorization established at queue time is never trusted at execution time." The pass's first
    # effects are a `crawl_host_gates` row, a robots request and a WRITE-ONCE sitemap outcome, and all
    # three used to happen before admission reached the gate. Both examples below were failures found by
    # the security lens and reproduced against a suspended tenant and a lapsed reservation.

    it "makes NO request and writes NO gate row once the Organization is suspended" do
      ctx = running_crawl
      action = first_action(ctx)
      expect(suspend_organization(ctx[:g]).success?).to be(true)

      result = execute(ctx, action, outbound_by_path({}))

      expect(result.success?).to be(true)
      expect(result.payload[:pass_outcome]).to eq("halted")
      expect(result.payload[:reason_code]).to eq("admission_organization_inactive")
      # The three effects that used to precede the gate.
      expect(requests).to be_empty
      expect(gate_row(ctx[:crawl_id])).to be_nil
      expect(attempts(ctx[:crawl_id])).to be_empty
      expect(result.payload[:next_action_id]).to be_nil
      expect(entries(ctx[:crawl_id]).first["state"]).to eq("queued")
    end

    it "makes NO request and writes NO gate row once the entitlement reservation has lapsed" do
      # The harm here was worse than a wasted request: the pass reached sitemap discovery and wrote the
      # WRITE-ONCE `sitemap_unavailable`, which :450/:452 turn into permanently partial coverage for the
      # Source root — attributing to the host a failure that was entirely our own authorization result.
      ctx = running_crawl
      action = first_action(ctx)
      # Expired against the RUN's clock, not the wall clock: `reservation_executing?` compares `lease_due`
      # to the instant the caller injects, and `now()` here is three days AFTER the fixture's `start_now`,
      # so a real-time expiry would have left the lease valid and the example would have proved nothing.
      lapsed = DbInspector.connection.exec_params(<<~SQL, [ctx[:crawl_id], (start_now - 3600).utc.iso8601(6)])
        UPDATE entitlement_reservations SET lease_due = $2::timestamptz,
               state_version = state_version + 1
        WHERE id = (SELECT entitlement_reservation_id FROM crawls WHERE id = $1::uuid)
      SQL
      expect(lapsed.cmd_tuples).to eq(1), "the reservation was not lapsed; the example would be vacuous"

      result = execute(ctx, action, outbound_by_path({}))

      expect(result.payload[:pass_outcome]).to eq("halted")
      expect(result.payload[:reason_code]).to eq("admission_entitlement_not_executing")
      expect(requests).to be_empty
      expect(gate_row(ctx[:crawl_id])).to be_nil
      expect(entries(ctx[:crawl_id]).first["state"]).to eq("queued")
    end
  end

  describe "the same action delivered twice" do
    it "replays the stored result and creates neither a second attempt nor a second link" do
      ctx = fetchable
      action = first_action(ctx)
      first = execute(ctx, action, outbound_by_path("/" => html))

      requests.clear
      replay = execute(ctx, action, outbound_by_path({}))

      expect(first.success?).to be(true)
      expect(replay.success?).to be(true)
      expect(replay.replayed).to be(true)
      expect(replay.payload[:frontier_entry_id]).to eq(first.payload[:frontier_entry_id])
      expect(requests).to be_empty
      expect(attempts(ctx[:crawl_id]).size).to eq(1)
      expect(fetch_actions(ctx[:crawl_id]).size).to eq(1)
    end

    it "refuses to claim an entry another pass already took, and hands the run on instead" do
      # `Admission#claim_entry` claims the NAMED entry or nothing. A redelivery whose original pass was
      # lost after claiming must not fetch a second, unrelated URL under the first one's identity, and
      # must not leave the chain dead either.
      ctx = fetchable(hosts: %w[shop.acme.example zeta.acme.example])
      roots = entries(ctx[:crawl_id])
      action = first_action(ctx)
      Platform::UnitOfWork.run do |conn|
        store = IdentityAccess::Infrastructure::CrawlFrontierStore.new(conn.raw_connection)
        store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
        store.lock_frontier(ctx[:crawl_id])
        store.claim_next(ctx[:g][:organization_id], ctx[:crawl_id], start_now)
      end

      result = execute(ctx, action, outbound_by_path({}))

      expect(result.payload[:pass_outcome]).to eq("superseded")
      expect(requests).to be_empty
      expect(attempts(ctx[:crawl_id])).to be_empty
      expect(result.payload[:next_frontier_entry_id]).to eq(roots.last["id"])
      # IT DOES NOT STEAL THE CLAIM IT DECLINED. The other pass's entry is left exactly as it was, no
      # seal is released, and the ledger attributes nothing to a fetch this pass never made.
      expect(result.payload[:frontier_seal_released]).to be(false)
      expect(entries(ctx[:crawl_id]).map { |r| r["state"] }).to eq(%w[in_progress queued])
      expect(result.payload[:outcome]).to be_nil
    end
  end

  describe "a delivery that loses its lease stops (F-04 FU-24, ADR-091)" do
    it "PROOF 13 — a confirmed transfer mid-pass produces NO request, NO ledger and NO link" do
      # The stale worker must not keep acting for a delivery it no longer owns. The keeper reports a
      # CONFIRMED transfer — not a transport failure — and the pass stops at its next safe boundary.
      ctx = fetchable
      action = first_action(ctx)
      before = entries(ctx[:crawl_id]).first
      lost = Platform::ScheduledActions::LeaseKeeper.new(
        action_id: action["id"], owner: SecureRandom.uuid_v7, generation: 0,
        lease_seconds: Platform::ScheduledActions::Worker::WORKER_LEASE_SECONDS
      )
      # A renewal against an action this owner never held is refused, which is exactly what a transfer
      # looks like from the stale worker's side.
      expect(lost.renew).to eq(Platform::ScheduledActions::LeaseKeeper::LOST)

      result = Platform::ScheduledActions::Lease.with(lost) do
        execute(ctx, action, outbound_by_path({}))
      end

      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("scheduled_action_lease_lost")
      expect(requests).to be_empty
      expect(attempts(ctx[:crawl_id])).to be_empty
      # NOTHING DURABLE: the frontier is untouched, no ledger row names this entry, and no link exists.
      expect(entries(ctx[:crawl_id]).first["state"]).to eq(before["state"])
      expect(entries(ctx[:crawl_id]).first["state_version"]).to eq(before["state_version"])
      expect(fetch_actions(ctx[:crawl_id]).size).to eq(1)
      expect(DbInspector.all(<<~SQL, [ctx[:crawl_id]])).to be_empty
        SELECT e.id FROM command_executions ce
        JOIN crawl_frontier_entries e ON e.id = ce.target_id
        WHERE ce.target_type = 'crawl_frontier_entry' AND e.crawl_id = $1::uuid
      SQL
    end

    it "PROOF 14 — a pass that loses its lease mid-flight mints NO forward action and NO ledger row" do
      # Both `deferred` returns used to precede the ownership guard, so a delivery that had already lost its
      # lease still wrote a full ledger set and MINTED A DUPLICATE `crawl_fetch_due` — including the
      # idempotency record the winning delivery would later collide with. Demonstrated by review.
      ctx = gated
      action = first_action(ctx)
      lost = Platform::ScheduledActions::LeaseKeeper.new(
        action_id: action["id"], owner: SecureRandom.uuid_v7, generation: 0,
        lease_seconds: Platform::ScheduledActions::Worker::WORKER_LEASE_SECONDS
      )
      # The cadence is due, so the authoritative guard genuinely asks the database rather than answering
      # from the keeper's construction.
      lost.instance_variable_set(:@renewed_at, lost.send(:monotonic) - 1_000)

      # Robots resolves, then the pass reaches the ownership boundary — which is now ABOVE every disposition.
      result = Platform::ScheduledActions::Lease.with(lost) do
        execute(ctx, action, outbound_by_path("/robots.txt" => robots_allow, "/sitemap.xml" => sitemap_missing))
      end

      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("scheduled_action_lease_lost")
      # NO forward action beyond the one that started the pass, and NO ledger row for this entry.
      expect(fetch_actions(ctx[:crawl_id]).size).to eq(1)
      expect(DbInspector.all(<<~SQL, [ctx[:crawl_id]])).to be_empty
        SELECT e.id FROM command_executions ce
        JOIN crawl_frontier_entries e ON e.id = ce.target_id
        WHERE ce.target_type = 'crawl_frontier_entry' AND e.crawl_id = $1::uuid
      SQL
      expect(DbInspector.all(<<~SQL, [ctx[:crawl_id]])).to be_empty
        SELECT i.id FROM idempotency_records i
        JOIN crawl_frontier_entries e ON e.id = i.target_id
        WHERE i.target_type = 'crawl_frontier_entry' AND e.crawl_id = $1::uuid
      SQL
    end

    it "PROOF 15 — the lease is renewed BEFORE each bounded request, not only where the code waits" do
      # The first heartbeat had exactly two renewal sites — between redirect hops, and the sitemap pacer —
      # and an ordinary pass reached NEITHER: robots and a first sitemap candidate are two bounded requests
      # with no wait between them, so 30 seconds could elapse with zero renewals. Measured then: 2 requests,
      # 0 heartbeat writes. The property is that a renewal boundary PRECEDES the request that spends the
      # time, which is asserted here from inside the request itself.
      ctx = gated
      action = first_action(ctx)
      # Claimed and dispatched through the REAL transport, so the keeper holds a lease that genuinely
      # renews — the same state a worker delivery runs in.
      keeper = keeper_for_dispatched(action)
      keeper.instance_variable_set(:@renewed_at, keeper.send(:monotonic) - 1_000)
      heartbeat_at_request = {}
      # Hoisted into locals: inside `define_singleton_method` the receiver is the stub, so calling an
      # example helper there raises — and `EnsureRobots#fetch` rescues any error as a RETRYABLE transport
      # failure, which would silently turn a broken stub into a passing-looking deferral.
      responses = { "/robots.txt" => robots_allow, "/sitemap.xml" => sitemap_missing }
      action_id = action["id"]
      outbound = Object.new.tap do |o|
        o.define_singleton_method(:fetch) do |url, **_kwargs|
          path = URI.parse(url.to_s).path
          heartbeat_at_request[path] =
            DbInspector.one("SELECT last_heartbeat_at FROM scheduled_actions WHERE id = $1::uuid",
                            [action_id])["last_heartbeat_at"]
          responses.fetch(path)
        end
      end

      Platform::ScheduledActions::Lease.with(keeper) { execute(ctx, action, outbound) }

      # AT THE MOMENT THE ROBOTS REQUEST WAS ISSUED the heartbeat had already been written — the boundary
      # precedes the request rather than following it. One renewal covers both requests, which is the
      # bounded cadence doing its job: more boundaries do not mean more writes.
      expect(heartbeat_at_request["/robots.txt"]).not_to be_nil
      expect(heartbeat_at_request.keys).to eq(["/robots.txt", "/sitemap.xml"])
    end

    it "PROOF 16 — losing the lease DURING discovery mints no action and writes no ledger" do
      # The guard used to sit BELOW both `deferred` returns, so a delivery that lost its lease during the
      # sitemap traversal still took a disposition: it wrote a full ledger set and minted a duplicate
      # `crawl_fetch_due`, including the idempotency record the winner would later collide with.
      # Demonstrated by review. Here the loss happens mid-pass, after the ownership guard has already
      # passed once — which is the interleaving the earlier example could not reach.
      ctx = gated
      action = first_action(ctx)
      keeper = keeper_for_dispatched(action)
      action_id = action["id"]
      sweeper = lambda do
        DbInspector.connection.exec_params(
          "UPDATE scheduled_actions SET lease_expires_at = now() - interval '1 second',
             state_version = state_version + 1 WHERE id = $1::uuid", [action_id])
        Platform::ScheduledActions::TransportConnection.with do |pg|
          Platform::ScheduledActions::Store.new(pg).release_expired_leases(limit: 10)
        end
      end
      responses = { "/robots.txt" => robots_allow, "/sitemap.xml" => sitemap_missing }
      outbound = Object.new.tap do |o|
        o.define_singleton_method(:fetch) do |url, **_kwargs|
          path = URI.parse(url.to_s).path
          # The lease lapses and is swept WHILE the sitemap request is in flight, and the keeper's cadence
          # is forced due so the next guard genuinely asks.
          if path == "/sitemap.xml"
            sweeper.call
            keeper.instance_variable_set(:@renewed_at, keeper.send(:monotonic) - 1_000)
          end
          responses.fetch(path)
        end
      end

      result = Platform::ScheduledActions::Lease.with(keeper) { execute(ctx, action, outbound) }

      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("scheduled_action_lease_lost")
      # NOTHING DURABLE from a delivery that no longer owns the action.
      expect(fetch_actions(ctx[:crawl_id]).size).to eq(1)
      expect(DbInspector.all(<<~SQL, [ctx[:crawl_id]])).to be_empty
        SELECT e.id FROM command_executions ce
        JOIN crawl_frontier_entries e ON e.id = ce.target_id
        WHERE ce.target_type = 'crawl_frontier_entry' AND e.crawl_id = $1::uuid
      SQL
      expect(attempts(ctx[:crawl_id])).to be_empty
    end

    it "does not interfere when there is no lease, which is every non-worker caller" do
      ctx = fetchable
      expect(Platform::ScheduledActions::Lease.current).to be_nil

      result = execute(ctx, first_action(ctx), outbound_by_path("/" => html))

      expect(result.payload[:pass_outcome]).to eq("fetched")
    end
  end

  describe "transport integrity" do
    it "refuses an action naming a frontier entry that does not exist" do
      ctx = fetchable
      action = first_action(ctx).merge("target_id" => SecureRandom.uuid_v7)

      result = execute(ctx, action, outbound_by_path({}))

      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("scheduled_action_target_mismatch")
      expect(requests).to be_empty
    end

    it "refuses to run before the action is due" do
      ctx = fetchable
      action = first_action(ctx, at: start_now + 600)

      result = execute(ctx, action, outbound_by_path({}), at: start_now)

      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("scheduled_action_not_due")
      expect(requests).to be_empty
      expect(attempts(ctx[:crawl_id])).to be_empty
    end
  end
end
