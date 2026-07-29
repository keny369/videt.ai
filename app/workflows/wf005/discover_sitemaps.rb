# frozen_string_literal: true

require "digest"
require "securerandom"

module Workflows
  module Wf005
    # Sitemap discovery for one `(crawl, canonical_host)` (S-07-006; WORKFLOW_SPECIFICATIONS.md :450
    # and :454; SEARCH_CRAWL_RETRIEVAL.md § Robots And Sitemap Processing — "A sitemap item only
    # creates a frontier candidate after canonicalization, same-host scope, destination and queue
    # admission checks").
    #
    # THE CANDIDATE SET (:450). "Sitemap discovery uses all in-scope `Sitemap:` locations in the
    # parsed robots file plus `https://<canonical_host>/sitemap.xml`; canonical duplicates are fetched
    # once." The robots-declared list is UNFILTERED — S-07-005 stores it verbatim, exactly as declared
    # — so every in-scope, same-host and canonicalization check happens HERE. That separation is
    # deliberate: what a site DECLARED and what this platform ADMITTED are different facts and both
    # are auditable.
    #
    # THE ORDER (:454) is `SitemapCandidates`, a selection over a set rather than over arrival order.
    #
    # THE OUTCOMES (:450), which decide whether the Source root's coverage is reduced:
    #   * `absent`      — robots declared none AND the default returned 404/410. "This is covered and
    #                     does not reduce coverage."
    #   * `succeeded`   — at least one candidate parsed. "Other non-limit sitemap-candidate failures
    #                     remain telemetry and do not reduce coverage."
    #   * `unavailable` — a declared sitemap existed, or the default returned a non-404/410, and no
    #                     candidate succeeded after retries/validation. Coverage becomes partial.
    #
    # Every fetch goes through the SAME gates a content fetch does — the host gate's rate and
    # concurrency claim, and `FetchAuthorization` at execution time — because :450 requires a sitemap
    # to "pass Source Scope, destination safety, robots, redirect, request, retry and 10 MiB limits",
    # and none of those may be skipped merely because the document is XML rather than HTML. The
    # network call is made outside every transaction and lock, as MTX-030 requires.
    class DiscoverSitemaps
      DEFAULT_PATH = "/sitemap.xml"
      ABSENT = "sitemap_absent"
      UNAVAILABLE = "sitemap_unavailable"
      TIMEOUT_S = CrawlPolicy::GLOBAL_CEILING.fetch("request_timeout_seconds").fetch("hard")
      MAX_BODY_BYTES = SitemapParser::MAX_CHARACTER_BYTES
      REDIRECT_BUDGET = CrawlPolicy::GLOBAL_CEILING.fetch("redirects_per_url").fetch("soft")
      USER_AGENT = RobotsPolicy::AGENT_TOKEN

      Result = Data.define(:state, :reason_code, :documents_fetched, :urls_offered, :max_index_depth,
                           :retained, :discarded) do
        def succeeded? = state == "succeeded"
        # Only `unavailable` reduces coverage (:450).
        def reduces_coverage? = state == "unavailable"
      end

      # A gate refusal is a SCHEDULING condition, never a candidate failure: :442 says a start over
      # the rate is "DELAYED", and treating the delay as a failure would silently turn the rate
      # limiter into "only the first sitemap per second is ever read, the rest are unavailable" —
      # which then reduces coverage for a host that was perfectly reachable. `pacer` is how the
      # traversal waits; it is injectable so a test can simulate elapsed time instead of spending it.
      MAX_DEFERRALS_PER_CANDIDATE = 5
      DEFERRED = :deferred

      # :444's shape, applied to sitemap fetches because :450 requires a sitemap to pass the same
      # "request, retry" bounds as any other fetch — and because :450 conditions `sitemap_unavailable`
      # on "no sitemap candidate succeeds AFTER RETRIES/validation". Recording a host unavailable
      # without having retried would reduce its coverage on the strength of one transient failure.
      MAX_ATTEMPTS = 3
      RETRYABLE_STATUSES = [408, 429].freeze

      # One fetch outcome. `parsed` is the parser Result when the document was retrieved and parsed;
      # `status` is the HTTP status when there was a response; `retryable` marks a transient failure.
      Attempt = Data.define(:parsed, :status, :retryable) do
        def ok? = parsed&.ok?
        # :450 — the default sitemap returning 404/410 is what makes "absent" the right outcome, as
        # distinct from any other response, which makes it "unavailable".
        def absent? = [404, 410].include?(status)
      end

      def initialize(outbound: Platform::Outbound, ids: Platform::Ids.system, correlation_id: nil,
                     pacer: ->(ms) { sleep(ms.to_i / 1000.0) })
        @outbound = outbound
        @ids = ids
        @correlation_id = correlation_id || SecureRandom.uuid_v7
        @pacer = pacer
      end

      def pace(milliseconds) = @pacer.call(milliseconds)

      # Resolve every sitemap for the host and admit the content URLs it names to the frontier.
      # Robots must already be terminal — :450's discovery reads the parsed robots file.
      def call(organization_id:, crawl_id:, canonical_host:, source_id:, project_id:, now:)
        gate = load_gate(organization_id, crawl_id, canonical_host)
        return already(gate) if gate && terminal?(gate["sitemap_state"])
        return Result.new(state: "pending", reason_code: "robots_not_resolved", documents_fetched: 0,
                          urls_offered: 0, max_index_depth: 0, retained: [], discarded: []) unless gate && robots_terminal?(gate)

        declared = declared_candidates(gate, canonical_host)
        retained, discarded = SitemapCandidates.retain(declared)
        begin_discovery(organization_id, gate["id"], retained, discarded, now)

        state = Traversal.new(self, organization_id:, crawl_id:, canonical_host:, source_id:,
                              project_id:, gate_id: gate["id"], now:).run(retained, declared_any: declared_any?(gate))
        terminalize(organization_id, gate["id"], state, now)
        state
      end

      # ---- candidate construction ----------------------------------------------

      # The declared set: robots' UNFILTERED `Sitemap:` values, filtered here to same-host in-scope
      # https URLs, plus the default. Duplicates collapse in `SitemapCandidates.distinct`.
      def declared_candidates(gate, canonical_host)
        raw = JSON.parse(gate["robots_sitemap_candidates"].to_s)
        raw = [] unless raw.is_a?(::Array)
        same_host = raw.filter_map { |url| normalize(url, canonical_host) }
        (same_host + [default_url(canonical_host)]).uniq
             .map { |url| SitemapCandidates.candidate(canonical_url: url) }
      rescue JSON::ParserError
        [SitemapCandidates.candidate(canonical_url: default_url(canonical_host))]
      end

      def declared_any?(gate)
        raw = JSON.parse(gate["robots_sitemap_candidates"].to_s)
        raw.is_a?(::Array) && raw.any?
      rescue JSON::ParserError
        false
      end

      def default_url(canonical_host) = "https://#{canonical_host}#{DEFAULT_PATH}"

      # :450 — "A sitemap or sitemap index must remain on the verified canonical host". A cross-host
      # or non-HTTPS location is recorded and skipped, never followed.
      def normalize(url, canonical_host)
        candidate = url.to_s.strip
        return nil unless candidate.start_with?("https://")

        authority = candidate.delete_prefix("https://").split(%r{[/?#]}, 2).first.to_s
        host = authority.split("@", 2).last.to_s.split(":", 2).first.to_s.downcase
        host == canonical_host.to_s.downcase ? candidate : nil
      end

      # ---- one candidate --------------------------------------------------------

      # Fetch and parse ONE sitemap. Returns the parser Result, or nil when the gate, authorization
      # or transport refused — refusals are telemetry unless nothing at all succeeds (:450).
      def fetch_document(organization_id:, crawl_id:, canonical_host:, source_id:, gate_id:, url:, now:)
        claim = claim_slot(organization_id, gate_id, now)
        # Distinguish "the host gate is pacing us" from "this candidate failed". Only the second is a
        # sitemap outcome; the first means try again shortly.
        return DEFERRED unless claim&.granted?

        begin
          unless authorized?(organization_id:, crawl_id:, source_id:, url:, gate_id:, now:)
            return Attempt.new(parsed: nil, status: nil, retryable: false)
          end

          classify(fetch(url))
        ensure
          release_slot(organization_id, gate_id, claim.lease_token, now)
        end
      end

      # A transport failure is retryable when the adapter says so; 408/429/5xx are retryable by
      # :444; every other status is terminal for the candidate. A non-2xx never reaches the parser,
      # so attacker-controlled bytes behind an error status are never interpreted as a sitemap.
      def classify(outcome)
        unless outcome.respond_to?(:response?) && outcome.response?
          return Attempt.new(parsed: nil, status: nil,
                             retryable: outcome.respond_to?(:retryable) && outcome.retryable)
        end

        status = outcome.status.to_i
        return Attempt.new(parsed: nil, status:, retryable: true) if RETRYABLE_STATUSES.include?(status) ||
                                                                     (500..599).cover?(status)
        unless (200..299).cover?(status)
          return Attempt.new(parsed: nil, status:, retryable: false)
        end

        Attempt.new(parsed: SitemapParser.parse(outcome.body, content_type: content_type_of(outcome)),
                    status:, retryable: false)
      end

      def content_type_of(outcome)
        headers = outcome.headers
        return nil unless headers.is_a?(::Hash)

        headers.find { |k, _v| k.to_s.downcase == "content-type" }&.last
      end

      def fetch(url)
        @outbound.fetch(url, timeout_s: TIMEOUT_S, byte_cap: MAX_BODY_BYTES,
                        max_redirects: REDIRECT_BUDGET, user_agent: USER_AGENT)
      rescue StandardError
        Platform::Outbound::Outcome.failure(:connection_failure, reason: :adapter_error, retryable: true)
      end

      # ---- transactions ---------------------------------------------------------

      def load_gate(organization_id, crawl_id, canonical_host)
        in_unit(organization_id) { |store| store.gate(organization_id, crawl_id, canonical_host) }
      end

      def claim_slot(organization_id, gate_id, now)
        in_unit(organization_id) do |store|
          HostGate.new(store, ids: @ids, correlation_id: @correlation_id)
                  .claim(organization_id:, gate_id:, now:, kind: "sitemap")
        end
      end

      def release_slot(organization_id, gate_id, lease_token, now)
        in_unit(organization_id) { |store| store.release_slot(gate_id, lease_token, now) }
      end

      def authorized?(organization_id:, crawl_id:, source_id:, url:, gate_id:, now:)
        in_unit(organization_id) do |store|
          gate = store.lock_gate(organization_id, gate_id)
          FetchAuthorization.new(store).authorize(
            organization_id:, crawl_id:, source_id:, canonical_url: url, gate:, now:, kind: "sitemap"
          ).allowed?
        end
      end

      def begin_discovery(organization_id, gate_id, retained, discarded, now)
        in_unit(organization_id) do |store|
          store.begin_sitemaps(gate_id, now,
                               retained.map { |c| candidate_json(c) },
                               discarded.map { |c| candidate_json(c) })
        end
      end

      def terminalize(organization_id, gate_id, result, now)
        in_unit(organization_id) do |store|
          store.terminalize_sitemaps(gate_id, now, state: result.state, reason: result.reason_code,
                                                   documents: result.documents_fetched,
                                                   max_depth: result.max_index_depth)
        end
      end

      def offer_url(organization_id:, project_id:, crawl_id:, source_id:, url:, discovering:, now:)
        in_unit(organization_id) do |store|
          gate_store = store
          frontier_store = IdentityAccess::Infrastructure::CrawlFrontierStore.new(gate_store.connection)
          scope = gate_store.current_scope_policy(organization_id, project_id, source_id)
          next false if scope.nil?

          # :450 — "Content URLs still pass normal scope, destination safety, robots, queue, depth and
          # deduplication rules." Scope is checked here; the frontier owns dedup and queue admission.
          decision = Wf004::SourceScopePredicate.evaluate(url:, policies: [scope_policy(scope)])
          next false unless decision.allowed?

          Frontier.new(frontier_store, ids: @ids, correlation_id: @correlation_id).offer(
            organization_id:, project_id:, crawl_id:, source_id:,
            canonical_url: decision.canonical_url, origin: "sitemap",
            # :440 — "a sitemap-discovered content URL starts at depth 1".
            depth: 1, now:, discovering_document_url: "", link_position: 0,
            # :454 forces the ENTRY tuple to ('',0) for a sitemap candidate, so the discovering
            # sitemap URL is carried on the OCCURRENCE, where the provenance survives.
            occurrence_document_url: discovering,
            scope_policy_id: scope["id"], scope_policy_version: scope["policy_version"]
          )
          true
        end
      end

      def scope_policy(row)
        Wf004::SourceScopePredicate::Policy.new(
          canonical_host: row["canonical_host"],
          allowed_schemes: Platform::PgArray.parse(row["allowed_schemes"]),
          allowed_ports: Platform::PgArray.parse_integers(row["allowed_ports"]),
          include_prefixes: Platform::PgArray.parse(row["include_prefixes"]),
          exclude_prefixes: Platform::PgArray.parse(row["exclude_prefixes"]),
          query_handling: row["query_handling"].to_s == Wf004::SourceScopePredicate::RETAIN_ALL ?
                            Wf004::SourceScopePredicate::RETAIN_ALL : Platform::PgArray.parse(row["query_handling"])
        )
      end

      def in_unit(organization_id)
        Platform::UnitOfWork.run do |conn|
          store = IdentityAccess::Infrastructure::CrawlHostGateStore.new(conn.raw_connection)
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          yield store
        end
      end

      def candidate_json(candidate)
        { "url" => candidate.canonical_url, "index_depth" => candidate.index_depth,
          "discovered_by" => candidate.discovering_sitemap_url }
      end

      def terminal?(state) = %w[succeeded absent unavailable].include?(state)
      def robots_terminal?(gate) = %w[rules_applied no_restrictions].include?(gate["robots_state"])

      def already(gate)
        Result.new(state: gate["sitemap_state"], reason_code: gate["sitemap_outcome_reason"],
                   documents_fetched: gate["sitemap_documents_fetched"].to_i, urls_offered: 0,
                   max_index_depth: gate["sitemap_max_index_depth"].to_i, retained: [], discarded: [])
      end

      # The breadth-first traversal of the candidate set, following sitemap-index edges up to the
      # ratified depth. Extracted so the fetch/parse/offer loop is readable as one thing.
      class Traversal
        def initialize(service, organization_id:, crawl_id:, canonical_host:, source_id:, project_id:,
                       gate_id:, now:)
          @service = service
          @context = { organization_id:, crawl_id:, canonical_host:, source_id:, project_id:, gate_id:, now: }
          @seen = []
          @documents = 0
          @offered = 0
          @max_depth = 0
          @succeeded = false
          @default_url = service.default_url(canonical_host)
          # nil until the default has been attempted; then true only if it answered 404/410.
          @default_absent = nil
        end

        def run(retained, declared_any:)
          queue = retained.dup
          until queue.empty?
            candidate = queue.shift
            next if @seen.include?(candidate.canonical_url)

            @seen << candidate.canonical_url
            queue.concat(visit(candidate))
            # The document bound applies to the whole run of this host (:450 sitemaps 40/50).
            break if @documents >= SitemapCandidates::DOCUMENT_LIMIT
          end
          outcome(declared_any:)
        end

        private

        # Wait out the host gate rather than recording a paced candidate as unavailable, and RETRY a
        # transient failure under :444 — :450 conditions `sitemap_unavailable` on "no candidate
        # succeeds AFTER retries", so recording it on one 503 would reduce coverage prematurely.
        def fetch_paced(candidate)
          last = nil
          DiscoverSitemaps::MAX_ATTEMPTS.times do
            attempt = fetch_once(candidate)
            return attempt if attempt == DiscoverSitemaps::DEFERRED

            last = attempt
            return attempt unless attempt.retryable

            @service.pace(HostGate::REFUSAL_RETRY_MS)
          end
          last
        end

        def fetch_once(candidate)
          DiscoverSitemaps::MAX_DEFERRALS_PER_CANDIDATE.times do
            attempt = @service.fetch_document(**@context.slice(:organization_id, :crawl_id, :canonical_host,
                                                               :source_id, :gate_id, :now),
                                              url: candidate.canonical_url)
            return attempt unless attempt == DiscoverSitemaps::DEFERRED

            @service.pace(HostGate::REFUSAL_RETRY_MS)
          end
          DiscoverSitemaps::DEFERRED
        end

        # Fetch one candidate; return any child candidates a sitemap INDEX names.
        def visit(candidate)
          attempt = fetch_paced(candidate)
          return [] if attempt == DiscoverSitemaps::DEFERRED   # still paced after the bound; telemetry only

          # :450 distinguishes the DEFAULT sitemap answering 404/410 (which makes the host "absent",
          # covered, no coverage reduction) from it answering anything else (which makes the host
          # "unavailable", reducing coverage). Recording which happened is the only way the outcome
          # table below can tell them apart.
          @default_absent = attempt.absent? if candidate.canonical_url == @default_url

          parsed = attempt.parsed
          return [] if parsed.nil? || !parsed.ok?

          @documents += 1
          @succeeded = true
          @max_depth = [@max_depth, candidate.index_depth].max
          parsed.urls.each { |url| @offered += 1 if offer(url, candidate.canonical_url) }
          children(parsed, candidate)
        end

        def children(parsed, candidate)
          depth = candidate.index_depth + 1
          return [] unless SitemapCandidates.within_index_depth?(depth)

          parsed.sitemaps.filter_map do |url|
            normalized = @service.normalize(url, @context[:canonical_host])
            next if normalized.nil?

            SitemapCandidates.candidate(canonical_url: normalized, index_depth: depth,
                                        discovering_sitemap_url: candidate.canonical_url)
          end.then { |set| SitemapCandidates.order(set) }
        end

        def offer(url, discovering)
          @service.offer_url(**@context.slice(:organization_id, :project_id, :crawl_id, :source_id, :now),
                             url:, discovering:)
        end

        # :450's outcome table, exactly:
        #   "When robots declares no sitemap AND the default sitemap returns 404 or 410, record
        #    sitemap_absent; this is covered and does not reduce coverage."
        #   "If a declared sitemap exists, OR the default returns a non-404/410 response, and no
        #    sitemap candidate succeeds after retries/validation, record sitemap_unavailable."
        # Both limbs of the `absent` condition are required: robots declaring nothing is NOT enough
        # on its own, because a default that answered 500 is an unavailable host, not an absent one.
        def outcome(declared_any:)
          state, reason =
            if @succeeded then ["succeeded", nil]
            elsif !declared_any && @default_absent then ["absent", DiscoverSitemaps::ABSENT]
            else ["unavailable", DiscoverSitemaps::UNAVAILABLE]
            end
          DiscoverSitemaps::Result.new(state:, reason_code: reason, documents_fetched: @documents,
                                       urls_offered: @offered, max_index_depth: @max_depth,
                                       retained: @seen, discarded: [])
        end
      end
    end
  end
end
