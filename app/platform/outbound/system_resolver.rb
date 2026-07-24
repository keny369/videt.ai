# frozen_string_literal: true

require "resolv"
require "ipaddr"

module Platform
  module Outbound
    # The production DNS seam behind GuardedResolver — the ONE place `Resolv` is used
    # in the whole application (FOUNDATION-001 property 10; enforced by the outbound
    # architecture fitness spec). It performs pure DNS queries: `Resolv::DNS` does not
    # read `/etc/hosts` and does no `inet_aton`-style numeric-shorthand parsing, so a
    # host either has real A/AAAA/TXT records or it does not.
    #
    # It returns raw answers (IPAddr list; TXT segment lists) and translates the two
    # transient Resolv failures into the neutral GuardedResolver::Timeout / ::Temporary
    # the guard rescues. NXDOMAIN / NODATA is not a failure: `getresources` returns an
    # empty array, which the guard reads as an empty answer (fail-closed for a
    # connection; :absent for TXT). No live DNS runs in the deterministic suite; this
    # thin wrapper is exercised only in production, so it holds no branching logic.
    class SystemResolver
      def addresses(host, timeout_s:)
        with_dns(timeout_s) do |dns|
          v4 = dns.getresources(host, Resolv::DNS::Resource::IN::A)
          v6 = dns.getresources(host, Resolv::DNS::Resource::IN::AAAA)
          (v4 + v6).map { |record| IPAddr.new(record.address.to_s) }
        end
      end

      def txt(host, timeout_s:)
        with_dns(timeout_s) do |dns|
          dns.getresources(host, Resolv::DNS::Resource::IN::TXT).map { |record| record.strings.map(&:dup) }
        end
      end

      private

      def with_dns(timeout_s)
        dns = Resolv::DNS.new
        dns.timeouts = timeout_s
        yield dns
      rescue Resolv::ResolvTimeout => e
        raise GuardedResolver::Timeout, e.message
      rescue Resolv::ResolvError => e
        raise GuardedResolver::Temporary, e.message
      ensure
        dns&.close
      end
    end
  end
end
