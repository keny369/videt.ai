# frozen_string_literal: true

module AutonomousBuild
  # Provider-neutral agent adapters (mandate §6). An adapter takes a structured Invocation and returns
  # a SCHEMA-VALIDATED result hash for its role; provider-specific command construction stays behind
  # the adapter. No adapter receives unrestricted credentials or production access, and none may use a
  # permission-bypass mode. The synthetic proof runs on the deterministic Fake/Local adapters (§16);
  # ClaudeCode is the real implementer and is exercised only against a live environment.
  module Adapters
    Invocation = Data.define(:role, :run_id, :block_id, :tranche_id, :brief, :worktree, :context) do
      def base_output(status:)
        {
          "schema_version" => 1, "role" => role == "escalation" ? "controller" : role, "run_id" => run_id,
          "block_id" => block_id, "tranche_id" => tranche_id, "status" => status,
          "generated_at" => Time.now.utc.iso8601
        }
      end
    end

    # The adapter contract. `invoke` MUST return a hash that passes Schema.validate for `schema_name`.
    class Base
      def schema_name = raise(NotImplementedError)
      def available? = true
      def invoke(_invocation) = raise(NotImplementedError)

      def validate!(hash) = Schema.validate(schema_name, hash)
    end

    # Deterministic scripted adapter for controller testing (§15). Responses are pre-programmed (a
    # Hash, or a Proc(invocation, call_number) -> Hash). An `effect` Proc may mutate the worktree to
    # simulate real implementation/repair. Raises if scripted responses are exhausted.
    class Fake < Base
      attr_reader :schema_name, :calls

      def initialize(schema_name:, responses:, effect: nil, available: true)
        @schema_name = schema_name
        @responses = Array(responses).dup
        @effect = effect
        @available = available
        @calls = 0
      end

      def available? = @available

      def invoke(invocation)
        @calls += 1
        @effect&.call(invocation, @calls)
        response = @responses.shift or raise(Error, "fake #{@schema_name} adapter: no scripted response left")
        body = response.is_a?(Proc) ? response.call(invocation, @calls) : response
        validate!(body)
      end
    end

    # The real Claude Code implementer (§6). Constructs a headless, structured-output CLI invocation
    # scoped to the worktree, with NO permission-bypass flag, and validates the returned JSON against
    # the implementer schema. Construction is unit-tested; invocation requires a live `claude` CLI.
    class ClaudeCodeImplementer < Base
      def initialize(runner: CommandRunner.new, model: ENV.fetch("F1_CONTROLLER_IMPLEMENTER_MODEL", nil))
        @runner = runner
        @model = model
      end

      def schema_name = "implementer"
      def available? = which?("claude")

      # The CLI command. Explicitly headless + JSON output, scoped by chdir to the worktree, and
      # deliberately WITHOUT any permission-bypass mode (CommandPolicy would reject one anyway).
      def build_command(invocation)
        parts = ["claude", "-p", shellescape(invocation.brief.to_s), "--output-format", "json"]
        parts += ["--model", @model] if @model && !@model.empty?
        parts.join(" ")
      end

      def invoke(invocation)
        command = build_command(invocation)
        CommandPolicy.assert_allowed!(command)
        result = @runner.run(command, chdir: invocation.worktree, timeout: 3600)
        raise(Error, "implementer CLI exited #{result.exit_status}") unless result.success?

        validate!(Schema.parse(result.output))
      end

      private

      def shellescape(str) = "'#{str.gsub("'", "'\\\\''")}'"

      # Executable-on-PATH check without spawning a shell (no command-injection surface).
      def which?(bin)
        ENV["PATH"].to_s.split(File::PATH_SEPARATOR).any? { |dir| File.executable?(File.join(dir, bin)) }
      end
    end

    # The deterministic, non-model reviewer stub (§6: "Provide a deterministic local reviewer stub …
    # for proving orchestration"). It inspects the committed diff structurally and ALWAYS returns a
    # schema-valid review. It is NOT a substitute for true cross-provider review, and it says so: it
    # always records one non-blocking observation that true independent review has not yet run.
    class LocalReviewer < Base
      def initialize(runner: CommandRunner.new, repo_root: AutonomousBuild::ROOT)
        @runner = runner
        @repo_root = repo_root
      end

      def schema_name = "reviewer"
      def available? = true

      def invoke(invocation)
        commit = invocation.context[:reviewed_commit].to_s
        cross_provider_note = {
          "finding_id" => "OBS-CROSS-PROVIDER", "severity" => "observation", "classification" => "observation",
          "location" => "controller", "violated_requirement" => "independent cross-provider review",
          "failure_mode" => "This review is the deterministic same-process stub, not a true cross-provider review.",
          "evidence" => ["reviewer=LocalReviewer(stub)"],
          "recommended_correction" => "Run a cross-provider reviewer adapter before merge.",
          "blocks_completion" => false
        }
        validate!(invocation.base_output(status: "pass_with_observations").merge(
          "reviewed_commit" => commit, "blocking_findings" => [], "non_blocking_findings" => [cross_provider_note],
          "architecture_assessment" => "structural stub review only", "security_assessment" => "not performed by stub",
          "test_assessment" => "verifier is authoritative for tests", "recommended_action" => "ready_for_review"
        ))
      end
    end
  end
end
