# frozen_string_literal: true

module Workflows
  # The `evaluation_stage_advance` router.
  #
  # WHY A ROUTER EXISTS AT ALL. The dispatch registry is keyed on `(action_kind,
  # action_schema_version)` and resolves to exactly one command/handler pair — that closure is
  # deliberate, because "a generic action not present here is `scheduled_work_mapping_mismatch`
  # and quarantines; it is never dispatched by method-name reflection". But the ratified
  # catalogue gives the whole Evaluation stage chain ONE kind, and the chain legitimately spans
  # two workflows: WF-006 owns `seal_input_snapshot` and WF-007 owns the stages after it.
  #
  # So the routing happens inside a registered pair rather than by registering two, and it
  # routes on the action's own TARGET TYPE, which the transport already carries as a scalar:
  #
  #     target_type `crawl`      -> WF-006 SealEvaluationInputs
  #     target_type `evaluation` -> WF-007 AdvanceEvaluationStage
  #
  # That is a closed two-branch table over values the catalogue fixes, not a lookup derived
  # from the action row: an unrecognized target type is refused here exactly as an unregistered
  # kind is refused at the registry, rather than being resolved to whichever handler happens to
  # match. Both branches remain ordinary handlers with their own commands, idempotency records
  # and ledgers; nothing about either is special-cased for the other.
  module EvaluationStage
    CRAWL = "crawl"
    EVALUATION = "evaluation"

    class Router
      def call(command:, request_context:)
        action = command.action
        case action.target_type
        when CRAWL
          delegate(Wf006::Commands::SealEvaluationInputs, Wf006::Handlers::SealEvaluationInputs,
                   command, request_context)
        when EVALUATION
          delegate(Wf007::Commands::AdvanceEvaluationStage, Wf007::Handlers::AdvanceEvaluationStage,
                   command, request_context)
        else
          # Fail closed, in the same shape and for the same reason the registry does: a stage
          # action naming a target type no stage owns is a mapping mismatch, and guessing a
          # handler for it would be exactly the reflection the contract forbids.
          Platform::CommandResult.failure(
            result_id: request_context.generate_id, command_type: command.command_type,
            failure: Platform::ErrorCatalog.failure("scheduled_action_target_mismatch",
                                                    support_reference: request_context.correlation_id),
            audit_record_id: request_context.generate_id, correlation_id: request_context.correlation_id
          )
        end
      end

      private

      def delegate(command_class, handler_class, command, request_context)
        inner = command_class.from_scheduled_action(
          action: command.action, command_id: command.command_id,
          requested_at_utc: command.requested_at_utc
        )
        handler_class.new.call(command: inner, request_context:)
      end
    end
  end
end
