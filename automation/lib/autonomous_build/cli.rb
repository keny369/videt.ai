# frozen_string_literal: true

module AutonomousBuild
  # The controller command line (mandate §4.7). Derives work from versioned repository files, prints
  # concise status, runs the synthetic self-test, and refuses to run a human-gated product tranche
  # autonomously. Exit codes are documented and distinct so a caller (or a wrapping process) can tell
  # a decision-required stop from an error. There is NO automatic merge and NO production path.
  class CLI
    EXIT = {
      "ready_for_review" => 0, "completed" => 0,
      "human_decision_required" => 10, "blocked_external_dependency" => 11,
      "verification_failed" => 1, "retry_limit_reached" => 1, "policy_violation" => 1, "controller_error" => 1
    }.freeze
    COMMANDS = %w[status plan preflight run-next selftest verify review resume abort help].freeze

    def initialize(paths: Paths.new, out: $stdout, err: $stderr, worktree_root: nil)
      @paths = paths
      @out = out
      @err = err
      @worktree_root = worktree_root || File.join(@paths.automation_dir, "worktrees")
    end

    def run(argv)
      command = argv.first || "help"
      unless COMMANDS.include?(command)
        @err.puts("unknown command #{command.inspect}; try `bin/autonomous-build help`")
        return 64
      end

      send("cmd_#{command.tr('-', '_')}", argv[1..])
    rescue LockError => e
      @err.puts("[locked] #{e.message}")
      2
    rescue Error => e
      @err.puts("[error] #{e.message}")
      1
    end

    private

    def cmd_help(_args)
      @out.puts(<<~USAGE)
        bin/autonomous-build <command>
          status      Show the current build state and the next authorised block.
          plan        Show the next authorised block from BUILD_PLAN (and any human gate).
          preflight   Check the repository is clean, committed and consistent before a tranche.
          run-next    Run the next authorised tranche (preflight-gated; refuses a human-gated block).
          selftest    Run the synthetic end-to-end proof tranche (deterministic; no product change).
          verify      Run the always-required verification checks against the current repository.
          review      Note the reviewer configuration and availability.
          resume      Resume after a validated owner decision (--decision HD-xxx --option A).
          abort       Release a stale controller lock.
          help        This message.
      USAGE
      0
    end

    def cmd_status(_args)
      state = build_state
      @out.puts("controller_version: #{state['controller_version']}")
      @out.puts("status:             #{state.status}")
      @out.puts("current_block:      #{state.current_block}")
      @out.puts("completed_blocks:   #{state.completed_blocks.join(', ')}")
      nb = plan.next_block(completed_blocks: state.completed_blocks)
      @out.puts("next_block:         #{nb ? "#{nb['id']} (#{nb['name']})#{' [HUMAN GATE]' if plan.human_gated_before?(nb)}" : 'none'}")
      0
    end

    def cmd_plan(_args)
      nb = plan.next_block(completed_blocks: build_state.completed_blocks)
      return (@out.puts("No runnable block: dependencies unsatisfied or all blocks complete.") || 0) unless nb

      @out.puts("Next authorised block: #{nb['id']} — #{nb['name']}")
      @out.puts("  depends_on: #{Array(nb['depends_on']).join(', ')}")
      @out.puts("  risk_level: #{nb['risk_level']}")
      @out.puts("  human_gate_before: #{plan.human_gated_before?(nb)}")
      @out.puts("  authoritative_sources: #{Array(nb['authoritative_sources']).join(', ')}") if nb['authoritative_sources']
      0
    end

    def cmd_preflight(_args)
      result = Preflight.check(git: Git.new(repo_root: @paths.repo_root), build_state:, plan:)
      @out.puts(result.ok? ? "preflight OK" : "preflight FAILED:")
      result.failures.each { |f| @out.puts("  - #{f}") }
      result.ok? ? 0 : 1
    end

    def cmd_run_next(_args)
      pf = Preflight.check(git: Git.new(repo_root: @paths.repo_root), build_state:, plan:)
      unless pf.ok?
        @out.puts("[preflight blocked] #{pf.summary}")
        return 1
      end

      nb = plan.next_block(completed_blocks: build_state.completed_blocks)
      return (@out.puts("Nothing to run.") || 0) unless nb

      if plan.human_gated_before?(nb)
        @out.puts("[human gate] #{nb['id']} (#{nb['name']}) requires owner approval before an autonomous run.")
        @out.puts("This controller version does not run a human-gated product tranche autonomously.")
        return EXIT["human_decision_required"]
      end

      @out.puts("[not-implemented-in-v1] Autonomous product tranches are enabled after the first owner-approved pilot.")
      @out.puts("Run `selftest` to prove the controller, or `plan` to inspect #{nb['id']}.")
      EXIT["blocked_external_dependency"]
    end

    def cmd_selftest(_args)
      outcome = SelfTest.new(worktree_root: @worktree_root).run
      @out.puts("selftest terminal status: #{outcome.status}")
      @out.puts("worktree: #{outcome.worktree}")
      @out.puts(outcome.status == "ready_for_review" ? "SELFTEST PASS" : "SELFTEST DID NOT REACH ready_for_review")
      EXIT.fetch(outcome.status, 1)
    end

    def cmd_verify(_args)
      manifest = Verifier.load_manifest(@paths.verification_manifest_file)
      result = Verifier.new(manifest:).run(run_id: "VERIFY-#{Time.now.utc.strftime('%Y%m%d%H%M%S')}",
                                          block_id: build_state.current_block, tranche_id: "adhoc",
                                          verified_commit: Git.new.head_commit,
                                          changed_paths: Git.new.working_changes(worktree: @paths.repo_root))
      @out.puts("verification: #{result['status']} — #{result['summary']}")
      result["checks"].each { |c| @out.puts("  #{c['status'].ljust(8)} #{c['id']}") }
      result["status"] == "pass" ? 0 : 1
    end

    def cmd_review(_args)
      reviewer = Adapters::LocalReviewer.new
      @out.puts("reviewer adapter: LocalReviewer (deterministic stub); available: #{reviewer.available?}")
      @out.puts("cross-provider review is a configurable adapter and is NOT active by default.")
      0
    end

    def cmd_resume(args)
      decision = flag(args, "--decision")
      option = flag(args, "--option")
      return (@err.puts("resume requires --decision HD-xxx --option A") || 64) unless decision && option

      @out.puts("[resume] validated decision #{decision} option #{option}; append it to DECISIONS.md and re-run the gated tranche.")
      0
    end

    def cmd_abort(_args)
      lock = @paths.lock_file
      File.delete(lock) if File.exist?(lock)
      @out.puts("[abort] released controller lock (if held). Worktrees are preserved; remove them explicitly.")
      0
    end

    def build_state = BuildState.load(@paths.build_state_file)
    def plan = Plan.load(@paths.build_plan_file)
    def flag(args, name) = (i = args.index(name)) ? args[i + 1] : nil
  end
end
