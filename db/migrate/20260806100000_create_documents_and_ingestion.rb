# frozen_string_literal: true

# S-07-010's three product tables: the Document a crawl produces, the Ingestion Job that produces it,
# and that job's attempt history (schemas/POSTGRESQL_SCHEMA.md :302, :303, :304).
#
# WHAT THIS SLICE OWNS AND WHAT IT DOES NOT. BUILD_PLAN scopes S-07-010 to "documents +
# ingestion_jobs + ingestion_attempts; IngestionJob lifecycle; F-03 source_document / content_absent
# Evidence (D3 interim, ADR-067); durable handoff", and it ENDS BEFORE the OD-027 withheld limb.
# S-07.json MTX-008 names that limb exactly: "The `unique (parsing_job_id)` constraint that would
# narrow ParsingJob-to-IndexingJob is WITHHELD under OD-027 and MUST NOT be added." No
# `parsing_jobs`, no `indexing_jobs`, no `has_one`, and no such constraint appears here. WF-006 is
# S-08's.
#
# THE LINK S-07-009 LEFT NULL BECOMES REACHABLE. `crawl_terminal_outcomes.document_id` was created
# nullable with its own comment saying why — "S-07-010's. NULL until Documents exist (:301, 'Document
# ID NULL')". This migration is what makes a Document exist. It does NOT retro-constrain that column:
# an outcome recorded before Documents existed is still a valid row, and :301 keeps the link nullable.
#
# OD-015 IS ENFORCED BY OMISSION, WHICH IS THE ONLY WAY A CHECK CAN ENFORCE IT. :302 is emphatic:
# "OD-015 removes `quarantined` and `retired` from the canonical lifecycle under ADR-019, so the check
# MUST NOT recognize either value even as forward-compatible migration shape". A CHECK that admitted
# them "for later" would BE the defect, so the vocabulary below is exactly four values and the guard
# admits exactly three edges.
class CreateDocumentsAndIngestion < ActiveRecord::Migration[8.1]
  # :302 — "The check admits exactly `discovered`, `ingested`, `parsed`, `indexed`."
  DOCUMENT_STATES = %w[discovered ingested parsed indexed].freeze
  # :302 — "The only edges are `discovered -> ingested -> parsed -> indexed`, and `indexed` is
  # terminal." Written as the closed edge set rather than as an ordering, because an ordering admits
  # `discovered -> indexed` and this sentence does not.
  DOCUMENT_EDGES = { "discovered" => %w[ingested], "ingested" => %w[parsed], "parsed" => %w[indexed] }.freeze

  # :303 — the Ingestion Job vocabulary.
  JOB_STATES = %w[queued running succeeded failed dead_letter].freeze
  # :303 — "Authorized replay changes this existing row `dead_letter -> queued`". Everything else is
  # the ordinary attempt cycle. `succeeded` is terminal; `failed` may be retried while attempts remain
  # and is otherwise dead-lettered.
  JOB_EDGES = {
    "queued" => %w[running],
    "running" => %w[succeeded failed],
    "failed" => %w[queued dead_letter],
    "dead_letter" => %w[queued]
  }.freeze

  ATTEMPT_OUTCOMES = %w[succeeded failed].freeze

  INGESTION_SCHEMA_VERSION = "ingestion-interim-v1"

  def up
    execute <<~SQL
      -- ================================================================= documents (:302) T-MUT LINEAGE
      CREATE TABLE documents (
        id                        uuid PRIMARY KEY,
        state_version             bigint NOT NULL DEFAULT 0,
        lock_version              bigint NOT NULL DEFAULT 0,
        schema_version            text NOT NULL,
        created_at                timestamptz(6) NOT NULL,
        updated_at                timestamptz(6) NOT NULL,

        -- LINEAGE (:116).
        correlation_id            uuid NOT NULL,
        causation_id              uuid NOT NULL,
        command_id                uuid,

        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        source_id                 uuid NOT NULL,
        crawl_id                  uuid NOT NULL,

        canonical_url             text NOT NULL CHECK (length(canonical_url) BETWEEN 1 AND 8192),
        canonical_url_sha256      bytea NOT NULL CHECK (octet_length(canonical_url_sha256) = 32),

        -- :302 "positive version". Zero would be indistinguishable from an unset bigint default.
        version                   bigint NOT NULL CHECK (version > 0),
        -- :302 "predecessor ID NULL" — the first version of a URL has none. LINEAGE within one Source.
        predecessor_document_id   uuid,

        -- :302 "fetched object ID, media type, byte size/digest". The bytes live in `stored_objects`;
        -- this row carries the identity and the digest, never the body.
        fetched_object_id         uuid NOT NULL,
        media_type                text NOT NULL CHECK (length(media_type) BETWEEN 1 AND 255),
        byte_size                 bigint NOT NULL CHECK (byte_size >= 0),
        content_sha256            bytea NOT NULL CHECK (octet_length(content_sha256) = 32),

        state                     text NOT NULL CHECK (state IN #{list(DOCUMENT_STATES)}),
        discovered_at             timestamptz(6) NOT NULL,
        ingested_at               timestamptz(6),
        parsed_at                 timestamptz(6),
        indexed_at                timestamptz(6),
        transition_reason_code    text CHECK (transition_reason_code IS NULL
                                              OR transition_reason_code ~ '^[a-z][a-z0-9_]{0,119}$'),

        -- EVERY STATE CARRIES THE TIMESTAMP OF EVERY STATE IT HAS PASSED THROUGH, and none it has not.
        -- The lifecycle is linear, so "has reached `parsed`" and "has a `parsed_at`" are the same
        -- statement and are not allowed to disagree.
        CONSTRAINT documents_lifecycle_times CHECK (
          (state = 'discovered' AND ingested_at IS NULL AND parsed_at IS NULL AND indexed_at IS NULL)
          OR (state = 'ingested'  AND ingested_at IS NOT NULL AND parsed_at IS NULL AND indexed_at IS NULL)
          OR (state = 'parsed'    AND ingested_at IS NOT NULL AND parsed_at IS NOT NULL AND indexed_at IS NULL)
          OR (state = 'indexed'   AND ingested_at IS NOT NULL AND parsed_at IS NOT NULL AND indexed_at IS NOT NULL)
        ),
        -- A Document cannot be its own predecessor, and a predecessor is a DIFFERENT version of the
        -- same URL on the same Source; the composite FK below carries the tenancy half.
        CONSTRAINT documents_predecessor_not_self CHECK (predecessor_document_id IS DISTINCT FROM id),

        -- :302 "unique `(source_id,canonical_url_sha256,version)`".
        CONSTRAINT documents_source_url_version_unique
          UNIQUE (source_id, canonical_url_sha256, version),
        CONSTRAINT documents_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT documents_org_project_id_unique UNIQUE (organization_id, project_id, id),

        -- :128 — every Project-owned link carries all three columns, so a Crawl in Project A cannot
        -- create a Document against Project B's Source. FU-7 records this rule being violated
        -- silently three times; it is easier to satisfy than to detect.
        CONSTRAINT documents_project_fk
          FOREIGN KEY (organization_id, project_id) REFERENCES projects (organization_id, id),
        CONSTRAINT documents_source_fk
          FOREIGN KEY (organization_id, project_id, source_id) REFERENCES sources (organization_id, project_id, id),
        CONSTRAINT documents_crawl_fk
          FOREIGN KEY (organization_id, project_id, crawl_id) REFERENCES crawls (organization_id, project_id, id),
        CONSTRAINT documents_predecessor_fk
          FOREIGN KEY (organization_id, project_id, predecessor_document_id)
          REFERENCES documents (organization_id, project_id, id)
      );

      CREATE INDEX documents_project_state ON documents (organization_id, project_id, state, id);
      CREATE INDEX documents_crawl ON documents (organization_id, crawl_id);

      ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
      ALTER TABLE documents FORCE ROW LEVEL SECURITY;
      CREATE POLICY documents_context ON documents
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());

      -- ============================================================ ingestion_jobs (:303) T-MUT LINEAGE
      CREATE TABLE ingestion_jobs (
        id                        uuid PRIMARY KEY,
        state_version             bigint NOT NULL DEFAULT 0,
        lock_version              bigint NOT NULL DEFAULT 0,
        schema_version            text NOT NULL,
        created_at                timestamptz(6) NOT NULL,
        updated_at                timestamptz(6) NOT NULL,

        correlation_id            uuid NOT NULL,
        causation_id              uuid NOT NULL,
        command_id                uuid,

        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        source_id                 uuid NOT NULL,
        crawl_id                  uuid NOT NULL,
        document_id               uuid NOT NULL,

        canonical_url             text NOT NULL CHECK (length(canonical_url) BETWEEN 1 AND 8192),
        fetched_body_sha256       bytea NOT NULL CHECK (octet_length(fetched_body_sha256) = 32),
        ingestion_schema_version  text NOT NULL
                                  CHECK (ingestion_schema_version = '#{INGESTION_SCHEMA_VERSION}'),

        replay_generation         bigint NOT NULL DEFAULT 0 CHECK (replay_generation >= 0),
        attempt_count             bigint NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
        next_due_at               timestamptz(6),
        deadline_at               timestamptz(6),

        -- :303 — the replay capsule. All seven are NULL before the first replay and are captured
        -- ATOMICALLY with the `dead_letter -> queued` edge. `replay_human_rationale` is a human
        -- sentence and :303 is explicit that it "never enters the Event reason field".
        recovery_source_event_id      uuid,
        recovery_command_id           uuid,
        earlier_terminal_reason_code  text,
        replay_requester_account_id   uuid,
        replay_support_session_id     uuid,
        replay_human_rationale        text CHECK (replay_human_rationale IS NULL
                                                  OR length(replay_human_rationale) BETWEEN 20 AND 2000),
        replay_requested_at           timestamptz(6),

        state                     text NOT NULL CHECK (state IN #{list(JOB_STATES)}),
        last_reason_code          text CHECK (last_reason_code IS NULL
                                              OR last_reason_code ~ '^[a-z][a-z0-9_]{0,119}$'),

        -- ":303 ... all NULL before first replay". One biconditional over the whole capsule rather
        -- than seven independent nullable columns, so a partially-captured replay cannot exist: the
        -- shape a constraint assembled from loose parts admits is exactly the shape review misses.
        CONSTRAINT ingestion_jobs_replay_capsule CHECK (
          (replay_generation = 0
             AND recovery_source_event_id IS NULL AND recovery_command_id IS NULL
             AND earlier_terminal_reason_code IS NULL AND replay_requester_account_id IS NULL
             AND replay_support_session_id IS NULL AND replay_human_rationale IS NULL
             AND replay_requested_at IS NULL)
          OR
          (replay_generation > 0
             AND recovery_source_event_id IS NOT NULL AND recovery_command_id IS NOT NULL
             AND earlier_terminal_reason_code IS NOT NULL AND replay_requester_account_id IS NOT NULL
             AND replay_human_rationale IS NOT NULL AND replay_requested_at IS NOT NULL)
        ),

        -- :303 "unique `(crawl_id,source_id,canonical_url,fetched_body_sha256,ingestion_schema_version)`".
        -- Replay REUSES this row, so the key stays unique across replay generations by construction.
        CONSTRAINT ingestion_jobs_identity_unique
          UNIQUE (crawl_id, source_id, canonical_url, fetched_body_sha256, ingestion_schema_version),
        CONSTRAINT ingestion_jobs_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT ingestion_jobs_org_project_id_unique UNIQUE (organization_id, project_id, id),

        CONSTRAINT ingestion_jobs_project_fk
          FOREIGN KEY (organization_id, project_id) REFERENCES projects (organization_id, id),
        CONSTRAINT ingestion_jobs_source_fk
          FOREIGN KEY (organization_id, project_id, source_id) REFERENCES sources (organization_id, project_id, id),
        CONSTRAINT ingestion_jobs_crawl_fk
          FOREIGN KEY (organization_id, project_id, crawl_id) REFERENCES crawls (organization_id, project_id, id),
        CONSTRAINT ingestion_jobs_document_fk
          FOREIGN KEY (organization_id, project_id, document_id) REFERENCES documents (organization_id, project_id, id)
      );

      CREATE INDEX ingestion_jobs_due ON ingestion_jobs (organization_id, state, next_due_at)
        WHERE state = 'queued';
      CREATE INDEX ingestion_jobs_document ON ingestion_jobs (organization_id, document_id);

      ALTER TABLE ingestion_jobs ENABLE ROW LEVEL SECURITY;
      ALTER TABLE ingestion_jobs FORCE ROW LEVEL SECURITY;
      CREATE POLICY ingestion_jobs_context ON ingestion_jobs
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());

      -- ================================== ingestion_attempts (:304) T-CHK LINEAGE WORK-CLAIM
      CREATE TABLE ingestion_attempts (
        id                        uuid PRIMARY KEY,
        checkpoint_version        bigint NOT NULL DEFAULT 0,
        lock_version              bigint NOT NULL DEFAULT 0,
        schema_version            text NOT NULL,
        created_at                timestamptz(6) NOT NULL,
        updated_at                timestamptz(6) NOT NULL,

        correlation_id            uuid NOT NULL,
        causation_id              uuid NOT NULL,
        command_id                uuid,

        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        ingestion_job_id          uuid NOT NULL,

        -- :304 "immutable job/attempt/input identity".
        attempt_number            integer NOT NULL CHECK (attempt_number > 0),
        replay_generation         bigint NOT NULL DEFAULT 0 CHECK (replay_generation >= 0),
        input_sha256              bytea NOT NULL CHECK (octet_length(input_sha256) = 32),

        -- WORK-CLAIM, in the shape `fetch_attempts` already establishes.
        claim_owner               uuid,
        claim_generation          bigint NOT NULL DEFAULT 0,
        claimed_at                timestamptz(6),
        lease_expires_at          timestamptz(6),
        last_heartbeat_at         timestamptz(6),

        -- :304 "scheduled/started/completed/deadline checkpoints".
        scheduled_at              timestamptz(6) NOT NULL,
        started_at                timestamptz(6),
        completed_at              timestamptz(6),
        deadline_at               timestamptz(6) NOT NULL,

        -- :304 "output object/digests NULL until terminal, outcome/reason".
        output_object_id          uuid,
        output_sha256             bytea CHECK (output_sha256 IS NULL OR octet_length(output_sha256) = 32),
        outcome                   text CHECK (outcome IS NULL OR outcome IN #{list(ATTEMPT_OUTCOMES)}),
        reason_code               text CHECK (reason_code IS NULL
                                              OR reason_code ~ '^[a-z][a-z0-9_]{0,119}$'),

        -- ":304 output object/digests NULL UNTIL TERMINAL" as a biconditional: an attempt that has
        -- not completed has no output and no outcome, and a completed one has an outcome and a
        -- completion instant. A failed attempt has a reason; a succeeded one has an output.
        CONSTRAINT ingestion_attempts_terminal_shape CHECK (
          (outcome IS NULL AND completed_at IS NULL
             AND output_object_id IS NULL AND output_sha256 IS NULL AND reason_code IS NULL)
          OR
          (outcome = 'succeeded' AND completed_at IS NOT NULL
             AND output_object_id IS NOT NULL AND output_sha256 IS NOT NULL)
          OR
          (outcome = 'failed' AND completed_at IS NOT NULL
             AND output_object_id IS NULL AND output_sha256 IS NULL AND reason_code IS NOT NULL)
        ),
        CONSTRAINT ingestion_attempts_started_before_completed CHECK (
          completed_at IS NULL OR (started_at IS NOT NULL AND started_at <= completed_at)
        ),

        -- :304 "unique `(ingestion_job_id,attempt_number)`".
        CONSTRAINT ingestion_attempts_number_unique UNIQUE (ingestion_job_id, attempt_number),
        CONSTRAINT ingestion_attempts_org_id_unique UNIQUE (organization_id, id),

        CONSTRAINT ingestion_attempts_project_fk
          FOREIGN KEY (organization_id, project_id) REFERENCES projects (organization_id, id),
        CONSTRAINT ingestion_attempts_job_fk
          FOREIGN KEY (organization_id, project_id, ingestion_job_id)
          REFERENCES ingestion_jobs (organization_id, project_id, id)
      );

      CREATE INDEX ingestion_attempts_job ON ingestion_attempts
        (organization_id, ingestion_job_id, attempt_number);

      ALTER TABLE ingestion_attempts ENABLE ROW LEVEL SECURITY;
      ALTER TABLE ingestion_attempts FORCE ROW LEVEL SECURITY;
      CREATE POLICY ingestion_attempts_context ON ingestion_attempts
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
    SQL

    add_document_guard
    add_ingestion_job_guard
    add_ingestion_attempt_guard
    close_after_terminal

    F1::RuntimeGrants.apply_all(connection)
  end

  # OWNER RULING 2: A POST-TERMINAL CHILD FACT IS A DATA-INTEGRITY VIOLATION.
  #
  # `crawl_terminal_fact_closure_spec.rb`'s PROOF 156 DERIVES every table carrying a foreign key to
  # `crawls` and requires each to be either closed on INSERT or recorded as deliberately ungoverned
  # with a reason. It caught both of these tables the moment they existed, which is the check working:
  # a new child table must be CLASSIFIED rather than defaulted.
  #
  # BOTH ARE CLOSED, NOT EXCUSED. A Document is the coverage-bearing product of a run — :452 makes "an
  # admitted content URL has a COVERED outcome ONLY when it creates a valid Document" — so a Document
  # appearing for a Crawl that has already terminalised would change that run's coverage after the
  # run was decided. An Ingestion Job is created with its Document and carries the same run identity.
  # Neither belongs to the excused categories: they are not reservation bookkeeping, not written
  # before a terminal state is reachable, and not another workflow's lifecycle.
  #
  # THE CLOSURE IS ON INSERT ONLY, WHICH IS THE POINT. Ingestion EXECUTES after the crawl ends — that
  # is what the durable handoff is — so the job's later `queued -> running -> succeeded` UPDATEs must
  # remain legal. What may not happen is a NEW row appearing against a finished run.
  def close_after_terminal
    execute <<~SQL
      CREATE TRIGGER documents_terminal_closure AFTER INSERT ON documents
        FOR EACH ROW EXECUTE FUNCTION f1_crawl_child_fact_closed();
      CREATE TRIGGER ingestion_jobs_terminal_closure AFTER INSERT ON ingestion_jobs
        FOR EACH ROW EXECUTE FUNCTION f1_crawl_child_fact_closed();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS ingestion_jobs_terminal_closure ON ingestion_jobs;
      DROP TRIGGER IF EXISTS documents_terminal_closure ON documents;
      DROP TRIGGER IF EXISTS ingestion_attempts_guard ON ingestion_attempts;
      DROP FUNCTION IF EXISTS f1_ingestion_attempts_guard();
      DROP TRIGGER IF EXISTS ingestion_jobs_lifecycle_guard ON ingestion_jobs;
      DROP FUNCTION IF EXISTS f1_ingestion_jobs_lifecycle_guard();
      DROP TRIGGER IF EXISTS documents_lifecycle_guard ON documents;
      DROP FUNCTION IF EXISTS f1_documents_lifecycle_guard();
      DROP TABLE IF EXISTS ingestion_attempts;
      DROP TABLE IF EXISTS ingestion_jobs;
      DROP TABLE IF EXISTS documents;
    SQL
  end

  private

  def list(values) = "(#{values.map { |v| "'#{v}'" }.join(',')})"

  # The edge map, rendered as a plpgsql CASE that returns the admitted successors of OLD.state.
  def edge_case(edges)
    body = edges.map { |from, tos| "WHEN '#{from}' THEN ARRAY[#{tos.map { |t| "'#{t}'" }.join(',')}]" }
    "CASE OLD.state #{body.join(' ')} ELSE ARRAY[]::text[] END"
  end

  # :302 — "The only edges are `discovered -> ingested -> parsed -> indexed`, and `indexed` is
  # terminal. A Document leaves product use only through the separate retention and deletion
  # lifecycle, which destroys the row rather than transitioning it." So DELETE is permitted (that is
  # the deletion lifecycle's edge) and every other transition is refused, including a self-edge:
  # `discovered -> discovered` is not a state change and must not consume a state version.
  def add_document_guard
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_documents_lifecycle_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      DECLARE allowed text[];
      BEGIN
        IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.source_id IS DISTINCT FROM OLD.source_id
           OR NEW.crawl_id IS DISTINCT FROM OLD.crawl_id
           OR NEW.canonical_url IS DISTINCT FROM OLD.canonical_url
           OR NEW.canonical_url_sha256 IS DISTINCT FROM OLD.canonical_url_sha256
           OR NEW.version IS DISTINCT FROM OLD.version
           OR NEW.predecessor_document_id IS DISTINCT FROM OLD.predecessor_document_id
           OR NEW.fetched_object_id IS DISTINCT FROM OLD.fetched_object_id
           OR NEW.content_sha256 IS DISTINCT FROM OLD.content_sha256
           OR NEW.byte_size IS DISTINCT FROM OLD.byte_size
           OR NEW.media_type IS DISTINCT FROM OLD.media_type
           OR NEW.discovered_at IS DISTINCT FROM OLD.discovered_at THEN
          RAISE EXCEPTION 'document_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        allowed := #{edge_case(DOCUMENT_EDGES)};
        IF NOT (NEW.state = ANY (allowed)) THEN
          RAISE EXCEPTION 'document_illegal_transition % -> %', OLD.state, NEW.state
            USING ERRCODE = 'raise_exception';
        END IF;

        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER documents_lifecycle_guard BEFORE UPDATE ON documents
        FOR EACH ROW EXECUTE FUNCTION f1_documents_lifecycle_guard();
    SQL
  end

  # :303 — the job's identity is frozen, its lifecycle is the closed edge set, and the replay edge
  # "increments replay generation EXACTLY ONCE". The trigger enforces the increment rather than
  # trusting the writer, because "exactly once" is the property a retry or a double-apply breaks.
  def add_ingestion_job_guard
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
           OR NEW.ingestion_schema_version IS DISTINCT FROM OLD.ingestion_schema_version THEN
          RAISE EXCEPTION 'ingestion_job_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        allowed := #{edge_case(JOB_EDGES)};
        IF NOT (NEW.state = ANY (allowed)) THEN
          RAISE EXCEPTION 'ingestion_job_illegal_transition % -> %', OLD.state, NEW.state
            USING ERRCODE = 'raise_exception';
        END IF;

        -- THE REPLAY GENERATION MOVES ON EXACTLY ONE EDGE, AND BY EXACTLY ONE. :303 — "Authorized
        -- replay changes this existing row `dead_letter -> queued`, increments replay generation
        -- exactly once". Any other edge must leave it alone; that edge must advance it by one.
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
      CREATE TRIGGER ingestion_jobs_lifecycle_guard BEFORE UPDATE ON ingestion_jobs
        FOR EACH ROW EXECUTE FUNCTION f1_ingestion_jobs_lifecycle_guard();
    SQL
  end

  # T-CHK: an attempt is insert-then-terminalise. Its identity and its recorded outcome are both
  # write-once — a terminal attempt is a fact, and re-deciding one is how two readers disagree about
  # what happened.
  def add_ingestion_attempt_guard
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_ingestion_attempts_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.ingestion_job_id IS DISTINCT FROM OLD.ingestion_job_id
           OR NEW.attempt_number IS DISTINCT FROM OLD.attempt_number
           OR NEW.replay_generation IS DISTINCT FROM OLD.replay_generation
           OR NEW.input_sha256 IS DISTINCT FROM OLD.input_sha256
           OR NEW.scheduled_at IS DISTINCT FROM OLD.scheduled_at THEN
          RAISE EXCEPTION 'ingestion_attempt_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;

        IF OLD.outcome IS NOT NULL THEN
          RAISE EXCEPTION 'ingestion_attempt_terminal' USING ERRCODE = 'raise_exception';
        END IF;

        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER ingestion_attempts_guard BEFORE UPDATE ON ingestion_attempts
        FOR EACH ROW EXECUTE FUNCTION f1_ingestion_attempts_guard();
    SQL
  end
end
