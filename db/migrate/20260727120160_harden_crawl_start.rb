# frozen_string_literal: true

# S-07-003 review hardening (ADR-026 schema, contract and security lenses). Database-level closures
# for invariants the application was enforcing alone, or that the S-07-003 (1/n) migration expressed
# too weakly.
#
#   1. THE COMPOSITE PROJECT FK RULE. schemas/POSTGRESQL_SCHEMA.md :128 is categorical: "Every
#      Project-owned parent additionally exposes UNIQUE (organization_id,project_id,id), and every
#      Project-owned child-to-parent foreign key contains all three values. These constraints,
#      rather than a separate Project lookup or application assertion, prevent a same-Organization
#      cross-Project child link." `evaluation_orchestration_contexts_evaluation_fk` was created
#      (20260727120140) with only TWO columns, against the `(organization_id, id)` unique this
#      tranche added to `evaluations` — the only two-column Project-owned child-to-parent FK in the
#      schema. A context row could therefore claim `project_id = P1` while naming an Evaluation
#      belonging to P2 of the same Organization, and the T-IMM guard would then freeze that row
#      forever. `evaluations` gains the mandated three-column unique and the FK is rebuilt on it.
#
#   2. `crawls.completion_reason` is a CLOSED enum — `completed`, `limit_reached`,
#      `partial_source_failure`, `canceled`, `failed` (WORKFLOW_SPECIFICATIONS.md :456;
#      API_CONTRACTS.md :956/:1005 repeat it for the `crawl_terminal` event schema and the WF-014
#      notification context). The column was unconstrained `text`, so a handler could write a machine
#      reason code into it and nothing would object. The CHECK makes the enum unable to drift; the
#      exact reason for a terminal outcome lives in the audit record and the event, never here.
#
#   3. THE MISSING TENANT FKs. The references StartCrawl stamps on an accepted start
#      (`crawls.entitlement_decision_id` / `entitlement_reservation_id`,
#      `evaluations.crawl_id`) and the orchestration context's `prior_evaluation_id` /
#      `root_entitlement_reservation_id` carried no FK at all, so cross-tenant lineage was blocked
#      only by RLS and by the application always deriving the ids under the entered context. Each
#      target already exposes the unique these need. Validation is immediate: every one of these
#      columns is NULL on every existing row, because nothing has started before this tranche.
class HardenCrawlStart < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      -- 1. the three-column Project-owned unique + the rebuilt orchestration-context FK
      ALTER TABLE evaluations ADD CONSTRAINT evaluations_org_project_id_unique
        UNIQUE (organization_id, project_id, id);
      ALTER TABLE evaluation_orchestration_contexts
        DROP CONSTRAINT evaluation_orchestration_contexts_evaluation_fk;
      ALTER TABLE evaluation_orchestration_contexts
        ADD CONSTRAINT evaluation_orchestration_contexts_evaluation_fk
        FOREIGN KEY (organization_id, project_id, evaluation_id)
        REFERENCES evaluations (organization_id, project_id, id);
      ALTER TABLE evaluation_orchestration_contexts
        ADD CONSTRAINT evaluation_orchestration_contexts_prior_evaluation_fk
        FOREIGN KEY (organization_id, project_id, prior_evaluation_id)
        REFERENCES evaluations (organization_id, project_id, id);
      ALTER TABLE evaluation_orchestration_contexts
        ADD CONSTRAINT evaluation_orchestration_contexts_reservation_fk
        FOREIGN KEY (organization_id, root_entitlement_reservation_id)
        REFERENCES entitlement_reservations (organization_id, id);

      -- 2. the closed CompletionReason enum
      ALTER TABLE crawls ADD CONSTRAINT crawls_completion_reason_check
        CHECK (completion_reason IS NULL OR completion_reason IN
               ('completed','limit_reached','partial_source_failure','canceled','failed'));

      -- 3. the entitlement lineage FKs StartCrawl stamps, and the Evaluation's Crawl
      ALTER TABLE crawls ADD CONSTRAINT crawls_entitlement_decision_fk
        FOREIGN KEY (organization_id, entitlement_decision_id)
        REFERENCES entitlement_decisions (organization_id, id);
      ALTER TABLE crawls ADD CONSTRAINT crawls_entitlement_reservation_fk
        FOREIGN KEY (organization_id, entitlement_reservation_id)
        REFERENCES entitlement_reservations (organization_id, id);
      ALTER TABLE evaluations ADD CONSTRAINT evaluations_crawl_fk
        FOREIGN KEY (organization_id, project_id, crawl_id)
        REFERENCES crawls (organization_id, project_id, id);
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE evaluations DROP CONSTRAINT IF EXISTS evaluations_crawl_fk;
      ALTER TABLE crawls DROP CONSTRAINT IF EXISTS crawls_entitlement_reservation_fk;
      ALTER TABLE crawls DROP CONSTRAINT IF EXISTS crawls_entitlement_decision_fk;
      ALTER TABLE crawls DROP CONSTRAINT IF EXISTS crawls_completion_reason_check;
      ALTER TABLE evaluation_orchestration_contexts
        DROP CONSTRAINT IF EXISTS evaluation_orchestration_contexts_reservation_fk;
      ALTER TABLE evaluation_orchestration_contexts
        DROP CONSTRAINT IF EXISTS evaluation_orchestration_contexts_prior_evaluation_fk;
      ALTER TABLE evaluation_orchestration_contexts
        DROP CONSTRAINT evaluation_orchestration_contexts_evaluation_fk;
      ALTER TABLE evaluation_orchestration_contexts
        ADD CONSTRAINT evaluation_orchestration_contexts_evaluation_fk
        FOREIGN KEY (organization_id, evaluation_id) REFERENCES evaluations (organization_id, id);
      ALTER TABLE evaluations DROP CONSTRAINT IF EXISTS evaluations_org_project_id_unique;
    SQL
  end
end
