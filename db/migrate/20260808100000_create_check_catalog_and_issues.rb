# frozen_string_literal: true

# S-09 and S-12's product tables: the ratified `check-catalog-v1` Definitions, the frozen
# applicability seal, Check Result identity and Results, and the Issues and Issue Set WF-007
# derives from them (schemas/POSTGRESQL_SCHEMA.md § Evidence, Checks, Issues, and scores;
# SCORE_EVIDENCE_MODEL.md Check Result Contract, Check Definition And Check Catalog Contract,
# Frozen Check Applicability Snapshot, Issue Contract; OD-010 and OD-017, both RATIFIED).
#
# THE CATALOGUE IS GLOBAL AND OWNER-OWNED, NOT TENANT DATA. `check_definitions`,
# `check_catalogs` and `check_catalog_entries` carry no `organization_id`, no row level
# security and NO runtime INSERT or UPDATE grant. That is the schema expression of
# "Tenant actors cannot create, edit, disable, remap, or reorder a Definition": the runtime
# can read the catalogue and nothing else, so no tenant code path — permitted or not — can
# reach a write. The seven ratified rows are seeded by `Workflows::Wf007::CheckCatalog`
# through the owner connection, and their digests are recomputed and proved on every
# activation validation rather than trusted from the row.
#
# THE PREIMAGE IS THE AUTHORITY AND THE HASH IS AN INDEX. Both uniqueness rules that matter
# here are built on retained canonical bytes, never on a SHA-256 alone:
#
#   * `check_result_keys` is unique on `(evaluation_id, key_preimage)` — PRULE-010's
#     "the COMPLETE retained preimage, not the hash, is uniqueness authority within the
#     Evaluation, so the unique index MUST NOT be built on the hash alone".
#   * `issues` is unique on `(evaluation_id, fingerprint_version, fingerprint_preimage)` —
#     PRULE-023's "a unique constraint on `fingerprint_sha256` alone MUST NOT exist: it
#     would merge exactly the records the model requires to stay distinct".
#
# Each hash also carries a NON-unique index, because it is the lookup path for collision
# detection: a matching hash with a different preimage must be findable in order to be
# refused, which a unique index would instead silently prevent from ever being inserted and
# therefore from ever being detected.
#
# NO `evaluation_stage_checkpoints`. The ratified stage registry names one, and this build
# does not add it: WF-006's `seal_input_snapshot` stage already runs on the established
# pattern — the stage is idempotent on its ScheduledAction identity and the succeeding
# transaction creates the unique next-stage action — and WF-007's stages join that same
# chain. Adding a second stage-authority representation for only half the stages would give
# the pipeline two answers to "what ran". The table remains available for the slice that
# converts the whole chain at once.
class CreateCheckCatalogAndIssues < ActiveRecord::Migration[8.1]
  # The exact seven Pillar literals (SCORE_EVIDENCE_MODEL.md Pillar Contract). A CHECK over
  # the closed set is what stops an eighth pillar arriving as data.
  PILLARS = %w[technical_integrity content_quality trust_signals search_presence
               ai_presence authority_signals local_presence].freeze

  EXECUTION_STATUSES = %w[passed failed not_applicable error].freeze
  IMPACT_BANDS = %w[informational low medium high critical].freeze
  CONFIDENCE_STATUSES = %w[valid missing invalid].freeze
  CONFIDENCE_BANDS = %w[low medium high].freeze
  EFFORT_BANDS = %w[low medium high].freeze
  SUBJECT_SCOPES = %w[project source document].freeze
  SUBJECT_TYPES = %w[project source url].freeze

  # The handled Check error reasons, in the ratified first-match semantic order, plus the two
  # retryable ones (`check-executor-interim-v1`). A handled error is TERMINAL and does not
  # fail the Evaluation; the boundary failures that do are Evaluation `reason` values and are
  # deliberately absent from this set.
  ERROR_REASONS = %w[
    input_evidence_missing input_evidence_stale input_evidence_indeterminate
    input_evidence_invalid normalized_input_invalid output_schema_invalid
    check_dependency_unavailable check_internal_timeout
  ].freeze

  ISSUE_STATES = %w[candidate open resolved dismissed superseded].freeze
  ADJUDICATION_STATUSES = %w[not_required review_required disputed in_review upheld
                             rejected withdrawn dismissed].freeze
  PUBLICATION_STATUSES = %w[published withheld suppressed].freeze
  FINGERPRINT_KINDS = %w[check_result issue ai_response citation].freeze

  def up
    create_global_catalogue
    create_applicability
    create_result_identity
    create_results
    create_issues
    create_guards
    F1::RuntimeGrants.apply_all(connection)
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS issue_sets_guard ON issue_sets;
      DROP TRIGGER IF EXISTS issues_guard ON issues;
      DROP TRIGGER IF EXISTS check_results_guard ON check_results;
      DROP TRIGGER IF EXISTS check_result_keys_guard ON check_result_keys;
      DROP TRIGGER IF EXISTS check_result_slots_guard ON check_result_slots;
      DROP TRIGGER IF EXISTS check_applicability_snapshots_guard ON check_applicability_snapshots;
      DROP TRIGGER IF EXISTS check_applicability_entries_guard ON check_applicability_entries;
      DROP FUNCTION IF EXISTS f1_issue_sets_guard();
      DROP FUNCTION IF EXISTS f1_issues_guard();
      DROP FUNCTION IF EXISTS f1_check_immutable_guard();
      DROP FUNCTION IF EXISTS f1_check_result_slots_guard();
      DROP TABLE IF EXISTS issue_set_memberships;
      DROP TABLE IF EXISTS issue_sets;
      DROP TABLE IF EXISTS issue_lineage_heads;
      DROP TABLE IF EXISTS issue_evidences;
      DROP TABLE IF EXISTS issues;
      DROP TABLE IF EXISTS deduplication_keys;
      DROP TABLE IF EXISTS fingerprint_collision_decisions;
      DROP TABLE IF EXISTS check_result_evidences;
      DROP TABLE IF EXISTS check_results;
      DROP TABLE IF EXISTS check_attempts;
      DROP TABLE IF EXISTS check_result_slots;
      DROP TABLE IF EXISTS check_result_keys;
      DROP TABLE IF EXISTS check_applicability_entries;
      DROP TABLE IF EXISTS check_applicability_snapshots;
      DROP TABLE IF EXISTS check_catalog_entries;
      DROP TABLE IF EXISTS check_catalogs;
      DROP TABLE IF EXISTS check_definitions;
    SQL
  end

  private

  def quoted(values) = values.map { |v| "'#{v}'" }.join(", ")

  # ------------------------------------------------------------------ the global catalogue
  def create_global_catalogue
    execute <<~SQL
      -- G-IMM. One immutable versioned logical artifact per (definition_id, semantic_version).
      -- The `contract` payload is the Definition's complete semantic body — outcomes, impact
      -- rule, effort rule, subject and cardinality, selector, template mapping — and
      -- `content_sha256` is the SHA-256 over its canonical JSON. Reuse of a version for
      -- changed content is prohibited, which the unique version key plus the recomputed digest
      -- make checkable rather than promised.
      CREATE TABLE check_definitions (
        id                        uuid PRIMARY KEY,
        created_at                timestamptz(6) NOT NULL,
        definition_id             text NOT NULL CHECK (definition_id ~ '^CHK-[A-Z]+-[0-9]{3}$'),
        semantic_version          text NOT NULL CHECK (semantic_version ~ '^[0-9]+\\.[0-9]+\\.[0-9]+$'),
        pillar_id                 text NOT NULL CHECK (pillar_id IN (#{quoted(PILLARS)})),
        capability_id             text NOT NULL,
        owner                     text NOT NULL,
        released_at               timestamptz(6) NOT NULL,
        score_capable             boolean NOT NULL DEFAULT true CHECK (score_capable),
        rule_or_model_version     text NOT NULL,
        impact_rule_version       text NOT NULL,
        effort_policy_version     text NOT NULL,
        confidence_policy_version text NOT NULL,
        executor_policy_version   text NOT NULL,
        absence_proof_mode        text NOT NULL CHECK (absence_proof_mode = 'check_pass_resolves_all'),
        contract                  jsonb NOT NULL,
        content_sha256            bytea NOT NULL CHECK (octet_length(content_sha256) = 32),

        CONSTRAINT check_definitions_version_unique UNIQUE (definition_id, semantic_version)
      );

      -- G-MUT. `check-catalog-v1` is the one ratified Catalog; `state` exists because the
      -- contract has one, not because a second state is reachable in this build.
      CREATE TABLE check_catalogs (
        id                                uuid PRIMARY KEY,
        created_at                        timestamptz(6) NOT NULL,
        catalog_version                   text NOT NULL,
        owner                             text NOT NULL,
        released_at                       timestamptz(6) NOT NULL,
        state                             text NOT NULL CHECK (state IN ('active','superseded')),
        executor_policy_version           text NOT NULL,
        external_measurement_policy_version text NOT NULL,
        effort_policy_version             text NOT NULL,
        content_sha256                    bytea NOT NULL CHECK (octet_length(content_sha256) = 32),
        superseded_catalog_id             uuid REFERENCES check_catalogs (id),
        activated_at                      timestamptz(6) NOT NULL,

        CONSTRAINT check_catalogs_version_unique UNIQUE (catalog_version),
        CONSTRAINT check_catalogs_hash_unique UNIQUE (content_sha256)
      );

      -- G-IMM. Ordered membership. The row FK and the denormalized semantic tuple must agree
      -- with exactly one `check_definitions` row — carried here so an applicability entry can
      -- copy the tuple without a join, and constrained by the composite FK so the copy cannot
      -- drift from the row it names.
      CREATE TABLE check_catalog_entries (
        id                        uuid PRIMARY KEY,
        created_at                timestamptz(6) NOT NULL,
        catalog_id                uuid NOT NULL REFERENCES check_catalogs (id),
        check_definition_row_id   uuid NOT NULL REFERENCES check_definitions (id),
        check_definition_id       text NOT NULL,
        definition_version        text NOT NULL,
        definition_sha256         bytea NOT NULL CHECK (octet_length(definition_sha256) = 32),
        ordering                  integer NOT NULL CHECK (ordering >= 1),

        CONSTRAINT check_catalog_entries_order_unique UNIQUE (catalog_id, ordering),
        CONSTRAINT check_catalog_entries_definition_unique
          UNIQUE (catalog_id, check_definition_id, definition_version)
      );

      -- The semantic tuple on the entry IS the row it names, not a second opinion about it.
      CREATE UNIQUE INDEX check_definitions_semantic_identity
        ON check_definitions (id, definition_id, semantic_version, content_sha256);
      ALTER TABLE check_catalog_entries ADD CONSTRAINT check_catalog_entries_definition_fk
        FOREIGN KEY (check_definition_row_id, check_definition_id, definition_version, definition_sha256)
        REFERENCES check_definitions (id, definition_id, semantic_version, content_sha256);
    SQL
  end

  # ------------------------------------------------------------------------- applicability
  def create_applicability
    execute <<~SQL
      -- T-IMM. One frozen Snapshot per Evaluation, sealed BEFORE any execution, after which
      -- no expected entry may be added, removed or reordered.
      CREATE TABLE check_applicability_snapshots (
        id                          uuid PRIMARY KEY,
        schema_version              text NOT NULL,
        created_at                  timestamptz(6) NOT NULL,
        correlation_id              uuid NOT NULL,

        organization_id             uuid NOT NULL,
        project_id                  uuid NOT NULL,
        evaluation_id               uuid NOT NULL,
        evaluation_input_snapshot_id uuid NOT NULL,

        check_catalog_id            uuid NOT NULL REFERENCES check_catalogs (id),
        check_catalog_version       text NOT NULL,
        check_catalog_sha256        bytea NOT NULL CHECK (octet_length(check_catalog_sha256) = 32),

        -- The frozen Project profile decision. All three are NULL together when the Project
        -- has committed no profile, which is NOT the same as a valid `false`: only a valid
        -- false with its nonblank reason makes CHK-LP-001 inapplicable.
        project_profile_version     text,
        local_presence_applicable   boolean,
        local_presence_reason       text,

        source_set_version          bigint NOT NULL,
        active_source_ids           uuid[] NOT NULL,
        crawl_coverage_status       text NOT NULL,
        readiness_status            text NOT NULL,
        entry_count                 integer NOT NULL CHECK (entry_count >= 0),
        content_sha256              bytea NOT NULL CHECK (octet_length(content_sha256) = 32),
        sealed_at                   timestamptz(6) NOT NULL,

        -- A false decision without its reason is not a valid decision; recording one would
        -- make CHK-LP-001 inapplicable on the strength of an incomplete profile.
        CONSTRAINT check_applicability_snapshots_false_has_reason CHECK (
          (local_presence_applicable IS DISTINCT FROM false)
            OR (local_presence_reason IS NOT NULL AND length(btrim(local_presence_reason)) > 0)
        ),
        CONSTRAINT check_applicability_snapshots_evaluation_fk
          FOREIGN KEY (organization_id, project_id, evaluation_id)
          REFERENCES evaluations (organization_id, project_id, id),
        CONSTRAINT check_applicability_snapshots_org_id_unique UNIQUE (organization_id, id)
      );

      CREATE UNIQUE INDEX check_applicability_snapshots_evaluation_unique
        ON check_applicability_snapshots (evaluation_id);

      -- T-IMM. Every expected entry, exhaustive and ordered. `applicable=false` carries its
      -- exact reason; the expected result-key preimage is frozen here so materialization has
      -- nothing left to decide.
      CREATE TABLE check_applicability_entries (
        id                        uuid PRIMARY KEY,
        created_at                timestamptz(6) NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        snapshot_id               uuid NOT NULL,
        catalog_entry_id          uuid NOT NULL REFERENCES check_catalog_entries (id),
        check_definition_row_id   uuid NOT NULL REFERENCES check_definitions (id),
        check_definition_id       text NOT NULL,
        definition_version        text NOT NULL,
        pillar_id                 text NOT NULL CHECK (pillar_id IN (#{quoted(PILLARS)})),

        subject_scope             text NOT NULL CHECK (subject_scope IN (#{quoted(SUBJECT_SCOPES)})),
        canonical_subject_type    text NOT NULL CHECK (canonical_subject_type IN (#{quoted(SUBJECT_TYPES)})),
        canonical_subject_key     text NOT NULL CHECK (length(canonical_subject_key) BETWEEN 1 AND 8192),
        source_id                 uuid,
        document_id               uuid,

        applicable                boolean NOT NULL,
        inapplicable_reason       text,
        absence_selector          jsonb NOT NULL,
        selected_evidence         jsonb NOT NULL,
        expected_key_preimage     bytea NOT NULL,
        expected_key_sha256       bytea NOT NULL CHECK (octet_length(expected_key_sha256) = 32),
        ordering                  integer NOT NULL CHECK (ordering >= 1),

        -- Contract cardinality made structural: a `project` subject has no Source and no
        -- Document; a `source` subject has a Source and no Document; a `document` subject has
        -- both. An entry that violates this would place a Project Result under a Source key.
        CONSTRAINT check_applicability_entries_subject_shape CHECK (
          (subject_scope = 'project'  AND source_id IS NULL     AND document_id IS NULL)
          OR (subject_scope = 'source'   AND source_id IS NOT NULL AND document_id IS NULL)
          OR (subject_scope = 'document' AND source_id IS NOT NULL AND document_id IS NOT NULL)
        ),
        CONSTRAINT check_applicability_entries_inapplicable_has_reason CHECK (
          applicable OR (inapplicable_reason IS NOT NULL AND length(btrim(inapplicable_reason)) > 0)
        ),
        CONSTRAINT check_applicability_entries_snapshot_fk
          FOREIGN KEY (organization_id, snapshot_id)
          REFERENCES check_applicability_snapshots (organization_id, id),
        CONSTRAINT check_applicability_entries_order_unique UNIQUE (snapshot_id, ordering),
        CONSTRAINT check_applicability_entries_org_id_unique UNIQUE (organization_id, id)
      );

      -- One expected entry per (Definition, subject) within a Snapshot. A duplicate expected
      -- entry is `check_applicability_snapshot_invalid`, and this is where it becomes
      -- unrepresentable rather than merely detected.
      CREATE UNIQUE INDEX check_applicability_entries_subject_unique
        ON check_applicability_entries (snapshot_id, check_definition_id, definition_version,
                                        canonical_subject_type, canonical_subject_key);
    SQL

    tenant_rls("check_applicability_snapshots")
    tenant_rls("check_applicability_entries")
  end

  # --------------------------------------------------------------------- result identity
  def create_result_identity
    execute <<~SQL
      -- T-IMM. The retained canonical preimage IS the authority; the SHA-256 beside it is an
      -- index. The unique index is on `(evaluation_id, key_preimage)`, so two different
      -- preimages that hash alike CAN both be inserted — which is the only way the collision
      -- can be detected and the Evaluation failed, instead of one record silently displacing
      -- the other.
      CREATE TABLE check_result_keys (
        id                        uuid PRIMARY KEY,
        created_at                timestamptz(6) NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        evaluation_id             uuid NOT NULL,
        applicability_entry_id    uuid NOT NULL,
        key_preimage              bytea NOT NULL,
        check_result_key_sha256   bytea NOT NULL CHECK (octet_length(check_result_key_sha256) = 32),
        collision_ordinal         integer NOT NULL DEFAULT 0 CHECK (collision_ordinal >= 0),
        ordering                  integer NOT NULL CHECK (ordering >= 1),

        CONSTRAINT check_result_keys_entry_unique UNIQUE (applicability_entry_id),
        CONSTRAINT check_result_keys_org_id_unique UNIQUE (organization_id, id)
      );

      CREATE UNIQUE INDEX check_result_keys_preimage_unique
        ON check_result_keys (evaluation_id, key_preimage);
      -- NON-unique, deliberately: this is the lookup that FINDS a same-hash record so a
      -- different preimage can be refused.
      CREATE INDEX check_result_keys_hash ON check_result_keys (evaluation_id, check_result_key_sha256);

      -- T-MUT. The slot preallocates the Check Result identity BEFORE execution, so a crashed
      -- attempt leaves a materialized key rather than a phantom Result, and two concurrent
      -- executors cannot produce two Results for one key.
      CREATE TABLE check_result_slots (
        id                        uuid PRIMARY KEY,
        state_version             bigint NOT NULL DEFAULT 0,
        created_at                timestamptz(6) NOT NULL,
        updated_at                timestamptz(6) NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        evaluation_id             uuid NOT NULL,
        applicability_entry_id    uuid NOT NULL,
        check_result_key_id       uuid NOT NULL,
        check_result_id           uuid NOT NULL,
        ordering                  integer NOT NULL CHECK (ordering >= 1),
        state                     text NOT NULL CHECK (state IN ('pending','running','terminal')),
        attempt_count             integer NOT NULL DEFAULT 0 CHECK (attempt_count BETWEEN 0 AND 2),
        terminal_result_id        uuid,

        -- Terminalization requires the terminal Result to BE the preallocated identity.
        CONSTRAINT check_result_slots_terminal_identity CHECK (
          terminal_result_id IS NULL OR terminal_result_id = check_result_id
        ),
        CONSTRAINT check_result_slots_terminal_shape CHECK (
          (state = 'terminal') = (terminal_result_id IS NOT NULL)
        ),
        CONSTRAINT check_result_slots_entry_unique UNIQUE (applicability_entry_id),
        CONSTRAINT check_result_slots_key_unique UNIQUE (check_result_key_id),
        CONSTRAINT check_result_slots_result_unique UNIQUE (check_result_id),
        CONSTRAINT check_result_slots_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT check_result_slots_key_fk FOREIGN KEY (organization_id, check_result_key_id)
          REFERENCES check_result_keys (organization_id, id)
      );

      -- T-CHK. One row per attempt. Implementation-owned telemetry, never a domain event.
      CREATE TABLE check_attempts (
        id                        uuid PRIMARY KEY,
        created_at                timestamptz(6) NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        evaluation_id             uuid NOT NULL,
        slot_id                   uuid NOT NULL,
        attempt_number            integer NOT NULL CHECK (attempt_number BETWEEN 1 AND 2),
        retry_of_attempt_number   integer CHECK (retry_of_attempt_number IS NULL OR retry_of_attempt_number >= 1),
        check_catalog_version     text NOT NULL,
        check_definition_id       text NOT NULL,
        definition_version        text NOT NULL,
        applicability_sha256      bytea NOT NULL CHECK (octet_length(applicability_sha256) = 32),
        result_key_sha256         bytea NOT NULL CHECK (octet_length(result_key_sha256) = 32),
        deterministic_input_sha256 bytea NOT NULL CHECK (octet_length(deterministic_input_sha256) = 32),
        scheduled_at              timestamptz(6) NOT NULL,
        started_at                timestamptz(6) NOT NULL,
        completed_at              timestamptz(6),
        deadline_at               timestamptz(6) NOT NULL,
        produced_check_result_id  uuid,
        output_sha256             bytea CHECK (output_sha256 IS NULL OR octet_length(output_sha256) = 32),
        execution_status          text CHECK (execution_status IS NULL OR execution_status IN (#{quoted(EXECUTION_STATUSES)})),
        elapsed_ms                integer CHECK (elapsed_ms IS NULL OR elapsed_ms >= 0),
        reason_code               text,

        -- Only the FIRST attempt has no antecedent (`check-executor-interim-v1`: one initial
        -- attempt plus exactly one retry).
        CONSTRAINT check_attempts_retry_lineage CHECK (
          (attempt_number = 1) = (retry_of_attempt_number IS NULL)
        ),
        CONSTRAINT check_attempts_number_unique UNIQUE (slot_id, attempt_number),
        CONSTRAINT check_attempts_slot_fk FOREIGN KEY (organization_id, slot_id)
          REFERENCES check_result_slots (organization_id, id),
        CONSTRAINT check_attempts_org_id_unique UNIQUE (organization_id, id)
      );
    SQL

    tenant_rls("check_result_keys")
    tenant_rls("check_result_slots")
    tenant_rls("check_attempts")
  end

  # ----------------------------------------------------------------------------- results
  def create_results
    execute <<~SQL
      -- T-IMM. `id` EQUALS the owning Slot's preallocated Check Result identity, which is why
      -- there is no separate slot->result allocation step and no window in which a Result
      -- exists under an identity the slot does not name.
      CREATE TABLE check_results (
        id                          uuid PRIMARY KEY,
        schema_version              text NOT NULL,
        created_at                  timestamptz(6) NOT NULL,
        correlation_id              uuid NOT NULL,

        organization_id             uuid NOT NULL,
        project_id                  uuid NOT NULL,
        evaluation_id               uuid NOT NULL,
        evaluation_input_snapshot_id uuid NOT NULL,
        applicability_snapshot_id   uuid NOT NULL,
        applicability_entry_id      uuid NOT NULL,
        slot_id                     uuid NOT NULL,
        check_result_key_id         uuid NOT NULL,
        check_result_key_sha256     bytea NOT NULL CHECK (octet_length(check_result_key_sha256) = 32),
        check_result_key_preimage   bytea NOT NULL,

        check_catalog_version       text NOT NULL,
        check_definition_row_id     uuid NOT NULL REFERENCES check_definitions (id),
        check_definition_id         text NOT NULL,
        check_definition_version    text NOT NULL,
        pillar_id                   text NOT NULL CHECK (pillar_id IN (#{quoted(PILLARS)})),

        subject_scope               text NOT NULL CHECK (subject_scope IN (#{quoted(SUBJECT_SCOPES)})),
        canonical_subject_type      text NOT NULL CHECK (canonical_subject_type IN (#{quoted(SUBJECT_TYPES)})),
        canonical_subject_key       text NOT NULL,
        source_id                   uuid,
        document_id                 uuid,

        absence_coverage_selector   jsonb NOT NULL,
        subject_set_complete        boolean NOT NULL,
        evidence_set_sha256         bytea NOT NULL CHECK (octet_length(evidence_set_sha256) = 32),

        execution_status            text NOT NULL CHECK (execution_status IN (#{quoted(EXECUTION_STATUSES)})),
        outcome_code                text NOT NULL,
        error_reason_code           text CHECK (error_reason_code IS NULL OR error_reason_code IN (#{quoted(ERROR_REASONS)})),
        normalized_observation      jsonb NOT NULL,

        impact_band                 text CHECK (impact_band IS NULL OR impact_band IN (#{quoted(IMPACT_BANDS)})),
        impact_rule_version         text NOT NULL,
        confidence_value            numeric(5,4) CHECK (confidence_value IS NULL OR (confidence_value >= 0 AND confidence_value <= 1)),
        confidence_status           text NOT NULL CHECK (confidence_status IN (#{quoted(CONFIDENCE_STATUSES)})),
        confidence_band             text NOT NULL CHECK (confidence_band IN (#{quoted(CONFIDENCE_BANDS)})),
        confidence_policy_version   text NOT NULL,
        effort_band                 text CHECK (effort_band IS NULL OR effort_band IN (#{quoted(EFFORT_BANDS)})),
        effort_basis                text,
        recommendation_template_id  text,
        rule_or_model_version       text NOT NULL,

        execution_attempt_count     integer NOT NULL CHECK (execution_attempt_count IN (1,2)),
        deterministic_input_sha256  bytea NOT NULL CHECK (octet_length(deterministic_input_sha256) = 32),
        deterministic_output_sha256 bytea NOT NULL CHECK (octet_length(deterministic_output_sha256) = 32),
        produced_at                 timestamptz(6) NOT NULL,

        -- The Check Result Contract, made structural rather than asserted in code:
        --   `impact_band` is REQUIRED for failed and NULL for passed/not_applicable/error;
        --   `error_reason_code` is nonnull exactly when the status is error;
        --   a `not_applicable` result is valid only for CHK-LP-001 (an attempted
        --   not-applicable from any other Definition is `check_catalog_integrity_failure`,
        --   and this refuses to persist one at all).
        CONSTRAINT check_results_impact_shape CHECK (
          (execution_status = 'failed') = (impact_band IS NOT NULL)
        ),
        CONSTRAINT check_results_error_shape CHECK (
          (execution_status = 'error') = (error_reason_code IS NOT NULL)
        ),
        CONSTRAINT check_results_not_applicable_owner CHECK (
          execution_status <> 'not_applicable' OR check_definition_id = 'CHK-LP-001'
        ),
        -- A handled error has no usable confidence; a decided result has one.
        CONSTRAINT check_results_confidence_shape CHECK (
          (confidence_status = 'valid') = (confidence_value IS NOT NULL)
        ),
        CONSTRAINT check_results_subject_shape CHECK (
          (subject_scope = 'project'  AND source_id IS NULL     AND document_id IS NULL)
          OR (subject_scope = 'source'   AND source_id IS NOT NULL AND document_id IS NULL)
          OR (subject_scope = 'document' AND source_id IS NOT NULL AND document_id IS NOT NULL)
        ),
        CONSTRAINT check_results_slot_unique UNIQUE (slot_id),
        CONSTRAINT check_results_key_unique UNIQUE (check_result_key_id),
        CONSTRAINT check_results_entry_unique UNIQUE (applicability_entry_id),
        CONSTRAINT check_results_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT check_results_evaluation_fk FOREIGN KEY (organization_id, project_id, evaluation_id)
          REFERENCES evaluations (organization_id, project_id, id),
        CONSTRAINT check_results_slot_fk FOREIGN KEY (organization_id, slot_id)
          REFERENCES check_result_slots (organization_id, id)
      );

      CREATE INDEX check_results_evaluation ON check_results (organization_id, evaluation_id, check_definition_id);

      -- T-IMM. The Evidence a Result was decided from, with the Validation Decision statuses
      -- FROZEN as of Check creation. A later Decision never rewrites these.
      CREATE TABLE check_result_evidences (
        id                        uuid PRIMARY KEY,
        created_at                timestamptz(6) NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        check_result_id           uuid NOT NULL,
        evidence_id               uuid NOT NULL,
        evidence_sha256           bytea NOT NULL CHECK (octet_length(evidence_sha256) = 32),
        validation_decision_id    uuid,
        validation_status         text NOT NULL,
        ordering                  integer NOT NULL CHECK (ordering >= 1),

        CONSTRAINT check_result_evidences_pair_unique UNIQUE (check_result_id, evidence_id),
        CONSTRAINT check_result_evidences_order_unique UNIQUE (check_result_id, ordering),
        CONSTRAINT check_result_evidences_result_fk FOREIGN KEY (organization_id, check_result_id)
          REFERENCES check_results (organization_id, id),
        CONSTRAINT check_result_evidences_org_id_unique UNIQUE (organization_id, id)
      );

      -- T-IMM. The same-hash/different-preimage record, for BOTH ratified fail-closed
      -- branches: PRULE-010's `check_result_key_collision` and OD-017's Issue collision.
      -- Existing and conflicting roles are semantic and are never reordered by UUID.
      CREATE TABLE fingerprint_collision_decisions (
        id                        uuid PRIMARY KEY,
        created_at                timestamptz(6) NOT NULL,
        correlation_id            uuid NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        evaluation_id             uuid NOT NULL,
        fingerprint_kind          text NOT NULL CHECK (fingerprint_kind IN (#{quoted(FINGERPRINT_KINDS)})),
        fingerprint_sha256        bytea NOT NULL CHECK (octet_length(fingerprint_sha256) = 32),
        existing_record_type      text NOT NULL,
        existing_record_id        uuid NOT NULL,
        conflicting_record_type   text NOT NULL,
        conflicting_record_id     uuid NOT NULL,
        detecting_service_identity_id uuid NOT NULL,
        definition_versions       jsonb NOT NULL,
        input_sha256              bytea NOT NULL CHECK (octet_length(input_sha256) = 32),
        output_sha256             bytea NOT NULL CHECK (octet_length(output_sha256) = 32),
        decision_type             text NOT NULL CHECK (decision_type = 'fingerprint_collision'),
        decision_value            text NOT NULL CHECK (decision_value = 'collision_detected'),
        decision_status           text NOT NULL CHECK (decision_status = 'final'),
        decision_reason_code      text CHECK (decision_reason_code IS NULL),
        collision_detected_at     timestamptz(6) NOT NULL,
        collision_identity_sha256 bytea NOT NULL CHECK (octet_length(collision_identity_sha256) = 32),

        -- Both record types are the one type implied by the kind, and the two identities differ.
        CONSTRAINT fingerprint_collision_decisions_same_type CHECK (
          existing_record_type = conflicting_record_type
            AND existing_record_type = fingerprint_kind
        ),
        CONSTRAINT fingerprint_collision_decisions_distinct CHECK (
          existing_record_id <> conflicting_record_id
        ),
        CONSTRAINT fingerprint_collision_decisions_unique UNIQUE (
          organization_id, project_id, fingerprint_kind, fingerprint_sha256,
          existing_record_id, conflicting_record_id
        ),
        CONSTRAINT fingerprint_collision_decisions_org_id_unique UNIQUE (organization_id, id)
      );
    SQL

    tenant_rls("check_results")
    tenant_rls("check_result_evidences")
    tenant_rls("fingerprint_collision_decisions")
  end

  # ------------------------------------------------------------------------------ issues
  def create_issues
    execute <<~SQL
      -- T-IMM. The retained canonical fingerprint preimage and its digest, allocated once per
      -- distinct preimage in a namespace. `collision_ordinal` exists for the same reason it
      -- does on scheduled actions: two different preimages that hash alike are BOTH allocated,
      -- distinctly, so the collision is representable and therefore refusable.
      CREATE TABLE deduplication_keys (
        id                        uuid PRIMARY KEY,
        created_at                timestamptz(6) NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        namespace                 text NOT NULL,
        digest                    bytea NOT NULL CHECK (octet_length(digest) = 32),
        preimage                  bytea NOT NULL,
        collision_ordinal         integer NOT NULL DEFAULT 0 CHECK (collision_ordinal >= 0),
        allocated_at              timestamptz(6) NOT NULL,

        CONSTRAINT deduplication_keys_identity_unique
          UNIQUE (organization_id, namespace, digest, collision_ordinal),
        CONSTRAINT deduplication_keys_org_id_unique UNIQUE (organization_id, id)
      );

      CREATE UNIQUE INDEX deduplication_keys_preimage_unique
        ON deduplication_keys (organization_id, namespace, preimage);

      -- T-MUT. The ONE persisted product deficiency object. Every Issue originates from one
      -- FAILED catalog Check Result — `check_result_id` is NOT NULL — which is PRULE-011's
      -- origination invariant expressed where no writer can be exempted from it.
      CREATE TABLE issues (
        id                        uuid PRIMARY KEY,
        schema_version            text NOT NULL,
        state_version             bigint NOT NULL DEFAULT 0,
        created_at                timestamptz(6) NOT NULL,
        updated_at                timestamptz(6) NOT NULL,
        correlation_id            uuid NOT NULL,

        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        evaluation_id             uuid NOT NULL,
        check_result_id           uuid NOT NULL,
        source_id                 uuid,
        dedup_key_id              uuid NOT NULL,

        issue_type                text NOT NULL,
        fingerprint_version       text NOT NULL CHECK (fingerprint_version = 'issue-fingerprint-v1'),
        fingerprint_preimage      bytea NOT NULL,
        fingerprint_sha256        bytea NOT NULL CHECK (octet_length(fingerprint_sha256) = 32),

        canonical_subject_type    text NOT NULL CHECK (canonical_subject_type IN (#{quoted(SUBJECT_TYPES)})),
        canonical_subject_key     text NOT NULL,
        check_definition_id       text NOT NULL,
        pillar_id                 text NOT NULL CHECK (pillar_id IN (#{quoted(PILLARS)})),

        impact_band               text NOT NULL CHECK (impact_band IN (#{quoted(IMPACT_BANDS)})),
        confidence_value          numeric(5,4),
        confidence_band           text NOT NULL CHECK (confidence_band IN (#{quoted(CONFIDENCE_BANDS)})),
        confidence_status         text NOT NULL CHECK (confidence_status IN (#{quoted(CONFIDENCE_STATUSES)})),
        effort_band               text CHECK (effort_band IS NULL OR effort_band IN (#{quoted(EFFORT_BANDS)})),
        effort_basis              text,
        recommendation_template_id text,

        state                     text NOT NULL CHECK (state IN (#{quoted(ISSUE_STATES)})),
        adjudication_status       text NOT NULL CHECK (adjudication_status IN (#{quoted(ADJUDICATION_STATUSES)})),
        publication_status        text NOT NULL CHECK (publication_status IN (#{quoted(PUBLICATION_STATUSES)})),
        predecessor_issue_id      uuid,
        successor_issue_id        uuid,
        published_at              timestamptz(6),
        suppressed_at             timestamptz(6),
        terminal_at               timestamptz(6),
        terminal_reason           text,

        -- Check-To-Issue Rules: a failed Result with valid medium/high confidence creates a
        -- PUBLISHED, OPEN Issue; low, missing or invalid confidence creates a WITHHELD
        -- candidate in `review_required`. The two shapes are the whole rule, and a row that
        -- is neither is the permissive middle an implementation drifts into.
        CONSTRAINT issues_published_shape CHECK (
          publication_status <> 'published'
            OR (state = 'open' AND confidence_status = 'valid' AND confidence_band IN ('medium','high')
                AND published_at IS NOT NULL)
        ),
        CONSTRAINT issues_withheld_shape CHECK (
          publication_status <> 'withheld'
            OR (state = 'candidate' AND adjudication_status = 'review_required')
        ),
        CONSTRAINT issues_dedup_key_fk FOREIGN KEY (organization_id, dedup_key_id)
          REFERENCES deduplication_keys (organization_id, id),
        CONSTRAINT issues_check_result_fk FOREIGN KEY (organization_id, check_result_id)
          REFERENCES check_results (organization_id, id),
        CONSTRAINT issues_evaluation_fk FOREIGN KEY (organization_id, project_id, evaluation_id)
          REFERENCES evaluations (organization_id, project_id, id),
        CONSTRAINT issues_org_id_unique UNIQUE (organization_id, id)
      );

      -- PRULE-023: the FULL canonical preimage is uniqueness authority within one Evaluation.
      -- There is deliberately NO unique index on `fingerprint_sha256`.
      CREATE UNIQUE INDEX issues_fingerprint_preimage_unique
        ON issues (evaluation_id, fingerprint_version, fingerprint_preimage);
      CREATE INDEX issues_fingerprint_hash ON issues (organization_id, project_id, fingerprint_sha256);
      CREATE INDEX issues_evaluation ON issues (organization_id, evaluation_id);
      -- One direct successor per predecessor.
      CREATE UNIQUE INDEX issues_successor_unique ON issues (predecessor_issue_id)
        WHERE predecessor_issue_id IS NOT NULL;

      CREATE TABLE issue_evidences (
        id                        uuid PRIMARY KEY,
        created_at                timestamptz(6) NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        issue_id                  uuid NOT NULL,
        evidence_id               uuid NOT NULL,
        evidence_sha256           bytea NOT NULL CHECK (octet_length(evidence_sha256) = 32),
        role                      text NOT NULL,
        ordering                  integer NOT NULL CHECK (ordering >= 1),

        CONSTRAINT issue_evidences_pair_unique UNIQUE (issue_id, evidence_id),
        CONSTRAINT issue_evidences_order_unique UNIQUE (issue_id, ordering),
        CONSTRAINT issue_evidences_issue_fk FOREIGN KEY (organization_id, issue_id)
          REFERENCES issues (organization_id, id),
        CONSTRAINT issue_evidences_org_id_unique UNIQUE (organization_id, id)
      );

      -- T-MUT. Exactly one current leaf per full fingerprint identity, across Evaluations.
      CREATE TABLE issue_lineage_heads (
        id                        uuid PRIMARY KEY,
        state_version             bigint NOT NULL DEFAULT 0,
        created_at                timestamptz(6) NOT NULL,
        updated_at                timestamptz(6) NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        dedup_key_id              uuid NOT NULL,
        current_issue_id          uuid NOT NULL,

        CONSTRAINT issue_lineage_heads_key_unique UNIQUE (dedup_key_id),
        CONSTRAINT issue_lineage_heads_key_fk FOREIGN KEY (organization_id, dedup_key_id)
          REFERENCES deduplication_keys (organization_id, id),
        CONSTRAINT issue_lineage_heads_issue_fk FOREIGN KEY (organization_id, current_issue_id)
          REFERENCES issues (organization_id, id),
        CONSTRAINT issue_lineage_heads_org_id_unique UNIQUE (organization_id, id)
      );

      -- T-IMM. The sealed set. Membership and order live only in the memberships table, so
      -- there is one representation of "what was in the set" rather than two.
      CREATE TABLE issue_sets (
        id                        uuid PRIMARY KEY,
        schema_version            text NOT NULL,
        created_at                timestamptz(6) NOT NULL,
        correlation_id            uuid NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        evaluation_id             uuid NOT NULL,
        member_count              integer NOT NULL CHECK (member_count >= 0),
        current_leaf_count        integer NOT NULL CHECK (current_leaf_count >= 0),
        membership_root_sha256    bytea NOT NULL CHECK (octet_length(membership_root_sha256) = 32),
        content_sha256            bytea NOT NULL CHECK (octet_length(content_sha256) = 32),
        sealed_at                 timestamptz(6) NOT NULL,

        CONSTRAINT issue_sets_leaf_subset CHECK (current_leaf_count <= member_count),
        CONSTRAINT issue_sets_evaluation_unique UNIQUE (evaluation_id),
        CONSTRAINT issue_sets_evaluation_fk FOREIGN KEY (organization_id, project_id, evaluation_id)
          REFERENCES evaluations (organization_id, project_id, id),
        CONSTRAINT issue_sets_org_id_unique UNIQUE (organization_id, id)
      );

      CREATE TABLE issue_set_memberships (
        id                        uuid PRIMARY KEY,
        created_at                timestamptz(6) NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        issue_set_id              uuid NOT NULL,
        issue_id                  uuid NOT NULL,
        current_leaf              boolean NOT NULL,
        frozen_state              text NOT NULL CHECK (frozen_state IN (#{quoted(ISSUE_STATES)})),
        frozen_state_version      bigint NOT NULL,
        ordering                  integer NOT NULL CHECK (ordering >= 1),

        CONSTRAINT issue_set_memberships_pair_unique UNIQUE (issue_set_id, issue_id),
        CONSTRAINT issue_set_memberships_order_unique UNIQUE (issue_set_id, ordering),
        CONSTRAINT issue_set_memberships_set_fk FOREIGN KEY (organization_id, issue_set_id)
          REFERENCES issue_sets (organization_id, id),
        CONSTRAINT issue_set_memberships_issue_fk FOREIGN KEY (organization_id, issue_id)
          REFERENCES issues (organization_id, id),
        CONSTRAINT issue_set_memberships_org_id_unique UNIQUE (organization_id, id)
      );
    SQL

    %w[deduplication_keys issues issue_evidences issue_lineage_heads
       issue_sets issue_set_memberships].each { |t| tenant_rls(t) }
  end

  def tenant_rls(table)
    execute <<~SQL
      ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
      ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;
      CREATE POLICY #{table}_context ON #{table}
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
    SQL
  end

  # -------------------------------------------------------------------------------- guards
  #
  # T-IMM at the database, not by convention. Every one of these rows is a decision that a
  # later read must be able to trust was not revised after the fact: the applicability seal
  # is the input authority a Result freezes, the result key is uniqueness authority, and a
  # Check Result that could be rewritten would make "immutable" an application habit.
  def create_guards
    immutable = %w[check_applicability_snapshots check_applicability_entries check_result_keys
                   check_results check_result_evidences fingerprint_collision_decisions
                   deduplication_keys issue_evidences issue_sets issue_set_memberships]
    execute <<~SQL
      CREATE FUNCTION f1_check_immutable_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        RAISE EXCEPTION '% is immutable', TG_TABLE_NAME USING ERRCODE = 'raise_exception';
      END;
      $$;
    SQL
    immutable.each do |table|
      execute <<~SQL
        CREATE TRIGGER #{table}_guard BEFORE UPDATE OR DELETE ON #{table}
          FOR EACH ROW EXECUTE FUNCTION f1_check_immutable_guard();
      SQL
    end

    # The Slot is the one mutable member of the identity chain, and exactly three things about
    # it may change: its state along the closed edge set, its attempt count, and the terminal
    # Result it names. Its preallocated identity may never be repointed — repointing it after
    # execution would let a Result be attributed to a key it was not computed for.
    execute <<~SQL
      CREATE FUNCTION f1_check_result_slots_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'check_result_slot_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.evaluation_id IS DISTINCT FROM OLD.evaluation_id
           OR NEW.applicability_entry_id IS DISTINCT FROM OLD.applicability_entry_id
           OR NEW.check_result_key_id IS DISTINCT FROM OLD.check_result_key_id
           OR NEW.check_result_id IS DISTINCT FROM OLD.check_result_id THEN
          RAISE EXCEPTION 'check_result_slot_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF OLD.state = 'terminal' AND NEW.state IS DISTINCT FROM OLD.state THEN
          RAISE EXCEPTION 'check_result_slot_terminal' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.attempt_count < OLD.attempt_count THEN
          RAISE EXCEPTION 'check_result_slot_attempts_monotonic' USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER check_result_slots_guard BEFORE UPDATE OR DELETE ON check_result_slots
        FOR EACH ROW EXECUTE FUNCTION f1_check_result_slots_guard();
    SQL

    # PRULE-012: no actor may alter a persisted `impact_band` or `confidence_value`.
    # Adjudication changes `adjudication_status` and eligibility, never the metadata — so the
    # prohibition is enforced where a permission cannot reach it. The origin, fingerprint and
    # subject are equally fixed: an Issue that could be repointed at another Check Result
    # would break PRULE-011's origination invariant after the fact.
    execute <<~SQL
      CREATE FUNCTION f1_issues_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'issue_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.evaluation_id IS DISTINCT FROM OLD.evaluation_id
           OR NEW.check_result_id IS DISTINCT FROM OLD.check_result_id
           OR NEW.dedup_key_id IS DISTINCT FROM OLD.dedup_key_id
           OR NEW.fingerprint_preimage IS DISTINCT FROM OLD.fingerprint_preimage
           OR NEW.fingerprint_sha256 IS DISTINCT FROM OLD.fingerprint_sha256
           OR NEW.issue_type IS DISTINCT FROM OLD.issue_type
           OR NEW.canonical_subject_key IS DISTINCT FROM OLD.canonical_subject_key THEN
          RAISE EXCEPTION 'issue_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.impact_band IS DISTINCT FROM OLD.impact_band
           OR NEW.confidence_value IS DISTINCT FROM OLD.confidence_value
           OR NEW.confidence_band IS DISTINCT FROM OLD.confidence_band
           OR NEW.confidence_status IS DISTINCT FROM OLD.confidence_status THEN
          RAISE EXCEPTION 'issue_impact_metadata_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER issues_guard BEFORE UPDATE OR DELETE ON issues
        FOR EACH ROW EXECUTE FUNCTION f1_issues_guard();
    SQL
  end
end
