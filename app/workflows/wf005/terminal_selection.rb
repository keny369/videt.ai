# frozen_string_literal: true

module Workflows
  module Wf005
    # :458'S TERMINAL SELECTION, AS A PURE FUNCTION OVER WHAT THE RUN RECORDED (S-07-009).
    #
    # "Terminal selection occurs once at a serialized checkpoint. ... Otherwise zero valid Documents or
    # failure of every active Source root yields `Crawl.Failed`; otherwise the Crawl completes. The single
    # completion reason follows precedence `canceled`, `failed`, `limit_reached`, `partial_source_failure`,
    # then `completed`. Any in-scope candidate not evaluated because of depth, sitemap, queue, page, byte,
    # response, request, or wall-clock bound makes coverage partial and records its exact limit reason. A
    # completed Crawl is `full` only when every in-scope candidate admitted by the frozen discovery rules
    # reached a terminal covered outcome and no Source or discovery path has an unresolved failure."
    #
    # NO DATABASE, NO CLOCK, NO IDENTITY. Everything this needs is counted by the caller in one serialized
    # transaction and handed in; the derivation itself is total, order-independent and exhaustively
    # testable without a run. MTX-030 says the same thing from the other side — "coverage and readiness
    # derivation are pure functions over the manifest" — and the manifest here is
    # `crawl_terminal_outcomes` plus `crawl_limit_decisions` plus the host gates, which are the three
    # records :452, :442 and :450 respectively make authoritative.
    #
    # `canceled` IS ABSENT FROM THIS FUNCTION AND THAT IS DELIBERATE. :458 puts it first in the precedence
    # and settles it by ORDER OF COMMIT, not by derivation: "a cancellation committed strictly before that
    # checkpoint yields `Crawl.Canceled`; a cancellation at or after the checkpoint is rejected as
    # `crawl_already_terminal`". `CancelCrawl` writes that state itself, and the guard then refuses every
    # edge out of it, so a checkpoint arriving afterwards finds a terminal Crawl and derives nothing. A
    # `canceled` limb here would be a second implementation of a rule the state machine already enforces.
    module TerminalSelection
      COMPLETED = "completed"
      FAILED = "failed"
      LIMIT_REACHED = "limit_reached"
      PARTIAL_SOURCE_FAILURE = "partial_source_failure"

      FULL = "full"
      PARTIAL = "partial"

      # What the checkpoint counted. Every field is a fact the run wrote down, not a judgement:
      #
      #   * `documents` — outcomes recording :436's accepted page (`document_created`). :453's "a run is
      #     failed when it yields zero valid Documents" is measured over these. THE INTERIM BOUNDARY IS
      #     STATED RATHER THAN HIDDEN: nothing creates a `documents` row yet (S-07-010 owns them), and the
      #     accepted `crawl_terminal_outcomes` migration already ratified `document_created` with
      #     `document_id` NULL as the representation of a fetch that did everything :436 asks. S-07-010
      #     must confirm this against the artifact; until it exists there is nothing truer to read.
      #   * `roots` — one entry per ACTIVE pinned Source: did its depth-zero URL reach `document_created`?
      #     :452 — "a Source root succeeds only when its depth-zero URL ultimately creates a valid Document
      #     after in-scope redirects; every other root outcome is a Source-root failure EVEN IF another URL
      #     for that Source succeeds."
      #   * `fetch_failures` — outcomes recording `content_fetch_failed`, which :452 keeps in the
      #     denominator and which makes coverage partial.
      #   * `unresolved_discovery` — hosts whose sitemap discovery ended `sitemap_unavailable` (:450 —
      #     "link discovery may continue but coverage is PARTIAL") or whose robots record is fail-closed.
      #   * `hard_limits` — `crawl_limit_decisions` rows at the hard threshold. :442 — at a hard limit
      #     "set `coverage_status=partial` and `completion_reason=limit_reached`."
      #   * `uncovered` — outcomes in the denominator that did not reach a covered outcome, and
      #     `unevaluated` — in-scope candidates discarded by a bound without an outcome at all. :458's
      #     `full` requires that neither exists.
      Facts = Data.define(:documents, :roots_total, :roots_succeeded, :fetch_failures,
                          :unresolved_discovery, :hard_limits, :uncovered, :unevaluated) do
        # :453 — "A run is failed when it yields zero valid Documents OR every active Source root fails."
        # The second limb is not implied by the first: a run can create a Document from a sitemap-found URL
        # while every root itself failed, and :452 is explicit that another URL succeeding does not rescue
        # a root. `roots_total.zero?` cannot happen on an accepted start (the gate refuses a run with no
        # active pinned Source), and is treated as failure rather than as vacuous success because a run
        # with no root produced nothing.
        def failed? = documents.zero? || roots_total.zero? || roots_succeeded.zero?

        def root_failures = roots_total - roots_succeeded
      end

      Selection = Data.define(:state, :completion_reason, :coverage_status)

      def self.derive(facts)
        return Selection.new(state: FAILED, completion_reason: FAILED, coverage_status: nil) if facts.failed?

        Selection.new(state: COMPLETED, completion_reason: completion_reason(facts),
                      coverage_status: coverage_status(facts))
      end

      # :458's precedence, minus the two limbs the state machine settles: `canceled` by commit order and
      # `failed` by the caller above. What remains is `limit_reached` over `partial_source_failure` over
      # `completed`, and :452 states the same order from the other end — "a limit hit takes the higher
      # `limit_reached` precedence already defined".
      def self.completion_reason(facts)
        return LIMIT_REACHED if facts.hard_limits.positive?
        # :452 — "For a completed run with NO LIMIT HIT, any Source-root failure, `content_fetch_failed`,
        # or `sitemap_unavailable` yields `completion_reason=partial_source_failure`; otherwise it is
        # `completed`." Three causes, one reason, and all three are counted separately by the caller so
        # the audit record can say which of them fired.
        return PARTIAL_SOURCE_FAILURE if facts.root_failures.positive? ||
                                         facts.fetch_failures.positive? ||
                                         facts.unresolved_discovery.positive?

        COMPLETED
      end

      # :458 — "A completed Crawl is `full` ONLY WHEN every in-scope candidate admitted by the frozen
      # discovery rules reached a terminal covered outcome AND no Source or discovery path has an
      # unresolved failure." Plus the sentence before it: "any in-scope candidate not evaluated because of
      # depth, sitemap, queue, page, byte, response, request, or wall-clock bound makes coverage partial".
      #
      # Written as a conjunction of the four things that must be ABSENT rather than as a re-derivation of
      # the completion reason, because they are different questions: a run can complete with reason
      # `completed` and still be partial (a candidate discarded by the discovered-queue bound is not a
      # Source failure, and there is no `content_fetch_failed` to point at), and the direction of an error
      # here is always the same one — coverage that reads better than the run was.
      def self.coverage_status(facts)
        uncovered = facts.uncovered.positive? || facts.unevaluated.positive?
        return PARTIAL if uncovered || facts.hard_limits.positive?
        return PARTIAL if facts.root_failures.positive? || facts.unresolved_discovery.positive?

        FULL
      end
    end
  end
end
