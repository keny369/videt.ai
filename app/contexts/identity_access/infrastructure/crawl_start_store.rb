# frozen_string_literal: true

require "json"

module IdentityAccess
  module Infrastructure
    # Persistence for the WF-005 service-only `Queued -> Running` start commit (S-07-003),
    # written in the worker's unit of work under the action's Organization context.
    #
    # Service-attributed throughout: `service_identity_id` is set and `actor_id` stays null. The
    # start is the crawl orchestration service's act at the `crawl_dispatch` ScheduledAction, not
    # a human's — the human authority was established and recorded at queue time
    # (contracts/S-07.json MTX-030: `StartCrawl` is a "service, at the Queued -> Running commit").
    #
    # It takes the SAME per-Project advisory lock QueueCrawl uses, so the OD-018
    # single-initial-orchestration guard is re-checked at the start commit against a consistent
    # view and two concurrent starts for one Project serialize (WORKFLOW_SPECIFICATIONS.md :725).
    class CrawlStartStore
      include ActiveCrawlPolicies

      def initialize(pg_connection)
        @pg = pg_connection
      end

      def enter_org_context(org:, correlation_id:)
        exec("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, correlation_id]).values.dig(0, 0)
      end

      # The SAME key QueueCrawl locks on, so the OD-018 guard read and the start commit cannot
      # interleave with a queue-time guard read or with another Crawl's start for this Project.
      def lock_project(organization_id, project_id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["crawl-queue:#{organization_id}:#{project_id}"])
      end

      def crawl(organization_id, crawl_id)
        exec(<<~SQL, [organization_id, crawl_id]).to_a.first
          SELECT id, organization_id, project_id, kind, state, state_version, queued_at,
                 requested_crawl_policy_id, requested_crawl_policy_version,
                 requested_entitlement_policy_id, requested_entitlement_policy_version,
                 triggered_by_account_id, trigger_kind
          FROM crawls WHERE organization_id = $1::uuid AND id = $2::uuid
        SQL
      end

      # The Organization re-authorized at the start commit (SEARCH_CRAWL_RETRIEVAL.md § Crawl
      # Admission And Snapshot step 1; WORKFLOW_SPECIFICATIONS.md :541 puts `organization_inactive`
      # first in the entitlement precedence). Read under the entered context, so a nonexistent or
      # foreign Organization returns nothing.
      def organization(organization_id)
        exec("SELECT id, status, authorization_epoch FROM organizations WHERE id = $1::uuid", [organization_id]).to_a.first
      end

      def project(organization_id, project_id)
        exec("SELECT id, state, state_version, source_set_version FROM projects WHERE organization_id=$1::uuid AND id=$2::uuid",
             [organization_id, project_id]).to_a.first
      end

      def active_source_count(organization_id, project_id)
        exec(<<~SQL, [organization_id, project_id]).to_a.first["n"].to_i
          SELECT COUNT(*) AS n FROM sources
          WHERE organization_id = $1::uuid AND project_id = $2::uuid AND state = 'active'
        SQL
      end

      # Every active crawl-policy version applying to the Project (Organization scope and Project
      # scope), most specific last. The effective bounds are the most restrictive of these AND the
      # frozen global ceiling; a new restriction therefore "affects queued work immediately"
      # (WORKFLOW_SPECIFICATIONS.md :732) because this is re-resolved at start, not pinned.

      # The MTX-030 Evaluation key `(crawl_id, kind=initial)` already taken for THIS Crawl — the
      # `evaluation_creation_conflict` predicate. (The entitlement-policy version is NOT read here:
      # it is taken from the Decision that resolved it, so no second read can disagree with it.)
      def initial_evaluation_for_crawl?(organization_id, project_id, crawl_id)
        exec(<<~SQL, [organization_id, project_id, crawl_id]).to_a.first["n"].to_i.positive?
          SELECT COUNT(*) AS n FROM evaluations
          WHERE organization_id = $1::uuid AND project_id = $2::uuid AND kind = 'initial'
            AND crawl_id = $3::uuid
        SQL
      end

      # OD-018 at the start commit: a pending or running initial-assessment Evaluation for this
      # Project belonging to ANOTHER Crawl. Our own Crawl is excluded so a duplicate delivery is
      # resolved by the idempotency record rather than by this guard.
      def initial_evaluation_elsewhere?(organization_id, project_id, crawl_id)
        exec(<<~SQL, [organization_id, project_id, crawl_id]).to_a.first["n"].to_i.positive?
          SELECT COUNT(*) AS n FROM evaluations
          WHERE organization_id = $1::uuid AND project_id = $2::uuid AND kind = 'initial'
            AND state IN ('pending','running') AND crawl_id IS DISTINCT FROM $3::uuid
        SQL
      end

      # queued -> running, guarded on the expected state version, stamping the accepted start:
      # the entitlement Decision/reservation, `started_at` (the wall-clock origin) and the
      # resolved wall-clock `deadline_at`. Returns the affected row count.
      def start(id, expected_version, now, deadline_at, decision_id, reservation_id)
        params = [id, expected_version, iso(now), iso(deadline_at), decision_id, reservation_id]
        exec(<<~SQL, params).cmd_tuples
          UPDATE crawls
          SET state = 'running', started_at = $3::timestamptz, deadline_at = $4::timestamptz,
              entitlement_decision_id = $5::uuid, entitlement_reservation_id = $6::uuid,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state = 'queued' AND state_version = $2
        SQL
      end

      # queued -> failed before execution: no fetch, no provider side effect, no reservation and no
      # Evaluation. `coverage_status` stays NULL — nothing was covered.
      #
      # `completion_reason` is the CLOSED five-value CompletionReason enum
      # (WORKFLOW_SPECIFICATIONS.md :456; API_CONTRACTS.md :956/:1005), so a pre-execution failure
      # records exactly `failed`. The exact machine reason is retained where the contract puts it —
      # the restricted audit record's `reason_code` and the `CrawlFailed` envelope — never in this
      # column. `entitlement_decision_id` stays NULL: POSTGRESQL_SCHEMA.md :338 defines it as
      # "entitlement Decision/reservation NULL until start", and this Crawl never started; the
      # blocked Decision is carried in the audit record (MTX-030 audit_record "entitlement
      # outcome"). Returns the affected row count.
      COMPLETION_REASON_FAILED = "failed"

      def fail(id, expected_version, now)
        params = [id, expected_version, iso(now), COMPLETION_REASON_FAILED]
        exec(<<~SQL, params).cmd_tuples
          UPDATE crawls
          SET state = 'failed', terminal_at = $3::timestamptz, completion_reason = $4,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state = 'queued' AND state_version = $2
        SQL
      end

      # ---- the terminal checkpoint (S-07-009) ------------------------------------
      #
      # THE THREE `crawls` WRITERS LIVE TOGETHER, DELIBERATELY. `start`, `fail` and `terminalize` are
      # the whole of what production does to this row, and keeping them adjacent is the same reasoning
      # ADR-095 recorded after the lease rule was found stated three different ways in three places: a
      # rule split across writers drifts, and the drift is invisible until it matters.

      # :458 — "TERMINAL SELECTION OCCURS ONCE AT A SERIALIZED CHECKPOINT." This is the serialization,
      # and it is a ROW lock rather than an advisory one: the checkpoint decides about the Crawl row
      # itself, so locking that row is both the narrowest and the most direct expression of the rule.
      # `FOR UPDATE` blocks rather than skips, because a second checkpoint arriving concurrently must
      # SEE the first one's decision — and then find the Crawl terminal — rather than derive its own.
      def lock_crawl(organization_id, crawl_id)
        exec(<<~SQL, [organization_id, crawl_id]).to_a.first
          SELECT id, state, state_version, started_at, deadline_at, project_id,
                 entitlement_reservation_id, entitlement_decision_id
          FROM crawls WHERE organization_id = $1::uuid AND id = $2::uuid
          FOR UPDATE
        SQL
      end

      # `running -> completed | failed`, guarded on both the state and the expected version, so a
      # checkpoint that lost its race writes nothing and LEARNS that it did. `coverage_status` is NULL
      # for `failed`, which is exactly the shape `crawls_terminal_shape` scopes by state (ADR-097).
      def terminalize(id, expected_version, now, state:, completion_reason:, coverage_status:)
        params = [id, expected_version, iso(now), state, completion_reason, coverage_status]
        exec(<<~SQL, params).cmd_tuples
          UPDATE crawls
          SET state = $4, terminal_at = $3::timestamptz, completion_reason = $5, coverage_status = $6,
              state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND state = 'running' AND state_version = $2
        SQL
      end

      # EVERYTHING :458 COUNTS, IN ONE STATEMENT AND ONE SNAPSHOT. Eight separate reads would let the
      # run change between them — a pass committing an outcome between the document count and the
      # coverage count would produce a selection that no single state of the database ever justified.
      # One statement under the Crawl row lock cannot.
      #
      # Each subquery is one ratified sentence:
      #   `documents`      :453 "a run is failed when it yields zero valid Documents"
      #   `roots_*`        :452 "a Source root succeeds only when its DEPTH-ZERO URL ultimately creates
      #                    a valid Document"; the join to `sources.state = 'active'` is :453's "every
      #                    ACTIVE Source root", re-read now rather than taken from the pinned set
      #   `fetch_failures` :452 "`content_fetch_failed` ... remains in the denominator"
      #   `uncovered`      :458 "every in-scope candidate ... reached a terminal COVERED outcome".
      #                    `excluded` rows are OUTSIDE the denominator and are deliberately not counted
      #   `unevaluated`    :458 "any in-scope candidate NOT EVALUATED because of depth, sitemap, queue,
      #                    page, byte, response, request, or wall-clock bound" — both the candidates a
      #                    bound discarded and the ones the run simply never reached
      #   `unresolved`     :450 `sitemap_unavailable` ("coverage is partial") and :452
      #                    `robots_unavailable_fail_closed` ("makes that Source root failed")
      #   `unattempted`    :458 "any in-scope candidate NOT EVALUATED ... makes coverage partial", for a
      #                    host whose sitemap discovery never reached an outcome at all (owner ruling 3;
      #                    round-6 blocker R6-4). IT IS COUNTED SEPARATELY FROM `unresolved` ON PURPOSE.
      #                    :450's `sitemap_unavailable` requires an antecedent — a declared sitemap, or a
      #                    default answering non-404/410 — followed by failure after retries and
      #                    validation, and a gate the run never attempted has none of them. Folding it
      #                    into `unresolved` would make :452's completion reason say
      #                    `partial_source_failure`, which asserts a SOURCE FAILURE about a host nobody
      #                    contacted. So it lowers COVERAGE, which is what :458 says it does, and leaves
      #                    the completion reason to the three causes :452 actually lists.
      #                    A fail-closed robots host is excluded because `unresolved` already counts it
      #                    and :448 means discovery correctly never ran there.
      #   `hard_limit_dimensions` — every HARD decision dimension, retained for audit and then
      #                    classified by the canonical R5-1 table. A hard decision is not by itself
      #                    a run-terminal reason (ADR-117).
      #   `sitemap_limit_facts` — :450's persisted sitemap XML/body/time/context limit reasons. Those
      #                    are terminal facts even when no general crawl-limit decision represents
      #                    the contextual sitemap outcome.
      def terminal_facts(organization_id, crawl_id, project_id)
        exec(<<~SQL, [organization_id, crawl_id, project_id]).to_a.first
          WITH roots AS (
            SELECT e.id
            FROM crawl_frontier_entries e
            JOIN sources s ON s.organization_id = e.organization_id
                          AND s.project_id = e.project_id AND s.id = e.source_id
            WHERE e.organization_id = $1::uuid AND e.crawl_id = $2::uuid
              AND e.depth = 0 AND e.origin = 'root' AND s.state = 'active'
          )
          SELECT
            (SELECT COUNT(*) FROM crawl_terminal_outcomes o
              WHERE o.organization_id = $1::uuid AND o.crawl_id = $2::uuid
                AND o.outcome = 'document_created') AS documents,
            (SELECT COUNT(*) FROM roots) AS roots_total,
            (SELECT COUNT(*) FROM roots r
              JOIN crawl_terminal_outcomes o ON o.crawl_frontier_entry_id = r.id
             WHERE o.organization_id = $1::uuid AND o.outcome = 'document_created') AS roots_succeeded,
            (SELECT COUNT(*) FROM crawl_terminal_outcomes o
              WHERE o.organization_id = $1::uuid AND o.crawl_id = $2::uuid
                AND o.outcome = 'content_fetch_failed') AS fetch_failures,
            (SELECT COUNT(*) FROM crawl_terminal_outcomes o
              WHERE o.organization_id = $1::uuid AND o.crawl_id = $2::uuid
                AND o.coverage_effect = 'not_covered') AS uncovered,
            (SELECT COUNT(*) FROM crawl_frontier_entries e
              WHERE e.organization_id = $1::uuid AND e.crawl_id = $2::uuid
                AND (e.state IN ('discovered','queued','in_progress','fetched_pending_commit')
                     OR (e.state = 'discarded' AND e.reason IS NOT NULL))) AS unevaluated,
            (SELECT COUNT(*) FROM crawl_host_gates g
              WHERE g.organization_id = $1::uuid AND g.crawl_id = $2::uuid
                AND (g.sitemap_state = 'unavailable' OR g.robots_state = 'unavailable')) AS unresolved,
            (SELECT COUNT(*) FROM crawl_host_gates g
              WHERE g.organization_id = $1::uuid AND g.crawl_id = $2::uuid
                AND g.sitemap_state IN ('pending', 'in_progress')
                AND g.robots_state IS DISTINCT FROM 'unavailable') AS unattempted,
            COALESCE((SELECT jsonb_agg(d.limit_dimension ORDER BY d.limit_dimension)
              FROM crawl_limit_decisions d
              WHERE d.organization_id = $1::uuid AND d.project_id = $3::uuid AND d.crawl_id = $2::uuid
                AND d.threshold_kind = 'hard'), '[]'::jsonb)::text AS hard_limit_dimensions,
            (SELECT COALESCE(SUM(jsonb_array_length(g.sitemap_limit_reasons)), 0)
              FROM crawl_host_gates g
              WHERE g.organization_id = $1::uuid AND g.crawl_id = $2::uuid) AS sitemap_limit_facts
        SQL
      end

      # `queued | running -> canceled` (:736; :458). Guarded on both the state and the expected version,
      # so a cancellation that raced the terminal checkpoint matches zero rows and the caller learns it
      # rather than overwriting a decision. :458 settles the boundary BY COMMIT ORDER — "a cancellation
      # committed strictly before that checkpoint yields `Crawl.Canceled`" — and this statement, under
      # the Crawl row lock, is what makes "strictly before" a fact rather than an intention.
      #
      # `coverage_status` stays NULL: `crawls_terminal_shape` requires it only of `completed`, and a
      # cancelled run's coverage is not a number anyone should read — the run was stopped, not measured.
      CANCELED_STATES = %w[queued running].freeze

      # CANCELLATION CARRIES ITS OWN AUTHORITY CHECK, IN THE WRITE (D3 / R10-10).
      #
      # THE DEFECT THIS CLOSES. `:335`/SEC-REQ-004/005 require authority to be re-read AFTER the wait,
      # because the wait is exactly when it can be revoked. Round 9 expressed that as a Ruby recheck
      # that minted an attestation the commit demanded. The round-10 review then hoisted the mint
      # ABOVE `lock_frontier`/`lock_crawl` — an ordinary "compute it once, early" refactor — and the
      # cancellation COMMITTED ON REVOKED AUTHORITY, irreversibly, while passing every mechanism.
      # Round 11 added a floor requiring the transaction to hold an assigned xid before minting; the
      # exact same hoist SURVIVED it, because `authorize` assigns an xid before the locks are taken.
      #
      # WHY THIS SHAPE ENDS IT. `CommandAuthorizer.authority_current?` is, in full,
      # "`organizations.authorization_epoch` equals the epoch the actor was authenticated with". That
      # is ORDINARY ROW STATE, so it can be a CONJUNCT OF THE WRITE rather than a Ruby statement
      # standing next to it. There is then nothing to hoist, reorder, extract into a helper,
      # short-circuit or arrange a Boolean around: the authority test and the state transition are one
      # statement, and the authority read takes `FOR KEY SHARE` on the organization row.
      #
      # WHY THE LOCK CLAUSE IS THERE AND NOT JUST THE CONJUNCT. Without it the predicate is evaluated
      # from the snapshot the statement opened with, so a statement that BLOCKS INSIDE ITSELF would
      # not see a revocation committing during that block — and the safety of the whole mechanism
      # would rest on an unwritten enumeration of which other transactions might hold a conflicting
      # lock. That is the shape this tranche exists to remove.
      #
      # THE LOCK STRENGTH IS `FOR SHARE`, AND `FOR KEY SHARE` WAS THE WRONG ONE (D7). The round-two
      # repair wrote `FOR KEY SHARE` and claimed "an epoch advance must take a conflicting lock on
      # the same row". IT DOES NOT. `authorization_epoch` is in no key, so the advance is a NON-KEY
      # update and takes `FOR NO KEY UPDATE`, which DOES NOT CONFLICT with `FOR KEY SHARE`. Measured
      # on this branch: with a reader holding `FOR KEY SHARE`, a concurrent epoch advance committed
      # straight through; with `FOR SHARE`, it blocked. The repair had restated the very premise it
      # was written to remove. `FOR SHARE` conflicts with the advance and NOT with another `FOR
      # SHARE`, so concurrent authorized commands still run side by side while a revocation must
      # either land before this read (the predicate then fails on the updated row) or wait until
      # after this transaction ends (the transition was authorised when it happened).
      #
      # THE CAPABILITY AXIS IS A CONJUNCT TOO (FU-48). The epoch detects a CHANGE in authority; it
      # does not detect the ABSENCE of one, and until D7 nothing below the handler did. The write now
      # re-reads the granting Role Assignments the decision relied on — active, effective, unexpired,
      # at the version and scope it saw — under the same `FOR SHARE`. An actor who never held
      # `crawl.cancel` carries no grant, so the array is empty and the predicate is false.
      #
      # THE ZERO-ROW CASES ARE DISTINGUISHED, because they are different kinds of event. Authority
      # that moved and a capability that is gone are DOMAIN DENIALS the caller must report; a lost
      # serialized transition is CORRUPTION. All three are computed in the same statement so none can
      # be inferred from another.
      def cancel(id, expected_version, now, authority:)
        params = [id, expected_version, iso(now), authority.epoch, authority.organization_id,
                  authority.uuid_array, authority.bigint_array, authority.text_array,
                  authority.account_id, authority.required_role]
        row = exec(<<~SQL, params).first
          WITH epoch_authority AS (
            SELECT 1 FROM organizations
            WHERE id = $5::uuid AND authorization_epoch = $4::bigint
            FOR SHARE
          ), capability_authority AS (
            SELECT 1 FROM role_assignments ra
            JOIN unnest($6::uuid[], $7::bigint[], $8::text[]) AS g(id, state_version, scope_hex)
              ON g.id = ra.id AND g.state_version = ra.state_version
             AND g.scope_hex = coalesce(encode(ra.scope_sha256, 'hex'), '')
            WHERE ra.organization_id = $5::uuid AND ra.account_id = $9::uuid
              AND ra.status = 'active'
              AND ra.effective_at IS NOT NULL AND ra.effective_at <= $3::timestamptz
              AND (ra.expires_at IS NULL OR $3::timestamptz < ra.expires_at)
              -- THE SCOPE RULE, AS A PREDICATE RATHER THAN AS A RUBY OPERAND (FU-48).
              AND ($10::text IS NULL OR ra.canonical_role = $10::text)
            FOR SHARE OF ra
          ), moved AS (
            UPDATE crawls
            SET state = 'canceled', terminal_at = $3::timestamptz, completion_reason = 'canceled',
                state_version = state_version + 1, updated_at = $3::timestamptz
            WHERE id = $1::uuid AND state = ANY (ARRAY['queued','running']) AND state_version = $2
              AND EXISTS (SELECT 1 FROM epoch_authority)
              AND EXISTS (SELECT 1 FROM capability_authority)
            RETURNING 1
          )
          SELECT (SELECT count(*) FROM epoch_authority) AS epoch_authorized,
                 (SELECT count(*) FROM capability_authority) AS capability_authorized,
                 (SELECT count(*) FROM moved) AS moved
        SQL
        epoch = row["epoch_authorized"].to_i.positive?
        capability = row["capability_authorized"].to_i.positive?
        { authorized: epoch && capability, epoch_authorized: epoch, capability_authorized: capability,
          moved: row["moved"].to_i }
      end

      # ":442 — record … AFFECTED SOURCE AND URL COUNTS" for the wall-clock crossing, and — since
      # DECISIONS ADR-114 / FU-35 — THE PREDICATE THAT DECIDES WHETHER THERE IS A CROSSING TO RECORD
      # AT ALL. A count of zero means the deadline abandoned nothing, and :458 conditions the whole
      # rule on there being "any in-scope candidate NOT EVALUATED because of … wall-clock bound".
      #
      # TWO POPULATIONS, BECAUSE :442'S OWN CANCELLATION CREATES THE SECOND (ADR-113).
      #
      #   * candidates the run never reached — still `discovered`, `queued`, `in_progress` or
      #     `fetched_pending_commit`. `observe_wall_clock` runs only once `now >= deadline_at`, so
      #     these are exactly the candidates that will now never be evaluated because the run ended.
      #   * candidates whose REQUEST the wall clock cancelled. Those entries are `terminal` and carry
      #     a `crawl_terminal_outcomes` row, so they have left the first population entirely — and
      #     they are the clearest case of a candidate the deadline prevented from being evaluated.
      #     Omitting them would let the repair for FU-34 silently suppress the record FU-35 exists to
      #     make correct.
      #
      # A DISCARDED CANDIDATE IS NOT THIS DIMENSION'S (round 3, R3-1). This query used to admit
      # `state = 'discarded' AND reason IS NOT NULL`, on the stated ground that it must describe the
      # same set as `terminal_facts`'s `unevaluated`. THAT REASONING WAS THE DEFECT, because the two
      # answer different sentences. `terminal_facts` answers :458's coverage denominator — "NOT
      # EVALUATED because of DEPTH, SITEMAP, QUEUE, PAGE, BYTE, RESPONSE, REQUEST, OR WALL-CLOCK
      # bound", every bound at once — and counting discards there is right. This query answers :442's
      # "AFFECTED source and URL counts" FOR THE WALL-CLOCK DIMENSION ALONE, and a candidate another
      # bound affirmatively disposed of was not affected by the clock.
      #
      # The whole discarded population belongs to another dimension, verifiably and not by assumption:
      # `crawl_frontier_store#discard` has exactly ONE caller in the repository, `Frontier`'s :454
      # eviction, and it passes exactly one reason, `queue_limit_discarded`. Nothing discards an entry
      # for the wall clock, so no wall-clock-affected candidate is lost by excluding them.
      #
      # WHAT IT COST: a run whose only unfetched URL was evicted by the QUEUE limit at minute zero
      # recorded a HARD `wall_clock_run_duration` decision with `affected_urls = 1` and spent its
      # once-per-run `CrawlLimitReached` on a dimension that bounded nothing. Both records are
      # immutable and `f1_crawls_guard` refuses correction of the terminal row, so the customer is
      # permanently told their crawl ran out of time.
      #
      # `UNION` rather than `UNION ALL`: an entry cannot be in both populations, but a future one that
      # was would be one affected URL, not two.
      # Has a HARD decision whose canonical disposition abandons the UNSELECTED frontier already been
      # made? Only that causal population can make the queued rows cease to be the wall clock's. A local
      # per-URL decision, a depth refusal and a queue-admission refusal do not own unrelated queued rows;
      # treating every other hard decision as a run stop was the R5-1/R5-4 classifier defect.
      #
      # `dimensions` comes only from `LimitSemantics::UNSELECTED_FRONTIER_STOP_DIMENSIONS`, whose
      # classifier invariant fixes this causal population at exactly two dimensions. Keep even the
      # placeholder arity static: the store must reject classifier drift rather than turn it into SQL.
      def unselected_frontier_already_stopped?(organization_id, crawl_id, dimensions)
        dimensions = Array(dimensions)
        raise ArgumentError, "expected the two unselected-frontier stop dimensions" unless dimensions.length == 2

        params = [organization_id, crawl_id, *dimensions]
        exec(<<~SQL, params).to_a.first["n"].to_i.positive?
          SELECT COUNT(*) AS n FROM crawl_limit_decisions
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
            AND threshold_kind = 'hard' AND limit_dimension IN ($3, $4)
        SQL
      end

      def unevaluated_reach(organization_id, crawl_id, wall_clock_reason)
        exec(<<~SQL, [organization_id, crawl_id, wall_clock_reason]).to_a.first
          WITH prevented AS (
            SELECT id AS entry_id, source_id
            FROM crawl_frontier_entries
            WHERE organization_id = $1::uuid AND crawl_id = $2::uuid
              AND state IN ('discovered','queued','in_progress','fetched_pending_commit')
            UNION
            SELECT o.crawl_frontier_entry_id, o.source_id
            FROM crawl_terminal_outcomes o
            WHERE o.organization_id = $1::uuid AND o.crawl_id = $2::uuid AND o.reason = $3
          )
          SELECT COUNT(*) AS urls, COUNT(DISTINCT source_id) AS sources FROM prevented
        SQL
      end

      # FU-9's TRANSFERRED OBLIGATION (ADR-096). Every host gate this run left `sitemap_state='pending'`.
      #
      # `Workflows::Wf005::DiscoverSitemaps` writes :450's terminal sitemap outcome only once the run has
      # EXPIRED, and `CrawlDriver#advance` halts on the same wall clock BEFORE it calls discovery with the
      # same `now` — so a gate under sustained host contention stayed `pending` for ever and :450's
      # `sitemap_unavailable` was unreachable on any production path. The checkpoint is the only place
      # left that can decide it honestly: at this instant no candidate can ever be attempted, which is
      # exactly the "after retries/validation" premise :450 conditions the outcome on.
      #
      # THE CHECKPOINT DOES NOT WRITE THE OUTCOME ITSELF. `f1_crawl_host_gates_sitemap_guard` admits
      # `pending -> in_progress -> unavailable` and nothing wider, so the decision goes through the
      # ACCEPTED claim/terminalize surface (`CrawlHostGateStore#begin_sitemaps` then
      # `#terminalize_sitemaps`) exactly as a discovery pass does. That is not a workaround for the
      # guard, it is the reason the guard is right: a worker that still holds the claim BLOCKS the
      # checkpoint from writing over the decision it is in the middle of making.
      # The one pending initial Evaluation of an accepted root start, keyed by
      # `(crawl_id, kind='initial')`. `orchestration_slot_active` stays FALSE: the slot is the
      # WF-011 reassessment/retry single-flight (POSTGRESQL_SCHEMA.md :340), and OD-018's initial
      # single-flight is the dedicated `evaluations_initial_single_flight_unique` backstop.
      def insert_evaluation(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id],
                  row[:project_id], row[:crawl_id]]
        exec(<<~SQL, params)
          INSERT INTO evaluations
            (id, state_version, created_at, updated_at, correlation_id, organization_id, project_id,
             kind, crawl_id, prior_evaluation_id, retry_of_evaluation_id, input_snapshot_id,
             applicability_snapshot_id, policy_snapshot_id, state, started_at, completed_at,
             failed_at, superseded_at, deadline_at, reason, orchestration_slot_active)
          VALUES ($1::uuid,0,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,
                  'initial',$6::uuid,NULL,NULL,NULL,
                  NULL,NULL,'pending',NULL,NULL,
                  NULL,NULL,NULL,NULL,false)
        SQL
      end

      # The immutable orchestration context of the accepted start (T-IMM, one per Evaluation).
      def insert_orchestration_context(row)
        params = [
          row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:project_id],
          row[:evaluation_id], row[:crawl_id], row[:crawl_policy_version], row[:entitlement_policy_version],
          row[:root_entitlement_decision_id], row[:root_entitlement_reservation_id],
          JSON.generate(row[:publication_preconditions])
        ]
        exec(<<~SQL, params)
          INSERT INTO evaluation_orchestration_contexts
            (id, created_at, correlation_id, organization_id, project_id, evaluation_id, crawl_id,
             prior_evaluation_id, prior_issue_set_id, prior_score_snapshot_id,
             source_set_hash, normalized_scope_hash, crawl_policy_version, entitlement_policy_version,
             root_entitlement_decision_id, root_entitlement_reservation_id,
             stage_input_hashes, publication_preconditions)
          VALUES ($1::uuid,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7::uuid,
                  NULL,NULL,NULL,
                  NULL,NULL,$8,$9,
                  $10::uuid,$11::uuid,
                  '{}'::jsonb,$12::jsonb)
        SQL
      end

      def find_idempotency(org:, command_type:, target_type:, target_id:, key_digest:)
        exec(<<~SQL, [org, command_type, target_type, target_id, bytea(key_digest)]).to_a.first
          SELECT encode(request_sha256,'hex') AS request_hex, command_result_id
          FROM idempotency_records
          WHERE scope_kind = 'organization' AND organization_id = $1::uuid
            AND command_type = $2 AND target_type = $3 AND target_id = $4::uuid AND key_digest = $5
          LIMIT 1
        SQL
      end

      def load_command_result(id)
        exec(<<~SQL, [id]).to_a.first
          SELECT id, outcome, authorized_payload, audit_record_id, correlation_id,
                 error_class, error_code, reason_code, severity, retryable, recovery_action, support_reference
          FROM command_results WHERE id = $1::uuid
        SQL
      end

      # ---- service-attributed platform ledgers (WF-005) -------------------------

      def insert_command_execution(row)
        params = [
          row[:id], row[:created_at], row[:correlation_id], row[:causation_id], row[:command_id],
          bytea(row[:idempotency_key_digest]), row[:command_type], row[:command_schema_version],
          row[:service_identity_id], row[:organization_id], row[:target_type], row[:target_id],
          row[:action], row[:requested_at], row[:authorization_check_at], row[:policy_versions],
          row[:canonical_payload], bytea(row[:request_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO command_executions
            (id, schema_version, created_at, correlation_id, causation_id, command_id,
             idempotency_key_digest, content_sha256, command_type, command_schema_version,
             service_identity_id, organization_id, target_type, target_id, action,
             requested_at, authorization_check_at, policy_versions, canonical_payload, request_sha256)
          VALUES ($1,'1.0',$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6,NULL,$7,$8,$9::uuid,$10::uuid,$11,$12::uuid,$13,
                  $14::timestamptz,$15::timestamptz,$16::jsonb,$17::jsonb,$18)
        SQL
      end

      def insert_audit(row)
        params = [
          row[:id], row[:occurred_at], row[:partition_month], row[:organization_id], row[:service_identity_id],
          row[:correlation_id], row[:causation_id], row[:command_id], row[:entity_type], row[:entity_id],
          row[:to_state], row[:outcome], row[:reason_code], row[:payload], bytea(row[:content_sha256])
        ]
        exec(<<~SQL, params)
          INSERT INTO audit_record_registry
            (id, schema_version, created_at, occurred_at, partition_month, organization_id, workflow_id,
             service_identity_id, correlation_id, causation_id, command_id, entity_type, entity_id,
             to_state, outcome, reason_code, classification, payload, content_sha256, retention_class)
          VALUES ($1,'1.0',$2::timestamptz,$2::timestamptz,$3::date,$4::uuid,'WF-005',
                  $5::uuid,$6::uuid,$7::uuid,$8::uuid,$9,$10::uuid,$11,$12,$13,'restricted',$14::jsonb,$15,'security_audit')
        SQL
      end

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

      def insert_command_result(row)
        failure = row[:failure]
        params = [
          row[:id], row[:created_at], row[:correlation_id], row[:causation_id], row[:command_id],
          row[:command_execution_id], row[:outcome], row[:organization_id], row[:service_identity_id],
          row[:completed_at], row[:authorization_check_at], row[:target_refs], row[:governing_policy_versions],
          failure&.error_class, failure&.error_code, failure&.reason_code, failure&.severity,
          failure&.retryable, failure&.recovery_action, failure&.support_reference,
          row[:authorized_payload], row[:audit_record_id]
        ]
        exec(<<~SQL, params)
          INSERT INTO command_results
            (id, schema_version, created_at, correlation_id, causation_id, command_id, command_execution_id,
             result_schema_version, outcome, organization_id, service_identity_id, completed_at,
             authorization_check_at, target_refs, governing_policy_versions,
             error_class, error_code, reason_code, severity, retryable, recovery_action, support_reference,
             authorized_payload, audit_record_id)
          VALUES ($1,'1.0',$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,'1.0',$7,$8::uuid,$9::uuid,
                  $10::timestamptz,$11::timestamptz,$12::jsonb,$13::jsonb,
                  $14,$15,$16,$17,$18,$19,$20,$21::jsonb,$22::uuid)
        SQL
      end

      # RETURNS THE ROW COUNT, and tolerates a concurrent delivery that got there first.
      #
      # This was a bare INSERT against `idempotency_scope_key`, and the unique violation it raised did not
      # merely fail the duplicate — IT ROLLED BACK THE WINNING DELIVERY'S ENTIRE TERMINAL TRANSACTION. Two
      # independent reviewers demonstrated the consequence for `crawl_fetch_due`, where the terminal
      # transaction also carries the run's only forward link: a real request left the platform, its attempt
      # row committed, and then its ledger AND the link vanished — leaving the frontier entry claimed, the
      # whole per-URL byte reservation charged with nothing accounted, and NO scheduled action for the run.
      # The crawl was dead and the surviving ledger described the delivery that had done nothing.
      #
      # Concurrent duplicate deliveries are ORDINARY: the transport recovers an expired worker lease and
      # re-dispatches, and the idempotency record cannot prevent that because it is written at the END of the
      # work it protects. So the first committer owns the replayable outcome, the second learns it lost from
      # a zero row count, and neither destroys the other. Product-side duplication is prevented where it
      # actually can be — the frontier claim, the attempt identity's `ON CONFLICT`, and the byte reservation.
      def insert_idempotency(row)
        params = [
          row[:id], row[:created_at], row[:organization_id], row[:command_type], row[:target_type],
          row[:target_id], bytea(row[:key_digest]), bytea(row[:request_sha256]),
          row[:command_execution_id], row[:command_result_id], row[:retain_until]
        ]
        exec(<<~SQL, params).cmd_tuples
          INSERT INTO idempotency_records
            (id, state_version, lock_version, created_at, updated_at, scope_kind, organization_id,
             command_type, target_type, target_id, key_digest, request_sha256,
             command_execution_id, command_result_id, retain_until)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,'organization',$3::uuid,
                  $4,$5,$6::uuid,$7,$8,$9::uuid,$10::uuid,$11::timestamptz)
          ON CONFLICT DO NOTHING
        SQL
      end

      private

      def exec(sql, params = []) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      def iso(time) = time&.getutc&.iso8601(6)
    end
  end
end
