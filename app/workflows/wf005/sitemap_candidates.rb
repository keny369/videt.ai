# frozen_string_literal: true

module Workflows
  module Wf005
    # Deterministic sitemap-candidate selection (S-07-006; WORKFLOW_SPECIFICATIONS.md :454 —
    # "Sitemap candidates are ordered by sitemap-index depth, canonical URL UTF-8 bytes, and
    # discovering sitemap URL; only the first 50 distinct candidates in that order are retained").
    #
    # PURE. The ordering is a total function of the candidate tuple, so the same declared set always
    # produces the same retained set, whatever order the documents were discovered or fetched in.
    #
    # THE RETENTION RULE IS A SELECTION OVER A SET, not over an arrival sequence — the same shape the
    # S-07-004 review had to correct in the frontier. "The first 50 distinct candidates IN THAT ORDER"
    # means the 50 LOWEST by the tuple, so a late-arriving lower-ordered candidate displaces a higher
    # one rather than being dropped for arriving late. `retain` therefore always sorts the whole
    # candidate set before truncating; it never truncates an append.
    module SitemapCandidates
      module_function

      # `crawl-policy-v1` (:425-438): sitemap documents soft 40 / hard 50; index depth soft 2 / hard 3.
      DOCUMENT_LIMIT = CrawlPolicy::GLOBAL_CEILING.fetch("sitemap_documents").fetch("hard")
      MAX_INDEX_DEPTH = CrawlPolicy::GLOBAL_CEILING.fetch("sitemap_index_depth").fetch("hard")

      # A candidate is identified by its canonical URL; `index_depth` is how many sitemap-index edges
      # were followed to reach it (0 for a robots-declared or default sitemap), and
      # `discovering_sitemap_url` is the index that named it ("" at depth 0).
      Candidate = Data.define(:canonical_url, :index_depth, :discovering_sitemap_url) do
        # Volume I's tuple, with the string fields compared as UTF-8 BYTES (:454).
        def sort_key = [index_depth.to_i, canonical_url.to_s.b, discovering_sitemap_url.to_s.b]
      end

      def candidate(canonical_url:, index_depth: 0, discovering_sitemap_url: "")
        Candidate.new(canonical_url:, index_depth:, discovering_sitemap_url:)
      end

      # The ratified order.
      def order(candidates) = candidates.sort_by(&:sort_key)

      # Distinct by canonical URL, keeping the LOWEST-ordered occurrence of each — "the first 50
      # DISTINCT candidates in that order". Deduplication happens after ordering so that which
      # duplicate survives is decided by the tuple, not by arrival.
      def distinct(candidates)
        order(candidates).each_with_object([]) do |candidate, kept|
          kept << candidate unless kept.any? { |k| k.canonical_url == candidate.canonical_url }
        end
      end

      # The retained set and the overflow, as [retained, discarded]. The overflow is returned rather
      # than dropped because :452 keeps limit-discarded candidates accountable.
      def retain(candidates, limit: DOCUMENT_LIMIT)
        ordered = distinct(candidates)
        [ordered.first(limit), ordered.drop(limit)]
      end

      # :450 — "A sitemap index may nest through three edges from an initial sitemap." A child at a
      # depth beyond the bound is not followed; the caller records the limit rather than the child.
      def within_index_depth?(index_depth) = index_depth.to_i <= MAX_INDEX_DEPTH
    end
  end
end
