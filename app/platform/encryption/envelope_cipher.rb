# frozen_string_literal: true

module Platform
  module Encryption
    # Envelope encryption over a KeyProvider (FOUNDATION-002 §Abstraction). Per protected
    # value: a fresh random 256-bit DEK encrypts the payload with AES-256-GCM under the
    # canonical AAD; the provider wraps the DEK under the active wrapping key; the result
    # is a fully-versioned Envelope. Plaintext exists only transiently here — it is never a
    # column, log, event or audit field. The cipher depends only on the KeyProvider
    # contract, so any provider (in-memory test, platform key ring) works unchanged.
    #
    # AAD binds both the payload ciphertext AND the wrapped DEK to the record location, so
    # relocating either to another record/attribute/purpose/tenant fails authentication.
    # There is no fallback decryption path: any mismatch is a single typed failure.
    class EnvelopeCipher
      def initialize(key_provider:)
        @provider = key_provider
      end

      def encrypt(plaintext:, aad:)
        aad_bytes = aad.canonical_bytes
        dek = Aes256Gcm.random_key
        sealed = Aes256Gcm.seal(key: dek, plaintext:, aad: aad_bytes)
        wrapped = @provider.wrap(dek:, aad: aad_bytes)

        Envelope.new(
          format_version: Envelope::FORMAT_VERSION,
          algorithm: Envelope::ALGORITHM,
          key_provider: @provider.id,
          wrapping_key_version: wrapped.version,
          wrapped_dek: wrapped.bytes,
          ciphertext: sealed.ciphertext,
          nonce: sealed.nonce,
          authentication_tag: sealed.tag,
          aad_schema_version: aad.schema_version
        )
      end

      def decrypt(envelope:, aad:)
        validate_envelope!(envelope, aad)
        aad_bytes = aad.canonical_bytes
        dek = @provider.unwrap(wrapped: envelope.wrapped_dek, version: envelope.wrapping_key_version, aad: aad_bytes)
        Aes256Gcm.open(
          key: dek, nonce: envelope.nonce, ciphertext: envelope.ciphertext,
          tag: envelope.authentication_tag, aad: aad_bytes
        )
      end

      private

      def validate_envelope!(envelope, aad)
        raise Error.new(:unsupported_format) unless envelope.format_version == Envelope::FORMAT_VERSION
        raise Error.new(:unsupported_algorithm) unless envelope.algorithm == Envelope::ALGORITHM
        raise Error.new(:unsupported_key_provider) unless envelope.key_provider == @provider.id
        raise Error.new(:aad_mismatch) unless envelope.aad_schema_version == aad.schema_version
      end
    end
  end
end
