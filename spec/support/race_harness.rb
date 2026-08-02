# frozen_string_literal: true

require "pg"

# Deterministic concurrency, built on the locks the production commands already
# take rather than on timing.
#
# The problem with `Thread.new { a }; Thread.new { b }` is that it proves
# nothing: the operations may run one after the other and the test still passes.
# A race is only a race if BOTH operations are demonstrably in flight against the
# contested state before either outcome is released.
#
# This harness gets that from PostgreSQL itself. Every authority-changing WF-013
# command takes `pg_advisory_xact_lock` on `organization:<id>` and, where it
# transitions one record, on `role_assignment:<id>` or `invitation:<id>`. So the
# harness holds that exact advisory lock from a controller connection first. Each
# racing operation then opens its own transaction, reaches its lock statement,
# and BLOCKS there — inside its transaction, having already resolved its actor,
# its authority and its expected versions, and unable to commit. The controller
# waits until every operation is *observably* blocked, by reading `pg_locks` for
# ungranted advisory waiters, and only then releases the gate.
#
# There is no `sleep` used to order anything. `wait_until` polls a database
# predicate and raises if it never becomes true; the release happens because the
# blocked state was OBSERVED, not because time passed. If the predicate were
# never satisfied the test fails loudly instead of silently degrading into a
# sequential run.
#
# Two shapes:
#
#   contend   every operation is gated; they are released together and fight for
#             the same contested state. Exactly one may win.
#   interleave  the gated operations are held mid-transaction while a different
#             operation runs to completion and COMMITS underneath them. This is
#             how "authority became invalid before the authorization transaction
#             completed" is expressed without a production test hook.
module RaceHarness
  module_function

  TIMEOUT_SECONDS = 15.0
  POLL_SECONDS = 0.002

  # The same key the production stores derive: hashtextextended(name, 0).
  def key_for(name)
    observer.exec_params("SELECT hashtextextended($1, 0)", [name]).getvalue(0, 0).to_i
  end

  def organization_key(id) = key_for("organization:#{id}")
  def role_assignment_key(id) = key_for("role_assignment:#{id}")
  def invitation_key(id) = key_for("invitation:#{id}")

  # Hold `key`, release every gated operation only once ALL of them are blocked
  # on it, and return their results in order.
  def contend(key, *operations)
    interleave(key, gated: operations).first
  end

  # Hold `key`; start `gated`; wait until all of them are blocked on it; run
  # `while_committing` to completion (it commits underneath them); release.
  # Returns [gated_results, committed_result].
  #
  # The gate is released and every thread joined even when the wait fails, so a
  # broken example never leaves a transaction open to deadlock the next one's
  # truncation.
  def interleave(key, gated:, while_committing: nil)
    controller = open_connection
    controller.exec_params("SELECT pg_advisory_lock($1)", [key])
    threads = gated.map { |op| spawn_operation(op) }
    committed = nil
    failure = nil

    begin
      wait_until("#{gated.size} operation(s) blocked on advisory lock #{key}") do
        blocked_on(key) >= gated.size
      end
      committed = while_committing&.call
    rescue StandardError => e
      failure = e
    ensure
      controller.exec_params("SELECT pg_advisory_unlock($1)", [key])
      controller.close
    end

    results = threads.map(&:value)
    raise failure if failure

    [results, committed]
  end

  # Ungranted advisory waiters on `key` in this database. A bigint advisory key
  # is stored split across classid (high 32 bits) and objid (low 32 bits).
  def blocked_on(key)
    sql = <<~SQL
      SELECT count(*) FROM pg_locks
      WHERE locktype = 'advisory' AND NOT granted
        AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
        AND classid = ((($1::bigint >> 32) & 4294967295))::oid
        AND objid = (($1::bigint & 4294967295))::oid
    SQL
    observer.exec_params(sql, [key]).getvalue(0, 0).to_i
  end

  # Ungranted ROW waiters that are blocked BY A BACKEND WAITING ON `key`.
  #
  # A `SELECT ... FOR UPDATE` waiter registers as an ungranted `transactionid` or `tuple` lock on the
  # holder's transaction, never as an ungranted lock on the relation, so `blocked_on` cannot express it.
  # The obvious substitute — `count(*) FROM pg_locks WHERE NOT granted AND locktype IN (...)` — is what
  # two specs used, and it is CLUSTER-WIDE: `pg_locks` spans every database, and `transactionid` rows
  # carry `database = NULL`, so no column on `pg_locks` alone can narrow it. Round 3 measured the
  # consequence: with ONE unrelated waiter in a DIFFERENT database, deleting the `FOR UPDATE` that
  # ADR-105 rests on left PROOF 101 passing 10/10, and deleting ADR-106's `lock_reservation` left
  # PROOF 92 passing 10/10. Both proofs became unfalsifiable exactly when the cluster was busy, which is
  # its normal condition — three review suites shared this cluster the day it was found.
  #
  # Filtering to `current_database()` is necessary and NOT sufficient: two suites in the same database
  # would still satisfy each other's predicate. So this asserts the actual causal edge the specs mean —
  # the waiter is blocked by a backend that is itself queued on the controller's gate — which no
  # unrelated transaction anywhere can satisfy.
  # Waiters blocked BY A BACKEND THAT IS ITSELF QUEUED ON `key` — whatever object they are queued on.
  #
  # Deliberately not restricted by lock type. Which object two transactions collide on is a property of
  # the implementation under test, not of the race: when `CancelCrawl` began taking the frontier
  # advisory lock before the `crawls` row (R3-6), cancel-versus-checkpoint stopped colliding on the row
  # and started colliding on the advisory lock. A predicate naming `transactionid`/`tuple` silently
  # stopped observing the very race it was written for, and would have to be edited again the next time
  # a lock moved. The causal edge is what the specs actually mean, and it does not move.
  #
  # The `gated` CTE is the set of backends WAITING on `key` (ungranted). The controller HOLDS `key`
  # granted, so it is correctly excluded — otherwise every waiter in the database would match.
  def blocked_behind(key)
    sql = <<~SQL
      WITH gated AS (
        SELECT pid FROM pg_locks
        WHERE locktype = 'advisory' AND NOT granted
          AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
          AND classid = ((($1::bigint >> 32) & 4294967295))::oid
          AND objid = (($1::bigint & 4294967295))::oid
      )
      SELECT count(*) FROM pg_locks l
      JOIN pg_stat_activity a ON a.pid = l.pid
      WHERE NOT l.granted
        AND a.datname = current_database()
        AND EXISTS (SELECT 1 FROM gated g WHERE g.pid = ANY(pg_blocking_pids(l.pid)))
    SQL
    observer.exec_params(sql, [key]).getvalue(0, 0).to_i
  end

  # A connection of the harness's own. The racing operations read committed
  # state through DbInspector, so polling on that shared connection would
  # interleave two conversations on one socket.
  def observer
    @observer ||= open_connection
  end

  # Poll a database predicate to a hard deadline. Not an ordering sleep: nothing
  # is released until the predicate is true, and a predicate that never becomes
  # true fails the example rather than degrading it into a sequential run.
  def wait_until(description)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT_SECONDS
    until yield
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        raise "race harness timed out waiting for: #{description}"
      end

      Kernel.sleep(POLL_SECONDS)
    end
    true
  end

  # Each operation gets its own pooled connection, so the transactions are
  # genuinely independent rather than nested in one.
  def spawn_operation(operation)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection { operation.call }
    rescue StandardError => e
      e
    end
  end

  def open_connection
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    PG.connect(host: cfg[:host], port: cfg[:port], dbname: cfg[:database], user: DbInspector.superuser)
  end
end
