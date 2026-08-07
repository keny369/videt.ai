# frozen_string_literal: true

module Workflows
  module Wf006
    # Whether a parser policy version can be resolved for a Project — the second of the four
    # ratified blocked predicates (WORKFLOW_SPECIFICATIONS.md :505, "`blocked` when the
    # manifest is invalid, PARSER POLICY IS UNAVAILABLE, zero Parsed Artifacts succeeded, or
    # zero Source-root Parsed Artifacts succeeded").
    #
    # IT IS NOW AVAILABLE, AND THAT IS AGAIN A FACT ABOUT THIS BUILD. Until the S-08 parsing
    # limb landed there was no ParsingJob, no Parsed Artifact and no normalization schema, so
    # no policy version existed to name and two of the four predicates held for every
    # Evaluation. The parser, its definition version and the `parsed-observation-v1` schema
    # now exist, so the honest answer changed with the code rather than with a decision.
    #
    # WHAT IT STILL DOES NOT CLAIM. The versions below name a parser and a normalization
    # schema, nothing else. Check semantics, scoring and recommendations remain unresolved
    # and unimplemented; a resolvable parser policy only means a Document's bytes can become
    # a Parsed Artifact, which is exactly what the predicate asks.
    #
    # `html-parser-interim-v1` is an INTERIM in the same sense as `source-scope-interim-v1`
    # and `ingestion-interim-v1`: baseline media types only (`text/html` and
    # `application/xhtml+xml`, :480), and no owner decision is pre-empted by it.
    module ParserPolicy
      module_function

      DEFINITION_VERSION = ParsedObservation::PARSER_DEFINITION_VERSION
      NORMALIZATION_SCHEMA_VERSION = ParsedObservation::SCHEMA_VERSION
      POLICY_VERSION = "parser-policy-interim-v1"

      # Not per-Project today: one parser definition serves every tenant, and there is no
      # per-Project parser configuration to resolve. The arguments are accepted so the
      # callers do not change when there is.
      def available?(_organization_id = nil, _project_id = nil) = true

      def version = POLICY_VERSION
    end
  end
end
