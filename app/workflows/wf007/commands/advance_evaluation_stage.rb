# frozen_string_literal: true

module Workflows
  module Wf007
    module Commands
      # WF-007 AdvanceEvaluationStage — one visit to the Evaluation's stage chain, behind the
      # ratified `evaluation_stage_advance` ScheduledAction whose target is the EVALUATION.
      #
      # Service-only: no Session and no human actor. "WF-007 Authorization names the evaluation
      # service identity for checks and creation, and no other actor may change Issue or
      # Evidence validation state." No principal permission exists for catalog validation,
      # applicability sealing, key materialization or Check execution, and none may be invented.
      #
      # Scalar identifiers only. The handler reloads every product value from PostgreSQL under
      # the action's Organization context, and derives WHICH stage to run from the Evaluation's
      # persisted state rather than from anything the message carries.
      AdvanceEvaluationStage = Data.define(:command_id, :schema_version, :organization_id, :target_type,
                                           :evaluation_id, :stage_ordinal, :due_at, :action_id,
                                           :action_identity_sha256, :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class AdvanceEvaluationStage
        TYPE = "wf007.advance_evaluation_stage"

        def self.from_scheduled_action(action:, command_id:, requested_at_utc:)
          new(command_id:, schema_version: action.action_schema_version,
              organization_id: action.organization_id, target_type: action.target_type,
              evaluation_id: action.target_id, stage_ordinal: action.product_generation.to_i,
              due_at: action.due_at, action_id: action.id,
              action_identity_sha256: action.identity_sha256, requested_at_utc:)
        end

        def command_type = TYPE
        def idempotency_key = action_identity_sha256
      end
    end
  end
end
