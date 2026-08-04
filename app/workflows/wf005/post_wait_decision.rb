# frozen_string_literal: true

module Workflows
  module Wf005
    # THE ONE PLACE WF-005 SAYS WHAT IS TRUE AFTER A LOCK WAIT (owner ruling 1 of the round-6
    # programme; round-6 blockers R6-1, R6-5, R6-6).
    #
    # THE RULE. Any handler that waits on a lock before an irreversible decision must, once it holds
    # that lock and before its first durable write:
    #
    #   1. re-read the authoritative state it is about to act on;
    #   2. take its decision instant from database time, not from the value it entered with;
    #   3. re-check any time-sensitive lease or deadline against that instant;
    #   4. re-check current human authority where the command depends on one;
    #   5. write nothing derived from the pre-wait snapshot.
    #
    # WHY IT IS ONE CLASS AND NOT THREE CAREFUL HANDLERS. Round 5's R5-3 repair added the state
    # re-read to `Admission` and stopped there, because "re-read and re-authorize" reads like a
    # statement about ROWS. Round 6 then found the same wait unrepaired along three other axes: the
    # instant in `Admission` (R6-1), the human authority in `CancelCrawl` (R6-5) and the entitlement
    # settlement instant in `CompleteCrawl` (R6-6). Three handlers each revalidating a different
    # subset is what produced that, so the subset is named here, once, and every waiting handler is
    # constructed from this object rather than from its own reading of the rule.
    #
    # WHAT IT OWNS AND WHAT IT DELIBERATELY DOES NOT. It owns the decision instant, the terminal-state
    # vocabulary and the authority recheck's call site. It does NOT own the re-read itself: the three
    # handlers read through three different stores under three different locks, and a fourth store
    # wrapping them would be a second persistence surface for rows that already have one. The re-read
    # therefore stays in the handler, next to the lock that makes it meaningful, and this object is
    # what the handler asks for everything the re-read cannot answer on its own.
    #
    # NOT A UNIT OF WORK. It is constructed INSIDE the caller's transaction, after the caller's locks
    # are held, and it opens nothing.
    class PostWaitDecision
      # :458's "once". A Crawl in any of these has had its one terminal selection, and both waiting
      # handlers refuse against the same list rather than each spelling it out — `CancelCrawl` to
      # answer :458's own `crawl_already_terminal` token, `CompleteCrawl` to distinguish a second
      # delivery from a Crawl that never started.
      TERMINAL_STATES = %w[completed failed canceled].freeze

      # `anchored_at` is the database instant `entered_with` was true at. A handler that captures its
      # instant inside its own unit of work may omit it; a caller that captured one earlier and did
      # work in between — `CrawlDriver#advance`, whose robots fetch and sitemap discovery run outside
      # every transaction — must supply it, or the elapsed time before its transaction opened is
      # invisible to the decision (round 7, C-1).
      def initialize(connection, entered_with:, anchored_at: nil)
        @connection = connection
        @entered_with = entered_with
        @anchored_at = anchored_at
      end

      # THE DECISION INSTANT, measured by PostgreSQL after the wait (`Platform::PgInstant.after_wait`,
      # which carries the reasoning for why it is an advance over the caller's instant rather than a
      # raw `clock_timestamp()` reading).
      #
      # MEMOIZED, because one decision is made at one instant. Reading it twice inside a handler would
      # let the deadline test and the record it writes disagree by however long the writes took, which
      # is the same class of defect one step smaller.
      def now
        @now ||= Platform::PgInstant.after_wait(@connection, entered_with: @entered_with,
                                                             anchored_at: @anchored_at)
      end

      def terminal?(crawl) = TERMINAL_STATES.include?(crawl["state"])

      # THE HUMAN AUTHORITY THE COMMAND IS ABOUT TO SPEND, RE-READ (:335, SEC-REQ-004/005).
      #
      # `CommandAuthorizer.authority_current?` is the ratified durable-checkpoint recheck and stays
      # the only implementation; this is its call site for a WF-005 handler that WAITS. The platform
      # deferral recorded at DECISIONS.md § S-06-006 covers handlers that authorize and act with no
      # wait between the two, where the window is a few statements wide. A handler that can block on
      # `crawl-frontier:<crawl>` for as long as another transaction holds it is not that case: a
      # revocation, suspension or policy change can commit in the middle, and the stale allowed
      # decision would still perform an irreversible cancel, release and event.
      def authority_current?(auth_store:, actor:)
        IdentityAccess::Authorization::CommandAuthorizer.authority_current?(store: auth_store, actor:)
      end

      # THE SAME RECHECK, RETURNING PROOF INSTEAD OF A BOOLEAN (round 9, R9-3).
      #
      # A boolean can be short-circuited past by adding one operand to the guard that reads it, and
      # round 9's review did exactly that on an axis two rounds of branch matrices had not driven —
      # committing a policy activation on revoked authority. An ATTESTATION cannot be short-circuited
      # past, because the protected write demands one and only a passing recheck mints one. The
      # handler still branches on nil exactly as it branched on false; what changed is that skipping
      # the branch no longer reaches a commit.
      def authority_attestation(auth_store:, actor:)
        AuthorityAttestation.attest(@connection, auth_store:, actor:)
      end
    end
  end
end
