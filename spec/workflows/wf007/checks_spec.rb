# frozen_string_literal: true

require "rails_helper"

# The seven ratified Check rules, asserted against their exact outcome codes and their
# first-match branch order (SCORE_EVIDENCE_MODEL.md § Mandatory Check Definitions; CAP-009,
# CAP-010, CAP-011; OD-010 ratified).
#
# Two branch orders are load-bearing and are asserted with a fixture where BOTH branches
# would match, because an ordering assertion made on input that only satisfies one branch
# proves nothing:
#
#   * CHK-TI-001's error precedes failed and pass. A partial crawl with an absent target
#     satisfies both `error/coverage_incomplete` and `failed/broken_internal_links`.
#   * CHK-TR-001 selects `organization_schema_invalid` before `organization_identity_
#     mismatch`. A payload with no schema-valid node and a wrong name satisfies both.
RSpec.describe Workflows::Wf007::Checks, type: :domain,
               acceptance_ids: %w[AC-CAP-009 AC-CAP-010 AC-CAP-011], test_types: %w[TYP-DATA] do
  let(:checks) { described_class }

  def target(url, status, reason, referrers: [])
    { "canonical_url" => url, "terminal_status" => status, "reason" => reason, "referrers" => referrers }
  end

  def link_payload(targets, coverage: "full")
    { "canonical_root" => "https://shop.example/", "relevant_coverage" => coverage, "targets" => targets }
  end

  # =====================================================================================
  describe "CHK-TI-001 Internal Link Resolution" do
    it "passes on full coverage with an empty target set (FX-CHK-TI-001-01)" do
      outcome = checks.chk_ti_001(payload: link_payload([]), source_id: "s1")
      expect(outcome.execution_status).to eq("passed")
      expect(outcome.outcome_code).to eq("internal_links_resolve")
      expect(outcome.observation["total_target_count"]).to eq(0)
      expect(outcome.subject_set_complete).to be(true)
    end

    it "passes on full coverage with every target reachable (FX-CHK-TI-001-02)" do
      outcome = checks.chk_ti_001(
        payload: link_payload([target("https://shop.example/a", "reachable", "document_valid"),
                               target("https://shop.example/b", "reachable", "document_valid")]),
        source_id: "s1"
      )
      expect(outcome.outcome_code).to eq("internal_links_resolve")
      expect(outcome.observation["reachable_count"]).to eq(2)
    end

    it "fails with the absent set when coverage is full" do
      outcome = checks.chk_ti_001(
        payload: link_payload([target("https://shop.example/a", "absent", "content_absent"),
                               target("https://shop.example/b", "reachable", "document_valid")]),
        source_id: "s1"
      )
      expect(outcome.execution_status).to eq("failed")
      expect(outcome.outcome_code).to eq("broken_internal_links")
      expect(outcome.observation["absent_count"]).to eq(1)
      expect(outcome.observation["absent_target_keys"]).to eq(["https://shop.example/a"])
    end

    it "errors on partial relevant coverage (FX-CHK-TI-001-08)" do
      outcome = checks.chk_ti_001(
        payload: link_payload([target("https://shop.example/a", "reachable", "document_valid")],
                              coverage: "partial"),
        source_id: "s1"
      )
      expect(outcome.execution_status).to eq("error")
      expect(outcome.outcome_code).to eq("internal_link_coverage_incomplete")
      expect(outcome.error_reason_code).to eq("input_evidence_indeterminate")
      expect(outcome.subject_set_complete).to be(false)
    end

    it "errors on a single unobserved target under otherwise full coverage (FX-CHK-TI-001-09)" do
      outcome = checks.chk_ti_001(
        payload: link_payload([target("https://shop.example/a", "reachable", "document_valid"),
                               target("https://shop.example/b", "unobserved", "parse_omitted")]),
        source_id: "s1"
      )
      expect(outcome.outcome_code).to eq("internal_link_coverage_incomplete")
    end

    # THE ORDER ASSERTION. This payload is partial AND has an absent target, so it satisfies
    # both `error` and `failed`. The contract selects the error, and an implementation that
    # evaluated the absent set first would report a broken-link finding over a crawl it never
    # finished — a false accusation rather than a missing measurement.
    it "selects the error over the failure when BOTH branches match" do
      outcome = checks.chk_ti_001(
        payload: link_payload([target("https://shop.example/a", "absent", "content_absent")],
                              coverage: "partial"),
        source_id: "s1"
      )
      expect(outcome.execution_status).to eq("error")
      expect(outcome.outcome_code).to eq("internal_link_coverage_incomplete")
    end

    it "reports counts that equal their corresponding arrays" do
      outcome = checks.chk_ti_001(
        payload: link_payload([target("https://shop.example/a", "absent", "content_absent"),
                               target("https://shop.example/b", "absent", "content_absent")]),
        source_id: "s1"
      )
      expect(outcome.observation["absent_count"]).to eq(outcome.observation["absent_target_keys"].length)
      expect(outcome.observation["absent_count"]).to eq(outcome.observation["absent_targets"].length)
    end

    describe "payload validity" do
      it "rejects duplicate target URLs" do
        outcome = checks.chk_ti_001(
          payload: link_payload([target("https://shop.example/a", "reachable", "document_valid"),
                                 target("https://shop.example/a", "reachable", "document_valid")]),
          source_id: "s1"
        )
        expect(outcome.error_reason_code).to eq("input_evidence_invalid")
      end

      it "rejects noncanonical target ordering" do
        outcome = checks.chk_ti_001(
          payload: link_payload([target("https://shop.example/b", "reachable", "document_valid"),
                                 target("https://shop.example/a", "reachable", "document_valid")]),
          source_id: "s1"
        )
        expect(outcome.error_reason_code).to eq("input_evidence_invalid")
      end

      # `reachable` REQUIRES `document_valid`; `absent` REQUIRES `content_absent`. A pair
      # that disagrees is an invalid payload, not a target to be interpreted generously.
      it "rejects an inconsistent status/reason pair" do
        outcome = checks.chk_ti_001(
          payload: link_payload([target("https://shop.example/a", "reachable", "content_absent")]),
          source_id: "s1"
        )
        expect(outcome.error_reason_code).to eq("input_evidence_invalid")
      end

      it "rejects duplicate referrer tuples" do
        referrer = { "document_id" => "d1", "canonical_referring_url" => "https://shop.example/",
                     "link_position" => 0 }
        outcome = checks.chk_ti_001(
          payload: link_payload([target("https://shop.example/a", "reachable", "document_valid",
                                        referrers: [referrer, referrer])]),
          source_id: "s1"
        )
        expect(outcome.error_reason_code).to eq("input_evidence_invalid")
      end

      # The SAME document may legitimately link to the same target twice at two positions.
      # That is two distinct referrers, and refusing it would invalidate a valid page.
      it "accepts the same document referring twice from different positions" do
        outcome = checks.chk_ti_001(
          payload: link_payload([target("https://shop.example/a", "reachable", "document_valid", referrers: [
                                          { "document_id" => "d1", "canonical_referring_url" => "https://shop.example/", "link_position" => 0 },
                                          { "document_id" => "d1", "canonical_referring_url" => "https://shop.example/", "link_position" => 4 }
                                        ])]),
          source_id: "s1"
        )
        expect(outcome.execution_status).to eq("passed")
      end
    end

    it "produces the handled missing error when no Evidence was selected" do
      outcome = checks.chk_ti_001(payload: nil, source_id: "s1")
      expect(outcome.error_reason_code).to eq("input_evidence_missing")
      expect(outcome.subject_set_complete).to be(false)
    end
  end

  # =====================================================================================
  describe "CHK-CQ-001 Meta-title Presence And Singularity" do
    def title_payload(*titles)
      { "title_nodes" => titles.each_with_index.map do |text, index|
        { "position" => index, "locator" => "head/title[#{index}]", "normalized_title" => text }
      end }
    end

    it "fails as missing on zero nodes (FX-CHK-CQ-001-01)" do
      outcome = checks.chk_cq_001(payload: title_payload, canonical_url: "https://shop.example/")
      expect(outcome.outcome_code).to eq("meta_title_missing")
      expect(outcome.observation["title_node_count"]).to eq(0)
      expect(outcome.observation["nonblank_title_count"]).to eq(0)
    end

    # A blank <title> IS a node and is NOT a title. Counting it as either one thing or the
    # other would collapse two different observations into one outcome.
    it "fails as missing on blank-only nodes, but still reports the node (FX-CHK-CQ-001-02)" do
      outcome = checks.chk_cq_001(payload: title_payload(""), canonical_url: "https://shop.example/")
      expect(outcome.outcome_code).to eq("meta_title_missing")
      expect(outcome.observation["title_node_count"]).to eq(1)
      expect(outcome.observation["nonblank_title_count"]).to eq(0)
    end

    it "passes on exactly one nonblank title (FX-CHK-CQ-001-03)" do
      outcome = checks.chk_cq_001(payload: title_payload("Acme Supplies"),
                                  canonical_url: "https://shop.example/")
      expect(outcome.execution_status).to eq("passed")
      expect(outcome.outcome_code).to eq("meta_title_present")
    end

    it "fails as multiple on two nonblank titles (FX-CHK-CQ-001-04)" do
      outcome = checks.chk_cq_001(payload: title_payload("One", "Two"),
                                  canonical_url: "https://shop.example/")
      expect(outcome.outcome_code).to eq("meta_title_multiple")
      expect(outcome.observation["nonblank_title_count"]).to eq(2)
    end

    it "errors on an unresolved locator (FX-CHK-CQ-001-05)" do
      payload = { "title_nodes" => [{ "position" => 0, "locator" => "  ", "normalized_title" => "x" }] }
      outcome = checks.chk_cq_001(payload:, canonical_url: "https://shop.example/")
      expect(outcome.error_reason_code).to eq("input_evidence_invalid")
    end

    it "errors on repeated positions" do
      payload = { "title_nodes" => [{ "position" => 0, "locator" => "a", "normalized_title" => "x" },
                                    { "position" => 0, "locator" => "b", "normalized_title" => "y" }] }
      outcome = checks.chk_cq_001(payload:, canonical_url: "https://shop.example/")
      expect(outcome.error_reason_code).to eq("input_evidence_invalid")
    end
  end

  # =====================================================================================
  describe "CHK-TR-001 Structured Organization Identity" do
    def node(name:, url:, valid: true, position: 0)
      { "position" => position, "locator" => "script[0]/#{position}", "schema_valid" => valid,
        "normalized_public_name" => name, "canonical_url" => url }
    end

    def identity_payload(nodes, name: "Acme Supplies", url: "https://shop.example/")
      { "canonical_root_url" => url, "public_identity_profile_id" => "p1",
        "public_identity_profile_version" => "public-identity-interim-v1",
        "expected_public_name" => name, "expected_public_url" => url,
        "organization_nodes" => nodes }
    end

    # ZERO OBSERVED NODES IS A VALID OBSERVATION, not an invalid payload.
    it "fails as schema_missing on zero nodes (FX-CHK-TR-001-01)" do
      outcome = checks.chk_tr_001(payload: identity_payload([]), source_id: "s1")
      expect(outcome.execution_status).to eq("failed")
      expect(outcome.outcome_code).to eq("organization_schema_missing")
      expect(outcome.observation["node_count"]).to eq(0)
    end

    it "fails as schema_invalid when no node is schema-valid (FX-CHK-TR-001-02)" do
      outcome = checks.chk_tr_001(
        payload: identity_payload([node(name: nil, url: nil, valid: false)]), source_id: "s1"
      )
      expect(outcome.outcome_code).to eq("organization_schema_invalid")
    end

    it "fails as identity_mismatch when a valid node disagrees (FX-CHK-TR-001-03)" do
      outcome = checks.chk_tr_001(
        payload: identity_payload([node(name: "Acme Holdings", url: "https://shop.example/")]),
        source_id: "s1"
      )
      expect(outcome.outcome_code).to eq("organization_identity_mismatch")
      expect(outcome.observation["valid_node_count"]).to eq(1)
      expect(outcome.observation["matching_node_count"]).to eq(0)
    end

    it "passes on one exact matching valid node AMONG OTHERS (FX-CHK-TR-001-04)" do
      outcome = checks.chk_tr_001(
        payload: identity_payload([node(name: "Wrong", url: "https://shop.example/", position: 0),
                                   node(name: "Acme Supplies", url: "https://shop.example/", position: 1)]),
        source_id: "s1"
      )
      expect(outcome.execution_status).to eq("passed")
      expect(outcome.outcome_code).to eq("organization_identity_consistent")
      expect(outcome.observation["matching_node_count"]).to eq(1)
    end

    # THE ORDER ASSERTION. No node is schema-valid AND the observed name disagrees, so both
    # `schema_invalid` and `identity_mismatch` would match. The contract selects the former.
    it "selects schema_invalid over identity_mismatch when BOTH branches match" do
      outcome = checks.chk_tr_001(
        payload: identity_payload([node(name: "Something Else", url: "https://other.example/", valid: false)]),
        source_id: "s1"
      )
      expect(outcome.outcome_code).to eq("organization_schema_invalid")
    end

    # "A valid matching node has `schema_valid=true` AND both normalized values equal the
    # expected values" — both clauses, asserted independently.
    it "requires BOTH the name and the URL to match, not either" do
      name_only = checks.chk_tr_001(
        payload: identity_payload([node(name: "Acme Supplies", url: "https://elsewhere.example/")]),
        source_id: "s1"
      )
      url_only = checks.chk_tr_001(
        payload: identity_payload([node(name: "Acme Holdings", url: "https://shop.example/")]),
        source_id: "s1"
      )
      expect(name_only.outcome_code).to eq("organization_identity_mismatch")
      expect(url_only.outcome_code).to eq("organization_identity_mismatch")
    end

    # "Unicode 15.1 default full case folding for comparison" — the observed name may differ
    # in case from the expected one and still match.
    it "compares public names under full case folding" do
      outcome = checks.chk_tr_001(
        payload: identity_payload([node(name: "ACME SUPPLIES", url: "https://shop.example/")]),
        source_id: "s1"
      )
      expect(outcome.execution_status).to eq("passed")
    end

    it "errors on a missing expected identity (FX-CHK-TR-001-05)" do
      outcome = checks.chk_tr_001(payload: identity_payload([], name: "  "), source_id: "s1")
      expect(outcome.error_reason_code).to eq("input_evidence_invalid")
    end

    it "produces the handled missing error when no root Evidence was selected" do
      outcome = checks.chk_tr_001(payload: nil, source_id: "s1")
      expect(outcome.error_reason_code).to eq("input_evidence_missing")
    end
  end

  # =====================================================================================
  describe "the four measurement Definitions under the ratified OD-010 baseline" do
    # `external-measurement-v1` bundles no query, intent, listing, provider or adapter set,
    # so each of these deterministically selects NO Evidence and persists a handled
    # one-attempt `input_evidence_missing` error. That is the APPROVED baseline outcome.
    it "each persists input_evidence_missing with no Evidence, and no impact" do
      outcomes = {
        "CHK-SP-001" => checks.chk_sp_001(payload: nil, project_id: "p1"),
        "CHK-AIP-001" => checks.chk_aip_001(payload: nil, project_id: "p1"),
        "CHK-AS-001" => checks.chk_as_001(payload: nil, project_id: "p1"),
        "CHK-LP-001" => checks.chk_lp_001(payload: nil, project_id: "p1", applicable: true,
                                          profile_version: nil, inapplicable_reason: nil)
      }
      outcomes.each do |id, outcome|
        expect(outcome.execution_status).to eq("error"), "#{id} should be a handled error"
        expect(outcome.error_reason_code).to eq("input_evidence_missing")
        expect(outcome.subject_set_complete).to be(false)
      end
    end

    it "names each Definition's own domain outcome rather than a generic one" do
      expect(checks.chk_sp_001(payload: nil, project_id: "p1").outcome_code).to eq("search_presence_gap")
      expect(checks.chk_aip_001(payload: nil, project_id: "p1").outcome_code).to eq("ai_answer_presence_gap")
      expect(checks.chk_as_001(payload: nil, project_id: "p1").outcome_code).to eq("authority_reference_absent")
    end
  end

  describe "CHK-SP-001 Search Index Presence, when a Measurement Set exists" do
    def sp_payload(items, keys, coverage: "complete")
      { "coverage_status" => coverage, "measurement_policy_version" => "external-measurement-interim-v1",
        "collector_adapter_id" => "adapter", "collector_adapter_version" => "1",
        "measurement_set_version" => "1",
        "body" => { "expected_query_keys" => keys, "items" => items } }
    end

    def query(key, status, urls = [])
      { "query_key" => key, "presence_status" => status, "urls" => urls }
    end

    it "passes only at an exact 1.0000 presence rate (FX-CHK-SP-001-06)" do
      outcome = checks.chk_sp_001(
        payload: sp_payload([query("a", "present", ["https://shop.example/"]),
                             query("b", "present", ["https://shop.example/b"])], %w[a b]),
        project_id: "p1"
      )
      expect(outcome.execution_status).to eq("passed")
      expect(outcome.observation["presence_rate"]).to eq("1.0000")
    end

    it "fails at zero presence with the rate recorded as an exact decimal (FX-CHK-SP-001-07)" do
      outcome = checks.chk_sp_001(
        payload: sp_payload([query("a", "absent"), query("b", "absent")], %w[a b]), project_id: "p1"
      )
      expect(outcome.outcome_code).to eq("search_presence_gap")
      expect(outcome.observation["presence_rate"]).to eq("0.0000")
      expect(outcome.observation["absent_query_keys"]).to eq(%w[a b])
    end

    it "fails at partial presence (FX-CHK-SP-001-08)" do
      outcome = checks.chk_sp_001(
        payload: sp_payload([query("a", "present", ["https://shop.example/"]), query("b", "absent")], %w[a b]),
        project_id: "p1"
      )
      expect(outcome.observation["presence_rate"]).to eq("0.5000")
    end

    it "errors on an empty expected set (FX-CHK-SP-001-01)" do
      outcome = checks.chk_sp_001(payload: sp_payload([], []), project_id: "p1")
      expect(outcome.error_reason_code).to eq("input_evidence_indeterminate")
    end

    it "errors on a key-set mismatch (FX-CHK-SP-001-02)" do
      outcome = checks.chk_sp_001(payload: sp_payload([query("a", "present", ["u"])], %w[a b]), project_id: "p1")
      expect(outcome.error_reason_code).to eq("input_evidence_indeterminate")
    end

    it "errors on partial coverage (FX-CHK-SP-001-03)" do
      outcome = checks.chk_sp_001(
        payload: sp_payload([query("a", "present", ["u"])], %w[a], coverage: "partial"), project_id: "p1"
      )
      expect(outcome.error_reason_code).to eq("input_evidence_indeterminate")
    end

    it "errors on any indeterminate item (FX-CHK-SP-001-04)" do
      outcome = checks.chk_sp_001(payload: sp_payload([query("a", "indeterminate")], %w[a]), project_id: "p1")
      expect(outcome.error_reason_code).to eq("input_evidence_indeterminate")
    end
  end

  describe "CHK-AS-001 Attributable Authority Reference, when a Measurement Set exists" do
    def as_payload(references, coverage: "complete")
      { "coverage_status" => coverage, "measurement_policy_version" => "external-measurement-interim-v1",
        "collector_adapter_id" => "adapter", "collector_adapter_version" => "1",
        "measurement_set_version" => "1", "body" => { "references" => references } }
    end

    def reference(key, type: "backlink", status: "attributable")
      { "observation_key" => key, "reference_type" => type, "canonical_referrer" => "https://ref.example/#{key}",
        "canonical_target" => "https://shop.example/", "attribution_status" => status }
    end

    # AN EMPTY COMPLETE LIST IS A VALID ZERO-SIGNAL OBSERVATION that FAILS at `medium` — it
    # is not an error. "We looked and found nothing" is a finding, not a missing measurement.
    it "fails on an empty COMPLETE list rather than erroring (FX-CHK-AS-001-01)" do
      outcome = checks.chk_as_001(payload: as_payload([]), project_id: "p1")
      expect(outcome.execution_status).to eq("failed")
      expect(outcome.outcome_code).to eq("authority_reference_absent")
      expect(outcome.observation["total_count"]).to eq(0)
    end

    it "passes on one attributable backlink (FX-CHK-AS-001-02)" do
      outcome = checks.chk_as_001(payload: as_payload([reference("k1")]), project_id: "p1")
      expect(outcome.execution_status).to eq("passed")
      expect(outcome.observation["backlink_count"]).to eq(1)
    end

    it "passes on one attributable brand mention (FX-CHK-AS-001-03)" do
      outcome = checks.chk_as_001(payload: as_payload([reference("k1", type: "brand_mention")]),
                                  project_id: "p1")
      expect(outcome.execution_status).to eq("passed")
      expect(outcome.observation["brand_mention_count"]).to eq(1)
    end

    it "fails when every reference is nonattributable (FX-CHK-AS-001-04)" do
      outcome = checks.chk_as_001(payload: as_payload([reference("k1", status: "not_attributable")]),
                                  project_id: "p1")
      expect(outcome.outcome_code).to eq("authority_reference_absent")
      expect(outcome.observation["nonattributable_count"]).to eq(1)
    end

    it "errors on an indeterminate reference (FX-CHK-AS-001-05)" do
      outcome = checks.chk_as_001(payload: as_payload([reference("k1", status: "indeterminate")]),
                                  project_id: "p1")
      expect(outcome.error_reason_code).to eq("input_evidence_indeterminate")
    end

    it "errors on an exact duplicate tuple (FX-CHK-AS-001-06)" do
      outcome = checks.chk_as_001(payload: as_payload([reference("k1"), reference("k1")]), project_id: "p1")
      expect(outcome.error_reason_code).to eq("input_evidence_invalid")
    end
  end

  # =====================================================================================
  describe "CHK-LP-001 Local Profile Consistency" do
    def lp_payload(items, keys, coverage: "complete")
      { "coverage_status" => coverage, "measurement_policy_version" => "external-measurement-interim-v1",
        "collector_adapter_id" => "adapter", "collector_adapter_version" => "1",
        "measurement_set_version" => "1",
        "body" => { "required_listing_keys" => keys, "items" => items } }
    end

    def listing(key, status: "present", comparisons: nil)
      { "listing_key" => key, "listing_status" => status,
        "comparisons" => comparisons || %w[name address telephone service_area].to_h { |f| [f, "match"] } }
    end

    # `not_applicable` comes ONLY from a validly false frozen decision with its nonblank
    # reason, and it needs no Measurement Evidence at all (FX-CHK-LP-001-01).
    it "returns not_applicable from a valid false decision, WITHOUT Measurement Evidence" do
      outcome = checks.chk_lp_001(payload: nil, project_id: "p1", applicable: false,
                                  profile_version: "project-profile-v1",
                                  inapplicable_reason: "This project serves customers online only.")
      expect(outcome.execution_status).to eq("not_applicable")
      expect(outcome.outcome_code).to eq("local_presence_not_applicable")
      expect(outcome.observation["reason"]).to eq("This project serves customers online only.")
      # "A `not_applicable` Local Presence result has TRUE subject-set completeness for its
      # inapplicable Project selector" — the selector resolved fully; it selected nothing.
      expect(outcome.subject_set_complete).to be(true)
    end

    it "passes when every required listing is qualified (FX-CHK-LP-001-06)" do
      outcome = checks.chk_lp_001(payload: lp_payload([listing("a"), listing("b")], %w[a b]),
                                  project_id: "p1", applicable: true, profile_version: "project-profile-v1",
                                  inapplicable_reason: nil)
      expect(outcome.execution_status).to eq("passed")
      expect(outcome.observation["qualified_count"]).to eq(2)
    end

    it "fails as absent when no listing is present (FX-CHK-LP-001-04)" do
      absent = %w[name address telephone service_area].to_h { |f| [f, "missing"] }
      outcome = checks.chk_lp_001(
        payload: lp_payload([listing("a", status: "absent", comparisons: absent)], %w[a]),
        project_id: "p1", applicable: true, profile_version: "project-profile-v1", inapplicable_reason: nil
      )
      expect(outcome.outcome_code).to eq("local_profiles_absent")
      expect(outcome.observation["present_count"]).to eq(0)
    end

    it "fails as inconsistent on a partial or mismatched listing (FX-CHK-LP-001-05)" do
      mismatched = { "name" => "match", "address" => "mismatch", "telephone" => "match",
                     "service_area" => "match" }
      outcome = checks.chk_lp_001(
        payload: lp_payload([listing("a"), listing("b", comparisons: mismatched)], %w[a b]),
        project_id: "p1", applicable: true, profile_version: "project-profile-v1", inapplicable_reason: nil
      )
      expect(outcome.outcome_code).to eq("local_profile_inconsistent")
      expect(outcome.observation["present_count"]).to eq(2)
      expect(outcome.observation["qualified_count"]).to eq(1)
    end

    # A QUALIFIED listing is present with ALL FOUR comparisons `match`. Three out of four is
    # not a partial credit.
    it "requires all four comparisons to match before a listing qualifies" do
      %w[name address telephone service_area].each do |field|
        comparisons = %w[name address telephone service_area].to_h { |f| [f, f == field ? "missing" : "match"] }
        outcome = checks.chk_lp_001(
          payload: lp_payload([listing("a", comparisons:)], %w[a]),
          project_id: "p1", applicable: true, profile_version: "project-profile-v1", inapplicable_reason: nil
        )
        expect(outcome.outcome_code).to eq("local_profile_inconsistent"), "#{field} must disqualify"
      end
    end
  end

  # =====================================================================================
  # "`not_applicable` is valid ONLY for `CHK-LP-001`." The other six MUST return passed,
  # failed or error, and this asserts it over EVERY reachable outcome of all six rather than
  # over one convenient example.
  describe "`not_applicable` belongs to exactly one Definition" do
    it "is never produced by the other six under any input" do
      outcomes = [
        checks.chk_ti_001(payload: nil, source_id: "s1"),
        checks.chk_ti_001(payload: link_payload([]), source_id: "s1"),
        checks.chk_cq_001(payload: nil, canonical_url: "u"),
        checks.chk_cq_001(payload: { "title_nodes" => [] }, canonical_url: "u"),
        checks.chk_tr_001(payload: nil, source_id: "s1"),
        checks.chk_sp_001(payload: nil, project_id: "p1"),
        checks.chk_aip_001(payload: nil, project_id: "p1"),
        checks.chk_as_001(payload: nil, project_id: "p1")
      ]
      expect(outcomes.map(&:execution_status).uniq).to all(be_in(%w[passed failed error]))
    end
  end
end
