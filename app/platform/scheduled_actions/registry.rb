# frozen_string_literal: true

module Platform
  module ScheduledActions
    # The closed action-kind => operation dispatch registry
    # (BACKGROUND_PROCESSING.md :375 "the exact action-kind table below; no
    # arbitrary command discriminator", :421 "A generic action not present here is
    # `scheduled_work_mapping_mismatch` and quarantines; it is never dispatched by
    # method-name reflection").
    #
    # Registration is explicit and validated against the ratified catalogue: the
    # kind must exist, and the declared operation must be exactly the one the
    # catalogue assigns to it. Resolution is therefore a table lookup, never a
    # constant/method name derived from the action row.
    #
    # Fail-closed by construction. An action whose kind has no registered handler,
    # or whose `action_schema_version` no registered handler declares, resolves to
    # nil and the worker quarantines it without performing product work.
    class Registry
      Entry = Data.define(:action_kind, :action_schema_version, :operation, :handler, :command)

      class UnknownActionKind < StandardError; end
      class OperationMismatch < StandardError; end

      def self.default
        @default ||= new
      end

      def initialize
        @entries = {}
      end

      # `handler` responds to `new.call(command:, request_context:)` and `command`
      # responds to `from_scheduled_action(action:, command_id:, requested_at_utc:)`.
      def register(action_kind:, action_schema_version:, operation:, handler:, command:)
        unless Catalogue.kind?(action_kind)
          raise UnknownActionKind, "#{action_kind.inspect} is not in the ratified action-kind catalogue"
        end

        expected = Catalogue::GENERIC_OPERATIONS[action_kind]
        if expected && expected != operation
          raise OperationMismatch, "#{action_kind} maps to #{expected}, not #{operation}"
        end

        @entries[[action_kind, action_schema_version]] =
          Entry.new(action_kind:, action_schema_version:, operation:, handler:, command:)
        self
      end

      # The registered entry for this exact (kind, schema version) pair, or nil.
      def resolve(action_kind:, action_schema_version:)
        @entries[[action_kind, action_schema_version]]
      end

      # True when the kind is registered at some schema version — used to tell an
      # unmapped kind apart from an unsupported schema version, so each fails
      # closed under its own reason.
      def kind_registered?(action_kind)
        @entries.keys.any? { |(kind, _)| kind == action_kind }
      end

      def reset! = @entries.clear
      def size = @entries.size
    end
  end
end
