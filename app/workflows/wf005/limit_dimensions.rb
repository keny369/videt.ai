# frozen_string_literal: true

module Workflows
  module Wf005
    # The twelve ratified limit dimensions (S-07-008; WORKFLOW_SPECIFICATIONS.md :425-438 and :442;
    # schemas/POSTGRESQL_SCHEMA.md :300; API_CONTRACTS.md `crawl_limit_decision`).
    #
    # THE NAMES ARE A CLOSED ENUM AND THEY ARE NOT THE POLICY KEYS. `crawl-policy-v1` labels a
    # dimension `accepted_pages`; a limit decision and its event must say `accepted_pages_per_run`.
    # The two vocabularies are ratified separately — the policy names in :425-438, the decision names
    # in :300 and in `API_CONTRACTS.md`'s `limit_dimension` enum — and the schema pins the second with
    # a CHECK. Mapping them in one place is what stops a decision row being written under a name the
    # event contract does not admit, which no functional test would catch because both look plausible.
    module LimitDimensions
      module_function

      # decision name => crawl-policy-v1 key. Exactly :300's enum, in its order.
      POLICY_KEYS = {
        "accepted_pages_per_run" => "accepted_pages",
        "discovered_url_queue" => "discovered_queue",
        "crawl_depth_from_source_root" => "crawl_depth",
        "accounted_response_body_bytes_per_run" => "run_response_mib",
        "response_body_per_url" => "per_url_body_mib",
        "wall_clock_run_duration" => "wall_clock_minutes",
        "redirects_per_url" => "redirects_per_url",
        "request_rate_per_canonical_host" => "request_rate_per_host",
        "concurrent_requests_per_canonical_host" => "concurrency_per_host",
        "connection_plus_response_time_per_request" => "request_timeout_seconds",
        "sitemap_documents_per_run" => "sitemap_documents",
        "sitemap_index_nesting_depth" => "sitemap_index_depth"
      }.freeze

      ALL = POLICY_KEYS.keys.freeze
      SOFT = "soft"
      HARD = "hard"
      THRESHOLDS = [SOFT, HARD].freeze

      # :442 — "A soft event fires when the observed or reserved value first equals the soft limit"
      # and "a capacity hard-limit event fires BEFORE an action would exceed the maximum".
      DECISION_VALUES = { SOFT => "soft_reached", HARD => "hard_reached" }.freeze
      # :300 — "A row check requires soft/soft_reached/null reason or hard/hard_reached/limit_reached".
      REASON_CODES = { SOFT => nil, HARD => "limit_reached" }.freeze

      # Dimensions whose values are counted MIB in policy but BYTES in the decision record. :442
      # requires the decision to carry the "configured value" and "observed value"; recording 1250
      # where the observed number is 1,310,720,000 would make the two incomparable.
      MIB_SCALED = %w[accounted_response_body_bytes_per_run response_body_per_url].freeze
      MIB = 1024 * 1024

      def known?(dimension) = POLICY_KEYS.key?(dimension.to_s)

      def policy_key(dimension) = POLICY_KEYS.fetch(dimension.to_s)

      # The configured value for a dimension, in the units the DECISION records — bytes for the byte
      # dimensions, the policy's own unit otherwise.
      def configured(dimension, bounds, threshold)
        raw = bounds.fetch(policy_key(dimension)).fetch(threshold).to_i
        MIB_SCALED.include?(dimension.to_s) ? raw * MIB : raw
      end
    end
  end
end
