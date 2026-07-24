# frozen_string_literal: true

require "digest"

module EncryptionSupport
  # An in-memory stand-in for DatabaseMetadataStore, so PlatformKeyProvider's logic is
  # unit-tested without a database. State and the active pointer are controlled
  # independently, so a metadata inconsistency (e.g. a version retired between resolving
  # the active version and describing it) can be exercised.
  class FakeMetadataStore
    Record = Platform::Encryption::DatabaseMetadataStore::Record

    def initialize
      @state = {}        # version => "active" | "retired" | "destroyed"
      @fingerprint = {}  # version => 32 raw bytes (nil once destroyed)
      @active = nil
    end

    def register(version, key, state: "active")
      @state[version] = state
      @fingerprint[version] = state == "destroyed" ? nil : Digest::SHA256.digest(key)
      @active = version if state == "active"
    end

    def set_state(version, state)
      @state[version] = state
      @fingerprint[version] = nil if state == "destroyed"
    end

    def activate(version) = (@active = version)
    def clear_active = (@active = nil)

    # --- MetadataStore contract ---
    def active_version(_provider) = @active

    def describe(_provider, version)
      return nil unless @state.key?(version)

      Record.new(state: @state.fetch(version), fingerprint: @fingerprint[version])
    end
  end
end
