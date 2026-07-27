# frozen_string_literal: true

require "rails_helper"

# Unit spec for the pure crawl-policy resolver/validation (S-07-001; ADR-026 review NB —
# most_restrictive is the load-bearing effective-resolution function the later fetch tranche
# consumes, so it is unit-tested here).
RSpec.describe Workflows::Wf005::CrawlPolicy do
  def ceiling = described_class::GLOBAL_CEILING
  def bounds(overrides = {})
    b = ceiling.to_h { |d, v| [d, v.dup] }
    overrides.each { |d, o| b[d] = b[d].merge(o) }
    b
  end

  describe ".complete?" do
    it "accepts the full twelve-dimension set with non-negative integer soft/hard" do
      expect(described_class.complete?(bounds)).to be(true)
    end

    it "rejects a missing dimension, an extra key, a non-integer, and a negative value" do
      expect(described_class.complete?(bounds.tap { |b| b.delete("crawl_depth") })).to be(false)
      expect(described_class.complete?(bounds.merge("extra" => { "soft" => 1, "hard" => 2 }))).to be(false)
      expect(described_class.complete?(bounds("crawl_depth" => { "soft" => 1.5, "hard" => 2 }))).to be(false)
      expect(described_class.complete?(bounds("crawl_depth" => { "soft" => -1, "hard" => 2 }))).to be(false)
    end
  end

  describe ".soft_le_hard?" do
    it "is true when soft <= hard for every dimension and false otherwise" do
      expect(described_class.soft_le_hard?(bounds)).to be(true)
      expect(described_class.soft_le_hard?(bounds("crawl_depth" => { "soft" => 9, "hard" => 8 }))).to be(false)
    end
  end

  describe ".narrows?" do
    it "is true iff every dimension is at or below the parent (equal is allowed)" do
      expect(described_class.narrows?(bounds, ceiling)).to be(true) # equal narrows
      expect(described_class.narrows?(bounds("crawl_depth" => { "soft" => 4, "hard" => 5 }), ceiling)).to be(true)
      expect(described_class.narrows?(bounds("crawl_depth" => { "soft" => 4, "hard" => 11 }), ceiling)).to be(false) # hard above
      expect(described_class.narrows?(bounds("accepted_pages" => { "soft" => 9_000, "hard" => 10_000 }), ceiling)).to be(false) # soft above
    end
  end

  describe ".most_restrictive" do
    it "takes the per-dimension minimum of soft and hard across sets (effective resolution)" do
      org = bounds("accepted_pages" => { "soft" => 5_000, "hard" => 6_000 }, "crawl_depth" => { "soft" => 6, "hard" => 8 })
      proj = bounds("accepted_pages" => { "soft" => 1_000, "hard" => 2_000 }, "crawl_depth" => { "soft" => 8, "hard" => 9 })
      eff = described_class.most_restrictive(ceiling, org, proj)
      expect(eff["accepted_pages"]).to eq("soft" => 1_000, "hard" => 2_000) # project tightest
      expect(eff["crawl_depth"]).to eq("soft" => 6, "hard" => 8)            # org tightest on both
      expect(eff["redirects_per_url"]).to eq(ceiling["redirects_per_url"])   # untouched -> global
    end

    it "never yields soft > hard for well-formed narrowed inputs, and ignores nils" do
      org = bounds("wall_clock_minutes" => { "soft" => 10, "hard" => 20 })
      eff = described_class.most_restrictive(ceiling, nil, org)
      described_class::DIMENSIONS.each { |d| expect(eff[d]["soft"]).to be <= eff[d]["hard"] }
    end
  end
end
