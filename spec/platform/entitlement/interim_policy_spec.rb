# frozen_string_literal: true

require "rails_helper"

# F-05 entitlement-interim-v1 policy — the pure formula, counter windows and frozen rules
# (WORKFLOW_SPECIFICATIONS.md § Interim Entitlement Contract :519, :523, :527; DECISIONS ADR-069).
RSpec.describe Platform::Entitlement::InterimPolicy do
  describe "the frozen high-cost operation rules (WORKFLOW :527)" do
    it "carries the ratified crawl.start rule" do
      r = described_class.rule("crawl.start")
      expect(r).to include(counter_group: "crawl.start", usage_unit: "crawl_run", soft: 3, hard: 4,
                           max_execution_seconds: 65 * 60, durable_commit_point: "crawl_completed_with_valid_document")
    end

    it "carries all four high-cost operations with soft < hard" do
      expect(described_class::HIGH_COST_RULES.keys).to contain_exactly(
        "crawl.start", "reassessment.start", "ai.generate", "export.generate")
      described_class::HIGH_COST_RULES.each_value { |r| expect(r[:soft]).to be < r[:hard] }
      expect(described_class.high_cost?("crawl.start")).to be(true)
      expect(described_class.high_cost?("report.view")).to be(false)
      expect(described_class.rule("nope")).to be_nil
    end

    it "fixes the interim prestart lifetime at 15 minutes and heartbeat cadence at 5" do
      expect(described_class::PRESTART_LIFETIME_SECONDS).to eq(15 * 60)
      expect(described_class::LEASE_RENEWAL_SECONDS).to eq(15 * 60)
      expect(described_class::HEARTBEAT_CADENCE_SECONDS).to eq(5 * 60)
    end
  end

  describe ".counter_window — the half-open UTC calendar day (WORKFLOW :523)" do
    it "spans [00:00:00Z, next 00:00:00Z) for the day containing the instant" do
      s, e = described_class.counter_window(Time.utc(2026, 7, 27, 13, 45, 6))
      expect(s).to eq(Time.utc(2026, 7, 27, 0, 0, 0))
      expect(e).to eq(Time.utc(2026, 7, 28, 0, 0, 0))
    end

    it "puts the exclusive end instant in the NEXT window" do
      s, = described_class.counter_window(Time.utc(2026, 7, 28, 0, 0, 0))
      expect(s).to eq(Time.utc(2026, 7, 28, 0, 0, 0))
    end
  end

  describe ".classify — allow iff committed+reserved+requested <= hard, equality allowed (WORKFLOW :519)" do
    def c(committed, reserved, requested) = described_class.classify(committed:, active_reserved: reserved, requested:, soft: 3, hard: 4)

    it "allows within the soft limit" do
      expect(c(0, 0, 1)).to eq([:allow, "within_limit", "none"])          # total 1 < soft
      expect(c(1, 0, 1)).to eq([:allow, "within_limit", "none"])          # total 2 < soft
    end

    it "allows-with-warning at or above soft and up to (including) hard" do
      expect(c(2, 0, 1)).to eq([:allow_with_warning, "soft_limit_reached", "none"]) # total 3 == soft
      expect(c(3, 0, 1)).to eq([:allow_with_warning, "soft_limit_reached", "none"]) # total 4 == hard, allowed
      expect(c(2, 1, 1)).to eq([:allow_with_warning, "soft_limit_reached", "none"]) # reserved counts: total 4
    end

    it "blocks strictly above hard" do
      expect(c(4, 0, 1)).to eq([:block, "hard_limit_exceeded", "wait_for_window"]) # total 5 > hard
      expect(c(3, 1, 1)).to eq([:block, "hard_limit_exceeded", "wait_for_window"]) # reserved pushes total 5
    end
  end
end
