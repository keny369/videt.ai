# frozen_string_literal: true

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
      REDIRECT_BUDGET = CrawlPolicy::GLOBAL_CEILING.fetch("redirects_per_url").fetch("hard")
      USER_AGENT = RobotsPolicy::AGENT_TOKEN

      # How many audit entries are persisted. The bound exists because both lists are driven by a
      # remote input (robots.txt bounds its body, not its `Sitemap:` line count), and the gate row is
      # read under an exclusive lock on the authorization path. Truncation is RECORDED, never silent.
      AUDIT_BOUND = 200
      AUDIT_TRUNCATED = "sitemap_audit_truncated"

      Result = Data.define(:state, :reason_code, :documents_fetched, :urls_offered, :max_index_depth,
                           :retained, :discarded, :skipped, :limit_reasons) do
        def succeeded? = state == "succeeded"
        # Only `unavailable` reduces coverage (:450) — but a LIMIT is a separate, stronger outcome
        # that forces `limit_reached` for the whole run whatever else happened.
        def reduces_coverage? = state == "unavailable"
        # :450 — "any sitemap depth/count/body/time/XML limit still produces limit_reached".
        def limit_reached? = !limit_reasons.empty?
      end

      # The :450 reason codes that are LIMITS rather than mere failures. Only these force
      # `limit_reached`; everything else is telemetry once a candidate has succeeded.
      DOCUMENTS_LIMIT = "sitemap_documents_limit"
      INDEX_DEPTH_LIMIT = "sitemap_index_depth_limit"
      LIMIT_REASONS = [SitemapParser::LIMIT, DOCUMENTS_LIMIT, INDEX_DEPTH_LIMIT].freeze
      CONTENDED = "sitemap_discovery_contended"

      # A gate refusal is a SCHEDULING condition, never a candidate failure: :442 says a start over
      # the rate is "DELAYED", and treating the delay as a failure would silently turn the rate
      # limiter into "only the first sitemap per second is ever read, the rest are unavailable" —
      # which then reduces coverage for a host that was perfectly reachable. `pacer` is how the
      # traversal waits; it is injectable so a test can simulate elapsed time instead of spending it.
      #
      # The wait is the length the GATE reports, not a fixed constant — a host declaring
      # `Crawl-delay: 10` needs ten seconds, and pacing it in 250 ms increments merely exhausted the
      # deferral budget on a reachable host. With the real interval waited, the count below is a
      # liveness backstop against a wedged gate rather than a scheduling parameter, and reaching it
      # is RECORDED rather than silently dropped.
      MAX_DEFERRALS_PER_CANDIDATE = 20
      DEFERRED = :deferred
      GATE_DEFERRED = "sitemap_gate_deferred"

      # :444's shape, applied to sitemap fetches because :450 requires a sitemap to pass the same
      # "request, retry" bounds as any other fetch — and because :450 conditions `sitemap_unavailable`
      # on "no sitemap candidate succeeds AFTER RETRIES/validation". Recording a host unavailable
      # without having retried would reduce its coverage on the strength of one transient failure.
      MAX_ATTEMPTS = FetchRetryPolicy::MAX_ATTEMPTS

      # One fetch outcome. `parsed` is the parser Result when the document was retrieved and parsed;
      # `status` is the HTTP status when there was a response; `retryable` marks a transient failure.
      Attempt = Data.define(:parsed, :status, :retryable, :outcome) do
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
      def call(organization_id:, crawl_id:, canonical_host:, source_id:, project_id: nil, now:)
        gate = load_gate(organization_id, crawl_id, canonical_host)
        return already(gate) if gate && terminal?(gate["sitemap_state"])
        return pending("robots_not_resolved") unless gate && robots_terminal?(gate)

        # The Project is resolved from the CRAWL, never from the caller. `FetchAuthorization` already
        # does this deliberately; reading a caller-supplied value here would evaluate Source Scope
        # against another Project's policy before a composite foreign key rejected the insert —
        # fail-closed, but a decision taken on unverified input, which is not the same thing.
        crawl = load_crawl(organization_id, crawl_id)
        return pending("crawl_not_found") if crawl.nil?

        declared = declared_candidates(gate, canonical_host)
        retained, discarded = SitemapCandidates.retain(declared)
        # A zero row count means another worker won the pending -> in_progress transition. Standing
        # down is the point: both workers running the traversal would DOUBLE the request volume
        # against the host this whole subsystem exists to pace.
        # The claim token identifies THIS attempt. Only the holder may write the terminal outcome, so
        # a worker that lost the race — or one whose lost attempt was later taken over — cannot close
        # a run it is not executing.
        token = @ids.generate
        if begin_discovery(organization_id, gate, retained, discarded, token, now).zero?
          return pending(CONTENDED)
        end

        state = Traversal.new(self, organization_id:, crawl_id:, canonical_host:, source_id:,
                              project_id: crawl["project_id"], gate_id: gate["id"], now:)
                         .run(retained, declared_any: declared_any?(gate), discarded:)
        terminalize(organization_id, gate["id"], token, state, now)
        state
      end

      def pending(reason)
        Result.new(state: "pending", reason_code: reason, documents_fetched: 0, urls_offered: 0,
                   max_index_depth: 0, retained: [], discarded: [], skipped: [], limit_reasons: [])
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

      # :450 — "A sitemap or sitemap index must remain on the verified canonical host" and "canonical
      # duplicates are fetched once"; :454 orders candidates by CANONICAL URL bytes. Both require the
      # location to be CANONICALIZED, not merely host-compared: without it
      # `https://Host/sitemap.xml`, `https://host:443/sitemap.xml`, `https://host/a/../sitemap.xml`
      # and a `#fragment` variant are four candidates for one document, each fetched separately and
      # each sorting on the wrong bytes.
      #
      # The canonicalizer is the S-06 predicate — the same one content URLs go through — driven by a
      # permissive identity policy for this host, so host/scheme/port/path/query normalization and
      # the same-host rule are decided by one implementation rather than two.
      def normalize(url, canonical_host)
        decision = Wf004::SourceScopePredicate.evaluate(url: url.to_s.strip,
                                                        policies: [identity_policy(canonical_host)])
        decision.allowed? ? decision.canonical_url : nil
      rescue ArgumentError
        nil
      end

      def identity_policy(canonical_host)
        Wf004::SourceScopePredicate::Policy.new(
          canonical_host: canonical_host.to_s.downcase, allowed_schemes: ["https"],
          allowed_ports: [443], include_prefixes: ["/"], exclude_prefixes: [],
          query_handling: Wf004::SourceScopePredicate::RETAIN_ALL
        )
      end

      # ---- one candidate --------------------------------------------------------

      # Fetch and parse ONE sitemap. Returns the parser Result, or nil when the gate, authorization
      # or transport refused — refusals are telemetry unless nothing at all succeeds (:450).
      def fetch_document(organization_id:, crawl_id:, canonical_host:, source_id:, gate_id:, url:, now:)
        claim = claim_slot(organization_id, gate_id, now)
        # Distinguish "the host gate is pacing us" from "this candidate failed". Only the second is a
        # sitemap outcome; the first means try again after the interval the GATE names.
        return [DEFERRED, claim&.retry_after_ms || HostGate::REFUSAL_RETRY_MS] unless claim&.granted?

        begin
          unless authorized?(organization_id:, crawl_id:, source_id:, url:, gate_id:, now:)
            return Attempt.new(parsed: nil, status: nil, retryable: false, outcome: nil)
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
          return Attempt.new(parsed: nil, status: nil, outcome:,
                             retryable: FetchRetryPolicy.retryable?(outcome))
        end

        status = outcome.status.to_i
        return Attempt.new(parsed: nil, status:, retryable: true, outcome:) if FetchRetryPolicy.retryable?(outcome)
        unless (200..299).cover?(status)
          return Attempt.new(parsed: nil, status:, retryable: false, outcome:)
        end

        # A body stopped AT the byte cap is over the :450 bound, not at it, and handing the truncated
        # prefix to the parser would report `sitemap_malformed` for what is really `sitemap_xml_limit`
        # — and, worse, parse a document the site never served. `EnsureRobots` already checks this.
        if outcome.byte_count.to_i > MAX_BODY_BYTES || (outcome.respond_to?(:truncated) && outcome.truncated)
          return Attempt.new(parsed: SitemapParser.failure(SitemapParser::LIMIT), status:,
                             retryable: false, outcome:)
        end

        # :450 — "A sitemap or sitemap index MUST REMAIN ON THE VERIFIED CANONICAL HOST". F-01
        # revalidates destination safety on every redirect hop but imposes no same-host rule, so a
        # sitemap that redirects off-host would otherwise be fetched and parsed as this host's
        # sitemap. The final URL is what was actually retrieved, so that is what is checked.
        final = outcome.final_url
        if final && normalize(final, outcome.canonical_host).nil?
          return Attempt.new(parsed: nil, status:, retryable: false, outcome:)
        end

        Attempt.new(parsed: SitemapParser.parse(outcome.body, content_type: content_type_of(outcome)),
                    status:, retryable: false, outcome:)
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
        Platform::Outbound::Outcome.failure(:connection_failure, reason: :adapter_error, retryable: true,
                                           canonical_host: nil)
      end

      # ---- transactions ---------------------------------------------------------

      def load_gate(organization_id, crawl_id, canonical_host)
        in_unit(organization_id) { |store| store.gate(organization_id, crawl_id, canonical_host) }
      end

      def load_crawl(organization_id, crawl_id)
        in_unit(organization_id) { |store| store.crawl(organization_id, crawl_id) }
      end

      # Reserve one slot from the RUN-WIDE sitemap-document budget (:437 — 50 distinct canonical
      # sitemap URLs PER RUN). Returns false when the run has spent it.
      #
      # The counter lives on `crawl_budget_counters`, which schema :298 assigns run-wide accounting
      # to. S-07-006 had to use `crawls.limit_counters` because that table did not yet exist; when
      # S-07-007 created it, the writer moved here rather than leaving the bound with two homes.
      def reserve_document(organization_id:, project_id:, crawl_id:, now:)
        Platform::UnitOfWork.run do |conn|
          store = IdentityAccess::Infrastructure::CrawlBudgetStore.new(conn.raw_connection)
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          store.ensure_counters(id: @ids.generate, now:, correlation_id: @correlation_id,
                                organization_id:, project_id:, crawl_id:)
          !store.reserve_sitemap_document(organization_id, crawl_id,
                                          SitemapCandidates::DOCUMENT_LIMIT, now).nil?
        end
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

      def begin_discovery(organization_id, gate, retained, discarded, token, now)
        in_unit(organization_id) do |store|
          store.begin_sitemaps(gate["id"], gate["state_version"].to_i, now,
                               retained.map { |c| candidate_json(c) },
                               bounded(discarded.map { |c| candidate_json(c) }, "url"), token)
        end.to_i
      end

      # Persist at most `AUDIT_BOUND` entries, recording that the list was truncated. The overflow of
      # a 39,000-candidate declared set is genuine audit data, but it is remote-controlled and it
      # lives on the row every authorization read locks — so it is bounded, and the bound is visible.
      def bounded(entries, key)
        return entries if entries.length <= AUDIT_BOUND

        entries.first(AUDIT_BOUND - 1) +
          [{ key => AUDIT_TRUNCATED, "reason" => AUDIT_TRUNCATED, "omitted" => entries.length - AUDIT_BOUND + 1 }]
      end

      # A zero-row terminalize would leave the gate permanently `in_progress`, so the :450 outcome
      # would never be recorded and nothing would notice. It is asserted, not assumed.
      def terminalize(organization_id, gate_id, token, result, now)
        moved = in_unit(organization_id) do |store|
          store.terminalize_sitemaps(gate_id, token, now, state: result.state, reason: result.reason_code,
                                                   documents: result.documents_fetched,
                                                   max_depth: result.max_index_depth,
                                                   skipped: bounded(result.skipped, "url"),
                                                   limit_reasons: result.limit_reasons)
        end
        raise Platform::InvariantViolation, "sitemap terminal decision lost" if moved.to_i.zero?
      end

      # Admit every content URL ONE PARSED DOCUMENT names, in one unit of work. Per-URL transactions
      # were the shape here, and they cost a `f1_enter_org_context`, a two-table `current_scope_policy`
      # join, an advisory lock and a commit EACH — for a document naming 16,000 URLs, and up to 50
      # documents per run. The network call is already outside every transaction because the document
      # is in memory by the time this runs, so batching costs no invariant: the scope policy is read
      # once for URLs that are admitted together anyway, and `FetchAuthorization` re-reads it at fetch
      # time regardless, which is where freshness actually matters.
      def offer_urls(organization_id:, project_id:, crawl_id:, source_id:, urls:, discovering:, now:)
        return 0 if urls.empty?

        in_unit(organization_id) do |store, conn|
          scope = store.current_scope_policy(organization_id, project_id, source_id)
          next 0 if scope.nil?

          policy = scope_policy(scope)
          frontier = Frontier.new(IdentityAccess::Infrastructure::CrawlFrontierStore.new(conn),
                                  ids: @ids, correlation_id: @correlation_id)
          urls.count { |url| admit(frontier, policy, scope, url, discovering, organization_id,
                                   project_id, crawl_id, source_id, now) }
        end
      end

      def admit(frontier, policy, scope, url, discovering, organization_id, project_id, crawl_id,
                source_id, now)
        # :450 — "Content URLs still pass normal scope, destination safety, robots, queue, depth and
        # deduplication rules." Scope is checked here; the frontier owns dedup and queue admission.
        decision = Wf004::SourceScopePredicate.evaluate(url:, policies: [policy])
        return false unless decision.allowed?

        # `urls_offered` counts URLs genuinely ADMITTED to the frontier. Counting every call made a
        # duplicate or a queue-limit discard look like a new candidate, which is exactly the number a
        # reader would use to check that discovery did what it says.
        frontier.offer(
          organization_id:, project_id:, crawl_id:, source_id:,
          canonical_url: decision.canonical_url, origin: "sitemap",
          # :440 — "a sitemap-discovered content URL starts at depth 1".
          depth: 1, now:, discovering_document_url: "", link_position: 0,
          # :454 forces the ENTRY tuple to ('',0) for a sitemap candidate, so the discovering
          # sitemap URL is carried on the OCCURRENCE, where the provenance survives.
          occurrence_document_url: discovering,
          scope_policy_id: scope["id"], scope_policy_version: scope["policy_version"]
        ).admitted?
      rescue ArgumentError
        false
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

      # Yields the gate store AND the raw connection, so a caller needing a sibling store on the same
      # transaction can build one without the gate store publishing its own connection as public API.
      def in_unit(organization_id)
        Platform::UnitOfWork.run do |conn|
          raw = conn.raw_connection
          store = IdentityAccess::Infrastructure::CrawlHostGateStore.new(raw)
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          yield store, raw
        end
      end

      def candidate_json(candidate)
        { "url" => candidate.canonical_url, "index_depth" => candidate.index_depth,
          "discovered_by" => candidate.discovering_sitemap_url }
      end

      def parse_json(value)
        parsed = JSON.parse(value.to_s)
        parsed.is_a?(::Array) ? parsed : []
      rescue JSON::ParserError
        []
      end

      def terminal?(state) = %w[succeeded absent unavailable].include?(state)
      def robots_terminal?(gate) = %w[rules_applied no_restrictions].include?(gate["robots_state"])

      # An already-terminal gate reports what was RECORDED, including the retained candidate set and
      # the overflow — the same fields a fresh run reports, read back from the row rather than
      # invented as empty.
      def already(gate)
        Result.new(state: gate["sitemap_state"], reason_code: gate["sitemap_outcome_reason"],
                   documents_fetched: gate["sitemap_documents_fetched"].to_i, urls_offered: 0,
                   max_index_depth: gate["sitemap_max_index_depth"].to_i,
                   retained: parse_json(gate["sitemap_candidates"]).filter_map { |c| c["url"] },
                   discarded: parse_json(gate["sitemap_discarded"]).filter_map { |c| c["url"] },
                   skipped: parse_json(gate["sitemap_skipped"]),
                   limit_reasons: parse_json(gate["sitemap_limit_reasons"]))
      end

      # The breadth-first traversal of the candidate set, following sitemap-index edges up to the
      # ratified depth. Every skipped or failed candidate is RECORDED with its reason (:450), and the
      # LIMIT subset is separated because only those force `limit_reached` for the whole run.
      class Traversal
        def initialize(service, organization_id:, crawl_id:, canonical_host:, source_id:, project_id:,
                       gate_id:, now:)
          @service = service
          @context = { organization_id:, crawl_id:, canonical_host:, source_id:, project_id:, gate_id:, now: }
          # Insertion-ordered and O(1) to test. The previous Array + `include?` was quadratic over a
          # remote-controlled candidate list.
          @visited = {}
          @pending = []
          @documents = 0
          @offered = 0
          @max_depth = 0
          @succeeded = false
          @skipped = []
          @limit_reasons = []
          @default_url = service.default_url(canonical_host)
          # nil until the default has been attempted; then true only if it answered 404/410.
          @default_absent = nil
        end

        def run(retained, declared_any:, discarded: [])
          discarded.each { |c| skip(c.canonical_url, DiscoverSitemaps::DOCUMENTS_LIMIT) }
          @pending = SitemapCandidates.order(retained)
          until @pending.empty?
            candidate = @pending.shift
            next if @visited.key?(candidate.canonical_url)

            # :437 — "sitemap documents per RUN | 40 | 50 | distinct canonical sitemap URLs". The
            # budget is reserved from the CRAWL, not from this host: `crawl_host_gates` holds one row
            # per `(crawl, canonical_host)`, so a per-host counter would let a Crawl with ten Sources
            # on ten hosts fetch ten times the ratified maximum.
            #
            # Reserved BEFORE the attempt, because the unit is distinct canonical URLs ATTEMPTED.
            # Counting successful parses instead would let one index naming ten thousand dead
            # children fetch every one of them without the counter ever moving.
            unless @service.reserve_document(**@context.slice(:organization_id, :project_id, :crawl_id, :now))
              skip(candidate.canonical_url, DiscoverSitemaps::DOCUMENTS_LIMIT)
              next
            end

            @visited[candidate.canonical_url] = candidate
            admit(visit(candidate))
          end
          outcome(declared_any:)
        end

        private

        # :454's retention is a SELECTION OVER THE WHOLE CANDIDATE SET, not over the declared set
        # alone. Applying it only at depth 0 and then appending index children unbounded is what let
        # one attacker-authored index name 500 children and produce 501 outbound fetches — the
        # ceiling that exists to stop precisely that.
        #
        # Re-selecting over visited + pending + new keeps the invariant stable: candidates sort by
        # index depth first and the traversal is breadth-first, so the visited set is always a prefix
        # of the order and re-selection never has to un-visit anything.
        def admit(children)
          return if children.empty?

          retained, overflow = SitemapCandidates.retain(@visited.values + @pending + children)
          overflow.each do |c|
            skip(c.canonical_url, DiscoverSitemaps::DOCUMENTS_LIMIT) unless @visited.key?(c.canonical_url)
          end
          @pending = retained.reject { |c| @visited.key?(c.canonical_url) }
        end

        def skip(url, reason)
          @skipped << { "url" => url, "reason" => reason }
          @limit_reasons << reason if DiscoverSitemaps::LIMIT_REASONS.include?(reason)
        end

        # Wait out the host gate rather than recording a paced candidate as unavailable, and RETRY a
        # transient failure under :444 — :450 conditions `sitemap_unavailable` on "no candidate
        # succeeds AFTER retries", so recording it on one 503 would reduce coverage prematurely.
        def fetch_paced(candidate)
          last = nil
          DiscoverSitemaps::MAX_ATTEMPTS.times do |index|
            attempt = fetch_once(candidate)
            return attempt if attempt == DiscoverSitemaps::DEFERRED

            last = attempt
            return attempt unless attempt.retryable

            @service.pace(FetchRetryPolicy.delay_ms(index + 1, attempt.outcome))
          end
          last
        end

        def fetch_once(candidate)
          DiscoverSitemaps::MAX_DEFERRALS_PER_CANDIDATE.times do
            attempt = @service.fetch_document(**@context.slice(:organization_id, :crawl_id, :canonical_host,
                                                               :source_id, :gate_id, :now),
                                              url: candidate.canonical_url)
            return attempt unless attempt.is_a?(::Array) && attempt.first == DiscoverSitemaps::DEFERRED

            # Wait the length the GATE reports, not a fixed constant: the interval is
            # max(base, robots Crawl-delay, ...), so pacing a `Crawl-delay: 10` host in 250 ms
            # increments merely burned the budget on a host that was perfectly reachable.
            @service.pace(attempt.last)
          end
          DiscoverSitemaps::DEFERRED
        end

        # Fetch one candidate; return any child candidates a sitemap INDEX names.
        def visit(candidate)
          attempt = fetch_paced(candidate)
          if attempt == DiscoverSitemaps::DEFERRED
            skip(candidate.canonical_url, DiscoverSitemaps::GATE_DEFERRED)
            return []
          end

          # :450 distinguishes the DEFAULT sitemap answering 404/410 (which makes the host "absent",
          # covered, no coverage reduction) from it answering anything else (which makes the host
          # "unavailable", reducing coverage). Recording which happened is the only way the outcome
          # table below can tell them apart.
          @default_absent = attempt.absent? if candidate.canonical_url == @default_url

          parsed = attempt.parsed
          if parsed.nil?
            skip(candidate.canonical_url, attempt.status ? "sitemap_fetch_failed" : "sitemap_unreachable")
            return []
          end
          unless parsed.ok?
            # `sitemap_xml_unsafe`, `sitemap_xml_limit`, malformed, unsupported media — each recorded
            # under its own :450 reason, with the limit subset separated.
            skip(candidate.canonical_url, parsed.reason)
            return []
          end

          @documents += 1
          @succeeded = true
          @max_depth = [@max_depth, candidate.index_depth].max
          @offered += @service.offer_urls(**@context.slice(:organization_id, :project_id, :crawl_id,
                                                           :source_id, :now),
                                          urls: parsed.urls, discovering: candidate.canonical_url)
          children(parsed, candidate)
        end

        def children(parsed, candidate)
          depth = candidate.index_depth + 1
          normalized = parsed.sitemaps.filter_map do |url|
            target = @service.normalize(url, @context[:canonical_host])
            # A cross-host or unparseable location is recorded and skipped, never followed (:450).
            next skip(url, "sitemap_cross_host_location") && nil if target.nil?

            target
          end
          unless SitemapCandidates.within_index_depth?(depth)
            normalized.each { |url| skip(url, DiscoverSitemaps::INDEX_DEPTH_LIMIT) }
            return []
          end

          normalized.map do |url|
            SitemapCandidates.candidate(canonical_url: url, index_depth: depth,
                                        discovering_sitemap_url: candidate.canonical_url)
          end
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
                                       retained: @visited.keys,
                                       discarded: @skipped.map { |s| s["url"] },
                                       skipped: @skipped, limit_reasons: @limit_reasons.uniq)
        end
      end
    end
  end
end
