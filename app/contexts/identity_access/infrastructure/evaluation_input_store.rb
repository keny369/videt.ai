# frozen_string_literal: true

require "json"

module IdentityAccess
  module Infrastructure
    # Persistence for the WF-006 evaluation-input gate (`seal_input_snapshot`), written in
    # the worker's unit of work under the Evaluation's Organization context.
    #
    # Service-attributed throughout: `service_identity_id` is set and `actor_id` stays
    # null. Deriving input readiness and recording the terminal input-gate failure is the
    # evaluation-input service's act, not a human's — no actor triggers it and no
    # permission gates it (WORKFLOW_SPECIFICATIONS.md § WF-006 Authorization: "Tenant-scoped
    # parsing/evaluation/indexing service identities execute"). This is the same
    # service-attributed writer set as VerificationObservationStore, which is now its
    # FOURTH structural copy; the `ServiceLedgerWriters` extraction that store's comment
    # already calls for is the right fix and is still deferred, because doing it here
    # would edit three merged stores for no behaviour change.
    class EvaluationInputStore
      # The raw connection, exposed so a caller can schedule F-04 work on THIS transaction.
      # `Platform::ScheduledActions::Store` takes a connection, and a schedule that opened its
      # own would commit independently of the rows it describes.
      attr_reader :connection

      def initialize(pg_connection)
        @pg = pg_connection
        @connection = pg_connection
      end

      def enter_org_context(org:, correlation_id:)
        exec("SELECT f1_enter_org_context($1::uuid, $2::uuid)", [org, correlation_id]).values.dig(0, 0)
      end

      # Serialize on the Evaluation: the readiness derivation and the transition it
      # decides are one critical section, so two deliveries of the same action cannot
      # both read `pending`.
      def lock_evaluation(id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["evaluation:#{id}"])
      end

      def read_evaluation(id)
        exec(<<~SQL, [id]).to_a.first
          SELECT id, organization_id, project_id, crawl_id, kind, state, state_version, reason
          FROM evaluations WHERE id = $1::uuid
        SQL
      end

      # The one pending or running initial Evaluation of a Crawl. The action targets the
      # Crawl rather than the Evaluation, because the Crawl is what the terminalizing
      # transaction knows and the Evaluation identity is derivable from it.
      def initial_evaluation_for_crawl(crawl_id)
        exec(<<~SQL, [crawl_id]).to_a.first
          SELECT id, organization_id, project_id, crawl_id, kind, state, state_version, reason
          FROM evaluations
          WHERE crawl_id = $1::uuid AND kind = 'initial'
          ORDER BY created_at ASC, id ASC LIMIT 1
        SQL
      end

      def read_crawl(id)
        exec(<<~SQL, [id]).to_a.first
          SELECT id, organization_id, project_id, state, coverage_status, completion_reason
          FROM crawls WHERE id = $1::uuid
        SQL
      end

      # The parse manifest's cardinality: "the complete set of distinct Documents whose
      # IngestionJobs reached `succeeded` for the selected Crawl" (contracts/S-08.json
      # test_contracts). The ORDER the manifest requires is irrelevant here because the
      # blocked derivation reads counts only; sealing an ordered snapshot is S-08's job
      # and needs the Parsed Artifacts that do not exist.
      def manifest_entry_count(crawl_id)
        exec(<<~SQL, [crawl_id]).to_a.first["n"].to_i
          SELECT COUNT(DISTINCT j.document_id) AS n
          FROM ingestion_jobs j
          WHERE j.crawl_id = $1::uuid AND j.state = 'succeeded' AND j.document_id IS NOT NULL
        SQL
      end

      # Distinct Source roots the Crawl pinned, and how many of them produced a succeeded
      # ingestion. Counted for the audit record: the derivation is already blocked on the
      # parser, but a reader deserves to see what the run actually had.
      def source_root_counts(crawl_id)
        exec(<<~SQL, [crawl_id]).to_a.first
          SELECT COUNT(*) AS total,
                 COUNT(*) FILTER (
                   WHERE EXISTS (
                     SELECT 1 FROM documents d
                     WHERE d.crawl_id = cs.crawl_id AND d.source_id = cs.source_id
                       AND d.canonical_url = cs.canonical_root_uri
                   )
                 ) AS with_root_document
          FROM crawl_sources cs
          WHERE cs.crawl_id = $1::uuid
        SQL
      end

      # The atomic input-gate failure (WORKFLOW_SPECIFICATIONS.md :511, "atomically
      # transitions `Evaluation.Pending -> Evaluation.Running -> Evaluation.Failed` solely
      # to record the terminal input-gate failure").
      #
      # TWO STATEMENTS, ONE TRANSACTION. `f1_evaluations_guard` admits `pending -> running`
      # and `running -> failed` and refuses everything else, including the shortcut
      # `pending -> failed`. That is the database being right: `running` is a real waypoint
      # the contract names and `EvaluationStarted` reports, so it is written rather than
      # implied. Atomicity comes from the transaction, not from squeezing both edges into
      # one UPDATE — no other transaction can observe the intermediate `running`, because
      # this one holds the Evaluation's advisory lock and has not committed.
      #
      # Each step is guarded on the version it expects, so a concurrent delivery that won
      # the race leaves the loser with zero affected rows on the FIRST step.
      def fail_on_blocked_inputs(id, expected_version, now, reason)
        started = exec(<<~SQL, [id, expected_version, iso(now)]).cmd_tuples
          UPDATE evaluations
          SET state = 'running', state_version = state_version + 1, updated_at = $3::timestamptz,
              started_at = $3::timestamptz
          WHERE id = $1::uuid AND state = 'pending' AND state_version = $2
        SQL
        return 0 if started.to_i.zero?

        exec(<<~SQL, [id, expected_version.to_i + 1, iso(now), reason]).cmd_tuples
          UPDATE evaluations
          SET state = 'failed', state_version = state_version + 1, updated_at = $3::timestamptz,
              failed_at = $3::timestamptz, reason = $4
          WHERE id = $1::uuid AND state = 'running' AND state_version = $2
        SQL
      end

      # ---- S-08 parse manifest -----------------------------------------------------

      # The candidate manifest tuples: every distinct Document whose IngestionJob reached
      # `succeeded` for this Crawl, with the members :470 requires each tuple to contain.
      # `document_content_digest` is read ALONGSIDE the job's digest rather than instead of
      # it, because the manifest/content-digest mismatch predicate compares the two.
      def manifest_rows(crawl_id)
        exec(<<~SQL, [crawl_id]).to_a
          SELECT j.organization_id, j.project_id, j.source_id, j.crawl_id,
                 j.id AS ingestion_job_id, j.document_id, j.evidence_id AS input_evidence_id,
                 d.canonical_url, j.media_type, encode(j.fetched_body_sha256, 'hex') AS content_digest,
                 encode(d.content_sha256, 'hex') AS document_content_digest,
                 j.data_classification,
                 (d.canonical_url = cs.canonical_root_uri) AS source_root
          FROM ingestion_jobs j
          JOIN documents d ON d.id = j.document_id AND d.organization_id = j.organization_id
          JOIN crawl_sources cs ON cs.crawl_id = j.crawl_id AND cs.source_id = j.source_id
          WHERE j.crawl_id = $1::uuid AND j.state = 'succeeded' AND j.document_id IS NOT NULL
        SQL
      end

      # Read separately and compared against the manifest, so an omission is detectable.
      def succeeded_ingestion_job_ids(crawl_id)
        exec(<<~SQL, [crawl_id]).to_a.map { |r| r["id"] }
          SELECT id FROM ingestion_jobs
          WHERE crawl_id = $1::uuid AND state = 'succeeded' AND document_id IS NOT NULL
        SQL
      end

      # The sealed per-URL terminal outcomes a Source-root payload must agree with.
      #
      # THE TWO VOCABULARIES ARE NOT THE SAME AND MUST BE TRANSLATED. `crawl_terminal_outcomes`
      # records the run's own outcome — `document_created`, `content_absent`,
      # `content_fetch_failed`, `policy_excluded`, `limit_discarded`,
      # `robots_unavailable_fail_closed` — while :476 admits exactly four values in the
      # parsed-observation map: `document_valid`, `content_absent`, `content_fetch_failed`,
      # `policy_excluded`. A crawl outcome with no parsed-observation equivalent
      # (`limit_discarded`, `robots_unavailable_fail_closed`) names a URL the run never
      # covered, so it is ABSENT from the map rather than translated to a near-miss: the map
      # describes what was observed, and "we stopped before this one" is not an observation.
      CRAWL_TO_OBSERVED_OUTCOME = {
        "document_created" => "document_valid",
        "content_absent" => "content_absent",
        "content_fetch_failed" => "content_fetch_failed",
        "policy_excluded" => "policy_excluded"
      }.freeze

      def crawl_terminal_outcome_map(crawl_id)
        exec(<<~SQL, [crawl_id]).to_a.each_with_object({}) do |row, map|
          SELECT t.outcome, d.canonical_url
          FROM crawl_terminal_outcomes t
          LEFT JOIN documents d ON d.id = t.document_id
          WHERE t.crawl_id = $1::uuid AND d.canonical_url IS NOT NULL
        SQL
          observed = CRAWL_TO_OBSERVED_OUTCOME[row["outcome"]]
          map[row["canonical_url"]] = observed if observed
        end
      end

      # The active scope policy versions a Source's links are canonicalized against. These
      # are the FROZEN ones the Crawl pinned, read through `crawl_sources`, so the parser and
      # the frontier cannot disagree about what is in scope.
      def source_scope_policies(crawl_id, source_id)
        exec(<<~SQL, [crawl_id, source_id]).to_a
          SELECT p.canonical_host, p.allowed_schemes, p.allowed_ports,
                 p.include_prefixes, p.exclude_prefixes, p.query_handling
          FROM crawl_sources cs
          JOIN source_scope_policies p ON p.id = cs.scope_policy_id
          WHERE cs.crawl_id = $1::uuid AND cs.source_id = $2::uuid
        SQL
      end

      # ---- S-08 parsing jobs -------------------------------------------------------

      def insert_parsing_job(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:causation_id], row[:command_id],
                  row[:organization_id], row[:project_id], row[:source_id], row[:crawl_id],
                  row[:evaluation_id], row[:document_id], row[:ingestion_job_id], row[:input_evidence_id],
                  row[:canonical_url], row[:source_root], row[:media_type], hexbytea(row[:content_digest]),
                  row[:data_classification], row[:parser_definition_version],
                  row[:normalization_schema_version], row[:idempotency_key], row[:schema_version]]
        exec(<<~SQL, params)
          INSERT INTO parsing_jobs
            (id, schema_version, created_at, updated_at, correlation_id, causation_id, command_id,
             organization_id, project_id, source_id, crawl_id, evaluation_id, document_id,
             ingestion_job_id, input_evidence_id, canonical_url, source_root, media_type,
             content_digest, data_classification, parser_definition_version,
             normalization_schema_version, status, attempt_number, idempotency_key, queued_at)
          VALUES ($1::uuid,$22,$2::timestamptz,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,
                  $6::uuid,$7::uuid,$8::uuid,$9::uuid,$10::uuid,$11::uuid,
                  $12::uuid,$13::uuid,$14,$15,$16,
                  $17,$18,$19,
                  $20,'queued',1,$21,$2::timestamptz)
          ON CONFLICT (document_id, content_digest, parser_definition_version) DO NOTHING
        SQL
      end

      def parsing_jobs_for_evaluation(evaluation_id)
        exec(<<~SQL, [evaluation_id]).to_a
          SELECT id, document_id, source_id, status, attempt_number, last_reason_code,
                 parsed_artifact_id, source_root, canonical_url
          FROM parsing_jobs WHERE evaluation_id = $1::uuid
          ORDER BY source_id, canonical_url, document_id
        SQL
      end

      def read_parsing_job(id)
        exec(<<~SQL, [id]).to_a.first
          SELECT * FROM parsing_jobs WHERE id = $1::uuid
        SQL
      end

      def lock_parsing_job(id)
        exec("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["parsing-job:#{id}"])
      end

      def start_parsing_job(id, expected_version, now)
        exec(<<~SQL, [id, expected_version, iso(now)]).cmd_tuples
          UPDATE parsing_jobs
          SET status = 'running', state_version = state_version + 1, updated_at = $3::timestamptz,
              started_at = $3::timestamptz
          WHERE id = $1::uuid AND status = 'queued' AND state_version = $2
        SQL
      end

      def succeed_parsing_job(id, expected_version, now, artifact_id, artifact_digest)
        exec(<<~SQL, [id, expected_version, iso(now), artifact_id, bytea(artifact_digest)]).cmd_tuples
          UPDATE parsing_jobs
          SET status = 'succeeded', state_version = state_version + 1, updated_at = $3::timestamptz,
              completed_at = $3::timestamptz, parsed_artifact_id = $4::uuid, parsed_artifact_digest = $5
          WHERE id = $1::uuid AND status = 'running' AND state_version = $2
        SQL
      end

      # `running -> failed` then, for a nonretryable reason or an exhausted retry,
      # `failed -> dead_letter` at the SAME serialized checkpoint (:483). Two statements
      # because the guard admits the two edges and refuses the shortcut.
      def fail_parsing_job(id, expected_version, now, reason, dead_letter:)
        affected = exec(<<~SQL, [id, expected_version, iso(now), reason]).cmd_tuples
          UPDATE parsing_jobs
          SET status = 'failed', state_version = state_version + 1, updated_at = $3::timestamptz,
              completed_at = $3::timestamptz, last_reason_code = $4
          WHERE id = $1::uuid AND status = 'running' AND state_version = $2
        SQL
        return 0 if affected.to_i.zero? || !dead_letter

        exec(<<~SQL, [id, expected_version.to_i + 1, iso(now)]).cmd_tuples
          UPDATE parsing_jobs
          SET status = 'dead_letter', state_version = state_version + 1, updated_at = $3::timestamptz
          WHERE id = $1::uuid AND status = 'failed' AND state_version = $2
        SQL
      end

      # A retryable failure returns the SAME job to `queued` at the next attempt number.
      def requeue_parsing_job(id, expected_version, now)
        exec(<<~SQL, [id, expected_version, iso(now)]).cmd_tuples
          UPDATE parsing_jobs
          SET status = 'queued', state_version = state_version + 1, updated_at = $3::timestamptz,
              attempt_number = attempt_number + 1, started_at = NULL, completed_at = NULL
          WHERE id = $1::uuid AND status = 'failed' AND state_version = $2
        SQL
      end

      def insert_parsed_artifact(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:project_id],
                  row[:source_id], row[:document_id], row[:parsing_job_id], row[:canonical_url],
                  row[:source_root], row[:input_media_type], hexbytea(row[:input_content_digest]),
                  row[:parser_definition_version], row[:normalization_schema_version],
                  row[:normalized_payload_reference], bytea(row[:normalized_payload_sha256]),
                  row[:data_classification], row[:schema_version]]
        exec(<<~SQL, params)
          INSERT INTO parsed_artifacts
            (id, schema_version, created_at, correlation_id, organization_id, project_id, source_id,
             document_id, parsing_job_id, canonical_url, source_root, input_media_type,
             input_content_digest, parser_definition_version, normalization_schema_version,
             normalized_payload_reference, normalized_payload_sha256, data_classification)
          VALUES ($1::uuid,$18,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,
                  $7::uuid,$8::uuid,$9,$10,$11,
                  $12,$13,$14,
                  $15,$16,$17)
        SQL
      end

      # :475 "changes the same-version Document from ingested to parsed". Guarded on
      # `ingested`, so a Document already advanced is left alone and the caller replays.
      def mark_document_parsed(id, now)
        exec(<<~SQL, [id, iso(now)]).cmd_tuples
          UPDATE documents
          SET state = 'parsed', state_version = state_version + 1, updated_at = $2::timestamptz,
              parsed_at = $2::timestamptz
          WHERE id = $1::uuid AND state = 'ingested'
        SQL
      end

      def read_evidence(id)
        exec("SELECT id, payload_reference, validation_status FROM evidence WHERE id = $1::uuid", [id]).to_a.first
      end

      # ---- S-08 evaluation input snapshot ------------------------------------------

      def insert_evaluation_input_snapshot(row)
        params = [row[:id], iso(row[:now]), row[:correlation_id], row[:organization_id], row[:project_id],
                  row[:evaluation_id], row[:crawl_id], row[:crawl_coverage_status], row[:crawl_completion_reason],
                  row[:parser_policy_version], row[:parser_definition_version], row[:normalization_schema_version],
                  row[:manifest], row[:failed_entries], row[:readiness_status], row[:coverage_status],
                  row[:blocked_predicate], row[:successful_count], row[:failed_count],
                  row[:source_roots_total], row[:source_roots_succeeded], bytea(row[:content_sha256]),
                  row[:schema_version]]
        exec(<<~SQL, params)
          INSERT INTO evaluation_input_snapshots
            (id, schema_version, created_at, correlation_id, organization_id, project_id, evaluation_id,
             crawl_id, crawl_coverage_status, crawl_completion_reason, parser_policy_version,
             parser_definition_version, normalization_schema_version, manifest, failed_entries,
             readiness_status, coverage_status, blocked_predicate, successful_count, failed_count,
             source_roots_total, source_roots_succeeded, content_sha256)
          VALUES ($1::uuid,$23,$2::timestamptz,$3::uuid,$4::uuid,$5::uuid,$6::uuid,
                  $7::uuid,$8,$9,$10,
                  $11,$12,$13::jsonb,$14::jsonb,
                  $15,$16,$17,$18,$19,
                  $20,$21,$22)
          ON CONFLICT (evaluation_id) DO NOTHING
        SQL
      end

      def read_snapshot(evaluation_id)
        exec("SELECT * FROM evaluation_input_snapshots WHERE evaluation_id = $1::uuid", [evaluation_id]).to_a.first
      end

      # ---- ledger writers ---------------------------------------------------------

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
          VALUES ($1,'1.0',$2::timestamptz,$2::timestamptz,$3::date,$4::uuid,'WF-006',
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
          VALUES ($1,'1.0',$2::timestamptz,$3,'1.0','WF-006',$4,
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

      def insert_idempotency(row)
        params = [
          row[:id], row[:created_at], row[:organization_id], row[:command_type], row[:target_type],
          row[:target_id], bytea(row[:key_digest]), bytea(row[:request_sha256]),
          row[:command_execution_id], row[:command_result_id], row[:retain_until]
        ]
        exec(<<~SQL, params)
          INSERT INTO idempotency_records
            (id, state_version, lock_version, created_at, updated_at, scope_kind, organization_id,
             command_type, target_type, target_id, key_digest, request_sha256,
             command_execution_id, command_result_id, retain_until)
          VALUES ($1,0,0,$2::timestamptz,$2::timestamptz,'organization',$3::uuid,
                  $4,$5,$6::uuid,$7,$8,$9::uuid,$10::uuid,$11::timestamptz)
        SQL
      end

      private

      def exec(sql, params) = @pg.exec_params(sql, params)
      def bytea(bytes) = bytes && { value: bytes, format: 1 }
      # The manifest carries digests as hex (it is canonical JSON), the columns are `bytea`.
      def hexbytea(hex) = hex && bytea([hex].pack("H*"))
      def iso(time) = time&.getutc&.iso8601(6)
    end
  end
end
