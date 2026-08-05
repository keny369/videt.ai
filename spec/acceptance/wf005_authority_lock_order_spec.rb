# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# ONE LOCK ORDER FOR THE TWO AUTHORITY ROWS, ACROSS EVERY WORKFLOW THAT TOUCHES BOTH
# (round-15 concurrency finding R15-CONC-1).
#
# WHAT FU-48 ADDED, AND WHAT IT COST. Before D7 each protected WF-005 write locked ONE row: the
# Organization's, for the epoch. FU-48 added a second locked relation — the granting Role Assignments,
# under `FOR SHARE OF ra` — and the statement takes them in the order its conjuncts are written:
# `organizations` first, then `role_assignments`.
#
# THE THREE WF-013 HANDLERS THAT REMOVE OR CHANGE AN ACTIVE GRANT WROTE THEM THE OTHER WAY ROUND —
# `role_assignments` first, then the epoch advance on `organizations` — in one transaction, with an
# ordinary inter-statement gap between the two. That is a cycle, and PostgreSQL resolves a cycle by
# aborting one side with SQLSTATE 40P01. Nothing on either path rescues it:
#
#   * when the customer's command is the victim, `QueueCrawl` / `CancelCrawl` / `ActivateCrawlPolicy`
#     raises `PG::TRDeadlockDetected` out of `#call` instead of returning the `Platform::CommandResult`
#     ADR-103 exists to guarantee;
#   * when the revocation is the victim, `RevokeRoleAssignment` raises, the grant stays `active` and
#     the epoch is not advanced — a security-critical revocation that did not land.
#
# WHICH SIDE DIES IS THE DEADLOCK DETECTOR'S CHOICE, i.e. arrival order. `start_crawl.rb` already
# records this exact failure mode as a blocker, in the abstract, for a different pair of rows.
#
# THE REPAIR IS ONE GLOBAL ORDER: `organizations` BEFORE `role_assignments`, everywhere. The WF-005
# side already had it and cannot easily be reordered (both locks are taken inside one statement), so
# the three WF-013 handlers advance the epoch FIRST. Both writes stay in the same transaction, both
# keep their guards and both still raise `LostRace` on zero rows, so no product semantics change: what
# changes is which of the two rows this transaction holds first.
#
# HOW THESE PROOFS AVOID ASSERTING THE ORDER THEY ARE TESTING. A probe that hard-codes "epoch first"
# would pass whatever the handlers do. So PROOF 262 READS THE ORDER OUT OF THE RUNNING HANDLER — the
# real command, observed at the connection — and PROOF 263 replays THAT observed order against a real
# WF-005 protected write driven into a genuine mid-flight block. Reverse the handler and the observed
# order reverses with it, and PROOF 263's control shows that the reversed order really does deadlock,
# so a green result is never the absence of a cycle-capable interleaving.
RSpec.describe "WF-005/WF-013 authority lock order", type: :acceptance,
                                                     acceptance_ids: ["AC-WF-005", "AC-CAP-007"],
                                                     test_types: %w[TYP-INT TYP-SEC] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  LOCK_TIMEOUT = "2000ms"
  # `RevokeRoleAssignment` requires a free-text reason of at least 20 characters.
  REVOCATION_REASON = "the round-15 lock-order proof revokes this grant deliberately"

  def tagged_connection(name)
    conn = RaceHarness.open_connection
    conn.exec("SET application_name = '#{name}'")
    conn
  end

  def pid_of(conn) = conn.exec("SELECT pg_backend_pid()").getvalue(0, 0).to_i

  def blocked_behind?(pid)
    DbInspector.one(<<~SQL, [pid])["n"].to_i.positive?
      SELECT count(*) AS n FROM pg_stat_activity WHERE $1::int = ANY (pg_blocking_pids(pid))
    SQL
  end

  def active_grant(org)
    DbInspector.one(<<~SQL, [org])
      SELECT id, state_version, account_id FROM role_assignments
      WHERE organization_id = $1::uuid AND status = 'active' ORDER BY id LIMIT 1
    SQL
  end

  def epoch_of(org)
    DbInspector.one("SELECT authorization_epoch FROM organizations WHERE id = $1::uuid",
                    [org])["authorization_epoch"].to_i
  end

  def queueable_org
    g = bootstrap
    sid = register_source(g, "https://lockorder.acme.example")
    verify(g, sid)
    activate_source(g, sid)
    raise "activation failed" unless activate_project(g).success?

    g
  end

  def queue(g)
    Workflows::Wf005::Handlers::QueueCrawl.new.call(
      command: Workflows::Wf005::Commands::QueueCrawl.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "lo-#{SecureRandom.hex(6)}",
        schema_version: "1.0", session_id: g[:session_id], organization_id: g[:organization_id],
        project_id: g[:project_id], requested_at_utc: act_now
      ), request_context: act_ctx
    )
  end

  # The two production statements a revocation issues, driven in a CHOSEN order on one connection so
  # the interleaving is deterministic. They are the real store methods, not transcriptions.
  def revocation_steps(conn, org, grant)
    store = IdentityAccess::Infrastructure::RoleAssignmentStore.new(conn)
    epoch = epoch_of(org)
    {
      organizations: -> { store.advance_authorization_epoch(org, epoch, act_now) },
      role_assignments: lambda {
        store.revoke(grant["id"], grant["state_version"].to_i, act_now, REVOCATION_REASON, epoch + 1)
      }
    }
  end

  # Drive the WF-005 command into a genuine mid-flight block against a revocation that has already
  # taken its first row lock, then let the revocation take its second. Returns both outcomes.
  #
  # Nothing is ordered by `Kernel.sleep`: the command is released onto its advisory key only once the
  # revoker holds its first row, and the revoker's second statement is issued only once PostgreSQL
  # reports the command's backend as blocked behind the revoker's.
  def interleave(g, order)
    org = g[:organization_id]
    grant = active_grant(org)
    gate_key = RaceHarness.key_for("crawl-queue:#{org}:#{g[:project_id]}")
    gate = tagged_connection("lock_order_gate")
    revoker = tagged_connection("lock_order_revoker")
    steps = revocation_steps(revoker, org, grant)
    command = nil
    revocation = nil

    begin
      gate.exec_params("SELECT pg_advisory_lock($1)", [gate_key])
      op = RaceHarness.spawn_operation(-> { queue(g) })
      RaceHarness.wait_until("the command blocked on crawl-queue:#{org}:#{g[:project_id]}") do
        RaceHarness.blocked_on(gate_key) >= 1
      end

      revoker.exec("BEGIN")
      revoker.exec("SET lock_timeout = '#{LOCK_TIMEOUT}'")
      steps.fetch(order.first).call

      gate.exec_params("SELECT pg_advisory_unlock_all()")
      RaceHarness.wait_until("the command reached its protected write and blocked behind the revoker") do
        blocked_behind?(pid_of(revoker))
      end

      revocation = begin
        steps.fetch(order.last).call
        revoker.exec("COMMIT")
        :committed
      rescue PG::Error => e
        begin
          revoker.exec("ROLLBACK")
        rescue PG::Error
          nil
        end
        e
      end
      command = op.value
    ensure
      begin
        gate.exec_params("SELECT pg_advisory_unlock_all()")
      rescue PG::Error
        nil
      end
      [gate, revoker].each(&:close)
    end

    { command:, revocation: }
  end

  def deadlock?(value) = value.is_a?(PG::TRDeadlockDetected)

  # A second, non-protected grant for the same Account, so a revocation can be driven without meeting
  # the last-administrator invariant — which is a different rule and not what these proofs are about.
  def revocable_grant(g)
    account = DbInspector.one("SELECT account_id FROM sessions WHERE id = $1::uuid",
                              [g[:session_id]])["account_id"]
    result = Workflows::Wf013::Handlers::RequestRoleAssignment.new.call(
      command: Workflows::Wf013::Commands::RequestRoleAssignment.new(
        command_id: SecureRandom.uuid_v7, idempotency_key: "lo-req-#{SecureRandom.hex(6)}",
        schema_version: "1.0", session_id: g[:session_id], account_id: account,
        canonical_role: "MarketingOperator", permission_mode: "standard", persona: nil,
        scope_sha256: Digest::SHA256.digest("scope:organization"), expires_at: nil,
        expected_authorization_epoch: epoch_of(g[:organization_id]), reason: nil,
        requested_at_utc: act_now
      ), request_context: act_ctx
    )
    raise "grant request failed: #{result.reason_code}" unless result.success?

    DbInspector.one(<<~SQL, [g[:organization_id]])
      SELECT id, state_version FROM role_assignments
      WHERE organization_id = $1::uuid AND canonical_role = 'MarketingOperator' AND status = 'active'
    SQL
  end

  # THE ORDER PRODUCTION ACTUALLY TAKES THE TWO ROWS IN, MEASURED INSIDE THE HANDLER'S OWN
  # TRANSACTION BY POSTGRESQL.
  #
  # WHY NOT INSTRUMENT THE CONNECTION. The first version of this proof prepended a module to
  # `PG::Connection#exec_params` to record statement order. It worked, and it BLINDED
  # `GovernedWriteSentinel`: that instrument locates the frame owning a write by walking the stack
  # against a depth bound, and one extra frame per call pushed every owning frame out of its window —
  # seven of its proofs went from green to empty. A proof that silently disables another proof is
  # worse than no proof, so nothing here touches the execution path.
  #
  # WHY NOT A CONCURRENT PROBE EITHER. A second connection can only observe the order by catching the
  # handler mid-transaction, which makes the measurement depend on catching it — and a proof whose
  # verdict depends on an interleaving it does not control is the defect class D10 was.
  #
  # WHAT IS MEASURED INSTEAD. A trigger on `role_assignments`, firing INSIDE the handler's own
  # transaction, asks PostgreSQL whether this backend ALREADY holds a write lock on `organizations`.
  # A transaction that has updated `organizations` holds `RowExclusiveLock` on that relation for the
  # rest of its life, so the answer is exact, single-connection and deterministic: it is true when the
  # epoch advance came first and false when it did not.
  def measure_first_lock
    DbInspector.connection.exec(<<~SQL)
      CREATE UNLOGGED TABLE IF NOT EXISTS f1_test_lock_order (org_already_locked boolean NOT NULL);
      TRUNCATE f1_test_lock_order;
      -- the handler writes as the runtime role, which owns nothing; this scratch table lives and
      -- dies inside this example
      GRANT INSERT ON f1_test_lock_order TO PUBLIC;
      CREATE OR REPLACE FUNCTION f1_test_lock_order_probe() RETURNS trigger
      LANGUAGE plpgsql AS $fn$
      BEGIN
        INSERT INTO f1_test_lock_order (org_already_locked)
        SELECT EXISTS (
          SELECT 1 FROM pg_locks
          WHERE pid = pg_backend_pid() AND relation = 'organizations'::regclass
            AND mode = 'RowExclusiveLock' AND granted
        );
        RETURN NEW;
      END
      $fn$;
      CREATE TRIGGER f1_test_lock_order_probe BEFORE UPDATE ON role_assignments
      FOR EACH ROW EXECUTE FUNCTION f1_test_lock_order_probe();
    SQL
    yield
    rows = DbInspector.all("SELECT org_already_locked FROM f1_test_lock_order")
    raise "the trigger never fired: the handler wrote no role_assignments row" if rows.empty?

    Platform::PgBool.true?(rows.first["org_already_locked"]) ? :organizations : :role_assignments
  ensure
    DbInspector.connection.exec(<<~SQL)
      DROP TRIGGER IF EXISTS f1_test_lock_order_probe ON role_assignments;
      DROP FUNCTION IF EXISTS f1_test_lock_order_probe();
      DROP TABLE IF EXISTS f1_test_lock_order;
    SQL
  end

  def production_first_lock(g)
    grant = revocable_grant(g)
    measure_first_lock do
      result = Workflows::Wf013::Handlers::RevokeRoleAssignment.new.call(
        command: Workflows::Wf013::Commands::RevokeRoleAssignment.new(
          command_id: SecureRandom.uuid_v7, idempotency_key: "lo-rv-#{SecureRandom.hex(6)}",
          schema_version: "1.0", session_id: g[:session_id],
          role_assignment_id: grant["id"], expected_state_version: grant["state_version"].to_i,
          expected_authorization_epoch: epoch_of(g[:organization_id]),
          reason: REVOCATION_REASON, requested_at_utc: act_now
        ), request_context: act_ctx
      )
      raise "revocation failed: #{result.reason_code}" unless result.success?
    end
  end

  def production_write_order(g)
    first = production_first_lock(g)
    first == :organizations ? %i[organizations role_assignments] : %i[role_assignments organizations]
  end

  describe "PROOF 262 — the order is read out of the running handler, not written down here" do
    it "RevokeRoleAssignment takes the Organization row before the grant row" do
      first = production_first_lock(bootstrap)

      expect(first).to eq(:organizations),
                       "the handler took #{first} first; every WF-005 protected write locks " \
                       "organizations before role_assignments, so this order closes a cycle"
    end
  end

  describe "PROOF 263 — with that order there is no cycle, and the reverse order proves there could be" do
    it "the observed order lets both sides finish, and the command is refused rather than crashing" do
      # THE ORDER IS THE HANDLER'S, TAKEN FRESH. If a future change puts the grant write first, this
      # example replays THAT and deadlocks, which is the binding PROOF 262 alone cannot provide.
      # ONE Organization for both halves: `identity` is memoized per example, so a second bootstrap
      # in the same example would collide on the principal.
      g = queueable_org
      order = production_write_order(g)

      outcome = interleave(g, order)

      expect(deadlock?(outcome[:command])).to be(false),
                                              "the customer's command died with 40P01: #{outcome[:command].inspect}"
      expect(deadlock?(outcome[:revocation])).to be(false),
                                                 "the revocation died with 40P01: #{outcome[:revocation].inspect}"
      expect(outcome[:revocation]).to eq(:committed)
      expect(outcome[:command]).to be_a(Platform::CommandResult)
      expect(outcome[:command].success?).to be(false)
      expect(outcome[:command].reason_code).to eq("crawl_trigger_unauthorized")
      expect(DbInspector.all("SELECT id FROM crawls WHERE organization_id = $1::uuid",
                             [g[:organization_id]])).to be_empty
    end

    it "PROOF 263b — the SAME interleaving with the two writes reversed deadlocks, so the pass is not vacuous" do
      # THE CONTROL. Without this, a green PROOF 263 would be indistinguishable from an interleaving
      # that never had a cycle available to it. This is the pre-repair order, driven identically.
      g = queueable_org

      outcome = interleave(g, %i[role_assignments organizations])

      expect(deadlock?(outcome[:command]) || deadlock?(outcome[:revocation])).to be(true),
                                                                                "the reversed order did not " \
                                                                                "deadlock, so PROOF 263 proves " \
                                                                                "nothing about lock order: " \
                                                                                "#{outcome.inspect}"
    end
  end

  describe "PROOF 264 — the WF-005 side's half of the order, measured" do
    it "a protected write blocked on role_assignments is already holding the organizations row" do
      # THE PREMISE THE GLOBAL ORDER RESTS ON. The two locks are taken inside ONE statement, so the
      # order is a property of the statement rather than of Ruby. It is measured here — while the
      # command is blocked on the grant row, a third connection cannot take the Organization row —
      # rather than read off the plan.
      g = queueable_org
      org = g[:organization_id]
      grant = active_grant(org)
      gate_key = RaceHarness.key_for("crawl-queue:#{org}:#{g[:project_id]}")
      gate = tagged_connection("lock_order_gate2")
      holder = tagged_connection("lock_order_holder")
      prober = tagged_connection("lock_order_prober")
      held = nil

      begin
        gate.exec_params("SELECT pg_advisory_lock($1)", [gate_key])
        op = RaceHarness.spawn_operation(-> { queue(g) })
        RaceHarness.wait_until("the command blocked on its queue key") { RaceHarness.blocked_on(gate_key) >= 1 }

        # Hold the grant row so the command's statement must stop at its SECOND lock.
        holder.exec("BEGIN")
        holder.exec_params("SELECT 1 FROM role_assignments WHERE id = $1::uuid FOR UPDATE", [grant["id"]])

        gate.exec_params("SELECT pg_advisory_unlock_all()")
        RaceHarness.wait_until("the command blocked behind the grant-row holder") { blocked_behind?(pid_of(holder)) }

        prober.exec("SET lock_timeout = '#{LOCK_TIMEOUT}'")
        held = begin
          prober.exec("BEGIN")
          prober.exec_params("SELECT 1 FROM organizations WHERE id = $1::uuid FOR NO KEY UPDATE", [org])
          prober.exec("COMMIT")
          false
        rescue PG::LockNotAvailable, PG::QueryCanceled
          prober.exec("ROLLBACK")
          true
        end

        holder.exec("ROLLBACK")
        op.value
      ensure
        begin
          gate.exec_params("SELECT pg_advisory_unlock_all()")
        rescue PG::Error
          nil
        end
        [gate, holder, prober].each(&:close)
      end

      expect(held).to be(true),
                      "the command was blocked on role_assignments without holding organizations, so the " \
                      "two halves of the global lock order do not meet and the WF-013 order cannot be " \
                      "derived from this one"
    end
  end
end
