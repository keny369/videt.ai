# frozen_string_literal: true

require "uri"
require "set"

module Platform
  module Outbound
    # The single guarded HTTP(S) surface for F-01 Shared Outbound Transport
    # (FOUNDATION-001). Every platform-originated HTTP request — S-05 verification file
    # observation, S-07 crawl, any future provider — goes through here, so SSRF
    # prevention, pinning, redirect revalidation and the byte cap are properties of the
    # platform, not of each caller. The client owns *safety*; it returns a typed Outcome
    # and the caller owns *meaning*.
    #
    # For each connection attempt, in order:
    #   parse+validate target (HTTPS, allowed port, no userinfo)
    #   -> GuardedResolver: canonical host -> classified, pinned public address
    #   -> Connector: connect to EXACTLY the pinned address, verify the peer equals it,
    #      send the canonical host as Host header + TLS SNI, verify the certificate
    #   -> HttpResponseReader: read the response, capping decoded body at byte_cap + 1
    #   -> a 3xx + Location is never followed blindly: it triggers a NEW full resolution
    #      and re-validation of the redirect target, bounded by max_redirects and loop
    #      detection; a redirect over budget, to a loop, or to an unsafe target is a
    #      nonretryable redirect_rejected.
    #
    # The socket/TLS layer is an injected Connector seam so the whole orchestration is
    # deterministic under test with no live network; production wires TlsConnector.
    class GuardedHttpClient
      # Raised by the Connector seam (translated from socket/OpenSSL errors) and by the
      # reader; the client rescues them all and maps each to exactly one Outcome. A raw
      # socket or OpenSSL error never escapes the adapter.
      class ConnectionError < StandardError; end
      class TlsError < StandardError; end
      class TimeoutError < StandardError; end
      class PeerMismatchError < StandardError; end
      class ProtocolError < StandardError; end

      REDIRECT_STATUSES = [301, 302, 303, 307, 308].freeze

      Redirect = Data.define(:location)

      Target = Data.define(:uri) do
        def canonical_host = uri.host.downcase.sub(/\.\z/, "")
        def port = uri.port
        def request_uri = uri.request_uri
        def userinfo? = !uri.userinfo.nil?
        def key = "#{canonical_host}:#{port}#{request_uri}"
        def to_s = uri.to_s
      end

      def initialize(resolver: nil, connector: nil)
        @resolver = resolver
        @connector = connector
      end

      # Perform a guarded GET. Returns an Outcome; never raises for a network/safety
      # condition (only for a genuine programming error).
      def get(url, policy:)
        started = monotonic
        parsed = parse_target(url, policy)
        return parsed if parsed.is_a?(Outcome)

        follow(parsed, policy, started)
      end

      private

      def resolver = @resolver ||= GuardedResolver.new
      def connector = @connector ||= TlsConnector.new

      def follow(target, policy, started)
        visited = Set.new
        redirects = 0

        loop do
          if visited.include?(target.key)
            return reject(:redirect_loop, target, redirects, started)
          end

          visited << target.key
          result = attempt(target, policy, redirects, started)
          return result unless result.is_a?(Redirect)
          if redirects >= policy.max_redirects
            return reject(:redirect_budget_exhausted, target, redirects, started)
          end

          nxt = resolve_redirect(target, result.location, policy, redirects, started)
          return nxt if nxt.is_a?(Outcome)

          # SEARCH_CRAWL_RETRIEVAL.md § Destination And HTTP Safety makes "canonicalize and
          # recheck Source Scope and robots policy" STEP 1 of the indivisible per-redirect
          # sequence, and :448 says redirects are rechecked "BEFORE FOLLOWING". Those policies
          # belong to the caller — the platform cannot evaluate them — so a caller that supplies
          # a guard gets it consulted here, before the next connection is attempted. Retrospective
          # validation of the FINAL url would not do: the disallowed intermediate would already
          # have been fetched.
          unless policy.redirect_allowed?(nxt.uri)
            return reject(:redirect_policy_denied, nxt, redirects, started)
          end

          redirects += 1
          target = nxt
        end
      end

      # One connection attempt against one target. Returns a terminal Outcome, or a
      # Redirect signal for the caller to revalidate.
      def attempt(target, policy, redirects, started)
        pin = resolver.resolve(target.canonical_host, timeout_s: policy.timeout_s)
        return refusal_outcome(pin, target, redirects, started) if pin.refused?

        deadline = monotonic + policy.timeout_s
        connection =
          begin
            connector.open(pinned: pin.address, host: target.canonical_host, port: target.port, deadline:)
          rescue TimeoutError
            return Outcome.timeout(**failure_meta(target, pin, redirects, started))
          rescue TlsError
            return Outcome.tls_failure(**failure_meta(target, pin, redirects, started))
          rescue PeerMismatchError, ConnectionError
            return Outcome.connection_failure(**failure_meta(target, pin, redirects, started))
          end

        exchange(target, pin, connection, policy, deadline, redirects, started)
      end

      def exchange(target, pin, connection, policy, deadline, redirects, started)
        connection.write(request_bytes(target, policy))
        raw = HttpResponseReader.read(connection, deadline:, read_limit: policy.read_limit)

        if REDIRECT_STATUSES.include?(raw.status) && raw.headers["location"]
          Redirect.new(location: raw.headers["location"])
        else
          Outcome.response(
            status: raw.status, headers: raw.headers, body: raw.body,
            byte_count: raw.byte_count, truncated: raw.truncated,
            canonical_host: target.canonical_host, port: target.port, pinned_address: pin.address,
            final_url: target.to_s, redirect_count: redirects, latency_ms: ms_since(started)
          )
        end
      rescue TimeoutError
        Outcome.timeout(**failure_meta(target, pin, redirects, started))
      rescue ProtocolError, ConnectionError
        Outcome.connection_failure(**failure_meta(target, pin, redirects, started))
      ensure
        safe_close(connection)
      end

      def request_bytes(target, policy)
        [
          "GET #{target.request_uri} HTTP/1.1",
          "Host: #{target.canonical_host}",
          "User-Agent: #{policy.user_agent}",
          "Accept: */*",
          # identity: no content-coding, so the byte cap measures the body the caller
          # would consume and no decompression can bypass it.
          "Accept-Encoding: identity",
          "Connection: close",
          "", ""
        ].join("\r\n").b
      end

      # Parse and validate the initial URL. Returns a Target, or a nonretryable Outcome.
      def parse_target(url, policy)
        uri = URI.parse(url.to_s)
        return reject_now(:unsupported_scheme) unless uri.is_a?(URI::HTTPS)
        return reject_now(:destination_host_invalid) if uri.host.nil? || uri.host.empty? || !uri.userinfo.nil?
        return reject_now(:unsupported_port) unless policy.port_allowed?(uri.port)

        Target.new(uri:)
      rescue URI::InvalidURIError
        reject_now(:destination_host_invalid)
      end

      # Resolve and validate a redirect target against the current URL. Any problem —
      # relative-join failure, non-HTTPS, userinfo, disallowed port, invalid host — is a
      # nonretryable `redirect_rejected`; the prior host's decision is never inherited.
      #
      # A LOOP and an EXHAUSTED BUDGET carry their own reasons rather than sharing this one.
      # WORKFLOW_SPECIFICATIONS.md :454 requires a limit to record "its EXACT limit reason", and
      # :452 classifies them differently — a redirect to `http://` is a rejected target, not an
      # eleventh-redirect limit hit, and a caller filing them together cannot tell the two apart.
      def resolve_redirect(current, location, policy, redirects, started)
        uri = URI.join(current.uri, location.to_s)
        bad = uri.scheme != "https" || uri.host.nil? || uri.host.empty? ||
              !uri.userinfo.nil? || !policy.port_allowed?(uri.port)
        return reject(:redirect_rejected, current, redirects, started) if bad

        Target.new(uri:)
      rescue URI::Error, ArgumentError
        reject(:redirect_rejected, current, redirects, started)
      end

      def refusal_outcome(refusal, target, redirects, started)
        case refusal.reason
        when :resolver_failure
          Outcome.resolver_failure(**failure_meta(target, nil, redirects, started))
        when :destination_host_invalid
          reject(:destination_host_invalid, target, redirects, started)
        else # :destination_address_prohibited
          reject(:destination_address_prohibited, target, redirects, started)
        end
      end

      def reject(reason, target, redirects, started)
        Outcome.rejected(reason, canonical_host: target.canonical_host, port: target.port,
                                 final_url: target.to_s, redirect_count: redirects, latency_ms: ms_since(started))
      end

      def reject_now(reason)
        Outcome.rejected(reason)
      end

      def failure_meta(target, pin, redirects, started)
        {
          canonical_host: target.canonical_host, port: target.port, pinned_address: pin&.address,
          final_url: target.to_s, redirect_count: redirects, latency_ms: ms_since(started)
        }
      end

      def safe_close(connection)
        connection&.close
      rescue StandardError
        nil
      end

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      def ms_since(started) = ((monotonic - started) * 1000).round
    end
  end
end
