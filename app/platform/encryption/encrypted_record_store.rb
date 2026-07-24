# frozen_string_literal: true

require "digest"

module Platform
  module Encryption
    # The encrypted-record storage boundary (FOUNDATION-002). Persists an Envelope plus
    # non-secret lifecycle metadata through the SECURITY DEFINER functions — never the
    # owner-only table directly — and returns an unguessable reference. A consumer stores
    # only that reference (+ key version + content digest) on its own row; holding the
    # reference is the capability to fetch or destroy the envelope.
    #
    # Record-level `destroy` is cryptographic erasure of ONE value: the envelope (and thus
    # the only path to its DEK and plaintext) is removed, while the content digest and the
    # row's audit survive. It is not bulk key-version erasure.
    class EncryptedRecordStore
      Fetched = Data.define(:envelope, :state, :content_digest, :wrapping_key_version, :key_provider) do
        def destroyed? = state == "destroyed"
      end

      def initialize(pg: nil)
        @pg = pg
      end

      # Store an envelope for the value bound by `aad`; content_digest is SHA-256 of the
      # plaintext (a non-secret anchor). Returns the reference (a uuid String).
      def put(envelope:, aad:, content_digest:)
        connection.exec_params(
          "SELECT f1_encrypted_record_put($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) AS id",
          [
            aad.application, aad.record_type, aad.record_id, aad.purpose, aad.tenant,
            aad.schema_version, envelope.key_provider, envelope.wrapping_key_version,
            { value: envelope.serialize, format: 1 }, { value: content_digest, format: 1 }
          ]
        ).to_a.first.fetch("id")
      end

      # Fetch by reference, or nil if unknown. A destroyed record returns state
      # "destroyed" with a nil envelope; the content digest survives.
      def fetch(reference)
        row = connection.exec_params(
          "SELECT envelope_hex, state, content_digest_hex, wrapping_key_version, key_provider " \
          "FROM f1_encrypted_record_get($1)", [reference]
        ).to_a.first
        return nil if row.nil?

        Fetched.new(
          envelope: unhex(row["envelope_hex"]),
          state: row["state"],
          content_digest: unhex(row["content_digest_hex"]),
          wrapping_key_version: row["wrapping_key_version"],
          key_provider: row["key_provider"]
        )
      end

      # Record-level cryptographic erasure. Idempotent; returns :destroyed,
      # :already_destroyed or :unknown.
      def destroy(reference)
        connection.exec_params("SELECT f1_encrypted_record_destroy($1) AS outcome", [reference])
                  .to_a.first.fetch("outcome").to_sym
      end

      private

      def connection = @pg || ActiveRecord::Base.connection.raw_connection

      def unhex(hex) = hex && [hex].pack("H*")
    end
  end
end
