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
      def initialize(pg_connection)
        @pg = pg_connection
      end

      def enter_org_context(org:, correlation_id:)
        exec("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, correlation_id]).values.dig(0, 0)
      end

      # Serialize frontier ADMISSION for ONE Crawl (not the dequeue, which uses SKIP LOCKED and must
      # not block). Admission has to be serialized because both the deduplication decision and the
      # 20,000-candidate retention bound are order-dependent reads-then-writes: two concurrent
      # admissions that each read "19,999 admitted" would both admit. The key is per-Crawl, so
      # different Crawls never contend.
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

      # THE DISCOVERED QUEUE — the ONE population the :438 bound is measured over, and the same
      # population `Frontier#offer` enforces against and evicts from. Nothing may count toward the
      # ceiling while being exempt from enforcement or invisible to eviction.
      #
      # MEMBERSHIP: every candidate this run has discovered EXCEPT those the queue bound itself
      # refused. :440 — "the discovered queue counts distinct content-candidate URLs after Source
      # Scope canonicalization, INCLUDING AN IN-SCOPE URL EVEN WHEN IT IS LATER REJECTED FOR DEPTH".
      # So a depth-rejected candidate is a member; a `queue_limit_discarded` one never joined, and
      # counting it would make the bound self-defeating.
      #
      # The bound is checked BEFORE a candidate joins — in `Frontier#offer` AND in `seed_roots`,
      # which are the two entry points — so the population can never exceed it: a joiner at the
      # bound either displaces a member or is refused entry.
      #
      # TWO SETS, DELIBERATELY. This count is `:440`'s DISCOVERY metric — what the bound is measured
      # over — and it includes depth-rejected candidates because they were discovered. `:454`'s
      # "retain the lowest 20,000 by this order" is a RETENTION selection among candidates still
      # competing to be crawled, which is why `highest_unclaimed` sees only `('discovered','queued')`.
      # A depth-rejected member has already been resolved: it is not competing, its reason is frozen,
      # and it permanently occupies the discovery slot it genuinely used.
      #
      # The consequence is worth stating plainly rather than discovering later: a run that discovers
      # its whole bound in too-deep URLs admits nothing further, and that is correct — it discovered
      # 20,000 distinct in-scope candidates. What it must never do is exceed the bound, which is why
      # entry is the enforcement point.
      def admitted_count(organization_id, crawl_id)
        exec(<<~SQL, [organization_id, crawl_id]).to_a.first["n"].to_i
          SELECT COUNT(*) AS n FROM crawl_frontier_entries
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
            AND (state <> 'discarded' OR reason = 'depth_limit_discarded')
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
          -- A re-offer of the same (document, position) is the SAME observation, not a second one.
          -- S-07-007's fetch retries re-parse a document and re-offer its links, so this must be an
          -- idempotent no-op rather than a unique violation that aborts the caller's transaction.
          ON CONFLICT (crawl_id, frontier_entry_id, discovering_document_url, link_position) DO NOTHING
        SQL
      end

      # The DEQUEUE, with the breadth-first SEAL.
      #
      # The next candidate is the lowest `dequeue_key` among this Crawl's `queued` entries — the
      # materialized Volume I tuple, ordered by PostgreSQL bytewise, never by an application sort.
      #
      # Ordering alone does NOT deliver ":454 all depth `d` discoveries are sealed before any depth
      # `d+1` candidate is SELECTED". Sealing is the stronger property, and it binds to selection,
      # which is this statement. Without the barrier, once every remaining depth-`d` row is
      # `in_progress` (or row-locked) `SKIP LOCKED` would hand the next worker a depth-`d+1` row
      # while depth `d` is still in flight and its outgoing links are still undiscovered. The
      # `sealed_depth` CTE is the barrier: selection is confined to the LOWEST depth that still has
      # any non-terminal entry, so a deeper candidate becomes selectable only once every shallower
      # one has left the frontier.
      #
      # `FOR UPDATE SKIP LOCKED` then lets concurrent workers take DISTINCT candidates within that
      # depth without blocking. It is the CLAIM that may interleave; the ordered COMMIT of results
      # is a separate obligation belonging to S-07-007's coordinator. Returns the claimed row or nil.
      # The entry `claim_next` WOULD claim, without claiming it. Same selection, same sealing, no
      # state change and no row lock.
      #
      # It exists because `in_progress` has no way back: the guard admits only
      # `discovered -> queued|discarded` and `queued -> in_progress|discarded`, so an entry claimed
      # and then refused a byte reservation is stranded, and `sealed_depth`'s MIN over
      # `('queued','in_progress','fetched_pending_commit')` then pins the run's breadth-first
      # frontier at that depth for the rest of the run. Admission therefore decides whether it can
      # PAY for an entry before it takes it. Safe against a concurrent claimer only because the
      # caller holds the per-Crawl frontier advisory lock across both statements — which is the same
      # lock that makes the reservation happen in dequeue order.
      def peek_next(organization_id, crawl_id)
        exec(<<~SQL, [organization_id, crawl_id]).to_a.first
          WITH sealed_depth AS (
            SELECT MIN(depth) AS d FROM crawl_frontier_entries
            WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
              AND state IN ('queued','in_progress','fetched_pending_commit')
          )
          SELECT e.id, e.canonical_url, e.source_id, e.depth
          FROM crawl_frontier_entries e, sealed_depth
          WHERE e.organization_id = $1::uuid AND e.crawl_id = $2::uuid AND e.state = 'queued'
            AND e.depth = sealed_depth.d
            AND EXISTS (
              SELECT 1 FROM sources s
              WHERE s.organization_id = e.organization_id AND s.project_id = e.project_id
                AND s.id = e.source_id AND s.state = 'active')
          ORDER BY e.dequeue_key
          LIMIT 1
        SQL
      end

      def claim_next(organization_id, crawl_id, now)
        exec(<<~SQL, [organization_id, crawl_id, iso(now)]).to_a.first
          WITH sealed_depth AS (
            SELECT MIN(depth) AS d FROM crawl_frontier_entries
            WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
              AND state IN ('queued','in_progress','fetched_pending_commit')
          ), next_entry AS (
            SELECT e.id FROM crawl_frontier_entries e, sealed_depth
            WHERE e.organization_id = $1::uuid AND e.crawl_id = $2::uuid AND e.state = 'queued'
              AND e.depth = sealed_depth.d
              -- The owner's requirement is "no longer active AT EXECUTION TIME", and the dequeue IS
              -- execution time. Seeding excludes Sources inactive at the START commit; this excludes
              -- a Source deactivated at any point AFTER it, so a candidate whose Source the customer
              -- has since disabled or removed is never handed to a worker. Re-read every claim
              -- rather than cached, because the whole point is that the answer changes mid-run.
              AND EXISTS (
                SELECT 1 FROM sources s
                WHERE s.organization_id = e.organization_id AND s.project_id = e.project_id
                  AND s.id = e.source_id AND s.state = 'active')
            ORDER BY e.dequeue_key
            FOR UPDATE OF e SKIP LOCKED
            LIMIT 1
          )
          UPDATE crawl_frontier_entries e
          SET state = 'in_progress', state_version = e.state_version + 1, updated_at = $3::timestamptz
          FROM next_entry
          WHERE e.id = next_entry.id
          RETURNING e.id, e.canonical_url, e.source_id, e.depth, e.origin, e.link_position,
                    e.discovering_document_url, e.scope_policy_id, e.scope_policy_version,
                    e.enqueue_order, e.state,
                    -- The post-claim version, so the caller's later seal release is a compare-and-set
                    -- on THIS claim rather than on a value re-read after another writer moved it.
                    e.state_version,
                    -- :456's ordering tuple, carried to the attempt record so the run's accounting
                    -- can be replayed "in canonical dequeue/attempt order" without re-deriving it.
                    e.dequeue_key
        SQL
      end

      # THE SEAL RELEASE (S-07-012). Retire a claimed entry whose fetch has been decided, so
      # `sealed_depth` can advance and :454's "all depth d discoveries are SEALED before any depth d+1
      # candidate is SELECTED" stops holding a depth whose work is finished.
      #
      # Guarded on `state = 'in_progress'` AND the expected `state_version`, so it is a compare-and-set
      # on exactly the claim this caller took: a redelivered action whose entry has already been
      # retired matches zero rows and the caller learns that rather than rewriting a decision. Nothing
      # else about the row is touched — `reason` stays NULL, which
      # `crawl_frontier_entries_discard_reason` requires of every non-discarded state, and `terminal`
      # is deliberately distinct from `discarded`: the candidate WAS acted on, so :452 keeps it in the
      # coverage denominator, where a discard is not.
      #
      # `commit_order` is NOT assigned here. It is :456's coordinator sequence for committing
      # DISCOVERIES in increasing dequeue key, which arrives with concurrent fetching and link
      # extraction (S-07-010); this driver advances one entry per pass, so a sequence it wrote would
      # be a restatement of `enqueue_order` rather than the ordering the column exists to record.
      #
      # AND THIS IS NOT THE ENTRY'S TERMINAL RECORD. `crawl_terminal_outcomes` is — T-IMM, one row per
      # frontier entry, carrying the terminal commit order, the outcome, the Document ID and the
      # COVERAGE EFFECT (schemas/POSTGRESQL_SCHEMA.md :299). It is catalogued and unbuilt, and it
      # belongs to the tranches that own Documents and coverage (S-07-009/S-07-010). What this
      # statement does is release the SEAL, so the run can reach the next depth.
      #
      # AND IT IS NOT A COVERAGE FACT EITHER. `terminal` records only that the entry was acted on and
      # is no longer selectable. What happened to the URL lives elsewhere, and it is NOT always a
      # `fetch_attempts` row: the fetch path authorizes BEFORE it claims an attempt, so a URL refused
      # by robots or by current scope, or one whose host-gate claim was refused, retires with no attempt
      # row at all. For a robots fail-closed host the distinguishing fact is the gate's own
      # `robots_terminal_reason`, which :452 reads by name; for the others it is the WF-005 command
      # result and audit record the pass writes. FU-21 carries the reconciliation, and S-07-009's
      # `crawl_terminal_outcomes` is where the per-entry coverage effect belongs.
      #
      # ORGANIZATION-SCOPED, not merely RLS-scoped. Row level security is forced on this table and does
      # hold — proved behaviourally as `f1_web` — but it depends on every caller having entered the
      # tenant context. Naming the Organization makes the isolation LOCAL to the statement, so a future
      # caller that forgets cannot reach another tenant's row even for an instant.
      def terminalize(organization_id, id, expected_version, now)
        exec(<<~SQL, [id, expected_version, iso(now), organization_id]).cmd_tuples
          UPDATE crawl_frontier_entries
          SET state = 'terminal', state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND organization_id = $4::uuid
            AND state = 'in_progress' AND state_version = $2
        SQL
      end

      # Is any candidate still unfinished? The fact that distinguishes a DRAINED frontier from a PINNED
      # one, and without it the driver could not tell them apart: `peek_next` returns nil for BOTH, so a
      # run whose seal is held by a stranded `in_progress` claim reported itself drained while admitted
      # work sat in the queue. The state set is exactly `sealed_depth`'s, plus `discovered`, so a
      # candidate staged but not yet admitted also counts as unfinished.
      # The boolean is read through `Platform::PgBool` because this connection returns a real `true`
      # while a plain `PG.connect` returns `"t"`, and a `== "t"` test was silently ALWAYS FALSE — which is
      # exactly how a pinned frontier would have gone on reporting itself drained.
      def unfinished?(organization_id, crawl_id)
        Platform::PgBool.true?(exec(<<~SQL, [organization_id, crawl_id]).to_a.first["present"])
          SELECT EXISTS (
            SELECT 1 FROM crawl_frontier_entries
            WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
              AND state IN ('discovered','queued','in_progress','fetched_pending_commit')
          ) AS present
        SQL
      end

      # Admit a candidate that was staged as `discovered`. NOT reachable yet: `Frontier#offer`
      # inserts straight to `queued` or `discarded`, so the two-phase stage-then-admit path exists
      # for the discovery tranches (S-07-006/007) that need to hold a candidate before deciding.
      # Guarded on the expected state so a lost race can never double-admit. Returns the row count.
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
          WHERE id = $1::uuid AND state IN ('discovered','queued') AND state_version = $2
        SQL
      end

      # Move an UNCLAIMED entry to a lower frontier position. ":454 Deduplication retains the first
      # candidate in this order" — the retained candidate is the LOWEST-ordered discovery of that
      # canonical URL, so a later discovery that sorts lower promotes the entry rather than being
      # dropped. Guarded on the state and version, and the guard refuses this once claimed.
      def reposition(id, expected_version, now, row)
        params = [id, expected_version, iso(now), row[:origin], row[:depth],
                  row[:discovering_document_url], row[:link_position],
                  bytea(row[:dequeue_key]), row[:parent_entry_id]]
        exec(<<~SQL, params).cmd_tuples
          UPDATE crawl_frontier_entries
          SET origin = $4, depth = $5, discovering_document_url = $6, link_position = $7,
              dequeue_key = $8, parent_entry_id = $9::uuid,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state IN ('discovered','queued') AND state_version = $2
        SQL
      end

      # The HIGHEST-ordered admitted-but-unclaimed candidate — the eviction victim when a
      # lower-ordered candidate arrives at the discovered-queue bound (":454 retain the LOWEST
      # 20,000 by this order"). A claimed entry is never evicted: it has already been acted on.
      def highest_unclaimed(organization_id, crawl_id)
        exec(<<~SQL, [organization_id, crawl_id]).to_a.first
          SELECT id, state_version, dequeue_key FROM crawl_frontier_entries
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid AND state IN ('discovered','queued')
          ORDER BY dequeue_key DESC
          LIMIT 1
        SQL
      end

      # One entry by ID. `project_id`, `crawl_id`, `source_id`, `canonical_url` and the scope-policy pair are
      # here because a `crawl_fetch_due` action carries only the entry ID and the run driver resolves
      # everything else from the row — and because the guard freezes every one of them for the life of the
      # entry, so a caller may carry them across a transaction boundary without their going stale.
      #
      # THE SCOPE-POLICY PAIR IS NOT OPTIONAL. `FetchContent#claim_attempt` reads `scope_policy_id` and
      # `scope_policy_version` off whatever entry it is handed and writes them into the T-IMM attempt row.
      # `claim_next` returns them; this reader did not, so every RESUMED retry persisted NULL/NULL — and for
      # exactly the URLs that needed retries, the immutable record of a request that left the platform could
      # no longer be reconciled against the policy version that permitted it. Both columns are nullable, so
      # nothing failed and nothing complained. Found by the security lens, proven on two consecutive passes.
      def entry(organization_id, id)
        exec(<<~SQL, [organization_id, id]).to_a.first
          SELECT id, state, state_version, dequeue_key, depth, origin,
                 discovering_document_url, link_position, parent_entry_id,
                 project_id, crawl_id, source_id, canonical_url,
                 scope_policy_id, scope_policy_version
          FROM crawl_frontier_entries WHERE organization_id = $1::uuid AND id = $2::uuid
        SQL
      end

      private

      def exec(sql, params = []) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      def iso(time) = time&.getutc&.iso8601(6)
    end
  end
end
