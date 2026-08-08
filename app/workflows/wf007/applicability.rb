# frozen_string_literal: true

module Workflows
  module Wf007
    # The FROZEN CHECK APPLICABILITY SNAPSHOT and its exhaustive ordered expected entries
    # (SCORE_EVIDENCE_MODEL.md § Frozen Check Applicability Snapshot; PRULE-010).
    #
    # WHY IT IS SEALED BEFORE ANY EXECUTION. "Because the Snapshot is sealed before any
    # execution, completion order never changes the expected-entry set, its order or its
    # content hash." Everything downstream — which Results must exist, what each one is
    # allowed to read, and what the Evaluation is waiting for — is decided here, once, and
    # cannot be renegotiated by a Check that runs later.
    #
    # AN ENTRY IS NEVER SILENTLY OMITTED. "A missing selected input that is permitted by an
    # otherwise valid selector REMAINS an entry and produces the Definition's handled `error`;
    # it is NOT silently omitted." A Source whose root was never parsed still gets its
    # CHK-TR-001 entry; the four measurement Definitions still get their Project entries even
    # though `external-measurement-v1` bundles nothing for them to select. Dropping those
    # entries would turn "we could not measure this" into "there was nothing to measure",
    # which is the difference between an insufficient pillar and a complete one.
    #
    # ACTUAL SOURCE IDS ARE BOUND ONLY HERE. "Actual Source IDs are bound only in this
    # Snapshot and its absence-selector instances, never in a global Definition" — which is
    # why the Definitions in `CheckCatalog` carry a Source-neutral selector template and this
    # module instantiates it per entry.
    module Applicability
      module_function

      SCHEMA_VERSION = "check-applicability-snapshot-v1"

      # An expected entry, before it becomes a row.
      Entry = Data.define(:definition, :catalog_entry_id, :definition_row_id, :subject_scope,
                          :canonical_subject_type, :canonical_subject_key, :source_id, :document_id,
                          :applicable, :inapplicable_reason, :absence_selector, :selected_evidence)

      # Build every expected entry, exhaustively, in canonical order.
      #
      # `documents` are the successfully parsed HTML/XHTML Documents of the Evaluation Input
      # Snapshot; `sources` the ACTIVE Sources the Crawl pinned; `evidence_index` the frozen
      # derived Evidence keyed by its producer attempt identity.
      def build(organization_id:, project_id:, evaluation_id:, sources:, documents:, evidence_index:,
                local_presence_applicable:, local_presence_reason:, snapshot_sealed_at: nil)
        index = lambda do |schema, subject|
          select_evidence(evidence_index, evaluation_id, schema, subject, sealed_at: snapshot_sealed_at)
        end
        entries = CheckCatalog::DEFINITIONS.flat_map do |definition|
          case definition["check_definition_id"]
          when "CHK-TI-001", "CHK-TR-001" then source_entries(definition, sources, index)
          when "CHK-CQ-001" then document_entries(definition, documents, index)
          when "CHK-LP-001"
            [local_presence_entry(definition, organization_id, project_id, index,
                                  local_presence_applicable, local_presence_reason)]
          else
            [project_entry(definition, organization_id, project_id, index)]
          end
        end
        order(entries)
      end

      # "Expected entries are exhaustive and ordered by Catalog position, canonical subject
      # key UTF-8 bytes, Source ID, then Document ID." The Catalog position comes first, so a
      # permutation of the input arrays produces an identical Snapshot content hash.
      def order(entries)
        entries.sort_by do |entry|
          [CheckCatalog::DEFINITION_IDS.index(entry.definition["check_definition_id"]),
           entry.canonical_subject_key.b, entry.source_id.to_s, entry.document_id.to_s]
        end
      end

      # One entry for EVERY active Source — including, for CHK-TR-001, a Source whose root
      # input is missing, which is why the Evidence lookup may legitimately return nil here.
      def source_entries(definition, sources, index)
        sources.map do |source|
          Entry.new(
            definition:, catalog_entry_id: CheckCatalog.catalog_entry_row_id(definition),
            definition_row_id: CheckCatalog.definition_row_id(definition),
            subject_scope: "source", canonical_subject_type: "source",
            # "For a Project or Source subject, the canonical key is the OPAQUE Project or
            # Source ID UNCHANGED" — not the root URL, and not a normalization of it.
            canonical_subject_key: source["id"], source_id: source["id"], document_id: nil,
            applicable: true, inapplicable_reason: nil,
            absence_selector: selector(definition, source_id: source["id"], subject_key: source["id"],
                                       subject_type: "source"),
            selected_evidence: index.call(definition["evidence_schema_version"], source["id"])
          )
        end
      end

      # One entry per successfully parsed HTML or XHTML Document; the canonical key is the
      # Document's canonical URL.
      def document_entries(definition, documents, index)
        documents.map do |document|
          Entry.new(
            definition:, catalog_entry_id: CheckCatalog.catalog_entry_row_id(definition),
            definition_row_id: CheckCatalog.definition_row_id(definition),
            subject_scope: "document", canonical_subject_type: "url",
            canonical_subject_key: document["canonical_url"],
            source_id: document["source_id"], document_id: document["document_id"],
            applicable: true, inapplicable_reason: nil,
            absence_selector: selector(definition, source_id: document["source_id"],
                                       subject_key: document["canonical_url"], subject_type: "url"),
            selected_evidence: index.call(definition["evidence_schema_version"], document["canonical_url"])
          )
        end
      end

      def project_entry(definition, organization_id, project_id, index)
        Entry.new(
          definition:, catalog_entry_id: CheckCatalog.catalog_entry_row_id(definition),
          definition_row_id: CheckCatalog.definition_row_id(definition),
          subject_scope: "project", canonical_subject_type: "project",
          canonical_subject_key: project_id, source_id: nil, document_id: nil,
          applicable: true, inapplicable_reason: nil,
          absence_selector: selector(definition, source_id: nil, subject_key: project_id,
                                     subject_type: "project", organization_id:),
          # The measurement Definitions select by measurement kind. Under the ratified OD-010
          # baseline `external-measurement-v1` bundles no active Measurement Set, so this
          # deterministically selects NOTHING — which is the approved outcome, not a gap.
          selected_evidence: index.call(definition["evidence_schema_version"], definition["measurement_kind"])
        )
      end

      # "It is inapplicable ONLY when the frozen Project profile validly records
      # `local_presence_applicable=false` AND its nonblank reason." Anything else — no
      # committed profile, a true decision, or a false one without its reason — leaves the
      # entry APPLICABLE, and it then reaches its handled error rather than a not-applicable
      # Result. A project with no profile has made no decision, and silence is not a `false`.
      def local_presence_entry(definition, organization_id, project_id, index,
                               applicable_decision, reason)
        inapplicable = applicable_decision == false && !reason.to_s.strip.empty?
        Entry.new(
          definition:, catalog_entry_id: CheckCatalog.catalog_entry_row_id(definition),
          definition_row_id: CheckCatalog.definition_row_id(definition),
          subject_scope: "project", canonical_subject_type: "project",
          canonical_subject_key: project_id, source_id: nil, document_id: nil,
          applicable: !inapplicable, inapplicable_reason: inapplicable ? reason : nil,
          absence_selector: selector(definition, source_id: nil, subject_key: project_id,
                                     subject_type: "project", organization_id:),
          selected_evidence: inapplicable ? [] : index.call(definition["evidence_schema_version"],
                                                            definition["measurement_kind"])
        )
      end

      # "An instance contains the Definition's subject namespace plus EXACTLY the entry's
      # Organization, Project, nullable Source, subject type, and canonical subject key."
      # Nothing else: an instance that carried, say, the Crawl would make two Evaluations of
      # the same subject incomparable.
      def selector(definition, source_id:, subject_key:, subject_type:, organization_id: nil)
        {
          "absence_proof_mode" => CheckCatalog::ABSENCE_PROOF_MODE,
          "subject_namespace" => definition["check_definition_id"],
          "organization_id" => organization_id,
          "source_id" => source_id,
          "canonical_subject_type" => subject_type,
          "canonical_subject_key" => subject_key
        }
      end

      # The ordered selected Evidence ID/digest/Validation-Decision tuples, resolved through
      # the producer attempt identity — which is itself derived from `(evaluation, schema,
      # subject key)`, so the selector is a computation over the entry's own frozen subject
      # rather than a search. That is what makes "deterministically select no Evidence" a
      # DETERMINATE outcome for the four measurement Definitions instead of a failed lookup.
      def select_evidence(evidence_index, evaluation_id, schema_version, subject_key, sealed_at: nil)
        return [] if subject_key.nil?

        attempt_id = evidence_attempt_id(evaluation_id:, schema_version:, subject_key:)
        Array(evidence_index[attempt_id]).sort_by { |e| e["id"] }.map do |row|
          { "evidence_id" => row["id"], "evidence_sha256" => row["content_sha256"],
            # No Evidence Validation Decision exists at the baseline, so the effective status
            # is the Evidence's own initial one. It is recorded as the FROZEN status either
            # way: a later Decision must never retroactively change an existing Result.
            "validation_decision_id" => nil, "validation_status" => row["validation_status"],
            "freshness" => freshness_of(row, sealed_at) }
        end
      end

      # THE FRESHNESS PREDICATE, AND WHY A STALE OBSERVATION IS STILL SELECTED.
      #
      # "An Evaluation Input Snapshot may consume an observation only when
      # `observed_at_utc <= snapshot_sealed_at_utc < fresh_until_utc`, and equality at
      # `fresh_until_utc` is STALE." Both boundaries are exact: `<=` at the observation and a
      # STRICT `<` at expiry.
      #
      # A stale observation is selected anyway, tagged `stale`. Dropping it would make the entry
      # indistinguishable from one that selected nothing, and the two are different findings with
      # different reasons: `input_evidence_stale` says "we measured this, and the measurement has
      # expired", while `input_evidence_missing` says "no measurement exists". Collapsing them
      # would tell a customer nothing had ever been measured when in fact it had.
      #
      # Evidence with no observation window — the platform-derived payloads, which are derived
      # from the same sealed run rather than collected against a clock — is `not_applicable`, and
      # the executor treats that as fresh.
      def freshness_of(row, sealed_at)
        observed = row["observed_at_utc"]
        fresh_until = row["fresh_until_utc"]
        return "not_applicable" if sealed_at.nil? || observed.nil? || fresh_until.nil?

        sealed = Platform::PgInstant.utc(sealed_at)
        return "stale" if Platform::PgInstant.utc(observed) > sealed
        return "stale" if sealed >= Platform::PgInstant.utc(fresh_until)

        "fresh"
      end

      # The producer attempt identity a piece of Evidence must be written under to be findable.
      # Exposed rather than inlined because BOTH sides depend on it: the seal computes this key to
      # select, and every producer must write under the same one. Two private copies of this
      # derivation is how Evidence comes to exist that no Check can see.
      def evidence_attempt_id(evaluation_id:, schema_version:, subject_key:)
        Platform::DerivedUuid.v8(Platform::CanonicalJson.digest(
                                   { "evaluation_id" => evaluation_id,
                                     "schema_version" => schema_version,
                                     "subject_key" => subject_key }
                                 ))
      end

      # ---- identity -----------------------------------------------------------------------

      # The Check Result uniqueness preimage: "exactly Evaluation ID, Evaluation Input
      # Snapshot ID, Check Applicability Snapshot ID, Check Catalog version, Check Definition
      # ID and version, canonical subject type and key, and pillar ID IN THAT ORDER".
      #
      # It is encoded as an ORDERED ARRAY of name/value pairs, not an object, because
      # canonical JSON sorts object keys — an object would silently discard the very ordering
      # the contract specifies, and two Definitions whose fields sorted differently would
      # produce preimages that no longer say what they claim to say.
      def key_preimage(evaluation_id:, input_snapshot_id:, applicability_snapshot_id:, catalog_version:,
                       definition_id:, definition_version:, subject_type:, subject_key:, pillar_id:)
        Platform::CanonicalJson.encode(
          [["evaluation_id", evaluation_id],
           ["evaluation_input_snapshot_id", input_snapshot_id],
           ["check_applicability_snapshot_id", applicability_snapshot_id],
           ["check_catalog_version", catalog_version],
           ["check_definition_id", definition_id],
           ["check_definition_version", definition_version],
           ["canonical_subject_type", subject_type],
           ["canonical_subject_key", subject_key],
           ["pillar_id", pillar_id]]
        ).b
      end

      def key_digest(preimage) = Digest::SHA256.digest(preimage)

      # The Snapshot content hash: SHA-256 over canonical JSON of all semantic fields. The
      # generated Snapshot identifier is excluded — it is allocated before the entries can
      # reference it, so including it would make the hash depend on an accident of allocation
      # rather than on what the Snapshot says.
      def content_body(catalog_version:, catalog_sha256:, input_snapshot_id:, project_profile_version:,
                       local_presence_applicable:, local_presence_reason:, active_source_ids:, entries:)
        {
          "check_catalog_version" => catalog_version,
          "check_catalog_sha256" => catalog_sha256,
          "evaluation_input_snapshot_id" => input_snapshot_id,
          "project_profile_version" => project_profile_version,
          "local_presence_applicable" => local_presence_applicable,
          "local_presence_reason" => local_presence_reason,
          "active_source_ids" => active_source_ids.sort,
          "entries" => entries.each_with_index.map do |entry, index|
            { "ordering" => index + 1,
              "check_definition_id" => entry.definition["check_definition_id"],
              "check_definition_version" => entry.definition["semantic_version"],
              "pillar_id" => entry.definition["pillar_id"],
              "subject_scope" => entry.subject_scope,
              "canonical_subject_type" => entry.canonical_subject_type,
              "canonical_subject_key" => entry.canonical_subject_key,
              "source_id" => entry.source_id, "document_id" => entry.document_id,
              "applicable" => entry.applicable, "inapplicable_reason" => entry.inapplicable_reason,
              "absence_selector" => entry.absence_selector,
              "selected_evidence" => entry.selected_evidence }
          end
        }
      end
    end
  end
end
