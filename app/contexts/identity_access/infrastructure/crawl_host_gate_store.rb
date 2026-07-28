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

      # pending -> in_progress for one robots attempt, guarded on the version.
      def begin_robots(id, expected_version, now)
        exec(<<~SQL, [id, expected_version, iso(now)]).cmd_tuples
          UPDATE crawl_host_gates
          SET robots_state = 'in_progress', robots_attempt_count = robots_attempt_count + 1,
              robots_generation = robots_generation + 1,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND robots_state = 'pending' AND state_version = $2
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

      def source(organization_id, source_id)
        exec("SELECT id, state, canonical_host FROM sources WHERE organization_id=$1::uuid AND id=$2::uuid",
             [organization_id, source_id]).to_a.first
      end

      # The reservation admitting this run must still be EXECUTING. A committed, released or expired
      # reservation means the run is no longer metered.
      def reservation_executing?(organization_id, reservation_id)
        return false if reservation_id.nil?

        exec(<<~SQL, [organization_id, reservation_id]).to_a.first["n"].to_i.positive?
          SELECT COUNT(*) AS n FROM entitlement_reservations
          WHERE organization_id = $1::uuid AND id = $2::uuid AND state = 'executing'
        SQL
      end

      # The Source's CURRENT scope policy — whichever version `sources.current_scope_policy_id`
      # names right now, never the version pinned onto the Crawl at queue time.
      def current_scope_policy(organization_id, source_id)
        exec(<<~SQL, [organization_id, source_id]).to_a.first
          SELECT p.id, p.policy_version, p.canonical_host, p.allowed_schemes, p.allowed_ports,
                 p.include_prefixes, p.exclude_prefixes, p.query_handling
          FROM sources s
          JOIN source_scope_policies p ON p.id = s.current_scope_policy_id
          WHERE s.organization_id = $1::uuid AND s.id = $2::uuid
        SQL
      end

      private

      def exec(sql, params = []) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      def iso(time) = time&.getutc&.iso8601(6)
    end
  end
end
