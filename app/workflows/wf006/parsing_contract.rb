# frozen_string_literal: true

module Workflows
  module Wf006
    # The `parsing-interim-v1` job contract: the versions a ParsingJob records and the retry
    # schedule it runs under (WORKFLOW_SPECIFICATIONS.md :480-484).
    module ParsingContract
      module_function

      SCHEMA_VERSION = "parsing-interim-v1"

      # :481 "Only `parser_timeout` and `parser_dependency_unavailable` are internally
      # retryable." Every other reason — including an exhausted third attempt — is terminal
      # at the same serialized checkpoint.
      RETRYABLE = %w[parser_timeout parser_dependency_unavailable].freeze

      # :481 "one initial attempt plus two retries exactly 30 and 120 seconds after the
      # preceding failed attempt". Indexed by the attempt that just failed.
      RETRY_DELAYS_SECONDS = { 1 => 30, 2 => 120 }.freeze
      MAX_ATTEMPTS = 3

      def retryable?(reason) = RETRYABLE.include?(reason)

      # Whether a failure gets another attempt, and when. A nonretryable reason never does,
      # and neither does the third attempt of a retryable one.
      def retry_delay(reason:, attempt_number:)
        return nil unless retryable?(reason)

        RETRY_DELAYS_SECONDS[attempt_number.to_i]
      end

      def dead_letter?(reason:, attempt_number:) = retry_delay(reason:, attempt_number:).nil?
    end
  end
end
