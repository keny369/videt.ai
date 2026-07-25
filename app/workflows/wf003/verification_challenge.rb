# frozen_string_literal: true

require "securerandom"

module Workflows
  module Wf003
    # The pure verification-method predicate and challenge-token construction for
    # WF-003 (PRULE-020 / MTX-071 the method set; SCORE_EVIDENCE_MODEL.md § Verification
    # Request). No tenant read, no clock and no persistence: it decides input-only
    # facts so an unsupported method is rejected before authentication and before any
    # token is generated.
    module VerificationChallenge
      module_function

      REQUEST_SCHEMA_VERSION = "verification-request-v1"

      # OD-001 (ratified, ADR-019, Option 2) — the method set is exactly these two.
      # A CHECK constraint makes any other value unrepresentable at rest; this is the
      # matching application-edge predicate that rejects it before challenge issuance.
      SUPPORTED_METHODS = %w[dns_txt http_file].freeze

      # 256 bits of cryptographically secure entropy (>= the 128-bit floor), rendered
      # as URL-safe Base64 so the token is exact ASCII and safe to place verbatim in a
      # DNS TXT value or an HTTPS file body without escaping.
      CHALLENGE_TOKEN_BYTES = 32

      def supported_method?(method) = SUPPORTED_METHODS.include?(method)

      # The command envelope must declare the supported major (mirrors the WF-004
      # `supported_schema?` gate).
      def supported_schema?(schema_version) = schema_version.to_s.split(".").first == "1"

      def generate_challenge_token = SecureRandom.urlsafe_base64(CHALLENGE_TOKEN_BYTES)
    end
  end
end
