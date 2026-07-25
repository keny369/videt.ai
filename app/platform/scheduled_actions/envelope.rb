# frozen_string_literal: true

module Platform
  module ScheduledActions
    # The scalar Sidekiq argument envelope (BACKGROUND_PROCESSING.md :69-84). A Sidekiq
    # invocation carries IDENTIFIERS ONLY — never an Active Record object, domain payload,
    # provider body, secret reference, token, email, URL or customer text. Exactly the eight
    # ratified fields, and the worker reloads everything else from PostgreSQL (:84).
    #
    # `work_id` is the UUID of the restricted Work Dispatch Binding created for this exact
    # enqueue/claim (:78); the receiver resolves the authorised target THROUGH it, never from
    # an envelope string. `claim_generation` is the exact claim this delivery is for, so a
    # stale or duplicate delivery fails the binding-mediated CAS and does no product work.
    # `correlation_id` and `causation_id` are copied from the persisted work (:81-82) so every
    # execution runs under the work's lineage — carried in the envelope, not reloaded.
    #
    # Any unknown, missing or mistyped field is rejected (`parse` returns nil) and the worker
    # exits without claiming work (:84) — never guessing an identity from a malformed message.
    class Envelope < Data.define(:schema_version, :organization_id, :work_type, :work_id,
                                 :product_generation, :claim_generation, :correlation_id, :causation_id)
      SCHEMA_VERSION = "1.0"
      FIELDS = %w[schema_version organization_id work_type work_id
                  product_generation claim_generation correlation_id causation_id].freeze
      # organization_id may be null only for a global platform-control job; F-04's kinds are
      # all Organization-scoped, so it is required here (relaxing to null later is backwards
      # compatible). The other four are always present identifiers.
      STRING_FIELDS = %w[organization_id work_type work_id correlation_id causation_id].freeze
      # The identifier fields that MUST be well-formed UUIDs. Validated at parse so a shape-valid
      # but non-UUID id fails closed here (a clean no-op) rather than raising at a `::uuid` cast
      # deeper in the transport. `work_type` is a catalogue token, not a UUID.
      UUID_FIELDS = %w[organization_id work_id correlation_id causation_id].freeze
      UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

      def to_args
        {
          "schema_version" => schema_version, "organization_id" => organization_id,
          "work_type" => work_type, "work_id" => work_id,
          "product_generation" => product_generation, "claim_generation" => claim_generation,
          "correlation_id" => correlation_id, "causation_id" => causation_id
        }
      end

      # Build the enqueue envelope from a freshly claimed Action (:71-83).
      def self.for(action)
        new(
          schema_version: SCHEMA_VERSION, organization_id: action.organization_id,
          work_type: action.work_type, work_id: action.work_id,
          product_generation: action.product_generation, claim_generation: action.claim_generation,
          correlation_id: action.correlation_id, causation_id: action.causation_id
        )
      end

      def self.parse(args)
        return nil unless args.is_a?(Hash)

        map = args.transform_keys(&:to_s)
        return nil unless map.keys.sort == FIELDS.sort
        return nil unless map["schema_version"] == SCHEMA_VERSION
        return nil unless STRING_FIELDS.all? { |field| map[field].is_a?(String) && !map[field].empty? }
        return nil unless UUID_FIELDS.all? { |field| map[field].match?(UUID_FORMAT) }
        return nil unless map["claim_generation"].is_a?(Integer) && map["claim_generation"].positive?
        return nil unless map["product_generation"].is_a?(Integer) && !map["product_generation"].negative?

        new(
          schema_version: map["schema_version"], organization_id: map["organization_id"],
          work_type: map["work_type"], work_id: map["work_id"],
          product_generation: map["product_generation"], claim_generation: map["claim_generation"],
          correlation_id: map["correlation_id"], causation_id: map["causation_id"]
        )
      end
    end
  end
end
