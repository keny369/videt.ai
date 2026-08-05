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
      LANGUAGE plpgsql SET search_path TO 'pg_catalog', 'public' AS $fn$
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
    conn.exec("SET lock_timeout = '2000ms'")
    ["DROP TRIGGER IF EXISTS f1_test_lock_order_probe ON role_assignments",
     "DROP FUNCTION IF EXISTS f1_test_lock_order_probe()",
     "DROP TABLE IF EXISTS f1_test_lock_order"].each do |statement|
      conn.exec(statement)
    rescue PG::Error => e
      warn "lock-order probe cleanup could not run `#{statement}`: #{e.message}"
      LockOrderProbeResidue.record(statement)
    end
  ensure
    begin
      conn&.exec("SET lock_timeout = 0")
    rescue PG::Error
      nil
    end
  end

  # A leak is a property of the RUN, so it is judged once at the end of it rather than by whichever
  # example happened to be contended.
  module LockOrderProbeResidue
    class << self
      def statements = (@statements ||= [])
      def record(statement) = statements << statement

      def assert_none!
        return if statements.empty?

        raise "the lock-order probe could not remove #{statements.length} object(s) from the database " \
              "and they are still installed on a production authority table: #{statements.uniq.join('; ')}"
      end
    end
  end



end

RSpec.configure { |config| config.after(:suite) { LockOrderProbe::LockOrderProbeResidue.assert_none! } }
