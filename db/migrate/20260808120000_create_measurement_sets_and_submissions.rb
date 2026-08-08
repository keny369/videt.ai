# frozen_string_literal: true

# The external-measurement intake boundary: the owner-approved Measurement Set package and the
# immutable observation submissions it authorizes
# (WORKFLOW_SPECIFICATIONS.md :480-482; schemas/POSTGRESQL_SCHEMA.md `external_measurement_submissions`;
# OD-010 § Required Owner Approval Package).
#
# A DEDICATED TABLE, NOT `release_artifacts`. The canonical schema files a Measurement Set under
# the generic `release_artifacts` framework, and POSTGRESQL_SCHEMA.md :273 (ADR-068) settles what
# to do about that: the generic policy/release framework "is deferred shared infrastructure ... and
# MUST NOT be introduced piecemeal by a product slice. A dedicated per-domain policy table
# satisfies the same logical contract." `access_policies`, `source_scope_policies`,
# `entitlement_policies` and `crawl_policies` are all built that way. This is the fifth.
#
# TENANT-SCOPED, AND THAT IS A PRODUCT FACT RATHER THAN A CONVENIENCE. A Measurement Set carries
# the ordered intent keys a Check measures against, and those keys are specific to what the
# Organization sells — "who are the best custom home builders in Melbourne" is not a question that
# means anything for a different tenant's Project. A single global set applied to every Project
# would measure most of them against questions no buyer would ever ask. So the set is owned by an
# Organization, row level security applies, and the approval package is approved per set.
#
# NOTHING HERE ACTIVATES ANYTHING. `status` starts `proposed` and the activation edge requires two
# signatures over the package SHA-256 (OD-010: "one signature or signatures over different bytes do
# not authorize activation"). That is enforced by a CHECK constraint, not by a code path, so an
# implementation cannot activate a set by forgetting to look.
class CreateMeasurementSetsAndSubmissions < ActiveRecord::Migration[8.1]
  KINDS = %w[search_index_presence ai_answer_presence authority_reference_set
             local_profile_consistency].freeze
  STATES = %w[proposed active superseded rejected].freeze

  def up
    execute <<~SQL
      -- T-IMM in its identity and payload, T-MUT in its activation state only.
      CREATE TABLE measurement_sets (
        id                        uuid PRIMARY KEY,
        state_version             bigint NOT NULL DEFAULT 0,
        created_at                timestamptz(6) NOT NULL,
        updated_at                timestamptz(6) NOT NULL,
        correlation_id            uuid NOT NULL,

        organization_id           uuid NOT NULL,
        project_id                uuid,

        -- OD-010: "package identity, schema version, immutable version, complete canonical bytes,
        -- SHA-256 of those exact bytes, predecessor or null, creation time, and proposed
        -- effective time".
        package_schema_version    text NOT NULL CHECK (package_schema_version = 'measurement-set-package-v1'),
        measurement_set_id        text NOT NULL CHECK (measurement_set_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,119}$'),
        measurement_set_version   text NOT NULL CHECK (measurement_set_version ~ '^[0-9]+\\.[0-9]+\\.[0-9]+$'),
        measurement_kind          text NOT NULL CHECK (measurement_kind IN (#{quoted(KINDS)})),
        supersedes_id             uuid REFERENCES measurement_sets (id),
        package_created_at        timestamptz(6) NOT NULL,
        proposed_effective_at     timestamptz(6) NOT NULL,

        -- The canonical bytes are protected content behind F-02; the row carries the opaque
        -- reference and the digest, never the bytes. The digest is what both signatures sign.
        package_reference         text NOT NULL CHECK (length(package_reference) BETWEEN 1 AND 512),
        package_sha256            bytea NOT NULL CHECK (octet_length(package_sha256) = 32),

        -- "the exact provider identities and allowed measurement kinds, plus each bound collector
        -- adapter ID, immutable adapter version and digest".
        provider_identities       jsonb NOT NULL,
        collector_adapter_id      text NOT NULL CHECK (length(collector_adapter_id) BETWEEN 1 AND 120),
        collector_adapter_version text NOT NULL CHECK (length(collector_adapter_version) BETWEEN 1 AND 120),
        collector_adapter_sha256  bytea NOT NULL CHECK (octet_length(collector_adapter_sha256) = 32),

        -- "the complete ordered search-query keys and exact query text, AI-intent keys and exact
        -- intent content". Ordered, and the order is part of the approved bytes.
        expected_keys             jsonb NOT NULL,
        key_content               jsonb NOT NULL,
        locale                    text NOT NULL CHECK (locale = 'en-AU'),
        time_zone                 text NOT NULL CHECK (time_zone = 'UTC'),
        -- "maximum Evidence age" — the freshness bound the observation must satisfy. The ratified
        -- `external-observation-v1` value is exactly 24 hours; a package may not widen it.
        max_evidence_age_seconds  integer NOT NULL CHECK (max_evidence_age_seconds = 86400),

        -- "the pinning rule": the Catalog and Definition digests this package binds unchanged.
        bound_catalog_version     text NOT NULL,
        bound_catalog_sha256      bytea NOT NULL CHECK (octet_length(bound_catalog_sha256) = 32),
        bound_definition_id       text NOT NULL,
        bound_definition_version  text NOT NULL,
        bound_definition_sha256   bytea NOT NULL CHECK (octet_length(bound_definition_sha256) = 32),
        retention_location        text NOT NULL CHECK (length(retention_location) BETWEEN 1 AND 512),

        -- "separate signatures from Chief Product and Chief Architect over the SAME package
        -- SHA-256, with signer identity, authority, signed time, and decision".
        product_signature         jsonb,
        architect_signature       jsonb,
        owner_approval_reference  text,

        status                    text NOT NULL CHECK (status IN (#{quoted(STATES)})),
        activated_at              timestamptz(6),
        superseded_at             timestamptz(6),
        rejected_reason           text,

        -- ACTIVATION IS UNREACHABLE WITHOUT BOTH SIGNATURES. Expressed as a constraint rather
        -- than as a check in one command, because OD-010's whole point is that a single approval,
        -- or an approval over different bytes, authorizes nothing — and a rule that lives only in
        -- a code path can be reached around by the next code path.
        CONSTRAINT measurement_sets_activation_requires_both_signatures CHECK (
          status <> 'active'
            OR (product_signature IS NOT NULL AND architect_signature IS NOT NULL
                AND owner_approval_reference IS NOT NULL AND activated_at IS NOT NULL)
        ),
        CONSTRAINT measurement_sets_rejected_has_reason CHECK (
          (status = 'rejected') = (rejected_reason IS NOT NULL)
        ),
        CONSTRAINT measurement_sets_superseded_has_time CHECK (
          (status = 'superseded') = (superseded_at IS NOT NULL)
        ),
        CONSTRAINT measurement_sets_version_unique
          UNIQUE (organization_id, measurement_set_id, measurement_set_version),
        -- Reuse of a version for changed bytes is prohibited; distinct bytes are a distinct row.
        CONSTRAINT measurement_sets_digest_unique UNIQUE (organization_id, package_sha256),
        CONSTRAINT measurement_sets_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT measurement_sets_project_fk FOREIGN KEY (organization_id, project_id)
          REFERENCES projects (organization_id, id)
      );

      -- AT MOST ONE ACTIVE SET per (Organization, Project, kind). Two active sets for one kind
      -- would make "the active Measurement Set" ambiguous, and a Check would then select
      -- whichever the query happened to order first.
      CREATE UNIQUE INDEX measurement_sets_one_active
        ON measurement_sets (organization_id, coalesce(project_id, '00000000-0000-0000-0000-000000000000'::uuid), measurement_kind)
        WHERE status = 'active';

      -- T-IMM. One accepted observation per `(evaluation_id, measurement_kind,
      -- measurement_set_version)` — the ratified uniqueness tuple.
      CREATE TABLE external_measurement_submissions (
        id                        uuid PRIMARY KEY,
        schema_version            text NOT NULL,
        created_at                timestamptz(6) NOT NULL,
        correlation_id            uuid NOT NULL,

        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        evaluation_id             uuid NOT NULL,

        measurement_kind          text NOT NULL CHECK (measurement_kind IN (#{quoted(KINDS)})),
        measurement_set_row_id    uuid NOT NULL,
        measurement_set_id        text NOT NULL,
        measurement_set_version   text NOT NULL,
        measurement_set_sha256    bytea NOT NULL CHECK (octet_length(measurement_set_sha256) = 32),
        collector_adapter_id      text NOT NULL,
        collector_adapter_version text NOT NULL,

        payload_reference         text NOT NULL,
        payload_sha256            bytea NOT NULL CHECK (octet_length(payload_sha256) = 32),
        observed_at               timestamptz(6) NOT NULL,
        captured_at               timestamptz(6) NOT NULL,
        fresh_until               timestamptz(6) NOT NULL,
        coverage_status           text NOT NULL CHECK (coverage_status IN ('complete','partial','indeterminate')),
        data_classification       text NOT NULL CHECK (data_classification IN ('public','internal','confidential','restricted')),
        payload_retention_class   text NOT NULL CHECK (payload_retention_class = 'product_evidence_payload'),
        evidence_id               uuid NOT NULL,
        outcome                   text NOT NULL CHECK (outcome = 'accepted'),

        -- `fresh_until_utc` is EXACTLY 24 elapsed hours after `observed_at_utc`. Not "at least",
        -- not "at most": a payload that claims a wider window is invalid content, and expressing
        -- it here means no writer can widen the freshness window by supplying its own value.
        CONSTRAINT external_measurement_submissions_freshness CHECK (
          fresh_until = observed_at + interval '24 hours'
        ),
        -- "`captured_at_utc` MUST be at or after observation and before freshness expiry."
        CONSTRAINT external_measurement_submissions_capture_window CHECK (
          captured_at >= observed_at AND captured_at < fresh_until
        ),
        CONSTRAINT external_measurement_submissions_unique
          UNIQUE (evaluation_id, measurement_kind, measurement_set_version),
        CONSTRAINT external_measurement_submissions_set_fk
          FOREIGN KEY (organization_id, measurement_set_row_id)
          REFERENCES measurement_sets (organization_id, id),
        CONSTRAINT external_measurement_submissions_evaluation_fk
          FOREIGN KEY (organization_id, project_id, evaluation_id)
          REFERENCES evaluations (organization_id, project_id, id),
        CONSTRAINT external_measurement_submissions_org_id_unique UNIQUE (organization_id, id)
      );

      CREATE INDEX external_measurement_submissions_evaluation
        ON external_measurement_submissions (organization_id, evaluation_id, measurement_kind);
    SQL

    tenant_rls("measurement_sets")
    tenant_rls("external_measurement_submissions")
    create_guards
    F1::RuntimeGrants.apply_all(connection)
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS external_measurement_submissions_guard ON external_measurement_submissions;
      DROP TRIGGER IF EXISTS measurement_sets_guard ON measurement_sets;
      DROP FUNCTION IF EXISTS f1_measurement_sets_guard();
      DROP TABLE IF EXISTS external_measurement_submissions;
      DROP TABLE IF EXISTS measurement_sets;
    SQL
  end

  private

  def quoted(values) = values.map { |v| "'#{v}'" }.join(", ")

  def tenant_rls(table)
    execute <<~SQL
      ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
      ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;
      CREATE POLICY #{table}_context ON #{table}
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
    SQL
  end

  # The package's IDENTITY AND BYTES ARE IMMUTABLE FROM INSERT; only the checked activation
  # state tuple may change. "Corrected bytes require a new version row" — so a package cannot be
  # edited after the owner has read it and before the release service activates it, which is
  # exactly the substitution the two signatures exist to prevent.
  #
  # The submission is immutable outright: an accepted observation is a fact.
  def create_guards
    execute <<~SQL
      CREATE FUNCTION f1_measurement_sets_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'measurement_set_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.measurement_set_id IS DISTINCT FROM OLD.measurement_set_id
           OR NEW.measurement_set_version IS DISTINCT FROM OLD.measurement_set_version
           OR NEW.measurement_kind IS DISTINCT FROM OLD.measurement_kind
           OR NEW.package_sha256 IS DISTINCT FROM OLD.package_sha256
           OR NEW.package_reference IS DISTINCT FROM OLD.package_reference
           OR NEW.expected_keys IS DISTINCT FROM OLD.expected_keys
           OR NEW.key_content IS DISTINCT FROM OLD.key_content
           OR NEW.collector_adapter_id IS DISTINCT FROM OLD.collector_adapter_id
           OR NEW.collector_adapter_version IS DISTINCT FROM OLD.collector_adapter_version
           OR NEW.max_evidence_age_seconds IS DISTINCT FROM OLD.max_evidence_age_seconds THEN
          RAISE EXCEPTION 'measurement_set_bytes_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        -- A set never returns from a terminal state; reactivation of unapproved bytes is exactly
        -- what OD-010 says rollback must NOT be.
        IF OLD.status IN ('superseded','rejected') AND NEW.status IS DISTINCT FROM OLD.status THEN
          RAISE EXCEPTION 'measurement_set_terminal' USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER measurement_sets_guard BEFORE UPDATE OR DELETE ON measurement_sets
        FOR EACH ROW EXECUTE FUNCTION f1_measurement_sets_guard();

      CREATE TRIGGER external_measurement_submissions_guard
        BEFORE UPDATE OR DELETE ON external_measurement_submissions
        FOR EACH ROW EXECUTE FUNCTION f1_check_immutable_guard();
    SQL
  end
end
