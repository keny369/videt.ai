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
    clear_rate_window_for_crawl(ctx[:crawl_id])
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

  # A BLOCKED WAIT IN A TEST MUST FAIL, NOT HANG. `Queue#pop` with no timeout waits for ever, so an
  # example whose counterpart thread dies before pushing turns a red suite into one that never
  # finishes — observed here once as an eleven-minute stall with the process at 0% CPU and every
  # backend idle, which reads exactly like "still running" and is the least actionable failure mode
  # there is. `RaceHarness.wait_until` was already bounded; these three waits were not.
  #
  # Generous enough never to fire on a healthy run (the whole file takes about two seconds), short
  # enough that CI reports something a reader can act on.
  POP_TIMEOUT_S = 30

  def await(queue, what)
    value = queue.pop(timeout: POP_TIMEOUT_S)
    raise "timed out after #{POP_TIMEOUT_S}s waiting for: #{what}" if value.nil?

    value
  end

  # A façade stub that suspends INSIDE the request until the example releases it. This is the natural
  # mid-request window rather than a simulation of one: `fetch_and_settle` performs the network call
  # outside every transaction, so a pass here holds nothing at all.
  #
  # Defined at this level rather than inside one describe because TWO races need it — the checkpoint's
  # (FU-34) and the cancellation's (R3-6, PROOF 118) — and the second is the one ADR-113 never proved.
  def gated_page_outbound(started, release)
    body = "<html><title>t</title></html>"
    outcome = Platform::Outbound::Outcome.response(
      status: 200, headers: { "content-type" => "text/html" }, body:, byte_count: body.bytesize,
      truncated: false, canonical_host: "shop.acme.example", port: 443,
      pinned_address: "198.51.100.7", final_url: "https://shop.acme.example/", redirect_count: 0,
      latency_ms: 5
    )
    # Captured as a local, because `define_singleton_method`'s block runs with the STUB as `self`, so
    # a bare `await(...)` inside it would resolve against the stub and raise NoMethodError.
    awaiter = method(:await)
    Object.new.tap do |o|
      o.define_singleton_method(:fetch) do |*_a, **_k|
        started << :in_flight
        # Bounded like the others. `FetchContent#fetch` rescues StandardError, so this raise surfaces
        # as an adapter error and the example fails on its assertions — which is a report, not a hang.
        awaiter.call(release, "the example to release the in-flight request")
        outcome
      end
    end
  end

  def run_pass_with(ctx, action, outbound)
    command = Workflows::Wf005::Commands::RecordFetchAttempt.new(
      command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
      organization_id: action["organization_id"], target_type: action["target_type"],
      frontier_entry_id: action["target_id"], due_at: Time.parse(action["due_at"]).getutc,
      action_id: action["id"],
      action_identity_sha256: [action["identity_sha256"].sub(/\A\\x/, "")].pack("H*"),
      requested_at_utc: start_now
    )
    Workflows::Wf005::Handlers::RecordFetchAttempt.new.call(
      command:, request_context: executor_ctx(start_now), outbound:, pacer: pacer_for(ctx)
    )
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

  # A cancellation issued by an actor at the instant under test. The bootstrap session is issued at
  # `fixed_now - 300` and stays valid here, since these examples run at `start_now`.
  def run_cancel(ctx)
    Workflows::Wf005::Handlers::CancelCrawl.new.call(
      command: Workflows::Wf005::Commands::CancelCrawl.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "cc-#{SecureRandom.hex(6)}", schema_version: "1.0",
        session_id: ctx[:g][:session_id], organization_id: ctx[:g][:organization_id],
        project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id],
        expected_state_version: crawl_row(ctx[:crawl_id])["state_version"].to_i, requested_at_utc: act_now
      ), request_context: act_ctx
    )
  end

  # Gate a handler at its FIRST statement — the `command_executions` INSERT — so it is suspended INSIDE
  # its transaction, past `lock_crawl`. Conditional on the command type so the operation running
  # underneath does not block on the same gate.
  def gate_command(command_type, key)
    conn = DbInspector.connection
    conn.exec(<<~SQL)
      CREATE OR REPLACE FUNCTION f1_test_gate_cmd() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.command_type = '#{command_type}' THEN
          PERFORM pg_advisory_xact_lock(#{key});
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER f1_test_gate_cmd BEFORE INSERT ON command_executions
        FOR EACH ROW EXECUTE FUNCTION f1_test_gate_cmd();
    SQL
    yield
  ensure
    conn.exec(<<~SQL)
      DROP TRIGGER IF EXISTS f1_test_gate_cmd ON command_executions;
      DROP FUNCTION IF EXISTS f1_test_gate_cmd();
    SQL
  end

  # :458'S "ONCE", AS A RACE RATHER THAN AS A SEQUENCE (B10).
  #
  # ADR-101 and ADR-102 both rest their central claim on `CrawlStartStore#lock_crawl`'s `FOR UPDATE`,
  # and deleting it left 218 examples green: PROOF 64 and PROOF 82 are sequential, and PROOF 65 mutates
  # the row before it acts. The failure mode if the lock is ever lost is the exact class ADR-103 was
  # written to repair — both terminal handlers raise `Platform::InvariantViolation` on a lost
  # compare-and-set, so the loser of a genuine race would surface an invariant failure instead of
  # :458's ratified `crawl_already_terminal`, and timing would once again decide which.
  describe ":458's \"once\" under a real race (B10)" do
    # `interleave` is unusable here for the same reason it was in PROOF 91: it runs `while_committing`
    # TO COMPLETION while the gated operation is held, and the gated operation holds the crawls row —
    # so the committing one blocks on it and the harness deadlocks against its own gate. The primitives
    # express it directly: gate the WINNER inside its transaction, start the LOSER, observe the loser
    # contending for the row (an ungranted `transactionid` lock, not an advisory key), then release.
    def race_on_the_crawl_row(winner, loser, key)
      controller = RaceHarness.open_connection
      controller.exec_params("SELECT pg_advisory_lock($1)", [key])
      w = RaceHarness.spawn_operation(winner)
      RaceHarness.wait_until("the winner blocked inside its transaction") { RaceHarness.blocked_on(key) >= 1 }
      l = RaceHarness.spawn_operation(loser)
      RaceHarness.wait_until("the loser blocked behind the winner") do
        RaceHarness.blocked_behind(key) >= 1
      end
      controller.exec_params("SELECT pg_advisory_unlock($1)", [key])
      [w.value, l.value]
    ensure
      controller.exec_params("SELECT pg_advisory_unlock_all()")
      controller.close
    end

    it "PROOF 100 — a cancellation losing to a checkpoint reports the ratified refusal, not an exception" do
      ctx = fetchable
      drain_one_pass(ctx)
      checkpoint_action = due_now_checkpoint(ctx)
      key = RaceHarness.key_for("f1-test-checkpoint-first")

      _won, cancelled = gate_command("wf005.complete_crawl", key) do
        race_on_the_crawl_row(-> { run_checkpoint(ctx, checkpoint_action) }, -> { run_cancel(ctx) }, key)
      end

      expect(cancelled).to be_a(Platform::CommandResult),
                           "the loser raised instead of returning: #{cancelled.inspect}"
      expect(cancelled.success?).to be(false)
      expect(cancelled.failure.reason_code).to eq("crawl_already_terminal")
      expect(crawl_row(ctx[:crawl_id])["state"]).to eq("completed")
    end

    it "PROOF 101 — a checkpoint losing to a cancellation reports the same refusal, not an exception" do
      ctx = fetchable
      drain_one_pass(ctx)
      checkpoint_action = due_now_checkpoint(ctx)
      key = RaceHarness.key_for("f1-test-cancel-first")

      _won, checkpointed = gate_command("wf005.cancel_crawl", key) do
        race_on_the_crawl_row(-> { run_cancel(ctx) }, -> { run_checkpoint(ctx, checkpoint_action) }, key)
      end

      expect(checkpointed).to be_a(Platform::CommandResult),
                              "the loser raised instead of returning: #{checkpointed.inspect}"
      expect(checkpointed.success?).to be(false)
      expect(checkpointed.failure.reason_code).to eq("crawl_already_terminal")
      expect(crawl_row(ctx[:crawl_id])["state"]).to eq("canceled")
    end
  end

  # One pass, so the run has a retired entry and a Document to be counted.
  def drain_one_pass(ctx)
    action = first_fetch_action(ctx)
    run_pass(ctx, action)
  end

  # SCOPE, STATED SO IT CANNOT BE READ WIDER THAN IT IS (round 2, ADR-112 observation 2). This gates
  # the outcome INSERT, so the pass it races is ALREADY INSIDE `retire` holding the frontier lock. It
  # proves the sub-window ADR-105 closed and nothing more; the general property — that a checkpoint
  # cannot contradict a pass in its FETCH — is PROOF 110's, and ADR-105 claimed it without proving it.
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

  # THE WINDOW ROUND 1 AND ROUND 2 BOTH USED, AND THE ONE ADR-105 DID NOT CLOSE (FU-34; ADR-113).
  #
  # PROOF 91 above gates the outcome INSERT, so the pass it races is already inside `retire` holding
  # the frontier lock. A pass in its FETCH holds NOTHING: `fetch_and_settle` performs the network call
  # outside every transaction — correctly, per MTX-030 — and only afterwards opens `retire`'s. That is
  # the window round 1 reproduced at natural timing 10/10 ("a 150 ms fetch with the checkpoint fired
  # 50 ms in") and round 2 reproduced 3/3 against the repaired candidate, as
  #
  #     crawls    state=failed  completion_reason=failed  coverage_status=NULL   entitlement RELEASED
  #     outcomes  [document_created, covered, commit_order 1]
  #
  # permanently, because `f1_crawls_guard` refuses every UPDATE of a terminal row.
  #
  # NO TRIGGER GATES ANYTHING HERE. The F-01 façade stub simply does not return until the example lets
  # it, which is the natural window itself rather than a simulation of it, and nothing is ordered by a
  # sleep: the checkpoint is started only once the pass is OBSERVED inside the request.
  describe "the checkpoint racing a pass that is mid-REQUEST (FU-34)" do
    # Both halves of the race, run at the natural window: the pass suspended INSIDE its request, the
    # checkpoint run to completion underneath it, then the request released.
    def race_mid_request(ctx)
      started = Queue.new
      release = Queue.new
      pass = RaceHarness.spawn_operation(
        -> { run_pass_with(ctx, first_fetch_action(ctx), gated_page_outbound(started, release)) }
      )
      await(started, "the pass to enter its request")
      checkpoint = RaceHarness.spawn_operation(-> { run_checkpoint(ctx, due_now_checkpoint(ctx)) }).value
      release << :go
      [pass.value, checkpoint]
    end

    it "PROOF 110 — the run's terminal record and its committed facts cannot contradict each other" do
      ctx = fetchable
      pass_result, checkpoint_result = race_mid_request(ctx)

      expect(checkpoint_result).to be_a(Platform::CommandResult)
      expect(checkpoint_result.success?).to be(true)
      expect(pass_result).to be_a(Platform::CommandResult)

      crawl = crawl_row(ctx[:crawl_id])
      expect(crawl["state"]).to eq("failed")
      # THE ASSERTION THE REPAIR TURNS ON. Before it, this held one `document_created / covered` row —
      # a covered URL recorded against a run the same database says retrieved nothing.
      expect(outcomes(ctx[:crawl_id])).to be_empty

      # The pass reports the run that ended under it, and CREATES NOTHING: :442's "stop scheduling
      # affected work" and :458's "terminal selection occurs once" both forbid handing a finished run
      # more work, and a link here would also mint a second terminal checkpoint.
      expect(pass_result.payload[:pass_outcome]).to eq("halted")
      expect(pass_result.payload[:reason_code]).to eq("crawl_not_running")
      expect(pass_result.payload[:next_action_id]).to be_nil
      expect(pass_result.payload[:terminal_checkpoint_action_id]).to be_nil
      expect(pass_result.payload).not_to have_key("terminal_outcome")
    end

    it "PROOF 111 — entitlement, coverage, outcomes and attempts remain mutually consistent" do
      ctx = fetchable
      _pass, checkpoint_result = race_mid_request(ctx)

      crawl = crawl_row(ctx[:crawl_id])
      payload = checkpoint_result.payload

      # 1. The selection is RE-DERIVABLE from the facts that exist, not merely stored. `documents` is
      #    counted over `crawl_terminal_outcomes`, which is empty, so :453's "zero valid Documents"
      #    is what the record says and `failed` is what it implies.
      expect(outcomes(ctx[:crawl_id]).count { |o| o["outcome"] == "document_created" }).to eq(0)
      expect(payload[:documents]).to eq(0)
      derived = Workflows::Wf005::TerminalSelection.derive(
        Workflows::Wf005::TerminalSelection::Facts.new(
          documents: payload[:documents], roots_total: payload[:source_roots],
          roots_succeeded: payload[:source_roots_succeeded], fetch_failures: payload[:content_fetch_failures],
          unresolved_discovery: payload[:unresolved_discovery], hard_limits: payload[:hard_limit_decisions],
          uncovered: payload[:uncovered_candidates], unevaluated: payload[:unevaluated_candidates]
        )
      )
      expect([derived.state, derived.completion_reason, derived.coverage_status])
        .to eq([crawl["state"], crawl["completion_reason"], crawl["coverage_status"]])

      # 2. :551 — a run without the durable commit point RELEASES exactly once, and the ledger agrees
      #    with the state the run was recorded in.
      expect(payload[:entitlement_outcome]).to eq("released")
      expect(reservation(ctx[:crawl_id])["state"]).to eq("released")

      # 3. THE ATTEMPT ROW IS NOT SUPPRESSED, and that is deliberate. The request completed and its
      #    bytes left the platform; :442's "run-wide accounted bytes are EXACTLY sum(...)" has to stay
      #    reproducible. What :458 settles BY COMMIT ORDER is whether the run counted it, and it did
      #    not — so the attempt exists, carries no coverage-bearing consequence, and contradicts
      #    nothing the terminal record claims.
      attempt = DbInspector.one(<<~SQL, [ctx[:crawl_id]])
        SELECT * FROM fetch_attempts WHERE crawl_id = $1::uuid AND request_kind = 'content'
      SQL
      expect(attempt["http_status"].to_i).to eq(200)
      expect(attempt["outcome"]).to eq("document_created")

      # 4. The claimed entry stays `in_progress` on a run that is over: inert, unreachable, and the
      #    shape FU-22 already describes. What it is NOT is a coverage fact that outranks the record.
      entry = DbInspector.one("SELECT state FROM crawl_frontier_entries WHERE crawl_id=$1::uuid", [ctx[:crawl_id]])
      expect(entry["state"]).to eq("in_progress")
    end
  end

  # THE CANCELLATION COUNTERPART, WHICH THE REPAIR THAT CLOSED R3-6 DID NOT CARRY.
  #
  # ADR-113 justified `retire`'s plain SELECT of `crawls.state` by saying it reads "under the frontier
  # advisory lock it already takes, which is the same lock `Handlers::CompleteCrawl` takes first
  # (ADR-105) — so exactly one of the two transactions holds it". That argument named the CHECKPOINT and
  # covered only the checkpoint. `Handlers::CancelCrawl` took the `crawls` row lock alone, and the
  # outcome row's FK takes `FOR KEY SHARE`, which is compatible with the cancellation's `FOR NO KEY
  # UPDATE` — so the two never contended and a pass could commit `document_created / covered` onto a
  # Crawl the cancellation had already terminalized and whose entitlement it had already released.
  # R2-B1's shape with `canceled` in place of `failed`, and irreversible for the same reason.
  #
  # R3-6 made `CancelCrawl` take `lock_frontier` first. NOTHING ASSERTED THAT until these two examples:
  # the repair's own commit changed two spec files and both changes were a helper rename. A lock with no
  # proof it is load-bearing is precisely the defect class this tranche keeps finding (R3-5, FU-41), and
  # it is the one a fourth review round would find here.
  #
  # TWO WINDOWS, BECAUSE THE ORDER DECIDES WHICH FACT IS AT RISK.
  describe "cancellation versus an in-flight pass (R3-6)" do
    # WINDOW 1 — THE PASS IS INSIDE `retire`, PAST ITS RE-READ. This is the window the lock closes and
    # the only one that can distinguish its presence. The pass has already established the run is
    # `running` and is about to write its outcome; if the cancellation can commit through that window,
    # the outcome lands on a terminal, released run. Mirrors PROOF 91, which asserts exactly this
    # against the checkpoint.
    it "PROOF 117 — a cancellation cannot commit through a retirement that is already in flight" do
      ctx = fetchable
      fetch_action = first_fetch_action(ctx)
      gate_key = RaceHarness.key_for(RETIRE_GATE)
      frontier_key = RaceHarness.key_for("crawl-frontier:#{ctx[:crawl_id]}")

      controller = RaceHarness.open_connection
      pass_result = nil
      cancel_result = nil
      begin
        controller.exec_params("SELECT pg_advisory_lock($1)", [gate_key])

        gate_retire(gate_key) do
          pass = RaceHarness.spawn_operation(-> { run_pass(ctx, fetch_action) })
          # The pass holds the frontier lock, has terminalized the entry, and is suspended before its
          # outcome INSERT. Observed in `pg_locks`, never waited for.
          RaceHarness.wait_until("the pass blocked mid-retirement") { RaceHarness.blocked_on(gate_key) >= 1 }

          cancel = RaceHarness.spawn_operation(-> { run_cancel(ctx) })
          # THE ASSERTION THE REPAIR TURNS ON, and the one that dies when `lock_frontier` is deleted
          # from `CancelCrawl`: without it the cancellation sails past, commits `canceled` and RELEASES
          # the reservation while the retirement is suspended, and the retirement then commits its
          # Document onto it.
          RaceHarness.wait_until("the cancellation blocked on the frontier lock") do
            RaceHarness.blocked_on(frontier_key) >= 1
          end

          controller.exec_params("SELECT pg_advisory_unlock($1)", [gate_key])
          pass_result = pass.value
          cancel_result = cancel.value
        end
      ensure
        controller.exec_params("SELECT pg_advisory_unlock_all()")
        controller.close
      end

      # The retirement won the lock and its Document is committed.
      expect(pass_result).to be_a(Platform::CommandResult)
      expect(pass_result.payload[:pass_outcome]).to eq("fetched")
      expect(outcomes(ctx[:crawl_id]).sole["outcome"]).to eq("document_created")

      # The cancellation then ran against the run's committed state, not through it. It succeeds — the
      # run was still `running` when it finally got the lock — and the ORDER is what makes the pair
      # coherent: the Document was recorded while the run was live, and the cancellation followed it.
      expect(cancel_result).to be_a(Platform::CommandResult)
      expect(cancel_result.success?).to be(true)
      crawl = crawl_row(ctx[:crawl_id])
      expect(crawl["state"]).to eq("canceled")
      expect(crawl["completion_reason"]).to eq("canceled")
      # :551 — a cancellation releases, never commits, "even when intermediate Documents ... exist".
      expect(cancel_result.payload[:entitlement_outcome]).to eq("released")
      expect(reservation(ctx[:crawl_id])["state"]).to eq("released")
    end

    # WINDOW 2 — THE CANCELLATION COMMITS FIRST, WHILE THE PASS IS STILL IN ITS REQUEST. Here `retire`'s
    # re-read is the whole defence, and ADR-113 built that re-read but proved it against `CompleteCrawl`
    # ONLY. The acceptance review said so in as many words: the in-transaction half is "authoritative
    # against `CompleteCrawl` only". This is the same window PROOF 110 uses, pointed at the other
    # terminal command, and no trigger gates anything: the F-01 façade stub simply does not return
    # until the example lets it.
    it "PROOF 118 — a pass that was mid-request when a cancellation committed records nothing" do
      ctx = fetchable
      started = Queue.new
      release = Queue.new
      pass = RaceHarness.spawn_operation(
        -> { run_pass_with(ctx, first_fetch_action(ctx), gated_page_outbound(started, release)) }
      )
      await(started, "the pass to enter its request")
      cancel_result = RaceHarness.spawn_operation(-> { run_cancel(ctx) }).value
      release << :go
      pass_result = pass.value

      expect(cancel_result).to be_a(Platform::CommandResult)
      expect(cancel_result.success?).to be(true)

      crawl = crawl_row(ctx[:crawl_id])
      expect(crawl["state"]).to eq("canceled")
      expect(crawl["completion_reason"]).to eq("canceled")
      expect(reservation(ctx[:crawl_id])["state"]).to eq("released")

      # THE ASSERTION THE RE-READ TURNS ON. Without it this holds one `document_created / covered` row:
      # a covered URL, and a customer's Document, recorded against a run the same database says was
      # cancelled and never charged for.
      expect(outcomes(ctx[:crawl_id])).to be_empty

      # The pass reports the run that ended under it and creates nothing — no link, no checkpoint. A
      # cancelled run may not be handed more work any more than a completed one may.
      expect(pass_result).to be_a(Platform::CommandResult)
      expect(pass_result.payload[:pass_outcome]).to eq("halted")
      expect(pass_result.payload[:reason_code]).to eq("crawl_not_running")
      expect(pass_result.payload[:next_action_id]).to be_nil
      expect(pass_result.payload[:terminal_checkpoint_action_id]).to be_nil
      expect(pass_result.payload).not_to have_key("terminal_outcome")
    end
  end
end
