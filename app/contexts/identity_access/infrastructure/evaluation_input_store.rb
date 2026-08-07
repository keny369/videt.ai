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
      def initialize(pg_connection)
        @pg = pg_connection
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
      def iso(time) = time&.getutc&.iso8601(6)
    end
  end
end
