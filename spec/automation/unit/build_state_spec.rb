# frozen_string_literal: true

require_relative "../automation_helper"
require "tmpdir"

# BUILD_STATE: validated, atomic, append-only-in-intent (mandate §4.3, §12; AUTONOMY_POLICY).
RSpec.describe AutonomousBuild::BuildState do
  around do |example|
    Dir.mktmpdir do |dir|
      @path = File.join(dir, "BUILD_STATE.json")
      File.write(@path, JSON.pretty_generate(valid_state))
      example.run
    end
  end

  def valid_state(**overrides)
    {
      "schema_version" => 1, "controller_version" => "0.1.0", "current_block" => "CTRL-01",
      "current_tranche" => "t1", "status" => "in_progress", "attempt_number" => 1,
      "base_commit" => "abc", "worktree_path" => "", "branch_name" => "b",
      "implementation_commit" => nil, "review_commit" => nil, "last_verified_commit" => "abc",
      "verification_run_id" => "", "open_decisions" => [], "completed_blocks" => %w[F-01 F-02 F-03 F-04],
      "failed_attempts" => [], "updated_at" => "2026-07-25T00:00:00Z"
    }.merge(overrides.transform_keys(&:to_s))
  end

  it "loads and validates a well-formed state" do
    state = described_class.load(@path)
    expect(state.status).to eq("in_progress")
    expect(state.completed_blocks).to eq(%w[F-01 F-02 F-03 F-04])
  end

  it "rejects a missing required key" do
    File.write(@path, JSON.pretty_generate(valid_state.tap { |s| s.delete("base_commit") }))
    expect { described_class.load(@path) }.to raise_error(AutonomousBuild::SchemaError, /missing keys/)
  end

  it "rejects an unknown status" do
    File.write(@path, JSON.pretty_generate(valid_state(status: "still_working_probably")))
    expect { described_class.load(@path) }.to raise_error(AutonomousBuild::SchemaError, /not a valid state/)
  end

  it "rejects a wrong schema_version" do
    File.write(@path, JSON.pretty_generate(valid_state(schema_version: 2)))
    expect { described_class.load(@path) }.to raise_error(AutonomousBuild::SchemaError, /schema_version/)
  end

  it "writes atomically and re-reads a validated update, stamping updated_at" do
    state = described_class.load(@path)
    state.update({ status: "ready_for_review" }, now: Time.utc(2026, 7, 25, 12))
    reloaded = described_class.load(@path)
    expect(reloaded.status).to eq("ready_for_review")
    expect(reloaded["updated_at"]).to eq("2026-07-25T12:00:00Z")
    # No stray temp files left behind.
    expect(Dir.children(File.dirname(@path)).grep(/\.tmp\z/)).to be_empty
  end

  it "refuses to write an invalid update (fail closed before touching disk)" do
    state = described_class.load(@path)
    before = File.read(@path)
    expect { state.update({ status: "definitely_not_a_state" }) }.to raise_error(AutonomousBuild::SchemaError)
    expect(File.read(@path)).to eq(before) # unchanged
  end

  it "appends completed blocks and failed attempts without rewriting history" do
    state = described_class.load(@path)
    state.complete_block("S-05")
    state.append_failed_attempt({ "attempt" => 1, "reason" => "verification_failed" })
    reloaded = described_class.load(@path)
    expect(reloaded.completed_blocks).to eq(%w[F-01 F-02 F-03 F-04 S-05])
    expect(reloaded["failed_attempts"].size).to eq(1)
    expect(reloaded["failed_attempts"].first["reason"]).to eq("verification_failed")
  end
end
