# frozen_string_literal: true

require "openssl"
require "securerandom"

module Platform
  module Encryption
    # The single authenticated-encryption primitive for F-02 (FOUNDATION-002 §Envelope
    # format: AES-256-GCM). This is the ONE place `OpenSSL::Cipher` is used in the whole
    # application (enforced by the F-02 architecture fitness spec). Both the payload
    # encryption (EnvelopeCipher) and the DEK wrapping (KeyProvider) go through it, so
    # the AEAD contract — 256-bit key, fresh 96-bit nonce per seal, 128-bit tag,
    # AAD-authenticated, tamper-detected on open — is defined in exactly one place.
    #
    # Nonce uniqueness: a fresh cryptographically-random 96-bit nonce is generated per
    # `seal`. A data-encryption key protects exactly one payload (per-record DEK), so its
    # nonce is never reused; the wrapping key is reused across DEK wraps under fresh random
    # nonces, well within the safe random-nonce bound for AES-GCM. Auth failure on `open`
    # (tampered ciphertext/tag/nonce, wrong key, or wrong AAD) is a single typed outcome —
    # never a silent plaintext-of-garbage, and there is no fallback decrypt.
    module Aes256Gcm
      module_function

      CIPHER = "aes-256-gcm"
      KEY_BYTES = 32
      NONCE_BYTES = 12
      TAG_BYTES = 16
      PACK_VERSION = 0x01 # a 1-byte version prefix so the wrapped/packed layout is explicit

      # A sealed value: the fresh nonce, the ciphertext, and the authentication tag.
      Sealed = Data.define(:nonce, :ciphertext, :tag) do
        # Explicit, versioned, fixed-layout serialization for an opaque single-blob field
        # (e.g. a wrapped DEK): [version:1][nonce:12][tag:16][ciphertext:rest]. Not an
        # ambiguous concatenation — every field but the trailing ciphertext is fixed-width.
        def pack = [PACK_VERSION].pack("C") + nonce + tag + ciphertext
      end

      # A cryptographically-random 256-bit key (a DEK, or a wrapping key for a test provider).
      def random_key = random_bytes(KEY_BYTES)

      def random_bytes(count)
        SecureRandom.bytes(count)
      rescue StandardError => e
        raise Error.new(:random_source_failure, e.class.name)
      end

      def seal(key:, plaintext:, aad:)
        validate_key!(key)
        nonce = random_bytes(NONCE_BYTES)
        cipher = OpenSSL::Cipher.new(CIPHER).encrypt
        cipher.key = key
        cipher.iv = nonce
        cipher.auth_data = aad.b
        ciphertext = cipher.update(plaintext.b) + cipher.final
        Sealed.new(nonce:, ciphertext:, tag: cipher.auth_tag)
      rescue OpenSSL::Cipher::CipherError => e
        raise Error.new(:provider_failure, e.class.name)
      end

      def open(key:, nonce:, ciphertext:, tag:, aad:)
        validate_key!(key)
        raise Error.new(:authentication_failed) unless valid_field?(nonce, NONCE_BYTES)
        raise Error.new(:authentication_failed) unless valid_field?(tag, TAG_BYTES)

        cipher = OpenSSL::Cipher.new(CIPHER).decrypt
        cipher.key = key
        cipher.iv = nonce
        cipher.auth_tag = tag
        cipher.auth_data = aad.b
        cipher.update(ciphertext.b) + cipher.final
      rescue OpenSSL::Cipher::CipherError
        raise Error.new(:authentication_failed)
      end

      # Parse a packed Sealed blob back into its fields. A short or wrong-version blob is a
      # typed malformed_envelope rather than an index error.
      def unpack(bytes)
        raw = bytes.to_s.b
        minimum = 1 + NONCE_BYTES + TAG_BYTES
        raise Error.new(:malformed_envelope, "short packed blob") if raw.bytesize < minimum
        raise Error.new(:malformed_envelope, "packed version") unless raw.getbyte(0) == PACK_VERSION

        offset = 1
        nonce = raw.byteslice(offset, NONCE_BYTES)
        tag = raw.byteslice(offset + NONCE_BYTES, TAG_BYTES)
        ciphertext = raw.byteslice(offset + NONCE_BYTES + TAG_BYTES..) || "".b
        Sealed.new(nonce:, ciphertext:, tag:)
      end

      def valid_field?(value, size) = value.is_a?(String) && value.bytesize == size

      def validate_key!(key)
        raise Error.new(:provider_failure, "invalid key length") unless valid_field?(key, KEY_BYTES)
      end
    end
  end
end
