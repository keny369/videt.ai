# frozen_string_literal: true

# A stand-in handler and command for the ScheduledAction transport specs. They
# satisfy exactly the two interfaces the worker requires — `new.call(command:,
# request_context:)` and `from_scheduled_action(action:, command_id:,
# requested_at_utc:)` — so the transport can be proved (one execution per action,
# fail-closed dispatch, service-identity context, non-stranding recovery)
# independently of any product workflow.
module ScheduledActionSpies
  class Handler
    class << self
      attr_accessor :calls, :behaviour

      def reset!(&behaviour)
        self.calls = []
        self.behaviour = behaviour
      end
    end

    def call(command:, request_context:)
      self.class.calls << { command:, request_context: }
      self.class.behaviour.call(command, request_context)
    end
  end

  Command = Data.define(:action, :command_id, :requested_at_utc) do
    def self.from_scheduled_action(action:, command_id:, requested_at_utc:)
      new(action:, command_id:, requested_at_utc:)
    end
  end
end
