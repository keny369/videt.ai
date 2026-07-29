# frozen_string_literal: true

require "rails_helper"

# S-07-007 byte accounting (WORKFLOW_SPECIFICATIONS.md :436/:442).
#
# The two rules this asserts are the ones a plausible-looking implementation gets wrong:
#
#   * `accounted` is the MAXIMUM of the two accounting paths, not the received count. A response
#     that arrives as 2 KiB of gzip and expands to 40 MiB costs the run 40 MiB; measuring the wire
#     alone would let it through for 2 KiB.
#   * a body of EXACTLY the maximum is allowed and a body of maximum + 1 is not. Both stop the
#     reader in the same place, so `truncated` cannot distinguish them — the sentinel byte can.
RSpec.describe Workflows::Wf005::ByteAccounting, type: :model do
  subject(:accounting) { described_class }

  let(:cap) { described_class::PER_URL_CEILING }

  describe "the ratified bounds" do
    it "reads the crawl-policy-v1 dimensions rather than restating them" do
      expect(described_class::PER_URL_CEILING).to eq(10 * 1024 * 1024)
      expect(described_class::PER_URL_TARGET).to eq(8 * 1024 * 1024)
      expect(described_class::RUN_CEILING).to eq(1_250 * 1024 * 1024)
      expect(described_class::RUN_TARGET).to eq(1_000 * 1024 * 1024)
    end
  end

  describe "accounted bytes are the MAXIMUM of the two paths (:436)" do
    it "accounts a compressed body at its EXPANDED size" do
      m = accounting.measure(received: 2048, expanded: 40 * 1024, ceiling: 1024 * 1024)
      expect(m.accounted).to eq(40 * 1024)
    end

    it "accounts an uncompressed body at its RECEIVED size" do
      m = accounting.measure(received: 40 * 1024, expanded: 40 * 1024, ceiling: 1024 * 1024)
      expect(m.accounted).to eq(40 * 1024)
    end

    it "accounts the larger path when the transport path is the larger one" do
      m = accounting.measure(received: 9000, expanded: 10, ceiling: 1024 * 1024)
      expect(m.accounted).to eq(9000)
    end

    it "treats an absent expanded count as 'one accounting path', not as zero" do
      # Reporting 0 for the decoded path and taking the max would be harmless; taking the MINIMUM,
      # or averaging, would not. This pins the interpretation.
      expect(accounting.measure(received: 5000, ceiling: 1024 * 1024).accounted).to eq(5000)
    end
  end

  describe "the sentinel byte distinguishes exact-maximum from over-limit (:442)" do
    it "ALLOWS a body of exactly the maximum, with no probe" do
      m = accounting.measure(received: cap)
      expect(m.over_limit?).to be(false)
      expect(m.probe_bytes).to eq(0)
      expect(m.accounted).to eq(cap)
    end

    it "FAILS a body one byte past the maximum" do
      m = accounting.measure(received: cap + 1)
      expect(m.over_limit?).to be(true)
      expect(m.probe_bytes).to eq(1)
    end

    it "never lets a probe byte enter the accounted total" do
      # ":442 — limit_probe_bytes are detection telemetry, not accepted/accounted capacity."
      m = accounting.measure(received: cap + 1)
      expect(m.accounted).to eq(cap)
    end

    it "counts AT MOST ONE probe per accounting path, so at most two in total" do
      both = accounting.measure(received: cap + 1, expanded: cap + 1)
      expect(both.probe_bytes).to eq(2)
      one = accounting.measure(received: 10, expanded: cap + 1)
      expect(one.probe_bytes).to eq(1)
      expect(one.over_limit?).to be(true)
    end

    it "fails on EITHER path being over, not only the received one" do
      # The decompression-bomb shape: small on the wire, over-limit once decoded.
      m = accounting.measure(received: 2048, expanded: cap + 1)
      expect(m.over_limit?).to be(true)
      expect(m.accounted).to eq(cap)
    end
  end

  describe "reservation sizing (:442 — 'reserves UP TO the per-URL maximum from the REMAINING budget')" do
    it "reserves the per-URL maximum when the run has ample budget" do
      expect(accounting.reservation(remaining: described_class::RUN_CEILING)).to eq(cap)
    end

    it "reserves only what REMAINS when the run is nearly spent" do
      expect(accounting.reservation(remaining: 3 * 1024 * 1024)).to eq(3 * 1024 * 1024)
    end

    it "reserves nothing when the budget is exhausted, which is the caller's signal" do
      expect(accounting.reservation(remaining: 0)).to eq(0)
      expect(accounting.reservation(remaining: -5_000)).to eq(0)
    end
  end

  describe "effective bounds are the most restrictive (:390)" do
    it "narrows to a Project policy that tightened either dimension" do
      narrowed = Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING.merge(
        "per_url_body_mib" => { "soft" => 1, "hard" => 2 },
        "run_response_mib" => { "soft" => 5, "hard" => 6 }
      )
      bounds = accounting.bounds_from(narrowed)
      expect(bounds.per_url).to eq(2 * 1024 * 1024)
      expect(bounds.per_run).to eq(6 * 1024 * 1024)
    end

    it "uses the global ceiling as the outermost clamp" do
      expect(described_class::GLOBAL_BOUNDS.per_url).to eq(cap)
      expect(described_class::GLOBAL_BOUNDS.per_run).to eq(described_class::RUN_CEILING)
    end
  end
end
