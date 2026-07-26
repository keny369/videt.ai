# frozen_string_literal: true

require "digest"

module Workflows
  module Wf003
    # The pure ownership-verification OBSERVATION engine (SCORE_EVIDENCE_MODEL.md § DNS TXT
    # Method / HTTP File Method; contracts/S-05.json MTX-028). Given a method, canonical host
    # and challenge token it performs ONE guarded outbound observation through the frozen F-01
    # façade (Platform::Outbound — the single egress surface; never a second network path) and
    # applies the ratified DNS/HTTP predicate, returning a structured, RESTRICTED-SAFE outcome:
    # the network outcome, nullable status, received byte count, the `observed_value_sha256`
    # digest (or nil), the match decision and exactly one reason code. It retains NO plaintext
    # token and NO raw DNS/HTTP content — only the digest and the enum/status fields, exactly
    # what the later verification_observation Evidence may hold.
    #
    # It performs no persistence, produces no Evidence, and transitions nothing; reservation,
    # completion, Evidence and the success commit are later S-05 sub-tranches. `outbound` is
    # injected so the whole decision is deterministic in tests with no live network.
    module VerificationObservation
      module_function

      DNS_TIMEOUT_S = 10
      HTTP_TIMEOUT_S = 10
      HTTP_BYTE_CAP = 4096 # F-01 reads up to byte_cap + 1 (4097) and flags `truncated` at oversize.
      LF = "\n".b

      # The 14 ratified observation reason codes (SCORE_EVIDENCE_MODEL.md; contracts/S-05.json).
      REASON_CODES = %w[
        matched dns_nxdomain dns_value_mismatch dns_timeout dns_temporary_failure
        http_status_mismatch http_content_mismatch http_body_too_large http_redirect_rejected
        http_timeout http_rate_limited http_server_error tls_validation_failed connection_failure
      ].freeze

      NETWORK_OUTCOMES = %w[response timeout resolver_failure connection_failure tls_failure].freeze
      MATCH_DECISIONS = %w[matched not_matched indeterminate].freeze

      # A restricted-safe observation outcome. `observed_value_sha256` is the 32-byte digest (or
      # nil); no field carries the plaintext token or raw DNS/HTTP content.
      Result = Data.define(:method, :observation_location, :network_outcome, :http_status,
                           :dns_response_code, :received_byte_count, :observed_value_sha256,
                           :match_decision, :reason_code)

      def observe(method:, canonical_host:, token:, outbound: Platform::Outbound)
        case method
        when "dns_txt" then observe_dns(canonical_host, token, outbound)
        when "http_file" then observe_http(canonical_host, token, outbound)
        else raise ArgumentError, "unsupported verification method #{method.inspect}"
        end
      end

      def dns_location(canonical_host) = "_f1-verify.#{canonical_host}"
      def http_url(canonical_host) = "https://#{canonical_host}/.well-known/f1-verification.txt"
      def expected_value(token) = "f1-verification=#{token}".b

      # ---- DNS TXT --------------------------------------------------------------

      def observe_dns(canonical_host, token, outbound)
        location = dns_location(canonical_host)
        answer = outbound.fetch_dns_txt(location, timeout_s: DNS_TIMEOUT_S)
        return dns_refusal(location, answer) if answer.refused?

        # Join character-string segments within each record (DNS semantics), in
        # resolver-returned order; every value is compared and hashed as raw bytes.
        values = answer.records.map { |segments| Array(segments).map { |s| s.to_s.b }.join }
        digest = Digest::SHA256.digest(values.join(LF))
        matched = values.any? { |v| v == expected_value(token) }

        dns_result(location,
                   reason: matched ? "matched" : "dns_value_mismatch",
                   match: matched ? "matched" : "not_matched",
                   digest:)
      end

      def dns_refusal(location, answer)
        case answer.reason
        when :absent # NXDOMAIN / no records — a definitive answer, null hash.
          dns_result(location, reason: "dns_nxdomain", match: "not_matched", digest: nil, network: "response")
        when :resolver_timeout
          dns_result(location, reason: "dns_timeout", match: "indeterminate", digest: nil, network: "timeout")
        else # :resolver_temporary_failure, :destination_host_invalid, or any other resolver-side refusal
          dns_result(location, reason: "dns_temporary_failure", match: "indeterminate", digest: nil, network: "resolver_failure")
        end
      end

      def dns_result(location, reason:, match:, digest:, network: "response")
        Result.new(method: "dns_txt", observation_location: location, network_outcome: network,
                   http_status: nil, dns_response_code: nil, received_byte_count: nil,
                   observed_value_sha256: digest, match_decision: match, reason_code: reason)
      end

      # ---- HTTP file ------------------------------------------------------------

      def observe_http(canonical_host, token, outbound)
        url = http_url(canonical_host)
        outcome = outbound.fetch(url, timeout_s: HTTP_TIMEOUT_S, byte_cap: HTTP_BYTE_CAP, max_redirects: 0)
        return http_response(url, outcome, token) if outcome.response?
        return http_result(url, reason: "http_redirect_rejected", match: "not_matched", network: "response") if outcome.rejected? && outcome.reason == :redirect_rejected

        http_result(url, **http_transport_failure(outcome))
      end

      def http_response(url, outcome, token)
        body = outcome.body.to_s.b
        digest = Digest::SHA256.digest(body)
        count = outcome.byte_count
        status = outcome.status

        return http_result(url, reason: reason_for_status(status), match: match_for_status(status),
                           status:, count:, digest:) unless status == 200
        # 200: an oversize body (F-01 flagged `truncated` at 4097) proves http_body_too_large.
        return http_result(url, reason: "http_body_too_large", match: "not_matched", status:, count:, digest:) if outcome.truncated

        # Exact UTF-8 equality after removal of at most one trailing line feed, over the raw bytes.
        trimmed = body.end_with?(LF) ? body[0...-1] : body
        content_ok = trimmed.dup.force_encoding("UTF-8").valid_encoding? && trimmed == expected_value(token)
        http_result(url, reason: content_ok ? "matched" : "http_content_mismatch",
                    match: content_ok ? "matched" : "not_matched", status:, count:, digest:)
      end

      # Non-200 status mapping (SCORE_EVIDENCE_MODEL.md): 408 -> http_timeout, 429 ->
      # http_rate_limited, 5xx -> http_server_error, every other non-200 -> http_status_mismatch.
      def reason_for_status(status)
        return "http_timeout" if status == 408
        return "http_rate_limited" if status == 429
        return "http_server_error" if (500..599).cover?(status)

        "http_status_mismatch"
      end

      # A dependency failure (timeout/rate-limit/server-error) is indeterminate; a definitive
      # non-200 (a wrong page/status) is not_matched.
      def match_for_status(status)
        [408, 429].include?(status) || (500..599).cover?(status) ? "indeterminate" : "not_matched"
      end

      # Transport-level F-01 outcomes (SCORE_EVIDENCE network outcomes). A rejected safety
      # refusal other than a redirect cannot occur for a validated HTTPS :443 host; it is mapped
      # defensively to an indeterminate connection failure.
      def http_transport_failure(outcome)
        case outcome.kind
        when :timeout then { reason: "http_timeout", match: "indeterminate", network: "timeout" }
        when :tls_failure then { reason: "tls_validation_failed", match: "indeterminate", network: "tls_failure" }
        when :resolver_failure then { reason: "connection_failure", match: "indeterminate", network: "resolver_failure" }
        else { reason: "connection_failure", match: "indeterminate", network: "connection_failure" }
        end
      end

      def http_result(url, reason:, match:, network: "response", status: nil, count: nil, digest: nil)
        Result.new(method: "http_file", observation_location: url, network_outcome: network,
                   http_status: status, dns_response_code: nil, received_byte_count: count,
                   observed_value_sha256: digest, match_decision: match, reason_code: reason)
      end
    end
  end
end
