# frozen_string_literal: true

module EncryptionSupport
  # A deterministic, in-memory KeyProvider used to prove the F-02 contract and to drive
  # EnvelopeCipher tests with no database and no deployment secrets. It holds real
  # wrapping-key material in memory (legitimate for a test double — never for the
  # production provider) and performs real AES-256-GCM DEK wrapping through the shared
  # primitive, so it exercises the same crypto path the production provider does.
  #
  # It is the "second provider" the acceptance bar requires: EnvelopeCipher works against
  # it without change. The lifecycle hooks (rotate!/retire!/destroy!) are test controls,
  # not part of the KeyProvider contract.
  class InMemoryKeyProvider
    Aes = Platform::Encryption::Aes256Gcm
    Wrapped = Platform::Encryption::KeyProvider::Wrapped
    Failure = Platform::Encryption::Error

    attr_reader :id

    def initialize(id: "in-memory-test")
      @id = id
      @keys = {}   # version => 32-byte key (nil once destroyed)
      @state = {}  # version => :usable | :retired | :destroyed
      @active = nil
      rotate!("v1")
    end

    # --- KeyProvider contract ---

    def active_version
      raise Failure.new(:key_unavailable) if @active.nil? || @state[@active] != :usable

      @active
    end

    def wrap(dek:, aad:)
      version = active_version
      sealed = Aes.seal(key: @keys.fetch(version), plaintext: dek, aad: aad)
      Wrapped.new(bytes: sealed.pack, version:)
    end

    def unwrap(wrapped:, version:, aad:)
      raise Failure.new(:key_version_unknown) unless @state.key?(version)
      raise Failure.new(:key_destroyed) if @state[version] == :destroyed || @keys[version].nil?

      sealed = Aes.unpack(wrapped)
      Aes.open(key: @keys.fetch(version), nonce: sealed.nonce, ciphertext: sealed.ciphertext, tag: sealed.tag, aad:)
    end

    def status(version) = @state.fetch(version, :unknown)

    # --- test controls (not the contract) ---

    # Activate a new usable version, demoting the previous active one to retired.
    def rotate!(version)
      @keys[version] = Aes.random_key
      @state.each { |existing, state| @state[existing] = :retired if state == :usable && existing != version }
      @state[version] = :usable
      @active = version
      version
    end

    def retire!(version)
      @state[version] = :retired if @state[version] == :usable
      @active = nil if @active == version
    end

    def destroy!(version)
      @keys[version] = nil
      @state[version] = :destroyed
      @active = nil if @active == version
    end
  end
end
