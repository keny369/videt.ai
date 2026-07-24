# frozen_string_literal: true

module Platform
  module Encryption
    # The closed, typed failure set for F-02 Envelope Encryption (FOUNDATION-002 §Failure
    # model). Every crypto failure is one of REASONS — there is no untyped raise and no
    # fallback path. The loggable representation (`redacted`) is the reason symbol alone:
    # it never carries key material, plaintext, ciphertext, or AAD values, and neither
    # does the exception message (raise sites pass only non-secret detail such as a class
    # name or a version id).
    class Error < StandardError
      REASONS = %i[
        key_unavailable
        key_version_unknown
        key_retired_for_encryption
        key_destroyed
        malformed_envelope
        unsupported_format
        unsupported_algorithm
        unsupported_key_provider
        authentication_failed
        aad_mismatch
        random_source_failure
        provider_failure
      ].freeze

      attr_reader :reason

      def initialize(reason, detail = nil)
        raise ArgumentError, "unknown encryption failure #{reason.inspect}" unless REASONS.include?(reason)

        @reason = reason
        super(detail ? "#{reason}: #{detail}" : reason.to_s)
      end

      # The ONLY representation that may enter a log, event, audit or metric.
      def redacted = { error: "encryption_error", reason: }
    end
  end
end
