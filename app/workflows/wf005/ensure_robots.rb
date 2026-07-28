# frozen_string_literal: true

require "digest"
require "securerandom"

module Workflows
  module Wf005
    # Resolve `robots.txt` for one `(crawl, canonical_host)`, FAIL-CLOSED
    # (WORKFLOW_SPECIFICATIONS.md :448; SEARCH_CRAWL_RETRIEVAL.md § Robots And Sitemap Processing —
    # "One robots record exists per `(crawl_id, canonical_host)` ... Content dispatch is blocked
    # until that record is terminal").
    #
    # :448 fixes the outcomes exactly, and this is the whole decision table:
    #
    #   valid 2xx body           -> `rules_applied`, rules parsed by the pure RobotsPolicy
    #   404 or 410               -> `no_restrictions` ("means no robots restrictions")
    #   401 or 403               -> `unavailable`  ] each "denies all content fetching for that host
    #   body over 1 MiB          -> `unavailable`  ] for the run and records
    #   exhausted timeout / 5xx  -> `unavailable`  ] `robots_unavailable_fail_closed`
    #
    # Anything not in that table also fails closed. The owner's direction is the tie-breaker for
    # every case Volume I does not enumerate: "Fail closed whenever authorization or robots semantics
    # are uncertain."
    #
    # DETERMINISM ACROSS RETRIES. The decision is a pure function of the HTTP outcome, and it is
    # written ONCE — the schema makes the terminal robots columns write-once, so a later attempt can
    # never reopen a host that failed closed. Retries are bounded by :444's fixed schedule (one
    # initial attempt plus at most two retries, for timeout/408/429/5xx only); exhausting them is
    # itself the fail-closed outcome, not an error. A non-retryable status terminalizes immediately.
    class EnsureRobots
      ROBOTS_PATH = "/robots.txt"

      # :448 — "under the same request timeout/retry bounds with a 1 MiB response maximum".
      MAX_BODY_BYTES = RobotsPolicy::MAX_BODY_BYTES
      TIMEOUT_S = CrawlPolicy::GLOBAL_CEILING.fetch("request_timeout_seconds").fetch("hard")
      # :444 — one initial attempt plus at most two retries, with EXACTLY these delays after the
      # first and second failed attempts. A `Retry-After` of 1..120 seconds replaces that retry's
      # delay; every other value is ignored.
      MAX_ATTEMPTS = 3
      RETRY_DELAYS_S = { 1 => 30, 2 => 120 }.freeze
      RETRY_AFTER_MIN_S = 1
      RETRY_AFTER_MAX_S = 120

      FAIL_CLOSED = "robots_unavailable_fail_closed"
      # :448 — robots is fetched with the ratified crawler token.
      USER_AGENT = RobotsPolicy::AGENT_TOKEN

      # `retry_after_ms` is the :444 delay the caller must wait before the next attempt — the fixed
      # 30s/120s schedule, or a `Retry-After` of 1..120s when the response supplied one.
      Result = Data.define(:state, :reason_code, :terminal, :retryable, :retry_after_ms) do
        def terminal? = terminal
        def fetchable? = %w[rules_applied no_restrictions].include?(state)
      end

      def initialize(outbound: Platform::Outbound, correlation_id: nil)
        @outbound = outbound
        @correlation_id = correlation_id || SecureRandom.uuid_v7
      end

      # Resolve robots for the host, performing at most ONE network attempt per call. The caller
      # re-invokes for a retryable outcome under :444's schedule; the record carries the attempt
      # count, so the bound survives process loss.
      #
      # THREE PHASES, because MTX-030 `transaction_boundary` ends "No external call sits inside a
      # database transaction" — and a robots fetch may block for the full request timeout, so holding
      # the gate's row lock across it would stall every other worker on that host:
      #
      #   1. claim the attempt (`pending -> in_progress`) in its own transaction, and COMMIT;
      #   2. perform the network fetch holding NO transaction and NO lock;
      #   3. record the outcome in a second transaction, re-reading the row under its lock.
      #
      # This is the shape the accepted `Wf003::ObserveAutomatedSlot` uses for the same reason.
      def call(organization_id:, crawl_id:, canonical_host:, now:)
        claim = claim_attempt(organization_id:, crawl_id:, canonical_host:, now:)
        return claim[:result] if claim[:result]

        # PHASE 2 — outside every transaction and every lock.
        outcome = fetch(canonical_host)

        record(organization_id:, gate_id: claim[:gate_id], attempt: claim[:attempt], outcome:, now:)
      end

      private

      # PHASE 1. Returns either a terminal `:result` (already resolved, or contended) or the claimed
      # `:gate_id`/`:attempt` to fetch for.
      def claim_attempt(organization_id:, crawl_id:, canonical_host:, now:)
        Platform::UnitOfWork.run do |conn|
          store = new_store(conn, organization_id)
          gate = store.gate(organization_id, crawl_id, canonical_host)
          next { result: contended } if gate.nil?
          next { result: already(gate) } if terminal?(gate["robots_state"])

          locked = store.lock_gate(organization_id, gate["id"])
          next { result: already(locked) } if terminal?(locked["robots_state"])
          next { result: contended } if store.begin_robots(locked["id"], locked["state_version"].to_i, now).to_i.zero?

          { gate_id: locked["id"], attempt: locked["robots_attempt_count"].to_i + 1 }
        end
      end

      # PHASE 3.
      def record(organization_id:, gate_id:, attempt:, outcome:, now:)
        Platform::UnitOfWork.run do |conn|
          store = new_store(conn, organization_id)
          decide(store:, organization_id:, gate_id:, attempt:, outcome:, now:)
        end
      end

      def new_store(conn, organization_id)
        IdentityAccess::Infrastructure::CrawlHostGateStore.new(conn.raw_connection).tap do |store|
          store.enter_org_context(org: organization_id, correlation_id: @correlation_id)
        end
      end

      def fetch(canonical_host)
        @outbound.fetch("https://#{canonical_host}#{ROBOTS_PATH}",
                        timeout_s: TIMEOUT_S, byte_cap: MAX_BODY_BYTES + 1,
                        max_redirects: 0, user_agent: USER_AGENT)
      rescue StandardError
        # An adapter defect must not leave the host unresolved and the run wedged: treat it as a
        # retryable transport failure and let the attempt bound turn exhaustion into fail-closed.
        Platform::Outbound::Outcome.failure(:connection_failure, reason: :adapter_error,
                                            retryable: true, canonical_host:)
      end

      def decide(store:, organization_id:, gate_id:, attempt:, outcome:, now:)
        gate = store.lock_gate(organization_id, gate_id)
        return contended if gate.nil? || gate["robots_state"] != "in_progress"

        verdict = classify(outcome)
        if verdict[:retry] && attempt < MAX_ATTEMPTS
          store.defer_robots(gate_id, gate["state_version"].to_i, now)
          return Result.new(state: "pending", reason_code: verdict[:reason], terminal: false,
                            retryable: true, retry_after_ms: retry_delay_ms(attempt, outcome))
        end

        # An exhausted retry schedule IS the fail-closed outcome (:448), not a separate error.
        state = verdict[:retry] ? "unavailable" : verdict[:state]
        reason = verdict[:retry] ? FAIL_CLOSED : verdict[:reason]
        write_terminal(store, gate_id, gate, now, state, reason, outcome)
        Result.new(state:, reason_code: reason, terminal: true, retryable: false, retry_after_ms: nil)
      end

      # :444 — "Retry delays are exactly 30 seconds after completion of the first failed attempt and
      # 120 seconds after completion of the second failed attempt. A valid integer `Retry-After` from
      # 1 through 120 seconds replaces that retry's delay; every other value is ignored."
      def retry_delay_ms(attempt, outcome)
        header = retry_after_seconds(outcome)
        seconds = header || RETRY_DELAYS_S.fetch(attempt, RETRY_DELAYS_S.values.last)
        seconds * 1000
      end

      def retry_after_seconds(outcome)
        return nil unless outcome.respond_to?(:headers) && outcome.headers.is_a?(::Hash)

        raw = outcome.headers.find { |k, _v| k.to_s.downcase == "retry-after" }&.last.to_s
        return nil unless /\A\d+\z/.match?(raw)

        value = raw.to_i
        # "from 1 through 120 seconds ... every other value is ignored" — including 0 and >120.
        value.between?(RETRY_AFTER_MIN_S, RETRY_AFTER_MAX_S) ? value : nil
      end

      # The :448 decision table. `retry: true` means "retryable under the :444 schedule", which
      # becomes fail-closed once the schedule is exhausted.
      def classify(outcome)
        return transport_verdict(outcome) unless outcome.respond_to?(:response?) && outcome.response?

        status = outcome.status.to_i
        return { state: "unavailable", reason: FAIL_CLOSED, retry: false } if oversize?(outcome)

        case status
        when 200..299 then { state: "rules_applied", reason: nil, retry: false }
        when 404, 410 then { state: "no_restrictions", reason: "robots_absent", retry: false }
        when 401, 403 then { state: "unavailable", reason: FAIL_CLOSED, retry: false }
        when 408, 429 then { state: "unavailable", reason: FAIL_CLOSED, retry: true }
        when 500..599 then { state: "unavailable", reason: FAIL_CLOSED, retry: true }
        else
          # Every other status is uncertain, so it fails closed rather than being read as permission.
          { state: "unavailable", reason: FAIL_CLOSED, retry: false }
        end
      end

      # A timeout, connection or resolver failure is retryable; a TLS failure and a
      # destination-safety rejection are not (:446 `destination_address_prohibited` is nonretryable).
      def transport_verdict(outcome)
        retryable = outcome.respond_to?(:retryable) && outcome.retryable
        { state: "unavailable", reason: FAIL_CLOSED, retry: retryable }
      end

      # :448 — "content over 1 MiB" fails closed. The reader is given a cap one byte above the
      # maximum, so a body that reaches the cap is over it.
      def oversize?(outcome)
        outcome.byte_count.to_i > MAX_BODY_BYTES || (outcome.respond_to?(:truncated) && outcome.truncated)
      end

      def write_terminal(store, gate_id, gate, now, state, reason, outcome)
        rules = nil
        row = { state:, reason:, http_status: response_status(outcome), rules: nil, rules_schema: nil,
                agent_group: nil, crawl_delay_ms: nil, sitemaps: [], source_sha256: nil }

        if state == "rules_applied"
          body = outcome.body.to_s
          rules = RobotsPolicy.parse(body)
          row = row.merge(rules: rules.to_json_h, rules_schema: RobotsPolicy::RULES_SCHEMA,
                          agent_group: rules.agent_group, crawl_delay_ms: rules.crawl_delay_ms,
                          sitemaps: rules.sitemaps, source_sha256: Digest::SHA256.digest(body))
        end
        moved = store.terminalize_robots(gate_id, gate["state_version"].to_i, now, row)
        raise Platform::InvariantViolation, "robots terminal decision lost" if moved.to_i.zero?
      end

      def response_status(outcome)
        outcome.respond_to?(:response?) && outcome.response? ? outcome.status.to_i : nil
      end

      def terminal?(state) = %w[rules_applied no_restrictions unavailable].include?(state)

      def already(gate)
        Result.new(state: gate["robots_state"], reason_code: gate["robots_terminal_reason"],
                   terminal: true, retryable: false, retry_after_ms: nil)
      end

      # Another worker holds the attempt; the caller re-reads rather than racing it.
      def contended
        Result.new(state: "in_progress", reason_code: nil, terminal: false, retryable: true,
                   retry_after_ms: nil)
      end
    end
  end
end
