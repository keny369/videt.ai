# frozen_string_literal: true

require "digest"

module Workflows
  module Wf007
    # The COMMON PURE CHECK EXECUTOR `check-executor-interim-v1`
    # (SCORE_EVIDENCE_MODEL.md § Common Pure Check Executor; PRULE-010; PRULE-012).
    #
    # It takes one frozen applicability entry and its revealed Evidence payloads, dispatches
    # to the Definition's rule in `Checks`, and returns the complete semantic output plus the
    # two hashes that make replay checkable. It performs no I/O of any kind: the caller
    # reveals the Evidence and persists the Result, and this decides.
    #
    # THE TWO HASHES ARE NOT THE SAME KIND OF THING. `deterministic_input_hash` is over the
    # frozen inputs, so a changed Evidence digest changes it (FX-CHECK-COM-002) and the same
    # inputs always produce it. `deterministic_output_hash` is over the SEMANTIC output only —
    # generated identifiers, attempt timestamps, correlation identifiers and `produced_at_utc`
    # are EXCLUDED from semantic equality, because a replay that differed only in when it ran
    # would otherwise be indistinguishable from one that decided differently.
    module Executor
      module_function

      SCHEMA_VERSION = "check-result-v1"

      Decision = Data.define(:execution_status, :outcome_code, :error_reason_code, :observation,
                             :subject_set_complete, :impact_band, :impact_rule_version, :confidence,
                             :effort, :recommendation_template_id, :rule_or_model_version,
                             :input_sha256, :output_sha256)

      # `evidence_payloads` maps evidence_id => revealed payload Hash. A payload that is
      # absent from the map is absent to the Check, which is what makes the baseline
      # `input_evidence_missing` a deterministic selection rather than a lookup failure.
      def run(entry:, definition:, input:, evidence_payloads:, project_profile_version: nil)
        outcome = evaluate(definition, entry, evidence_payloads, project_profile_version)
        impact = Policies.impact_band(definition, outcome.execution_status, outcome.outcome_code,
                                      outcome.observation)
        effort = Policies.effort(definition, outcome.execution_status, outcome.outcome_code,
                                 outcome.observation)
        # Passed, failed and not-applicable results use confidence `1.0000`, `valid`, band
        # `high`; handled errors use the common null/missing/low fallback.
        confidence = outcome.error? ? Policies.missing_confidence : Policies.decided_confidence

        input_sha256 = Digest::SHA256.digest(Platform::CanonicalJson.encode(input))
        semantic = semantic_output(entry, definition, outcome, impact, confidence)
        Decision.new(
          execution_status: outcome.execution_status, outcome_code: outcome.outcome_code,
          error_reason_code: outcome.error_reason_code, observation: outcome.observation,
          subject_set_complete: outcome.subject_set_complete, impact_band: impact,
          impact_rule_version: definition["impact_rule_version"], confidence:, effort:,
          recommendation_template_id: definition["recommendation_templates"][outcome.outcome_code],
          rule_or_model_version: CheckCatalog.rule_version(definition["check_definition_id"]),
          input_sha256:, output_sha256: Digest::SHA256.digest(Platform::CanonicalJson.encode(semantic))
        )
      end

      # The canonical input tuple, exactly as the Check Result Contract orders it. Locale is
      # `en-AU` and the time-zone assumption is UTC unless a Definition explicitly versions
      # another value; none of the seven does.
      def input_tuple(organization_id:, project_id:, input_snapshot_id:, catalog_version:, catalog_sha256:,
                      applicability_snapshot_id:, applicability_sha256:, definition:, entry:)
        {
          "organization_id" => organization_id,
          "project_id" => project_id,
          "evaluation_input_snapshot_id" => input_snapshot_id,
          "check_catalog_version" => catalog_version,
          "check_catalog_sha256" => catalog_sha256,
          "check_applicability_snapshot_id" => applicability_snapshot_id,
          "check_applicability_snapshot_sha256" => applicability_sha256,
          "check_definition_id" => definition["check_definition_id"],
          "check_definition_version" => definition["semantic_version"],
          "pillar_id" => definition["pillar_id"],
          "subject_scope" => entry["subject_scope"],
          "canonical_subject_type" => entry["canonical_subject_type"],
          "canonical_subject_key" => entry["canonical_subject_key"],
          "absence_coverage_selector" => entry["absence_selector"],
          # Sorted Evidence identifiers and digests with their effective Validation Decision
          # identifiers and statuses. Sorting is what makes an array permutation of the same
          # selection produce an identical hash.
          "selected_evidence" => Array(entry["selected_evidence"]).sort_by { |e| e["evidence_id"].to_s },
          "impact_rule_version" => definition["impact_rule_version"],
          "effort_policy_version" => Policies::EFFORT_POLICY_VERSION,
          "confidence_policy_version" => Policies::CONFIDENCE_POLICY_VERSION,
          "executor_policy_version" => CheckCatalog::EXECUTOR_POLICY,
          "rule_or_model_version" => CheckCatalog.rule_version(definition["check_definition_id"]),
          "locale" => CheckCatalog::LOCALE,
          "time_zone" => CheckCatalog::TIME_ZONE
        }
      end

      # "execution status, outcome code, normalized observation, impact band, confidence value
      # or status, confidence band, pillar, subject identity, absence selector, and
      # subject-set-complete flag" — and nothing else.
      def semantic_output(entry, definition, outcome, impact, confidence)
        {
          "execution_status" => outcome.execution_status,
          "outcome_code" => outcome.outcome_code,
          "error_reason_code" => outcome.error_reason_code,
          "normalized_observation" => outcome.observation,
          "impact_band" => impact,
          "confidence_value" => confidence["confidence_value"],
          "confidence_status" => confidence["confidence_status"],
          "confidence_band" => confidence["confidence_band"],
          "pillar_id" => definition["pillar_id"],
          "canonical_subject_type" => entry["canonical_subject_type"],
          "canonical_subject_key" => entry["canonical_subject_key"],
          "absence_coverage_selector" => entry["absence_selector"],
          "subject_set_complete" => outcome.subject_set_complete
        }
      end

      # The dispatch table. It is a closed `case` on the ratified Definition identifiers
      # rather than a constant lookup or a `send`, so an identifier that is not one of the
      # seven cannot reach a rule at all.
      def evaluate(definition, entry, evidence_payloads, project_profile_version = nil)
        return stale_outcome(definition, entry) if stale_selection?(entry)

        payload = first_payload(entry, evidence_payloads)
        case definition["check_definition_id"]
        when "CHK-TI-001" then Checks.chk_ti_001(payload:, source_id: entry["source_id"])
        when "CHK-CQ-001" then Checks.chk_cq_001(payload:, canonical_url: entry["canonical_subject_key"])
        when "CHK-TR-001" then Checks.chk_tr_001(payload:, source_id: entry["source_id"])
        when "CHK-SP-001" then Checks.chk_sp_001(payload:, project_id: entry["canonical_subject_key"])
        when "CHK-AIP-001" then Checks.chk_aip_001(payload:, project_id: entry["canonical_subject_key"])
        when "CHK-AS-001" then Checks.chk_as_001(payload:, project_id: entry["canonical_subject_key"])
        when "CHK-LP-001"
          # The profile version comes from the SNAPSHOT, not from the selector instance: the
          # selector contains "exactly the entry's Organization, Project, nullable Source,
          # subject type, and canonical subject key", and smuggling a sixth field into it
          # would make two Evaluations of the same subject produce different selectors.
          Checks.chk_lp_001(payload:, project_id: entry["canonical_subject_key"],
                            applicable: entry["applicable"], profile_version: project_profile_version,
                            inapplicable_reason: entry["inapplicable_reason"])
        else
          raise Policies::CatalogIntegrityFailure, "unknown_definition:#{definition['check_definition_id']}"
        end
      end

      # Every Definition selects at most one Evidence record, so "the first selected payload"
      # is the whole selection. `nil` when the entry selected none — which the rules treat as
      # `input_evidence_missing`, the ratified baseline outcome for the four measurement-fed
      # Definitions.
      def first_payload(entry, evidence_payloads)
        selected = Array(entry["selected_evidence"]).first
        return nil if selected.nil?

        evidence_payloads[selected["evidence_id"]]
      end

      # STALENESS IS DECIDED BEFORE THE RULE RUNS, and it OUTRANKS every reason the rule could
      # reach. The ratified first-match order is `input_evidence_missing`, `input_evidence_stale`,
      # `input_evidence_indeterminate`, `input_evidence_invalid`, ... — so an observation that is
      # both expired AND partially covered is STALE, not indeterminate. Letting the rule see it
      # first would report the second reason and hide the first, and "your coverage was partial"
      # is a very different sentence from "this measurement expired".
      #
      # It is decided here rather than inside each Definition because freshness is a property of
      # the SELECTION — it needs the snapshot's sealed instant, which a pure rule does not have
      # and must not acquire, since reading a clock is exactly what `check-executor-interim-v1`
      # forbids.
      def stale_selection?(entry)
        Array(entry["selected_evidence"]).any? { |e| e["freshness"] == "stale" }
      end

      # The Definition's own domain outcome, carrying the stale reason. The outcome equals the
      # reason "unless the Definition expressly names a narrower domain outcome" — all four
      # measurement Definitions do, so the domain code is used and the reason records why.
      def stale_outcome(definition, entry)
        code = definition["outcomes"].find { |o| o["execution_status"] == "failed" }&.fetch("outcome_code")
        Checks.error(code, "input_evidence_stale",
                     { "reason" => "input_evidence_stale",
                       "canonical_subject_key" => entry["canonical_subject_key"] })
      end
    end
  end
end
