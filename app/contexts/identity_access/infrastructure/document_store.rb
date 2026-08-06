# frozen_string_literal: true

module IdentityAccess
  module Infrastructure
    # Persistence for the Document (schemas/POSTGRESQL_SCHEMA.md :302; WORKFLOW_SPECIFICATIONS.md
    # :462, :464). MTX-008 names `DocumentRepository` as a root of its own, and this is it.
    #
    # THE VERSION IS ALLOCATED HERE, UNDER A LOCK, AND NOT SUPPLIED BY THE CALLER.
    #
    # :462 — "A DIFFERENT BODY DIGEST creates a NEW VERSIONED Document/job and never overwrites prior
    # Evidence", and :302 keys the table `(source_id, canonical_url_sha256, version)` with a "positive
    # version" and a nullable predecessor. So the version of a URL is `MAX + 1` over that URL's own
    # history on that Source, and the predecessor is the row that held the maximum.
    #
    # The lock is `document-version:<source>:<url hash>`, taken for the whole allocating transaction.
    # Two Crawls of one Project can retire the same URL at the same instant — they hold DIFFERENT
    # per-Crawl frontier locks, so nothing else serialises them — and without this both would compute
    # the same `MAX + 1` and one would take a unique violation out of the workflow. It is always taken
    # AFTER the frontier lock and never before, so it adds no cycle to the subsystem's lock order.
    #
    # NO DELETE PATH, AND NO STATE-CHANGE PATH BEYOND THE LIFECYCLE. :302 — a Document "leaves product
    # use only through the separate retention and deletion lifecycle, WHICH DESTROYS THE ROW rather
    # than transitioning it". That lifecycle is not built and is not this tranche's, so nothing here
    # destroys a Document and the runtime role holds no DELETE on the table.
    class DocumentStore
      SCHEMA_VERSION = "1.0"
      DISCOVERED = "discovered"
      INGESTED = "ingested"

      def initialize(pg_connection)
        @pg = pg_connection
      end

      def enter_org_context(org:, correlation_id:)
        query("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, correlation_id]).values.dig(0, 0)
      end

      # Serialize version allocation for one URL on one Source. Held for the transaction.
      def lock_document_line(source_id, canonical_url_sha256)
        query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
              ["document-version:#{source_id}:#{hex(canonical_url_sha256)}"])
      end

      # Create the discovered Document for one retained successful fetch. The caller holds
      # `lock_document_line`. Returns the inserted row.
      def create(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:causation_id], row[:command_id],
          row[:organization_id], row[:project_id], row[:source_id], row[:crawl_id],
          row[:canonical_url], bytea(row[:canonical_url_sha256]), row[:fetched_object_id],
          row[:media_type], row[:byte_size], bytea(row[:content_sha256])
        ]
        query(<<~SQL, params).to_a.first
          WITH prior AS (
            SELECT d.id, d.version FROM documents d
            WHERE d.source_id = $8::uuid AND d.canonical_url_sha256 = $11
            ORDER BY d.version DESC LIMIT 1
          )
          INSERT INTO documents
            (id, state_version, lock_version, schema_version, created_at, updated_at,
             correlation_id, causation_id, command_id, organization_id, project_id, source_id,
             crawl_id, canonical_url, canonical_url_sha256, version, predecessor_document_id,
             fetched_object_id, media_type, byte_size, content_sha256, state, discovered_at)
          SELECT $1::uuid, 0, 0, '#{SCHEMA_VERSION}', $2::timestamptz, $2::timestamptz,
                 $3::uuid, $4::uuid, $5::uuid, $6::uuid, $7::uuid, $8::uuid,
                 $9::uuid, $10, $11,
                 COALESCE((SELECT p.version FROM prior p), 0) + 1,
                 (SELECT p.id FROM prior p),
                 $12::uuid, $13, $14, $15, '#{DISCOVERED}', $2::timestamptz
          RETURNING id, version, predecessor_document_id, state, canonical_url, state_version
        SQL
      end

      # `discovered -> ingested` for the SAME version, guarded on the state version the caller read.
      #
      # PRULE-009 — "Successful same-version Documents advance ingested-to-parsed and parsed-to-indexed
      # EXACTLY ONCE, guarded ON THE DOCUMENT BY ITS VERSION rather than by delivery deduplication."
      # This is the first limb of that rule, applied where MTX-008 states it: "each successful
      # same-version job advances the Document exactly once". The compare-and-set is the guard — a
      # second delivery matches zero rows and advances nothing — and `f1_documents_lifecycle_guard`
      # refuses the edge outright if the row has already moved on.
      def mark_ingested(organization_id, document_id, expected_state_version, now)
        query(<<~SQL, [organization_id, document_id, expected_state_version, iso(now)]).cmd_tuples
          UPDATE documents
             SET state = '#{INGESTED}', ingested_at = $4::timestamptz, updated_at = $4::timestamptz,
                 state_version = state_version + 1
           WHERE organization_id = $1::uuid AND id = $2::uuid
             AND state_version = $3::bigint AND state = '#{DISCOVERED}'
        SQL
      end

      def get(organization_id, document_id)
        query(<<~SQL, [organization_id, document_id]).to_a.first
          SELECT id, organization_id, project_id, source_id, crawl_id, canonical_url,
                 canonical_url_sha256, version, predecessor_document_id, fetched_object_id,
                 media_type, byte_size, content_sha256, state, state_version,
                 discovered_at, ingested_at
          FROM documents WHERE organization_id = $1::uuid AND id = $2::uuid
        SQL
      end

      private

      def query(sql, params = []) = @pg.exec_params(sql, params)
      def iso(time) = time&.getutc&.iso8601(6)
      def bytea(value) = value && { value:, format: 1 }
      def hex(value) = value.unpack1("H*")
    end
  end
end
