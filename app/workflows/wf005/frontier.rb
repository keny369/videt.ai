# frozen_string_literal: true

require "digest"

module Workflows
  module Wf005
    # The S-07-004 crawl frontier: candidate admission, deduplication and the deterministic dequeue
    # (WORKFLOW_SPECIFICATIONS.md :454; SEARCH_CRAWL_RETRIEVAL.md § Frontier And Deterministic
    # Selection; contracts/S-07.json MTX-030 concurrency/persistence_model).
    #
    # It is a technical execution surface, not a product aggregate — MTX-030 forbids promoting the
    # frontier to a domain entity, so nothing here emits a domain event or transitions a Crawl.
    # It is called INSIDE the caller's transaction, under the caller's proved Organization context,
    # and it takes the per-Crawl frontier lock because both deduplication and the 20,000-candidate
    # retention bound are order-dependent decisions.
    #
    # Scope of THIS tranche: the frontier structure, the canonical order, deduplication with
    # collision handling, the discovered-queue bound, ROOT seeding, and the dequeue claim. Sitemap
    # candidates (S-07-006) and link candidates (S-07-007) enter through the same `offer` surface
    # when those tranches build discovery; robots admission (S-07-005) fills the two nullable
    # `robots_*` columns. No fetch happens here and no network call exists on this path.
    class Frontier
      # `crawl-policy-v1` discovered-queue hard bound (WORKFLOW_SPECIFICATIONS.md :425-438, :454).
      # The soft bound (16,000) is an observability threshold owned by S-07-008, which emits
      # `CrawlSoftLimitApproaching`; the frontier enforces only the retention rule.
      DISCOVERED_QUEUE_HARD = Wf005::CrawlPolicy::GLOBAL_CEILING.fetch("discovered_queue").fetch("hard")

      # The normalization contract the canonical URL was produced under. S-06 owns the canonicalizer
      # (PRULE-021); S-07 consumes it and records which version admitted each candidate.
      CANONICALIZATION_VERSION = "source-scope-interim-v1"

      Seeded = Data.define(:admitted, :pinned_total, :excluded_inactive) do
        # True when the pinned set has shrunk since queue time — the customer disabled or removed a
        # Source between queueing and execution.
        def excluded_any? = excluded_inactive.positive?
      end

      Offered = Data.define(:disposition, :entry_id, :reason) do
        def admitted? = disposition == :admitted
        def duplicate? = disposition == :duplicate
        def discarded? = disposition == :discarded
      end

      def initialize(store, ids:, correlation_id:)
        @store = store
        @ids = ids
        @correlation_id = correlation_id
      end

      # Seed the ordered ROOT frontier for an accepted start (SEARCH_CRAWL_RETRIEVAL.md § Crawl
      # Admission And Snapshot step 6, "creates ordered root frontier entries").
      #
      # ONE entry per pinned Source THAT IS STILL ACTIVE. The intersection is mandatory, not an
      # optimisation: `crawl_sources` is immutable and records queue-time membership, so seeding
      # from it alone would crawl a Source the customer has since disabled or removed on queue-time
      # authority (owner decision HD-S07-FU4-FU5). Roots are seeded in the Volume I root order and
      # go straight to `queued` — a root is admitted by the accepted start itself.
      def seed_roots(organization_id:, project_id:, crawl_id:, now:)
        @store.lock_frontier(crawl_id)
        pinned_total = @store.pinned_source_count(organization_id, crawl_id)
        sources = @store.active_pinned_sources(organization_id, crawl_id)
        order = @store.next_enqueue_order(organization_id, crawl_id)

        sources.each_with_index do |source, index|
          insert(organization_id:, project_id:, crawl_id:, now:, state: "queued",
                 source_id: source["source_id"], canonical_url: source["canonical_root_uri"],
                 origin: "root", depth: 0, discovering_document_url: "", link_position: 0,
                 parent_entry_id: nil, scope_policy_id: source["scope_policy_id"],
                 scope_policy_version: source["scope_policy_version"], enqueue_order: order + index,
                 collision_ordinal: 0, reason: nil)
        end

        Seeded.new(admitted: sources.size, pinned_total:, excluded_inactive: pinned_total - sources.size)
      end

      # Offer a discovered candidate. Returns :admitted (a new retained entry), :duplicate (an
      # occurrence recorded against the entry that already holds the identity) or :discarded (the
      # discovered-queue bound). The caller has already decided the candidate is in scope.
      def offer(organization_id:, project_id:, crawl_id:, source_id:, canonical_url:, origin:,
                depth:, now:, discovering_document_url: "", link_position: 0, parent_entry_id: nil,
                scope_policy_id:, scope_policy_version:)
        @store.lock_frontier(crawl_id)
        preimage = canonical_url.to_s.unicode_normalize(:nfc).b
        digest = Digest::SHA256.digest(preimage)

        existing = @store.entries_for_digest(organization_id, crawl_id, digest)
        # Byte-equal preimage => the SAME candidate. Deduplication "retains the first candidate in
        # this order" (:454), so the later discovery becomes an occurrence and never a second entry.
        same = existing.find { |row| unhex(row["preimage"]) == preimage }
        if same
          return record_occurrence(organization_id:, project_id:, crawl_id:, source_id:, now:,
                                   frontier_entry_id: same["id"], canonical_url:, digest:,
                                   discovering_document_url:, link_position:,
                                   referrer_entry_id: parent_entry_id)
        end

        # Digest match with a DIFFERENT preimage is a SHA-256 collision. It must never merge two
        # candidates: allocate the next ordinal and retain both, each with its own full preimage.
        collision_ordinal = existing.empty? ? 0 : existing.map { |r| r["collision_ordinal"].to_i }.max + 1

        # The retention bound. Admitted candidates beyond the hard discovered-queue limit are
        # recorded as `queue_limit_discarded` rather than dropped, so the coverage denominator can
        # still account for them (:452 "plus every in-scope candidate discarded by a Crawl limit").
        over_limit = @store.admitted_count(organization_id, crawl_id) >= DISCOVERED_QUEUE_HARD
        state = over_limit ? "discarded" : "queued"
        reason = over_limit ? IdentityAccess::Infrastructure::CrawlFrontierStore::QUEUE_LIMIT_DISCARDED : nil

        id = insert(organization_id:, project_id:, crawl_id:, now:, state:, source_id:, canonical_url:,
                    origin:, depth:, discovering_document_url:, link_position:, parent_entry_id:,
                    scope_policy_id:, scope_policy_version:,
                    enqueue_order: @store.next_enqueue_order(organization_id, crawl_id),
                    collision_ordinal:, reason:, preimage:, digest:)

        Offered.new(disposition: over_limit ? :discarded : :admitted, entry_id: id, reason:)
      end

      # Claim the next candidate in canonical dequeue order, or nil when the frontier is drained.
      def claim_next(organization_id:, crawl_id:, now:)
        @store.claim_next(organization_id, crawl_id, now)
      end

      private

      def record_occurrence(organization_id:, project_id:, crawl_id:, source_id:, now:,
                            frontier_entry_id:, canonical_url:, digest:, discovering_document_url:,
                            link_position:, referrer_entry_id:)
        @store.insert_occurrence(
          id: @ids.generate, now:, correlation_id: @correlation_id, organization_id:, project_id:,
          crawl_id:, frontier_entry_id:, source_id:, referrer_entry_id:,
          occurrence_url: canonical_url, digest:, discovering_document_url:, link_position:,
          occurrence_order: @store.next_occurrence_order(organization_id, crawl_id),
          duplicate_reason: IdentityAccess::Infrastructure::CrawlFrontierStore::DUPLICATE_DISCOVERY
        )
        Offered.new(disposition: :duplicate, entry_id: frontier_entry_id, reason: nil)
      end

      # rubocop:disable Metrics/ParameterLists
      def insert(organization_id:, project_id:, crawl_id:, now:, state:, source_id:, canonical_url:,
                 origin:, depth:, discovering_document_url:, link_position:, parent_entry_id:,
                 scope_policy_id:, scope_policy_version:, enqueue_order:, collision_ordinal:, reason:,
                 preimage: nil, digest: nil)
        id = @ids.generate
        preimage ||= canonical_url.to_s.unicode_normalize(:nfc).b
        digest ||= Digest::SHA256.digest(preimage)
        @store.insert_entry(
          id:, now:, correlation_id: @correlation_id, organization_id:, project_id:, crawl_id:,
          source_id:, canonical_url:, preimage:, digest:, collision_ordinal:, origin:, depth:,
          discovering_document_url:, link_position:, parent_entry_id:,
          canonicalization_version: CANONICALIZATION_VERSION, scope_policy_id:, scope_policy_version:,
          enqueue_order:, state:, reason:,
          dequeue_key: FrontierOrder.dequeue_key(
            depth:, origin:, canonical_url:, discovering_document_url:, link_position:, entry_id: id
          )
        )
        id
      end
      # rubocop:enable Metrics/ParameterLists

      # `bytea` comes back as a hex-escaped string on a plain read.
      def unhex(value)
        return value if value.nil?
        return [value.sub(/\A\\x/, "")].pack("H*") if value.is_a?(::String) && value.start_with?("\\x")

        value.b
      end
    end
  end
end
