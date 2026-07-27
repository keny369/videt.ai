# frozen_string_literal: true

require "rails_helper"

# crawl_policies persistence invariants (S-07-001; DECISIONS ADR-068). A dedicated immutable
# versioned crawl policy table: FORCE RLS, immutable content, a single active -> superseded
# lifecycle edge, one active version per (Organization, scope, Project), DELETE refused.
# Exercised directly against the deployed guard via the BYPASSRLS superuser connection.
RSpec.describe "crawl_policies invariants", type: :model do
  self.use_transactional_tests = false
  # TRUNCATE does not fire the BEFORE DELETE guard (which refuses DELETE), so it is the
  # teardown path for an insert-only/immutable table.
  after { conn.exec("TRUNCATE crawl_policies") }

  def conn = DbInspector.connection
  def bytea(b) = { value: b, format: 1 }
  def bounds_json = JSON.generate(Workflows::Wf005::CrawlPolicy::GLOBAL_CEILING)

  def insert_active(org: SecureRandom.uuid_v7, scope: "organization", project_id: nil,
                    version: "crawl-policy-organization-v1", id: SecureRandom.uuid_v7)
    conn.exec_params(<<~SQL, [id, org, project_id, scope, version, bounds_json, bytea(Digest::SHA256.digest("x"))])
      INSERT INTO crawl_policies
        (id, state_version, created_at, updated_at, correlation_id, schema_version, organization_id,
         project_id, scope, policy_version, state, supersedes_id, activated_by_account_id,
         normalized_bounds, content_sha256, superseded_at)
      VALUES ($1::uuid,0,now(),now(),gen_random_uuid(),'crawl-policy-v1',$2::uuid,
              $3::uuid,$4,$5,'active',NULL,gen_random_uuid(),$6::jsonb,$7,NULL)
    SQL
    { id:, org: }
  end

  describe "tenancy and least privilege" do
    it "forces row level security with the tenant-context policy" do
      row = conn.exec("SELECT relrowsecurity, relforcerowsecurity FROM pg_class WHERE relname='crawl_policies'").first
      expect(row["relrowsecurity"]).to eq("t")
      expect(row["relforcerowsecurity"]).to eq("t")
    end

    it "grants the runtime role SELECT, INSERT, UPDATE and NOT DELETE" do
      privs = conn.exec_params(
        "SELECT privilege_type FROM information_schema.role_table_grants WHERE table_name='crawl_policies' AND grantee='f1_runtime'", []
      ).map { |r| r["privilege_type"] }.sort
      expect(privs).to include("SELECT", "INSERT", "UPDATE")
      expect(privs).not_to include("DELETE")
    end
  end

  describe "the active -> superseded lifecycle edge and content immutability" do
    it "permits active -> superseded (stamping superseded_at)" do
      p = insert_active
      expect { conn.exec_params("UPDATE crawl_policies SET state='superseded', superseded_at=now() WHERE id=$1::uuid", [p[:id]]) }
        .not_to raise_error
    end

    it "refuses a content mutation on an active row (including the primary key)" do
      p = insert_active
      expect { conn.exec_params("UPDATE crawl_policies SET normalized_bounds='{}'::jsonb WHERE id=$1::uuid", [p[:id]]) }
        .to raise_error(PG::RaiseException, /crawl_policy_facts_immutable/)
      expect { conn.exec_params("UPDATE crawl_policies SET policy_version='x' WHERE id=$1::uuid", [p[:id]]) }
        .to raise_error(PG::RaiseException, /crawl_policy_facts_immutable/)
      # ADR-026 NB-2 hardening: id is frozen too (a supersession UPDATE cannot re-key the row).
      expect { conn.exec_params("UPDATE crawl_policies SET id=gen_random_uuid(), state='superseded', superseded_at=now() WHERE id=$1::uuid", [p[:id]]) }
        .to raise_error(PG::RaiseException, /crawl_policy_facts_immutable/)
    end

    it "makes a superseded row fully immutable" do
      p = insert_active
      conn.exec_params("UPDATE crawl_policies SET state='superseded', superseded_at=now() WHERE id=$1::uuid", [p[:id]])
      expect { conn.exec_params("UPDATE crawl_policies SET state='active', superseded_at=NULL WHERE id=$1::uuid", [p[:id]]) }
        .to raise_error(PG::RaiseException, /crawl_policy_immutable/)
    end

    it "refuses any other state transition of an active row" do
      p = insert_active
      expect { conn.exec_params("UPDATE crawl_policies SET state='bogus' WHERE id=$1::uuid", [p[:id]]) }
        .to raise_error(PG::Error) # state CHECK or transition guard
    end

    it "refuses DELETE" do
      p = insert_active
      expect { conn.exec_params("DELETE FROM crawl_policies WHERE id=$1::uuid", [p[:id]]) }
        .to raise_error(PG::RaiseException, /crawl_policy_immutable/)
    end
  end

  describe "one active version per (Organization, scope, Project)" do
    it "refuses a second active organization-scope row for the same Organization" do
      p = insert_active(scope: "organization")
      expect { insert_active(org: p[:org], scope: "organization", version: "crawl-policy-organization-v2") }
        .to raise_error(PG::UniqueViolation, /crawl_policies_active_unique/)
    end

    it "allows a superseded row to coexist with a new active row" do
      p = insert_active
      conn.exec_params("UPDATE crawl_policies SET state='superseded', superseded_at=now() WHERE id=$1::uuid", [p[:id]])
      expect { insert_active(org: p[:org], version: "crawl-policy-organization-v2") }.not_to raise_error
    end
  end

  describe "shape CHECKs" do
    it "requires scope/project agreement (organization scope has no project)" do
      expect { insert_active(scope: "organization", project_id: SecureRandom.uuid_v7) }
        .to raise_error(PG::CheckViolation, /scope_project_agreement/)
    end
  end
end
