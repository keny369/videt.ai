# frozen_string_literal: true

require "ipaddr"

module Platform
  module Outbound
    # The SSRF egress classifier for F-01 Shared Outbound Transport
    # (FOUNDATION-001; SECURITY_PERFORMANCE.md `destination-safety-v1` :487-499).
    #
    # A destination is allowed only when EVERY resolved address is public
    # global-unicast. Prohibited space is enumerated, not inferred, and mixed
    # public/prohibited answers fail closed — so a host that resolves to one public
    # and one private address is rejected, which is exactly the DNS-rebinding and
    # split-horizon defence the connector relies on.
    #
    # This class is pure: it takes already-resolved addresses and decides. Actual
    # resolution and connection live in the resolver and HTTP client, which call
    # this before every attempt, retry and redirect. Raw addresses are restricted
    # telemetry (:508) and never appear in Evidence or customer output.
    module AddressPolicy
      module_function

      REASON = "destination_address_prohibited"

      # IPv4 prohibited ranges (:493-495), enumerated. `169.254.169.254` is inside
      # link-local 169.254.0.0/16 and is called out by the contract; the /16 covers it.
      PROHIBITED_V4 = [
        "0.0.0.0/8",        # unspecified / "this network"
        "10.0.0.0/8",       # private
        "172.16.0.0/12",    # private
        "192.168.0.0/16",   # private
        "100.64.0.0/10",    # carrier-grade NAT
        "127.0.0.0/8",      # loopback
        "169.254.0.0/16",   # link-local (incl. 169.254.169.254)
        "192.0.0.0/24",     # IETF protocol assignments
        "192.0.2.0/24",     # documentation (TEST-NET-1)
        "198.51.100.0/24",  # documentation (TEST-NET-2)
        "203.0.113.0/24",   # documentation (TEST-NET-3)
        "198.18.0.0/15",    # benchmarking
        "224.0.0.0/4",      # multicast
        "240.0.0.0/4",      # reserved (incl. 255.255.255.255 broadcast)
      ].map { |c| IPAddr.new(c) }.freeze

      # IPv6 prohibited ranges (:495-497). IPv4-mapped is converted to IPv4 first
      # (below) and evaluated against the v4 rules, so it is not listed here.
      PROHIBITED_V6 = [
        "::/128",       # unspecified
        "::1/128",      # loopback
        "100::/64",     # discard-only
        "2001:db8::/32", # documentation
        "fc00::/7",     # unique-local
        "fe80::/10",    # link-local
        "ff00::/8",     # multicast
      ].map { |c| IPAddr.new(c) }.freeze

      # IPv6 global unicast is 2000::/3; everything outside it is non-global and
      # therefore prohibited (:496-497 "reserved/non-global ranges").
      GLOBAL_UNICAST_V6 = IPAddr.new("2000::/3")

      # Nonretryable rejection reason, or nil when every address is allowed.
      # An empty answer, or ANY prohibited address, rejects the whole set
      # (:490-491, :499 "mixed public and prohibited answers fail closed").
      def reject_reason(addresses)
        list = Array(addresses)
        return REASON if list.empty?
        return REASON unless list.all? { |addr| allowed?(addr) }

        nil
      end

      # True only for a public global-unicast address. Accepts a String or IPAddr.
      def allowed?(address)
        ip = address.is_a?(IPAddr) ? address : IPAddr.new(address.to_s)
        ip = to_v4_if_mapped(ip)
        ip.ipv4? ? allowed_v4?(ip) : allowed_v6?(ip)
      rescue IPAddr::Error
        false
      end

      def allowed_v4?(ip)
        PROHIBITED_V4.none? { |range| range.include?(ip) }
      end

      def allowed_v6?(ip)
        GLOBAL_UNICAST_V6.include?(ip) && PROHIBITED_V6.none? { |range| range.include?(ip) }
      end

      # Normalize IPv4-mapped IPv6 (::ffff:a.b.c.d) to IPv4 so it is judged by the
      # v4 rules (:489, :495 "IPv4-mapped after conversion").
      def to_v4_if_mapped(ip)
        return ip unless ip.ipv6?

        mapped = ip.ipv4_mapped? rescue false
        mapped ? ip.native : ip
      end
    end
  end
end
