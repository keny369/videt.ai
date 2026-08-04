# frozen_string_literal: true

require "rails_helper"

# `Platform::PgInstant.after_wait` — the decision instant a handler uses once it holds the lock it
# waited for (owner ruling 1 of the round-6 programme; blockers R6-1, R6-5, R6-6).
#
# The decode half of this module is proved by the authorized WF-005 single-surface check, which is
# scoped to decoding and must stay that way. This file proves the READING, against a real transaction
# on real PostgreSQL, because the property is about elapsed database time and nothing in-process can
# stand in for it.
RSpec.describe Platform::PgInstant, type: :model do
  self.use_transactional_tests = false

  # Elapsed database time, inside one transaction, without an in-process sleep deciding anything.
  def in_transaction_after(seconds)
    Platform::UnitOfWork.run do |conn|
      raw = conn.raw_connection
      raw.exec_params("SELECT pg_sleep($1)", [seconds])
      yield raw
    end
  end

  it "PROOF 146 — advances the caller's instant by the transaction's own elapsed database time" do
    entered = Time.utc(2026, 7, 27, 10, 0, 0, 123_456)

    decided = in_transaction_after(0.05) { |raw| described_class.after_wait(raw, entered_with: entered) }

    # The wait happened, so the instant moved: this is the whole point, and a `after_wait` that
    # returned its argument would fail here.
    expect(decided).to be > entered
    expect(decided - entered).to be >= 0.05
    # And it moved by the WAIT, not by the gap between the fixture's era and today. A 20-second
    # ceiling is three orders of magnitude below that gap and two above the sleep.
    expect(decided - entered).to be < 20
  end

  it "PROOF 147 — is an advance on the caller's axis, never a `clock_timestamp()` reading" do
    # THE MUTATION THIS KILLS is the obvious reading of "use database time": `SELECT clock_timestamp()`.
    # Every instant this value is compared against — `crawls.deadline_at`, `crawls.started_at`,
    # `entitlement_reservations.lease_due` — is written by an application clock, so a raw database
    # reading would judge an application-clock deadline on a second axis and make every boundary
    # depend on host-to-database skew. `CrawlHostGateStore#reservation_executing?` states the same
    # rule for the same reason.
    entered = Time.utc(2020, 1, 1, 0, 0, 0)
    real_now = Time.now.utc

    decided = in_transaction_after(0.01) { |raw| described_class.after_wait(raw, entered_with: entered) }

    expect(decided).to be < (entered + 60)
    expect(decided).to be < (real_now - (365 * 24 * 3600))
  end

  it "PROOF 148 — preserves microseconds and returns UTC, and never moves backwards" do
    entered = Time.new(2026, 7, 27, 20, 0, 0 + Rational(654_321, 1_000_000), "+10:00")

    decided = in_transaction_after(0.0) { |raw| described_class.after_wait(raw, entered_with: entered) }

    expect(decided.utc?).to be(true)
    expect(decided).to be >= entered.getutc
    # Sub-second exactness survives the round trip: the advance is computed in PostgreSQL at
    # microsecond resolution, so the fractional part is the entry's plus the elapsed, not a rounding.
    expect(decided - entered.getutc).to be < 20
    expect(((decided - entered.getutc) * 1_000_000).to_i).to be >= 0
  end

  # ---- :442's boundary, exactly (round 8, R8-9) --------------------------------
  #
  # WHY THESE LIVE HERE AND NOT AT `Admission`. The comparison used to be spelled out at three call
  # sites, each judging an instant produced by `after_wait` — whose advance is a number of microseconds
  # nobody can predict. Exact equality was therefore unconstructible from outside, which is why
  # weakening `Admission`'s `<=` to `<` survived the entire repository suite. Moving the boundary to
  # this module is what makes the exact case reachable: these operands are chosen, not measured.
  describe ".expired? — :442's \"AT 60 elapsed minutes\"" do
    # The run's own clock, at microsecond resolution, with a fractional deadline so that no assertion
    # here can be satisfied by whole-second luck.
    let(:deadline) { Time.utc(2026, 8, 4, 11, 0, 0 + Rational(123_456, 1_000_000)) }
    def usec(n) = Rational(n, 1_000_000)

    it "PROOF 180 — one microsecond BEFORE the deadline is not expired" do
      expect(described_class.expired?(deadline, at: deadline - usec(1))).to be(false)
    end

    it "PROOF 181 — EXACTLY at the deadline IS expired, which is the whole of :442's \"AT\"" do
      # THE MUTATION THIS KILLS: `<=` to `<`. Nothing else in the repository can fail for it — the
      # difference between the two is exactly this instant and no other.
      expect(described_class.expired?(deadline, at: deadline)).to be(true)
    end

    it "PROOF 182 — one microsecond AFTER the deadline is expired" do
      expect(described_class.expired?(deadline, at: deadline + usec(1))).to be(true)
    end

    it "PROOF 183 — the boundary survives the encodings a connection may deliver" do
      # ROUND 4's R4-1 WAS A TRUNCATION, NOT A COMPARISON. `Time.parse(value.to_s)` formats a `Time`
      # to whole seconds, so a deadline 123,456 microseconds past the second compared as though it
      # were at the second — and the tie never fired at the real boundary. Both operands go through
      # `utc`, so the text encoding a bare libpq connection returns decides identically to the `Time`
      # a pooled connection returns.
      text = deadline.iso8601(6)
      expect(described_class.expired?(text, at: deadline)).to be(true)
      expect(described_class.expired?(text, at: deadline - usec(1))).to be(false)
      expect(described_class.expired?(deadline, at: (deadline - usec(1)).iso8601(6))).to be(false)
      # A whole-second TRUNCATION of either side would answer `true` here, because it would compare
      # 11:00:00 against 11:00:00 rather than 11:00:00.123456 against 11:00:00.000001.
      expect(described_class.expired?(deadline, at: deadline.change(usec: 1))).to be(false)
    end

    it "PROOF 184 — it reads no clock of its own, and a NULL deadline never expires" do
      # A RECOMPUTATION FROM `Time.now` would make the answer depend on when the example ran rather
      # than on the operands. Both of these instants are decades from now in opposite directions.
      expect(described_class.expired?(Time.utc(1990, 1, 1), at: Time.utc(1990, 1, 1) - usec(1))).to be(false)
      expect(described_class.expired?(Time.utc(2200, 1, 1), at: Time.utc(2200, 1, 1))).to be(true)
      expect(described_class.expired?(nil, at: Time.utc(2200, 1, 1))).to be(false)
    end

    # DEADLINE COMPARISONS THAT ARE A DIFFERENT QUESTION, each with the reason it is. "Is this run
    # over?" and "may this action be SCHEDULED at this instant?" are not the same sentence, and :442
    # answers them differently at the boundary: a run AT its deadline is over, while an action due
    # exactly AT the deadline is "the last honest opportunity" whose pass will then find the clock
    # expired and halt. Both of these carry that reasoning in their own headers already.
    #
    # A COMPARISON IN NEITHER THIS LIST NOR `expired?` FAILS PROOF 185, which is the property that
    # matters: the next one has to be classified rather than defaulted.
    CLASSIFIED_DEADLINE_COMPARISONS = {
      "app/workflows/wf005/crawl_fetch_due_schedule.rb" =>
        ["return { entry_id:, beyond_deadline: true } if deadline && now > deadline",
         "due_at = deadline if deadline && due_at > deadline"],
      "app/workflows/wf005/crawl_driver.rb" =>
        ["return nil if deadline && at > deadline"],
      # A DURATION AGAINST A CEILING, not an instant against a boundary. `remaining` is how much of
      # the run's clock is left; the comparison decides whether the per-request timeout or the run's
      # remainder is the tighter bound (:442's "incomplete requests are canceled", FU-34). Equality
      # picks the unbounded branch, which is correct: a remainder exactly equal to the ceiling is not
      # a shorter budget.
      "app/workflows/wf005/fetch_content.rb" =>
        ["return WallClockBudget.new(seconds: bounds.timeout_s, bounded: false) if remaining > bounds.timeout_s"]
    }.freeze

    it "PROOF 185 — every WF-005 RUN-EXPIRY test is this one function" do
      # THE PROPERTY THAT KEEPS IT ONE RULE. Three copies of "is this run over" is three chances to
      # invert a direction, and round 8 found the copy nobody could construct a test for. Any WF-005
      # line that compares a deadline must be `Platform::PgInstant.expired?` or must be classified
      # above as a different question.
      # A LOCAL BOUND FROM A DEADLINE IS STILL A DEADLINE. `d = crawl["deadline_at"]` followed by
      # `utc(d) < now` names the column on one line and compares on another, and a rule that matched
      # text alone would see neither — which is the escape round 6 and round 8 both found, one rule
      # at a time. Names bound from a deadline expression are carried, per file.
      offenders = Dir[Rails.root.join("app/workflows/wf005/**/*.rb")].sort.flat_map do |file|
        relative = Pathname(file).relative_path_from(Rails.root).to_s
        classified = CLASSIFIED_DEADLINE_COMPARISONS.fetch(relative, [])
        # The seed is a SUBSTRING because the column is `deadline_at` and a word boundary would not
        # match it; carried names are whole words because `d` must not match `deadline`.
        tainted = Set.new
        File.read(file).lines.each_with_index.filter_map do |line, index|
          text = line.strip
          next if text.start_with?("#")

          mentions = lambda do |source|
            source.include?("deadline") ||
              tainted.any? { |name| source.match?(/\b#{Regexp.escape(name)}\b/) }
          end
          # `x = <expression naming a deadline>` taints `x` for the rest of the file.
          if (binding_match = text.match(/\A([a-z_][a-zA-Z_0-9]*)\s*=[^=~>]\s*(.+)\z/)) &&
             mentions.call(binding_match[2])
            tainted << binding_match[1]
          end
          next unless mentions.call(text)
          # An ORDERING operator, not a hash rocket, not an assignment, not a comment.
          next unless text.gsub("=>", "").match?(/[<>]/)
          next if classified.include?(text)

          "#{relative}:#{index + 1}: #{text}"
        end
      end

      expect(offenders).to be_empty, <<~MESSAGE
        A WF-005 file compares a deadline itself instead of asking Platform::PgInstant.expired?, and
        is not classified as a different question. :442's run-expiry boundary is one rule with one
        owner, because a second copy is a second direction to invert:
        #{offenders.join("\n")}
      MESSAGE
    end

    it "PROOF 186 — the classification list names only comparisons that still exist" do
      # The exclusions may not rot into a way of silencing PROOF 185: a classified line that has been
      # edited or deleted is removed rather than left to excuse whatever later takes its place.
      CLASSIFIED_DEADLINE_COMPARISONS.each do |relative, lines|
        source = Rails.root.join(relative).read
        lines.each do |line|
          expect(source).to include(line), "#{relative} no longer contains the classified comparison"
        end
      end
    end
  end
end
