# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf005
    # ONE resolution of a Crawl's operative limits (WORKFLOW_SPECIFICATIONS.md :390 — "the most
    # restrictive of global safety, approved entitlement, Organization, and Project limits").
    #
    # WHY THIS IS ONE PLACE. Four call sites had grown their own copy of the same eight lines —
    # `StartCrawl`, `HostGate`, `FetchContent` and `Admission` — each re-deriving the effective
    # bounds and each with its own rescue. They agreed, but nothing made them agree, and S-07-008
    # adds a fifth consumer that must not merely agree: a limit decision records the CONFIGURED
    # VALUE it was judged against (:442), so if the number in the event and the bound the scheduler
    # enforced come from two resolutions, a customer can be told they hit a limit that was never
    # applied. Resolving once and passing the result is the same discipline `StartCrawl` already
    # applies to the entitlement decision: "never a second read, so the Decision row, this context
    # and the event can never name different resolutions."
    #
    # THE CONTRIBUTING SET AND THE NAMED SET ARE THE SAME SET. A stored policy whose bounds are
    # malformed is ignored rather than guessed at (its own activation command already refuses one,
    # so falling back on the global clamp is strictly safe) — and because it did not contribute, it
    # must not appear in `definition_versions` either. Filtering the parsed bounds and the governing
    # versions together is what keeps that true; filtering them separately would let an event name a
    # policy that had no part in the number beside it.
    module EffectiveLimits
      module_function

      GLOBAL_ARTIFACT_TYPE = "global_crawl_safety"
      POLICY_ARTIFACT_TYPE = "crawl_policy"

      # The frozen ceiling is a constant, not a row (ADR-068 defers `release_artifacts`), but
      # `EventGoverningVersion` requires a `uuid`. Deriving it from the ceiling's own canonical bytes
      # gives a stable identity that changes only when the ceiling does — and one the deferred
      # release artifact can adopt without breaking the event stream.
      GLOBAL_CONTENT_SHA256 = Digest::SHA256.digest(
        Platform::CanonicalJson.encode(CrawlPolicy.normalize(CrawlPolicy::GLOBAL_CEILING))
      )
      GLOBAL_ARTIFACT_ID = Platform::DerivedUuid.v8(GLOBAL_CONTENT_SHA256)
      GLOBAL_VERSION = {
        "artifact_type" => GLOBAL_ARTIFACT_TYPE, "artifact_id" => GLOBAL_ARTIFACT_ID,
        "version" => CrawlPolicy::GLOBAL_VERSION,
        "content_sha256" => GLOBAL_CONTENT_SHA256.unpack1("H*")
      }.freeze

      # The resolved bounds plus the exact governing set that produced them.
      Resolution = Data.define(:bounds, :definition_versions) do
        # The per-fetch byte/timeout/redirect view the fetch path uses.
        def byte_bounds = ByteAccounting.bounds_from(bounds)

        # The configured value for one dimension and threshold, in the units a limit decision
        # records (:442 — "record dimension, configured value, observed value").
        def configured(dimension, threshold) = LimitDimensions.configured(dimension, bounds, threshold)

        def versions = definition_versions.map { |v| v["version"] }
      end

      GLOBAL = Resolution.new(bounds: CrawlPolicy::GLOBAL_CEILING, definition_versions: [GLOBAL_VERSION].freeze)

      # Resolve from the active `crawl_policies` rows for a Crawl's Organization and Project. The
      # rows must carry `id`, `policy_version`, `normalized_bounds` and `content_sha256`.
      def resolve(rows)
        contributing = (rows || []).filter_map do |row|
          bounds = JSON.parse(row["normalized_bounds"].to_s)
          next unless CrawlPolicy.complete?(bounds)

          [bounds, governing_version(row)]
        end
        Resolution.new(
          bounds: CrawlPolicy.most_restrictive(CrawlPolicy::GLOBAL_CEILING, *contributing.map(&:first)),
          definition_versions: sorted_unique([GLOBAL_VERSION, *contributing.map(&:last)])
        )
      rescue JSON::ParserError, TypeError
        GLOBAL
      end

      # NOTE the rescue above catches a MALFORMED STORED POLICY and nothing else. `KeyError` was in
      # the four copies this replaced, and carrying it here would have been a silent trap: a caller
      # whose query forgot `content_sha256` would raise inside `governing_version`, be swallowed, and
      # every Crawl would quietly fall back to the global clamp with no Organization or Project
      # policy applied. A reader that does not select what an event needs must fail loudly.

      def governing_version(row)
        { "artifact_type" => POLICY_ARTIFACT_TYPE, "artifact_id" => row.fetch("id"),
          "version" => row.fetch("policy_version"), "content_sha256" => hex(row.fetch("content_sha256")) }
      end

      # ":713 sorted by artifact type, ID, version, then digest and duplicate-free."
      def sorted_unique(entries)
        entries.uniq.sort_by { |e| e.values_at("artifact_type", "artifact_id", "version", "content_sha256") }.freeze
      end

      # `content_sha256` arrives as PostgreSQL's `\x…` bytea text from a raw connection and as raw
      # bytes from anywhere else. Both mean the same digest and the envelope wants lowercase hex.
      def hex(value)
        text = value.to_s
        return text.delete_prefix("\\x").downcase if text.start_with?("\\x")

        text.bytesize == 32 ? text.unpack1("H*") : text.downcase
      end
    end
  end
end
