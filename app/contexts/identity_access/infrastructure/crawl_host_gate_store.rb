# frozen_string_literal: true

require "digest"
require "json"

module IdentityAccess
  module Infrastructure
    # Persistence for the S-07-005 per-host gate (schemas/POSTGRESQL_SCHEMA.md :296;
    # WORKFLOW_SPECIFICATIONS.md :442/:448; SEARCH_CRAWL_RETRIEVAL.md § Robots And Sitemap
    # Processing and the run/per-host gate paragraph).
    #
    # SEARCH_CRAWL_RETRIEVAL is explicit about the mechanism: "The run and per-host gates use
    # PostgreSQL `clock_timestamp()` and row locks. A worker cannot start merely because Redis
    # granted a token. It claims a host slot only when the rolling-start and concurrency predicates
    # pass, commits `submission_started`, then connects."
    #
    # So every predicate here is evaluated IN THE DATABASE, against `clock_timestamp()` (real elapsed
    # time, not the transaction snapshot — a rolling one-second window must not freeze for the life
    # of a transaction), under `SELECT ... FOR UPDATE` on the gate row. No application clock and no
    # cached counter participates in the decision.
    class CrawlHostGateStore
      def initialize(pg_connection)
        @pg = pg_connection
      end

      def enter_org_context(org:, correlation_id:)
        query("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, correlation_id]).values.dig(0, 0)
      end

      # Create the gate for `(crawl, canonical_host)` if it does not exist, and return it. Idempotent
      # under the unique key, so concurrent workers discovering the same host converge on one row.
      def ensure_gate(row)
        digest = Digest::SHA256.digest(row[:canonical_host])
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id],
                  row[:project_id], row[:crawl_id], row[:canonical_host], bytea(digest)]
        query(<<~SQL, params)
          INSERT INTO crawl_host_gates
            (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id,
             crawl_id, canonical_host, canonical_host_sha256, robots_state)
          VALUES ($1::uuid,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,
                  $6::uuid,$7,$8,'pending')
          ON CONFLICT (crawl_id, canonical_host_sha256) DO NOTHING
        SQL
        gate(row[:organization_id], row[:crawl_id], row[:canonical_host])
      end

      def gate(organization_id, crawl_id, canonical_host)
        query(<<~SQL, [organization_id, crawl_id, bytea(Digest::SHA256.digest(canonical_host))]).to_a.first
          SELECT * FROM crawl_host_gates
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid AND canonical_host_sha256 = $3
        SQL
      end

      # The columns the LOCKED read needs, named explicitly. `SELECT g.*` would ship the audit
      # payloads (`sitemap_candidates`, `sitemap_discarded`, `sitemap_skipped`,
      # `robots_sitemap_candidates`) on a path that runs under an exclusive row lock before EVERY
      # fetch, where every other worker on that host is queued behind it — reviewed at ~15 ms of
      # lock-held detoast per read for a robots file naming many sitemaps. Nothing on the
      # authorization path reads them, so the bulk never travels here.
      # EXCLUDED, deliberately and exhaustively: `sitemap_candidates`, `sitemap_discarded`,
      # `sitemap_skipped`, `sitemap_limit_reasons`, `robots_sitemap_candidates`, `active_leases`.
      # Every other column is included, so a reader that needs one is never surprised by a nil — the
      # failure mode when this list was derived from "what the gate decision needs" rather than from
      # "everything except the bulk".
      LOCKED_COLUMNS = %w[
        id state_version created_at updated_at correlation_id organization_id project_id crawl_id
        canonical_host canonical_host_sha256
        robots_state robots_terminal_reason robots_terminal_at robots_http_status robots_rules
        robots_rules_schema robots_agent_group robots_crawl_delay_ms robots_source_sha256
        robots_attempt_count robots_attempt_started_at robots_generation
        next_allowed_start_at recent_start_instants active_connection_count lease_version
        sitemap_state sitemap_outcome_reason sitemap_terminal_at sitemap_documents_fetched
        sitemap_max_index_depth sitemap_claim_token sitemap_attempt_started_at
      ].freeze

      # The gate row under a WRITE lock, with `clock_timestamp()` alongside it so the caller decides
      # against the same real instant the predicates used. Blocks rather than skipping: two workers
      # contending for one host must serialize, not both proceed.
      def lock_gate(organization_id, id)
        query(<<~SQL, [organization_id, id]).to_a.first
          SELECT #{LOCKED_COLUMNS.map { |c| "g.#{c}" }.join(', ')}, clock_timestamp() AS observed_at,
                 -- the rolling half-open window (:442): starts strictly after now-1s, through now
                 (SELECT COUNT(*) FROM unnest(g.recent_start_instants) AS s
                  WHERE s > clock_timestamp() - interval '1 second' AND s <= clock_timestamp()) AS window_starts,
                 (g.next_allowed_start_at IS NULL OR g.next_allowed_start_at <= clock_timestamp()) AS delay_elapsed,
                 -- How long the caller must actually wait. A fixed retry constant is wrong here:
                 -- the interval is max(base, robots Crawl-delay, ...), and a host declaring
                 -- `Crawl-delay: 10` needs ten seconds, not 250 ms. Reporting the real remainder is
                 -- what stops a bounded retry loop from expiring on a perfectly reachable host.
                 GREATEST(0, CEIL(EXTRACT(EPOCH FROM
                   (COALESCE(g.next_allowed_start_at, clock_timestamp()) - clock_timestamp())) * 1000))::bigint
                   AS delay_remaining_ms
          FROM crawl_host_gates g
          WHERE g.organization_id = $1::uuid AND g.id = $2::uuid
          FOR UPDATE
        SQL
      end

      # A lease older than this is presumed lost with its worker and is reclaimed
      # (SEARCH_CRAWL_RETRIEVAL :82 "Process loss after claim is repaired by the lease sweeper").
      # Generously longer than the hard per-request timeout, so a slow-but-live request is never
      # reclaimed out from under itself.
      LEASE_STALE_SECONDS = 120

      # Commit a claimed slot: append this start to the rolling window (trimming anything already
      # outside it), advance the crawl-delay floor, and add an IDENTIFIED lease. Guarded on the
      # expected version so a lost race can never double-claim.
      #
      # The same statement sweeps leases older than `LEASE_STALE_SECONDS`, so reclamation needs no
      # separate scheduled job and cannot itself be lost: every claim repairs the accounting it is
      # about to rely on. `active_connection_count` is derived from the surviving lease set, so the
      # counter and the leases can never disagree.
      # EVERY LEASE STATEMENT COMPUTES THE SURVIVING SET FROM THE TARGET ROW'S OWN COLUMN, in a
      # correlated sub-select, NEVER from a `WITH` clause.
      #
      # This is not a style preference. Under READ COMMITTED a `WITH live AS (SELECT ... FROM
      # crawl_host_gates ...)` is evaluated once from the statement's snapshot. When the UPDATE then
      # blocks on a row another transaction is updating, EvalPlanQual re-fetches the new row version
      # and re-evaluates the QUALS and the TARGETLIST against it — but the CTE is a separate join
      # input and is NOT recomputed. The statement therefore writes a lease array assembled from the
      # row as it looked BEFORE the concurrent claim, destroying a lease belonging to a worker that
      # is at that moment connecting. Reviewed end-to-end: the accounted count drifted to 0 with
      # three workers genuinely in flight, and the gate then granted two more claims — five real
      # connections against a nonexceedable ceiling of four (:442).
      #
      # A correlated sub-select over `crawl_host_gates.active_leases` IS part of the targetlist, so
      # EPQ recomputes it against the updated tuple — the same reason `SET n = n + 1` is safe.
      def claim_slot(id, expected_version, interval_ms, token, now)
        params = [id, expected_version, interval_ms.to_i, token, iso(now), LEASE_STALE_SECONDS]
        query(<<~SQL, params).to_a.first
          UPDATE crawl_host_gates
          SET recent_start_instants =
                (SELECT COALESCE(array_agg(s), ARRAY[]::timestamptz(6)[])
                 FROM unnest(recent_start_instants) AS s
                 WHERE s > clock_timestamp() - interval '1 second') || clock_timestamp(),
              next_allowed_start_at = clock_timestamp() + ($3 || ' milliseconds')::interval,
              active_leases = #{live_leases("$5", "$6")} ||
                              jsonb_build_object('token', $4::text, 'claimed_at', $5::text),
              active_connection_count = jsonb_array_length(#{live_leases("$5", "$6")}) + 1,
              lease_version = lease_version + 1,
              state_version = state_version + 1,
              updated_at = clock_timestamp()
          WHERE id = $1::uuid AND state_version = $2
          RETURNING id, lease_version, active_connection_count, next_allowed_start_at
        SQL
      end

      # The leases on THIS row that are not yet stale, as a correlated sub-select. `crawl_host_gates`
      # here refers to the row being updated, so EvalPlanQual re-evaluates it after a blocked update.
      def self.live_leases(now_param, stale_param)
        <<~SQL.strip
          COALESCE((SELECT jsonb_agg(l) FROM jsonb_array_elements(crawl_host_gates.active_leases) AS l
                    WHERE (l->>'claimed_at')::timestamptz >
                          #{now_param}::timestamptz - (#{stale_param} || ' seconds')::interval), '[]'::jsonb)
        SQL
      end

      def live_leases(now_param, stale_param) = self.class.live_leases(now_param, stale_param)

      # Release the slot a specific TOKEN holds. Removing a token is idempotent — a second release of
      # the same claim removes nothing — and it can only ever release the claim it names, so one
      # worker can no longer drop another's slot and silently widen the nonexceedable ceiling.
      def release_slot(id, token, now)
        remaining = <<~SQL.strip
          COALESCE((SELECT jsonb_agg(l) FROM jsonb_array_elements(crawl_host_gates.active_leases) AS l
                    WHERE l->>'token' <> $2::text), '[]'::jsonb)
        SQL
        query(<<~SQL, [id, token, iso(now)]).to_a.first
          UPDATE crawl_host_gates
          SET active_leases = #{remaining},
              active_connection_count = jsonb_array_length(#{remaining}),
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid
          RETURNING active_connection_count
        SQL
      end

      # Reclaim every lease older than the stale bound, without claiming. Exposed so a sweeper or a
      # health check can repair a host no worker is currently claiming on.
      def sweep_leases(id, now)
        params = [id, iso(now), LEASE_STALE_SECONDS]
        query(<<~SQL, params).to_a.first
          UPDATE crawl_host_gates
          SET active_leases = #{live_leases("$2", "$3")},
              active_connection_count = jsonb_array_length(#{live_leases("$2", "$3")}),
              state_version = state_version + 1, updated_at = $2::timestamptz
          WHERE id = $1::uuid
            AND jsonb_array_length(#{live_leases("$2", "$3")}) <> active_connection_count
          RETURNING active_connection_count
        SQL
      end

      # An `in_progress` attempt older than this is presumed lost with its worker and may be
      # reclaimed. It is generously longer than the request timeout plus the retry schedule, so a
      # slow-but-live attempt is never stolen from underneath itself.
      ATTEMPT_STALE_SECONDS = 300

      # pending -> in_progress for one robots attempt, guarded on the version. Also RECLAIMS a stale
      # `in_progress` attempt: the claim commits in its own transaction (no external call may sit
      # inside one), so a process lost between the claim and the outcome would otherwise leave the
      # host wedged — never resolved, never failed closed, and every content fetch on it refused for
      # the life of the run. Reclaiming is safe because the terminal decision is write-once: a
      # reclaimed attempt can only ever reach the same terminal states, never reopen one.
      def begin_robots(id, expected_version, now)
        params = [id, expected_version, iso(now), ATTEMPT_STALE_SECONDS]
        query(<<~SQL, params).cmd_tuples
          UPDATE crawl_host_gates
          SET robots_state = 'in_progress', robots_attempt_count = robots_attempt_count + 1,
              robots_generation = robots_generation + 1, robots_attempt_started_at = $3::timestamptz,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state_version = $2
            AND (robots_state = 'pending'
                 OR (robots_state = 'in_progress'
                     AND robots_attempt_started_at IS NOT NULL
                     AND robots_attempt_started_at < $3::timestamptz - ($4 || ' seconds')::interval))
        SQL
      end

      # in_progress -> pending, for a retryable attempt that has not exhausted its schedule (:444).
      def defer_robots(id, expected_version, now)
        query(<<~SQL, [id, expected_version, iso(now)]).cmd_tuples
          UPDATE crawl_host_gates
          SET robots_state = 'pending', state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND robots_state = 'in_progress' AND state_version = $2
        SQL
      end

      # in_progress -> a TERMINAL robots decision. Write-once: the guard refuses any later change to
      # these columns, so a host that failed closed can never become fetchable within the run.
      def terminalize_robots(id, expected_version, now, row)
        params = [id, expected_version, iso(now), row[:state], row[:reason], row[:http_status],
                  row[:rules] && JSON.generate(row[:rules]), row[:rules_schema], row[:agent_group],
                  row[:crawl_delay_ms], JSON.generate(row[:sitemaps] || []), bytea(row[:source_sha256])]
        query(<<~SQL, params).cmd_tuples
          UPDATE crawl_host_gates
          SET robots_state = $4, robots_terminal_reason = $5, robots_terminal_at = $3::timestamptz,
              robots_http_status = $6, robots_rules = $7::jsonb, robots_rules_schema = $8,
              robots_agent_group = $9, robots_crawl_delay_ms = $10,
              robots_sitemap_candidates = $11::jsonb, robots_source_sha256 = $12,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND robots_state = 'in_progress' AND state_version = $2
        SQL
      end

      # ---- sitemap discovery (S-07-006) -----------------------------------------

      # pending -> in_progress, recording the RESOLVED candidate set (:454-ordered, retained) and the
      # overflow. Distinct from `robots_sitemap_candidates`, which stays the raw declared list.
      #
      # GUARDED ON THE EXPECTED VERSION, exactly as the robots limb is. Without it two workers
      # discovering the same host both fell through this transition and both ran the whole traversal
      # — doubling the request volume against the very host this subsystem exists to pace. The caller
      # treats a zero row count as contention and stands down.
      # An attempt whose worker was lost this long ago may be taken over. Mirrors the robots limb's
      # `ATTEMPT_STALE_SECONDS`, and is what stops the claim guard from wedging a host for the rest of
      # the run when a traversal crashes.
      SITEMAP_ATTEMPT_STALE_SECONDS = 300

      def begin_sitemaps(id, expected_version, now, retained, discarded, token)
        params = [id, expected_version, iso(now), JSON.generate(retained), JSON.generate(discarded),
                  token, SITEMAP_ATTEMPT_STALE_SECONDS]
        query(<<~SQL, params).cmd_tuples
          UPDATE crawl_host_gates
          SET sitemap_state = 'in_progress', sitemap_candidates = $4::jsonb,
              sitemap_discarded = $5::jsonb, sitemap_claim_token = $6::uuid,
              sitemap_attempt_started_at = $3::timestamptz,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state_version = $2
            AND (sitemap_state = 'pending'
                 -- Take over an attempt whose worker is presumed lost. The token ROTATES, so the
                 -- lost worker can never terminalize on top of its successor.
                 OR (sitemap_state = 'in_progress'
                     AND sitemap_attempt_started_at <
                         $3::timestamptz - ($7 || ' seconds')::interval))
        SQL
      end

      # :450 requires every skipped or failed candidate to be RECORDED, and the LIMIT subset to
      # produce `limit_reached` for the whole run. Both are written with the terminal decision, in one
      # statement, so the record can never be half-written.
      #
      # BOUND TO THE CLAIM. Matching on `in_progress` alone let a worker that lost the claim write
      # the write-once outcome for a run another worker was still executing — and the executing
      # worker's own terminalize then matched zero rows silently.
      def terminalize_sitemaps(id, token, now, state:, reason:, documents:, max_depth:,
                               skipped: [], limit_reasons: [])
        params = [id, iso(now), state, reason, documents.to_i, max_depth.to_i,
                  JSON.generate(skipped), JSON.generate(limit_reasons.uniq), token]
        query(<<~SQL, params).cmd_tuples
          UPDATE crawl_host_gates
          SET sitemap_state = $3, sitemap_outcome_reason = $4, sitemap_terminal_at = $2::timestamptz,
              sitemap_documents_fetched = $5, sitemap_max_index_depth = $6,
              sitemap_skipped = $7::jsonb, sitemap_limit_reasons = $8::jsonb,
              state_version = state_version + 1, updated_at = $2::timestamptz
          WHERE id = $1::uuid AND sitemap_state = 'in_progress' AND sitemap_claim_token = $9::uuid
        SQL
      end

      # ---- execution-time authorization reads -----------------------------------
      #
      # Every one of these is read FRESH immediately before a connection. None is cached and none is
      # carried from queue time — that is the whole point of the gate they serve.

      # Every active crawl policy applying to the Project, most specific last — the same resolution
      # StartCrawl uses. The gate needs it because WORKFLOW_SPECIFICATIONS.md :390 makes the
      # operative limits "the most restrictive of global safety, approved entitlement, Organization,
      # and Project limits", so a Project that has narrowed its per-host rate or concurrency must
      # bind at the claim — not merely at the start commit.
      def active_crawl_policies(organization_id, project_id)
        query(<<~SQL, [organization_id, project_id]).to_a
          SELECT id, policy_version, scope, normalized_bounds, encode(content_sha256,'hex') AS content_sha256
          FROM crawl_policies
          WHERE organization_id = $1::uuid AND state = 'active'
            AND ((scope = 'project' AND project_id = $2::uuid) OR scope = 'organization')
          ORDER BY (scope = 'project') ASC
        SQL
      end

      def organization(organization_id)
        query("SELECT id, status FROM organizations WHERE id = $1::uuid", [organization_id]).to_a.first
      end

      def crawl(organization_id, crawl_id)
        query(<<~SQL, [organization_id, crawl_id]).to_a.first
          SELECT id, project_id, state, entitlement_reservation_id, started_at, deadline_at
          FROM crawls WHERE organization_id = $1::uuid AND id = $2::uuid
        SQL
      end

      def project(organization_id, project_id)
        query("SELECT id, state FROM projects WHERE organization_id=$1::uuid AND id=$2::uuid",
             [organization_id, project_id]).to_a.first
      end

      # Keyed on (organization, PROJECT, source). The project predicate is what stops a Crawl in one
      # Project being authorized against another Project's Source of the same Organization —
      # POSTGRESQL_SCHEMA :128's rule expressed in the read path, where no FK can enforce it.
      def source(organization_id, project_id, source_id)
        query(<<~SQL, [organization_id, project_id, source_id]).to_a.first
          SELECT id, state, canonical_host FROM sources
          WHERE organization_id = $1::uuid AND project_id = $2::uuid AND id = $3::uuid
        SQL
      end

      # The reservation admitting this run must still be EXECUTING. A committed, released or expired
      # reservation means the run is no longer metered.
      # `executing` AND still within its effective deadline. F-05 has no `executing -> expired` edge,
      # so a dead worker's reservation stays `executing` until something reclaims it; state alone
      # would therefore keep authorizing fetches for a run whose lease and maximum-execution ceiling
      # had both passed. The deadline is the same one `Entitlement::Service#effective_deadline`
      # applies: the renewable lease, capped by started_at + the operation's maximum execution.
      # The deadline is compared against the CALLER'S `now`, not `clock_timestamp()`. F-05 owns the
      # reservation lifecycle and is `now:`-driven throughout (`Service#effective_deadline` takes the
      # instant from its caller), so this must agree with it — two surfaces judging one reservation
      # against two different clocks would disagree about whether a run is still metered. The rate
      # window is the opposite case and correctly uses `clock_timestamp()`: it measures REAL elapsed
      # time against a remote host, which no injected clock may compress.
      def reservation_executing?(organization_id, reservation_id, max_execution_seconds, now)
        return false if reservation_id.nil?

        params = [organization_id, reservation_id, max_execution_seconds.to_i, iso(now)]
        query(<<~SQL, params).to_a.first["n"].to_i.positive?
          SELECT COUNT(*) AS n FROM entitlement_reservations
          WHERE organization_id = $1::uuid AND id = $2::uuid AND state = 'executing'
            AND lease_due > $4::timestamptz
            AND (started_at IS NULL
                 OR started_at + ($3 || ' seconds')::interval > $4::timestamptz)
        SQL
      end

      # The Source's CURRENT scope policy — whichever version `sources.current_scope_policy_id`
      # names right now, never the version pinned onto the Crawl at queue time.
      def current_scope_policy(organization_id, project_id, source_id)
        query(<<~SQL, [organization_id, project_id, source_id]).to_a.first
          SELECT p.id, p.policy_version, p.canonical_host, p.allowed_schemes, p.allowed_ports,
                 p.include_prefixes, p.exclude_prefixes, p.query_handling
          FROM sources s
          JOIN source_scope_policies p ON p.id = s.current_scope_policy_id
          WHERE s.organization_id = $1::uuid AND s.project_id = $2::uuid AND s.id = $3::uuid
        SQL
      end

      private

      # Named `query` rather than `exec` deliberately: a private `exec` in a class shadows
      # `Kernel#exec`, and every statement that interpolates a SQL FRAGMENT (never a value) into a
      # heredoc then reads to a static analyser as a possible command execution. Every parameter here
      # is bound, never interpolated.
      def query(sql, params = []) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      def iso(time) = time&.getutc&.iso8601(6)
    end
  end
end
