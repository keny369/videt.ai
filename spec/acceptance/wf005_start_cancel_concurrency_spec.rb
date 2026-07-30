# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# StartCrawl RACING CancelCrawl (S-07-009; DECISIONS ADR-103).
#
# The two commands serialize on DIFFERENT OBJECTS. `StartCrawl` takes the per-Project ADVISORY lock and
# then relies on a compare-and-set (`state = 'queued' AND state_version = $2`); `CancelCrawl` takes the
# Crawl ROW lock. So a cancellation can commit in the window between StartCrawl's authoritative read and
# its transition — and before this tranche the SAME cancellation produced `crawl_not_queued` when it
# landed a moment earlier and a `Platform::InvariantViolation` when it landed a moment later. Timing
# decided whether an ordinary race was a domain refusal or an invariant failure.
#
# THE WINDOW IS FORCED, NOT WAITED FOR, and it is forced with the repository's own technique: a database
# trigger rather than a hook in production code, exactly as `FailureInjector` aborts a real statement.
# The trigger takes an advisory lock the example holds, on the FIRST statement of the accepted-start
# commit, so StartCrawl blocks INSIDE its transaction — past the read, past the reservation, before the
# compare-and-set. `RaceHarness#interleave` then runs the cancellation underneath it and releases only
# once StartCrawl is OBSERVABLY blocked (`pg_locks`, not a sleep).
RSpec.describe "WF-005 start versus cancel", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-DATA TYP-INT TYP-SEC] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  GATE_NAME = "f1-test-start-cancel-window"

  def crawl_row(cid) = DbInspector.one("SELECT * FROM crawls WHERE id = $1::uuid", [cid])
  def count(sql, params = []) = DbInspector.one(sql, params)["c"].to_i

  # Suspend the accepted-start commit at its first statement. Conditional on the command type, because
  # the cancellation running underneath writes to the SAME table and must not block on the same gate.
  def gate_accepted_start(key)
    conn = DbInspector.connection
    conn.exec(<<~SQL)
      CREATE OR REPLACE FUNCTION f1_test_gate_start() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.command_type = 'wf005.start_crawl' THEN
          PERFORM pg_advisory_xact_lock(#{key});
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER f1_test_gate_start BEFORE INSERT ON command_executions
        FOR EACH ROW EXECUTE FUNCTION f1_test_gate_start();
    SQL
    yield
  ensure
    conn.exec(<<~SQL)
      DROP TRIGGER IF EXISTS f1_test_gate_start ON command_executions;
      DROP FUNCTION IF EXISTS f1_test_gate_start();
    SQL
  end

  # A QUEUED Crawl with its `crawl_dispatch` action, ready to be started.
  def queued_crawl
    g = bootstrap
    sid = register_source(g, "https://shop.acme.example").tap { |s| verify(g, s) }
    activate_source(g, sid)
    raise "activation failed" unless activate_project(g).success?

    crawl_id = Workflows::Wf005::Handlers::QueueCrawl.new.call(
      command: Workflows::Wf005::Commands::QueueCrawl.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "qc-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: g[:session_id], organization_id: g[:organization_id], project_id: g[:project_id],
        requested_at_utc: act_now
      ), request_context: act_ctx
    ).payload[:crawl_id]
    { g:, crawl_id:,
      action: DbInspector.one("SELECT * FROM scheduled_actions WHERE action_kind='crawl_dispatch' AND target_id=$1::uuid",
                              [crawl_id]) }
  end

  def start(ctx)
    a = ctx[:action]
    Workflows::Wf005::Handlers::StartCrawl.new.call(
      command: Workflows::Wf005::Commands::StartCrawl.new(
        command_id: SecureRandom.uuid_v7, schema_version: a["action_schema_version"],
        organization_id: a["organization_id"], target_type: a["target_type"], crawl_id: a["target_id"],
        due_at: Time.parse(a["due_at"]).getutc, action_id: a["id"],
        action_identity_sha256: [a["identity_sha256"].sub(/\A\\x/, "")].pack("H*"),
        requested_at_utc: start_now
      ), request_context: executor_ctx(start_now)
    )
  end

  def cancel(ctx)
    Workflows::Wf005::Handlers::CancelCrawl.new.call(
      command: Workflows::Wf005::Commands::CancelCrawl.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "cc-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: ctx[:g][:session_id], organization_id: ctx[:g][:organization_id],
        project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id],
        expected_state_version: crawl_row(ctx[:crawl_id])["state_version"].to_i, requested_at_utc: act_now
      ), request_context: act_ctx
    )
  end

  it "PROOF 88 — a cancellation committed INSIDE the start window is a domain refusal, not an invariant failure" do
    ctx = queued_crawl
    key = RaceHarness.key_for(GATE_NAME)

    started, canceled = gate_accepted_start(key) do
      RaceHarness.interleave(key, gated: [-> { start(ctx) }], while_committing: -> { cancel(ctx) })
    end
    result = started.first

    # THE RACE HAPPENED. The cancellation committed while the start was inside its transaction, past
    # its authoritative read: if it had committed earlier, StartCrawl's own `crawl_not_queued` guard
    # would have fired before any of the writes below were attempted, and this example would prove
    # nothing about the window it exists for.
    expect(canceled.success?).to be(true)

    # 1. THE CALLER RECEIVES THE DOMAIN REFUSAL. Not `Platform::InvariantViolation`, and not a raised
    #    exception of any kind — the same reason code the same handler reports when it sees the
    #    transition a moment earlier, because it is the same fact.
    expect(result).to be_a(Platform::CommandResult)
    expect(result.success?).to be(false)
    expect(result.failure.reason_code).to eq("crawl_not_queued")

    # 2. THE CANCELLATION REMAINS COMMITTED. The loser's rollback took nothing of the winner's with it.
    crawl = crawl_row(ctx[:crawl_id])
    expect(crawl["state"]).to eq("canceled")
    expect(crawl["completion_reason"]).to eq("canceled")

    # 3. NO START-SIDE WRITE SURVIVED. `started_at`, the deadline and the metering columns are the ones
    #    the accepted start stamps in the very statement that lost.
    expect(crawl["started_at"]).to be_nil
    expect(crawl["deadline_at"]).to be_nil
    expect(crawl["entitlement_reservation_id"]).to be_nil
    expect(count("SELECT count(*) AS c FROM evaluations WHERE crawl_id = $1::uuid", [ctx[:crawl_id]])).to eq(0)
    expect(count("SELECT count(*) AS c FROM crawl_frontier_entries WHERE crawl_id = $1::uuid", [ctx[:crawl_id]])).to eq(0)

    # 4. NO RESERVATION LEAKS. `reserve` and `start_execution` both ran before the lost compare-and-set,
    #    so a denial written INLINE would have committed a reservation left `executing` for a run that
    #    never ran — and nothing would ever commit or release it. The rollback is what prevents that,
    #    which is why the refusal is written in a SECOND transaction rather than in this one.
    expect(count("SELECT count(*) AS c FROM entitlement_reservations WHERE organization_id = $1::uuid",
                 [ctx[:g][:organization_id]])).to eq(0)
    expect(count("SELECT count(*) AS c FROM entitlement_decisions WHERE organization_id = $1::uuid AND operation = 'crawl.start'",
                 [ctx[:g][:organization_id]])).to eq(0)

    # 5. THE REFUSAL IS AUDITED ONCE, against what the winner actually committed. The rolled-back
    #    attempt's own execution row went with it, so there is exactly one.
    executions = DbInspector.all(<<~SQL, [ctx[:crawl_id]])
      SELECT * FROM command_executions WHERE command_type = 'wf005.start_crawl' AND target_id = $1::uuid
    SQL
    expect(executions.size).to eq(1)
    audit = DbInspector.one(<<~SQL, [ctx[:crawl_id]])
      SELECT * FROM audit_record_registry WHERE entity_id = $1::uuid AND reason_code = 'crawl_not_queued'
    SQL
    expect(audit).not_to be_nil
    expect(JSON.parse(audit["payload"])["observed_state"]).to eq("canceled")
    # And NO `CrawlStarted`: the start did not happen, so nothing says it did.
    expect(count(<<~SQL, [ctx[:crawl_id]])).to eq(0)
      SELECT count(*) AS c FROM event_registry WHERE aggregate_id = $1::uuid AND event_type = 'CrawlStarted'
    SQL
  end

  it "PROOF 89 — a lost compare-and-set the state does NOT explain still escalates" do
    # The discrimination that stops this repair from being a blanket rescue. `f1_crawls_guard` permits a
    # non-state update on a non-terminal row, so `state_version` can move while `state` stays `queued` —
    # and a compare-and-set lost to THAT is not a cancellation. Nothing in production does it, which is
    # exactly why it must still escalate: a lost race nobody can name is not an ordinary outcome.
    ctx = queued_crawl
    key = RaceHarness.key_for(GATE_NAME)

    bump = lambda do
      DbInspector.connection.exec_params(
        "UPDATE crawls SET limit_counters = '{\"probe\":1}'::jsonb, state_version = state_version + 1 WHERE id = $1::uuid",
        [ctx[:crawl_id]]
      )
    end
    started, = gate_accepted_start(key) do
      RaceHarness.interleave(key, gated: [-> { start(ctx) }], while_committing: bump)
    end

    # `spawn_operation` returns the exception rather than raising it in the example's thread.
    expect(started.first).to be_a(Platform::InvariantViolation)
    expect(crawl_row(ctx[:crawl_id])["state"]).to eq("queued")
    expect(count("SELECT count(*) AS c FROM entitlement_reservations WHERE organization_id = $1::uuid",
                 [ctx[:g][:organization_id]])).to eq(0)
  end
end
