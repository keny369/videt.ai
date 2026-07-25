# frozen_string_literal: true

require "tmpdir"

module AutonomousBuild
  # The controller's synthetic self-proof, runnable from the CLI (mandate §16). It builds a throwaway
  # git repository, runs one harmless tranche on deterministic fake adapters through the REAL git and
  # verifier — implement (writes a BAD marker) -> verification fails -> repair (removes it) -> passes
  # -> independent review -> commit -> ready_for_review — and leaves the real F1 repository untouched.
  # This is the same flow proven in spec/automation/end_to_end, exposed as a live command.
  class SelfTest
    def initialize(worktree_root:, clock: -> { Time.now.utc })
      @worktree_root = worktree_root
      @clock = clock
    end

    def run
      Dir.mktmpdir("f1-controller-selftest-") do |repo|
        Dir.mktmpdir("f1-controller-work-") do |work|
          seed_repo(repo)
          controller(repo, work).run_tranche(block_id: "SELFTEST", tranche_id: "synthetic",
                                             task: "write synthetic.txt without the BAD marker")
        end
      end
    end

    private

    def seed_repo(repo)
      runner = CommandRunner.new
      runner.run("git init -q -b work", chdir: repo)
      runner.run("git config user.email selftest@f1 && git config user.name selftest", chdir: repo)
      File.write(File.join(repo, "seed.txt"), "seed\n")
      runner.run("git add -A && git commit -q -m seed", chdir: repo)
    end

    def controller(repo, work)
      Controller.new(
        git: Git.new(repo_root: repo), planner: fake_planner, implementer: fake_implementer("BAD\ncode\n"),
        repair: fake_repair("GOOD\ncode\n"), reviewer: Adapters::LocalReviewer.new, verifier_factory: no_bad_verifier,
        lock: ControllerLock.new(File.join(work, ".lock")), paths: Paths.new(repo_root: repo),
        worktree_root: work, build_state_path: File.join(work, "BUILD_STATE.json"),
        clock: @clock, extra_secrets: []
      )
    end

    def no_bad_verifier
      lambda do |worktree|
        manifest = { "check_sets" => { "always_required" => [
          { "id" => "no_bad_marker", "type" => "deterministic",
            "command" => %q{bash -c '! grep -q BAD synthetic.txt'}, "mandatory" => true, "timeout_seconds" => 30 }
        ] } }
        Verifier.new(manifest:, runner: CommandRunner.new(default_chdir: worktree))
      end
    end

    def common(role, status)
      { "schema_version" => 1, "role" => role, "run_id" => "SELFTEST", "block_id" => "SELFTEST",
        "tranche_id" => "synthetic", "status" => status, "generated_at" => @clock.call.iso8601 }
    end

    def fake_planner
      Adapters::Fake.new(schema_name: "planner", responses: [common("planner", "planned").merge(
        "summary" => "synthetic", "authoritative_sources" => [], "dependencies" => [], "scope" => ["synthetic.txt"],
        "out_of_scope" => [], "acceptance_criteria" => ["no BAD marker"], "required_verification" => ["no_bad_marker"],
        "protected_contracts" => [], "assumptions" => [], "possible_escalations" => [], "recommended_action" => "implement"
      )])
    end

    def fake_implementer(content)
      Adapters::Fake.new(schema_name: "implementer",
                         effect: ->(inv, _n) { File.write(File.join(inv.worktree, "synthetic.txt"), content) },
                         responses: [common("implementer", "completed").merge(
                           "summary" => "wrote synthetic.txt", "files_changed" => ["synthetic.txt"], "migrations_added" => [],
                           "tests_added" => [], "commands_run" => [], "assumptions" => [], "decisions" => [],
                           "possible_escalations" => [], "known_limitations" => [], "recommended_next_action" => "verify"
                         )])
    end

    def fake_repair(content)
      Adapters::Fake.new(schema_name: "repair",
                         effect: ->(inv, _n) { File.write(File.join(inv.worktree, "synthetic.txt"), content) },
                         responses: Array.new(3) do
                           common("repair", "completed").merge(
                             "addressed_findings" => [], "unresolved_findings" => [], "files_changed" => ["synthetic.txt"],
                             "commands_run" => [], "assumptions" => [], "recommended_next_action" => "verify"
                           )
                         end)
    end
  end
end
