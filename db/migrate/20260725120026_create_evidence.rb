# frozen_string_literal: true

# F-03 Evidence Production — the append-only Evidence store (FOUNDATION-003;
# SCORE_EVIDENCE_MODEL.md :43-67). Evidence records FACTS and is IMMUTABLE: written once,
# never updated or deleted. Immutability is enforced two ways — the runtime is granted
# SELECT/INSERT only (no UPDATE/DELETE, via F1::RuntimeGrants), AND a trigger rejects every
# UPDATE and DELETE from any role, so the envelope can never change (a correction is a new
# record). The table is FORCE ROW LEVEL SECURITY, tenant-scoped by the proved context org,
# with composite FK integrity to projects/sources so a cross-Project or cross-Organization
# reference is a database error. evaluation_id has no FK (the evaluations capability does not
# exist yet; verification Evidence is captured with a null evaluation_id). The append is
# idempotent on (organization_id, producer_id, attempt_id), so a retried producer completion
# writes no second record. F-03 creates NO validation-head, adjudication, or scoring table.
class CreateEvidence < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE evidence (
        id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        created_at              timestamptz(6) NOT NULL DEFAULT now(),
        schema_version          text NOT NULL,
        organization_id         uuid NOT NULL,
        project_id              uuid NOT NULL,
        source_id               uuid,
        evaluation_id           uuid,
        evidence_type           text NOT NULL
          CHECK (evidence_type IN ('source_document','crawl_observation','parsed_content','external_measurement','verification_observation')),
        producer_id             text NOT NULL,
        attempt_id              text NOT NULL,
        payload_reference       text NOT NULL,
        content_sha256          text NOT NULL CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
        captured_at_utc         timestamptz(6) NOT NULL,
        observed_at_utc         timestamptz(6) NOT NULL,
        source_system           text NOT NULL,
        collection_method       text NOT NULL,
        collector_version       text NOT NULL,
        validation_status       text NOT NULL CHECK (validation_status IN ('valid','invalid','quarantined')),
        validation_reason_code  text,
        data_classification     text NOT NULL CHECK (data_classification IN ('public','internal','confidential','restricted')),
        payload_retention_class text NOT NULL CHECK (payload_retention_class = 'product_evidence_payload'),
        correlation_id          uuid NOT NULL,
        -- validation_reason_code is null only when valid (SCORE_EVIDENCE_MODEL.md :60)
        CONSTRAINT evidence_validation_reason_consistency CHECK (
          (validation_status = 'valid' AND validation_reason_code IS NULL) OR
          (validation_status <> 'valid' AND validation_reason_code IS NOT NULL)
        ),
        CONSTRAINT evidence_org_id_unique UNIQUE (organization_id, id),
        -- one Evidence per producer attempt (idempotent append)
        CONSTRAINT evidence_producer_attempt_unique UNIQUE (organization_id, producer_id, attempt_id),
        -- same-Organization, same-Project references, enforced by the database
        CONSTRAINT evidence_project_fk FOREIGN KEY (organization_id, project_id)
          REFERENCES projects (organization_id, id),
        CONSTRAINT evidence_source_fk FOREIGN KEY (organization_id, project_id, source_id)
          REFERENCES sources (organization_id, project_id, id)
      );
      CREATE INDEX evidence_content_hash_lookup ON evidence (organization_id, content_sha256);

      ALTER TABLE evidence ENABLE ROW LEVEL SECURITY;
      ALTER TABLE evidence FORCE ROW LEVEL SECURITY;
      CREATE POLICY evidence_context ON evidence
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
      REVOKE ALL ON evidence FROM PUBLIC;
    SQL

    # Append-only: no role may ever change or remove an Evidence envelope. Payload
    # destruction happens against the referenced F-02 record; the envelope is product_history
    # and is retained forever, so update and delete are unconditionally refused.
    execute <<~SQL
      CREATE FUNCTION f1_evidence_append_only() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        RAISE EXCEPTION 'evidence_is_immutable' USING ERRCODE = 'raise_exception';
      END;
      $$;
      CREATE TRIGGER evidence_append_only BEFORE UPDATE OR DELETE ON evidence
        FOR EACH ROW EXECUTE FUNCTION f1_evidence_append_only();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS evidence_append_only ON evidence;
      DROP FUNCTION IF EXISTS f1_evidence_append_only();
      DROP TABLE IF EXISTS evidence;
    SQL
  end
end
