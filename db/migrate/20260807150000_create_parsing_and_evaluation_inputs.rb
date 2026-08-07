# frozen_string_literal: true

# S-08's three product tables: the ParsingJob that turns an ingested Document into a Parsed
# Artifact, the immutable Artifact itself, and the immutable Evaluation Input Snapshot that
# WF-006 seals from them (WORKFLOW_SPECIFICATIONS.md :470-476, :503-509).
#
# WHAT THIS OWNS AND WHAT IT DOES NOT. The parsing half of WF-006: manifest -> ParsingJob ->
# Parsed Artifact -> Evaluation Input Snapshot, which is what makes readiness derive `ready`
# instead of `blocked`. It does NOT create `indexing_jobs` or `index_receipts`. That is not
# an oversight: :493 settles that "indexing is an asynchronous Retrieval Context projection
# and is NOT a WF-007 Evaluation-input prerequisite", so the Retrieval projection can land
# separately without changing a sealed Evaluation, and building it here would add a second
# unbuilt lifecycle to a slice whose point is unblocking the first.
#
# THE OD-027 WITHHELD LIMB IS ABSENT, as it was in S-07-010. OD-027 asks whether ParsingJob
# to IndexingJob is one-to-many or at most one. Nothing here answers it: there is no
# `unique (parsing_job_id)`, no `has_one` and no IndexingJob at all. `indexing-interim-v1`
# pins the ParsingJob key to `(document_id, content_digest, parser_definition_version)`,
# which is the half OD-027 does NOT contest, and that is the key used below.
#
# DOCUMENT `ingested -> parsed` IS ALREADY ADMITTED by the S-07-010 lifecycle guard, so no
# guard changes here — the edge existed before anything could travel it.
class CreateParsingAndEvaluationInputs < ActiveRecord::Migration[8.1]
  # :481 — the exhaustive ParsingJob status vocabulary, identical in shape to the ingestion
  # job's because :481-484 describe the same attempt/retry/dead-letter cycle.
  JOB_STATES = %w[queued running succeeded failed dead_letter].freeze
  # :484 — "Authorized replay of `dead_letter` ... transitions that job to queued".
  # `succeeded` is terminal; `failed` retries while attempts remain and is otherwise
  # dead-lettered at the same serialized checkpoint.
  JOB_EDGES = {
    "queued" => %w[running],
    "running" => %w[succeeded failed],
    "failed" => %w[queued dead_letter],
    "dead_letter" => %w[queued]
  }.freeze

  # :480 — the exhaustive reason set and its precedence. Pre-execution first-match, then the
  # three execution reasons. A CHECK over the closed set is what stops an implementation
  # inventing a seventh reason to describe a case it did not plan for.
  JOB_REASONS = %w[
    tenant_mismatch input_quarantined input_bytes_missing input_digest_mismatch
    unsupported_media_type parser_policy_unavailable
    parser_timeout parser_dependency_unavailable normalized_output_invalid
  ].freeze

  READINESS = %w[blocked ready_full ready_partial].freeze
  COVERAGE = %w[full partial].freeze
  CLASSIFICATIONS = %w[public internal confidential restricted].freeze

  def up
    execute <<~SQL
      -- =============================================================== parsing_jobs (:474) T-MUT LINEAGE
      CREATE TABLE parsing_jobs (
        id                          uuid PRIMARY KEY,
        state_version               bigint NOT NULL DEFAULT 0,
        lock_version                bigint NOT NULL DEFAULT 0,
        schema_version              text NOT NULL,
        created_at                  timestamptz(6) NOT NULL,
        updated_at                  timestamptz(6) NOT NULL,

        correlation_id              uuid NOT NULL,
        causation_id                uuid NOT NULL,
        command_id                  uuid,

        organization_id             uuid NOT NULL,
        project_id                  uuid NOT NULL,
        source_id                   uuid NOT NULL,
        crawl_id                    uuid NOT NULL,
        evaluation_id               uuid NOT NULL,
        document_id                 uuid NOT NULL,
        ingestion_job_id            uuid NOT NULL,
        -- :470 "input-Evidence IDs" — the `source_document` Evidence the body is read from.
        input_evidence_id           uuid NOT NULL,

        canonical_url               text NOT NULL CHECK (length(canonical_url) BETWEEN 1 AND 8192),
        source_root                 boolean NOT NULL,
        media_type                  text NOT NULL CHECK (length(media_type) BETWEEN 1 AND 255),
        content_digest              bytea NOT NULL CHECK (octet_length(content_digest) = 32),
        data_classification         text NOT NULL CHECK (data_classification IN (#{quoted(CLASSIFICATIONS)})),

        parser_definition_version   text NOT NULL CHECK (length(parser_definition_version) BETWEEN 1 AND 120),
        normalization_schema_version text NOT NULL CHECK (length(normalization_schema_version) BETWEEN 1 AND 120),

        status                      text NOT NULL CHECK (status IN (#{quoted(JOB_STATES)})),
        attempt_number              integer NOT NULL CHECK (attempt_number BETWEEN 1 AND 3),
        last_reason_code            text CHECK (last_reason_code IN (#{quoted(JOB_REASONS)})),
        parsed_artifact_id          uuid,
        parsed_artifact_digest      bytea CHECK (parsed_artifact_digest IS NULL OR octet_length(parsed_artifact_digest) = 32),
        idempotency_key             text NOT NULL CHECK (length(idempotency_key) BETWEEN 1 AND 255),
        replay_generation           integer NOT NULL DEFAULT 0 CHECK (replay_generation >= 0),

        queued_at                   timestamptz(6) NOT NULL,
        started_at                  timestamptz(6),
        completed_at                timestamptz(6),

        -- :475 "Every successful job atomically creates one immutable Parsed Artifact": a
        -- succeeded job without its Artifact is a half-recorded success and cannot exist.
        CONSTRAINT parsing_jobs_success_has_artifact CHECK (
          (status <> 'succeeded') OR (parsed_artifact_id IS NOT NULL AND parsed_artifact_digest IS NOT NULL)
        ),
        -- A terminal non-success must say why; a non-terminal job has nothing to say yet.
        CONSTRAINT parsing_jobs_failure_has_reason CHECK (
          (status NOT IN ('failed','dead_letter')) OR last_reason_code IS NOT NULL
        ),
        CONSTRAINT parsing_jobs_org_project_fk FOREIGN KEY (organization_id, project_id)
          REFERENCES projects (organization_id, id),
        CONSTRAINT parsing_jobs_document_fk FOREIGN KEY (organization_id, project_id, document_id)
          REFERENCES documents (organization_id, project_id, id),
        CONSTRAINT parsing_jobs_evaluation_fk FOREIGN KEY (organization_id, project_id, evaluation_id)
          REFERENCES evaluations (organization_id, project_id, id),
        CONSTRAINT parsing_jobs_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT parsing_jobs_org_project_id_unique UNIQUE (organization_id, project_id, id)
      );

      -- :474 "Exactly one ParsingJob exists per (document_id, content_digest,
      -- parser_definition_version)". The identity `indexing-interim-v1` pins and OD-027 does
      -- not contest: a changed digest or parser version is a DISTINCT job, never an overwrite.
      CREATE UNIQUE INDEX parsing_jobs_identity_unique
        ON parsing_jobs (document_id, content_digest, parser_definition_version);
      CREATE INDEX parsing_jobs_evaluation ON parsing_jobs (organization_id, evaluation_id, status);
      CREATE INDEX parsing_jobs_crawl ON parsing_jobs (organization_id, crawl_id);

      ALTER TABLE parsing_jobs ENABLE ROW LEVEL SECURITY;
      ALTER TABLE parsing_jobs FORCE ROW LEVEL SECURITY;
      CREATE POLICY parsing_jobs_context ON parsing_jobs
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());

      -- ============================================================ parsed_artifacts (:475) T-IMM LINEAGE
      CREATE TABLE parsed_artifacts (
        id                          uuid PRIMARY KEY,
        schema_version              text NOT NULL,
        created_at                  timestamptz(6) NOT NULL,
        correlation_id              uuid NOT NULL,

        organization_id             uuid NOT NULL,
        project_id                  uuid NOT NULL,
        source_id                   uuid NOT NULL,
        document_id                 uuid NOT NULL,
        parsing_job_id              uuid NOT NULL,

        canonical_url               text NOT NULL CHECK (length(canonical_url) BETWEEN 1 AND 8192),
        source_root                 boolean NOT NULL,
        input_media_type            text NOT NULL CHECK (length(input_media_type) BETWEEN 1 AND 255),
        input_content_digest        bytea NOT NULL CHECK (octet_length(input_content_digest) = 32),
        parser_definition_version   text NOT NULL CHECK (length(parser_definition_version) BETWEEN 1 AND 120),
        normalization_schema_version text NOT NULL CHECK (length(normalization_schema_version) BETWEEN 1 AND 120),

        -- The normalized payload is protected content behind F-02, exactly as every other
        -- product payload is; the row carries its opaque reference and its digest, never bytes.
        normalized_payload_reference text NOT NULL CHECK (length(normalized_payload_reference) BETWEEN 1 AND 512),
        normalized_payload_sha256   bytea NOT NULL CHECK (octet_length(normalized_payload_sha256) = 32),
        data_classification         text NOT NULL CHECK (data_classification IN (#{quoted(CLASSIFICATIONS)})),

        CONSTRAINT parsed_artifacts_job_fk FOREIGN KEY (organization_id, parsing_job_id)
          REFERENCES parsing_jobs (organization_id, id),
        CONSTRAINT parsed_artifacts_document_fk FOREIGN KEY (organization_id, project_id, document_id)
          REFERENCES documents (organization_id, project_id, id),
        CONSTRAINT parsed_artifacts_org_id_unique UNIQUE (organization_id, id)
      );

      -- One Artifact per successful job. A second row for the same job would be a second
      -- answer for one set of bytes.
      CREATE UNIQUE INDEX parsed_artifacts_job_unique ON parsed_artifacts (parsing_job_id);
      CREATE INDEX parsed_artifacts_document ON parsed_artifacts (organization_id, document_id);

      ALTER TABLE parsed_artifacts ENABLE ROW LEVEL SECURITY;
      ALTER TABLE parsed_artifacts FORCE ROW LEVEL SECURITY;
      CREATE POLICY parsed_artifacts_context ON parsed_artifacts
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());

      -- =================================================== evaluation_input_snapshots (:501) T-IMM
      CREATE TABLE evaluation_input_snapshots (
        id                          uuid PRIMARY KEY,
        schema_version              text NOT NULL,
        created_at                  timestamptz(6) NOT NULL,
        correlation_id              uuid NOT NULL,

        organization_id             uuid NOT NULL,
        project_id                  uuid NOT NULL,
        evaluation_id               uuid NOT NULL,
        crawl_id                    uuid NOT NULL,

        crawl_coverage_status       text CHECK (crawl_coverage_status IS NULL OR crawl_coverage_status IN (#{quoted(COVERAGE)})),
        crawl_completion_reason     text,
        parser_policy_version       text,
        parser_definition_version   text,
        normalization_schema_version text,

        -- The ordered manifest tuples and the failed subset, as canonical JSON. They are the
        -- snapshot's content, and the content hash below is over them, so a reader can
        -- re-derive the readiness decision instead of trusting the recorded status.
        manifest                    jsonb NOT NULL,
        failed_entries              jsonb NOT NULL,

        readiness_status            text NOT NULL CHECK (readiness_status IN (#{quoted(READINESS)})),
        coverage_status             text NOT NULL CHECK (coverage_status IN (#{quoted(COVERAGE)})),
        blocked_predicate           text,
        successful_count            integer NOT NULL CHECK (successful_count >= 0),
        failed_count                integer NOT NULL CHECK (failed_count >= 0),
        source_roots_total          integer NOT NULL CHECK (source_roots_total >= 0),
        source_roots_succeeded      integer NOT NULL CHECK (source_roots_succeeded >= 0),
        content_sha256              bytea NOT NULL CHECK (octet_length(content_sha256) = 32),

        -- :503 "`blocked` ... Coverage is `partial`". The two are not independently chosen.
        CONSTRAINT evaluation_input_snapshots_blocked_shape CHECK (
          (readiness_status <> 'blocked') OR (coverage_status = 'partial' AND blocked_predicate IS NOT NULL)
        ),
        -- :504 "`ready_full` when the Crawl coverage is full and every manifest job succeeded.
        -- Coverage is `full`." A ready_full with a failed member contradicts its own manifest.
        CONSTRAINT evaluation_input_snapshots_ready_full_shape CHECK (
          (readiness_status <> 'ready_full') OR (coverage_status = 'full' AND failed_count = 0 AND blocked_predicate IS NULL)
        ),
        CONSTRAINT evaluation_input_snapshots_ready_partial_shape CHECK (
          (readiness_status <> 'ready_partial') OR (coverage_status = 'partial' AND successful_count > 0 AND blocked_predicate IS NULL)
        ),
        CONSTRAINT evaluation_input_snapshots_evaluation_fk FOREIGN KEY (organization_id, project_id, evaluation_id)
          REFERENCES evaluations (organization_id, project_id, id),
        CONSTRAINT evaluation_input_snapshots_org_id_unique UNIQUE (organization_id, id)
      );

      -- :475/:501 one snapshot per Evaluation: the seal happens once, and a second row would
      -- be a second immutable answer for the same question.
      CREATE UNIQUE INDEX evaluation_input_snapshots_evaluation_unique
        ON evaluation_input_snapshots (evaluation_id);

      ALTER TABLE evaluation_input_snapshots ENABLE ROW LEVEL SECURITY;
      ALTER TABLE evaluation_input_snapshots FORCE ROW LEVEL SECURITY;
      CREATE POLICY evaluation_input_snapshots_context ON evaluation_input_snapshots
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
    SQL

    create_parsing_job_guard
    create_immutability_guards
    # The runtime role owns no table, so a new table is unreachable to it until its grants
    # are applied. Doing it here means the tables and the access to them arrive together.
    F1::RuntimeGrants.apply_all(connection)
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS evaluation_input_snapshots_guard ON evaluation_input_snapshots;
      DROP TRIGGER IF EXISTS parsed_artifacts_guard ON parsed_artifacts;
      DROP TRIGGER IF EXISTS parsing_jobs_guard ON parsing_jobs;
      DROP FUNCTION IF EXISTS f1_parsed_artifacts_guard();
      DROP FUNCTION IF EXISTS f1_evaluation_input_snapshots_guard();
      DROP FUNCTION IF EXISTS f1_parsing_jobs_guard();
      DROP TABLE IF EXISTS evaluation_input_snapshots;
      DROP TABLE IF EXISTS parsed_artifacts;
      DROP TABLE IF EXISTS parsing_jobs;
    SQL
  end

  private

  def quoted(values) = values.map { |v| "'#{v}'" }.join(", ")

  # The closed ParsingJob edge set (:481-484), plus the identity columns a job may never
  # re-point. The job row is reused across attempts and replay generations, so its
  # Document/digest/parser tuple is exactly what must not drift: it IS the job's identity.
  def create_parsing_job_guard
    edges = JOB_EDGES.map { |from, tos| "('#{from}', ARRAY[#{quoted(tos)}])" }.join(", ")
    execute <<~SQL
      CREATE FUNCTION f1_parsing_jobs_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      DECLARE
        allowed text[];
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'parsing_job_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.document_id IS DISTINCT FROM OLD.document_id
           OR NEW.content_digest IS DISTINCT FROM OLD.content_digest
           OR NEW.parser_definition_version IS DISTINCT FROM OLD.parser_definition_version
           OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
          RAISE EXCEPTION 'parsing_job_facts_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        -- :475 "Parsed Artifact content never mutates": once a job names its Artifact that
        -- link is final, so a later attempt cannot silently repoint a success at other bytes.
        IF OLD.parsed_artifact_id IS NOT NULL AND NEW.parsed_artifact_id IS DISTINCT FROM OLD.parsed_artifact_id THEN
          RAISE EXCEPTION 'parsing_job_artifact_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.status IS DISTINCT FROM OLD.status THEN
          SELECT e.tos INTO allowed FROM (VALUES #{edges}) AS e(from_state, tos)
            WHERE e.from_state = OLD.status;
          IF allowed IS NULL OR NOT (NEW.status = ANY (allowed)) THEN
            RAISE EXCEPTION 'parsing_job_transition_unavailable % -> %', OLD.status, NEW.status
              USING ERRCODE = 'raise_exception';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER parsing_jobs_guard BEFORE UPDATE OR DELETE ON parsing_jobs
        FOR EACH ROW EXECUTE FUNCTION f1_parsing_jobs_guard();
    SQL
  end

  # T-IMM. :475 "Parsed Artifact content never mutates" and :501 makes the snapshot immutable
  # with its canonical content hash. Neither has any lifecycle at all, so the guard is total:
  # the row is written once and is thereafter a fact.
  def create_immutability_guards
    execute <<~SQL
      CREATE FUNCTION f1_parsed_artifacts_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        RAISE EXCEPTION 'parsed_artifact_immutable' USING ERRCODE = 'raise_exception';
      END;
      $$;
      CREATE TRIGGER parsed_artifacts_guard BEFORE UPDATE OR DELETE ON parsed_artifacts
        FOR EACH ROW EXECUTE FUNCTION f1_parsed_artifacts_guard();

      CREATE FUNCTION f1_evaluation_input_snapshots_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        RAISE EXCEPTION 'evaluation_input_snapshot_immutable' USING ERRCODE = 'raise_exception';
      END;
      $$;
      CREATE TRIGGER evaluation_input_snapshots_guard BEFORE UPDATE OR DELETE ON evaluation_input_snapshots
        FOR EACH ROW EXECUTE FUNCTION f1_evaluation_input_snapshots_guard();
    SQL
  end
end
