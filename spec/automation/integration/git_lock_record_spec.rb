# frozen_string_literal: true

require_relative "../automation_helper"
require "tmpdir"

# Git worktree lifecycle, controller lock, and append-only run records. controller_locking +
# controller_integration.
RSpec.describe "Git, lock and run records" do
  describe AutonomousBuild::Git do
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

    subject(:git) { described_class.new(repo_root: @repo) }

    it "confirms a clean, non-protected base and reports HEAD" do
      expect(git.clean?).to be(true)
      expect(git.protected_branch?("work")).to be(false)
      expect(git.confirm_clean_base!).to match(/\A[0-9a-f]{40}\z/)
    end

    it "creates an isolated worktree, commits into it, and lists changed files" do
      base = git.head_commit
      wt = File.join(Dir.tmpdir, "wt-#{SecureRandom.hex(4)}")
      begin
        git.create_worktree(branch: "tranche/t1", path: wt, base:)
        File.write(File.join(wt, "new.rb"), "puts 1\n")
        commit = git.commit_all(worktree: wt, message: "add new", block_id: "CTRL-01", tranche_id: "t1")
        expect(commit).to match(/\A[0-9a-f]{40}\z/)
        expect(git.changed_files(worktree: wt, base:)).to include("new.rb")
        # protected branch untouched: the main repo's branch/commit did not move.
        expect(git.head_commit).to eq(base)
      ensure
        git.remove_worktree(wt, force: true)
      end
    end

    it "refuses to create a protected branch and refuses to remove the main working tree" do
      expect { git.create_worktree(branch: "main", path: "/tmp/x", base: git.head_commit) }
        .to raise_error(AutonomousBuild::PolicyViolation)
      expect { git.remove_worktree(@repo) }.to raise_error(AutonomousBuild::PolicyViolation)
    end
  end

  describe AutonomousBuild::ControllerLock do
    around { |ex| Dir.mktmpdir { |d| @lock = File.join(d, ".controller.lock"); ex.run } }

    it "locks out a duplicate controller run" do
      held = described_class.new(@lock).acquire
      begin
        expect { described_class.new(@lock).acquire }.to raise_error(AutonomousBuild::LockError, /locked out/)
      ensure
        held.release
      end
      # released -> reacquirable
      described_class.new(@lock).with_lock { |l| expect(l.held?).to be(true) }
    end
  end

  describe AutonomousBuild::RunRecord do
    around { |ex| Dir.mktmpdir { |d| @dir = File.join(d, "RUN-1"); ex.run } }

    subject(:record) { described_class.new(@dir, extra_secrets: []) }

    it "appends events and redacts secrets, and refuses to overwrite an artifact" do
      record.start({ "task" => "synthetic", "token" => "ghp_ABCDEFGHIJKLMNOP012345" })
      record.append_event("verification", { "status" => "pass" })
      record.append_event("policy_decision", { "note" => "password=hunter2" })

      meta = JSON.parse(File.read(File.join(@dir, "meta.json")))
      expect(meta["token"]).to eq("[REDACTED]")
      events = record.events
      expect(events.map { |e| e["type"] }).to eq(%w[verification policy_decision])
      expect(events.last["data"]["note"]).to eq("password=[REDACTED]")

      record.write_artifact("brief.md", "the brief")
      expect { record.write_artifact("brief.md", "again") }.to raise_error(AutonomousBuild::Error, /append-only/)
    end
  end
end
