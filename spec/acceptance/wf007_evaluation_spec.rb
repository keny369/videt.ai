# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf006_parse_chain"

# WF-007 END TO END — the ratified seven-check catalogue over a real crawl.
#
# Governing text: WORKFLOW_SPECIFICATIONS.md § WF-007; SCORE_EVIDENCE_MODEL.md § Check Result
# Contract, § Frozen Check Applicability Snapshot, § Common Pure Check Executor,
# § Check-To-Issue Rules, § Fingerprint `issue-fingerprint-v1`; PRULE-010 through PRULE-013,
# PRULE-023; OD-010 and OD-017, both RATIFIED.
#
# EVERY EXAMPLE DRIVES THE PRODUCTION CHAIN. A Crawl is bootstrapped, started, fetched
# through the real `RecordFetchAttempt`, ingested, terminalized, parsed, its Evidence derived
# and sealed, and then evaluated through the real registered WF-007 handlers behind real
# ScheduledActions. Only the frozen F-01 outbound facade is stubbed.
#
# THE BASELINE THIS ASSERTS IS THE APPROVED ONE. `external-measurement-v1` bundles no query,
# intent, listing, provider or adapter set, so four of the seven checks deterministically
# select no Evidence and persist handled `input_evidence_missing` errors, their pillars are
# insufficient, and the overall score is UNAVAILABLE. That is settled behaviour under the
# ratified OD-010, and it is asserted here as the expected outcome rather than tolerated as a
# gap — including the negative: no query set is invented to make a number appear.
RSpec.describe "WF-007 evaluation", type: :acceptance,
               acceptance_ids: %w[AC-WF-007 AC-CAP-009 AC-CAP-010 AC-CAP-011 AC-PRULE-010
                                  AC-PRULE-011 AC-PRULE-012 AC-SM-006],
               test_types: %w[TYP-E2E TYP-DATA TYP-SEC] do
  include Wf006ParseChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  # METHODS, NOT CONSTANTS. A constant assigned inside a `RSpec.describe` block is lexically
  # scoped to the FILE, so it lands on `Object` and is visible to every other spec in the
  # suite — `ROOT` in particular is already a global in the architecture specs, and defining
  # it here silently broke them in a full run while this file passed in isolation.
  def root_page
    <<~HTML
      <html><head><title>Acme Supplies</title></head>
      <body><a href="/about">About</a><a href="/gone">Gone</a></body></html>
    HTML
  end

  def about_page = "<html><head><title>About Acme</title></head><body>hello</body></html>"

  # A run seeded from the sitemap, so every linked URL is actually observed. Since S-07-007
  # in-crawl link discovery, the run would reach `/about` and `/gone` from the root page anyway;
  # the seeding is retained because it makes the observed target set independent of traversal
  # order, which is what these examples are about rather than what discovery is about.
  def evaluated_run(pages: nil, sitemap: %w[https://shop.acme.example/about https://shop.acme.example/gone])
    ctx = crawlable(sitemap:)
    run_to_evaluated(ctx, outbound_pages(pages || default_pages))
    ctx
  end

  def default_pages
    { "/" => { body: root_page }, "/about" => { body: about_page },
      "/gone" => { status: 404, body: "", type: "text/plain" } }
  end

  # A SECOND crawl of the SAME Project — no new Organization, no new Source. It only works
  # because the first Evaluation completed: `QueueCrawl` refuses while one is pending or
  # running, so every example that calls this is also asserting the OD-018 release.
  def rerun(ctx, pages: nil)
    @driven_stage_actions = []
    @driven_check_actions = []
    second = recrawl(ctx)
    run_to_evaluated(second, outbound_pages(pages || default_pages))
    second
  end

  def results_by_definition(evaluation_id)
    check_results(evaluation_id).group_by { |r| r["check_definition_id"] }
  end

  # =====================================================================================
  describe "the frozen applicability seal" do
    it "expects one entry per ratified Definition and subject, ordered by Catalog position" do
      ctx = evaluated_run
      eid = evaluation_for(ctx[:crawl_id])["id"]
      entries = applicability_entries(eid)

      # Cardinality is exact: one CHK-TI-001 and one CHK-TR-001 per active Source; one
      # CHK-CQ-001 per successfully parsed Document; exactly one Project entry each for the
      # four measurement Definitions.
      by_definition = entries.group_by { |e| e["check_definition_id"] }
      expect(by_definition["CHK-TI-001"].length).to eq(1)
      expect(by_definition["CHK-TR-001"].length).to eq(1)
      expect(by_definition["CHK-CQ-001"].length).to eq(2)
      %w[CHK-SP-001 CHK-AIP-001 CHK-AS-001 CHK-LP-001].each do |id|
        expect(by_definition[id].length).to eq(1), "#{id} must have exactly one Project entry"
      end

      # Ordered by Catalog position first, so the seal reads in the catalogue's own order.
      expect(entries.map { |e| e["check_definition_id"] }.uniq)
        .to eq(Workflows::Wf007::CheckCatalog::DEFINITION_IDS)
      expect(entries.map { |e| e["ordering"].to_i }).to eq((1..entries.length).to_a)
    end

    it "binds the subject exactly: Project by ID, Source by ID, Document by canonical URL" do
      ctx = evaluated_run
      eid = evaluation_for(ctx[:crawl_id])["id"]
      entries = applicability_entries(eid).index_by { |e| e["check_definition_id"] }

      # "For a Project or Source subject, the canonical key is the OPAQUE Project or Source
      # ID unchanged" — not the root URL, and not a normalization of it.
      expect(entries["CHK-TI-001"]["canonical_subject_key"]).to eq(ctx[:source_id])
      expect(entries["CHK-TI-001"]["canonical_subject_type"]).to eq("source")
      expect(entries["CHK-SP-001"]["canonical_subject_key"]).to eq(ctx[:g][:project_id])
      expect(entries["CHK-SP-001"]["canonical_subject_type"]).to eq("project")
      expect(entries["CHK-CQ-001"]["canonical_subject_type"]).to eq("url")
      expect(entries["CHK-CQ-001"]["canonical_subject_key"]).to start_with("https://shop.acme.example/")
    end

    # "Actual Source IDs are bound ONLY in this Snapshot and its absence-selector instances,
    # never in a global Definition."
    it "binds Source IDs in the Snapshot and never in a Definition" do
      ctx = evaluated_run
      serialized = Workflows::Wf007::CheckCatalog::DEFINITIONS.map(&:to_s).join
      expect(serialized).not_to include(ctx[:source_id])
      expect(serialized).not_to include(ctx[:g][:project_id])
      expect(serialized).not_to include(ctx[:g][:organization_id])
    end

    # A missing selected input permitted by an otherwise valid selector REMAINS an entry.
    # The four measurement Definitions select nothing at the baseline, and their entries are
    # asserted PRESENT — dropping them would turn "we could not measure this" into "there was
    # nothing to measure".
    it "keeps an entry whose selector legitimately selected nothing" do
      ctx = evaluated_run
      eid = evaluation_for(ctx[:crawl_id])["id"]
      measurement = applicability_entries(eid).select do |e|
        %w[CHK-SP-001 CHK-AIP-001 CHK-AS-001 CHK-LP-001].include?(e["check_definition_id"])
      end
      expect(measurement.length).to eq(4)
      expect(measurement.map { |e| JSON.parse(e["selected_evidence"]) }.uniq).to eq([[]])

      # Three of the four stay applicable and select nothing. CHK-LP-001 is the exception,
      # and for a different reason: the genesis Project this chain creates carries a validly
      # false local-presence decision, so the entry is INAPPLICABLE and selects nothing
      # because there is nothing to select — not because the input is missing. The two are
      # distinguished here so a regression cannot silently convert one into the other.
      by_id = measurement.to_h { |e| [e["check_definition_id"], e] }
      expect(by_id.values_at("CHK-SP-001", "CHK-AIP-001", "CHK-AS-001").map { |e| e["applicable"] })
        .to eq(%w[t t t])
      expect(by_id["CHK-LP-001"]["applicable"]).to eq("f")
      expect(by_id["CHK-LP-001"]["inapplicable_reason"]).to eq(GenesisProjectProfile::DEFAULT_REASON)
    end
  end

  # =====================================================================================
  describe "Check Result identity" do
    # "The retained preimage is exactly Evaluation ID, Evaluation Input Snapshot ID, Check
    # Applicability Snapshot ID, Check Catalog version, Check Definition ID and version,
    # canonical subject type and key, and pillar ID IN THAT ORDER."
    it "retains the full preimage in the contract's order and hashes it into the key" do
      ctx = evaluated_run
      eid = evaluation_for(ctx[:crawl_id])["id"]
      result = check_results(eid).first
      preimage = [result["check_result_key_preimage"].sub(/\A\\x/, "")].pack("H*")
      decoded = JSON.parse(preimage)

      expect(decoded.map(&:first)).to eq(%w[evaluation_id evaluation_input_snapshot_id
                                            check_applicability_snapshot_id check_catalog_version
                                            check_definition_id check_definition_version
                                            canonical_subject_type canonical_subject_key pillar_id])
      expect(decoded.first.last).to eq(eid)
      expect(result["check_result_key_sha256"].sub(/\A\\x/, ""))
        .to eq(Digest::SHA256.hexdigest(preimage))
    end

    # PRULE-010: "the COMPLETE retained preimage, not the hash, is uniqueness authority
    # within the Evaluation, so the unique index MUST NOT be built on the hash alone." A
    # unique index on the hash would refuse the very insert that makes a collision
    # detectable.
    it "makes the retained preimage the unique index, and the hash a non-unique lookup" do
      indexes = DbInspector.all(<<~SQL, [])
        SELECT indexname, indexdef FROM pg_indexes
        WHERE tablename = 'check_result_keys'
      SQL
      preimage_index = indexes.find { |i| i["indexdef"].include?("key_preimage") }
      hash_index = indexes.find { |i| i["indexdef"].include?("check_result_key_sha256") }
      expect(preimage_index["indexdef"]).to include("UNIQUE")
      expect(hash_index["indexdef"]).not_to include("UNIQUE")
    end

    # Materialization allocates the Check Result identity BEFORE execution, so a crashed
    # attempt leaves a materialized key rather than a phantom Result.
    it "preallocates each Result's identity on its Slot, and the Result adopts it" do
      ctx = evaluated_run
      eid = evaluation_for(ctx[:crawl_id])["id"]
      slots = DbInspector.all("SELECT * FROM check_result_slots WHERE evaluation_id=$1::uuid ORDER BY ordering",
                              [eid])
      expect(slots.map { |s| s["state"] }.uniq).to eq(["terminal"])
      slots.each do |slot|
        expect(slot["terminal_result_id"]).to eq(slot["check_result_id"])
        result = DbInspector.one("SELECT id FROM check_results WHERE slot_id=$1::uuid", [slot["id"]])
        expect(result["id"]).to eq(slot["check_result_id"])
      end
    end
  end

  # =====================================================================================
  describe "execution over the ratified seven" do
    it "produces exactly one terminal Result per expected entry, and no other" do
      ctx = evaluated_run
      eid = evaluation_for(ctx[:crawl_id])["id"]
      expect(check_results(eid).length).to eq(applicability_entries(eid).length)
      expect(check_results(eid).map { |r| r["applicability_entry_id"] }.uniq.length)
        .to eq(applicability_entries(eid).length)
    end

    it "reaches decision-grade pass and fail on the three platform-derived Definitions" do
      ctx = evaluated_run
      by_definition = results_by_definition(evaluation_for(ctx[:crawl_id])["id"])

      # One linked target returned a terminal 404 under full coverage: a real broken link,
      # one absent target, impact `low`, effort `low`.
      ti = by_definition["CHK-TI-001"].sole
      expect(ti["execution_status"]).to eq("failed")
      expect(ti["outcome_code"]).to eq("broken_internal_links")
      expect(ti["impact_band"]).to eq("low")
      expect(ti["effort_band"]).to eq("low")
      expect(JSON.parse(ti["normalized_observation"])["absent_count"]).to eq(1)

      # Both parsed Documents carry exactly one nonblank title.
      expect(by_definition["CHK-CQ-001"].map { |r| r["outcome_code"] }.uniq).to eq(["meta_title_present"])
      expect(by_definition["CHK-CQ-001"].map { |r| r["execution_status"] }.uniq).to eq(["passed"])

      # The site publishes no Organization structured data at all: zero nodes is a VALID
      # observation and a real finding, at `medium`.
      tr = by_definition["CHK-TR-001"].sole
      expect(tr["execution_status"]).to eq("failed")
      expect(tr["outcome_code"]).to eq("organization_schema_missing")
      expect(tr["impact_band"]).to eq("medium")
    end

    # THE APPROVED BASELINE, asserted as the expected outcome. CHK-LP-001 is NOT in this
    # list: it is the one Definition for which `not_applicable` is valid, and the genesis
    # Project validly declares local presence inapplicable, so it never reaches an error.
    # Its own outcome is asserted immediately below.
    it "persists a handled one-attempt input_evidence_missing on each measurement Definition" do
      ctx = evaluated_run
      by_definition = results_by_definition(evaluation_for(ctx[:crawl_id])["id"])

      %w[CHK-SP-001 CHK-AIP-001 CHK-AS-001].each do |id|
        result = by_definition[id].sole
        expect(result["execution_status"]).to eq("error"), "#{id} should be a handled error"
        expect(result["error_reason_code"]).to eq("input_evidence_missing")
        expect(result["execution_attempt_count"].to_i).to eq(1)
        expect(result["impact_band"]).to be_nil
        expect(result["confidence_value"]).to be_nil
        expect(result["confidence_status"]).to eq("missing")
        expect(result["confidence_band"]).to eq("low")
        expect(result["subject_set_complete"]).to eq("f")
      end
    end

    # SCORE_EVIDENCE_MODEL.md :207 `not_applicable` "is valid only for `CHK-LP-001`"; :273
    # it is inapplicable "only when the frozen Project profile validly records
    # `local_presence_applicable=false` and its nonblank reason".
    #
    # The Project this chain evaluates is created by WF-001 genesis, and it now carries that
    # decision. Before it did, the row was the all-NULL profile shape — legal, but not a
    # valid false — and this Result was `error / local_profiles_absent /
    # input_evidence_missing`, which blocked the pillar by omission rather than by a
    # decision anyone made.
    it "reaches not_applicable on CHK-LP-001 from the genesis Project's own declared-false profile" do
      ctx = evaluated_run
      result = results_by_definition(evaluation_for(ctx[:crawl_id])["id"])["CHK-LP-001"].sole

      expect(result["execution_status"]).to eq("not_applicable")
      expect(result["outcome_code"]).to eq("local_presence_not_applicable")
      expect(result["error_reason_code"]).to be_nil

      profile = DbInspector.all(<<~SQL, [ctx[:g][:project_id]]).sole
        SELECT project_profile_schema_version, local_presence_applicable, local_presence_reason,
               local_business_profile, local_business_profile_content_sha256,
               profile_attesting_account_id, profile_committed_at
        FROM projects WHERE id = $1::uuid
      SQL
      expect(profile["project_profile_schema_version"]).to eq("project-profile-v1")
      expect(profile["local_presence_applicable"]).to eq("f")
      expect(profile["local_presence_reason"]).to eq(GenesisProjectProfile::DEFAULT_REASON)
      # ":657 when local presence is false ... `local_business_profile` is null" — and the
      # `projects_local_profile_shape` CHECK pairs the attestation with the decision.
      expect(profile["local_business_profile"]).to be_nil
      expect(profile["local_business_profile_content_sha256"]).to be_nil
      expect(profile["profile_attesting_account_id"]).not_to be_nil
      expect(profile["profile_committed_at"]).not_to be_nil
    end

    # "no implementation invents a query, intent, listing directory, prompt, provider,
    # threshold or adapter to avoid that outcome."
    it "invents no Measurement Evidence to make a score appear" do
      ctx = evaluated_run
      eid = evaluation_for(ctx[:crawl_id])["id"]
      measurements = DbInspector.all(<<~SQL, [eid])
        SELECT * FROM evidence WHERE evaluation_id = $1::uuid AND evidence_type = 'external_measurement'
      SQL
      expect(measurements).to be_empty
    end

    it "gives every decided Result confidence 1.0000 / valid / high" do
      ctx = evaluated_run
      decided = check_results(evaluation_for(ctx[:crawl_id])["id"])
                .reject { |r| r["execution_status"] == "error" }
      expect(decided).not_to be_empty
      expect(decided.map { |r| r["confidence_value"].to_f }.uniq).to eq([1.0])
      expect(decided.map { |r| r["confidence_status"] }.uniq).to eq(["valid"])
      expect(decided.map { |r| r["confidence_band"] }.uniq).to eq(["high"])
    end

    it "records the exact rule version, and no model, for every Result" do
      ctx = evaluated_run
      check_results(evaluation_for(ctx[:crawl_id])["id"]).each do |result|
        expect(result["rule_or_model_version"]).to eq("#{result['check_definition_id']}-rule-v1")
      end
    end

    # A Check performs NO network request or provider call. Asserted by observing that the
    # guarded outbound surface is never reached during the whole WF-007 half of the run.
    it "makes no outbound call during Check execution" do
      ctx = crawlable(sitemap: %w[https://shop.acme.example/about https://shop.acme.example/gone])
      run_to_parsed(ctx, outbound_pages(default_pages))

      allow(Platform::Outbound).to receive(:fetch).and_raise("a Check made a provider call")
      advance_wf007(ctx)
      drain_check_attempts(ctx)
      advance_wf007(ctx)

      expect(evaluation_row(evaluation_for(ctx[:crawl_id])["id"])["state"]).to eq("completed")
    end
  end

  # =====================================================================================
  describe "determinism" do
    # "Two executions with the same canonical input tuple MUST produce the same semantic
    # output tuple", while generated identifiers and timestamps are EXCLUDED from semantic
    # equality. Two independent runs of the same site are compared: their Evaluation and
    # Snapshot IDs differ, so their input hashes legitimately differ — but the SEMANTIC
    # output of each Definition must be identical.
    it "produces the same semantic output for the same observation across two runs" do
      first = evaluated_run
      second = rerun(first)

      def semantic(results)
        results.to_h do |r|
          [[r["check_definition_id"], r["canonical_subject_type"]],
           r.values_at("execution_status", "outcome_code", "error_reason_code", "impact_band",
                       "confidence_value", "confidence_status", "confidence_band", "pillar_id",
                       "subject_set_complete")]
        end
      end

      a = semantic(check_results(evaluation_for(first[:crawl_id])["id"]))
      b = semantic(check_results(evaluation_for(second[:crawl_id])["id"]))
      expect(b).to eq(a)
    end

    it "gives a Result the same output hash for the same semantic decision across runs" do
      first = evaluated_run
      second = rerun(first)
      # The four Project-subject Results depend on nothing that differs between the two runs
      # of the SAME Project except the Evaluation identity, which is excluded from semantic
      # equality — so their deterministic OUTPUT hashes must be byte-equal across runs.
      def project_output_hashes(evaluation_id)
        DbInspector.all(<<~SQL, [evaluation_id]).to_h { |r| [r["check_definition_id"], r["h"]] }
          SELECT check_definition_id, encode(deterministic_output_sha256,'hex') AS h
          FROM check_results
          WHERE evaluation_id = $1::uuid AND canonical_subject_type = 'project'
        SQL
      end
      a = project_output_hashes(evaluation_for(first[:crawl_id])["id"])
      b = project_output_hashes(evaluation_for(second[:crawl_id])["id"])
      expect(a.keys.sort).to eq(%w[CHK-AIP-001 CHK-AS-001 CHK-LP-001 CHK-SP-001])
      expect(b).to eq(a)
    end

    # FX-CHECK-COM-002: a changed Evidence digest changes the deterministic input hash. Two
    # runs whose Documents differ must not produce the same input hash for CHK-CQ-001.
    it "changes the input hash when the Evidence digest changes" do
      base = evaluated_run
      changed = rerun(base, pages: default_pages.merge(
        "/about" => { body: "<html><head><title>A Completely Different Title</title></head></html>" }
      ))

      def cq_hashes(evaluation_id)
        DbInspector.all(<<~SQL, [evaluation_id]).map { |r| r["h"] }
          SELECT encode(deterministic_input_sha256,'hex') AS h FROM check_results
          WHERE evaluation_id = $1::uuid AND check_definition_id = 'CHK-CQ-001'
        SQL
      end
      expect(cq_hashes(evaluation_for(base[:crawl_id])["id"]) &
             cq_hashes(evaluation_for(changed[:crawl_id])["id"])).to be_empty
    end
  end

  # =====================================================================================
  describe "Issue derivation" do
    it "creates one published open Issue per failed Result, and none for pass, error or n/a" do
      ctx = evaluated_run
      eid = evaluation_for(ctx[:crawl_id])["id"]
      failed = check_results(eid).select { |r| r["execution_status"] == "failed" }
      issues = issues_of(eid)

      expect(issues.length).to eq(failed.length)
      expect(issues.map { |i| i["issue_type"] }.sort)
                                                 .to eq(%w[broken_internal_links organization_schema_missing])
      expect(issues.map { |i| i["state"] }.uniq).to eq(["open"])
      expect(issues.map { |i| i["publication_status"] }.uniq).to eq(["published"])
      expect(issues.map { |i| i["adjudication_status"] }.uniq).to eq(["not_required"])
    end

    # PRULE-012: the metadata is COPIED, never re-derived. The Issue's impact and confidence
    # must equal its origin Check Result's, field for field.
    it "copies impact and confidence from the origin Result rather than recomputing them" do
      ctx = evaluated_run
      eid = evaluation_for(ctx[:crawl_id])["id"]
      results = check_results(eid).index_by { |r| r["id"] }

      issues_of(eid).each do |issue|
        origin = results.fetch(issue["check_result_id"])
        expect(issue["impact_band"]).to eq(origin["impact_band"])
        expect(issue["confidence_value"]).to eq(origin["confidence_value"])
        expect(issue["confidence_band"]).to eq(origin["confidence_band"])
        expect(issue["confidence_status"]).to eq(origin["confidence_status"])
        expect(issue["effort_band"]).to eq(origin["effort_band"])
        expect(issue["recommendation_template_id"]).to eq(origin["recommendation_template_id"])
      end
    end

    # PRULE-012: "No actor — including one holding `issue.adjudicate` — may alter a persisted
    # `impact_band` or `confidence_value`." Enforced where a permission cannot reach it.
    it "refuses to alter a persisted impact band at the database" do
      ctx = evaluated_run
      issue = issues_of(evaluation_for(ctx[:crawl_id])["id"]).first
      expect { DbInspector.connection.exec_params("UPDATE issues SET impact_band='critical' WHERE id=$1::uuid", [issue["id"]]) }
        .to raise_error(PG::RaiseException, /issue_impact_metadata_immutable/)
    end

    it "refuses to repoint an Issue at another Check Result" do
      ctx = evaluated_run
      issue = issues_of(evaluation_for(ctx[:crawl_id])["id"]).first
      expect do
        DbInspector.connection.exec_params("UPDATE issues SET check_result_id = gen_random_uuid() WHERE id=$1::uuid",
                         [issue["id"]])
      end.to raise_error(PG::RaiseException, /issue_identity_immutable/)
    end

    # PRULE-011: every Issue references at least one effectively valid same-Organization
    # Evidence record.
    it "links every Issue to the valid Evidence its Result was decided from" do
      ctx = evaluated_run
      eid = evaluation_for(ctx[:crawl_id])["id"]
      issues_of(eid).each do |issue|
        links = DbInspector.all(<<~SQL, [issue["id"]])
          SELECT ie.*, e.validation_status, e.organization_id
          FROM issue_evidences ie JOIN evidence e ON e.id = ie.evidence_id
          WHERE ie.issue_id = $1::uuid
        SQL
        expect(links).not_to be_empty
        expect(links.map { |l| l["validation_status"] }.uniq).to eq(["valid"])
        expect(links.map { |l| l["organization_id"] }.uniq).to eq([ctx[:g][:organization_id]])
      end
    end

    # PRULE-023: uniqueness authority is the FULL canonical preimage. A unique index on the
    # hash alone MUST NOT exist — it would merge exactly the records the model requires to
    # stay distinct.
    it "makes the fingerprint preimage unique and the hash a non-unique lookup" do
      indexes = DbInspector.all("SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'issues'", [])
      preimage_index = indexes.find { |i| i["indexdef"].include?("fingerprint_preimage") }
      hash_index = indexes.find do |i|
        i["indexdef"].include?("fingerprint_sha256") && !i["indexdef"].include?("fingerprint_preimage")
      end
      expect(preimage_index["indexdef"]).to include("UNIQUE")
      expect(hash_index["indexdef"]).not_to include("UNIQUE")
    end

    # The preimage contains EXACTLY the seven named fields.
    it "builds the fingerprint preimage from exactly the seven contract fields" do
      ctx = evaluated_run
      issue = issues_of(evaluation_for(ctx[:crawl_id])["id"]).first
      preimage = [issue["fingerprint_preimage"].sub(/\A\\x/, "")].pack("H*")
      expect(JSON.parse(preimage).keys.sort)
        .to eq(%w[canonical_subject_key canonical_subject_type check_definition_id issue_type
                  organization_id project_id source_id])
    end
  end

  # =====================================================================================
  describe "the Issue-set seal and completion" do
    it "seals one immutable Issue Set and transitions the Evaluation to completed" do
      ctx = evaluated_run
      eid = evaluation_for(ctx[:crawl_id])["id"]
      set = issue_set_of(eid)

      expect(set).not_to be_nil
      expect(set["member_count"].to_i).to eq(issues_of(eid).length)
      expect(set["current_leaf_count"].to_i).to eq(issues_of(eid).length)
      expect(evaluation_row(eid)["state"]).to eq("completed")
      expect(evaluation_row(eid)["completed_at"]).not_to be_nil
    end

    it "emits exactly one EvaluationStarted and one EvaluationCompleted" do
      ctx = evaluated_run
      eid = evaluation_for(ctx[:crawl_id])["id"]
      types = DbInspector.all(<<~SQL, [eid]).map { |e| e["event_type"] }
        SELECT event_type FROM event_registry WHERE aggregate_id = $1::uuid ORDER BY created_at
      SQL
      expect(types.count("EvaluationStarted")).to eq(1)
      expect(types.count("EvaluationCompleted")).to eq(1)
      expect(types).not_to include("EvaluationFailed")
    end

    # `CheckResultCreated` is emitted ONLY with the one persisted Result, and the per-attempt
    # telemetry row is NOT a domain event.
    it "emits one CheckResultCreated per Result and never emits attempt telemetry" do
      ctx = evaluated_run
      eid = evaluation_for(ctx[:crawl_id])["id"]
      created = DbInspector.all(<<~SQL, [ctx[:g][:organization_id]])
        SELECT aggregate_id FROM event_registry
        WHERE organization_id = $1::uuid AND event_type = 'CheckResultCreated'
      SQL
      expect(created.length).to eq(check_results(eid).length)
      expect(created.map { |e| e["aggregate_id"] }.sort).to eq(check_results(eid).map { |r| r["id"] }.sort)

      all_types = DbInspector.all(<<~SQL, [ctx[:g][:organization_id]]).map { |e| e["event_type"] }.uniq
        SELECT DISTINCT event_type FROM event_registry WHERE organization_id = $1::uuid
      SQL
      expect(all_types).not_to include("CheckExecutionAttempted", "CheckAttemptStarted")
    end

    it "records one attempt telemetry row per Result, outside the event stream" do
      ctx = evaluated_run
      eid = evaluation_for(ctx[:crawl_id])["id"]
      attempts = DbInspector.all("SELECT * FROM check_attempts WHERE evaluation_id=$1::uuid", [eid])
      expect(attempts.length).to eq(check_results(eid).length)
      expect(attempts.map { |a| a["attempt_number"].to_i }.uniq).to eq([1])
      expect(attempts.map { |a| a["retry_of_attempt_number"] }.uniq).to eq([nil])
    end

    # COMPLETION IS NOT PROMOTION. A scoreless Evaluation is a COMPLETED Evaluation with an
    # unpromoted pointer, not a failure — which is exactly why the ratified OD-010 baseline
    # does not fail WF-007.
    it "completes with an unavailable score rather than failing" do
      ctx = evaluated_run
      eid = evaluation_for(ctx[:crawl_id])["id"]
      insufficient = check_results(eid).select { |r| r["execution_status"] == "error" }
                                       .map { |r| r["pillar_id"] }.uniq
      # THREE blocking pillars, not four. Local Presence is validly not applicable and so
      # cannot make the score unavailable (:678 "an inapplicable pillar ... has null score,
      # weight `0/1`"). `not_to include` is the load-bearing half: if the genesis profile
      # regressed to the all-NULL shape this pillar would rejoin the list.
      expect(insufficient).to contain_exactly("search_presence", "ai_presence", "authority_signals")
      expect(insufficient).not_to include("local_presence")
      # THE SCORE IS STILL UNAVAILABLE, and removing one blocker does not change that. Three
      # of the four owner decisions in VOL3-INPUT-external-pillar-evidence-gap stand between
      # here and a number.
      expect(evaluation_row(eid)["state"]).to eq("completed")
      expect(evaluation_row(eid)["reason"]).to be_nil
    end

    it "refuses to rewrite a sealed Issue Set" do
      ctx = evaluated_run
      set = issue_set_of(evaluation_for(ctx[:crawl_id])["id"])
      expect { DbInspector.connection.exec_params("UPDATE issue_sets SET member_count = 99 WHERE id=$1::uuid", [set["id"]]) }
        .to raise_error(PG::RaiseException, /immutable/)
    end

    it "refuses to rewrite a persisted Check Result" do
      ctx = evaluated_run
      result = check_results(evaluation_for(ctx[:crawl_id])["id"]).first
      expect do
        DbInspector.connection.exec_params("UPDATE check_results SET execution_status='passed' WHERE id=$1::uuid", [result["id"]])
      end.to raise_error(PG::RaiseException, /immutable/)
    end
  end

  # =====================================================================================
  describe "the OD-018 latch, and the second crawl" do
    # THE PROPERTY THE WHOLE SLICE TURNS ON. A completed Evaluation holds no orchestration
    # slot, so the Project can be crawled again — which is the release the input gate began
    # and WF-007 finishes.
    it "releases the guard, so a second crawl runs and is evaluated in its own right" do
      first = evaluated_run
      first_eid = evaluation_for(first[:crawl_id])["id"]
      expect(evaluation_row(first_eid)["state"]).to eq("completed")

      held = DbInspector.all(<<~SQL, [first[:g][:project_id]])
        SELECT * FROM evaluations WHERE project_id = $1::uuid AND state IN ('pending','running')
      SQL
      expect(held).to be_empty
    end

    it "evaluates a second crawl of the SAME project to its own completed Evaluation" do
      first = evaluated_run
      first_eid = evaluation_for(first[:crawl_id])["id"]

      second = rerun(first)
      second_eid = evaluation_for(second[:crawl_id])["id"]

      expect(second_eid).not_to eq(first_eid)
      expect(evaluation_row(second_eid)["state"]).to eq("completed")
      expect(check_results(second_eid).length).to eq(check_results(first_eid).length)
      expect(issue_set_of(second_eid)).not_to be_nil
    end
  end

  # =====================================================================================
  describe "the coverage-incomplete branch, when the crawl did not observe every target" do
    # THE CAUSE THIS PINS IS THE ONE A LIVE SITE ACTUALLY HITS, and it survives in-crawl link
    # discovery (S-07-007) rather than being repaired by it.
    #
    # :478 derives CHK-TI-001's targets from EVERY in-scope `link_edges` target, and `link_edges`
    # covers `<link href>` as well as `<a href>`. :452 records an unsupported media type as
    # `policy_excluded` and puts it OUTSIDE the coverage denominator — so the CRAWL is `full`.
    # But :294's target reason vocabulary has no token for `policy_excluded`, so the derivation
    # can only call such a target `unobserved`, and CHK-TI-001 evaluates the error BEFORE failed
    # and pass. A same-host stylesheet therefore leaves the Check indeterminate over a crawl that
    # observed everything it was asked to observe.
    #
    # That is every page built by every mainstream CMS: measured on the real subject site, the
    # `xirconhomes.com.au` home page alone names 79 distinct in-scope targets of which 37 are
    # stylesheets, fonts, images or JSON endpoints. The repair is a Volume I decision about
    # whether `policy_excluded` belongs in the target set at all; it is recorded here, not made.
    it "reports coverage-incomplete for a target the crawl observed but could not document" do
      ctx = crawlable
      run_to_evaluated(ctx, outbound_pages(
                              "/" => { body: '<html><head><title>Acme Supplies</title>' \
                                             '<link rel="stylesheet" href="/s.css"></head><body>hi</body></html>' },
                              "/s.css" => { body: "a{}", type: "text/css" }
                            ))
      ti = results_by_definition(evaluation_for(ctx[:crawl_id])["id"])["CHK-TI-001"].sole

      # THE CRAWL IS COMPLETE. This is the half that makes the Check's error surprising, and it
      # is asserted first so a later reader cannot mistake the error for a failed crawl.
      expect(crawl_row(ctx[:crawl_id])["coverage_status"]).to eq("full")
      expect(terminal_outcomes(ctx[:crawl_id]).map { |o| o["outcome"] })
        .to contain_exactly("document_created", "policy_excluded")

      expect(ti["execution_status"]).to eq("error")
      expect(ti["outcome_code"]).to eq("internal_link_coverage_incomplete")
      expect(ti["error_reason_code"]).to eq("input_evidence_indeterminate")
      expect(ti["impact_band"]).to be_nil
      # An error creates NO Issue and makes its pillar insufficient.
      expect(issues_of(evaluation_for(ctx[:crawl_id])["id"]).map { |i| i["check_definition_id"] })
        .not_to include("CHK-TI-001")
    end

    # AND THE OTHER HALF, so the example above cannot be read as "CHK-TI-001 never passes". With
    # every in-scope target a real page, discovery alone carries the run to a decision-grade pass
    # — no sitemap seeding, no help.
    it "reaches a decision-grade pass when discovery observed every target" do
      ctx = crawlable
      run_to_evaluated(ctx, outbound_pages("/" => { body: root_page },
                                           "/about" => { body: about_page },
                                           "/gone" => { body: about_page }))
      ti = results_by_definition(evaluation_for(ctx[:crawl_id])["id"])["CHK-TI-001"].sole

      expect(ti["execution_status"]).to eq("passed")
      expect(ti["outcome_code"]).to eq("internal_links_resolve")
      expect(ti["subject_set_complete"]).to eq("t")
    end
  end
end
