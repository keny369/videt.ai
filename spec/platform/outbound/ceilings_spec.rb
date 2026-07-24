# frozen_string_literal: true

require "rails_helper"

# F-01 Shared Outbound Transport — the hard platform ceilings
# (FOUNDATION-001 properties 4/5/6; SECURITY_PERFORMANCE.md PRULE-008 :550-553).
# A caller may ask for something tighter, never wider: every clamp fails to the ceiling.
RSpec.describe Platform::Outbound::Ceilings, type: :model do
  describe "the ratified hard bounds" do
    it "pins the crawl-policy hard ceilings" do
      expect(described_class::CONNECT_RESPONSE_TIMEOUT_MAX_S).to eq(15.0)
      expect(described_class::DNS_TIMEOUT_MAX_S).to eq(15.0)
      expect(described_class::RESPONSE_BYTES_MAX).to eq(10 * 1024 * 1024)
      expect(described_class::REDIRECTS_MAX).to eq(10)
      expect(described_class::ALLOWED_PORTS).to eq([443])
      expect(described_class::DEFAULT_PORT).to eq(443)
    end
  end

  describe ".clamp_positive (timeouts)" do
    it "passes a tighter caller value through unchanged" do
      expect(described_class.clamp_positive(10, 15.0)).to eq(10.0)
    end

    it "reduces a value above the ceiling to the ceiling" do
      expect(described_class.clamp_positive(999, 15.0)).to eq(15.0)
    end

    it "falls back to the ceiling for a non-positive or NaN value (still bounded)" do
      expect(described_class.clamp_positive(0, 15.0)).to eq(15.0)
      expect(described_class.clamp_positive(-5, 15.0)).to eq(15.0)
      expect(described_class.clamp_positive(Float::NAN, 15.0)).to eq(15.0)
    end
  end

  describe ".clamp_bytes" do
    it "passes a tighter cap through and reduces an over-ceiling cap" do
      expect(described_class.clamp_bytes(4096)).to eq(4096)
      expect(described_class.clamp_bytes(50 * 1024 * 1024)).to eq(10 * 1024 * 1024)
    end

    it "treats a negative cap as zero (a body-free probe), never unbounded" do
      expect(described_class.clamp_bytes(-1)).to eq(0)
      expect(described_class.clamp_bytes(0)).to eq(0)
    end
  end

  describe ".clamp_redirects" do
    it "passes a tighter budget through and reduces an over-ceiling budget" do
      expect(described_class.clamp_redirects(0)).to eq(0)
      expect(described_class.clamp_redirects(5)).to eq(5)
      expect(described_class.clamp_redirects(50)).to eq(10)
    end

    it "treats a negative budget as zero" do
      expect(described_class.clamp_redirects(-1)).to eq(0)
    end
  end
end
