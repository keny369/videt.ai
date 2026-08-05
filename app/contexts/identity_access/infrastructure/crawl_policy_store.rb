# frozen_string_literal: true

require "json"

module IdentityAccess
  module Infrastructure
    # Persistence for WF-005 ActivateCrawlPolicy (S-07-001), written in the actor's unit of
    # work inside the proved Organization context. The dedicated `crawl_policies` table (owner
    # D1, DECISIONS ADR-068) mirrors the source_scope_policies shape: immutable content, a
    # single active -> superseded lifecycle edge. It reuses ActorLedgerWriters and overrides
    # only the two writers that stamp `workflow_id` = 'WF-005'.
    class CrawlPolicyStore
      include ActorLedgerWriters

      def initialize(pg_connection)
        @pg = pg_connection
      end

      # Serialize ALL crawl-policy activations for one Organization (organization AND project
      # scope) so a project activation cannot race an Organization-scope supersession of its
      # parent, and exactly one new version per scope wins; the loser's expected-version guard
      # then fails cleanly. Crawl-policy activation is a rare administrative operation, so a
      # single per-Organization lock is ample and avoids the cross-scope race (ADR-026 NB-1).
      def lock_organization(organization_id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["crawl-policy:#{organization_id}"])
      end

      # The current active crawl policy version for the scope, or nil (project_id NULL for
      # organization scope; IS NOT DISTINCT FROM matches NULL to NULL).
      def active_policy(organization_id, scope, project_id)
        exec(<<~SQL, [organization_id, scope, project_id]).to_a.first
          SELECT id, state_version, policy_version, scope, normalized_bounds,
                 encode(content_sha256,'hex') AS content_hex
          FROM crawl_policies
          WHERE organization_id = $1::uuid AND scope = $2
            AND project_id IS NOT DISTINCT FROM $3::uuid AND state = 'active'
        SQL
      end

      # The number of existing versions for the scope — the ordinal a new version takes
      # (crawl-policy-{scope}-v{N}); read under the per-scope lock.
      def version_count(organization_id, scope, project_id)
        exec(<<~SQL, [organization_id, scope, project_id]).to_a.first["n"].to_i
          SELECT COUNT(*) AS n FROM crawl_policies
          WHERE organization_id = $1::uuid AND scope = $2 AND project_id IS NOT DISTINCT FROM $3::uuid
        SQL
      end

      # POLICY ACTIVATION IS ONE STATEMENT, AND IT CARRIES ITS OWN AUTHORITY CHECK.
      #
      # WHY ONE STATEMENT. The transition is two writes — supersede the prior active version, insert
      # the new one — and the scope's one-active-per-scope partial-unique index means a half-applied
      # transition is a corrupt scope: superseded with nothing active, or two active rows. Run as two
      # statements with authority tested in each, a revocation landing BETWEEN them denies the second
      # while the first stands. Run as two statements with authority tested in Ruby, the test can be
      # hoisted, reordered or deleted. Neither is acceptable, so the supersede and the insert are one
      # statement whose data-modifying CTEs share a single evaluation of one authority predicate.
      # PostgreSQL applies both or neither, and `inserted` depends on `superseded`, which forces the
      # order rather than leaving it to the planner.
      #
      # WHY THE PREDICATE IS ORDINARY ROW STATE. `authority_current?` is, in full,
      # "`organizations.authorization_epoch` equals the epoch the actor authenticated with", so it
      # belongs in the statement that depends on it. There is then no handler-level check to hoist and
      # no list of which handlers must remember to perform one.
      #
      # THE THREE OUTCOMES ARE REPORTED SEPARATELY because the contract distinguishes them: authority
      # that moved is a DOMAIN DENIAL, a prior version that would not supersede is a LOST SERIALIZED
      # TRANSITION the handler raises on, and a successful pair is the transition.
      def activate_version(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:project_id],
          row[:scope], row[:policy_version], row[:supersedes_id], row[:activated_by_account_id],
          JSON.generate(row[:normalized_bounds]), bytea(row[:content_sha256]),
          row[:expected_state_version], row.fetch(:authorization_epoch)
        ]
        result = exec(<<~SQL, params).to_a.first
          WITH authority AS (
            SELECT 1 FROM organizations
            WHERE id = $4::uuid AND authorization_epoch = $13::bigint
            FOR KEY SHARE
          ), superseded AS (
            UPDATE crawl_policies
            SET state = 'superseded', superseded_at = $2::timestamptz,
                state_version = state_version + 1, updated_at = $2::timestamptz
            WHERE $8::uuid IS NOT NULL AND id = $8::uuid AND state = 'active'
              AND state_version = $12::int
              -- THE SUPERSEDED ROW MUST BELONG TO THE SCOPE BEING ACTIVATED.
              --
              -- Without these three predicates the CTE matched on `id` alone, so a `supersedes_id`
              -- naming another scope's active version superseded THAT scope and activated this one,
              -- reporting {authorized: true, superseded: 1, inserted: 1} — a fully successful
              -- transition by every signal the caller has, leaving the other scope with ZERO active
              -- versions. `f1_crawl_policies_guard` makes a superseded row terminal, so the emptied
              -- scope cannot be restored, only re-activated. RLS barred the cross-TENANT case; nothing
              -- barred the cross-SCOPE one, and the store must hold its own contract rather than
              -- depend on the one caller that happens to derive the id correctly.
              AND organization_id = $4::uuid
              AND scope = $6
              AND project_id IS NOT DISTINCT FROM $5::uuid
              AND EXISTS (SELECT 1 FROM authority)
            RETURNING 1
          ), inserted AS (
            INSERT INTO crawl_policies
              (id, state_version, created_at, updated_at, correlation_id, schema_version, organization_id,
               project_id, scope, policy_version, state, supersedes_id, activated_by_account_id,
               normalized_bounds, content_sha256, superseded_at)
            SELECT $1,0,$2::timestamptz,$2::timestamptz,$3::uuid,'crawl-policy-v1',$4::uuid,
                   $5::uuid,$6,$7,'active',$8::uuid,$9::uuid,$10::jsonb,$11,NULL
            WHERE EXISTS (SELECT 1 FROM authority)
              AND ($8::uuid IS NULL OR EXISTS (SELECT 1 FROM superseded))
            RETURNING 1
          )
          SELECT (SELECT count(*) FROM authority) AS authorized,
                 (SELECT count(*) FROM superseded) AS superseded,
                 (SELECT count(*) FROM inserted) AS inserted
        SQL
        { authorized: result["authorized"].to_i.positive?,
          superseded: result["superseded"].to_i, inserted: result["inserted"].to_i }
      end

      # WF-005 audit writer — ActorLedgerWriters row shape stamped 'WF-005'.
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

      # WF-005 event writer — ActorLedgerWriters row shape stamped 'WF-005'.
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
