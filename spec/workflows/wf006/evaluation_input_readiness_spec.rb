# frozen_string_literal: true

require "rails_helper"

# WF-006 readiness derivation (WORKFLOW_SPECIFICATIONS.md :503-509). Pure, so every branch
# is pinned exactly as the contract words it — including the two that cannot be reached
# until the parsing pipeline exists, because the rule is ratified and this file is what
# will hold it when they become live.
RSpec.describe Workflows::Wf006::EvaluationInputReadiness, type: :model do
  def derive(**overrides)
    described_class.derive(**{
      manifest_valid: true, parser_policy_available: true,
      parsed_artifacts_succeeded: 3, source_root_artifacts_succeeded: 1,
      manifest_entries: 3, jobs_succeeded: 3, crawl_coverage: "full"
    }.merge(overrides))
  end

  describe "the four blocked predicates, in the contract's order" do
    it "blocks on an invalid manifest" do
      result = derive(manifest_valid: false)

      expect(result).to be_blocked
      expect(result.blocked_predicate).to eq("input_manifest_invalid")
    end

    it "blocks when parser policy is unavailable" do
      expect(derive(parser_policy_available: false).blocked_predicate).to eq("parser_policy_unavailable")
    end

    it "blocks when zero Parsed Artifacts succeeded" do
      expect(derive(parsed_artifacts_succeeded: 0).blocked_predicate).to eq("no_parsed_artifact_succeeded")
    end

    it "blocks when zero Source-root Parsed Artifacts succeeded" do
      expect(derive(source_root_artifacts_succeeded: 0).blocked_predicate)
        .to eq("no_source_root_parsed_artifact_succeeded")
    end

    it "reports the FIRST matching predicate, so the audit names which one fired" do
      result = derive(manifest_valid: false, parser_policy_available: false, parsed_artifacts_succeeded: 0)

      expect(result.blocked_predicate).to eq("input_manifest_invalid")
    end

    it "always carries partial coverage and the one literal reason" do
      result = derive(parser_policy_available: false)

      expect(result.coverage_status).to eq("partial")
      expect(result.reason).to eq("evaluation_inputs_unavailable")
    end
  end

  describe "ready_full" do
    it "requires full crawl coverage AND every manifest job succeeded" do
      result = derive(crawl_coverage: "full", manifest_entries: 3, jobs_succeeded: 3)

      expect(result.readiness_status).to eq("ready_full")
      expect(result.coverage_status).to eq("full")
      expect(result.reason).to be_nil
    end

    it "degrades to ready_partial when the crawl covered only part of the source" do
      expect(derive(crawl_coverage: "partial").readiness_status).to eq("ready_partial")
    end

    it "degrades to ready_partial when a manifest job did not succeed" do
      result = derive(crawl_coverage: "full", manifest_entries: 3, jobs_succeeded: 2)

      expect(result.readiness_status).to eq("ready_partial")
      expect(result.coverage_status).to eq("partial")
    end
  end

  describe "what this build actually derives" do
    # These two examples track a FACT ABOUT THE BUILD, and the fact changed when the S-08
    # parsing limb landed: a parser policy now resolves, so the predicate that used to hold
    # for every Evaluation no longer does. They are kept rather than deleted because the
    # value is in pinning what the derivation reads from, not in the answer of the day.
    it "resolves a parser policy, so that predicate no longer blocks" do
      expect(Workflows::Wf006::ParserPolicy.available?).to be(true)
      expect(Workflows::Wf006::ParserPolicy.version).to eq("parser-policy-interim-v1")
    end

    it "is still blocked when the manifest produced no Parsed Artifact" do
      result = described_class.derive(
        manifest_valid: true,
        parser_policy_available: Workflows::Wf006::ParserPolicy.available?,
        parsed_artifacts_succeeded: 0, source_root_artifacts_succeeded: 0,
        manifest_entries: 1, jobs_succeeded: 0, crawl_coverage: "full"
      )

      expect(result).to be_blocked
      expect(result.blocked_predicate).to eq("no_parsed_artifact_succeeded")
      expect(result.reason).to eq("evaluation_inputs_unavailable")
    end

    it "is READY when the parser produced a Source-root Artifact for a fully covered crawl" do
      result = described_class.derive(
        manifest_valid: true,
        parser_policy_available: Workflows::Wf006::ParserPolicy.available?,
        parsed_artifacts_succeeded: 1, source_root_artifacts_succeeded: 1,
        manifest_entries: 1, jobs_succeeded: 1, crawl_coverage: "full"
      )

      expect(result).to be_ready
      expect(result.readiness_status).to eq("ready_full")
      expect(result.reason).to be_nil
    end
  end
end
