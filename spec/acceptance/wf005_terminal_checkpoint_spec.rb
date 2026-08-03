# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# WF-005 THE TERMINAL CHECKPOINT (S-07-009) — :458's serialized terminal selection, driven through the
# REAL `crawl_terminal_deadline` handler over the production-real chain
# (WORKFLOW_SPECIFICATIONS.md :450, :452, :453, :458; BACKGROUND_PROCESSING.md :139/:199/:377).
#
# Until this tranche NOTHING TERMINALIZED A RUN. `f1_crawls_guard` admitted no edge out of `running`,
# nothing scheduled `crawl_terminal_deadline`, and a Crawl whose frontier drained stayed `running` for
# ever. These examples assert the whole of it: that the action exists, that it fires once, that the
# selection is derived from what the run recorded, and that the entitlement reservation is settled.
#
# THE COUNTS ARE READ BACK FROM THE LEDGER, not recomputed here. MTX-030's audit requirement is "the
# complete failed subset with counts and reasons; the derived coverage and completion", so a reader can
# re-derive the decision — and so can this spec, which is what makes the assertions about a DERIVATION
# rather than about a stored string.
RSpec.describe "WF-005 terminal checkpoint", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-E2E TYP-DATA TYP-INT] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  ALLOW_ALL_ROBOTS = "User-agent: *\nAllow: /\n"

  def outbound_by_path(map)
    Object.new.tap do |o|
      o.define_singleton_method(:fetch) do |url, **_kwargs|
        path = URI.parse(url.to_s).path
        raise "unexpected outbound fetch: #{url}" unless map.key?(path)

        entry = map[path]
        entry.is_a?(Array) ? (entry.length > 1 ? entry.shift : entry.first) : entry
      end
    end
  end

  def page(status: 200, body: "<html><title>t</title></html>", type: "text/html", path: "/")
    Platform::Outbound::Outcome.response(
      status:, headers: type.nil? ? {} : { "content-type" => type }, body:, byte_count: body.bytesize,
      truncated: false, canonical_host: "shop.acme.example", port: 443, pinned_address: "198.51.100.7",
      final_url: "https://shop.acme.example#{path}", redirect_count: 0, latency_ms: 5
    )
  end

  # A stub that answers AS THE HOST IT WAS ASKED. `outbound_by_path` reports one canonical host for every
  # request, which is fine while a run has one Source and silently fails a second Source's fetch on
  # :436's final-URL scope check. Keyed on "<host><path>", and the response it builds carries the
  # requested host in `canonical_host` and `final_url`.
  def outbound_by_host_path(map)
    Object.new.tap do |o|
      o.define_singleton_method(:fetch) do |url, **_kwargs|
        uri = URI.parse(url.to_s)
        key = "#{uri.host}#{uri.path}"
        raise "unexpected outbound fetch: #{url}" unless map.key?(key)

        spec = map[key]
        spec = spec.length > 1 ? spec.shift : spec.first if spec.is_a?(Array)
        body = spec.fetch(:body, "<html><title>t</title></html>")
        Platform::Outbound::Outcome.response(
          status: spec.fetch(:status, 200), headers: { "content-type" => spec.fetch(:type, "text/html") },
          body:, byte_count: body.bytesize, truncated: false, canonical_host: uri.host, port: 443,
          pinned_address: "198.51.100.7", final_url: "https://#{uri.host}#{uri.path}",
          redirect_count: 0, latency_ms: 5
        )
      end
    end
  end

  def crawl_row(cid) = DbInspector.one("SELECT * FROM crawls WHERE id = $1::uuid", [cid])
  def action_row(id) = DbInspector.one("SELECT * FROM scheduled_actions WHERE id = $1::uuid", [id])
  def entries(cid) = DbInspector.all("SELECT * FROM crawl_frontier_entries WHERE crawl_id=$1::uuid ORDER BY dequeue_key", [cid])

  # BOTH of them, in due order: the deadline one the accepted start scheduled, and the due-now one a
  # pass that drained the frontier scheduled for itself (ADR-101). Two distinct identities, both real.
  def terminal_actions(cid)
    DbInspector.all(<<~SQL, [cid])
      SELECT * FROM scheduled_actions
      WHERE action_kind = 'crawl_terminal_deadline' AND target_id = $1::uuid
      ORDER BY due_at
    SQL
  end

  def deadline_action(cid) = terminal_actions(cid).max_by { |a| Time.parse(a["due_at"]) }
  def drained_action(cid) = terminal_actions(cid).min_by { |a| Time.parse(a["due_at"]) }

  def events(cid)
    DbInspector.all(<<~SQL, [cid])
      SELECT * FROM event_registry WHERE aggregate_id = $1::uuid
        AND event_type IN ('CrawlCompleted','CrawlFailed','CrawlCanceled') ORDER BY created_at
    SQL
  end

  def reservation(cid)
    DbInspector.one(<<~SQL, [cid])
      SELECT r.* FROM entitlement_reservations r
      JOIN crawls c ON c.entitlement_reservation_id = r.id WHERE c.id = $1::uuid
    SQL
  end

  # A run whose robots and sitemap records are terminal and whose rate window is clear.
  def fetchable(hosts: ["shop.acme.example"])
    ctx = running_crawl(hosts:)
    ensure_gate(ctx)
    resolve_robots(ctx, outbound_returning(response(status: 200, body: ALLOW_ALL_ROBOTS)))
    resolve_sitemaps(ctx, outbound_returning(response(status: 404, body: "")))
    clear_rate_window_for_crawl(ctx[:crawl_id])
    ctx
  end

  # Drive the fetch chain to exhaustion, exactly as the transport does.
  # Each pass runs at ITS OWN due instant, which is what the transport does. Executing every pass at
  # `start_now` silently skipped :444's retries — they are due at `completed_at + 30s`, so the handler
  # refused them `scheduled_action_not_due` and the chain stopped one pass in.
  def drain(ctx, outbound, limit: 8, at: start_now)
    action = link_first(ctx, at:)
    return [] if action.nil?

    [].tap do |results|
      limit.times do
        results << execute_fetch(ctx, action, outbound, at: Time.parse(action["due_at"]).getutc)
        nxt = results.last.success? && results.last.payload[:next_action_id]
        break unless nxt

        clear_rate_window_for_crawl(ctx[:crawl_id])
        action = action_row(nxt)
      end
    end
  end

  def link_first(ctx, at: start_now)
    link = Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg)
                                                        .enter_org_context(org: ctx[:g][:organization_id],
                                                                          correlation_id: SecureRandom.uuid_v7)
      Workflows::Wf005::CrawlFetchDueSchedule.link_next(
        pg:, organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
        crawl_id: ctx[:crawl_id], now: at, correlation_id: SecureRandom.uuid_v7
      )
    end
    link[:action_id] && action_row(link[:action_id])
  end

  def execute_fetch(ctx, action, outbound, at: start_now)
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

  # The checkpoint, through the REAL registered handler and a REAL action. Defaults to the EARLIEST
  # one, which is the path an ordinary run actually takes: a pass that drains the frontier schedules a
  # checkpoint for itself, and the deadline one behind it then finds the Crawl terminal.
  def checkpoint(ctx, at: nil, action: nil)
    row = action || drained_action(ctx[:crawl_id])
    raise "no terminal checkpoint action exists" if row.nil?

    instant = at || Time.parse(row["due_at"]).getutc
    command = Workflows::Wf005::Commands::CompleteCrawl.new(
      command_id: SecureRandom.uuid_v7, schema_version: row["action_schema_version"],
      organization_id: row["organization_id"], target_type: row["target_type"],
      crawl_id: row["target_id"], due_at: Time.parse(row["due_at"]).getutc, action_id: row["id"],
      action_identity_sha256: [row["identity_sha256"].sub(/\A\\x/, "")].pack("H*"),
      requested_at_utc: instant
    )
    Workflows::Wf005::Handlers::CompleteCrawl.new.call(command:, request_context: executor_ctx(instant))
  end

  describe "the action that bounds every run (FU-22)" do
    it "PROOF 58 — the accepted start schedules the checkpoint at exactly `deadline_at`" do
      # Nothing created this action until S-07-009. A run whose frontier stopped advancing stayed
      # `running` for ever, because the chain only links forward FROM a pass.
      ctx = running_crawl
      crawl = crawl_row(ctx[:crawl_id])
      row = terminal_actions(ctx[:crawl_id]).sole

      expect(row).not_to be_nil
      expect(row["action_kind"]).to eq("crawl_terminal_deadline")
      expect(row["target_type"]).to eq("crawl")
      # :139's "exact 60-minute terminal checkpoint" — the run's OWN resolved deadline, not a second
      # derivation of sixty minutes.
      expect(Time.parse(row["due_at"]).getutc).to eq(Time.parse(crawl["deadline_at"]).getutc)
      expect(row["organization_id"]).to eq(ctx[:g][:organization_id])
    end

    it "PROOF 59 — it is registered, so the worker dispatches it instead of quarantining it" do
      entry = Platform::ScheduledActions::Registry.default.resolve(action_kind: "crawl_terminal_deadline",
                                                                   action_schema_version: "1.0")
      expect(entry).not_to be_nil
      expect(entry.operation).to eq("CompleteCrawl")
      expect(entry.handler).to eq(Workflows::Wf005::Handlers::CompleteCrawl)
      expect(entry.command).to eq(Workflows::Wf005::Commands::CompleteCrawl)
    end
  end

  describe ":458's selection, derived from what the run recorded" do
    it "PROOF 60 — a run that fetched its root completes, FULL, and commits its reservation" do
      ctx = fetchable
      passes = drain(ctx, outbound_by_path("/" => page))
      expect(passes.last.payload[:pass_outcome]).to eq("fetched")
      expect(entries(ctx[:crawl_id]).map { |e| e["state"] }).to eq(["terminal"])
      # The drained pass scheduled its own checkpoint (ADR-101), so the run reaches its terminal
      # selection now rather than waiting out a deadline it has no work left to fill.
      expect(passes.last.payload[:frontier_drained]).to be(true)
      expect(passes.last.payload[:terminal_checkpoint_action_id]).not_to be_nil

      result = checkpoint(ctx)

      expect(result.success?).to be(true)
      crawl = crawl_row(ctx[:crawl_id])
      expect(crawl["state"]).to eq("completed")
      # :452 — no Source-root failure, no `content_fetch_failed`, no `sitemap_unavailable`, no limit.
      expect(crawl["completion_reason"]).to eq("completed")
      # :458 — "full ONLY WHEN every in-scope candidate ... reached a terminal covered outcome and no
      # Source or discovery path has an unresolved failure."
      expect(crawl["coverage_status"]).to eq("full")
      expect(crawl["terminal_at"]).not_to be_nil
      expect(result.payload[:documents]).to eq(1)
      expect(result.payload[:source_roots]).to eq(1)
      expect(result.payload[:source_roots_succeeded]).to eq(1)
      # MTX-030 — "commit or release its reservation EXACTLY ONCE at the listed Crawl durable point".
      expect(result.payload[:entitlement_outcome]).to eq("committed")
      expect(reservation(ctx[:crawl_id])["state"]).to eq("committed")
      expect(events(ctx[:crawl_id]).sole["event_type"]).to eq("CrawlCompleted")
    end

    it "PROOF 152 — a checkpoint whose wait outlasts the lease RELEASES instead of committing" do
      # :551 — "the durable commit point must have committed STRICTLY BEFORE" the effective deadline,
      # and expiry wins at equality. The commit point is THIS TRANSACTION'S terminal transition, not
      # the instant the delivery arrived, and `Entitlement::Service#commit` decides commit versus
      # release from the instant it is handed and nothing else.
      #
      # THE RUN IS THE COMMITTING ONE. PROOF 60 is this same fixture and it commits, so the only
      # difference here is that the checkpoint waited past the lease — which is the whole finding.
      ctx = fetchable
      drain(ctx, outbound_by_path("/" => page))
      action = drained_action(ctx[:crawl_id])
      at = Platform::PgInstant.utc(action["due_at"])
      set_lease_due(ctx[:crawl_id], at + 1)

      result = wait_out_frontier(ctx, 1.5) { checkpoint(ctx, action:, at:) }

      expect(result).to be_a(Platform::CommandResult), result.inspect
      expect(result.success?).to be(true)
      # The run still terminalizes and still completed: the entitlement outcome is the only thing the
      # lapsed lease changes, which is exactly what :551 says it changes.
      expect(result.payload[:state]).to eq("completed")
      expect(result.payload[:entitlement_outcome]).to eq("released")
      expect(reservation(ctx[:crawl_id])["state"]).to eq("released")
      # MTX-030's "exactly once" is not satisfied by a commit intent that should never have existed.
      expect(DbInspector.one(<<~SQL, [ctx[:crawl_id]])["n"].to_i).to eq(0)
        SELECT count(*) AS n FROM entitlement_commit_intents WHERE reservation_id IN
          (SELECT entitlement_reservation_id FROM crawls WHERE id = $1::uuid)
      SQL
    end

    it "PROOF 61 — zero valid Documents is FAILED, whatever the coverage looked like" do
      # :453 — "A run is failed when it yields zero valid Documents or every active Source root fails."
      # A 404 root is :452-COVERED (`content_absent`), so this run's every candidate reached a covered
      # outcome and it is STILL failed: the two questions are different, and reading coverage as the
      # answer to both is how a run that produced nothing would report itself complete.
      ctx = fetchable
      drain(ctx, outbound_by_path("/" => page(status: 404, body: "", type: "text/plain")))

      result = checkpoint(ctx)

      crawl = crawl_row(ctx[:crawl_id])
      expect(crawl["state"]).to eq("failed")
      expect(crawl["completion_reason"]).to eq("failed")
      # `crawls_terminal_shape` (ADR-097) requires a reason of every terminal state and coverage only
      # of `completed`; a failed run retrieved nothing there is coverage to report on.
      expect(crawl["coverage_status"]).to be_nil
      expect(result.payload[:documents]).to eq(0)
      # A run with no durable output RELEASES rather than commits, so the customer is not charged.
      expect(result.payload[:entitlement_outcome]).to eq("released")
      expect(reservation(ctx[:crawl_id])["state"]).to eq("released")
      expect(reservation(ctx[:crawl_id])["terminal_reason"]).to eq("crawl_terminal_without_durable_output")
      expect(events(ctx[:crawl_id]).sole["event_type"]).to eq("CrawlFailed")
    end

    it "PROOF 62 — a fail-closed robots host makes its Source root fail and coverage partial" do
      # :452 — "`robots_unavailable_fail_closed` makes that Source root failed and coverage partial."
      # Two Sources: one healthy, one 403 on robots. The run completes because it produced a Document,
      # and it is `partial_source_failure` / `partial` because one root never became one.
      ctx = running_crawl(hosts: %w[shop.acme.example zeta.acme.example])
      ensure_gate(ctx)
      resolve_robots(ctx, outbound_returning(response(status: 200, body: ALLOW_ALL_ROBOTS)))
      resolve_sitemaps(ctx, outbound_returning(response(status: 404, body: "")))
      clear_rate_window_for_crawl(ctx[:crawl_id])
      drain(ctx, outbound_by_path("/" => page, "/robots.txt" => page(status: 403, body: "no", type: "text/plain"),
                                  "/sitemap.xml" => page(status: 404, body: "", type: "text/plain")))

      result = checkpoint(ctx)

      crawl = crawl_row(ctx[:crawl_id])
      expect(crawl["state"]).to eq("completed")
      expect(crawl["completion_reason"]).to eq("partial_source_failure")
      expect(crawl["coverage_status"]).to eq("partial")
      expect(result.payload[:source_roots]).to eq(2)
      expect(result.payload[:source_roots_succeeded]).to eq(1)
      expect(result.payload[:unresolved_discovery]).to be >= 1
    end

    it "PROOF 63 — an unfetched candidate makes coverage partial even with a clean completion" do
      # :458 — "any in-scope candidate NOT EVALUATED because of depth, sitemap, queue, page, byte,
      # response, request, or wall-clock bound makes coverage PARTIAL". This run fetched its root and
      # then stopped with a depth-1 candidate still queued, which is the wall-clock bound reached: a
      # completion reason of `completed` and coverage of `partial` is the honest pair, and treating the
      # reason as the coverage answer is the mistake this pins.
      ctx = fetchable
      root = nil
      drain(ctx, outbound_by_path("/" => page)) # retires the root
      root = entries(ctx[:crawl_id]).first
      in_frontier(ctx) do |store|
        Workflows::Wf005::Frontier.new(store, ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
          .offer(organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
                 crawl_id: ctx[:crawl_id], source_id: root["source_id"],
                 canonical_url: "https://#{ctx[:host]}/deeper", origin: "sitemap", depth: 1, now: start_now,
                 discovering_document_url: "", link_position: 0, parent_entry_id: root["id"],
                 scope_policy_id: root["scope_policy_id"], scope_policy_version: root["scope_policy_version"])
      end

      result = checkpoint(ctx)

      crawl = crawl_row(ctx[:crawl_id])
      expect(crawl["state"]).to eq("completed")
      expect(crawl["completion_reason"]).to eq("completed")
      expect(crawl["coverage_status"]).to eq("partial")
      expect(result.payload[:unevaluated_candidates]).to eq(1)
    end
  end

  # THE COUNTED FACTS THAT DECIDE THE COVERAGE NUMBER (B9).
  #
  # `TerminalSelection` is proved exhaustively as a pure function, with the facts handed in by hand. The
  # SQL that SUPPLIES those facts had no behavioural anchor at all: zeroing `uncovered`, `fetch_failures`
  # or the terminal-limit count in `count_facts` left 218 examples green. `uncovered` is :458's coverage denominator,
  # so zeroing it turns `partial` into `full` — the one error direction `CoverageClassification`'s own
  # header says it exists to prevent — and no example noticed. These three make each fact decide.
  describe "each counted fact decides something a run can be wrong about (B9)" do
    def decisions(cid)
      DbInspector.all("SELECT * FROM crawl_limit_decisions WHERE crawl_id = $1::uuid", [cid])
    end

    # TWO SOURCES, because :452 makes a Source root succeed ONLY when its own depth-zero URL creates a
    # Document — so a run whose single root failed is `failed` by :453's second limb whatever else it
    # fetched, and the fact under test would never reach the coverage question. One root succeeds, the
    # other carries the defect.
    ROBOTS_OK = { body: "User-agent: *\nAllow: /\n", type: "text/plain" }.freeze
    SITEMAP_ABSENT = { status: 404, body: "", type: "text/plain" }.freeze

    def decisions(cid)
      DbInspector.all("SELECT * FROM crawl_limit_decisions WHERE crawl_id = $1::uuid", [cid])
    end

    def two_source_run(failing_root)
      ctx = running_crawl(hosts: %w[shop.acme.example zeta.acme.example])
      ensure_gate(ctx)
      resolve_robots(ctx, outbound_returning(response(status: 200, body: ALLOW_ALL_ROBOTS)))
      resolve_sitemaps(ctx, outbound_returning(response(status: 404, body: "")))
      clear_rate_window_for_crawl(ctx[:crawl_id])
      drain(ctx, outbound_by_host_path(
        "shop.acme.example/" => failing_root,
        "zeta.acme.example/" => [{}],
        "zeta.acme.example/robots.txt" => [ROBOTS_OK],
        "zeta.acme.example/sitemap.xml" => [SITEMAP_ABSENT]
      ), limit: 14)
      ctx
    end

    it "PROOF 98 — a `content_fetch_failed` outcome is the DECIDING fact: partial, and not covered" do
      # :452 — "Exhausted timeout/408/429/5xx … is `content_fetch_failed`, REMAINS IN THE DENOMINATOR,
      # and makes coverage partial." Three 5xx responses exhaust :444's bound, and a 5xx trips no
      # per-fetch hard limit (only a timeout, an over-limit body or redirect exhaustion do), so
      # `limit_reached` cannot mask the fact under test. The other root produces a Document, so the run
      # completes and `uncovered`/`fetch_failures` are the only things between it and `full`.
      ctx = two_source_run([{ status: 500, body: "server error", type: "text/plain" }])

      outcomes = DbInspector.all(<<~SQL, [ctx[:crawl_id]]).map { |r| r["outcome"] }
        SELECT outcome FROM crawl_terminal_outcomes WHERE crawl_id = $1::uuid ORDER BY commit_order
      SQL
      expect(outcomes).to include("content_fetch_failed", "document_created")

      result = checkpoint(ctx)

      expect(result.payload[:content_fetch_failures]).to eq(1)
      expect(result.payload[:uncovered_candidates]).to eq(1)
      expect(result.payload[:hard_limit_decisions]).to eq(0)
      crawl = crawl_row(ctx[:crawl_id])
      expect(crawl["state"]).to eq("completed")
      expect(crawl["completion_reason"]).to eq("partial_source_failure")
      expect(crawl["coverage_status"]).to eq("partial")
    end

    it "PROOF 114 — a PARTIALLY covered run that left nothing unevaluated records no wall-clock crossing" do
      # The distinction FU-35 turns on, stated from the partial side so it cannot be read as "drained
      # runs are exempt". This run IS partial — one root exhausted :444 into `content_fetch_failed`,
      # which :452 keeps in the denominator — and it is terminalized AFTER its deadline. Every
      # candidate was nonetheless EVALUATED before the deadline, so :458's "any in-scope candidate NOT
      # EVALUATED because of … wall-clock bound" has no subject and the clock bounded nothing.
      ctx = two_source_run([{ status: 500, body: "server error", type: "text/plain" }])
      at = age_run_to(ctx, Time.parse(crawl_row(ctx[:crawl_id])["deadline_at"]).getutc + 60)

      result = checkpoint(ctx, action: deadline_action(ctx[:crawl_id]), at:)

      crawl = crawl_row(ctx[:crawl_id])
      # :452's reason for a completed run with no limit hit — NOT `limit_reached`, which outranks it.
      expect(crawl["completion_reason"]).to eq("partial_source_failure")
      expect(crawl["coverage_status"]).to eq("partial")
      expect(result.payload[:hard_limit_decisions]).to eq(0)
      expect(decisions(ctx[:crawl_id])).to be_empty
      events = DbInspector.all(<<~SQL, [ctx[:crawl_id]])
        SELECT event_type FROM event_registry WHERE aggregate_id = $1::uuid
          AND event_type IN ('CrawlLimitReached','CrawlSoftLimitApproaching')
      SQL
      expect(events).to be_empty
    end

    it "PROOF 99 — a local hard decision remains local at the terminal checkpoint" do
      # A hard decision and a terminal reason are separate facts. The per-URL body limit below is a
      # real hard decision, but its disposition is the affected URL only. It therefore contributes
      # partial coverage and a source failure without promoting the whole run to `limit_reached`.
      #
      # The limit is REAL, recorded by the accepted per-fetch observation point — a body past the
      # per-URL maximum — not a row this example inserted.
      oversized = "x" * (Workflows::Wf005::ByteAccounting::PER_URL_CEILING + 64)
      ctx = two_source_run([{ body: oversized }])

      hard = DbInspector.all(<<~SQL, [ctx[:crawl_id]])
        SELECT * FROM crawl_limit_decisions WHERE crawl_id = $1::uuid AND threshold_kind = 'hard'
      SQL
      expect(hard.map { |r| r["limit_dimension"] }).to include("response_body_per_url")

      result = checkpoint(ctx)

      expect(result.payload[:hard_limit_decisions]).to be >= 1
      expect(result.payload[:terminal_forcing_limit_decisions]).to eq(0)
      expect(result.payload[:sitemap_terminal_limit_facts]).to eq(0)
      expect(result.payload[:documents]).to eq(1)
      crawl = crawl_row(ctx[:crawl_id])
      expect(crawl["state"]).to eq("completed")
      expect(crawl["completion_reason"]).to eq("partial_source_failure")
      expect(crawl["coverage_status"]).to eq("partial")
    end

    it "PROOF 144 — a persisted sitemap request-time limit selects `limit_reached`" do
      ctx = running_crawl
      ensure_gate(ctx)
      robots = <<~ROBOTS
        User-agent: *
        Allow: /
        Sitemap: https://shop.acme.example/a.xml
        Sitemap: https://shop.acme.example/z.xml
      ROBOTS
      resolve_robots(ctx, outbound_returning(response(status: 200, body: robots)))

      valid = %(<?xml version="1.0"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"/>)
      timeout_attempts = 0
      outbound = Object.new
      outbound.define_singleton_method(:fetch) do |url, **_kwargs|
        if url.end_with?("z.xml")
          timeout_attempts += 1
          next Platform::Outbound::Outcome.timeout(canonical_host: "shop.acme.example")
        end

        body = url.end_with?("a.xml") ? valid : ""
        Platform::Outbound::Outcome.response(
          status: url.end_with?("a.xml") ? 200 : 404,
          headers: { "content-type" => "application/xml" }, body:, byte_count: body.bytesize,
          truncated: false, canonical_host: "shop.acme.example", port: 443,
          pinned_address: "198.51.100.7", final_url: url, redirect_count: 0, latency_ms: 1
        )
      end
      sitemap = resolve_sitemaps(ctx, outbound)
      expect(sitemap.state).to eq("succeeded")
      expect(sitemap.limit_reasons)
        .to include(Workflows::Wf005::DiscoverSitemaps::REQUEST_TIME_LIMIT)
      expect(timeout_attempts).to eq(Workflows::Wf005::DiscoverSitemaps::MAX_ATTEMPTS)

      clear_rate_window_for_crawl(ctx[:crawl_id])
      drain(ctx, outbound_by_path("/" => page))
      result = checkpoint(ctx)

      expect(result.payload[:documents]).to eq(1)
      expect(result.payload[:hard_limit_decisions]).to eq(0)
      expect(result.payload[:terminal_forcing_limit_decisions]).to eq(0)
      expect(result.payload[:sitemap_terminal_limit_facts]).to eq(1)
      crawl = crawl_row(ctx[:crawl_id])
      expect(crawl["state"]).to eq("completed")
      expect(crawl["completion_reason"]).to eq("limit_reached")
      expect(crawl["coverage_status"]).to eq("partial")
    end
  end

  describe "the two instants the checkpoint has to be reachable at (ADR-101)" do
    it "PROOF 69 — a drained run schedules its own checkpoint, and the deadline one stays behind it" do
      ctx = fetchable
      passes = drain(ctx, outbound_by_path("/" => page))

      actions = terminal_actions(ctx[:crawl_id])
      expect(actions.size).to eq(2)
      expect(Time.parse(actions.first["due_at"]).getutc).to eq(start_now)
      expect(Time.parse(actions.last["due_at"]).getutc)
        .to eq(Time.parse(crawl_row(ctx[:crawl_id])["deadline_at"]).getutc)
      expect(actions.first["id"]).to eq(passes.last.payload[:terminal_checkpoint_action_id])
      # Two DISTINCT identities, so both exist; :458's "once" is enforced by the Crawl row lock and the
      # state machine, not by there being only one delivery.
      expect(actions.map { |a| a["identity_sha256"] }.uniq.size).to eq(2)
    end

    it "PROOF 70 — THE EVIDENCE THAT FORCED IT: at the deadline, the commit is a release" do
      # :551 — "It commits exactly once ONLY IF the durable commit point committed STRICTLY BEFORE" the
      # lease-expiry instant; "otherwise it releases exactly once." A run that drained at minute zero and
      # was only terminalized at minute sixty has a lease that expired at minute fifteen, so
      # `Entitlement::Service#commit` takes its release limb — faithfully, and with the consequence that
      # `crawl.start` is never committed against the customer's entitlement. That is what the
      # drained-run checkpoint above exists to avoid, and it is asserted rather than argued.
      ctx = fetchable
      drain(ctx, outbound_by_path("/" => page))

      result = checkpoint(ctx, action: deadline_action(ctx[:crawl_id]))

      expect(crawl_row(ctx[:crawl_id])["state"]).to eq("completed")
      expect(result.payload[:entitlement_outcome]).to eq("released")
      expect(reservation(ctx[:crawl_id])["terminal_reason"]).to eq("lease_expired_at_commit")
    end
  end

  describe ":442's wall clock, recorded where it actually ends the run (B2)" do
    def decisions(cid)
      DbInspector.all(<<~SQL, [cid])
        SELECT * FROM crawl_limit_decisions WHERE crawl_id = $1::uuid
        ORDER BY limit_dimension, threshold_kind
      SQL
    end

    def limit_events(cid)
      DbInspector.all(<<~SQL, [cid])
        SELECT * FROM event_registry WHERE aggregate_id = $1::uuid
          AND event_type IN ('CrawlLimitReached','CrawlSoftLimitApproaching') ORDER BY created_at
      SQL
    end

    it "PROOF 95 — a run ended BY its own deadline records the wall-clock crossing and `limit_reached`" do
      # `Admission` records this when a PASS arrives past the deadline. The case the deadline action
      # EXISTS for is the one where no pass ever does — FU-22's pinned run, and any run whose chain
      # stopped — so the run ended by its own sixty minutes recorded nothing about them, and :458's
      # "records its exact limit reason" had no reason to record.
      ctx = fetchable
      drain(ctx, outbound_by_path("/" => page))
      root = entries(ctx[:crawl_id]).first
      in_frontier(ctx) do |store|
        Workflows::Wf005::Frontier.new(store, ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
          .offer(organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
                 crawl_id: ctx[:crawl_id], source_id: root["source_id"],
                 canonical_url: "https://#{ctx[:host]}/deeper", origin: "sitemap", depth: 1, now: start_now,
                 discovering_document_url: "", link_position: 0, parent_entry_id: root["id"],
                 scope_policy_id: root["scope_policy_id"], scope_policy_version: root["scope_policy_version"])
      end
      expect(decisions(ctx[:crawl_id])).to be_empty

      result = checkpoint(ctx, action: deadline_action(ctx[:crawl_id]))

      crawl = crawl_row(ctx[:crawl_id])
      # :442 — "set `coverage_status=partial` and `completion_reason=limit_reached`". :458 puts
      # `limit_reached` ABOVE `partial_source_failure`, which is what this run would otherwise have read.
      expect(crawl["completion_reason"]).to eq("limit_reached")
      expect(crawl["coverage_status"]).to eq("partial")
      expect(result.payload[:hard_limit_decisions]).to eq(1)

      hard = decisions(ctx[:crawl_id]).find { |r| r["threshold_kind"] == "hard" }
      expect(hard).not_to be_nil
      expect(hard["limit_dimension"]).to eq("wall_clock_run_duration")
      expect(hard["configured_value"].to_i).to eq(60)
      expect(hard["observed_value"].to_i).to eq(60)
      # ":442 — record … AFFECTED SOURCE AND URL COUNTS." The clock abandoned the depth-1 candidate, and
      # the counts are read from the frontier rather than assumed.
      expect(hard["affected_url_count"].to_i).to eq(1)
      expect(hard["affected_source_count"].to_i).to eq(1)
      # ":442 — emit `CrawlLimitReached` exactly once per dimension and run."
      expect(limit_events(ctx[:crawl_id]).count { |e| e["event_type"] == "CrawlLimitReached" }).to eq(1)
    end

    it "PROOF 112 — a FULLY COVERED, FULLY DRAINED run terminalized at its deadline is `completed` / `full`" do
      # THE REGRESSION THIS REMOVES (FU-35). The first version of `observe_wall_clock` compared only
      # `now` with `deadline_at` — the CHECKPOINT'S DELIVERY INSTANT — so this run, which fetched every
      # in-scope candidate and drained, was permanently recorded `limit_reached` / `partial` with a hard
      # decision affecting ZERO URLs and a real `CrawlLimitReached` for a dimension that bounded
      # nothing. `f1_crawls_guard` refuses every correction, so the wrong answer was the final one.
      ctx = fetchable
      drain(ctx, outbound_by_path("/" => page))
      expect(entries(ctx[:crawl_id]).map { |e| e["state"] }).to all(eq("terminal"))
      at = age_run_to(ctx, Time.parse(crawl_row(ctx[:crawl_id])["deadline_at"]).getutc)

      result = checkpoint(ctx, action: deadline_action(ctx[:crawl_id]), at:)

      crawl = crawl_row(ctx[:crawl_id])
      expect(crawl["completion_reason"]).to eq("completed")
      expect(crawl["coverage_status"]).to eq("full")
      expect(result.payload[:hard_limit_decisions]).to eq(0)
      # ":442 — emit `CrawlLimitReached` exactly once per dimension and run" is not a licence to emit
      # one for a dimension that bounded nothing.
      expect(decisions(ctx[:crawl_id])).to be_empty
      expect(limit_events(ctx[:crawl_id])).to be_empty
    end

    # R3-1. FU-35's repair removed DELIVERY LATENCY as a determinant and stopped there. The affected
    # population still admitted `state = 'discarded' AND reason IS NOT NULL` — every candidate a
    # DIFFERENT bound affirmatively disposed of — on the stated ground that this measure must describe
    # the same set as `terminal_facts`'s `unevaluated`. That ground was itself the defect: the two
    # answer different sentences. `terminal_facts` answers :458's coverage denominator, which is every
    # bound at once; this answers :442's "AFFECTED source and URL counts" for the WALL CLOCK ALONE.
    #
    # The eviction here is REAL, produced by :454's own retention rule at a stubbed bound, exactly as
    # `wf005_crawl_frontier_spec` produces it. Nothing is written by hand into `crawl_frontier_entries`.
    it "PROOF 123 — a candidate the QUEUE bound evicted is not a candidate the wall clock affected" do
      ctx = fetchable
      org = ctx[:g][:organization_id]
      root = entries(ctx[:crawl_id]).first

      # Two links offered at a bound of one: the lower-sorting one is retained, the other is evicted
      # as `queue_limit_discarded` — by the frontier, for the QUEUE dimension, at minute zero.
      stub_const("Workflows::Wf005::Frontier::DISCOVERED_QUEUE_HARD", 1)
      in_frontier(ctx) do |store|
        frontier = Workflows::Wf005::Frontier.new(store, ids: Platform::Ids.system,
                                                         correlation_id: SecureRandom.uuid_v7)
        %w[a z].each do |slug|
          frontier.offer(organization_id: org, project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id],
                         source_id: root["source_id"], canonical_url: "https://shop.acme.example/#{slug}",
                         origin: "link", depth: 1, now: start_now,
                         discovering_document_url: "https://shop.acme.example/", link_position: 1,
                         parent_entry_id: root["id"], scope_policy_id: root["scope_policy_id"],
                         scope_policy_version: root["scope_policy_version"])
        end
      end
      evicted = entries(ctx[:crawl_id]).select { |e| e["state"] == "discarded" }
      expect(evicted).not_to be_empty, "the queue bound evicted nothing, so this proves nothing"
      expect(evicted.map { |e| e["reason"] }).to all(eq("queue_limit_discarded"))

      # Everything the run could still evaluate, it evaluates. What is left unevaluated is exactly the
      # one candidate the QUEUE bound removed.
      drain(ctx, outbound_by_path("/" => page, "/a" => page))
      remaining = entries(ctx[:crawl_id]).reject { |e| e["state"] == "discarded" }
      expect(remaining.map { |e| e["state"] }).to all(eq("terminal"))

      at = age_run_to(ctx, Time.parse(crawl_row(ctx[:crawl_id])["deadline_at"]).getutc)

      # The predicate, read from the store the handler reads it from. The queue-evicted candidate is
      # not the wall clock's, so the clock abandoned nothing and there is no crossing to record.
      reach = Platform::UnitOfWork.run do |conn|
        store = IdentityAccess::Infrastructure::CrawlStartStore.new(conn.raw_connection)
        store.enter_org_context(org:, correlation_id: SecureRandom.uuid_v7)
        store.unevaluated_reach(org, ctx[:crawl_id], Workflows::Wf005::FetchContent::REASONS[:wall_clock])
      end
      expect(reach["urls"].to_i).to eq(0)

      result = checkpoint(ctx, action: deadline_action(ctx[:crawl_id]), at:)

      # No hard wall-clock decision, and the once-per-run CrawlLimitReached is NOT spent on a
      # dimension that bounded nothing. Both records are immutable, so getting this wrong is permanent.
      expect(result.payload[:hard_limit_decisions]).to eq(0)
      expect(decisions(ctx[:crawl_id]).select { |r| r["limit_dimension"] == "wall_clock_run_duration" })
        .to be_empty
      expect(limit_events(ctx[:crawl_id]).count { |e| e["event_type"] == "CrawlLimitReached" }).to eq(0)

      # And the QUEUE bound's own disposals are still visible in the coverage measure, which is the
      # sentence `terminal_facts` answers. Excluding them from the wall clock did not erase them —
      # which is the half of this repair that could have gone wrong in the other direction.
      expect(result.payload[:unevaluated_candidates]).to eq(evicted.size)
      expect(evicted.size).to be >= 1
    end

    # R4-3. :452's "robots-disallowed URLs, duplicate occurrences, unsupported media types, and redirect
    # targets rejected by current scope are recorded as `policy_excluded` and are OUTSIDE the
    # denominator" was asserted by NOTHING that could fail. Its only claimed proof, PROOF 78, evaluated
    # `derive(uncovered: 0)` against a fixture that already sets `uncovered: 0` — byte-identical to the
    # assertion PROOF 76 makes one screen above.
    #
    # THE RULE CANNOT BE PROVED WHERE PROOF 78 SAT. `TerminalSelection::Facts` has no field for excluded
    # candidates; the exclusion lives entirely in one SQL predicate, `AND o.coverage_effect =
    # 'not_covered'` in `CrawlStartStore#terminal_facts`. So the proof has to run the store.
    #
    # Round 4 measured the cost: inverting that predicate to `<> 'covered'` — which counts excluded rows
    # in the denominator, exactly what :452 forbids — left THE WHOLE SUITE GREEN at 2085/0.
    it "PROOF 127 — an EXCLUDED candidate leaves the denominator, so a run that covered the rest is `full`" do
      ctx = fetchable
      org = ctx[:g][:organization_id]
      root = entries(ctx[:crawl_id]).first

      # A depth-1 candidate admitted through :454's own path, exactly as PROOF 123 admits one. This
      # tranche has no HTML link extraction — candidates reach the frontier through `Frontier#offer` —
      # so offering one is the real admission, not a substitute for it.
      in_frontier(ctx) do |store|
        Workflows::Wf005::Frontier.new(store, ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
                                  .offer(organization_id: org, project_id: ctx[:g][:project_id],
                                         crawl_id: ctx[:crawl_id], source_id: root["source_id"],
                                         canonical_url: "https://shop.acme.example/brochure.pdf",
                                         origin: "link", depth: 1, now: start_now,
                                         discovering_document_url: "https://shop.acme.example/",
                                         link_position: 1, parent_entry_id: root["id"],
                                         scope_policy_id: root["scope_policy_id"],
                                         scope_policy_version: root["scope_policy_version"])
      end

      # The root creates a Document; the brochure is refused for its media type, which :452 puts
      # OUTSIDE the denominator rather than merely uncovered.
      drain(ctx, outbound_by_path("/" => page,
                                  "/brochure.pdf" => page(type: "application/pdf", body: "%PDF-1.4 binary",
                                                          path: "/brochure.pdf")))

      # THE PRECONDITION, ASSERTED SO THE EXAMPLE CANNOT PASS VACUOUSLY. A run that never produced an
      # excluded outcome would satisfy every assertion below for the wrong reason.
      by_outcome = DbInspector.all(
        "SELECT * FROM crawl_terminal_outcomes WHERE crawl_id = $1::uuid", [ctx[:crawl_id]]
      ).to_h { |o| [o["outcome"], o] }
      expect(by_outcome.keys).to include("document_created", "policy_excluded")
      expect(by_outcome["policy_excluded"]["reason"]).to eq("unsupported_media_type")
      expect(by_outcome["policy_excluded"]["coverage_effect"]).to eq("excluded")
      expect(by_outcome["document_created"]["coverage_effect"]).to eq("covered")

      at = age_run_to(ctx, Time.parse(crawl_row(ctx[:crawl_id])["deadline_at"]).getutc)
      result = checkpoint(ctx, action: deadline_action(ctx[:crawl_id]), at:)

      # THE ASSERTION THE RULE TURNS ON. The excluded candidate is outside the denominator, so the run
      # covered everything that counts and coverage is `full`. Counting it would read `partial`, and
      # `f1_crawls_guard` refuses every correction of a terminal row — so the customer would be told
      # permanently that their crawl was incomplete because it declined to parse a PDF.
      expect(result.payload[:uncovered_candidates]).to eq(0)
      crawl = crawl_row(ctx[:crawl_id])
      expect(crawl["coverage_status"]).to eq("full")
      expect(crawl["completion_reason"]).to eq("completed")
    end

    # R4-6. R3-1 removed the `discarded` leg and PROOF 123 pins it. The leg it LEFT is the one that
    # bites harder: a run a DIFFERENT hard bound halted leaves its remaining candidates `queued`, and
    # `unevaluated_reach` counted every one of them as wall-clock-affected.
    #
    # Here the run hits its per-URL byte ceiling — a real LOCAL hard decision from the accepted
    # observation point — while a second candidate is still queued. At minute sixty the clock owns
    # that unrelated queued candidate; the per-URL decision did not stop the run's frontier.
    it "PROOF 131 — a local hard decision does not steal the wall clock's causal population" do
      ctx = fetchable
      org = ctx[:g][:organization_id]
      root = entries(ctx[:crawl_id]).first

      in_frontier(ctx) do |store|
        Workflows::Wf005::Frontier.new(store, ids: Platform::Ids.system, correlation_id: SecureRandom.uuid_v7)
                                  .offer(organization_id: org, project_id: ctx[:g][:project_id],
                                         crawl_id: ctx[:crawl_id], source_id: root["source_id"],
                                         canonical_url: "https://shop.acme.example/second",
                                         origin: "link", depth: 1, now: start_now,
                                         discovering_document_url: "https://shop.acme.example/",
                                         link_position: 1, parent_entry_id: root["id"],
                                         scope_policy_id: root["scope_policy_id"],
                                         scope_policy_version: root["scope_policy_version"])
      end

      # One pass only: the root exceeds the per-URL ceiling and records a HARD byte decision.
      oversized = "x" * (Workflows::Wf005::ByteAccounting::PER_URL_CEILING + 64)
      execute_fetch(ctx, link_first(ctx), outbound_by_path("/" => page(body: oversized)))

      hard = decisions(ctx[:crawl_id]).select { |r| r["threshold_kind"] == "hard" }
      expect(hard.map { |r| r["limit_dimension"] }).to include("response_body_per_url"),
                                                       "no other hard bound fired, so this proves nothing"
      still_queued = entries(ctx[:crawl_id]).count { |e| e["state"] == "queued" }
      expect(still_queued).to be >= 1, "nothing was left queued, so this proves nothing"

      at = age_run_to(ctx, Time.parse(crawl_row(ctx[:crawl_id])["deadline_at"]).getutc)
      result = checkpoint(ctx, action: deadline_action(ctx[:crawl_id]), at:)

      # THE ASSERTION THE REPAIR TURNS ON. The wall decision exists and owns exactly the queued
      # population the clock prevented from being evaluated. Both per-dimension records are immutable.
      wall = decisions(ctx[:crawl_id]).select do |row|
        row["limit_dimension"] == "wall_clock_run_duration" && row["threshold_kind"] == "hard"
      end
      expect(wall.size).to eq(1)
      expect(wall.first["affected_url_count"].to_i).to eq(still_queued)
      expect(limit_events(ctx[:crawl_id]).count { |e| e["event_type"] == "CrawlLimitReached" }).to eq(2)
      expect(result.payload[:hard_limit_decisions]).to eq(2)
      expect(result.payload[:terminal_forcing_limit_decisions]).to eq(1)

      # Failure still outranks the terminal wall limit because the oversized root produced no Document.
      expect(crawl_row(ctx[:crawl_id])["completion_reason"]).to eq("failed")
      expect(hard).not_to be_empty
    end

    it "PROOF 113 — TRANSPORT LATENCY ALONE cannot change the verdict, and the predicate is the count" do
      # The same run reached through the DRAINED checkpoint (ADR-101's own instant) delivered a minute
      # late. Nothing about the run differs; only when the message arrived. A verdict that moved would
      # be a verdict set by the message queue.
      ctx = fetchable
      drain(ctx, outbound_by_path("/" => page))
      at = age_run_to(ctx, Time.parse(crawl_row(ctx[:crawl_id])["deadline_at"]).getutc + 60)

      # The predicate itself, read from the store the handler reads it from: zero candidates were
      # prevented from being evaluated, which is why there is no crossing to record.
      reach = Platform::UnitOfWork.run do |conn|
        store = IdentityAccess::Infrastructure::CrawlStartStore.new(conn.raw_connection)
        store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
        store.unevaluated_reach(ctx[:g][:organization_id], ctx[:crawl_id],
                                Workflows::Wf005::FetchContent::REASONS[:wall_clock])
      end
      expect(reach["urls"].to_i).to eq(0)
      expect(reach["sources"].to_i).to eq(0)

      checkpoint(ctx, action: drained_action(ctx[:crawl_id]), at:)

      crawl = crawl_row(ctx[:crawl_id])
      expect([crawl["completion_reason"], crawl["coverage_status"]]).to eq(%w[completed full])
      expect(decisions(ctx[:crawl_id])).to be_empty
    end

    it "PROOF 115 — a candidate whose REQUEST the clock cancelled IS an affected candidate" do
      # WHERE THE TWO REPAIRS MEET (ADR-113 + ADR-114). :442's cancellation retires the candidate as
      # `limit_discarded`, so it leaves the `unevaluated` population entirely — and if the affected
      # measure counted only that population, the cancellation would silently suppress the very record
      # :458 requires for it. The clearest case of a candidate the deadline prevented from being
      # evaluated must not be the one case that goes unrecorded.
      ctx = fetchable
      action = link_first(ctx)
      at = age_run_to(ctx, Time.parse(crawl_row(ctx[:crawl_id])["deadline_at"]).getutc - 5)
      clear_rate_window_for_crawl(ctx[:crawl_id])
      execute_fetch(ctx, action, outbound_by_path("/" => timeout_outcome), at:)

      outcome = DbInspector.one("SELECT * FROM crawl_terminal_outcomes WHERE crawl_id=$1::uuid", [ctx[:crawl_id]])
      expect(outcome["outcome"]).to eq("limit_discarded")
      expect(outcome["reason"]).to eq(Workflows::Wf005::Admission::WALL_CLOCK)
      expect(outcome["coverage_effect"]).to eq("not_covered")

      # NOT a second `age_run_to`: it replays the heartbeat schedule from `start_now`, and the lease
      # this run already holds runs fifteen minutes past the last one, so the checkpoint's own instant
      # needs no further renewal.
      terminal_at = Time.parse(crawl_row(ctx[:crawl_id])["deadline_at"]).getutc
      checkpoint(ctx, action: deadline_action(ctx[:crawl_id]), at: terminal_at)

      hard = decisions(ctx[:crawl_id]).find { |r| r["threshold_kind"] == "hard" }
      expect(hard).not_to be_nil, "the cancelled candidate was not counted as affected"
      expect(hard["limit_dimension"]).to eq("wall_clock_run_duration")
      expect(hard["affected_url_count"].to_i).to eq(1)
      expect(hard["affected_source_count"].to_i).to eq(1)
    end

    it "PROOF 96 — a checkpoint INSIDE the deadline records no wall-clock crossing at all" do
      # The other side of the comparison. Without it the limb could become "every checkpoint records a
      # hard limit", which would make every drained run read `limit_reached`.
      ctx = fetchable
      drain(ctx, outbound_by_path("/" => page))

      result = checkpoint(ctx)

      expect(crawl_row(ctx[:crawl_id])["completion_reason"]).to eq("completed")
      expect(result.payload[:hard_limit_decisions]).to eq(0)
      expect(decisions(ctx[:crawl_id])).to be_empty
      expect(limit_events(ctx[:crawl_id])).to be_empty
    end

    it "PROOF 145 — the checkpoint preserves the deadline's exact microsecond" do
      # THE MARGIN IS 400ms, NOT ONE MICROSECOND, AND THE FRACTION IS .987654 (round 6, R6-1/R6-6).
      # The checkpoint no longer decides on the instant it was DELIVERED at: it takes both its locks
      # and then reads its decision instant from the database, so the transaction's own elapsed time
      # is part of the answer. A one-microsecond margin was smaller than that elapsed time, which made
      # this example measure scheduling noise rather than the decode it exists for.
      #
      # THE TWO BOUNDS THE MARGIN SITS BETWEEN, both real. It must exceed the handler's own transaction
      # time (milliseconds) or the example fails without any defect; it must stay under the truncation
      # error the mutation introduces (987,654µs) or the example passes WITH one. 400ms is two orders
      # of magnitude clear of the first and less than half the second, so `Time.parse(typed.to_s)`
      # still moves the boundary from `.987654` back to `.000000`, still puts this delivery AFTER it,
      # and still makes the immutable wall-clock crossing fire falsely.
      began = start_now + Rational(987_654, 1_000_000)
      ctx = running_crawl(at: began)
      ensure_gate(ctx)
      resolve_robots(ctx, outbound_returning(response(status: 200, body: ALLOW_ALL_ROBOTS)))
      resolve_sitemaps(ctx, outbound_returning(response(status: 404, body: "")))
      clear_rate_window_for_crawl(ctx[:crawl_id])
      drain(ctx, outbound_by_path("/" => page), at: began)

      # The drained pass made a due-now checkpoint. Reintroduce one legitimate frontier candidate so
      # the wall-clock predicate has a causal population to misattribute if the typed PostgreSQL Time
      # is stringified and truncated. This is a reachable post-pass offer through the real frontier.
      root = entries(ctx[:crawl_id]).first
      in_frontier(ctx) do |store|
        Workflows::Wf005::Frontier.new(store, ids: Platform::Ids.system,
                                              correlation_id: SecureRandom.uuid_v7)
                                  .offer(organization_id: ctx[:g][:organization_id],
                                         project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id],
                                         source_id: root["source_id"],
                                         canonical_url: "https://shop.acme.example/late-candidate",
                                         origin: "link", depth: 1, now: began,
                                         discovering_document_url: "https://shop.acme.example/",
                                         link_position: 1, parent_entry_id: root["id"],
                                         scope_policy_id: root["scope_policy_id"],
                                         scope_policy_version: root["scope_policy_version"])
      end

      exact = Time.parse(crawl_row(ctx[:crawl_id])["deadline_at"]).getutc
      expect(exact.usec).to eq(987_654), "the fixture did not produce a sub-second deadline"
      just_before = age_run_to(ctx, exact - Rational(400, 1_000))
      result = checkpoint(ctx, action: drained_action(ctx[:crawl_id]), at: just_before)

      # `Time.parse(typed_time.to_s)` moves the boundary back to `.000000` and makes this one-
      # microsecond-before delivery falsely record the immutable wall-clock crossing.
      expect(result.payload[:hard_limit_decisions]).to eq(0)
      expect(decisions(ctx[:crawl_id])).to be_empty
      expect(crawl_row(ctx[:crawl_id])["completion_reason"]).to eq("completed")
    end

    it "PROOF 97 — a pass that already recorded the crossing is not double-counted" do
      # `crawl_limit_decisions` is unique on `(crawl_id, limit_dimension, threshold_kind)`, so the
      # checkpoint's observation is idempotent against a pass that already made it — which is what keeps
      # :442's "exactly once per dimension and run" true with two observation points.
      ctx = fetchable
      action = link_first(ctx)
      expired = age_run_to(ctx, Time.parse(crawl_row(ctx[:crawl_id])["deadline_at"]).getutc + 60)
      execute_fetch(ctx, action, outbound_by_path({}), at: expired)
      expect(decisions(ctx[:crawl_id]).count { |r| r["threshold_kind"] == "hard" }).to eq(1)

      checkpoint(ctx, action: deadline_action(ctx[:crawl_id]), at: expired)

      expect(decisions(ctx[:crawl_id]).count { |r| r["threshold_kind"] == "hard" }).to eq(1)
      expect(limit_events(ctx[:crawl_id]).count { |e| e["event_type"] == "CrawlLimitReached" }).to eq(1)
      # `failed`, not `limit_reached`, and that is :458's precedence rather than a defect: this run
      # halted on the wall clock before fetching anything, so it yielded zero valid Documents, and
      # `failed` outranks `limit_reached`. The decision row is still written and still counted once —
      # which is the property this example is about.
      expect(crawl_row(ctx[:crawl_id])["completion_reason"]).to eq("failed")
    end
  end

  # THE ENVELOPE THE CATALOGUE DEFINES (B3, B4).
  describe "the terminal event carries what API_CONTRACTS defines (B3, B4)" do
    def envelope(event) = JSON.parse([event["event_bytes"].sub(/\A\\x/, "")].pack("H*"))

    it "PROOF 102 — `CrawlCompleted` carries `accepted_document_count`, and a null reason" do
      # :956 — the `crawl_terminal` extra schema is `coverage_status`, `completion_reason` AND
      # `accepted_document_count: uint53`. The third member was absent everywhere in the repository
      # while the value sat one line away in the counted facts. :807 gives `CrawlCompleted` the reason
      # source `none`, and :938 says a `none` source requires null — so this one keeps it null.
      ctx = fetchable
      drain(ctx, outbound_by_path("/" => page))

      checkpoint(ctx)

      body = envelope(events(ctx[:crawl_id]).sole)
      expect(body["event_type"]).to eq("CrawlCompleted")
      expect(body["accepted_document_count"]).to eq(1)
      expect(body["coverage_status"]).to eq("full")
      expect(body["completion_reason"]).to eq("completed")
      expect(body["reason_code"]).to be_nil

      # R4-7. This asserted `not_to have_key("transition_reason_code")`, which encoded the defect as the
      # rule. :938 lists `transition_reason_code` among the BASE members of every `state_transition` and
      # says "it is NULL where the catalogue source is `none`" — null is a VALUE, and :807 gives
      # `CrawlCompleted` the source `none`. So the member is PRESENT AND NULL, and its two siblings
      # already carried it: `CrawlCompleted` alone shipped an envelope missing a required base member.
      #
      # Present and null asserted as two facts, because :938's consumer rule rejects a missing required
      # member and defines a null one — the same distinction R3-3 turned on for `coverage_status`.
      expect(body).to have_key("transition_reason_code")
      expect(body["transition_reason_code"]).to be_nil
    end

    it "PROOF 103 — `CrawlFailed` carries the reason the catalogue's `transition` source requires" do
      # :808 gives `CrawlFailed` the reason source `transition`; :938 requires the `state_transition`
      # base member `transition_reason_code` and root `reason_code` "equals it exactly when the
      # catalogue source is `transition`". Both were absent, while WF-005's OWN pre-execution
      # `CrawlFailed` set the root reason — two producers of one event type disagreeing.
      ctx = fetchable
      drain(ctx, outbound_by_path("/" => page(status: 404, body: "", type: "text/plain")))

      checkpoint(ctx)

      body = envelope(events(ctx[:crawl_id]).sole)
      expect(body["event_type"]).to eq("CrawlFailed")
      expect(body["reason_code"]).to eq("failed")
      expect(body["transition_reason_code"]).to eq("failed")
      expect(body["accepted_document_count"]).to eq(0)
    end
  end

  describe ":458's \"once\", and the cancellation boundary it implies" do
    it "PROOF 64 — a second delivery replays the stored decision and writes no second one" do
      ctx = fetchable
      drain(ctx, outbound_by_path("/" => page))
      first = checkpoint(ctx)

      replay = checkpoint(ctx)

      expect(replay.replayed).to be(true)
      expect(replay.payload[:state]).to eq(first.payload[:state])
      expect(events(ctx[:crawl_id]).size).to eq(1)
      expect(crawl_row(ctx[:crawl_id])["state_version"].to_i)
        .to eq(DbInspector.one("SELECT state_version FROM crawls WHERE id=$1::uuid", [ctx[:crawl_id]])["state_version"].to_i)
    end

    it "PROOF 65 — a checkpoint arriving after a terminal Crawl decides nothing" do
      # :458 — a cancellation committed strictly BEFORE the checkpoint yields `Crawl.Canceled`. The
      # checkpoint that follows finds a terminal Crawl, and the guard refuses every edge out of it
      # anyway; the outcome is the canonical harmless terminal execution, audited and not raised.
      ctx = fetchable
      drain(ctx, outbound_by_path("/" => page))
      DbInspector.connection.exec_params(<<~SQL, [ctx[:crawl_id]])
        UPDATE crawls SET state='canceled', terminal_at=now(), completion_reason='canceled',
               state_version = state_version + 1 WHERE id = $1::uuid
      SQL

      result = checkpoint(ctx)

      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("crawl_already_terminal")
      expect(crawl_row(ctx[:crawl_id])["completion_reason"]).to eq("canceled")
      expect(events(ctx[:crawl_id])).to be_empty
    end

    it "PROOF 66 — it refuses to run before it is due" do
      ctx = fetchable
      result = checkpoint(ctx, at: start_now)

      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("scheduled_action_not_due")
      expect(crawl_row(ctx[:crawl_id])["state"]).to eq("running")
    end
  end

  # OWNER RULING 3: VOLUME I :450 GOVERNS, AND PENDING IS NOT AN OUTCOME (round-6 blocker R6-4).
  #
  # ":450 — If a DECLARED SITEMAP EXISTS, or the default returns a non-404/410 response, and no
  # sitemap candidate succeeds AFTER RETRIES/VALIDATION, record `sitemap_unavailable`." The sentence
  # has an antecedent. The checkpoint used to satisfy only its consequent — "at this instant no
  # candidate can ever be attempted" — and write the outcome anyway, and the proof that pinned it used
  # allow-all robots with NO declared sitemap and NO default fetch, so the expectation itself asserted
  # the invented observation.
  #
  # THESE THREE EXAMPLES ARE THE STATES THE OLD ONE COULD NOT TELL APART: never attempted, attempted
  # and genuinely unavailable, and terminalized by a sitemap-specific limit. Only the second and third
  # may produce a :450 outcome, and the first must produce none while still stopping the run being
  # `full`.
  describe ":450's antecedents, and the three states a gate can end in" do
    it "PROOF 67 — a PENDING, NEVER-ATTEMPTED gate gets no outcome, and still makes coverage partial" do
      # Allow-all robots, no declared sitemap, no default fetch: exactly the fixture the old PROOF 67
      # used, and on these facts :450 authorises NOTHING. `absent` needs the default to have answered
      # 404/410 and `unavailable` needs a declared sitemap or a non-404/410 default, and this run
      # observed neither because it never asked.
      ctx = running_crawl
      ensure_gate(ctx)
      resolve_robots(ctx, outbound_returning(response(status: 200, body: ALLOW_ALL_ROBOTS)))
      expect(gate_rows(ctx[:crawl_id]).sole["sitemap_state"]).to eq("pending")

      result = checkpoint(ctx)

      # THE GATE IS EXACTLY AS THE RUN LEFT IT. Nothing was claimed, nothing was terminalized, and the
      # customer's record carries no statement about a host nobody contacted.
      gate = gate_rows(ctx[:crawl_id]).sole
      expect(gate["sitemap_state"]).to eq("pending")
      expect(gate["sitemap_outcome_reason"]).to be_nil
      expect(gate["sitemap_terminal_at"]).to be_nil
      # :450's count stays zero, because :450 recorded nothing.
      expect(result.payload[:unresolved_discovery]).to eq(0)
      # :458's not-evaluated limb is what carries it instead: coverage partial, and the completion
      # reason is NOT `partial_source_failure`, because :452 lists three causes and this is none.
      expect(result.payload[:unattempted_discovery]).to eq(1)
      # This run fetched nothing, so :453 makes it `failed` and ADR-097 leaves coverage NULL. The
      # coverage claim is PROOF 162's, on a run that actually completes.
      expect(result.payload[:state]).to eq("failed")
      expect(result.payload[:completion_reason]).not_to eq("partial_source_failure")
    end

    it "PROOF 162 — a COMPLETED run with an unattempted host is `partial`, not `full`" do
      # THE ANSWER THE OLD ROUTE REACHED, KEPT. `resolve_pending_sitemaps` existed because an
      # unattempted host must stop a run being `full`, and it got there by writing an outcome :450 does
      # not authorise. The answer was right; only the route was invented. This proves the answer
      # survives the route's removal, on a run that genuinely completed with a valid Document.
      ctx = fetchable
      drain(ctx, outbound_by_path("/" => page))
      # A SECOND HOST THE RUN TOUCHED AND NEVER GOT TO. A gate is created the first time a pass reaches
      # a host, so a run that ran out of clock between creating the gate and resolving it leaves exactly
      # this row: no robots, no discovery, no outcome.
      in_gate(ctx[:g][:organization_id]) do |_s, gate|
        gate.ensure_gate(organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
                         crawl_id: ctx[:crawl_id], canonical_host: "www.acme.example", now: start_now)
      end
      second = gate_rows(ctx[:crawl_id]).find { |g| g["canonical_host"] == "www.acme.example" }
      expect(second["sitemap_state"]).to eq("pending")

      result = checkpoint(ctx, action: drained_action(ctx[:crawl_id]))

      expect(result.payload[:state]).to eq("completed")
      expect(result.payload[:unattempted_discovery]).to be >= 1
      expect(result.payload[:coverage_status]).to eq("partial")
      expect(crawl_row(ctx[:crawl_id])["coverage_status"]).to eq("partial")
    end

    it "PROOF 68 — an ATTEMPTED gate whose candidates all fail IS `sitemap_unavailable`" do
      # The antecedent satisfied: a DECLARED sitemap, fetched, failing after :450's retries. This is
      # the outcome the ruling preserves, and the one the old checkpoint made indistinguishable from
      # the case above by writing the same token for both.
      ctx = running_crawl
      ensure_gate(ctx)
      resolve_robots(ctx, outbound_returning(
        response(status: 200, body: "User-agent: *\nAllow: /\nSitemap: https://shop.acme.example/s.xml\n")
      ))
      resolve_sitemaps(ctx, outbound_returning(response(status: 503, body: "")))

      gate = gate_rows(ctx[:crawl_id]).sole
      expect(gate["sitemap_state"]).to eq("unavailable")
      expect(gate["sitemap_outcome_reason"]).to eq("sitemap_unavailable")

      result = checkpoint(ctx)

      # :450 — "link discovery may continue but COVERAGE IS PARTIAL", counted through `unresolved`,
      # and it is a Source failure, so :452's completion reason DOES fire here.
      # :450's count is the one that moves here, and the unattempted count stays at zero: this host WAS
      # attempted. That separation is the whole of the ruling — PROOF 67's gate and this one used to
      # produce the identical `sitemap_unavailable` row and were indistinguishable afterwards.
      expect(result.payload[:unresolved_discovery]).to be >= 1
      expect(result.payload[:unattempted_discovery]).to eq(0)
    end

    it "PROOF 69 — a fail-closed robots host is neither unavailable nor counted unattempted" do
      # :448 denies all content fetching for that host, so discovery correctly never ran and the gate
      # is legitimately `pending`. `unresolved` already counts it through `robots_state`, so counting
      # it again as unattempted would double-charge one host in the coverage measure.
      ctx = running_crawl
      ensure_gate(ctx)
      resolve_robots(ctx, outbound_returning(response(status: 403, body: "no")))
      expect(gate_rows(ctx[:crawl_id]).sole["robots_state"]).to eq("unavailable")

      result = checkpoint(ctx)

      gate = gate_rows(ctx[:crawl_id]).sole
      expect(gate["sitemap_state"]).to eq("pending")
      expect(gate["sitemap_outcome_reason"]).to be_nil
      expect(result.payload[:unresolved_discovery]).to eq(1)
      expect(result.payload[:unattempted_discovery]).to eq(0)
    end

    it "PROOF 161 — a sitemap-specific LIMIT still terminalizes the gate, which :450 does authorise" do
      # ":450 — any sitemap depth/count/body/time/XML limit still produces `limit_reached`." The ruling
      # withdraws the INVENTED outcome, not the recorded ones: a gate the run genuinely attempted and
      # bounded keeps its terminal state and its limit reason, and the checkpoint reads them.
      ctx = running_crawl
      ensure_gate(ctx)
      resolve_robots(ctx, outbound_returning(
        response(status: 200, body: "User-agent: *\nAllow: /\nSitemap: https://shop.acme.example/s.xml\n")
      ))
      oversized = "<?xml version=\"1.0\"?><urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">" \
                  "#{'<url><loc>https://shop.acme.example/x</loc></url>' * 3}</urlset>"
      resolve_sitemaps(ctx, outbound_returning(
        response(status: 200, body: oversized, truncated: true,
                 headers: { "content-type" => "application/xml" })
      ))

      gate = gate_rows(ctx[:crawl_id]).sole
      expect(gate["sitemap_state"]).not_to eq("pending")
      expect(gate["sitemap_terminal_at"]).not_to be_nil

      result = checkpoint(ctx)

      # Attempted, so it is not the unattempted count; terminal, so the checkpoint left it alone.
      expect(result.payload[:unattempted_discovery]).to eq(0)
      expect(gate_rows(ctx[:crawl_id]).sole["sitemap_state"]).to eq(gate["sitemap_state"])
    end
  end

  def in_frontier(ctx)
    Platform::UnitOfWork.run do |conn|
      store = IdentityAccess::Infrastructure::CrawlFrontierStore.new(conn.raw_connection)
      store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
      yield store
    end
  end
end
