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

  def gate_rows(cid)
    DbInspector.all("SELECT * FROM crawl_host_gates WHERE crawl_id=$1::uuid ORDER BY id", [cid])
  end

  # A run whose robots and sitemap records are terminal and whose rate window is clear.
  def fetchable(hosts: ["shop.acme.example"])
    ctx = running_crawl(hosts:)
    ensure_gate(ctx)
    resolve_robots(ctx, outbound_returning(response(status: 200, body: ALLOW_ALL_ROBOTS)))
    resolve_sitemaps(ctx, outbound_returning(response(status: 404, body: "")))
    clear_rate_window(gate_row(ctx[:crawl_id])["id"])
    ctx
  end

  # Drive the fetch chain to exhaustion, exactly as the transport does.
  def drain(ctx, outbound, limit: 8, at: start_now)
    action = link_first(ctx, at:)
    return [] if action.nil?

    [].tap do |results|
      limit.times do
        results << execute_fetch(ctx, action, outbound, at:)
        nxt = results.last.success? && results.last.payload[:next_action_id]
        break unless nxt

        clear_rate_window(gate_row(ctx[:crawl_id])["id"])
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
      clear_rate_window(gate_row(ctx[:crawl_id])["id"])
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

  describe "FU-9's transferred obligation: :450's unreachable outcome" do
    it "PROOF 67 — a gate left `pending` is terminalized `sitemap_unavailable` at the checkpoint" do
      # FU-9, transferred whole at S-07-012's acceptance (ADR-096). `DiscoverSitemaps` writes :450's
      # terminal outcome only once the run has EXPIRED, and `CrawlDriver#advance` halts on the same
      # wall clock BEFORE it calls discovery with the same `now` — so a gate under sustained contention
      # stayed `pending` for ever and :450's `sitemap_unavailable` was unreachable on every production
      # path. At the checkpoint no candidate can ever be attempted, which is exactly the "after
      # retries/validation" premise :450 conditions the outcome on.
      ctx = running_crawl
      ensure_gate(ctx)
      resolve_robots(ctx, outbound_returning(response(status: 200, body: ALLOW_ALL_ROBOTS)))
      expect(gate_rows(ctx[:crawl_id]).sole["sitemap_state"]).to eq("pending")

      result = checkpoint(ctx)

      gate = gate_rows(ctx[:crawl_id]).sole
      expect(gate["sitemap_state"]).to eq("unavailable")
      expect(gate["sitemap_outcome_reason"]).to eq("sitemap_unavailable")
      expect(gate["sitemap_terminal_at"]).not_to be_nil
      expect(result.payload[:sitemap_outcomes_derived]).to eq(1)
      # :450 — "link discovery may continue but COVERAGE IS PARTIAL", counted through `unresolved`.
      expect(result.payload[:unresolved_discovery]).to be >= 1
    end

    it "PROOF 68 — a fail-closed robots host is NOT also recorded sitemap-unavailable" do
      # :448 denies all content fetching for that host, so discovery never had a sitemap to fail at.
      # Recording `sitemap_unavailable` there would count one host's robots failure twice in the
      # coverage measure — and coverage that is wrong in that direction is the one that matters least,
      # but a count that double-charges a host is still a count nobody can reconcile.
      ctx = running_crawl
      ensure_gate(ctx)
      resolve_robots(ctx, outbound_returning(response(status: 403, body: "no")))
      expect(gate_rows(ctx[:crawl_id]).sole["robots_state"]).to eq("unavailable")

      result = checkpoint(ctx)

      gate = gate_rows(ctx[:crawl_id]).sole
      expect(gate["sitemap_state"]).to eq("pending")
      expect(result.payload[:sitemap_outcomes_derived]).to eq(0)
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
