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

  def events(cid)
    DbInspector.all(<<~SQL, [cid])
      SELECT event_type FROM event_registry WHERE aggregate_id = $1::uuid ORDER BY created_at
    SQL
  end

  # `db_clock`, `lease_due`, `set_lease_due`, `advance_authorization_epoch` and `wait_out_frontier`
  # are the shared post-wait harness in `Wf005CrawlChain`, used by these proofs and by PROOF 152 in
  # the terminal-checkpoint spec.

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

  # ---- the post-wait decision instant (owner ruling 1; R6-1, R6-5, R6-6) -------
  #
  # PROOFS 133-135 established that the ROWS are re-read after the wait. These establish that the
  # INSTANT is too, which is the half round 5's repair left behind: a `running` re-read agreeing with
  # a stale clock is exactly as wrong as no re-read at all, and it is harder to see because the state
  # assertion passes.

  it "PROOF 149 — a frontier wait that outlasts the deadline refuses instead of admitting" do
    # :442 — "At 60 elapsed minutes, NO NEW REQUEST STARTS." The admission sets out one second inside
    # the run's sixty minutes and is held on the frontier lock until PostgreSQL reports that more than
    # a second has passed, so by the time it may decide, the run's own deadline is behind it.
    ctx = running_crawl
    deadline = Platform::PgInstant.utc(crawl_row(ctx[:crawl_id])["deadline_at"])
    at = age_run_to(ctx, deadline - 1)

    decision = wait_out_frontier(ctx, 1.5) { admit(ctx, at:) }

    expect(decision).to be_a(Workflows::Wf005::Admission::Decision), decision.inspect
    expect(decision.reason_code).to eq(Workflows::Wf005::Admission::WALL_CLOCK)
    # NOTHING WAS SPENT. Under the pre-wait instant this admission reserved the per-URL maximum and
    # took a frontier entry for a run whose wall clock had already stopped it.
    expect(effects(ctx)).to include(reserved: 0, claimed: 0)
    expect(DbInspector.one(<<~SQL, [ctx[:crawl_id]])).not_to be_nil
      SELECT id FROM crawl_limit_decisions
      WHERE crawl_id = $1::uuid AND limit_dimension = 'wall_clock_run_duration' AND threshold_kind = 'hard'
    SQL
  end

  it "PROOF 150 — a frontier wait that outlasts the entitlement lease refuses instead of admitting" do
    # :551's strict-before lease rule, at the other surface that reads it. `reservation_executing?`
    # compares `lease_due` against the instant it is handed, so a lease that lapses inside the wait was
    # invisible: the run kept reserving budget and claiming work while no longer metered.
    ctx = running_crawl
    at = age_run_to(ctx, start_now + (10 * 60))
    set_lease_due(ctx[:crawl_id], at + 1)
    expect(lease_due(ctx[:crawl_id])).to eq(at + 1)

    decision = wait_out_frontier(ctx, 1.5) { admit(ctx, at:) }

    expect(decision).to be_a(Workflows::Wf005::Admission::Decision), decision.inspect
    expect(decision.reason_code).to eq(Workflows::Wf005::Admission::DENIALS[:entitlement])
    # The denial is reached in `authorize`, ahead of every observation, so not even a limit decision
    # is written for a run this admission never had the authority to touch.
    expect(effects(ctx)).to eq({ decisions: 0, reserved: 0, claimed: 0 })
  end

  it "PROOF 151 — a cancellation whose authority is revoked while it waits does not commit" do
    # :335 and SEC-REQ-004/005. The command authenticates and authorizes, then blocks on the frontier
    # lock, and the Organization's authorization epoch advances underneath it — the ratified
    # serialization point for every effective-access mutation, so this is a revocation, a suspension
    # or a policy change as far as this handler can tell, which is exactly as far as it should need to.
    ctx = running_crawl
    command = cancel_command(ctx)
    org = ctx[:g][:organization_id]
    frontier_key = RaceHarness.key_for("crawl-frontier:#{ctx[:crawl_id]}")
    controller = RaceHarness.open_connection
    cancelled = nil

    begin
      controller.exec_params("SELECT pg_advisory_lock($1)", [frontier_key])
      op = RaceHarness.spawn_operation(-> { cancel(ctx, command) })
      RaceHarness.wait_until("the cancellation blocked on the frontier lock") do
        RaceHarness.blocked_on(frontier_key) >= 1
      end
      # COMMITTED UNDERNEATH THE WAITER, which is what makes this a revocation rather than a fixture.
      advance_authorization_epoch(org)
      expect(RaceHarness.blocked_on(frontier_key)).to be >= 1
    ensure
      controller.exec_params("SELECT pg_advisory_unlock_all()")
      cancelled = op&.value
      controller.close
    end

    expect(cancelled).to be_a(Platform::CommandResult), cancelled.inspect
    expect(cancelled.success?).to be(false)
    expect(cancelled.failure.reason_code).to eq("crawl_cancel_unauthorized")
    # IRREVERSIBILITY IS THE POINT. `f1_crawls_guard` admits no edge out of a terminal state, so a
    # cancellation committed on revoked authority could never be undone.
    expect(crawl_row(ctx[:crawl_id])["state"]).to eq("running")
    expect(events(ctx[:crawl_id]).map { |e| e["event_type"] }).not_to include("CrawlCanceled")
    expect(DbInspector.one(<<~SQL, [ctx[:crawl_id]])["n"].to_i).to eq(0)
      SELECT count(*) AS n FROM entitlement_commit_intents WHERE reservation_id IN
        (SELECT entitlement_reservation_id FROM crawls WHERE id = $1::uuid)
    SQL
  end

  # ---- the closed fact set (owner ruling 2; R6-2, R6-3) -----------------------

  # A child fact written by a worker that is neither Admission nor a terminal handler: the shape every
  # unfenced producer has, reduced to the one statement they all end in.
  def insert_limit_decision_as_runtime(ctx)
    pg = PgTestConnection.connect(user: "f1_web")
    pg.exec("BEGIN")
    pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)",
                   [ctx[:g][:organization_id], SecureRandom.uuid_v7])
    pg.exec_params(<<~SQL, [SecureRandom.uuid_v7, ctx[:g][:organization_id], ctx[:g][:project_id], ctx[:crawl_id]])
      INSERT INTO crawl_limit_decisions
        (id, schema_version, created_at, correlation_id, causation_id, organization_id, project_id,
         crawl_id, limit_dimension, threshold_kind, configured_value, observed_value,
         affected_source_count, affected_url_count, decision_type, decision_value, decision_status,
         decision_reason_code, decided_by_service_identity_id, definition_versions, input_sha256,
         output_sha256, decided_at)
      VALUES ($1,'1.0',now(),gen_random_uuid(),gen_random_uuid(),$2::uuid,$3::uuid,$4::uuid,
              'accepted_pages_per_run','hard',10,10,1,1,'crawl_limit_observation','hard_reached','final',
              'limit_reached',gen_random_uuid(),'["v1"]'::jsonb,sha256(''::bytea),sha256(''::bytea),now())
    SQL
    pg.exec("COMMIT")
    :inserted
  rescue StandardError => e
    e
  ensure
    begin
      pg&.exec("ROLLBACK")
    rescue StandardError
      nil
    end
    pg&.close
  end

  it "PROOF 158 — a late fact racing a cancellation serializes and is refused, and the cancel stands" do
    # ROUND 6'S R6-2 INTERLEAVING, EXACTLY. CancelCrawl holds `crawl-frontier` and `crawls FOR UPDATE`,
    # has written `canceled`, and has not committed. A producer that read `running` a moment earlier
    # then arrives at its INSERT. Before this tranche it blocked on the foreign key's own tuple lock,
    # waited for the cancellation to commit, and then wrote its immutable fact onto the cancelled
    # Crawl — a valid row, permanently disagreeing with a frozen outcome that `f1_crawls_guard` makes
    # uncorrectable.
    ctx = running_crawl
    command = cancel_command(ctx)
    gate_key = RaceHarness.key_for("f1-test-late-fact-#{ctx[:crawl_id]}")
    controller = RaceHarness.open_connection
    cancelled = late = nil

    begin
      controller.exec_params("SELECT pg_advisory_lock($1)", [gate_key])
      gate_terminal("wf005.cancel_crawl", gate_key) do
        cancellation_op = late_op = nil
        begin
          cancellation_op = RaceHarness.spawn_operation(-> { cancel(ctx, command) })
          RaceHarness.wait_until("cancellation paused holding frontier and the Crawl row") do
            RaceHarness.blocked_on(gate_key).positive?
          end
          late_op = RaceHarness.spawn_operation(-> { insert_limit_decision_as_runtime(ctx) })
          # THE SERIALIZATION IS OBSERVED, NOT ASSUMED: the late writer is queued on a row lock behind
          # the backend that holds the gate, which is the closure trigger's `FOR KEY SHARE` waiting on
          # the cancellation's `FOR UPDATE`.
          RaceHarness.wait_until("the late fact blocked on the cancelling transaction's Crawl row") do
            RaceHarness.blocked_on_row_behind(gate_key).positive?
          end
        ensure
          controller.exec_params("SELECT pg_advisory_unlock_all()")
          cancelled = cancellation_op&.value
          late = late_op&.value
        end
      end
    ensure
      controller.exec_params("SELECT pg_advisory_unlock_all()")
      controller.close
    end

    # THE TERMINAL TRANSITION IS NOT ROLLED BACK BY THE STALE WORKER. The loser is the late fact.
    expect(cancelled).to be_a(Platform::CommandResult), cancelled.inspect
    expect(cancelled.success?).to be(true)
    expect(crawl_row(ctx[:crawl_id])["state"]).to eq("canceled")
    # And it is refused for the right reason: not privileges, not the foreign key, not the tenant
    # predicate — all three of which this row satisfies — but the parent's state.
    expect(late).to be_a(PG::RaiseException), late.inspect
    expect(late.message).to include("crawl_child_fact_after_terminal")
    expect(effects(ctx)).to include(decisions: 0)
  end
end
