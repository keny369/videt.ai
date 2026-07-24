# frozen_string_literal: true

module Platform
  module Encryption
    # The additional authenticated data (FOUNDATION-002 §AAD). AAD binds a ciphertext to
    # its intended LOCATION, not merely to a plaintext type: the application/domain, the
    # record type and identifier, the protected attribute/purpose, the tenant boundary
    # where applicable, and the AAD schema version. Relocating a ciphertext to another
    # record, attribute, purpose or tenant changes the AAD and therefore fails
    # authentication.
    #
    # Canonicalisation is deterministic (RFC 8785 canonical JSON via Platform::CanonicalJson):
    # sorted keys, no ambiguous ordering. Two Aads with equal fields always produce equal
    # bytes; that determinism is what makes the binding verifiable, and it is tested.
    class Aad < Data.define(:application, :record_type, :record_id, :purpose, :tenant, :schema_version)
      SCHEMA_VERSION = "record-aad-v1"

      # Build a binding. application/record_type/record_id/purpose are required; tenant is
      # optional (nil where a value is not tenant-scoped). A missing required field is a
      # caller programming error, not a crypto failure.
      def self.for(application:, record_type:, record_id:, purpose:, tenant: nil, schema_version: SCHEMA_VERSION)
        { application:, record_type:, record_id:, purpose:, schema_version: }.each do |name, value|
          raise ArgumentError, "AAD #{name} is required" if value.nil? || value.to_s.empty?
        end
        new(
          application: application.to_s, record_type: record_type.to_s, record_id: record_id.to_s,
          purpose: purpose.to_s, tenant: tenant&.to_s, schema_version: schema_version.to_s
        )
      end

      # The deterministic canonical AAD bytes fed to AES-256-GCM.
      def canonical_bytes
        Platform::CanonicalJson.encode(
          "application" => application, "record_type" => record_type, "record_id" => record_id,
          "purpose" => purpose, "tenant" => tenant, "schema_version" => schema_version
        ).b
      end
    end
  end
end
