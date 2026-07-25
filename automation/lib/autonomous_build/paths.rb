# frozen_string_literal: true

module AutonomousBuild
  # Filesystem safety (mandate §8.2, AUTONOMY_POLICY filesystem policy): the controller operates only
  # within the repository and its designated worktree root, refuses `..` traversal and absolute
  # escapes, and never resolves a path outside an allowed root. All controller file operations route
  # through `within!`.
  class Paths
    attr_reader :repo_root, :worktree_root

    def initialize(repo_root: AutonomousBuild::ROOT, worktree_root: nil)
      @repo_root = File.realpath(repo_root)
      @worktree_root = worktree_root && File.expand_path(worktree_root)
    end

    def automation_dir = File.join(@repo_root, "automation")
    def runs_dir = File.join(automation_dir, "runs")
    def run_dir(run_id) = File.join(runs_dir, within_segment!(run_id))
    def spec_automation_dir = File.join(@repo_root, "spec", "automation")

    def build_state_file = File.join(@repo_root, "specification", "automation", "BUILD_STATE.json")
    def build_plan_file = File.join(@repo_root, "specification", "automation", "BUILD_PLAN.yml")
    def verification_manifest_file = File.join(@repo_root, "specification", "automation", "VERIFICATION_MANIFEST.yml")
    def decision_ledger_file = File.join(@repo_root, "DECISIONS.md")
    def lock_file = File.join(runs_dir, ".controller.lock")

    # Resolve `candidate` and confirm it is inside `root` (default: repo root). Refuses absolute
    # escapes and `..` traversal. Returns the expanded absolute path or raises UnsafePath.
    def within!(candidate, root: @repo_root)
      base = File.expand_path(root)
      resolved = File.expand_path(candidate.to_s, base)
      unless resolved == base || resolved.start_with?(base + File::SEPARATOR)
        raise UnsafePath, "path #{candidate.inspect} escapes #{base}"
      end

      resolved
    end

    def safe?(candidate, root: @repo_root)
      within!(candidate, root:)
      true
    rescue UnsafePath
      false
    end

    private

    # A single path segment (run id, branch suffix): no separators, no traversal, no leading dot.
    def within_segment!(segment)
      s = segment.to_s
      unless s.match?(/\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/) && !s.include?("..")
        raise UnsafePath, "unsafe path segment #{segment.inspect}"
      end

      s
    end
  end
end
