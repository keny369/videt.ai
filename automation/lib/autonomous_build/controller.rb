# frozen_string_literal: true

module AutonomousBuild
  # The orchestration core (mandate §2, §9). Runs ONE tranche end to end through the explicit state
  # machine: plan -> implement -> verify -> commit -> review -> (repair -> verify -> commit -> review)*
  # -> report -> ready_for_review. Every phase is bounded, every completion claim is independently
  # verified (never model prose), the protected branch is never touched, and the run always exits in
  # exactly one terminal state. Dependencies are injected so the whole flow is deterministically
  # testable without real models (§15).
  class Controller
    # Raised internally to exit early to a terminal state.
    class Stop < StandardError
      attr_reader :status, :details

      def initialize(status, details = {})
        @status = status
        @details = details
        super(status)
      end
    end

    Outcome = Data.define(:status, :run_id, :report, :run_record, :worktree, :details) do
      def terminal? = StateMachine.terminal?(status)
    end

    DEFAULT_LIMITS = {
      "implementation_attempts_per_tranche" => 3, "repair_cycles_per_tranche" => 3,
      "independent_review_cycles" => 2, "repeated_identical_verification_failure" => 2,
      "max_agent_invocations_per_tranche" => 10, "max_changed_files_before_escalation" => 40
    }.freeze

    def initialize(git:, verifier_factory:, planner:, implementer:, reviewer:, repair:, lock:, paths:,
                   worktree_root:, build_state_path:, limits: {}, clock: -> { Time.now.utc }, run_id: nil,
                   extra_secrets: nil, require_independent_review: false)
      @require_independent_review = require_independent_review
      @git = git
      @verifier_factory = verifier_factory
      @planner = planner
      @implementer = implementer
      @reviewer = reviewer
      @repair = repair
      @lock = lock
      @paths = paths
      @worktree_root = worktree_root
      @build_state_path = build_state_path
      @limits = DEFAULT_LIMITS.merge(limits)
      @clock = clock
      @run_id = run_id
      @extra_secrets = extra_secrets
    end

    # Run one tranche. Returns an Outcome in a terminal state. A concurrent run raises LockError
    # (duplicate execution is locked out) — that is intentionally not swallowed.
    def run_tranche(block_id:, tranche_id:, task:)
      @block_id = block_id
      @tranche_id = tranche_id
      @task = task
      @invocations = 0
      @lock.acquire
      begin
        setup
        do_plan
        do_implement
        do_verify_repair_loop
        do_report
      rescue Stop => e
        terminal_outcome(e.status, e.details)
      rescue PolicyViolation => e
        record_event("policy_violation", { "error" => e.message })
        terminal_outcome("policy_violation", { "error" => e.message })
      rescue SchemaError => e
        record_event("controller_error", { "error" => "malformed agent output: #{e.message}" })
        terminal_outcome("controller_error", { "error" => e.message })
      ensure
        @lock.release
      end
    end

    private

    # ---- phases -------------------------------------------------------------

    def setup
      @state = "idle"
      @base = @git.confirm_clean_base!
      @run_id ||= "RUN-#{@clock.call.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(3)}"
      @record = RunRecord.new(File.join(@worktree_root, "runs", @run_id), extra_secrets: @extra_secrets)
      @record.start({ "run_id" => @run_id, "block_id" => @block_id, "tranche_id" => @tranche_id,
                      "task" => @task, "base_commit" => @base, "started_at" => @clock.call.iso8601 })
      @branch = "tranche/#{@block_id}/#{@tranche_id}-#{@run_id.split('-').last}".gsub(/[^A-Za-z0-9_.\/-]/, "-")
      @worktree = @git.create_worktree(branch: @branch, path: File.join(@worktree_root, @run_id), base: @base)
      @verifier = @verifier_factory.call(@worktree)
      record_event("worktree_created", { "branch" => @branch, "worktree" => @worktree, "base" => @base })
      advance("planning")
    end

    def do_plan
      result = invoke(@planner, "planner", brief: "Plan the smallest reviewable tranche for #{@block_id}/#{@tranche_id}: #{@task}")
      record_artifact("planner.json", result)
      stop_for_agent_status(result["status"], planner: true)
      advance("implementing")
    end

    def do_implement
      attempt = 0
      loop do
        budget!
        attempt += 1
        result = invoke(@implementer, "implementer",
                        brief: "Implement only this tranche in the worktree: #{@task}. Do not modify frozen contracts.")
        record_artifact("implementer_attempt_#{attempt}.json", result)

        case result["status"]
        when "completed", "partial" then break
        when "failed"
          raise Stop.new("retry_limit_reached", stage: "implementation") if attempt >= @limits["implementation_attempts_per_tranche"]

          next
        else stop_for_agent_status(result["status"])
        end
      end

      @changed = @git.working_changes(worktree: @worktree)
      guard_frozen_and_size!
      advance("verifying")
    end

    def do_verify_repair_loop
      repairs = 0
      identical = 0
      last_signature = nil

      loop do
        @verification = @verifier.run(run_id: @run_id, block_id: @block_id, tranche_id: @tranche_id,
                                      verified_commit: @base, changed_paths: @changed)
        record_artifact("verification_repair_#{repairs}.json", @verification)

        if @verification["status"] == "pass"
          do_commit
          return if do_review(repairs)
        else
          signature = @verification["missing_checks"] + failed_ids(@verification)
          identical += 1 if signature == last_signature
          last_signature = signature
          raise Stop.new("verification_failed", stage: "verification") if identical >= @limits["repeated_identical_verification_failure"]
        end

        repairs += 1
        raise Stop.new("retry_limit_reached", stage: "repair") if repairs > @limits["repair_cycles_per_tranche"]

        advance("repairing")
        do_repair(repairs)
        @changed = @git.working_changes(worktree: @worktree)
        guard_frozen_and_size!
      end
    end

    def do_commit
      advance("committing")
      @implementation_commit = @git.commit_all(worktree: @worktree, message: "#{@block_id}/#{@tranche_id}: #{@task}",
                                              block_id: @block_id, tranche_id: @tranche_id)
      record_event("committed", { "commit" => @implementation_commit })
      advance("reviewing")
    end

    # Returns true when the review is accepted (proceed to report); false to loop back into repair.
    def do_review(_repairs)
      # The owner's operational rule (ADR-026): an autonomous PRODUCT tranche requires a real
      # independent reviewer; the same-process stub proves orchestration but must never gate real work.
      if @require_independent_review && !@reviewer.independent?
        raise Stop.new("blocked_external_dependency", stage: "review",
                       reason: "autonomous product tranche requires a real independent reviewer, not the stub (ADR-026)")
      end
      unless @reviewer.available?
        raise Stop.new("blocked_external_dependency", stage: "review", reason: "reviewer adapter unavailable")
      end

      review = invoke(@reviewer, "reviewer", brief: "Independently review the committed tranche.",
                      context: { reviewed_commit: @implementation_commit })
      record_artifact("review.json", review)

      unless review["reviewed_commit"] == @implementation_commit
        raise Stop.new("controller_error", reason: "reviewed_commit does not match implementation commit")
      end

      @review = review
      case review["status"]
      when "pass", "pass_with_observations" then true
      when "changes_required" then false # loop back: repair the blocking findings
      else stop_for_agent_status(review["status"])
      end
    end

    def do_repair(cycle)
      findings = (@review && @review["blocking_findings"]) || []
      result = invoke(@repair, "repair",
                      brief: "Repair only these verified blocking findings: #{JSON.generate(findings)}. Failed verification: #{@verification && @verification['summary']}.",
                      context: { findings: })
      record_artifact("repair_#{cycle}.json", result)
      stop_for_agent_status(result["status"]) unless %w[completed partial].include?(result["status"])
      advance("verifying")
    end

    def do_report
      report = Schema.validate("completion", {
        "schema_version" => 1, "role" => "controller", "run_id" => @run_id, "block_id" => @block_id,
        "tranche_id" => @tranche_id, "status" => "ready_for_review", "generated_at" => @clock.call.iso8601,
        "base_commit" => @base, "implementation_commit" => @implementation_commit.to_s,
        "reviewed_commit" => @implementation_commit.to_s, "branch_name" => @branch, "worktree_path" => @worktree,
        "summary" => "Tranche implemented, verified and independently reviewed; awaiting human review before merge.",
        "guarantees_established" => [], "verification_run_id" => @run_id,
        "verification_status" => @verification["status"], "review_status" => @review["status"],
        "decisions_recorded" => [], "remaining_risks" => remaining_risks, "known_limitations" => [],
        "merge_authorised" => false
      })
      advance("reporting")
      record_artifact("completion.json", report)
      persist_build_state("ready_for_review")
      advance("ready_for_review")
      Outcome.new(status: "ready_for_review", run_id: @run_id, report:, run_record: @record, worktree: @worktree, details: {})
    end

    # ---- helpers ------------------------------------------------------------

    def advance(to)
      @state = StateMachine.transition!(@state, to)
      record_event("state", { "state" => to })
    end

    def invoke(adapter, schema_name, brief:, context: {})
      budget!
      @invocations += 1
      invocation = Adapters::Invocation.new(role: schema_name, run_id: @run_id, block_id: @block_id,
                                            tranche_id: @tranche_id, brief:, worktree: @worktree, context:)
      adapter.invoke(invocation)
    end

    def budget!
      return if @invocations < @limits["max_agent_invocations_per_tranche"]

      raise Stop.new("retry_limit_reached", stage: "invocation_budget")
    end

    def guard_frozen_and_size!
      frozen = FrozenContracts.frozen_changes(@changed)
      if frozen.any?
        raise Stop.new("human_decision_required",
                       escalation: escalation("A change touches frozen foundation contract(s): #{frozen.join(', ')}. Modify a frozen foundation?",
                                               affected: frozen))
      end
      return unless @changed.size > @limits["max_changed_files_before_escalation"]

      raise Stop.new("human_decision_required",
                     escalation: escalation("Tranche changes #{@changed.size} files (> limit #{@limits['max_changed_files_before_escalation']}). Split or proceed?",
                                             affected: []))
    end

    def stop_for_agent_status(status, planner: false)
      case status
      when "planned", "completed", "partial", "pass", "pass_with_observations" then return
      when "human_decision_required" then raise Stop.new("human_decision_required", escalation: escalation("An agent requested a human decision."))
      when "blocked_external_dependency" then raise Stop.new("blocked_external_dependency")
      when "policy_violation" then raise Stop.new("policy_violation")
      when "invalid_plan" then raise Stop.new("controller_error", reason: "planner returned invalid_plan") if planner
      else raise Stop.new("controller_error", reason: "unexpected agent status #{status.inspect}")
      end
    end

    def escalation(question, affected: [])
      Schema.validate("escalation", {
        "schema_version" => 1, "role" => "controller", "run_id" => @run_id, "block_id" => @block_id,
        "tranche_id" => @tranche_id, "status" => "human_decision_required", "generated_at" => @clock.call.iso8601,
        "decision_id" => "HD-#{@run_id.split('-').last}", "question" => question, "recommended_option" => "A",
        "confidence" => 0.5, "evidence" => affected, "affected_contracts" => affected,
        "options" => [{ "id" => "A", "summary" => "Pause without changing protected state", "benefits" => ["safe"], "risks" => [] }],
        "default_safe_action" => "Pause; preserve the worktree; make no frozen-contract change.",
        "consequence_of_deferral" => "The tranche stays blocked; no state is lost."
      })
    end

    def persist_build_state(status)
      return unless File.exist?(@build_state_path)

      BuildState.load(@build_state_path).update({
        "status" => status, "current_block" => @block_id, "current_tranche" => @tranche_id,
        "base_commit" => @base, "worktree_path" => @worktree, "branch_name" => @branch,
        "implementation_commit" => @implementation_commit, "review_commit" => @implementation_commit,
        "last_verified_commit" => @implementation_commit.to_s, "verification_run_id" => @run_id
      }, now: @clock.call)
    rescue SchemaError
      nil # never let a build-state write failure mask the tranche outcome
    end

    def terminal_outcome(status, details)
      record_event("terminal", { "status" => status }.merge(stringify(details)))
      persist_build_state(status) if StateMachine.state?(status)
      escalation = details[:escalation]
      record_artifact("escalation.json", escalation) if escalation
      Outcome.new(status:, run_id: @run_id, report: nil, run_record: @record, worktree: @worktree, details:)
    end

    def failed_ids(verification) = verification["checks"].select { |c| c["status"] == "fail" }.map { |c| c["id"] }
    def remaining_risks = (@review ? @review["non_blocking_findings"].map { |f| f["finding_id"] } : [])
    def record_event(type, data = {}) = @record&.append_event(type, data, now: @clock.call)
    def record_artifact(name, hash) = @record&.write_artifact(name, hash)
    def stringify(hash) = hash.transform_keys(&:to_s)
  end
end
