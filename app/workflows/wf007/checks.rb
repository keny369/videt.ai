# frozen_string_literal: true

module Workflows
  module Wf007
    # The seven ratified Check rules, as PURE FUNCTIONS of a frozen applicability entry and
    # its frozen Evidence (SCORE_EVIDENCE_MODEL.md § Mandatory Check Definitions;
    # `check-executor-interim-v1`; CAP-009, CAP-010, CAP-011).
    #
    # NO CHECK MAKES A PROVIDER CALL. EVER. This is product authority, not a performance
    # preference: a Check "MUST NOT perform a network request, provider call, mutable read,
    # clock-dependent query or tenant-policy mutation". Every function in this file takes its
    # entire world as arguments — an Evidence payload and the frozen applicability decision —
    # and returns a value. There is no store, no connection, no clock and no HTTP client in
    # scope, so the prohibition is a property of the code's shape rather than a rule someone
    # has to remember.
    #
    # THE ORDER OF THE BRANCHES IS PART OF THE CONTRACT. Two Definitions state a FIRST-MATCH
    # order in which two branches can both be true, and evaluating them in the other order
    # returns a different, wrong answer:
    #
    #   * CHK-TI-001's ERROR PRECEDES failed and pass. An implementation that evaluates the
    #     absent set before checking coverage reports a PASS on a partial crawl.
    #   * CHK-TR-001 selects `organization_schema_invalid` before `organization_identity_
    #     mismatch`, so a payload with no schema-valid node AND a mismatched name is `invalid`.
    #
    # A HANDLED ERROR IS A TERMINAL RESULT, NOT A FAILURE. Missing, stale, indeterminate or
    # invalid Evidence produces `Outcome.error`, which persists a Result, creates no Issue,
    # makes its pillar insufficient — and does NOT fail the Evaluation. The boundary failures
    # that DO fail it (catalog, applicability, tenant integrity, result identity) are decided
    # before this file is ever reached.
    module Checks
      # What a rule returns. `observation` is the Definition's exact normalized observation
      # and is the sole authority for the Result's history — impact mapping and template
      # rendering resolve from it, so a later change elsewhere cannot reinterpret the Result.
      Outcome = Data.define(:execution_status, :outcome_code, :error_reason_code, :observation,
                            :subject_set_complete) do
        def initialize(error_reason_code: nil, subject_set_complete: false, **) = super
        def error? = execution_status == "error"
        def failed? = execution_status == "failed"
      end

      module_function

      def passed(code, observation, complete: true)
        Outcome.new(execution_status: "passed", outcome_code: code, observation:,
                    subject_set_complete: complete)
      end

      def failed(code, observation, complete: true)
        Outcome.new(execution_status: "failed", outcome_code: code, observation:,
                    subject_set_complete: complete)
      end

      # `subject_set_complete` is FALSE for every error, without exception: an error means the
      # selected evidence did not prove complete coverage for that selector instance.
      def error(code, reason, observation)
        Outcome.new(execution_status: "error", outcome_code: code, error_reason_code: reason,
                    observation:, subject_set_complete: false)
      end

      def not_applicable(code, observation)
        # "A `not_applicable` Local Presence result has TRUE subject-set completeness for its
        # inapplicable Project selector" — the selector was fully resolved; it simply selected
        # nothing to observe.
        Outcome.new(execution_status: "not_applicable", outcome_code: code, observation:,
                    subject_set_complete: true)
      end

      # =====================================================================================
      # CHK-TI-001 Internal Link Resolution
      # =====================================================================================
      #
      # `error/internal_link_coverage_incomplete` with `input_evidence_indeterminate` when
      # relevant coverage is partial OR any target is unobserved; `failed/broken_internal_links`
      # when coverage is full and one or more targets are absent; `passed/internal_links_resolve`
      # when coverage is full, every target is reachable and the absent set is empty.
      def chk_ti_001(payload:, source_id:)
        return missing("internal_link_coverage_incomplete") if payload.nil?

        invalid = link_payload_invalid(payload)
        return error("internal_link_coverage_incomplete", "input_evidence_invalid", { "invalid" => invalid }) if invalid

        targets = Array(payload["targets"])
        absent = targets.select { |t| t["terminal_status"] == "absent" }
        unobserved = targets.select { |t| t["terminal_status"] == "unobserved" }
        observation = {
          "source_id" => source_id,
          "canonical_root" => payload["canonical_root"],
          "total_target_count" => targets.length,
          "reachable_count" => targets.count { |t| t["terminal_status"] == "reachable" },
          "absent_count" => absent.length,
          "unobserved_count" => unobserved.length,
          "absent_target_keys" => absent.map { |t| t["canonical_url"] },
          "absent_targets" => absent.map do |t|
            { "canonical_url" => t["canonical_url"], "referrers" => t["referrers"] }
          end
        }

        # THE ERROR IS EVALUATED FIRST. Reordering these two lines is the defect the contract
        # names: it reports a pass over a set the run did not finish observing.
        if payload["relevant_coverage"] != "full" || unobserved.any?
          return error("internal_link_coverage_incomplete", "input_evidence_indeterminate", observation)
        end
        return failed("broken_internal_links", observation) if absent.any?

        passed("internal_links_resolve", observation)
      end

      # "Duplicate target URLs or referrer tuples, a target outside frozen Source Scope, an
      # inconsistent status/reason pair and noncanonical ordering" — five conditions, each
      # invalidating the payload. Scope is proved by the producer (the parser canonicalizes
      # through the same frozen predicate the frontier admitted URLs with), so the four that
      # remain observable from the payload alone are checked here.
      def link_payload_invalid(payload)
        targets = Array(payload["targets"])
        urls = targets.map { |t| t["canonical_url"] }
        return "duplicate_target" if urls.uniq.length != urls.length
        return "noncanonical_order" if urls.map(&:b) != urls.map(&:b).sort

        targets.each do |target|
          status = target["terminal_status"]
          reason = target["reason"]
          return "status_reason_inconsistent" unless admitted_reasons(status).include?(reason)

          tuples = Array(target["referrers"]).map { |r| r.values_at("document_id", "canonical_referring_url", "link_position") }
          return "duplicate_referrer" if tuples.uniq.length != tuples.length
        end
        nil
      end

      # The reasons each terminal status admits. The binding is the contract's: `reachable`
      # REQUIRES `document_valid`, `absent` REQUIRES `content_absent`, and every other reason
      # REQUIRES `unobserved`. A pair that disagrees invalidates the payload rather than being
      # read generously, because a target claimed reachable on a `content_absent` observation
      # would turn a broken link into a passing one.
      def admitted_reasons(status)
        case status
        when "reachable" then ["document_valid"]
        when "absent" then ["content_absent"]
        else %w[fetch_failed limit_discarded parse_omitted]
        end
      end

      # =====================================================================================
      # CHK-CQ-001 Meta-title Presence And Singularity
      # =====================================================================================
      #
      # Zero nonblank normalized titles is `failed/meta_title_missing`; exactly one is
      # `passed/meta_title_present`; two or more is `failed/meta_title_multiple`.
      def chk_cq_001(payload:, canonical_url:)
        return missing("meta_title_missing") if payload.nil?

        nodes = Array(payload["title_nodes"])
        positions = nodes.map { |n| n["position"] }
        if positions != (0...nodes.length).to_a || nodes.any? { |n| n["locator"].to_s.strip.empty? }
          return error("meta_title_missing", "input_evidence_invalid",
                       { "canonical_url" => canonical_url, "invalid" => "unresolved_locator_or_position" })
        end

        # BLANK NORMALIZED VALUES REMAIN IN THE NODE LIST and are counted as nodes, not as
        # titles. `title_node_count` and `nonblank_title_count` are therefore different
        # numbers, and collapsing them would make an empty <title> indistinguishable from a
        # page with no <title> at all.
        nonblank = nodes.reject { |n| n["normalized_title"].to_s.empty? }
        observation = {
          "canonical_url" => canonical_url,
          "title_node_count" => nodes.length,
          "nonblank_title_count" => nonblank.length,
          "title_nodes" => nodes.map do |n|
            { "position" => n["position"], "locator" => n["locator"],
              "normalized_title" => n["normalized_title"].to_s }
          end
        }

        return failed("meta_title_missing", observation) if nonblank.empty?
        return passed("meta_title_present", observation) if nonblank.length == 1

        failed("meta_title_multiple", observation)
      end

      # =====================================================================================
      # CHK-TR-001 Structured Organization Identity
      # =====================================================================================
      #
      # First-match: zero nodes -> `failed/organization_schema_missing`; at least one node
      # schema-valid AND exactly matching -> `passed/organization_identity_consistent`; no
      # node schema-valid -> `failed/organization_schema_invalid`; otherwise
      # `failed/organization_identity_mismatch`.
      def chk_tr_001(payload:, source_id:)
        return missing("organization_schema_missing") if payload.nil?

        invalid = identity_payload_invalid(payload)
        if invalid
          return error("organization_schema_missing", "input_evidence_invalid",
                       { "source_id" => source_id, "invalid" => invalid })
        end

        nodes = Array(payload["organization_nodes"])
        expected_name = fold(payload["expected_public_name"])
        expected_url = payload["expected_public_url"].to_s
        valid_nodes = nodes.select { |n| n["schema_valid"] == true }
        # A valid MATCHING node needs `schema_valid=true` AND both normalized values equal to
        # the expected values. Both clauses matter independently: a schema-valid node with the
        # wrong name is a mismatch, and a matching name on a malformed node is not a match.
        matching = valid_nodes.select do |n|
          fold(n["normalized_public_name"]) == expected_name && n["canonical_url"].to_s == expected_url
        end

        observation = {
          "source_id" => source_id,
          "canonical_root" => payload["canonical_root_url"],
          "public_identity_profile_id" => payload["public_identity_profile_id"],
          "public_identity_profile_version" => payload["public_identity_profile_version"],
          "node_count" => nodes.length,
          "valid_node_count" => valid_nodes.length,
          "matching_node_count" => matching.length,
          "nodes" => nodes.each_with_index.map do |n, index|
            { "position" => n["position"] || index, "locator" => n["locator"],
              "schema_valid" => n["schema_valid"] == true,
              "name_matches" => fold(n["normalized_public_name"]) == expected_name,
              "url_matches" => n["canonical_url"].to_s == expected_url }
          end
        }

        # ZERO OBSERVED NODES IS A VALID OBSERVATION, not an invalid payload: the page simply
        # published no Organization node, which is exactly what this Check exists to find.
        return failed("organization_schema_missing", observation) if nodes.empty?
        return passed("organization_identity_consistent", observation) if matching.any?
        return failed("organization_schema_invalid", observation) if valid_nodes.empty?

        failed("organization_identity_mismatch", observation)
      end

      # "Missing expected identity or profile values, an ambiguous profile version, an invalid
      # locator, or inconsistent normalization invalidates the payload."
      def identity_payload_invalid(payload)
        return "expected_identity_missing" if payload["expected_public_name"].to_s.strip.empty? ||
                                              payload["expected_public_url"].to_s.strip.empty?
        return "profile_version_ambiguous" if payload["public_identity_profile_version"].to_s.strip.empty?
        return "invalid_locator" if Array(payload["organization_nodes"]).any? { |n| n["locator"].to_s.strip.empty? }

        nil
      end

      # "Unicode 15.1 default full case folding FOR COMPARISON" — Ruby's `String#downcase(:fold)`
      # is that folding. It is applied here, at comparison, and never to the retained value.
      def fold(value) = value.to_s.unicode_normalize(:nfc).downcase(:fold)

      # =====================================================================================
      # CHK-SP-001 Search Index Presence
      # =====================================================================================
      def chk_sp_001(payload:, project_id:)
        return missing("search_presence_gap") if payload.nil?

        items = Array(payload.dig("body", "items"))
        keys = Array(payload.dig("body", "expected_query_keys"))
        indeterminate = measurement_indeterminate(payload, keys, items, "query_key")
        if indeterminate
          return error("search_presence_gap", indeterminate,
                       { "project_id" => project_id, "reason" => indeterminate })
        end

        present = items.select { |i| i["presence_status"] == "present" }
        rate = Policies.rate(present.length, keys.length)
        observation = measurement_header(payload).merge(
          "expected_count" => keys.length, "present_count" => present.length,
          "absent_count" => keys.length - present.length, "presence_rate" => rate,
          "absent_query_keys" => items.reject { |i| i["presence_status"] == "present" }
                                      .map { |i| i["query_key"] }.sort_by(&:b)
        )
        return passed("search_presence_complete", observation) if rate == "1.0000"

        failed("search_presence_gap", observation)
      end

      # =====================================================================================
      # CHK-AIP-001 AI Answer Presence
      # =====================================================================================
      def chk_aip_001(payload:, project_id:)
        return missing("ai_answer_presence_gap") if payload.nil?

        items = Array(payload.dig("body", "items"))
        keys = Array(payload.dig("body", "expected_intent_keys"))
        indeterminate = measurement_indeterminate(payload, keys, items, "intent_key")
        if indeterminate
          return error("ai_answer_presence_gap", indeterminate,
                       { "project_id" => project_id, "reason" => indeterminate })
        end

        # A QUALIFIED item is present, cited AND has at least one entity key. All three, which
        # is why "present but not cited" is unqualified rather than a partial credit.
        qualified = items.select do |i|
          i["presence_status"] == "present" && i["citation_status"] == "cited" &&
            Array(i["entity_keys"]).any?
        end
        rate = Policies.rate(qualified.length, keys.length)
        observation = measurement_header(payload).merge(
          "expected_count" => keys.length, "qualified_count" => qualified.length,
          "unqualified_count" => keys.length - qualified.length, "qualified_rate" => rate,
          "unqualified_intent_keys" => (items - qualified).map do |i|
            { "intent_key" => i["intent_key"], "presence_status" => i["presence_status"],
              "citation_status" => i["citation_status"] }
          end.sort_by { |i| i["intent_key"].b }
        )
        return passed("ai_answer_presence_complete", observation) if rate == "1.0000"

        failed("ai_answer_presence_gap", observation)
      end

      # =====================================================================================
      # CHK-AS-001 Attributable Authority Reference
      # =====================================================================================
      def chk_as_001(payload:, project_id:)
        return missing("authority_reference_absent") if payload.nil?

        references = Array(payload.dig("body", "references"))
        tuples = references.map { |r| r.values_at("canonical_referrer", "reference_type", "canonical_target", "observation_key") }
        if tuples.uniq.length != tuples.length
          return error("authority_reference_absent", "input_evidence_invalid",
                       { "project_id" => project_id, "reason" => "duplicate_reference_tuple" })
        end
        if payload["coverage_status"] != "complete" ||
           references.any? { |r| r["attribution_status"] == "indeterminate" }
          return error("authority_reference_absent", "input_evidence_indeterminate",
                       { "project_id" => project_id, "reason" => "coverage_indeterminate" })
        end

        attributable = references.select { |r| r["attribution_status"] == "attributable" }
        observation = measurement_header(payload).merge(
          "backlink_count" => references.count { |r| r["reference_type"] == "backlink" },
          "brand_mention_count" => references.count { |r| r["reference_type"] == "brand_mention" },
          "attributable_count" => attributable.length,
          "nonattributable_count" => references.length - attributable.length,
          "total_count" => references.length,
          "attributable_observation_keys" => attributable.map { |r| r["observation_key"] }.sort_by(&:b)
        )
        # AN EMPTY COMPLETE LIST IS A VALID ZERO-SIGNAL OBSERVATION that FAILS at `medium` —
        # it is not an error. "We looked everywhere and found nothing" is a finding.
        return passed("authority_reference_present", observation) if attributable.any?

        failed("authority_reference_absent", observation)
      end

      # =====================================================================================
      # CHK-LP-001 Local Profile Consistency
      # =====================================================================================
      #
      # The ONE Definition for which `not_applicable` is valid, and only from a VALIDLY FALSE
      # frozen applicability decision carrying its nonblank reason. An absent Project profile
      # is not a valid false decision: it is no decision at all, so the entry stays applicable
      # and reaches its handled error.
      def chk_lp_001(payload:, project_id:, applicable:, profile_version:, inapplicable_reason:)
        unless applicable
          return not_applicable("local_presence_not_applicable",
                                { "project_id" => project_id,
                                  "project_profile_version" => profile_version,
                                  "reason" => inapplicable_reason })
        end
        return missing("local_profiles_absent") if payload.nil?

        keys = Array(payload.dig("body", "required_listing_keys"))
        items = Array(payload.dig("body", "items"))
        indeterminate = measurement_indeterminate(payload, keys, items, "listing_key")
        if indeterminate
          return error("local_profiles_absent", indeterminate,
                       { "project_id" => project_id, "reason" => indeterminate })
        end

        present = items.select { |i| i["listing_status"] == "present" }
        # A QUALIFIED listing is present with ALL FOUR comparisons `match`.
        qualified = present.select do |i|
          %w[name address telephone service_area].all? { |field| i.dig("comparisons", field) == "match" }
        end
        observation = measurement_header(payload).merge(
          "required_count" => keys.length, "present_count" => present.length,
          "qualified_count" => qualified.length,
          "nonqualified_listing_keys" => (items - qualified).map do |i|
            { "listing_key" => i["listing_key"], "listing_status" => i["listing_status"],
              "comparisons" => i["comparisons"] }
          end.sort_by { |i| i["listing_key"].b }
        )

        return passed("local_profiles_consistent", observation) if qualified.length == keys.length
        return failed("local_profiles_absent", observation) if present.empty?

        failed("local_profile_inconsistent", observation)
      end

      # =====================================================================================
      # shared measurement handling
      # =====================================================================================

      # The exact intake mapping for `external-observation-v1`, in the ratified precedence.
      # Freshness is checked by the applicability seal (it needs the snapshot's sealed time,
      # which a pure Check does not have), so what remains here is coverage and key-set
      # agreement: "partial coverage, ANY indeterminate item, or a KEY-SET MISMATCH produces
      # `input_evidence_indeterminate`".
      def measurement_indeterminate(payload, keys, items, key_field)
        return "input_evidence_indeterminate" if keys.empty?
        return "input_evidence_indeterminate" if payload["coverage_status"] != "complete"
        return "input_evidence_indeterminate" if items.map { |i| i[key_field] } != keys
        return "input_evidence_indeterminate" if items.any? do |i|
          i["presence_status"] == "indeterminate" || i["citation_status"] == "indeterminate" ||
            i["listing_status"] == "indeterminate"
        end

        nil
      end

      def measurement_header(payload)
        {
          "measurement_policy_version" => payload["measurement_policy_version"],
          "collector_adapter_id" => payload["collector_adapter_id"],
          "collector_adapter_version" => payload["collector_adapter_version"],
          "measurement_set_version" => payload["measurement_set_version"]
        }
      end

      # The one-attempt handled error for absent Evidence. Its outcome equals its reason
      # unless the Definition expressly names a narrower domain outcome, which is why the
      # caller passes the Definition's own code.
      #
      # UNDER THE RATIFIED OD-010 BASELINE THIS IS THE APPROVED OUTCOME for CHK-SP-001,
      # CHK-AIP-001, CHK-AS-001 and applicable CHK-LP-001: `external-measurement-v1` bundles
      # no active Measurement Set, so each deterministically selects no Evidence and persists
      # this. It is settled behaviour, not a defect and not a withheld limb.
      def missing(outcome_code)
        error(outcome_code, "input_evidence_missing", { "reason" => "input_evidence_missing" })
      end
    end
  end
end
