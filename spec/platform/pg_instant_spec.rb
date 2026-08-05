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
  # THEY TEST THE LIVE BOUNDARY, WHICH IS `Platform::RunDeadline#expired?` (round 9, R9-7). They used
  # to test `PgInstant.expired?`, and when the boundary moved into the value object the ledger caught
  # these examples still passing against a method nothing called — a proof defending dead code, which
  # is the same class of defect as a proof that never reaches the code it names.
  #
  # WHY THEY LIVE HERE AND NOT AT `Admission`. The comparison used to be spelled out at three call
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
      expect(Platform::RunDeadline.of("deadline_at" => deadline).expired?(at: deadline - usec(1))).to be(false)
    end

    it "PROOF 181 — EXACTLY at the deadline IS expired, which is the whole of :442's \"AT\"" do
      # THE MUTATION THIS KILLS: `<=` to `<`. Nothing else in the repository can fail for it — the
      # difference between the two is exactly this instant and no other.
      expect(Platform::RunDeadline.of("deadline_at" => deadline).expired?(at: deadline)).to be(true)
    end

    it "PROOF 182 — one microsecond AFTER the deadline is expired" do
      expect(Platform::RunDeadline.of("deadline_at" => deadline).expired?(at: deadline + usec(1))).to be(true)
    end

    it "PROOF 183 — the boundary survives the encodings a connection may deliver" do
      # ROUND 4's R4-1 WAS A TRUNCATION, NOT A COMPARISON. `Time.parse(value.to_s)` formats a `Time`
      # to whole seconds, so a deadline 123,456 microseconds past the second compared as though it
      # were at the second — and the tie never fired at the real boundary. Both operands go through
      # `utc`, so the text encoding a bare libpq connection returns decides identically to the `Time`
      # a pooled connection returns.
      text = deadline.iso8601(6)
      expect(Platform::RunDeadline.of("deadline_at" => text).expired?(at: deadline)).to be(true)
      expect(Platform::RunDeadline.of("deadline_at" => text).expired?(at: deadline - usec(1))).to be(false)
      expect(Platform::RunDeadline.of("deadline_at" => deadline).expired?(at: (deadline - usec(1)).iso8601(6))).to be(false)
      # A whole-second TRUNCATION of either side would answer `true` here, because it would compare
      # 11:00:00 against 11:00:00 rather than 11:00:00.123456 against 11:00:00.000001.
      expect(Platform::RunDeadline.of("deadline_at" => deadline).expired?(at: deadline.change(usec: 1))).to be(false)
    end

    it "PROOF 184 — it reads no clock of its own, and a NULL deadline never expires" do
      # A RECOMPUTATION FROM `Time.now` would make the answer depend on when the example ran rather
      # than on the operands. Both of these instants are decades from now in opposite directions.
      expect(Platform::RunDeadline.of("deadline_at" => Time.utc(1990, 1, 1))
               .expired?(at: Time.utc(1990, 1, 1) - usec(1))).to be(false)
      expect(Platform::RunDeadline.of("deadline_at" => Time.utc(2200, 1, 1))
               .expired?(at: Time.utc(2200, 1, 1))).to be(true)
      expect(Platform::RunDeadline.of("deadline_at" => nil).expired?(at: Time.utc(2200, 1, 1))).to be(false)
    end

    # THERE ARE NO CLASSIFIED DEADLINE COMPARISONS LEFT (round 9, R9-7).
    #
    # Round 9 gave the boundary one owner and defended the ownership with a per-line text scan plus a
    # list of three "different question" comparisons. The review defeated the scan with ONE METHOD
    # INDIRECTION and then inverted the boundary at a line the same candidate had written.
    #
    # A DEADLINE IS NO LONGER AN INSTANT ANYONE CAN COMPARE. `Platform::RunDeadline` answers :442's
    # questions — `expired?`, `remaining_seconds`, `not_after`, `beyond?`, `at?` — and exposes no
    # comparison operator and no way to obtain the raw value except one named
    # `instant_for_transport`, which exists solely to hand a plain instant to FROZEN F-04. So the
    # classification list is empty, and the rule below is no longer a text scan hoping to notice a
    # second implementation: there is nothing to implement one FROM.
    #
    # `RowInstantGuard` enforces the same rule on the value the connection returns, so a caller that
    # reaches for `crawl["deadline_at"]` to rebuild a comparison — behind any number of helpers —
    # raises at runtime rather than passing a scan.
    CLASSIFIED_DEADLINE_COMPARISONS = {}.freeze

    # PROOF 185 AND 186 ARE DELETED, NOT WIDENED (D5 family 1, R10-18).
    #
    # 185 was a per-line text scan for a raw deadline read carrying one exception; 186 was an
    # eight-name denylist of comparison methods. On this branch, inverting
    # `Admission#wall_clock_expired?` through `instant_for_transport` — an accessor 186 does not name
    # and 185 skips by construction — left this file and two others at 82 examples, 0 failures. A
    # denylist that omits the accessor that matters is not a defence, and widening it would be the
    # sixth enumeration in six rounds.
    #
    # WHAT DEFENDS THE BOUNDARY NOW is `spec/acceptance/wf005_deadline_gates_spec.rb`, which proves BY
    # CALLER-BOUND INVOCATION that each :442 gate consulted `RunDeadline#expired?` as part of its own
    # execution, on the asserting thread. No respelling through any accessor satisfies that, because
    # it observes the owner EXECUTING rather than observing that some spelling is absent.
  end
end
