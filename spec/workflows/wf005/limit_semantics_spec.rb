# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workflows::Wf005::LimitSemantics do
  subject(:matrix) { described_class::MATRIX }

  it "PROOF 136 — classifies the closed twelve-dimension enum exactly once" do
    expect(matrix.keys).to eq(Workflows::Wf005::LimitDimensions::ALL)
    expect(matrix.size).to eq(12)
    expect(matrix.values).to all(be_frozen)
  end

  it "PROOF 137 — separates the four residual run-stopping dimensions from local and pacing limits" do
    expect(described_class::RUN_STOPPING_DIMENSIONS).to contain_exactly(
      "accepted_pages_per_run", "discovered_url_queue",
      "accounted_response_body_bytes_per_run", "wall_clock_run_duration"
    )
    expect(matrix.fetch("crawl_depth_from_source_root").scheduling_stop).to eq(:affected_url)
    expect(matrix.fetch("response_body_per_url").scheduling_stop).to eq(:affected_url)
    expect(matrix.fetch("redirects_per_url").scheduling_stop).to eq(:affected_url)
  end

  it "PROOF 138 — rate and concurrency are delay-only controls and cannot produce decisions" do
    %w[request_rate_per_canonical_host concurrent_requests_per_canonical_host].each do |dimension|
      row = matrix.fetch(dimension)
      expect(row.delay).to eq(:pacing)
      expect(row.hard_decision).to eq(:none)
      expect(row.decision_reason).to be_nil
      expect(row.terminal_completion_reason).to be_nil
      expect(row.coverage_effect).to eq(:unchanged)
      expect(row.affected_count_owner).to eq(:none)
    end
  end

  it "PROOF 139 — only ratified terminal dimensions promote their hard decision to the Crawl reason" do
    expect(described_class::TERMINAL_DECISION_DIMENSIONS).to contain_exactly(
      "accepted_pages_per_run", "discovered_url_queue",
      "accounted_response_body_bytes_per_run", "wall_clock_run_duration",
      "sitemap_documents_per_run", "sitemap_index_nesting_depth"
    )
    %w[crawl_depth_from_source_root response_body_per_url redirects_per_url
       connection_plus_response_time_per_request].each do |dimension|
      row = matrix.fetch(dimension)
      expect(row.decision_reason).to eq("limit_reached")
      expect(row.terminal_completion_reason).to be_nil
    end
  end

  it "PROOF 140 — sitemap context is an explicit override, not a property of every hard decision" do
    expect(matrix.fetch("response_body_per_url").sitemap_terminal_override).to be(true)
    expect(matrix.fetch("connection_plus_response_time_per_request").sitemap_terminal_override).to be(true)
    expect(matrix.fetch("crawl_depth_from_source_root").sitemap_terminal_override).to be(false)
    expect(matrix.fetch("redirects_per_url").sitemap_terminal_override).to be(false)
  end

  it "PROOF 141 — affected counts belong to the causal population at the immutable first decision" do
    expect(matrix.fetch("accounted_response_body_bytes_per_run").affected_count_owner)
      .to eq(:unselected_frontier_at_first_decision)
    expect(matrix.fetch("wall_clock_run_duration").affected_count_owner)
      .to eq(:unselected_frontier_at_first_decision)
    expect(matrix.fetch("response_body_per_url").affected_count_owner)
      .to eq(:observation_point_causal_population)
    expect(matrix.fetch("discovered_url_queue").affected_count_owner)
      .to eq(:observation_point_causal_population)
  end
end
