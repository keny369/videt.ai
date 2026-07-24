# frozen_string_literal: true

require "ipaddr"

module Platform
  module Outbound
    # The guarded DNS surface for F-01 Shared Outbound Transport
    # (FOUNDATION-001 properties 1-3; SECURITY_PERFORMANCE.md destination-safety-v1
    # :488-508). It turns a canonical host into a single PINNED public address that a
    # connection may use, and it resolves TXT records for S-05 dns_txt verification.
    # It owns *safety*; the caller owns *meaning* (S-05 maps :absent to dns_nxdomain,
    # compares TXT values; the resolver never interprets them).
    #
    # What "guarded" means here:
    #  - the host is enforced ASCII-canonical before any lookup (no raw Unicode,
    #    no IP-literal or DNS-shorthand bypass of resolution);
    #  - an empty answer or ANY non-public-global-unicast answer rejects the whole
    #    set as nonretryable destination_address_prohibited (fail-closed, mixed
    #    answers included) — the AddressPolicy decision;
    #  - the allowed answers are normalised, de-duplicated and sorted by address
    #    bytes, and the FIRST is pinned for the attempt so the HTTP client connects
    #    to exactly one classified address and can verify the transport peer equals it.
    #
    # Pure orchestration over an injected DNS seam (SystemResolver in production, a
    # double in tests) so the whole decision is deterministic with no live network.
    # TXT records carry the verification challenge token; this class never logs them.
    class GuardedResolver
      # A pinned connection target. `address` is the single IPAddr the attempt must
      # connect to; `candidates` is the full sorted-unique allowed set (diagnostics).
      Pin = Data.define(:address, :candidates) do
        def refused? = false
      end

      # A successful TXT answer: records in resolver-returned order, each an array of
      # raw character-string segments (S-05 joins/hashes them; the resolver does not).
      Txt = Data.define(:records) do
        def refused? = false
      end

      # A typed refusal. `reason` is a symbol; `retryable` says whether a later
      # attempt could succeed. Address-path reasons: :destination_host_invalid,
      # :destination_address_prohibited (both nonretryable), :resolver_failure
      # (retryable). TXT-path reasons: :destination_host_invalid, :absent (nonretryable),
      # :resolver_timeout, :resolver_temporary_failure (retryable).
      Refusal = Data.define(:reason, :retryable) do
        def refused? = true
      end

      # Raised by the DNS seam and rescued here; a raw Resolv error never escapes.
      class Timeout < StandardError; end
      class Temporary < StandardError; end

      HOST_MAX_BYTES = 253
      # Authority punctuation that must never appear in a bare canonical host
      # (scheme/path/query/fragment/userinfo/port/IPv6 brackets). Control chars,
      # space and DEL are rejected separately by code point.
      FORBIDDEN_HOST_PUNCTUATION = "/@?#[]:"

      def initialize(resolver: nil)
        @resolver = resolver
      end

      # Resolve a connection target to a single pinned public address.
      # Returns Pin on success, or Refusal.
      def resolve(host, timeout_s:)
        canonical = canonical_host(host)
        return Refusal.new(reason: :destination_host_invalid, retryable: false) if canonical.nil?

        timeout = Ceilings.clamp_positive(timeout_s, Ceilings::DNS_TIMEOUT_MAX_S)
        addresses =
          begin
            resolver.addresses(canonical, timeout_s: timeout)
          rescue Timeout, Temporary
            return Refusal.new(reason: :resolver_failure, retryable: true)
          end

        classified = normalize_all(addresses)
        # A malformed member or an empty/any-prohibited/mixed set fails closed.
        return prohibited if classified.nil?
        return prohibited if AddressPolicy.reject_reason(classified)

        ordered = classified.uniq(&:hton).sort_by(&:hton)
        Pin.new(address: ordered.first, candidates: ordered.freeze)
      end

      # Resolve TXT records for the canonical host (S-05 dns_txt). Returns Txt on
      # success, or Refusal. Unlike an address lookup there is no connection and thus
      # no pinning: the SSRF surface is the configured recursive resolver, not the
      # customer host, so AddressPolicy does not apply to a record lookup.
      def resolve_txt(host, timeout_s:)
        canonical = canonical_host(host)
        return Refusal.new(reason: :destination_host_invalid, retryable: false) if canonical.nil?

        timeout = Ceilings.clamp_positive(timeout_s, Ceilings::DNS_TIMEOUT_MAX_S)
        records =
          begin
            resolver.txt(canonical, timeout_s: timeout)
          rescue Timeout
            return Refusal.new(reason: :resolver_timeout, retryable: true)
          rescue Temporary
            return Refusal.new(reason: :resolver_temporary_failure, retryable: true)
          end

        return Refusal.new(reason: :absent, retryable: false) if Array(records).empty?

        Txt.new(records: freeze_records(records))
      end

      private

      def resolver
        @resolver ||= SystemResolver.new
      end

      def prohibited
        Refusal.new(reason: :destination_address_prohibited, retryable: false)
      end

      # Enforce the ASCII canonical host before any lookup (FOUNDATION-001 property 2).
      # Returns the canonical host string, or nil to refuse. Rejects raw Unicode, any
      # authority punctuation, IP literals, and DNS-shorthand IPv4 (a final all-digit
      # label such as `2130706433` or `1.2.3.4` that a permissive resolver could turn
      # into a private address, bypassing resolution). The address classifier is the
      # real guard; these checks close the paths that would skip it.
      def canonical_host(host)
        return nil unless host.is_a?(String) && host.ascii_only?

        h = host.downcase.sub(/\.\z/, "")
        return nil if h.empty? || h.bytesize > HOST_MAX_BYTES
        return nil if forbidden_host_chars?(h)
        return nil if ip_literal?(h)

        final_label = h.split(".").last
        return nil unless final_label && final_label.match?(/[A-Za-z]/)

        h
      end

      def forbidden_host_chars?(host)
        host.each_char.any? do |char|
          code = char.ord
          code <= 0x20 || code == 0x7f || FORBIDDEN_HOST_PUNCTUATION.include?(char)
        end
      end

      def ip_literal?(string)
        IPAddr.new(string)
        true
      rescue IPAddr::Error
        false
      end

      # Normalise each answer to its canonical IPAddr (IPv4-mapped IPv6 -> IPv4), so
      # pinning and de-duplication use one representation. Returns nil if any member is
      # malformed, so a single bad answer fails the whole set closed.
      def normalize_all(addresses)
        out = []
        Array(addresses).each do |raw|
          ip = coerce(raw)
          return nil if ip.nil?

          out << ip
        end
        out
      end

      def coerce(raw)
        ip = raw.is_a?(IPAddr) ? raw : IPAddr.new(raw.to_s)
        (ip.ipv6? && ipv4_mapped?(ip)) ? ip.native : ip
      rescue IPAddr::Error
        nil
      end

      def ipv4_mapped?(ip)
        ip.ipv4_mapped?
      rescue StandardError
        false
      end

      def freeze_records(records)
        records.map { |segments| Array(segments).map { |s| s.dup.freeze }.freeze }.freeze
      end
    end
  end
end
