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

      # The single Source behind the verification screen. `state_version` is read here
      # because every WF-003/WF-004 command this screen submits is version-guarded: the
      # row the user acted on is the row the command must find.
      def source(organization_id:, project_id:, source_id:)
        exec(<<~SQL, [organization_id, project_id, source_id]).to_a.first
          SELECT id, submitted_root_uri, canonical_root_uri, canonical_host, state,
                 registered_at, verified_at, activated_at, state_version
          FROM sources
          WHERE organization_id = $1::uuid AND project_id = $2::uuid AND id = $3::uuid
        SQL
      end

      # QRY-021 PendingVerificationChallenge (APPLICATION_LAYER.md :172): the Verification
      # Request currently governing a Source, with its delivery and attempt metadata.
      #
      # It carries NO challenge material and cannot: the plaintext token is never a
      # column. `challenge_token_sha256` and `challenge_ciphertext_reference` are
      # deliberately absent from the projection — the token reaches a user only through
      # the authorized IssueVerificationChallenge response or its audited replay, so a
      # read model that returned it would be a second, unaudited disclosure path.
      #
      # The newest Request wins. A Source may accumulate terminal Requests (expired,
      # cancelled) before a later one verifies it, and the screen speaks about the
      # current one.
      def verification_request(organization_id:, source_id:)
        exec(<<~SQL, [organization_id, source_id]).to_a.first
          SELECT id, method, canonical_host, request_status, request_initiator_account_id,
                 issued_at_utc, expires_at_utc, attempt_count, on_demand_observation_count,
                 on_demand_in_progress_attempt_id, last_on_demand_completed_at_utc,
                 last_observed_at_utc, decision_reason_code, state_version
          FROM verification_requests
          WHERE organization_id = $1::uuid AND source_id = $2::uuid
          ORDER BY issued_at_utc DESC, id DESC
          LIMIT 1
        SQL
      end

      # The observation history behind a Request, newest first. Every column here is
      # already restricted-safe: enums, counts and statuses, never the observed content.
      def verification_attempts(organization_id:, verification_request_id:, limit: 20)
        exec(<<~SQL, [organization_id, verification_request_id, limit]).to_a
          SELECT id, attempt_number, origin, state, reserved_at_utc, completed_at_utc,
                 network_outcome, http_status, match_decision, reason_code
          FROM verification_attempts
          WHERE organization_id = $1::uuid AND verification_request_id = $2::uuid
          ORDER BY attempt_number DESC, id DESC
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

      # QRY-023 CrawlDetail (APPLICATION_LAYER.md :174): "Crawl, Source/URL outcome and
      # stage summary projection". The four reads below are that projection — the run
      # itself, the Sources it was pinned to, what it fetched, and what it produced.
      #
      # A Crawl with no rows in the child tables is a real and common answer, not an
      # error: a run that could not resolve its host has attempts and no Documents, and
      # a run that has not started yet has neither. The screen says so rather than
      # implying the data is missing.
      def crawl(organization_id:, project_id:, crawl_id:)
        exec(<<~SQL, [organization_id, project_id, crawl_id]).to_a.first
          SELECT id, kind, trigger_kind, state, coverage_status, completion_reason,
                 created_at, queued_at, started_at, terminal_at, deadline_at,
                 requested_crawl_policy_version, retry_generation, recovery_generation
          FROM crawls
          WHERE organization_id = $1::uuid AND project_id = $2::uuid AND id = $3::uuid
        SQL
      end

      # The Sources a Crawl was pinned to at admission, with the scope policy version each
      # was pinned at. This is why a Crawl's coverage cannot silently change underneath it.
      def crawl_sources(organization_id:, crawl_id:)
        exec(<<~SQL, [organization_id, crawl_id]).to_a
          SELECT source_id, canonical_root_uri, scope_policy_version, source_order
          FROM crawl_sources
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
          ORDER BY source_order ASC
        SQL
      end

      # Every fetch the run made, newest first. `reason_code` is the fetch's own outcome
      # vocabulary, never a message composed here.
      def fetch_attempts(organization_id:, crawl_id:, limit: 100)
        exec(<<~SQL, [organization_id, crawl_id, limit]).to_a
          SELECT id, request_kind, canonical_url, attempt_number, depth, outcome, reason_code,
                 http_status, media_type, accounted_response_bytes, redirect_count,
                 latency_ms, completed_at
          FROM fetch_attempts
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
          ORDER BY completed_at DESC NULLS LAST, created_at DESC, id DESC
          LIMIT $3
        SQL
      end

      # What the run actually produced. A Document is the unit a later Evaluation reads,
      # so this is the answer to "did the crawl get me anything".
      def crawl_documents(organization_id:, crawl_id:, limit: 100)
        exec(<<~SQL, [organization_id, crawl_id, limit]).to_a
          SELECT id, canonical_url, version, media_type, byte_size, state,
                 discovered_at, ingested_at, transition_reason_code
          FROM documents
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
          ORDER BY discovered_at DESC, id DESC
          LIMIT $3
        SQL
      end

      # The Evaluation a Crawl opened, and how it resolved. `reason` is the workflow's own
      # reason code, never a sentence composed in SQL.
      def crawl_evaluation(organization_id:, crawl_id:)
        exec(<<~SQL, [organization_id, crawl_id]).to_a.first
          SELECT id, kind, state, reason, created_at, started_at, completed_at, failed_at
          FROM evaluations
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid AND kind = 'initial'
          ORDER BY created_at ASC, id ASC LIMIT 1
        SQL
      end

      # The OD-018 queue-time guard, read for the screen rather than discovered by pressing
      # a button WF-005 will refuse: a Project with a pending or running `initial`
      # Evaluation cannot queue another Crawl.
      #
      # This is the same predicate `QueueCrawl` evaluates, so the screen states the
      # workflow's own precondition and not an approximation of it.
      def initial_evaluation_in_flight?(organization_id:, project_id:)
        exec(<<~SQL, [organization_id, project_id]).to_a.first["n"].to_i.positive?
          SELECT COUNT(*) AS n FROM evaluations
          WHERE organization_id = $1::uuid AND project_id = $2::uuid AND kind = 'initial'
            AND state IN ('pending','running')
        SQL
      end

      # The per-URL terminal record: the decided outcome of each frontier entry and what
      # it did to coverage. This is the row that explains a run with no Documents — a
      # host that could not serve robots.txt terminates here with `not_covered` and
      # nothing else to show, and the screen has to be able to say so.
      def crawl_terminal_outcomes(organization_id:, crawl_id:, limit: 100)
        exec(<<~SQL, [organization_id, crawl_id, limit]).to_a
          SELECT commit_order, outcome, reason, coverage_effect, document_id,
                 accounted_response_body_bytes, decided_at
          FROM crawl_terminal_outcomes
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
          ORDER BY commit_order ASC
          LIMIT $3
        SQL
      end

      private

      def exec(sql, params) = @pg.exec_params(sql, params)
    end
  end
end
