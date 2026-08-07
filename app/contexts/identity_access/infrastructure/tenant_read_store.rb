# frozen_string_literal: true

module IdentityAccess
  module Infrastructure
    # The read side for the authorized product screens (APPLICATION_LAYER.md § Repository
    # Contracts: "Query read stores are separate interfaces optimized for authorized DTO
    # materialization; they cannot be passed into a command handler").
    #
    # Every statement here runs inside the proved Organization context that
    # Platform::AuthenticatedRequest established, so tenant scoping is enforced by row
    # level security in the database rather than by a WHERE clause a query could forget.
    # The `organization_id = $1` predicates below are therefore belt-and-braces, not the
    # control: if RLS were the only thing standing between two tenants, a single missing
    # predicate would be a cross-tenant read, and if the predicate were the only thing,
    # so would a single missing context.
    class TenantReadStore
      def initialize(pg_connection)
        @pg = pg_connection
      end

      # QRY-001 OrganizationHome: the Session-bound destination shell. Deliberately no
      # Project, notice or administration collection — each of those is its own screen
      # behind its own named read contract.
      def organization_home(organization_id)
        exec(<<~SQL, [organization_id]).to_a.first
          SELECT id, display_name, status, default_locale, reporting_time_zone, authorization_epoch
          FROM organizations
          WHERE id = $1::uuid
        SQL
      end

      def account(account_id)
        exec("SELECT id, normalized_email, display_name, status FROM accounts WHERE id = $1::uuid",
             [account_id]).to_a.first
      end

      # QRY-002 ProjectCollection. Ordered by creation with the canonical UUID
      # tie-breaker, so a page boundary is stable when two Projects share an instant.
      def projects(organization_id:, limit: 50)
        exec(<<~SQL, [organization_id, limit]).to_a
          SELECT id, display_name, state, objective, locale, time_zone, created_at, source_set_version
          FROM projects
          WHERE organization_id = $1::uuid
          ORDER BY created_at DESC, id DESC
          LIMIT $2
        SQL
      end

      def project(organization_id:, project_id:)
        exec(<<~SQL, [organization_id, project_id]).to_a.first
          SELECT id, display_name, state, objective, locale, time_zone, created_at, source_set_version
          FROM projects
          WHERE organization_id = $1::uuid AND id = $2::uuid
        SQL
      end

      # QRY-004 SourceCollection.
      def sources(organization_id:, project_id:, limit: 100)
        exec(<<~SQL, [organization_id, project_id, limit]).to_a
          SELECT id, submitted_root_uri, canonical_root_uri, canonical_host, state,
                 registered_at, verified_at, activated_at
          FROM sources
          WHERE organization_id = $1::uuid AND project_id = $2::uuid
          ORDER BY registered_at DESC, id DESC
          LIMIT $3
        SQL
      end

      # QRY-022 CrawlCollection.
      def crawls(organization_id:, project_id:, limit: 50)
        exec(<<~SQL, [organization_id, project_id, limit]).to_a
          SELECT id, kind, trigger_kind, state, coverage_status, completion_reason,
                 created_at, queued_at, started_at, terminal_at
          FROM crawls
          WHERE organization_id = $1::uuid AND project_id = $2::uuid
          ORDER BY created_at DESC, id DESC
          LIMIT $3
        SQL
      end

      private

      def exec(sql, params) = @pg.exec_params(sql, params)
    end
  end
end
