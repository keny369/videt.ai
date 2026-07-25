# frozen_string_literal: true

require_relative "../automation_helper"
require "tmpdir"
require "stringio"

# The controller CLI (§4.7): derives status/plan from versioned files, refuses a human-gated tranche,
# and runs the synthetic self-proof. controller_integration.
RSpec.describe AutonomousBuild::CLI do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(@root, "specification", "automation"))
      File.write(File.join(@root, "specification/automation/BUILD_STATE.json"), JSON.pretty_generate(build_state))
      File.write(File.join(@root, "specification/automation/BUILD_PLAN.yml"), build_plan)
      example.run
    end
  end

  def build_state
    {
      "schema_version" => 1, "controller_version" => "0.1.0", "current_block" => "CTRL-01", "current_tranche" => "t",
      "status" => "in_progress", "attempt_number" => 1, "base_commit" => "x", "worktree_path" => "", "branch_name" => "b",
      "implementation_commit" => nil, "review_commit" => nil, "last_verified_commit" => "x", "verification_run_id" => "",
      "open_decisions" => [], "completed_blocks" => %w[F-01 F-02 F-03 F-04 CTRL-01], "failed_attempts" => [],
      "updated_at" => "2026-07-25T00:00:00Z"
    }
  end

  def build_plan
    <<~YAML
      schema_version: 1
      protected_foundations:
        - { id: F-04, status: frozen }
      blocks:
        - id: CTRL-01
          name: Autonomous Build Controller
          status: completed
          depends_on: [F-04]
        - id: S-05-PILOT
          name: First S-05 Pilot Tranche
          status: awaiting_architecture_review
          depends_on: [CTRL-01]
          risk_level: medium
          human_gate_before: true
    YAML
  end

  def cli(out:, err: StringIO.new)
    described_class.new(paths: AutonomousBuild::Paths.new(repo_root: @root), out:, err:,
                        worktree_root: File.join(@root, "wt"))
  end

  it "prints status derived from the versioned build state" do
    out = StringIO.new
    expect(cli(out:).run(["status"])).to eq(0)
    expect(out.string).to include("completed_blocks:   F-01, F-02, F-03, F-04, CTRL-01")
    expect(out.string).to include("next_block:         S-05-PILOT")
    expect(out.string).to include("[HUMAN GATE]")
  end

  it "refuses to run the next tranche autonomously when it is human-gated" do
    out = StringIO.new
    code = cli(out:).run(["run-next"])
    expect(out.string).to include("human gate", "requires owner approval")
    expect(code).to eq(described_class::EXIT["human_decision_required"])
  end

  it "runs the synthetic self-proof to ready_for_review without touching the real repo" do
    out = StringIO.new
    code = cli(out:).run(["selftest"])
    expect(out.string).to include("SELFTEST PASS")
    expect(out.string).to include("ready_for_review")
    expect(code).to eq(0)
  end

  it "rejects an unknown command" do
    expect(cli(out: StringIO.new).run(["frobnicate"])).to eq(64)
  end
end
