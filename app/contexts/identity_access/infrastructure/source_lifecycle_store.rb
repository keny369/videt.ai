# frozen_string_literal: true

require "json"

module IdentityAccess
  module Infrastructure
    # Persistence for the WF-004 Source lifecycle transitions (S-06-006; PRULE-006 /
    # contracts/S-06.json MTX-057): Activate, Disable, Reactivate, Remove. Written in the
    # actor's unit of work inside the proved Organization context, actor-attributed and
    # stamped `WF-004` — the SourceStore shape (which it mirrors) specialized to the lifecycle
    # transition. It reuses the workflow-agnostic ActorLedgerWriters and overrides only the two
    # writers that stamp `workflow_id`.
    #
    # It takes the SAME per-Source advisory lock as the scope-change paths so a lifecycle
    # transition and a scope-policy activation for one Source serialize; the guarded UPDATE
    # (state = expected FROM state AND state_version = expected) is the concurrency backstop.
    class SourceLifecycleStore
      include ActorLedgerWriters

      TIMESTAMP_COLUMNS = %w[activated_at disabled_at removed_at].freeze

      def initialize(pg_connection)
        @pg = pg_connection
      end

      def lock_source(source_id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["source-scope-change:#{source_id}"])
      end

      # The Source read in the proved Organization context; the pinned policy version is the
      # policy_version of the current active Source Scope Policy (the reference the transition
      # persists alongside the new state). A not-found Source is invisible under RLS.
      def source(source_id)
        exec(<<~SQL, [source_id]).to_a.first
          SELECT s.id, s.organization_id, s.project_id, s.state, s.state_version, s.current_scope_policy_id,
                 p.policy_version AS pinned_policy_version
          FROM sources s
          LEFT JOIN source_scope_policies p ON p.id = s.current_scope_policy_id
          WHERE s.id = $1::uuid
        SQL
      end

      # Transition exactly one Source from the expected FROM state to the TO state, stamping the
      # lifecycle timestamp and (optional) reason, guarded on the expected state version AND the
      # FROM state (the DB trigger independently refuses any unlisted edge). Returns the row count.
      def transition(source_id, from_state, to_state, expected_version, timestamp_column, reason, now)
        raise ArgumentError, "unknown timestamp column #{timestamp_column.inspect}" unless TIMESTAMP_COLUMNS.include?(timestamp_column)

        exec(<<~SQL, [source_id, from_state, to_state, expected_version, reason, iso(now)]).cmd_tuples
          UPDATE sources
          SET state = $3, #{timestamp_column} = $6::timestamptz, lifecycle_reason = $5,
              state_version = state_version + 1, updated_at = $6::timestamptz
          WHERE id = $1::uuid AND state = $2 AND state_version = $4
        SQL
      end

      # WF-004 audit writer — the ActorLedgerWriters row shape with `workflow_id` stamped
      # 'WF-004' (SourceStore parity).
      def insert_audit(row)
        params = [
          row[:id], row[:occurred_at], row[:partition_month], row[:organization_id], row[:actor_id],
          row[:correlation_id], row[:causation_id], row[:command_id], row[:entity_type], row[:entity_id],
          row[:to_state], row[:outcome], row[:reason_code], row[:payload], bytea(row[:content_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO audit_record_registry
            (id, schema_version, created_at, occurred_at, partition_month, organization_id, workflow_id,
             actor_id, correlation_id, causation_id, command_id, entity_type, entity_id,
             to_state, outcome, reason_code, classification, payload, content_sha256, retention_class)
          VALUES ($1,'1.0',$2::timestamptz,$2::timestamptz,$3::date,$4::uuid,'WF-004',
                  $5::uuid,$6::uuid,$7::uuid,$8::uuid,$9,$10::uuid,$11,$12,$13,'restricted',$14::jsonb,$15,'security_audit')
        SQL
      end

      # WF-004 event writer — the ActorLedgerWriters row shape with `workflow_id` stamped
      # 'WF-004'. The database re-verifies event_sha256 against event_bytes.
      def insert_event(row)
        params = [
          row[:id], row[:created_at], row[:event_type], row[:event_profile], row[:occurred_at],
          row[:organization_id], row[:aggregate_type], row[:aggregate_id], row[:aggregate_version],
          row[:partition_month], row[:correlation_id], row[:causation_id], row[:command_id],
          row[:audit_record_id], bytea(row[:event_bytes]), row[:event_bytes].bytesize, bytea(row[:event_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO event_registry
            (id, schema_version, created_at, event_type, event_schema_version, workflow_id, event_profile,
             occurred_at, organization_id, aggregate_type, aggregate_id, aggregate_version, partition_month,
             correlation_id, causation_id, command_id, audit_record_id, event_bytes, event_byte_count, event_sha256)
          VALUES ($1,'1.0',$2::timestamptz,$3,'1.0','WF-004',$4,
                  $5::timestamptz,$6::uuid,$7,$8::uuid,$9,$10::date,
                  $11::uuid,$12::uuid,$13::uuid,$14::uuid,$15,$16,$17)
        SQL
      end

      private

      def exec(sql, params) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      def iso(time) = time&.getutc&.iso8601(6)
    end
  end
end
