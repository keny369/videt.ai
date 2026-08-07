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
        # THE WALL-CLOCK BOUNDARY FOR THE WHOLE OPERATION, FIXED ONCE (FU-43). Everything below
        # measures against this instant: it is never recomputed, so no hop can extend it.
        total_deadline = started + policy.total_timeout_s
        parsed = parse_target(url, policy)
        return parsed if parsed.is_a?(Outcome)

        follow(parsed, policy, started, total_deadline)
      end

      private

      def resolver = @resolver ||= GuardedResolver.new
      def connector = @connector ||= TlsConnector.new

      # What is left of the total budget, in seconds. Negative once it is spent.
      def remaining(total_deadline) = total_deadline - monotonic

      def follow(target, policy, started, total_deadline)
        visited = Set.new
        redirects = 0

        loop do
          if visited.include?(target.key)
            return reject(:redirect_loop, target, redirects, started)
          end

          visited << target.key
          result = attempt(target, policy, redirects, started, total_deadline)
          return result unless result.is_a?(Redirect)
          if redirects >= policy.max_redirects
            return reject(:redirect_budget_exhausted, target, redirects, started)
          end

          # THE BUDGET IS CHECKED BEFORE THE NEXT HOP IS EVEN RESOLVED (FU-43). A redirect chain
          # used to re-arm the caller's timeout at every hop, so a request bounded at N seconds
          # could run (max_redirects + 1) x N — measured at 11.1x, and the reason `deadline_at`
          # was not a real boundary. Stopping here rather than inside the next attempt means the
          # exhausted budget costs no DNS lookup and no connection.
          return Outcome.timeout(**failure_meta(target, nil, redirects, started)) if remaining(total_deadline) <= 0

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
      def attempt(target, policy, redirects, started, total_deadline)
        # EVERY OPERATION SPENDS THE SAME BUDGET (FU-43). The resolver call used to be handed the
        # caller's full `timeout_s` and the connect/read deadline a fresh one after it, so a single
        # attempt could cost 2x the caller's number before a redirect was even considered.
        left = remaining(total_deadline)
        return Outcome.timeout(**failure_meta(target, nil, redirects, started)) if left <= 0

        pin = resolver.resolve(target.canonical_host, timeout_s: policy.effective_timeout_s(left))
        return refusal_outcome(pin, target, redirects, started) if pin.refused?

        connect(target, pin, policy, redirects, started, total_deadline)
      end

      # A dual-stack host resolves to several addresses and the resolver pins ONE of them
      # (`ordered.first`, which sorts IPv6 before IPv4). On a network with no route to
      # that family the connection is unreachable and the host was, until this method,
      # permanently unfetchable through the platform: every crawl of it failed closed at
      # robots.txt with `connection_failure`, on a host any browser reaches.
      #
      # So an UNREACHABLE address falls through to the next candidate. This weakens
      # nothing. The candidates are the same answer from the same lookup, and
      # `GuardedResolver` already refused the whole set unless every member classified as
      # public (a mixed set fails closed), so candidate two is exactly as safe as
      # candidate one. There is no re-resolution — the DNS-rebinding backstop is
      # untouched — and each attempt still verifies that the transport peer equals the
      # address it was told to use.
      #
      # ONLY unreachability falls through. A TLS failure, a peer mismatch or a timeout is
      # a property of the destination or a safety signal, not of the route, and retrying
      # elsewhere would either hide it or spend the budget twice over. The shared
      # `total_deadline` is never recomputed, so the whole fallback still lives inside the
      # caller's one wall-clock boundary (FU-43).
      CONNECT_CANDIDATE_LIMIT = 4

      def connect(target, pin, policy, redirects, started, total_deadline)
        addresses = connect_order(pin)
        addresses.each do |address|
          left = remaining(total_deadline)
          return Outcome.timeout(**failure_meta(target, pin, redirects, started)) if left <= 0

          # The connect + read deadline is the earlier of the per-attempt ceiling and the total
          # boundary, so the subordinate ceiling can only ever make a request tighter.
          deadline = monotonic + policy.effective_timeout_s(left)
          connection =
            begin
              connector.open(pinned: address, host: target.canonical_host, port: target.port, deadline:)
            rescue TimeoutError
              return Outcome.timeout(**failure_meta(target, pin, redirects, started))
            rescue TlsError
              return Outcome.tls_failure(**failure_meta(target, pin, redirects, started))
            rescue PeerMismatchError
              return Outcome.connection_failure(**failure_meta(target, pin, redirects, started))
            rescue ConnectionError
              next
            end

          return exchange(target, pin, connection, policy, deadline, redirects, started)
        end

        Outcome.connection_failure(**failure_meta(target, pin, redirects, started))
      end

      # The pinned address first, then the rest of the same classified answer. Bounded so
      # a host with many records cannot turn one request into many connections; the bound
      # is on ATTEMPTS, while the wall-clock bound remains the caller's total deadline.
      def connect_order(pin)
        ([pin.address] + Array(pin.candidates)).uniq(&:hton).first(CONNECT_CANDIDATE_LIMIT)
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
