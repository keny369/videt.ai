# frozen_string_literal: true

module Workflows
  module Wf005
    # :452'S EXHAUSTIVE COVERAGE CLASSIFICATION, AS A FUNCTION OF THE OUTCOME (S-07-009; FU-21).
    #
    # "The content coverage set is every distinct canonical in-scope candidate retained by
    # deduplication, PLUS every in-scope candidate discarded by a Crawl limit; robots-disallowed URLs,
    # duplicate occurrences, unsupported media types, and redirect targets rejected by current scope are
    # recorded as `policy_excluded` and are OUTSIDE the denominator. An admitted content URL has a
    # COVERED outcome ONLY WHEN it creates a valid Document, or returns terminal 404/410 and creates a
    # valid body-free `crawl_observation` with reason `content_absent`." Plus, further down the same
    # paragraph, "`robots_unavailable_fail_closed` makes that Source root failed and coverage partial".
    #
    # THE EFFECT IS DERIVED, NEVER CHOSEN. A writer that got to decide "this one was covered" would be
    # deciding the number the customer reads, and the direction of the mistake that matters is always
    # the same: coverage that reads better than reality. So the caller supplies WHAT HAPPENED and this
    # supplies what it means, and `crawl_terminal_outcomes_coverage_agreement` then refuses any row
    # where the two disagree — the same rule stated twice, once where it is applied and once where it
    # cannot be evaded.
    #
    # THE DUPLICATION WITH THE MIGRATION IS DELIBERATE AND IS PINNED BY A PROOF. The CHECK's vocabulary
    # lives in `CreateCrawlTerminalOutcomes`, which is a migration class and is not loadable at runtime,
    # so this map cannot import it and the two could drift. PROOF 41 reads the LIVE constraint out of
    # `pg_constraint` and asserts this map against it in both directions, which is the only form of that
    # check worth having: a spec that compared this constant to itself would agree by construction.
    module CoverageClassification
      COVERED = "covered"
      NOT_COVERED = "not_covered"
      EXCLUDED = "excluded"

      # :448's fail-closed robots record, which :452 names by this token. It is not a `FetchContent`
      # outcome because no content request was ever made — that is precisely FU-21's case, and the whole
      # reason this vocabulary is wider than the fetch's.
      ROBOTS_UNAVAILABLE = "robots_unavailable_fail_closed"

      EFFECTS = {
        FetchContent::DOCUMENT_CREATED => COVERED,
        FetchContent::CONTENT_ABSENT => COVERED,
        FetchContent::POLICY_EXCLUDED => EXCLUDED,
        FetchContent::FETCH_FAILED => NOT_COVERED,
        FetchContent::LIMIT_DISCARDED => NOT_COVERED,
        ROBOTS_UNAVAILABLE => NOT_COVERED
      }.freeze

      # What one frontier entry's retirement records. `reason` is :456's "its EXACT limit reason", and it
      # is nil on a covered outcome because there is nothing to explain.
      Decision = Data.define(:outcome, :coverage_effect, :reason)

      # RAISES RATHER THAN GUESSES, and the choice is worth stating because the failure is loud either
      # way. This runs inside the transaction that releases :454's depth seal, so an unclassifiable
      # outcome aborts that transaction and the entry stays claimed — which is FU-22's stranded claim,
      # recoverable, and strictly better than retiring an entry under an invented classification, which
      # is irreversible (`crawl_terminal_outcomes` is T-IMM and the frontier guard admits no edge out of
      # `terminal`). The CHECK would refuse both rows anyway; what this adds is the name of what broke.
      def self.of(outcome:, reason:)
        effect = EFFECTS[outcome]
        raise Platform::InvariantViolation, "unclassifiable terminal outcome: #{outcome.inspect}" if effect.nil?

        if effect == COVERED
          # `content_absent` arrives carrying its own name as a reason code, and :456 asks for a reason
          # only from an entry that did not reach a covered outcome. The outcome column already says
          # which of :452's two covered forms this was, so the reason would be a restatement.
          return Decision.new(outcome:, coverage_effect: effect, reason: nil)
        end
        if reason.to_s.empty?
          raise Platform::InvariantViolation, "terminal outcome #{outcome} carries no reason"
        end

        Decision.new(outcome:, coverage_effect: effect, reason:)
      end
    end
  end
end
