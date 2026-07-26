# frozen_string_literal: true

# S-05 Ownership Verification, observation-reservation limb — the
# `verification_attempts` table (schemas/POSTGRESQL_SCHEMA.md :288 the canonical
# `verification_attempts` T-MUT/LINEAGE/WORK-CLAIM table; SCORE_EVIDENCE_MODEL.md
# § Attempts, Expiry, And Evidence; contracts/S-05.json MTX-028; APPLICATION_LAYER.md
# § WF-003 Reserve/Complete).
#
# A Verification Attempt is a child of the `verification_requests` aggregate root: one
# provider observation of a Request's ownership challenge. It is created in `reserved`
# by `ReserveVerificationAttempt` (this tranche, on-demand path) and later transitions
# reserved -> running -> completed (or quarantined) when the observation runs and its
# outcome is recorded — those transitions are the S-05-005 CompleteVerificationAttempt
# limb, not built here. So this migration creates ONLY the reservation baseline:
#
# - The lineage is fixed at reservation: tenant (organization/project), the parent
#   Request, the Source, the `attempt_number`, the `origin` (automated/on_demand) and,
#   for an automated attempt, its slot offset. Following the Project-owned tenancy rule
#   (POSTGRESQL_SCHEMA.md :128) the row carries `organization_id`/`project_id` NOT NULL
#   and composite foreign keys `(organization_id, verification_request_id) ->
#   verification_requests (organization_id, id)` and `(organization_id, project_id,
#   source_id) -> sources (organization_id, project_id, id)`, so a cross-tenant or
#   cross-Project attempt is refused by the database rather than an application check.
# - `unique (verification_request_id, attempt_number)` makes the attempt sequence a
#   database fact: the serialized reservation (advisory lock + Request state-version
#   guard) assigns `attempt_number = attempt_count + 1`, and this index is the backstop
#   that two attempts can never share a number.
# - The observation OUTCOME columns (started/completed/deadline instants, the
#   network/status/byte-count/digest/match/reason fields) are present but a `reserved`
#   attempt must carry NONE of them (the `reserved_has_no_outcome` CHECK); they are
#   written by the completion limb.
#
# The lifecycle guard freezes the reservation lineage and refuses EVERY state
# transition until each later slice relaxes exactly its ratified edge — the same
# discipline the `verification_requests` and `sources` guards use.
class CreateVerificationAttempts < ActiveRecord::Migration[8.1]
  NETWORK_OUTCOMES = %w[response timeout resolver_failure connection_failure tls_failure].freeze
  MATCH_DECISIONS = %w[matched not_matched indeterminate].freeze
  REASON_CODES = %w[
    matched dns_nxdomain dns_value_mismatch dns_timeout dns_temporary_failure
    http_status_mismatch http_content_mismatch http_body_too_large http_redirect_rejected
    http_timeout http_rate_limited http_server_error tls_validation_failed connection_failure
  ].freeze

  def up
    create_verification_attempts
    create_lifecycle_guard
  end

  def down
    execute "DROP TRIGGER IF EXISTS verification_attempts_lifecycle_guard ON verification_attempts;"
    execute "DROP FUNCTION IF EXISTS f1_verification_attempts_lifecycle_guard();"
    execute "DROP TABLE IF EXISTS verification_attempts;"
  end

  private

  def create_verification_attempts
    execute <<~SQL
      CREATE TABLE verification_attempts (
        id                            uuid PRIMARY KEY,
        state_version                 bigint NOT NULL DEFAULT 0,
        lock_version                  bigint NOT NULL DEFAULT 0,
        created_at                    timestamptz(6) NOT NULL,
        updated_at                    timestamptz(6) NOT NULL,
        correlation_id                uuid NOT NULL,
        schema_version                text NOT NULL
          CHECK (schema_version = 'verification-attempt-v1'),
        organization_id               uuid NOT NULL,
        project_id                    uuid NOT NULL,
        verification_request_id       uuid NOT NULL,
        source_id                     uuid NOT NULL,
        -- The attempt's position in the Request's serialized sequence. Assigned as
        -- attempt_count + 1 under the per-Request lock, so it is dense and unique.
        attempt_number                integer NOT NULL
          CHECK (attempt_number > 0),
        -- An automated slot observation or an accepted on-demand attempt. The slot
        -- offset is present exactly for an automated attempt (the S-05-007 schedule);
        -- an on-demand attempt has no slot.
        origin                        text NOT NULL
          CHECK (origin IN ('automated','on_demand')),
        automated_slot_offset_minutes integer,
        reserved_at_utc               timestamptz(6) NOT NULL,
        -- Observation outcome, written only by the completion limb (S-05-005). A
        -- `reserved` attempt carries none of these (enforced below).
        started_at_utc                timestamptz(6),
        completed_at_utc              timestamptz(6),
        deadline_at_utc               timestamptz(6),
        network_outcome               text
          CHECK (network_outcome IS NULL OR network_outcome IN
                 ('response','timeout','resolver_failure','connection_failure','tls_failure')),
        http_status                   integer,
        dns_response_code             text,
        received_byte_count           integer
          CHECK (received_byte_count IS NULL OR received_byte_count >= 0),
        observed_value_sha256         bytea
          CHECK (observed_value_sha256 IS NULL OR octet_length(observed_value_sha256) = 32),
        match_decision                text
          CHECK (match_decision IS NULL OR match_decision IN ('matched','not_matched','indeterminate')),
        reason_code                   text
          CHECK (reason_code IS NULL OR reason_code IN
                 ('matched','dns_nxdomain','dns_value_mismatch','dns_timeout','dns_temporary_failure',
                  'http_status_mismatch','http_content_mismatch','http_body_too_large','http_redirect_rejected',
                  'http_timeout','http_rate_limited','http_server_error','tls_validation_failed','connection_failure')),
        state                         text NOT NULL
          CHECK (state IN ('reserved','running','completed','quarantined')),
        -- The slot offset is present exactly when the attempt is automated.
        CONSTRAINT verification_attempts_slot_offset_matches_origin
          CHECK ((origin = 'automated' AND automated_slot_offset_minutes IS NOT NULL)
                 OR (origin = 'on_demand' AND automated_slot_offset_minutes IS NULL)),
        -- A reserved-but-not-yet-run attempt has started nothing and recorded no
        -- outcome. This is the load-bearing invariant of the reservation limb: the
        -- completion limb (S-05-005) is the only writer of the outcome columns.
        CONSTRAINT verification_attempts_reserved_has_no_outcome
          CHECK (state <> 'reserved'
                 OR (started_at_utc IS NULL AND completed_at_utc IS NULL AND deadline_at_utc IS NULL
                     AND network_outcome IS NULL AND http_status IS NULL AND dns_response_code IS NULL
                     AND received_byte_count IS NULL AND observed_value_sha256 IS NULL
                     AND match_decision IS NULL AND reason_code IS NULL)),
        CONSTRAINT verification_attempts_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT verification_attempts_request_attempt_unique
          UNIQUE (verification_request_id, attempt_number),
        CONSTRAINT verification_attempts_request_fk
          FOREIGN KEY (organization_id, verification_request_id)
          REFERENCES verification_requests (organization_id, id),
        CONSTRAINT verification_attempts_source_fk
          FOREIGN KEY (organization_id, project_id, source_id)
          REFERENCES sources (organization_id, project_id, id)
      );
    SQL
    force_rls("verification_attempts", using: "organization_id = f1_current_context_org()")
  end

  # The reservation lineage is the attempt's immutable provenance, and no lifecycle
  # transition exists in this baseline. Both are database properties, mirroring the
  # `verification_requests` lifecycle guard.
  def create_lifecycle_guard
    execute <<~SQL
      CREATE FUNCTION f1_verification_attempts_lifecycle_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        -- The tenant, Project, parent Request and Source an attempt belongs to are
        -- fixed for life.
        IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.verification_request_id IS DISTINCT FROM OLD.verification_request_id
           OR NEW.source_id IS DISTINCT FROM OLD.source_id THEN
          RAISE EXCEPTION 'verification_attempt_tenant_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        -- The reservation facts (schema, attempt number, origin, slot offset and the
        -- instant it was reserved) are frozen at creation.
        IF NEW.schema_version IS DISTINCT FROM OLD.schema_version
           OR NEW.attempt_number IS DISTINCT FROM OLD.attempt_number
           OR NEW.origin IS DISTINCT FROM OLD.origin
           OR NEW.automated_slot_offset_minutes IS DISTINCT FROM OLD.automated_slot_offset_minutes
           OR NEW.reserved_at_utc IS DISTINCT FROM OLD.reserved_at_utc THEN
          RAISE EXCEPTION 'verification_attempt_reservation_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        -- Attempt lifecycle transitions (reserved -> running -> completed, or
        -- quarantined) are owned by the later observation-completion limb (S-05-005).
        -- None is built. No path may change an attempt's state in this baseline; that
        -- slice will relax exactly its ratified edges.
        IF NEW.state IS DISTINCT FROM OLD.state THEN
          RAISE EXCEPTION 'verification_attempt_transition_unavailable % -> %', OLD.state, NEW.state
            USING ERRCODE = 'raise_exception';
        END IF;

        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER verification_attempts_lifecycle_guard BEFORE UPDATE ON verification_attempts
        FOR EACH ROW EXECUTE FUNCTION f1_verification_attempts_lifecycle_guard();
    SQL
  end

  def force_rls(table, using:, check: nil)
    execute <<~SQL
      ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
      ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;
      CREATE POLICY #{table}_context ON #{table}
        USING (#{using}) WITH CHECK (#{check || using});
      REVOKE ALL ON #{table} FROM PUBLIC;
    SQL
  end
end
