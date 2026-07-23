# frozen_string_literal: true

require "json"

module IdentityAccess
  module Infrastructure
    # Persistence for WF-004 Source registration, written in the caller's unit of
    # work inside the actor's proved Organization context.
    #
    # The Source aggregate is the "Intake Context" in 011 DOMAIN_MODEL.md :102,
    # distinct from Identity and Access and from the Project Context. Its
    # persistence adapter co-locates here exactly as `ProjectStore` and
    # `OrganizationGenesisStore` do — the workflow coordinates the authorization
    # context and this store, and a later Intake context extraction is a mechanical
    # move that carries this adapter and the shared ledger writers with it. It
    # reuses the workflow-agnostic platform ledger writers from `ActorLedgerWriters`
    # and overrides only the two writers that stamp `workflow_id`, so its events and
    # audits are attributed to `WF-004`.
    #
    # The registration facts are written ONCE, at insert; the sources lifecycle
    # trigger refuses to change them — or the tenant/Project identity, or the state
    # — afterwards, so this store deliberately offers no Source update.
    class SourceStore
      include ActorLedgerWriters

      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Serialize registrations contending for the ratified uniqueness key
      # (project_id, canonical_host), so the loser observes the winner's committed
      # Source and replays or is refused rather than racing the partial unique
      # index into a raw violation.
      def lock_source_host(project_id, canonical_host)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["source-host:#{project_id}:#{canonical_host}"])
      end

      # The Project precondition read, in the proved Organization context: a
      # not-found Project (another Organization's, or nonexistent) is invisible
      # under RLS and is treated as a tenant boundary failure by the handler.
      def project(project_id)
        exec("SELECT id, organization_id, state, state_version FROM projects WHERE id = $1::uuid",
             [project_id]).to_a.first
      end

      # Does a non-removed Source already hold this canonical host in this Project?
      # The ratified uniqueness key is (organization_id, project_id, canonical_host)
      # over every Source not `removed`.
      def host_registered?(organization_id, project_id, canonical_host)
        exec(<<~SQL, [organization_id, project_id, canonical_host]).values.any?
          SELECT 1 FROM sources
          WHERE organization_id = $1::uuid AND project_id = $2::uuid AND canonical_host = $3
            AND state <> 'removed' LIMIT 1
        SQL
      end

      # Insert exactly one proposed Source with its immutable registration
      # provenance. `registered_at` and the row timestamps are the same server
      # commit instant (the injected clock).
      def insert_source(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:project_id],
          row[:submitted_root_uri], row[:canonical_root_uri], row[:canonical_host],
          row[:registration_schema_version], row[:host_normalization_version],
          row[:registering_account_id], row[:registration_command_id],
          bytea(row[:registration_idempotency_key_digest]), row[:registration_authorization_decision_id]
        ]
        exec(<<~SQL, params)
          INSERT INTO sources
            (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id, project_id,
             submitted_root_uri, canonical_root_uri, canonical_host,
             registration_schema_version, host_normalization_version, registration_origin,
             registering_account_id, registration_command_id, registration_idempotency_key_digest,
             registration_authorization_decision_id, registered_at, state)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,
                  $6,$7,$8,
                  $9,$10,'human_command',
                  $11::uuid,$12::uuid,$13,
                  $14::uuid,$2::timestamptz,'proposed')
        SQL
      end

      # WF-004 audit writer — the ActorLedgerWriters row shape with `workflow_id`
      # stamped 'WF-004' instead of the shared writer's WF-013 default.
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

      # WF-004 event writer — the ActorLedgerWriters row shape with `workflow_id`
      # stamped 'WF-004'. The database re-verifies event_sha256 against event_bytes.
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
