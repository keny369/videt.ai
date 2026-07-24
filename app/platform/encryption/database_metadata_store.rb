# frozen_string_literal: true

module Platform
  module Encryption
    # Reads key-ring METADATA through the SECURITY DEFINER boundary — never the
    # f1_encryption_key_versions table, which carries no runtime grant. The runtime holds
    # EXECUTE on the two read functions only; it cannot see the table and cannot mutate the
    # ring. Bound parameters via exec_params (the established infrastructure convention).
    class DatabaseMetadataStore
      Record = Data.define(:state, :fingerprint)

      def initialize(pg: nil)
        @pg = pg
      end

      # The active wrapping-key version for a provider, or nil.
      def active_version(provider)
        row = connection.exec_params(
          "SELECT f1_encryption_active_version($1) AS version", [provider.to_s]
        ).to_a.first
        value = row && row["version"]
        value unless value.to_s.empty?
      end

      # The state + non-secret fingerprint (32 raw bytes) of one version, or nil if unknown.
      def describe(provider, version)
        row = connection.exec_params(
          "SELECT state, fingerprint_hex FROM f1_encryption_describe_version($1, $2)",
          [provider.to_s, version.to_s]
        ).to_a.first
        return nil if row.nil? || row["state"].nil?

        Record.new(state: row["state"], fingerprint: decode_hex(row["fingerprint_hex"]))
      end

      private

      def connection = @pg || ActiveRecord::Base.connection.raw_connection

      def decode_hex(hex) = hex && [hex].pack("H*")
    end
  end
end
