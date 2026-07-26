# frozen_string_literal: true

# S-05-007 automated observation slot schedule — the one-automated-attempt-per-slot
# invariant (SCORE_EVIDENCE_MODEL.md :151; contracts/S-05.json MTX-028
# background_job/retry_policy).
#
# The automated schedule reserves at most one Verification Attempt per due slot: ten
# slots at fixed offsets, each starting once in its half-open window. The
# `AutomatedObservationSlot` handler reserves under the per-Request advisory lock and
# only after `find_automated_attempt` finds no prior attempt for the slot, so a
# redelivered or retried slot job resumes the existing attempt rather than reserving a
# second one and double-counting. This partial unique index is the database backstop for
# that idempotency: two automated attempts can never share a (Request, slot offset),
# exactly as `verification_attempts_request_attempt_unique` backstops the attempt-number
# sequence. On-demand attempts carry a NULL slot offset and are excluded by the partial
# predicate, so their reservation path is untouched.
class AddAutomatedObservationSlotIndex < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE UNIQUE INDEX verification_attempts_one_automated_per_slot
        ON verification_attempts (verification_request_id, automated_slot_offset_minutes)
        WHERE origin = 'automated';
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS verification_attempts_one_automated_per_slot;"
  end
end
