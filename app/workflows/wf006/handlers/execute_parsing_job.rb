# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf006
    module Handlers
      # WF-006 ExecuteParsingJob — one ParsingJob attempt (WORKFLOW_SPECIFICATIONS.md
      # :474-484).
      #
      # THE SUCCESS IS ONE TRANSACTION AND IT IS INDIVISIBLE. :475 — "Every successful job
      # atomically creates one immutable Parsed Artifact and changes the same-version
      # Document from ingested to parsed ... `ParsingSucceeded` and `DocumentParsed` commit
      # together; NEITHER MAY EXIST WITHOUT the validated Artifact and successful job." So
      # the Artifact insert, the Document advance, the job completion and both events are in
      # the same unit of work, and a validation failure writes none of them.
      #
      # THE PARSE ITSELF HOLDS NO TRANSACTION-CRITICAL RESOURCE. It opens no socket: the
      # bytes come from a retained Evidence payload and JSON-LD contexts are never fetched.
      # There is therefore no provider call to move outside the transaction — the rule that
      # shapes the WF-003 and WF-005 handlers does not apply here, and saying so is clearer
      # than mimicking a phasing that guards nothing.
      #
      # A LATE ATTEMPT WRITES NOTHING. The job is re-read under its advisory lock and must
      # still be `queued` at the version the attempt claimed; anything else means another
      # delivery won, and :483's "a late completion after timeout or dead letter is
      # discarded and cannot create an Artifact" is enforced by that guard rather than by a
      # timer.
      class ExecuteParsingJob
        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "parsing_job"
        AGGREGATE_TYPE = "parsing_job"
        ACTION = "parsing.execute"
        POLICY_VERSION = "permission-baseline-v1"
        WORKFLOW_ID = "WF-006"

        # F-02 binding for the normalized payload. Distinct from the ingestion binding, so an
        # Artifact payload cannot be revealed with an Evidence AAD or the other way round.
        PAYLOAD_AAD = { application: "wf006", record_type: "parsed_artifact",
                        purpose: "normalized_payload" }.freeze

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)
          return in_memory_failure(command, ctx, "scheduled_action_target_mismatch") unless command.target_type == TARGET_TYPE

          Platform::UnitOfWork.run { |conn| run(conn.raw_connection, command, ctx) }
        end

        private

        def run(pg, command, ctx)
          now = ctx.now_utc.floor(6)
          store = IdentityAccess::Infrastructure::EvaluationInputStore.new(pg)
          org = command.organization_id
          store.enter_org_context(org:, correlation_id: ctx.correlation_id)
          store.lock_parsing_job(command.parsing_job_id)

          job = store.read_parsing_job(command.parsing_job_id)
          d = { store:, command:, ctx:, org:, now: }
          return deny(**d, reason: "scheduled_action_target_mismatch") if job.nil? || job["organization_id"] != org

          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org:, command_type: command.command_type, target_type: TARGET_TYPE,
                                            target_id: command.parsing_job_id, key_digest:)
          return rebuild(store, existing, command) if existing

          # A job another delivery already took, or already terminalized. Recording the
          # checkpoint and writing nothing is the correct outcome, not an error.
          return settle_void(d, job, key_digest) unless job["status"] == "queued"

          attempt(d, job, key_digest)
        end

        def attempt(d, job, key_digest)
          store = d[:store]
          version = job["state_version"].to_i
          raise LostRace if store.start_parsing_job(job["id"], version, d[:now]).to_i.zero?

          outcome = ParsingExecution.run(
            job:, evidence: store.read_evidence(job["input_evidence_id"]),
            scope_policies: store.source_scope_policies(job["crawl_id"], job["source_id"]),
            sealed_outcomes: store.crawl_terminal_outcome_map(job["crawl_id"]),
            clock: d[:ctx].clock
          )
          return succeed(d, job, outcome, version + 1, key_digest) if outcome.success?

          fail_attempt(d, job, outcome.reason_code, version + 1, key_digest)
        rescue LostRace
          raise Platform::InvariantViolation, "parsing job claimed concurrently"
        end

        # ---- success ------------------------------------------------------------------

        def succeed(d, job, outcome, version, key_digest)
          store = d[:store]
          ctx = d[:ctx]
          org = d[:org]
          now = d[:now]
          ids = %i[execution audit result idem artifact parsed transitioned].to_h { |k| [k, ctx.generate_id] }

          payload_bytes = Platform::CanonicalJson.encode(outcome.payload).b
          aad = Platform::Encryption::Aad.for(**PAYLOAD_AAD, record_id: ids[:artifact], tenant: org)
          protected_payload = Platform::Encryption.protect(plaintext: payload_bytes, aad:)

          store.insert_parsed_artifact(
            id: ids[:artifact], now:, correlation_id: ctx.correlation_id, organization_id: org,
            project_id: job["project_id"], source_id: job["source_id"], document_id: job["document_id"],
            parsing_job_id: job["id"], canonical_url: job["canonical_url"],
            source_root: job["source_root"], input_media_type: job["media_type"],
            input_content_digest: hex_of(job["content_digest"]),
            parser_definition_version: job["parser_definition_version"],
            normalization_schema_version: job["normalization_schema_version"],
            normalized_payload_reference: protected_payload.reference,
            normalized_payload_sha256: protected_payload.content_digest,
            data_classification: job["data_classification"],
            schema_version: ParsingContract::SCHEMA_VERSION
          )
          raise LostRace if store.succeed_parsing_job(job["id"], version, now, ids[:artifact],
                                                      protected_payload.content_digest).to_i.zero?
          # :475 "changes the SAME-VERSION Document from ingested to parsed". A Document
          # already advanced by an exact replay is left alone and this is still a success —
          # the Artifact is what the Evaluation consumes.
          advanced = store.mark_document_parsed(job["document_id"], now).to_i.positive?

          result_payload = {
            "parsing_job_id" => job["id"], "parsed_artifact_id" => ids[:artifact],
            "document_id" => job["document_id"], "organization_id" => org,
            "canonical_url" => job["canonical_url"], "status" => "succeeded",
            "document_transitioned" => advanced,
            "normalized_payload_sha256" => protected_payload.content_digest.unpack1("H*"),
            "title_nodes" => outcome.payload["title_nodes"].length,
            "link_edges" => outcome.payload["link_edges"].length,
            "organization_nodes" => outcome.payload["organization_nodes"].length
          }
          write_ledger(d, ids, key_digest, entity_id: job["id"], to_state: "succeeded",
                       outcome: "success", reason_code: nil, payload: result_payload)
          emit(store, ids, org, ctx, d[:command], now, id: ids[:parsed], event_type: "ParsingSucceeded",
               profile: "state_transition", aggregate_id: job["id"], aggregate_version: version + 1,
               extra: { "from_state" => "running", "to_state" => "succeeded",
                        "parsed_artifact_id" => ids[:artifact], "document_id" => job["document_id"],
                        "project_id" => job["project_id"], "outcome" => "success", "reason_code" => nil })
          if advanced
            emit(store, ids, org, ctx, d[:command], now, id: ids[:transitioned], event_type: "DocumentParsed",
                 profile: "state_transition", aggregate_id: job["document_id"], aggregate_version: 0,
                 aggregate_type: "document",
                 extra: { "from_state" => "ingested", "to_state" => "parsed",
                          "parsed_artifact_id" => ids[:artifact], "parsing_job_id" => job["id"],
                          "project_id" => job["project_id"], "outcome" => "success", "reason_code" => nil })
          end
          advance_evaluation_if_last(d, job)

          Platform::CommandResult.success(result_id: ids[:result], command_type: d[:command].command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: result_payload.transform_keys(&:to_sym))
        end

        # ---- failure ------------------------------------------------------------------

        # :483 a nonretryable reason (or an exhausted third attempt) moves `running -> failed
        # -> dead_letter` at the SAME serialized checkpoint, emitting one `ParsingFailed` and
        # one `ParsingDeadLettered`. A retryable one stops at `failed`, is requeued at the
        # next attempt number, and emits no second failure for the prior attempt.
        def fail_attempt(d, job, reason, version, key_digest)
          store = d[:store]
          ctx = d[:ctx]
          org = d[:org]
          now = d[:now]
          attempt_number = job["attempt_number"].to_i
          delay = ParsingContract.retry_delay(reason:, attempt_number:)
          dead = delay.nil?
          ids = %i[execution audit result idem failed dead].to_h { |k| [k, ctx.generate_id] }

          raise LostRace if store.fail_parsing_job(job["id"], version, now, reason, dead_letter: dead).to_i.zero? && dead
          if dead
            status = "dead_letter"
          else
            store.requeue_parsing_job(job["id"], version + 1, now)
            ParsingAttemptSchedule.schedule(
              pg: store.connection, organization_id: org, project_id: job["project_id"],
              parsing_job_id: job["id"], due_at: now + delay, now:, correlation_id: ctx.correlation_id,
              command_id: d[:command].command_id, state_version: attempt_number + 1
            )
            status = "queued"
          end

          payload = { "parsing_job_id" => job["id"], "document_id" => job["document_id"],
                      "organization_id" => org, "status" => status, "reason_code" => reason,
                      "attempt_number" => attempt_number, "retry_in_seconds" => delay }
          write_ledger(d, ids, key_digest, entity_id: job["id"], to_state: status,
                       outcome: "failure", reason_code: reason, payload:)
          emit(store, ids, org, ctx, d[:command], now, id: ids[:failed], event_type: "ParsingFailed",
               profile: "state_transition", aggregate_id: job["id"], aggregate_version: version + 1,
               extra: { "from_state" => "running", "to_state" => "failed", "reason_code" => reason,
                        "document_id" => job["document_id"], "project_id" => job["project_id"],
                        "outcome" => "failure", "attempt_number" => attempt_number })
          if dead
            emit(store, ids, org, ctx, d[:command], now, id: ids[:dead], event_type: "ParsingDeadLettered",
                 profile: "state_transition", aggregate_id: job["id"], aggregate_version: version + 2,
                 extra: { "from_state" => "failed", "to_state" => "dead_letter", "reason_code" => reason,
                          "document_id" => job["document_id"], "project_id" => job["project_id"],
                          "outcome" => "failure" })
            advance_evaluation_if_last(d, job)
          end

          Platform::CommandResult.success(result_id: ids[:result], command_type: d[:command].command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        # THE HANDOFF BACK TO THE INPUT GATE. When this attempt was the last outstanding one,
        # schedule the stage checkpoint that seals the snapshot. Scheduling it from the LAST
        # job rather than from every job means one checkpoint per completed manifest instead
        # of one per Document.
        #
        # "LAST" IS ONLY A FACT UNDER A LOCK ON THE EVALUATION. The parse queue runs five
        # workers, so several jobs of one manifest commit at once; without this lock each
        # transaction reads a snapshot in which the others are still uncommitted, every one
        # counts an outstanding sibling, and NOBODY schedules the seal — leaving a fully
        # parsed Evaluation pending for ever behind the OD-018 guard. This was found by
        # running the Check pipeline, where seven concurrent attempts made it reproducible;
        # the same shape is here and the same lock fixes it. It serializes only the decision,
        # never the parse.
        def advance_evaluation_if_last(d, job)
          d[:store].serialize_on("evaluation:#{job['evaluation_id']}")
          jobs = d[:store].parsing_jobs_for_evaluation(job["evaluation_id"])
          outstanding = jobs.reject { |row| row["id"] == job["id"] }
                            .count { |row| !%w[succeeded dead_letter].include?(row["status"]) }
          return unless outstanding.zero?

          EvaluationStageSchedule.schedule(
            pg: d[:store].connection, organization_id: d[:org], project_id: job["project_id"],
            crawl_id: job["crawl_id"], terminal_at: d[:now], now: d[:now],
            correlation_id: d[:ctx].correlation_id, command_id: d[:command].command_id,
            schedule_generation: EvaluationStageSchedule::VISIT_PARSING_COMPLETE
          )
        end

        # ---- outcomes and writers -------------------------------------------------------

        def settle_void(d, job, key_digest)
          ids = %i[execution audit result idem].to_h { |k| [k, d[:ctx].generate_id] }
          payload = { "parsing_job_id" => job["id"], "organization_id" => d[:org],
                      "outcome" => "void", "status" => job["status"] }
          write_ledger(d, ids, key_digest, entity_id: job["id"], to_state: nil, outcome: "success",
                       reason_code: "parsing_attempt_void", payload:)
          Platform::CommandResult.success(result_id: ids[:result], command_type: d[:command].command_type,
                                          audit_record_id: ids[:audit], correlation_id: d[:ctx].correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        def deny(store:, command:, ctx:, org:, now:, reason:)
          ids = %i[execution audit result].to_h { |k| [k, ctx.generate_id] }
          d = { store:, command:, ctx:, org:, now: }
          payload = { "outcome" => "failure", "internal_reason" => reason,
                      "parsing_job_id" => command.parsing_job_id, "organization_id" => org }
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          write_ledger(d, ids, Digest::SHA256.digest(command.idempotency_key), entity_id: command.parsing_job_id,
                       to_state: nil, outcome: "failure", reason_code: reason, payload:,
                       failure:, idempotent: false)
          Platform::CommandResult.failure(result_id: ids[:result], command_type: command.command_type,
                                          failure:, audit_record_id: ids[:audit], correlation_id: ctx.correlation_id)
        end

        def write_ledger(d, ids, key_digest, entity_id:, to_state:, outcome:, reason_code:, payload:,
                         failure: nil, idempotent: true)
          store = d[:store]
          command = d[:command]
          ctx = d[:ctx]
          org = d[:org]
          now = d[:now]
          request_sha256 = request_hash(command, ctx)

          store.insert_command_execution(
            id: ids[:execution], created_at: iso(now), correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id,
            idempotency_key_digest: key_digest, command_type: command.command_type,
            command_schema_version: command.schema_version, service_identity_id: ctx.service_identity_id,
            organization_id: org, target_type: TARGET_TYPE, target_id: command.parsing_job_id,
            action: ACTION, requested_at: iso(command.requested_at_utc), authorization_check_at: iso(now),
            policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            canonical_payload: JSON.generate({ "parsing_job_id" => command.parsing_job_id }),
            request_sha256:
          )
          store.insert_audit(
            id: ids[:audit], occurred_at: iso(now), partition_month: month(now), organization_id: org,
            service_identity_id: ctx.service_identity_id, correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id, entity_type: AGGREGATE_TYPE,
            entity_id:, to_state:, outcome:, reason_code:, payload: JSON.generate(payload),
            content_sha256: Platform::CanonicalJson.digest(payload)
          )
          store.insert_command_result(
            id: ids[:result], created_at: iso(now), correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id,
            command_execution_id: ids[:execution], outcome: failure ? "failure" : "success",
            organization_id: org, service_identity_id: ctx.service_identity_id, completed_at: iso(now),
            authorization_check_at: iso(now),
            target_refs: JSON.generate(failure ? {} : { TARGET_TYPE => command.parsing_job_id }),
            governing_policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            failure:, authorized_payload: JSON.generate(payload), audit_record_id: ids[:audit]
          )
          return unless idempotent

          store.insert_idempotency(
            id: ids[:idem], created_at: iso(now), organization_id: org, command_type: command.command_type,
            target_type: TARGET_TYPE, target_id: command.parsing_job_id, key_digest:,
            request_sha256:, command_execution_id: ids[:execution], command_result_id: ids[:result],
            retain_until: iso(now + (30 * 24 * 3600))
          )
        end

        def emit(store, ids, org, ctx, command, now, id:, event_type:, profile:, aggregate_id:,
                 aggregate_version:, extra:, aggregate_type: AGGREGATE_TYPE)
          envelope = {
            "account_id" => nil, "actor_id" => nil, "affected_entity_id" => aggregate_id,
            "affected_entity_type" => aggregate_type, "aggregate_version" => aggregate_version,
            "audit_record_id" => ids[:audit], "causation_id" => ctx.correlation_id,
            "command_id" => command.command_id, "correlation_id" => ctx.correlation_id,
            "event_id" => id, "event_profile" => profile, "event_type" => event_type,
            "occurred_at_utc" => now.iso8601(6), "organization_id" => org, "schema_version" => "1.0",
            "service_identity_id" => ctx.service_identity_id, "workflow_id" => WORKFLOW_ID
          }.merge(extra)
          bytes = Platform::CanonicalJson.encode(envelope)
          store.insert_event(
            id:, created_at: iso(now), event_type:, event_profile: profile, occurred_at: iso(now),
            organization_id: org, aggregate_type:, aggregate_id:, aggregate_version:,
            partition_month: month(now), correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id,
            audit_record_id: ids[:audit], event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
          )
        end

        def rebuild(store, existing, command)
          stored = store.load_command_result(existing["command_result_id"])
          return replay_failure(stored, command) unless stored["outcome"] == "success"

          Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type,
                                          payload: JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym),
                                          audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end

        def replay_failure(stored, command)
          failure = Platform::Failure.new(
            error_class: stored["error_class"], error_code: stored["error_code"],
            reason_code: stored["reason_code"], severity: stored["severity"],
            retryable: stored["retryable"] == "t" || stored["retryable"] == true,
            recovery_action: stored["recovery_action"], support_reference: stored["support_reference"]
          )
          Platform::CommandResult.failure(result_id: stored["id"], command_type: command.command_type,
                                          failure:, audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end

        def request_hash(command, ctx)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "service_identity_id" => ctx.service_identity_id,
            "organization_id" => command.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => command.parsing_job_id, "policy_versions" => [POLICY_VERSION],
            "command_payload" => { "parsing_job_id" => command.parsing_job_id }
          })
        end

        def schema_failure(command, ctx) = in_memory_failure(command, ctx, "command_schema_unsupported")

        def in_memory_failure(command, ctx, reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                          failure:, audit_record_id: ctx.generate_id, correlation_id: ctx.correlation_id)
        end

        # The stored digest arrives as PostgreSQL's `\x…` bytea text; the Artifact writer
        # wants the same hex the manifest carried.
        def hex_of(value) = value.to_s.sub(/\A\\x/, "")

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
        def iso(time) = time&.getutc&.iso8601(6)
        def month(time) = Date.new(time.year, time.month, 1).iso8601

        class LostRace < StandardError; end
      end
    end
  end
end
