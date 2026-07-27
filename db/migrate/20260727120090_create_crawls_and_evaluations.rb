# frozen_string_literal: true

# S-07-002 Crawl aggregate + QueueCrawl (contracts/S-07.json MTX-030 queue limb, MTX-058
# PRULE-007; WORKFLOW_SPECIFICATIONS.md § WF-005 :725-728). Creates the three S-07 product
# tables this and the next tranches own (schemas/POSTGRESQL_SCHEMA.md :292/293/339):
#
#   crawls       — the execution root. QueueCrawl inserts a 'queued' row pinning the
#                  request-time crawl-policy + entitlement-policy versions (per owner D1,
#                  ADR-068, the pinned versions are dedicated columns, not a policy_snapshot
#                  row); the entitlement Decision/reservation stay NULL until start (F-05).
#   crawl_sources— T-IMM: the pinned request-time Source set (each Source's state version and
#                  active Source Scope Policy id/version + canonical root + dequeue order).
#   evaluations  — the Evaluation root. Created here so the OD-018 queue-time guard can read it
#                  and StartCrawl (S-07-003) can insert the one pending initial Evaluation; the
#                  two OD-018 partial-unique indexes are the DB backstop. S-08/S-09 own the rest
#                  of the Evaluation lifecycle.
#
# Lifecycle transitions (queued->running, terminal, cancel) are RELAXED by later tranches; this
# migration's guards freeze identity/pinned facts, refuse DELETE, and refuse every state change.
class CreateCrawlsAndEvaluations < ActiveRecord::Migration[8.1]
  def up
    create_crawls
    create_crawl_sources
    create_evaluations
    force_rls("crawls", using: "organization_id = f1_current_context_org()")
    force_rls("crawl_sources", using: "organization_id = f1_current_context_org()")
    force_rls("evaluations", using: "organization_id = f1_current_context_org()")
    create_crawls_guard
    create_crawl_sources_guard
    create_evaluations_guard
  end

  def down
    %w[crawls crawl_sources evaluations].each do |t|
      execute "DROP TRIGGER IF EXISTS #{t}_guard ON #{t};"
      execute "DROP FUNCTION IF EXISTS f1_#{t}_guard();"
    end
    execute "DROP TABLE IF EXISTS crawl_sources;"
    execute "DROP TABLE IF EXISTS evaluations;"
    execute "DROP TABLE IF EXISTS crawls;"
  end

  private

  def create_crawls
    execute <<~SQL
      CREATE TABLE crawls (
        id                                 uuid PRIMARY KEY,
        state_version                      bigint NOT NULL DEFAULT 0,
        created_at                         timestamptz(6) NOT NULL,
        updated_at                         timestamptz(6) NOT NULL,
        correlation_id                     uuid NOT NULL,
        organization_id                    uuid NOT NULL,
        project_id                         uuid NOT NULL,
        kind                               text NOT NULL CHECK (kind IN ('root','reassessment_child')),
        parent_evaluation_id               uuid,
        parent_crawl_id                    uuid,
        -- Request-time pinned versions (D1: dedicated columns, no policy_snapshot row). The
        -- crawl policy may be global-only (no Org/Project row) at request, so its id/version
        -- are nullable; the entitlement policy is always resolvable.
        requested_crawl_policy_id          uuid,
        requested_crawl_policy_version     text,
        requested_entitlement_policy_id    uuid NOT NULL,
        requested_entitlement_policy_version text NOT NULL,
        entitlement_decision_id            uuid,
        entitlement_reservation_id         uuid,
        trigger_kind                       text NOT NULL CHECK (trigger_kind IN ('manual','scheduled')),
        triggered_by_account_id            uuid,
        queued_at                          timestamptz(6) NOT NULL,
        started_at                         timestamptz(6),
        terminal_at                        timestamptz(6),
        deadline_at                        timestamptz(6),
        state                              text NOT NULL CHECK (state IN ('queued','running','completed','failed','canceled')),
        coverage_status                    text CHECK (coverage_status IN ('full','partial')),
        completion_reason                  text,
        limit_counters                     jsonb NOT NULL DEFAULT '{}',
        retry_generation                   bigint NOT NULL DEFAULT 0,
        recovery_generation                bigint NOT NULL DEFAULT 0,
        recovery_of_id                     uuid,
        idempotency_key_digest             bytea CHECK (idempotency_key_digest IS NULL OR octet_length(idempotency_key_digest) = 32),
        CONSTRAINT crawls_kind_parent_agreement CHECK (
          (kind = 'root' AND parent_evaluation_id IS NULL) OR
          (kind = 'reassessment_child' AND parent_evaluation_id IS NOT NULL)
        ),
        CONSTRAINT crawls_terminal_shape CHECK (
          (state IN ('queued','running') AND terminal_at IS NULL AND coverage_status IS NULL AND completion_reason IS NULL) OR
          (state IN ('completed','failed','canceled') AND terminal_at IS NOT NULL)
        ),
        CONSTRAINT crawls_org_project_id_unique UNIQUE (organization_id, project_id, id),
        CONSTRAINT crawls_project_fk FOREIGN KEY (organization_id, project_id)
          REFERENCES projects (organization_id, id)
      );
      CREATE INDEX crawls_project_state ON crawls (organization_id, project_id, state);
    SQL
  end

  def create_crawl_sources
    execute <<~SQL
      CREATE TABLE crawl_sources (
        id                    uuid PRIMARY KEY,
        created_at            timestamptz(6) NOT NULL,
        correlation_id        uuid NOT NULL,
        organization_id       uuid NOT NULL,
        project_id            uuid NOT NULL,
        crawl_id              uuid NOT NULL,
        source_id             uuid NOT NULL,
        source_state_version  bigint NOT NULL,
        scope_policy_id       uuid NOT NULL,
        scope_policy_version  text NOT NULL,
        canonical_root_uri    text NOT NULL,
        source_order          integer NOT NULL CHECK (source_order >= 0),
        CONSTRAINT crawl_sources_crawl_fk FOREIGN KEY (organization_id, project_id, crawl_id)
          REFERENCES crawls (organization_id, project_id, id),
        CONSTRAINT crawl_sources_source_fk FOREIGN KEY (organization_id, project_id, source_id)
          REFERENCES sources (organization_id, project_id, id)
      );
      CREATE UNIQUE INDEX crawl_sources_crawl_source_unique ON crawl_sources (crawl_id, source_id);
      CREATE UNIQUE INDEX crawl_sources_crawl_order_unique ON crawl_sources (crawl_id, source_order);
    SQL
  end

  def create_evaluations
    execute <<~SQL
      CREATE TABLE evaluations (
        id                        uuid PRIMARY KEY,
        state_version             bigint NOT NULL DEFAULT 0,
        created_at                timestamptz(6) NOT NULL,
        updated_at                timestamptz(6) NOT NULL,
        correlation_id            uuid NOT NULL,
        organization_id           uuid NOT NULL,
        project_id                uuid NOT NULL,
        kind                      text NOT NULL CHECK (kind IN ('initial','reassessment','retry')),
        crawl_id                  uuid,
        prior_evaluation_id       uuid,
        retry_of_evaluation_id    uuid,
        input_snapshot_id         uuid,
        applicability_snapshot_id uuid,
        policy_snapshot_id        uuid,
        state                     text NOT NULL CHECK (state IN ('pending','running','completed','failed','superseded')),
        started_at                timestamptz(6),
        completed_at              timestamptz(6),
        failed_at                 timestamptz(6),
        superseded_at             timestamptz(6),
        deadline_at               timestamptz(6),
        reason                    text,
        orchestration_slot_active boolean NOT NULL DEFAULT false,
        CONSTRAINT evaluations_project_fk FOREIGN KEY (organization_id, project_id)
          REFERENCES projects (organization_id, id)
      );
      -- OD-018 DB backstops (DECISIONS OD-018): at most one orchestration slot per Project, and
      -- exactly one initial Evaluation per Crawl.
      CREATE UNIQUE INDEX evaluations_orchestration_slot_unique ON evaluations
        (organization_id, project_id) WHERE orchestration_slot_active;
      CREATE UNIQUE INDEX evaluations_initial_per_crawl_unique ON evaluations
        (organization_id, project_id, crawl_id) WHERE kind = 'initial';
      CREATE INDEX evaluations_project_kind_state ON evaluations (organization_id, project_id, kind, state);
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

  # crawls: freeze tenant identity + request-pinned facts; refuse DELETE; refuse every state
  # change (later tranches relax queued->running, terminal, cancel).
  def create_crawls_guard
    execute <<~SQL
      CREATE FUNCTION f1_crawls_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'crawl_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.kind IS DISTINCT FROM OLD.kind
           OR NEW.parent_evaluation_id IS DISTINCT FROM OLD.parent_evaluation_id
           OR NEW.parent_crawl_id IS DISTINCT FROM OLD.parent_crawl_id
           OR NEW.requested_crawl_policy_id IS DISTINCT FROM OLD.requested_crawl_policy_id
           OR NEW.requested_crawl_policy_version IS DISTINCT FROM OLD.requested_crawl_policy_version
           OR NEW.requested_entitlement_policy_id IS DISTINCT FROM OLD.requested_entitlement_policy_id
           OR NEW.requested_entitlement_policy_version IS DISTINCT FROM OLD.requested_entitlement_policy_version
           OR NEW.trigger_kind IS DISTINCT FROM OLD.trigger_kind
           OR NEW.triggered_by_account_id IS DISTINCT FROM OLD.triggered_by_account_id
           OR NEW.queued_at IS DISTINCT FROM OLD.queued_at
           OR NEW.correlation_id IS DISTINCT FROM OLD.correlation_id
           OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
          RAISE EXCEPTION 'crawl_facts_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.state IS DISTINCT FROM OLD.state THEN
          RAISE EXCEPTION 'crawl_transition_unavailable % -> %', OLD.state, NEW.state USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER crawls_guard BEFORE UPDATE OR DELETE ON crawls
        FOR EACH ROW EXECUTE FUNCTION f1_crawls_guard();
    SQL
  end

  # crawl_sources: T-IMM (no UPDATE, no DELETE).
  def create_crawl_sources_guard
    execute <<~SQL
      CREATE FUNCTION f1_crawl_sources_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        RAISE EXCEPTION 'crawl_source_immutable' USING ERRCODE = 'raise_exception';
      END;
      $$;
      CREATE TRIGGER crawl_sources_guard BEFORE UPDATE OR DELETE ON crawl_sources
        FOR EACH ROW EXECUTE FUNCTION f1_crawl_sources_guard();
    SQL
  end

  # evaluations: freeze tenant identity; refuse DELETE; refuse every state change (StartCrawl in
  # S-07-003 inserts the pending row; S-08/S-09 relax the lifecycle edges).
  def create_evaluations_guard
    execute <<~SQL
      CREATE FUNCTION f1_evaluations_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'evaluation_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.id IS DISTINCT FROM OLD.id
           OR NEW.organization_id IS DISTINCT FROM OLD.organization_id
           OR NEW.project_id IS DISTINCT FROM OLD.project_id
           OR NEW.kind IS DISTINCT FROM OLD.kind
           OR NEW.crawl_id IS DISTINCT FROM OLD.crawl_id
           OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
          RAISE EXCEPTION 'evaluation_facts_immutable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NEW.state IS DISTINCT FROM OLD.state THEN
          RAISE EXCEPTION 'evaluation_transition_unavailable % -> %', OLD.state, NEW.state USING ERRCODE = 'raise_exception';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER evaluations_guard BEFORE UPDATE OR DELETE ON evaluations
        FOR EACH ROW EXECUTE FUNCTION f1_evaluations_guard();
    SQL
  end
end
