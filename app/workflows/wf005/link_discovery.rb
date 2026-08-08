# frozen_string_literal: true

module Workflows
  module Wf005
    # IN-CRAWL LINK DISCOVERY (S-07-007).
    #
    # ":440 — the Source root is depth 0, a sitemap-discovered content URL starts at depth 1, and
    # EACH FOLLOWED CONTENT LINK ADDS ONE EDGE." Until this existed nothing followed one: a run was
    # seeded from the Source root and the sitemap and reached exactly what those two named, so a page
    # linked from another page but absent from the sitemap was never fetched. That is not merely a
    # smaller crawl. `CHK-TI-001` derives its target set from :478's `link_edges`, and a target with
    # no terminal outcome is `unobserved`, which the Check evaluates BEFORE pass or fail — so the
    # whole Technical Integrity pillar returned `error/internal_link_coverage_incomplete` on every
    # real multi-page site, correctly and permanently.
    #
    # THE SCOPE PREDICATE DOES NOT FORK, AND NEITHER DOES THE EXTRACTION. Both come from the surfaces
    # that already own them: `Wf006::ParsedObservation.link_targets` is the parser's own `link_edges`,
    # and it resolves each target through `Wf004::SourceScopePredicate` — the same module
    # `FetchAuthorization` authorizes with and `DiscoverSitemaps` admits with. The set this offers and
    # the set the Check asks about are therefore the same set by construction rather than by
    # agreement between two implementations.
    #
    # WHAT THIS DOES NOT DECIDE. Deduplication, the 20,000-candidate retention bound, the depth bound
    # and their limit decisions are the frontier's, reached through the same `offer` surface sitemap
    # candidates use. Robots, destination safety and the media type are the FETCH's, checked when the
    # candidate is eventually dequeued — :450's "content URLs still pass normal scope, destination
    # safety, robots, queue, depth, and deduplication rules" is satisfied by admitting here and
    # letting each owner refuse in its own place, not by pre-judging any of it.
    #
    # ORDER, AND WHY OUT-OF-ORDER COMPLETION CANNOT CHANGE SELECTION.
    #
    # :454 requires that "completed responses are buffered and their outgoing links are canonicalized,
    # sorted, and committed in dequeue sequence", and SEARCH_CRAWL_RETRIEVAL.md adds that "one
    # coordinator commits discoveries and budget effects in increasing dequeue key. A completion with
    # a later key waits in `fetched_pending_commit`."
    #
    # PASSES GENUINELY RUN CONCURRENTLY. `worker_crawl` has concurrency 10 and a live run of
    # `xirconhomes.com.au` was observed with six entries `in_progress` at once, so the reading that
    # the driver is a serial chain — one action, one pass, each pass minting the next — is FALSE, and
    # any argument resting on it is worth nothing. What is true is narrower and sufficient:
    #
    #   * Discovery COMMITS are serialized. This runs inside the caller's terminal transaction, which
    #     already holds the per-Crawl frontier advisory lock, so two passes can fetch at once but
    #     cannot commit discoveries at once, and a discovery and the retirement that produced it
    #     commit together or not at all.
    #   * A candidate's position DOES NOT DEPEND ON WHEN IT WAS COMMITTED. `dequeue_key` is a pure
    #     function of `(depth, origin_rank, canonical_url, discovering_document_url, link_position,
    #     entry_id)`. A later-committing pass therefore cannot reorder an earlier one's candidates.
    #   * The two order-dependent DECISIONS are already order-independent at the point they are made.
    #     Deduplication keeps "the first candidate in this order" by REPOSITIONING a retained entry
    #     when a lower-ordered discovery arrives afterwards, and the 20,000 bound is a selection over
    #     the retained set against the highest unclaimed member, not over an arrival sequence. Both
    #     live in `Frontier#offer` and both are reached through it here.
    #
    # So `fetched_pending_commit` stays unbuilt for DISCOVERY because discovery has nothing left for
    # it to protect. It remains owed for the BUDGET effects :454 names in the same sentence, which are
    # `Admission`'s and not this file's, and ADR-087 already records it as that tranche's.
    class LinkDiscovery
      # What one document's discovery did. `in_scope` is the number of admitted targets the
      # extraction found, `admitted` the number that became new retained frontier entries — the
      # difference is duplicates and candidates the frontier's own bounds discarded, which are
      # dispositions rather than failures.
      Discovered = Data.define(:in_scope, :admitted) do
        def initialize(in_scope: 0, admitted: 0) = super
      end

      NONE = Discovered.new

      def initialize(ids: Platform::Ids.system, correlation_id: nil, limit_decisions: nil)
        @ids = ids
        @correlation_id = correlation_id
        @limits = limit_decisions || LimitDecisions.new(ids: @ids, correlation_id: @correlation_id)
      end

      # Offer this document's outgoing links, on the CALLER'S connection and inside the caller's
      # transaction. It opens no unit of work of its own: the frontier lock, the entry's terminal
      # transition and these offers are one atomic act, and a discovery that committed without its
      # retirement (or the reverse) would either duplicate work or lose it silently.
      def discover(pg:, organization_id:, crawl:, entry:, result:, now:)
        return NONE unless followable?(result)

        gates = IdentityAccess::Infrastructure::CrawlHostGateStore.new(pg)
        # THE CURRENT SCOPE, re-read now, exactly as `FetchAuthorization` and `DiscoverSitemaps` read
        # it. A candidate admitted under a scope the customer has since narrowed would be refused at
        # its own fetch anyway; admitting it under the narrowed scope means it is never admitted at
        # all, which is the same answer one round trip earlier.
        scope = gates.current_scope_policy(organization_id, crawl["project_id"], entry["source_id"])
        return NONE if scope.nil?

        targets = Wf006::ParsedObservation.link_targets(
          bytes: result.body, media_type: result.media_type,
          # THE DOCUMENT'S OWN CANONICAL URL, which is `entry["canonical_url"]` — the same value the
          # Document, the IngestionJob and therefore the parser's `canonical_document_url` carry. A
          # relative href resolves against it, and :294's referrer tuple is keyed by it, so taking
          # the fetch's `final_url` instead would resolve a redirected page's links against a URL no
          # referrer record names.
          canonical_document_url: entry["canonical_url"], scope_policies: [scope_policy(scope)]
        )
        return NONE if targets.empty?

        Discovered.new(in_scope: targets.size,
                       admitted: admit_all(pg, gates, organization_id, crawl, entry, scope, targets, now))
      end

      private

      # ONLY AN ACCEPTED PAGE HAS OUTGOING LINKS. :452 gives an admitted content URL exactly one
      # covered form that produces a body — "it creates a valid Document" — and `FetchContent`
      # returns `body: nil` on every other outcome, including the `content_absent` 404/410 that is
      # covered but body-free. So this is a guard on the OUTCOME rather than on the body being
      # non-nil: an empty-bodied document is still a document, and its zero links are an
      # observation, whereas a nil body on a covered outcome would be corruption worth failing on.
      def followable?(result)
        !result.nil? && result.outcome == FetchContent::DOCUMENT_CREATED &&
          Wf006::ParsedObservation.supported_media_type?(result.media_type)
      end

      def admit_all(pg, gates, organization_id, crawl, entry, scope, targets, now)
        frontier = Frontier.new(IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg),
                                ids: @ids, correlation_id: @correlation_id)
        observer = observer_for(pg, gates, organization_id, crawl)
        # ":440 — each followed content link ADDS ONE EDGE." The frontier owns what happens to a
        # candidate past the depth bound; this only states the depth the candidate is at.
        depth = entry["depth"].to_i + 1
        targets.count { |target| offer(frontier, observer, organization_id, crawl, entry, scope, target, depth, now) }
      end

      def offer(frontier, observer, organization_id, crawl, entry, scope, target, depth, now)
        frontier.offer(
          organization_id:, project_id: crawl["project_id"], crawl_id: crawl["id"],
          source_id: entry["source_id"], canonical_url: target["canonical_url"],
          origin: "link", depth:, now:,
          # :454's tuple for a link candidate carries BOTH the discovering document and the link
          # position, so unlike a sitemap candidate there is nothing to displace onto the occurrence:
          # the ordering tuple already holds the whole provenance.
          discovering_document_url: entry["canonical_url"], link_position: target["link_position"].to_i,
          parent_entry_id: entry["id"], observer:,
          scope_policy_id: scope["id"], scope_policy_version: scope["policy_version"]
        ).admitted?
      rescue ArgumentError
        # An unencodable ordering field (a negative or oversized position) is this candidate's
        # problem, not the run's: `DiscoverSitemaps#admit` refuses its own the same way, and losing
        # the whole page's discovery to one malformed edge would be the larger defect.
        false
      end

      # The run's limit observation point, on the caller's connection. The bounds are re-resolved
      # here rather than passed in because this is the only place in the pass that offers, and a
      # decision must record the numbers that were actually enforced.
      def observer_for(pg, gates, organization_id, crawl)
        project_id = crawl["project_id"]
        return nil if project_id.nil?

        bounds = EffectiveLimits.resolve(gates.active_crawl_policies(organization_id, project_id))
        @limits.for(pg, organization_id:, project_id:, crawl_id: crawl["id"], limits: bounds)
      end

      def scope_policy(row)
        Wf004::SourceScopePredicate::Policy.new(
          canonical_host: row["canonical_host"],
          allowed_schemes: Platform::PgArray.parse(row["allowed_schemes"]),
          allowed_ports: Platform::PgArray.parse_integers(row["allowed_ports"]),
          include_prefixes: Platform::PgArray.parse(row["include_prefixes"]),
          exclude_prefixes: Platform::PgArray.parse(row["exclude_prefixes"]),
          query_handling: query_handling(row["query_handling"])
        )
      end

      def query_handling(value)
        return Wf004::SourceScopePredicate::RETAIN_ALL if value.to_s == Wf004::SourceScopePredicate::RETAIN_ALL

        Platform::PgArray.parse(value)
      end
    end
  end
end
