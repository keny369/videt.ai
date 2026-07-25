# frozen_string_literal: true

require_relative "../automation_helper"
require "tmpdir"

# Command runner (bounded, redacted), verifier (deterministic, required-check enforcement), and the
# provider adapters (fake, Claude Code construction, local reviewer). controller_integration.
RSpec.describe "Runner, verifier and adapters" do
  describe AutonomousBuild::CommandRunner do
    subject(:runner) { described_class.new }

    it "captures output and exit status for a successful command" do
      result = runner.run("echo hello", timeout: 10)
      expect(result).to be_success
      expect(result.output).to include("hello")
      expect(result.exit_status).to eq(0)
    end

    it "reports a non-zero exit as failure" do
      expect(runner.run("false", timeout: 10)).not_to be_success
    end

    it "redacts secrets from captured output" do
      result = runner.run("echo token=ghp_ABCDEFGHIJKLMNOP012345", timeout: 10)
      expect(result.output).not_to include("ghp_ABCDEFGHIJKLMNOP012345")
      expect(result.output).to include("[REDACTED]")
    end

    it "refuses to run a prohibited command" do
      expect { runner.run("git push --force origin main") }.to raise_error(AutonomousBuild::PolicyViolation)
    end

    it "kills a command that exceeds its timeout and marks it timed_out" do
      result = runner.run("sleep 5", timeout: 1)
      expect(result.timed_out).to be(true)
      expect(result).not_to be_success
      expect(result.duration_seconds).to be < 3
    end
  end

  describe AutonomousBuild::Verifier do
    around { |ex| Dir.mktmpdir { |d| @dir = d; ex.run } }

    def manifest(command)
      {
        "check_sets" => {
          "always_required" => [
            { "id" => "cleanliness", "type" => "deterministic", "command" => command, "mandatory" => true, "timeout_seconds" => 10 }
          ],
          "controller_code" => {
            "match_paths" => ["automation/**"],
            "checks" => [
              { "id" => "controller_unit", "type" => "deterministic", "command" => "true", "mandatory" => true, "timeout_seconds" => 10 },
              { "id" => "covered", "type" => "covered_by", "command" => nil, "covered_by" => "controller_unit", "mandatory" => false }
            ]
          }
        }
      }
    end

    it "passes when every mandatory check passes" do
      result = described_class.new(manifest: manifest("true")).run(
        run_id: "RUN-1", block_id: "CTRL-01", tranche_id: "t", verified_commit: "abc", changed_paths: []
      )
      expect(result["status"]).to eq("pass")
      expect(result["required_checks"]).to include("cleanliness")
    end

    it "selects path-matched check sets and records covered_by checks without running them" do
      result = described_class.new(manifest: manifest("true")).run(
        run_id: "RUN-1", block_id: "CTRL-01", tranche_id: "t", verified_commit: "abc",
        changed_paths: ["automation/lib/x.rb"]
      )
      ids = result["checks"].map { |c| c["id"] }
      expect(ids).to include("controller_unit", "covered")
      covered = result["checks"].find { |c| c["id"] == "covered" }
      expect(covered["status"]).to eq("covered")
    end

    it "fails when a mandatory check fails (model prose cannot override an objective check)" do
      result = described_class.new(manifest: manifest("false")).run(
        run_id: "RUN-1", block_id: "CTRL-01", tranche_id: "t", verified_commit: "abc", changed_paths: []
      )
      expect(result["status"]).to eq("fail")
    end
  end

  describe AutonomousBuild::Adapters do
    let(:invocation) do
      described_class::Invocation.new(role: "implementer", run_id: "RUN-1", block_id: "CTRL-01",
                                      tranche_id: "t", brief: "do the thing", worktree: "/tmp/wt", context: {})
    end

    it "the fake adapter returns scripted, schema-validated output and runs its effect" do
      touched = []
      fake = described_class::Fake.new(
        schema_name: "implementer",
        responses: [invocation.base_output(status: "completed").merge(
          "summary" => "s", "files_changed" => ["a.rb"], "migrations_added" => [], "tests_added" => [],
          "commands_run" => [], "assumptions" => [], "decisions" => [], "possible_escalations" => [],
          "known_limitations" => [], "recommended_next_action" => "verify"
        )],
        effect: ->(inv, n) { touched << [inv.tranche_id, n] }
      )
      out = fake.invoke(invocation)
      expect(out["status"]).to eq("completed")
      expect(touched).to eq([["t", 1]])
      expect { fake.invoke(invocation) }.to raise_error(AutonomousBuild::Error, /no scripted response/)
    end

    it "the Claude Code adapter constructs a headless JSON command with no permission bypass" do
      cmd = described_class::ClaudeCodeImplementer.new.build_command(invocation)
      expect(cmd).to include("claude", "-p", "--output-format", "json")
      expect(cmd).not_to include("--dangerously-skip-permissions")
      expect { AutonomousBuild::CommandPolicy.assert_allowed!(cmd) }.not_to raise_error
    end

    it "the local reviewer stub returns a schema-valid review flagging that it is not cross-provider" do
      review = described_class::LocalReviewer.new.invoke(
        described_class::Invocation.new(role: "reviewer", run_id: "RUN-1", block_id: "CTRL-01", tranche_id: "t",
                                        brief: "", worktree: "/tmp/wt", context: { reviewed_commit: "abc123" })
      )
      expect(review["status"]).to eq("pass_with_observations")
      expect(review["blocking_findings"]).to be_empty
      expect(review["non_blocking_findings"].first["finding_id"]).to eq("OBS-CROSS-PROVIDER")
    end
  end
end
