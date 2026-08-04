# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# THE C-1 ANCHOR AT THE ONLY PRODUCTION CALL SITE THAT MOTIVATES IT (round 8, R8-1).
#
# ROUND 7 REPAIRED THE BEHAVIOUR AND ROUND 8 FOUND THE REPAIR UNDEFENDED. `Admission` measures its
# post-wait decision instant as an ADVANCE over the instant it is handed, and it must measure that
# advance from where the CALLER's instant was true — not from where its own transaction opened —
# because everything between those two points (the robots fetch, sitemap discovery, host pacing) is
# real elapsed time spent outside every transaction. `CrawlDriver#advance` captures that anchor and
# carries it down.
#
# PROOF 164 and 165 call `Admission#claim_next` DIRECTLY with an explicit anchor, so they prove the
# parameter works and say nothing about the propagation that IS the repair. Round 8 replaced
# `anchored_at` with `nil` at the driver's only call site — restoring the exact C-1 defect — and it
# survived 2148 examples, 0 failures. On real PostgreSQL the same build ADMITTED a run one second
# inside its deadline that had spent 1.6s in its pre-transaction window: frontier entry
# `in_progress`, bytes reserved, a `crawl_terminal_outcomes` row written — where :442 requires
# refusal with zero effects.
#
# So every proof here drives the REAL `crawl_fetch_due` handler, and the elapsed time is real time
# measured by PostgreSQL. Nothing calls `Admission` directly and no example asserts a parameter.
RSpec.describe "WF-005 the pass anchor", type: :acceptance,
                                          acceptance_ids: ["AC-CAP-007", "AC-WF-005"],
                                          test_types: %w[TYP-DATA TYP-INT] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

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

  def content_response
    Platform::Outbound::Outcome.response(
      status: 200, headers: { "content-type" => "text/html" }, body: "<html><title>t</title></html>",
      byte_count: 29, truncated: false, canonical_host: "shop.acme.example", port: 443,
      pinned_address: "198.51.100.7", final_url: "https://shop.acme.example/p1",
      redirect_count: 0, latency_ms: 5
    )
  end

  def crawl_row(cid) = DbInspector.one("SELECT * FROM crawls WHERE id=$1::uuid", [cid])

  # A run whose robots and sitemaps are already terminal, so the pass under test goes straight to
  # admission — which is the pass shape that reaches the anchor's call site.
  def ready_to_fetch
    ctx = running_crawl
    ensure_gate(ctx)
    resolve_robots(ctx, outbound_returning(response(status: 200, body: "User-agent: *\nAllow: /\n")))
    resolve_sitemaps(ctx, outbound_returning(response(status: 404)))
    ctx[:gate_id] = gate_row(ctx[:crawl_id])["id"]
    advance_gate(ctx)
    ctx
  end

  def pass(ctx, outbound, at:)
    action = DbInspector.one(<<~SQL, [ctx[:crawl_id]])
      SELECT sa.* FROM scheduled_actions sa
      JOIN crawl_frontier_entries e ON e.id = sa.target_id
      WHERE sa.action_kind = 'crawl_fetch_due' AND e.crawl_id = $1::uuid AND sa.status = 'pending'
      ORDER BY sa.due_at, sa.created_at LIMIT 1
    SQL
    raise "no crawl_fetch_due action exists" if action.nil?

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

  # THE PASS'S PRE-TRANSACTION WINDOW, MADE TO COST REAL TIME — IN THE DATABASE, NOT IN RUBY.
  #
  # In production this window is the robots fetch, sitemap discovery and host pacing: network calls
  # outside every transaction, whose duration `now` cannot see. A pass that reaches admission has
  # already resolved robots and sitemaps, so there is nothing left to be slow; this makes the gate
  # write that opens every pass take `seconds`, which puts the elapsed time in exactly the place the
  # contract is about — after the driver captured its anchor, before the admission transaction opens.
  #
  # A DATABASE TRIGGER RATHER THAN A STUB. `pg_sleep` runs in whichever backend executes the pass, so
  # this needs no production seam and no in-process sleep deciding the outcome, and the time is
  # measured by the same clock the decision is measured by.
  def slow_gate_write(ctx, seconds)
    conn = DbInspector.connection
    conn.exec(<<~SQL)
      CREATE OR REPLACE FUNCTION f1_test_slow_gate() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        PERFORM pg_sleep(#{seconds.to_f});
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER f1_test_slow_gate
        BEFORE INSERT OR UPDATE ON crawl_host_gates
        FOR EACH ROW WHEN (NEW.crawl_id = '#{ctx[:crawl_id]}'::uuid)
        EXECUTE FUNCTION f1_test_slow_gate();
    SQL
    yield
  ensure
    conn.exec(<<~SQL)
      DROP TRIGGER IF EXISTS f1_test_slow_gate ON crawl_host_gates;
      DROP FUNCTION IF EXISTS f1_test_slow_gate();
    SQL
  end

  def effects(ctx)
    {
      reserved: DbInspector.one(
        "SELECT reserved_response_bytes FROM crawl_budget_counters WHERE crawl_id=$1::uuid", [ctx[:crawl_id]]
      )&.fetch("reserved_response_bytes", 0).to_i,
      claimed: DbInspector.one(
        "SELECT count(*) AS n FROM crawl_frontier_entries WHERE crawl_id=$1::uuid AND state='in_progress'",
        [ctx[:crawl_id]]
      )["n"].to_i
    }
  end

  def hard_wall_clock_decision(ctx)
    DbInspector.one(<<~SQL, [ctx[:crawl_id]])
      SELECT id FROM crawl_limit_decisions
      WHERE crawl_id = $1::uuid AND limit_dimension = 'wall_clock_run_duration' AND threshold_kind = 'hard'
    SQL
  end

  it "PROOF 177 — a pass whose pre-transaction window outlasts the margin REFUSES, with no effects" do
    # THE DEFECT, AT THE DRIVER. One second of margin, 1.6 seconds spent before the admission
    # transaction opens. With the anchor carried the run is over by the time admission decides; with
    # the anchor dropped — which is the mutation round 8 applied — admission measures its advance from
    # its own `BEGIN` and the run is admitted with 1.6 seconds of its clock invisible.
    ctx = ready_to_fetch
    deadline = Platform::PgInstant.utc(crawl_row(ctx[:crawl_id])["deadline_at"])
    at = age_run_to(ctx, deadline - 1)

    result = slow_gate_write(ctx, 1.6) { pass(ctx, content_outbound(content_response), at:) }

    expect(result).to be_success
    expect(result.payload[:pass_outcome]).to eq(Workflows::Wf005::CrawlDriver::HALTED)
    expect(result.payload[:reason_code]).to eq(Workflows::Wf005::Admission::WALL_CLOCK)
    # ":442 — at 60 elapsed minutes NO NEW REQUEST STARTS." Not a late refusal: no request was made.
    expect(requests).to be_empty
    expect(effects(ctx)).to eq({ reserved: 0, claimed: 0 })
    expect(hard_wall_clock_decision(ctx)).not_to be_nil
  end

  it "PROOF 178 — the same pass INSIDE the margin admits, fetches and reserves" do
    # THE ADVERSARIAL HALF. A driver that refused every slow pass would satisfy PROOF 177 and be
    # useless. Same fixture, same 1.6-second window, a margin that comfortably contains it.
    ctx = ready_to_fetch
    at = age_run_to(ctx, start_now + (10 * 60))

    result = slow_gate_write(ctx, 1.6) { pass(ctx, content_outbound(content_response), at:) }

    expect(result).to be_success
    expect(result.payload[:pass_outcome]).to eq(Workflows::Wf005::CrawlDriver::FETCHED)
    expect(requests.length).to eq(1)
    expect(effects(ctx)[:reserved]).to be > 0
    expect(hard_wall_clock_decision(ctx)).to be_nil
  end

  it "PROOF 179 — elapsed time SPLIT across BEGIN decides identically to all of it before" do
    # THE EQUIVALENCE, THROUGH THE DRIVER. C-1's whole content is that which side of `BEGIN` the
    # elapsed time falls on must not change the answer. PROOF 177 spends it all before; this spends
    # half before and half after — the second half inside the admission transaction, by holding the
    # frontier lock the admission must wait for — and the outcome is the same refusal.
    ctx = ready_to_fetch
    deadline = Platform::PgInstant.utc(crawl_row(ctx[:crawl_id])["deadline_at"])
    at = age_run_to(ctx, deadline - 1)

    result = slow_gate_write(ctx, 0.8) do
      wait_out_frontier(ctx, 0.9) { pass(ctx, content_outbound(content_response), at:) }
    end

    expect(result).to be_success
    expect(result.payload[:pass_outcome]).to eq(Workflows::Wf005::CrawlDriver::HALTED)
    expect(result.payload[:reason_code]).to eq(Workflows::Wf005::Admission::WALL_CLOCK)
    expect(requests).to be_empty
    expect(effects(ctx)).to eq({ reserved: 0, claimed: 0 })
  end

  # ---- :442's boundary, through the real handler (round 8, R8-9) ---------------

  it "PROOF 187 — a pass entering EXACTLY at the deadline halts and starts no request" do
    # THE BOUNDARY WHERE IT IS DETERMINISTIC. `deadline_at` is frozen at the accepted start and the
    # handler's instant is the command's `requested_at_utc`, so this is the one place the exact
    # equality :442 states can be constructed end to end: the pass enters at the very microsecond the
    # run's sixty minutes are up.
    ctx = ready_to_fetch
    deadline = Platform::PgInstant.utc(crawl_row(ctx[:crawl_id])["deadline_at"])
    at = age_run_to(ctx, deadline)
    expect(at).to eq(deadline)

    result = pass(ctx, content_outbound(content_response), at:)

    expect(result).to be_success
    expect(result.payload[:pass_outcome]).to eq(Workflows::Wf005::CrawlDriver::HALTED)
    # ":442 — AT 60 elapsed minutes, NO NEW REQUEST STARTS." At, not after.
    expect(requests).to be_empty
    expect(effects(ctx)).to eq({ reserved: 0, claimed: 0 })
  end

  it "PROOF 188 — five seconds INSIDE the deadline the same pass fetches" do
    # THE ADVERSARIAL HALF, AT A MARGIN THE PASS CAN FIT INSIDE. Deliberately not one microsecond: a
    # pass takes real milliseconds to reach admission, and `after_wait` adds them, so a run with one
    # microsecond left is genuinely over by the time the decision is made and refusing it is CORRECT.
    # The microsecond-precise half of :442's boundary is asserted where it can be constructed exactly
    # — PROOF 180-184 against `Platform::PgInstant.expired?` — and this asserts the end-to-end half:
    # a run with time left still starts its request.
    ctx = ready_to_fetch
    deadline = Platform::PgInstant.utc(crawl_row(ctx[:crawl_id])["deadline_at"])
    at = age_run_to(ctx, deadline - 5)

    result = pass(ctx, content_outbound(content_response), at:)

    expect(result).to be_success
    expect(result.payload[:pass_outcome]).to eq(Workflows::Wf005::CrawlDriver::FETCHED)
    expect(requests.length).to eq(1)
  end
end
