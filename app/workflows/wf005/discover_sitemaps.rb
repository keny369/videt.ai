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
                           :retained, :discarded, :skipped, :limit_reasons, :retry_after) do
        def initialize(retry_after: nil, **) = super

        def succeeded? = state == "succeeded"
        # Only `unavailable` reduces coverage (:450) — but a LIMIT is a separate, stronger outcome
        # that forces `limit_reached` for the whole run whatever else happened.
        def reduces_coverage? = state == "unavailable"
        # :450 — "any sitemap depth/count/body/time/XML limit still produces limit_reached".
        def limit_reached? = !limit_reasons.empty?
        # FU-9: nothing was decided about this host, and the scheduler owes it another pass.
        def rescheduled? = state == "pending" && reason_code == DiscoverSitemaps::CONTENDED
      end

      # The :450 reason codes that are LIMITS rather than mere failures. Only these force
      # `limit_reached`; everything else is telemetry once a candidate has succeeded.
      DOCUMENTS_LIMIT = "sitemap_documents_limit"
      INDEX_DEPTH_LIMIT = "sitemap_index_depth_limit"
      # The two ratified `limit_dimension` members this service is the observation point for.
      DOCUMENTS_DIMENSION = "sitemap_documents_per_run"
      INDEX_DEPTH_DIMENSION = "sitemap_index_nesting_depth"
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
      # The run-wide sitemap-document budget refused this attempt. Distinct from DEFERRED: the gate
      # would have let us out, the RUN cannot pay.
      DOCUMENTS_EXHAUSTED = :documents_exhausted

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
                     pacer: ->(ms) { sleep(ms.to_i / 1000.0) }, limit_decisions: nil)
        @outbound = outbound
        @ids = ids
        @correlation_id = correlation_id || SecureRandom.uuid_v7
        @pacer = pacer
        @limit_decisions = limit_decisions || LimitDecisions.new(ids: @ids, correlation_id: @correlation_id)
      end

      def pace(milliseconds) = @pacer.call(milliseconds)

      # The resolved sitemap bounds, exposed for the traversal (an inner class, not a client). They
      # default to the frozen ceiling until `call` has resolved them.
      def bounds = @bounds || EffectiveLimits::GLOBAL
      def documents_hard = bounds.configured(DOCUMENTS_DIMENSION, LimitDimensions::HARD)
      def index_depth_hard = bounds.configured(INDEX_DEPTH_DIMENSION, LimitDimensions::HARD)

      # Resolve every sitemap for the host and admit the content URLs it names to the frontier.
      # Robots must already be terminal — :450's discovery reads the parsed robots file.
      # NOTE there is no `project_id:` parameter, deliberately. It used to be accepted and silently
      # ignored — the Project is resolved from the CRAWL below, never from the caller — which invited
      # a caller to believe it was authoritative.
      def call(organization_id:, crawl_id:, canonical_host:, source_id:, now:)
        gate = load_gate(organization_id, crawl_id, canonical_host)
        return already(gate) if gate && terminal?(gate["sitemap_state"])
        return pending("robots_not_resolved") unless gate && robots_terminal?(gate)

        # The Project is resolved from the CRAWL, never from the caller. `FetchAuthorization` already
        # does this deliberately; reading a caller-supplied value here would evaluate Source Scope
        # against another Project's policy before a composite foreign key rejected the insert —
        # fail-closed, but a decision taken on unverified input, which is not the same thing.
        crawl = load_crawl(organization_id, crawl_id)
        return pending("crawl_not_found") if crawl.nil?

        # :390 — the operative sitemap bounds are the most restrictive of global safety and every
        # active Organization/Project policy. They were class constants here, so a Project that
        # narrowed `sitemap_documents` or `sitemap_index_depth` was silently ignored: the same
        # defect S-07-007 found and fixed on the per-fetch bounds. Resolved ONCE per run so the
        # bound that discards a candidate and the `configured_value` a decision records agree.
        @bounds = resolution(organization_id, crawl["project_id"])

        declared = declared_candidates(gate, canonical_host)
        retained, discarded = SitemapCandidates.retain(declared, limit: documents_hard)
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

        # A TRANSFERRED DELIVERY IS NOT AN OUTCOME EITHER, and this is checked ABOVE `defer_to_scheduler?`
        # because that predicate is false for a traversal that recorded no `sitemap_gate_deferred` skip —
        # so a delivery that lost its lease part-way through a run of candidates fell straight through to
        # `terminalize` and wrote the WRITE-ONCE gate outcome on behalf of an action the database had
        # already given to someone else. Demonstrated. The claim is handed back exactly as FU-9 hands back
        # a contended one; the winner's own traversal decides.
        return reschedule(organization_id, gate["id"], token, now) unless
          Platform::ScheduledActions::Lease.owned?

        # FU-9 (ADR-081): SUSTAINED CONTENTION IS NOT AN OUTCOME, so it does not get written as one.
        return reschedule(organization_id, gate["id"], token, now) if defer_to_scheduler?(state, crawl, now)

        terminalize(organization_id, crawl["project_id"], crawl_id, gate["id"], token, state, now)
        state
      end

      def pending(reason, retry_after: nil)
        Result.new(state: "pending", reason_code: reason, documents_fetched: 0, urls_offered: 0,
                   max_index_depth: 0, retained: [], discarded: [], skipped: [], limit_reasons: [],
                   retry_after:)
      end

      # ---- FU-9: scheduler re-entry after sustained host-gate contention -----------
      #
      # THE DEFECT (ADR-081, ADR-026 concurrency lens): a host under sustained contention could
      # exhaust the traversal's deferral budget and then be terminalized `sitemap_unavailable` —
      # WRITE-ONCE, coverage permanently partial — having made ZERO network attempts. S-07-006
      # mitigated the trigger (the gate now reports the real remaining wait, so pacing no longer
      # expires on a legitimate `Crawl-delay`) but left the failure mode reachable, and the build
      # plan makes the re-entry this tranche's to provide.
      #
      # THE FIX IS TO NOT DECIDE. :450 conditions `sitemap_unavailable` on "no sitemap candidate
      # succeeds AFTER RETRIES/VALIDATION"; a candidate the rate limiter never released has had
      # neither, so the premise of that sentence is unmet and there is nothing to record. The claim
      # is handed back, the gate returns to `pending`, and the host is exactly as discoverable as it
      # was before this attempt.
      #
      # WHY NO NEW SCHEDULED-ACTION KIND. The ratified catalogue is closed, and none of its crawl
      # kinds means "re-run sitemap discovery for a host" — `crawl_fetch_due` is bound to a Fetch
      # Attempt identity and `crawl_dispatch` to `StartCrawl`/`CompleteCrawl`/`FailCrawl`/
      # `CancelCrawl` "selected solely from persisted Crawl/deadline state". Inventing one would add
      # vocabulary to a frozen catalogue to express something the existing state already expresses:
      # a `pending` gate IS the re-entry, because the next pass claims it exactly as the first did.
      #
      # WHAT BOUNDS IT. The run's own wall clock, which is now enforced at admission (:442 — "at 60
      # elapsed minutes, no new request starts"). A host that stays contended until the deadline is
      # terminalized honestly HERE, once, with `unavailable` — at that point no candidate can ever
      # be attempted, so the coverage reduction is true rather than premature, and the run already
      # carries a `wall_clock_run_duration` decision explaining it.
      def defer_to_scheduler?(state, crawl, now)
        return false if state.succeeded? || !gate_deferred?(state)

        !run_expired?(crawl, now)
      end

      def gate_deferred?(state)
        state.skipped.any? { |s| s["reason"] == GATE_DEFERRED }
      end

      def run_expired?(crawl, now)
        deadline = crawl["deadline_at"]
        return false if deadline.nil?

        Time.parse(deadline.to_s).utc <= now.utc
      end

      # Hand the claim back and tell the caller when the host is next startable, so a scheduler can
      # place the re-entry rather than spin. A zero row count means the claim had already been taken
      # over by a presumed-lost-worker sweep, which is itself the re-entry.
      def reschedule(organization_id, gate_id, token, now)
        next_start = in_unit(organization_id) do |store|
          store.release_sitemaps(gate_id, token, now)
          store.next_allowed_start(organization_id, gate_id)
        end
        pending(CONTENDED, retry_after: next_start)
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
      # `canonical_url` is bounded at persistence (`crawl_sitemap_document_charges` CHECKs
      # `length BETWEEN 1 AND 8192`), so it must be bounded HERE, where a refusal is an ordinary
      # recorded skip. Remote input reaches this from a customer's robots.txt and from
      # `<sitemapindex>` bodies the parser admits up to 10 MiB of character data; neither caps a
      # single location. Without this an over-long URL raised an uncaught `PG::CheckViolation` out of
      # the charge, AFTER `begin_sitemaps` had committed the gate `in_progress` — so the gate never
      # terminalized, the stale-attempt sweep re-ran the identical traversal and raised identically,
      # and the host was wedged for the run's whole wall clock.
      MAX_SITEMAP_URL_BYTES = 8192

      def normalize(url, canonical_host)
        raw = url.to_s.strip
        return nil if raw.bytesize > MAX_SITEMAP_URL_BYTES

        decision = Wf004::SourceScopePredicate.evaluate(url: raw,
                                                        policies: [identity_policy(canonical_host)])
        # NFC here, so the traversal's dedup (`SitemapCandidates.distinct`, `@visited`) keys on the
        # SAME identity the charge ledger does. Hashing the fold while comparing raw bytes made two
        # spellings of one URL two candidates, two fetches and one charge.
        canonical = decision.allowed? ? decision.canonical_url.unicode_normalize(:nfc) : nil
        # The bound is asserted on what will actually be stored. Verified safe: no assigned code
        # point has `nfc.length > raw.bytesize`, and the CHECK counts characters while this counts
        # bytes, so passing here cannot fail there.
        canonical if canonical && canonical.bytesize <= MAX_SITEMAP_URL_BYTES
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
      # `charge` reserves one slot of the run-wide document budget and answers whether the run can
      # pay. It is invoked HERE — after the gate has granted and authorization has passed, and
      # immediately before the connection — because :437 counts "distinct canonical sitemap URLs"
      # and the code's own rule is that the unit is URLs ATTEMPTED.
      #
      # It used to be charged in the traversal loop, before the gate was even consulted. That made a
      # PACED candidate cost the run a document it never fetched, and the charge had no release
      # path (`reserve_sitemap_document` only ever increments), so FU-9's re-entry inherited a
      # strictly smaller budget every pass: a contended host burned the whole run-wide 50 without a
      # single network request, and the next pass then found every reservation refused, recorded
      # `sitemap_documents_limit` instead of a deferral, and terminalized the very
      # `sitemap_unavailable` outcome FU-9 exists to prevent — with a false `CrawlLimitReached`
      # beside it. Charging at the point an attempt genuinely begins removes the leak at its source
      # rather than adding a compensating release.
      def fetch_document(organization_id:, crawl_id:, canonical_host:, source_id:, gate_id:, url:, now:,
                         charge: nil)
        claim = claim_slot(organization_id, gate_id, now)
        # Distinguish "the host gate is pacing us" from "this candidate failed". Only the second is a
        # sitemap outcome; the first means try again after the interval the GATE names.
        return [DEFERRED, claim&.retry_after_ms || HostGate::REFUSAL_RETRY_MS] unless claim&.granted?

        begin
          unless authorized?(organization_id:, crawl_id:, source_id:, url:, gate_id:, now:)
            return Attempt.new(parsed: nil, status: nil, retryable: false, outcome: nil)
          end
          return DOCUMENTS_EXHAUSTED unless charge.nil? || charge.call

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
        # RENEW WHERE TIME IS SPENT, AND AT EVERY HOP (F-04 FU-24). The traversal only PACES on a gate
        # deferral or a retry, so a run of candidates that each answer slowly reaches no other boundary —
        # and one document is itself up to eleven bounded requests, because `REDIRECT_BUDGET` is ten and
        # F-01 takes a fresh deadline per hop. Two such documents behind a single renewal is ~330 seconds
        # under a 30-second lease. `Lease.owned?` guards the first connection, `redirect_guard` each one
        # after it; both are no-ops without a lease.
        return relinquished_outcome unless Platform::ScheduledActions::Lease.owned?

        @outbound.fetch(url, timeout_s: TIMEOUT_S, byte_cap: MAX_BODY_BYTES,
                        max_redirects: REDIRECT_BUDGET, user_agent: USER_AGENT,
                        redirect_guard: Platform::ScheduledActions::Lease.redirect_guard)
      rescue StandardError
        Platform::Outbound::Outcome.failure(:connection_failure, reason: :adapter_error, retryable: true,
                                           canonical_host: nil)
      end

      # No request was made because the lease had already moved. NONRETRYABLE deliberately: `fetch_paced`
      # must not pace and retry a candidate this delivery may not fetch at all, and the traversal stops at
      # its next boundary regardless, after which `call` reschedules rather than recording anything.
      def relinquished_outcome
        Platform::Outbound::Outcome.failure(:connection_failure,
                                            reason: :scheduled_action_lease_lost,
                                            retryable: false, canonical_host: nil)
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
      # Charge one distinct canonical sitemap URL against the run-wide budget. Returns true when the
      # run may attempt it — either because this call paid for it, or because an earlier pass
      # already did.
      #
      # The identity is DURABLE (`crawl_sitemap_document_charges`, `UNIQUE (crawl_id,
      # canonical_url_sha256)`), not a hash on this object. An in-memory memo can only mean "once
      # per traversal", and a `Traversal` is rebuilt on every `call`, so scheduler re-entry
      # re-charged every URL that had already reached the network — a host with one failing
      # candidate and one paced candidate spent the whole run-wide 50 on two distinct URLs and then
      # emitted the false `CrawlLimitReached` that FU-9 exists to prevent. :437's unit is DISTINCT
      # URLs, so the database adjudicates it.
      def reserve_document(organization_id:, project_id:, crawl_id:, canonical_url:, now:)
        Platform::UnitOfWork.run do |conn|
          raw = conn.raw_connection
          store = IdentityAccess::Infrastructure::CrawlBudgetStore.new(raw)
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          store.ensure_counters(id: @ids.generate, now:, correlation_id: @correlation_id,
                                organization_id:, project_id:, crawl_id:)
          outcome = store.charge_sitemap_document(
            organization_id:, project_id:, crawl_id:, canonical_url:, ceiling: documents_hard,
            id: @ids.generate, correlation_id: @correlation_id, now:
          )
          # The limit decision is written on the SAME transaction as the charge that produced it.
          observe_documents(raw, organization_id, project_id, crawl_id, outcome, now)
          outcome != :exhausted
        end
      end

      # :437's run-wide sitemap-document SOFT crossing, taken from the reservation that produced
      # it. The hard limb is recorded at terminalization instead, from the traversal's limit
      # reasons, because the bound is reachable by ordered retention as well as by this refusal.
      def observe_documents(pg, organization_id, project_id, crawl_id, outcome, now)
        return unless outcome == :granted

        observer = observer_for(pg, organization_id, project_id, crawl_id)
        return if observer.nil?

        used = IdentityAccess::Infrastructure::CrawlBudgetStore.new(pg)
                                                               .counters(organization_id, crawl_id)["sitemap_documents"].to_i
        observer.soft(DOCUMENTS_DIMENSION, used, now:) if used >= observer.soft_bound(DOCUMENTS_DIMENSION)
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
      def terminalize(organization_id, project_id, crawl_id, gate_id, token, result, now)
        in_unit(organization_id) do |store, raw|
          moved = store.terminalize_sitemaps(gate_id, token, now, state: result.state, reason: result.reason_code,
                                                   documents: result.documents_fetched,
                                                   max_depth: result.max_index_depth,
                                                   skipped: bounded(result.skipped, "url"),
                                                   limit_reasons: result.limit_reasons)
          # THE GUARD IS INSIDE THE TRANSACTION, AND BEFORE THE OBSERVATION. It used to sit after the
          # unit of work returned, which was harmless while the block held only this UPDATE — a
          # zero-row result committed nothing. Putting the limit decisions in the same block changed
          # that: a worker whose claim had been taken over by the stale-attempt sweep matched zero
          # rows here and still committed an immutable, once-per-run `CrawlLimitReached` for a
          # traversal whose outcome was discarded, after which the legitimate worker's own
          # observation collided and emitted nothing. Raising inside rolls both back together, which
          # is what `FetchContent#settle` already does.
          raise Platform::InvariantViolation, "sitemap terminal decision lost" if moved.to_i.zero?

          # The sitemap bounds are observed HERE rather than where each candidate was skipped,
          # because the traversal holds no transaction — and this is the transaction that makes the
          # outcome durable, so the decisions and the outcome they explain commit together.
          observe_sitemap_limits(raw, organization_id, project_id, crawl_id, result, now)
        end
      end

      # :437/:438's two sitemap bounds, recorded from the traversal's own `limit_reasons` — the
      # same list :450 uses to force `limit_reached` for the run.
      #
      # WHY FROM THE REASONS RATHER THAN FROM THE COUNTERS. The document bound is reachable two
      # ways: the run-wide reservation refusing, and the ORDERED RETENTION dropping candidates past
      # the bound before any of them is attempted (":450 only the first 50 distinct candidates in
      # that order are retained"). Watching only the reservation missed the second entirely — a run
      # that discovered sixty sitemaps and kept fifty recorded no limit at all. The traversal already
      # records the exact reason on both paths, so reading THAT is what makes the two agree.
      #
      # NOTE `sitemap_xml_limit` (the parser's 65-level / 50,001-element / 10 MiB decoded bounds)
      # deliberately produces NO decision row: the ratified `limit_dimension` enum has no member for
      # an XML structural limit. It still forces `limit_reached` through the sitemap outcome the
      # terminal checkpoint reads, so nothing is lost — but inventing a dimension for it would put a
      # value in a customer event that the contract does not admit.
      def observe_sitemap_limits(pg, organization_id, project_id, crawl_id, result, now)
        observer = observer_for(pg, organization_id, project_id, crawl_id)
        return if observer.nil?

        # ":442 — at any hard limit, record ... AFFECTED SOURCE AND URL COUNTS." The work a sitemap
        # bound abandons is SITEMAP CANDIDATES, which are not frontier entries at all — reporting
        # the unselected content frontier here named a population that will be crawled in full.
        if result.limit_reasons.include?(DOCUMENTS_LIMIT)
          observer.hard(DOCUMENTS_DIMENSION, observer.hard_bound(DOCUMENTS_DIMENSION), now:,
                        affected: skipped_for(result, DOCUMENTS_LIMIT))
        end

        # Soft is independent of hard: a run that nested past the bound reached the soft depth on
        # the way, and the once-per-run decision would otherwise lose that permanently.
        depth_hit = result.limit_reasons.include?(INDEX_DEPTH_LIMIT)
        observed_depth = depth_hit ? observer.hard_bound(INDEX_DEPTH_DIMENSION) + 1 : result.max_index_depth
        observer.soft(INDEX_DEPTH_DIMENSION, observed_depth, now:) if
          observed_depth >= observer.soft_bound(INDEX_DEPTH_DIMENSION)
        return unless depth_hit

        observer.hard(INDEX_DEPTH_DIMENSION, observed_depth, now:,
                      affected: skipped_for(result, INDEX_DEPTH_LIMIT))
      end

      # The sitemap URLs this bound abandoned, and the Sources they belong to. Discovery runs per
      # canonical host and a host belongs to one Source, so the Source count is 1 whenever anything
      # was skipped.
      def skipped_for(result, reason)
        urls = result.skipped.count { |s| s["reason"] == reason }
        LimitDecisions::Affected.new(sources: urls.zero? ? 0 : 1, urls:)
      end

      # The run's observation point, resolved ONCE per service instance: the bounds a decision
      # records must be the bounds the traversal enforced, and re-reading the policy per candidate
      # would allow an activation mid-traversal to split one run across two resolutions.
      # Called from INSIDE the caller's transaction, so it never resolves: `call` has already read
      # the policies on their own connection. Resolving here would open a nested unit of work, and
      # would also mean two crossings in one run could be judged against two resolutions.
      def observer_for(pg, organization_id, project_id, crawl_id)
        return nil if project_id.nil?

        @limit_decisions.for(pg, organization_id:, project_id:, crawl_id:, limits: bounds)
      end

      def resolution(organization_id, project_id)
        return EffectiveLimits::GLOBAL if project_id.nil?

        in_unit(organization_id) { |store| EffectiveLimits.resolve(store.active_crawl_policies(organization_id, project_id)) }
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
          # The frontier's own two bounds (discovered queue, depth) are observed inside `offer`, on
          # this transaction, so an admitted candidate and the decision its admission produced
          # commit together.
          observer = observer_for(conn, organization_id, project_id, crawl_id)
          urls.count { |url| admit(frontier, policy, scope, url, discovering, organization_id,
                                   project_id, crawl_id, source_id, now, observer) }
        end
      end

      def admit(frontier, policy, scope, url, discovering, organization_id, project_id, crawl_id,
                source_id, now, observer = nil)
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
          occurrence_document_url: discovering, observer:,
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
          # Candidates the gate never released, so they stay candidates across re-entry. (The
          # charge ledger is durable and lives in the database — see `charge_for`.)
          @deferred = {}
          @default_url = service.default_url(canonical_host)
          # nil until the default has been attempted; then true only if it answered 404/410.
          @default_absent = nil
        end

        def run(retained, declared_any:, discarded: [])
          discarded.each { |c| skip(c.canonical_url, DiscoverSitemaps::DOCUMENTS_LIMIT) }
          @pending = SitemapCandidates.order(retained)
          until @pending.empty?
            # A CONFIRMED TRANSFER ENDS THE TRAVERSAL, not merely the inner loop it was noticed in. The
            # `break`s in `fetch_paced` and `fetch_once` leave only their own per-candidate loops, so the
            # traversal moved on to the NEXT candidate and kept requesting, kept spending the run-wide
            # document budget and kept offering content URLs to the frontier — for a delivery that no
            # longer owned the action. Demonstrated: three further document requests and two URLs offered
            # after the pacer reported the transfer.
            break unless Platform::ScheduledActions::Lease.owned?

            candidate = @pending.shift
            next if @visited.key?(candidate.canonical_url)

            # :437 — "sitemap documents per RUN | 40 | 50 | distinct canonical sitemap URLs". The
            # budget is reserved from the CRAWL, not from this host: `crawl_host_gates` holds one row
            # per `(crawl, canonical_host)`, so a per-host counter would let a Crawl with ten Sources
            # on ten hosts fetch ten times the ratified maximum.
            #
            # The charge happens INSIDE `fetch_document`, once the gate has granted — see the note
            # there. A candidate that never reaches the network costs the run nothing, so a paced
            # host can be re-entered without its budget having moved. `@visited` is likewise only
            # marked once an attempt genuinely began: a deferred candidate must remain a candidate.
            children = visit(candidate)
            next if children == DiscoverSitemaps::DOCUMENTS_EXHAUSTED

            @visited[candidate.canonical_url] = candidate unless @deferred.key?(candidate.canonical_url)
            admit(children)
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

          retained, overflow = SitemapCandidates.retain(@visited.values + @pending + children,
                                                        limit: @service.documents_hard)
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
            return attempt if [DiscoverSitemaps::DEFERRED, DiscoverSitemaps::DOCUMENTS_EXHAUSTED].include?(attempt)

            last = attempt
            return attempt unless attempt.retryable

            break if @service.pace(FetchRetryPolicy.delay_ms(index + 1, attempt.outcome)) ==
                     Platform::ScheduledActions::LeaseKeeper::LOST
          end
          last
        end

        def fetch_once(candidate)
          DiscoverSitemaps::MAX_DEFERRALS_PER_CANDIDATE.times do
            attempt = @service.fetch_document(**@context.slice(:organization_id, :crawl_id, :canonical_host,
                                                               :source_id, :gate_id, :now),
                                              url: candidate.canonical_url,
                                              charge: charge_for(candidate))
            return attempt unless attempt.is_a?(::Array) && attempt.first == DiscoverSitemaps::DEFERRED

            # Wait the length the GATE reports, not a fixed constant: the interval is
            # max(base, robots Crawl-delay, ...), so pacing a `Crawl-delay: 10` host in 250 ms
            # increments merely burned the budget on a host that was perfectly reachable.
            #
            # A CONFIRMED LEASE TRANSFER ENDS THE TRAVERSAL. The lease-aware pacer reports it, and
            # discarding that report meant a delivery kept issuing requests after the database had told it
            # the action belonged to someone else — with :444's interval collapsed to zero, because the
            # wait returns immediately once ownership is gone.
            break if @service.pace(attempt.last) == Platform::ScheduledActions::LeaseKeeper::LOST
          end
          DiscoverSitemaps::DEFERRED
        end

        # One charge per DISTINCT candidate URL, taken at the moment its first real attempt begins
        # and adjudicated by `UNIQUE (crawl_id, canonical_url_sha256)`. :444's retries of the same
        # URL, and any later scheduler re-entry, resolve to `:already` in the database rather than to
        # a hash on this object that a fresh `Traversal` throws away.
        def charge_for(candidate)
          lambda do
            @service.reserve_document(**@context.slice(:organization_id, :project_id, :crawl_id, :now),
                                      canonical_url: candidate.canonical_url)
          end
        end

        # Fetch one candidate; return any child candidates a sitemap INDEX names.
        def visit(candidate)
          attempt = fetch_paced(candidate)
          if attempt == DiscoverSitemaps::DEFERRED
            @deferred[candidate.canonical_url] = true
            skip(candidate.canonical_url, DiscoverSitemaps::GATE_DEFERRED)
            return []
          end
          if attempt == DiscoverSitemaps::DOCUMENTS_EXHAUSTED
            skip(candidate.canonical_url, DiscoverSitemaps::DOCUMENTS_LIMIT)
            return DiscoverSitemaps::DOCUMENTS_EXHAUSTED
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
          unless SitemapCandidates.within_index_depth?(depth, limit: @service.index_depth_hard)
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
