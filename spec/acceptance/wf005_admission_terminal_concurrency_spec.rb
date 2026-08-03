# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# R5-3: Admission versus the two terminal handlers, on real PostgreSQL locks.
#
# The cycle was `Admission: crawls FOR KEY SHARE -> frontier advisory` against
# `Cancel/Complete: frontier advisory -> crawls FOR UPDATE`. A soft wall-clock observation supplied
# the first edge because its immutable child row fell through into dequeue. These proofs gate the
# actual writes with database triggers and observe the named advisory locks in `pg_locks`; no sleep
# establishes order and no production hook exists for the tests.
RSpec.describe "WF-005 Admission versus terminal handlers", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-DATA TYP-INT] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def crawl_row(cid) = DbInspector.one("SELECT * FROM crawls WHERE id=$1::uuid", [cid])

  def soft_now(ctx)
    age_run_to(ctx, start_now + (46 * 60))
  end

  def admit(ctx, at: soft_now(ctx))
    Workflows::Wf005::Admission.new.claim_next(
      organization_id: ctx[:g][:organization_id], crawl_id: ctx[:crawl_id], now: at
    )
  end

  def cancel_command(ctx)
    Workflows::Wf005::Commands::CancelCrawl.new(
      command_id: SecureRandom.uuid_v7, idempotency_key: "cc-#{SecureRandom.hex(6)}", schema_version: "1.0",
      session_id: ctx[:g][:session_id], organization_id: ctx[:g][:organization_id],
      project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id],
      expected_state_version: crawl_row(ctx[:crawl_id])["state_version"].to_i, requested_at_utc: act_now
    )
  end

  def cancel(ctx, command)
    Workflows::Wf005::Handlers::CancelCrawl.new.call(command:, request_context: act_ctx)
  end

  def checkpoint_action(ctx)
    id = Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg)
                                                            .enter_org_context(org: ctx[:g][:organization_id],
                                                                              correlation_id: SecureRandom.uuid_v7)
      Workflows::Wf005::CrawlTerminalDeadlineSchedule.schedule(
        pg:, organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
        crawl_id: ctx[:crawl_id], due_at: start_now, now: start_now,
        correlation_id: SecureRandom.uuid_v7
      )
    end
    DbInspector.one("SELECT * FROM scheduled_actions WHERE id=$1::uuid", [id])
  end

  def complete(ctx, action)
    command = Workflows::Wf005::Commands::CompleteCrawl.new(
      command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
      organization_id: action["organization_id"], target_type: action["target_type"],
      crawl_id: action["target_id"], due_at: Platform::PgInstant.utc(action["due_at"]), action_id: action["id"],
      action_identity_sha256: [action["identity_sha256"].sub(/\A\\x/, "")].pack("H*"),
      requested_at_utc: start_now
    )
    Workflows::Wf005::Handlers::CompleteCrawl.new.call(command:, request_context: executor_ctx(start_now))
  end

  def effects(ctx)
    {
      decisions: DbInspector.one(
        "SELECT count(*) AS n FROM crawl_limit_decisions WHERE crawl_id=$1::uuid", [ctx[:crawl_id]]
      )["n"].to_i,
      reserved: DbInspector.one(
        "SELECT reserved_response_bytes FROM crawl_budget_counters WHERE crawl_id=$1::uuid", [ctx[:crawl_id]]
      )&.fetch("reserved_response_bytes", 0).to_i,
      claimed: DbInspector.one(
        "SELECT count(*) AS n FROM crawl_frontier_entries WHERE crawl_id=$1::uuid AND state='in_progress'",
        [ctx[:crawl_id]]
      )["n"].to_i
    }
  end

  # THE RUNTIME STRUCTURAL PROBE. It executes at the actual child-row INSERT and derives the expected
  # frontier identity from NEW.crawl_id. A soft fall-through may insert only while this backend already
  # holds that xact advisory lock. With the old decision-then-frontier order the trigger raises before
  # the insert, so the mutation fails deterministically rather than depending on a rival transaction.
  # When `gate_key` is present the same trigger then suspends Admission at that exact point.
  def probe_limit_insert(gate_key: nil)
    gate_statement = gate_key ? "PERFORM pg_advisory_xact_lock(#{gate_key});" : ""
    conn = DbInspector.connection
    conn.exec(<<~SQL)
      CREATE OR REPLACE FUNCTION f1_test_probe_admission_limit() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE
        expected bigint := hashtextextended('crawl-frontier:' || NEW.crawl_id::text, 0);
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_locks
          WHERE pid = pg_backend_pid() AND locktype = 'advisory' AND granted
            AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
            AND classid = (((expected >> 32) & 4294967295))::oid
            AND objid = ((expected & 4294967295))::oid
        ) THEN
          RAISE EXCEPTION 'soft Admission decision preceded crawl frontier lock';
        END IF;
        #{gate_statement}
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER f1_test_probe_admission_limit
        BEFORE INSERT ON crawl_limit_decisions
        FOR EACH ROW WHEN (NEW.limit_dimension = 'wall_clock_run_duration' AND NEW.threshold_kind = 'soft')
        EXECUTE FUNCTION f1_test_probe_admission_limit();
    SQL
    yield
  ensure
    conn.exec(<<~SQL)
      DROP TRIGGER IF EXISTS f1_test_probe_admission_limit ON crawl_limit_decisions;
      DROP FUNCTION IF EXISTS f1_test_probe_admission_limit();
    SQL
  end

  # Suspend a terminal handler at its command ledger insert. Both handlers have already acquired
  # frontier then Crawl and made their terminal effects, but those effects are still uncommitted.
  def gate_terminal(command_type, key)
    conn = DbInspector.connection
    conn.exec(<<~SQL)
      CREATE OR REPLACE FUNCTION f1_test_gate_terminal() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.command_type = '#{command_type}' THEN
          PERFORM pg_advisory_xact_lock(#{key});
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER f1_test_gate_terminal BEFORE INSERT ON command_executions
        FOR EACH ROW EXECUTE FUNCTION f1_test_gate_terminal();
    SQL
    yield
  ensure
    conn.exec(<<~SQL)
      DROP TRIGGER IF EXISTS f1_test_gate_terminal ON command_executions;
      DROP FUNCTION IF EXISTS f1_test_gate_terminal();
    SQL
  end

  it "PROOF 132 — the soft fall-through insert structurally occurs under the Crawl frontier lock" do
    ctx = running_crawl

    decision = probe_limit_insert { admit(ctx) }

    expect(decision).to be_a(Workflows::Wf005::Admission::Decision)
    expect(DbInspector.one(<<~SQL, [ctx[:crawl_id]])).not_to be_nil
      SELECT id FROM crawl_limit_decisions
      WHERE crawl_id=$1::uuid AND limit_dimension='wall_clock_run_duration' AND threshold_kind='soft'
    SQL
  end

  it "PROOF 133 — Admission first makes cancellation wait on frontier, never a 40P01 cycle" do
    ctx = running_crawl
    at = soft_now(ctx)
    command = cancel_command(ctx)
    gate_key = RaceHarness.key_for("f1-test-admission-soft-#{ctx[:crawl_id]}")
    frontier_key = RaceHarness.key_for("crawl-frontier:#{ctx[:crawl_id]}")
    controller = RaceHarness.open_connection
    admitted = cancelled = nil

    begin
      controller.exec_params("SELECT pg_advisory_lock($1)", [gate_key])
      probe_limit_insert(gate_key:) do
        admission_op = cancellation_op = nil
        begin
          admission_op = RaceHarness.spawn_operation(-> { admit(ctx, at:) })
          RaceHarness.wait_until("Admission paused after frontier and at its soft decision") do
            RaceHarness.blocked_on(gate_key).positive?
          end

          cancellation_op = RaceHarness.spawn_operation(-> { cancel(ctx, command) })
          RaceHarness.wait_until("cancellation waiting on Admission's frontier lock") do
            RaceHarness.blocked_on(frontier_key).positive?
          end
          expect(RaceHarness.blocked_on(frontier_key)).to be >= 1
        ensure
          controller.exec_params("SELECT pg_advisory_unlock_all()")
          admitted = admission_op&.value
          cancelled = cancellation_op&.value
        end
      end
    ensure
      controller.exec_params("SELECT pg_advisory_unlock_all()")
      controller.close
    end

    expect(admitted).to be_a(Workflows::Wf005::Admission::Decision), admitted.inspect
    expect(cancelled).to be_a(Platform::CommandResult), cancelled.inspect
    expect(cancelled.success?).to be(true)
    expect(crawl_row(ctx[:crawl_id])["state"]).to eq("canceled")
  end

  it "PROOF 134 — cancellation first is re-read under frontier before any Admission effect" do
    ctx = running_crawl
    at = soft_now(ctx)
    command = cancel_command(ctx)
    gate_key = RaceHarness.key_for("f1-test-cancel-before-admission-#{ctx[:crawl_id]}")
    frontier_key = RaceHarness.key_for("crawl-frontier:#{ctx[:crawl_id]}")
    controller = RaceHarness.open_connection
    cancelled = admitted = nil

    begin
      controller.exec_params("SELECT pg_advisory_lock($1)", [gate_key])
      gate_terminal("wf005.cancel_crawl", gate_key) do
        cancellation_op = admission_op = nil
        begin
          cancellation_op = RaceHarness.spawn_operation(-> { cancel(ctx, command) })
          RaceHarness.wait_until("cancellation paused after its terminal effect") do
            RaceHarness.blocked_on(gate_key).positive?
          end
          admission_op = RaceHarness.spawn_operation(-> { admit(ctx, at:) })
          RaceHarness.wait_until("Admission waiting behind cancellation on frontier") do
            RaceHarness.blocked_on(frontier_key).positive?
          end
        ensure
          controller.exec_params("SELECT pg_advisory_unlock_all()")
          cancelled = cancellation_op&.value
          admitted = admission_op&.value
        end
      end
    ensure
      controller.exec_params("SELECT pg_advisory_unlock_all()")
      controller.close
    end

    expect(cancelled).to be_a(Platform::CommandResult), cancelled.inspect
    expect(cancelled.success?).to be(true)
    expect(admitted).to be_a(Workflows::Wf005::Admission::Decision), admitted.inspect
    expect(admitted.reason_code).to eq("admission_crawl_not_running")
    expect(effects(ctx)).to eq({ decisions: 0, reserved: 0, claimed: 0 })
  end

  it "PROOF 135 — CompleteCrawl first is likewise re-read before any Admission effect" do
    ctx = running_crawl
    at = soft_now(ctx)
    action = checkpoint_action(ctx)
    gate_key = RaceHarness.key_for("f1-test-complete-before-admission-#{ctx[:crawl_id]}")
    frontier_key = RaceHarness.key_for("crawl-frontier:#{ctx[:crawl_id]}")
    controller = RaceHarness.open_connection
    completed = admitted = nil

    begin
      controller.exec_params("SELECT pg_advisory_lock($1)", [gate_key])
      gate_terminal("wf005.complete_crawl", gate_key) do
        completion_op = admission_op = nil
        begin
          completion_op = RaceHarness.spawn_operation(-> { complete(ctx, action) })
          RaceHarness.wait_until("CompleteCrawl paused after its terminal effect") do
            RaceHarness.blocked_on(gate_key).positive?
          end
          admission_op = RaceHarness.spawn_operation(-> { admit(ctx, at:) })
          RaceHarness.wait_until("Admission waiting behind CompleteCrawl on frontier") do
            RaceHarness.blocked_on(frontier_key).positive?
          end
        ensure
          controller.exec_params("SELECT pg_advisory_unlock_all()")
          completed = completion_op&.value
          admitted = admission_op&.value
        end
      end
    ensure
      controller.exec_params("SELECT pg_advisory_unlock_all()")
      controller.close
    end

    expect(completed).to be_a(Platform::CommandResult), completed.inspect
    expect(completed.success?).to be(true)
    expect(crawl_row(ctx[:crawl_id])["state"]).to eq("failed")
    expect(admitted).to be_a(Workflows::Wf005::Admission::Decision), admitted.inspect
    expect(admitted.reason_code).to eq("admission_crawl_not_running")
    expect(effects(ctx)).to eq({ decisions: 0, reserved: 0, claimed: 0 })
  end
end
