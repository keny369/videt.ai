# frozen_string_literal: true

require_relative "../automation_helper"

# Controller run state machine: every run ends in exactly one terminal state, and transitions are
# closed (mandate §2). controller_policy / controller_unit check.
RSpec.describe AutonomousBuild::StateMachine do
  it "partitions states into working and terminal with no overlap" do
    expect(described_class::WORKING & described_class::TERMINAL).to be_empty
    expect(described_class::STATES).to match_array(described_class::WORKING + described_class::TERMINAL)
  end

  it "declares the eight ratified terminal exit states" do
    expect(described_class::TERMINAL).to contain_exactly(
      "completed", "ready_for_review", "human_decision_required", "blocked_external_dependency",
      "verification_failed", "retry_limit_reached", "policy_violation", "controller_error"
    )
  end

  it "allows the happy-path flow plan -> implement -> verify -> commit -> review -> report -> ready_for_review" do
    flow = %w[idle planning implementing verifying committing reviewing reporting ready_for_review]
    flow.each_cons(2) { |from, to| expect(described_class.transition!(from, to)).to eq(to) }
  end

  it "commits before review and lets a failed verify enter repair" do
    expect(described_class.allowed?("verifying", "committing")).to be(true)  # commit on pass
    expect(described_class.allowed?("verifying", "repairing")).to be(true)   # repair on fail
    expect(described_class.allowed?("committing", "reviewing")).to be(true)  # review the committed diff
    expect(described_class.allowed?("reviewing", "repairing")).to be(true)   # changes_required loops back
    expect(described_class.allowed?("repairing", "verifying")).to be(true)   # re-verify after repair
  end

  it "refuses an illegal transition" do
    expect { described_class.transition!("planning", "committing") }
      .to raise_error(AutonomousBuild::InvalidTransition)
    expect { described_class.transition!("idle", "reviewing") }
      .to raise_error(AutonomousBuild::InvalidTransition)
  end

  it "never transitions out of a terminal state" do
    described_class::TERMINAL.each do |terminal|
      expect(described_class.terminal?(terminal)).to be(true)
      expect { described_class.transition!(terminal, "planning") }
        .to raise_error(AutonomousBuild::InvalidTransition)
    end
  end

  it "can reach every terminal state from some working state" do
    reachable = described_class::TRANSITIONS.values.flatten.uniq
    (described_class::TERMINAL - %w[completed]).each do |terminal|
      # completed is reached only via reporting; every other terminal has an inbound edge too.
      expect(reachable).to include(terminal)
    end
    expect(reachable).to include("completed")
  end

  it "rejects an unknown state" do
    expect { described_class.allowed?("banana", "planning") }.to raise_error(AutonomousBuild::InvalidState)
  end
end
