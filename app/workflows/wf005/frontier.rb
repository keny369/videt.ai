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
      DISCOVERED_QUEUE_HARD = Wf005::CrawlPolicy::GLOBAL_CEILING.fetch("discovered_queue").fetch("hard")
      # :438's depth bound. ":442 — a URL deeper than 10 fails that URL"; :456 keeps it in the
      # coverage denominator as "an in-scope candidate discarded by a Crawl limit", which is why it
      # is retained as a `discarded` row rather than dropped.
      CRAWL_DEPTH_HARD = Wf005::CrawlPolicy::GLOBAL_CEILING.fetch("crawl_depth").fetch("hard")

      QUEUE_DIMENSION = "discovered_url_queue"
      DEPTH_DIMENSION = "crawl_depth_from_source_root"

      # The normalization contract the canonical URL was produced under. S-06 owns the canonicalizer
      # (PRULE-021); S-07 consumes it and records which version admitted each candidate.
      CANONICALIZATION_VERSION = "source-scope-interim-v1"

      # Volume I reason vocabulary (:454 "record all later candidates as `queue_limit_discarded`";
      # SEARCH_CRAWL_RETRIEVAL "every duplicate discovery"). These are DOMAIN constants, so they live
      # on the domain surface and the persistence adapter reads them from here, not the reverse.
      QUEUE_LIMIT_DISCARDED = "queue_limit_discarded"
      DEPTH_LIMIT_DISCARDED = "depth_limit_discarded"
      DUPLICATE_DISCOVERY = "duplicate_discovery"

      Seeded = Data.define(:admitted, :pinned_total, :excluded_inactive) do
        # True when the pinned set has shrunk since queue time — the customer disabled or removed a
        # Source between queueing and execution.
        def excluded_any? = excluded_inactive.positive?
      end

      # `evicted_entry_id` names the previously-admitted candidate this one displaced at the queue
      # bound, and `repositioned` is true when a duplicate discovery moved the retained entry to a
      # lower frontier position. Both are nil/false on the ordinary path.
      Offered = Data.define(:disposition, :entry_id, :reason, :evicted_entry_id, :repositioned) do
        def admitted? = disposition == :admitted
        def duplicate? = disposition == :duplicate
        def discarded? = disposition == :discarded
      end

      def self.offered(disposition:, entry_id:, reason: nil, evicted_entry_id: nil, repositioned: false)
        Offered.new(disposition:, entry_id:, reason:, evicted_entry_id:, repositioned:)
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
      # `occurrence_document_url` is the provenance recorded on an OCCURRENCE when it differs from
      # the entry's ordering tuple. It exists for sitemap candidates: :454 forces a sitemap entry's
      # `discovering_document_url` to "" (the tuple has no room for it), so without this the URL of
      # the sitemap that named a candidate would be lost the moment the candidate was a duplicate —
      # which is exactly where provenance matters most. Defaults to the tuple's own value.
      #
      # `observer` is the S-07-008 limit observation point (`LimitDecisions::Observer`), already
      # bound to this run and its RESOLVED bounds. It is optional because the frontier's own specs
      # exercise admission without a Crawl policy resolution in hand; when it is absent the bounds
      # fall back to the frozen global ceiling and nothing is recorded, which is the correct
      # behaviour for a caller that is not executing a run.
      def offer(organization_id:, project_id:, crawl_id:, source_id:, canonical_url:, origin:,
                depth:, now:, discovering_document_url: "", link_position: 0, parent_entry_id: nil,
                occurrence_document_url: nil, observer: nil, scope_policy_id:, scope_policy_version:)
        @store.lock_frontier(crawl_id)
        preimage = canonical_url.to_s.unicode_normalize(:nfc).b
        digest = Digest::SHA256.digest(preimage)

        existing = @store.entries_for_digest(organization_id, crawl_id, digest)
        # Byte-equal preimage => the SAME candidate: one retained entry, and the other discovery
        # recorded as an occurrence "without becoming another candidate".
        #
        # WHICH one is retained is fixed by :454 — "Deduplication retains the first candidate in
        # THIS ORDER", i.e. the LOWEST-ordered discovery, not the first offered. The two genuinely
        # diverge: :440 puts sitemap-discovered URLs and root-followed links both at depth 1, where
        # `origin_rank` rather than the URL decides parent order, so a sitemap page can be dequeued
        # before a link page whose own URL sorts lower, and their children then arrive in the wrong
        # relative order. Committing in dequeue sequence does not repair that, because parent order
        # is not child order. So a lower-ordered later discovery REPOSITIONS the retained entry (the
        # schema permits that only while it is still unclaimed) and the superseded position is
        # recorded as the occurrence.
        same = existing.find { |row| unhex(row["preimage"]) == preimage }
        if same
          return deduplicate(organization_id:, project_id:, crawl_id:, source_id:, now:, existing: same,
                             canonical_url:, digest:, origin:, depth:, discovering_document_url:,
                             link_position:, parent_entry_id:,
                             occurrence_document_url: occurrence_document_url || discovering_document_url)
        end

        # Digest match with a DIFFERENT preimage is a SHA-256 collision. It must never merge two
        # candidates: allocate the next ordinal and retain both, each with its own full preimage.
        collision_ordinal = existing.empty? ? 0 : existing.map { |r| r["collision_ordinal"].to_i }.max + 1

        # The retention bound is a selection over a SET, not over an arrival sequence: ":454 retain
        # the LOWEST 20,000 by this order and record all later candidates as `queue_limit_discarded`".
        # So at the bound the new candidate is compared against the highest-ordered UNCLAIMED entry;
        # if the newcomer sorts lower, that entry is EVICTED to make room and the newcomer is
        # admitted. Only when the newcomer is the higher of the two is it the one discarded. Either
        # way the loser is retained as a `discarded` row rather than dropped, so the coverage
        # denominator can still account for it (:452 "plus every in-scope candidate discarded by a
        # Crawl limit"). A CLAIMED entry is never evicted — it has already been acted on.
        id = @ids.generate
        key = FrontierOrder.dequeue_key(depth:, origin:, canonical_url:,
                                        discovering_document_url:, link_position:, entry_id: id)
        evicted = nil
        state = "queued"
        reason = nil

        # AN OBSERVATION IS NOT A DISPOSITION, and this chain decides dispositions.
        #
        # The depth SOFT limb was briefly written as an `elsif` here, between the depth-hard limb and
        # the queue limb. It set neither `state` nor `reason` — it only recorded — but it still
        # consumed the branch, so every candidate whose depth fell in [soft, hard] skipped the
        # 20,000-candidate retention bound entirely: no eviction, no `queue_limit_discarded`, no
        # `discovered_url_queue` decision, permanently. All five ADR-026 lenses found it
        # independently. Under a legal `crawl_depth.soft = 1` policy that is EVERY sitemap-discovered
        # candidate (:440 puts them at depth 1), and under the frozen ceiling it becomes unconditional
        # the moment link extraction reaches depth 8, because breadth-first sealing means every
        # subsequent offer is at least that deep.
        #
        # So the soft observation is taken FIRST and unconditionally, outside the chain, and control
        # continues into the ordinary disposition path. A candidate over the hard bound records both:
        # the run genuinely did reach the soft value on its way past it, and the decision table
        # dedupes each to one row.
        observe_depth_soft(observer, depth, now)

        # DEPTH IS DECIDED BEFORE THE QUEUE BOUND. A URL past the depth bound is inadmissible on its
        # own terms — it would not become admissible if the queue had room — whereas a queue discard
        # is positional and would reverse if a lower-ordered candidate arrived. Deciding positionally
        # first would label a too-deep URL `queue_limit_discarded` purely because the run was full.
        #
        # The row is written either way: ":456 the discovered queue counts distinct content-candidate
        # URLs after Source Scope canonicalization, INCLUDING an in-scope URL EVEN WHEN IT IS LATER
        # REJECTED FOR DEPTH", and :452 puts every candidate "discarded by a Crawl limit" in the
        # coverage denominator. Dropping it would understate both.
        # ONE POPULATION, ONE BOUND. `admitted_count` is the discovered queue (see the store), and
        # this is the only place a candidate joins it. The bound is therefore enforced AT ENTRY:
        # a joiner at the ceiling either displaces a member or is refused entry.
        #
        # This ordering is load-bearing. Deciding depth first and exempting an over-depth candidate
        # from the queue check let it join a population it was not enforced against and could never
        # be evicted from, so N over-depth candidates put the run permanently N past its own
        # inclusive maximum with only the first crossing recorded.
        retained = @store.admitted_count(organization_id, crawl_id)
        if retained >= queue_hard(observer)
          victim = @store.highest_unclaimed(organization_id, crawl_id)
          if victim && unhex(victim["dequeue_key"]) > key
            # :454 — "retain the LOWEST 20,000 by this order". The newcomer sorts lower, so the
            # highest member leaves the population and the newcomer joins in its place.
            #
            # The row count is checked: `discard` is guarded on `state IN ('discovered','queued')`
            # AND the expected version, so a claim landing between `highest_unclaimed` and here
            # matches nothing — and reporting an eviction that did not happen would leave the run
            # one candidate above its nonexceedable bound.
            raise Platform::InvariantViolation, "frontier eviction lost" if
              @store.discard(victim["id"], victim["state_version"].to_i, now, QUEUE_LIMIT_DISCARDED).to_i.zero?

            evicted = victim["id"]
          else
            # Refused entry. It never joins the population, so it is not counted — and depth is not
            # consulted, because depth describes what kind of MEMBER a candidate is and this one is
            # not a member.
            state = "discarded"
            reason = QUEUE_LIMIT_DISCARDED
          end
          # One candidate was abandoned for the bound — the displaced member, or this one. The
          # observed value is the count read BEFORE any eviction; re-reading after it reported
          # `configured - 1`, because a discarded row leaves the population.
          observer&.hard(QUEUE_DIMENSION, retained, now:,
                         affected: LimitDecisions::Affected.new(sources: 1, urls: 1))
        end

        # DEPTH describes a MEMBER. A candidate refused entry above is not one, so this is skipped
        # for it — the queue bound is what kept it out, and that is the reason recorded.
        if reason.nil? && depth.to_i > depth_hard(observer)
          state = "discarded"
          reason = DEPTH_LIMIT_DISCARDED
          observer&.hard(DEPTH_DIMENSION, depth.to_i, now:, affected: LimitDecisions::Affected.new(sources: 1, urls: 1))
        end

        insert(id:, organization_id:, project_id:, crawl_id:, now:, state:, source_id:, canonical_url:,
               origin:, depth:, discovering_document_url:, link_position:, parent_entry_id:,
               scope_policy_id:, scope_policy_version:,
               enqueue_order: @store.next_enqueue_order(organization_id, crawl_id),
               collision_ordinal:, reason:, preimage:, digest:, dequeue_key: key)

        # AFTER the insert, so the count includes the candidate that produced the crossing. ":442 —
        # a soft event fires when the observed value FIRST EQUALS the soft limit"; asking before the
        # write would report the count one short and fire a candidate late.
        observe_queue_soft(observer, organization_id, crawl_id, now)

        self.class.offered(disposition: reason ? :discarded : :admitted, entry_id: id, reason:,
                           evicted_entry_id: evicted)
      end

      # Claim the next candidate in canonical dequeue order, or nil when the frontier is drained.
      def claim_next(organization_id:, crawl_id:, now:)
        @store.claim_next(organization_id, crawl_id, now)
      end

      private

      # The bounds an observer is enforcing, or the frozen global ceiling when there is none. Read
      # through the observer rather than resolved here so the number that discards a candidate and
      # the number the decision records are the same number.
      def depth_hard(observer) = observer ? observer.hard_bound(DEPTH_DIMENSION) : CRAWL_DEPTH_HARD
      def queue_hard(observer) = observer ? observer.hard_bound(QUEUE_DIMENSION) : DISCOVERED_QUEUE_HARD

      # ":442 — a soft event fires when the observed value first equals the soft limit." Recorded
      # unconditionally, never as a branch of the disposition chain — see the note at the top of
      # `offer` for what happened when it was.
      def observe_depth_soft(observer, depth, now)
        return if observer.nil? || depth.to_i < observer.soft_bound(DEPTH_DIMENSION)

        observer.soft(DEPTH_DIMENSION, depth.to_i, now:)
      end

      # ":442 — a soft event fires when the observed value first equals the soft limit." The
      # observed value for this dimension is the retained candidate count, which the unique key on
      # the decision table lets us test on every offer without any per-run bookkeeping: the first
      # crossing writes the row, every later one collides and emits nothing.
      def observe_queue_soft(observer, organization_id, crawl_id, now)
        return if observer.nil?

        admitted = @store.admitted_count(organization_id, crawl_id)
        return if admitted < observer.soft_bound(QUEUE_DIMENSION)

        observer.soft(QUEUE_DIMENSION, admitted, now:)
      end

      # One retained entry at the LOWEST-ordered position, and the superseded discovery recorded as
      # an occurrence. When the newcomer sorts lower AND the entry is still unclaimed, the entry is
      # repositioned onto it and the OLD position becomes the occurrence; otherwise the newcomer is
      # the occurrence. A claimed entry keeps its position — it has already been acted on.
      def deduplicate(organization_id:, project_id:, crawl_id:, source_id:, now:, existing:,
                      canonical_url:, digest:, origin:, depth:, discovering_document_url:,
                      link_position:, parent_entry_id:, occurrence_document_url: nil)
        entry = @store.entry(organization_id, existing["id"])
        incoming = FrontierOrder.dequeue_key(depth:, origin:, canonical_url:,
                                             discovering_document_url:, link_position:,
                                             entry_id: existing["id"])
        promote = %w[discovered queued].include?(entry["state"]) && incoming < unhex(entry["dequeue_key"])

        superseded = if promote
                       moved = @store.reposition(existing["id"], entry["state_version"].to_i, now,
                                                 { origin:, depth:, discovering_document_url:,
                                                   link_position:, dequeue_key: incoming, parent_entry_id: })
                       raise Platform::InvariantViolation, "frontier reposition lost" if moved.to_i.zero?

                       { url: entry_url(entry, canonical_url), discovering: entry["discovering_document_url"],
                         position: entry["link_position"].to_i, referrer: entry["parent_entry_id"] }
                     else
                       { url: canonical_url,
                         discovering: occurrence_document_url || discovering_document_url,
                         position: link_position, referrer: parent_entry_id }
                     end

        @store.insert_occurrence(
          id: @ids.generate, now:, correlation_id: @correlation_id, organization_id:, project_id:,
          crawl_id:, frontier_entry_id: existing["id"], source_id:, referrer_entry_id: superseded[:referrer],
          occurrence_url: superseded[:url], digest:, discovering_document_url: superseded[:discovering],
          link_position: superseded[:position],
          occurrence_order: @store.next_occurrence_order(organization_id, crawl_id),
          duplicate_reason: DUPLICATE_DISCOVERY
        )
        self.class.offered(disposition: :duplicate, entry_id: existing["id"], repositioned: promote)
      end

      # The canonical URL is identical for both discoveries by construction (byte-equal preimage).
      def entry_url(_entry, canonical_url) = canonical_url

      # rubocop:disable Metrics/ParameterLists
      def insert(organization_id:, project_id:, crawl_id:, now:, state:, source_id:, canonical_url:,
                 origin:, depth:, discovering_document_url:, link_position:, parent_entry_id:,
                 scope_policy_id:, scope_policy_version:, enqueue_order:, collision_ordinal:, reason:,
                 id: nil, preimage: nil, digest: nil, dequeue_key: nil)
        id ||= @ids.generate
        canonical_url = canonical_url.to_s.unicode_normalize(:nfc)
        preimage ||= canonical_url.b
        digest ||= Digest::SHA256.digest(preimage)
        dequeue_key ||= FrontierOrder.dequeue_key(depth:, origin:, canonical_url:,
                                                  discovering_document_url:, link_position:, entry_id: id)
        @store.insert_entry(
          id:, now:, correlation_id: @correlation_id, organization_id:, project_id:, crawl_id:,
          source_id:, canonical_url:, preimage:, digest:, collision_ordinal:, origin:, depth:,
          discovering_document_url:, link_position:, parent_entry_id:,
          canonicalization_version: CANONICALIZATION_VERSION, scope_policy_id:, scope_policy_version:,
          enqueue_order:, state:, reason:, dequeue_key:
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
