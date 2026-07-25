# frozen_string_literal: true

require_relative "../automation_helper"
require "tmpdir"

# Filesystem safety: operate only within the repo/worktree, refuse traversal and escapes (§8.2).
RSpec.describe AutonomousBuild::Paths do
  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(@root, "automation", "runs"))
      example.run
    end
  end

  subject(:paths) { described_class.new(repo_root: @root) }

  it "resolves paths inside the repo root" do
    expect(paths.within!("automation/runs/RUN-1")).to eq(File.join(@root, "automation/runs/RUN-1"))
    expect(paths.safe?("db/structure.sql")).to be(true)
  end

  it "refuses traversal outside the root" do
    expect { paths.within!("../../etc/passwd") }.to raise_error(AutonomousBuild::UnsafePath)
    expect { paths.within!("/etc/passwd") }.to raise_error(AutonomousBuild::UnsafePath)
    expect(paths.safe?("automation/../../secret")).to be(false)
  end

  it "does not treat a sibling directory with the same prefix as inside the root" do
    # /root vs /root-evil must not be considered "within".
    expect(paths.safe?("#{@root}-evil/x", root: @root)).to be(false)
  end

  it "rejects an unsafe run-id segment" do
    expect { paths.run_dir("../escape") }.to raise_error(AutonomousBuild::UnsafePath)
    expect { paths.run_dir("a/b") }.to raise_error(AutonomousBuild::UnsafePath)
    expect(paths.run_dir("RUN-2026-07-25-ab12")).to eq(File.join(@root, "automation/runs/RUN-2026-07-25-ab12"))
  end

  it "points at the canonical authoritative files" do
    expect(paths.build_state_file).to eq(File.join(@root, "specification/automation/BUILD_STATE.json"))
    expect(paths.verification_manifest_file).to eq(File.join(@root, "specification/automation/VERIFICATION_MANIFEST.yml"))
    expect(paths.lock_file).to eq(File.join(@root, "automation/runs/.controller.lock"))
  end
end
