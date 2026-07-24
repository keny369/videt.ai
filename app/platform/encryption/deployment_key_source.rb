# frozen_string_literal: true

require "base64"
require "json"

module Platform
  module Encryption
    # Resolves wrapping-key MATERIAL out of band, by (provider, version) — NEVER from the
    # database (FOUNDATION-002 §KeyProvider; owner refinement 2026-07-25: the DB holds only
    # metadata). The Genesis backing is a platform-managed versioned key ring supplied
    # through deployment configuration (env `F1_ENCRYPTION_KEY_RING`: JSON of
    # provider -> version -> base64(32 bytes)), in the session-key style. The shape is
    # vendor-neutral: a later deployment may back it with a cloud secret manager without
    # any consumer change, and no cloud vendor is hard-coded here.
    #
    # A missing version resolves to nil, which the provider surfaces as :key_unavailable —
    # fail closed, never a guessed key.
    class DeploymentKeySource
      ENV_VAR = "F1_ENCRYPTION_KEY_RING"

      def initialize(keys: nil)
        @keys = normalize(keys || load_from_environment)
      end

      # 32 raw key bytes for (provider, version), or nil if the deployment source has none.
      def key_bytes(provider, version)
        @keys.dig(provider.to_s, version.to_s)
      end

      private

      def load_from_environment
        raw = ENV[ENV_VAR].to_s
        return {} if raw.empty?

        JSON.parse(raw).transform_values do |versions|
          versions.transform_values { |b64| Base64.strict_decode64(b64) }
        end
      rescue JSON::ParserError, ArgumentError => e
        raise Error.new(:provider_failure, "malformed #{ENV_VAR}: #{e.class.name}")
      end

      def normalize(keys)
        keys.each_with_object({}) do |(provider, versions), out|
          out[provider.to_s] = versions.each_with_object({}) do |(version, bytes), inner|
            inner[version.to_s] = bytes.to_s.b
          end
        end
      end
    end
  end
end
