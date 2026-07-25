# frozen_string_literal: true

module AutonomousBuild
  # Git worktree lifecycle and safe git operations (mandate §8.1, §9). Product changes happen only in
  # an isolated worktree/branch; the protected branch is never mutated by the controller. Force push,
  # history rewrite and protected-branch reset are impossible here (no such method) and are also
  # rejected by CommandPolicy. There is no automatic merge in version one.
  class Git
    PROTECTED_BRANCHES = %w[main master].freeze

    def initialize(repo_root: AutonomousBuild::ROOT, runner: CommandRunner.new)
      @repo_root = repo_root
      @runner = runner
    end

    def head_commit = capture("git rev-parse HEAD")
    def current_branch = capture("git rev-parse --abbrev-ref HEAD")
    def rev_parse(ref) = capture("git rev-parse #{shellword(ref)}")

    # True when the working tree has no uncommitted changes to TRACKED files. Untracked files are
    # ignored: parallel tracks (branding/, investor/, …) and the new files a tranche is about to
    # create are expected, and must not read as a dirty base.
    def clean?(chdir: @repo_root) = run("git status --porcelain --untracked-files=no", chdir:).output.strip.empty?

    def protected_branch?(branch) = PROTECTED_BRANCHES.include?(branch.to_s)

    # Confirm a clean base on a non-protected branch before starting a tranche (§9.1-9.2, §8.1).
    def confirm_clean_base!
      raise Error, "working tree is not clean; refusing to start a tranche" unless clean?
      raise Error, "refusing to build product changes directly on protected branch #{current_branch}" if protected_branch?(current_branch)

      head_commit
    end

    # Create an isolated worktree on a NEW branch at `base` (a commit). The branch must be new and
    # non-protected; the worktree path must be a fresh directory.
    def create_worktree(branch:, path:, base:)
      raise PolicyViolation, "refusing to create a protected branch #{branch}" if protected_branch?(branch)
      raise Error, "worktree path already exists: #{path}" if File.exist?(path)

      result = run("git worktree add -b #{shellword(branch)} #{shellword(path)} #{shellword(base)}")
      raise Error, "git worktree add failed: #{result.output}" unless result.success?

      path
    end

    # Remove a worktree. Never deletes a worktree that still holds uncommitted work unless `force`,
    # and never removes the main working tree.
    def remove_worktree(path, force: false)
      raise PolicyViolation, "refusing to remove the main working tree" if File.expand_path(path) == File.expand_path(@repo_root)

      run("git worktree remove #{'--force ' if force}#{shellword(path)}")
    end

    # Commit everything in the worktree; the message must identify the block and tranche (§8.1).
    def commit_all(worktree:, message:, block_id:, tranche_id:)
      full = "#{message}\n\nBuild-Block: #{block_id}\nTranche: #{tranche_id}"
      run("git add -A", chdir: worktree)
      result = run("git commit -q -m #{shellword(full)}", chdir: worktree)
      raise Error, "git commit failed: #{result.output}" unless result.success?

      run("git rev-parse HEAD", chdir: worktree).output.strip
    end

    # Files changed in the worktree relative to `base` (committed diff), for cross-checking an
    # implementer's claimed files against actual committed Git state (§13).
    def changed_files(worktree:, base:)
      run("git diff --name-only #{shellword(base)} HEAD", chdir: worktree).output.split("\n").map(&:strip).reject(&:empty?)
    end

    # Uncommitted working-tree changes (modified + staged + untracked). The frozen-contract check and
    # verification path selection run BEFORE the tranche is committed, so they must see these.
    def working_changes(worktree:)
      run("git status --porcelain --untracked-files=all", chdir: worktree)
        .output.lines.map { |l| l[3..].to_s.strip.split(" -> ").last.to_s.strip }.reject(&:empty?)
    end

    # The unified diff of one path in the worktree relative to `base` (working-tree changes included),
    # used to classify a frozen-path change as a purely-additive extension vs a privilege change (§7.1).
    def diff_path(base:, worktree:, path:)
      run("git diff #{shellword(base)} -- #{shellword(path)}", chdir: worktree).output
    end

    def worktrees = run("git worktree list --porcelain").output

    private

    def run(command, chdir: @repo_root) = @runner.run(command, chdir:)

    def capture(command)
      result = run(command)
      raise Error, "#{command} failed: #{result.output}" unless result.success?

      result.output.strip
    end

    def shellword(str) = "'#{str.to_s.gsub("'", "'\\\\''")}'"
  end
end
