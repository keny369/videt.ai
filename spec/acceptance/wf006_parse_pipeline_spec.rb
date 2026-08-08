# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf006_parse_chain"

# WF-006 THE PARSE PIPELINE, AND THE TWO DEFECTS A GREEN SUITE MISSED.
#
# Governing text: WORKFLOW_SPECIFICATIONS.md :470-476 (the manifest, the parse,
# `parsed-observation-v1`), :503-511 (the readiness derivation), contracts/S-08.json.
#
# Both defects pinned here were found by RUNNING the product against a real site, not by the
# suite, and both are seam defects — the kind a spec that exercises one side of a boundary
# cannot see. Each example below drives the REAL chain: a running Crawl, real fetches through
# the frozen outbound facade, real ingestion, the real terminal checkpoint, the real Evaluation
# input gate and the real ParsingJob handler, each behind its own registered ScheduledAction.
RSpec.describe "WF-006 parse pipeline", type: :acceptance,
               acceptance_ids: ["AC-CAP-012", "AC-WF-006"], test_types: %w[TYP-E2E TYP-DATA] do
  include Wf006ParseChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  ROOT_PAGE = <<~HTML
    <html><head><title>Acme</title></head>
    <body><a href="/about">about</a></body></html>
  HTML

  def store_in(org)
    Platform::UnitOfWork.run do |conn|
      store = IdentityAccess::Infrastructure::EvaluationInputStore.new(conn.raw_connection)
      store.enter_org_context(org:, correlation_id: SecureRandom.uuid_v7)
      yield store
    end
  end

  # The Artifact's normalized payload, revealed through the same AAD the producer sealed it
  # with. Reading the real bytes is the point: the payload is what a Check will consume.
  def artifact_payload(artifact, org)
    aad = Platform::Encryption::Aad.for(application: "wf006", record_type: "parsed_artifact",
                                        purpose: "normalized_payload", record_id: artifact["id"], tenant: org)
    JSON.parse(Platform::Encryption.reveal(artifact["normalized_payload_reference"], aad:))
  end

  # ==========================================================================================
  describe "DEFECT 1 — the Crawl and the parser do not speak the same outcome vocabulary" do
    # `crawl_terminal_outcomes` records `document_created`; `parsed-observation-v1` (:476)
    # admits exactly `document_valid`, `content_absent`, `content_fetch_failed` and
    # `policy_excluded`. The Source-root payload carries that map AND is validated against it,
    # so an untranslated `document_created` is `terminal_outcome_unknown`, the payload is
    # invalid, and the first real parse dead-lettered as `normalized_output_invalid`.
    #
    # Reverting the translation to a pass-through reproduces it here; dropping the entry
    # entirely fails the same assertion from the other side.
    it "REGRESSION — a root the Crawl recorded as `document_created` parses, and its sealed map reads `document_valid`" do
      ctx = crawlable
      run_to_parsed(ctx, outbound_pages("/" => { body: ROOT_PAGE }, "/about" => { body: "<html><title>a</title></html>" }))
      org = ctx[:g][:organization_id]

      # The Crawl really did record the crawl-side word, so the translation is exercised
      # rather than assumed.
      expect(terminal_outcomes(ctx[:crawl_id]).map { |r| r["outcome"] }).to include("document_created")

      root = parsing_jobs(ctx[:crawl_id]).find { |j| j["source_root"] == "t" }
      expect(root).not_to be_nil
      # The consequence: the parse SUCCEEDED. Before the fix this row was `dead_letter` with
      # `normalized_output_invalid`.
      expect(root["status"]).to eq("succeeded")
      expect(root["last_reason_code"]).to be_nil

      artifact = parsed_artifacts(ctx[:crawl_id]).find { |a| a["source_root"] == "t" }
      payload = artifact_payload(artifact, org)
      root_url = source_row(ctx[:source_id])["canonical_root_uri"]

      # The map is in the parsed-observation vocabulary, and the root URL is in it. A
      # pass-through would read `document_created` here; a dropped entry would read nil.
      expect(payload["crawl_terminal_outcomes"][root_url]).to eq("document_valid")
      expect(payload["crawl_terminal_outcomes"].values.uniq)
        .to all(be_in(Workflows::Wf006::ParsedObservation::TERMINAL_OUTCOMES))
    end

    it "REGRESSION — the translation is total: every value the store emits is admissible to `parsed-observation-v1`" do
      ctx = crawlable
      # A run with an accepted page AND a terminal 404, so the map carries two distinct crawl
      # words and a single-outcome fixture cannot pass by accident.
      drain_fetches(ctx, outbound_pages("/" => { body: ROOT_PAGE },
                                        "/about" => { status: 404, body: "", type: "text/plain" }))
      drain_ingestion(ctx)
      complete_crawl(ctx)

      recorded = terminal_outcomes(ctx[:crawl_id]).map { |r| r["outcome"] }.uniq
      expect(recorded).to include("document_created")

      map = store_in(ctx[:g][:organization_id]) { |s| s.crawl_terminal_outcome_map(ctx[:crawl_id]) }
      expect(map).not_to be_empty
      expect(map.values.uniq).to all(be_in(Workflows::Wf006::ParsedObservation::TERMINAL_OUTCOMES))
      expect(map.values).not_to include("document_created")
    end

    # :476's translation table is deliberately PARTIAL. `limit_discarded` and
    # `robots_unavailable_fail_closed` name URLs the run never covered, and "we stopped before
    # this one" is not an observation, so they are absent from the map rather than translated
    # to a near-miss. A total table would put an unknown word in the payload.
    it "the crawl outcomes with no parsed-observation equivalent are absent, not approximated" do
      table = IdentityAccess::Infrastructure::EvaluationInputStore::CRAWL_TO_OBSERVED_OUTCOME
      expect(table["document_created"]).to eq("document_valid")
      expect(table.keys).not_to include("limit_discarded", "robots_unavailable_fail_closed")
      expect(table.values.uniq).to all(be_in(Workflows::Wf006::ParsedObservation::TERMINAL_OUTCOMES))
    end
  end

  # ==========================================================================================
  describe "DEFECT 2 — an empty manifest scheduled nothing and latched the Evaluation for ever" do
    # A Crawl that ingested nothing opens zero ParsingJobs. Opening zero jobs schedules zero
    # `parsing_attempt_due` actions, so nothing ever came back to seal the snapshot: the
    # Evaluation stayed `pending`, and OD-018 refuses another root Crawl while one is pending.
    # That is precisely the latch this gate exists to release, so the empty manifest must
    # DERIVE on the visit that observes it.
    it "REGRESSION — a Crawl that ingested nothing resolves its Evaluation instead of waiting" do
      ctx = crawlable
      # Robots allows everything and the root itself 404s, so the run is terminal with no
      # Document and no succeeded IngestionJob: an empty manifest, reached honestly.
      drain_fetches(ctx, outbound_pages("/" => { status: 404, body: "", type: "text/plain" }))
      drain_ingestion(ctx)
      complete_crawl(ctx)

      evaluation = evaluation_for(ctx[:crawl_id])
      expect(evaluation["state"]).to eq("pending")

      result = advance_evaluation(ctx)
      expect(result).to be_success

      # ONE visit resolves it. No ParsingJob was opened, and none could have been.
      expect(parsing_jobs(ctx[:crawl_id])).to be_empty
      expect(actions_of("parsing_attempt_due", ctx[:crawl_id])).to be_empty

      resolved = evaluation_row(evaluation["id"])
      expect(resolved["state"]).to eq("failed")
      expect(resolved["reason"]).to eq("evaluation_inputs_unavailable")

      # A blocked derivation still seals its snapshot, so the decision is re-derivable from a
      # row rather than only from an event (:439).
      snapshot = input_snapshot(evaluation["id"])
      expect(snapshot).not_to be_nil
      expect(snapshot["readiness_status"]).to eq("blocked")
      expect(JSON.parse(snapshot["manifest"])).to eq([])
    end

    it "REGRESSION — and the OD-018 latch is released, so the Project can be crawled again" do
      ctx = crawlable
      drain_fetches(ctx, outbound_pages("/" => { status: 404, body: "", type: "text/plain" }))
      drain_ingestion(ctx)
      complete_crawl(ctx)
      advance_evaluation(ctx)

      # The guard reads pending-or-running Evaluations for the Project. A terminal one holds
      # nothing, which is the whole point of resolving the empty manifest.
      held = DbInspector.all(<<~SQL, [ctx[:g][:project_id]])
        SELECT * FROM evaluations WHERE project_id = $1::uuid AND state IN ('pending','running')
      SQL
      expect(held).to be_empty
    end
  end

  # ==========================================================================================
  describe "the pipeline the two defects were blocking" do
    it "a crawled Document becomes one immutable Parsed Artifact and a ready input snapshot" do
      ctx = crawlable
      run_to_parsed(ctx, outbound_pages("/" => { body: ROOT_PAGE },
                                        "/about" => { body: "<html><title>About</title></html>" }))

      jobs = parsing_jobs(ctx[:crawl_id])
      expect(jobs).not_to be_empty
      expect(jobs.map { |j| j["status"] }.uniq).to eq(["succeeded"])
      expect(parsed_artifacts(ctx[:crawl_id]).length).to eq(jobs.length)

      snapshot = input_snapshot(evaluation_for(ctx[:crawl_id])["id"])
      expect(snapshot["readiness_status"]).to eq("ready_full")
      expect(snapshot["failed_count"].to_i).to eq(0)
      expect(snapshot["successful_count"].to_i).to eq(jobs.length)
    end
  end
end
