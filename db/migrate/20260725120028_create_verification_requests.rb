# frozen_string_literal: true

# S-05 Ownership Verification, first limb — the Verification Request aggregate
# (schemas/POSTGRESQL_SCHEMA.md :287 the canonical `verification_requests` table;
# SCORE_EVIDENCE_MODEL.md § Ownership-Verification Evidence Contract → Verification
# Request; APPLICATION_LAYER.md § WF-003; contracts/S-05.json MTX-028/MTX-071).
#
# A Verification Request is its own aggregate root (S-05.json aggregate), owned by a
# Source (which is owned by a Project). Following the Project-owned tenancy rule
# (POSTGRESQL_SCHEMA.md :128) it carries `organization_id`/`project_id` NOT NULL and
# its direct Source reference is the composite `(organization_id, project_id,
# source_id) -> sources (organization_id, project_id, id)`, so a same-Organization
# cross-Project link — or a Request against a Source in another Organization — is
# refused by the database rather than an application assertion.
#
# This migration adds ONLY the IssueVerificationChallenge limb: one Request is
# created in `pending` with its immutable issuance facts and its challenge material
# stored behind F-02 envelope encryption (only the ciphertext reference, key
# reference and the token digest are columns; the plaintext token is never a
# column). The `method` CHECK makes an unsupported method unrepresentable
# (PRULE-020, MTX-071). The partial unique index over a pending Request per Source
# is the concurrency control that makes `verification_in_progress` a database fact
# rather than an advisory hint (S-05.json concurrency/migration).
#
# No observation, expiry, cancellation, failure or cryptographic-deletion path
# exists yet: those are the later S-05 limbs (Reserve/Complete/Expire/Cancel/Fail
# and ChallengeCryptographicDeletion). So `verification_attempts` and the
# scope/source-set tables are NOT created here, and the lifecycle guard freezes the
# issuance facts and refuses every `request_status` transition until each of those
# slices lands and relaxes exactly its ratified edge — the same discipline the
# `sources` guard uses for the Source lifecycle.
class CreateVerificationRequests < ActiveRecord::Migration[8.1]
  def up
    create_verification_requests
    create_lifecycle_guard
  end

  def down
    execute "DROP TRIGGER IF EXISTS verification_requests_lifecycle_guard ON verification_requests;"
    execute "DROP FUNCTION IF EXISTS f1_verification_requests_lifecycle_guard();"
    execute "DROP TABLE IF EXISTS verification_requests;"
  end

  private

  def create_verification_requests
    execute <<~SQL
      CREATE TABLE verification_requests (
        id                                 uuid PRIMARY KEY,
        state_version                      bigint NOT NULL DEFAULT 0,
        lock_version                       bigint NOT NULL DEFAULT 0,
        created_at                         timestamptz(6) NOT NULL,
        updated_at                         timestamptz(6) NOT NULL,
        correlation_id                     uuid NOT NULL,
        schema_version                     text NOT NULL
          CHECK (schema_version = 'verification-request-v1'),
        organization_id                    uuid NOT NULL,
        project_id                         uuid NOT NULL,
        source_id                          uuid NOT NULL,
        request_initiator_account_id       uuid NOT NULL,
        method                             text NOT NULL
          CHECK (method IN ('dns_txt','http_file')),
        canonical_host                     text NOT NULL,
        challenge_token_sha256             bytea NOT NULL
          CHECK (octet_length(challenge_token_sha256) = 32),
        -- The challenge material lives behind F-02 (Platform::Encryption): only the
        -- opaque ciphertext reference and the protection-profile key reference are
        -- stored, both restricted, and both NULLABLE only after terminal
        -- cryptographic deletion (a later limb). A pending Request must always carry
        -- both (enforced below), so no pending Request can exist without recoverable
        -- challenge material.
        challenge_ciphertext_reference     uuid,
        challenge_key_id                   text,
        initial_challenge_delivered_at_utc timestamptz(6) NOT NULL,
        issued_at_utc                      timestamptz(6) NOT NULL,
        expires_at_utc                     timestamptz(6) NOT NULL,
        idempotency_key_digest             bytea NOT NULL
          CHECK (octet_length(idempotency_key_digest) = 32),
        request_status                     text NOT NULL
          CHECK (request_status IN ('pending','verified','expired','canceled','failed')),
        attempt_count                      integer NOT NULL DEFAULT 0
          CHECK (attempt_count >= 0),
        on_demand_observation_count        integer NOT NULL DEFAULT 0
          CHECK (on_demand_observation_count BETWEEN 0 AND 10),
        on_demand_in_progress_attempt_id   uuid,
        last_on_demand_completed_at_utc    timestamptz(6),
        last_observed_at_utc               timestamptz(6),
        decision_reason_code               text,
        -- A pending Request carries no decision reason and MUST retain recoverable
        -- challenge material; both are load-bearing invariants of the issuance limb.
        -- The challenge is valid for exactly 24 hours (SCORE_EVIDENCE_MODEL.md;
        -- CAP-005 Failure Condition). Named because it spans two columns.
        CONSTRAINT verification_requests_expires_at_utc_is_24h
          CHECK (expires_at_utc = issued_at_utc + interval '24 hours'),
        CONSTRAINT verification_requests_pending_reason_null
          CHECK (request_status <> 'pending' OR decision_reason_code IS NULL),
        CONSTRAINT verification_requests_pending_has_challenge
          CHECK (request_status <> 'pending'
                 OR (challenge_ciphertext_reference IS NOT NULL AND challenge_key_id IS NOT NULL)),
        CONSTRAINT verification_requests_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT verification_requests_source_fk
          FOREIGN KEY (organization_id, project_id, source_id)
          REFERENCES sources (organization_id, project_id, id)
      );
      -- At most one pending Verification Request per Source (S-05.json concurrency):
      -- the losing racer observes the winner's committed pending Request and is
      -- refused `verification_in_progress` before any token is issued.
      CREATE UNIQUE INDEX verification_requests_one_pending_per_source
        ON verification_requests (organization_id, project_id, source_id)
        WHERE request_status = 'pending';
    SQL
    force_rls("verification_requests", using: "organization_id = f1_current_context_org()")
  end

  # The issuance facts are the Request's immutable provenance, and no lifecycle
  # transition exists in this baseline. Both are database properties, mirroring the
  # `sources` lifecycle guard.
  def create_lifecycle_guard
    execute <<~SQL
      CREATE FUNCTION f1_verification_requests_lifecycle_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        -- The tenant, Project and Source a Request belongs to are fixed for life.
        IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.source_id IS DISTINCT FROM OLD.source_id THEN
          RAISE EXCEPTION 'verification_request_tenant_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        -- The issuance facts (method, canonical host, challenge digest, initiator,
        -- issued/expiry instants, idempotency provenance and schema) are frozen at
        -- creation. The challenge digest in particular MUST survive the later
        -- cryptographic deletion of the ciphertext (SCORE_EVIDENCE_MODEL.md: "the
        -- digest and access audit remain").
        IF NEW.schema_version IS DISTINCT FROM OLD.schema_version
           OR NEW.request_initiator_account_id IS DISTINCT FROM OLD.request_initiator_account_id
           OR NEW.method IS DISTINCT FROM OLD.method
           OR NEW.canonical_host IS DISTINCT FROM OLD.canonical_host
           OR NEW.challenge_token_sha256 IS DISTINCT FROM OLD.challenge_token_sha256
           OR NEW.idempotency_key_digest IS DISTINCT FROM OLD.idempotency_key_digest
           OR NEW.initial_challenge_delivered_at_utc IS DISTINCT FROM OLD.initial_challenge_delivered_at_utc
           OR NEW.issued_at_utc IS DISTINCT FROM OLD.issued_at_utc
           OR NEW.expires_at_utc IS DISTINCT FROM OLD.expires_at_utc THEN
          RAISE EXCEPTION 'verification_request_issuance_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        -- Request lifecycle transitions are owned by the later S-05 limbs
        -- (observation completion -> verified; the expiry job -> expired;
        -- cancellation -> canceled; the integrity service -> failed) and the
        -- cryptographic-deletion limb (which nulls the challenge material). None is
        -- built. No path may change a Request's status in this baseline; each of
        -- those slices will relax exactly its ratified edge.
        IF NEW.request_status IS DISTINCT FROM OLD.request_status THEN
          RAISE EXCEPTION 'verification_request_transition_unavailable % -> %', OLD.request_status, NEW.request_status
            USING ERRCODE = 'raise_exception';
        END IF;

        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER verification_requests_lifecycle_guard BEFORE UPDATE ON verification_requests
        FOR EACH ROW EXECUTE FUNCTION f1_verification_requests_lifecycle_guard();
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
