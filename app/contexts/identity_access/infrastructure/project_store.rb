# frozen_string_literal: true

require "json"

module IdentityAccess
  module Infrastructure
    # Persistence for WF-002 Project creation, written in the caller's unit of work
    # inside the actor's proved Organization context.
    #
    # The Project aggregate is the "Project Context" in 011 DOMAIN_MODEL.md :92,
    # distinct from Identity and Access; its persistence adapter co-locates here
    # exactly as `OrganizationGenesisStore` persists the Organization (Tenant
    # Governance Context) during S-02 genesis — the WF-002 workflow coordinates the
    # authorization context and this store, and a later Project/Intake context
    # extraction is a mechanical move. It reuses the workflow-agnostic platform
    # ledger writers from `ActorLedgerWriters` and overrides only the two writers
    # that stamp `workflow_id`, so its events and audits are attributed to `WF-002`
    # while the command-execution, result and idempotency writers stay shared.
    #
    # The creation profile is written ONCE, at insert, and the projects lifecycle
    # trigger refuses to change it — or the Organization, or the state — afterwards,
    # so this store deliberately offers no project update.
    class ProjectStore
      include ActorLedgerWriters

      def initialize(pg_connection)
        @pg = pg_connection
      end

      # The same advisory-lock convention every other tenant transition uses, so
      # two creations sharing an idempotency key serialize: the loser reaches its
      # lock, blocks, and on release observes the winner's committed idempotency
      # record rather than inserting a second Project.
      def lock_organization(organization_id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["organization:#{organization_id}"])
      end

      # The exact normalized Organization display name, read in the proved context
      # for the Local Business Profile business-name cross-check.
      def organization_display_name(organization_id)
        exec("SELECT display_name FROM organizations WHERE id = $1::uuid", [organization_id]).values.dig(0, 0)
      end

      # Insert exactly one draft Project with its immutable creation profile. State
      # is the literal 'draft', versions start at 0, and `profile_committed_at` is
      # the server commit instant (the injected clock), the same value as
      # created_at.
      def insert_project(row)
        lbp = row[:local_business_profile]
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id],
          row[:display_name], row[:locale], row[:time_zone], row[:objective],
          row[:project_profile_schema_version], row[:local_presence_applicable], row[:local_presence_reason],
          (lbp ? JSON.generate(lbp) : nil), bytea(row[:local_business_profile_content_sha256]),
          row[:profile_attesting_account_id]
        ]
        exec(<<~SQL, params)
          INSERT INTO projects
            (id, state_version, lock_version, created_at, updated_at, correlation_id, organization_id,
             display_name, locale, time_zone, objective, state, source_set_version,
             project_profile_schema_version, local_presence_applicable, local_presence_reason,
             local_business_profile, local_business_profile_content_sha256,
             profile_attesting_account_id, profile_committed_at)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,
                  $5,$6,$7,$8,'draft',0,
                  $9,$10::boolean,$11,
                  $12::jsonb,$13,
                  $14::uuid,$2::timestamptz)
        SQL
      end

      # WF-002 audit writer — the ActorLedgerWriters row shape with `workflow_id`
      # stamped 'WF-002' instead of the shared writer's WF-013 default.
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
          VALUES ($1,'1.0',$2::timestamptz,$2::timestamptz,$3::date,$4::uuid,'WF-002',
                  $5::uuid,$6::uuid,$7::uuid,$8::uuid,$9,$10::uuid,$11,$12,$13,'restricted',$14::jsonb,$15,'security_audit')
        SQL
      end

      # WF-002 event writer — the ActorLedgerWriters row shape with `workflow_id`
      # stamped 'WF-002'. The database re-verifies event_sha256 against event_bytes.
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
          VALUES ($1,'1.0',$2::timestamptz,$3,'1.0','WF-002',$4,
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
