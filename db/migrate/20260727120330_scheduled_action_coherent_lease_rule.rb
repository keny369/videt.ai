# frozen_string_literal: true

# THE LEASE RULE MADE COHERENT ACROSS ALL THREE WRITERS (owner ruling 2026-07-30; DECISIONS ADR-095).
#
# `20260727120320` implemented BACKGROUND_PROCESSING.md :288's derived lease in TWO of the THREE functions
# that assign `lease_expires_at`. The third, `f1_heartbeat_scheduled_action`, kept
# `v_now + make_interval(secs => greatest(p_lease_seconds, 1))` — and the live worker passes
# `Worker::WORKER_LEASE_SECONDS` = 30 to it. So a `crawl_fetch_due` dispatched with a 900-second derived
# lease had it REWRITTEN TO 30 SECONDS at the first renewal boundary, which `Lease.owned?` reaches after
# ten seconds of handler time. From that instant the system was byte-for-byte in the state FU-25 was raised
# to repair. The record said the defect was closed; it was not, on the only production path.
#
# THREE CORRECTIONS ARE TAKEN TOGETHER, because each of the other two would otherwise be left standing as a
# knowingly false invariant.
#
# 1. THE HEARTBEAT DERIVES. Same expression, same inputs, same authority: `transaction_timestamp()`, the
#    stored immutable `product_attempt_deadline`, the floor and the cap. No signature change, no
#    worker-side reconstruction of the lease, no caller-supplied instant. Note there is deliberately NO
#    monotonic `greatest(a.lease_expires_at, ...)` guard: the derived value SHRINKS as `v_now` approaches
#    the deadline, and that is the point — ownership is valid for exactly as long as legitimate work can
#    exist, no longer. A monotonic guard would let ownership outlive the deadline it is derived from.
#
# 2. THE CAP IS ABSOLUTE. It was written `greatest(interval '15 minutes', <caller floor>)`, which is not a
#    cap at all above 900 seconds: a caller passing 3600 received 3600. Measured. Both call sites pass a
#    literal 30, so it was sound only by accident of today's values, while ADR-094 and FU-25 both described
#    an unconditional cap. The outer operation is now `least(..., interval '15 minutes')` and no input can
#    escape it.
#
# 3. THE FLOOR IS 60 SECONDS, NOT 30. :288's own floor was internally inconsistent with :288's own cadence
#    and F-01's ratified maximum hop. The invariant a lease must satisfy is
#
#      lease > interval + max_hop,  interval = clamp(floor(lease/3), 5, 30),  max_hop = 30
#
#    where `max_hop` is `Ceilings::DNS_TIMEOUT_MAX_S` (15, taken OUTSIDE the per-hop deadline) plus the
#    ratified hard request timeout (15). At a 30-second lease that reads `30 > 10 + 30`, which is FALSE —
#    so the ratified floor could not survive one ratified hop. It is reachable, not theoretical: the
#    derived lease falls to the floor near the run deadline and for every action kind that stamps no
#    deadline at all. At 60 it reads `60 > 20 + 30`, which is true. The owner's ruling corrects the
#    defective constant in :288 rather than preserving a proof that is mathematically false.
#
# WHY THE CALLER ARGUMENT SURVIVES AT ALL. It is the caller's FLOOR, so no existing caller loses a lease it
# asked for; it can no longer raise the ceiling. Both production callers pass 30, which the 60-second floor
# now dominates, so the argument is inert today and retained only so the contract does not silently narrow.
class ScheduledActionCoherentLeaseRule < ActiveRecord::Migration[8.1]
  # :288 as corrected by ADR-095: the floor, the +30s grace and the ABSOLUTE cap.
  FLOOR = "interval '60 seconds'"
  GRACE = "interval '30 seconds'"
  CAP = "interval '15 minutes'"
  CALLER_FLOOR = "make_interval(secs => greatest(p_lease_seconds, 1))"

  # THE ONE CANONICAL EXPRESSION. All three functions are written from this single string, so the three
  # spellings cannot drift — which is exactly how the heartbeat came to disagree with the other two.
  # Inlined rather than extracted into a helper function, and deliberately: `spec/platform/scheduled_actions/
  # store_spec.rb` fails any `%scheduled_action%` function that accepts a `timestamptz`, because :114 makes
  # PostgreSQL transaction time the sole lease authority and a function taking an instant is a way for a
  # caller to lie about time. That gate was right when it caught the first attempt and it is still right.
  LEASE_INTERVAL = <<~SQL.strip
    least(
        greatest(#{CALLER_FLOOR}, #{FLOOR},
                 CASE WHEN a.product_attempt_deadline IS NULL THEN #{FLOOR}
                      ELSE (a.product_attempt_deadline - v_now) + #{GRACE} END),
        #{CAP})
  SQL

  # What `20260727120320` left behind in the claim and dispatch functions: the derived expression with the
  # 30-second floor and the escapable cap. Byte-identical in both, so one target serves both.
  SUPERSEDED_DERIVED = <<~SQL.strip
    least(
        greatest(make_interval(secs => greatest(p_lease_seconds, 1)), interval '30 seconds',
                 CASE WHEN a.product_attempt_deadline IS NULL THEN interval '30 seconds'
                      ELSE (a.product_attempt_deadline - v_now) + interval '30 seconds' END),
        greatest(interval '15 minutes', make_interval(secs => greatest(p_lease_seconds, 1))))
  SQL

  # What the heartbeat still carried: the flat caller value, with no reference to the product deadline.
  SUPERSEDED_FLAT = "make_interval(secs => greatest(p_lease_seconds, 1))"

  DERIVED_FUNCTIONS = %w[f1_claim_due_scheduled_actions f1_dispatch_scheduled_action].freeze

  def up
    DERIVED_FUNCTIONS.each { |name| execute rewrite(name, SUPERSEDED_DERIVED) }
    execute rewrite("f1_heartbeat_scheduled_action", SUPERSEDED_FLAT)

    F1::RuntimeGrants.apply_all(connection)
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "f1_claim_due_scheduled_actions and f1_dispatch_scheduled_action must be restored from " \
          "20260727120320 (which itself rewrote 20260725120027's definitions), and " \
          "f1_heartbeat_scheduled_action from 20260727120310"
  end

  private

  # Read the live definition and rewrite ONLY the lease assignment, so nothing else about these functions
  # can drift here by accident. The assignment is matched WHOLE — `lease_expires_at = v_now + <expr>` —
  # because the flat form is also a SUBSTRING of the superseded derived form, and matching the fragment
  # alone would corrupt the caller-floor term inside the very expression being replaced.
  def rewrite(name, superseded)
    definition = function_body(name)
    target = "lease_expires_at = v_now + #{superseded}"
    unless definition.include?(target)
      raise "#{name}: lease assignment not found in the expected form; the function has changed shape"
    end

    definition.sub("CREATE OR REPLACE FUNCTION", "CREATE FUNCTION")
              .sub("CREATE FUNCTION", "CREATE OR REPLACE FUNCTION")
              .sub(target, "lease_expires_at = v_now + #{LEASE_INTERVAL}")
  end

  def function_body(name)
    definition = connection.select_value(<<~SQL)
      SELECT pg_get_functiondef(p.oid)
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.proname = '#{name}'
    SQL
    raise "#{name} not found" if definition.nil?

    definition
  end
end
