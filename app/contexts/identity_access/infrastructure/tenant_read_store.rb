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

      # QRY-022 CrawlCollection. The Evaluation each run opened is joined in rather than
      # fetched per row: its state is what decides whether the Project can be crawled
      # again, so a list that omitted it would leave the reader unable to tell a run that
      # is still holding the queue from one that has released it.
      def crawls(organization_id:, project_id:, limit: 50)
        exec(<<~SQL, [organization_id, project_id, limit]).to_a
          SELECT c.id, c.kind, c.trigger_kind, c.state, c.coverage_status, c.completion_reason,
                 c.created_at, c.queued_at, c.started_at, c.terminal_at,
                 e.state AS evaluation_state, e.reason AS evaluation_reason,
                 (SELECT count(*) FROM documents d WHERE d.crawl_id = c.id) AS document_count
          FROM crawls c
          LEFT JOIN evaluations e
            ON e.crawl_id = c.id AND e.organization_id = c.organization_id AND e.kind = 'initial'
          WHERE c.organization_id = $1::uuid AND c.project_id = $2::uuid
          ORDER BY c.created_at DESC, c.id DESC
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
          SELECT e.id, e.kind, e.state, e.reason, e.created_at, e.started_at, e.completed_at, e.failed_at,
                 s.readiness_status, s.coverage_status, s.successful_count, s.failed_count
          FROM evaluations e
          LEFT JOIN evaluation_input_snapshots s
            ON s.evaluation_id = e.id AND s.organization_id = e.organization_id
          WHERE e.organization_id = $1::uuid AND e.crawl_id = $2::uuid AND e.kind = 'initial'
          ORDER BY e.created_at ASC, e.id ASC LIMIT 1
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

      # ---- WF-007 evaluation output -------------------------------------------------
      #
      # Read as PERSISTED, with no derivation in SQL. The screen's job is to state what the
      # Evaluation decided; recomputing an outcome, a band or a score here would create a
      # second answer to a question the Check Result already answers, and the two could
      # disagree.

      # Every terminal Check Result, in the Catalog's own order. `execution_status` and
      # `error_reason_code` are returned unmodified because they are the exact distinction
      # the screen has to draw: a `failed` Result is a finding, an `error` is evidence that
      # was missing or indeterminate, and `not_applicable` is neither.
      def evaluation_check_results(organization_id:, evaluation_id:)
        exec(<<~SQL, [organization_id, evaluation_id]).to_a
          SELECT r.check_definition_id, r.check_definition_version, r.pillar_id, r.execution_status,
                 r.outcome_code, r.error_reason_code, r.impact_band, r.effort_band, r.effort_basis,
                 r.confidence_value, r.confidence_band, r.confidence_status, r.subject_set_complete,
                 r.canonical_subject_type, r.canonical_subject_key, r.normalized_observation,
                 r.recommendation_template_id, r.produced_at, e.ordering
          FROM check_results r
          JOIN check_applicability_entries e ON e.id = r.applicability_entry_id
          WHERE r.organization_id = $1::uuid AND r.evaluation_id = $2::uuid
          ORDER BY e.ordering
        SQL
      end

      # The applicability seal's own count of what was EXPECTED, so the screen can say
      # "7 of 7 checks ran" from two independent numbers rather than from one it assumes.
      def evaluation_applicability(organization_id:, evaluation_id:)
        exec(<<~SQL, [organization_id, evaluation_id]).to_a.first
          SELECT id, check_catalog_version, entry_count, local_presence_applicable,
                 local_presence_reason, project_profile_version, sealed_at
          FROM check_applicability_snapshots
          WHERE organization_id = $1::uuid AND evaluation_id = $2::uuid
        SQL
      end

      def evaluation_issues(organization_id:, evaluation_id:)
        exec(<<~SQL, [organization_id, evaluation_id]).to_a
          SELECT id, issue_type, check_definition_id, pillar_id, canonical_subject_type,
                 canonical_subject_key, impact_band, effort_band, confidence_band, confidence_status,
                 state, adjudication_status, publication_status, recommendation_template_id, created_at
          FROM issues
          WHERE organization_id = $1::uuid AND evaluation_id = $2::uuid
          ORDER BY
            CASE impact_band WHEN 'critical' THEN 0 WHEN 'high' THEN 1 WHEN 'medium' THEN 2
                             WHEN 'low' THEN 3 ELSE 4 END,
            check_definition_id, canonical_subject_key
        SQL
      end

      def evaluation_issue_set(organization_id:, evaluation_id:)
        exec(<<~SQL, [organization_id, evaluation_id]).to_a.first
          SELECT id, member_count, current_leaf_count, sealed_at
          FROM issue_sets
          WHERE organization_id = $1::uuid AND evaluation_id = $2::uuid
        SQL
      end

      private

      def exec(sql, params) = @pg.exec_params(sql, params)
    end
  end
end
