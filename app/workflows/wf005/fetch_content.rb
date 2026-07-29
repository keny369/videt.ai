# frozen_string_literal: true

require "digest"
require "securerandom"

module Workflows
  module Wf005
    # Content fetch for one frontier entry (S-07-007; WORKFLOW_SPECIFICATIONS.md :436, :442, :444,
    # :446, :448, :452; SEARCH_CRAWL_RETRIEVAL.md § Destination And HTTP Safety).
    #
    # The order of operations is the specification, not a convenience:
    #
    #   1. CLAIM the host slot (:442's rolling-rate and concurrency predicates, under a row lock).
    #   2. AUTHORIZE at execution time — Organization, Crawl, Project, Source, reservation, current
    #      Source Scope, robots. Never queue-time authority: S-07-004's dequeue check is necessary
    #      and not sufficient, and the owner's direction on this block is explicit.
    #   3. RESERVE bytes from the run-wide budget BEFORE the body is read (:442).
    #   4. CLAIM the attempt row, so a worker lost mid-request leaves a record rather than a hole.
    #   5. FETCH, with the caller's redirect guard rechecking robots and Source Scope on every hop
    #      before it is followed (:448) — the platform owns destination safety, the caller owns
    #      policy, and neither can be inferred from the other.
    #   6. MEASURE against :442's max-of-two-paths formula and the sentinel rule.
    #   7. COMMIT the accounted bytes and RELEASE the unused remainder, in one statement.
    #   8. TERMINALISE the attempt write-once, and RELEASE the host slot however it ended.
    #
    # Steps 1, 2, 3, 4, 7 and 8 are each their own transaction, and step 5 is inside NONE of them:
    # MTX-030 requires that no external call sits inside a database transaction, and a fetch that
    # held the gate row would serialise every other worker on that host behind a network round trip.
    class FetchContent
      TIMEOUT_S = CrawlPolicy::GLOBAL_CEILING.fetch("request_timeout_seconds").fetch("hard")
      REDIRECT_BUDGET = CrawlPolicy::GLOBAL_CEILING.fetch("redirects_per_url").fetch("hard")
      USER_AGENT = RobotsPolicy::AGENT_TOKEN
      MAX_ATTEMPTS = FetchRetryPolicy::MAX_ATTEMPTS

      # :436 — "has a media type before parameters of `text/html` or `application/xhtml+xml`".
      DOCUMENT_MEDIA_TYPES = %w[text/html application/xhtml+xml].freeze

      # :452's exhaustive vocabulary for one admitted content URL.
      DOCUMENT_CREATED = "document_created"
      CONTENT_ABSENT = "content_absent"
      FETCH_FAILED = "content_fetch_failed"
      POLICY_EXCLUDED = "policy_excluded"
      LIMIT_DISCARDED = "limit_discarded"

      # Reasons, kept as constants because :452 and :456 both read them by name.
      REASONS = {
        gate_deferred: "host_gate_deferred",
        unauthorized: "fetch_not_authorized",
        budget_exhausted: "run_byte_budget_exhausted",
        page_limit: "page_limit_discarded",
        over_limit: ByteAccounting::OVER_LIMIT,
        unsupported_media: "unsupported_media_type",
        redirect_policy: "redirect_policy_denied",
        redirect_limit: "redirect_limit_exhausted",
        unreachable: "content_unreachable",
        http_error: "content_http_error",
        contended: "attempt_contended"
      }.freeze

      Result = Data.define(:outcome, :reason_code, :attempt_id, :http_status, :accounted_bytes,
                           :probe_bytes, :media_type, :body, :final_url, :redirect_count, :retryable) do
        def document? = outcome == DOCUMENT_CREATED
        # :452 — an admitted URL is `covered` only when it creates a valid Document, or returns a
        # terminal 404/410 and creates a valid body-free observation.
        def covered? = [DOCUMENT_CREATED, CONTENT_ABSENT].include?(outcome)
        # :452 — "`content_fetch_failed` ... REMAINS IN THE DENOMINATOR and makes coverage partial".
        def reduces_coverage? = outcome == FETCH_FAILED
        # :452 — robots-disallowed URLs, unsupported media types and redirect targets rejected by
        # current scope are "recorded as `policy_excluded` and are OUTSIDE the denominator".
        def in_denominator? = outcome != POLICY_EXCLUDED
      end

      def initialize(outbound: Platform::Outbound, ids: Platform::Ids.system, correlation_id: nil,
                     pacer: ->(ms) { sleep(ms.to_i / 1000.0) })
        @outbound = outbound
        @ids = ids
        @correlation_id = correlation_id || SecureRandom.uuid_v7
        @pacer = pacer
      end

      def pace(milliseconds) = @pacer.call(milliseconds)

      # Fetch one frontier entry's URL. `entry` is the claimed `crawl_frontier_entries` row.
      def call(organization_id:, crawl_id:, entry:, gate_id:, now:)
        crawl = load_crawl(organization_id, crawl_id)
        return excluded(REASONS[:unauthorized]) if crawl.nil?

        context = {
          organization_id:, crawl_id:, gate_id:, now:,
          project_id: crawl["project_id"], source_id: entry["source_id"],
          entry_id: entry["id"], canonical_url: entry["canonical_url"],
          canonical_host: host_of(entry["canonical_url"]), depth: entry["depth"].to_i
        }
        attempt_loop(context, entry)
      end

      private

      # :444 — one initial attempt plus at most two retries, with the attempt NUMBER read from
      # committed state so a process loss cannot reset it.
      def attempt_loop(context, entry)
        last = nil
        MAX_ATTEMPTS.times do
          number = next_attempt_number(context)
          return last || excluded(REASONS[:contended]) if number > MAX_ATTEMPTS

          last = one_attempt(context, entry, number)
          return last unless last.retryable

          pace(FetchRetryPolicy.delay_ms(number, @last_outcome))
        end
        last
      end

      def one_attempt(context, entry, number)
        claim = claim_slot(context)
        return deferred(claim) unless claim&.granted?

        begin
          return excluded(REASONS[:unauthorized]) unless authorized?(context)

          bounds = effective_bounds(context)
          reserved = reserve_bytes(context, bounds)
          return limit_discarded(REASONS[:budget_exhausted]) if reserved.nil?

          attempt = claim_attempt(context, entry, number, reserved)
          return release_and(context, reserved, excluded(REASONS[:contended])) if attempt.nil?

          perform(context, attempt, reserved, bounds)
        ensure
          release_slot(context, claim.lease_token)
        end
      end

      # The network call, and everything that depends on its result. No transaction is open here.
      def perform(context, attempt, reserved, bounds)
        outcome = fetch(context, reserved)
        @last_outcome = outcome
        measurement = measure(outcome, reserved)
        commit_bytes(context, reserved, measurement)
        result = classify(outcome, measurement, context, reserved, bounds)
        terminalize(context, attempt, result, outcome, measurement)
        result
      end

      # ---- the fetch -------------------------------------------------------------

      # The redirect guard is :448's "redirects are rechecked against robots and Source Scope Policy
      # BEFORE FOLLOWING", expressed where the connector can act on it. Retrospective validation of
      # the final URL would not satisfy the sentence: the disallowed intermediate would already have
      # been requested, which is both a robots violation and a request the run cannot account for.
      def fetch(context, reserved)
        guard = redirect_guard(context)
        @outbound.fetch(context[:canonical_url], timeout_s: TIMEOUT_S, byte_cap: reserved,
                        max_redirects: REDIRECT_BUDGET, user_agent: USER_AGENT, redirect_guard: guard)
      rescue StandardError
        Platform::Outbound::Outcome.failure(:connection_failure, reason: :adapter_error, retryable: true)
      end

      def redirect_guard(context)
        lambda do |uri|
          in_unit(context[:organization_id]) do |store|
            gate = store.lock_gate(context[:organization_id], context[:gate_id])
            next false if gate.nil?

            FetchAuthorization.new(store).authorize(
              organization_id: context[:organization_id], crawl_id: context[:crawl_id],
              source_id: context[:source_id], canonical_url: uri.to_s, gate:,
              now: context[:now], kind: "content"
            ).allowed?
          end
        rescue StandardError
          # Fail closed. An error deciding whether a hop is permitted is not permission.
          false
        end
      end

      # ---- measurement and classification ---------------------------------------

      # Measured against the RESERVATION, not the per-URL ceiling. The body was capped at what was
      # reserved, and :442 says "an attempt cannot add accounted bytes BEYOND ITS RESERVATION" — so
      # a body stopped at reservation+1 is over ITS bound even when that bound is below the per-URL
      # maximum, which happens whenever the run's remaining budget is the tighter of the two.
      def measure(outcome, reserved)
        return nil unless outcome.respond_to?(:response?) && outcome.response?

        ByteAccounting.measure(received: outcome.byte_count, ceiling: reserved)
      end

      # :436's accepted-page definition and :452's exhaustive outcome table, in the order the
      # specification states them — a URL that fails an earlier test never reaches a later one.
      def classify(outcome, measurement, context, reserved, bounds)
        unless outcome.respond_to?(:response?) && outcome.response?
          return transport_outcome(outcome)
        end

        status = outcome.status.to_i
        # :452 — "returns terminal 404/410 and creates a valid body-free crawl_observation with
        # reason content_absent" is COVERED, not a failure.
        return absent(outcome) if [404, 410].include?(status)
        return failed(REASONS[:http_error], outcome, retryable: FetchRetryPolicy.retryable?(outcome)) unless (200..299).cover?(status)
        # :442 — "observing a sentinel byte FAILS THAT URL as over-limit". A body at exactly the
        # maximum is fine; one byte past it is not.
        #
        # WHICH bound it exceeded decides the outcome, and the two are genuinely different. Over the
        # PER-URL maximum is a property of the response: :452 makes it `content_fetch_failed`, in
        # the denominator, coverage partial. Over a reservation that was smaller only because the
        # RUN's byte budget was nearly spent is a run-limit hit: :442 says to "stop scheduling
        # affected work" and record the dimension, which is a limit discard, not a failure of this
        # URL. Collapsing them would blame the site for the run's budget.
        if measurement&.over_limit?
          return failed(REASONS[:over_limit], outcome, measurement:) if reserved >= bounds.per_url

          return limit_discarded(REASONS[:budget_exhausted], outcome:, measurement:)
        end

        media = media_type_of(outcome)
        # :452 — "unsupported media types ... are recorded as `policy_excluded` and are OUTSIDE the
        # denominator", which is why this is not a failure.
        unless DOCUMENT_MEDIA_TYPES.include?(media)
          return excluded(REASONS[:unsupported_media], outcome:, measurement:, media:)
        end
        # :436 — the accepted page must also still be in scope at its FINAL url; a redirect that
        # stayed safe and passed every hop guard can still land somewhere current scope excludes.
        return excluded(REASONS[:redirect_policy], outcome:, measurement:, media:) unless final_in_scope?(context, outcome)
        return limit_discarded(REASONS[:page_limit], outcome:, measurement:, media:) unless reserve_page(context)

        Result.new(outcome: DOCUMENT_CREATED, reason_code: nil, attempt_id: nil, http_status: status,
                   accounted_bytes: measurement&.accounted.to_i, probe_bytes: measurement&.probe_bytes.to_i,
                   media_type: media, body: outcome.body, final_url: outcome.final_url,
                   redirect_count: outcome.redirect_count.to_i, retryable: false)
      end

      # :452 — "Exhausted timeout/408/429/5xx, DNS/TLS/connection failure, other 4xx, redirect-limit
      # exhaustion ... is `content_fetch_failed`". A caller-policy redirect denial is different: the
      # target was excluded by policy, not by failure, so :452 puts it outside the denominator.
      def transport_outcome(outcome)
        if outcome.respond_to?(:rejected?) && outcome.rejected?
          return excluded(REASONS[:redirect_policy], outcome:) if outcome.reason == :redirect_policy_denied
          return failed(REASONS[:redirect_limit], outcome) if outcome.reason == :redirect_rejected

          return failed(outcome.reason.to_s, outcome)
        end

        failed(REASONS[:unreachable], outcome, retryable: FetchRetryPolicy.retryable?(outcome))
      end

      def absent(outcome)
        Result.new(outcome: CONTENT_ABSENT, reason_code: CONTENT_ABSENT, attempt_id: nil,
                   http_status: outcome.status.to_i, accounted_bytes: 0, probe_bytes: 0,
                   media_type: nil, body: nil, final_url: outcome.final_url,
                   redirect_count: outcome.redirect_count.to_i, retryable: false)
      end

      def failed(reason, outcome = nil, retryable: false, measurement: nil)
        build(FETCH_FAILED, reason, outcome, measurement, retryable:)
      end

      def excluded(reason, outcome: nil, measurement: nil, media: nil)
        build(POLICY_EXCLUDED, reason, outcome, measurement, media:)
      end

      def limit_discarded(reason, outcome: nil, measurement: nil, media: nil)
        build(LIMIT_DISCARDED, reason, outcome, measurement, media:)
      end

      def build(outcome_name, reason, outcome, measurement, retryable: false, media: nil)
        Result.new(outcome: outcome_name, reason_code: reason, attempt_id: nil,
                   http_status: outcome&.status&.to_i, accounted_bytes: measurement&.accounted.to_i,
                   probe_bytes: measurement&.probe_bytes.to_i, media_type: media, body: nil,
                   final_url: outcome&.final_url, redirect_count: outcome&.redirect_count.to_i,
                   retryable:)
      end

      def deferred(claim)
        Result.new(outcome: LIMIT_DISCARDED, reason_code: REASONS[:gate_deferred], attempt_id: nil,
                   http_status: nil, accounted_bytes: 0, probe_bytes: 0, media_type: nil, body: nil,
                   final_url: nil, redirect_count: 0, retryable: false).tap do
          @retry_after_ms = claim&.retry_after_ms
        end
      end

      def media_type_of(outcome)
        headers = outcome.headers
        return nil unless headers.is_a?(::Hash)

        raw = headers.find { |k, _v| k.to_s.downcase == "content-type" }&.last
        raw.to_s.split(";").first.to_s.strip.downcase.presence
      end

      # NOTE: an endless method cannot carry its own rescue; written out so the rescue binds to
      # THIS method rather than to the class body, where it would silently swallow load errors.
      def host_of(url)
        URI.parse(url.to_s).host.to_s.downcase
      rescue URI::InvalidURIError
        ""
      end

      # ---- transactions ----------------------------------------------------------

      def in_unit(organization_id)
        Platform::UnitOfWork.run do |conn|
          raw = conn.raw_connection
          store = IdentityAccess::Infrastructure::CrawlHostGateStore.new(raw)
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          yield store, raw
        end
      end

      def budget_unit(organization_id)
        Platform::UnitOfWork.run do |conn|
          store = IdentityAccess::Infrastructure::CrawlBudgetStore.new(conn.raw_connection)
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          yield store
        end
      end

      def attempt_unit(organization_id)
        Platform::UnitOfWork.run do |conn|
          store = IdentityAccess::Infrastructure::FetchAttemptStore.new(conn.raw_connection)
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
          yield store
        end
      end

      def load_crawl(organization_id, crawl_id)
        in_unit(organization_id) { |store| store.crawl(organization_id, crawl_id) }
      end

      def claim_slot(context)
        in_unit(context[:organization_id]) do |store|
          HostGate.new(store, ids: @ids, correlation_id: @correlation_id)
                  .claim(organization_id: context[:organization_id], gate_id: context[:gate_id],
                         now: context[:now], kind: "content")
        end
      end

      def release_slot(context, lease_token)
        in_unit(context[:organization_id]) { |store| store.release_slot(context[:gate_id], lease_token, context[:now]) }
      end

      def authorized?(context)
        in_unit(context[:organization_id]) do |store|
          gate = store.lock_gate(context[:organization_id], context[:gate_id])
          FetchAuthorization.new(store).authorize(
            organization_id: context[:organization_id], crawl_id: context[:crawl_id],
            source_id: context[:source_id], canonical_url: context[:canonical_url], gate:,
            now: context[:now], kind: "content"
          ).allowed?
        end
      end

      def final_in_scope?(context, outcome)
        final = outcome.final_url
        return true if final.nil? || final == context[:canonical_url]

        in_unit(context[:organization_id]) do |store|
          gate = store.lock_gate(context[:organization_id], context[:gate_id])
          next false if gate.nil?

          FetchAuthorization.new(store).authorize(
            organization_id: context[:organization_id], crawl_id: context[:crawl_id],
            source_id: context[:source_id], canonical_url: final, gate:,
            now: context[:now], kind: "content"
          ).allowed?
        end
      end

      # :390 — the operative bounds are the most restrictive of global safety and every active
      # Organization/Project policy, resolved HERE rather than carried from queue time.
      def effective_bounds(context)
        rows = in_unit(context[:organization_id]) do |store|
          store.active_crawl_policies(context[:organization_id], context[:project_id])
        end
        sets = rows.map { |r| JSON.parse(r["normalized_bounds"]) }.select { |s| CrawlPolicy.complete?(s) }
        ByteAccounting.bounds_from(CrawlPolicy.most_restrictive(CrawlPolicy::GLOBAL_CEILING, *sets))
      rescue JSON::ParserError, KeyError
        ByteAccounting::GLOBAL_BOUNDS
      end

      # :442 — reserve BEFORE the body is read, sized from what the run has left. A shrinking
      # reservation is retried down to nothing rather than abandoned on the first loss, because
      # another worker committing between the read and the write is normal, not exceptional.
      def reserve_bytes(context, bounds)
        budget_unit(context[:organization_id]) do |store|
          ensure_counters(store, context)
          3.times do
            row = store.counters(context[:organization_id], context[:crawl_id])
            remaining = bounds.per_run - row["reserved_response_bytes"].to_i
            want = ByteAccounting.reservation(remaining:, per_url: bounds.per_url)
            break nil if want.zero?

            granted = store.reserve_bytes(context[:organization_id], context[:crawl_id], want,
                                          bounds.per_run, context[:now])
            break want if granted
          end
        end
      end

      def ensure_counters(store, context)
        store.ensure_counters(id: @ids.generate, now: context[:now], correlation_id: @correlation_id,
                              organization_id: context[:organization_id], project_id: context[:project_id],
                              crawl_id: context[:crawl_id])
      end

      def commit_bytes(context, reserved, measurement)
        budget_unit(context[:organization_id]) do |store|
          store.commit_bytes(context[:organization_id], context[:crawl_id], reserved,
                             measurement&.accounted.to_i, measurement&.probe_bytes.to_i, context[:now])
        end
      end

      def release_and(context, reserved, result)
        budget_unit(context[:organization_id]) do |store|
          store.release_bytes(context[:organization_id], context[:crawl_id], reserved, context[:now])
        end
        result
      end

      def reserve_page(context)
        budget_unit(context[:organization_id]) do |store|
          !store.reserve_page(context[:organization_id], context[:crawl_id],
                              CrawlPolicy::GLOBAL_CEILING.fetch("accepted_pages").fetch("hard"),
                              context[:now]).nil?
        end
      end

      def next_attempt_number(context)
        attempt_unit(context[:organization_id]) do |store|
          store.attempt_count(context[:organization_id], context[:crawl_id], context[:entry_id], "content") + 1
        end
      end

      def claim_attempt(context, entry, number, reserved)
        attempt_unit(context[:organization_id]) do |store|
          store.claim(id: @ids.generate, now: context[:now], correlation_id: @correlation_id,
                      organization_id: context[:organization_id], project_id: context[:project_id],
                      crawl_id: context[:crawl_id], source_id: context[:source_id],
                      frontier_entry_id: context[:entry_id], kind: "content", attempt_number: number,
                      canonical_url: context[:canonical_url], canonical_host: context[:canonical_host],
                      depth: context[:depth], scope_policy_id: entry["scope_policy_id"],
                      scope_policy_version: entry["scope_policy_version"],
                      crawl_policy_id: nil, crawl_policy_version: nil, reserved_bytes: reserved)
        end
      end

      def terminalize(context, attempt, result, outcome, measurement)
        attempt_unit(context[:organization_id]) do |store|
          store.terminalize(attempt["id"], attempt["state_version"].to_i, context[:now],
                            outcome: result.outcome, reason_code: result.reason_code,
                            http_status: result.http_status,
                            accounted_response_bytes: measurement&.accounted,
                            received_body_bytes: measurement&.received,
                            expanded_body_bytes: measurement&.expanded,
                            limit_probe_bytes: measurement&.probe_bytes.to_i,
                            media_type: result.media_type, redirect_count: result.redirect_count,
                            final_url: result.final_url,
                            body_sha256: result.body && Digest::SHA256.digest(result.body),
                            retryable: result.retryable,
                            latency_ms: outcome.respond_to?(:latency_ms) ? outcome.latency_ms : nil)
        end
      end
    end
  end
end
