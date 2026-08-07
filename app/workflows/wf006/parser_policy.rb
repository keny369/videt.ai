# frozen_string_literal: true

module Workflows
  module Wf006
    # Whether a parser policy version can be resolved for a Project — the second of the
    # four ratified blocked predicates (WORKFLOW_SPECIFICATIONS.md :505, "`blocked` when
    # the manifest is invalid, PARSER POLICY IS UNAVAILABLE, zero Parsed Artifacts
    # succeeded, or zero Source-root Parsed Artifacts succeeded").
    #
    # IT IS UNAVAILABLE, AND THAT IS A FACT ABOUT THIS BUILD RATHER THAN A PLACEHOLDER.
    # A parse manifest is turned into Parsed Artifacts by the WF-006 parsing pipeline
    # (contracts/S-08.json): ParsingJob, Parsed Artifact, the `parsed-observation-v1`
    # normalization schema and the parser definition/policy versions the snapshot must
    # record. None of them exists — there is no `parsing_jobs`, `parsed_artifacts` or
    # `evaluation_input_snapshots` table in the schema — so there is no parser policy
    # version to resolve and no Parsed Artifact can succeed. Two of the four blocked
    # predicates therefore hold, truthfully, for every Evaluation this build creates.
    #
    # This is deliberately a NAMED FACT rather than a `false` buried inside the readiness
    # handler. It is the single line that changes when the parsing pipeline lands, it
    # says why it reads as it does, and a reader looking for "why did my evaluation
    # fail" finds the answer here instead of inferring it from an absent branch.
    #
    # What it is NOT: a decision about scoring, checks, issues or recommendations. Those
    # semantics stay unresolved and unfabricated. This only answers whether the inputs a
    # Check would consume can be produced today, and they cannot.
    module ParserPolicy
      module_function

      # The reason surfaced to a person reading the Evaluation, in their terms rather
      # than the contract's predicate name.
      UNAVAILABLE_EXPLANATION =
        "Content analysis is not part of this build yet, so the crawl's documents cannot be turned " \
        "into evaluation inputs."

      def available?(_organization_id = nil, _project_id = nil) = false

      def version = nil
    end
  end
end
