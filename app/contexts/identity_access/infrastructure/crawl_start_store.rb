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
      #   `hard_limits`    :442 "at any other hard limit ... set `coverage_status=partial` and
      #                    `completion_reason=limit_reached`"
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
            (SELECT COUNT(*) FROM crawl_limit_decisions d
              WHERE d.organization_id = $1::uuid AND d.project_id = $3::uuid AND d.crawl_id = $2::uuid
                AND d.threshold_kind = 'hard') AS hard_limits
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
      def pending_sitemap_gates(organization_id, crawl_id)
        exec(<<~SQL, [organization_id, crawl_id]).to_a
          SELECT id, state_version, robots_state, sitemap_state,
                 sitemap_candidates::text AS sitemap_candidates
          FROM crawl_host_gates
          WHERE organization_id = $1::uuid AND crawl_id = $2::uuid AND sitemap_state = 'pending'
          ORDER BY id
        SQL
      end

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
