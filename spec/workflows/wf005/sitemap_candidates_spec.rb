# frozen_string_literal: true

require "rails_helper"

# S-07-006 deterministic sitemap-candidate selection (WORKFLOW_SPECIFICATIONS.md :454 — "Sitemap
# candidates are ordered by sitemap-index depth, canonical URL UTF-8 bytes, and discovering sitemap
# URL; only the first 50 distinct candidates in that order are retained").
#
# The retention rule is a SELECTION OVER A SET, not over an arrival sequence — the same distinction
# the S-07-004 review had to correct in the frontier — so these assert that a late-arriving
# lower-ordered candidate displaces a higher one rather than being dropped for arriving late.
RSpec.describe Workflows::Wf005::SitemapCandidates, type: :model do
  subject(:candidates) { described_class }

  def c(url, depth: 0, by: "") = candidates.candidate(canonical_url: url, index_depth: depth, discovering_sitemap_url: by)

  describe "the :454 ordering tuple" do
    it "orders by sitemap-index depth first" do
      set = [c("https://h.example/z", depth: 0), c("https://h.example/a", depth: 1)]
      expect(candidates.order(set).map(&:canonical_url))
        .to eq(["https://h.example/z", "https://h.example/a"])
    end

    it "orders by canonical URL UTF-8 BYTES within a depth" do
      set = [c("https://h.example/b"), c("https://h.example/a"), c("https://h.example/A")]
      # Byte order, not a collation: uppercase sorts before lowercase.
      expect(candidates.order(set).map(&:canonical_url))
        .to eq(["https://h.example/A", "https://h.example/a", "https://h.example/b"])
    end

    it "orders by discovering sitemap URL last" do
      set = [c("https://h.example/x", depth: 1, by: "https://h.example/z.xml"),
             c("https://h.example/x", depth: 1, by: "https://h.example/a.xml")]
      expect(candidates.order(set).map(&:discovering_sitemap_url))
        .to eq(["https://h.example/a.xml", "https://h.example/z.xml"])
    end

    it "is a total order, so the same set always yields the same sequence" do
      set = [c("https://h.example/b", depth: 1), c("https://h.example/a"), c("https://h.example/c", depth: 1)]
      5.times { expect(candidates.order(set.shuffle).map(&:canonical_url)).to eq(candidates.order(set).map(&:canonical_url)) }
    end
  end

  describe "distinctness" do
    it "keeps the LOWEST-ordered occurrence of a duplicated URL, not the first offered" do
      set = [c("https://h.example/dup", depth: 2, by: "https://h.example/deep.xml"),
             c("https://h.example/dup", depth: 0)]
      kept = candidates.distinct(set)
      expect(kept.size).to eq(1)
      expect(kept.first.index_depth).to eq(0)
    end
  end

  describe "the retention bound (a selection over a SET)" do
    it "retains the LOWEST 50 by the tuple and returns the overflow" do
      set = (1..60).map { |i| c(format("https://h.example/%03d", i)) }
      retained, discarded = candidates.retain(set)
      expect(retained.size).to eq(50)
      expect(discarded.size).to eq(10)
      expect(retained.first.canonical_url).to eq("https://h.example/001")
      expect(retained.last.canonical_url).to eq("https://h.example/050")
    end

    it "lets a lower-ordered LATE arrival displace a higher-ordered retained candidate" do
      # Offered in the worst possible order: the 50 highest first, then one that sorts lowest.
      set = (11..60).map { |i| c(format("https://h.example/%03d", i)) }
      retained, discarded = candidates.retain(set + [c("https://h.example/001")])
      expect(retained.map(&:canonical_url)).to include("https://h.example/001")
      expect(discarded.map(&:canonical_url)).to eq(["https://h.example/060"])
    end

    it "retains everything when the set is within the bound" do
      set = (1..5).map { |i| c("https://h.example/#{i}") }
      retained, discarded = candidates.retain(set)
      expect(retained.size).to eq(5)
      expect(discarded).to be_empty
    end

    it "uses the ratified crawl-policy-v1 bounds" do
      expect(described_class::DOCUMENT_LIMIT).to eq(50)
      expect(described_class::MAX_INDEX_DEPTH).to eq(3)
    end
  end

  describe "index nesting depth (:450 — three edges from an initial sitemap)" do
    it "admits depths up to three and refuses beyond" do
      expect(candidates.within_index_depth?(0)).to be(true)
      expect(candidates.within_index_depth?(3)).to be(true)
      expect(candidates.within_index_depth?(4)).to be(false)
    end
  end
end
