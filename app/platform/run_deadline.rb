# frozen_string_literal: true

module Platform
  # :442'S RUN DEADLINE AS A VALUE, NOT AS A COMPARABLE INSTANT (round 9, R9-7 and the :442
  # cross-deadline defect).
  #
  # WHY THE BOUNDARY KEPT COMING BACK. Round 8 found `<=` weakened to `<` surviving the whole suite.
  # Round 9 gave the comparison one owner, `PgInstant.expired?`, and defended the ownership with a
  # per-line text scan — which round 9's review defeated with ONE METHOD INDIRECTION, then inverted
  # the boundary at a line the same candidate had just written, and passed 2223 examples. A rule that
  # says "everyone must call the owner" is only as strong as its ability to notice someone who did
  # not, and a text scan cannot notice a helper.
  #
  # SO THERE IS NOTHING LEFT TO REIMPLEMENT. A deadline is no longer an instant that callers compare;
  # it is a value that answers the three questions :442 actually asks, and NOTHING ELSE:
  #
  #   * `expired?(at:)`        — "at 60 elapsed minutes, no new request starts". EQUALITY IS EXPIRY.
  #   * `remaining_seconds(from:)` — how much of the run's clock a request may still use, which is
  #     what bounds an in-flight request (":442 ... and incomplete requests are canceled").
  #   * `not_after(instant)`   — the clamp a scheduler needs, where :442 permits an action due
  #     exactly AT the deadline as the last honest opportunity.
  #
  # WHAT THIS OBJECT DOES AND DOES NOT CLAIM, corrected. An earlier version of this comment said it
  # "carries no `<`, no `<=`, no `>`, no `>=` and no way to hand out the raw instant, so ... there is
  # no second implementation to write". That was FALSE four ways — `beyond?`, `at?` and `not_after`
  # all compare, and `instant_for_transport` hands out the raw instant — and the round-10 review
  # inverted :442's boundary through that very accessor with the whole suite green.
  #
  # The claim is narrowed to what is true: this is the ONE OWNER of :442's comparison, and every gate
  # is proved BY CALLER-BOUND INVOCATION to consult it as part of its own execution
  # (`spec/acceptance/wf005_deadline_gates_spec.rb`). It is not claimed that no reimplementation can
  # be written — that is a claim about every expression anyone could spell, and six rounds of trying
  # to enumerate them failed. It is claimed, and proved, that a gate which reimplements the boundary
  # does not invoke this owner and is caught there.
  class RunDeadline
    NONE = Object.new.tap do |none|
      def none.expired?(**) = false
      def none.remaining_seconds(**) = nil
      def none.not_after(instant) = instant
      # A RUN WITH NO DEADLINE IS PAST NOTHING AND AT NOTHING. Both are asked of a value that can be
      # NONE — `CrawlFetchDueSchedule.link` asks `beyond?`, `CancelCrawl` asks `at?` — and shipping
      # without them made both declared no-deadline branches raise `NoMethodError` (R10-4). A null
      # object that does not satisfy the interface its callers use is a crash with a comment on it.
      def none.beyond?(_instant) = false
      def none.at?(_instant) = false
      def none.present? = false
      def none.inspect = "#<Platform::RunDeadline NONE>"
    end.freeze

    # The deadline of a crawl row, or NONE when the run has none. This is the ONE decode of
    # `deadline_at` in the repository; every other reader asks this object a question instead.
    def self.of(row, column = "deadline_at")
      raw = row.is_a?(Hash) ? row[column] : row
      return NONE if raw.nil?

      new(PgInstant.utc(raw))
    end

    def initialize(instant)
      @instant = instant
      freeze
    end

    def present? = true

    # :442 SAYS "AT 60 ELAPSED MINUTES", SO EQUALITY IS EXPIRY. The one comparison in the repository.
    def expired?(at:) = @instant <= PgInstant.utc(at)

    # What is left of the run's clock, floored at zero. Nil has no meaning here — a run with no
    # deadline is `NONE`, which answers nil — so a caller can treat a number as a number.
    def remaining_seconds(from:)
      remaining = @instant - PgInstant.utc(from)
      remaining.negative? ? 0.0 : remaining
    end

    # The scheduling clamp: never past the run's own deadline, and AT it is permitted, which is the
    # reasoning `crawl_fetch_due_schedule.rb` already carries — "an action due exactly at the deadline
    # is the last honest opportunity, and the pass it runs will find the wall clock expired and halt".
    def not_after(instant)
      candidate = PgInstant.utc(instant)
      candidate > @instant ? @instant : candidate
    end

    # Past the deadline entirely — the scheduler's "do not link at all" question, distinct from
    # `expired?` because it asks about a FUTURE instant rather than about now.
    def beyond?(instant) = PgInstant.utc(instant) > @instant

    # :458's EXACT-INSTANT TIE. A cancellation requested at the very instant the checkpoint fires is
    # the one case the contract settles by commit order rather than by comparison, and `CancelCrawl`
    # needs to recognise it without being handed something it could compare loosely.
    def at?(instant) = PgInstant.utc(instant) == @instant

    # THE ONE WAY OUT, AND IT IS NAMED FOR WHY IT EXISTS. F-04's `scheduled_actions` is a FROZEN
    # transport that takes a plain instant and does its own arithmetic; it must not learn about a
    # WF-005 value object, or the foundation would depend on the workflow. Handing the instant across
    # that boundary is a deliberate, named act rather than an accessor a caller can reach for to
    # rebuild a comparison — which is why it is not called `to_time`.
    def instant_for_transport = @instant
    def inspect = "#<Platform::RunDeadline #{@instant.iso8601(6)}>"
  end
end
