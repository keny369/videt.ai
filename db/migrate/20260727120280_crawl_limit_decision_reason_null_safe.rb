# frozen_string_literal: true

# The S-07-008 threshold biconditional had a three-valued-logic hole
# (schemas/POSTGRESQL_SCHEMA.md :300; WORKFLOW_SPECIFICATIONS.md :442).
#
# As first written the hard limb read `decision_reason_code = 'limit_reached'`. For a row with
# `threshold_kind='hard'`, `decision_value='hard_reached'` and a NULL reason that comparison
# evaluates to NULL, not FALSE — so the whole expression is `FALSE OR NULL` = NULL, and SQL admits a
# CHECK whose result is unknown. A hard decision with no reason was therefore accepted, which is
# exactly the row `:300`'s "hard/hard_reached/`limit_reached`" sentence exists to forbid, and which
# the `decision` event profile would then have to serialize with a null `decision_reason_code` while
# claiming `outcome: limit_reached`.
#
# Found by the persistence-invariants spec written for this table after the ADR-026 security lens
# observed that it had shipped without one — the exact defect class that absence hides. Recorded as
# its own migration rather than by amending the original, so the hole and its repair both stay
# visible: `IS NOT DISTINCT FROM` is NULL-safe and makes the unknown case FALSE.
class CrawlLimitDecisionReasonNullSafe < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE crawl_limit_decisions
        DROP CONSTRAINT crawl_limit_decisions_threshold_agreement;
      ALTER TABLE crawl_limit_decisions
        ADD CONSTRAINT crawl_limit_decisions_threshold_agreement CHECK (
          (threshold_kind = 'soft' AND decision_value = 'soft_reached'
             AND decision_reason_code IS NULL)
          OR
          (threshold_kind = 'hard' AND decision_value = 'hard_reached'
             AND decision_reason_code IS NOT DISTINCT FROM 'limit_reached')
        );
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE crawl_limit_decisions
        DROP CONSTRAINT crawl_limit_decisions_threshold_agreement;
      ALTER TABLE crawl_limit_decisions
        ADD CONSTRAINT crawl_limit_decisions_threshold_agreement CHECK (
          (threshold_kind = 'soft' AND decision_value = 'soft_reached' AND decision_reason_code IS NULL)
          OR
          (threshold_kind = 'hard' AND decision_value = 'hard_reached' AND decision_reason_code = 'limit_reached')
        );
    SQL
  end
end
