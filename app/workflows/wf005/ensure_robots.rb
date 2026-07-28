# frozen_string_literal: true

require "digest"

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
      # :444 — one initial attempt plus at most two retries.
      MAX_ATTEMPTS = 3

      FAIL_CLOSED = "robots_unavailable_fail_closed"
      # :448 — robots is fetched with the ratified crawler token.
      USER_AGENT = RobotsPolicy::AGENT_TOKEN

      Result = Data.define(:state, :reason_code, :terminal, :retryable) do
        def terminal? = terminal
        def fetchable? = %w[rules_applied no_restrictions].include?(state)
      end

      def initialize(store, outbound: Platform::Outbound)
        @store = store
        @outbound = outbound
      end

      # Resolve robots for the host, performing at most ONE network attempt per call. The caller
      # re-invokes for a retryable outcome under :444's schedule; the record carries the attempt
      # count, so the bound survives process loss.
      #
      # `gate` is the current row. Returns a Result; when it is terminal the record is written and
      # frozen. The network call happens OUTSIDE any transaction the caller holds — MTX-030 is
      # explicit that no external call sits inside a database transaction.
      def call(organization_id:, gate:, now:)
        return already(gate) if terminal?(gate["robots_state"])

        claimed = @store.begin_robots(gate["id"], gate["state_version"].to_i, now)
        return contended if claimed.to_i.zero?

        outcome = fetch(gate["canonical_host"])
        decide(organization_id:, gate_id: gate["id"], attempt: gate["robots_attempt_count"].to_i + 1,
               outcome:, now:)
      end

      private

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

      def decide(organization_id:, gate_id:, attempt:, outcome:, now:)
        gate = reload(organization_id, gate_id)
        return contended if gate.nil? || gate["robots_state"] != "in_progress"

        verdict = classify(outcome)
        if verdict[:retry] && attempt < MAX_ATTEMPTS
          @store.defer_robots(gate_id, gate["state_version"].to_i, now)
          return Result.new(state: "pending", reason_code: verdict[:reason], terminal: false, retryable: true)
        end

        # An exhausted retry schedule IS the fail-closed outcome (:448), not a separate error.
        state = verdict[:retry] ? "unavailable" : verdict[:state]
        reason = verdict[:retry] ? FAIL_CLOSED : verdict[:reason]
        write_terminal(gate_id, gate, now, state, reason, outcome, verdict)
        Result.new(state:, reason_code: reason, terminal: true, retryable: false)
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

      def write_terminal(gate_id, gate, now, state, reason, outcome, _verdict)
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
        moved = @store.terminalize_robots(gate_id, gate["state_version"].to_i, now, row)
        raise Platform::InvariantViolation, "robots terminal decision lost" if moved.to_i.zero?
      end

      def response_status(outcome)
        outcome.respond_to?(:response?) && outcome.response? ? outcome.status.to_i : nil
      end

      def reload(organization_id, gate_id)
        @store.lock_gate(organization_id, gate_id)
      end

      def terminal?(state) = %w[rules_applied no_restrictions unavailable].include?(state)

      def already(gate)
        Result.new(state: gate["robots_state"], reason_code: gate["robots_terminal_reason"],
                   terminal: true, retryable: false)
      end

      # Another worker holds the attempt; the caller re-reads rather than racing it.
      def contended = Result.new(state: "in_progress", reason_code: nil, terminal: false, retryable: true)
    end
  end
end
