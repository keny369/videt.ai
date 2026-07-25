# frozen_string_literal: true

require_relative "../automation_helper"
require "tmpdir"

# The synthetic end-to-end proof (mandate §16) plus the eight safety proofs. A harmless synthetic
# tranche runs on deterministic fake adapters through real git and the real verifier: create a
# worktree, implement, INTENTIONALLY fail one verification check, repair, pass, review, commit,
# report, stop at ready_for_review, protected branch untouched. Then: malformed output rejected,
# prohibited command blocked, frozen-contract change escalates, duplicate run locked out, worktree
# preserved for resume, retry exhaustion stops, unavailable reviewer blocks, secrets redacted.
RSpec.describe "Autonomous controller — synthetic end-to-end proof", type: :model do
  include AutonomousBuild

  around do |example|
    # The git repo and the controller's work area (worktree root + run records + build state) are
    # SEPARATE directories, so creating worktrees and run records never dirties the repo working
    # tree — exactly as in production, where the worktree root and automation/runs are outside the
    # tracked tree.
    Dir.mktmpdir do |repo_dir|
      Dir.mktmpdir do |work_dir|
        @repo = File.realpath(repo_dir)
        @wt_root = File.realpath(work_dir)
        @build_state = File.join(@wt_root, "BUILD_STATE.json")
        runner = AutonomousBuild::CommandRunner.new
        runner.run("git init -q -b work", chdir: @repo)
        runner.run("git config user.email a@b.c && git config user.name t", chdir: @repo)
        File.write(File.join(@repo, "seed.txt"), "seed\n")
        runner.run("git add -A && git commit -q -m seed", chdir: @repo)
        File.write(@build_state, JSON.pretty_generate(base_state))
        example.run
      end
    end
  end

  def base_state
    {
      "schema_version" => 1, "controller_version" => "0.1.0", "current_block" => "SYN", "current_tranche" => "t",
      "status" => "in_progress", "attempt_number" => 1, "base_commit" => "x", "worktree_path" => "",
      "branch_name" => "b", "implementation_commit" => nil, "review_commit" => nil, "last_verified_commit" => "x",
      "verification_run_id" => "", "open_decisions" => [], "completed_blocks" => [], "failed_attempts" => [],
      "updated_at" => "2026-07-25T00:00:00Z"
    }
  end

  # ---- fakes ---------------------------------------------------------------

  def planner_ok
    AutonomousBuild::Adapters::Fake.new(schema_name: "planner", responses: [
      common("planner", "planned").merge(
        "summary" => "s", "authoritative_sources" => [], "dependencies" => [], "scope" => ["synthetic.txt"],
        "out_of_scope" => [], "acceptance_criteria" => ["no BAD marker"], "required_verification" => ["no_bad"],
        "protected_contracts" => [], "assumptions" => [], "possible_escalations" => [], "recommended_action" => "implement"
      )
    ])
  end

  def implementer_writing(content, path: "synthetic.txt", status: "completed", files: ["synthetic.txt"])
    AutonomousBuild::Adapters::Fake.new(
      schema_name: "implementer",
      effect: ->(inv, _n) { write_in(inv.worktree, path, content) },
      responses: [common("implementer", status).merge(
        "summary" => "wrote #{path}", "files_changed" => files, "migrations_added" => [], "tests_added" => [],
        "commands_run" => [], "assumptions" => [], "decisions" => [], "possible_escalations" => [],
        "known_limitations" => [], "recommended_next_action" => "verify"
      )]
    )
  end

  def repair_writing(content, path: "synthetic.txt", status: "completed")
    AutonomousBuild::Adapters::Fake.new(
      schema_name: "repair",
      effect: ->(inv, _n) { write_in(inv.worktree, path, content) },
      responses: Array.new(5) do
        common("repair", status).merge(
          "addressed_findings" => [], "unresolved_findings" => [], "files_changed" => [path],
          "commands_run" => [], "assumptions" => [], "recommended_next_action" => "verify"
        )
      end
    )
  end

  def write_in(worktree, path, content)
    full = File.join(worktree, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def common(role, status)
    { "schema_version" => 1, "role" => role, "run_id" => "RUN-SYN", "block_id" => "SYN",
      "tranche_id" => "t", "status" => status, "generated_at" => "2026-07-25T00:00:00Z" }
  end

  # A verifier bound to the worktree with a single controllable check: fail while the file contains
  # the BAD marker, pass once it does not.
  def no_bad_verifier_factory(command: %q{bash -c '! grep -q BAD synthetic.txt'})
    lambda do |worktree|
      manifest = { "check_sets" => { "always_required" => [
        { "id" => "no_bad", "type" => "deterministic", "command" => command, "mandatory" => true, "timeout_seconds" => 30 }
      ] } }
      AutonomousBuild::Verifier.new(manifest:, runner: AutonomousBuild::CommandRunner.new(default_chdir: worktree))
    end
  end

  def controller(planner:, implementer:, reviewer:, repair:, verifier_factory:, lock: nil, run_id: "RUN-SYN")
    AutonomousBuild::Controller.new(
      git: AutonomousBuild::Git.new(repo_root: @repo), verifier_factory:, planner:, implementer:, reviewer:, repair:,
      lock: lock || AutonomousBuild::ControllerLock.new(File.join(@wt_root, ".lock")),
      paths: AutonomousBuild::Paths.new(repo_root: @repo), worktree_root: @wt_root, build_state_path: @build_state,
      run_id:, extra_secrets: [], limits: { "repeated_identical_verification_failure" => 2 }
    )
  end

  def head = AutonomousBuild::CommandRunner.new.run("git rev-parse HEAD", chdir: @repo).output.strip

  # ---- the proof -----------------------------------------------------------

  it "runs the full synthetic tranche: implement, fail one check, repair, pass, review, commit, ready_for_review" do
    base = head
    outcome = controller(
      planner: planner_ok,
      implementer: implementer_writing("BAD\ncode\n"),        # first pass writes the BAD marker
      repair: repair_writing("GOOD\ncode\n"),                 # repair removes it
      reviewer: AutonomousBuild::Adapters::LocalReviewer.new,
      verifier_factory: no_bad_verifier_factory
    ).run_tranche(block_id: "SYN", tranche_id: "t", task: "write synthetic.txt without BAD")

    expect(outcome.status).to eq("ready_for_review")
    expect(outcome.report["merge_authorised"]).to be(false)
    expect(outcome.report["review_status"]).to eq("pass_with_observations")

    # The work is committed inside the isolated worktree; the protected branch never moved.
    expect(head).to eq(base)
    committed = AutonomousBuild::CommandRunner.new.run("git show HEAD:synthetic.txt", chdir: outcome.worktree).output
    expect(committed).to include("GOOD")
    expect(committed).not_to include("BAD")

    # Independent review produced exactly one non-blocking observation; none blocking.
    review = JSON.parse(File.read(File.join(outcome.run_record.dir, "review.json")))
    expect(review["blocking_findings"]).to be_empty
    expect(review["non_blocking_findings"].size).to eq(1)

    # The run record shows the fail-then-pass verification cycle, append-only.
    types = outcome.run_record.events.map { |e| e["type"] }
    expect(types).to include("worktree_created", "committed", "state")
    expect(File).to exist(File.join(outcome.run_record.dir, "verification_repair_0.json")) # the failing verify
    expect(File).to exist(File.join(outcome.run_record.dir, "verification_repair_1.json")) # the passing verify

    # BUILD_STATE was atomically updated to the terminal status.
    expect(AutonomousBuild::BuildState.load(@build_state).status).to eq("ready_for_review")
  end

  it "rejects malformed agent output (fails closed to controller_error)" do
    bad_implementer = AutonomousBuild::Adapters::Fake.new(
      schema_name: "implementer", responses: [common("implementer", "completed")] # missing all required fields
    )
    outcome = controller(planner: planner_ok, implementer: bad_implementer, repair: repair_writing("GOOD"),
                         reviewer: AutonomousBuild::Adapters::LocalReviewer.new, verifier_factory: no_bad_verifier_factory)
                .run_tranche(block_id: "SYN", tranche_id: "t", task: "x")
    expect(outcome.status).to eq("controller_error")
  end

  it "blocks a prohibited verification command (policy_violation)" do
    outcome = controller(planner: planner_ok, implementer: implementer_writing("GOOD"), repair: repair_writing("GOOD"),
                         reviewer: AutonomousBuild::Adapters::LocalReviewer.new,
                         verifier_factory: no_bad_verifier_factory(command: "git push --force origin main"))
                .run_tranche(block_id: "SYN", tranche_id: "t", task: "x")
    expect(outcome.status).to eq("policy_violation")
  end

  it "escalates a change that touches a frozen foundation contract" do
    outcome = controller(
      planner: planner_ok,
      implementer: implementer_writing("hack\n", path: "app/platform/encryption.rb", files: ["app/platform/encryption.rb"]),
      repair: repair_writing("GOOD"), reviewer: AutonomousBuild::Adapters::LocalReviewer.new,
      verifier_factory: no_bad_verifier_factory
    ).run_tranche(block_id: "SYN", tranche_id: "t", task: "x")

    expect(outcome.status).to eq("human_decision_required")
    escalation = JSON.parse(File.read(File.join(outcome.run_record.dir, "escalation.json")))
    expect(escalation["question"]).to match(/frozen foundation/)
    expect(escalation["affected_contracts"]).to include("app/platform/encryption.rb")
  end

  it "locks out a duplicate controller run" do
    lock = AutonomousBuild::ControllerLock.new(File.join(@wt_root, ".lock")).acquire
    begin
      expect do
        controller(planner: planner_ok, implementer: implementer_writing("GOOD"), repair: repair_writing("GOOD"),
                   reviewer: AutonomousBuild::Adapters::LocalReviewer.new, verifier_factory: no_bad_verifier_factory,
                   lock: AutonomousBuild::ControllerLock.new(File.join(@wt_root, ".lock")))
          .run_tranche(block_id: "SYN", tranche_id: "t", task: "x")
      end.to raise_error(AutonomousBuild::LockError)
    ensure
      lock.release
    end
  end

  it "stops on retry exhaustion and preserves the worktree + state for resume" do
    outcome = controller(
      planner: planner_ok, implementer: implementer_writing("BAD\n"),
      repair: repair_writing("BAD\n"),                         # repair never removes the marker
      reviewer: AutonomousBuild::Adapters::LocalReviewer.new, verifier_factory: no_bad_verifier_factory
    ).run_tranche(block_id: "SYN", tranche_id: "t", task: "x")

    expect(%w[verification_failed retry_limit_reached]).to include(outcome.status)
    expect(Dir).to exist(outcome.worktree)                     # worktree preserved (§14: resume-safe)
    expect(AutonomousBuild::BuildState.load(@build_state).status).to eq(outcome.status)
  end

  it "reaches a controlled blocked state when the reviewer is unavailable" do
    unavailable_reviewer = AutonomousBuild::Adapters::Fake.new(schema_name: "reviewer", responses: [], available: false)
    outcome = controller(planner: planner_ok, implementer: implementer_writing("GOOD"), repair: repair_writing("GOOD"),
                         reviewer: unavailable_reviewer, verifier_factory: no_bad_verifier_factory)
                .run_tranche(block_id: "SYN", tranche_id: "t", task: "x")
    expect(outcome.status).to eq("blocked_external_dependency")
  end

  it "redacts secrets from run records end to end" do
    outcome = controller(planner: planner_ok, implementer: implementer_writing("GOOD"), repair: repair_writing("GOOD"),
                         reviewer: AutonomousBuild::Adapters::LocalReviewer.new, verifier_factory: no_bad_verifier_factory)
                .run_tranche(block_id: "SYN", tranche_id: "t", task: "deploy with token ghp_ABCDEFGHIJKLMNOP012345")
    meta = File.read(File.join(outcome.run_record.dir, "meta.json"))
    expect(meta).not_to include("ghp_ABCDEFGHIJKLMNOP012345")
    expect(meta).to include("[REDACTED]")
  end
end
