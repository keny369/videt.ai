# frozen_string_literal: true

require "base64"
require "json"

module Platform
  module Encryption
    # The authenticated envelope (FOUNDATION-002 §Envelope format). Every field needed to
    # decrypt deterministically is carried explicitly and versioned — nothing relies on a
    # mutable default:
    #
    #   format_version        the envelope layout version
    #   algorithm             the AEAD algorithm ("AES-256-GCM")
    #   key_provider          which provider wrapped the DEK (selects the unwrap authority)
    #   wrapping_key_version  the wrapping-key version that wrapped the DEK
    #   wrapped_dek           the DEK, wrapped by the provider (opaque)
    #   ciphertext            the AES-256-GCM ciphertext of the payload
    #   nonce                 the payload nonce
    #   authentication_tag    the payload GCM tag
    #   aad_schema_version    the AAD schema the ciphertext was bound under
    #
    # Serialization is deterministic canonical JSON with base64 binary fields — explicitly
    # versioned (format_version) and unambiguous, never a concatenated blob. Deserializing
    # a malformed or wrong-version blob is a typed failure, not an index error.
    class Envelope < Data.define(
      :format_version, :algorithm, :key_provider, :wrapping_key_version,
      :wrapped_dek, :ciphertext, :nonce, :authentication_tag, :aad_schema_version
    )
      FORMAT_VERSION = 1
      ALGORITHM = "AES-256-GCM"
      BINARY_FIELDS = %i[wrapped_dek ciphertext nonce authentication_tag].freeze
      STRING_FIELDS = %i[algorithm key_provider wrapping_key_version aad_schema_version].freeze

      def serialize
        map = { "format_version" => format_version }
        STRING_FIELDS.each { |field| map[field.to_s] = public_send(field) }
        BINARY_FIELDS.each { |field| map[field.to_s] = Base64.strict_encode64(public_send(field)) }
        Platform::CanonicalJson.encode(map).b
      end

      def self.deserialize(bytes)
        map = JSON.parse(bytes.to_s)
        raise Error.new(:malformed_envelope, "not an object") unless map.is_a?(Hash)
        raise Error.new(:unsupported_format) unless map["format_version"] == FORMAT_VERSION

        new(
          format_version: FORMAT_VERSION,
          algorithm: string(map, "algorithm"),
          key_provider: string(map, "key_provider"),
          wrapping_key_version: string(map, "wrapping_key_version"),
          aad_schema_version: string(map, "aad_schema_version"),
          wrapped_dek: binary(map, "wrapped_dek"),
          ciphertext: binary(map, "ciphertext"),
          nonce: binary(map, "nonce"),
          authentication_tag: binary(map, "authentication_tag")
        )
      rescue JSON::ParserError
        raise Error.new(:malformed_envelope, "invalid JSON")
      end

      def self.string(map, key)
        value = map[key]
        raise Error.new(:malformed_envelope, "missing #{key}") unless value.is_a?(String) && !value.empty?

        value
      end

      def self.binary(map, key)
        value = map[key]
        raise Error.new(:malformed_envelope, "missing #{key}") unless value.is_a?(String)

        Base64.strict_decode64(value)
      rescue ArgumentError
        raise Error.new(:malformed_envelope, "invalid base64 #{key}")
      end
    end
  end
end
