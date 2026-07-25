# frozen_string_literal: true

require_relative "../automation_helper"
require "tmpdir"

# Enforced before/after tranche invariants (owner request). controller_policy.
RSpec.describe AutonomousBuild::Preflight do
  around do |example|
    Dir.mktmpdir do |dir|
      @repo = File.realpath(dir)
      run = AutonomousBuild::CommandRunner.new
      run.run("git init -q -b work", chdir: @repo)
      run.run("git config user.email a@b.c && git config user.name t", chdir: @repo)
      File.write(File.join(@repo, "seed.txt"), "seed\n")
      run.run("git add -A && git commit -q -m seed", chdir: @repo)
      example.run
    end
  end

  def git = AutonomousBuild::Git.new(repo_root: @repo)

  def state(**over)
    AutonomousBuild::BuildState.new("x", {
      "schema_version" => 1, "controller_version" => "1.0.0", "current_block" => "S-05", "current_tranche" => "t",
      "status" => "planned", "attempt_number" => 0, "base_commit" => "x", "worktree_path" => "", "branch_name" => "b",
      "implementation_commit" => nil, "review_commit" => nil, "last_verified_commit" => "x", "verification_run_id" => "",
      "open_decisions" => [], "completed_blocks" => %w[F-01 F-02 F-03 F-04 CTRL-01], "failed_attempts" => [],
      "updated_at" => "2026-07-25T00:00:00Z"
    }.merge(over.transform_keys(&:to_s)))
  end

  def plan(next_ok: true)
    data = {
      "protected_foundations" => [{ "id" => "F-04", "status" => "frozen" }],
      "blocks" => [{ "id" => "CTRL-01", "status" => "completed", "depends_on" => ["F-04"] },
                   { "id" => "S-05", "status" => next_ok ? "planned" : "completed", "depends_on" => ["CTRL-01"] }]
    }
    AutonomousBuild::Plan.new(data)
  end

  it "passes on a clean, committed, consistent repository with a runnable next block" do
    result = described_class.check(git:, build_state: state, plan:)
    expect(result).to be_ok, result.summary
  end

  it "fails when the tracked working tree is dirty (untracked parallel files are ignored)" do
    File.write(File.join(@repo, "seed.txt"), "changed\n")       # a tracked change
    File.write(File.join(@repo, "untracked.txt"), "new\n")      # an untracked file — should be ignored
    expect(described_class.check(git:, build_state: state, plan:).failures)
      .to include(a_string_matching(/uncommitted tracked changes/))
  end

  it "fails when BUILD_STATE is left in a working (mid-run) state" do
    expect(described_class.check(git:, build_state: state(status: "implementing"), plan:).failures)
      .to include(a_string_matching(/working state/))
  end

  it "fails when there is no runnable next block" do
    expect(described_class.check(git:, build_state: state, plan: plan(next_ok: false)).failures)
      .to include(a_string_matching(/no runnable next block/))
  end

  it "postflight requires verification, review, a commit and a clean worktree" do
    ok = described_class.postflight(verification: { "status" => "pass" }, review: { "status" => "pass" },
                                    implementation_commit: "abc", git:, worktree: @repo)
    expect(ok).to be_ok
    bad = described_class.postflight(verification: { "status" => "fail" }, review: nil,
                                     implementation_commit: "", git:, worktree: @repo)
    expect(bad.failures).to include(a_string_matching(/verification did not pass/), a_string_matching(/review missing/),
                                    a_string_matching(/no implementation commit/))
  end
end
