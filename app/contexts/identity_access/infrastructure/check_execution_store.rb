# frozen_string_literal: true

require "json"

module IdentityAccess
  module Infrastructure
    # Persistence for WF-007 — the applicability seal, Check Result identity and execution,
    # Issue derivation and the Issue-set seal — written in the worker's unit of work under
    # the Evaluation's Organization context.
    #
    # It EXTENDS `EvaluationInputStore` rather than copying it. That store already carries the
    # service-attributed ledger writers (command execution, audit, event, command result,
    # idempotency) and the Evaluation and Crawl reads WF-007's stages need, and its own
    # comment records that these writers are on their fourth structural copy and that the
    # extraction is deferred. Making a fifth copy to gain five new tables would be the wrong
    # trade; inheriting keeps one writer set and adds only what is genuinely new.
    #
    # Service-attributed throughout, exactly as the parent is: `service_identity_id` is set
    # and `actor_id` stays null. WF-007 Authorization names the evaluation service identity
    # for Check execution and Issue creation, and "no human principal executes a Check".
    class CheckExecutionStore < EvaluationInputStore
      # ---- reads the stages decide from ---------------------------------------------

      # The one active Catalog. A missing, altered, incomplete or unrecognized active Catalog
      # is `check_catalog_unavailable` and fails the Evaluation before any Check or Issue
      # write — so this returning nil is a decision, not an absence to work around.
      def active_catalog
        exec(<<~SQL, []).to_a.first
          SELECT id, catalog_version, state, executor_policy_version,
                 external_measurement_policy_version, effort_policy_version,
                 encode(content_sha256,'hex') AS content_sha256
          FROM check_catalogs WHERE state = 'active'
          ORDER BY activated_at DESC LIMIT 1
        SQL
      end

      # The Catalog's ordered membership with each Definition's persisted digest, so
      # activation validation can recompute against the ROWS rather than against the constant
      # it is trying to prove.
      def catalog_entries(catalog_id)
        exec(<<~SQL, [catalog_id]).to_a
          SELECT e.ordering, e.check_definition_id, e.definition_version,
                 encode(e.definition_sha256,'hex') AS definition_sha256,
                 d.pillar_id, encode(d.content_sha256,'hex') AS row_sha256
          FROM check_catalog_entries e
          JOIN check_definitions d ON d.id = e.check_definition_row_id
          WHERE e.catalog_id = $1::uuid ORDER BY e.ordering
        SQL
      end

      def read_input_snapshot(evaluation_id)
        exec(<<~SQL, [evaluation_id]).to_a.first
          SELECT id, evaluation_id, crawl_id, readiness_status, coverage_status, manifest,
                 encode(content_sha256,'hex') AS content_sha256, created_at
          FROM evaluation_input_snapshots WHERE evaluation_id = $1::uuid
        SQL
      end

      # The frozen Project profile decision. All four are NULL together when the Project has
      # committed no profile — which is NOT a false decision, and the applicability builder
      # treats it accordingly.
      def read_project_profile(project_id)
        exec(<<~SQL, [project_id]).to_a.first
          SELECT id, project_profile_schema_version, local_presence_applicable, local_presence_reason,
                 source_set_version
          FROM projects WHERE id = $1::uuid
        SQL
      end

      # Every derived Evidence record of this Evaluation, keyed by its producer attempt
      # identity. The attempt id is derived from `(evaluation, schema, subject key)`, so the
      # applicability builder resolves a selection by COMPUTING the key rather than searching
      # for it — which is what makes "selects no Evidence" determinate rather than a miss.
      def evidence_index(evaluation_id)
        exec(<<~SQL, [evaluation_id]).to_a.group_by { |row| row["attempt_id"] }
          SELECT e.id, e.attempt_id, e.schema_version, e.evidence_type, e.source_id,
                 e.content_sha256, e.validation_status, e.organization_id, e.payload_reference,
                 e.data_classification, e.observed_at_utc,
                 -- The freshness bound lives on the accepted SUBMISSION, not on the Evidence
                 -- envelope: `fresh_until_utc` is a property of the external observation and the
                 -- platform-derived payloads have none. A left join is therefore correct — a NULL
                 -- here means "this evidence has no observation window", which the selector reads
                 -- as `not_applicable` rather than as expired.
                 s.fresh_until AS fresh_until_utc
          FROM evidence e
          LEFT JOIN external_measurement_submissions s ON s.evidence_id = e.id
          WHERE e.evaluation_id = $1::uuid
        SQL
      end

      # The successfully parsed HTML/XHTML Documents of the Evaluation, which is CHK-CQ-001's
      # exact expected-entry cardinality.
      def parsed_documents(evaluation_id)
        exec(<<~SQL, [evaluation_id]).to_a
          SELECT a.document_id, a.source_id, a.canonical_url, a.input_media_type
          FROM parsed_artifacts a
          JOIN parsing_jobs j ON j.id = a.parsing_job_id
          WHERE j.evaluation_id = $1::uuid AND j.status = 'succeeded'
            AND split_part(a.input_media_type, ';', 1) IN ('text/html','application/xhtml+xml')
          ORDER BY a.canonical_url, a.document_id
        SQL
      end

      # ---- the applicability seal ------------------------------------------------------

      def insert_applicability_snapshot(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:project_id],
                  row[:evaluation_id], row[:evaluation_input_snapshot_id], row[:check_catalog_id],
                  row[:check_catalog_version], bytea(row[:check_catalog_sha256]), row[:project_profile_version],
                  row[:local_presence_applicable], row[:local_presence_reason], row[:source_set_version],
                  row[:active_source_ids], row[:crawl_coverage_status], row[:readiness_status],
                  row[:entry_count], bytea(row[:content_sha256]), row[:schema_version]]
        exec(<<~SQL, params)
          INSERT INTO check_applicability_snapshots
            (id, schema_version, created_at, correlation_id, organization_id, project_id, evaluation_id,
             evaluation_input_snapshot_id, check_catalog_id, check_catalog_version, check_catalog_sha256,
             project_profile_version, local_presence_applicable, local_presence_reason, source_set_version,
             active_source_ids, crawl_coverage_status, readiness_status, entry_count, content_sha256, sealed_at)
          VALUES ($1::uuid,$20,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,
                  $7::uuid,$8::uuid,$9,$10,
                  $11,$12,$13,$14,
                  $15::uuid[],$16,$17,$18,$19,$2::timestamptz)
        SQL
      end

      def insert_applicability_entry(row)
        params = [row[:id], iso(row[:now]), row[:organization_id], row[:project_id], row[:snapshot_id],
                  row[:catalog_entry_id], row[:check_definition_row_id], row[:check_definition_id],
                  row[:definition_version], row[:pillar_id], row[:subject_scope], row[:canonical_subject_type],
                  row[:canonical_subject_key], row[:source_id], row[:document_id], row[:applicable],
                  row[:inapplicable_reason], row[:absence_selector], row[:selected_evidence],
                  bytea(row[:expected_key_preimage]), bytea(row[:expected_key_sha256]), row[:ordering]]
        exec(<<~SQL, params)
          INSERT INTO check_applicability_entries
            (id, created_at, organization_id, project_id, snapshot_id, catalog_entry_id,
             check_definition_row_id, check_definition_id, definition_version, pillar_id, subject_scope,
             canonical_subject_type, canonical_subject_key, source_id, document_id, applicable,
             inapplicable_reason, absence_selector, selected_evidence, expected_key_preimage,
             expected_key_sha256, ordering)
          VALUES ($1::uuid,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,
                  $7::uuid,$8,$9,$10,$11,
                  $12,$13,$14::uuid,$15::uuid,$16,
                  $17,$18::jsonb,$19::jsonb,$20,
                  $21,$22)
        SQL
      end

      def applicability_snapshot_for(evaluation_id)
        exec(<<~SQL, [evaluation_id]).to_a.first
          SELECT id, evaluation_id, evaluation_input_snapshot_id, check_catalog_version,
                 encode(check_catalog_sha256,'hex') AS check_catalog_sha256, project_profile_version,
                 local_presence_applicable, local_presence_reason, entry_count,
                 encode(content_sha256,'hex') AS content_sha256
          FROM check_applicability_snapshots WHERE evaluation_id = $1::uuid
        SQL
      end

      def applicability_entries(snapshot_id)
        exec(<<~SQL, [snapshot_id]).to_a
          SELECT * FROM check_applicability_entries WHERE snapshot_id = $1::uuid ORDER BY ordering
        SQL
      end

      # ---- result identity ---------------------------------------------------------------

      # The materialization transaction: one retained preimage, one key, one slot with its
      # write-once preallocated Check Result identity — allocated BEFORE execution, so a
      # crashed attempt leaves a materialized key rather than a phantom Result.
      def insert_result_key(row)
        params = [row[:id], iso(row[:now]), row[:organization_id], row[:project_id], row[:evaluation_id],
                  row[:applicability_entry_id], bytea(row[:key_preimage]),
                  bytea(row[:check_result_key_sha256]), row[:collision_ordinal], row[:ordering]]
        exec(<<~SQL, params)
          INSERT INTO check_result_keys
            (id, created_at, organization_id, project_id, evaluation_id, applicability_entry_id,
             key_preimage, check_result_key_sha256, collision_ordinal, ordering)
          VALUES ($1::uuid,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7,$8,$9,$10)
          ON CONFLICT (evaluation_id, key_preimage) DO NOTHING
          RETURNING id
        SQL
      end

      # A record whose HASH matches but whose retained preimage does not. This is the lookup
      # that makes the OD-010 collision branch reachable: a unique index on the hash would
      # have refused the insert and hidden the collision instead of surfacing it.
      def colliding_result_key(evaluation_id, sha256, preimage)
        exec(<<~SQL, [evaluation_id, bytea(sha256), bytea(preimage)]).to_a.first
          SELECT id, encode(key_preimage,'hex') AS key_preimage
          FROM check_result_keys
          WHERE evaluation_id = $1::uuid AND check_result_key_sha256 = $2 AND key_preimage <> $3
          LIMIT 1
        SQL
      end

      def insert_result_slot(row)
        params = [row[:id], iso(row[:now]), row[:organization_id], row[:project_id], row[:evaluation_id],
                  row[:applicability_entry_id], row[:check_result_key_id], row[:check_result_id],
                  row[:ordering]]
        exec(<<~SQL, params)
          INSERT INTO check_result_slots
            (id, state_version, created_at, updated_at, organization_id, project_id, evaluation_id,
             applicability_entry_id, check_result_key_id, check_result_id, ordering, state, attempt_count)
          VALUES ($1::uuid,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,
                  $6::uuid,$7::uuid,$8::uuid,$9,'pending',0)
          ON CONFLICT (applicability_entry_id) DO NOTHING
          RETURNING id
        SQL
      end

      def read_slot(id)
        exec("SELECT * FROM check_result_slots WHERE id = $1::uuid", [id]).to_a.first
      end

      def slots_for_evaluation(evaluation_id)
        exec(<<~SQL, [evaluation_id]).to_a
          SELECT * FROM check_result_slots WHERE evaluation_id = $1::uuid ORDER BY ordering
        SQL
      end

      def read_entry(id)
        exec("SELECT * FROM check_applicability_entries WHERE id = $1::uuid", [id]).to_a.first
      end

      # The Evidence a Check may read, with the producer attempt identity its payload was
      # sealed under. `organization_id` is returned so the caller can prove same-tenancy at
      # the moment of the read, not merely at the moment the reference was written.
      def read_evidence_payload(id)
        exec(<<~SQL, [id]).to_a.first
          SELECT id, attempt_id, payload_reference, organization_id, validation_status,
                 content_sha256, evidence_type, schema_version
          FROM evidence WHERE id = $1::uuid
        SQL
      end

      def start_slot(id, expected_version, now)
        exec(<<~SQL, [id, expected_version, iso(now)]).cmd_tuples
          UPDATE check_result_slots
          SET state = 'running', attempt_count = attempt_count + 1,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state IN ('pending','running') AND state_version = $2
        SQL
      end

      def terminalize_slot(id, expected_version, now, result_id)
        exec(<<~SQL, [id, expected_version, iso(now), result_id]).cmd_tuples
          UPDATE check_result_slots
          SET state = 'terminal', terminal_result_id = $4::uuid,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state = 'running' AND state_version = $2
        SQL
      end

      def insert_attempt(row)
        params = [row[:id], iso(row[:now]), row[:organization_id], row[:project_id], row[:evaluation_id],
                  row[:slot_id], row[:attempt_number], row[:retry_of_attempt_number],
                  row[:check_catalog_version], row[:check_definition_id], row[:definition_version],
                  bytea(row[:applicability_sha256]), bytea(row[:result_key_sha256]),
                  bytea(row[:deterministic_input_sha256]), iso(row[:scheduled_at]), iso(row[:started_at]),
                  iso(row[:completed_at]), iso(row[:deadline_at]), row[:produced_check_result_id],
                  bytea(row[:output_sha256]), row[:execution_status], row[:elapsed_ms], row[:reason_code]]
        exec(<<~SQL, params)
          INSERT INTO check_attempts
            (id, created_at, organization_id, project_id, evaluation_id, slot_id, attempt_number,
             retry_of_attempt_number, check_catalog_version, check_definition_id, definition_version,
             applicability_sha256, result_key_sha256, deterministic_input_sha256, scheduled_at,
             started_at, completed_at, deadline_at, produced_check_result_id, output_sha256,
             execution_status, elapsed_ms, reason_code)
          VALUES ($1::uuid,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7,
                  $8,$9,$10,$11,
                  $12,$13,$14,$15::timestamptz,
                  $16::timestamptz,$17::timestamptz,$18::timestamptz,$19::uuid,$20,
                  $21,$22,$23)
        SQL
      end

      # ---- results ---------------------------------------------------------------------

      def insert_check_result(row)
        params = [row[:id], row[:schema_version], iso(row[:now]), row[:correlation_id], row[:organization_id],
                  row[:project_id], row[:evaluation_id], row[:evaluation_input_snapshot_id],
                  row[:applicability_snapshot_id], row[:applicability_entry_id], row[:slot_id],
                  row[:check_result_key_id], bytea(row[:check_result_key_sha256]),
                  bytea(row[:check_result_key_preimage]), row[:check_catalog_version],
                  row[:check_definition_row_id], row[:check_definition_id], row[:check_definition_version],
                  row[:pillar_id], row[:subject_scope], row[:canonical_subject_type],
                  row[:canonical_subject_key], row[:source_id], row[:document_id],
                  row[:absence_coverage_selector], row[:subject_set_complete], bytea(row[:evidence_set_sha256]),
                  row[:execution_status], row[:outcome_code], row[:error_reason_code],
                  row[:normalized_observation], row[:impact_band], row[:impact_rule_version],
                  row[:confidence_value], row[:confidence_status], row[:confidence_band],
                  row[:confidence_policy_version], row[:effort_band], row[:effort_basis],
                  row[:recommendation_template_id], row[:rule_or_model_version],
                  row[:execution_attempt_count], bytea(row[:deterministic_input_sha256]),
                  bytea(row[:deterministic_output_sha256])]
        exec(<<~SQL, params)
          INSERT INTO check_results
            (id, schema_version, created_at, correlation_id, organization_id, project_id, evaluation_id,
             evaluation_input_snapshot_id, applicability_snapshot_id, applicability_entry_id, slot_id,
             check_result_key_id, check_result_key_sha256, check_result_key_preimage, check_catalog_version,
             check_definition_row_id, check_definition_id, check_definition_version, pillar_id,
             subject_scope, canonical_subject_type, canonical_subject_key, source_id, document_id,
             absence_coverage_selector, subject_set_complete, evidence_set_sha256, execution_status,
             outcome_code, error_reason_code, normalized_observation, impact_band, impact_rule_version,
             confidence_value, confidence_status, confidence_band, confidence_policy_version,
             effort_band, effort_basis, recommendation_template_id, rule_or_model_version,
             execution_attempt_count, deterministic_input_sha256, deterministic_output_sha256, produced_at)
          VALUES ($1::uuid,$2,$3::timestamptz,$4::uuid,$5::uuid,$6::uuid,$7::uuid,
                  $8::uuid,$9::uuid,$10::uuid,$11::uuid,
                  $12::uuid,$13,$14,$15,
                  $16::uuid,$17,$18,$19,
                  $20,$21,$22,$23::uuid,$24::uuid,
                  $25::jsonb,$26,$27,$28,
                  $29,$30,$31::jsonb,$32,$33,
                  $34::numeric,$35,$36,$37,
                  $38,$39,$40,$41,
                  $42,$43,$44,$3::timestamptz)
        SQL
      end

      def insert_check_result_evidence(row)
        params = [row[:id], iso(row[:now]), row[:organization_id], row[:project_id], row[:check_result_id],
                  row[:evidence_id], hexbytea(row[:evidence_sha256]), row[:validation_decision_id],
                  row[:validation_status], row[:ordering]]
        exec(<<~SQL, params)
          INSERT INTO check_result_evidences
            (id, created_at, organization_id, project_id, check_result_id, evidence_id, evidence_sha256,
             validation_decision_id, validation_status, ordering)
          VALUES ($1::uuid,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7,$8::uuid,$9,$10)
        SQL
      end

      def check_results_for_evaluation(evaluation_id)
        exec(<<~SQL, [evaluation_id]).to_a
          SELECT * FROM check_results WHERE evaluation_id = $1::uuid
          ORDER BY check_definition_id, canonical_subject_key
        SQL
      end

      def check_result_evidences(check_result_id)
        exec(<<~SQL, [check_result_id]).to_a
          SELECT e.*, ev.organization_id
          FROM check_result_evidences e
          JOIN evidence ev ON ev.id = e.evidence_id
          WHERE e.check_result_id = $1::uuid ORDER BY e.ordering
        SQL
      end

      # ---- issues -------------------------------------------------------------------------

      def allocate_dedup_key(row)
        params = [row[:id], iso(row[:now]), row[:organization_id], row[:project_id], row[:namespace],
                  bytea(row[:digest]), bytea(row[:preimage])]
        exec(<<~SQL, params).to_a.first
          WITH ins AS (
            INSERT INTO deduplication_keys
              (id, created_at, organization_id, project_id, namespace, digest, preimage,
               collision_ordinal, allocated_at)
            VALUES ($1::uuid,$2::timestamptz,$3::uuid,$4::uuid,$5,$6,$7,
                    (SELECT coalesce(max(collision_ordinal) + 1, 0) FROM deduplication_keys
                     WHERE organization_id = $3::uuid AND namespace = $5 AND digest = $6),
                    $2::timestamptz)
            ON CONFLICT (organization_id, namespace, preimage) DO NOTHING
            RETURNING id, collision_ordinal
          )
          SELECT id, collision_ordinal FROM ins
          UNION ALL
          SELECT id, collision_ordinal FROM deduplication_keys
          WHERE organization_id = $3::uuid AND namespace = $5 AND preimage = $7
          LIMIT 1
        SQL
      end

      # A dedup key with the same DIGEST but a different retained preimage. Under the ratified
      # OD-017 this is the fail-closed branch: no second Issue is created and the Evaluation
      # fails, so the lookup exists to REFUSE a write rather than to reconcile one.
      def colliding_dedup_key(organization_id, namespace, digest, preimage)
        exec(<<~SQL, [organization_id, namespace, bytea(digest), bytea(preimage)]).to_a.first
          SELECT k.id, i.id AS issue_id
          FROM deduplication_keys k
          LEFT JOIN issues i ON i.dedup_key_id = k.id
          WHERE k.organization_id = $1::uuid AND k.namespace = $2 AND k.digest = $3 AND k.preimage <> $4
          LIMIT 1
        SQL
      end

      def insert_issue(row)
        params = [row[:id], row[:schema_version], iso(row[:now]), row[:correlation_id], row[:organization_id],
                  row[:project_id], row[:evaluation_id], row[:check_result_id], row[:source_id],
                  row[:dedup_key_id], row[:issue_type], row[:fingerprint_version],
                  bytea(row[:fingerprint_preimage]), bytea(row[:fingerprint_sha256]),
                  row[:canonical_subject_type], row[:canonical_subject_key], row[:check_definition_id],
                  row[:pillar_id], row[:impact_band], row[:confidence_value], row[:confidence_band],
                  row[:confidence_status], row[:effort_band], row[:effort_basis],
                  row[:recommendation_template_id], row[:state], row[:adjudication_status],
                  row[:publication_status], row[:published_at]]
        exec(<<~SQL, params)
          INSERT INTO issues
            (id, schema_version, state_version, created_at, updated_at, correlation_id, organization_id,
             project_id, evaluation_id, check_result_id, source_id, dedup_key_id, issue_type,
             fingerprint_version, fingerprint_preimage, fingerprint_sha256, canonical_subject_type,
             canonical_subject_key, check_definition_id, pillar_id, impact_band, confidence_value,
             confidence_band, confidence_status, effort_band, effort_basis, recommendation_template_id,
             state, adjudication_status, publication_status, published_at)
          VALUES ($1::uuid,$2,0,$3::timestamptz,$3::timestamptz,$4::uuid,$5::uuid,
                  $6::uuid,$7::uuid,$8::uuid,$9::uuid,$10::uuid,$11,
                  $12,$13,$14,$15,
                  $16,$17,$18,$19,$20::numeric,
                  $21,$22,$23,$24,$25,
                  $26,$27,$28,$29::timestamptz)
          ON CONFLICT (evaluation_id, fingerprint_version, fingerprint_preimage) DO NOTHING
          RETURNING id
        SQL
      end

      def insert_issue_evidence(row)
        params = [row[:id], iso(row[:now]), row[:organization_id], row[:project_id], row[:issue_id],
                  row[:evidence_id], hexbytea(row[:evidence_sha256]), row[:role], row[:ordering]]
        exec(<<~SQL, params)
          INSERT INTO issue_evidences
            (id, created_at, organization_id, project_id, issue_id, evidence_id, evidence_sha256, role, ordering)
          VALUES ($1::uuid,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7,$8,$9)
        SQL
      end

      def upsert_lineage_head(row)
        params = [row[:id], iso(row[:now]), row[:organization_id], row[:project_id], row[:dedup_key_id],
                  row[:current_issue_id]]
        exec(<<~SQL, params)
          INSERT INTO issue_lineage_heads
            (id, state_version, created_at, updated_at, organization_id, project_id, dedup_key_id, current_issue_id)
          VALUES ($1::uuid,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid)
          ON CONFLICT (dedup_key_id) DO UPDATE
            SET current_issue_id = EXCLUDED.current_issue_id,
                state_version = issue_lineage_heads.state_version + 1,
                updated_at = EXCLUDED.updated_at
        SQL
      end

      def issues_for_evaluation(evaluation_id)
        exec(<<~SQL, [evaluation_id]).to_a
          SELECT * FROM issues WHERE evaluation_id = $1::uuid
        SQL
      end

      # Every Issue in the Project lineage graph, so the sealed set can include a non-current
      # ancestor as well as the current leaves.
      def project_issues(project_id)
        exec(<<~SQL, [project_id]).to_a
          SELECT i.*, (h.current_issue_id = i.id) AS current_leaf
          FROM issues i
          LEFT JOIN issue_lineage_heads h ON h.dedup_key_id = i.dedup_key_id
          WHERE i.project_id = $1::uuid
        SQL
      end

      def insert_issue_set(row)
        params = [row[:id], row[:schema_version], iso(row[:now]), row[:correlation_id], row[:organization_id],
                  row[:project_id], row[:evaluation_id], row[:member_count], row[:current_leaf_count],
                  bytea(row[:membership_root_sha256]), bytea(row[:content_sha256])]
        exec(<<~SQL, params)
          INSERT INTO issue_sets
            (id, schema_version, created_at, correlation_id, organization_id, project_id, evaluation_id,
             member_count, current_leaf_count, membership_root_sha256, content_sha256, sealed_at)
          VALUES ($1::uuid,$2,$3::timestamptz,$4::uuid,$5::uuid,$6::uuid,$7::uuid,
                  $8,$9,$10,$11,$3::timestamptz)
        SQL
      end

      def insert_issue_set_membership(row)
        params = [row[:id], iso(row[:now]), row[:organization_id], row[:project_id], row[:issue_set_id],
                  row[:issue_id], row[:current_leaf], row[:frozen_state], row[:frozen_state_version],
                  row[:ordering]]
        exec(<<~SQL, params)
          INSERT INTO issue_set_memberships
            (id, created_at, organization_id, project_id, issue_set_id, issue_id, current_leaf,
             frozen_state, frozen_state_version, ordering)
          VALUES ($1::uuid,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7,$8,$9,$10)
        SQL
      end

      def issue_set_for(evaluation_id)
        exec("SELECT * FROM issue_sets WHERE evaluation_id = $1::uuid", [evaluation_id]).to_a.first
      end

      def insert_collision_decision(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:project_id],
                  row[:evaluation_id], row[:fingerprint_kind], bytea(row[:fingerprint_sha256]),
                  row[:existing_record_type], row[:existing_record_id], row[:conflicting_record_type],
                  row[:conflicting_record_id], row[:detecting_service_identity_id],
                  JSON.generate(row[:definition_versions]), bytea(row[:input_sha256]),
                  bytea(row[:output_sha256]), bytea(row[:collision_identity_sha256])]
        exec(<<~SQL, params)
          INSERT INTO fingerprint_collision_decisions
            (id, created_at, correlation_id, organization_id, project_id, evaluation_id, fingerprint_kind,
             fingerprint_sha256, existing_record_type, existing_record_id, conflicting_record_type,
             conflicting_record_id, detecting_service_identity_id, definition_versions, input_sha256,
             output_sha256, decision_type, decision_value, decision_status, decision_reason_code,
             collision_detected_at, collision_identity_sha256)
          VALUES ($1::uuid,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7,
                  $8,$9,$10::uuid,$11,
                  $12::uuid,$13::uuid,$14::jsonb,$15,
                  $16,'fingerprint_collision','collision_detected','final',NULL,
                  $2::timestamptz,$17)
        SQL
      end

      # ---- Evaluation lifecycle ------------------------------------------------------------

      # WF-007's SINGLE start transition, guarded on `pending`, so a second delivery cannot
      # emit a second `EvaluationStarted`.
      def start_evaluation(id, expected_version, now, applicability_snapshot_id, input_snapshot_id)
        exec(<<~SQL, [id, expected_version, iso(now), applicability_snapshot_id, input_snapshot_id]).cmd_tuples
          UPDATE evaluations
          SET state = 'running', started_at = $3::timestamptz, state_version = state_version + 1,
              updated_at = $3::timestamptz, applicability_snapshot_id = $4::uuid, input_snapshot_id = $5::uuid
          WHERE id = $1::uuid AND state = 'pending' AND state_version = $2
        SQL
      end

      def complete_evaluation(id, expected_version, now)
        exec(<<~SQL, [id, expected_version, iso(now)]).cmd_tuples
          UPDATE evaluations
          SET state = 'completed', completed_at = $3::timestamptz, state_version = state_version + 1,
              updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state = 'running' AND state_version = $2
        SQL
      end

      def fail_evaluation(id, expected_version, now, reason)
        exec(<<~SQL, [id, expected_version, iso(now), reason]).cmd_tuples
          UPDATE evaluations
          SET state = 'failed', failed_at = $3::timestamptz, reason = $4,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state IN ('pending','running') AND state_version = $2
        SQL
      end
    end
  end
end
