# frozen_string_literal: true

require "rails_helper"

# THE QUESTIONS `:442` ASKS, EACH DEFENDED DIRECTLY (blocker ledger D1, D2).
#
# WHY THESE EXIST. Round 10 shipped `beyond?` and `not_after` with NO proof of any kind, and the
# round-11 review established that each body could be replaced by a constant and survive the entire
# suite. `NONE` shipped without two methods its own declared callers invoke, so both no-deadline
# branches raised. And `iso8601` was asked by nothing at all. None of that is exotic: it is what
# happens when a value object's surface grows faster than the proofs that pin it.
RSpec.describe Platform::RunDeadline, type: :platform do
  let(:at) { Time.utc(2026, 8, 4, 12, 0, 0) }
  let(:deadline) { described_class.of("deadline_at" => at) }
  def usec(n) = Rational(n, 1_000_000)

  describe "the scheduling questions, which :442 answers differently from expiry" do
    it "PROOF 210 — `beyond?` is strictly after, which is what lets a link land ON the deadline" do
      # ":442 — an action due exactly at the deadline is the last honest opportunity, and the pass it
      # runs will find the wall clock expired and halt" (`crawl_fetch_due_schedule.rb`). So `beyond?`
      # and `expired?` DELIBERATELY disagree at equality, and both directions need pinning.
      expect(deadline.beyond?(at - usec(1))).to be(false)
      expect(deadline.beyond?(at)).to be(false), "equality is the last honest opportunity, not beyond"
      expect(deadline.beyond?(at + usec(1))).to be(true)
      # AND IT DISAGREES WITH EXPIRY EXACTLY AT THE BOUNDARY, which is the whole reason both exist.
      expect(deadline.expired?(at: at)).to be(true)
    end

    it "PROOF 211 — `not_after` clamps to the deadline and never past it" do
      expect(deadline.not_after(at - 60)).to eq(at - 60)
      expect(deadline.not_after(at)).to eq(at)
      expect(deadline.not_after(at + 60)).to eq(at), "a scheduled instant may never fall past the run"
      expect(deadline.not_after(Time.utc(2999, 1, 1))).to eq(at)
    end

    it "PROOF 212 — `at?` is exact equality, which is :458's third sentence" do
      expect(deadline.at?(at)).to be(true)
      expect(deadline.at?(at - usec(1))).to be(false)
      expect(deadline.at?(at + usec(1))).to be(false)
    end
  end

  describe "NONE" do
    it "PROOF 213 — answers every question its declared callers ask" do
      # R10-4. `CrawlFetchDueSchedule.link` constructs NONE for `crawl_id: nil` and `run_deadline`
      # returns it for an unreadable crawl, then calls `beyond?`; `CancelCrawl` calls `at?`. Neither
      # existed, so both declared no-deadline branches raised `NoMethodError`.
      none = described_class::NONE
      %i[expired? remaining_seconds not_after beyond? at? present?].each do |question|
        expect(none).to respond_to(question), "RunDeadline::NONE cannot answer ##{question}"
      end

      far = Time.utc(2999, 1, 1)
      expect(none.beyond?(far)).to be(false), "a run with no deadline is past nothing"
      expect(none.at?(far)).to be(false), "a run with no deadline is at nothing"
      expect(none.expired?(at: far)).to be(false)
      expect(none.not_after(far)).to eq(far)
      expect(none.present?).to be(false)
    end
  end

  describe "the surface itself" do
    it "PROOF 214 — carries no question production never asks" do
      # D1. `iso8601` was on this object and was called by nothing — not by `app/`, not by any spec.
      # A method nothing asks cannot be defended by a behavioural proof, because no behaviour depends
      # on it: its body could be replaced by a constant and the whole suite would still pass. This
      # asserts the surface stays that way. `DeadlineQueryCensus` is the whole-suite half and catches
      # the case where a method IS defined and IS never reached; this is the cheap structural half.
      # `- Object.instance_methods` would be wrong here for the same reason it was wrong in the
      # census: ActiveSupport defines `present?` on Object, so subtracting it hides a real question.
      surface = described_class.instance_methods(false) - DeadlineQueryCensus::RENDERING
      expect(surface).not_to include(:iso8601),
                             "iso8601 was removed as dead production code; re-adding it needs a caller"
      expect(surface.sort).to eq(%i[at? beyond? expired? instant_for_transport not_after present?
                                    remaining_seconds inspect].sort - DeadlineQueryCensus::RENDERING)
    end
  end
end
