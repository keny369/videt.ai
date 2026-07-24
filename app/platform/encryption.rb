# frozen_string_literal: true

require "digest"

module Platform
  # Envelope Encryption (F-02, FOUNDATION-002) — FROZEN public contract.
  #
  # This module plus Aad, Error and Protected is the ENTIRE consumer surface. A feature
  # that must store a secret recoverably (S-05 challenge tokens first) calls `protect`,
  # `reveal` and `erase`, and builds an Aad to bind the ciphertext to its record. Consumers
  # never touch OpenSSL, the raw key rows, the wrapping internals, or a provider class:
  # the guarded classes behind these methods (EnvelopeCipher, Aes256Gcm, KeyProvider and
  # its implementations, DatabaseMetadataStore, DeploymentKeySource, EncryptedRecordStore,
  # Envelope) are internal, and spec/architecture/encryption_single_surface_spec.rb fails
  # CI on a raw OpenSSL::Cipher OR an internal-class reference outside the adapter.
  #
  # No plaintext, DEK or wrapping key is ever persisted, logged, or emitted; a failure is a
  # typed Platform::Encryption::Error whose loggable form is the reason alone.
  module Encryption
    module_function

    # The result of protecting a value: the storage reference (a capability the consumer
    # keeps on its own row) and the content digest (a non-secret anchor that survives erasure).
    Protected = Data.define(:reference, :content_digest)

    # Encrypt `plaintext` bound by `aad` and store it. Returns Protected(reference:, content_digest:).
    def protect(plaintext:, aad:, cipher: nil, store: nil)
      cipher ||= default_cipher
      store ||= EncryptedRecordStore.new
      digest = Digest::SHA256.digest(plaintext)
      envelope = cipher.encrypt(plaintext:, aad:)
      reference = store.put(envelope:, aad:, content_digest: digest)
      Protected.new(reference:, content_digest: digest)
    end

    # Fetch and decrypt the value at `reference`, bound by `aad`. Returns the plaintext, or
    # nil when the reference is unknown or the value has been erased. A crypto failure
    # (tampering, AAD mismatch, key retired/destroyed) raises a typed Platform::Encryption::Error.
    def reveal(reference, aad:, cipher: nil, store: nil)
      cipher ||= default_cipher
      store ||= EncryptedRecordStore.new
      fetched = store.fetch(reference)
      return nil if fetched.nil? || fetched.destroyed?

      cipher.decrypt(envelope: Envelope.deserialize(fetched.envelope), aad:)
    end

    # Record-level cryptographic erasure. Idempotent; returns :destroyed, :already_destroyed
    # or :unknown.
    def erase(reference, store: nil)
      (store || EncryptedRecordStore.new).destroy(reference)
    end

    def default_cipher
      EnvelopeCipher.new(key_provider: PlatformKeyProvider.new)
    end
  end
end
