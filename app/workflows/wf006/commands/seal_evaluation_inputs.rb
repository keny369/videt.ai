# frozen_string_literal: true

module Workflows
  module Wf006
    module Commands
      # WF-006 SealEvaluationInputs — the `seal_input_snapshot` Evaluation stage
      # (BACKGROUND_PROCESSING.md :439, whose outcome is the "immutable snapshot/blocked
      # result transaction"), executed behind the ratified `evaluation_stage_advance`
      # ScheduledAction that the crawl-terminalizing transaction schedules.
      #
      # Service-only: no Session and no human actor. WF-006's Authorization is
      # "tenant-scoped parsing/evaluation/indexing service identities execute and retry",
      # and the readiness derivation is a consequence of persisted facts rather than of
      # anyone's permission.
      #
      # The target is the CRAWL, not the Evaluation. The transaction that terminalizes a
      # Crawl knows the Crawl; the initial Evaluation is keyed `(crawl_id, kind=initial)`
      # and so is derivable, which keeps the action identity computable without a payload.
      SealEvaluationInputs = Data.define(:command_id, :schema_version, :organization_id, :target_type,
                                         :crawl_id, :due_at, :action_id, :action_identity_sha256,
                                         :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class SealEvaluationInputs
        TYPE = "wf006.seal_evaluation_inputs"

        def self.from_scheduled_action(action:, command_id:, requested_at_utc:)
          new(command_id:, schema_version: action.action_schema_version,
              organization_id: action.organization_id, target_type: action.target_type,
              crawl_id: action.target_id, due_at: action.due_at, action_id: action.id,
              action_identity_sha256: action.identity_sha256, requested_at_utc:)
        end

        def command_type = TYPE
        def idempotency_key = action_identity_sha256
      end
    end
  end
end
