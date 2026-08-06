# frozen_string_literal: true

# THE REST OF `ingestion-interim-v1`'s JOB RECORD (WORKFLOW_SPECIFICATIONS.md :462).
#
# `20260806100000_create_documents_and_ingestion` built the columns schemas/POSTGRESQL_SCHEMA.md
# :303 names. :303 is a SUMMARY of what distinguishes the table — it names neither `state_version`
# nor `correlation_id` either, and both have always been there — while Volume I :462 is the
# authoritative content list, and it names nine members the table does not yet carry:
#
#   "final HTTP status/media type; immutable staged-body reference, received byte count and
#    SHA-256; response-capture policy version; classification; ... nullable resulting Evidence ID;
#    ... idempotency key; queued/started/completed times"
#
# The two agree everywhere they overlap. This adds the members only :462 states, plus the two
# staging-lifecycle columns :466 forces (see STAGING, below), and reconciles :303 in the catalogue.
#
# THE TABLE IS EMPTY BY CONSTRUCTION, which is why NOT NULL is added directly rather than through a
# backfill. It was created two migrations ago on this same unreleased branch and has never had a
# writer: this tranche is the writer, and it is being built now.
#
# STAGING, AND WHY IT IS TWO COLUMNS AND NOT ONE.
#
# :462 — "Staged body bytes are immutable and INACCESSIBLE TO PRODUCT READS."
# :464 — success "deletes the SEPARATE staging reference within 60 seconds".
# :466 — failure "retains inaccessible staging bytes for AT MOST 24 HOURS FROM FETCH COMPLETION,
#        then destroys them; a replay after destruction is `staged_body_missing`".
#
# So a staged body has exactly two states — present, or destroyed — and the destruction instant is
# a fact about the row. `staged_body_reference` NULL means destroyed and `staged_body_destroyed_at`
# says when; the biconditional below makes "NULL because destroyed" and "NULL because never staged"
# impossible to confuse, which is the difference between `staged_body_missing` (a real refusal) and
# a job that was never capable of being ingested at all.
#
# `staging_expires_at` IS IMMUTABLE, AND THAT IS THE POINT. :466's bound is measured "from fetch
# completion", which is a fixed instant per job, so the deadline is stamped once at creation and
# frozen by the guard. FU-30 is the same lesson from `crawls.started_at`/`deadline_at`: a bound an
# UPDATE can move is a bound the holder can renegotiate, and a 24-hour retention limit that the
# retaining party may extend is not a retention limit. Replay does not reset it — :466 says a replay
# after destruction "requires a NEW CRAWL", not a longer window.
#
# THE DURABLE HANDOFF IS A CONSTRAINT, NOT A CONVENTION. MTX-008 persistence_model: "the durable
# handoff record IS the succeeded IngestionJob with its valid `source_document` Evidence", and :464:
# "No Document may become ingested or enter the parse manifest WITHOUT that valid Evidence."
# `ingestion_jobs_succeeded_carries_evidence` is that sentence as a CHECK, so a succeeded job
# without its Evidence is unrepresentable rather than merely unwritten — which is what makes S-08's
# parse manifest ("every Document whose IngestionJob reached `succeeded`", :472) safe to read
# without re-validating each one.
class IngestionJobCaptureContract < ActiveRecord::Migration[8.1]
  CLASSIFICATIONS = %w[public internal confidential restricted].freeze

  def up
    execute <<~SQL
      ALTER TABLE ingestion_jobs
        -- :462 "final HTTP status/media type". The status is the FINAL one after redirects, which
        -- is the response the body came from; a 3xx here would name a hop rather than a response.
        ADD COLUMN final_http_status integer NOT NULL
          CHECK (final_http_status BETWEEN 200 AND 299),
        ADD COLUMN media_type text NOT NULL
          CHECK (length(media_type) BETWEEN 1 AND 255),

        -- :462 "immutable staged-body reference ... and received byte count". The reference is an
        -- F-02 encrypted-record capability (see the ADR): holding it is the only way to reach the
        -- bytes, there is no product read path to them, and `Platform::Encryption.erase` is the
        -- destruction :464 and :466 both require.
        ADD COLUMN staged_body_reference uuid,
        ADD COLUMN staged_body_destroyed_at timestamptz(6),
        ADD COLUMN staging_expires_at timestamptz(6) NOT NULL,
        ADD COLUMN received_byte_count bigint NOT NULL CHECK (received_byte_count >= 0),

        -- :462 "response-capture policy version". The policy that governed what was captured from
        -- the response — the per-URL body ceiling, the sentinel rule, the request timeout and the
        -- accepted media types — is `crawl-policy-v1`, which is where all four are ratified
        -- (:425-438, :436, :442). Recorded rather than assumed so a later capture policy is a
        -- readable difference between two jobs.
        ADD COLUMN response_capture_policy_version text NOT NULL
          CHECK (length(response_capture_policy_version) BETWEEN 1 AND 120),

        -- :462 "classification". SCORE_EVIDENCE_MODEL.md's ladder, and the same vocabulary the
        -- Evidence envelope carries, because the Evidence this job produces inherits it.
        ADD COLUMN data_classification text NOT NULL
          CHECK (data_classification IN #{list(CLASSIFICATIONS)}),

        -- :462 "nullable resulting Evidence ID". Null until the job succeeds; :128's three-column
        -- link is impossible here because `evidence` is Source-scoped rather than Project-scoped,
        -- so the two-column tenancy link is the widest arity the parent offers.
        ADD COLUMN evidence_id uuid,

        -- :462 "idempotency key". The job's own, distinct from any delivery's: :462 keys the job on
        -- the fetched body, so an exact fetch replay "returns the same job".
        ADD COLUMN idempotency_key text NOT NULL
          CHECK (length(idempotency_key) BETWEEN 1 AND 200),

        -- :462 "queued/started/completed times".
        ADD COLUMN queued_at timestamptz(6) NOT NULL,
        ADD COLUMN started_at timestamptz(6),
        ADD COLUMN completed_at timestamptz(6),

        -- DESTROYED AND NEVER-STAGED ARE DIFFERENT FACTS. A reference is present, or it was
        -- destroyed at a recorded instant. Nothing else is representable.
        ADD CONSTRAINT ingestion_jobs_staging_shape CHECK (
          (staged_body_reference IS NOT NULL AND staged_body_destroyed_at IS NULL)
          OR (staged_body_reference IS NULL AND staged_body_destroyed_at IS NOT NULL)
        ),

        -- THE DURABLE HANDOFF (MTX-008; :464 "No Document may become ingested ... without that
        -- valid Evidence"). A succeeded job carries its Evidence and its completion instant, both.
        ADD CONSTRAINT ingestion_jobs_succeeded_carries_evidence CHECK (
          state <> 'succeeded' OR (evidence_id IS NOT NULL AND completed_at IS NOT NULL)
        ),
        -- AND ONLY A SUCCEEDED JOB CARRIES ONE. :464 creates the Evidence at success and nowhere
        -- else, so an Evidence ID on a `failed` or `dead_letter` job would be a handoff a parsing
        -- consumer must not observe.
        ADD CONSTRAINT ingestion_jobs_evidence_only_on_success CHECK (
          evidence_id IS NULL OR state = 'succeeded'
        ),
        ADD CONSTRAINT ingestion_jobs_started_before_completed CHECK (
          completed_at IS NULL OR (started_at IS NOT NULL AND started_at <= completed_at)
        ),
        ADD CONSTRAINT ingestion_jobs_evidence_fk
          FOREIGN KEY (organization_id, evidence_id) REFERENCES evidence (organization_id, id);

      -- The ingestion queue's own due index, in the shape `ingestion_jobs_due` already establishes
      -- for `queued`. A dead-lettered job is read by the (unbuilt, S-07-011) replay path and by the
      -- staging sweep, both of which ask "which are past their staging bound".
      CREATE INDEX ingestion_jobs_staging_live ON ingestion_jobs (organization_id, staging_expires_at)
        WHERE staged_body_reference IS NOT NULL;
    SQL

    replace_lifecycle_guard
    F1::RuntimeGrants.apply_all(connection)
  end

  # The guard `20260806100000` installed, extended over the columns this migration adds. Rewritten
  # whole with CREATE OR REPLACE rather than layered with a second trigger: one lifecycle, one
  # guard, so the admitted edges are readable in one place.
  #
  # THREE NEW RULES, EACH ONE A SENTENCE FROM :462 OR :464.
  #
  #   1. THE CAPTURE IS IDENTITY. ":462 — Staged body bytes are IMMUTABLE"; the status, media type,
  #      byte count, digest, capture policy and classification all describe the one response this
  #      job exists to ingest, and a job whose description of its own input can change is a job
  #      whose Evidence provenance means nothing.
  #   2. THE STAGED REFERENCE ONLY EVER GOES AWAY. Present -> destroyed is the whole lifecycle
  #      (:464's 60-second deletion, :466's 24-hour destruction). Re-staging would give a replay
  #      different bytes under the same digest, and pointing it elsewhere is the same thing with an
  #      extra step.
  #   3. THE EVIDENCE LINK IS WRITE-ONCE. ":464 — Success ATOMICALLY creates ONE immutable
  #      `source_document` Evidence"; re-pointing a succeeded job at a second Evidence record is how
  #      a sealed Evaluation Input Snapshot comes to disagree with the manifest it was derived from
  #      (MTX-008 concurrency: "concurrent completion or replay CANNOT change an earlier snapshot").
  def replace_lifecycle_guard
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_ingestion_jobs_lifecycle_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      DECLARE allowed text[];
      BEGIN
        IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.source_id IS DISTINCT FROM OLD.source_id
           OR NEW.crawl_id IS DISTINCT FROM OLD.crawl_id
           OR NEW.document_id IS DISTINCT FROM OLD.document_id
           OR NEW.canonical_url IS DISTINCT FROM OLD.canonical_url
           OR NEW.fetched_body_sha256 IS DISTINCT FROM OLD.fetched_body_sha256
           OR NEW.ingestion_schema_version IS DISTINCT FROM OLD.ingestion_schema_version
           -- The capture this job describes (rule 1).
           OR NEW.final_http_status IS DISTINCT FROM OLD.final_http_status
           OR NEW.media_type IS DISTINCT FROM OLD.media_type
           OR NEW.received_byte_count IS DISTINCT FROM OLD.received_byte_count
           OR NEW.response_capture_policy_version IS DISTINCT FROM OLD.response_capture_policy_version
           OR NEW.data_classification IS DISTINCT FROM OLD.data_classification
           OR NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key
           OR NEW.queued_at IS DISTINCT FROM OLD.queued_at
           -- :466's bound is measured from fetch completion and is not the holder's to move (FU-30).
           OR NEW.staging_expires_at IS DISTINCT FROM OLD.staging_expires_at THEN
          RAISE EXCEPTION 'ingestion_job_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        -- Rule 2: present -> destroyed, and nothing else.
        IF NEW.staged_body_reference IS DISTINCT FROM OLD.staged_body_reference
           AND NOT (OLD.staged_body_reference IS NOT NULL AND NEW.staged_body_reference IS NULL) THEN
          RAISE EXCEPTION 'ingestion_job_staged_body_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF OLD.staged_body_destroyed_at IS NOT NULL
           AND NEW.staged_body_destroyed_at IS DISTINCT FROM OLD.staged_body_destroyed_at THEN
          RAISE EXCEPTION 'ingestion_job_staged_body_destruction_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        -- Rule 3: write-once.
        IF OLD.evidence_id IS NOT NULL AND NEW.evidence_id IS DISTINCT FROM OLD.evidence_id THEN
          RAISE EXCEPTION 'ingestion_job_evidence_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        -- THE EDGE SET GOVERNS TRANSITIONS; A NON-TRANSITION IS A DIFFERENT RULE.
        --
        -- `20260806100000` evaluated the edge set on EVERY update, so `succeeded -> succeeded` was an
        -- illegal transition — and that made :464's own next sentence unexecutable, because "deletes
        -- the separate staging reference" is an UPDATE of a succeeded row that changes no state. The
        -- first version of this migration inherited the defect and the acceptance chain demonstrated
        -- it twice, on `succeeded` and on `queued`.
        --
        -- THE REPAIR IS NOT TO ADMIT SELF-EDGES. A self-edge in the EDGE SET would let a writer
        -- consume a `state_version` for a transition that did not happen, which is how another
        -- worker's compare-and-set comes to fail for no reason. So a state-preserving update is
        -- admitted and separately required to leave `state_version` alone: the version means "how
        -- many transitions this row has taken", and a non-transition takes none.
        IF NEW.state IS DISTINCT FROM OLD.state THEN
          allowed := CASE OLD.state
                       WHEN 'queued' THEN ARRAY['running']
                       WHEN 'running' THEN ARRAY['succeeded','failed']
                       WHEN 'failed' THEN ARRAY['queued','dead_letter']
                       WHEN 'dead_letter' THEN ARRAY['queued']
                       ELSE ARRAY[]::text[]
                     END;
          IF NOT (NEW.state = ANY (allowed)) THEN
            RAISE EXCEPTION 'ingestion_job_illegal_transition % -> %', OLD.state, NEW.state
              USING ERRCODE = 'raise_exception';
          END IF;
        ELSIF NEW.state_version IS DISTINCT FROM OLD.state_version THEN
          RAISE EXCEPTION 'ingestion_job_state_version_without_transition'
            USING ERRCODE = 'raise_exception';
        END IF;

        IF OLD.state = 'dead_letter' AND NEW.state = 'queued' THEN
          IF NEW.replay_generation IS DISTINCT FROM OLD.replay_generation + 1 THEN
            RAISE EXCEPTION 'ingestion_job_replay_generation_not_incremented'
              USING ERRCODE = 'raise_exception';
          END IF;
        ELSIF NEW.replay_generation IS DISTINCT FROM OLD.replay_generation THEN
          RAISE EXCEPTION 'ingestion_job_replay_generation_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        RETURN NEW;
      END;
      $$;
    SQL
  end

  def down
    execute <<~SQL
      DROP INDEX IF EXISTS ingestion_jobs_staging_live;
      ALTER TABLE ingestion_jobs
        DROP CONSTRAINT IF EXISTS ingestion_jobs_evidence_fk,
        DROP CONSTRAINT IF EXISTS ingestion_jobs_started_before_completed,
        DROP CONSTRAINT IF EXISTS ingestion_jobs_evidence_only_on_success,
        DROP CONSTRAINT IF EXISTS ingestion_jobs_succeeded_carries_evidence,
        DROP CONSTRAINT IF EXISTS ingestion_jobs_staging_shape,
        DROP COLUMN IF EXISTS completed_at,
        DROP COLUMN IF EXISTS started_at,
        DROP COLUMN IF EXISTS queued_at,
        DROP COLUMN IF EXISTS idempotency_key,
        DROP COLUMN IF EXISTS evidence_id,
        DROP COLUMN IF EXISTS data_classification,
        DROP COLUMN IF EXISTS response_capture_policy_version,
        DROP COLUMN IF EXISTS received_byte_count,
        DROP COLUMN IF EXISTS staging_expires_at,
        DROP COLUMN IF EXISTS staged_body_destroyed_at,
        DROP COLUMN IF EXISTS staged_body_reference,
        DROP COLUMN IF EXISTS media_type,
        DROP COLUMN IF EXISTS final_http_status;
    SQL
  end

  private

  def list(values) = "(#{values.map { |v| "'#{v}'" }.join(',')})"
end
