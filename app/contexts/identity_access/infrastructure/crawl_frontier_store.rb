# frozen_string_literal: true

require "digest"

module IdentityAccess
  module Infrastructure
    # Persistence for the S-07-004 crawl frontier (schemas/POSTGRESQL_SCHEMA.md :293-294;
    # WORKFLOW_SPECIFICATIONS.md :454; SEARCH_CRAWL_RETRIEVAL.md § Frontier And Deterministic
    # Selection). Written inside the caller's proved-Organization transaction.
    #
    # PostgreSQL is the ordering authority. Every read that decides "which candidate is next" goes
    # through `claim_next`, which orders by the materialized `dequeue_key` — never by an application
    # sort, and never by `created_at`.
    class CrawlFrontierStore
      # WORKFLOW_SPECIFICATIONS.md :454 — "If more than 20,000 distinct candidates are discovered,
      # retain the lowest 20,000 by this order and record all later candidates as
      # `queue_limit_discarded`." The hard discovered-queue bound of `crawl-policy-v1`.
      QUEUE_LIMIT_DISCARDED = "queue_limit_discarded"
      DUPLICATE_DISCOVERY = "duplicate_discovery"

      def initialize(pg_connection)
        @pg = pg_connection
      end

      def enter_org_context(org:, correlation_id:)
        exec("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, correlation_id]).values.dig(0, 0)
      end

      # Serialize all frontier admission and dequeue for ONE Crawl. Admission has to be serialized
      # because both the deduplication decision and the 20,000-candidate retention bound are
      # order-dependent: two concurrent admissions that each read "19,999 admitted" would both
      # admit. The key is per-Crawl, so different Crawls never contend.
      def lock_frontier(crawl_id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["crawl-frontier:#{crawl_id}"])
      end

      # The pinned request-time Source set INTERSECTED with the Sources that are still `active`.
      #
      # This intersection is the point of the whole read (owner decision HD-S07-FU4-FU5, restating
      # the S-07-003 review's gate requirement): `crawl_sources` is T-IMM and records the Sources as
      # they were at QUEUE time, so seeding the frontier from it alone would crawl a Source the
      # customer has since disabled or removed, purely on queue-time authority. The join to
      # `sources.state = 'active'` is what makes that impossible. Ordered by the Volume I root order
      # — "Source roots are ordered by canonical root URL UTF-8 bytes and then Source ID" (:454).
      def active_pinned_sources(organization_id, crawl_id)
        exec(<<~SQL, [organization_id, crawl_id]).to_a
          SELECT cs.source_id, cs.canonical_root_uri, cs.scope_policy_id, cs.scope_policy_version,
                 s.state AS source_state
          FROM crawl_sources cs
          JOIN sources s
            ON s.organization_id = cs.organization_id AND s.project_id = cs.project_id AND s.id = cs.source_id
          WHERE cs.organization_id = $1::uuid AND cs.crawl_id = $2::uuid AND s.state = 'active'
          ORDER BY convert_to(cs.canonical_root_uri, 'UTF8'), cs.source_id
        SQL
      end

      # Every pinned Source, active or not — the denominator the caller reports the exclusion from.
      def pinned_source_count(organization_id, crawl_id)
        exec(<<~SQL, [organization_id, crawl_id]).to_a.first["n"].to_i
          SELECT COUNT(*) AS n FROM crawl_sources
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
        SQL
      end

      # The Source's CURRENT Source Scope Policy, as the S-06 predicate's Policy value object needs
      # it. `source_scope_policies` is a T-IMM version table with no lifecycle column — the current
      # version is whichever one `sources.current_scope_policy_id` points at (the same resolution
      # `CrawlStore#active_sources` uses). Read at EXECUTION time, so the CURRENT restrictive scope
      # governs (MTX-030: "every URL is validated against the pinned AND current restrictive scope").
      def current_scope_policy(organization_id, source_id)
        exec(<<~SQL, [organization_id, source_id]).to_a.first
          SELECT p.id, p.policy_version, p.canonical_host, p.allowed_schemes, p.allowed_ports,
                 p.include_prefixes, p.exclude_prefixes, p.query_handling
          FROM sources s
          JOIN source_scope_policies p ON p.id = s.current_scope_policy_id
          WHERE s.organization_id = $1::uuid AND s.id = $2::uuid
        SQL
      end

      # How many candidates this Crawl has already ADMITTED (`queued` or beyond). A discarded
      # candidate never consumed queue capacity, so it is excluded.
      def admitted_count(organization_id, crawl_id)
        exec(<<~SQL, [organization_id, crawl_id]).to_a.first["n"].to_i
          SELECT COUNT(*) AS n FROM crawl_frontier_entries
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid AND state <> 'discarded'
        SQL
      end

      def next_enqueue_order(organization_id, crawl_id)
        exec(<<~SQL, [organization_id, crawl_id]).to_a.first["n"].to_i
          SELECT COALESCE(MAX(enqueue_order), -1) + 1 AS n FROM crawl_frontier_entries
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
        SQL
      end

      def next_occurrence_order(organization_id, crawl_id)
        exec(<<~SQL, [organization_id, crawl_id]).to_a.first["n"].to_i
          SELECT COALESCE(MAX(occurrence_order), -1) + 1 AS n FROM crawl_frontier_occurrences
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
        SQL
      end

      # Rows already allocated for this digest within the Crawl, lowest ordinal first. A digest
      # match whose retained preimage is BYTE-EQUAL is the same candidate (a duplicate); a digest
      # match with a different preimage is a SHA-256 collision, which must never merge two
      # candidates and instead takes the next `collision_ordinal`.
      def entries_for_digest(organization_id, crawl_id, digest)
        exec(<<~SQL, [organization_id, crawl_id, bytea(digest)]).to_a
          SELECT id, collision_ordinal, canonical_url_preimage AS preimage, state
          FROM crawl_frontier_entries
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid AND canonical_url_sha256 = $3
          ORDER BY collision_ordinal
        SQL
      end

      def insert_entry(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:project_id],
          row[:crawl_id], row[:source_id], row[:canonical_url], bytea(row[:preimage]), bytea(row[:digest]),
          row[:collision_ordinal], row[:origin], row[:depth], row[:discovering_document_url],
          row[:link_position], bytea(row[:dequeue_key]), row[:parent_entry_id],
          row[:canonicalization_version], row[:scope_policy_id], row[:scope_policy_version],
          row[:enqueue_order], row[:state], row[:reason]
        ]
        exec(<<~SQL, params)
          INSERT INTO crawl_frontier_entries
            (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id,
             crawl_id, source_id, canonical_url, canonical_url_preimage, canonical_url_sha256,
             collision_ordinal, origin, depth, discovering_document_url, link_position, dequeue_key,
             parent_entry_id, canonicalization_version, scope_policy_id, scope_policy_version,
             robots_decision_id, robots_policy_version, enqueue_order, commit_order, state, reason)
          VALUES ($1::uuid,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,
                  $6::uuid,$7::uuid,$8,$9,$10,
                  $11,$12,$13,$14,$15,$16,
                  $17::uuid,$18,$19::uuid,$20,
                  NULL,NULL,$21,NULL,$22,$23)
        SQL
      end

      def insert_occurrence(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:project_id],
          row[:crawl_id], row[:frontier_entry_id], row[:source_id], row[:referrer_entry_id],
          row[:occurrence_url], bytea(row[:digest]), row[:discovering_document_url],
          row[:link_position], row[:occurrence_order], row[:duplicate_reason]
        ]
        exec(<<~SQL, params)
          INSERT INTO crawl_frontier_occurrences
            (id, created_at, correlation_id, organization_id, project_id, crawl_id, frontier_entry_id,
             source_id, referrer_entry_id, occurrence_url, occurrence_url_sha256,
             discovering_document_url, link_position, occurrence_order, discovered_at, duplicate_reason)
          VALUES ($1::uuid,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7::uuid,
                  $8::uuid,$9::uuid,$10,$11,
                  $12,$13,$14,$2::timestamptz,$15)
        SQL
      end

      # The DEQUEUE. The next candidate is the lowest `dequeue_key` among this Crawl's `queued`
      # entries — the materialized Volume I tuple, ordered by PostgreSQL bytewise, never by an
      # application sort. `FOR UPDATE SKIP LOCKED` lets concurrent workers take DISTINCT candidates
      # without either of them reordering the frontier or blocking. Returns the claimed row or nil.
      def claim_next(organization_id, crawl_id, now)
        exec(<<~SQL, [organization_id, crawl_id, iso(now)]).to_a.first
          WITH next_entry AS (
            SELECT id FROM crawl_frontier_entries
            WHERE organization_id = $1::uuid AND crawl_id = $2::uuid AND state = 'queued'
            ORDER BY dequeue_key
            FOR UPDATE SKIP LOCKED
            LIMIT 1
          )
          UPDATE crawl_frontier_entries e
          SET state = 'in_progress', state_version = e.state_version + 1, updated_at = $3::timestamptz
          FROM next_entry
          WHERE e.id = next_entry.id
          RETURNING e.id, e.canonical_url, e.source_id, e.depth, e.origin, e.link_position,
                    e.discovering_document_url, e.scope_policy_id, e.scope_policy_version,
                    e.enqueue_order, e.state
        SQL
      end

      # Admit a `discovered` candidate, or discard it at the queue bound. Guarded on the expected
      # state so a lost race can never double-admit. Returns the affected row count.
      def admit(id, expected_version, now)
        exec(<<~SQL, [id, expected_version, iso(now)]).cmd_tuples
          UPDATE crawl_frontier_entries
          SET state = 'queued', state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state = 'discovered' AND state_version = $2
        SQL
      end

      def discard(id, expected_version, now, reason)
        exec(<<~SQL, [id, expected_version, iso(now), reason]).cmd_tuples
          UPDATE crawl_frontier_entries
          SET state = 'discarded', reason = $4, state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state = 'discovered' AND state_version = $2
        SQL
      end

      def entries(organization_id, crawl_id)
        exec(<<~SQL, [organization_id, crawl_id]).to_a
          SELECT * FROM crawl_frontier_entries
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
          ORDER BY dequeue_key
        SQL
      end

      private

      def exec(sql, params = []) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      def iso(time) = time&.getutc&.iso8601(6)
    end
  end
end
