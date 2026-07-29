# frozen_string_literal: true

# S-07-007 fetch attempt record.
#
# CANONICAL AUTHORITY IS `schemas/POSTGRESQL_SCHEMA.md` :298. The first draft of this table was built
# from SEARCH_CRAWL_RETRIEVAL.md's one-line summary ("immutable attempt identity/input plus mutable
# write-once checkpoint/result columns") and the ADR-026 schema lens caught that :298 is considerably
# stricter. It types the table `T-CHK`, `LINEAGE`, `WORK-CLAIM` and requires:
#
#   Crawl/host-gate/Source IDs; `request_kind CHECK ('robots','sitemap','content')`; frontier ID is
#   null only for robots and nonnull otherwise; attempt number and immutable canonical
#   URL/schedule/input/pin/policy values; prepared/submission-started/completed/deadline
#   checkpoints; reserved/accounted/expanded/limit-probe bytes, HTTP/media/redirect/object and
#   normalized robots decision digest NULL until terminal, outcome/reason;
#   `UNIQUE NULLS NOT DISTINCT (crawl_host_gate_id,request_kind,crawl_frontier_entry_id,attempt_number)`
#
# Three of those omissions were live defects, not pedantry:
#
#   * `UNIQUE` without `NULLS NOT DISTINCT` does not constrain rows with a NULL frontier entry — the
#     robots attempts. The store's `ON CONFLICT DO NOTHING` idempotency simply never fired for them,
#     and the reviewer inserted 20,000 duplicates.
#   * Without the "null only for robots" CHECK, a `content` attempt with a NULL frontier entry is
#     accepted, is unbounded in number, and is invisible to the `frontier_entry_id = $3` predicate
#     that enforces :444's three-attempt bound.
#   * `WORK-CLAIM` plus the DEADLINE checkpoint are what make SEARCH_CRAWL_RETRIEVAL :82 true —
#     "Process loss after claim is repaired by the lease sweeper; the same attempt identity is
#     completed OR TIMED OUT, never replaced by an unaccounted request." Without them nothing could
#     time an attempt out: the reviewer killed three workers and the frontier entry was retired
#     permanently, and each loss also retired 10 MiB of the run's byte budget with no way to reclaim
#     it. The lease is the reclamation handle for BOTH.
#
# `T-CHK` is `G-CHK` plus the tenant columns: identity is immutable from insert, and "only declared
# checkpoint/result columns may change monotonically under a trigger" — hence `checkpoint_version`
# and `lock_version` rather than the `state_version` of a `T-MUT` row.
class CreateFetchAttempts < ActiveRecord::Migration[8.1]
  # :452's exhaustive vocabulary for one admitted content URL, plus the dispositions that keep a URL
  # out of the denominator entirely.
  OUTCOMES = %w[
    document_created content_absent content_fetch_failed policy_excluded limit_discarded timed_out
  ].freeze

  KINDS = %w[robots sitemap content].freeze

  def up
    execute <<~SQL
      CREATE TABLE fetch_attempts (
        id                        uuid PRIMARY KEY,
        -- G-CHK: a checkpoint row, not a mutable-state row.
        checkpoint_version        bigint NOT NULL DEFAULT 0,
        lock_version              bigint NOT NULL DEFAULT 0,
        schema_version            text NOT NULL,
        created_at                timestamptz(6) NOT NULL,
        updated_at                timestamptz(6) NOT NULL,

        -- LINEAGE (:116): the full set, so an attempt can be traced to the command that caused it.
        correlation_id            uuid NOT NULL,
        causation_id              uuid NOT NULL,
        command_id                uuid,
        idempotency_key_digest    bytea CHECK (idempotency_key_digest IS NULL OR octet_length(idempotency_key_digest) = 32),
        content_sha256            bytea CHECK (content_sha256 IS NULL OR octet_length(content_sha256) = 32),

        -- ---- immutable identity and input -------------------------------------
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        crawl_id                  uuid NOT NULL,
        crawl_host_gate_id        uuid NOT NULL,
        source_id                 uuid NOT NULL,
        crawl_frontier_entry_id   uuid,
        request_kind              text NOT NULL CHECK (request_kind IN #{list(KINDS)}),
        attempt_number            integer NOT NULL CHECK (attempt_number BETWEEN 1 AND 3),
        canonical_url             text NOT NULL,
        -- The full preimage is retained alongside the digest for the same reason the frontier
        -- retains it: hash equality without byte equality is a COLLISION and must never merge two
        -- attempts.
        canonical_url_preimage    bytea NOT NULL,
        canonical_url_sha256      bytea NOT NULL CHECK (octet_length(canonical_url_sha256) = 32),
        canonical_host            text NOT NULL,
        depth                     integer NOT NULL CHECK (depth >= 0),
        -- :456's ordering tuple, materialized. The coordinator that applies budget effects "in
        -- increasing dequeue key" is S-07-008's; recording the key here is what lets it do so
        -- without re-deriving an order this table would otherwise have lost.
        dequeue_key               bytea,
        -- The exact policy versions this attempt was authorized under, so a later scope or crawl
        -- policy change cannot retroactively change what this attempt is understood to have done.
        scope_policy_id           uuid,
        scope_policy_version      text,
        crawl_policy_id           uuid,
        crawl_policy_version      text,
        -- The byte reservation :442 requires BEFORE the body is read.
        reserved_bytes            bigint NOT NULL CHECK (reserved_bytes >= 0),

        -- ---- WORK-CLAIM (:122) -------------------------------------------------
        claim_owner               uuid,
        claim_generation          bigint NOT NULL DEFAULT 0,
        claimed_at                timestamptz(6),
        lease_expires_at          timestamptz(6),
        last_heartbeat_at         timestamptz(6),

        -- ---- checkpoints (:298) ------------------------------------------------
        prepared_at               timestamptz(6) NOT NULL,
        submission_started_at     timestamptz(6),
        completed_at              timestamptz(6),
        deadline_at               timestamptz(6) NOT NULL,

        -- ---- write-once result -------------------------------------------------
        outcome                   text CHECK (outcome IS NULL OR outcome IN #{list(OUTCOMES)}),
        reason_code               text,
        http_status               integer,
        accounted_response_bytes  bigint CHECK (accounted_response_bytes IS NULL OR accounted_response_bytes >= 0),
        received_body_bytes       bigint CHECK (received_body_bytes IS NULL OR received_body_bytes >= 0),
        expanded_body_bytes       bigint CHECK (expanded_body_bytes IS NULL OR expanded_body_bytes >= 0),
        limit_probe_bytes         integer NOT NULL DEFAULT 0 CHECK (limit_probe_bytes BETWEEN 0 AND 2),
        -- Attacker-controlled header text, so it is BOUNDED. A response can otherwise write up to
        -- the 64 KiB header section into a durable row, three times per URL, ten thousand URLs a run.
        media_type                text CHECK (media_type IS NULL OR length(media_type) <= 255),
        redirect_count            integer CHECK (redirect_count IS NULL OR redirect_count >= 0),
        final_url                 text CHECK (final_url IS NULL OR length(final_url) <= 2048),
        body_sha256               bytea CHECK (body_sha256 IS NULL OR octet_length(body_sha256) = 32),
        robots_decision_sha256    bytea CHECK (robots_decision_sha256 IS NULL OR octet_length(robots_decision_sha256) = 32),
        staging_object_id         uuid,
        retryable                 boolean,
        latency_ms                integer CHECK (latency_ms IS NULL OR latency_ms >= 0),
        terminal_at               timestamptz(6),

        -- Exactly the terminal rows carry an outcome and an instant.
        CONSTRAINT fetch_attempts_terminal_shape
          CHECK ((outcome IS NULL) = (terminal_at IS NULL)),
        -- :298 — "frontier ID is null only for robots and nonnull otherwise".
        CONSTRAINT fetch_attempts_frontier_entry_shape
          CHECK ((crawl_frontier_entry_id IS NULL) = (request_kind = 'robots')),
        -- :442 — "an attempt cannot add accounted bytes BEYOND ITS RESERVATION".
        CONSTRAINT fetch_attempts_within_reservation
          CHECK (accounted_response_bytes IS NULL OR accounted_response_bytes <= reserved_bytes),
        -- WORK-CLAIM (:122) — "owner/claimed/lease times are null while unclaimed and nonnull with
        -- positive generation while claimed".
        CONSTRAINT fetch_attempts_claim_shape
          CHECK ((claim_owner IS NULL) = (claimed_at IS NULL)
                 AND (claim_owner IS NULL) = (lease_expires_at IS NULL)
                 AND (claim_owner IS NULL OR claim_generation > 0)),
        -- :298's key, WITH `NULLS NOT DISTINCT`. Without it the key does not constrain robots
        -- attempts at all, because their frontier entry is NULL and NULLs are distinct by default —
        -- which is precisely the idempotency the store's ON CONFLICT depends on.
        CONSTRAINT fetch_attempts_attempt_unique
          UNIQUE NULLS NOT DISTINCT (crawl_host_gate_id, request_kind, crawl_frontier_entry_id, attempt_number),
        CONSTRAINT fetch_attempts_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT fetch_attempts_org_project_id_unique UNIQUE (organization_id, project_id, id),
        -- POSTGRESQL_SCHEMA :128 — all three of (organization_id, project_id, <parent>) on every
        -- Project-owned link.
        CONSTRAINT fetch_attempts_crawl_fk
          FOREIGN KEY (organization_id, project_id, crawl_id)
          REFERENCES crawls (organization_id, project_id, id),
        CONSTRAINT fetch_attempts_source_fk
          FOREIGN KEY (organization_id, project_id, source_id)
          REFERENCES sources (organization_id, project_id, id),
        CONSTRAINT fetch_attempts_frontier_entry_fk
          FOREIGN KEY (organization_id, project_id, crawl_frontier_entry_id)
          REFERENCES crawl_frontier_entries (organization_id, project_id, id),
        CONSTRAINT fetch_attempts_host_gate_fk
          FOREIGN KEY (organization_id, project_id, crawl_host_gate_id)
          REFERENCES crawl_host_gates (organization_id, project_id, id)
      );

      -- :442's run-wide sum is taken "in canonical dequeue/attempt order"; :452 walks every attempt.
      CREATE INDEX fetch_attempts_crawl_order ON fetch_attempts (crawl_id, dequeue_key, attempt_number, id);
      CREATE INDEX fetch_attempts_crawl_outcome ON fetch_attempts (organization_id, crawl_id, outcome);
      -- The sweeper's only query: expired leases on non-terminal attempts.
      CREATE INDEX fetch_attempts_expired_leases ON fetch_attempts (organization_id, crawl_id, lease_expires_at)
        WHERE outcome IS NULL;

      ALTER TABLE fetch_attempts ENABLE ROW LEVEL SECURITY;
      ALTER TABLE fetch_attempts FORCE ROW LEVEL SECURITY;
      CREATE POLICY fetch_attempts_context ON fetch_attempts
        USING (organization_id = f1_current_context_org())
        WITH CHECK (organization_id = f1_current_context_org());
    SQL
    add_guard
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS fetch_attempts_guard ON fetch_attempts;
      DROP FUNCTION IF EXISTS f1_fetch_attempts_guard();
      DROP TABLE IF EXISTS fetch_attempts;
    SQL
  end

  private

  def list(values) = "(#{values.map { |v| "'#{v}'" }.join(',')})"

  # Every identity/input column, named explicitly. S-07-006's review found the same defect class
  # three times — a frozen set that omitted columns the terminal statement writes — so the list is
  # written out in full and the review verifies it against the store's SET clauses column by column.
  IDENTITY = %w[
    id organization_id project_id crawl_id crawl_host_gate_id source_id crawl_frontier_entry_id
    request_kind attempt_number canonical_url canonical_url_preimage canonical_url_sha256
    canonical_host depth dequeue_key scope_policy_id scope_policy_version crawl_policy_id
    crawl_policy_version reserved_bytes prepared_at deadline_at schema_version
    created_at correlation_id causation_id command_id idempotency_key_digest
  ].freeze

  RESULT = %w[
    outcome reason_code http_status accounted_response_bytes received_body_bytes
    expanded_body_bytes limit_probe_bytes media_type redirect_count final_url body_sha256
    robots_decision_sha256 staging_object_id content_sha256 retryable latency_ms terminal_at
    completed_at
  ].freeze

  def add_guard
    identity = IDENTITY.map { |c| "NEW.#{c} IS DISTINCT FROM OLD.#{c}" }.join("\n           OR ")
    result = RESULT.map { |c| "NEW.#{c} IS DISTINCT FROM OLD.#{c}" }.join("\n             OR ")
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_fetch_attempts_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'fetch_attempt_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        -- The identity/input half is frozen from INSERT, not merely from terminalisation: it is what
        -- the attempt was authorized as, and rewriting it would relabel a request already made.
        IF #{identity} THEN
          RAISE EXCEPTION 'fetch_attempt_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.checkpoint_version <> OLD.checkpoint_version + 1 THEN
          RAISE EXCEPTION 'fetch_attempt_version_invalid' USING ERRCODE = 'raise_exception';
        END IF;
        -- Checkpoints advance once and never move again (:298's "only declared checkpoint/result
        -- columns may change MONOTONICALLY").
        IF (OLD.submission_started_at IS NOT NULL
            AND NEW.submission_started_at IS DISTINCT FROM OLD.submission_started_at)
           OR (OLD.claim_generation > NEW.claim_generation) THEN
          RAISE EXCEPTION 'fetch_attempt_checkpoint_not_monotonic' USING ERRCODE = 'raise_exception';
        END IF;
        -- The result half is write-once: once terminal, no column of it may change again.
        IF OLD.outcome IS NOT NULL THEN
          IF #{result} THEN
            RAISE EXCEPTION 'fetch_attempt_result_frozen' USING ERRCODE = 'raise_exception';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER fetch_attempts_guard BEFORE DELETE OR UPDATE ON fetch_attempts
        FOR EACH ROW EXECUTE FUNCTION f1_fetch_attempts_guard();
    SQL
  end
end
