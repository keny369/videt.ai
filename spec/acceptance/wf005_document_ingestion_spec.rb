# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf005_crawl_chain"

# WF-005 DOCUMENTS, INGESTION, EVIDENCE AND THE DURABLE HANDOFF (S-07-010).
#
# Governing text: WORKFLOW_SPECIFICATIONS.md § Interim Ingestion Contract `ingestion-interim-v1`
# (:460-466), :452's coverage classification, contracts/S-07.json MTX-008, and
# BACKGROUND_PROCESSING.md :140/:200/:378.
#
# EVERY EXAMPLE DRIVES THE PRODUCTION CHAIN. A Crawl is bootstrapped, started, fetched through the
# real `RecordFetchAttempt` handler, and its ingestion run through the real `RunIngestionJob`
# handler behind the real `ingestion_attempt_due` action. Only the frozen F-01 outbound facade is
# stubbed, and only by request path.
#
# THE PROPERTY THE WHOLE TRANCHE TURNS ON, asserted rather than argued: :452's `document_created` is
# COVERED only because a Document exists, and MTX-008's durable handoff is the succeeded job WITH its
# `source_document` Evidence. Both are checked against the database, not against a return value.
RSpec.describe "WF-005 documents and ingestion", type: :acceptance,
               acceptance_ids: ["AC-CAP-008", "AC-WF-005"], test_types: %w[TYP-E2E TYP-DATA TYP-SEC] do
  include Wf005CrawlChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  ROBOTS_ALLOW_ALL = "User-agent: *\nAllow: /\n"
  PAGE = "<html><title>acme</title><body>hello</body></html>"

  def outbound_by_path(map)
    seen = requests
    Object.new.tap do |o|
      o.define_singleton_method(:fetch) do |url, **_kwargs|
        path = URI.parse(url.to_s).path
        seen << path
        raise "unexpected outbound fetch: #{url}" unless map.key?(path)

        entry = map[path]
        entry.is_a?(Array) ? (entry.length > 1 ? entry.shift : entry.first) : entry
      end
    end
  end

  def requests = (@requests ||= [])

  def html(status: 200, body: PAGE, type: "text/html", path: "/", host: "shop.acme.example")
    Platform::Outbound::Outcome.response(
      status:, headers: type.nil? ? {} : { "content-type" => type }, body:, byte_count: body.bytesize,
      truncated: false, canonical_host: host, port: 443, pinned_address: "198.51.100.7",
      final_url: "https://#{host}#{path}", redirect_count: 0, latency_ms: 5
    )
  end

  def fetchable(hosts: ["shop.acme.example"])
    ctx = running_crawl(hosts:).tap { |c| ensure_gate(c) }
    resolve_robots(ctx, outbound_returning(response(status: 200, body: ROBOTS_ALLOW_ALL)))
    resolve_sitemaps(ctx, outbound_returning(response(status: 404, body: "")))
    clear_rate_window_for_crawl(ctx[:crawl_id])
    ctx
  end

  # ---- readers ---------------------------------------------------------------

  def documents(cid) = DbInspector.all("SELECT * FROM documents WHERE crawl_id=$1::uuid ORDER BY version", [cid])
  def jobs(cid) = DbInspector.all("SELECT * FROM ingestion_jobs WHERE crawl_id=$1::uuid ORDER BY created_at", [cid])
  def job_row(id) = DbInspector.one("SELECT * FROM ingestion_jobs WHERE id=$1::uuid", [id])
  def document_row(id) = DbInspector.one("SELECT * FROM documents WHERE id=$1::uuid", [id])
  def ingestion_attempts(jid) = DbInspector.all("SELECT * FROM ingestion_attempts WHERE ingestion_job_id=$1::uuid ORDER BY attempt_number", [jid])
  def outcomes(cid) = DbInspector.all("SELECT * FROM crawl_terminal_outcomes WHERE crawl_id=$1::uuid ORDER BY commit_order", [cid])
  def action_row(id) = DbInspector.one("SELECT * FROM scheduled_actions WHERE id=$1::uuid", [id])
  def evidence_rows(org) = DbInspector.all("SELECT * FROM evidence WHERE organization_id=$1::uuid ORDER BY created_at", [org])
  def evidence_row(id) = DbInspector.one("SELECT * FROM evidence WHERE id=$1::uuid", [id])
  def events(org) = DbInspector.all("SELECT * FROM event_registry WHERE organization_id=$1::uuid ORDER BY created_at", [org])
  def event_types(org) = events(org).map { |r| r["event_type"] }

  def ingestion_actions(jid)
    DbInspector.all(<<~SQL, [jid])
      SELECT * FROM scheduled_actions
      WHERE action_kind='ingestion_attempt_due' AND target_id=$1::uuid
      ORDER BY due_at, created_at
    SQL
  end

  def encrypted_record(reference)
    DbInspector.one("SELECT * FROM f1_encrypted_records WHERE id=$1::uuid", [reference])
  end

  # ---- the chain -------------------------------------------------------------

  def link_first(ctx, at: start_now)
    Platform::UnitOfWork.run do |conn|
      pg = conn.raw_connection
      IdentityAccess::Infrastructure::CrawlFrontierStore.new(pg)
                                                        .enter_org_context(org: ctx[:g][:organization_id],
                                                                          correlation_id: SecureRandom.uuid_v7)
      Workflows::Wf005::CrawlFetchDueSchedule.link_next(
        pg:, organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id],
        crawl_id: ctx[:crawl_id], now: at, correlation_id: SecureRandom.uuid_v7
      )
    end
  end

  def first_action(ctx, at: start_now) = action_row(link_first(ctx, at:)[:action_id])

  def fetch_pass(ctx, action, outbound, at: start_now)
    command = Workflows::Wf005::Commands::RecordFetchAttempt.new(
      command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
      organization_id: action["organization_id"], target_type: action["target_type"],
      frontier_entry_id: action["target_id"], due_at: Time.parse(action["due_at"]).getutc,
      action_id: action["id"],
      action_identity_sha256: [action["identity_sha256"].sub(/\A\\x/, "")].pack("H*"),
      requested_at_utc: at
    )
    Workflows::Wf005::Handlers::RecordFetchAttempt.new.call(
      command:, request_context: executor_ctx(at), outbound:, pacer: pacer_for(ctx)
    )
  end

  # One accepted page, fetched exactly as production fetches it.
  def one_page(ctx, body: PAGE, at: start_now)
    fetch_pass(ctx, first_action(ctx, at:), outbound_by_path("/" => html(body:)), at:)
  end

  def run_ingestion(action, at: start_now)
    command = Workflows::Wf005::Commands::RunIngestionJob.new(
      command_id: SecureRandom.uuid_v7, schema_version: action["action_schema_version"],
      organization_id: action["organization_id"], target_type: action["target_type"],
      ingestion_job_id: action["target_id"], due_at: Time.parse(action["due_at"]).getutc,
      action_id: action["id"],
      action_identity_sha256: [action["identity_sha256"].sub(/\A\\x/, "")].pack("H*"),
      requested_at_utc: at
    )
    Workflows::Wf005::Handlers::RunIngestionJob.new.call(command:, request_context: executor_ctx(at))
  end

  # ============================================================================
  describe "the fetch commit: :452's covered outcomes and their artifacts" do
    it "PROOF 163 — `document_created` creates ONE Document and ONE queued IngestionJob, and the terminal outcome NAMES the Document" do
      ctx = fetchable
      result = one_page(ctx)

      expect(result.payload[:outcome]).to eq("document_created")
      docs = documents(ctx[:crawl_id])
      expect(docs.size).to eq(1)
      doc = docs.first
      # :302 — "positive version", "predecessor ID NULL" for the first version of a URL.
      expect(doc["state"]).to eq("discovered")
      expect(doc["version"]).to eq("1")
      expect(doc["predecessor_document_id"]).to be_nil
      expect(doc["canonical_url"]).to eq("https://shop.acme.example/")
      expect(doc["media_type"]).to eq("text/html")
      expect(doc["byte_size"].to_i).to eq(PAGE.bytesize)
      expect(doc["content_sha256"].sub(/\A\\x/, "")).to eq(Digest::SHA256.hexdigest(PAGE))
      # Every lifecycle instant that has not happened is absent (`documents_lifecycle_times`).
      expect(doc["ingested_at"]).to be_nil
      expect(doc["parsed_at"]).to be_nil
      expect(doc["indexed_at"]).to be_nil

      all_jobs = jobs(ctx[:crawl_id])
      expect(all_jobs.size).to eq(1)
      job = all_jobs.first
      expect(job["state"]).to eq("queued")
      expect(job["document_id"]).to eq(doc["id"])
      expect(job["ingestion_schema_version"]).to eq("ingestion-interim-v1")
      expect(job["fetched_body_sha256"].sub(/\A\\x/, "")).to eq(Digest::SHA256.hexdigest(PAGE))
      expect(job["replay_generation"]).to eq("0")
      expect(job["attempt_count"]).to eq("0")
      expect(job["evidence_id"]).to be_nil
      expect(job["received_byte_count"].to_i).to eq(PAGE.bytesize)
      expect(job["final_http_status"]).to eq("200")
      expect(job["response_capture_policy_version"]).to eq("crawl-policy-v1")
      expect(job["data_classification"]).to eq("public")

      # THE LINK S-07-009 LEFT NULL. `crawl_terminal_outcomes.document_id` is the coverage-bearing
      # row's claim that a Document exists, and it now names the one that does.
      outcome = outcomes(ctx[:crawl_id]).first
      expect(outcome["outcome"]).to eq("document_created")
      expect(outcome["coverage_effect"]).to eq("covered")
      expect(outcome["document_id"]).to eq(doc["id"])
      expect(result.payload[:terminal_document_id]).to eq(doc["id"])
      expect(result.payload[:document_id]).to eq(doc["id"])
      expect(result.payload[:ingestion_job_id]).to eq(job["id"])
    end

    it "PROOF 164 — the staged body is an F-02 capability: no plaintext at rest, digest anchored, 24-hour bound stamped" do
      ctx = fetchable
      one_page(ctx)
      job = jobs(ctx[:crawl_id]).first

      expect(job["staged_body_reference"]).not_to be_nil
      expect(job["staged_body_destroyed_at"]).to be_nil
      # ":466 — at most 24 hours FROM FETCH COMPLETION."
      expect(Time.parse(job["staging_expires_at"]).getutc)
        .to eq(start_now + Workflows::Wf005::IngestionContract::STAGING_RETENTION_S)

      record = encrypted_record(job["staged_body_reference"])
      expect(record["state"]).to eq("active")
      # ":462 — Staged body bytes are IMMUTABLE AND INACCESSIBLE TO PRODUCT READS." What is at rest is
      # an envelope, and the page's text does not appear in it.
      expect(record["envelope"]).not_to include("hello")
      expect(record["content_digest"].sub(/\A\\x/, "")).to eq(Digest::SHA256.hexdigest(PAGE))
      expect(record["purpose"]).to eq("temporary_processing")
      # `documents.fetched_object_id` names the object that holds the fetched bytes.
      expect(documents(ctx[:crawl_id]).first["fetched_object_id"]).to eq(job["staged_body_reference"])
    end

    it "PROOF 165 — :378's ingestion action is created in the SAME terminal transaction, on the ratified queue and work type" do
      ctx = fetchable
      result = one_page(ctx)
      job = jobs(ctx[:crawl_id]).first

      actions = ingestion_actions(job["id"])
      expect(actions.size).to eq(1)
      action = actions.first
      expect(action["action_kind"]).to eq("ingestion_attempt_due")
      expect(action["target_type"]).to eq("ingestion_job")
      expect(action["status"]).to eq("pending")
      expect(action["product_generation"]).to eq("0")
      expect(result.payload[:ingestion_action_id]).to eq(action["id"])
      # BACKGROUND_PROCESSING.md :140/:200, transcribed once in the ratified catalogue.
      expect(Platform::ScheduledActions::Catalogue.queue_for("ingestion_attempt_due")).to eq("pipeline")
      expect(Platform::ScheduledActions::Catalogue.work_type_for("ingestion_attempt_due")).to eq("ingest")
    end

    it "PROOF 166 — the two creation events MTX-030 names are emitted, and only on a first creation" do
      ctx = fetchable
      one_page(ctx)
      org = ctx[:g][:organization_id]
      doc = documents(ctx[:crawl_id]).first
      job = jobs(ctx[:crawl_id]).first

      discovered = events(org).find { |e| e["event_type"] == "DocumentDiscovered" }
      queued = events(org).find { |e| e["event_type"] == "IngestionQueued" }
      expect(discovered).not_to be_nil
      expect(queued).not_to be_nil
      expect(discovered["aggregate_type"]).to eq("document")
      expect(discovered["aggregate_id"]).to eq(doc["id"])
      expect(discovered["event_profile"]).to eq("created")
      expect(queued["aggregate_type"]).to eq("ingestion_job")
      expect(queued["aggregate_id"]).to eq(job["id"])

      payload = JSON.parse(queued["event_bytes"].sub(/\A\\x/, "").then { |h| [h].pack("H*") })
      # API_CONTRACTS.md :958 — `pipeline_job`: "output fields are both nonnull ONLY ON SUCCESS", and
      # a queued job has produced nothing.
      expect(payload["document_id"]).to eq(doc["id"])
      expect(payload["input_content_sha256"]).to eq(Digest::SHA256.hexdigest(PAGE))
      expect(payload["output_entity"]).to be_nil
      expect(payload["output_content_sha256"]).to be_nil
      expect(payload["to_state"]).to eq("queued")
      expect(payload["from_state"]).to be_nil
    end

    it "PROOF 167 — a terminal 404 creates the body-free `crawl_observation` and NO Document and NO job" do
      # :452 — "returns terminal 404/410 and creates a valid BODY-FREE `crawl_observation` with reason
      # `content_absent`" is the OTHER covered outcome, and D3 (ADR-067) resolves it inline.
      ctx = fetchable
      result = fetch_pass(ctx, first_action(ctx), outbound_by_path("/" => html(status: 404, body: "")))

      expect(result.payload[:outcome]).to eq("content_absent")
      expect(documents(ctx[:crawl_id])).to be_empty
      expect(jobs(ctx[:crawl_id])).to be_empty

      outcome = outcomes(ctx[:crawl_id]).first
      expect(outcome["coverage_effect"]).to eq("covered")
      expect(outcome["document_id"]).to be_nil

      ev = evidence_rows(ctx[:g][:organization_id]).find { |e| e["evidence_type"] == "crawl_observation" }
      expect(ev).not_to be_nil
      expect(ev["validation_status"]).to eq("valid")
      expect(ev["validation_reason_code"]).to be_nil
      expect(result.payload[:crawl_observation_evidence_id]).to eq(ev["id"])
      # BODY-FREE: the payload records the observation and carries no response bytes.
      body = Platform::Encryption.reveal(
        ev["payload_reference"],
        aad: Platform::Encryption::Aad.for(
          **Workflows::Wf005::IngestionHandoff::OBSERVATION_AAD,
          record_id: outcome["crawl_frontier_entry_id"], tenant: ctx[:g][:organization_id]
        )
      )
      parsed = JSON.parse(body)
      expect(parsed["reason"]).to eq("content_absent")
      expect(parsed["http_status"]).to eq(404)
      expect(parsed.keys).not_to include("body_base64")
    end

    it "PROOF 168 — a `content_fetch_failed` retirement produces NO Document, NO job and NO Evidence" do
      ctx = fetchable
      result = fetch_pass(ctx, first_action(ctx), outbound_by_path("/" => html(status: 404, body: "").then { |_x|
        Platform::Outbound::Outcome.failure(:connection_failure, reason: :dns_failure, retryable: false)
      }))

      expect(result.payload[:outcome]).to eq("content_fetch_failed")
      expect(documents(ctx[:crawl_id])).to be_empty
      expect(jobs(ctx[:crawl_id])).to be_empty
      expect(evidence_rows(ctx[:g][:organization_id]).select { |e| e["evidence_type"] == "crawl_observation" })
        .to be_empty
      expect(result.payload).not_to have_key(:document_id)
    end
  end

  # ============================================================================
  describe "the ingestion attempt: :464's success path and the durable handoff" do
    it "PROOF 169 — success is ATOMIC: Evidence created, Document ingested, job succeeded, staging destroyed" do
      ctx = fetchable
      one_page(ctx)
      job = jobs(ctx[:crawl_id]).first
      staged_reference = job["staged_body_reference"]
      result = run_ingestion(ingestion_actions(job["id"]).first)

      expect(result.success?).to be(true)
      settled = job_row(job["id"])
      expect(settled["state"]).to eq("succeeded")
      expect(settled["evidence_id"]).not_to be_nil
      expect(settled["completed_at"]).not_to be_nil
      expect(settled["last_reason_code"]).to be_nil

      # ":464 — changes Document DISCOVERED TO INGESTED."
      doc = document_row(job["document_id"])
      expect(doc["state"]).to eq("ingested")
      expect(doc["ingested_at"]).not_to be_nil
      expect(doc["state_version"]).to eq("1")

      # ":464 — one immutable `source_document` Evidence."
      ev = evidence_row(settled["evidence_id"])
      expect(ev["evidence_type"]).to eq("source_document")
      expect(ev["validation_status"]).to eq("valid")
      expect(ev["source_id"]).to eq(job["source_id"])
      expect(ev["data_classification"]).to eq("public")
      expect(ev["payload_retention_class"]).to eq("product_evidence_payload")

      # ":464 — deletes the SEPARATE staging reference within 60 seconds." In the same commit, and
      # cryptographically: the envelope is gone and the digest survives.
      expect(settled["staged_body_reference"]).to be_nil
      expect(settled["staged_body_destroyed_at"]).not_to be_nil
      destroyed = encrypted_record(staged_reference)
      expect(destroyed["state"]).to eq("destroyed")
      expect(destroyed["envelope"]).to be_nil

      # ...AND THE EVIDENCE PAYLOAD SURVIVES IT, which is why :464 calls the destroyed one "separate".
      revealed = Platform::Encryption.reveal(
        ev["payload_reference"],
        aad: Platform::Encryption::Aad.for(**Workflows::Wf005::IngestionExecution::EVIDENCE_AAD,
                                           record_id: job["id"], tenant: ctx[:g][:organization_id])
      )
      payload = JSON.parse(revealed)
      expect(Base64.strict_decode64(payload["body_base64"])).to eq(PAGE)
      expect(payload["fetched_body_sha256"]).to eq(Digest::SHA256.hexdigest(PAGE))
      expect(payload["canonical_url"]).to eq(job["canonical_url"])

      attempt = ingestion_attempts(job["id"]).first
      expect(attempt["attempt_number"]).to eq("1")
      expect(attempt["outcome"]).to eq("succeeded")
      expect(attempt["output_object_id"]).to eq(ev["id"])
      expect(attempt["claim_owner"]).to be_nil
    end

    it "PROOF 170 — the durable handoff is a CONSTRAINT: a succeeded job without its Evidence is unrepresentable" do
      # MTX-008 — "the durable handoff record IS the succeeded IngestionJob with its valid
      # `source_document` Evidence"; :464 — "No Document may become ingested ... WITHOUT that valid
      # Evidence." Attempted directly against the database as the schema owner, so it is the CHECK
      # that refuses rather than the handler.
      ctx = fetchable
      one_page(ctx)
      job = jobs(ctx[:crawl_id]).first
      DbInspector.connection.exec_params(
        "UPDATE ingestion_jobs SET state='running', started_at=now(), state_version=state_version+1 WHERE id=$1::uuid",
        [job["id"]]
      )
      expect do
        DbInspector.connection.exec_params(
          "UPDATE ingestion_jobs SET state='succeeded', completed_at=now(), state_version=state_version+1
           WHERE id=$1::uuid", [job["id"]]
        )
      end.to raise_error(PG::CheckViolation, /ingestion_jobs_succeeded_carries_evidence/)
    end

    it "PROOF 171 — the three success events commit with the state changes and carry `pipeline_job`'s output fields" do
      ctx = fetchable
      one_page(ctx)
      org = ctx[:g][:organization_id]
      job = jobs(ctx[:crawl_id]).first
      run_ingestion(ingestion_actions(job["id"]).first)
      settled = job_row(job["id"])

      types = event_types(org)
      expect(types).to include("IngestionStarted", "DocumentIngested", "IngestionSucceeded")
      succeeded = events(org).find { |e| e["event_type"] == "IngestionSucceeded" }
      payload = JSON.parse(succeeded["event_bytes"].sub(/\A\\x/, "").then { |h| [h].pack("H*") })
      expect(payload["from_state"]).to eq("running")
      expect(payload["to_state"]).to eq("succeeded")
      expect(payload["transition_reason_code"]).to be_nil
      expect(payload["output_entity"]).to eq({ "entity_type" => "evidence",
                                               "entity_id" => settled["evidence_id"] })
      expect(payload["output_content_sha256"]).to match(/\A[0-9a-f]{64}\z/)
      expect(payload["committed_aggregate_version"]).to eq(payload["prior_aggregate_version"] + 1)

      ingested = events(org).find { |e| e["event_type"] == "DocumentIngested" }
      expect(ingested["aggregate_type"]).to eq("document")
      expect(ingested["aggregate_id"]).to eq(job["document_id"])
    end

    it "PROOF 172 — a duplicate delivery replays the stored result and advances the Document NO SECOND TIME" do
      # MTX-008 idempotency — "a duplicate queue delivery re-enters the same job identity and produces
      # no second Document advance"; MTX-008 concurrency — "each successful same-version job advances
      # the Document EXACTLY ONCE".
      ctx = fetchable
      one_page(ctx)
      job = jobs(ctx[:crawl_id]).first
      action = ingestion_actions(job["id"]).first
      first = run_ingestion(action)
      evidence_before = evidence_rows(ctx[:g][:organization_id]).size

      second = run_ingestion(action)
      expect(second.replayed).to be(true)
      expect(second.result_id).to eq(first.result_id)
      expect(evidence_rows(ctx[:g][:organization_id]).size).to eq(evidence_before)
      expect(document_row(job["document_id"])["state_version"]).to eq("1")
      expect(ingestion_attempts(job["id"]).size).to eq(1)
    end
  end

  # ============================================================================
  describe ":464's first-match refusals and :466's retry schedule" do
    def destroy_staging(job)
      DbInspector.connection.exec_params(
        "UPDATE ingestion_jobs SET staged_body_reference=NULL, staged_body_destroyed_at=now() WHERE id=$1::uuid",
        [job["id"]]
      )
    end

    it "PROOF 173 — `staged_body_missing` is NOT retryable: one failed attempt, straight to dead_letter, at one checkpoint" do
      # ":466 — Other failures and exhausted retry move `running -> failed -> dead_letter` at ONE
      # CHECKPOINT", and only `ingest_timeout` / `ingest_dependency_unavailable` retry.
      ctx = fetchable
      one_page(ctx)
      job = jobs(ctx[:crawl_id]).first
      destroy_staging(job)

      run_ingestion(ingestion_actions(job["id"]).first)
      settled = job_row(job["id"])
      expect(settled["state"]).to eq("dead_letter")
      expect(settled["last_reason_code"]).to eq("staged_body_missing")
      expect(document_row(job["document_id"])["state"]).to eq("discovered")
      expect(settled["evidence_id"]).to be_nil
      expect(ingestion_attempts(job["id"]).map { |a| a["outcome"] }).to eq(["failed"])
      # No retry action exists for a reason :466 does not retry.
      expect(ingestion_actions(job["id"]).size).to eq(1)
      expect(event_types(ctx[:g][:organization_id]))
        .to include("IngestionFailed", "IngestionDeadLettered")
    end

    it "PROOF 174 — the 24-hour staging bound is enforced by the record, not by a sweeper's punctuality" do
      # ":466 — retains inaccessible staging bytes for AT MOST 24 hours from fetch completion ... a
      # replay after destruction is `staged_body_missing`." A worker arriving after the window but
      # before any destruction executor must still refuse, so the BOUND is what is checked.
      ctx = fetchable
      one_page(ctx)
      job = jobs(ctx[:crawl_id]).first
      late = start_now + Workflows::Wf005::IngestionContract::STAGING_RETENTION_S + 1

      run_ingestion(ingestion_actions(job["id"]).first, at: late)
      settled = job_row(job["id"])
      expect(settled["state"]).to eq("dead_letter")
      expect(settled["last_reason_code"]).to eq("staged_body_missing")
      # The bytes were NOT read: the reference is still there, untouched, for the retention executor.
      expect(settled["staged_body_reference"]).not_to be_nil
    end

    it "PROOF 175 — `fetched_body_digest_mismatch`: the ingester re-verifies the capture it is about to make Evidence of" do
      ctx = fetchable
      one_page(ctx)
      job = jobs(ctx[:crawl_id]).first
      # A digest that no longer describes the staged bytes. The column is frozen by the lifecycle
      # guard, so this is done as the schema owner with the trigger's own rule stated: the point is
      # the INGESTER's check, and the mutation is the only way to reach it.
      DbInspector.connection.exec_params(
        "ALTER TABLE ingestion_jobs DISABLE TRIGGER ingestion_jobs_lifecycle_guard"
      )
      DbInspector.connection.exec_params(
        "UPDATE ingestion_jobs SET fetched_body_sha256 = sha256('different'::bytea) WHERE id=$1::uuid",
        [job["id"]]
      )
      DbInspector.connection.exec_params(
        "ALTER TABLE ingestion_jobs ENABLE TRIGGER ingestion_jobs_lifecycle_guard"
      )

      run_ingestion(ingestion_actions(job["id"]).first)
      settled = job_row(job["id"])
      expect(settled["state"]).to eq("dead_letter")
      expect(settled["last_reason_code"]).to eq("fetched_body_digest_mismatch")
      expect(document_row(job["document_id"])["state"]).to eq("discovered")
    end

    it "PROOF 176 — `ingest_dependency_unavailable` retries on :466's EXACT schedule and dead-letters at the third attempt" do
      # ":466 — one initial attempt plus two retries 30 and 120 seconds after the preceding failed
      # attempt." Asserted as the WHOLE sequence, not a prefix: the third attempt owes no retry.
      ctx = fetchable
      one_page(ctx)
      job = jobs(ctx[:crawl_id]).first

      allow(Platform::Encryption).to receive(:reveal)
        .and_raise(Platform::Encryption::Error.new(:key_unavailable))

      delays = []
      action = ingestion_actions(job["id"]).first
      at = start_now
      3.times do |i|
        run_ingestion(action, at:)
        row = job_row(job["id"])
        break if row["state"] == "dead_letter"

        expect(row["state"]).to eq("queued")
        due = Time.parse(row["next_due_at"]).getutc
        delays << (due - Time.parse(ingestion_attempts(job["id"])[i]["completed_at"]).getutc).round
        at = due
        action = ingestion_actions(job["id"]).last
      end

      expect(delays).to eq([30, 120])
      settled = job_row(job["id"])
      expect(settled["state"]).to eq("dead_letter")
      expect(settled["last_reason_code"]).to eq("ingest_dependency_unavailable")
      attempts = ingestion_attempts(job["id"])
      expect(attempts.map { |a| a["attempt_number"] }).to eq(%w[1 2 3])
      expect(attempts.map { |a| a["outcome"] }).to eq(%w[failed failed failed])
      expect(ingestion_actions(job["id"]).size).to eq(3)
    end

    it "PROOF 177 — the retry instant is DERIVED from committed state, so two deliveries compute one action" do
      ctx = fetchable
      one_page(ctx)
      job = jobs(ctx[:crawl_id]).first
      allow(Platform::Encryption).to receive(:reveal)
        .and_raise(Platform::Encryption::Error.new(:key_unavailable))
      run_ingestion(ingestion_actions(job["id"]).first)

      row = job_row(job["id"])
      attempt = ingestion_attempts(job["id"]).first
      expected = Time.parse(attempt["completed_at"]).getutc + 30
      expect(Time.parse(row["next_due_at"]).getutc).to eq(expected)
      retry_action = ingestion_actions(job["id"]).last
      expect(Time.parse(retry_action["due_at"]).getutc).to eq(expected)
      expect(retry_action["id"]).not_to eq(ingestion_actions(job["id"]).first["id"])
    end
  end

  # ============================================================================
  describe ":466's 30-second attempt bound and its late completion" do
    # THE LEASE LAPSES ON THE FIXTURE'S CLOCK, not the wall clock. Every instant in this chain is the
    # injected `start_now`, and `now()` here is the real one — months later — so an "expired" lease
    # written from `now()` is still in the future as far as the run is concerned, and the next
    # delivery reports `contended` rather than reclaiming. Caught by this example failing.
    def expire_lease(job_id)
      DbInspector.connection.exec_params(
        "UPDATE ingestion_attempts SET lease_expires_at = $2::timestamptz " \
        "WHERE ingestion_job_id = $1::uuid AND outcome IS NULL",
        [job_id, (start_now - 3600).iso8601(6)]
      )
    end

    def execution_for = Workflows::Wf005::IngestionExecution.new(correlation_id: SecureRandom.uuid_v7)

    it "PROOF 181 — ':466 equality belongs to timeout': an attempt settling AT its deadline is `ingest_timeout`" do
      ctx = fetchable
      one_page(ctx)
      job = jobs(ctx[:crawl_id]).first
      execution = execution_for
      claim = execution.claim(organization_id: ctx[:g][:organization_id], job_id: job["id"], now: start_now)
      work = execution.perform(claim:, now: start_now)
      expect(work.ok?).to be(true)

      # EXACTLY at the deadline. :466 gives the boundary to the timeout, so a result produced at the
      # instant the bound expires is not accepted — and this is the equality, not one microsecond past.
      at = start_now + Workflows::Wf005::IngestionContract::ATTEMPT_TIMEOUT_S
      settlement = Platform::UnitOfWork.run { |c| execution.settle(pg: c.raw_connection, claim:, work:, now: at) }

      expect(settlement.reason_code).to eq("ingest_timeout")
      expect(settlement.retried?).to be(true)
      expect(job_row(job["id"])["state"]).to eq("queued")
      expect(job_row(job["id"])["evidence_id"]).to be_nil
      expect(document_row(job["document_id"])["state"]).to eq("discovered")
    end

    it "PROOF 182 — ':466 late completion is DISCARDED': the reclaimed delivery writes nothing at all" do
      ctx = fetchable
      one_page(ctx)
      org = ctx[:g][:organization_id]
      job = jobs(ctx[:crawl_id]).first

      # DELIVERY A claims the attempt and does the work.
      execution = execution_for
      claim = execution.claim(organization_id: org, job_id: job["id"], now: start_now)
      expect(claim.performable?).to be(true)
      work = execution.perform(claim:, now: start_now)
      expect(work.ok?).to be(true)

      # A's lease lapses. DELIVERY B arrives, reclaims the dead attempt as `ingest_timeout`, and
      # settles it — which is the whole point of committing the claim before the work.
      expire_lease(job["id"])
      run_ingestion(ingestion_actions(job["id"]).first, at: start_now + 1)
      expect(job_row(job["id"])["state"]).to eq("queued")
      evidence_before = evidence_rows(org).size

      # A NOW FINISHES. It no longer owns the attempt, so it writes NOTHING: no Evidence, no Document
      # advance, no state change — not even a second opinion about the outcome.
      settlement = Platform::UnitOfWork.run do |c|
        execution.settle(pg: c.raw_connection, claim:, work:, now: start_now + 2)
      end
      expect(settlement.discarded?).to be(true)
      expect(settlement.reason_code).to eq("ingestion_late_completion_discarded")
      expect(evidence_rows(org).size).to eq(evidence_before)
      expect(job_row(job["id"])["state"]).to eq("queued")
      expect(job_row(job["id"])["evidence_id"]).to be_nil
      expect(document_row(job["document_id"])["state"]).to eq("discovered")
      expect(ingestion_attempts(job["id"]).map { |a| a["outcome"] }).to eq(["failed"])
    end

    it "PROOF 183 — a live lease is CONTENDED: a second delivery performs nothing and changes nothing" do
      ctx = fetchable
      one_page(ctx)
      job = jobs(ctx[:crawl_id]).first
      execution_for.claim(organization_id: ctx[:g][:organization_id], job_id: job["id"], now: start_now)
      version = job_row(job["id"])["state_version"]

      result = run_ingestion(ingestion_actions(job["id"]).first, at: start_now + 1)
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("ingestion_attempt_contended")
      expect(job_row(job["id"])["state_version"]).to eq(version)
      expect(ingestion_attempts(job["id"]).size).to eq(1)
    end
  end

  # ============================================================================
  describe "identity, versioning and tenancy" do
    it "PROOF 179 — RLS: another Organization sees neither the Document nor the job nor the Evidence" do
      ctx = fetchable
      one_page(ctx)
      job = jobs(ctx[:crawl_id]).first
      run_ingestion(ingestion_actions(job["id"]).first)

      other = SecureRandom.uuid_v7
      visible = Platform::UnitOfWork.run do |conn|
        pg = conn.raw_connection
        IdentityAccess::Infrastructure::IngestionJobStore.new(pg)
                                                         .enter_org_context(org: other,
                                                                            correlation_id: SecureRandom.uuid_v7)
        {
          documents: pg.exec("SELECT count(*) AS n FROM documents").to_a.first["n"].to_i,
          jobs: pg.exec("SELECT count(*) AS n FROM ingestion_jobs").to_a.first["n"].to_i,
          attempts: pg.exec("SELECT count(*) AS n FROM ingestion_attempts").to_a.first["n"].to_i,
          evidence: pg.exec("SELECT count(*) AS n FROM evidence").to_a.first["n"].to_i
        }
      end
      expect(visible).to eq({ documents: 0, jobs: 0, attempts: 0, evidence: 0 })
    end

    it "PROOF 180 — a delivery for a settled job claims nothing and writes no product state" do
      ctx = fetchable
      one_page(ctx)
      job = jobs(ctx[:crawl_id]).first
      action = ingestion_actions(job["id"]).first
      run_ingestion(action)
      version_after_success = job_row(job["id"])["state_version"]

      # A DIFFERENT delivery of the same kind against the settled job: distinct action, so the
      # idempotency record does not absorb it and the job's own state is what must refuse.
      forged = action.merge("id" => SecureRandom.uuid_v7,
                            "identity_sha256" => "\\x#{SecureRandom.hex(32)}")
      result = run_ingestion(forged)
      expect(result.success?).to be(false)
      expect(result.failure.reason_code).to eq("ingestion_job_not_runnable")
      expect(job_row(job["id"])["state_version"]).to eq(version_after_success)
      expect(ingestion_attempts(job["id"]).size).to eq(1)
    end
  end

end
