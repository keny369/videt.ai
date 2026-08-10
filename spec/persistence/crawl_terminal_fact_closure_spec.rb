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
    # FU-12(a): a REGISTERED author, where this was `gen_random_uuid()` against a column that
    # referenced nothing.
    params = [SecureRandom.uuid_v7, organization_id, f[:pid], f[:crawl],
              Platform::ServiceIdentity.scheduled_action_executor]
    pg.exec_params(<<~SQL, params)
      INSERT INTO crawl_limit_decisions
        (id, schema_version, created_at, correlation_id, causation_id, organization_id, project_id,
         crawl_id, limit_dimension, threshold_kind, configured_value, observed_value,
         affected_source_count, affected_url_count, decision_type, decision_value, decision_status,
         decision_reason_code, decided_by_service_identity_id, definition_versions, input_sha256,
         output_sha256, decided_at)
      VALUES ($1,'1.0',now(),gen_random_uuid(),gen_random_uuid(),$2::uuid,$3::uuid,$4::uuid,
              'wall_clock_run_duration','hard',60,60,1,1,'crawl_limit_observation','hard_reached','final',
              'limit_reached',$5::uuid,'["v1"]'::jsonb,sha256(''::bytea),sha256(''::bytea),now())
    SQL
  end

  # A claimed host gate, written while the Crawl is still live. The UPDATE limb of the closure is
  # about what may happen to THIS row afterwards, so it has to exist before the run terminalises.
  # COMMITTED, NOT WRITTEN INSIDE `as_runtime`. That helper wraps its block in BEGIN/ROLLBACK, so a
  # gate inserted there is gone before the UPDATE limb can be driven against it — the UPDATE then
  # matches zero rows, no trigger fires, and the proof reports "not refused" while never having
  # presented the database with anything to refuse. That is the vacuity this whole file guards against,
  # and it happened here first.
  def insert_host_gate(f, organization_id: org)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id, f[:pid], f[:crawl]])
      INSERT INTO crawl_host_gates
        (id, created_at, updated_at, correlation_id, organization_id, project_id, crawl_id,
         canonical_host, canonical_host_sha256)
      VALUES ($1, now(), now(), gen_random_uuid(), $2::uuid, $3::uuid, $4::uuid,
              'gate.example', sha256('gate.example'::bytea))
    SQL
    id
  end

  # `f1_crawl_host_gates_guard` requires every UPDATE to advance `state_version` and `updated_at`, so
  # an update that omits them is refused by THAT guard and never reaches the closure. A proof that
  # tripped the wrong guard would report a refusal it did not cause.
  # The columns the closure's UPDATE limb actually names, read from the catalogue. Used only to ASK
  # what the trigger says — never to decide what it ought to say.
  def closure_when_columns
    definition = DbInspector.one(<<~SQL, [CLOSURE_FUNCTION])["def"]
      SELECT pg_get_triggerdef(t.oid) AS def
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_proc pr ON pr.oid = t.tgfoid
      WHERE NOT t.tgisinternal AND pr.proname = $1 AND c.relname = 'crawl_host_gates'
        AND (t.tgtype & 16) <> 0
    SQL
    definition.scan(/new\.(\w+) IS DISTINCT FROM/).flatten.uniq
  end

  def gate_update(assignment)
    "UPDATE crawl_host_gates SET #{assignment}, state_version = state_version + 1, " \
      "updated_at = now() WHERE id = $1::uuid"
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

    # THE COLUMNS THE UPDATE LIMB MUST CLOSE, each driven from a LEGAL BASELINE.
    #
    # These are contract-derived: each is read by terminal selection, so a late write to it can
    # contradict a frozen coverage record. `sitemap_limit_reasons` is in the list because
    # `CrawlStartStore#terminal_facts` sums it into `sitemap_limit_facts`, which `TerminalSelection`
    # turns into `limit_reached` and `partial`.
    #
    # WHY A BASELINE IS NEEDED, AND WHY IT IS NOT A FIXTURE SHORTCUT. `crawl_host_gates` carries a
    # state machine and five shape constraints: `robots_state` may only walk pending -> in_progress ->
    # terminal and is FROZEN once terminal; `robots_terminal_at` is non-null exactly when robots is
    # terminal; `sitemap_state = 'pending'` exactly when the claim is unheld. A single-column poke at a
    # freshly inserted gate therefore trips one of THOSE guards and raises a different error — which is
    # how the first version of this proof reported refusals it had not caused. The gate is walked to a
    # legal resting state WHILE THE RUN IS LIVE, using the same transitions production uses, and only
    # then is the post-terminal write attempted. PROOF 157/live drives every one of those writes on a
    # live run and requires it to COMMIT, so the only thing left that can refuse them is the closure.
    def advance_gate_to_terminal_facts(gate)
      conn.exec_params(<<~SQL, [gate])
        UPDATE crawl_host_gates
        SET sitemap_state = 'in_progress', sitemap_claim_token = gen_random_uuid(),
            sitemap_attempt_started_at = now(), robots_state = 'in_progress',
            state_version = state_version + 1, updated_at = now()
        WHERE id = $1::uuid
      SQL
      conn.exec_params(<<~SQL, [gate])
        UPDATE crawl_host_gates
        SET sitemap_state = 'absent', sitemap_outcome_reason = 'no_sitemap', sitemap_terminal_at = now(),
            robots_state = 'unavailable', robots_terminal_reason = 'robots_unavailable',
            robots_terminal_at = now(), state_version = state_version + 1, updated_at = now()
        WHERE id = $1::uuid
      SQL
    end

    def advance_gate_to_robots_in_progress(gate)
      conn.exec_params(<<~SQL, [gate])
        UPDATE crawl_host_gates SET robots_state = 'in_progress',
               state_version = state_version + 1, updated_at = now()
        WHERE id = $1::uuid
      SQL
    end

    # THE GATE IS DRIVEN TO `in_progress` FIRST, AND THAT IS NOT A FIXTURE SHORTCUT.
    #
    # `crawl_host_gates` carries guards STRONGER than the closure: the sitemap guard raises
    # `crawl_host_gate_sitemap_decision_frozen` and the robots limb of `f1_crawl_host_gates_guard`
    # raises `crawl_host_gate_robots_decision_frozen` once each decision is terminal, whatever the
    # crawl's state. A column driven from a terminal gate is refused by THAT rule and proves nothing
    # about this one. Every write below is issued against a gate whose own guards still permit it, so
    # the CRAWL's terminality is the only thing left that can refuse it.
    def advance_gate_to_in_progress(gate)
      conn.exec_params(<<~SQL, [gate])
        UPDATE crawl_host_gates
        SET sitemap_state = 'in_progress', sitemap_claim_token = gen_random_uuid(),
            sitemap_attempt_started_at = now(), robots_state = 'in_progress',
            state_version = state_version + 1, updated_at = now()
        WHERE id = $1::uuid
      SQL
    end

    # EACH WRITE CHANGES EXACTLY ONE GOVERNED COLUMN.
    #
    # WHY THIS MATTERS AND WHAT IT REPLACED. The previous version drove two of these as "coherent
    # groups", and each group carried a THIRD governed column that masked the columns the group was
    # named for. The schema lens dropped `sitemap_state`, `sitemap_terminal_at`, `robots_state` and
    # `robots_terminal_at` from the trigger's WHEN clause ONE AT A TIME and the whole suite stayed
    # green — and two of those drops admit a real post-terminal production write, including the exact
    # `sitemap_state` case R10-15 named. Isolation is the property that makes a per-column proof mean
    # what its name says.
    #
    # THE STATE COLUMNS ARE ISOLATED BY WALKING BACK, not forward. Both guards permit
    # `in_progress -> pending`, and pending requires the claim columns to be NULL — and the claim
    # columns are NOT governed, so clearing them adds nothing to what the trigger sees.
    ISOLATED_WRITES = {
      "sitemap_state" => "sitemap_state = 'pending', sitemap_claim_token = NULL, " \
                         "sitemap_attempt_started_at = NULL",
      "sitemap_outcome_reason" => "sitemap_outcome_reason = 'sitemap_unavailable'",
      "sitemap_limit_reasons" => %q(sitemap_limit_reasons = '["depth_cap"]'::jsonb),
      "robots_state" => "robots_state = 'pending'",
      "robots_terminal_reason" => "robots_terminal_reason = 'robots_fetch_failed'"
    }.freeze

    # `sitemap_terminal_at` AND `robots_terminal_at` CANNOT BE ISOLATED, AND THE SCHEMA IS WHY.
    # `crawl_host_gates_sitemap_terminal_shape` and `crawl_host_gates_robots_terminal_shape` make each
    # instant non-null EXACTLY when its decision is terminal, so the instant and the state must move
    # together — there is no legal write that changes the instant alone. They are covered instead by
    # PROOF 157/shape below, which derives the binding from those constraints rather than asserting it.
    UNGOVERNED_PACING_WRITES = {
      "next_allowed_start_at" => "next_allowed_start_at = now() + interval '30 seconds'",
      "recent_start_instants" => "recent_start_instants = ARRAY[now()]"
    }.freeze

    ISOLATED_WRITES.each do |column, assignment|
      it "PROOF 157/#{column} — a post-terminal write to #{column} ALONE is REFUSED BY THE DATABASE" do
        f = fixture
        gate = insert_host_gate(f)
        advance_gate_to_in_progress(gate)
        terminalize(f[:crawl])

        as_runtime(org) do |pg|
          expect { pg.exec_params(gate_update(assignment), [gate]) }
            .to raise_error(PG::RaiseException, /crawl_child_fact_after_terminal/)
        end
      end
    end

    UNGOVERNED_PACING_WRITES.each do |column, assignment|
      it "PROOF 157/#{column} — pacing stays writable after terminal, so the limb is not blanket" do
        f = fixture
        gate = insert_host_gate(f)
        advance_gate_to_in_progress(gate)
        terminalize(f[:crawl])

        as_runtime(org) { |pg| expect { pg.exec_params(gate_update(assignment), [gate]) }.not_to raise_error }
      end
    end

    it "PROOF 157/live — every governed write COMMITS while the run is live, so terminality is what refuses" do
      ISOLATED_WRITES.each do |column, assignment|
        f = fixture
        gate = insert_host_gate(f)
        advance_gate_to_in_progress(gate)

        as_runtime(org) do |pg|
          expect { pg.exec_params(gate_update(assignment), [gate]) }
            .not_to raise_error, "#{column}'s write is not legal on a live run, so its refusal after " \
                                 "terminalisation would prove nothing about the closure"
        end
      end
    end

    it "PROOF 157/shape — a governed state column drags its terminal instant into the closure" do
      # THE TWO COLUMNS BEHAVIOUR CANNOT ISOLATE, COVERED FROM AN INDEPENDENT AUTHORITY.
      #
      # The previous coverage example derived its required set FROM THE TRIGGER — `governed =
      # definition.scan(/new\.(\w+) IS DISTINCT FROM/)` — so shrinking the WHEN clause shrank the
      # requirement and every single-column drop stayed green. It guarded addition only.
      #
      # This derives the requirement from the SCHEMA instead. A CHECK constraint of the form
      # `(<state> = ANY (...)) = (<instant> IS NOT NULL)` says the instant exists exactly when the
      # decision is terminal — so if the state is governed, a post-terminal write to the instant is a
      # write to the same decision and must be governed too. Dropping either instant from the WHEN
      # clause now fails here, and nothing about this reads the trigger to decide what it should say.
      pairs = DbInspector.all(<<~SQL).filter_map do |row|
        SELECT pg_get_constraintdef(oid) AS def FROM pg_constraint
        WHERE conrelid = 'crawl_host_gates'::regclass AND contype = 'c'
      SQL
        m = row["def"].match(/\((\w+) = ANY \(ARRAY\[[^\]]*\]\)\) = \((\w+) IS NOT NULL\)/)
        m && [m[1], m[2]]
      end
      expect(pairs).not_to be_empty, "no terminal-shape constraint parsed; the derivation is broken"

      governed = closure_when_columns
      pairs.each do |state_column, instant_column|
        next unless governed.include?(state_column)

        expect(governed).to include(instant_column),
                            "#{state_column} is closed after terminal but #{instant_column} is not, " \
                            "and #{instant_column} exists exactly when #{state_column} is terminal — " \
                            "so a post-terminal write can move the decision's instant unrefused"
      end
    end

    it "PROOF 157/reads — every gate column the terminal selection READS is closed" do
      # THE SECOND INDEPENDENT AUTHORITY: the consumer. `CrawlStartStore#terminal_facts` computes the
      # frozen coverage record from these columns, so a post-terminal write to any of them can
      # contradict a record that is already final. Derived by parsing the production SQL, not by
      # reading the trigger.
      sql = File.read(Rails.root.join("app/contexts/identity_access/infrastructure/crawl_start_store.rb"))
      body = sql[sql.index("def terminal_facts")..]
      read = body[0, body.index("\n      end")].scan(/\bg\.(\w+)/).flatten.uniq
      expect(read).not_to be_empty, "the terminal_facts parse found no gate columns"

      missing = read - closure_when_columns - %w[crawl_id organization_id id]
      expect(missing).to be_empty,
                         "terminal selection reads #{missing.join(', ')} from crawl_host_gates, and " \
                         "the closure does not govern them; a late write can contradict a frozen record"
    end

    it "PROOF 157b — the UPDATE trigger exists on the row, AFTER rather than BEFORE" do
      # RETAINED FROM THE OLD PROOF FOR THE ONE THING TEXT CAN HONESTLY ANSWER. PROOF 40b: PostgreSQL
      # evaluates a policy's WITH CHECK limb on the row a BEFORE trigger leaves behind, so a BEFORE
      # trigger would run ahead of RLS and answer a cross-tenant write with a state message instead of
      # a tenant refusal. Ordering is a property of the declaration, not of any single write.
      definition = DbInspector.one(<<~SQL, [CLOSURE_FUNCTION])["def"]
        SELECT pg_get_triggerdef(t.oid) AS def
        FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_proc pr ON pr.oid = t.tgfoid
        WHERE NOT t.tgisinternal AND pr.proname = $1 AND c.relname = 'crawl_host_gates'
          AND (t.tgtype & 16) <> 0
      SQL

      expect(definition).to include("AFTER UPDATE")
    end
  end
end
