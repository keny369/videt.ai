# frozen_string_literal: true

require "securerandom"

module Platform
  module Evidence
    # The append-only Evidence repository (FOUNDATION-003 §Abstraction). It exposes exactly
    # `append` and two read paths (`get`, `find_by_content_hash`) — there is no update path;
    # immutability is the table's own property. It runs on the caller's proved-context
    # connection, so RLS scopes every write and read to the current Organization.
    #
    # `append` is idempotent on (organization_id, producer_id, attempt_id): a retried
    # producer completion returns the existing evidence_id and writes no second record.
    class EvidenceStore
      # A persisted Evidence identity + the fields a reader needs to locate and trust it
      # (never any interpretation — that is CAP-013/S-09).
      Persisted = Data.define(
        :evidence_id, :evidence_type, :content_sha256, :payload_reference,
        :validation_status, :data_classification, :organization_id, :project_id,
        :source_id, :evaluation_id, :correlation_id
      )

      COLUMNS = %w[
        id evidence_type content_sha256 payload_reference validation_status
        data_classification organization_id project_id source_id evaluation_id correlation_id
      ].freeze

      def initialize(pg: nil)
        @pg = pg
      end

      # Append the validated record; returns its evidence_id (existing on idempotent replay).
      def append(record)
        evidence_id = SecureRandom.uuid_v7
        inserted = connection.exec_params(insert_sql, insert_params(record, evidence_id)).to_a.first
        return inserted["id"] if inserted

        existing_id(record)
      end

      def get(evidence_id)
        row = connection.exec_params(
          "SELECT #{COLUMNS.join(', ')} FROM evidence WHERE id = $1", [evidence_id]
        ).to_a.first
        row && to_persisted(row)
      end

      def find_by_content_hash(content_sha256)
        connection.exec_params(
          "SELECT #{COLUMNS.join(', ')} FROM evidence WHERE content_sha256 = $1 ORDER BY created_at", [content_sha256]
        ).to_a.map { |row| to_persisted(row) }
      end

      private

      def insert_sql
        <<~SQL
          INSERT INTO evidence
            (id, schema_version, organization_id, project_id, source_id, evaluation_id,
             evidence_type, producer_id, attempt_id, payload_reference, content_sha256,
             captured_at_utc, observed_at_utc, source_system, collection_method, collector_version,
             validation_status, validation_reason_code, data_classification, payload_retention_class, correlation_id)
          VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::timestamptz,$13::timestamptz,$14,$15,$16,$17,$18,$19,$20,$21)
          ON CONFLICT (organization_id, producer_id, attempt_id) DO NOTHING
          RETURNING id
        SQL
      end

      def insert_params(record, evidence_id)
        [
          evidence_id, record.schema_version, record.organization_id, record.project_id,
          record.source_id, record.evaluation_id, record.evidence_type, record.producer_id,
          record.attempt_id, record.payload_reference, record.content_sha256,
          ts(record.captured_at_utc), ts(record.observed_at_utc), record.source_system,
          record.collection_method, record.collector_version, record.validation_status,
          record.validation_reason_code, record.data_classification, record.payload_retention_class,
          record.correlation_id
        ]
      end

      def existing_id(record)
        connection.exec_params(
          "SELECT id FROM evidence WHERE organization_id = $1 AND producer_id = $2 AND attempt_id = $3",
          [record.organization_id, record.producer_id, record.attempt_id]
        ).to_a.first&.fetch("id")
      end

      def to_persisted(row)
        Persisted.new(
          evidence_id: row["id"], evidence_type: row["evidence_type"], content_sha256: row["content_sha256"],
          payload_reference: row["payload_reference"], validation_status: row["validation_status"],
          data_classification: row["data_classification"], organization_id: row["organization_id"],
          project_id: row["project_id"], source_id: row["source_id"], evaluation_id: row["evaluation_id"],
          correlation_id: row["correlation_id"]
        )
      end

      def ts(time) = time.getutc.iso8601(6)

      def connection = @pg || ActiveRecord::Base.connection.raw_connection
    end
  end
end
