# frozen_string_literal: true

require "rails_helper"
require_relative "support/wf006_parse_chain"

# THE EXTERNAL-MEASUREMENT INTAKE BOUNDARY, and the edge it refuses to cross
# (WORKFLOW_SPECIFICATIONS.md :480-482; OD-010 § Required Owner Approval Package).
#
# The register's sentence is the whole design: OD-010 approval "is valid only for one immutable
# Measurement Set package whose owner-supplied content includes ALL of the following; OMISSION
# LEAVES THE NO-SET SAFE INTERIM ACTIVE AND AUTHORIZES NO INFERRED VALUE." So every refusal below
# is product behaviour rather than defensive coding — an incomplete package does not authorize a
# partial measurement, it authorizes nothing, and the platform keeps saying `input_evidence_missing`.
#
# THE ACTIVATION EDGE IS ASSERTED FROM BOTH SIDES. Activation needs two owner signatures over the
# SAME package digest; these examples prove that one signature, or two over different bytes,
# activates nothing, and that submission without an active set is refused. That is the boundary
# this build stops at deliberately.
RSpec.describe "WF-006 external measurement intake", type: :acceptance,
               acceptance_ids: %w[AC-CAP-010 AC-WF-006], test_types: %w[TYP-DATA TYP-SEC] do
  include Wf006ParseChain
  self.use_transactional_tests = false
  after { ReceiptMinter.truncate_all }

  let(:catalog) { Workflows::Wf007::CheckCatalog }
  let(:intake) { Workflows::Wf006::MeasurementIntake }
  let(:package_module) { Workflows::Wf006::MeasurementPackage }

  # An Evaluation with a sealed input snapshot, which is what a submission attaches to.
  def sealed_evaluation
    ctx = crawlable
    run_to_parsed(ctx, outbound_pages("/" => { body: "<html><head><title>Acme</title></head></html>" }))
    ctx
  end

  def in_org(org)
    Platform::UnitOfWork.run do |conn|
      store = IdentityAccess::Infrastructure::CheckExecutionStore.new(conn.raw_connection)
      store.enter_org_context(org:, correlation_id: SecureRandom.uuid_v7)
      yield store
    end
  end

  # CONTEMPORANEOUS WITH THE SEALED SNAPSHOT, not with the wall clock. The harness drives the
  # chain on a fixed clock, so a snapshot seals at `start_now`; an observation stamped with the
  # real current time would be made AFTER the snapshot it is offered to and would correctly read
  # as stale. That is the freshness predicate working, and it is asserted directly elsewhere —
  # here the fixture needs to be inside the window so the Definition's own rule is what gets tested.
  def observed_at = (start_now - 60).floor
  def definition = catalog.definition("CHK-AIP-001")

  # A complete, valid package. Every example below starts from this and removes or corrupts
  # exactly one thing, so each refusal is attributable to that one thing.
  def valid_package(organization_id:, project_id:, items: nil, observed: nil, keys: %w[Q-1 Q-2])
    observed ||= observed_at
    items ||= keys.map do |key|
      { "intent_key" => key, "presence_status" => "present", "citation_status" => "cited",
        "entity_keys" => ["Acme Supplies"] }
    end
    {
      "package_schema_version" => "measurement-set-package-v1",
      "measurement_set_id" => "test-aip-set", "measurement_set_version" => "1.0.0",
      "measurement_kind" => "ai_answer_presence",
      "organization_id" => organization_id, "project_id" => project_id,
      "package_created_at" => observed.iso8601, "proposed_effective_at" => observed.iso8601,
      "provider_identities" => [{ "provider" => "openai", "model" => "gpt-5.5" }],
      "collector_adapter" => { "id" => "videt-probe-harness", "version" => "v0.1",
                               "sha256" => Digest::SHA256.hexdigest("adapter") },
      "expected_keys" => keys,
      "key_content" => keys.to_h { |k| [k, "Who are the best builders in Melbourne? (#{k})"] },
      "locale" => "en-AU", "time_zone" => "UTC", "max_evidence_age_seconds" => 86_400,
      "binding" => {
        "catalog_version" => catalog::CATALOG_VERSION,
        "catalog_sha256" => catalog.hex(catalog.catalog_digest),
        "definition_id" => "CHK-AIP-001", "definition_version" => "1.0.0",
        "definition_sha256" => catalog.hex(catalog.definition_digest(definition))
      },
      "retention_location" => "operations/probe-harness/evidence/",
      "owner_approval_reference" => "OD-010",
      "observations" => [{
        "schema_version" => "external-observation-v1",
        "organization_id" => organization_id, "project_id" => project_id,
        "measurement_kind" => "ai_answer_presence",
        "measurement_policy_version" => "external-measurement-interim-v1",
        "collector_adapter_id" => "videt-probe-harness", "collector_adapter_version" => "v0.1",
        "measurement_set_version" => "1.0.0", "locale" => "en-AU", "time_zone" => "UTC",
        "observed_at_utc" => observed.iso8601,
        "captured_at_utc" => observed.iso8601,
        "fresh_until_utc" => (observed + 86_400).iso8601,
        "coverage_status" => "complete",
        "body" => { "expected_intent_keys" => keys, "items" => items }
      }]
    }
  end

  def import(store, package, ctx)
    intake.import(store:, package:, organization_id: ctx[:g][:organization_id],
                  project_id: ctx[:g][:project_id], now: Time.now.utc,
                  correlation_id: SecureRandom.uuid_v7,
                  catalog_version: catalog::CATALOG_VERSION,
                  catalog_sha256: catalog.hex(catalog.catalog_digest))
  end

  # Both owners signing the SAME digest, which is what makes a package activatable.
  def signed(package)
    hex = package_module.digest(package).unpack1("H*")
    # ONLY the signatures are added. The digest excludes `signatures` and nothing else, so
    # adding any other field here would sign different bytes than the ones imported.
    package.merge(
      "signatures" => {
        "chief_product" => { "signer_identity" => "chief.product@videt.example", "authority" => "Chief Product",
                             "signed_at" => Time.now.utc.iso8601, "decision" => "approved",
                             "package_sha256" => hex },
        "chief_architect" => { "signer_identity" => "chief.architect@videt.example", "authority" => "Chief Architect",
                               "signed_at" => Time.now.utc.iso8601, "decision" => "approved",
                               "package_sha256" => hex }
      }
    )
  end

  # =====================================================================================
  describe "import" do
    it "stages a valid package as PROPOSED and activates nothing" do
      ctx = sealed_evaluation
      result = in_org(ctx[:g][:organization_id]) do |store|
        import(store, valid_package(organization_id: ctx[:g][:organization_id],
                                    project_id: ctx[:g][:project_id]), ctx)
      end

      expect(result).to be_ok
      expect(result.record["status"]).to eq("proposed")
      expect(result.record["activated_at"]).to be_nil
      expect(result.record["product_signature"]).to be_nil
      expect(result.record["architect_signature"]).to be_nil
    end

    # Idempotent on the package digest: an operator who submits the same file twice has not
    # created two things for the owner to sign.
    it "returns the same row for a byte-identical re-import" do
      ctx = sealed_evaluation
      package = valid_package(organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id])
      first = in_org(ctx[:g][:organization_id]) { |s| import(s, package, ctx) }
      second = in_org(ctx[:g][:organization_id]) { |s| import(s, package, ctx) }

      expect(second).to be_ok
      expect(second.record["id"]).to eq(first.record["id"])
      expect(DbInspector.all("SELECT id FROM measurement_sets", []).length).to eq(1)
    end

    # "Reuse of a version for changed content is prohibited." Different bytes under the same
    # version is refused, not accepted as a second proposal — otherwise an owner who signed
    # version 1.0.0 would have signed something ambiguous.
    it "refuses a different package that reuses an existing version" do
      ctx = sealed_evaluation
      base = valid_package(organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id])
      altered = base.merge("retention_location" => "somewhere/else/")
      in_org(ctx[:g][:organization_id]) { |s| import(s, base, ctx) }
      result = in_org(ctx[:g][:organization_id]) { |s| import(s, altered, ctx) }

      expect(result).not_to be_ok
      expect(result.reason).to eq("measurement_set_version_reused")
    end

    # FAIL CLOSED ON THE WRONG TENANT. The package names its own Organization, and a package
    # whose declared Organization is not the importing one is refused before anything persists.
    it "refuses a package naming another organization" do
      ctx = sealed_evaluation
      foreign = valid_package(organization_id: SecureRandom.uuid_v7, project_id: ctx[:g][:project_id])
      result = in_org(ctx[:g][:organization_id]) { |s| import(s, foreign, ctx) }

      expect(result).not_to be_ok
      expect(result.reason).to eq("measurement_package_invalid")
      expect(result.detail).to include("tenant_mismatch")
      expect(DbInspector.all("SELECT id FROM measurement_sets", [])).to be_empty
    end

    # Each of the register's required fields, removed one at a time. "Omission leaves the no-set
    # safe interim active" — so every one of these is a refusal, not a defaulted value.
    it "refuses a package missing any field the register requires" do
      ctx = sealed_evaluation
      base = valid_package(organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id])

      %w[measurement_set_id measurement_set_version measurement_kind provider_identities
         collector_adapter expected_keys key_content binding retention_location observations
         owner_approval_reference max_evidence_age_seconds].each do |field|
        result = in_org(ctx[:g][:organization_id]) { |s| import(s, base.except(field), ctx) }
        expect(result).not_to be_ok, "omitting #{field} must refuse the package"
        expect(result.reason).to eq("measurement_package_invalid")
      end
      expect(DbInspector.all("SELECT id FROM measurement_sets", [])).to be_empty
    end

    # THE PINNING RULE. A package must bind the unchanged Catalog and Definition digests; one
    # that names different digests is measuring against thresholds nobody approved.
    it "refuses a package bound to a Catalog or Definition digest that is not the active one" do
      ctx = sealed_evaluation
      base = valid_package(organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id])
      wrong_catalog = base.merge("binding" => base["binding"].merge("catalog_sha256" => Digest::SHA256.hexdigest("x")))
      wrong_definition = base.merge("binding" => base["binding"].merge("definition_sha256" => Digest::SHA256.hexdigest("y")))

      expect(in_org(ctx[:g][:organization_id]) { |s| import(s, wrong_catalog, ctx) }.detail)
        .to include("binding_catalog_mismatch")
      expect(in_org(ctx[:g][:organization_id]) { |s| import(s, wrong_definition, ctx) }.detail)
        .to include("binding_definition_mismatch")
    end

    # A package may not widen the freshness window. Refused rather than clamped: clamping would
    # accept a package the owner did not approve and quietly change what it means.
    it "refuses a package that widens the 24-hour evidence age" do
      ctx = sealed_evaluation
      base = valid_package(organization_id: ctx[:g][:organization_id], project_id: ctx[:g][:project_id])
      result = in_org(ctx[:g][:organization_id]) { |s| import(s, base.merge("max_evidence_age_seconds" => 604_800), ctx) }

      expect(result.detail).to include("evidence_age_invalid")
    end

    it "refuses unordered, duplicated or unbound intent keys" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      base = valid_package(organization_id: org, project_id: ctx[:g][:project_id], keys: %w[Q-1 Q-2])

      unordered = base.merge("expected_keys" => %w[Q-2 Q-1])
      expect(in_org(org) { |s| import(s, unordered, ctx) }.detail).to include("expected_keys_unordered")

      duplicated = base.merge("expected_keys" => %w[Q-1 Q-1])
      expect(in_org(org) { |s| import(s, duplicated, ctx) }.detail).to include("expected_keys_duplicated")

      unbound = base.merge("key_content" => base["key_content"].merge("Q-9" => "extra"))
      expect(in_org(org) { |s| import(s, unbound, ctx) }.detail.join).to include("key_content_unbound")
    end

    # The schema's one cross-field rule: "`absent` requires `not_cited` and no entity key". An
    # observation claiming a citation for a business the answers never named is invalid content.
    it "refuses an observation whose absent item claims a citation or an entity" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      items = [{ "intent_key" => "Q-1", "presence_status" => "absent", "citation_status" => "cited",
                 "entity_keys" => [] },
               { "intent_key" => "Q-2", "presence_status" => "present", "citation_status" => "cited",
                 "entity_keys" => ["Acme"] }]
      package = valid_package(organization_id: org, project_id: ctx[:g][:project_id], items:)

      expect(in_org(org) { |s| import(s, package, ctx) }.detail.join)
        .to include("absent_requires_not_cited_and_no_entity")
    end
  end

  # =====================================================================================
  describe "activation, which is the owner's and not ours" do
    it "refuses to activate a package carrying no signatures" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      package = valid_package(organization_id: org, project_id: ctx[:g][:project_id])
      in_org(org) { |s| import(s, package, ctx) }

      result = in_org(org) do |store|
        intake.activate(store:, package:, organization_id: org, now: Time.now.utc,
                        correlation_id: SecureRandom.uuid_v7)
      end

      expect(result).not_to be_ok
      expect(result.reason).to eq("measurement_set_approval_incomplete")
      expect(DbInspector.one("SELECT status FROM measurement_sets", [])["status"]).to eq("proposed")
    end

    # "ONE SIGNATURE ... does not authorize activation."
    it "refuses to activate on a single signature" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      package = valid_package(organization_id: org, project_id: ctx[:g][:project_id])
      in_org(org) { |s| import(s, package, ctx) }
      one = signed(package)
      one["signatures"].delete("chief_architect")

      result = in_org(org) do |store|
        intake.activate(store:, package: one, organization_id: org, now: Time.now.utc,
                        correlation_id: SecureRandom.uuid_v7)
      end

      expect(result.detail).to include("signature_missing:chief_architect")
      expect(DbInspector.one("SELECT status FROM measurement_sets", [])["status"]).to eq("proposed")
    end

    # "SIGNATURES OVER DIFFERENT BYTES do not authorize activation." This is the substitution
    # attack the two signatures exist to stop: a real approval of one package, presented to
    # activate another.
    it "refuses to activate when a signature is over different bytes" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      package = valid_package(organization_id: org, project_id: ctx[:g][:project_id])
      in_org(org) { |s| import(s, package, ctx) }
      forged = signed(package)
      forged["signatures"]["chief_product"]["package_sha256"] = Digest::SHA256.hexdigest("other bytes")

      result = in_org(org) do |store|
        intake.activate(store:, package: forged, organization_id: org, now: Time.now.utc,
                        correlation_id: SecureRandom.uuid_v7)
      end

      expect(result.detail).to include("signature_over_other_bytes:chief_product")
      expect(DbInspector.one("SELECT status FROM measurement_sets", [])["status"]).to eq("proposed")
    end

    # The database refuses an active row without both signatures independently of the command,
    # so an implementation cannot activate a set by forgetting to look.
    it "refuses an unsigned activation at the database, not only in the command" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      in_org(org) { |s| import(s, valid_package(organization_id: org, project_id: ctx[:g][:project_id]), ctx) }
      id = DbInspector.one("SELECT id FROM measurement_sets", [])["id"]

      expect do
        DbInspector.connection.exec_params(
          "UPDATE measurement_sets SET status='active', activated_at=now() WHERE id=$1::uuid", [id]
        )
      end.to raise_error(PG::CheckViolation, /activation_requires_both_signatures/)
    end

    it "activates on two complete signatures over the same digest" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      package = valid_package(organization_id: org, project_id: ctx[:g][:project_id])
      in_org(org) { |s| import(s, package, ctx) }

      result = in_org(org) do |store|
        intake.activate(store:, package: signed(package), organization_id: org, now: Time.now.utc,
                        correlation_id: SecureRandom.uuid_v7)
      end

      expect(result).to be_ok
      expect(result.record["status"]).to eq("active")
      expect(result.record["activated_at"]).not_to be_nil
    end
  end

  # =====================================================================================
  describe "submission" do
    def submit(store, ctx, payload)
      intake.submit(store:, payload:, organization_id: ctx[:g][:organization_id],
                    project_id: ctx[:g][:project_id],
                    evaluation_id: evaluation_for(ctx[:crawl_id])["id"],
                    now: Time.now.utc, correlation_id: SecureRandom.uuid_v7)
    end

    # THE RATIFIED BASELINE, ASSERTED AS A REFUSAL: "unknown/inactive set is
    # `F1-DOMAIN-409 / measurement_set_unavailable`". This is the state this build ships in.
    it "refuses every submission while no set is active" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      package = valid_package(organization_id: org, project_id: ctx[:g][:project_id])
      in_org(org) { |s| import(s, package, ctx) }

      result = in_org(org) { |s| submit(s, ctx, package["observations"].first) }

      expect(result).not_to be_ok
      expect(result.reason).to eq("measurement_set_unavailable")
      expect(DbInspector.all("SELECT id FROM external_measurement_submissions", [])).to be_empty
      expect(DbInspector.all("SELECT id FROM evidence WHERE evidence_type='external_measurement'", []))
        .to be_empty
    end

    it "accepts one observation once the set is active, and produces one Evidence record" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      package = valid_package(organization_id: org, project_id: ctx[:g][:project_id])
      in_org(org) { |s| import(s, package, ctx) }
      in_org(org) { |s| intake.activate(store: s, package: signed(package), organization_id: org, now: Time.now.utc, correlation_id: SecureRandom.uuid_v7) }

      result = in_org(org) { |s| submit(s, ctx, package["observations"].first) }

      expect(result).to be_ok
      expect(result.record["outcome"]).to eq("accepted")
      evidence = DbInspector.all("SELECT * FROM evidence WHERE evidence_type='external_measurement'", [])
      expect(evidence.length).to eq(1)
      expect(evidence.first["schema_version"]).to eq("external-observation-v1")
      expect(evidence.first["validation_status"]).to eq("valid")
    end

    it "returns the stored record on exact replay and refuses altered bytes for the same tuple" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      package = valid_package(organization_id: org, project_id: ctx[:g][:project_id])
      in_org(org) { |s| import(s, package, ctx) }
      in_org(org) { |s| intake.activate(store: s, package: signed(package), organization_id: org, now: Time.now.utc, correlation_id: SecureRandom.uuid_v7) }
      payload = package["observations"].first

      first = in_org(org) { |s| submit(s, ctx, payload) }
      replay = in_org(org) { |s| submit(s, ctx, payload) }
      expect(replay).to be_ok
      expect(replay.record["id"]).to eq(first.record["id"])

      altered = payload.merge("coverage_status" => "partial")
      conflict = in_org(org) { |s| submit(s, ctx, altered) }
      expect(conflict).not_to be_ok
      expect(conflict.reason).to eq("idempotency_conflict")
      expect(DbInspector.all("SELECT id FROM external_measurement_submissions", []).length).to eq(1)
    end

    it "refuses a payload whose tenancy disagrees with the envelope" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      package = valid_package(organization_id: org, project_id: ctx[:g][:project_id])
      in_org(org) { |s| import(s, package, ctx) }
      in_org(org) { |s| intake.activate(store: s, package: signed(package), organization_id: org, now: Time.now.utc, correlation_id: SecureRandom.uuid_v7) }
      foreign = package["observations"].first.merge("project_id" => SecureRandom.uuid_v7)

      result = in_org(org) { |s| submit(s, ctx, foreign) }
      expect(result.reason).to eq("tenant_mismatch")
    end

    it "refuses a payload whose key set disagrees with the approved set" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      package = valid_package(organization_id: org, project_id: ctx[:g][:project_id])
      in_org(org) { |s| import(s, package, ctx) }
      in_org(org) { |s| intake.activate(store: s, package: signed(package), organization_id: org, now: Time.now.utc, correlation_id: SecureRandom.uuid_v7) }
      payload = package["observations"].first
      wrong = payload.merge("body" => payload["body"].merge("expected_intent_keys" => %w[Q-1 Q-2 Q-3]))

      result = in_org(org) { |s| submit(s, ctx, wrong) }
      expect(result.detail).to include("key_set_mismatch")
    end

    # The freshness window is a database constraint too: a payload claiming a wider window
    # cannot be stored even if a code path let it through.
    it "refuses a submission whose freshness window is not exactly 24 hours" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      package = valid_package(organization_id: org, project_id: ctx[:g][:project_id])
      widened = package.merge(
        "observations" => [package["observations"].first.merge(
          "fresh_until_utc" => (observed_at + 172_800).iso8601
        )]
      )
      result = in_org(org) { |s| import(s, widened, ctx) }
      expect(result.detail.join).to include("freshness_window_invalid")
    end
  end

  # =====================================================================================
  describe "freshness at selection, asserted at the exact boundary" do
    # "consumable when `observed_at_utc <= snapshot_sealed_at_utc < fresh_until_utc`; equality at
    # `fresh_until_utc` is STALE" — asserted immediately before, exactly at, and immediately after.
    def freshness_at(offset_seconds)
      observed = Time.utc(2026, 8, 1, 0, 0, 0)
      fresh_until = observed + 86_400
      row = { "observed_at_utc" => observed.iso8601, "fresh_until_utc" => fresh_until.iso8601 }
      Workflows::Wf007::Applicability.freshness_of(row, (fresh_until + offset_seconds).iso8601)
    end

    it "is fresh immediately before expiry, STALE at expiry, and stale after" do
      expect(freshness_at(-1)).to eq("fresh")
      expect(freshness_at(0)).to eq("stale")
      expect(freshness_at(1)).to eq("stale")
    end

    it "is stale when the snapshot sealed BEFORE the observation was made" do
      observed = Time.utc(2026, 8, 1, 12, 0, 0)
      row = { "observed_at_utc" => observed.iso8601, "fresh_until_utc" => (observed + 86_400).iso8601 }
      expect(Workflows::Wf007::Applicability.freshness_of(row, (observed - 1).iso8601)).to eq("stale")
      expect(Workflows::Wf007::Applicability.freshness_of(row, observed.iso8601)).to eq("fresh")
    end

    # Platform-derived Evidence has no observation window; treating a missing window as expired
    # would make every parsed-content Check report stale evidence.
    it "treats evidence with no observation window as not applicable rather than expired" do
      expect(Workflows::Wf007::Applicability.freshness_of({}, Time.now.utc.iso8601))
        .to eq("not_applicable")
    end

    # A STALE SELECTION IS STILL A SELECTION, and it reports the reason that is true.
    # `input_evidence_stale` says "we measured this and it expired"; `input_evidence_missing`
    # says "nothing was ever measured". Collapsing them would tell a customer nothing had been
    # measured when in fact it had.
    it "produces input_evidence_stale rather than input_evidence_missing" do
      entry = { "canonical_subject_key" => "p1", "applicable" => true,
                "selected_evidence" => [{ "evidence_id" => "e1", "freshness" => "stale" }] }
      outcome = Workflows::Wf007::Executor.evaluate(
        Workflows::Wf007::CheckCatalog.definition("CHK-AIP-001"), entry, {}
      )

      expect(outcome.execution_status).to eq("error")
      expect(outcome.error_reason_code).to eq("input_evidence_stale")
      expect(outcome.outcome_code).to eq("ai_answer_presence_gap")
      expect(outcome.subject_set_complete).to be(false)
    end

    # Staleness OUTRANKS every reason the Definition's own rule could reach: the ratified
    # first-match order puts `input_evidence_stale` above `input_evidence_indeterminate`, so an
    # observation that is both expired AND partially covered reports that it expired.
    it "reports stale ahead of indeterminate when the payload is also incomplete" do
      entry = { "canonical_subject_key" => "p1", "applicable" => true,
                "selected_evidence" => [{ "evidence_id" => "e1", "freshness" => "stale" }] }
      payloads = { "e1" => { "coverage_status" => "partial",
                             "body" => { "expected_intent_keys" => [], "items" => [] } } }
      outcome = Workflows::Wf007::Executor.evaluate(
        Workflows::Wf007::CheckCatalog.definition("CHK-AIP-001"), entry, payloads
      )
      expect(outcome.error_reason_code).to eq("input_evidence_stale")
    end
  end

  # =====================================================================================
  describe "CHK-AIP-001 over a real activated observation" do
    # The whole path, end to end: import, activate, submit, evaluate. This is what happens the
    # moment the owner signs — and it is asserted here so that the activation decision is the
    # only thing standing between the platform and a live AI-presence result.
    it "computes qualified_rate and the ratified outcome from the accepted observation" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      # Two intents qualified of five, exactly the shape the real Xircon Homes probe produced.
      keys = %w[Q-1 Q-2 Q-3 Q-4 Q-5]
      items = keys.each_with_index.map do |key, index|
        if index < 2
          { "intent_key" => key, "presence_status" => "present", "citation_status" => "cited",
            "entity_keys" => ["Acme Supplies"] }
        else
          { "intent_key" => key, "presence_status" => "absent", "citation_status" => "not_cited",
            "entity_keys" => [] }
        end
      end
      package = valid_package(organization_id: org, project_id: ctx[:g][:project_id], keys:, items:)
      in_org(org) { |s| import(s, package, ctx) }
      in_org(org) { |s| intake.activate(store: s, package: signed(package), organization_id: org, now: Time.now.utc, correlation_id: SecureRandom.uuid_v7) }
      in_org(org) do |s|
        intake.submit(store: s, payload: package["observations"].first, organization_id: org,
                      project_id: ctx[:g][:project_id],
                      evaluation_id: evaluation_for(ctx[:crawl_id])["id"],
                      now: Time.now.utc, correlation_id: SecureRandom.uuid_v7)
      end

      advance_wf007(ctx)
      drain_check_attempts(ctx)
      advance_wf007(ctx)

      aip = check_results(evaluation_for(ctx[:crawl_id])["id"])
            .find { |r| r["check_definition_id"] == "CHK-AIP-001" }
      observation = JSON.parse(aip["normalized_observation"])

      expect(aip["execution_status"]).to eq("failed")
      expect(aip["outcome_code"]).to eq("ai_answer_presence_gap")
      expect(observation["expected_count"]).to eq(5)
      expect(observation["qualified_count"]).to eq(2)
      expect(observation["qualified_rate"]).to eq("0.4000")
      # `0.0000 < rate < 1.0000` is medium; effort is `high` for this Definition.
      expect(aip["impact_band"]).to eq("medium")
      expect(aip["effort_band"]).to eq("high")
      expect(aip["subject_set_complete"]).to eq("t")
      # A failed Result with valid high confidence creates a published, open Issue.
      expect(issues_of(evaluation_for(ctx[:crawl_id])["id"]).map { |i| i["issue_type"] })
        .to include("ai_answer_presence_gap")
    end

    it "still reports input_evidence_missing for the kinds no approved set supplies" do
      ctx = sealed_evaluation
      org = ctx[:g][:organization_id]
      package = valid_package(organization_id: org, project_id: ctx[:g][:project_id])
      in_org(org) { |s| import(s, package, ctx) }
      in_org(org) { |s| intake.activate(store: s, package: signed(package), organization_id: org, now: Time.now.utc, correlation_id: SecureRandom.uuid_v7) }
      in_org(org) do |s|
        intake.submit(store: s, payload: package["observations"].first, organization_id: org,
                      project_id: ctx[:g][:project_id],
                      evaluation_id: evaluation_for(ctx[:crawl_id])["id"],
                      now: Time.now.utc, correlation_id: SecureRandom.uuid_v7)
      end

      advance_wf007(ctx)
      drain_check_attempts(ctx)
      advance_wf007(ctx)

      results = check_results(evaluation_for(ctx[:crawl_id])["id"]).index_by { |r| r["check_definition_id"] }
      # Approving an AI-presence set says nothing about search or authority, and the platform
      # does not infer one measurement from another.
      %w[CHK-SP-001 CHK-AS-001 CHK-LP-001].each do |id|
        expect(results[id]["error_reason_code"]).to eq("input_evidence_missing"), "#{id} must stay unmeasured"
      end
    end
  end
end
