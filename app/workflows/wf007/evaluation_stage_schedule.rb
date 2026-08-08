# frozen_string_literal: true

module Workflows
  module Wf007
    # The WF-007 halves of the Evaluation stage chain and the per-key Check attempt
    # (BACKGROUND_PROCESSING.md § Action-kind catalogue and § Evaluation stage registry).
    #
    # TWO RATIFIED KINDS, AND NO NEW ONE. Stages ride `evaluation_stage_advance`, exactly as
    # WF-006's `seal_input_snapshot` does; each Check attempt rides `check_attempt_due`, whose
    # catalogue cell is already `[pipeline, check_execute]`. Adding a kind is an
    # implementation-architecture change, and nothing here needed one.
    #
    # THE STAGE IS DERIVED, NOT CARRIED. A claimed Action hands a handler scalar identifiers
    # only — no payload — so a WF-007 stage cannot be named in the message. It does not need
    # to be: the Evaluation's own persisted state says unambiguously which stage is next
    # (no applicability snapshot -> seal it; slots outstanding -> wait; every slot terminal
    # and no Issue Set -> seal it). Deriving it is also strictly safer than carrying it,
    # because a stale or replayed action then cannot instruct the pipeline to run a stage the
    # Evaluation is not at.
    #
    # `product_generation` CARRIES THE STAGE ORDINAL, which is what keeps two stage actions
    # for one Evaluation distinct: the action identity preimage covers
    # `(kind, schema, organization, project, target, product_generation, schedule_generation,
    # due_at)`, and two stages scheduled at the same instant would otherwise collide into one
    # row and the second stage would never be delivered.
    module EvaluationStageSchedule
      module_function

      ACTION_KIND = "evaluation_stage_advance"
      ACTION_SCHEMA_VERSION = "1.0"
      TARGET_TYPE = "evaluation"

      # The ratified stage ordinals (BACKGROUND_PROCESSING.md :439-444). `seal_input_snapshot`
      # is ordinal 1 and belongs to WF-006.
      ORDINALS = { "materialize_applicability" => 2, "materialize_check_result_keys" => 3,
                   "seal_issue_set" => 5 }.freeze

      def schedule_applicability(**kwargs) = schedule(stage: "materialize_applicability", **kwargs)
      def schedule_issue_set(**kwargs) = schedule(stage: "seal_issue_set", **kwargs)

      def schedule(pg:, stage:, organization_id:, project_id:, evaluation_id:, due_at:, now:,
                   correlation_id:, causation_id: nil, command_id: nil)
        Platform::ScheduledActions::Store.new(pg).create(
          id: Platform::Ids.system.generate, action_kind: ACTION_KIND,
          action_schema_version: ACTION_SCHEMA_VERSION, organization_id:, project_id:,
          target_type: TARGET_TYPE, target_id: evaluation_id,
          product_generation: ORDINALS.fetch(stage), schedule_generation: 1,
          due_at:, now:, correlation_id:, causation_id: causation_id || correlation_id,
          command_id:, executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor
        )[:id]
      end
    end

    # `CheckAttemptSchedule` — the other half of this chain — lives in its own
    # `check_attempt_schedule.rb`. It used to be declared here as a sibling, where Zeitwerk had
    # no path implying it and could not autoload it; see that file for what that cost.
  end
end
