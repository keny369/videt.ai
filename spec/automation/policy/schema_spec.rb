# frozen_string_literal: true

require_relative "../automation_helper"

# Fail-closed structured-output validation (mandate §13; AGENT_OUTPUT_SCHEMAS.md). controller_policy.
RSpec.describe AutonomousBuild::Schema do
  def base(role)
    {
      "schema_version" => 1, "role" => role, "run_id" => "RUN-1", "block_id" => "S-05",
      "tranche_id" => "S-05-001", "generated_at" => "2026-07-25T00:00:00Z"
    }
  end

  def implementer(**over)
    base("implementer").merge(
      "status" => "completed", "summary" => "s", "files_changed" => [], "migrations_added" => [],
      "tests_added" => [], "commands_run" => [], "assumptions" => [], "decisions" => [],
      "possible_escalations" => [], "known_limitations" => [], "recommended_next_action" => "verify"
    ).merge(over.transform_keys(&:to_s))
  end

  it "accepts a well-formed implementer result" do
    expect(described_class.validate("implementer", implementer)).to be_a(Hash)
    expect(described_class.valid?("implementer", implementer.to_json)).to be(true)
  end

  it "rejects malformed JSON (fails closed, never interprets loosely)" do
    expect { described_class.validate("implementer", "{ not json ") }.to raise_error(AutonomousBuild::SchemaError, /malformed JSON/)
  end

  it "rejects an unknown top-level field" do
    expect { described_class.validate("implementer", implementer("surprise" => 1)) }
      .to raise_error(AutonomousBuild::SchemaError, /unexpected field/)
  end

  it "rejects a missing required field" do
    payload = implementer.tap { |h| h.delete("files_changed") }
    expect { described_class.validate("implementer", payload) }.to raise_error(AutonomousBuild::SchemaError, /missing field/)
  end

  it "rejects a disallowed status" do
    expect { described_class.validate("implementer", implementer("status" => "looks_done_to_me")) }
      .to raise_error(AutonomousBuild::SchemaError, /status/)
  end

  it "rejects a wrong field type and a wrong schema_version and a wrong role" do
    expect { described_class.validate("implementer", implementer("files_changed" => "a.rb")) }.to raise_error(AutonomousBuild::SchemaError, /must be array/)
    expect { described_class.validate("implementer", implementer("schema_version" => 2)) }.to raise_error(AutonomousBuild::SchemaError, /schema_version/)
    expect { described_class.validate("implementer", implementer("role" => "reviewer")) }.to raise_error(AutonomousBuild::SchemaError, /role must be/)
  end

  it "validates reviewer findings and their severity/classification vocabulary" do
    finding = {
      "finding_id" => "F1", "severity" => "high", "classification" => "defect", "location" => "x.rb:1",
      "violated_requirement" => "r", "failure_mode" => "m", "evidence" => [], "recommended_correction" => "c",
      "blocks_completion" => true
    }
    reviewer = base("reviewer").merge(
      "status" => "changes_required", "reviewed_commit" => "abc", "blocking_findings" => [finding],
      "non_blocking_findings" => [], "architecture_assessment" => "", "security_assessment" => "",
      "test_assessment" => "", "recommended_action" => "repair"
    )
    expect(described_class.validate("reviewer", reviewer)).to be_a(Hash)
    bad = reviewer.merge("blocking_findings" => [finding.merge("severity" => "catastrophic")])
    expect { described_class.validate("reviewer", bad) }.to raise_error(AutonomousBuild::SchemaError, /severity/)
  end

  it "keys escalation and completion by schema even though both carry role 'controller'" do
    escalation = base("controller").merge(
      "status" => "human_decision_required", "decision_id" => "HD-1", "question" => "q?",
      "recommended_option" => "A", "confidence" => 0.9, "evidence" => [], "affected_contracts" => [],
      "options" => [], "default_safe_action" => "pause", "consequence_of_deferral" => "blocked"
    )
    expect(described_class.validate("escalation", escalation)).to be_a(Hash)
    # completion requires different fields, so the same payload fails the completion schema.
    expect { described_class.validate("completion", escalation) }.to raise_error(AutonomousBuild::SchemaError)
  end
end
