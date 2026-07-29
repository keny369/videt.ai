# frozen_string_literal: true

module Workflows
  module Wf005
    # The ratified per-fetch retry schedule (WORKFLOW_SPECIFICATIONS.md :444), shared by every WF-005
    # fetch limb so there is ONE implementation rather than a copy per request kind.
    #
    # :444 — "A fetch receives one initial attempt plus at most two retries for timeout, `408`, `429`,
    # or `5xx`. Retry delays are exactly 30 seconds after completion of the first failed attempt and
    # 120 seconds after completion of the second failed attempt. A valid integer `Retry-After` from 1
    # through 120 seconds replaces that retry's delay; every other value is ignored. Other `4xx`,
    # policy denial, invalid URL, and content validation errors are non-retryable."
    module FetchRetryPolicy
      module_function

      MAX_ATTEMPTS = 3
      DELAYS_S = { 1 => 30, 2 => 120 }.freeze
      RETRY_AFTER_MIN_S = 1
      RETRY_AFTER_MAX_S = 120
      RETRYABLE_STATUSES = [408, 429].freeze

      # Is this outcome retryable under :444? A transport failure defers to the adapter's own
      # judgement; a response is retryable only for the four named conditions.
      def retryable?(outcome)
        unless outcome.respond_to?(:response?) && outcome.response?
          return outcome.respond_to?(:retryable) && outcome.retryable
        end

        status = outcome.status.to_i
        RETRYABLE_STATUSES.include?(status) || (500..599).cover?(status)
      end

      # The delay before the retry that follows `attempt` (the attempt that just failed), in
      # milliseconds: the fixed schedule, or a valid `Retry-After` when the response supplied one.
      def delay_ms(attempt, outcome)
        seconds = retry_after_seconds(outcome) || DELAYS_S.fetch(attempt.to_i, DELAYS_S.values.last)
        seconds * 1000
      end

      # "A valid INTEGER Retry-After from 1 through 120 seconds ... every other value is ignored" —
      # which includes 0, values above 120, negatives, and the HTTP-date form.
      def retry_after_seconds(outcome)
        return nil unless outcome.respond_to?(:headers) && outcome.headers.is_a?(::Hash)

        raw = outcome.headers.find { |k, _v| k.to_s.downcase == "retry-after" }&.last.to_s
        return nil unless /\A\d+\z/.match?(raw)

        value = raw.to_i
        value.between?(RETRY_AFTER_MIN_S, RETRY_AFTER_MAX_S) ? value : nil
      end
    end
  end
end
