# frozen_string_literal: true

require "rails_helper"

# S-07-003 crawl-start database invariants (schemas/POSTGRESQL_SCHEMA.md :292/:340;
# contracts/S-07.json MTX-030 start limb; DECISIONS OD-018). The properties that must hold in the
# database itself, independently of the application: forced tenant RLS and the least-privilege
# runtime matrix on `evaluation_orchestration_contexts`, its T-IMM guard and composite tenant FKs,
# and the exact set of Crawl state edges the guard now permits.
#
# Exercised via the BYPASSRLS superuser connection (the runtime role and even the schema owner are
# subject to FORCE RLS); the same guards are exercised on REAL rows produced by the workflow in
# spec/acceptance/wf005_start_crawl_spec.rb.
RSpec.describe "Crawl-start invariants", type: :model do
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

  # A Crawl in an arbitrary state. `crawls` FKs only to `projects`, so a draft Project suffices;
  # the guard is BEFORE UPDATE OR DELETE, so any starting state can be inserted.
  def insert_crawl(pid, state: "queued", organization_id: org)
    id = SecureRandom.uuid_v7
    terminal = %w[completed failed canceled].include?(state) ? "now()" : "NULL"
    conn.exec_params(<<~SQL, [id, organization_id, pid, state])
      INSERT INTO crawls
        (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id, kind,
         requested_entitlement_policy_id, requested_entitlement_policy_version, trigger_kind,
         queued_at, terminal_at, state)
      VALUES ($1,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,'root',
              gen_random_uuid(),'entitlement-interim-v1','manual',
              now(),#{terminal},$4)
    SQL
    id
  end

  def insert_evaluation(pid, crawl_id, organization_id: org, state: "pending")
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id, pid, crawl_id, state])
      INSERT INTO evaluations
        (id, created_at, updated_at, correlation_id, organization_id, project_id, kind, crawl_id, state)
      VALUES ($1,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,'initial',$4::uuid,$5)
    SQL
    id
  end

  def insert_decision(organization_id: org)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id, Platform::ServiceIdentity.scheduled_action_executor])
      INSERT INTO entitlement_decisions
        (id, created_at, decided_at, correlation_id, organization_id, service_identity_id, operation,
         usage_unit, requested_units, policy_version, plan_version, idempotency_key_digest,
         decision, reason_code, recovery_action)
      VALUES ($1,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,'crawl.start',
              'crawl_run',1,'entitlement-interim-v1','interim-baseline-plan-v1',sha256('k'),
              'allow','within_limit','none')
    SQL
    id
  end

  def insert_context(pid, crawl_id, evaluation_id, decision_id, organization_id: org, **overrides)
    id = SecureRandom.uuid_v7
    row = { organization_id:, project_id: pid, crawl_id:, evaluation_id:, decision_id: }.merge(overrides)
    conn.exec_params(<<~SQL, [id, row[:organization_id], row[:project_id], row[:evaluation_id], row[:crawl_id], row[:decision_id]])
      INSERT INTO evaluation_orchestration_contexts
        (id, created_at, correlation_id, organization_id, project_id, evaluation_id, crawl_id,
         root_entitlement_decision_id)
      VALUES ($1,now(),gen_random_uuid(),$2::uuid,$3::uuid,$4::uuid,$5::uuid,$6::uuid)
    SQL
    id
  end

  # One committed accepted-start shape: Crawl, its initial Evaluation, its Decision and context.
  def started(organization_id: org)
    pid = draft_project(organization_id:)
    cid = insert_crawl(pid, state: "running", organization_id:)
    eid = insert_evaluation(pid, cid, organization_id:)
    did = insert_decision(organization_id:)
    { project_id: pid, crawl_id: cid, evaluation_id: eid, decision_id: did,
      context_id: insert_context(pid, cid, eid, did, organization_id:) }
  end

  describe "tenancy and least privilege on evaluation_orchestration_contexts" do
    it "forces row level security with the tenant-context policy" do
      rel = DbInspector.one("SELECT relrowsecurity AS e, relforcerowsecurity AS f FROM pg_class WHERE relname = $1",
                            ["evaluation_orchestration_contexts"])
      expect(rel["e"]).to eq("t")
      expect(rel["f"]).to eq("t")
      policy = DbInspector.one("SELECT qual, with_check FROM pg_policies WHERE tablename = $1 AND policyname = $2",
                               %w[evaluation_orchestration_contexts evaluation_orchestration_contexts_context])
      expect(policy["qual"]).to include("f1_current_context_org")
      expect(policy["with_check"]).to include("f1_current_context_org")
    end

    it "grants the runtime role exactly SELECT/INSERT (T-IMM — never UPDATE or DELETE)" do
      privs = DbInspector.all(<<~SQL, ["evaluation_orchestration_contexts"]).map { |r| r["privilege_type"] }.sort
        SELECT privilege_type FROM information_schema.role_table_grants
        WHERE table_name = $1 AND grantee = 'f1_runtime'
      SQL
      expect(privs).to eq(%w[INSERT SELECT])
    end

    it "hides another Organization's orchestration context from a proved runtime context" do
      other = started(organization_id: TenantSeeder.create_organization(display_name: "Rival"))
      visible = Platform::UnitOfWork.run do |c|
        pg = c.raw_connection
        pg.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, SecureRandom.uuid_v7])
        pg.exec_params("SELECT count(*) AS n FROM evaluation_orchestration_contexts WHERE id = $1::uuid",
                       [other[:context_id]]).to_a.first["n"].to_i
      end
      expect(visible).to eq(0)
    end
  end

  describe "the orchestration-context immutability guard and keys" do
    it "refuses every UPDATE and DELETE (T-IMM)" do
      s = started
      expect { conn.exec_params("UPDATE evaluation_orchestration_contexts SET crawl_policy_version = 'x' WHERE id = $1::uuid", [s[:context_id]]) }
        .to raise_error(PG::RaiseException, /evaluation_orchestration_context_immutable/)
      expect { conn.exec_params("DELETE FROM evaluation_orchestration_contexts WHERE id = $1::uuid", [s[:context_id]]) }
        .to raise_error(PG::RaiseException, /evaluation_orchestration_context_immutable/)
    end

    it "permits at most one orchestration context per Evaluation" do
      s = started
      expect { insert_context(s[:project_id], s[:crawl_id], s[:evaluation_id], s[:decision_id]) }
        .to raise_error(PG::UniqueViolation, /evaluation_orchestration_contexts_evaluation_unique/)
    end

    it "rejects a context whose Evaluation, Crawl or Decision belongs to another Organization" do
      rival = TenantSeeder.create_organization(display_name: "Rival")
      pid = draft_project
      their_project = draft_project(organization_id: rival)
      their_crawl = insert_crawl(their_project, organization_id: rival)
      their_evaluation = insert_evaluation(their_project, their_crawl, organization_id: rival)
      their_decision = insert_decision(organization_id: rival)

      # Each composite tenant FK is (organization_id, ...), so naming a rival's row under my
      # organization_id resolves to no parent row at all.
      expect { insert_context(pid, insert_crawl(pid), their_evaluation, insert_decision) }
        .to raise_error(PG::ForeignKeyViolation, /evaluation_orchestration_contexts_evaluation_fk/)
      cid = insert_crawl(pid)
      expect { insert_context(pid, their_crawl, insert_evaluation(pid, cid), insert_decision) }
        .to raise_error(PG::ForeignKeyViolation, /evaluation_orchestration_contexts_crawl_fk/)
      cid2 = insert_crawl(pid)
      expect { insert_context(pid, cid2, insert_evaluation(pid, cid2, state: "completed"), their_decision) }
        .to raise_error(PG::ForeignKeyViolation, /evaluation_orchestration_contexts_decision_fk/)
    end
  end

  describe "the exact Crawl state edges the guard permits after S-07-003" do
    it "permits queued -> running and queued -> failed" do
      pid = draft_project
      running = insert_crawl(pid)
      expect { conn.exec_params("UPDATE crawls SET state = 'running', started_at = now() WHERE id = $1::uuid", [running]) }
        .not_to raise_error
      failed = insert_crawl(pid)
      expect { conn.exec_params("UPDATE crawls SET state = 'failed', terminal_at = now(), completion_reason = 'hard_limit_exceeded' WHERE id = $1::uuid", [failed]) }
        .not_to raise_error
    end

    it "still refuses every other edge, including the running terminals later tranches own" do
      pid = draft_project
      %w[completed canceled].each do |target|
        cid = insert_crawl(pid)
        expect { conn.exec_params("UPDATE crawls SET state = $2, terminal_at = now() WHERE id = $1::uuid", [cid, target]) }
          .to raise_error(PG::RaiseException, /crawl_transition_unavailable queued -> #{target}/)
      end
      running = insert_crawl(pid, state: "running")
      %w[completed failed canceled].each do |target|
        expect { conn.exec_params("UPDATE crawls SET state = $2, terminal_at = now() WHERE id = $1::uuid", [running, target]) }
          .to raise_error(PG::RaiseException, /crawl_transition_unavailable running -> #{target}/)
      end
    end

    it "keeps the pinned request facts frozen across the start edge" do
      cid = insert_crawl(draft_project)
      expect { conn.exec_params("UPDATE crawls SET state = 'running', queued_at = now() WHERE id = $1::uuid", [cid]) }
        .to raise_error(PG::RaiseException, /crawl_facts_immutable/)
      expect { conn.exec_params("UPDATE crawls SET requested_crawl_policy_version = 'x' WHERE id = $1::uuid", [cid]) }
        .to raise_error(PG::RaiseException, /crawl_facts_immutable/)
    end
  end
end
