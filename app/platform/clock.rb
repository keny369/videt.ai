# frozen_string_literal: true

module Platform
  # Injected UTC clock. Domain and application code never read wall-clock time
  # directly (architecture fitness check forbids Time.now/Time.current in domain
  # code); they receive a Clock through the request context. Tests install a
  # fixed clock so every deadline boundary is exercised deterministically.
  #
  # Product equality races are decided by PostgreSQL transaction time, not this
  # clock; Clock supplies the application-side instant for envelopes and the
  # network/monotonic-free decisions the application makes before the commit.
  class Clock
    def self.system
      new(-> { Time.now.utc })
    end

    # A clock frozen at one instant, for tests and for a single request's
    # application-side timestamps.
    def self.fixed(instant)
      frozen = instant.getutc
      new(-> { frozen })
    end

    def initialize(source)
      @source = source
      freeze
    end

    # Always UTC.
    def now_utc
      @source.call
    end
  end
end
