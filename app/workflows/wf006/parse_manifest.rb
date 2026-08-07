# frozen_string_literal: true

module Workflows
  module Wf006
    # The ordered parse manifest (WORKFLOW_SPECIFICATIONS.md :470).
    #
    # "The parse manifest is the complete set of distinct Documents whose IngestionJobs
    # reached `succeeded` for the selected Crawl, ordered by Source ID, canonical Document
    # URL UTF-8 bytes, then Document ID."
    #
    # Pure, and deliberately given BOTH the candidate rows and the independently-read set of
    # succeeded IngestionJob ids. That second argument is the whole point of the fifth
    # invalidity: a manifest that quietly omits a succeeded job cannot be detected from the
    # manifest alone, because the omission looks exactly like a smaller manifest. So the
    # check compares against a separate reading of the same fact, and :470's closing clause —
    # "an implementation cannot silently drop it" — is enforceable rather than aspirational.
    #
    # The five invalidities all resolve to `input_manifest_invalid`, which BLOCKS readiness.
    # None of them is a repair: a manifest that is wrong is not narrowed to the members that
    # look right, because the missing member might have been the Source root.
    module ParseManifest
      module_function

      INVALID_REASON = "input_manifest_invalid"

      # The five predicates, in the order :470 lists them. Each names what it found so an
      # audit record can say which member broke the manifest rather than only that one did.
      MISSING_TUPLE = "manifest_tuple_incomplete"
      DUPLICATE_DOCUMENT = "manifest_duplicate_document"
      CROSS_ORGANIZATION = "manifest_cross_organization_reference"
      DIGEST_MISMATCH = "manifest_content_digest_mismatch"
      OMITS_SUCCEEDED_JOB = "manifest_omits_succeeded_ingestion_job"

      # Every member :470 requires a tuple to contain. `source_root` and `classification` are
      # booleans/enums that may legitimately be false or "public", so presence is tested by
      # key rather than by truthiness.
      REQUIRED = %w[organization_id project_id source_id crawl_id ingestion_job_id document_id
                    input_evidence_id canonical_url media_type content_digest data_classification
                    source_root].freeze

      Manifest = Data.define(:entries, :invalid_reason, :invalid_detail) do
        def valid? = invalid_reason.nil?
        def size = entries.length
        def source_root_entries = entries.select { |e| e["source_root"] }
      end

      def build(rows:, organization_id:, succeeded_ingestion_job_ids:)
        rows = Array(rows).map { |row| row.transform_keys(&:to_s) }

        detail = first_invalidity(rows, organization_id, Array(succeeded_ingestion_job_ids))
        return Manifest.new(entries: [], invalid_reason: INVALID_REASON, invalid_detail: detail) if detail

        Manifest.new(entries: order(rows), invalid_reason: nil, invalid_detail: nil)
      end

      def first_invalidity(rows, organization_id, succeeded_ids)
        incomplete = rows.find { |row| REQUIRED.any? { |key| !row.key?(key) || row[key].nil? } }
        return "#{MISSING_TUPLE}:#{incomplete["document_id"] || "unknown"}" if incomplete

        duplicate = rows.group_by { |row| row["document_id"] }.find { |_, group| group.length > 1 }
        return "#{DUPLICATE_DOCUMENT}:#{duplicate.first}" if duplicate

        foreign = rows.find { |row| row["organization_id"] != organization_id }
        return "#{CROSS_ORGANIZATION}:#{foreign["document_id"]}" if foreign

        # :470 "manifest/content-digest mismatch". The tuple carries the digest the manifest
        # will parse; the Document carries the digest the crawl recorded. If they disagree the
        # manifest is describing bytes nobody fetched.
        mismatched = rows.find { |row| row.key?("document_content_digest") && row["document_content_digest"] != row["content_digest"] }
        return "#{DIGEST_MISMATCH}:#{mismatched["document_id"]}" if mismatched

        omitted = succeeded_ids - rows.map { |row| row["ingestion_job_id"] }
        return "#{OMITS_SUCCEEDED_JOB}:#{omitted.sort.join(",")}" if omitted.any?

        nil
      end

      # :470's exact ordering. The URL is compared as UTF-8 BYTES rather than by collation, so
      # the order is the same on any database and locale — a manifest whose order depended on
      # `lc_collate` would seal a different snapshot hash on a different server.
      def order(rows)
        rows.sort_by { |row| [row["source_id"].to_s, row["canonical_url"].to_s.b, row["document_id"].to_s] }
      end
    end
  end
end
