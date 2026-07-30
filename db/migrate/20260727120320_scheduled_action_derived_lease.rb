# frozen_string_literal: true

# BACKGROUND_PROCESSING.md :288's LEASE DURATION RULE, which was ratified and never built.
#
#   "Lease duration is `max(30 seconds, product_attempt_deadline - claim_time + 30 seconds)` capped at
#    15 minutes."
#
# THE DEFECT IT CLOSES, which was demonstrated rather than theorised. `WORKER_LEASE_SECONDS` was a flat 30,
# and F-01 bounds ONE redirect hop at the resolver timeout (15 s, taken outside the per-hop deadline) plus
# the request timeout (15 s) — so a single ratified hop is up to 30 seconds, equal to the whole lease and
# three times the heartbeat interval. One 30.5-second request lapsed the lease under a LIVE worker with no
# heartbeat written and a valid `robots.txt` discarded; because the pass then correctly relinquishes, every
# redelivery repeated it, so such a host could never be resolved inside the run's wall clock.
#
# THE INVARIANT that must hold is `lease > interval + max_hop`, where `interval = clamp(lease/3, 5, 30)` and
# the ratified `max_hop` is 30. A flat 30 fails it. The derived lease satisfies it with room: a
# `crawl_fetch_due` bound to a 60-minute run deadline takes the 15-minute cap, whose interval clamps to 30,
# so the worst gap is 60 seconds against a 900-second lease.
#
# WHY THE PRODUCER STAMPS IT AND TRANSPORT ONLY READS IT. `scheduled_actions` is a transport table served by
# one scheduler across every tenant; it must not interpret product state, and having the claim function reach
# into `crawls` to find a deadline would couple F-04 to WF-005 and to every future work type. The producer
# already knows the deadline of the attempt it is scheduling, so it writes a plain timestamp and transport
# does arithmetic on it. NULL means "no product deadline", which yields the caller's floor and is exactly
# today's behaviour — so every action kind that does not stamp it is unchanged.
#
# The column is IMMUTABLE after creation, like `due_at` and `not_before_at`: a lease that could be widened
# after the fact by rewriting the deadline would be a way for a worker to extend its own ownership, which is
# the whole thing the fence exists to prevent.
class ScheduledActionDerivedLease < ActiveRecord::Migration[8.1]
  # :288, exactly: the floor, the +30s grace and the cap.
  FLOOR = "interval '30 seconds'"
  GRACE = "interval '30 seconds'"
  CAP = "interval '15 minutes'"

  # :288's arithmetic, INLINED rather than extracted into a helper function, and deliberately.
  #
  # A helper would have been the obvious "one place", but it must take the deadline and the claim instant
  # as ARGUMENTS — and `spec/platform/scheduled_actions/store_spec.rb` fails any `%scheduled_action%`
  # function that accepts a `timestamptz`, because :114 makes PostgreSQL transaction time the sole due-time
  # and lease authority and a function that accepts an instant is a way for a caller to lie about time.
  # That gate is right and it caught this. Inlining keeps every input inside the transport function that
  # already owns `v_now`, and adds no new grantable surface to a table whose entire posture is that only
  # `f1_platform_worker` may transition it. Both call sites are still written from THIS one string.
  FLOOR_ARG = "make_interval(secs => greatest(p_lease_seconds, 1))"
  LEASE_INTERVAL = <<~SQL.strip
    least(
        greatest(#{FLOOR_ARG}, #{FLOOR},
                 CASE WHEN a.product_attempt_deadline IS NULL THEN #{FLOOR}
                      ELSE (a.product_attempt_deadline - v_now) + #{GRACE} END),
        greatest(#{CAP}, #{FLOOR_ARG}))
  SQL

  def up
    add_column :scheduled_actions, :product_attempt_deadline, :timestamptz, precision: 6, null: true

    # Both lease-setting transport functions now derive from the row rather than from the argument alone.
    # The argument survives as the caller's FLOOR, so no existing caller loses a lease it asked for.
    replace_claim_due
    replace_dispatch
    guard_deadline_immutable

    F1::RuntimeGrants.apply_all(connection)
  end

  def down
    remove_column :scheduled_actions, :product_attempt_deadline
    raise ActiveRecord::IrreversibleMigration,
          "f1_claim_due_scheduled_actions / f1_dispatch_scheduled_action / f1_scheduled_actions_guard " \
          "must be restored from the prior migration"
  end

  private

  def replace_claim_due
    body = function_body("f1_claim_due_scheduled_actions")
    execute rewrite_lease(body)
  end

  def replace_dispatch
    body = function_body("f1_dispatch_scheduled_action")
    execute rewrite_lease(body)
  end

  # Read the live definition and rewrite ONLY the lease expression, so nothing else about these functions
  # can drift here by accident.
  def function_body(name)
    definition = connection.select_value(<<~SQL)
      SELECT pg_get_functiondef(p.oid)
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = '#{name}'
    SQL
    raise "#{name} not found" if definition.nil?

    definition
  end

  def rewrite_lease(definition)
    target = "lease_expires_at = v_now + make_interval(secs => greatest(p_lease_seconds, 1))"
    replacement = "lease_expires_at = v_now + #{LEASE_INTERVAL}"
    raise "lease expression not found; the transport function has changed shape" unless definition.include?(target)

    definition.sub("CREATE OR REPLACE FUNCTION", "CREATE FUNCTION")
              .sub("CREATE FUNCTION", "CREATE OR REPLACE FUNCTION")
              .sub(target, replacement)
  end

  def guard_deadline_immutable
    definition = function_body("f1_scheduled_actions_guard")
    anchor = "     OR NEW.not_before_at IS DISTINCT FROM OLD.not_before_at\n"
    raise "guard anchor not found" unless definition.include?(anchor)

    execute definition.sub("CREATE FUNCTION", "CREATE OR REPLACE FUNCTION")
                      .sub(anchor, "#{anchor}     OR NEW.product_attempt_deadline " \
                                   "IS DISTINCT FROM OLD.product_attempt_deadline\n")
  end
end
