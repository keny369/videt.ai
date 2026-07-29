# frozen_string_literal: true

module Platform
  module Outbound
    # The single typed result of a guarded request (FOUNDATION-001 Abstraction; the
    # network-outcome enum S-05 records on verification Evidence). The transport owns
    # *safety* and reports one of a closed set of outcomes; the CALLER owns *meaning*
    # (S-05's dns/http match rules, S-07's robots/content rules) and reads the raw
    # bytes/status itself.
    #
    # kinds:
    #  :response            — a complete HTTP response was read (see status/headers/body).
    #  :timeout             — the connect-plus-response deadline was exceeded (retryable).
    #  :connection_failure  — TCP connect/read failed: refused, reset, unreachable (retryable).
    #  :tls_failure         — TLS handshake, certificate chain or hostname check failed.
    #  :resolver_failure    — DNS resolution failed transiently (retryable).
    #  :rejected            — a nonretryable safety refusal; see `reason`:
    #       :destination_address_prohibited, :destination_host_invalid,
    #       :redirect_rejected, :redirect_loop, :redirect_budget_exhausted,
    #       :redirect_policy_denied, :unsupported_scheme, :unsupported_port.
    #
    # The redirect reasons are DISTINCT because :454 requires "its exact limit reason" and :452
    # classifies them differently: `:redirect_budget_exhausted` and `:redirect_loop` are limit
    # conditions on the URL, `:redirect_rejected` is the target failing the platform's own shape
    # checks (non-HTTPS, userinfo, disallowed port, malformed Location), and
    # `:redirect_policy_denied` is the CALLER's guard refusing a hop the platform would have
    # allowed — :448's robots and Source Scope recheck.
    #
    # `body` holds the RAW received entity-body bytes (ASCII-8BIT), truncated at
    # byte_cap + 1; `truncated` is true exactly when the body reached that limit and is
    # therefore oversize. Raw bytes, header values, host addresses and DNS values are
    # surfaced to the caller but are restricted telemetry: `redacted` is the only shape
    # that may enter a log, event, audit or metric.
    Outcome = Data.define(
      :kind, :reason, :retryable,
      :status, :headers, :body, :byte_count, :truncated,
      :canonical_host, :port, :pinned_address, :final_url, :redirect_count, :latency_ms
    ) do
      def self.response(status:, headers:, body:, byte_count:, truncated:, canonical_host:, port:,
                        pinned_address:, final_url:, redirect_count:, latency_ms:)
        new(
          kind: :response, reason: nil, retryable: false,
          status:, headers: headers.freeze, body:, byte_count:, truncated:,
          canonical_host:, port:, pinned_address:, final_url:, redirect_count:, latency_ms:
        )
      end

      def self.failure(kind, reason:, retryable:, canonical_host: nil, port: nil, pinned_address: nil,
                       final_url: nil, redirect_count: 0, latency_ms: nil)
        new(
          kind:, reason:, retryable:,
          status: nil, headers: nil, body: nil, byte_count: nil, truncated: nil,
          canonical_host:, port:, pinned_address:, final_url:, redirect_count:, latency_ms:
        )
      end

      def self.timeout(**) = failure(:timeout, reason: :timeout, retryable: true, **)
      def self.connection_failure(**) = failure(:connection_failure, reason: :connection_failure, retryable: true, **)
      def self.tls_failure(**) = failure(:tls_failure, reason: :tls_failure, retryable: false, **)
      def self.resolver_failure(**) = failure(:resolver_failure, reason: :resolver_failure, retryable: true, **)
      def self.rejected(reason, **) = failure(:rejected, reason:, retryable: false, **)

      def response? = kind == :response
      def rejected? = kind == :rejected

      # The ONLY representation that may be logged/audited/metered (FOUNDATION-001
      # property 9): enums, counts, canonical host, scheme/port, latency — never a
      # header value, a body byte, a DNS value, or a raw IP address.
      def redacted
        {
          outcome: kind, reason:, status:, byte_count:, truncated:,
          canonical_host:, scheme: "https", port:, redirect_count:, latency_ms:
        }
      end
    end
  end
end
