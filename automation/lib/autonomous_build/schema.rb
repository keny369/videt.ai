# frozen_string_literal: true

module AutonomousBuild
  # Fail-closed validation of all structured agent/controller outputs (mandate §6.6, §13;
  # AGENT_OUTPUT_SCHEMAS.md). Machine control never depends on free-form prose: malformed JSON, a
  # missing field, a wrong type, an unknown top-level field, or a disallowed status is REJECTED
  # (raises SchemaError) rather than interpreted loosely. Human-readable summaries are generated
  # from validated records, never the reverse.
  module Schema
    module_function

    COMMON = %w[schema_version role run_id block_id tranche_id status generated_at].freeze

    # schema_name => { role: expected `role` value, fields: {name => type} required beyond COMMON,
    # statuses: allowed status values }. Types: :string :integer :number :boolean :array :object.
    SCHEMAS = {
      "planner" => {
        role: "planner",
        fields: {
          "summary" => :string, "authoritative_sources" => :array, "dependencies" => :array,
          "scope" => :array, "out_of_scope" => :array, "acceptance_criteria" => :array,
          "required_verification" => :array, "protected_contracts" => :array, "assumptions" => :array,
          "possible_escalations" => :array, "recommended_action" => :string
        },
        statuses: %w[planned human_decision_required blocked_external_dependency invalid_plan]
      },
      "implementer" => {
        role: "implementer",
        fields: {
          "summary" => :string, "files_changed" => :array, "migrations_added" => :array,
          "tests_added" => :array, "commands_run" => :array, "assumptions" => :array,
          "decisions" => :array, "possible_escalations" => :array, "known_limitations" => :array,
          "recommended_next_action" => :string
        },
        statuses: %w[completed partial human_decision_required blocked_external_dependency policy_violation failed]
      },
      "verifier" => {
        role: "verifier",
        fields: {
          "verified_commit" => :string, "checks" => :array, "required_checks" => :array,
          "missing_checks" => :array, "summary" => :string
        },
        statuses: %w[pass fail incomplete controller_error]
      },
      "reviewer" => {
        role: "reviewer",
        fields: {
          "reviewed_commit" => :string, "blocking_findings" => :array, "non_blocking_findings" => :array,
          "architecture_assessment" => :string, "security_assessment" => :string,
          "test_assessment" => :string, "recommended_action" => :string
        },
        statuses: %w[pass pass_with_observations changes_required human_decision_required blocked_external_dependency review_error]
      },
      "repair" => {
        role: "repair",
        fields: {
          "addressed_findings" => :array, "unresolved_findings" => :array, "files_changed" => :array,
          "commands_run" => :array, "assumptions" => :array, "recommended_next_action" => :string
        },
        statuses: %w[completed partial human_decision_required blocked_external_dependency failed]
      },
      "escalation" => {
        role: "controller",
        fields: {
          "decision_id" => :string, "question" => :string, "recommended_option" => :string,
          "confidence" => :number, "evidence" => :array, "affected_contracts" => :array,
          "options" => :array, "default_safe_action" => :string, "consequence_of_deferral" => :string
        },
        statuses: %w[human_decision_required]
      },
      "completion" => {
        role: "controller",
        fields: {
          "base_commit" => :string, "implementation_commit" => :string, "reviewed_commit" => :string,
          "branch_name" => :string, "worktree_path" => :string, "summary" => :string,
          "guarantees_established" => :array, "verification_run_id" => :string,
          "verification_status" => :string, "review_status" => :string, "decisions_recorded" => :array,
          "remaining_risks" => :array, "known_limitations" => :array, "merge_authorised" => :boolean
        },
        statuses: %w[ready_for_review human_decision_required blocked_external_dependency verification_failed retry_limit_reached policy_violation controller_error]
      }
    }.freeze

    # Finding sub-object (reviewer). Validated when present in blocking/non_blocking findings.
    FINDING_FIELDS = {
      "finding_id" => :string, "severity" => :string, "classification" => :string, "location" => :string,
      "violated_requirement" => :string, "failure_mode" => :string, "evidence" => :array,
      "recommended_correction" => :string, "blocks_completion" => :boolean
    }.freeze
    FINDING_SEVERITIES = %w[critical high medium low observation].freeze
    FINDING_CLASSES = %w[defect risk observation false_positive].freeze

    def parse(json_text)
      JSON.parse(json_text)
    rescue JSON::ParserError => e
      raise SchemaError, "malformed JSON: #{e.message.lines.first&.strip}"
    end

    # Validate a payload (JSON string or Hash) against the named schema. Returns the validated Hash
    # (string keys) or raises SchemaError. Unknown top-level fields are rejected.
    def validate(schema_name, payload)
      spec = SCHEMAS.fetch(schema_name) { raise SchemaError, "unknown schema #{schema_name.inspect}" }
      hash = payload.is_a?(String) ? parse(payload) : payload
      raise SchemaError, "#{schema_name}: output is not a JSON object" unless hash.is_a?(Hash)

      allowed = COMMON + spec[:fields].keys
      reject_unknown_fields!(schema_name, hash, allowed)
      require_fields!(schema_name, hash, allowed)
      check_common!(schema_name, spec, hash)
      spec[:fields].each { |name, type| check_type!(schema_name, name, hash[name], type) }
      validate_findings!(hash) if schema_name == "reviewer"
      hash
    end

    def valid?(schema_name, payload)
      validate(schema_name, payload)
      true
    rescue SchemaError
      false
    end

    # ---- internals ----------------------------------------------------------

    def reject_unknown_fields!(schema_name, hash, allowed)
      extra = hash.keys - allowed
      raise SchemaError, "#{schema_name}: unexpected field(s) #{extra.join(', ')}" unless extra.empty?
    end

    def require_fields!(schema_name, hash, allowed)
      missing = allowed - hash.keys
      raise SchemaError, "#{schema_name}: missing field(s) #{missing.join(', ')}" unless missing.empty?
    end

    def check_common!(schema_name, spec, hash)
      raise SchemaError, "#{schema_name}: schema_version must be 1" unless hash["schema_version"] == 1
      raise SchemaError, "#{schema_name}: role must be #{spec[:role].inspect}" unless hash["role"] == spec[:role]
      unless spec[:statuses].include?(hash["status"])
        raise SchemaError, "#{schema_name}: status #{hash['status'].inspect} not allowed"
      end
      %w[run_id block_id tranche_id generated_at].each do |k|
        raise SchemaError, "#{schema_name}: #{k} must be a non-empty string" unless hash[k].is_a?(String) && !hash[k].empty?
      end
    end

    def check_type!(schema_name, name, value, type)
      ok =
        case type
        when :string then value.is_a?(String)
        when :integer then value.is_a?(Integer)
        when :number then value.is_a?(Numeric)
        when :boolean then value == true || value == false
        when :array then value.is_a?(Array)
        when :object then value.is_a?(Hash)
        else true
        end
      raise SchemaError, "#{schema_name}: #{name} must be #{type} (got #{value.class})" unless ok
    end

    def validate_findings!(hash)
      (hash["blocking_findings"] + hash["non_blocking_findings"]).each do |finding|
        raise SchemaError, "reviewer: finding must be an object" unless finding.is_a?(Hash)

        missing = FINDING_FIELDS.keys - finding.keys
        raise SchemaError, "reviewer finding missing #{missing.join(', ')}" unless missing.empty?
        FINDING_FIELDS.each { |name, type| check_type!("reviewer.finding", name, finding[name], type) }
        raise SchemaError, "reviewer finding severity #{finding['severity'].inspect}" unless FINDING_SEVERITIES.include?(finding["severity"])
        raise SchemaError, "reviewer finding classification #{finding['classification'].inspect}" unless FINDING_CLASSES.include?(finding["classification"])
      end
    end
  end
end
