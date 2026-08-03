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
end
