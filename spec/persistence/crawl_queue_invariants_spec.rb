# frozen_string_literal: true

require "rails_helper"

# S-07-002 Crawl-queue database invariants (schemas/POSTGRESQL_SCHEMA.md :292/293/339;
# contracts/S-07.json MTX-030/MTX-058; DECISIONS OD-018). The properties that must hold in the
# database itself: forced tenant RLS on the three new tables, the least-privilege runtime matrix
# (crawl_sources is T-IMM even at the grant layer; no DELETE anywhere), the OD-018 DB backstops on
# `evaluations`, and the evaluations immutability/lifecycle guard.
#
# Exercised via the BYPASSRLS superuser connection (the runtime role and even the schema owner are
# subject to FORCE RLS). `crawls`/`evaluations` FK only to `projects`, so a draft Project suffices;
# the `crawls`/`crawl_sources` guards are exercised on real rows in spec/acceptance/wf005_queue_crawl_spec.rb.
RSpec.describe "Crawl-queue invariants", type: :model do
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

  def insert_evaluation(pid, kind: "initial", state: "pending", crawl_id: SecureRandom.uuid_v7, slot: false, organization_id: org)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id, pid, kind, crawl_id, state, slot])
      INSERT INTO evaluations
        (id, created_at, updated_at, correlation_id, organization_id, project_id, kind, crawl_id, state, orchestration_slot_active)
      VALUES ($1,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,$4,$5::uuid,$6,$7)
    SQL
    id
  end

  describe "tenancy and least privilege" do
    { "crawls" => %w[INSERT SELECT UPDATE], "crawl_sources" => %w[INSERT SELECT], "evaluations" => %w[INSERT SELECT UPDATE] }.each do |table, grants|
      it "forces row level security on #{table} with the tenant-context policy" do
        rel = DbInspector.one("SELECT relrowsecurity AS e, relforcerowsecurity AS f FROM pg_class WHERE relname = $1", [table])
        expect(rel["e"]).to eq("t")
        expect(rel["f"]).to eq("t")
        policy = DbInspector.one("SELECT qual FROM pg_policies WHERE tablename = $1 AND policyname = $2", [table, "#{table}_context"])
        expect(policy["qual"]).to include("f1_current_context_org")
      end

      it "grants the runtime role exactly #{grants.join('/')} on #{table} (never DELETE)" do
        privs = DbInspector.all(<<~SQL, [table]).map { |r| r["privilege_type"] }.sort
          SELECT privilege_type FROM information_schema.role_table_grants
          WHERE table_name = $1 AND grantee = 'f1_runtime'
        SQL
        expect(privs).to eq(grants)
        expect(privs).not_to include("DELETE")
      end
    end
  end

  describe "the OD-018 database backstops on evaluations" do
    it "permits at most one active orchestration slot per Project" do
      pid = draft_project
      insert_evaluation(pid, slot: true)
      expect { insert_evaluation(pid, slot: true, crawl_id: SecureRandom.uuid_v7) }
        .to raise_error(PG::UniqueViolation, /evaluations_orchestration_slot_unique/)
    end

    it "permits at most one initial Evaluation per Crawl" do
      pid = draft_project
      cid = SecureRandom.uuid_v7
      insert_evaluation(pid, kind: "initial", crawl_id: cid)
      expect { insert_evaluation(pid, kind: "initial", crawl_id: cid) }
        .to raise_error(PG::UniqueViolation, /evaluations_initial_per_crawl_unique/)
    end

    it "allows two non-slot initial Evaluations for DIFFERENT Crawls" do
      pid = draft_project
      insert_evaluation(pid, kind: "initial", crawl_id: SecureRandom.uuid_v7)
      expect { insert_evaluation(pid, kind: "initial", crawl_id: SecureRandom.uuid_v7) }.not_to raise_error
    end

    it "requires an initial Evaluation to carry its crawl_id (closes the NULL-crawl_id backstop hole)" do
      pid = draft_project
      expect { insert_evaluation(pid, kind: "initial", crawl_id: nil) }
        .to raise_error(PG::CheckViolation, /evaluations_initial_requires_crawl/)
      # a non-initial Evaluation may have a null crawl_id
      expect { insert_evaluation(pid, kind: "retry", crawl_id: nil) }.not_to raise_error
    end
  end

  describe "the evaluations immutability/lifecycle guard" do
    it "refuses DELETE, refuses identity edits, and refuses every state transition" do
      pid = draft_project
      eid = insert_evaluation(pid, state: "pending")
      expect { conn.exec_params("DELETE FROM evaluations WHERE id = $1::uuid", [eid]) }
        .to raise_error(PG::RaiseException, /evaluation_immutable/)
      expect { conn.exec_params("UPDATE evaluations SET kind = 'retry' WHERE id = $1::uuid", [eid]) }
        .to raise_error(PG::RaiseException, /evaluation_facts_immutable/)
      expect { conn.exec_params("UPDATE evaluations SET state = 'running' WHERE id = $1::uuid", [eid]) }
        .to raise_error(PG::RaiseException, /evaluation_transition_unavailable/)
    end
  end
end
