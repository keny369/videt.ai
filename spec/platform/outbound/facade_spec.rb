# frozen_string_literal: true

require "rails_helper"

# F-01 Shared Outbound Transport — the frozen public façade (FOUNDATION-001).
#
# The façade is the entire public surface; these examples prove it clamps caller budgets
# to the platform ceilings and delegates to the guarded internals, with the internals
# stubbed so no network is touched. End-to-end safety is proven in the resolver, client
# and TLS-connector specs; here we only assert the wiring.
RSpec.describe Platform::Outbound, type: :model do
  describe ".fetch" do
    it "clamps caller budgets to the hard ceilings and delegates to the guarded client" do
      captured = nil
      client = instance_double(Platform::Outbound::GuardedHttpClient)
      allow(Platform::Outbound::GuardedHttpClient).to receive(:new).and_return(client)
      allow(client).to receive(:get) { |url, policy:| captured = [url, policy]; :the_outcome }

      result = described_class.fetch("https://host/x", timeout_s: 999, byte_cap: 50_000_000, max_redirects: 99)

      expect(result).to eq(:the_outcome)
      url, policy = captured
      expect(url).to eq("https://host/x")
      expect(policy).to be_a(Platform::Outbound::RequestPolicy)
      expect(policy.timeout_s).to eq(Platform::Outbound::Ceilings::CONNECT_RESPONSE_TIMEOUT_MAX_S)
      expect(policy.byte_cap).to eq(Platform::Outbound::Ceilings::RESPONSE_BYTES_MAX)
      expect(policy.max_redirects).to eq(Platform::Outbound::Ceilings::REDIRECTS_MAX)
      expect(policy.allowed_ports).to eq([443])
    end

    it "passes a caller-specific policy through unchanged (S-05: 10s / 4096 / 0 redirects)" do
      captured = nil
      client = instance_double(Platform::Outbound::GuardedHttpClient)
      allow(Platform::Outbound::GuardedHttpClient).to receive(:new).and_return(client)
      allow(client).to receive(:get) { |_url, policy:| captured = policy; :ok }

      described_class.fetch("https://host/.well-known/f1-verification.txt", timeout_s: 10, byte_cap: 4096, max_redirects: 0)

      expect(captured.timeout_s).to eq(10.0)
      expect(captured.byte_cap).to eq(4096)
      expect(captured.read_limit).to eq(4097)
      expect(captured.max_redirects).to eq(0)
    end
  end

  describe ".fetch_dns_txt" do
    it "delegates to the guarded resolver's TXT lookup" do
      resolver = instance_double(Platform::Outbound::GuardedResolver)
      allow(Platform::Outbound::GuardedResolver).to receive(:new).and_return(resolver)
      allow(resolver).to receive(:resolve_txt).with("_f1.host", timeout_s: 10).and_return(:the_answer)

      expect(described_class.fetch_dns_txt("_f1.host", timeout_s: 10)).to eq(:the_answer)
    end
  end
end
