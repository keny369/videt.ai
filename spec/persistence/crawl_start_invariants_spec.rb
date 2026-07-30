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

  # S-07-003 review hardening (migration 20260727120160). POSTGRESQL_SCHEMA.md :128 requires every
  # Project-owned child-to-parent FK to carry all three of (organization_id, project_id, id) —
  # "these constraints, rather than a separate Project lookup or application assertion, prevent a
  # same-Organization cross-Project child link". The 1/n migration made the Evaluation limb
  # two-column, which admitted exactly that link.
  describe "the composite Project foreign keys" do
    it "rejects an orchestration context naming an Evaluation from another Project of the SAME Organization" do
      p1 = draft_project
      p2 = draft_project
      c1 = insert_crawl(p1)
      e2 = insert_evaluation(p2, insert_crawl(p2))
      expect { insert_context(p1, c1, e2, insert_decision) }
        .to raise_error(PG::ForeignKeyViolation, /evaluation_orchestration_contexts_evaluation_fk/)
    end

    it "rejects an Evaluation naming a Crawl from another Project of the same Organization" do
      p1 = draft_project
      foreign_crawl = insert_crawl(draft_project)
      expect { insert_evaluation(p1, foreign_crawl) }
        .to raise_error(PG::ForeignKeyViolation, /evaluations_crawl_fk/)
    end

    it "rejects a Crawl naming another Organization's entitlement Decision or reservation" do
      rival = TenantSeeder.create_organization(display_name: "Rival")
      their_decision = insert_decision(organization_id: rival)
      cid = insert_crawl(draft_project)
      expect { conn.exec_params("UPDATE crawls SET state='running', started_at=now(), entitlement_decision_id=$2::uuid WHERE id=$1::uuid", [cid, their_decision]) }
        .to raise_error(PG::ForeignKeyViolation, /crawls_entitlement_decision_fk/)
      expect { conn.exec_params("UPDATE crawls SET state='running', started_at=now(), entitlement_reservation_id=$2::uuid WHERE id=$1::uuid", [cid, SecureRandom.uuid_v7]) }
        .to raise_error(PG::ForeignKeyViolation, /crawls_entitlement_reservation_fk/)
    end
  end

  describe "the closed CompletionReason enum" do
    # WORKFLOW_SPECIFICATIONS.md :456; API_CONTRACTS.md :956/:1005 repeat it for the crawl_terminal
    # event schema and the WF-014 notification context.
    it "admits exactly the five ratified values and refuses a machine reason code" do
      %w[completed limit_reached partial_source_failure canceled failed].each do |reason|
        cid = insert_crawl(draft_project)
        expect { conn.exec_params("UPDATE crawls SET state='failed', terminal_at=now(), completion_reason=$2 WHERE id=$1::uuid", [cid, reason]) }
          .not_to raise_error
      end
      cid = insert_crawl(draft_project)
      expect { conn.exec_params("UPDATE crawls SET state='failed', terminal_at=now(), completion_reason='hard_limit_exceeded' WHERE id=$1::uuid", [cid]) }
        .to raise_error(PG::CheckViolation, /crawls_completion_reason_check/)
    end
  end

  describe "the exact Crawl state edges the guard permits after S-07-003" do
    it "permits queued -> running and queued -> failed" do
      pid = draft_project
      running = insert_crawl(pid)
      expect { conn.exec_params("UPDATE crawls SET state = 'running', started_at = now() WHERE id = $1::uuid", [running]) }
        .not_to raise_error
      failed = insert_crawl(pid)
      expect { conn.exec_params("UPDATE crawls SET state = 'failed', terminal_at = now(), completion_reason = 'failed' WHERE id = $1::uuid", [failed]) }
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

  # FU-11, S-07-009's BLOCKING PRECONDITION, repaired by `20260727120340_crawls_terminal_completeness`.
  #
  # A terminal Crawl could carry NULL in BOTH `coverage_status` and `completion_reason`, so a fully
  # covered run was byte-indistinguishable from one that recorded nothing — and S-07-009 writes exactly
  # those two columns. These insert TERMINAL ROWS DIRECTLY rather than driving the state machine, because
  # the property under test is the table's own, and the transition guard would otherwise mask it.
  describe "terminal completeness (FU-11)" do
    def insert_terminal(pid, state:, coverage_status: nil, completion_reason: nil, organization_id: org)
      conn.exec_params(<<~SQL, [SecureRandom.uuid_v7, organization_id, pid, state, coverage_status, completion_reason])
        INSERT INTO crawls
          (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id, kind,
           requested_entitlement_policy_id, requested_entitlement_policy_version, trigger_kind,
           queued_at, terminal_at, state, coverage_status, completion_reason)
        VALUES ($1,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,'root',
                gen_random_uuid(),'entitlement-interim-v1','manual',now(),now(),$4,$5,$6)
      SQL
    end

    it "PROOF 26 — a `completed` Crawl cannot be written with neither coverage nor a reason" do
      # THE DEFECT ITSELF, and it is the whole reason this is a precondition rather than an improvement.
      pid = draft_project
      expect { insert_terminal(pid, state: "completed") }
        .to raise_error(PG::CheckViolation, /crawls_terminal_shape/)

      # Nor with only one of the two. `completed` is the state :452's coverage denominator is read for,
      # so it is the one state that needs both.
      expect { insert_terminal(pid, state: "completed", completion_reason: "completed") }
        .to raise_error(PG::CheckViolation, /crawls_terminal_shape/)
      expect { insert_terminal(pid, state: "completed", coverage_status: "full") }
        .to raise_error(PG::CheckViolation, /crawls_terminal_shape/)

      expect { insert_terminal(pid, state: "completed", coverage_status: "full", completion_reason: "completed") }
        .not_to raise_error
    end

    it "PROOF 27 — every terminal state needs a reason, and only `completed` needs coverage" do
      # THE SCOPING IS THE REPAIR. Requiring BOTH columns on every terminal state is the obvious rule and
      # it is WRONG: `IdentityAccess::Infrastructure::CrawlStartStore#fail` is the only production writer
      # of `completion_reason` and records `failed` with a reason and NO coverage, correctly, because a
      # Crawl that failed before execution retrieved nothing there is coverage to report on.
      pid = draft_project
      %w[failed canceled].each do |state|
        expect { insert_terminal(pid, state:, completion_reason: state) }.not_to raise_error
        expect { insert_terminal(pid, state:) }
          .to raise_error(PG::CheckViolation, /crawls_terminal_shape/)
      end
    end

    it "PROOF 28 — the production fail path still writes the shape it has always written" do
      # Not a restatement of PROOF 27: this drives the REAL store rather than an insert shaped like it,
      # so a future change to `fail` that stopped setting a reason fails here.
      pid = draft_project
      cid = insert_crawl(pid)
      version = conn.exec_params("SELECT state_version FROM crawls WHERE id = $1::uuid", [cid])
                    .first.fetch("state_version").to_i

      expect do
        Platform::ScheduledActions::TransportConnection # loaded for parity with the store's own env
        IdentityAccess::Infrastructure::CrawlStartStore.new(conn).fail(cid, version, Time.now.utc)
      end.not_to raise_error

      row = conn.exec_params("SELECT * FROM crawls WHERE id = $1::uuid", [cid]).first
      expect(row.fetch("state")).to eq("failed")
      expect(row.fetch("completion_reason")).to eq("failed")
      expect(row.fetch("coverage_status")).to be_nil
    end

    it "PROOF 29 — a non-terminal Crawl still carries neither column, and that is unchanged" do
      pid = draft_project
      expect(conn.exec_params("SELECT coverage_status, completion_reason FROM crawls WHERE id = $1::uuid",
                              [insert_crawl(pid)]).first.values).to eq([nil, nil])

      # `crawls_coverage_status_check` is DELIBERATELY NOT the constraint that was changed. The earlier
      # diagnosis of FU-11 blamed it and prescribed a NULL-safe rewrite; that is a PROVEN NO-OP, because
      # `NULL = ANY(...)` is UNKNOWN and admitted, and `IS NOT DISTINCT FROM` is TRUE and also admitted.
      # Asserted here so the no-op cannot be reintroduced as a fix.
      admits_null = conn.exec_params(
        "SELECT (NULL::text = ANY (ARRAY['full','partial'])) IS NOT FALSE AS live_form,
                (NULL::text IS NULL OR NULL::text = ANY (ARRAY['full','partial'])) IS NOT FALSE AS null_safe_form"
      ).first
      # A CHECK admits UNKNOWN and admits TRUE, so both forms admit a NULL. The rewrite changes the
      # value and not the outcome, which is what makes it a no-op rather than a repair.
      #
      # Read through `Platform::PgBool` and not `== "t"`. This is a raw `PG.connect`, which yields the
      # STRING `"t"`, and the same tranche that added this file found a `== "t"` written against a
      # type-mapped connection that was therefore a constant false. Asserting `[true, true]` against
      # string values here would fail; asserting `["t", "t"]` would pass on this connection and break on
      # any other. One reader crosses both encodings.
      expect(admits_null.values.map { |v| Platform::PgBool.true?(v) }).to eq([true, true])
    end
  end
end
