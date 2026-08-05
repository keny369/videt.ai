# frozen_string_literal: true

# THE LOCK-ORDER PROBE, IN ITS OWN FILE SO IT CAN BE MUTATED (round-17).
#
# It lived inside `spec/acceptance/wf005_authority_lock_order_spec.rb`, which is also the proof that
# reads it — so the mutation that blinds it changed its own proof's bytes, and `verify_bindings!`
# correctly refused the ledger: "the proof that failed is not the proof that exists". An instrument
# that cannot be mutated cannot be shown able to fail, which is the whole point of PROOF 262d.
module LockOrderProbe
  module_function

  #
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
  # transaction, asks PostgreSQL whether this transaction has ALREADY WRITTEN AN `organizations` ROW.
  #
  # IT ASKS ABOUT THE ROW, NOT THE RELATION (round-17 concurrency observation O-1). The first version
  # asked whether the backend held `RowExclusiveLock` on `organizations`. The forward implication is
  # true and the CONVERSE — which is what the proof depends on — is false: ANY data-modifying
  # statement against the relation takes that lock, including one that matches no row. Measured, a
  # handler that ran `UPDATE organizations … AND false` and THEN wrote the grant row first reported
  # "organizations first" and every example stayed green with the cycle live. `o.xmin =
  # pg_current_xact_id()` is true only of a row THIS transaction actually wrote, so the zero-row
  # statement cannot buy it. Single-connection and deterministic either way.
  def measure_first_lock
    # THE SETUP IS DELIBERATELY UNBOUNDED, AND THAT IS RECORDED RATHER THAN FIXED (round-18 finding
    # A18-3). Its idempotent `DROP TRIGGER IF EXISTS` needs ACCESS EXCLUSIVE once the trigger exists,
    # so against an open reader it waits — measured at 43.6s. Bounding it with a `lock_timeout` was
    # tried and made things WORSE: the bounded acquisition turned the wait into a genuine deadlock
    # against this file's own concurrency probes, failing seven examples instead of one. A wait that
    # resolves is better than a cycle that aborts, so the bound stays off and the exposure is written
    # down: under heavy contention this setup can stall for the connection's `statement_timeout`.
    DbInspector.connection.exec(<<~SQL)
      -- IDEMPOTENT SETUP. A contended cleanup can leave the trigger installed (`DROP TRIGGER` needs
      -- ACCESS EXCLUSIVE and one ordinary reader defeats it), and a bare CREATE would then fail every
      -- later example with `already exists` — turning one contended run into a cascade. The residue
      -- is still reported at suite end; it just cannot break the next measurement.
      DROP TRIGGER IF EXISTS f1_test_lock_order_probe ON role_assignments;
      CREATE UNLOGGED TABLE IF NOT EXISTS f1_test_lock_order (org_already_locked boolean NOT NULL);
      TRUNCATE f1_test_lock_order;
      -- the handler writes as the runtime role, which owns nothing; this scratch table lives and
      -- dies inside this example
      GRANT INSERT ON f1_test_lock_order TO PUBLIC;
      CREATE OR REPLACE FUNCTION f1_test_lock_order_probe() RETURNS trigger
      LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'public' AS $fn$
      BEGIN
        INSERT INTO f1_test_lock_order (org_already_locked)
        SELECT EXISTS (
          SELECT 1 FROM organizations o
          WHERE o.xmin = pg_current_xact_id()::text::xid
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
    drop_probe!
  end

  # THE CLEANUP CANNOT LEAK SILENTLY, AND ROUND 16's REPAIR DID NOT ACHIEVE THAT (round-17 schema
  # finding S-R17-1).
  #
  # Round 16 split one multi-statement `exec` into three under a short `lock_timeout`, on the theory
  # that a later statement failing would no longer roll back the earlier drops. The measurement it did
  # not make: `DROP TRIGGER` is the FIRST statement AND the one needing the strongest lock
  # (ACCESS EXCLUSIVE). One ordinary open reader of `role_assignments` — a plain `SELECT count(*)` in
  # an open transaction — makes it time out, and the leak set is identical to before, byte for byte.
  # Splitting a batch cannot help when statement one is the contended one.
  #
  # SO THIS DOES THREE THINGS INSTEAD. It never raises, because a `raise` in an `ensure` REPLACES the
  # example's real failure (S-R17-5) and skips the `lock_timeout` reset (S-R17-2) — the round-16
  # repair introduced both. It always restores `lock_timeout`, which lives on the process-wide
  # inspector connection. And what it cannot drop is recorded, so `assert_no_probe_residue!` fails the
  # run at suite end rather than leaving committed DDL on a production authority table for the drift
  # gate to find much later.
  def drop_probe!
    conn = DbInspector.connection
    begin
      conn.exec("SET lock_timeout = '2000ms'")
    rescue PG::Error => e
      warn "lock-order probe cleanup could not set lock_timeout: #{e.message}"
    end

    # THE TRIGGER GOES FIRST AND THE TABLE ONLY IF IT WENT (round-18 finding S-R18-1). Round 17
    # removed the `raise` and kept the order, so a contended `DROP TRIGGER` was SKIPPED while the
    # uncontended `DROP TABLE` ran — leaving a `BEFORE UPDATE` trigger on `role_assignments` whose
    # body inserts into a table that no longer exists, and every later grant write failing with
    # `relation "f1_test_lock_order" does not exist`. Round 16's ordering comment claimed the trigger
    # "can never outlive its table"; with the raise gone it guaranteed the opposite.
    dropped_trigger = try_drop("DROP TRIGGER IF EXISTS f1_test_lock_order_probe ON role_assignments")
    if dropped_trigger
      try_drop("DROP FUNCTION IF EXISTS f1_test_lock_order_probe()")
      try_drop("DROP TABLE IF EXISTS f1_test_lock_order")
    end
  ensure
    begin
      DbInspector.connection.exec("SET lock_timeout = 0")
    rescue PG::Error
      nil
    end
  end

  def try_drop(statement)
    DbInspector.connection.exec(statement)
    true
  rescue PG::Error => e
    warn "lock-order probe cleanup could not run `#{statement}`: #{e.message}"
    false
  end

  # A leak is a property of the RUN, so it is judged once at the end of it rather than by whichever
  # example happened to be contended.
  # A LEAK IS A PROPERTY OF THE DATABASE, SO IT IS READ FROM THE CATALOGUE (round-18 findings
  # S-R18-2 and S-R18-4). The first version remembered which statements had failed, which was wrong in
  # both directions: it accused a clean run when a later example's setup had already dropped the
  # object, and it stayed silent when the failure happened before any statement was recorded — a
  # `SET lock_timeout` outside the rescue took the whole cleanup with it, leaked all three objects,
  # and the suite-end check passed. Asking the catalogue cannot do either.
  module LockOrderProbeResidue
    class << self
      def survivors
        DbInspector.all(<<~SQL).map { |r| r["object"] }
          SELECT 'trigger f1_test_lock_order_probe on role_assignments' AS object
          WHERE EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'f1_test_lock_order_probe')
          UNION ALL
          SELECT 'function f1_test_lock_order_probe()'
          WHERE EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'f1_test_lock_order_probe')
          UNION ALL
          SELECT 'table f1_test_lock_order'
          WHERE EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'f1_test_lock_order')
        SQL
      end

      def assert_none!
        left = survivors
        return if left.empty?

        raise "the lock-order probe left #{left.length} object(s) installed on a production authority " \
              "table: #{left.join('; ')}"
      end
    end
  end
end

RSpec.configure { |config| config.after(:suite) { LockOrderProbe::LockOrderProbeResidue.assert_none! } }
