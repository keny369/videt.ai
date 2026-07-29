# frozen_string_literal: true

module IdentityAccess
  module Infrastructure
    # The one read of a Crawl's governing policies (WORKFLOW_SPECIFICATIONS.md :390).
    #
    # It had grown three copies across the stores that need it, and S-07-008 added a reason they
    # must not drift apart: `content_sha256` is now part of what an event asserts, so a store that
    # selects four of the five columns produces an `EventGoverningVersion` that cannot be built.
    # One definition means adding a column is one edit, not a hunt.
    #
    # Mixed in rather than injected because each store already owns its own connection and its own
    # transaction discipline; this is a query, not a collaborator.
    module ActiveCrawlPolicies
      # Organization-scope policies plus this Project's, most general first — `crawl_policies_active_unique`
      # admits at most one active row per scope, so the result is at most [organization, project].
      def active_crawl_policies(organization_id, project_id)
        active_crawl_policies_sql(organization_id, project_id).to_a
      end

      private

      def active_crawl_policies_sql(organization_id, project_id)
        @pg.exec_params(<<~SQL, [organization_id, project_id])
          SELECT id, policy_version, scope, normalized_bounds,
                 encode(content_sha256,'hex') AS content_sha256
          FROM crawl_policies
          WHERE organization_id = $1::uuid AND state = 'active'
            AND ((scope = 'project' AND project_id = $2::uuid) OR scope = 'organization')
          ORDER BY (scope = 'project') ASC
        SQL
      end
    end
  end
end
