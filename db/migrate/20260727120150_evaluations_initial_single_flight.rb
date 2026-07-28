# frozen_string_literal: true

# S-07-003 StartCrawl — the OD-018 single-initial-orchestration DATABASE backstop, plus the
# canonical orchestration-slot restriction it depends on.
#
# schemas/POSTGRESQL_SCHEMA.md :340 states that `orchestration_slot_active` "may be true only for
# a reassessment/retry", so the S-07-002 `evaluations_orchestration_slot_unique` partial unique
# (one active slot per Project) is the WF-011 reassessment single-flight and does NOT constrain an
# INITIAL Evaluation. OD-018 nevertheless requires that at most one pending-or-running INITIAL
# assessment Evaluation exists per Project, re-checked at the `Queued -> Running` commit
# (WORKFLOW_SPECIFICATIONS.md :725; contracts/S-07.json MTX-030 concurrency). The application
# serializes that check on the per-Project advisory lock QueueCrawl already uses; this migration
# adds the database backstop so the invariant cannot be lost to an application defect.
#
#   1. CHECK: only a reassessment/retry may hold the orchestration slot (a transcription of the
#      canonical restriction; the "pending, running, or completed-awaiting-publication" state limb
#      is WF-011's and is not asserted here).
#   2. Partial unique `(organization_id, project_id) WHERE kind = 'initial' AND state IN
#      ('pending','running')` — the OD-018 backstop proper. It is additive: it constrains no shape
#      any accepted tranche writes, because before S-07-003 nothing created an Evaluation at all.
class EvaluationsInitialSingleFlight < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE evaluations ADD CONSTRAINT evaluations_orchestration_slot_kind
        CHECK (NOT orchestration_slot_active OR kind IN ('reassessment','retry'));
      CREATE UNIQUE INDEX evaluations_initial_single_flight_unique ON evaluations
        (organization_id, project_id) WHERE kind = 'initial' AND state IN ('pending','running');
    SQL
  end

  def down
    execute <<~SQL
      DROP INDEX IF EXISTS evaluations_initial_single_flight_unique;
      ALTER TABLE evaluations DROP CONSTRAINT IF EXISTS evaluations_orchestration_slot_kind;
    SQL
  end
end
