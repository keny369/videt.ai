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
        exec("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, correlation_id]).values.dig(0, 0)
      end

      # Create the gate for `(crawl, canonical_host)` if it does not exist, and return it. Idempotent
      # under the unique key, so concurrent workers discovering the same host converge on one row.
      def ensure_gate(row)
        digest = Digest::SHA256.digest(row[:canonical_host])
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id],
                  row[:project_id], row[:crawl_id], row[:canonical_host], bytea(digest)]
        exec(<<~SQL, params)
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
        exec(<<~SQL, [organization_id, crawl_id, bytea(Digest::SHA256.digest(canonical_host))]).to_a.first
          SELECT * FROM crawl_host_gates
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid AND canonical_host_sha256 = $3
        SQL
      end

      # The gate row under a WRITE lock, with `clock_timestamp()` alongside it so the caller decides
      # against the same real instant the predicates used. Blocks rather than skipping: two workers
      # contending for one host must serialize, not both proceed.
      def lock_gate(organization_id, id)
        exec(<<~SQL, [organization_id, id]).to_a.first
          SELECT g.*, clock_timestamp() AS observed_at,
                 -- the rolling half-open window (:442): starts strictly after now-1s, through now
                 (SELECT COUNT(*) FROM unnest(g.recent_start_instants) AS s
                  WHERE s > clock_timestamp() - interval '1 second' AND s <= clock_timestamp()) AS window_starts,
                 (g.next_allowed_start_at IS NULL OR g.next_allowed_start_at <= clock_timestamp()) AS delay_elapsed
          FROM crawl_host_gates g
          WHERE g.organization_id = $1::uuid AND g.id = $2::uuid
          FOR UPDATE
        SQL
      end

      # Commit a claimed slot: append this start to the rolling window (trimming anything already
      # outside it), advance the crawl-delay floor, and increment the live connection count. Guarded
      # on the expected version so a lost race can never double-claim.
      def claim_slot(id, expected_version, interval_ms)
        exec(<<~SQL, [id, expected_version, interval_ms.to_i]).to_a.first
          UPDATE crawl_host_gates
          SET recent_start_instants =
                (SELECT COALESCE(array_agg(s), ARRAY[]::timestamptz(6)[])
                 FROM unnest(recent_start_instants) AS s
                 WHERE s > clock_timestamp() - interval '1 second') || clock_timestamp(),
              next_allowed_start_at = clock_timestamp() + ($3 || ' milliseconds')::interval,
              active_connection_count = active_connection_count + 1,
              lease_version = lease_version + 1,
              state_version = state_version + 1,
              updated_at = clock_timestamp()
          WHERE id = $1::uuid AND state_version = $2
          RETURNING id, lease_version, active_connection_count, next_allowed_start_at
        SQL
      end

      # Release a slot when the attempt terminates. `GREATEST(...,0)` is deliberate: a double release
      # must not drive the count negative and silently widen the concurrency ceiling.
      def release_slot(id, now)
        exec(<<~SQL, [id, iso(now)]).to_a.first
          UPDATE crawl_host_gates
          SET active_connection_count = GREATEST(active_connection_count - 1, 0),
              state_version = state_version + 1, updated_at = $2::timestamptz
          WHERE id = $1::uuid
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
        exec(<<~SQL, params).cmd_tuples
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
        exec(<<~SQL, [id, expected_version, iso(now)]).cmd_tuples
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
        exec(<<~SQL, params).cmd_tuples
          UPDATE crawl_host_gates
          SET robots_state = $4, robots_terminal_reason = $5, robots_terminal_at = $3::timestamptz,
              robots_http_status = $6, robots_rules = $7::jsonb, robots_rules_schema = $8,
              robots_agent_group = $9, robots_crawl_delay_ms = $10,
              robots_sitemap_candidates = $11::jsonb, robots_source_sha256 = $12,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND robots_state = 'in_progress' AND state_version = $2
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
        exec(<<~SQL, [organization_id, project_id]).to_a
          SELECT id, policy_version, scope, normalized_bounds FROM crawl_policies
          WHERE organization_id = $1::uuid AND state = 'active'
            AND ((scope = 'project' AND project_id = $2::uuid) OR scope = 'organization')
          ORDER BY (scope = 'project') ASC
        SQL
      end

      def organization(organization_id)
        exec("SELECT id, status FROM organizations WHERE id = $1::uuid", [organization_id]).to_a.first
      end

      def crawl(organization_id, crawl_id)
        exec(<<~SQL, [organization_id, crawl_id]).to_a.first
          SELECT id, project_id, state, entitlement_reservation_id
          FROM crawls WHERE organization_id = $1::uuid AND id = $2::uuid
        SQL
      end

      def project(organization_id, project_id)
        exec("SELECT id, state FROM projects WHERE organization_id=$1::uuid AND id=$2::uuid",
             [organization_id, project_id]).to_a.first
      end

      # Keyed on (organization, PROJECT, source). The project predicate is what stops a Crawl in one
      # Project being authorized against another Project's Source of the same Organization —
      # POSTGRESQL_SCHEMA :128's rule expressed in the read path, where no FK can enforce it.
      def source(organization_id, project_id, source_id)
        exec(<<~SQL, [organization_id, project_id, source_id]).to_a.first
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
        exec(<<~SQL, params).to_a.first["n"].to_i.positive?
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
        exec(<<~SQL, [organization_id, project_id, source_id]).to_a.first
          SELECT p.id, p.policy_version, p.canonical_host, p.allowed_schemes, p.allowed_ports,
                 p.include_prefixes, p.exclude_prefixes, p.query_handling
          FROM sources s
          JOIN source_scope_policies p ON p.id = s.current_scope_policy_id
          WHERE s.organization_id = $1::uuid AND s.project_id = $2::uuid AND s.id = $3::uuid
        SQL
      end

      private

      def exec(sql, params = []) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      def iso(time) = time&.getutc&.iso8601(6)
    end
  end
end
