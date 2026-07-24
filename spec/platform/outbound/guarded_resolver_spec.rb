# frozen_string_literal: true

require "rails_helper"
require "ipaddr"

# F-01 Shared Outbound Transport — the guarded DNS surface
# (FOUNDATION-001 properties 1-3; SECURITY_PERFORMANCE.md destination-safety-v1 :488-508).
#
# The DNS seam is injected, so the whole resolve/pin/classify decision is proven with
# no live network: every SSRF outcome, the address pin, and the typed failures are
# asserted against scripted answers.
# A scripted DNS double standing in for SystemResolver. It returns the stubbed answer
# verbatim (so the guard's own coercion/normalisation is exercised) or raises one of the
# guard's neutral transient errors, and records every call for assertions. Namespaced so
# the helper never leaks a generic top-level constant into the suite.
module GuardedResolverSpecSupport
  class Nameserver
    attr_reader :calls

    def initialize
      @addresses = {}
      @txt = {}
      @errors = {}
      @calls = []
    end

    def on_addresses(host, list) = (@addresses[host] = list)
    def on_txt(host, records) = (@txt[host] = records)
    def on_error(host, error) = (@errors[host] = error)

    def addresses(host, timeout_s:)
      @calls << [:addresses, host, timeout_s]
      raise @errors[host] if @errors[host]

      @addresses.fetch(host, [])
    end

    def txt(host, timeout_s:)
      @calls << [:txt, host, timeout_s]
      raise @errors[host] if @errors[host]

      @txt.fetch(host, [])
    end
  end
end

