# frozen_string_literal: true

module Workflows
  module Wf007
    # `check-catalog-v1` — the RATIFIED Check Catalog, transcribed
    # (SCORE_EVIDENCE_MODEL.md § Check Definition And Check Catalog Contract and
    # § Mandatory Check Definitions; OD-010 **Ratified 2026-07-17, ratified as specified**).
    #
    # THIS AUTHORS NOTHING. Every value below is copied from the ratified contract: seven
    # Definitions, no more and no fewer, with their exact outcome codes, impact boundaries,
    # effort mappings, rule versions, recommendation template identifiers, subject
    # cardinalities and Evidence selectors. OD-010 approved `check-catalog-v1` as specified,
    # so the implementation's job here is transcription and proof, not design. Frozen prose
    # elsewhere calling this catalogue `status: active_interim` or "pending OD-010 approval"
    # is pre-ratification wording; it neither reopens the decision nor broadens the catalogue.
    #
    # THE CATALOGUE IS GLOBAL AND THE RUNTIME CANNOT WRITE IT. The three tables carry no
    # `organization_id` and the runtime role holds SELECT only, so "Tenant actors cannot
    # create, edit, disable, remap, or reorder a Definition" is a privilege, not a promise.
    # `seed!` runs on the owner connection from the provisioning task, alongside the reserved
    # Service Identities, for the same reason those are provisioned there: db/structure.sql
    # carries no data, so a migration-time INSERT would never run on the structure-load route.
    #
    # IDENTITIES ARE DERIVED FROM CONTENT. A Definition's row id is `DerivedUuid.v8` over its
    # own content digest, so the same Definition has the same identity in every environment
    # and re-seeding is a no-op rather than a second row. It also makes the prohibition on
    # "reuse of a Definition version for changed content" self-evident: changed content is a
    # different digest, hence a different identity, hence a distinct row that the unique
    # `(definition_id, semantic_version)` key then refuses.
    module CheckCatalog
      module_function

      CATALOG_VERSION = "check-catalog-v1"
      OWNER = "Chief Product"
      RELEASED_AT = "2026-07-16T00:00:00Z"
      EXECUTOR_POLICY = "check-executor-interim-v1"
      EXTERNAL_MEASUREMENT_POLICY = "external-measurement-v1"
      EFFORT_POLICY = "effort-interim-v1"
      CONFIDENCE_POLICY = "confidence-policy-v1"
      ABSENCE_PROOF_MODE = "check_pass_resolves_all"
      LOCALE = "en-AU"
      TIME_ZONE = "UTC"

      # The exact seven Pillars, in Catalog order. Exactly one score-capable Definition per
      # Pillar is an activation-validation obligation, so the two lists are proved against
      # each other rather than kept in step by hand.
      PILLARS = %w[technical_integrity content_quality trust_signals search_presence
                   ai_presence authority_signals local_presence].freeze

      # ---- the seven ratified Definitions ------------------------------------------------
      #
      # `outcomes` is the exhaustive execution-status/outcome-code mapping, IN FIRST-MATCH
      # ORDER where the contract specifies one. `impact` and `effort` are the exhaustive
      # mappings from a failed outcome (and, for the threshold Definitions, from the
      # normalized observation) to a band. A Definition with a nonexhaustive mapping cannot
      # enter an active Catalog, which `validate!` proves rather than assumes.
      DEFINITIONS = [
        {
          "check_definition_id" => "CHK-TI-001",
          "semantic_version" => "1.0.0",
          "purpose" => "Detect broken in-scope internal targets.",
          "capability_id" => "CAP-009",
          "pillar_id" => "technical_integrity",
          "evidence_type" => "crawl_observation",
          "evidence_schema_version" => "internal-link-observation-v1",
          "subject_scope" => "source",
          "canonical_subject_type" => "source",
          "cardinality" => "one_per_active_source",
          # Exhaustive, and the ERROR PRECEDES failed and pass evaluation: an implementation
          # that evaluates the absent set before checking coverage reports a pass on a
          # partial crawl.
          "outcomes" => [
            { "execution_status" => "error", "outcome_code" => "internal_link_coverage_incomplete",
              "error_reason_code" => "input_evidence_indeterminate" },
            { "execution_status" => "failed", "outcome_code" => "broken_internal_links",
              "issue_type" => "broken_internal_links" },
            { "execution_status" => "passed", "outcome_code" => "internal_links_resolve" }
          ],
          "impact_rule_version" => "impact-CHK-TI-001-v1",
          # 1-4 low, 5-19 medium, 20 or more high, keyed on the absent-target count.
          "impact" => { "broken_internal_links" => { "metric" => "absent_count",
                                                     "thresholds" => [[1, "low"], [5, "medium"], [20, "high"]] } },
          "effort" => { "broken_internal_links" => { "metric" => "absent_count",
                                                     "thresholds" => [[1, "low"], [5, "medium"], [20, "high"]] } },
          "recommendation_templates" => { "broken_internal_links" => "REC-CHK-TI-001-v1" },
          "normalized_observation_fields" => %w[source_id canonical_root total_target_count reachable_count
                                                absent_count unobserved_count absent_target_keys absent_targets],
          "acceptance_fixtures" => (1..10).map { |n| format("FX-CHK-TI-001-%02d", n) }
        },
        {
          "check_definition_id" => "CHK-CQ-001",
          "semantic_version" => "1.0.0",
          "purpose" => "Require one nonblank title per parsed page.",
          "capability_id" => "CAP-010",
          "pillar_id" => "content_quality",
          "evidence_type" => "parsed_content",
          "evidence_schema_version" => "document-title-observation-v1",
          "subject_scope" => "document",
          "canonical_subject_type" => "url",
          "cardinality" => "one_per_parsed_document",
          "outcomes" => [
            { "execution_status" => "failed", "outcome_code" => "meta_title_missing",
              "issue_type" => "meta_title_missing" },
            { "execution_status" => "passed", "outcome_code" => "meta_title_present" },
            { "execution_status" => "failed", "outcome_code" => "meta_title_multiple",
              "issue_type" => "meta_title_multiple" }
          ],
          "impact_rule_version" => "impact-CHK-CQ-001-v1",
          "impact" => { "meta_title_missing" => { "band" => "medium" },
                        "meta_title_multiple" => { "band" => "low" } },
          "effort" => { "meta_title_missing" => { "band" => "low" },
                        "meta_title_multiple" => { "band" => "low" } },
          "recommendation_templates" => { "meta_title_missing" => "REC-CHK-CQ-001-v1",
                                          "meta_title_multiple" => "REC-CHK-CQ-001-v1" },
          "normalized_observation_fields" => %w[canonical_url title_node_count nonblank_title_count title_nodes],
          "acceptance_fixtures" => (1..6).map { |n| format("FX-CHK-CQ-001-%02d", n) }
        },
        {
          "check_definition_id" => "CHK-TR-001",
          "semantic_version" => "1.0.0",
          "purpose" => "Require valid Organization structured data matching the frozen public identity.",
          "capability_id" => "CAP-011",
          "pillar_id" => "trust_signals",
          "evidence_type" => "parsed_content",
          "evidence_schema_version" => "organization-identity-observation-v1",
          "subject_scope" => "source",
          "canonical_subject_type" => "source",
          "cardinality" => "one_per_active_source",
          # FIRST-MATCH ORDER, and the order matters where two branches would both match: a
          # payload with no schema-valid node AND a mismatch satisfies both `schema_invalid`
          # and `identity_mismatch`, and the contract selects the former.
          "outcomes" => [
            { "execution_status" => "failed", "outcome_code" => "organization_schema_missing",
              "issue_type" => "organization_schema_missing" },
            { "execution_status" => "passed", "outcome_code" => "organization_identity_consistent" },
            { "execution_status" => "failed", "outcome_code" => "organization_schema_invalid",
              "issue_type" => "organization_schema_invalid" },
            { "execution_status" => "failed", "outcome_code" => "organization_identity_mismatch",
              "issue_type" => "organization_identity_mismatch" }
          ],
          "impact_rule_version" => "impact-CHK-TR-001-v1",
          "impact" => { "organization_schema_missing" => { "band" => "medium" },
                        "organization_schema_invalid" => { "band" => "medium" },
                        "organization_identity_mismatch" => { "band" => "high" } },
          "effort" => { "organization_schema_missing" => { "band" => "medium" },
                        "organization_schema_invalid" => { "band" => "medium" },
                        "organization_identity_mismatch" => { "band" => "medium" } },
          "recommendation_templates" => { "organization_schema_missing" => "REC-CHK-TR-001-v1",
                                          "organization_schema_invalid" => "REC-CHK-TR-001-v1",
                                          "organization_identity_mismatch" => "REC-CHK-TR-001-v1" },
          "normalized_observation_fields" => %w[source_id canonical_root public_identity_profile_id
                                                public_identity_profile_version node_count valid_node_count
                                                matching_node_count nodes],
          "acceptance_fixtures" => (1..6).map { |n| format("FX-CHK-TR-001-%02d", n) }
        },
        {
          "check_definition_id" => "CHK-SP-001",
          "semantic_version" => "1.0.0",
          "purpose" => "Measure observed presence for the complete frozen search-query set.",
          "capability_id" => "CAP-010",
          "pillar_id" => "search_presence",
          "evidence_type" => "external_measurement",
          "evidence_schema_version" => "external-observation-v1",
          "measurement_kind" => "search_index_presence",
          "subject_scope" => "project",
          "canonical_subject_type" => "project",
          "cardinality" => "one_per_project",
          "outcomes" => [
            { "execution_status" => "passed", "outcome_code" => "search_presence_complete" },
            { "execution_status" => "failed", "outcome_code" => "search_presence_gap",
              "issue_type" => "search_presence_gap" }
          ],
          "impact_rule_version" => "impact-CHK-SP-001-v1",
          # Rate `0.0000` is high; `0.0000 < rate < 1.0000` is medium. A pass is the only
          # other reachable state, so the mapping is exhaustive over failed outcomes.
          "impact" => { "search_presence_gap" => { "metric" => "presence_rate",
                                                   "zero_band" => "high", "partial_band" => "medium" } },
          "effort" => { "search_presence_gap" => { "band" => "medium" } },
          "recommendation_templates" => { "search_presence_gap" => "REC-CHK-SP-001-v1" },
          "normalized_observation_fields" => %w[measurement_policy_version collector_adapter_id
                                                collector_adapter_version measurement_set_version expected_count
                                                present_count absent_count presence_rate absent_query_keys],
          "acceptance_fixtures" => (1..9).map { |n| format("FX-CHK-SP-001-%02d", n) }
        },
        {
          "check_definition_id" => "CHK-AIP-001",
          "semantic_version" => "1.0.0",
          "purpose" => "Measure attributable, cited presence for the complete frozen AI-intent set.",
          "capability_id" => "CAP-010",
          "pillar_id" => "ai_presence",
          "evidence_type" => "external_measurement",
          "evidence_schema_version" => "external-observation-v1",
          "measurement_kind" => "ai_answer_presence",
          "subject_scope" => "project",
          "canonical_subject_type" => "project",
          "cardinality" => "one_per_project",
          "outcomes" => [
            { "execution_status" => "passed", "outcome_code" => "ai_answer_presence_complete" },
            { "execution_status" => "failed", "outcome_code" => "ai_answer_presence_gap",
              "issue_type" => "ai_answer_presence_gap" }
          ],
          "impact_rule_version" => "impact-CHK-AIP-001-v1",
          "impact" => { "ai_answer_presence_gap" => { "metric" => "qualified_rate",
                                                      "zero_band" => "high", "partial_band" => "medium" } },
          "effort" => { "ai_answer_presence_gap" => { "band" => "high" } },
          "recommendation_templates" => { "ai_answer_presence_gap" => "REC-CHK-AIP-001-v1" },
          "normalized_observation_fields" => %w[measurement_policy_version collector_adapter_id
                                                collector_adapter_version measurement_set_version expected_count
                                                qualified_count unqualified_count qualified_rate
                                                unqualified_intent_keys],
          "acceptance_fixtures" => (1..6).map { |n| format("FX-CHK-AIP-001-%02d", n) }
        },
        {
          "check_definition_id" => "CHK-AS-001",
          "semantic_version" => "1.0.0",
          "purpose" => "Establish at least one attributable external backlink or brand mention.",
          "capability_id" => "CAP-010",
          "pillar_id" => "authority_signals",
          "evidence_type" => "external_measurement",
          "evidence_schema_version" => "external-observation-v1",
          "measurement_kind" => "authority_reference_set",
          "subject_scope" => "project",
          "canonical_subject_type" => "project",
          "cardinality" => "one_per_project",
          "outcomes" => [
            { "execution_status" => "passed", "outcome_code" => "authority_reference_present" },
            { "execution_status" => "failed", "outcome_code" => "authority_reference_absent",
              "issue_type" => "authority_reference_absent" }
          ],
          "impact_rule_version" => "impact-CHK-AS-001-v1",
          "impact" => { "authority_reference_absent" => { "band" => "medium" } },
          "effort" => { "authority_reference_absent" => { "band" => "high" } },
          "recommendation_templates" => { "authority_reference_absent" => "REC-CHK-AS-001-v1" },
          "normalized_observation_fields" => %w[measurement_policy_version collector_adapter_id
                                                collector_adapter_version measurement_set_version backlink_count
                                                brand_mention_count attributable_count nonattributable_count
                                                total_count attributable_observation_keys],
          "acceptance_fixtures" => (1..6).map { |n| format("FX-CHK-AS-001-%02d", n) }
        },
        {
          "check_definition_id" => "CHK-LP-001",
          "semantic_version" => "1.0.0",
          "purpose" => "Measure presence and identity consistency across the frozen required local-listing set.",
          "capability_id" => "CAP-010",
          "pillar_id" => "local_presence",
          "evidence_type" => "external_measurement",
          "evidence_schema_version" => "external-observation-v1",
          "measurement_kind" => "local_profile_consistency",
          "subject_scope" => "project",
          "canonical_subject_type" => "project",
          "cardinality" => "one_per_project",
          # The ONE Definition for which `not_applicable` is valid, and only from a validly
          # false frozen applicability decision carrying its nonblank reason.
          "outcomes" => [
            { "execution_status" => "not_applicable", "outcome_code" => "local_presence_not_applicable" },
            { "execution_status" => "passed", "outcome_code" => "local_profiles_consistent" },
            { "execution_status" => "failed", "outcome_code" => "local_profiles_absent",
              "issue_type" => "local_profiles_absent" },
            { "execution_status" => "failed", "outcome_code" => "local_profile_inconsistent",
              "issue_type" => "local_profile_inconsistent" }
          ],
          "impact_rule_version" => "impact-CHK-LP-001-v1",
          "impact" => { "local_profiles_absent" => { "band" => "high" },
                        "local_profile_inconsistent" => { "band" => "medium" } },
          "effort" => { "local_profiles_absent" => { "band" => "medium" },
                        "local_profile_inconsistent" => { "band" => "medium" } },
          # "no Artifact is generated for not-applicable" — the mapping covers failed
          # outcomes only, which is what makes its exhaustiveness checkable.
          "recommendation_templates" => { "local_profiles_absent" => "REC-CHK-LP-001-v1",
                                          "local_profile_inconsistent" => "REC-CHK-LP-001-v1" },
          "normalized_observation_fields" => %w[measurement_policy_version collector_adapter_id
                                                collector_adapter_version measurement_set_version required_count
                                                present_count qualified_count nonqualified_listing_keys],
          "acceptance_fixtures" => (1..6).map { |n| format("FX-CHK-LP-001-%02d", n) }
        }
      ].freeze

      DEFINITION_IDS = DEFINITIONS.map { |d| d["check_definition_id"] }.freeze

      # The complete semantic body a Definition's content digest is taken over. Every field
      # the contract enumerates is present; the row's generated identity is NOT, because an
      # identity derived from the digest cannot also be an input to it.
      def semantic_body(definition)
        definition.merge(
          "owner" => OWNER,
          "released_at_utc" => RELEASED_AT,
          "score_capable" => true,
          "rule_or_model_version" => rule_version(definition["check_definition_id"]),
          "confidence_rule" => "deterministic_binary_1.0000",
          "confidence_policy_version" => CONFIDENCE_POLICY,
          "effort_policy_version" => EFFORT_POLICY,
          "executor_policy_version" => EXECUTOR_POLICY,
          "absence_proof_mode" => ABSENCE_PROOF_MODE,
          "locale" => LOCALE,
          "time_zone" => TIME_ZONE
        )
      end

      # "Each Definition's `rule_or_model_version` is exactly `<check_definition_id>-rule-v1`
      # ... none invokes a model."
      def rule_version(definition_id) = "#{definition_id}-rule-v1"

      def definition(definition_id)
        DEFINITIONS.find { |d| d["check_definition_id"] == definition_id } ||
          raise(ArgumentError, "#{definition_id} is not in #{CATALOG_VERSION}")
      end

      def definition_digest(definition) = Platform::CanonicalJson.digest(semantic_body(definition))
      def definition_row_id(definition) = Platform::DerivedUuid.v8(definition_digest(definition))

      # The Catalog content hash is SHA-256 over canonical JSON of every field except the
      # content hash itself, with membership as the ordered ID/version/digest tuples.
      def catalog_body
        {
          "check_catalog_version" => CATALOG_VERSION,
          "owner" => OWNER,
          "released_at_utc" => RELEASED_AT,
          "executor_policy_version" => EXECUTOR_POLICY,
          "external_measurement_policy_version" => EXTERNAL_MEASUREMENT_POLICY,
          "effort_policy_version" => EFFORT_POLICY,
          "membership" => DEFINITIONS.map do |d|
            { "check_definition_id" => d["check_definition_id"],
              "definition_version" => d["semantic_version"],
              "content_sha256" => hex(definition_digest(d)) }
          end,
          "superseded_catalog_version" => nil
        }
      end

      def catalog_digest = Platform::CanonicalJson.digest(catalog_body)
      def catalog_row_id = Platform::DerivedUuid.v8(catalog_digest)
      def catalog_entry_row_id(definition)
        Platform::DerivedUuid.v8(Platform::CanonicalJson.digest(
                                   { "catalog" => CATALOG_VERSION,
                                     "definition" => definition["check_definition_id"],
                                     "version" => definition["semantic_version"] }
                                 ))
      end

      def hex(bytes) = bytes.unpack1("H*")

      # ---- activation validation ---------------------------------------------------------
      #
      # "Activation validation recomputes the Catalog and Definition digests; proves exactly
      # one score-capable Definition for each Pillar; proves every outcome, impact, effort,
      # template, subject, error, and fixture mapping exhaustive; and rejects unknown or
      # duplicate membership." It runs before execution and commits nothing, and a Catalog
      # that fails it executes NOTHING — there is no partially validated Catalog.
      #
      # Returns an array of failure strings; empty means valid.
      def validation_failures
        failures = []
        # Derived from DEFINITIONS here rather than read from `DEFINITION_IDS`. The constant
        # is computed once at load and is the ordering lookup; validating against it would
        # compare the catalogue to a cached copy of itself and pass on a membership that had
        # actually changed.
        ids = DEFINITIONS.map { |d| d["check_definition_id"] }
        failures << "membership_not_seven" unless DEFINITIONS.length == 7
        failures << "membership_duplicated" unless ids.uniq.length == ids.length

        pillars = DEFINITIONS.map { |d| d["pillar_id"] }
        failures << "pillar_coverage_incomplete" unless pillars.sort == PILLARS.sort
        failures << "pillar_not_exactly_one" unless pillars.uniq.length == pillars.length

        DEFINITIONS.each do |d|
          id = d["check_definition_id"]
          failed = d["outcomes"].select { |o| o["execution_status"] == "failed" }.map { |o| o["outcome_code"] }
          failures << "impact_nonexhaustive:#{id}" unless failed.all? { |code| d["impact"].key?(code) }
          failures << "effort_nonexhaustive:#{id}" unless failed.all? { |code| d["effort"].key?(code) }
          failures << "template_nonexhaustive:#{id}" unless failed.all? { |code| d["recommendation_templates"].key?(code) }
          failures << "issue_type_nonexhaustive:#{id}" unless d["outcomes"].select { |o| o["execution_status"] == "failed" }
                                                                          .all? { |o| o["issue_type"].to_s != "" }
          failures << "fixtures_absent:#{id}" if Array(d["acceptance_fixtures"]).empty?
          # `not_applicable` belongs to exactly one Definition. An attempted not-applicable
          # from any other is `check_catalog_integrity_failure`, so a Catalog that DECLARED
          # one would be integrity-failed before it could ever produce the Result.
          na = d["outcomes"].any? { |o| o["execution_status"] == "not_applicable" }
          failures << "not_applicable_owner:#{id}" if na && id != "CHK-LP-001"
          failures << "not_applicable_missing:#{id}" if !na && id == "CHK-LP-001"
        end
        failures
      end

      def valid? = validation_failures.empty?

      def validate!
        failures = validation_failures
        return true if failures.empty?

        raise Platform::InvariantViolation, "check_catalog_integrity_failure: #{failures.join(', ')}"
      end

      # ---- seeding (owner connection only) ------------------------------------------------
      #
      # Idempotent by construction: identities are derived from content, so a re-run inserts
      # nothing. Returns the number of rows written.
      def seed!(connection)
        return 0 if connection.select_value("SELECT to_regclass('public.check_definitions')::text").nil?

        validate!
        written = 0
        now = "now()"
        DEFINITIONS.each do |d|
          body = semantic_body(d)
          written += connection.select_value(<<~SQL).to_i
            WITH ins AS (
              INSERT INTO public.check_definitions
                (id, created_at, definition_id, semantic_version, pillar_id, capability_id, owner,
                 released_at, score_capable, rule_or_model_version, impact_rule_version,
                 effort_policy_version, confidence_policy_version, executor_policy_version,
                 absence_proof_mode, contract, content_sha256)
              VALUES (#{q(connection, definition_row_id(d))}, #{now}, #{q(connection, d['check_definition_id'])},
                      #{q(connection, d['semantic_version'])}, #{q(connection, d['pillar_id'])},
                      #{q(connection, d['capability_id'])}, #{q(connection, OWNER)},
                      #{q(connection, RELEASED_AT)}::timestamptz, true,
                      #{q(connection, body['rule_or_model_version'])}, #{q(connection, d['impact_rule_version'])},
                      #{q(connection, EFFORT_POLICY)}, #{q(connection, CONFIDENCE_POLICY)},
                      #{q(connection, EXECUTOR_POLICY)}, #{q(connection, ABSENCE_PROOF_MODE)},
                      #{q(connection, JSON.generate(body))}::jsonb,
                      decode(#{q(connection, hex(definition_digest(d)))}, 'hex'))
              ON CONFLICT (id) DO NOTHING
              RETURNING 1
            )
            SELECT count(*) FROM ins
          SQL
        end

        written += connection.select_value(<<~SQL).to_i
          WITH ins AS (
            INSERT INTO public.check_catalogs
              (id, created_at, catalog_version, owner, released_at, state, executor_policy_version,
               external_measurement_policy_version, effort_policy_version, content_sha256,
               superseded_catalog_id, activated_at)
            VALUES (#{q(connection, catalog_row_id)}, #{now}, #{q(connection, CATALOG_VERSION)},
                    #{q(connection, OWNER)}, #{q(connection, RELEASED_AT)}::timestamptz, 'active',
                    #{q(connection, EXECUTOR_POLICY)}, #{q(connection, EXTERNAL_MEASUREMENT_POLICY)},
                    #{q(connection, EFFORT_POLICY)}, decode(#{q(connection, hex(catalog_digest))}, 'hex'),
                    NULL, #{q(connection, RELEASED_AT)}::timestamptz)
            ON CONFLICT (id) DO NOTHING
            RETURNING 1
          )
          SELECT count(*) FROM ins
        SQL

        DEFINITIONS.each_with_index do |d, index|
          written += connection.select_value(<<~SQL).to_i
            WITH ins AS (
              INSERT INTO public.check_catalog_entries
                (id, created_at, catalog_id, check_definition_row_id, check_definition_id,
                 definition_version, definition_sha256, ordering)
              VALUES (#{q(connection, catalog_entry_row_id(d))}, #{now}, #{q(connection, catalog_row_id)},
                      #{q(connection, definition_row_id(d))}, #{q(connection, d['check_definition_id'])},
                      #{q(connection, d['semantic_version'])},
                      decode(#{q(connection, hex(definition_digest(d)))}, 'hex'), #{index + 1})
              ON CONFLICT (id) DO NOTHING
              RETURNING 1
            )
            SELECT count(*) FROM ins
          SQL
        end
        written
      end

      def q(connection, value) = connection.quote(value.to_s)
    end
  end
end
