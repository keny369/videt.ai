# frozen_string_literal: true

module Workflows
  module Wf006
    # WF-006 readiness derivation (WORKFLOW_SPECIFICATIONS.md § Readiness derivation is
    # exact, :503-509). Pure: given the facts about a Crawl's parse manifest it returns
    # exactly one of `blocked`, `ready_full` or `ready_partial` with its coverage.
    #
    #   1. `blocked` when the manifest is invalid, parser policy is unavailable, zero
    #      Parsed Artifacts succeeded, or zero Source-root Parsed Artifacts succeeded.
    #      Coverage is `partial`; no checks execute.
    #   2. `ready_full` when the Crawl coverage is full and every manifest job succeeded.
    #      Coverage is `full`.
    #   3. `ready_partial` in every remaining case with at least one successful Parsed
    #      Artifact and at least one successful Source-root Parsed Artifact.
    #
    # All three branches are implemented and pinned even though only `blocked` is
    # reachable today, because the derivation is the ratified rule and not a description
    # of the current build: when the parsing pipeline lands, the other two become live
    # without this file changing. What makes `blocked` the honest answer NOW is
    # `ParserPolicy.available?` — see that file.
    module EvaluationInputReadiness
      module_function

      BLOCKED = "blocked"
      READY_FULL = "ready_full"
      READY_PARTIAL = "ready_partial"

      FULL = "full"
      PARTIAL = "partial"

      # The single reason a blocked derivation carries, fixed by the contract
      # (API_CONTRACTS.md :826 "literal `evaluation_inputs_unavailable`").
      BLOCKED_REASON = "evaluation_inputs_unavailable"

      Result = Data.define(:readiness_status, :coverage_status, :reason, :blocked_predicate) do
        def blocked? = readiness_status == BLOCKED
        def ready? = !blocked?
      end

      # `crawl_coverage` is the sealed Crawl's own `coverage_status` (`full` or `partial`,
      # and nil for a Crawl that failed before deriving one).
      def derive(manifest_valid:, parser_policy_available:, parsed_artifacts_succeeded:,
                 source_root_artifacts_succeeded:, manifest_entries:, jobs_succeeded:, crawl_coverage:)
        predicate = blocked_predicate(manifest_valid:, parser_policy_available:, parsed_artifacts_succeeded:,
                                      source_root_artifacts_succeeded:)
        return blocked(predicate) if predicate

        if crawl_coverage == FULL && jobs_succeeded == manifest_entries
          return Result.new(readiness_status: READY_FULL, coverage_status: FULL, reason: nil, blocked_predicate: nil)
        end

        Result.new(readiness_status: READY_PARTIAL, coverage_status: PARTIAL, reason: nil, blocked_predicate: nil)
      end

      # The four blocked predicates in the order the contract lists them. The FIRST match
      # is retained, so the audit record can say which one fired rather than only that
      # something did.
      def blocked_predicate(manifest_valid:, parser_policy_available:, parsed_artifacts_succeeded:,
                            source_root_artifacts_succeeded:)
        return "input_manifest_invalid" unless manifest_valid
        return "parser_policy_unavailable" unless parser_policy_available
        return "no_parsed_artifact_succeeded" if parsed_artifacts_succeeded.to_i.zero?
        return "no_source_root_parsed_artifact_succeeded" if source_root_artifacts_succeeded.to_i.zero?

        nil
      end

      def blocked(predicate)
        Result.new(readiness_status: BLOCKED, coverage_status: PARTIAL, reason: BLOCKED_REASON,
                   blocked_predicate: predicate)
      end
    end
  end
end