RSpec.describe Platform::Outbound::GuardedResolver, type: :model do
  let(:ns) { GuardedResolverSpecSupport::Nameserver.new }
  subject(:resolver) { described_class.new(resolver: ns) }

  def resolve(host, timeout_s: 10) = resolver.resolve(host, timeout_s:)
  def resolve_txt(host, timeout_s: 10) = resolver.resolve_txt(host, timeout_s:)

  describe "#resolve — a fully public answer is pinned" do
    it "pins the single public address" do
      ns.on_addresses("example.com", %w[93.184.216.34])
      pin = resolve("example.com")
      expect(pin).to be_a(described_class::Pin)
      expect(pin).not_to be_refused
      expect(pin.address).to eq(IPAddr.new("93.184.216.34"))
      expect(pin.candidates).to eq([IPAddr.new("93.184.216.34")])
    end

    it "pins the first address by sorted unique bytes, deterministically regardless of answer order" do
      ns.on_addresses("multi.example", %w[93.184.216.34 8.8.8.8 1.1.1.1 8.8.8.8])
      pin = resolve("multi.example")
      # sorted by packed bytes: 1.1.1.1 < 8.8.8.8 < 93.184.216.34; the duplicate collapses.
      expect(pin.candidates).to eq([IPAddr.new("1.1.1.1"), IPAddr.new("8.8.8.8"), IPAddr.new("93.184.216.34")])
      expect(pin.address).to eq(IPAddr.new("1.1.1.1"))
    end

    it "normalises an IPv4-mapped IPv6 answer to IPv4 and pins it" do
      ns.on_addresses("mapped.example", %w[::ffff:8.8.8.8])
      pin = resolve("mapped.example")
      expect(pin.address).to eq(IPAddr.new("8.8.8.8"))
    end

    it "pins across a mixed public IPv4/IPv6 answer set" do
      ns.on_addresses("dual.example", %w[8.8.8.8 2606:2800:220:1:248:1893:25c8:1946])
      pin = resolve("dual.example")
      expect(pin.candidates.length).to eq(2)
      expect(pin.address).to eq(IPAddr.new("8.8.8.8")) # 4-byte answer sorts before the 16-byte one
    end
  end

  describe "#resolve — the SSRF classifier fails closed" do
    it "rejects a mixed public + private answer as nonretryable destination_address_prohibited" do
      ns.on_addresses("rebind.example", %w[93.184.216.34 10.0.0.1])
      refusal = resolve("rebind.example")
      expect(refusal).to be_refused
      expect(refusal.reason).to eq(:destination_address_prohibited)
      expect(refusal.retryable).to be(false)
    end

    it "rejects an all-private answer" do
      ns.on_addresses("internal.example", %w[169.254.169.254])
      expect(resolve("internal.example").reason).to eq(:destination_address_prohibited)
    end

    it "rejects an empty answer (NXDOMAIN / NODATA) as an empty set" do
      ns.on_addresses("void.example", [])
      expect(resolve("void.example").reason).to eq(:destination_address_prohibited)
    end

    it "rejects an IPv4-mapped answer whose embedded IPv4 is private" do
      ns.on_addresses("sneaky.example", %w[::ffff:127.0.0.1])
      expect(resolve("sneaky.example").reason).to eq(:destination_address_prohibited)
    end

    it "fails the whole set closed when any answer is malformed" do
      ns.on_addresses("garbage.example", ["8.8.8.8", "not-an-ip"])
      expect(resolve("garbage.example").reason).to eq(:destination_address_prohibited)
    end
  end

  describe "#resolve — transient resolver failure is retryable" do
    it "maps a DNS timeout to resolver_failure" do
      ns.on_error("slow.example", described_class::Timeout.new("timed out"))
      refusal = resolve("slow.example")
      expect(refusal.reason).to eq(:resolver_failure)
      expect(refusal.retryable).to be(true)
    end

    it "maps a temporary resolver failure to resolver_failure" do
      ns.on_error("servfail.example", described_class::Temporary.new("SERVFAIL"))
      expect(resolve("servfail.example").reason).to eq(:resolver_failure)
    end
  end

  describe "#resolve — an unsafe host never reaches the resolver" do
    {
      "raw Unicode" => "exämple.com",
      "IPv4 literal" => "93.184.216.34",
      "loopback literal" => "127.0.0.1",
      "IPv6 literal" => "::1",
      "bracketed IPv6" => "[2606:2800::1]",
      "DNS-shorthand integer" => "2130706433",
      "all-digit TLD" => "example.123",
      "embedded port" => "example.com:8080",
      "embedded path" => "example.com/admin",
      "userinfo" => "user@example.com",
      "empty" => "",
      "overlong" => "#{'a' * 250}.example.com"
    }.each do |label, host|
      it "refuses #{label} as destination_host_invalid without a lookup" do
        refusal = resolve(host)
        expect(refusal).to be_refused
        expect(refusal.reason).to eq(:destination_host_invalid)
        expect(refusal.retryable).to be(false)
        expect(ns.calls).to be_empty
      end
    end

    it "refuses a non-String host" do
      expect(resolve(nil).reason).to eq(:destination_host_invalid)
    end
  end

  describe "#resolve — host canonicalisation and timeout clamping" do
    it "lowercases and strips a trailing dot before the lookup" do
      ns.on_addresses("example.com", %w[8.8.8.8])
      expect(resolve("EXAMPLE.COM.")).to be_a(described_class::Pin)
      expect(ns.calls).to eq([[:addresses, "example.com", 10.0]])
    end

    it "clamps a caller timeout above the hard ceiling down to it" do
      ns.on_addresses("example.com", %w[8.8.8.8])
      resolve("example.com", timeout_s: 999)
      expect(ns.calls.last).to eq([:addresses, "example.com", Platform::Outbound::Ceilings::DNS_TIMEOUT_MAX_S])
    end
  end

  describe "#resolve_txt — verification record lookup" do
    it "returns records in resolver order, preserving multi-segment values" do
      records = [["f1-verification=abc"], %w[seg-a seg-b]]
      ns.on_txt("_f1.example.com", records)
      answer = resolve_txt("_f1.example.com")
      expect(answer).to be_a(described_class::Txt)
      expect(answer.records).to eq([["f1-verification=abc"], %w[seg-a seg-b]])
    end

    it "treats an empty answer as :absent (nonretryable), which S-05 maps to dns_nxdomain" do
      ns.on_txt("_f1.example.com", [])
      refusal = resolve_txt("_f1.example.com")
      expect(refusal.reason).to eq(:absent)
      expect(refusal.retryable).to be(false)
    end

    it "maps a DNS timeout to :resolver_timeout (retryable), which S-05 maps to dns_timeout" do
      ns.on_error("_f1.example.com", described_class::Timeout.new("t"))
      refusal = resolve_txt("_f1.example.com")
      expect(refusal.reason).to eq(:resolver_timeout)
      expect(refusal.retryable).to be(true)
    end

    it "maps a temporary failure to :resolver_temporary_failure (retryable)" do
      ns.on_error("_f1.example.com", described_class::Temporary.new("t"))
      expect(resolve_txt("_f1.example.com").reason).to eq(:resolver_temporary_failure)
    end

    it "refuses an unsafe host without a lookup" do
      expect(resolve_txt("127.0.0.1").reason).to eq(:destination_host_invalid)
      expect(ns.calls).to be_empty
    end
  end
end
