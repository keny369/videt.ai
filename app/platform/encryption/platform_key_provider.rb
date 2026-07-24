# frozen_string_literal: true

require "openssl"
require "digest"

module Platform
  module Encryption
    # The production KeyProvider (FOUNDATION-002 §KeyProvider). It composes two seams:
    # the metadata boundary (which version is active/retired/destroyed, and its non-secret
    # fingerprint) and the deployment key source (the wrapping-key material, out of band).
    # It wraps/unwraps DEKs with AES-256-GCM and verifies the resolved key matches the
    # registered fingerprint, so a misconfigured deployment fails typed rather than
    # corrupting data. The wrapping key never leaves this object; a consumer only ever
    # receives opaque wrapped bytes.
    class PlatformKeyProvider
      DEFAULT_ID = "platform-keyring"

      attr_reader :id

      def initialize(id: DEFAULT_ID, metadata: nil, key_source: nil)
        @id = id
        @metadata = metadata || DatabaseMetadataStore.new
        @key_source = key_source || DeploymentKeySource.new
      end

      def active_version
        version = @metadata.active_version(@id)
        raise Error.new(:key_unavailable) if version.nil?

        version
      end

      def wrap(dek:, aad:)
        version = active_version
        key = resolve_key(version, for_encryption: true)
        sealed = Aes256Gcm.seal(key:, plaintext: dek, aad:)
        KeyProvider::Wrapped.new(bytes: sealed.pack, version:)
      end

      def unwrap(wrapped:, version:, aad:)
        key = resolve_key(version, for_encryption: false)
        sealed = Aes256Gcm.unpack(wrapped)
        Aes256Gcm.open(key:, nonce: sealed.nonce, ciphertext: sealed.ciphertext, tag: sealed.tag, aad:)
      end

      def status(version)
        record = @metadata.describe(@id, version)
        return :unknown if record.nil?

        case record.state
        when "active" then :usable
        when "retired" then :retired
        when "destroyed" then :destroyed
        else :unknown
        end
      end

      private

      # Resolve and validate the wrapping key for a version. Encryption requires the
      # active version; decryption also accepts retired versions; destroyed/unknown fail
      # typed; a resolved key whose fingerprint disagrees with the registered metadata is
      # a deployment misconfiguration, not a silent wrong-key decrypt.
      def resolve_key(version, for_encryption:)
        record = @metadata.describe(@id, version)
        raise Error.new(:key_version_unknown) if record.nil?
        raise Error.new(:key_destroyed) if record.state == "destroyed"
        raise Error.new(:key_retired_for_encryption) if for_encryption && record.state != "active"

        key = @key_source.key_bytes(@id, version)
        raise Error.new(:key_unavailable) if key.nil?

        verify_fingerprint!(record.fingerprint, key)
        key
      end

      def verify_fingerprint!(expected, key)
        return if expected.nil?

        actual = Digest::SHA256.digest(key)
        return if expected.bytesize == actual.bytesize && OpenSSL.fixed_length_secure_compare(expected, actual)

        raise Error.new(:provider_failure, "key fingerprint mismatch")
      end
    end
  end
end
