# frozen_string_literal: true

require "rails_helper"

# S-03 Project setup database invariants (schemas/POSTGRESQL_SCHEMA.md :283;
# WORKFLOW_SPECIFICATIONS.md :664, :671; contracts/S-03.json MTX-027, MTX-055).
#
# The properties that must hold in the database itself, not in a handler: forced
# tenant RLS, the least-privilege runtime matrix (no DELETE), the immutable
# creation profile, the withheld state transition, the applicability/profile
# shape, and the deliberate absence of any Source schema in this tranche.
RSpec.describe "Project setup invariants", type: :model do
  self.use_transactional_tests = false

  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization(display_name: "Acme Org") }
  def conn = DbInspector.connection

  def insert_draft(organization_id: org, **columns)
    id = SecureRandom.uuid_v7
    base = { display_name: "P", locale: "en-AU", time_zone: "UTC", objective: "discoverability_assessment" }
    row = base.merge(columns)
    conn.exec_params(<<~SQL, [id, organization_id, row[:display_name], row[:locale], row[:time_zone], row[:objective]])
      INSERT INTO projects
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
         display_name, locale, time_zone, objective, state, source_set_version)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,$3,$4,$5,$6,'draft',0)
    SQL
    id
  end

  describe "tenancy and least privilege" do
    it "forces row level security on projects with the tenant-context policy" do
      rel = DbInspector.one("SELECT relrowsecurity AS e, relforcerowsecurity AS f FROM pg_class WHERE relname = 'projects'")
      expect(rel["e"]).to eq("t")
      expect(rel["f"]).to eq("t")
      policy = DbInspector.one("SELECT qual FROM pg_policies WHERE tablename = 'projects' AND policyname = 'projects_context'")
      expect(policy["qual"]).to include("f1_current_context_org")
    end

    it "grants the runtime role SELECT, INSERT and UPDATE on projects but never DELETE" do
      privs = DbInspector.all(<<~SQL).map { |r| r["privilege_type"] }.sort
        SELECT privilege_type FROM information_schema.role_table_grants
        WHERE table_name = 'projects' AND grantee = 'f1_runtime'
      SQL
      expect(privs).to eq(%w[INSERT SELECT UPDATE])
      expect(privs).not_to include("DELETE")
    end
  end

  describe "the projects lifecycle guard" do
    it "refuses any state transition while activation is unavailable (OD-014 / no Source subsystem)" do
      id = insert_draft
      %w[active paused archived].each do |state|
        expect { conn.exec_params("UPDATE projects SET state = $2 WHERE id = $1::uuid", [id, state]) }
          .to raise_error(PG::RaiseException, /project_lifecycle_transition_unavailable/)
      end
      expect(DbInspector.one("SELECT state FROM projects WHERE id = $1::uuid", [id])["state"]).to eq("draft")
    end

    it "keeps the Project's Organization identity immutable" do
      id = insert_draft
      other = TenantSeeder.create_organization
      expect { conn.exec_params("UPDATE projects SET organization_id = $2::uuid WHERE id = $1::uuid", [id, other]) }
        .to raise_error(PG::RaiseException, /project_organization_immutable/)
    end

    it "keeps the creation profile immutable" do
      id = insert_draft
      expect { conn.exec_params("UPDATE projects SET display_name = 'changed' WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /project_profile_immutable/)
      expect { conn.exec_params("UPDATE projects SET objective = 'brand_lift' WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /project_profile_immutable/)
    end
  end

  describe "the applicability/profile shape check" do
    it "accepts the reduced genesis body with every profile field null" do
      expect { insert_draft }.not_to raise_error
    end

    it "rejects a local-presence applicability without its profile metadata" do
      expect do
        conn.exec_params(<<~SQL, [SecureRandom.uuid_v7, org])
          INSERT INTO projects
            (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
             display_name, locale, time_zone, objective, state, source_set_version, local_presence_applicable)
          VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,'P','en-AU','UTC','discoverability_assessment','draft',0,true)
        SQL
      end.to raise_error(PG::CheckViolation, /projects_local_profile_shape/)
    end
  end

  describe "no Source subsystem in this tranche" do
    it "has no sources table" do
      expect(DbInspector.one("SELECT to_regclass('public.sources') AS t")["t"]).to be_nil
    end
  end
end
