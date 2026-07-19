# frozen_string_literal: true

module Platform
  # Injected identifier generator. Every F1-created row uses an application
  # generated UUIDv7 (schemas/POSTGRESQL_SCHEMA.md § Identifiers). Domain code
  # never calls SecureRandom directly (architecture fitness); it receives an Ids
  # port through the request context. Tests inject a deterministic sequence so
  # ordering and idempotency assertions are stable.
  class Ids
    def self.system
      new(-> { SecureRandom.uuid_v7 })
    end

    # A deterministic generator that yields the supplied UUIDs in order and then
    # raises, so a test that allocates more IDs than it declared fails loudly.
    def self.sequence(uuids)
      queue = uuids.dup
      new(lambda do
        raise "Platform::Ids sequence exhausted" if queue.empty?

        queue.shift
      end)
    end

    def initialize(source)
      @source = source
      freeze
    end

    def generate
      @source.call
    end
  end
end
