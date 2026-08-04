# frozen_string_literal: true

require "rails_helper"

# OWNER RULING 2: A TERMINAL CRAWL HAS A CLOSED FACT SET (round-6 blockers R6-2 and R6-3).
#
# "Once a Crawl becomes terminal, no new child fact may be inserted for that Crawl. Treat a
# post-terminal child fact as a data-integrity violation, not as an accepted timing window. Own this
# rule at the database boundary so every producer is covered."
#
# THESE PROOFS READ THE CATALOGUE AND THE RUNTIME ROLE, NOT THE APPLICATION. The defect class this
# closes was repaired three times at one producer each — `CrawlDriver#retire` at B7/R2-B1, Admission's
# fall-through at R5-3 — and each repair left the other producers alone, so a proof that exercised one
# writer would prove exactly as much as those repairs did. The governed set is therefore DERIVED from
# `pg_constraint` and every member is probed as `f1_web` under FORCE RLS.
RSpec.describe "Crawl terminal fact closure", type: :model do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization(display_name: "Acme Org") }
  def conn = DbInspector.connection

  CLOSURE_FUNCTION = "f1_crawl_child_fact_closed"

  # NOT GOVERNED, each for a reason recorded in `20260727120390`'s header rather than by omission. A
  # new child table appears in neither list and fails PROOF 157 until someone classifies it, which is
  # the property this file exists to hold: the rule cannot be one producer behind again.
  UNGOVERNED_WITH_REASON = {
    "fetch_attempts" => "FU-32 is the open owner decision on pass-boundary cancellation; the rows are inert",
    "crawl_budget_counters" => "reservation bookkeeping; a late release is correct cleanup, not a fact",
    "crawl_sitemap_document_charges" => "run-wide budget bookkeeping, not a coverage fact",
    "crawl_sources" => "written at queue time, before any terminal state is reachable",
    "evaluations" => "WF-011's lifecycle, not a WF-005 post-terminal production path",
    "evaluation_orchestration_contexts" => "WF-011's lifecycle, not a WF-005 post-terminal production path"
  }.freeze

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

  # `f1_crawls_guard` admits `queued -> canceled`, and `crawls_terminal_shape` requires the terminal
  # instant and reason with it. This is the real edge a cancellation takes, not a fixture shortcut.
  def terminalize(crawl_id)
    conn.exec_params(<<~SQL, [crawl_id])
      UPDATE crawls SET state='canceled', terminal_at=now(), completion_reason='canceled',
                        state_version = state_version + 1, updated_at = now()
      WHERE id = $1::uuid
    SQL
  end

  def fixture
    pid = draft_project
    { pid:, crawl: insert_crawl(pid) }
  end

  # A `f1_web` transaction with the Organization context entered, exactly as every production caller
  # holds it. FORCE RLS applies to the schema owner too, so this is the only principal that proves
  # anything about what production may write.
  def as_runtime(organization_id)
    runtime = PgTestConnection.connect(user: "f1_web")
    runtime.exec("BEGIN")
    runtime.exec_params("SELECT f1_enter_org_context($1::uuid, $2::uuid)",
                        [organization_id, SecureRandom.uuid_v7])
    yield runtime
  ensure
    begin
      runtime&.exec("ROLLBACK")
    rescue StandardError
      nil
    end
    runtime&.close
  end

  def insert_limit_decision(pg, f, organization_id: org)
    pg.exec_params(<<~SQL, [SecureRandom.uuid_v7, organization_id, f[:pid], f[:crawl]])
      INSERT INTO crawl_limit_decisions
        (id, schema_version, created_at, correlation_id, causation_id, organization_id, project_id,
         crawl_id, limit_dimension, threshold_kind, configured_value, observed_value,
         affected_source_count, affected_url_count, decision_type, decision_value, decision_status,
         decision_reason_code, decided_by_service_identity_id, definition_versions, input_sha256,
         output_sha256, decided_at)
      VALUES ($1,'1.0',now(),gen_random_uuid(),gen_random_uuid(),$2::uuid,$3::uuid,$4::uuid,
              'wall_clock_run_duration','hard',60,60,1,1,'crawl_limit_observation','hard_reached','final',
              'limit_reached',gen_random_uuid(),'["v1"]'::jsonb,sha256(''::bytea),sha256(''::bytea),now())
    SQL
  end

  describe "the rule itself" do
    it "PROOF 153 — a governed child fact commits normally while the Crawl is NOT terminal" do
      # The closure must not be a blanket refusal. Every ordinary observation this subsystem makes
      # happens on a `queued` or `running` Crawl and must be untouched by it.
      f = fixture

      as_runtime(org) do |pg|
        expect { insert_limit_decision(pg, f) }.not_to raise_error
        expect(pg.exec_params("SELECT count(*) FROM crawl_limit_decisions WHERE crawl_id=$1::uuid",
                              [f[:crawl]]).getvalue(0, 0).to_i).to eq(1)
      end
    end

    it "PROOF 154 — the identical insert is REFUSED once the Crawl is terminal" do
      # THE CATALOGUE GAP ROUND 6 STATED, closed. `f1_runtime` still holds INSERT, the composite
      # foreign key is still satisfied and the RLS predicate still passes: the row is valid in every
      # respect except the one that matters, and only a rule about PARENT STATE can refuse it.
      f = fixture
      terminalize(f[:crawl])

      as_runtime(org) do |pg|
        expect { insert_limit_decision(pg, f) }
          .to raise_error(PG::RaiseException, /crawl_child_fact_after_terminal/)
      end
    end

    it "PROOF 155 — the refusal is the parent's STATE, not the runtime role's privileges" do
      # A different refusal with the same shape would satisfy PROOF 154 by accident. The schema owner
      # holds every privilege `f1_web` lacks and is refused identically, so the rule is the state.
      f = fixture
      terminalize(f[:crawl])

      expect { insert_limit_decision(conn, f) }
        .to raise_error(PG::RaiseException, /crawl_child_fact_after_terminal/)
    end
  end

  describe "every producer, derived rather than listed" do
    # Every table carrying a composite foreign key to `crawls`. Derived from the catalogue so a child
    # table added by a later tranche appears here without anyone remembering to add it.
    def crawl_child_tables
      DbInspector.all(<<~SQL).map { |r| r["child"] }
        SELECT DISTINCT c.relname AS child
        FROM pg_constraint con
        JOIN pg_class c ON c.oid = con.conrelid
        JOIN pg_class p ON p.oid = con.confrelid
        WHERE con.contype = 'f' AND p.relname = 'crawls'
        ORDER BY c.relname
      SQL
    end

    def closed_on_insert
      DbInspector.all(<<~SQL, [CLOSURE_FUNCTION]).map { |r| r["child"] }
        SELECT DISTINCT c.relname AS child
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_proc pr ON pr.oid = t.tgfoid
        WHERE NOT t.tgisinternal AND pr.proname = $1
          AND (t.tgtype & 4) <> 0
        ORDER BY c.relname
      SQL
    end

    it "PROOF 156 — every Crawl child table is either closed on INSERT or excluded with a reason" do
      unclassified = crawl_child_tables - closed_on_insert - UNGOVERNED_WITH_REASON.keys

      expect(unclassified).to be_empty, <<~MESSAGE
        A table carries a foreign key to `crawls` and is neither closed on INSERT by
        #{CLOSURE_FUNCTION} nor recorded as deliberately ungoverned: #{unclassified.join(', ')}.
        Owner ruling 2 makes a post-terminal child fact a data-integrity violation, so a new child
        table must be classified rather than defaulted.
      MESSAGE
      # And the exclusion list may not rot into a way of silencing this: every name in it must still
      # be a real Crawl child table.
      expect(UNGOVERNED_WITH_REASON.keys - crawl_child_tables).to be_empty
      expect(closed_on_insert).to include("crawl_limit_decisions", "crawl_terminal_outcomes",
                                          "crawl_frontier_entries", "crawl_frontier_occurrences",
                                          "crawl_host_gates")
    end

    it "PROOF 157 — the sitemap and robots OUTCOME columns are closed on UPDATE as well" do
      # R6-3's second variant is an UPDATE — `sitemap_unavailable` written onto a claimed gate after
      # the checkpoint had already counted `unresolved_discovery = 0` — so no INSERT rule can reach
      # it. The limb is narrowed to the outcome columns, and this asserts both halves of that: the
      # trigger exists on UPDATE, and its WHEN clause names the outcome rather than the whole row.
      definition = DbInspector.one(<<~SQL, [CLOSURE_FUNCTION])["def"]
        SELECT pg_get_triggerdef(t.oid) AS def
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_proc pr ON pr.oid = t.tgfoid
        WHERE NOT t.tgisinternal AND pr.proname = $1 AND c.relname = 'crawl_host_gates'
          AND (t.tgtype & 16) <> 0
      SQL

      # AFTER, not BEFORE, and PROOF 40b is why: PostgreSQL evaluates a policy's WITH CHECK limb on the
      # row a BEFORE trigger leaves behind, so a BEFORE trigger would run ahead of RLS and answer a
      # cross-tenant write with a state message instead of a tenant refusal.
      expect(definition).to include("AFTER UPDATE")
      # ALL SEVEN, NOT THE FOUR THAT WERE OBVIOUS (round 7, mutation-gap review). The round-6 form
      # asserted four columns, and narrowing the WHEN clause to drop `sitemap_limit_reasons`,
      # `robots_terminal_reason` and `robots_terminal_at` survived this proof AND the whole
      # 241-example persistence suite. `sitemap_limit_reasons` is coverage-bearing —
      # `CrawlStartStore#terminal_facts` sums it into `sitemap_limit_facts`, which
      # `TerminalSelection` turns into `limit_reached` and `partial` — so a late write to it can
      # contradict a frozen coverage record exactly as `sitemap_state` can.
      %w[sitemap_state sitemap_outcome_reason sitemap_terminal_at sitemap_limit_reasons
         robots_state robots_terminal_reason robots_terminal_at].each do |column|
        expect(definition).to include(column),
                              "the UPDATE closure does not govern #{column}, which the terminal " \
                              "selection reads; a late write to it can contradict a frozen record"
      end
      # The pacing columns stay writable: a terminal run must not break the host's rate window.
      expect(definition).not_to include("next_allowed_start_at")
      expect(definition).not_to include("recent_start_instants")
    end
  end
end
