# frozen_string_literal: true

# S-07-003 StartCrawl + initial Evaluation (contracts/S-07.json MTX-030 start limb; DECISIONS OD-018;
# WORKFLOW_SPECIFICATIONS.md § WF-005 :726-728, :734). Two schema changes for the Queued -> Running
# start commit:
#   1. Relax f1_crawls_guard to permit exactly Crawl.Queued -> Running (accepted start) and
#      Queued -> Failed (the pre-execution current-policy/Entitlement block gate); every other state
#      change stays refused (running->terminal and cancel are relaxed by later tranches). The pinned
#      request facts stay frozen; started_at / terminal_at / completion_reason / coverage_status /
#      entitlement_decision_id / entitlement_reservation_id remain mutable so StartCrawl can stamp them.
#   2. Add evaluation_orchestration_contexts (T-IMM): the immutable orchestration context for the
#      accepted start — the root Entitlement Decision/reservation, the pinned Source-set/scope/policy
#      hashes, prior current pointers (null for an initial), and publication preconditions
#      (schemas/POSTGRESQL_SCHEMA.md :340). One per Evaluation.
class StartCrawlAndOrchestrationContext < ActiveRecord::Migration[8.1]
  def up
    relax_crawls_guard(permit_start: true)
    # The composite-tenant unique the orchestration-context FK targets (evaluations had only its PK).
    execute "ALTER TABLE evaluations ADD CONSTRAINT evaluations_org_id_unique UNIQUE (organization_id, id);"
    create_orchestration_contexts
    force_rls("evaluation_orchestration_contexts", using: "organization_id = f1_current_context_org()")
    create_orchestration_contexts_guard
  end

  def down
    execute "DROP TRIGGER IF EXISTS evaluation_orchestration_contexts_guard ON evaluation_orchestration_contexts;"
    execute "DROP FUNCTION IF EXISTS f1_evaluation_orchestration_contexts_guard();"
    execute "DROP TABLE IF EXISTS evaluation_orchestration_contexts;"
    execute "ALTER TABLE evaluations DROP CONSTRAINT evaluations_org_id_unique;"
    relax_crawls_guard(permit_start: false)
  end

  private

  def force_rls(table, using:, check: nil)
    execute <<~SQL
      ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;
      ALTER TABLE #{table} FORCE ROW LEVEL SECURITY;
      CREATE POLICY #{table}_context ON #{table}
        USING (#{using}) WITH CHECK (#{check || using});
      REVOKE ALL ON #{table} FROM PUBLIC;
    SQL
  end

  # CREATE OR REPLACE the crawls guard. With permit_start, the only permitted state edges are
  # queued->running and queued->failed; otherwise (down) no state change is permitted.
  def relax_crawls_guard(permit_start:)
    allowed = permit_start ? "OLD.state = 'queued' AND NEW.state IN ('running','failed')" : "FALSE"
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_crawls_guard() RETURNS trigger
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
          IF NOT (#{allowed}) THEN
            RAISE EXCEPTION 'crawl_transition_unavailable % -> %', OLD.state, NEW.state USING ERRCODE = 'raise_exception';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $$;
    SQL
  end

  def create_orchestration_contexts
    execute <<~SQL
      CREATE TABLE evaluation_orchestration_contexts (
        id                            uuid PRIMARY KEY,
        created_at                    timestamptz(6) NOT NULL,
        correlation_id                uuid NOT NULL,
        organization_id               uuid NOT NULL,
        project_id                    uuid NOT NULL,
        evaluation_id                 uuid NOT NULL,
        crawl_id                      uuid NOT NULL,
        prior_evaluation_id           uuid,
        prior_issue_set_id            uuid,
        prior_score_snapshot_id       uuid,
        source_set_hash               bytea CHECK (source_set_hash IS NULL OR octet_length(source_set_hash) = 32),
        normalized_scope_hash         bytea CHECK (normalized_scope_hash IS NULL OR octet_length(normalized_scope_hash) = 32),
        crawl_policy_version          text,
        entitlement_policy_version    text,
        root_entitlement_decision_id  uuid NOT NULL,
        root_entitlement_reservation_id uuid,
        stage_input_hashes            jsonb NOT NULL DEFAULT '{}',
        publication_preconditions     jsonb NOT NULL DEFAULT '{}',
        CONSTRAINT evaluation_orchestration_contexts_evaluation_unique UNIQUE (evaluation_id),
        CONSTRAINT evaluation_orchestration_contexts_org_id_unique UNIQUE (organization_id, id),
        CONSTRAINT evaluation_orchestration_contexts_evaluation_fk FOREIGN KEY (organization_id, evaluation_id)
          REFERENCES evaluations (organization_id, id),
        CONSTRAINT evaluation_orchestration_contexts_project_fk FOREIGN KEY (organization_id, project_id)
          REFERENCES projects (organization_id, id),
        CONSTRAINT evaluation_orchestration_contexts_crawl_fk FOREIGN KEY (organization_id, project_id, crawl_id)
          REFERENCES crawls (organization_id, project_id, id),
        CONSTRAINT evaluation_orchestration_contexts_decision_fk FOREIGN KEY (organization_id, root_entitlement_decision_id)
          REFERENCES entitlement_decisions (organization_id, id)
      );
    SQL
  end

  # T-IMM: the orchestration context is written once at the accepted start and never changes.
  def create_orchestration_contexts_guard
    execute <<~SQL
      CREATE FUNCTION f1_evaluation_orchestration_contexts_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      BEGIN
        RAISE EXCEPTION 'evaluation_orchestration_context_immutable' USING ERRCODE = 'raise_exception';
      END;
      $$;
      CREATE TRIGGER evaluation_orchestration_contexts_guard BEFORE UPDATE OR DELETE ON evaluation_orchestration_contexts
        FOR EACH ROW EXECUTE FUNCTION f1_evaluation_orchestration_contexts_guard();
    SQL
  end
end
