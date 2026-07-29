# frozen_string_literal: true

require "rails_helper"

# S-07-008 limit-decision database invariants (schemas/POSTGRESQL_SCHEMA.md :300;
# WORKFLOW_SPECIFICATIONS.md :442; API_CONTRACTS.md `crawl_limit_decision`).
#
# Every other crawl table has one of these and this one shipped without it — the ADR-026 security
# lens's finding. The gap mattered more than usual here, because the tranche's completion report
# cited `verify_runtime`'s "15 checks, RLS intact" in a way that implied coverage: that task is a
# FIXED list over `sessions`, `accounts`, `scheduled_actions` and the transport functions, it never
# mentions this table, and it would pass identically if the table had no RLS at all.
#
# So these assert, against a live database rather than by reading the migration: forced tenant RLS
# on both policy limbs, the least-privilege runtime matrix, the three-column FK that rejects a
# same-Organization cross-Project Crawl, :442's once-per-dimension-and-run unique, the soft/hard
# biconditional, and T-IMM on both UPDATE and DELETE.
RSpec.describe "Crawl limit-decision invariants", type: :model do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization(display_name: "Acme Org") }
  def conn = DbInspector.connection

  def draft_project(organization_id: org)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id])
      INSERT INTO projects
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
         display_name, locale, time_zone, objective, state, source_set_version)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,'P','en-AU','UTC','discoverability_assessment','draft',0)
    SQL
    id
  end

  def insert_crawl(pid, organization_id: org)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id, pid])
      INSERT INTO crawls
        (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id, kind,
         requested_entitlement_policy_id, requested_entitlement_policy_version, trigger_kind, queued_at, state)
      VALUES ($1,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,'root',
              gen_random_uuid(),'entitlement-interim-v1','manual',now(),'queued')
    SQL
    id
  end

  def context
    pid = draft_project
    { org:, project: pid, crawl: insert_crawl(pid) }
  end

  DIGEST = ("\x11" * 32).b

  def insert_decision(ctx, dimension: "accounted_response_body_bytes_per_run", threshold: "hard",
                      value: nil, reason: nil, versions: '[{"artifact_type":"global_crawl_safety"}]',
                      configured: 100, observed: 100)
    id = SecureRandom.uuid_v7
    value ||= threshold == "soft" ? "soft_reached" : "hard_reached"
    reason = threshold == "hard" ? (reason || "limit_reached") : reason
    params = [id, ctx[:org], ctx[:project], ctx[:crawl], dimension, threshold, value,
              reason, versions, { value: DIGEST, format: 1 }, configured, observed]
    conn.exec_params(<<~SQL, params)
      INSERT INTO crawl_limit_decisions
        (id, schema_version, created_at, correlation_id, causation_id, organization_id, project_id,
         crawl_id, limit_dimension, threshold_kind, configured_value, observed_value,
         affected_source_count, affected_url_count, decision_type, decision_value, decision_status,
         decision_reason_code, decided_by_service_identity_id, definition_versions,
         input_sha256, output_sha256, decided_at)
      VALUES ($1,'1.0',now(),gen_random_uuid(),gen_random_uuid(),$2::uuid,$3::uuid,
              $4::uuid,$5,$6,$11,$12,
              0,0,'crawl_limit_observation',$7,'final',
              $8,gen_random_uuid(),$9::jsonb,
              $10,$10,now())
    SQL
    id
  end

  describe "tenancy and least privilege" do
    it "forces row level security with the tenant-context policy on BOTH limbs" do
      rel = DbInspector.one("SELECT relrowsecurity AS e, relforcerowsecurity AS f FROM pg_class WHERE relname = $1",
                            ["crawl_limit_decisions"])
      expect(rel["e"]).to eq("t")
      expect(rel["f"]).to eq("t")
      policy = DbInspector.one("SELECT qual, with_check FROM pg_policies WHERE tablename = $1 AND policyname = $2",
                               %w[crawl_limit_decisions crawl_limit_decisions_context])
      expect(policy["qual"]).to include("f1_current_context_org")
      expect(policy["with_check"]).to include("f1_current_context_org")
    end

    it "grants the runtime role exactly SELECT/INSERT — a decision is never updated or deleted" do
      privs = DbInspector.all(<<~SQL, ["crawl_limit_decisions"]).map { |r| r["privilege_type"] }.sort
        SELECT privilege_type FROM information_schema.role_table_grants
        WHERE table_name = $1 AND grantee = 'f1_runtime'
      SQL
      expect(privs).to eq(%w[INSERT SELECT])
    end

    it "rejects a decision naming a Crawl from another Project of the same Organization" do
      # POSTGRESQL_SCHEMA :128, and the defect class that has now appeared in four consecutive
      # tranches. RLS is Organization-scoped, so it does NOT catch this — the composite FK does.
      c = context
      other = context
      expect { insert_decision(c.merge(crawl: other[:crawl])) }
        .to raise_error(PG::ForeignKeyViolation, /crawl_limit_decisions_crawl_fk/)
    end
  end

  describe ":442's 'exactly once per dimension and run'" do
    it "permits one decision per (crawl, dimension, threshold) and refuses the second" do
      c = context
      insert_decision(c)
      expect { insert_decision(c) }.to raise_error(PG::UniqueViolation, /crawl_limit_decisions_once/)
    end

    it "keeps the dimensions and the thresholds independent" do
      c = context
      insert_decision(c, threshold: "hard")
      expect { insert_decision(c, threshold: "soft") }.not_to raise_error
      expect { insert_decision(c, dimension: "wall_clock_run_duration") }.not_to raise_error
    end

    it "scopes the once-ness to the RUN, so another Crawl may record the same dimension" do
      c = context
      insert_decision(c)
      expect { insert_decision(context) }.not_to raise_error
    end
  end

  describe "the recorded shape" do
    it "refuses a dimension outside the ratified twelve" do
      expect { insert_decision(context, dimension: "made_up_dimension") }
        .to raise_error(PG::CheckViolation, /limit_dimension/)
    end

    it "refuses a soft decision carrying a hard reason" do
      expect { insert_decision(context, threshold: "soft", reason: "limit_reached") }
        .to raise_error(PG::CheckViolation, /threshold_agreement/)
    end

    it "refuses a hard decision with no reason" do
      c = context
      params = [SecureRandom.uuid_v7, c[:org], c[:project], c[:crawl], { value: DIGEST, format: 1 }]
      expect do
        conn.exec_params(<<~SQL, params)
          INSERT INTO crawl_limit_decisions
            (id, schema_version, created_at, correlation_id, causation_id, organization_id, project_id,
             crawl_id, limit_dimension, threshold_kind, configured_value, observed_value,
             affected_source_count, affected_url_count, decision_type, decision_value, decision_status,
             decision_reason_code, decided_by_service_identity_id, definition_versions,
             input_sha256, output_sha256, decided_at)
          VALUES ($1,'1.0',now(),gen_random_uuid(),gen_random_uuid(),$2::uuid,$3::uuid,
                  $4::uuid,'redirects_per_url','hard',10,11,0,0,'crawl_limit_observation','hard_reached','final',
                  NULL,gen_random_uuid(),'[{"a":1}]'::jsonb,$5,$5,now())
        SQL
      end.to raise_error(PG::CheckViolation, /threshold_agreement/)
    end

    it "refuses an empty governing-version set" do
      expect { insert_decision(context, versions: "[]") }
        .to raise_error(PG::CheckViolation, /definition_versions_shape/)
    end

    it "refuses a negative configured or observed value" do
      expect { insert_decision(context, configured: -1) }.to raise_error(PG::CheckViolation)
    end
  end

  describe "T-IMM — a limit observation is a fact about a moment" do
    it "is never updatable" do
      c = context
      id = insert_decision(c)
      expect { conn.exec_params("UPDATE crawl_limit_decisions SET observed_value = 1 WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /crawl_limit_decision_immutable/)
    end

    it "is never deletable" do
      c = context
      id = insert_decision(c)
      expect { conn.exec_params("DELETE FROM crawl_limit_decisions WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /crawl_limit_decision_immutable/)
    end
  end
end
