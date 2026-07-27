# frozen_string_literal: true

module Workflows
  module Wf005
    # The interim Crawl Policy `crawl-policy-v1` (WORKFLOW_SPECIFICATIONS.md § Interim Crawl
    # Policy :423-458; contracts/S-07.json MTX-030/MTX-059 PRULE-008). It holds the twelve
    # ratified numeric dimensions and the FROZEN GLOBAL SAFETY CEILING — the widest envelope,
    # which "cannot be weakened" and which the release service would activate (deferred with
    # `release_artifacts`, DECISIONS ADR-068; owner-approved interim, HD-S07-D1). Organization
    # and Project policies (the dedicated `crawl_policies` table) may only NARROW this ceiling.
    #
    # Migration path (owner-approved, ADR-068): when `release_artifacts` is built the global
    # ceiling becomes a release-owned data row superseding this constant with NO behavioural
    # change — the resolver already treats it as the un-weakenable outermost bound.
    #
    # Every dimension is "lower is more restrictive": narrowing means every proposed value is
    # at or below the parent's, and soft never above hard.
    module CrawlPolicy
      SCHEMA_VERSION = "crawl-policy-v1"

      # Ordered canonical dimension keys (the twelve of PRULE-008). `unit` is documentary;
      # byte/duration dimensions are stored in the units the policy table records (MiB,
      # minutes, seconds) and converted at fetch time by later tranches.
      DIMENSIONS = %w[
        accepted_pages discovered_queue crawl_depth run_response_mib per_url_body_mib
        wall_clock_minutes redirects_per_url request_rate_per_host concurrency_per_host
        request_timeout_seconds sitemap_documents sitemap_index_depth
      ].freeze

      # The frozen global safety ceiling: {dimension => {"soft" => Integer, "hard" => Integer}}
      # (WORKFLOW_SPECIFICATIONS.md :425-438). soft <= hard for every dimension.
      GLOBAL_CEILING = {
        "accepted_pages"          => { "soft" => 8_000,  "hard" => 10_000 },
        "discovered_queue"        => { "soft" => 16_000, "hard" => 20_000 },
        "crawl_depth"             => { "soft" => 8,       "hard" => 10 },
        "run_response_mib"        => { "soft" => 1_000,   "hard" => 1_250 },
        "per_url_body_mib"        => { "soft" => 8,       "hard" => 10 },
        "wall_clock_minutes"      => { "soft" => 45,      "hard" => 60 },
        "redirects_per_url"       => { "soft" => 5,       "hard" => 10 },
        "request_rate_per_host"   => { "soft" => 1,       "hard" => 2 },
        "concurrency_per_host"    => { "soft" => 2,       "hard" => 4 },
        "request_timeout_seconds" => { "soft" => 10,      "hard" => 15 },
        "sitemap_documents"       => { "soft" => 40,      "hard" => 50 },
        "sitemap_index_depth"     => { "soft" => 2,       "hard" => 3 }
      }.freeze
      GLOBAL_VERSION = "crawl-policy-v1-global"

      module_function

      # True iff `bounds` is a complete, structurally valid set of the twelve dimensions, each
      # with non-negative integer soft/hard. (soft<=hard and narrowing are separate checks so
      # each maps to its own error reason.)
      def complete?(bounds)
        return false unless bounds.is_a?(::Hash) && bounds.keys.sort == DIMENSIONS.sort

        DIMENSIONS.all? do |d|
          v = bounds[d]
          v.is_a?(::Hash) && integer?(v["soft"]) && integer?(v["hard"]) && v["soft"] >= 0 && v["hard"] >= 0
        end
      end

      # True iff soft <= hard for every dimension (assumes complete?).
      def soft_le_hard?(bounds)
        DIMENSIONS.all? { |d| bounds[d]["soft"] <= bounds[d]["hard"] }
      end

      # True iff `bounds` is at or below `parent` on every dimension, both soft and hard
      # (narrowing-only; lower is more restrictive). Assumes both are well-formed.
      def narrows?(bounds, parent)
        DIMENSIONS.all? do |d|
          bounds[d]["soft"] <= parent[d]["soft"] && bounds[d]["hard"] <= parent[d]["hard"]
        end
      end

      # The most-restrictive (per-dimension minimum of soft and hard) of any number of
      # well-formed bound sets — the effective resolution (WORKFLOW:390 "most restrictive of
      # global safety, ... Organization, and Project limits").
      def most_restrictive(*sets)
        sets = sets.compact
        DIMENSIONS.to_h do |d|
          [d, { "soft" => sets.map { |s| s[d]["soft"] }.min, "hard" => sets.map { |s| s[d]["hard"] }.min }]
        end
      end

      # The bounds normalized to the canonical dimension order (for deterministic hashing).
      def normalize(bounds)
        DIMENSIONS.to_h { |d| [d, { "soft" => bounds[d]["soft"], "hard" => bounds[d]["hard"] }] }
      end

      def integer?(value) = value.is_a?(::Integer)
    end
  end
end
