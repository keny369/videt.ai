# frozen_string_literal: true

# S-07-009's BLOCKING PRECONDITION (FU-11): a terminal Crawl could carry NULL in both `coverage_status`
# and `completion_reason`, so a fully covered Crawl was byte-indistinguishable from one that recorded
# nothing. S-07-009 writes exactly those two columns, which is why this is repaired before it and not
# inside it.
#
# THE DEFECT IS ORDINARY TWO-VALUED LOGIC, and the record says so only after being wrong twice. The third
# review pass diagnosed it as a three-valued-logic hole in `crawls_coverage_status_check` and prescribed
# the `IS NOT DISTINCT FROM` form. THAT PRESCRIPTION IS A PROVEN NO-OP, evaluated against the live
# cluster: `NULL = ANY(ARRAY['full','partial'])` yields UNKNOWN, which a CHECK admits, and the NULL-safe
# rewrite yields TRUE, which it also admits. Applying it would have produced a diff, closed the item and
# left the hole open. `crawls_coverage_status_check` IS THEREFORE DELIBERATELY UNTOUCHED HERE.
#
# The admission is in `crawls_terminal_shape`, whose terminal limb required only `terminal_at IS NOT
# NULL`. Measured on the live cluster before this migration, the current predicate admits all of:
#
#   state='completed', terminal_at set, coverage_status NULL, completion_reason NULL   <- the defect
#   state='completed', completion_reason='completed', coverage_status NULL
#   state='failed',    completion_reason NULL
#
# THE RULE IS SCOPED BY STATE, AND THE SCOPING IS THE WHOLE REPAIR. "A terminal Crawl must carry BOTH
# columns" is WRONG and would break `IdentityAccess::Infrastructure::CrawlStartStore#fail`, which is the
# only production writer of `completion_reason` and sets `state='failed'` with a reason and NO coverage —
# correctly, because a queued Crawl that failed before execution made no request and covered nothing.
# So: every terminal state requires a `completion_reason`, and `completed` additionally requires a
# `coverage_status`. Verified against all seven reachable shapes; the `fail` shape is preserved exactly.
#
# WORKFLOW_SPECIFICATIONS.md :452 makes coverage a property of a run that RETRIEVED things, and the closed
# five-value CompletionReason enum (:456) exists precisely so that every terminal Crawl can say why it
# ended. A terminal row that says neither is not a state the contract has a name for.
class CrawlsTerminalCompleteness < ActiveRecord::Migration[8.1]
  NON_TERMINAL = <<~SQL.strip
    state = ANY (ARRAY['queued','running'])
        AND terminal_at IS NULL AND coverage_status IS NULL AND completion_reason IS NULL
  SQL

  # `state <> 'completed' OR coverage_status IS NOT NULL` rather than a CASE: inside this limb `state` is
  # already known to be one of the three terminal values and is NOT NULL on the column, so the disjunction
  # is two-valued here and cannot evaluate to UNKNOWN. That distinction is the one the first diagnosis of
  # this defect got wrong, so it is stated rather than assumed.
  TERMINAL = <<~SQL.strip
    state = ANY (ARRAY['completed','failed','canceled'])
        AND terminal_at IS NOT NULL
        AND completion_reason IS NOT NULL
        AND (state <> 'completed' OR coverage_status IS NOT NULL)
  SQL

  SHAPE = "((#{NON_TERMINAL}) OR (#{TERMINAL}))"

  def up
    # No backfill limb and none needed: verified at this migration that no `crawls` row violates the new
    # predicate, because the only terminal writer in production is `CrawlStartStore#fail`, whose shape the
    # rule preserves. NOT VALID would hide exactly the drift this constraint exists to catch.
    execute "ALTER TABLE crawls DROP CONSTRAINT crawls_terminal_shape"
    execute "ALTER TABLE crawls ADD CONSTRAINT crawls_terminal_shape CHECK #{SHAPE}"
  end

  def down
    execute "ALTER TABLE crawls DROP CONSTRAINT crawls_terminal_shape"
    execute <<~SQL
      ALTER TABLE crawls ADD CONSTRAINT crawls_terminal_shape CHECK
        ((#{NON_TERMINAL}) OR (state = ANY (ARRAY['completed','failed','canceled']) AND terminal_at IS NOT NULL))
    SQL
  end
end
