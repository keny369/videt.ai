# frozen_string_literal: true

# Admit the two Evaluation lifecycle edges the WF-006 input gate performs, and nothing
# wider.
#
# `create_evaluations_guard` (20260727120090) refused EVERY state change and said so:
# "StartCrawl in S-07-003 inserts the pending row; S-08/S-09 relax the lifecycle edges".
# Nothing relaxed them, so a started Crawl's `initial` Evaluation was created `pending`
# and could never leave it — and OD-018 refuses a Project another root Crawl while one is
# pending or running. The first Crawl of a Project was therefore permanently its last.
#
# This relaxes exactly the edges of the ratified blocked-input transaction
# (WORKFLOW_SPECIFICATIONS.md :511, "atomically transitions `Evaluation.Pending ->
# Evaluation.Running -> Evaluation.Failed` solely to record the terminal input-gate
# failure"):
#
#     pending -> running        the recorded waypoint EvaluationStarted names
#     running -> failed         the terminal state EvaluationFailed names
#
# EVERY OTHER EDGE STILL RAISES. `running -> completed` belongs to WF-007's Issue-set seal
# and `-> superseded` to WF-011 reassessment; neither workflow exists, so admitting their
# edges would let a future defect write a state no code is entitled to produce. The guard
# stays the narrowest statement of what this build can actually do, exactly as the crawl
# host-gate guard admits `pending -> in_progress -> unavailable` and nothing wider.
#
# The destination's instant is required with it, so a transition cannot leave an
# Evaluation in a state with no record of when it entered it.
class EvaluationInputGateEdges < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_evaluations_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'evaluation_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.kind IS DISTINCT FROM OLD.kind
           OR NEW.crawl_id IS DISTINCT FROM OLD.crawl_id
           OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
          RAISE EXCEPTION 'evaluation_facts_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        IF NEW.state IS DISTINCT FROM OLD.state THEN
          IF OLD.state = 'pending' AND NEW.state = 'running' THEN
            IF NEW.started_at IS NULL THEN
              RAISE EXCEPTION 'evaluation_transition_instant_required running'
                USING ERRCODE = 'raise_exception';
            END IF;
          ELSIF OLD.state = 'running' AND NEW.state = 'failed' THEN
            IF NEW.failed_at IS NULL THEN
              RAISE EXCEPTION 'evaluation_transition_instant_required failed'
                USING ERRCODE = 'raise_exception';
            END IF;
          ELSE
            RAISE EXCEPTION 'evaluation_transition_unavailable % -> %', OLD.state, NEW.state
              USING ERRCODE = 'raise_exception';
          END IF;
        END IF;

        RETURN NEW;
      END;
      $$;
    SQL
  end

  def down
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_evaluations_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'evaluation_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.kind IS DISTINCT FROM OLD.kind
           OR NEW.crawl_id IS DISTINCT FROM OLD.crawl_id
           OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
          RAISE EXCEPTION 'evaluation_facts_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.state IS DISTINCT FROM OLD.state THEN
          RAISE EXCEPTION 'evaluation_transition_unavailable % -> %', OLD.state, NEW.state USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END;
      $$;
    SQL
  end
end
