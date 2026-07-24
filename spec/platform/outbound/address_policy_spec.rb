# frozen_string_literal: true

require "rails_helper"

# F-01 Shared Outbound Transport — the SSRF address classifier
# (FOUNDATION-001; SECURITY_PERFORMANCE.md destination-safety-v1 :487-499).
#
# Pure, deterministic, no network: given already-resolved addresses, decide
# whether the destination is public global-unicast. This is the security heart of
# every guarded outbound connection, so its range coverage is exhaustive per
# category and its fail-closed behaviour is asserted directly.
RSpec.describe Platform::Outbound::AddressPolicy, type: :model do
  describe "public global-unicast is allowed" do
    it "allows public IPv4 and IPv6 addresses" do
      %w[8.8.8.8 1.1.1.1 93.184.216.34 203.0.114.1 2606:2800:220:1:248:1893:25c8:1946 2400:cb00::1]
        .each { |ip| expect(described_class.allowed?(ip)).to be(true), "expected #{ip} allowed" }
    end

    it "allows an IPv4-mapped IPv6 address whose IPv4 is public" do
      expect(described_class.allowed?("::ffff:8.8.8.8")).to be(true)
    end
  end

  describe "prohibited IPv4 space is rejected, enumerated by category" do
    {
      "unspecified/this-network" => "0.0.0.0",
      "private-10" => "10.1.2.3", "private-172" => "172.16.9.9", "private-192" => "192.168.1.1",
      "carrier-grade-nat" => "100.64.0.1",
      "loopback" => "127.0.0.1",
      "link-local" => "169.254.10.10",
      "cloud-metadata (link-local)" => "169.254.169.254",
      "protocol-assignment" => "192.0.0.1",
      "documentation-1" => "192.0.2.5", "documentation-2" => "198.51.100.5", "documentation-3" => "203.0.113.5",
      "benchmarking" => "198.18.0.1",
      "multicast" => "224.0.0.1",
      "reserved" => "240.0.0.1",
      "broadcast" => "255.255.255.255"
    }.each do |label, ip|
      it "rejects #{label} (#{ip})" do
        expect(described_class.allowed?(ip)).to be(false)
      end
    end
  end

  describe "prohibited IPv6 space is rejected, enumerated by category" do
    {
      "unspecified" => "::", "loopback" => "::1", "discard-only" => "100::1",
      "documentation" => "2001:db8::1", "unique-local" => "fc00::1", "link-local" => "fe80::1",
      "multicast" => "ff02::1", "nat64/non-global" => "64:ff9b::1"
    }.each do |label, ip|
      it "rejects #{label} (#{ip})" do
        expect(described_class.allowed?(ip)).to be(false)
      end
    end

    it "rejects an IPv4-mapped IPv6 address whose IPv4 is private (converted first)" do
      expect(described_class.allowed?("::ffff:10.0.0.1")).to be(false)
      expect(described_class.allowed?("::ffff:127.0.0.1")).to be(false)
    end
  end

  describe "reject_reason over a resolved set" do
    it "returns nil only when every address is public global-unicast" do
      expect(described_class.reject_reason(%w[8.8.8.8 1.1.1.1])).to be_nil
    end

    it "fails closed on an empty answer" do
      expect(described_class.reject_reason([])).to eq("destination_address_prohibited")
    end

    it "fails closed when public and prohibited answers are mixed" do
      expect(described_class.reject_reason(%w[8.8.8.8 10.0.0.1])).to eq("destination_address_prohibited")
      expect(described_class.reject_reason(%w[93.184.216.34 169.254.169.254])).to eq("destination_address_prohibited")
    end
  end

  describe "malformed input is rejected, never raised" do
    it "treats an unparseable address as not allowed" do
      expect(described_class.allowed?("not-an-ip")).to be(false)
      expect(described_class.reject_reason(["not-an-ip"])).to eq("destination_address_prohibited")
    end
  end
end
