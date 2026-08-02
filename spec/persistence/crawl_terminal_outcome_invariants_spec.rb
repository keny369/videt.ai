# frozen_string_literal: true

require "rails_helper"

# S-07-009's per-entry terminal record (schemas/POSTGRESQL_SCHEMA.md :301; WORKFLOW_SPECIFICATIONS.md
# :452, :454, :456), which is the home FU-21 said the coverage classification needed.
#
# THESE PROOFS ANCHOR TO THE RATIFIED SENTENCE, NOT TO PRODUCTION CONSTANTS. The S-07-012 review round
# ended with one lesson worth institutionalising: every defect that survived a green suite was one where
# the test restated the implementation's own arithmetic back to itself, and every defect the suite CAUGHT
# was found by a check that read the ratified document or the database catalogue. So the coverage
# vocabulary here is PARSED OUT OF `WORKFLOW_SPECIFICATIONS.md` :452 and asserted against the live CHECK
# constraint. A spec that imported `Workflows::Wf005::FetchContent::POLICY_EXCLUDED` would agree with the
# implementation by construction and prove nothing about the contract.
RSpec.describe "Crawl terminal-outcome invariants", type: :model do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization(display_name: "Acme Org") }
  def conn = DbInspector.connection

  # :452, the exhaustive coverage-classification sentence, read from the ratified document.
  def coverage_sentence
    text = Rails.root.join("specification/volume-i/WORKFLOW_SPECIFICATIONS.md").read
    sentence = text[/^Coverage classification is exhaustive\..*$/]
    raise "the :452 coverage-classification paragraph is not present" if sentence.nil?

    sentence
  end

  def constraint(name)
    conn.exec_params("SELECT pg_get_constraintdef(oid) AS d FROM pg_constraint WHERE conname = $1", [name])
        .first&.fetch("d")
  end

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

  # The source, scope-policy and frontier-entry fixtures are the ones
  # `spec/persistence/crawl_frontier_invariants_spec.rb` already proves against these FKs and CHECKs.
  # Copied rather than shared, following the convention of the sibling persistence specs: each owns the
  # rows it needs, so a change to one table's fixture cannot silently alter another spec's premise.
  def insert_source(pid, host: "s#{SecureRandom.hex(4)}.example", organization_id: org)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id, pid, host])
      INSERT INTO sources
        (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id,
         submitted_root_uri, canonical_root_uri, canonical_host, registration_schema_version,
         host_normalization_version, registration_origin, registering_account_id,
         registration_command_id, registration_idempotency_key_digest,
         registration_authorization_decision_id, registered_at, state)
      VALUES ($1,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,
              'https://'||$4, 'https://'||$4||'/', $4, 'source-registration-v1',
              'ascii-host-v1','human_command',gen_random_uuid(),
              gen_random_uuid(), sha256('k'),
              gen_random_uuid(),now(),'active')
    SQL
    id
  end

  def insert_scope_policy(sid, pid, organization_id: org)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, organization_id, pid, sid])
      INSERT INTO source_scope_policies
        (id, created_at, correlation_id, schema_version, organization_id, project_id, source_id,
         policy_version, scope, canonical_host, allowed_schemes, allowed_ports, include_prefixes,
         exclude_prefixes, query_handling, content_sha256)
      VALUES ($1,now(),gen_random_uuid(),'source-scope-policy-v1',$2::uuid,$3::uuid,$4::uuid,
              'source-scope-interim-v1','source','x.example', ARRAY['https'], ARRAY[443], ARRAY['/'],
              ARRAY[]::text[], 'retain_all', sha256('x'))
    SQL
    id
  end

  def next_order(crawl_id)
    conn.exec_params("SELECT COALESCE(MAX(enqueue_order),-1)+1 AS n FROM crawl_frontier_entries WHERE crawl_id=$1::uuid",
                     [crawl_id]).first.fetch("n").to_i
  end

  def insert_entry(ctx, url: "https://x.example/")
    id = SecureRandom.uuid_v7
    key = Workflows::Wf005::FrontierOrder.dequeue_key(
      depth: 0, origin: "root", canonical_url: url, discovering_document_url: "",
      link_position: 0, entry_id: id
    )
    params = [id, ctx[:org], ctx[:pid], ctx[:crawl], ctx[:source], url,
              { value: url.b, format: 1 }, { value: Digest::SHA256.digest(url), format: 1 },
              0, "root", 0, "", 0, { value: key, format: 1 },
              ctx[:policy], next_order(ctx[:crawl]), "queued", nil]
    conn.exec_params(<<~SQL, params)
      INSERT INTO crawl_frontier_entries
        (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id,
         crawl_id, source_id, canonical_url, canonical_url_preimage, canonical_url_sha256,
         collision_ordinal, origin, depth, discovering_document_url, link_position, dequeue_key,
         canonicalization_version, scope_policy_id, scope_policy_version, enqueue_order, state, reason)
      VALUES ($1,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,
              $4::uuid,$5::uuid,$6,$7,$8,
              $9,$10,$11,$12,$13,$14,
              'source-scope-interim-v1',$15::uuid,'source-scope-interim-v1',$16,$17,$18)
    SQL
    id
  end

  # A fixture whose defaults are a VALID row, so each example changes exactly the one thing it is about.
  def insert_outcome(pid, crawl_id, entry_id, source_id, organization_id: org, **overrides)
    row = { outcome: "document_created", coverage_effect: "covered", reason: nil, document_id: nil,
            commit_order: 1, bytes: 0 }.merge(overrides)
    params = [SecureRandom.uuid_v7, organization_id, pid, crawl_id, entry_id, source_id,
              row[:commit_order], row[:outcome], row[:reason], row[:document_id],
              row[:bytes], row[:coverage_effect]]
    conn.exec_params(<<~SQL, params)
      INSERT INTO crawl_terminal_outcomes
        (id, schema_version, created_at, correlation_id, causation_id, organization_id, project_id,
         crawl_id, crawl_frontier_entry_id, source_id, commit_order, outcome, reason, document_id,
         accounted_response_body_bytes, coverage_effect, decided_at)
      VALUES ($1,'1.0',now(),gen_random_uuid(),gen_random_uuid(),$2::uuid,$3::uuid,$4::uuid,$5::uuid,
              $6::uuid,$7,$8,$9,$10::uuid,$11,$12,now())
    SQL
  end

  let(:fixture) do
    pid = draft_project
    crawl = insert_crawl(pid)
    source = insert_source(pid)
    ctx = { org:, pid:, crawl:, source:, policy: insert_scope_policy(source, pid) }
    ctx.merge(entry: insert_entry(ctx))
  end

  describe ":452's classification, as a database fact" do
    it "PROOF 30 — the covered pair is exactly what the ratified sentence names with \"only when\"" do
      # THE ANCHOR. :452: "An admitted content URL has a covered outcome ONLY WHEN it creates a valid
      # Document, or returns terminal 404/410 and creates a valid body-free `crawl_observation` with
      # reason `content_absent`." Two ways, and the constraint must admit exactly those two.
      sentence = coverage_sentence
      expect(sentence).to include("has a covered outcome only when")
      expect(sentence).to include("content_absent")

      agreement = constraint("crawl_terminal_outcomes_coverage_agreement")
      expect(agreement).not_to be_nil

      covered = agreement[/\(outcome = ANY \(ARRAY\[(.*?)\]\)\) AND \(coverage_effect = 'covered'/m, 1]
      expect(covered).not_to be_nil, "the covered limb is not in the expected shape: #{agreement}"
      expect(covered.scan(/'(\w+)'/).flatten).to match_array(%w[document_created content_absent])
    end

    it "PROOF 31 — `policy_excluded` is the ONE token the sentence puts outside the denominator" do
      # :452 names four things "recorded as `policy_excluded` and ... outside the denominator": robots
      # disallowed, duplicate occurrences, unsupported media types, redirect targets rejected by current
      # scope. FOUR CAUSES, ONE TOKEN — so `excluded` must admit exactly one outcome, not four.
      sentence = coverage_sentence
      expect(sentence).to match(/recorded as `policy_excluded` and are outside the denominator/)

      excluded = constraint("crawl_terminal_outcomes_coverage_agreement")[
        /\(outcome = '(\w+)'::text\) AND \(coverage_effect = 'excluded'/m, 1
      ]
      expect(excluded).to eq("policy_excluded")
    end

    it "PROOF 32 — a limit discard is IN the denominator, which is the reading most easily got wrong" do
      # :452: "The content coverage set is every distinct canonical in-scope candidate retained by
      # deduplication, PLUS EVERY IN-SCOPE CANDIDATE DISCARDED BY A CRAWL LIMIT". A limit hit reduces
      # coverage; it does not remove the URL from the question. Treating it as `excluded` would silently
      # inflate coverage on exactly the runs a customer most needs the truth about.
      expect(coverage_sentence).to include("plus every in-scope candidate discarded by a Crawl limit")

      f = fixture
      expect { insert_outcome(f[:pid], f[:crawl], f[:entry], f[:source],
                              outcome: "limit_discarded", coverage_effect: "excluded",
                              reason: "queue_limit_discarded") }
        .to raise_error(PG::CheckViolation, /coverage_agreement/)

      expect { insert_outcome(f[:pid], f[:crawl], f[:entry], f[:source],
                              outcome: "limit_discarded", coverage_effect: "not_covered",
                              reason: "queue_limit_discarded") }.not_to raise_error
    end

    it "PROOF 33 — outcome and coverage effect cannot disagree, in either direction" do
      f = fixture
      # A covered outcome cannot be recorded as reducing coverage...
      expect { insert_outcome(f[:pid], f[:crawl], f[:entry], f[:source],
                              outcome: "document_created", coverage_effect: "not_covered",
                              reason: "x") }
        .to raise_error(PG::CheckViolation, /coverage_agreement/)
      # ...and a failure cannot be recorded as covered, which is the direction that inflates the number
      # a customer sees.
      expect { insert_outcome(f[:pid], f[:crawl], f[:entry], f[:source],
                              outcome: "content_fetch_failed", coverage_effect: "covered") }
        .to raise_error(PG::CheckViolation, /coverage_agreement/)
    end

    it "PROOF 34 — :456's \"exact limit reason\" is required of everything that is not covered" do
      f = fixture
      %w[content_fetch_failed limit_discarded robots_unavailable_fail_closed].each do |outcome|
        expect { insert_outcome(f[:pid], f[:crawl], f[:entry], f[:source],
                                outcome:, coverage_effect: "not_covered", reason: nil) }
          .to raise_error(PG::CheckViolation, /reason_presence/)
      end
      expect { insert_outcome(f[:pid], f[:crawl], f[:entry], f[:source],
                              outcome: "policy_excluded", coverage_effect: "excluded", reason: nil) }
        .to raise_error(PG::CheckViolation, /reason_presence/)

      # And a covered outcome has nothing to explain, so it must not carry one.
      expect { insert_outcome(f[:pid], f[:crawl], f[:entry], f[:source], reason: "why") }
        .to raise_error(PG::CheckViolation, /reason_presence/)
    end
  end

  describe "the record's own shape" do
    it "PROOF 35 — one frontier entry retires exactly once (:301, \"unique frontier entry\")" do
      # This is what makes a redelivery's `superseded` pass write NOTHING rather than a second opinion
      # about an entry another pass already decided.
      f = fixture
      insert_outcome(f[:pid], f[:crawl], f[:entry], f[:source])
      expect { insert_outcome(f[:pid], f[:crawl], f[:entry], f[:source], commit_order: 2) }
        .to raise_error(PG::UniqueViolation, /entry_once/)
    end

    it "PROOF 36 — commit order is unique within a run and strictly positive" do
      f = fixture
      insert_outcome(f[:pid], f[:crawl], f[:entry], f[:source], commit_order: 1)
      second = insert_entry(f, url: "https://x.example/b")
      expect { insert_outcome(f[:pid], f[:crawl], second, f[:source], commit_order: 1) }
        .to raise_error(PG::UniqueViolation, /commit_order_once/)
      expect { insert_outcome(f[:pid], f[:crawl], second, f[:source], commit_order: 0) }
        .to raise_error(PG::CheckViolation, /commit_order/)
    end

    it "PROOF 37 — a Document can only belong to the outcome that created one" do
      f = fixture
      expect { insert_outcome(f[:pid], f[:crawl], f[:entry], f[:source],
                              outcome: "content_absent", coverage_effect: "covered",
                              document_id: SecureRandom.uuid_v7) }
        .to raise_error(PG::CheckViolation, /document_agreement/)
    end

    it "PROOF 38 — T-IMM: a coverage-bearing decision cannot be rewritten or deleted" do
      # :456 makes the terminal transition irreversible by design ("no edge leaves terminal"). A record
      # of it that could be updated afterwards would make that an application convention rather than a
      # property of the system.
      f = fixture
      insert_outcome(f[:pid], f[:crawl], f[:entry], f[:source])
      id = conn.exec_params("SELECT id FROM crawl_terminal_outcomes WHERE crawl_frontier_entry_id = $1::uuid",
                            [f[:entry]]).first.fetch("id")

      expect { conn.exec_params("UPDATE crawl_terminal_outcomes SET coverage_effect = 'covered' WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /crawl_terminal_outcome_immutable/)
      expect { conn.exec_params("DELETE FROM crawl_terminal_outcomes WHERE id = $1::uuid", [id]) }
        .to raise_error(PG::RaiseException, /crawl_terminal_outcome_immutable/)
    end

    it "PROOF 39 — every Project-owned link EXISTS and carries all three columns (:128)" do
      # REWRITTEN, AND THE REWRITE IS THE POINT (ADR-110). The first version enumerated the foreign keys
      # that EXIST and asserted arity 3 on each. An absent foreign key has no arity, so it was
      # structurally incapable of seeing the one that was missing — `source_id` had none at all — and it
      # passed while its own title was false. A check that reads what is there cannot find what is not.
      #
      # This asserts the expected link SET first, from the columns that name a Project-owned parent, and
      # only then the arity :128 requires. FU-7 records this defect class appearing silently in three
      # consecutive tranches; `source_id` here was the fourth, asserted-as-satisfied by the proof.
      links = conn.exec_params(<<~SQL).to_h { |r| [r.fetch("columns"), r.fetch("cols").to_i] }
        SELECT (SELECT string_agg(a.attname, ',' ORDER BY k.ord)
                FROM unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
                JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum) AS columns,
               array_length(c.conkey, 1) AS cols
        FROM pg_constraint c
        WHERE c.conrelid = 'crawl_terminal_outcomes'::regclass AND c.contype = 'f'
      SQL

      expect(links.keys).to match_array(["organization_id,project_id,crawl_id",
                                         "organization_id,project_id,crawl_frontier_entry_id",
                                         "organization_id,project_id,source_id"])
      links.each { |name, cols| expect(cols).to eq(3), "#{name} links with #{cols} columns, not three" }
    end

    it "PROOF 39b — the `source_id` link REFUSES a cross-Project and a fabricated Source" do
      # The behavioural half, because a catalogue assertion says the constraint exists and this says what
      # it does. Both shapes were ADMITTED before the link was added.
      f = fixture
      other_project = draft_project
      foreign_source = insert_source(other_project)

      expect { insert_outcome(f[:pid], f[:crawl], f[:entry], foreign_source) }
        .to raise_error(PG::ForeignKeyViolation, /source_fk/)
      expect { insert_outcome(f[:pid], f[:crawl], f[:entry], SecureRandom.uuid_v7) }
        .to raise_error(PG::ForeignKeyViolation, /source_fk/)
      # And the Source that genuinely belongs to this Project is admitted.
      expect { insert_outcome(f[:pid], f[:crawl], f[:entry], f[:source]) }.not_to raise_error
    end

    it "PROOF 40 — forced RLS, and the runtime role may never rewrite an outcome" do
      flags = conn.exec_params(
        "SELECT relrowsecurity AS enabled, relforcerowsecurity AS forced FROM pg_class WHERE relname = 'crawl_terminal_outcomes'"
      ).first
      expect(Platform::PgBool.true?(flags.fetch("enabled"))).to be(true)
      expect(Platform::PgBool.true?(flags.fetch("forced"))).to be(true)

      granted = conn.exec_params(<<~SQL).map { |r| r.fetch("privilege_type") }.sort
        SELECT privilege_type FROM information_schema.role_table_grants
        WHERE table_name = 'crawl_terminal_outcomes' AND grantee = 'f1_runtime'
      SQL
      expect(granted).to eq(%w[INSERT SELECT])
    end

    # PROOF 40 above reads `pg_class` and `role_table_grants`. NEITHER CATALOGUE READ CAN SEE THE
    # POLICY PREDICATE. Round 3 measured exactly that: rewriting this table's policy to
    # `USING (true) WITH CHECK (true)` — which removes tenant isolation from the table outright —
    # left every S-07-009 spec green, 112 examples across five files including PROOF 40 itself.
    # S-07-008 established the rule and named this mutation in `crawl_limit_decision_invariants_spec`;
    # `crawl_terminal_outcomes` carries the customer's coverage verdict and got only the catalogue
    # half. `f1:db:verify_runtime` does not close the gap either — it is a fixed list over `sessions`,
    # `accounts`, `scheduled_actions` and the transport functions.
    #
    # Defined locally rather than reused from the S-07-008 spec: that file's `as_runtime` is a
    # top-level `def`, so it binds to Object and is only reachable here by load order (FU-37's
    # constant/method-leakage observation). A proof must not depend on which files RSpec loaded first.
    def as_runtime(organization_id)
      cfg = ActiveRecord::Base.connection_db_config.configuration_hash
      runtime = PG.connect(host: cfg[:host], port: cfg[:port], dbname: cfg[:database], user: "f1_web")
      # `f1_enter_org_context` sets transaction-local state, so the context exists only inside a
      # transaction — which is how every production caller holds it too.
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

    it "PROOF 40a — BLOCKS a cross-tenant read as the runtime role, not merely declares a policy" do
      f = fixture
      insert_outcome(f[:pid], f[:crawl], f[:entry], f[:source])
      intruder = TenantSeeder.create_organization(display_name: "Intruder")

      as_runtime(org) do |own|
        expect(own.exec_params("SELECT count(*) FROM crawl_terminal_outcomes WHERE crawl_id = $1::uuid",
                               [f[:crawl]]).getvalue(0, 0).to_i).to eq(1)
      end
      as_runtime(intruder) do |other|
        expect(other.exec_params("SELECT count(*) FROM crawl_terminal_outcomes WHERE crawl_id = $1::uuid",
                                 [f[:crawl]]).getvalue(0, 0).to_i).to eq(0)
      end
    end

    it "PROOF 40b — BLOCKS a cross-tenant write as the runtime role" do
      # The WITH CHECK limb, which no catalogue read can exercise either. The row names another
      # Organization's Crawl, so the composite foreign keys would all be SATISFIED — the refusal has
      # to come from the policy, and the error class distinguishes the two.
      f = fixture
      intruder = TenantSeeder.create_organization(display_name: "Intruder")

      as_runtime(intruder) do |other|
        params = [SecureRandom.uuid_v7, org, f[:pid], f[:crawl], f[:entry], f[:source]]
        expect do
          other.exec_params(<<~SQL, params)
            INSERT INTO crawl_terminal_outcomes
              (id, schema_version, created_at, correlation_id, causation_id, organization_id,
               project_id, crawl_id, crawl_frontier_entry_id, source_id, commit_order, outcome,
               reason, document_id, accounted_response_body_bytes, coverage_effect, decided_at)
            VALUES ($1,'1.0',now(),gen_random_uuid(),gen_random_uuid(),$2::uuid,$3::uuid,$4::uuid,
                    $5::uuid,$6::uuid,99,'document_created',NULL,NULL,0,'covered',now())
          SQL
        end.to raise_error(PG::InsufficientPrivilege, /row-level security/)
      end
    end
    it "PROOF 41 — the application's classification map and the live CHECK are the same map" do
      # THE ONE DUPLICATION THIS DESIGN COULD NOT AVOID. The CHECK's vocabulary lives in a MIGRATION
      # class, which is not loadable at runtime, so `Workflows::Wf005::CoverageClassification::EFFECTS`
      # cannot import it — and a token classified one way by the writer and another by the constraint
      # would either be refused at INSERT (loud) or, far worse, admitted by a constraint that had been
      # widened without the writer noticing. This reads the LIVE constraint and rebuilds the map from it.
      definition = constraint("crawl_terminal_outcomes_coverage_agreement")
      catalogued = definition.scan(
        /\(outcome = (?:ANY \(ARRAY\[(.*?)\]\)|('\w+'::text))\) AND \(coverage_effect = '(\w+)'::text\)/
      ).each_with_object({}) do |(list, single, effect), map|
        (list || single).scan(/'(\w+)'/).flatten.each { |token| map[token] = effect }
      end
      expect(catalogued).not_to be_empty, "the coverage agreement is not in the expected shape: #{definition}"

      expect(catalogued).to eq(Workflows::Wf005::CoverageClassification::EFFECTS)

      # And the three effect names the writer uses are the three the column admits, so a classification
      # the map produces can never be an effect the enum refuses.
      enum = constraint("crawl_terminal_outcomes_coverage_effect_check").scan(/'(\w+)'/).flatten
      expect(enum).to match_array([Workflows::Wf005::CoverageClassification::COVERED,
                                   Workflows::Wf005::CoverageClassification::NOT_COVERED,
                                   Workflows::Wf005::CoverageClassification::EXCLUDED])
    end

    it "PROOF 42 — the robots fail-closed token the GATE stores is a token this table admits" do
      # `EnsureRobots::FAIL_CLOSED` is written to `crawl_host_gates.robots_terminal_reason` and handed to
      # the driver as the retirement reason; :452 names the same token as a coverage outcome. They are
      # separate literals in separate modules, and the failure if they drifted is silent in the module
      # that matters least and fatal in the one that matters most — a fail-closed host's entry could not
      # be retired at all, which strands the claim and pins the frontier.
      expect(coverage_sentence).to include("`robots_unavailable_fail_closed` makes that Source root failed")

      vocabulary = constraint("crawl_terminal_outcomes_outcome_check").scan(/'(\w+)'/).flatten
      expect(vocabulary).to include(Workflows::Wf005::EnsureRobots::FAIL_CLOSED)
      expect(Workflows::Wf005::CoverageClassification::EFFECTS[Workflows::Wf005::EnsureRobots::FAIL_CLOSED])
        .to eq(Workflows::Wf005::CoverageClassification::NOT_COVERED)
    end
  end
end
