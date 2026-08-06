# frozen_string_literal: true

# THE DURABLE HANDOFF MUST NOT CROSS A PROJECT BOUNDARY (S-07-010 review, round 1, finding R1-1).
#
# POSTGRESQL_SCHEMA.md :128 requires every Project-owned child-to-parent reference to carry all three
# of `(organization_id, project_id, id)`, "RATHER THAN A SEPARATE PROJECT LOOKUP OR APPLICATION
# ASSERTION". `ingestion_jobs.evidence_id` carried two, so a job in Project A could name Evidence
# belonging to Project B of the same Organization. MEASURED, NOT INFERRED: the review drove the
# INSERT/UPDATE live as the schema owner and the database ACCEPTED it.
#
# THIS IS FU-7's DEFECT CLASS, FOURTH OCCURRENCE. FU-7 records it in `evaluation_orchestration_contexts`
# (ADR-076), in `crawl_frontier_entries.scope_policy_id` (ADR-078) and in S-07-005's read path
# (ADR-079), with the standing observation that "the rule is easy to violate silently and nothing
# mechanically detects it". It is acceptance-blocking here rather than cosmetic because MTX-008 makes
# `evidence_id` THE durable handoff, :472 makes the parse manifest read it, and :472 classes a
# cross-tenant reference as `input_manifest_invalid` and forbids an implementation from silently
# dropping it. A wrong-Project Evidence link is that error committed one boundary in.
#
# WHY A TRIGGER AND NOT THE THREE-COLUMN FOREIGN KEY. The three-column form needs
# `UNIQUE (organization_id, project_id, id)` on `evidence`, and `evidence` is F-03's table.
# AUTONOMY_POLICY makes any change to a frozen foundation an owner decision, and ADR-029's refinement
# admits exactly one additive exception — a new-table grant in `lib/f1/runtime_grants.rb` — which this
# is not. So the containment is enforced from the table S-07-010 OWNS, at the moment the link is
# written, which is the same guarantee at the same instant without touching a frozen surface. FU-68
# carries the structural form for whoever owns F-03 next.
#
# THE CHECK READS THE SAME THREE COLUMNS THE FK WOULD HAVE. `source_id` is included because :462 keys
# the job to one Source and the Evidence F-03 produces for it carries that Source; a link that agreed
# on Project and disagreed on Source would still be a handoff to the wrong artifact.
class IngestionJobEvidenceContainment < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION f1_ingestion_job_evidence_contained() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public
      AS $$
      DECLARE contained boolean;
      BEGIN
        IF NEW.evidence_id IS NULL THEN
          RETURN NEW;
        END IF;

        -- `e.source_id IS NOT NULL AND e.source_id = NEW.source_id` rather than a NULL-safe
        -- comparison operator, and the difference is exactness rather than style. `evidence.source_id`
        -- is nullable — SCORE_EVIDENCE_MODEL.md makes it "nullable only for project-level external
        -- measurements" — while `ingestion_jobs.source_id` is NOT NULL, so the only reachable NULL is
        -- on the Evidence side and it means the Evidence is not Source-scoped at all. That is a
        -- refusal, not an unknown. Plain `=` would yield NULL and be misreported below as an
        -- UNREADABLE row, which is a different failure with a different meaning.
        SELECT e.organization_id = NEW.organization_id
                 AND e.project_id = NEW.project_id
                 AND e.source_id IS NOT NULL AND e.source_id = NEW.source_id
          INTO contained
        FROM evidence e
        WHERE e.id = NEW.evidence_id;

        -- FAIL CLOSED ON AN UNREADABLE ROW. The foreign key guarantees the Evidence exists, so an
        -- invisible one means this statement is running outside a proved Organization context — and a
        -- handoff may not be admitted on the strength of a check that could not run. The same rule
        -- `f1_crawl_child_fact_closed` applies to a Crawl it cannot read.
        IF contained IS NULL THEN
          RAISE EXCEPTION 'ingestion_job_evidence_unreadable' USING ERRCODE = 'raise_exception';
        END IF;
        IF NOT contained THEN
          RAISE EXCEPTION 'ingestion_job_evidence_out_of_scope' USING ERRCODE = 'raise_exception';
        END IF;

        RETURN NEW;
      END;
      $$;

      -- ON INSERT AS WELL AS UPDATE. The success path only ever sets `evidence_id` by UPDATE, but a
      -- constraint that governs one statement kind and not the other is a constraint with a door in
      -- it, and nothing about the column makes an INSERT unreachable.
      CREATE TRIGGER ingestion_jobs_evidence_containment
        BEFORE INSERT OR UPDATE OF evidence_id ON ingestion_jobs
        FOR EACH ROW EXECUTE FUNCTION f1_ingestion_job_evidence_contained();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS ingestion_jobs_evidence_containment ON ingestion_jobs;
      DROP FUNCTION IF EXISTS f1_ingestion_job_evidence_contained();
    SQL
  end
end
