# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# THE TERMINAL CHECKPOINT RACING AN IN-FLIGHT PASS (S-07-009; DECISIONS ADR-105).
#
# `CrawlDriver#retire` writes the frontier terminalize AND the `crawl_terminal_outcomes` row in one
# transaction under the `crawl-frontier:<crawl>` advisory lock. `Handlers::CompleteCrawl` counts those
# rows. Before ADR-105 the two serialized on DIFFERENT OBJECTS — the checkpoint on `crawls FOR UPDATE`
# alone — so the checkpoint could count a snapshot the pass invalidated a moment later, and a run that
# had fetched a valid Document was recorded `failed` with its entitlement RELEASED while
# `crawl_terminal_outcomes` said `document_created / covered`. The acceptance review reproduced that at
# natural timing, 10/10, and it is IRREVERSIBLE: `f1_crawls_guard` refuses every UPDATE of a terminal row.
#
# ADR-101 is what makes this ordinary rather than exotic: a drained pass schedules a checkpoint for its
# own instant, so checkpoint-concurrent-with-pass is the design's normal case.
#
# `RaceHarness#interleave` CANNOT express this race, and the reason is the repair. `interleave` runs its
# `while_committing` operation TO COMPLETION while the gated one is held; under ADR-105 the checkpoint
# BLOCKS on the frontier lock the gated pass is holding, so it would never complete and the harness would
# deadlock against its own gate. The example therefore uses the harness's primitives — the same
# `pg_locks` observation, the same "no sleep orders anything" rule — and asserts the blocking directly.
RSpec.describe "WF-005 checkpoint versus an in-flight pass", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-DATA TYP-INT] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  RETIRE_GATE = "f1-test-retire-window"

  def crawl_row(cid) = DbInspector.one("SELECT * FROM crawls WHERE id = $1::uuid", [cid])
  def outcomes(cid) = DbInspector.all("SELECT * FROM crawl_terminal_outcomes WHERE crawl_id=$1::uuid", [cid])
  def action_row(id) = DbInspector.one("SELECT * FROM scheduled_actions WHERE id = $1::uuid", [id])

  def reservation(cid)
    DbInspector.one(<<~SQL, [cid])
      SELECT r.* FROM entitlement_reservations r
      JOIN crawls c ON c.entitlement_reservation_id = r.id WHERE c.id = $1::uuid
    SQL
  end

  # Suspend `CrawlDriver#retire` between its frontier terminalize and its outcome INSERT — the exact
  # window the defect lives in. A trigger, not a hook in production code, as `FailureInjector` already
  # establishes; the checkpoint never inserts into this table, so no predicate is needed.
  def gate_retire(key)
    conn = DbInspector.connection
    conn.exec(<<~SQL)
      CREATE OR REPLACE FUNCTION f1_test_gate_retire() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        PERFORM pg_advisory_xact_lock(#{key});
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER f1_test_gate_retire BEFORE INSERT ON crawl_terminal_outcomes
        FOR EACH ROW EXECUTE FUNCTION f1_test_gate_retire();
    SQL
    yield
  ensure
    conn.exec(<<~SQL)
      DROP TRIGGER IF EXISTS f1_test_gate_retire ON crawl_terminal_outcomes;
      DROP FUNCTION IF EXISTS f1_test_gate_retire();
    SQL
  end

  def fetchable
    ctx = running_crawl
    ensure_gate(ctx)
    resolve_robots(ctx, outbound_returning(response(status: 200, body: "User-agent: *\nAllow: /\n")))
    resolve_sitemaps(ctx, outbound_returning(response(status: 404, body: "")))
    clear_rate_window(gate_row(ctx[:crawl_id])["id"])
    ctx
  end

  def first_fetch_action(ctx)
    link = Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg)
                                                        .enter_org_context(org: ctx[:g][:organization_id],
                                                                          correlation_id: SecureRandom.uuid_v7)
      Workflows::Wf005::CrawlFetchDueSchedule.link_next(
        pg:, organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
        crawl_id: ctx[:crawl_id], now: start_now, correlation_id: SecureRandom.uuid_v7
      )
    end
    action_row(link[:action_id])
  end

  # A checkpoint due NOW, created exactly as a drained pass creates one (ADR-101).
  def due_now_checkpoint(ctx)
    id = Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg)
                                                        .enter_org_context(org: ctx[:g][:organization_id],
                                                                          correlation_id: SecureRandom.uuid_v7)
      Workflows::Wf005::CrawlTerminalDeadlineSchedule.schedule(
        pg:, organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
        crawl_id: ctx[:crawl_id], due_at: start_now, now: start_now, correlation_id: SecureRandom.uuid_v7
      )
    end
    action_row(id)
  end

  def run_pass(ctx, action)
    command = Workflows::Wf005::Commands::RecordFetchAttempt.new(
      command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
      organization_id: action["organization_id"], target_type: action["target_type"],
      frontier_entry_id: action["target_id"], due_at: Time.parse(action["due_at"]).getutc,
      action_id: action["id"],
      action_identity_sha256: [action["identity_sha256"].sub(/\A\\x/, "")].pack("H*"),
      requested_at_utc: start_now
    )
    Workflows::Wf005::Handlers::RecordFetchAttempt.new.call(
      command:, request_context: executor_ctx(start_now), outbound: page_outbound, pacer: pacer_for(ctx)
    )
  end

  def page_outbound
    body = "<html><title>t</title></html>"
    outcome = Platform::Outbound::Outcome.response(
      status: 200, headers: { "content-type" => "text/html" }, body:, byte_count: body.bytesize,
      truncated: false, canonical_host: "shop.acme.example", port: 443, pinned_address: "198.51.100.7",
      final_url: "https://shop.acme.example/", redirect_count: 0, latency_ms: 5
    )
    Object.new.tap { |o| o.define_singleton_method(:fetch) { |*_a, **_k| outcome } }
  end

  def run_checkpoint(ctx, action)
    command = Workflows::Wf005::Commands::CompleteCrawl.new(
      command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
      organization_id: action["organization_id"], target_type: action["target_type"],
      crawl_id: action["target_id"], due_at: Time.parse(action["due_at"]).getutc, action_id: action["id"],
      action_identity_sha256: [action["identity_sha256"].sub(/\A\\x/, "")].pack("H*"),
      requested_at_utc: start_now
    )
    Workflows::Wf005::Handlers::CompleteCrawl.new.call(command:, request_context: executor_ctx(start_now))
  end

  it "PROOF 91 — a checkpoint cannot count a run whose pass is mid-retirement" do
    ctx = fetchable
    fetch_action = first_fetch_action(ctx)
    checkpoint_action = due_now_checkpoint(ctx)
    gate_key = RaceHarness.key_for(RETIRE_GATE)
    frontier_key = RaceHarness.key_for("crawl-frontier:#{ctx[:crawl_id]}")

    controller = RaceHarness.open_connection
    pass_result = nil
    checkpoint_result = nil
    begin
      controller.exec_params("SELECT pg_advisory_lock($1)", [gate_key])

      gate_retire(gate_key) do
        pass = RaceHarness.spawn_operation(-> { run_pass(ctx, fetch_action) })
        # The pass is INSIDE `retire`: it has terminalized the frontier entry and is blocked on the
        # gate before its outcome INSERT, holding the frontier advisory lock. Observed in `pg_locks`,
        # not waited for.
        RaceHarness.wait_until("the pass blocked mid-retirement") { RaceHarness.blocked_on(gate_key) >= 1 }

        checkpoint = RaceHarness.spawn_operation(-> { run_checkpoint(ctx, checkpoint_action) })
        # THE ASSERTION THE REPAIR TURNS ON. The checkpoint must be unable to proceed while a
        # retirement is in flight, and it is stopped by the FRONTIER lock — the same object
        # `Admission` takes first, so no lock order is inverted. Before ADR-105 it sailed past and
        # committed `failed`/`released` against a run that had a Document.
        RaceHarness.wait_until("the checkpoint blocked on the frontier lock") do
          RaceHarness.blocked_on(frontier_key) >= 1
        end

        controller.exec_params("SELECT pg_advisory_unlock($1)", [gate_key])
        pass_result = pass.value
        checkpoint_result = checkpoint.value
      end
    ensure
      controller.exec_params("SELECT pg_advisory_unlock_all()")
      controller.close
    end

    expect(pass_result).to be_a(Platform::CommandResult)
    expect(pass_result.payload[:pass_outcome]).to eq("fetched")
    expect(outcomes(ctx[:crawl_id]).sole["outcome"]).to eq("document_created")

    # The checkpoint counted the COMMITTED retirement, not a snapshot taken through it.
    expect(checkpoint_result).to be_a(Platform::CommandResult)
    expect(checkpoint_result.success?).to be(true)
    expect(checkpoint_result.payload[:documents]).to eq(1)
    crawl = crawl_row(ctx[:crawl_id])
    expect(crawl["state"]).to eq("completed")
    expect(crawl["completion_reason"]).to eq("completed")
    expect(crawl["coverage_status"]).to eq("full")
    # And the customer is charged for the run they got, which is the half of the defect that reached
    # the ledger: before the repair this was `released`.
    expect(checkpoint_result.payload[:entitlement_outcome]).to eq("committed")
    expect(reservation(ctx[:crawl_id])["state"]).to eq("committed")
  end
end
