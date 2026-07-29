# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# WF-005 admission (S-07-008; WORKFLOW_SPECIFICATIONS.md :442/:456).
#
# :456 — "Selection under every finite bound is DETERMINISTIC" and "All run-wide byte, page, and
# queue admission accounting is also applied in dequeue sequence."
#
# S-07-007 enforced the SUM and not the ORDER: it claimed the frontier entry in one transaction and
# reserved bytes in another, so two workers claiming adjacent entries could reserve in either order
# and which URL received the last of the run's budget depended on thread scheduling. The ADR-026
# contract lens demonstrated a different pair winning on each run. These assert the repair.
RSpec.describe "WF-005 admission", type: :acceptance,
               acceptance_ids: ["AC-CAP-007", "AC-WF-005"], test_types: %w[TYP-E2E TYP-DATA] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  def admission = Workflows::Wf005::Admission.new

  def claim(ctx) = admission.claim_next(organization_id: ctx[:g][:organization_id],
                                        crawl_id: ctx[:crawl_id], now: start_now)

  def counters(cid) = DbInspector.one("SELECT * FROM crawl_budget_counters WHERE crawl_id=$1::uuid", [cid])

  # Observed, not timed: the rival commits because admission was SEEN waiting on the counter row.
  def blocked_on_counter?
    DbInspector.one(
      "SELECT 1 AS waiting FROM pg_stat_activity
       WHERE wait_event_type = 'Lock' AND query ILIKE '%crawl_budget_counters%'
         AND query ILIKE '%reserved_response_bytes%' LIMIT 1", []) ? true : false
  end

  def sleep_until(description, seconds: 15.0)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
    until yield
      raise "timed out waiting for: #{description}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      Kernel.sleep(0.005)
    end
  end

  # Seed extra queued entries at the same depth so several are admissible at once.
  def seed_entries(ctx, count)
    root = DbInspector.one("SELECT * FROM crawl_frontier_entries WHERE crawl_id=$1::uuid", [ctx[:crawl_id]])
    (1..count).each do |i|
      url = format("https://shop.acme.example/p%02d", i)
      DbInspector.connection.exec_params(
        "INSERT INTO crawl_frontier_entries
           (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id,
            crawl_id, source_id, canonical_url, canonical_url_preimage, canonical_url_sha256, collision_ordinal,
            origin, depth, discovering_document_url, link_position, dequeue_key, state,
            scope_policy_id, scope_policy_version, enqueue_order, canonicalization_version)
         SELECT gen_random_uuid(), 0, now(), now(), gen_random_uuid(), e.organization_id,
                e.project_id, e.crawl_id, e.source_id, $2, convert_to($2,'UTF8'),
                sha256(convert_to($2,'UTF8')), 0, 'link', e.depth, '', 0,
                -- A key that sorts by the index, so dequeue order is known independently of the
                -- production encoder.
                ('\\x00' || lpad(to_hex($3::int), 8, '0'))::bytea,
                'queued', e.scope_policy_id, e.scope_policy_version, $3, e.canonicalization_version
         FROM crawl_frontier_entries e WHERE e.id = $1::uuid",
        [root["id"], url, i])
    end
  end



  def set_remaining(ctx, bytes)
    Platform::UnitOfWork.run do |conn|
      store = IdentityAccess::Infrastructure::CrawlBudgetStore.new(conn.raw_connection)
      store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
      store.ensure_counters(id: Platform::Ids.system.generate, now: start_now,
                            correlation_id: SecureRandom.uuid_v7,
                            organization_id: ctx[:g][:organization_id],
                            project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id])
    end
    DbInspector.connection.exec_params(
      "UPDATE crawl_budget_counters
       SET reserved_response_bytes = $2, committed_response_bytes = $2, state_version = state_version + 1
       WHERE crawl_id = $1::uuid",
      [ctx[:crawl_id], Workflows::Wf005::ByteAccounting::RUN_CEILING - bytes])
  end

  describe "claiming and reserving are one decision" do
    it "admits the entry and its reservation together" do
      ctx = running_crawl
      decision = claim(ctx)

      expect(decision.admitted?).to be(true)
      expect(decision.entry["state"]).to eq("in_progress")
      expect(decision.reserved_bytes).to eq(Workflows::Wf005::ByteAccounting::PER_URL_CEILING)
      # The reservation is visible the moment the entry is claimed — not one transaction later,
      # where another worker could have taken the budget in between.
      expect(counters(ctx[:crawl_id])["reserved_response_bytes"].to_i).to eq(decision.reserved_bytes)
    end

    it "carries the :456 ordering tuple, so accounting can be replayed in dequeue order" do
      ctx = running_crawl
      expect(claim(ctx).entry["dequeue_key"]).not_to be_nil
    end

    it "returns IDLE when the frontier is empty, without touching the budget" do
      ctx = running_crawl
      claim(ctx)                       # take the only root entry
      decision = claim(ctx)

      expect(decision.idle?).to be(true)
      expect(decision.admitted?).to be(false)
      expect(counters(ctx[:crawl_id])["reserved_response_bytes"].to_i)
        .to eq(Workflows::Wf005::ByteAccounting::PER_URL_CEILING)
    end
  end

  describe "the run-wide byte bound (:442)" do
    it "reserves only what REMAINS when the run is nearly spent" do
      ctx = running_crawl
      set_remaining(ctx, 4096)
      expect(claim(ctx).reserved_bytes).to eq(4096)
    end

    it "refuses admission when the budget is spent, and says WHY" do
      ctx = running_crawl
      set_remaining(ctx, 0)
      decision = claim(ctx)

      expect(decision.admitted?).to be(false)
      expect(decision.limited?).to be(true)
      expect(decision.reason_code).to eq("run_byte_budget_exhausted")
      # The entry is NOT claimed. `in_progress` has no way back under the frontier guard, so an
      # entry claimed and then refused its bytes would be stranded — and `sealed_depth`'s MIN over
      # the non-terminal states would pin the run's breadth-first frontier at that depth forever.
      # Admission peeks, pays, then claims.
      expect(decision.entry).to be_nil
      expect(DbInspector.all("SELECT state FROM crawl_frontier_entries WHERE crawl_id=$1::uuid",
                             [ctx[:crawl_id]]).map { |r| r["state"] }).to all(eq("queued"))
      # :452 keeps a candidate discarded by a Crawl limit in the coverage denominator. The record of
      # that discard is the DECISION ROW, which S-07-009's terminal checkpoint reads — not a
      # frontier state the run cannot leave.
      expect(DbInspector.one(
        "SELECT threshold_kind FROM crawl_limit_decisions
         WHERE crawl_id=$1::uuid AND limit_dimension='accounted_response_body_bytes_per_run'",
        [ctx[:crawl_id]])["threshold_kind"]).to eq("hard")
    end

    it "never lets concurrent admissions sum above the run-wide maximum" do
      # The property :442 states directly: "concurrent reservations MUST NOT sum above the run-wide
      # maximum". The previous version of this test was VACUOUS, as the ADR-026 concurrency lens
      # showed: `running_crawl` seeds ONE root entry, so its three sequential `claim` calls returned
      # idle twice, and deleting the bound predicate from `reserve_bytes` left it green. It was the
      # only test named for this clause.
      #
      # This one seeds enough entries that every claimer has work, gives the run room for exactly
      # two reservations, and races four workers.
      #
      # HONEST LIMIT: `Admission` holds the frontier advisory lock across every statement here, so
      # the four SERIALISE and the counter's own `reserved + want <= ceiling` predicate is never
      # exercised — deleting it leaves this green. What this proves is that ADMISSION's own sizing
      # is exact under the lock. The predicate itself is proved by the test below, whose rival does
      # not hold that lock.
      ctx = running_crawl
      seed_entries(ctx, 6)
      set_remaining(ctx, Workflows::Wf005::ByteAccounting::PER_URL_CEILING * 2)

      granted = 4.times.map { Thread.new { claim(ctx) } }.map(&:value).select(&:admitted?)

      expect(granted.size).to eq(2)
      expect(granted.sum(&:reserved_bytes)).to eq(Workflows::Wf005::ByteAccounting::PER_URL_CEILING * 2)
      expect(counters(ctx[:crawl_id])["reserved_response_bytes"].to_i)
        .to eq(Workflows::Wf005::ByteAccounting::RUN_CEILING)
    end

    it "does not call a LOST RACE a limit — the counter has writers the frontier lock does not cover" do
      # `pg_advisory_xact_lock("crawl-frontier:<id>")` serialises ADMISSIONS; it does not serialise
      # `FetchContent`'s reserve/commit/release, none of which take it. The old code treated a failed
      # compare-and-update as proof the run was exhausted and wrote an irrevocable `CrawlLimitReached`
      # carrying the STALE pre-race figure — for a run whose budget the very next release handed back.
      #
      # DETERMINISTIC WITHOUT ANY PRODUCTION SEAM. A rival holds an UNCOMMITTED reservation on the
      # counter row through the production store. Admission's plain `SELECT` reads the pre-race
      # value (READ COMMITTED gives no dirty read, so it sees the stale figure), its `UPDATE` then
      # BLOCKS on the rival's row lock, and on the rival's COMMIT PostgreSQL re-evaluates the
      # predicate against the new tuple (EvalPlanQual) and matches nothing. That is exactly the lost
      # compare-and-update, ordered by the lock rather than by hope. An earlier version of this test
      # needed a `pacer:` probe point on the production constructor; this needs none, and uses the
      # same EPQ mechanism the store already documents.
      ctx = running_crawl
      seed_entries(ctx, 2)
      set_remaining(ctx, Workflows::Wf005::ByteAccounting::PER_URL_CEILING * 2)

      cfg = ActiveRecord::Base.connection_db_config.configuration_hash
      rival = PG.connect(host: cfg[:host], port: cfg[:port], dbname: cfg[:database],
                         user: cfg[:username], password: cfg[:password].presence)
      begin
        rival.exec("BEGIN")
        store = IdentityAccess::Infrastructure::CrawlBudgetStore.new(rival)
        store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
        # A bare row lock, NOT an UPDATE. An UPDATE would create a new tuple version whose
        # uncommitted index entry blocks admission at `ensure_counters` — which is BEFORE its read,
        # so it would then read the fresh value and the test would prove nothing about the window.
        rival.exec_params("SELECT 1 FROM crawl_budget_counters WHERE crawl_id = $1::uuid FOR UPDATE",
                          [ctx[:crawl_id]])

        # Admission now reads the STALE value (READ COMMITTED, non-locking SELECT) and blocks on its
        # own UPDATE — exactly the read-to-write window the defect lived in.
        worker = Thread.new { claim(ctx) }
        sleep_until("admission is blocked on the counter row") { blocked_on_counter? }

        # The rival takes the last of the budget and commits underneath it.
        expect(store.reserve_bytes(ctx[:g][:organization_id], ctx[:crawl_id],
                                   Workflows::Wf005::ByteAccounting::PER_URL_CEILING * 2,
                                   Workflows::Wf005::ByteAccounting::RUN_CEILING, start_now)).not_to be_nil
        rival.exec("COMMIT")
        decision = worker.value
      ensure
        rival.close
      end

      expect(decision.admitted?).to be(false)
      row = DbInspector.one(
        "SELECT observed_value FROM crawl_limit_decisions
         WHERE crawl_id=$1::uuid AND limit_dimension='accounted_response_body_bytes_per_run'
           AND threshold_kind='hard'", [ctx[:crawl_id]])
      # Admission re-read, found the budget genuinely spent, and recorded THAT figure — the one a
      # statement actually enforced against. The stale figure was RUN_CEILING - 2*PER_URL.
      expect(row).not_to be_nil
      expect(row["observed_value"].to_i).to eq(Workflows::Wf005::ByteAccounting::RUN_CEILING)
      expect(decision.reason_code).to eq("run_byte_budget_exhausted")

      # AND :442's own sentence: "concurrent reservations MUST NOT sum above the run-wide maximum."
      # The rival never takes the frontier lock, so nothing but `reserved + want <= ceiling` in the
      # statement's own WHERE stops admission adding its reservation on top. Mutation-proved.
      expect(counters(ctx[:crawl_id])["reserved_response_bytes"].to_i)
        .to eq(Workflows::Wf005::ByteAccounting::RUN_CEILING)
    end
  end

  describe "the run-wide byte bound is EXACT at its boundary" do
    # `reserved + want <= ceiling` is the whole bound, and every existing test approaches it from far
    # away — a run that wants twice the per-URL ceiling against a run ceiling orders of magnitude
    # larger. Nothing sat ON the boundary, so `<= $4 + 1` passed the suite. An off-by-one in the
    # loosening direction is the one direction a byte bound must never drift: it is the difference
    # between a ceiling and a suggestion.
    it "grants exactly the ceiling and refuses one byte more" do
      ctx = running_crawl
      ceiling = Workflows::Wf005::ByteAccounting::PER_URL_CEILING * 4

      Platform::UnitOfWork.run do |conn|
        store = IdentityAccess::Infrastructure::CrawlBudgetStore.new(conn.raw_connection)
        store.enter_org_context(org: ctx[:g][:organization_id], correlation_id: SecureRandom.uuid_v7)
        store.ensure_counters(id: Platform::Ids.system.generate, now: start_now,
                              correlation_id: SecureRandom.uuid_v7,
                              organization_id: ctx[:g][:organization_id],
                              project_id: ctx[:g][:project_id], crawl_id: ctx[:crawl_id])

        args = [ctx[:g][:organization_id], ctx[:crawl_id]]
        # One byte over, from empty. Refused.
        expect(store.reserve_bytes(*args, ceiling + 1, ceiling, start_now)).to be_nil
        # Exactly the ceiling, from empty. Granted, and it takes the whole budget.
        expect(store.reserve_bytes(*args, ceiling, ceiling, start_now)
                    &.fetch("reserved_response_bytes").to_i).to eq(ceiling)
        # And now nothing at all is left — not even one byte.
        expect(store.reserve_bytes(*args, 1, ceiling, start_now)).to be_nil
        # And a zero-byte reservation is refused before the predicate is ever reached: an attempt
        # that reserves nothing cannot honour ":442 — an attempt cannot add accounted bytes beyond
        # its reservation", so it is a caller defect rather than a free pass at the boundary.
        expect(store.reserve_bytes(*args, 0, ceiling, start_now)).to be_nil
      end
    end
  end

  describe "execution-time authorization, before any effect" do
    # Admission reserves budget, claims an entry and can write an IMMUTABLE customer-visible
    # decision. Checking only "does the Crawl exist" let a suspended tenant or an unmetered run get
    # all three.
    #
    # THREE of the four limbs delete their guard line to prove the test is load-bearing. The fourth,
    # the Project limb, is unreachable at HEAD and says so below rather than claiming coverage it
    # does not have — the claim that every limb was mutation-proved was false and is withdrawn.
    def effects(ctx)
      { decisions: DbInspector.all("SELECT id FROM crawl_limit_decisions WHERE crawl_id=$1::uuid", [ctx[:crawl_id]]).size,
        events: DbInspector.all("SELECT id FROM event_registry WHERE aggregate_id=$1::uuid AND event_type LIKE 'Crawl%Limit%'", [ctx[:crawl_id]]).size,
        reserved: counters(ctx[:crawl_id])&.fetch("reserved_response_bytes").to_i,
        claimed: DbInspector.all("SELECT id FROM crawl_frontier_entries WHERE crawl_id=$1::uuid AND state='in_progress'", [ctx[:crawl_id]]).size }
    end

    it "refuses a SUSPENDED Organization without reserving, claiming or recording anything" do
      ctx = running_crawl
      suspend_organization(ctx[:g])

      decision = claim(ctx)

      expect(decision.reason_code).to eq("admission_organization_inactive")
      expect(effects(ctx)).to eq({ decisions: 0, events: 0, reserved: 0, claimed: 0 })
    end

    it "refuses a Crawl that is not running, and emits no wall-clock limit for it" do
      # A Crawl that has not started has no `deadline_at`; a terminal one's is in the past. Either
      # way the wall-clock limb must never fire for a run the scheduler may not advance. Exercised
      # through the real chain by queueing WITHOUT starting — the `crawls` guard rightly refuses to
      # let a test fabricate a terminal state, so the pre-start state is the honest one to use.
      g = bootstrap
      sid = register_source(g, "https://shop.acme.example")
      verify(g, sid)
      activate_source(g, sid)
      activate_project(g)
      crawl_id = Workflows::Wf005::Handlers::QueueCrawl.new.call(
        command: Workflows::Wf005::Commands::QueueCrawl.new(
          command_id: SecureRandom.uuid_v7, idempotency_key: "qc-#{SecureRandom.hex(6)}",
          schema_version: "1.0", session_id: g[:session_id], organization_id: g[:organization_id],
          project_id: g[:project_id], requested_at_utc: act_now), request_context: act_ctx).payload[:crawl_id]
      ctx = { g:, crawl_id:, source_id: sid, host: "shop.acme.example" }

      decision = claim(ctx)

      expect(decision.reason_code).to eq("admission_crawl_not_running")
      expect(effects(ctx)).to eq({ decisions: 0, events: 0, reserved: 0, claimed: 0 })
    end

    it "cannot yet be exercised for an inactive Project — and that is asserted, not assumed" do
      # THREE lenses across two passes found the Project limb untested while this block's comment
      # claimed every limb was mutation-proved. The honest reason is that the limb is UNREACHABLE at
      # HEAD: `f1_projects_guard` admits exactly one state transition, `draft -> active`, so a
      # Project that has started a Crawl can never become inactive. There is no legitimate way to
      # reach the branch, and fabricating one with a double would assert the double.
      #
      # So this asserts the unreachability instead. When the Project lifecycle lands its
      # `active -> paused|archived` edges, this example fails — which is the signal to replace it
      # with the real denial test.
      ctx = running_crawl
      %w[paused archived draft].each do |state|
        expect do
          DbInspector.connection.exec_params(
            "UPDATE projects SET state=$2, state_version=state_version+1 WHERE id=$1::uuid",
            [ctx[:g][:project_id], state])
        end.to raise_error(PG::RaiseException, /project_lifecycle_transition_unavailable/)
      end
    end

    it "refuses a run whose entitlement reservation is no longer executing (PRULE-007)" do
      ctx = running_crawl
      DbInspector.connection.exec_params(
        "UPDATE entitlement_reservations SET state='released', terminal_at=now(),
           state_version=state_version+1
         WHERE id=(SELECT entitlement_reservation_id FROM crawls WHERE id=$1::uuid)", [ctx[:crawl_id]])

      expect(claim(ctx).reason_code).to eq("admission_entitlement_not_executing")
      expect(effects(ctx)).to eq({ decisions: 0, events: 0, reserved: 0, claimed: 0 })
    end
  end

  describe "admission order IS dequeue order (:456)" do

    it "admits in increasing dequeue key when several workers claim CONCURRENTLY" do
      # :456 — "Selection under every finite bound is deterministic." Claiming and reserving were
      # separate transactions, so which entry got the budget depended on scheduling. The frontier
      # advisory lock now spans both, so concurrent claimers serialise into dequeue order.
      ctx = running_crawl
      seed_entries(ctx, 6)

      all_keys = DbInspector.all(
        "SELECT dequeue_key FROM crawl_frontier_entries WHERE crawl_id=$1::uuid ORDER BY dequeue_key",
        [ctx[:crawl_id]]).map { |r| r["dequeue_key"] }

      admitted = 4.times.map { Thread.new { claim(ctx) } }.map(&:value).select(&:admitted?)
      keys = admitted.map { |d| d.entry["dequeue_key"] }

      # The property is WHICH ENTRIES were admitted, not which thread got which. `map(&:value)`
      # returns in thread-creation order, so asserting the returned sequence is sorted would be
      # asserting the scheduler, not the specification. What :456 requires is that the admitted SET
      # is the lowest-ordered prefix of the frontier — no worker may skip ahead of a lower key.
      expect(keys.size).to eq(4)
      expect(keys.uniq.size).to eq(4)
      expect(keys.sort).to eq(all_keys.first(4))
    end

    it "takes the FRONTIER LOCK across the reservation, so admission cannot interleave" do
      # Asserted directly rather than by racing: a race that only sometimes interleaves is a test
      # that only sometimes fails. Holding the same advisory key from another connection must BLOCK
      # admission — that is what makes the reservation happen in dequeue order, because the lock
      # already serialises the dequeue.
      ctx = running_crawl
      holder = DbInspector.connection
      holder.exec_params("SELECT pg_advisory_lock(hashtextextended($1, 0))",
                         ["crawl-frontier:#{ctx[:crawl_id]}"])

      begin
        done = false
        worker = Thread.new { d = claim(ctx); done = true; d }
        worker.join(1.5)
        expect(done).to be(false), "admission proceeded without the frontier lock"
      ensure
        holder.exec_params("SELECT pg_advisory_unlock(hashtextextended($1, 0))",
                           ["crawl-frontier:#{ctx[:crawl_id]}"])
      end

      expect(worker.value).to be_a(Workflows::Wf005::Admission::Decision)
      expect(done).to be(true)
    end

    it "gives the LAST of the budget to the lowest key, not to the fastest worker" do
      # The determinism that matters: at the boundary, which URL is admitted must be decided by the
      # ratified tuple. With one reservation's worth of budget left and several workers racing, the
      # winner must be the lowest-ordered entry every time.
      ctx = running_crawl
      seed_entries(ctx, 5)
      set_remaining(ctx, Workflows::Wf005::ByteAccounting::PER_URL_CEILING)

      results = 4.times.map { Thread.new { claim(ctx) } }.map(&:value)
      winners = results.select(&:admitted?)
      expect(winners.size).to eq(1)

      lowest = DbInspector.all(
        "SELECT dequeue_key FROM crawl_frontier_entries WHERE crawl_id=$1::uuid ORDER BY dequeue_key LIMIT 1",
        [ctx[:crawl_id]]).first["dequeue_key"]
      expect(winners.first.entry["dequeue_key"]).to eq(lowest)
      expect(results.count(&:limited?)).to be >= 1
    end
  end

  describe "the wall clock (:442 — 'At 60 elapsed minutes, no new request starts')" do
    it "refuses admission once the run's deadline has passed" do
      ctx = running_crawl
      DbInspector.connection.exec_params(
        "UPDATE crawls SET deadline_at = $2::timestamptz, state_version = state_version + 1
         WHERE id = $1::uuid", [ctx[:crawl_id], start_now - 1])

      decision = claim(ctx)
      expect(decision.limited?).to be(true)
      expect(decision.reason_code).to eq("wall_clock_exhausted")
      # Checked BEFORE the claim: an expired run does not take work out of the frontier only to
      # refuse it, which would leave the entry `in_progress` with nobody fetching it.
      expect(decision.entry).to be_nil
      expect(DbInspector.all("SELECT state FROM crawl_frontier_entries WHERE crawl_id=$1::uuid",
                             [ctx[:crawl_id]]).map { |r| r["state"] }).to all(eq("queued"))
    end

    it "admits while the deadline is still ahead" do
      ctx = running_crawl
      DbInspector.connection.exec_params(
        "UPDATE crawls SET deadline_at = $2::timestamptz, state_version = state_version + 1
         WHERE id = $1::uuid", [ctx[:crawl_id], start_now + 600])
      expect(claim(ctx).admitted?).to be(true)
    end
  end
end
