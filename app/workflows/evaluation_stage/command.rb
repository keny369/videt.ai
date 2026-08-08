# frozen_string_literal: true

module Workflows
  module EvaluationStage
    # The command half of the registered pair. It defers construction of the real command to
    # the branch, because each branch's command carries a different target identifier and
    # neither should be widened to accommodate the other.
    Command = Data.define(:action, :command_id, :requested_at_utc) do
      def self.from_scheduled_action(action:, command_id:, requested_at_utc:)
        new(action:, command_id:, requested_at_utc:)
      end

      def command_type = "evaluation_stage.advance"
      def idempotency_key = action.identity_sha256
      def schema_version = action.action_schema_version
      def target_type = action.target_type
    end
  end
end
