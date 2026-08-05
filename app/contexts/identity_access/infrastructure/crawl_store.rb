# frozen_string_literal: true

require "json"

module IdentityAccess
  module Infrastructure
    # Persistence for WF-005 QueueCrawl (S-07-002), written in the actor's unit of work inside
    # the proved Organization context. Reuses ActorLedgerWriters and overrides only the two
    # writers stamped `workflow_id` = 'WF-005'. It reads the queue preconditions (project state,
    # active Sources, the request-time crawl/entitlement policy versions, the OD-018 guard) and
    # writes the queued Crawl + its pinned Source set. It reserves no usage and creates no
    # Evaluation (PRULE-007 / MTX-030).
    class CrawlStore
      include ActorLedgerWriters

      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Serialize QueueCrawl + the OD-018 read for one Project so a replayed/concurrent request
      # observes a consistent guard result.
      def lock_project(organization_id, project_id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["crawl-queue:#{organization_id}:#{project_id}"])
      end

      def project(organization_id, project_id)
        exec("SELECT id, state, state_version FROM projects WHERE organization_id=$1::uuid AND id=$2::uuid",
             [organization_id, project_id]).to_a.first
      end

      # The Project's active Sources (lifecycle state 'active'), each with its pinned current
      # active Source Scope Policy id/version, in deterministic registration order.
      def active_sources(organization_id, project_id)
        exec(<<~SQL, [organization_id, project_id]).to_a
          SELECT s.id, s.state_version, s.current_scope_policy_id, p.policy_version AS scope_policy_version,
                 s.canonical_root_uri
          FROM sources s
          JOIN source_scope_policies p ON p.id = s.current_scope_policy_id
          WHERE s.organization_id = $1::uuid AND s.project_id = $2::uuid AND s.state = 'active'
          ORDER BY s.registered_at, s.id
        SQL
      end

      # The most specific active crawl policy for the Project (a Project-scope version, else an
      # Organization-scope version), or nil when only the frozen global ceiling applies.
      def active_crawl_policy(organization_id, project_id)
        exec(<<~SQL, [organization_id, project_id]).to_a.first
          SELECT id, policy_version, scope FROM crawl_policies
          WHERE organization_id = $1::uuid AND state = 'active'
            AND ((scope = 'project' AND project_id = $2::uuid) OR scope = 'organization')
          ORDER BY (scope = 'project') DESC
          LIMIT 1
        SQL
      end

      # The Organization's active Entitlement Policy id/version (the request-time counter context).
      def active_entitlement_policy(organization_id)
        exec(<<~SQL, [organization_id]).to_a.first
          SELECT id, semantic_version FROM entitlement_policies
          WHERE organization_id = $1::uuid AND status = 'active'
          LIMIT 1
        SQL
      end

      # OD-018: true when a pending or running initial-assessment Evaluation exists for the
      # Project (a second root request while one is in flight is refused).
      def running_initial_evaluation?(organization_id, project_id)
        exec(<<~SQL, [organization_id, project_id]).to_a.first["n"].to_i.positive?
          SELECT COUNT(*) AS n FROM evaluations
          WHERE organization_id = $1::uuid AND project_id = $2::uuid AND kind = 'initial'
            AND state IN ('pending','running')
        SQL
      end

      # QUEUEING CARRIES ITS OWN AUTHORITY CHECK, IN THE WRITE.
      #
      # THE SAME GOVERNING PRINCIPLE AS THE CANCELLATION WRITE. `authority_current?` is, in full,
      # "`organizations.authorization_epoch` equals the epoch the actor authenticated with" — ordinary
      # row state — so it belongs IN the statement that depends on it rather than in a Ruby check
      # standing next to it. There is then nothing to hoist, reorder, extract into a helper or arrange
      # a Boolean around, and no list of which handlers must remember to look: PostgreSQL evaluates
      # authority and the insertion together, IN THE SAME STATEMENT as the write, with the authority read
      # taking `FOR KEY SHARE` on the organization row.
      #
      # THE LOCK CLAUSE IS LOAD-BEARING. Without it the predicate comes from the snapshot the
      # statement opened with, so a statement that BLOCKS INSIDE ITSELF — this one waits on the
      # projects foreign-key check — would not see a revocation committing during that block, and the
      # safety of the mechanism would rest on an unwritten enumeration of who else might hold a
      # conflicting lock. `FOR KEY SHARE` makes an epoch advance conflict with this read, so it must
      # either land before the statement (predicate fails) or after it (the write was authorised when
      # it happened).
      #
      # A ZERO ROW COUNT HERE MEANS EXACTLY ONE THING. Unlike the cancellation UPDATE, this statement
      # carries no state or version predicate — a queued Crawl is new — so the only way it can insert
      # nothing is that authority moved. The caller therefore needs no disambiguation, and none is
      # invented.
      def insert_crawl(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:project_id],
          row[:kind], row[:requested_crawl_policy_id], row[:requested_crawl_policy_version],
          row[:requested_entitlement_policy_id], row[:requested_entitlement_policy_version],
          row[:trigger_kind], row[:triggered_by_account_id], bytea(row[:idempotency_key_digest]),
          row.fetch(:authorization_epoch)
        ]
        inserted = exec(<<~SQL, params).cmd_tuples
          INSERT INTO crawls
            (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id, kind,
             parent_evaluation_id, parent_crawl_id, requested_crawl_policy_id, requested_crawl_policy_version,
             requested_entitlement_policy_id, requested_entitlement_policy_version, entitlement_decision_id,
             entitlement_reservation_id, trigger_kind, triggered_by_account_id, queued_at, started_at,
             terminal_at, deadline_at, state, coverage_status, completion_reason, limit_counters,
             retry_generation, recovery_generation, recovery_of_id, idempotency_key_digest)
          SELECT $1::uuid,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6,
                 NULL,NULL,$7::uuid,$8,$9::uuid,$10,NULL,NULL,$11,$12::uuid,$2::timestamptz,NULL,
                 NULL,NULL,'queued',NULL,NULL,'{}'::jsonb,0,0,NULL,$13
          WHERE EXISTS (
            SELECT 1 FROM organizations
            WHERE id = $4::uuid AND authorization_epoch = $14::bigint
            FOR KEY SHARE
          )
        SQL
        { authorized: inserted.positive?, inserted: }
      end

      def insert_crawl_source(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:project_id],
          row[:crawl_id], row[:source_id], row[:source_state_version], row[:scope_policy_id],
          row[:scope_policy_version], row[:canonical_root_uri], row[:source_order]
        ]
        exec(<<~SQL, params)
          INSERT INTO crawl_sources
            (id, created_at, correlation_id, organization_id, project_id, crawl_id, source_id,
             source_state_version, scope_policy_id, scope_policy_version, canonical_root_uri, source_order)
          VALUES ($1::uuid,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7::uuid,$8,$9::uuid,$10,$11,$12)
        SQL
      end

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
          VALUES ($1,'1.0',$2::timestamptz,$2::timestamptz,$3::date,$4::uuid,'WF-005',
                  $5::uuid,$6::uuid,$7::uuid,$8::uuid,$9,$10::uuid,$11,$12,$13,'restricted',$14::jsonb,$15,'security_audit')
        SQL
      end

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
          VALUES ($1,'1.0',$2::timestamptz,$3,'1.0','WF-005',$4,
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
