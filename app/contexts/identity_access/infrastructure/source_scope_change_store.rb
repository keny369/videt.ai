# frozen_string_literal: true

require "json"

module IdentityAccess
  module Infrastructure
    # Persistence for WF-004 ProposeSourceScopeChange (S-06-003), written in the caller's
    # unit of work inside the actor's proved Organization context. It co-locates with the
    # other Source/Verification adapters (SourceStore, VerificationRequestStore) exactly as
    # 011 DOMAIN_MODEL.md keeps the Source/Scope aggregates alongside Identity/Access for now.
    #
    # It reuses the workflow-agnostic platform ledger writers from ActorLedgerWriters and
    # overrides only the two writers that stamp `workflow_id`, so its audits and events are
    # attributed to WF-004. This tranche creates PENDING requests only; the source_scope_
    # change_requests lifecycle trigger refuses every state transition and freezes the facts,
    # so this store deliberately offers no request update.
    class SourceScopeChangeStore
      include ActorLedgerWriters

      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Serialize ProposeSourceScopeChange commands for the same Source so an idempotent
      # replay observes the winner's committed request rather than racing.
      def lock_source(source_id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["source-scope-change:#{source_id}"])
      end

      # The Source precondition read in the proved Organization context; a not-found Source
      # (another Organization's, or nonexistent) is invisible under RLS and is a tenant
      # boundary failure for the handler.
      def source(source_id)
        exec(<<~SQL, [source_id]).to_a.first
          SELECT id, organization_id, project_id, state, state_version, canonical_host, current_scope_policy_id
          FROM sources WHERE id = $1::uuid
        SQL
      end

      # The current active Source Scope Policy version the proposal is made against.
      def active_scope_policy(policy_id)
        return nil if policy_id.nil?

        exec(<<~SQL, [policy_id]).to_a.first
          SELECT id, policy_version, scope, canonical_host, allowed_schemes, allowed_ports,
                 include_prefixes, exclude_prefixes, query_handling, content_sha256
          FROM source_scope_policies WHERE id = $1::uuid
        SQL
      end

      # Insert exactly one PENDING Source Scope Change Request with its immutable facts.
      # `requested_at`/row timestamps are the same server commit instant (the injected
      # clock); `due_at` is exactly 24 hours later.
      def insert_source_scope_change_request(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:project_id],
          row[:source_id], row[:requester_account_id], row[:expected_active_policy_version],
          bytea(row[:current_content_sha256]), row[:proposed_canonical_host],
          pg_text_array(row[:proposed_allowed_schemes]), pg_int_array(row[:proposed_allowed_ports]),
          pg_text_array(row[:proposed_include_prefixes]), pg_text_array(row[:proposed_exclude_prefixes]),
          row[:proposed_query_handling], bytea(row[:proposed_content_sha256]), row[:request_reason],
          iso(row[:requested_at]), iso(row[:due_at]), bytea(row[:idempotency_key_digest])
        ]
        exec(<<~SQL, params)
          INSERT INTO source_scope_change_requests
            (id, state_version, created_at, updated_at, correlation_id, schema_version,
             organization_id, project_id, source_id, requester_account_id,
             expected_active_policy_version, current_content_sha256, proposed_canonical_host,
             proposed_allowed_schemes, proposed_allowed_ports, proposed_include_prefixes,
             proposed_exclude_prefixes, proposed_query_handling, proposed_content_sha256,
             request_reason, requested_at_utc, due_at_utc, state, idempotency_key_digest)
          VALUES ($1,0,$2::timestamptz,$2::timestamptz,$3::uuid,'source-scope-change-request-v1',
                  $4::uuid,$5::uuid,$6::uuid,$7::uuid,
                  $8,$9,$10,
                  $11::text[],$12::integer[],$13::text[],
                  $14::text[],$15,$16,
                  $17,$18::timestamptz,$19::timestamptz,'pending',$20)
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

      # ---- S-06-004 decision + activation reads/writes ----

      def read_request(id)
        exec(<<~SQL, [id]).to_a.first
          SELECT id, organization_id, project_id, source_id, requester_account_id, state, state_version,
                 expected_active_policy_version, proposed_canonical_host, proposed_allowed_schemes,
                 proposed_allowed_ports, proposed_include_prefixes, proposed_exclude_prefixes,
                 proposed_query_handling, proposed_content_sha256, due_at_utc
          FROM source_scope_change_requests WHERE id = $1::uuid
        SQL
      end

      # The count of existing Source Scope Policy versions for a Source — the ordinal a new
      # activated version takes (`source-scope-v{ordinal+1}`); read under the per-Source lock.
      def policy_count(source_id)
        exec("SELECT COUNT(*) AS n FROM source_scope_policies WHERE source_id = $1::uuid", [source_id])
          .to_a.first["n"].to_i
      end

      # Insert a new immutable Source Scope Policy version (S-05-006 shape).
      def insert_source_scope_policy(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:project_id],
          row[:source_id], row[:policy_version], row[:canonical_host],
          pg_text_array(row[:allowed_schemes]), pg_int_array(row[:allowed_ports]),
          pg_text_array(row[:include_prefixes]), pg_text_array(row[:exclude_prefixes]),
          row[:query_handling], bytea(row[:content_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO source_scope_policies
            (id, created_at, correlation_id, schema_version, organization_id, project_id, source_id,
             policy_version, scope, canonical_host, allowed_schemes, allowed_ports,
             include_prefixes, exclude_prefixes, query_handling, content_sha256)
          VALUES ($1,$2::timestamptz,$3::uuid,'source-scope-policy-v1',$4::uuid,$5::uuid,$6::uuid,
                  $7,'source',$8,$9::text[],$10::integer[],$11::text[],$12::text[],$13,$14)
        SQL
      end

      # Repoint the Source's active Source Scope Policy, guarded on the expected current
      # pointer so two concurrent activations cannot both apply. Returns the row count.
      def repoint_source(source_id, new_policy_id, expected_policy_id, now)
        exec(<<~SQL, [source_id, new_policy_id, expected_policy_id, iso(now)]).cmd_tuples
          UPDATE sources
          SET current_scope_policy_id = $2::uuid, state_version = state_version + 1, updated_at = $4::timestamptz
          WHERE id = $1::uuid AND current_scope_policy_id = $3::uuid
        SQL
      end

      # Transition a pending request to a terminal state, guarded on the expected request
      # state version AND on the row still being pending. Returns the row count.
      def transition_request(id, expected_state_version, to_state, decision_actor_id:, decision_reason:,
                             activated_policy_version:, now:)
        params = [id, expected_state_version, to_state, decision_actor_id, decision_reason,
                  activated_policy_version, iso(now)]
        exec(<<~SQL, params).cmd_tuples
          UPDATE source_scope_change_requests
          SET state = $3, decision_actor_id = $4::uuid, decided_at_utc = $7::timestamptz,
              decision_reason = $5, activated_policy_version = $6, terminal_at_utc = $7::timestamptz,
              state_version = state_version + 1, updated_at = $7::timestamptz
          WHERE id = $1::uuid AND state = 'pending' AND state_version = $2
        SQL
      end

      private

      def exec(sql, params) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      def iso(time) = time&.getutc&.iso8601(6)
      def pg_text_array(values) = "{#{Array(values).map { |v| quote_array_element(v.to_s) }.join(',')}}"
      def pg_int_array(values) = "{#{Array(values).map(&:to_i).join(',')}}"
      def quote_array_element(str) = "\"#{str.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}\""
    end
  end
end
