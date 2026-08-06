# frozen_string_literal: true

require "rails_helper"

# S-07-010's three tables, and the guards that make their lifecycles properties of the DATABASE
# rather than conventions of a handler (schemas/POSTGRESQL_SCHEMA.md :302, :303, :304).
#
# WHY THE DATABASE AND NOT THE HANDLER. Every lifecycle in this repository that was enforced only in
# Ruby has eventually been reached another way; the S-07-009 rounds are twenty rounds of that lesson.
# A Document that could go `discovered -> indexed`, or an Ingestion Job whose replay generation could
# advance twice, is not a defect to be found in review if the constraint refuses it outright.
#
# OD-015 IS THE SHARPEST OF THESE. :302 says the check "MUST NOT recognize either value even as
# forward-compatible migration shape", so `quarantined` and `retired` are asserted absent from the
# LIVE constraint rather than merely unused by the code.
RSpec.describe "S-07-010 documents and ingestion schema", type: :model do
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  let(:org) { TenantSeeder.create_organization(display_name: "Acme Org") }
  def conn = DbInspector.connection
  def now_iso = Time.utc(2026, 8, 6, 10, 0, 0).iso8601(6)
  def sha(seed) = { value: Digest::SHA256.digest(seed), format: 1 }

  # Project, Source and Crawl fixtures follow the sibling persistence specs' convention: each spec
  # owns the rows it needs, so a change to one table's fixture cannot silently alter another spec's
  # premise. All three tables under test carry the :128 composite link, so a fabricated id would
  # prove the foreign key rather than the guard.
  def draft_project
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, org])
      INSERT INTO projects
        (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
         display_name, locale, time_zone, objective, state, source_set_version)
      VALUES ($1,0,0,now(),now(),gen_random_uuid(),$2,'P','en-AU','UTC','discoverability_assessment','draft',0)
    SQL
    id
  end

  def insert_source(pid, host: "s#{SecureRandom.hex(4)}.example")
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, org, pid, host])
      INSERT INTO sources
        (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id,
         submitted_root_uri, canonical_root_uri, canonical_host, registration_schema_version,
         host_normalization_version, registration_origin, registering_account_id,
         registration_command_id, registration_idempotency_key_digest,
         registration_authorization_decision_id, registered_at, state)
      VALUES ($1,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,
              'https://'||$4, 'https://'||$4||'/', $4, 'source-registration-v1',
              'ascii-host-v1','human_command',gen_random_uuid(),
              gen_random_uuid(), sha256('k'), gen_random_uuid(), now(), 'active')
    SQL
    id
  end

  def insert_crawl(pid)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, org, pid])
      INSERT INTO crawls
        (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id, kind,
         requested_entitlement_policy_id, requested_entitlement_policy_version, trigger_kind, queued_at, state)
      VALUES ($1,0,now(),now(),gen_random_uuid(),$2::uuid,$3::uuid,'root',
              gen_random_uuid(),'entitlement-interim-v1','manual',now(),'queued')
    SQL
    id
  end

  let(:project_id) { draft_project }
  let(:source_id)  { insert_source(project_id) }
  let(:crawl_id)   { insert_crawl(project_id) }

  def insert_document(url: "https://acme.example/a", version: 1)
    id = SecureRandom.uuid_v7
    params = [id, org, project_id, source_id, crawl_id, url, sha(url), version, now_iso,
              sha("body-#{url}-#{version}")]
    conn.exec_params(<<~SQL, params)
      INSERT INTO documents
        (id, state_version, schema_version, created_at, updated_at, correlation_id, causation_id,
         organization_id, project_id, source_id, crawl_id, canonical_url, canonical_url_sha256,
         version, fetched_object_id, media_type, byte_size, content_sha256, state, discovered_at)
      VALUES ($1,0,'document-v1',$9::timestamptz,$9::timestamptz,gen_random_uuid(),gen_random_uuid(),
              $2::uuid,$3::uuid,$4::uuid,$5::uuid,$6,$7,$8::bigint,gen_random_uuid(),'text/html',1024,
              $10,'discovered',$9::timestamptz)
    SQL
    id
  end

  # Moves the state AND the timestamp that state requires, so the lifecycle-times CHECK is satisfied
  # and the only thing that can refuse the move is the transition guard.
  def move_document(id, to)
    conn.exec_params(<<~SQL, [id, to, now_iso])
      UPDATE documents SET state = $2,
        ingested_at = CASE WHEN $2 IN ('ingested','parsed','indexed') THEN coalesce(ingested_at,$3::timestamptz) END,
        parsed_at   = CASE WHEN $2 IN ('parsed','indexed')            THEN coalesce(parsed_at,$3::timestamptz) END,
        indexed_at  = CASE WHEN $2 = 'indexed'                        THEN coalesce(indexed_at,$3::timestamptz) END,
        state_version = state_version + 1, updated_at = $3::timestamptz
      WHERE id = $1::uuid
    SQL
  end

  describe "the Document lifecycle (:302)" do
    it "admits exactly `discovered -> ingested -> parsed -> indexed`, in order" do
      id = insert_document
      %w[ingested parsed indexed].each { |to| expect { move_document(id, to) }.not_to raise_error }

      expect(DbInspector.one("SELECT state FROM documents WHERE id = $1::uuid", [id])["state"]).to eq("indexed")
    end

    it "refuses every skip and the self-edge" do
      { "https://acme.example/s1" => "parsed", "https://acme.example/s2" => "indexed" }.each do |url, to|
        id = insert_document(url:)
        expect { move_document(id, to) }
          .to raise_error(PG::RaiseException, /document_illegal_transition/), "discovered -> #{to} was admitted"
      end

      # A self-edge is not a state change and must not consume a state version.
      id = insert_document(url: "https://acme.example/self")
      expect { move_document(id, "discovered") }
        .to raise_error(PG::RaiseException, /document_illegal_transition/)
    end

    it "makes `indexed` terminal — no edge leaves it" do
      id = insert_document(url: "https://acme.example/terminal")
      %w[ingested parsed indexed].each { |to| move_document(id, to) }

      %w[discovered ingested parsed indexed].each do |to|
        expect { move_document(id, to) }
          .to raise_error(PG::RaiseException, /document_illegal_transition/), "indexed -> #{to} was admitted"
      end
    end

    it "freezes the Document's identity and the content it is a Document OF" do
      id = insert_document(url: "https://acme.example/frozen")

      { "canonical_url" => "'https://other.example/'", "version" => "2",
        "byte_size" => "9999", "media_type" => "'application/pdf'" }.each do |column, value|
        expect { conn.exec("UPDATE documents SET #{column} = #{value} WHERE id = '#{id}'") }
          .to raise_error(PG::RaiseException, /document_identity_immutable/), "#{column} was not frozen"
      end
    end

    # OD-015 / ADR-019. The values must be absent from the LIVE constraint, not merely unused by the
    # application: :302 forbids them "even as forward-compatible migration shape".
    it "does not recognize `quarantined` or `retired`, even as forward-compatible shape" do
      definition = DbInspector.one(<<~SQL)&.fetch("def")
        SELECT pg_get_constraintdef(oid) AS def FROM pg_constraint
        WHERE conrelid = 'documents'::regclass AND pg_get_constraintdef(oid) LIKE '%discovered%'
      SQL

      expect(definition).not_to be_nil, "the documents state CHECK is gone"
      expect(definition).to include("discovered", "ingested", "parsed", "indexed")
      expect(definition).not_to include("quarantined")
      expect(definition).not_to include("retired")
    end

    it "keeps the state and the lifecycle timestamps from disagreeing" do
      id = insert_document(url: "https://acme.example/times")

      expect { conn.exec("UPDATE documents SET state = 'ingested' WHERE id = '#{id}'") }
        .to raise_error(PG::CheckViolation, /documents_lifecycle_times/)
    end
  end

  # The :462 capture members arrived with `20260806110000`, and every one of them is NOT NULL: a job
  # that does not say what it is the ingestion OF cannot be written at all. `evidence_id` is
  # deliberately absent — it is what a SUCCESS adds, and the durable-handoff CHECK is what makes that
  # true (see "the durable handoff (:464, MTX-008)" below).
  def insert_job(document_id, url: "https://acme.example/a", state: "queued", staged: true)
    id = SecureRandom.uuid_v7
    params = [id, org, project_id, source_id, crawl_id, document_id, url, sha("body-#{url}"),
              state, now_iso, staged ? SecureRandom.uuid_v7 : nil]
    conn.exec_params(<<~SQL, params)
      INSERT INTO ingestion_jobs
        (id, state_version, schema_version, created_at, updated_at, correlation_id, causation_id,
         organization_id, project_id, source_id, crawl_id, document_id, canonical_url,
         fetched_body_sha256, ingestion_schema_version, state,
         final_http_status, media_type, staged_body_reference, staged_body_destroyed_at,
         staging_expires_at, received_byte_count, response_capture_policy_version,
         data_classification, idempotency_key, queued_at)
      VALUES ($1,0,'ingestion-job-v1',$10::timestamptz,$10::timestamptz,gen_random_uuid(),gen_random_uuid(),
              $2::uuid,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7,$8,'ingestion-interim-v1',$9,
              200,'text/html',$11::uuid,
              CASE WHEN $11::uuid IS NULL THEN $10::timestamptz END,
              $10::timestamptz + interval '24 hours', 1024, 'crawl-policy-v1',
              'public', encode(sha256(convert_to($7,'UTF8')),'hex'), $10::timestamptz)
    SQL
    id
  end

  def capsule_sql
    ", recovery_source_event_id = gen_random_uuid(), recovery_command_id = gen_random_uuid(), " \
      "earlier_terminal_reason_code = 'ingestion_failed', " \
      "replay_requester_account_id = gen_random_uuid(), " \
      "replay_human_rationale = 'the upstream parser regression is fixed and this replay is safe', " \
      "replay_requested_at = now()"
  end

  def move_job(id, to, generation: nil, capsule: false, evidence: nil)
    gen = generation ? ", replay_generation = #{generation}" : ""
    # `succeeded` carries its Evidence and its completion instant, because
    # `ingestion_jobs_succeeded_carries_evidence` refuses the row without them (:464, MTX-008). The
    # helper supplies both rather than each example restating the handoff.
    success = to == "succeeded" ? ", evidence_id = '#{evidence || insert_evidence}', completed_at = now()" : ""
    # `running` stamps its own start instant, because `ingestion_jobs_started_before_completed` makes
    # a completion without one unrepresentable — an ordering rule, not an ingestion rule, and it must
    # not be what a lifecycle example trips over.
    started = to == "running" ? ", started_at = coalesce(started_at, now())" : ""
    conn.exec("UPDATE ingestion_jobs SET state = '#{to}'#{gen}#{started}#{success}" \
              "#{capsule ? capsule_sql : ''}, state_version = state_version + 1 WHERE id = '#{id}'")
  end

  # A minimal valid Evidence row, appended exactly as F-03's own table requires. It exists so the
  # durable-handoff CHECK can be exercised against a REAL foreign key rather than a fabricated uuid.
  def insert_evidence(project: nil, source: nil)
    id = SecureRandom.uuid_v7
    conn.exec_params(<<~SQL, [id, org, project || project_id, source || source_id, SecureRandom.hex(32)])
      INSERT INTO evidence
        (id, created_at, schema_version, organization_id, project_id, source_id, evidence_type,
         producer_id, attempt_id, payload_reference, content_sha256, captured_at_utc, observed_at_utc,
         source_system, collection_method, collector_version, validation_status, data_classification,
         payload_retention_class, correlation_id)
      VALUES ($1::uuid, now(), 'source-document-v1', $2::uuid, $3::uuid, $4::uuid, 'source_document',
              'wf005.ingestion', $1::text, 'ref-'||$1::text, $5, now(), now(),
              'f1.crawler', 'crawl_content_ingestion', 'ingestion-interim-v1', 'valid', 'public',
              'product_evidence_payload', gen_random_uuid())
    SQL
    id
  end

  describe "the Ingestion Job lifecycle (:303)" do
    let(:document_id) { insert_document(url: "https://acme.example/job") }
    let(:job_id) { insert_job(document_id, url: "https://acme.example/job") }

    it "runs the ordinary attempt cycle and makes `succeeded` terminal" do
      expect { move_job(job_id, "running") }.not_to raise_error
      expect { move_job(job_id, "succeeded") }.not_to raise_error

      expect { move_job(job_id, "queued") }
        .to raise_error(PG::RaiseException, /ingestion_job_illegal_transition/)
    end

    it "advances the replay generation on the replay edge, by EXACTLY one" do
      move_job(job_id, "running")
      move_job(job_id, "failed")
      move_job(job_id, "dead_letter")

      # :303 — "increments replay generation exactly once". Two is refused as firmly as zero.
      expect { move_job(job_id, "queued", generation: 2, capsule: true) }
        .to raise_error(PG::RaiseException, /replay_generation_not_incremented/)
      expect { move_job(job_id, "queued", capsule: true) }
        .to raise_error(PG::RaiseException, /replay_generation_not_incremented/)

      expect { move_job(job_id, "queued", generation: 1, capsule: true) }.not_to raise_error
      expect(DbInspector.one("SELECT replay_generation FROM ingestion_jobs WHERE id = $1::uuid",
                             [job_id])["replay_generation"].to_i).to eq(1)
    end

    it "refuses to move the replay generation on any other edge" do
      expect { move_job(job_id, "running", generation: 1) }
        .to raise_error(PG::RaiseException, /replay_generation_immutable/)
    end

    # The capsule is seven columns and ONE fact. A partially-captured replay is exactly the shape a
    # constraint assembled from loose parts admits and review misses.
    it "refuses a partially captured replay capsule" do
      move_job(job_id, "running")
      move_job(job_id, "failed")
      move_job(job_id, "dead_letter")

      expect { move_job(job_id, "queued", generation: 1) }
        .to raise_error(PG::CheckViolation, /ingestion_jobs_replay_capsule/)
    end

    it "freezes the job's identity, including the body digest it is the ingestion of" do
      expect { conn.exec("UPDATE ingestion_jobs SET canonical_url = 'https://x.example/' WHERE id = '#{job_id}'") }
        .to raise_error(PG::RaiseException, /ingestion_job_identity_immutable/)
    end

    it "pins the interim ingestion schema version" do
      expect { conn.exec("UPDATE ingestion_jobs SET ingestion_schema_version = 'v2' WHERE id = '#{job_id}'") }
        .to raise_error(PG::Error)
    end

    # THE SELF-EDGE REPAIR, found by the S-07-010 acceptance chain and twice. :464's "deletes the
    # separate staging reference" is an UPDATE of a `succeeded` row that changes no state, and the
    # first guard evaluated the edge set on EVERY update — so the ratified success path could not
    # execute its own next sentence. The repair admits a state-PRESERVING update and separately
    # forbids it from consuming a state version, because the version counts transitions and a
    # non-transition takes none. Admitting a self-edge in the EDGE SET instead would have let a
    # writer burn versions and break another worker's compare-and-set for no reason.
    it "admits a state-preserving update, and refuses one that consumes a state version" do
      move_job(job_id, "running")
      move_job(job_id, "succeeded")

      expect do
        conn.exec("UPDATE ingestion_jobs SET staged_body_reference = NULL, " \
                  "staged_body_destroyed_at = now() WHERE id = '#{job_id}'")
      end.not_to raise_error

      expect do
        conn.exec("UPDATE ingestion_jobs SET state_version = state_version + 1 WHERE id = '#{job_id}'")
      end.to raise_error(PG::RaiseException, /state_version_without_transition/)
    end
  end

  # ============================================================================
  describe "the durable handoff and the capture contract (:462, :464; MTX-008)" do
    let(:document_id) { insert_document(url: "https://acme.example/handoff") }
    let(:job_id) { insert_job(document_id, url: "https://acme.example/handoff") }

    # MTX-008 — "the durable handoff record IS the succeeded IngestionJob with its valid
    # `source_document` Evidence"; :464 — "No Document may become ingested ... WITHOUT that valid
    # Evidence." Enforced by the DATABASE, which is what lets S-08's parse manifest read
    # `state = 'succeeded'` without re-validating every row it selects.
    it "refuses a succeeded job that carries no Evidence" do
      move_job(job_id, "running")
      expect do
        conn.exec("UPDATE ingestion_jobs SET state = 'succeeded', completed_at = now(), " \
                  "state_version = state_version + 1 WHERE id = '#{job_id}'")
      end.to raise_error(PG::CheckViolation, /ingestion_jobs_succeeded_carries_evidence/)
    end

    it "refuses an Evidence link on a job that did not succeed" do
      # :464 creates the Evidence AT SUCCESS and nowhere else, so a `failed` or `dead_letter` job
      # carrying one would be a handoff a parsing consumer must not observe.
      evidence = insert_evidence
      move_job(job_id, "running")
      expect do
        conn.exec("UPDATE ingestion_jobs SET state = 'failed', last_reason_code = 'ingest_timeout', " \
                  "completed_at = now(), evidence_id = '#{evidence}', " \
                  "state_version = state_version + 1 WHERE id = '#{job_id}'")
      end.to raise_error(PG::CheckViolation, /ingestion_jobs_evidence_only_on_success/)
    end

    # THE DURABLE HANDOFF MAY NOT CROSS A PROJECT BOUNDARY (review round 1, R1-1).
    #
    # POSTGRESQL_SCHEMA.md :128 requires all three of `(organization_id, project_id, id)` on a
    # Project-owned link "rather than a separate Project lookup or application assertion".
    # `ingestion_jobs.evidence_id` carried two, because `evidence` offers no three-column unique to
    # point at — and the review drove this INSERT live and the database ACCEPTED it. FU-7's class,
    # fourth occurrence, and acceptance-blocking here because MTX-008 makes this column THE durable
    # handoff and :472 makes a cross-boundary manifest reference `input_manifest_invalid`.
    it "refuses Evidence belonging to another Project of the same Organization" do
      other_project = draft_project
      other_source = insert_source(other_project)
      foreign = insert_evidence(project: other_project, source: other_source)
      move_job(job_id, "running")

      expect { move_job(job_id, "succeeded", evidence: foreign) }
        .to raise_error(PG::RaiseException, /ingestion_job_evidence_out_of_scope/)
    end

    it "refuses Evidence for another Source of the SAME Project" do
      # :462 keys the job to one Source, and the Evidence F-03 produces for it carries that Source. A
      # link that agreed on Project and disagreed on Source would still be a handoff to the wrong
      # artifact, so the containment covers all three columns the foreign key would have.
      sibling = insert_source(project_id)
      foreign = insert_evidence(source: sibling)
      move_job(job_id, "running")

      expect { move_job(job_id, "succeeded", evidence: foreign) }
        .to raise_error(PG::RaiseException, /ingestion_job_evidence_out_of_scope/)
    end

    it "admits Evidence that is contained, so the containment is not a blanket refusal" do
      move_job(job_id, "running")
      expect { move_job(job_id, "succeeded") }.not_to raise_error
      expect(DbInspector.one("SELECT evidence_id FROM ingestion_jobs WHERE id=$1::uuid", [job_id])["evidence_id"])
        .not_to be_nil
    end

    it "makes the Evidence link WRITE-ONCE, so an earlier snapshot cannot be re-pointed" do
      # MTX-008 concurrency — "concurrent completion or replay CANNOT change an earlier snapshot".
      first = insert_evidence
      second = insert_evidence
      move_job(job_id, "running")
      move_job(job_id, "succeeded", evidence: first)

      expect { conn.exec("UPDATE ingestion_jobs SET evidence_id = '#{second}' WHERE id = '#{job_id}'") }
        .to raise_error(PG::RaiseException, /ingestion_job_evidence_immutable/)
    end

    # ":462 — Staged body bytes are IMMUTABLE." Present -> destroyed is the whole lifecycle: a
    # re-staged job would hand a replay different bytes under the same digest, and pointing the
    # reference elsewhere is the same thing with an extra step.
    it "lets the staged reference be destroyed and nothing else" do
      expect do
        conn.exec("UPDATE ingestion_jobs SET staged_body_reference = gen_random_uuid() WHERE id = '#{job_id}'")
      end.to raise_error(PG::RaiseException, /ingestion_job_staged_body_immutable/)

      conn.exec("UPDATE ingestion_jobs SET staged_body_reference = NULL, " \
                "staged_body_destroyed_at = now() WHERE id = '#{job_id}'")

      expect do
        conn.exec("UPDATE ingestion_jobs SET staged_body_reference = gen_random_uuid(), " \
                  "staged_body_destroyed_at = NULL WHERE id = '#{job_id}'")
      end.to raise_error(PG::RaiseException, /ingestion_job_staged_body_immutable/)
    end

    it "keeps `destroyed` and `never staged` distinguishable" do
      # The biconditional is what makes `staged_body_missing` a real answer rather than a guess: a
      # NULL reference always means destroyed, and it always says when.
      expect do
        conn.exec("UPDATE ingestion_jobs SET staged_body_reference = NULL WHERE id = '#{job_id}'")
      end.to raise_error(PG::CheckViolation, /ingestion_jobs_staging_shape/)
    end

    # FU-30's lesson, applied where :466 puts a bound on the party that holds the bytes: a retention
    # limit the retainer may extend is not a retention limit. The capture columns go with it, because
    # a job whose description of its own input can change is a job whose Evidence provenance is
    # worthless.
    it "freezes the 24-hour staging deadline and the capture the job describes" do
      { "staging_expires_at" => "now() + interval '999 hours'",
        "received_byte_count" => "1", "media_type" => "'application/pdf'",
        "final_http_status" => "204",
        "response_capture_policy_version" => "'crawl-policy-v2'",
        "queued_at" => "now() - interval '1 hour'" }.each do |column, value|
        expect { conn.exec("UPDATE ingestion_jobs SET #{column} = #{value} WHERE id = '#{job_id}'") }
          .to raise_error(PG::RaiseException, /ingestion_job_identity_immutable/), "#{column} was not frozen"
      end
    end

    it "admits only a 2xx final status, because a 3xx names a hop rather than a response" do
      expect { insert_job_with_status(document_id, 302) }.to raise_error(PG::CheckViolation)
      expect { insert_job_with_status(document_id, 404) }.to raise_error(PG::CheckViolation)
    end

    def insert_job_with_status(document_id, status)
      params = [SecureRandom.uuid_v7, org, project_id, source_id, crawl_id, document_id,
                "https://acme.example/s#{status}", sha("b#{status}"), now_iso, status]
      conn.exec_params(<<~SQL, params)
        INSERT INTO ingestion_jobs
          (id, state_version, schema_version, created_at, updated_at, correlation_id, causation_id,
           organization_id, project_id, source_id, crawl_id, document_id, canonical_url,
           fetched_body_sha256, ingestion_schema_version, state, final_http_status, media_type,
           staged_body_reference, staging_expires_at, received_byte_count,
           response_capture_policy_version, data_classification, idempotency_key, queued_at)
        VALUES ($1::uuid,0,'ingestion-job-v1',$9::timestamptz,$9::timestamptz,gen_random_uuid(),
                gen_random_uuid(),$2::uuid,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7,$8,
                'ingestion-interim-v1','queued',$10::integer,'text/html',gen_random_uuid(),
                $9::timestamptz + interval '24 hours',1024,'crawl-policy-v1','public','k',$9::timestamptz)
      SQL
    end
  end

  # ============================================================================
  #
  # OWNER RULING 2, MEASURED RATHER THAN CATALOGUED. `crawl_terminal_fact_closure_spec`'s PROOF 156
  # derives every Crawl child table and requires each to carry the closure TRIGGER — which is the
  # right check for "was this table classified" and says nothing about whether the trigger still
  # REFUSES anything. A mutation that leaves the trigger in place with a WHEN clause that never holds
  # passes PROOF 156 untouched; it was measured surviving before these two examples existed.
  describe "post-terminal closure, as behaviour (owner ruling 2)" do
    # `f1_crawls_guard` admits `queued -> canceled`, and `crawls_terminal_shape` requires the terminal
    # instant and reason with it. The real edge a cancellation takes, not a fixture shortcut.
    def terminalize(id)
      conn.exec_params(<<~SQL, [id])
        UPDATE crawls SET state='canceled', terminal_at=now(), completion_reason='canceled',
                          state_version = state_version + 1, updated_at = now()
        WHERE id = $1::uuid
      SQL
    end

    it "refuses a Document created against an already-terminal Crawl" do
      # A Document is the coverage-bearing product of a run — :452 makes a covered outcome depend on
      # one existing — so one appearing after the terminal selection changes a coverage number that
      # has already been reported, and `f1_crawls_guard` refuses every correction.
      expect { insert_document(url: "https://acme.example/live") }.not_to raise_error
      terminalize(crawl_id)

      expect { insert_document(url: "https://acme.example/late") }
        .to raise_error(PG::RaiseException, /crawl_child_fact_after_terminal/)
    end

    it "refuses an IngestionJob created against an already-terminal Crawl, and leaves its LATER transitions legal" do
      document = insert_document(url: "https://acme.example/closure")
      job = insert_job(document, url: "https://acme.example/closure")
      terminalize(crawl_id)

      # THE CLOSURE IS ON INSERT ONLY, WHICH IS THE POINT: ingestion EXECUTES after the crawl ends —
      # that is what the durable handoff IS — so the job's own lifecycle must keep running.
      expect { move_job(job, "running") }.not_to raise_error
      expect { move_job(job, "succeeded") }.not_to raise_error

      expect { insert_job(document, url: "https://acme.example/closure", state: "queued") }
        .to raise_error(PG::Error)
    end
  end

  # ============================================================================
  describe "Document version allocation (:302, :462)" do
    # :462 — "A DIFFERENT BODY DIGEST creates a NEW VERSIONED Document/job and never overwrites prior
    # Evidence." Driven through the PRODUCTION WRITER rather than raw SQL, because the allocation is
    # the writer's: `MAX + 1` over the URL's own history on that Source, predecessor set to the row
    # that held the maximum, under the per-URL advisory lock that makes two concurrent Crawls of one
    # Source compute different numbers instead of colliding on the unique key.
    def create_via_store(url, seed)
      Platform::UnitOfWork.run do |c|
        pg = c.raw_connection
        store = IdentityAccess::Infrastructure::DocumentStore.new(pg)
        store.enter_org_context(org:, correlation_id: SecureRandom.uuid_v7)
        digest = Digest::SHA256.digest(url)
        store.lock_document_line(source_id, digest)
        store.create(id: SecureRandom.uuid_v7, now: Time.now.utc, correlation_id: SecureRandom.uuid_v7,
                     causation_id: SecureRandom.uuid_v7, command_id: nil, organization_id: org,
                     project_id:, source_id:, crawl_id:, canonical_url: url,
                     canonical_url_sha256: digest, fetched_object_id: SecureRandom.uuid_v7,
                     media_type: "text/html", byte_size: 10, content_sha256: Digest::SHA256.digest(seed))
      end
    end

    it "numbers versions from 1 and links each to its predecessor" do
      first = create_via_store("https://acme.example/v", "body-1")
      second = create_via_store("https://acme.example/v", "body-2")
      third = create_via_store("https://acme.example/v", "body-3")

      expect(first["version"].to_i).to eq(1)
      expect(first["predecessor_document_id"]).to be_nil
      expect(second["version"].to_i).to eq(2)
      expect(second["predecessor_document_id"]).to eq(first["id"])
      expect(third["version"].to_i).to eq(3)
      expect(third["predecessor_document_id"]).to eq(second["id"])
    end

    it "numbers a different URL on the same Source independently" do
      create_via_store("https://acme.example/v", "body-1")
      other = create_via_store("https://acme.example/other", "body-1")

      expect(other["version"].to_i).to eq(1)
      expect(other["predecessor_document_id"]).to be_nil
    end

    # PRULE-009 / MTX-008 — "each successful SAME-VERSION job advances the Document EXACTLY ONCE,
    # guarded ON THE DOCUMENT BY ITS VERSION rather than by delivery deduplication." The guard is the
    # compare-and-set, so it has to be measured as one: a stale version advances nothing.
    it "advances a Document only on the version the caller read" do
      document = create_via_store("https://acme.example/advance", "body-1")
      moved = Platform::UnitOfWork.run do |c|
        store = IdentityAccess::Infrastructure::DocumentStore.new(c.raw_connection)
        store.enter_org_context(org:, correlation_id: SecureRandom.uuid_v7)
        store.mark_ingested(org, document["id"], 7, Time.now.utc)
      end
      expect(moved.to_i).to eq(0)
      expect(DbInspector.one("SELECT state FROM documents WHERE id=$1::uuid", [document["id"]])["state"])
        .to eq("discovered")

      moved = Platform::UnitOfWork.run do |c|
        store = IdentityAccess::Infrastructure::DocumentStore.new(c.raw_connection)
        store.enter_org_context(org:, correlation_id: SecureRandom.uuid_v7)
        store.mark_ingested(org, document["id"], 0, Time.now.utc)
      end
      expect(moved.to_i).to eq(1)
      expect(DbInspector.one("SELECT state FROM documents WHERE id=$1::uuid", [document["id"]])["state"])
        .to eq("ingested")
    end
  end

  describe "the Ingestion Attempt record (:304)" do
    let(:document_id) { insert_document(url: "https://acme.example/attempt") }
    let(:job_id) { insert_job(document_id, url: "https://acme.example/attempt", state: "running") }

    def insert_attempt(job_id, number: 1)
      id = SecureRandom.uuid_v7
      params = [id, org, project_id, job_id, number, sha("input-#{number}"), now_iso]
      conn.exec_params(<<~SQL, params)
        INSERT INTO ingestion_attempts
          (id, schema_version, created_at, updated_at, correlation_id, causation_id,
           organization_id, project_id, ingestion_job_id, attempt_number, input_sha256,
           scheduled_at, started_at, deadline_at)
        VALUES ($1,'ingestion-attempt-v1',$7::timestamptz,$7::timestamptz,gen_random_uuid(),gen_random_uuid(),
                $2::uuid,$3::uuid,$4::uuid,$5::int,$6,$7::timestamptz,$7::timestamptz,
                $7::timestamptz + interval '5 minutes')
      SQL
      id
    end

    it "is write-once at its outcome — a terminal attempt cannot be re-decided" do
      attempt = insert_attempt(job_id)
      # The completion instant comes from the FIXTURE clock, not `now()`: the fixture's instant is
      # deliberately fixed, and a real `now()` earlier than `started_at` trips
      # `ingestion_attempts_started_before_completed` — which is the constraint doing its job, not the
      # property this example is about.
      conn.exec("UPDATE ingestion_attempts SET outcome = 'failed', completed_at = '#{now_iso}', " \
                "reason_code = 'ingestion_failed' WHERE id = '#{attempt}'")

      expect { conn.exec("UPDATE ingestion_attempts SET reason_code = 'other' WHERE id = '#{attempt}'") }
        .to raise_error(PG::RaiseException, /ingestion_attempt_terminal/)
    end

    it "freezes the attempt's job, number and input identity" do
      attempt = insert_attempt(job_id)

      expect { conn.exec("UPDATE ingestion_attempts SET attempt_number = 2 WHERE id = '#{attempt}'") }
        .to raise_error(PG::RaiseException, /ingestion_attempt_identity_immutable/)
    end

    it "carries no outcome without a completion instant, and no success without its output" do
      attempt = insert_attempt(job_id)

      expect { conn.exec("UPDATE ingestion_attempts SET outcome = 'succeeded' WHERE id = '#{attempt}'") }
        .to raise_error(PG::CheckViolation, /ingestion_attempts_terminal_shape/)

      expect do
        conn.exec("UPDATE ingestion_attempts SET outcome = 'succeeded', completed_at = '#{now_iso}' " \
                  "WHERE id = '#{attempt}'")
      end.to raise_error(PG::CheckViolation, /ingestion_attempts_terminal_shape/)
    end

    it "numbers attempts uniquely within one job" do
      insert_attempt(job_id, number: 1)

      expect { insert_attempt(job_id, number: 1) }.to raise_error(PG::UniqueViolation)
      expect { insert_attempt(job_id, number: 2) }.not_to raise_error
    end
  end

  describe "tenancy and grants" do
    it "forces row-level security on all three tables" do
      %w[documents ingestion_jobs ingestion_attempts].each do |table|
        row = DbInspector.one("SELECT relrowsecurity, relforcerowsecurity FROM pg_class WHERE relname = $1",
                              [table])
        expect(row["relrowsecurity"]).to eq("t"), "#{table} does not enable RLS"
        expect(row["relforcerowsecurity"]).to eq("t"), "#{table} does not FORCE RLS"
      end
    end

    # :302 — a Document "leaves product use only through the separate retention and deletion
    # lifecycle, which destroys the row rather than transitioning it". That lifecycle is not built and
    # is not S-07-010's, so no runtime role may destroy one yet.
    it "grants the runtime no DELETE on any of the three" do
      %w[documents ingestion_jobs ingestion_attempts].each do |table|
        granted = DbInspector.all(<<~SQL, [table]).map { |r| r["privilege_type"] }
          SELECT privilege_type FROM information_schema.role_table_grants
          WHERE table_name = $1 AND grantee = 'f1_runtime'
        SQL

        expect(granted).not_to include("DELETE"), "#{table} grants DELETE to f1_runtime"
        expect(granted).to include("SELECT", "INSERT", "UPDATE"), "#{table} is missing a runtime grant"
      end
    end
  end
end
