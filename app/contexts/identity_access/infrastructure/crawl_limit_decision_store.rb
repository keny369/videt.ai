# frozen_string_literal: true

require "json"

module IdentityAccess
  module Infrastructure
    # Persistence for S-07-008 limit decisions and the events derived from them
    # (schemas/POSTGRESQL_SCHEMA.md :300; WORKFLOW_SPECIFICATIONS.md :442; API_CONTRACTS.md
    # `crawl_limit_decision`).
    #
    # THE DECISION ROW IS THE OUTBOX TRIGGER, NOT A LOG OF ONE. `record` is a single
    # `ON CONFLICT DO NOTHING RETURNING`, so `UNIQUE (crawl_id, limit_dimension, threshold_kind)` —
    # :442's "exactly once per dimension and run" — decides whether this caller is the one that
    # observed the limit. A caller that gets `replayed: true` did not, and writes no event. Every
    # other ordering (emit then record, count then emit, check then insert) has a window in which a
    # crash or a race produces either two customer-visible events or none; this one has no window
    # because the barrier and the record are the same statement.
    #
    # `RETURNING` names every column the envelope needs, so the event is built from what was STORED
    # rather than from what the caller intended to store. The two cannot drift, and a CHECK that
    # rejected a value stops the event as well as the row.
    class CrawlLimitDecisionStore
      DECISION_TYPE = "crawl_limit_observation"
      DECISION_STATUS = "final"

      # Everything the envelope needs, so it is built from what was STORED. The digests come back
      # as hex because that is the form `sha256` takes on the wire, and `definition_versions` comes
      # back as the jsonb the row holds rather than the hash the caller passed in.
      RETURNED = <<~COLUMNS.freeze
        id, organization_id, project_id, crawl_id, limit_dimension, threshold_kind, configured_value,
        observed_value, affected_source_count, affected_url_count, decision_type, decision_value,
        decision_status, decision_reason_code, decided_by_service_identity_id, decided_at,
        definition_versions::text AS definition_versions,
        encode(input_sha256,'hex') AS input_sha256, encode(output_sha256,'hex') AS output_sha256
      COLUMNS

      def initialize(pg_connection)
        @pg = pg_connection
      end

      def enter_org_context(org:, correlation_id:)
        query("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, correlation_id]).values.dig(0, 0)
      end

      # Write the limit observation, or discover that it is already written. Returns
      # `{ row:, replayed: }` — `replayed` true means another worker, or an earlier attempt by this
      # one, already owns this (crawl, dimension, threshold) and no event is owed.
      def record(row)
        params = [
          row[:id], row[:correlation_id], row[:causation_id], row[:command_id], row[:organization_id],
          row[:project_id], row[:crawl_id], row[:limit_dimension], row[:threshold_kind],
          row[:configured_value], row[:observed_value], row[:affected_source_count],
          row[:affected_url_count], row[:decision_value], row[:decision_reason_code],
          row[:decided_by_service_identity_id], JSON.generate(row[:definition_versions]),
          bytea(row[:input_sha256]), bytea(row[:output_sha256]), row[:decided_at]
        ]
        inserted = query(<<~SQL, params).to_a.first
          INSERT INTO crawl_limit_decisions
            (id, schema_version, created_at, correlation_id, causation_id, command_id,
             organization_id, project_id, crawl_id, limit_dimension, threshold_kind,
             configured_value, observed_value, affected_source_count, affected_url_count,
             decision_type, decision_value, decision_status, decision_reason_code,
             decided_by_service_identity_id, definition_versions, input_sha256, output_sha256, decided_at)
          VALUES ($1::uuid,'1.0',$20::timestamptz,$2::uuid,$3::uuid,$4::uuid,
                  $5::uuid,$6::uuid,$7::uuid,$8,$9,
                  $10,$11,$12,$13,
                  '#{DECISION_TYPE}',$14,'#{DECISION_STATUS}',$15,
                  $16::uuid,$17::jsonb,$18,$19,$20::timestamptz)
          ON CONFLICT (crawl_id, limit_dimension, threshold_kind) DO NOTHING
          RETURNING #{RETURNED}
        SQL
        return { row: inserted, replayed: false } if inserted

        found = existing(row[:organization_id], row[:project_id], row[:crawl_id],
                         row[:limit_dimension], row[:threshold_kind])
        # `ON CONFLICT DO NOTHING` suppresses the RLS `WITH CHECK` on the conflicting path, so a
        # caller without a proved context inserts nothing AND reads nothing. Failing loudly here
        # beats returning a nil row for the caller to dereference three frames later.
        raise Platform::InvariantViolation, "limit decision conflicted but is not visible" if found.nil?

        { row: found, replayed: true }
      end

      # Keyed on all three of (organization, project, crawl) rather than on the unique key alone.
      # The unique key would have found the row, and RLS would have hidden a foreign tenant's — but
      # POSTGRESQL_SCHEMA :128's rule is that a Project-owned read is SAFE BY PREDICATE, not safe by
      # argument, and RLS is Organization-scoped so it says nothing about Projects. This was the
      # fourth consecutive tranche to grow an instance of that defect class.
      def existing(organization_id, project_id, crawl_id, dimension, threshold)
        query(<<~SQL, [organization_id, project_id, crawl_id, dimension, threshold]).to_a.first
          SELECT #{RETURNED} FROM crawl_limit_decisions
          WHERE organization_id = $1::uuid AND project_id = $2::uuid AND crawl_id = $3::uuid
            AND limit_dimension = $4 AND threshold_kind = $5
        SQL
      end

      # Every limit decision for a run, in decision order. S-07-009's terminal checkpoint reads this
      # to derive `coverage_status` and `completion_reason`: the decision table is the authority for
      # "a limit was hit", so the checkpoint never needs a second, differently-derived opinion.
      def decisions(organization_id, crawl_id)
        query(<<~SQL, [organization_id, crawl_id]).to_a
          SELECT #{RETURNED} FROM crawl_limit_decisions
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
          ORDER BY decided_at, limit_dimension, threshold_kind
        SQL
      end

      # ":456 — any in-scope candidate NOT EVALUATED because of a … bound makes coverage partial."
      # The candidates a hard limit abandons are the ones still awaiting SELECTION; `in_progress`
      # and `fetched_pending_commit` entries are already in flight and will finish, so counting them
      # as affected would overstate what the limit cost.
      def unselected_counts(organization_id, crawl_id)
        query(<<~SQL, [organization_id, crawl_id]).to_a.first
          SELECT COUNT(*) AS urls, COUNT(DISTINCT source_id) AS sources
          FROM crawl_frontier_entries
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
            AND state IN ('discovered','queued')
        SQL
      end

      def insert_audit(row)
        params = [
          row[:id], row[:occurred_at], row[:partition_month], row[:organization_id],
          row[:service_identity_id], row[:correlation_id], row[:causation_id], row[:entity_id],
          row[:outcome], row[:reason_code], row[:payload], bytea(row[:content_sha256])
        ]
        query(<<~SQL, params)
          INSERT INTO audit_record_registry
            (id, schema_version, created_at, occurred_at, partition_month, organization_id, workflow_id,
             service_identity_id, correlation_id, causation_id, entity_type, entity_id,
             to_state, outcome, reason_code, classification, payload, content_sha256, retention_class)
          VALUES ($1,'1.0',$2::timestamptz,$2::timestamptz,$3::date,$4::uuid,'WF-005',
                  $5::uuid,$6::uuid,$7::uuid,'crawl',$8::uuid,
                  NULL,$9,$10,'restricted',$11::jsonb,$12,'security_audit')
        SQL
      end

      def insert_event(row)
        params = [
          row[:id], row[:created_at], row[:event_type], row[:occurred_at], row[:organization_id],
          row[:project_id], row[:aggregate_id], row[:aggregate_version], row[:partition_month],
          row[:correlation_id], row[:causation_id], row[:audit_record_id], bytea(row[:event_bytes]),
          row[:event_bytes].bytesize, bytea(row[:event_sha256])
        ]
        query(<<~SQL, params)
          INSERT INTO event_registry
            (id, schema_version, created_at, event_type, event_schema_version, workflow_id, event_profile,
             occurred_at, organization_id, project_id, aggregate_type, aggregate_id, aggregate_version,
             partition_month, correlation_id, causation_id, audit_record_id,
             event_bytes, event_byte_count, event_sha256)
          VALUES ($1,'1.0',$2::timestamptz,$3,'1.0','WF-005','decision',
                  $4::timestamptz,$5::uuid,$6::uuid,'crawl',$7::uuid,$8,
                  $9::date,$10::uuid,$11::uuid,$12::uuid,
                  $13,$14,$15)
        SQL
      end

      private

      # Named `query` for the reason recorded on the sibling stores: a private `exec` shadows
      # `Kernel#exec` and makes every statement read as command execution to a static analyser.
      def query(sql, params = []) = @pg.exec_params(sql, params)

      def bytea(value) = { value:, format: 1, type: 17 }
    end
  end
end
