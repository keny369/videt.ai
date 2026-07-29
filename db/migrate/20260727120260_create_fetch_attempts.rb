# frozen_string_literal: true

# S-07-007 content-fetch attempt record (SEARCH_CRAWL_RETRIEVAL.md § Frontier And Deterministic
# Selection — "`fetch_attempts`: IMMUTABLE ATTEMPT IDENTITY/INPUT plus MUTABLE WRITE-ONCE
# checkpoint/result columns"; WORKFLOW_SPECIFICATIONS.md :436/:442/:444/:452).
#
# The two halves of that sentence are the whole design. The identity half — which URL, which
# frontier entry, which attempt number, under which policy versions — is written once at claim and
# is frozen thereafter. The result half is NULL until the attempt terminates and frozen once it
# does. Nothing here is ever rewritten, because :452's coverage classification and :442's
# "run-wide accounted response-body bytes are exactly sum(accounted_response_bytes_i) IN CANONICAL
# DEQUEUE/ATTEMPT ORDER" both read these rows after the fact and must get the same answer twice.
#
# WHY THE ATTEMPT IS CLAIMED BEFORE THE CONNECTION. SEARCH_CRAWL_RETRIEVAL :82 — "Process loss
# after claim is repaired by the lease sweeper; THE SAME ATTEMPT IDENTITY is completed or timed
# out, NEVER REPLACED BY AN UNACCOUNTED REQUEST." A row that appears only on success would make a
# lost worker's request invisible: its bytes were spent, its rate-limit slot was used, and the run
# would have no record of either. So the row is inserted before the fetch, in its own transaction,
# and terminalised afterwards.
#
# `accounted_response_bytes` is :442's formula, not the received count:
#   accounted_response_bytes_i = max(received_after_transfer_coding, expanded_after_content_decoding)
# and `limit_probe_bytes` is the at-most-one sentinel byte per accounting path, recorded separately
# because :442 says probes "are detection telemetry, not accepted/accounted capacity".
class CreateFetchAttempts < ActiveRecord::Migration[8.1]
  # :452's exhaustive outcome vocabulary for one admitted content URL, plus the two dispositions
  # that keep a URL out of the denominator entirely.
  OUTCOMES = %w[
    document_created content_absent content_fetch_failed policy_excluded limit_discarded
  ].freeze

  KINDS = %w[content robots sitemap].freeze

  def up
    execute <<~SQL
      CREATE TABLE fetch_attempts (
        id                        uuid PRIMARY KEY,
        state_version             bigint NOT NULL DEFAULT 0,
        created_at                timestamptz(6) NOT NULL,
        updated_at                timestamptz(6) NOT NULL,
        correlation_id            uuid NOT NULL,

        -- ---- immutable identity and input -------------------------------------
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        crawl_id                  uuid NOT NULL,
        source_id                 uuid NOT NULL,
        frontier_entry_id         uuid,
        kind                      text NOT NULL CHECK (kind IN #{list(KINDS)}),
        attempt_number            integer NOT NULL CHECK (attempt_number >= 1),
        canonical_url             text NOT NULL,
        -- The full preimage is retained alongside the digest for the same reason the frontier
        -- retains it: hash equality without byte equality is a COLLISION, and a collision must
        -- never merge two attempts.
        canonical_url_preimage    bytea NOT NULL,
        canonical_url_sha256      bytea NOT NULL CHECK (octet_length(canonical_url_sha256) = 32),
        canonical_host            text NOT NULL,
        depth                     integer NOT NULL CHECK (depth >= 0),
        -- The exact policy versions this attempt was authorized under, so a later scope or crawl
        -- policy change cannot retroactively change what this attempt is understood to have done.
        scope_policy_id           uuid,
        scope_policy_version      text,
        crawl_policy_id           uuid,
        crawl_policy_version      text,
        -- The byte reservation :442 requires BEFORE the body is read.
        reserved_bytes            bigint NOT NULL CHECK (reserved_bytes >= 0),
        started_at                timestamptz(6) NOT NULL,

        -- ---- write-once result -------------------------------------------------
        outcome                   text CHECK (outcome IS NULL OR outcome IN #{list(OUTCOMES)}),
        reason_code               text,
        http_status               integer,
        -- :442's accounted formula, and the sentinel probe recorded APART from it.
        accounted_response_bytes  bigint CHECK (accounted_response_bytes IS NULL OR accounted_response_bytes >= 0),
        received_body_bytes       bigint CHECK (received_body_bytes IS NULL OR received_body_bytes >= 0),
        expanded_body_bytes       bigint CHECK (expanded_body_bytes IS NULL OR expanded_body_bytes >= 0),
        limit_probe_bytes         integer NOT NULL DEFAULT 0 CHECK (limit_probe_bytes BETWEEN 0 AND 2),
        media_type                text,
        redirect_count            integer CHECK (redirect_count IS NULL OR redirect_count >= 0),
        final_url                 text,
        body_sha256               bytea CHECK (body_sha256 IS NULL OR octet_length(body_sha256) = 32),
        retryable                 boolean,
        latency_ms                integer CHECK (latency_ms IS NULL OR latency_ms >= 0),
        terminal_at               timestamptz(6),

        -- Exactly the terminal rows carry an outcome and an instant; neither exists without the
        -- other, so "did this attempt finish" has one answer rather than two.
        CONSTRAINT fetch_attempts_terminal_shape
          CHECK ((outcome IS NULL) = (terminal_at IS NULL)),
        -- :442 — "an attempt cannot add accounted bytes BEYOND ITS RESERVATION".
        CONSTRAINT fetch_attempts_within_reservation
          CHECK (accounted_response_bytes IS NULL OR accounted_response_bytes <= reserved_bytes),
        -- :444 — one initial attempt plus at most two retries.
        CONSTRAINT fetch_attempts_attempt_bound CHECK (attempt_number <= 3),
        CONSTRAINT fetch_attempts_entry_attempt_unique
          UNIQUE (crawl_id, frontier_entry_id, kind, attempt_number),
        CONSTRAINT fetch_attempts_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT fetch_attempts_org_project_id_unique UNIQUE (organization_id, project_id, id),
        -- POSTGRESQL_SCHEMA :128 — all three of (organization_id, project_id, <parent>) on every
        -- Project-owned link. The same-Organization cross-Project defect appeared in three
        -- consecutive tranches of this block; it is not left to a read path here.
        CONSTRAINT fetch_attempts_crawl_fk
          FOREIGN KEY (organization_id, project_id, crawl_id)
          REFERENCES crawls (organization_id, project_id, id),
        CONSTRAINT fetch_attempts_source_fk
          FOREIGN KEY (organization_id, project_id, source_id)
          REFERENCES sources (organization_id, project_id, id),
        CONSTRAINT fetch_attempts_frontier_entry_fk
          FOREIGN KEY (organization_id, project_id, frontier_entry_id)
          REFERENCES crawl_frontier_entries (organization_id, project_id, id)
      );

      -- :442's run-wide sum is taken "in canonical dequeue/attempt order", and :452 walks every
      -- attempt of a run; both are crawl-scoped scans.
      CREATE INDEX fetch_attempts_crawl_order ON fetch_attempts (crawl_id, started_at, id);
      CREATE INDEX fetch_attempts_crawl_outcome ON fetch_attempts (organization_id, crawl_id, outcome);

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
  # written out in full rather than trimmed to what seems load-bearing today.
  IDENTITY = %w[
    id organization_id project_id crawl_id source_id frontier_entry_id kind attempt_number
    canonical_url canonical_url_preimage canonical_url_sha256 canonical_host depth
    scope_policy_id scope_policy_version crawl_policy_id crawl_policy_version
    reserved_bytes started_at created_at correlation_id
  ].freeze

  RESULT = %w[
    outcome reason_code http_status accounted_response_bytes received_body_bytes
    expanded_body_bytes limit_probe_bytes media_type redirect_count final_url body_sha256
    retryable latency_ms terminal_at
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
        -- The identity/input half is frozen from insert, not merely from terminalisation: it is
        -- what the attempt WAS AUTHORIZED AS, and rewriting it would relabel a request that has
        -- already been made.
        IF #{identity} THEN
          RAISE EXCEPTION 'fetch_attempt_identity_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.state_version <> OLD.state_version + 1 THEN
          RAISE EXCEPTION 'fetch_attempt_version_invalid' USING ERRCODE = 'raise_exception';
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
