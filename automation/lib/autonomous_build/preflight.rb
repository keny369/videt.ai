# frozen_string_literal: true

module AutonomousBuild
  # Enforced before/after invariants for every tranche (owner request, 2026-07-25). Preflight refuses
  # to START a tranche unless the repository is in a known-good state; Postflight refuses to declare a
  # tranche `ready_for_review` unless it is fully verified, independently reviewed, recorded and
  # committed. This makes "everything is committed and consistent" a controller GUARANTEE, not a
  # prompt reminder — you never have to tell the controller to make sure everything is committed.
  module Preflight
    module_function

    Result = Data.define(:ok, :failures) do
      def ok? = ok
      def summary = ok ? "preflight/postflight ok" : failures.join("; ")
    end

    # Before a tranche: clean tracked tree, not on a protected branch, consistent BUILD_STATE, a
    # runnable next block whose dependencies are satisfied, and the previous tranche not left mid-run.
    def check(git:, build_state:, plan:)
      failures = []
      failures << "working tree has uncommitted tracked changes" unless git.clean?
      failures << "on a protected branch (#{git.current_branch})" if git.protected_branch?(git.current_branch)
      failures.concat(state_failures(build_state))
      failures.concat(plan_failures(plan, build_state))
      failures << "previous tranche left in a working state (#{build_state.status})" if StateMachine.working?(build_state.status)
      Result.new(ok: failures.empty?, failures:)
    end

    # Before declaring ready_for_review: verification passed, an independent review exists, the tranche
    # is committed, and the worktree is clean (nothing implemented-but-uncommitted).
    def postflight(verification:, review:, implementation_commit:, git:, worktree:)
      failures = []
      failures << "verification did not pass" unless verification && verification["status"] == "pass"
      failures << "independent review missing" if review.nil?
      failures << "no implementation commit" if implementation_commit.to_s.empty?
      failures << "worktree has uncommitted changes" unless git.clean?(chdir: worktree)
      Result.new(ok: failures.empty?, failures:)
    end

    def state_failures(build_state)
      build_state.validate!
      []
    rescue SchemaError => e
      ["BUILD_STATE inconsistent: #{e.message}"]
    end

    def plan_failures(plan, build_state)
      return ["no runnable next block (dependencies unsatisfied or all blocks complete)"] unless plan.next_block(completed_blocks: build_state.completed_blocks)

      []
    rescue StandardError => e
      ["BUILD_PLAN inconsistent: #{e.message}"]
    end
  end
end
