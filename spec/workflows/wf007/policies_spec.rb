# frozen_string_literal: true

require "rails_helper"

# The impact, effort and confidence policies, asserted AT EACH BOUNDARY AND ONE EITHER SIDE
# (SCORE_EVIDENCE_MODEL.md § Interim Confidence Policy, § Interim Effort Policy, and each
# Definition's impact rule; PRULE-012; OD-003 and OD-010 both ratified).
#
# A boundary asserted only at its midpoint passes with an off-by-one comparison, which is
# precisely the defect that silently reclassifies a `high` impact as `medium` on the one
# site that sits on the edge. Every threshold below is checked at the boundary value, at
# the value immediately beneath it, and at the value immediately above.
RSpec.describe Workflows::Wf007::Policies, type: :domain,
               acceptance_ids: %w[AC-PRULE-012 AC-CAP-009], test_types: %w[TYP-DATA] do
  let(:policies) { described_class }
  let(:catalog) { Workflows::Wf007::CheckCatalog }

  def definition(id) = catalog.definition(id)

  describe "confidence-policy-v1 bands" do
    # `low` 0.0000 <= v < 0.6000; `medium` 0.6000 <= v < 0.8500; `high` 0.8500 <= v <= 1.0000.
    it "maps each band at its exact boundary and one either side" do
      expect(policies.confidence_band("0.0000")).to eq("low")
      expect(policies.confidence_band("0.5999")).to eq("low")
      expect(policies.confidence_band("0.6000")).to eq("medium")
      expect(policies.confidence_band("0.6001")).to eq("medium")
      expect(policies.confidence_band("0.8499")).to eq("medium")
      expect(policies.confidence_band("0.8500")).to eq("high")
      expect(policies.confidence_band("1.0000")).to eq("high")
    end

    # "Rounded half up to four decimal places BEFORE band mapping." A value that rounds UP
    # across a boundary must land in the higher band, which is only true if the rounding
    # happens first.
    it "rounds half up before mapping, not after" do
      expect(policies.confidence_band("0.59995")).to eq("medium")
      expect(policies.confidence_band("0.84995")).to eq("high")
      expect(policies.confidence_band("0.599949")).to eq("low")
    end

    it "gives every decided result 1.0000 / valid / high" do
      decided = policies.decided_confidence
      expect(decided["confidence_value"]).to eq("1.0000")
      expect(decided["confidence_status"]).to eq("valid")
      expect(decided["confidence_band"]).to eq("high")
      expect(decided["confidence_policy_version"]).to eq("confidence-policy-v1")
    end

    # "Missing or invalid confidence maps to display band `low` ... the raw invalid value
    # MUST NOT be used downstream" — so the value is null, not zero. A zero would be a
    # usable number and would contribute to a calculation.
    it "gives a handled error a NULL value, missing status and low band" do
      missing = policies.missing_confidence
      expect(missing["confidence_value"]).to be_nil
      expect(missing["confidence_status"]).to eq("missing")
      expect(missing["confidence_band"]).to eq("low")
    end
  end

  describe "impact-CHK-TI-001-v1 absent-target thresholds" do
    def band(count)
      policies.impact_band(definition("CHK-TI-001"), "failed", "broken_internal_links",
                           { "absent_count" => count })
    end

    # FX-CHK-TI-001-03..-07: 1 -> low, 4 -> low, 5 -> medium, 19 -> medium, 20 -> high.
    it "maps 1-4 low, 5-19 medium, 20 or more high, at every boundary" do
      expect(band(1)).to eq("low")
      expect(band(4)).to eq("low")
      expect(band(5)).to eq("medium")
      expect(band(19)).to eq("medium")
      expect(band(20)).to eq("high")
      expect(band(21)).to eq("high")
      expect(band(1000)).to eq("high")
    end

    # Zero absent targets is not a failure at all — it is a pass — so there is no band for
    # it, and the rule refuses rather than defaulting to `low`.
    it "has no band beneath its lowest threshold, and refuses instead of defaulting" do
      expect { band(0) }.to raise_error(described_class::CatalogIntegrityFailure, /unmapped_metric/)
    end
  end

  describe "the constant impact rules" do
    it "maps CHK-CQ-001 missing to medium and multiple to low" do
      cq = definition("CHK-CQ-001")
      expect(policies.impact_band(cq, "failed", "meta_title_missing", {})).to eq("medium")
      expect(policies.impact_band(cq, "failed", "meta_title_multiple", {})).to eq("low")
    end

    it "maps CHK-TR-001 missing and invalid to medium, and identity mismatch to high" do
      tr = definition("CHK-TR-001")
      expect(policies.impact_band(tr, "failed", "organization_schema_missing", {})).to eq("medium")
      expect(policies.impact_band(tr, "failed", "organization_schema_invalid", {})).to eq("medium")
      expect(policies.impact_band(tr, "failed", "organization_identity_mismatch", {})).to eq("high")
    end

    it "maps CHK-AS-001 zero attributable references to medium" do
      expect(policies.impact_band(definition("CHK-AS-001"), "failed", "authority_reference_absent", {}))
        .to eq("medium")
    end

    it "maps CHK-LP-001 all-absent to high and partial or inconsistent to medium" do
      lp = definition("CHK-LP-001")
      expect(policies.impact_band(lp, "failed", "local_profiles_absent", {})).to eq("high")
      expect(policies.impact_band(lp, "failed", "local_profile_inconsistent", {})).to eq("medium")
    end
  end

  describe "the rate impact rules" do
    # Rate exactly `0.0000` is high; `0.0000 < rate < 1.0000` is medium. A rate of 1.0000 is
    # a pass and never reaches an impact band.
    it "maps CHK-SP-001 zero presence to high and partial presence to medium" do
      sp = definition("CHK-SP-001")
      expect(policies.impact_band(sp, "failed", "search_presence_gap", { "presence_rate" => "0.0000" }))
        .to eq("high")
      expect(policies.impact_band(sp, "failed", "search_presence_gap", { "presence_rate" => "0.0001" }))
        .to eq("medium")
      expect(policies.impact_band(sp, "failed", "search_presence_gap", { "presence_rate" => "0.9999" }))
        .to eq("medium")
    end

    it "maps CHK-AIP-001 zero qualified to high and partial to medium" do
      aip = definition("CHK-AIP-001")
      expect(policies.impact_band(aip, "failed", "ai_answer_presence_gap", { "qualified_rate" => "0.0000" }))
        .to eq("high")
      expect(policies.impact_band(aip, "failed", "ai_answer_presence_gap", { "qualified_rate" => "0.5000" }))
        .to eq("medium")
    end
  end

  # "`impact_band` is required for `failed` and null for `passed`, `not_applicable` and
  # `error`." A band on an error would let a Result that decided nothing carry a severity.
  describe "impact exists only for a failure" do
    it "is null for passed, not-applicable and error" do
      ti = definition("CHK-TI-001")
      expect(policies.impact_band(ti, "passed", "internal_links_resolve", {})).to be_nil
      expect(policies.impact_band(ti, "error", "internal_link_coverage_incomplete", {})).to be_nil
      expect(policies.impact_band(definition("CHK-LP-001"), "not_applicable",
                                  "local_presence_not_applicable", {})).to be_nil
    end

    # An unmapped failed outcome discovered after activation fails the Evaluation; it does
    # not silently downgrade the outcome to `informational`.
    it "raises on an unmapped failed outcome rather than downgrading it" do
      expect { policies.impact_band(definition("CHK-CQ-001"), "failed", "invented_outcome", {}) }
        .to raise_error(described_class::CatalogIntegrityFailure, /unmapped_failed_outcome/)
    end
  end

  describe "effort-interim-v1" do
    # "`CHK-TI-001` uses `low` for one through four absent targets, `medium` for five through
    # nineteen, and `high` for twenty or more. `CHK-CQ-001` uses `low`. `CHK-TR-001`,
    # `CHK-SP-001`, and `CHK-LP-001` use `medium`. `CHK-AIP-001` and `CHK-AS-001` use `high`."
    it "maps CHK-TI-001 effort on the same boundaries as its impact" do
      ti = definition("CHK-TI-001")
      expect(policies.effort(ti, "failed", "broken_internal_links",
                             { "absent_count" => 4 })["effort_band"]).to eq("low")
      expect(policies.effort(ti, "failed", "broken_internal_links",
                             { "absent_count" => 5 })["effort_band"]).to eq("medium")
      expect(policies.effort(ti, "failed", "broken_internal_links",
                             { "absent_count" => 20 })["effort_band"]).to eq("high")
    end

    it "maps the constant efforts of the other six Definitions" do
      expected = { "CHK-CQ-001" => %w[meta_title_missing low],
                   "CHK-TR-001" => %w[organization_schema_missing medium],
                   "CHK-SP-001" => %w[search_presence_gap medium],
                   "CHK-AIP-001" => %w[ai_answer_presence_gap high],
                   "CHK-AS-001" => %w[authority_reference_absent high],
                   "CHK-LP-001" => %w[local_profiles_absent medium] }
      expected.each do |id, (outcome, band)|
        expect(policies.effort(definition(id), "failed", outcome, {})["effort_band"]).to eq(band),
                                                                                        "#{id}/#{outcome} should be #{band}"
      end
    end

    # "The persisted `effort_basis` is exactly
    # `effort-interim-v1:<check_definition_id>:<outcome_code>:<matched-rule>`."
    it "records the exact effort basis string" do
      basis = policies.effort(definition("CHK-CQ-001"), "failed", "meta_title_missing", {})["effort_basis"]
      expect(basis).to eq("effort-interim-v1:CHK-CQ-001:meta_title_missing:constant_low")

      threshold = policies.effort(definition("CHK-TI-001"), "failed", "broken_internal_links",
                                  { "absent_count" => 7 })["effort_basis"]
      expect(threshold).to eq("effort-interim-v1:CHK-TI-001:broken_internal_links:absent_count_medium")
    end

    # "An unlisted failed outcome is `effort_policy_unavailable` and blocks Recommendation
    # publication and Priority Decision creation WITHOUT changing the Issue or the score." So
    # it returns a null band with its basis recorded — it does not raise, and it does not
    # invent an effort.
    it "records effort_policy_unavailable for an unlisted failed outcome without raising" do
      result = policies.effort(definition("CHK-AS-001"), "failed", "not_in_the_policy", {})
      expect(result["effort_band"]).to be_nil
      expect(result["effort_basis"]).to eq("effort-interim-v1:CHK-AS-001:not_in_the_policy:effort_policy_unavailable")
    end

    it "has no effort for a passed, not-applicable or error result" do
      expect(policies.effort(definition("CHK-TI-001"), "passed", "internal_links_resolve", {}))
        .to eq({ "effort_band" => nil, "effort_basis" => nil })
    end
  end

  describe "decimal arithmetic is base-10" do
    # "All decimal calculations use base-10 decimal arithmetic. Binary floating-point output
    # MUST NOT determine a persisted score." A rate is an exact four-place decimal STRING,
    # which is also what canonical JSON requires, since it forbids floats outright.
    it "renders every rate as an exact four-place decimal string" do
      expect(policies.rate(1, 3)).to eq("0.3333")
      expect(policies.rate(2, 3)).to eq("0.6667")
      expect(policies.rate(1, 1)).to eq("1.0000")
      expect(policies.rate(0, 5)).to eq("0.0000")
      expect(policies.rate(1, 8)).to eq("0.1250")
    end

    it "rounds half up at the fourth place" do
      expect(policies.rate(1, 16)).to eq("0.0625")
      expect(policies.rate(5, 8)).to eq("0.6250")
      # 1/6 = 0.16666... -> 0.1667 under half-up at four places.
      expect(policies.rate(1, 6)).to eq("0.1667")
    end

    it "treats an empty expected set as a zero rate rather than dividing by zero" do
      expect(policies.rate(0, 0)).to eq("0.0000")
    end

    # A rate is hashed into the deterministic output, so it must be encodable as canonical
    # JSON. A Float would raise there — which is exactly the protection being asserted.
    it "produces a value canonical JSON accepts" do
      expect { Platform::CanonicalJson.encode({ "rate" => policies.rate(1, 3) }) }.not_to raise_error
      expect { Platform::CanonicalJson.encode({ "rate" => 1.0 / 3 }) }.to raise_error(ArgumentError)
    end
  end
end
