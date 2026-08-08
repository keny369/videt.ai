# frozen_string_literal: true

# Admit the ONE Evaluation lifecycle edge WF-007 performs, and nothing wider.
#
# `EvaluationInputGateEdges` (20260807140000) admitted `pending -> running` and
# `running -> failed`, and said exactly why it stopped there: "`running -> completed` belongs
# to WF-007's Issue-set seal and `-> superseded` to WF-011 reassessment; neither workflow
# exists, so admitting their edges would let a future defect write a state no code is
# entitled to produce."
#
# WF-007 now exists. Its `seal_issue_set` stage seals the immutable Issue Set and transitions
# the Evaluation to completed, so this admits:
#
#     running -> completed      the terminal state EvaluationCompleted names
#
# `pending -> failed` joins it for the same reason the gate's edges did: WF-007 fails the
# Evaluation at the Catalog, applicability, tenant-integrity or result-identity boundary
# BEFORE it starts one, and a boundary failure discovered at that point has no running state
# to fail from.
#
# `-> superseded` STILL RAISES. WF-011 reassessment does not exist, and supersession is its
# transition, not WF-007's. The guard stays the narrowest statement of what this build can
# actually do.
#
# COMPLETION IS NOT PROMOTION, and the guard is where that stays true structurally: reaching
# `completed` advances no current Issue-set pointer and publishes no score. Promotion is
# WF-008's atomic act and needs a scorable ScoreSnapshot, which under the ratified OD-010
# baseline does not exist — so a completed Evaluation with an unavailable score is a
# COMPLETED Evaluation with an unpromoted pointer, not a failure, and this edge is what lets
# it say so.
class EvaluationCompletionEdge < ActiveRecord::Migration[8.1]
  def up
    execute(guard(completion: true))
  end

  def down
    execute(guard(completion: false))
  end

  private

  def guard(completion:)
    completed_branch = if completion
                         <<~SQL
                           ELSIF OLD.state = 'running' AND NEW.state = 'completed' THEN
                             IF NEW.completed_at IS NULL THEN
                               RAISE EXCEPTION 'evaluation_transition_instant_required completed'
                                 USING ERRCODE = 'raise_exception';
                             END IF;
                           ELSIF OLD.state = 'pending' AND NEW.state = 'failed' THEN
                             IF NEW.failed_at IS NULL THEN
                               RAISE EXCEPTION 'evaluation_transition_instant_required failed'
                                 USING ERRCODE = 'raise_exception';
                             END IF;
                         SQL
                       else
                         ""
                       end

    <<~SQL
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
          #{completed_branch}ELSE
            RAISE EXCEPTION 'evaluation_transition_unavailable % -> %', OLD.state, NEW.state
              USING ERRCODE = 'raise_exception';
          END IF;
        END IF;

        RETURN NEW;
      END;
      $$;
    SQL
  end
end
