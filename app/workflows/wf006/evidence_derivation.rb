# frozen_string_literal: true

require "json"

module Workflows
  module Wf006
    # The three BASELINE PLATFORM-DERIVED EVIDENCE PAYLOADS
    # (SCORE_EVIDENCE_MODEL.md § Baseline Platform-Derived Evidence Payloads).
    #
    # WHY WF-006 OWNS THIS. "Collection is WF-006 intake, owned by S-08; S-09 consumes only
    # frozen Evidence." A Check is a pure evaluation of the frozen applicability entry and
    # its Evidence, and it MUST NOT perform a network request, provider call, mutable read or
    # clock-dependent query — so the observation a Check reads has to have been recorded
    # before the Check existed. This module is that recording: it reads the sealed Parsed
    # Artifacts and the Crawl's own terminal outcomes, and derives the three payloads the
    # ratified Definitions name, on the transaction that seals the Evaluation Input Snapshot.
    #
    # WHAT IT DOES NOT DO. It derives no `external_measurement`. `external-measurement-v1`
    # bundles no query, intent, listing, provider or adapter set, so there is nothing to
    # collect — and OD-010 ratified that state AND its consequence. Manufacturing a query set
    # here to make a score appear would be inventing the artifact's content, which is the one
    # thing the ratified baseline forbids: "no implementation invents a query, intent, listing
    # directory, prompt, provider, threshold or adapter to avoid that outcome."
    #
    # PAYLOAD VALIDITY IS A PRODUCT RULE, NOT A CONVENIENCE. Each builder returns a payload
    # that satisfies its schema's exact validity conditions — canonical ordering, no duplicate
    # keys, consistent status/reason pairs — because the consuming Check treats a violation as
    # `input_evidence_invalid`. Producing a payload the consumer must then reject would move a
    # producer bug into the tenant's results.
    module EvidenceDerivation
      module_function

      PRODUCER = "wf006.evidence_derivation"
      SOURCE_SYSTEM = "f1.evaluation"
      COLLECTOR_VERSION = "parsed-observation-v1"
      EVIDENCE_AAD = { application: "wf006", record_type: "derived_observation",
                       purpose: "product_evidence_payload" }.freeze

      LINK_SCHEMA = "internal-link-observation-v1"
      TITLE_SCHEMA = "document-title-observation-v1"
      IDENTITY_SCHEMA = "organization-identity-observation-v1"
      PUBLIC_IDENTITY_PROFILE_VERSION = "public-identity-interim-v1"

      REACHABLE = "reachable"
      ABSENT = "absent"
      UNOBSERVED = "unobserved"

      # The Crawl's terminal vocabulary mapped onto the target `(status, reason)` pair the
      # payload admits. The contract binds the two: `reachable` REQUIRES `document_valid`,
      # `absent` REQUIRES `content_absent`, and every other reason REQUIRES `unobserved`.
      # This table is that binding written once, so a status and a reason cannot drift apart
      # into the "inconsistent status/reason" the schema calls invalid.
      TARGET_OUTCOME = {
        "document_created" => [REACHABLE, "document_valid"],
        "content_absent" => [ABSENT, "content_absent"],
        "content_fetch_failed" => [UNOBSERVED, "fetch_failed"],
        "limit_discarded" => [UNOBSERVED, "limit_discarded"],
        # A run that stopped on robots never looked at the URL, and `policy_excluded` means
        # scope removed it from the run. Neither is an observation of the target, so both are
        # `unobserved`; `parse_omitted` is the payload's word for "this run produced no
        # observation of it".
        "robots_unavailable_fail_closed" => [UNOBSERVED, "parse_omitted"],
        "policy_excluded" => [UNOBSERVED, "parse_omitted"]
      }.freeze

      # A target the run recorded nothing at all about. It is still a target — the link exists
      # in a parsed Document — so it stays in the payload as explicitly unobserved rather than
      # being dropped, which is what makes partial coverage visible instead of invisible.
      UNRECORDED = [UNOBSERVED, "parse_omitted"].freeze

      # ---- title observation ---------------------------------------------------------

      # One payload per successfully parsed Document. `title_nodes` are in document order with
      # zero-based positions, and BLANK NORMALIZED VALUES REMAIN in the list: a `<title></title>`
      # is a real observation, and dropping it would turn "the page has an empty title" into
      # "the page has no title" — two different outcomes with two different impact bands.
      def title_observation(artifact:, payload:, evaluation_id:)
        {
          "schema_version" => TITLE_SCHEMA,
          "organization_id" => artifact["organization_id"],
          "project_id" => artifact["project_id"],
          "source_id" => artifact["source_id"],
          "evaluation_id" => evaluation_id,
          "document_id" => artifact["document_id"],
          "canonical_url" => artifact["canonical_url"],
          "media_type" => artifact["input_media_type"],
          "parser_definition_version" => artifact["parser_definition_version"],
          "normalization_schema_version" => artifact["normalization_schema_version"],
          "title_nodes" => Array(payload["title_nodes"]).each_with_index.map do |node, index|
            { "position" => index,
              "locator" => node["locator"].to_s,
              "normalized_title" => normalize_title(node["text"]) }
          end
        }
      end

      # The exact normalization the schema states: decode character references (the parser
      # already did, when it exposed text), convert to Unicode NFC, trim leading and trailing
      # Unicode White_Space, and replace every internal run of one or more White_Space
      # characters with ONE ASCII space. `\p{Space}` is the Unicode White_Space property, not
      # ASCII `\s` — a title separated by a non-breaking space must collapse too, or two pages
      # that look identical would normalize differently.
      def normalize_title(text)
        text.to_s.unicode_normalize(:nfc).gsub(/\p{Space}+/, " ").strip
      end

      # ---- organization identity observation -----------------------------------------

      # One payload per active Source ROOT. The expected values come from the frozen public
      # identity profile: the Organization's normalized display name and the Source's
      # canonical root URL. The profile is a derived artifact rather than a row — its identity
      # is the digest of its own content, exactly as the global Crawl Policy artifact's is —
      # so two Evaluations that saw the same identity name the same profile, and a changed
      # display name is a different profile version rather than a silent reinterpretation.
      def identity_observation(artifact:, payload:, evaluation_id:, organization_name:, canonical_root:)
        profile = public_identity_profile(organization_name:, canonical_root:)
        {
          "schema_version" => IDENTITY_SCHEMA,
          "organization_id" => artifact["organization_id"],
          "project_id" => artifact["project_id"],
          "source_id" => artifact["source_id"],
          "evaluation_id" => evaluation_id,
          "root_document_id" => artifact["document_id"],
          "canonical_root_url" => canonical_root,
          "public_identity_profile_id" => profile[:id],
          "public_identity_profile_version" => PUBLIC_IDENTITY_PROFILE_VERSION,
          "expected_public_name" => profile[:expected_public_name],
          "expected_public_url" => profile[:expected_public_url],
          "parser_definition_version" => artifact["parser_definition_version"],
          "normalization_schema_version" => artifact["normalization_schema_version"],
          "organization_nodes" => Array(payload["organization_nodes"]).each_with_index.map do |node, index|
            { "position" => index,
              "locator" => node["locator"].to_s,
              # A node is schema-valid when the parser admitted it as an Organization at all.
              # A `malformed` item carries null name and url by construction, so it can never
              # be counted as a match.
              "schema_valid" => node["parse_status"] == ParsedObservation::VALID,
              "normalized_public_name" => node["name"] && normalize_public_name(node["name"]),
              "canonical_url" => node["url"] && node["url"].to_s }
          end
        }
      end

      def public_identity_profile(organization_name:, canonical_root:)
        expected_name = normalize_public_name(organization_name)
        content = { "profile_version" => PUBLIC_IDENTITY_PROFILE_VERSION,
                    "expected_public_name" => expected_name,
                    "expected_public_url" => canonical_root }
        { id: Platform::DerivedUuid.v8(Platform::CanonicalJson.digest(content)),
          expected_public_name: expected_name, expected_public_url: canonical_root }
      end

      # "Public-name normalization uses Unicode NFC, the same whitespace rule as title
      # normalization, and Unicode 15.1 default full case folding FOR COMPARISON." The folding
      # is applied at comparison time by the Check, not baked into the retained value, so the
      # payload keeps the name as observed rather than as compared.
      def normalize_public_name(text) = normalize_title(text)

      # ---- internal link observation --------------------------------------------------

      # One payload per active Source. `targets` are the distinct in-scope canonical target
      # URLs every parsed Document of that Source linked to, ordered by canonical target URL
      # UTF-8 BYTES, each with its terminal status from the Crawl's own outcomes and its
      # ordered referrers.
      #
      # `relevant_coverage` is `full` only when the Crawl's coverage is full AND every target
      # was actually observed. That conjunction is the point: a run whose coverage the Crawl
      # called full can still have linked to a URL it never fetched, and calling that `full`
      # would let CHK-TI-001 report a pass over a set it did not see.
      def link_observation(source:, artifacts:, evaluation_id:, crawl_id:, crawl_coverage:, outcomes:)
        targets = collect_targets(artifacts)
        entries = targets.keys.sort_by { |url| url.b }.map do |url|
          status, reason = TARGET_OUTCOME.fetch(outcomes[url], UNRECORDED)
          { "canonical_url" => url, "terminal_status" => status, "reason" => reason,
            "referrers" => targets[url] }
        end
        observed = entries.none? { |t| t["terminal_status"] == UNOBSERVED }

        {
          "schema_version" => LINK_SCHEMA,
          "organization_id" => source["organization_id"],
          "project_id" => source["project_id"],
          "source_id" => source["id"],
          "evaluation_id" => evaluation_id,
          "crawl_id" => crawl_id,
          "canonical_root" => source["canonical_root_uri"],
          "relevant_coverage" => (crawl_coverage == "full" && observed) ? "full" : "partial",
          "targets" => entries
        }
      end

      # Referrers are deduplicated on the exact `(document_id, canonical referring URL, link
      # position)` tuple the schema names, because "duplicate referrer tuples ... invalidates
      # the payload" — and the same document CAN legitimately contain the same target twice at
      # two different positions, which is two distinct referrers, not a duplicate.
      def collect_targets(artifacts)
        targets = {}
        artifacts.each do |artifact, payload|
          Array(payload["link_edges"]).each do |edge|
            url = edge["target_canonical_url"]
            next if url.nil?

            referrer = { "document_id" => artifact["document_id"],
                         "canonical_referring_url" => artifact["canonical_url"],
                         "link_position" => edge["position"].to_i }
            list = (targets[url] ||= [])
            list << referrer unless list.include?(referrer)
          end
        end
        targets.each_value do |list|
          list.sort_by! { |r| [r["canonical_referring_url"].b, r["link_position"]] }
        end
        targets
      end

      # ---- production -----------------------------------------------------------------

      # Append one Evidence record for a derived payload. Idempotent on
      # `(organization_id, producer_id, attempt_id)`, and the attempt identity is the payload's
      # own SUBJECT — the Evaluation plus the schema plus the subject key — so re-entering the
      # seal returns the existing Evidence rather than appending a second record for the same
      # observation.
      def produce(payload:, evidence_type:, schema_version:, organization_id:, project_id:, source_id:,
                  evaluation_id:, subject_key:, observed_at:, captured_at:, correlation_id:,
                  data_classification: "internal")
        bytes = Platform::CanonicalJson.encode(payload).b
        attempt_id = Platform::DerivedUuid.v8(Platform::CanonicalJson.digest(
                                                { "evaluation_id" => evaluation_id,
                                                  "schema_version" => schema_version,
                                                  "subject_key" => subject_key }
                                              ))
        aad = Platform::Encryption::Aad.for(**EVIDENCE_AAD, record_id: attempt_id, tenant: organization_id)
        protected_payload = Platform::Encryption.protect(plaintext: bytes, aad:)

        record = Platform::Evidence::Record.build(
          schema_version:, organization_id:, project_id:, source_id:, evaluation_id:,
          evidence_type:, producer_id: PRODUCER, attempt_id:,
          payload_reference: protected_payload.reference,
          content_sha256: protected_payload.content_digest.unpack1("H*"),
          captured_at_utc: captured_at, observed_at_utc: observed_at,
          source_system: SOURCE_SYSTEM, collection_method: "platform_derived_observation",
          collector_version: COLLECTOR_VERSION, validation_status: "valid", validation_reason_code: nil,
          data_classification:, payload_retention_class: Platform::Evidence::Record::PRODUCER_RETENTION_CLASS,
          correlation_id:
        )
        { evidence_id: Platform::Evidence.produce(record),
          content_sha256: protected_payload.content_digest,
          payload_reference: protected_payload.reference }
      end

      # Reveal one Parsed Artifact's normalized payload, through the AAD its producer sealed
      # it with.
      def artifact_payload(artifact)
        aad = Platform::Encryption::Aad.for(
          application: "wf006", record_type: "parsed_artifact", purpose: "normalized_payload",
          record_id: artifact["id"], tenant: artifact["organization_id"]
        )
        JSON.parse(Platform::Encryption.reveal(artifact["normalized_payload_reference"], aad:))
      end
    end
  end
end
