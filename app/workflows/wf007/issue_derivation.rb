# frozen_string_literal: true

require "digest"

module Workflows
  module Wf007
    # WF-007 Primary Path step 4: Issue derivation, `issue-fingerprint-v1`, and the sealed
    # Issue Set (SCORE_EVIDENCE_MODEL.md § Check-To-Issue Rules, § Fingerprint
    # `issue-fingerprint-v1`, § Issue Contract; PRULE-011, PRULE-023; OD-017 **ratified**).
    #
    # FOUR RULES DECIDE WHETHER AN ISSUE EXISTS AT ALL, and three of them are refusals:
    #
    #   * `passed` and `not_applicable` create NO Issue.
    #   * `error` creates NO Issue and contributes to coverage failure — which is why the
    #     ratified OD-010 baseline, where four Definitions error on absent Measurement
    #     Evidence, produces no Issue from them and an insufficient pillar instead.
    #   * `failed` with valid medium or high confidence creates a PUBLISHED, OPEN Issue.
    #   * `failed` with low, missing or invalid confidence creates a WITHHELD CANDIDATE in
    #     `review_required`.
    #
    # And one more that binds every writer regardless of permission (PRULE-011): every Issue,
    # INCLUDING a withheld review candidate, originates from one failed catalog Check Result
    # and references at least one effectively valid same-Organization Evidence record. A
    # failed Result with no valid Evidence creates nothing.
    #
    # THE PREIMAGE IS UNIQUENESS AUTHORITY, THE HASH IS AN INDEX. Within one Evaluation the
    # authority is the full tuple `(evaluation_id, fingerprint_version, fingerprint_preimage)`.
    # Under the ratified OD-017 a same-hash/different-preimage record MUST NOT be created and
    # the Evaluation FAILS CLOSED — detection happens at derivation, BEFORE any Issue write.
    module IssueDerivation
      module_function

      FINGERPRINT_VERSION = "issue-fingerprint-v1"
      ISSUE_SET_SCHEMA = "issue-set-v1"
      ISSUE_SCHEMA = "issue-v1"
      DEDUP_NAMESPACE = "issue-fingerprint-v1"

      # "The fingerprint preimage is canonical JSON containing EXACTLY `organization_id`,
      # `project_id`, `source_id`, `check_definition_id`, `issue_type`,
      # `canonical_subject_type`, `canonical_subject_key`." Exactly those seven: adding the
      # Evaluation would make every reassessment a new Issue instead of a successor, and
      # dropping the subject would merge two pages' findings into one.
      def fingerprint_preimage(organization_id:, project_id:, source_id:, check_definition_id:,
                               issue_type:, canonical_subject_type:, canonical_subject_key:)
        Platform::CanonicalJson.encode(
          "organization_id" => organization_id, "project_id" => project_id, "source_id" => source_id,
          "check_definition_id" => check_definition_id, "issue_type" => issue_type,
          "canonical_subject_type" => canonical_subject_type, "canonical_subject_key" => canonical_subject_key
        ).b
      end

      def fingerprint_digest(preimage) = Digest::SHA256.digest(preimage)

      # The Definition's Issue type for this failed outcome. A failed outcome with no declared
      # Issue type cannot enter an active Catalog, so its absence here is a catalog integrity
      # failure rather than a reason to invent a type.
      def issue_type(definition, outcome_code)
        entry = definition["outcomes"].find do |o|
          o["execution_status"] == "failed" && o["outcome_code"] == outcome_code
        end
        raise Policies::CatalogIntegrityFailure, "unmapped_issue_type:#{outcome_code}" if entry.nil?

        entry["issue_type"]
      end

      # Check-To-Issue Rules, as the two shapes the database also enforces. Valid medium or
      # high confidence publishes; everything else withholds a candidate for review. There is
      # no third shape, and the withheld one is the case a permissive implementation exempts
      # from the Evidence preconditions — so it goes through the identical path.
      def disposition(confidence_status, confidence_band)
        if confidence_status == "valid" && %w[medium high].include?(confidence_band)
          { "state" => "open", "adjudication_status" => "not_required", "publication_status" => "published" }
        else
          { "state" => "candidate", "adjudication_status" => "review_required",
            "publication_status" => "withheld" }
        end
      end

      # An Issue is derivable from a Check Result only when the Result FAILED and at least one
      # of its frozen Evidence references is effectively valid and same-Organization. The
      # predicate reads the FROZEN Validation Decision statuses recorded on the Result, never
      # a live re-read: "a later Decision does not retroactively unmake an existing Issue".
      def derivable?(result, evidences)
        return false unless result["execution_status"] == "failed"

        evidences.any? do |e|
          e["validation_status"] == "valid" && e["organization_id"] == result["organization_id"]
        end
      end

      # ---- the sealed set -------------------------------------------------------------------

      # "Both ordered lists sort by fingerprint preimage, then Issue originating-Evaluation
      # creation time, then Issue ID." Within one Evaluation the middle term is constant, so
      # the ordering reduces to preimage then id — stated in full so a reassessment that adds
      # ancestors keeps the same comparator.
      def order_members(members)
        members.sort_by { |m| [m["fingerprint_preimage"].b, m["created_at"].to_s, m["id"]] }
      end

      # The ordered-membership root: SHA-256 over the canonical ordered list of member
      # identities and their frozen states. It is the hash a later reader re-derives to prove
      # the set has not been re-membered.
      def membership_root(ordered)
        Digest::SHA256.digest(Platform::CanonicalJson.encode(
                                ordered.each_with_index.map do |m, index|
                                  { "ordering" => index + 1, "issue_id" => m["id"],
                                    "current_leaf" => m["current_leaf"],
                                    "frozen_state" => m["state"],
                                    "frozen_state_version" => m["state_version"].to_i }
                                end
                              ))
      end

      def content_body(evaluation_id:, ordered:, root_sha256:)
        {
          "schema_version" => ISSUE_SET_SCHEMA,
          "evaluation_id" => evaluation_id,
          "member_count" => ordered.length,
          "current_leaf_count" => ordered.count { |m| m["current_leaf"] },
          "membership_root_sha256" => root_sha256.unpack1("H*")
        }
      end
    end
  end
end
