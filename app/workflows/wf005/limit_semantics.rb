# frozen_string_literal: true

module Workflows
  module Wf005
    # The authoritative R5-1 classification for all twelve crawl-policy dimensions (ADR-117;
    # WORKFLOW_SPECIFICATIONS.md :442, :450, :452, :458).
    #
    # A hard decision, a scheduling stop and a terminal completion reason are THREE different facts.
    # In particular, `decision_reason_code=limit_reached` describes a `CrawlLimitReached` decision
    # event; it does not by itself select `crawls.completion_reason=limit_reached`. The old
    # `hard_limits > 0` rule erased that distinction and promoted local URL failures to run outcomes.
    module LimitSemantics
      module_function

      # Each field answers one ratified question. Symbols are internal classifications rather than
      # customer vocabulary; the only customer token here is the terminal/decision reason.
      Classification = Data.define(
        :local_disposition, :delay, :scheduling_stop, :hard_decision, :decision_reason,
        :terminal_completion_reason, :coverage_effect, :affected_count_owner,
        :sitemap_terminal_override
      ) do
        def decision_producing? = hard_decision == :produce
        def run_stopping? = %i[remaining_content excess_admission whole_run].include?(scheduling_stop)
        def terminal_forcing_decision? = terminal_completion_reason == "limit_reached"
        def default_unselected_affected? = affected_count_owner == :unselected_frontier_at_first_decision
        def abandons_unselected_frontier? = scheduling_stop == :remaining_content
      end

      LIMIT_REACHED = "limit_reached"

      MATRIX = {
        "accepted_pages_per_run" => Classification.new(
          local_disposition: :page_limit_discarded, delay: :none, scheduling_stop: :remaining_content,
          hard_decision: :produce, decision_reason: LIMIT_REACHED,
          terminal_completion_reason: LIMIT_REACHED, coverage_effect: :partial_in_denominator,
          affected_count_owner: :unselected_frontier_at_first_decision, sitemap_terminal_override: false
        ),
        "discovered_url_queue" => Classification.new(
          local_disposition: :queue_limit_discarded, delay: :none, scheduling_stop: :excess_admission,
          hard_decision: :produce, decision_reason: LIMIT_REACHED,
          terminal_completion_reason: LIMIT_REACHED, coverage_effect: :partial_in_denominator,
          affected_count_owner: :observation_point_causal_population, sitemap_terminal_override: false
        ),
        "crawl_depth_from_source_root" => Classification.new(
          local_disposition: :depth_limit_discarded, delay: :none, scheduling_stop: :affected_url,
          hard_decision: :produce, decision_reason: LIMIT_REACHED,
          terminal_completion_reason: nil, coverage_effect: :partial_in_denominator,
          affected_count_owner: :observation_point_causal_population, sitemap_terminal_override: false
        ),
        "accounted_response_body_bytes_per_run" => Classification.new(
          local_disposition: :reservation_refused, delay: :none, scheduling_stop: :remaining_content,
          hard_decision: :produce, decision_reason: LIMIT_REACHED,
          terminal_completion_reason: LIMIT_REACHED, coverage_effect: :partial_in_denominator,
          affected_count_owner: :unselected_frontier_at_first_decision, sitemap_terminal_override: false
        ),
        "response_body_per_url" => Classification.new(
          local_disposition: :content_fetch_failed_or_sitemap_skip, delay: :none,
          scheduling_stop: :affected_url, hard_decision: :produce, decision_reason: LIMIT_REACHED,
          terminal_completion_reason: nil, coverage_effect: :partial_in_denominator,
          affected_count_owner: :observation_point_causal_population, sitemap_terminal_override: true
        ),
        "wall_clock_run_duration" => Classification.new(
          local_disposition: :no_new_request_and_cancel_incomplete, delay: :none,
          scheduling_stop: :whole_run, hard_decision: :produce, decision_reason: LIMIT_REACHED,
          terminal_completion_reason: LIMIT_REACHED, coverage_effect: :partial_in_denominator,
          affected_count_owner: :unselected_frontier_at_first_decision, sitemap_terminal_override: false
        ),
        "redirects_per_url" => Classification.new(
          local_disposition: :content_fetch_failed, delay: :none, scheduling_stop: :affected_url,
          hard_decision: :produce, decision_reason: LIMIT_REACHED,
          terminal_completion_reason: nil, coverage_effect: :partial_in_denominator,
          affected_count_owner: :observation_point_causal_population, sitemap_terminal_override: false
        ),
        "request_rate_per_canonical_host" => Classification.new(
          local_disposition: :none, delay: :pacing, scheduling_stop: :delayed_only,
          hard_decision: :none, decision_reason: nil, terminal_completion_reason: nil,
          coverage_effect: :unchanged, affected_count_owner: :none, sitemap_terminal_override: false
        ),
        "concurrent_requests_per_canonical_host" => Classification.new(
          local_disposition: :none, delay: :pacing, scheduling_stop: :delayed_only,
          hard_decision: :none, decision_reason: nil, terminal_completion_reason: nil,
          coverage_effect: :unchanged, affected_count_owner: :none, sitemap_terminal_override: false
        ),
        "connection_plus_response_time_per_request" => Classification.new(
          local_disposition: :retry_then_content_fetch_failed_or_sitemap_skip, delay: :retry_schedule,
          scheduling_stop: :affected_url, hard_decision: :produce, decision_reason: LIMIT_REACHED,
          terminal_completion_reason: nil, coverage_effect: :partial_in_denominator,
          affected_count_owner: :observation_point_causal_population, sitemap_terminal_override: true
        ),
        "sitemap_documents_per_run" => Classification.new(
          local_disposition: :sitemap_candidate_skipped, delay: :none,
          scheduling_stop: :affected_sitemap_candidates, hard_decision: :produce,
          decision_reason: LIMIT_REACHED, terminal_completion_reason: LIMIT_REACHED,
          coverage_effect: :partial_in_denominator,
          affected_count_owner: :observation_point_causal_population, sitemap_terminal_override: true
        ),
        "sitemap_index_nesting_depth" => Classification.new(
          local_disposition: :sitemap_branch_skipped, delay: :none,
          scheduling_stop: :affected_sitemap_branch, hard_decision: :produce,
          decision_reason: LIMIT_REACHED, terminal_completion_reason: LIMIT_REACHED,
          coverage_effect: :partial_in_denominator,
          affected_count_owner: :observation_point_causal_population, sitemap_terminal_override: true
        )
      }.freeze

      raise "limit semantics must classify the closed dimension enum" unless MATRIX.keys == LimitDimensions::ALL

      RUN_STOPPING_DIMENSIONS = MATRIX.filter_map { |dimension, row| dimension if row.run_stopping? }.freeze
      TERMINAL_DECISION_DIMENSIONS = MATRIX.filter_map do |dimension, row|
        dimension if row.terminal_forcing_decision?
      end.freeze
      UNSELECTED_FRONTIER_STOP_DIMENSIONS = MATRIX.filter_map do |dimension, row|
        dimension if row.abandons_unselected_frontier?
      end.freeze

      def fetch(dimension) = MATRIX.fetch(dimension.to_s)
      def decision_producing?(dimension) = fetch(dimension).decision_producing?
      def terminal_forcing_decision?(dimension) = fetch(dimension).terminal_forcing_decision?
      def default_unselected_affected?(dimension) = fetch(dimension).default_unselected_affected?
      def abandons_unselected_frontier?(dimension) = fetch(dimension).abandons_unselected_frontier?
    end
  end
end
