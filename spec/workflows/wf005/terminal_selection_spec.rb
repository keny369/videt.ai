# frozen_string_literal: true

require "rails_helper"

# :458's TERMINAL SELECTION, exercised as the pure function it is (S-07-009).
#
# The acceptance spec drives this through the real checkpoint over the real chain, which is what proves
# the COUNTS are the run's. This proves the DERIVATION, and it can do so exhaustively because the
# function has no database, no clock and no identity: every combination of the four precedence limbs is
# reachable in one line, where reaching some of them through a real run would need a Crawl that hit a
# hard limit AND lost a Source root AND left a candidate unevaluated.
RSpec.describe Workflows::Wf005::TerminalSelection do
  # A run that did everything right: one Source, one root, one Document, nothing left over.
  def clean(**overrides)
    described_class::Facts.new(
      documents: 1, roots_total: 1, roots_succeeded: 1, fetch_failures: 0,
      unresolved_discovery: 0, hard_limits: 0, uncovered: 0, unevaluated: 0
    ).with(**overrides)
  end

  def derive(**overrides) = described_class.derive(clean(**overrides))

  describe ":453's failure test, which is not the coverage test" do
    it "PROOF 71 — zero valid Documents is failed, however covered the run looks" do
      # :453 — "A run is failed when it yields ZERO VALID DOCUMENTS or every active Source root fails."
      # A run of terminal 404s is :452-COVERED throughout (`content_absent`) and still produced nothing;
      # reading coverage as the answer to both questions is how such a run reports itself complete.
      selection = derive(documents: 0, roots_succeeded: 0)
      expect(selection.state).to eq("failed")
      expect(selection.completion_reason).to eq("failed")
      # `crawls_terminal_shape` (ADR-097) requires a reason of every terminal state and coverage only of
      # `completed`; a failed run has no coverage to report.
      expect(selection.coverage_status).to be_nil
    end

    it "PROOF 72 — every active Source root failing is failed EVEN WITH Documents" do
      # The second limb is not implied by the first. :452 — "a Source root succeeds only when its
      # DEPTH-ZERO URL ultimately creates a valid Document ... every other root outcome is a Source-root
      # failure EVEN IF another URL for that Source succeeds." A run whose roots all failed but whose
      # sitemap-found URLs produced Documents is exactly that shape.
      selection = derive(documents: 3, roots_total: 2, roots_succeeded: 0)
      expect(selection.state).to eq("failed")
      expect(selection.completion_reason).to eq("failed")
    end

    it "PROOF 73 — a run with no active Source root at all is failed, not vacuously complete" do
      expect(derive(roots_total: 0, roots_succeeded: 0).state).to eq("failed")
    end
  end

  describe ":458's completion-reason precedence" do
    it "PROOF 74 — `limit_reached` outranks `partial_source_failure`, which outranks `completed`" do
      # :458 — "the single completion reason follows precedence `canceled`, `failed`, `limit_reached`,
      # `partial_source_failure`, then `completed`"; :452 says the same from the other end — "a limit hit
      # takes the HIGHER `limit_reached` precedence already defined". Asserted as an ORDER rather than
      # three independent cases: the run below satisfies all three conditions at once.
      both = derive(hard_limits: 1, roots_total: 2, roots_succeeded: 1, fetch_failures: 1,
                    unresolved_discovery: 1)
      expect(both.completion_reason).to eq("limit_reached")
      expect(derive(hard_limits: 0, roots_total: 2, roots_succeeded: 1).completion_reason)
        .to eq("partial_source_failure")
      expect(derive.completion_reason).to eq("completed")
    end

    it "PROOF 75 — all three of :452's `partial_source_failure` causes reach it independently" do
      # ":452 — For a completed run with no limit hit, ANY Source-root failure, `content_fetch_failed`,
      # OR `sitemap_unavailable` yields `completion_reason=partial_source_failure`." Three causes, one
      # reason, and each must reach it on its own or the sentence is only two-thirds implemented.
      expect(derive(roots_total: 2, roots_succeeded: 1).completion_reason).to eq("partial_source_failure")
      expect(derive(fetch_failures: 1, uncovered: 1).completion_reason).to eq("partial_source_failure")
      expect(derive(unresolved_discovery: 1).completion_reason).to eq("partial_source_failure")
    end
  end

  describe ":458's `full` rule, which is a different question from the completion reason" do
    it "PROOF 76 — `full` requires ALL FOUR absences, and each one alone makes it partial" do
      # :458 — "a completed Crawl is `full` ONLY WHEN every in-scope candidate admitted by the frozen
      # discovery rules reached a terminal covered outcome AND no Source or discovery path has an
      # unresolved failure", plus the preceding sentence's "any in-scope candidate NOT EVALUATED because
      # of depth, sitemap, queue, page, byte, response, request, or wall-clock bound makes coverage
      # partial".
      expect(derive.coverage_status).to eq("full")
      expect(derive(uncovered: 1, fetch_failures: 1).coverage_status).to eq("partial")
      expect(derive(unevaluated: 1).coverage_status).to eq("partial")
      expect(derive(hard_limits: 1).coverage_status).to eq("partial")
      expect(derive(unresolved_discovery: 1).coverage_status).to eq("partial")
      expect(derive(roots_total: 2, roots_succeeded: 1).coverage_status).to eq("partial")
    end

    it "PROOF 77 — a clean completion can still be PARTIAL, which is the pair most easily collapsed" do
      # An in-scope candidate discarded by the discovered-queue bound is not a Source failure and there
      # is no `content_fetch_failed` to point at, so :452's reason stays `completed` while :458's
      # coverage is `partial`. Deriving one from the other — in either direction — is the mistake, and
      # the direction that matters is the one that makes coverage read better than the run was.
      selection = derive(unevaluated: 1)
      expect(selection.state).to eq("completed")
      expect(selection.completion_reason).to eq("completed")
      expect(selection.coverage_status).to eq("partial")
    end

    it "PROOF 78 — this function cannot see an exclusion at all, which is why :452's rule is proved elsewhere" do
      # :452 — "robots-disallowed URLs, duplicate occurrences, unsupported media types, and redirect
      # targets rejected by current scope are recorded as `policy_excluded` and are OUTSIDE the
      # denominator."
      #
      # THIS EXAMPLE USED TO ASSERT `derive(uncovered: 0).coverage_status == "full"` AND COULD NOT FAIL
      # (round 4, R4-3). `clean` already sets `uncovered: 0`, so it was byte-identical to `derive`, and
      # PROOF 76 asserts that same expression verbatim. It carried a title about a rule it did not
      # touch — the R3-8 defect class, in the tranche that repaired R3-8.
      #
      # THE RULE IS NOT EXPRESSIBLE HERE, and that is the honest thing to record. `Facts` has no input
      # for excluded candidates: the exclusion lives entirely in `CrawlStartStore#terminal_facts`, whose
      # `uncovered` subquery counts `coverage_effect = 'not_covered'` and therefore never sees an
      # `excluded` row. A pure function given no excluded input cannot demonstrate that exclusions are
      # ignored. So this asserts the STRUCTURAL fact that makes that true — and it fails the moment
      # someone adds an excluded input here without wiring it into the derivation.
      expect(described_class::Facts.members).not_to include(:excluded)
      expect(described_class::Facts.members)
        .to contain_exactly(:documents, :roots_total, :roots_succeeded, :fetch_failures,
                            :unresolved_discovery, :hard_limits, :uncovered, :unevaluated)

      # The behavioural half — a real run whose only non-document candidate is `policy_excluded` still
      # reads `full` — is PROOF 127 in `spec/acceptance/wf005_terminal_checkpoint_spec.rb`, which runs
      # the store and dies under the `<> 'covered'` mutation this one could not see.
    end
  end

  describe "the canceled limb, which is deliberately absent" do
    it "PROOF 79 — the function has no `canceled` outcome, because commit order settles it" do
      # :458 puts `canceled` FIRST in the precedence and settles it by ORDER OF COMMIT: "a cancellation
      # committed strictly before that checkpoint yields `Crawl.Canceled`; a cancellation at or after the
      # checkpoint is rejected as `crawl_already_terminal`." `CancelCrawl` writes that state itself and
      # the guard refuses every edge out of it, so a checkpoint arriving afterwards derives nothing at
      # all. A `canceled` limb here would be a second implementation of a rule the state machine already
      # enforces — and two implementations of one rule is how they come to disagree.
      states = [derive, derive(documents: 0), derive(hard_limits: 1), derive(unevaluated: 1)]
      expect(states.map(&:state).uniq).to match_array(%w[completed failed])
      expect(states.map(&:completion_reason)).not_to include("canceled")
    end
  end
end
