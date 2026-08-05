# frozen_string_literal: true

require "spec_helper"
require "open3"
require_relative "../../../automation/lib/autonomous_build/mutation_harness"

# THE VERDICT RULE HAS ONE IMPLEMENTATION AND IT HAS A PROOF (round-15 concurrency finding
# R15-CONC-2).
#
# WHAT WAS OPEN. `MutationHarness` classified a replay's outcome in TWO places — once in `replay`
# (82 definitions) and once in `replay_trigger` (10) — and they disagreed. D7 recorded that "both
# paths now carry the same classification"; the correction had reached one of them. The path carrying
# the trigger definitions still returned `broken` for a run whose examples passed and which tripped a
# suite-wide invariant, which is the STRONGEST kill available in this repository.
#
# WHY IT SURVIVED THE REPAIR THAT WAS SUPPOSED TO REMOVE IT. Neither copy had a test. The whole
# mutation ledger rests on this four-way decision and nothing exercised it, so the two copies could
# drift without any gate noticing — and `verify_bindings!` would then report a real kill as a ledger
# error, or, worse, a clean exit with a suite-level error as a survivor.
#
# The copies are gone; this file is the proof of the one that remains.
RSpec.describe AutonomousBuild::MutationHarness, ".classify" do
  Status = Struct.new(:success?)

  def classify(summary:, examples:, failures:, success:, output: "")
    described_class.classify(summary:, examples:, failures:, status: Status.new(success), output:)
  end

  it "calls a run that produced no summary line `broken` — nothing ran, so nothing was proved" do
    expect(classify(summary: nil, examples: nil, failures: nil, success: false)).to eq("broken")
  end

  it "calls a run of zero examples `broken`, however it exited" do
    expect(classify(summary: "0 examples, 0 failures", examples: 0, failures: 0, success: false))
      .to eq("broken")
    expect(classify(summary: "0 examples, 0 failures", examples: 0, failures: 0, success: true))
      .to eq("broken")
  end

  it "calls a run with a failing example `killed`" do
    expect(classify(summary: "13 examples, 7 failures", examples: 13, failures: 7, success: false))
      .to eq("killed")
  end

  it "calls a clean run `survived` — the mutation was not detected" do
    expect(classify(summary: "13 examples, 0 failures", examples: 13, failures: 0, success: true))
      .to eq("survived")
  end

  it "calls a run whose examples PASSED but which tripped a suite-wide invariant `killed`" do
    # THE CASE THE TWO COPIES DISAGREED ON. RSpec exits non-zero and appends its own sentence; the
    # mutation was detected by the suite-level rule rather than by a named example.
    output = "13 examples, 0 failures, 1 error occurred outside of examples"
    expect(classify(summary: "13 examples, 0 failures", examples: 13, failures: 0, success: false,
                    output:)).to eq("killed")
  end

  it "never calls a suite-level error `survived`, even if RSpec somehow exits zero" do
    # A false SURVIVOR is worse than a false BROKEN: it credits the mutation with defeating a proof
    # that in fact caught it, and no gate would look again.
    output = "13 examples, 0 failures, 1 error occurred outside of examples"
    expect(classify(summary: "13 examples, 0 failures", examples: 13, failures: 0, success: true,
                    output:)).to eq("killed")
  end
end
