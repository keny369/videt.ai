# frozen_string_literal: true

require "rails_helper"

# `check-catalog-v1` is RATIFIED, and these examples assert that the implementation
# transcribed it rather than authored one (SCORE_EVIDENCE_MODEL.md § Check Definition And
# Check Catalog Contract, § Mandatory Check Definitions; OD-010 Ratified 2026-07-17).
#
# The two failure modes worth pinning are opposite and both are silent: a catalogue that has
# been NARROWED loses a pillar without anyone noticing, and one that has been BROADENED
# invents a check the owner did not approve. Both are asserted here as exact membership
# rather than as a count.
RSpec.describe Workflows::Wf007::CheckCatalog, type: :domain,
               acceptance_ids: ["AC-PRULE-010"], test_types: %w[TYP-DATA] do
  let(:catalog) { described_class }

  describe "membership is exactly the seven ratified Definitions" do
    it "is neither narrowed nor broadened by OD-010's ratification" do
      expect(catalog::DEFINITION_IDS).to eq(%w[CHK-TI-001 CHK-CQ-001 CHK-TR-001 CHK-SP-001
                                               CHK-AIP-001 CHK-AS-001 CHK-LP-001])
      expect(catalog::DEFINITIONS.map { |d| d["semantic_version"] }.uniq).to eq(["1.0.0"])
    end

    it "carries the ratified owner, release and policy versions" do
      expect(catalog::CATALOG_VERSION).to eq("check-catalog-v1")
      expect(catalog::OWNER).to eq("Chief Product")
      expect(catalog::RELEASED_AT).to eq("2026-07-16T00:00:00Z")
      expect(catalog::EXECUTOR_POLICY).to eq("check-executor-interim-v1")
      expect(catalog::EXTERNAL_MEASUREMENT_POLICY).to eq("external-measurement-v1")
      expect(catalog::EFFORT_POLICY).to eq("effort-interim-v1")
      expect(catalog::LOCALE).to eq("en-AU")
      expect(catalog::TIME_ZONE).to eq("UTC")
    end

    # "Each Definition's `rule_or_model_version` is exactly `<check_definition_id>-rule-v1`
    # ... none invokes a model."
    it "names a rule version and never a model, for every Definition" do
      catalog::DEFINITIONS.each do |definition|
        id = definition["check_definition_id"]
        expect(catalog.rule_version(id)).to eq("#{id}-rule-v1")
        expect(catalog.semantic_body(definition)["rule_or_model_version"]).to eq("#{id}-rule-v1")
      end
    end

    it "declares exactly one score-capable Definition per Pillar, covering all seven" do
      pillars = catalog::DEFINITIONS.map { |d| d["pillar_id"] }
      expect(pillars.sort).to eq(catalog::PILLARS.sort)
      expect(pillars.uniq.length).to eq(7)
    end
  end

  describe "activation validation" do
    it "passes on the ratified catalogue" do
      expect(catalog.validation_failures).to be_empty
      expect(catalog).to be_valid
    end

    # A Definition with a nonexhaustive impact mapping cannot enter an active Catalog. The
    # check is asserted by REMOVING a mapping and requiring the validator to notice, because
    # a validator that only ever sees valid input proves nothing.
    it "refuses a Definition whose failed outcome has no impact mapping" do
      broken = catalog::DEFINITIONS.map(&:dup)
      broken[0] = broken[0].merge("impact" => {})
      stub_const("#{described_class}::DEFINITIONS", broken.freeze)
      expect(catalog.validation_failures).to include("impact_nonexhaustive:CHK-TI-001")
    end

    it "refuses a Definition whose failed outcome has no effort mapping" do
      broken = catalog::DEFINITIONS.map(&:dup)
      broken[1] = broken[1].merge("effort" => {})
      stub_const("#{described_class}::DEFINITIONS", broken.freeze)
      expect(catalog.validation_failures).to include("effort_nonexhaustive:CHK-CQ-001")
    end

    it "refuses a Definition whose failed outcome renders no template" do
      broken = catalog::DEFINITIONS.map(&:dup)
      broken[2] = broken[2].merge("recommendation_templates" => {})
      stub_const("#{described_class}::DEFINITIONS", broken.freeze)
      expect(catalog.validation_failures).to include("template_nonexhaustive:CHK-TR-001")
    end

    it "refuses duplicate membership and a missing pillar" do
      broken = [catalog::DEFINITIONS[0], catalog::DEFINITIONS[0]] + catalog::DEFINITIONS[2..]
      stub_const("#{described_class}::DEFINITIONS", broken.freeze)
      failures = catalog.validation_failures
      expect(failures).to include("membership_not_seven").or include("membership_duplicated")
      expect(failures).to include("pillar_coverage_incomplete")
    end

    it "raises `check_catalog_integrity_failure` rather than returning a partial catalogue" do
      stub_const("#{described_class}::DEFINITIONS", [catalog::DEFINITIONS.first].freeze)
      expect { catalog.validate! }.to raise_error(Platform::InvariantViolation, /check_catalog_integrity_failure/)
    end
  end

  # `not_applicable` belongs to exactly one Definition. Any other Definition that DECLARED
  # one would be integrity-failed before it could ever produce the Result — which is
  # stronger than catching the Result at execution.
  describe "`not_applicable` belongs to exactly one Definition" do
    it "is declared by CHK-LP-001 and by nothing else" do
      declaring = catalog::DEFINITIONS.select do |d|
        d["outcomes"].any? { |o| o["execution_status"] == "not_applicable" }
      end
      expect(declaring.map { |d| d["check_definition_id"] }).to eq(["CHK-LP-001"])
    end

    it "fails validation if another Definition declares one" do
      broken = catalog::DEFINITIONS.map(&:dup)
      broken[0] = broken[0].merge(
        "outcomes" => broken[0]["outcomes"] + [{ "execution_status" => "not_applicable",
                                                 "outcome_code" => "invented" }]
      )
      stub_const("#{described_class}::DEFINITIONS", broken.freeze)
      expect(catalog.validation_failures).to include("not_applicable_owner:CHK-TI-001")
    end
  end

  describe "identity is derived from content" do
    # "Reuse of a Catalog version or Definition version for changed content is prohibited."
    # Deriving the row identity from the digest makes that structural: changed content is a
    # different identity, which the unique `(definition_id, semantic_version)` key refuses.
    it "gives the same Definition the same identity on every call" do
      definition = catalog.definition("CHK-TI-001")
      expect(catalog.definition_row_id(definition)).to eq(catalog.definition_row_id(definition))
      expect(catalog.definition_digest(definition).bytesize).to eq(32)
    end

    it "gives changed content a different digest and therefore a different identity" do
      original = catalog.definition("CHK-CQ-001")
      changed = original.merge("impact" => { "meta_title_missing" => { "band" => "high" },
                                             "meta_title_multiple" => { "band" => "low" } })
      expect(catalog.definition_digest(changed)).not_to eq(catalog.definition_digest(original))
      expect(catalog.definition_row_id(changed)).not_to eq(catalog.definition_row_id(original))
    end

    # The Catalog content hash is over every field EXCEPT the content hash itself, with
    # membership as the ordered ID/version/digest tuples — so a reordering is a different
    # catalogue, not the same one written differently.
    it "hashes the catalogue over its ordered membership" do
      body = catalog.catalog_body
      expect(body["membership"].map { |m| m["check_definition_id"] }).to eq(catalog::DEFINITION_IDS)
      expect(body).not_to have_key("content_sha256")
      expect(catalog.catalog_digest.bytesize).to eq(32)
    end
  end

  describe "the seeded rows are the transcribed catalogue" do
    let(:connection) { ActiveRecord::Base.connection }

    it "seeded exactly seven Definitions, one Catalog and seven ordered entries" do
      expect(connection.select_value("SELECT count(*) FROM check_definitions").to_i).to eq(7)
      expect(connection.select_value("SELECT count(*) FROM check_catalogs WHERE state='active'").to_i).to eq(1)
      rows = connection.select_all(<<~SQL).to_a
        SELECT ordering, check_definition_id, definition_version, encode(definition_sha256,'hex') AS digest
        FROM check_catalog_entries ORDER BY ordering
      SQL
      expect(rows.map { |r| r["check_definition_id"] }).to eq(catalog::DEFINITION_IDS)
      expect(rows.map { |r| r["ordering"].to_i }).to eq((1..7).to_a)
    end

    # The persisted digest must equal the RECOMPUTED one. This is the assertion that would
    # catch a Definition whose content was edited without a version change: the constant and
    # the row would then disagree, which is exactly `check_catalog_integrity_failure`.
    it "persisted every Definition digest equal to its recomputed digest" do
      catalog::DEFINITIONS.each do |definition|
        stored = connection.select_value(
          "SELECT encode(content_sha256,'hex') FROM check_definitions WHERE definition_id = " \
          "#{connection.quote(definition['check_definition_id'])}"
        )
        expect(stored).to eq(catalog.hex(catalog.definition_digest(definition)))
      end
    end

    # Seeding is an OWNER operation and the suite runs as the runtime role, so the honest
    # assertion is not "re-seeding is a no-op" but "the runtime cannot seed at all". The
    # idempotence itself is proved above, by the derived identities: the same content always
    # produces the same row id, and `ON CONFLICT (id) DO NOTHING` then writes nothing.
    it "cannot be seeded from the runtime connection at all" do
      expect { catalog.seed!(connection) }
        .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
    end

    # "Tenant actors cannot create, edit, disable, remap, or reorder a Definition." That is a
    # PRIVILEGE here, not a promise: the runtime role holds SELECT and nothing else, so no
    # tenant code path — permitted or not — can reach a write.
    it "grants the runtime SELECT on the catalogue and no write of any kind" do
      %w[check_definitions check_catalogs check_catalog_entries].each do |table|
        expect(connection.select_value("SELECT has_table_privilege('f1_web','public.#{table}','SELECT')"))
          .to be_truthy
        %w[INSERT UPDATE DELETE].each do |privilege|
          expect(connection.select_value("SELECT has_table_privilege('f1_web','public.#{table}','#{privilege}')"))
            .to be_falsey, "f1_web must not hold #{privilege} on #{table}"
        end
      end
    end
  end
end
