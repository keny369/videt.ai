# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf005
    module Handlers
      # WF-005 RunIngestionJob — the service execution behind the ratified `ingestion_attempt_due`
      # ScheduledAction, and :378's only permitted operation for the `ingest` work type
      # (BACKGROUND_PROCESSING.md :140/:200; WORKFLOW_SPECIFICATIONS.md :464, :466).
      #
      # THE HANDLER OWNS THE LEDGER AND THE EVENTS; `Wf005::IngestionExecution` decides and performs.
      # That is the same division `RecordFetchAttempt` keeps with `CrawlDriver`, for the same reason:
      # a handler that also decided would have two authorities in one object and no way to test either
      # without the other.
      #
      # THREE PHASES, and only the middle one is different from the fetch pass's:
      #
      #   1. PREPARE — prove the Organization and the job exist, replay an identical delivery from the
      #      idempotency record, refuse a differing one, and check the due-at gate. Nothing is claimed
      #      before this passes.
      #   2. CLAIM AND WORK — `queued -> running` with its attempt row (one transaction), then :464's
      #      eight checks over the decrypted staged bytes (NO transaction).
      #   3. THE TERMINAL TRANSACTION — the settle, the events, the ledger and, when :466 owes one,
      #      the retry action. All of it in ONE commit, because unlike the fetch pass this workflow
      #      makes no external call: MTX-008 requires the durable handoff to "commit with the
      #      IngestionJob success, so a parsing consumer can never observe a succeeded job without its
      #      Evidence", and a settle in a different transaction from the handoff's announcement is
      #      exactly the observation that requirement forbids.
      class RunIngestionJob
        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "ingestion_job"
        ACTION = "ingestion.run"
        POLICY_VERSION = "permission-baseline-v1"
        WORKFLOW_ID = "WF-005"
        DOCUMENT_TYPE = "document"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)
          return in_memory_failure(command, ctx, "scheduled_action_target_mismatch") unless command.target_type == TARGET_TYPE

          prepared = prepare(command, ctx)
          return prepared if prepared.is_a?(Platform::CommandResult)

          execution = Wf005::IngestionExecution.new(ids: ctx.ids, correlation_id: ctx.correlation_id,
                                                    command_id: command.command_id)
          claim = execution.claim(organization_id: prepared[:org], job_id: command.ingestion_job_id,
                                  now: prepared[:now])
          return unclaimed(command, ctx, prepared, claim) unless claim.settleable?

          work = claim.performable? ? execution.perform(claim:, now: prepared[:now]) : nil
          finalize(command, ctx, prepared, execution, claim, work)
        end

        private

        def prepare(command, ctx)
          Platform::UnitOfWork.run do |conn|
            raw = conn.raw_connection
            store = IdentityAccess::Infrastructure::CrawlStartStore.new(raw)
            org = command.organization_id
            now = ctx.now_utc.floor(6)
            store.enter_org_context(org:, correlation_id: ctx.correlation_id)
            return in_memory_failure(command, ctx, "scheduled_action_target_mismatch") if store.organization(org).nil?

            jobs = IdentityAccess::Infrastructure::IngestionJobStore.new(raw)
            jobs.enter_org_context(org:, correlation_id: ctx.correlation_id)
            job = jobs.get(org, command.ingestion_job_id)
            return deny(store, command, ctx, org, now, "scheduled_action_target_mismatch") if job.nil?

            key_digest = Digest::SHA256.digest(command.action_identity_sha256)
            request_sha256 = request_hash(command)
            existing = store.find_idempotency(org:, command_type: command.command_type,
                                              target_type: TARGET_TYPE, target_id: command.ingestion_job_id,
                                              key_digest:)
            if existing
              return rebuild(store, existing, command) if existing["request_hex"] == hex(request_sha256)

              return deny(store, command, ctx, org, now, "idempotency_conflict")
            end
            return deny(store, command, ctx, org, now, "scheduled_action_not_due") if now < command.due_at

            { org:, now:, job:, key_digest:, request_sha256: }
          end
        end

        # A DELIVERY THAT CLAIMED NOTHING WRITES NO PRODUCT STATE AND SAYS SO.
        #
        # Three shapes reach here and all three are ordinary: the job is gone, another worker holds a
        # LIVE lease on the current attempt, or the job is already settled. The ledger records the
        # refusal so the delivery is accounted for, and the idempotency record is written so a
        # redelivery replays this same answer rather than racing the winner a second time.
        #
        # THE CONTENDED SHAPE ALSO MINTS A SUCCESSOR, AND WITHOUT IT THE JOB COULD BE STRANDED FOR
        # EVER. `Worker#run_handler` SETTLES every result that is not a confirmed lease loss, so this
        # delivery ends its own action; if the incumbent then dies, the job is left `running` behind an
        # attempt lease that lapses with nothing pending to notice, and :466's retry is only ever minted
        # by a settle that never happens. The successor is due at the incumbent's own lease boundary —
        # read from the committed attempt row, so two contended deliveries compute one identity — and by
        # then the job is either settled (`ingestion_job_not_runnable`, which mints nothing) or
        # reclaimable. Found by this tranche's review, not in production.
        def unclaimed(command, ctx, prepared, claim)
          Platform::UnitOfWork.run do |conn|
            raw = conn.raw_connection
            store = IdentityAccess::Infrastructure::CrawlStartStore.new(raw)
            store.enter_org_context(org: prepared[:org], correlation_id: ctx.correlation_id)
            link = reenter(raw, command, ctx, prepared, claim)
            deny(store, command, ctx, prepared[:org], prepared[:now], claim.reason_code, link:)
          end
        end

        def reenter(pg, command, ctx, prepared, claim)
          return {} unless claim.reenters?

          Wf005::IngestionAttemptDueSchedule.schedule(
            pg:, organization_id: prepared[:org], project_id: prepared[:job]["project_id"],
            job_id: command.ingestion_job_id,
            replay_generation: prepared[:job]["replay_generation"].to_i,
            due_at: claim.reenter_at, now: prepared[:now], correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id
          )
        end

        def finalize(command, ctx, prepared, execution, claim, work)
          Platform::UnitOfWork.run do |conn|
            raw = conn.raw_connection
            store = IdentityAccess::Infrastructure::CrawlStartStore.new(raw)
            store.enter_org_context(org: prepared[:org], correlation_id: ctx.correlation_id)

            settlement = execution.settle(pg: raw, claim:, work:, now: prepared[:now])
            link = schedule_retry(raw, command, ctx, prepared, settlement)

            ids = %i[execution audit result idem].to_h { |k| [k, ctx.generate_id] }
            payload = payload_for(command, claim, settlement, link)
            write_execution(store, command, ctx, prepared[:org], ids[:execution],
                            prepared[:request_sha256], prepared[:key_digest], prepared[:now])
            write_audit(store, ids[:audit], prepared[:org], ctx, command, payload, prepared[:now],
                        to_state: settlement.discarded? ? nil : settlement.state,
                        outcome: settlement.succeeded? ? "success" : "failure",
                        reason_code: settlement.reason_code)
            emit_events(store, ids[:audit], prepared, ctx, command, claim, settlement)
            write_result(store, ids, command, ctx, prepared[:org], payload, prepared[:now])
            write_idempotency(store, ids[:idem], command, prepared[:org], prepared[:key_digest],
                              prepared[:request_sha256], ids[:execution], ids[:result], prepared[:now])

            Platform::CommandResult.success(
              result_id: ids[:result], command_type: command.command_type,
              audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
              payload: payload.transform_keys(&:to_sym)
            )
          end
        end

        # ":140 — `ingestion_attempt_due` | initial or DECLARED 30/120-SECOND RETRY", minted on the
        # settle's own transaction so a requeued job and its next dispatch cannot come apart. A job
        # that succeeded, dead-lettered or discarded a late completion owes no action at all.
        def schedule_retry(pg, command, ctx, prepared, settlement)
          return {} unless settlement.retried?

          Wf005::IngestionAttemptDueSchedule.schedule(
            pg:, organization_id: prepared[:org], project_id: prepared[:job]["project_id"],
            job_id: command.ingestion_job_id,
            replay_generation: settlement.job["replay_generation"].to_i,
            due_at: settlement.retry_at, now: prepared[:now], correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id
          )
        end

        def payload_for(command, claim, settlement, link)
          {
            "ingestion_job_id" => command.ingestion_job_id,
            "document_id" => settlement.document_id,
            "crawl_id" => claim.job["crawl_id"],
            "source_id" => claim.job["source_id"],
            "canonical_url" => claim.job["canonical_url"],
            "state" => settlement.discarded? ? "discarded" : settlement.state,
            "reason_code" => settlement.reason_code,
            "attempt_number" => settlement.attempt_number.to_i,
            "replay_generation" => claim.job["replay_generation"].to_i,
            # The durable handoff itself: :464's `source_document` Evidence. Null on every path but
            # success, which is the same fact `ingestion_jobs_succeeded_carries_evidence` enforces.
            "evidence_id" => settlement.evidence_id,
            "retry_due_at_utc" => settlement.retry_at&.getutc&.iso8601(6),
            "retry_action_id" => link[:action_id],
            # ":466 — Failure ... retains inaccessible staging bytes for at most 24 hours"; a success
            # destroys them in this same commit. Reported so a reader can see which happened.
            "staging_destroyed" => settlement.succeeded?
          }
        end

        # ---- the domain events -----------------------------------------------------

        # MTX-030's ingestion limb, emitted where the state change commits (API_CONTRACTS.md
        # :811-:814). `IngestionStarted` is emitted HERE rather than at the claim because the claim
        # transaction carries no audit record and `event_registry.audit_record_id` is the link a
        # reader follows; the started event therefore commits with the attempt's outcome, which is
        # honest — it says an attempt ran, and the attempt is in the same commit.
        #
        # A DISCARDED LATE COMPLETION EMITS NOTHING. It changed no state, so there is no transition to
        # announce; the audit record is the whole of its trace.
        def emit_events(store, audit_id, prepared, ctx, command, claim, settlement)
          return if settlement.discarded?

          org = prepared[:org]
          job = settlement.job || claim.job
          base = { store:, audit_id:, org:, ctx:, command:, now: prepared[:now],
                   project_id: job["project_id"] }
          entry = settlement.entry_version

          # EMITTED ONLY BY THE DELIVERY THAT TOOK THE EDGE. A `:reclaimed` delivery is settling an
          # attempt SOMEBODY ELSE started, and that delivery's own `queued -> running` commit is a
          # fact this one did not cause; announcing it here would attribute another delivery's
          # transition to this command and this scheduled action.
          if claim.performable?
            write_event(**base, type: IngestionContract::INGESTION_STARTED, profile: "state_transition",
                        aggregate_type: TARGET_TYPE, aggregate_id: job["id"], aggregate_version: entry,
                        extra: transition(job, from: "queued", to: "running", reason: nil,
                                          prior: entry - 1, committed: entry))
          end

          if settlement.succeeded?
            emit_success(base, job, settlement, entry)
          else
            emit_failure(base, job, settlement, entry)
          end
        end

        # ":464 — Success ... changes Document discovered to ingested, changes the job to succeeded",
        # and both events commit with those changes. The Document's committed version is 1 because
        # `discovered` is version 0 by construction: `documents` is created with `state_version = 0`
        # and `mark_ingested` is the FIRST edge it can ever take.
        def emit_success(base, job, settlement, entry)
          write_event(**base, type: IngestionContract::DOCUMENT_INGESTED, profile: "state_transition",
                      aggregate_type: DOCUMENT_TYPE, aggregate_id: settlement.document_id,
                      aggregate_version: 1,
                      extra: { "from_state" => "discovered", "to_state" => "ingested",
                               "prior_aggregate_version" => 0, "committed_aggregate_version" => 1,
                               "transition_reason_code" => nil,
                               "document_id" => settlement.document_id,
                               "input_content_sha256" => digest_hex(job["fetched_body_sha256"]),
                               "output_entity" => { "entity_type" => "evidence",
                                                    "entity_id" => settlement.evidence_id },
                               "output_content_sha256" => settlement.evidence_content_sha256 })
          write_event(**base, type: IngestionContract::INGESTION_SUCCEEDED, profile: "state_transition",
                      aggregate_type: TARGET_TYPE, aggregate_id: job["id"], aggregate_version: entry + 1,
                      extra: transition(job, from: "running", to: "succeeded", reason: nil,
                                        prior: entry, committed: entry + 1,
                                        evidence_id: settlement.evidence_id,
                                        evidence_sha256: settlement.evidence_content_sha256))
        end

        # ":466 — Other failures and exhausted retry move `running -> failed -> dead_letter` AT ONE
        # CHECKPOINT." Two edges, so two events: `IngestionFailed` for the first and
        # `IngestionDeadLettered` for the second, each carrying the machine reason the catalogue's
        # `transition` source requires at the root as well as in the envelope (:938). A RETRYABLE
        # failure emits only the first, because `failed -> queued` is not a catalogued event and the
        # retry is announced by the scheduled action rather than by a transition nobody named.
        def emit_failure(base, job, settlement, entry)
          write_event(**base, type: IngestionContract::INGESTION_FAILED, profile: "state_transition",
                      aggregate_type: TARGET_TYPE, aggregate_id: job["id"], aggregate_version: entry + 1,
                      reason_code: settlement.reason_code,
                      extra: transition(job, from: "running", to: "failed", reason: settlement.reason_code,
                                        prior: entry, committed: entry + 1))
          return unless settlement.dead_lettered?

          write_event(**base, type: IngestionContract::INGESTION_DEAD_LETTERED, profile: "state_transition",
                      aggregate_type: TARGET_TYPE, aggregate_id: job["id"], aggregate_version: entry + 2,
                      reason_code: settlement.reason_code,
                      extra: transition(job, from: "failed", to: "dead_letter",
                                        reason: settlement.reason_code, prior: entry + 1,
                                        committed: entry + 2))
        end

        # The `state_transition` base members (API_CONTRACTS.md :938) plus the `pipeline_job` extra
        # schema (:958): "`document_id`, `input_content_sha256`, `output_entity` and
        # `output_content_sha256`; OUTPUT FIELDS ARE BOTH NONNULL ONLY ON SUCCESS."
        def transition(job, from:, to:, reason:, prior:, committed:, evidence_id: nil, evidence_sha256: nil)
          {
            "from_state" => from, "to_state" => to,
            "prior_aggregate_version" => prior, "committed_aggregate_version" => committed,
            "transition_reason_code" => reason,
            "document_id" => job["document_id"],
            "input_content_sha256" => digest_hex(job["fetched_body_sha256"]),
            "output_entity" => evidence_id && { "entity_type" => "evidence", "entity_id" => evidence_id },
            "output_content_sha256" => evidence_sha256
          }
        end

        # ---- ledger writers --------------------------------------------------------

        def deny(store, command, ctx, org, now, reason, link: {})
          ids = %i[execution audit result idem].to_h { |k| [k, ctx.generate_id] }
          request_sha256 = request_hash(command)
          key_digest = Digest::SHA256.digest(command.action_identity_sha256)
          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          write_audit(store, ids[:audit], org, ctx, command,
                      { "ingestion_job_id" => command.ingestion_job_id, "reason_code" => reason,
                        "reentry_action_id" => link[:action_id],
                        "reentry_due_at_utc" => link[:due_at]&.getutc&.iso8601(6) }.compact, now,
                      to_state: nil, outcome: "failure", reason_code: reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          write_result(store, ids, command, ctx, org, {}, now, failure:)
          write_idempotency(store, ids[:idem], command, org, key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.failure(
            result_id: ids[:result], command_type: command.command_type, failure:,
            audit_record_id: ids[:audit], correlation_id: ctx.correlation_id
          )
        end

        def rebuild(store, existing, command)
          stored = store.load_command_result(existing["command_result_id"])
          if stored["outcome"] == "success"
            Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type,
                                            payload: JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym),
                                            audit_record_id: stored["audit_record_id"],
                                            correlation_id: stored["correlation_id"], replayed: true)
          else
            failure = Platform::Failure.new(
              error_class: stored["error_class"], error_code: stored["error_code"],
              reason_code: stored["reason_code"], severity: stored["severity"],
              retryable: stored["retryable"] == true || stored["retryable"] == "t",
              recovery_action: stored["recovery_action"], support_reference: stored["support_reference"]
            )
            Platform::CommandResult.failure(result_id: stored["id"], command_type: command.command_type,
                                            failure:, audit_record_id: stored["audit_record_id"],
                                            correlation_id: stored["correlation_id"], replayed: true)
          end
        end

        def write_execution(store, command, ctx, org, id, request_sha256, key_digest, now)
          store.insert_command_execution(
            id:, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, idempotency_key_digest: key_digest,
            command_type: command.command_type, command_schema_version: command.schema_version,
            service_identity_id: ctx.service_identity_id, organization_id: org, target_type: TARGET_TYPE,
            target_id: command.ingestion_job_id, action: ACTION,
            requested_at: iso(command.requested_at_utc), authorization_check_at: iso(now),
            policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            canonical_payload: JSON.generate({ "scheduled_action_id" => command.action_id }), request_sha256:
          )
        end

        def write_audit(store, id, org, ctx, command, payload, now, to_state:, outcome:, reason_code:)
          store.insert_audit(
            id:, occurred_at: iso(now), partition_month: month(now), organization_id: org,
            service_identity_id: ctx.service_identity_id, correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id, entity_type: TARGET_TYPE,
            entity_id: command.ingestion_job_id, to_state:, outcome:, reason_code:,
            payload: JSON.generate(payload), content_sha256: Platform::CanonicalJson.digest(payload)
          )
        end

        def write_event(store:, audit_id:, org:, ctx:, command:, now:, project_id:, type:, profile:,
                        aggregate_type:, aggregate_id:, aggregate_version:, extra:, reason_code: nil)
          event_id = ctx.generate_id
          envelope = {
            "account_id" => nil, "actor_id" => nil, "affected_entity_id" => aggregate_id,
            "affected_entity_type" => aggregate_type, "aggregate_version" => aggregate_version,
            "audit_record_id" => audit_id, "causation_id" => ctx.correlation_id,
            "command_id" => command.command_id, "correlation_id" => ctx.correlation_id,
            "event_id" => event_id, "event_profile" => profile, "event_type" => type,
            "occurred_at_utc" => now.iso8601(6), "organization_id" => org, "outcome" => "success",
            "project_id" => project_id, "reason_code" => reason_code, "schema_version" => "1.0",
            "scheduled_action_id" => command.action_id, "service_identity_id" => ctx.service_identity_id,
            "state_version" => aggregate_version, "workflow_id" => WORKFLOW_ID
          }.merge(extra)
          bytes = Platform::CanonicalJson.encode(envelope)
          store.insert_event(
            id: event_id, created_at: iso(now), event_type: type, event_profile: profile,
            occurred_at: iso(now), organization_id: org, aggregate_type:, aggregate_id:,
            aggregate_version:, partition_month: month(now), correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id, audit_record_id: audit_id,
            event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
          )
        end

        def write_result(store, ids, command, ctx, org, payload, now, failure: nil)
          store.insert_command_result(
            id: ids[:result], created_at: iso(now), correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id,
            command_execution_id: ids[:execution], outcome: failure ? "failure" : "success",
            organization_id: org, service_identity_id: ctx.service_identity_id,
            completed_at: iso(now), authorization_check_at: iso(now),
            target_refs: JSON.generate(failure ? {} : { "ingestion_job_id" => command.ingestion_job_id }),
            governing_policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            failure:, authorized_payload: JSON.generate(payload), audit_record_id: ids[:audit]
          )
        end

        def write_idempotency(store, id, command, org, key_digest, request_sha256, execution_id, result_id, now)
          store.insert_idempotency(
            id:, created_at: iso(now), organization_id: org, command_type: command.command_type,
            target_type: TARGET_TYPE, target_id: command.ingestion_job_id, key_digest:, request_sha256:,
            command_execution_id: execution_id, command_result_id: result_id,
            retain_until: iso(now + (30 * 24 * 3600))
          )
        end

        def request_hash(command)
          Platform::CanonicalJson.digest(
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "organization_id" => command.organization_id,
            "target_type" => TARGET_TYPE, "target_id" => command.ingestion_job_id,
            "command_payload" => { "scheduled_action_id" => command.action_id }
          )
        end

        def schema_failure(command, ctx) = in_memory_failure(command, ctx, "command_schema_unsupported")

        def in_memory_failure(command, ctx, reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                          failure:, audit_record_id: ctx.generate_id, correlation_id: ctx.correlation_id)
        end

        # A PostgreSQL `bytea` arrives as the `\x`-prefixed hex text form; the event contract asks for
        # a bare lowercase `sha256`.
        def digest_hex(value) = value.to_s.sub(/\A\\x/, "")
        def hex(bytes) = bytes.unpack1("H*")
        def iso(time) = time.getutc.floor(6).iso8601(6)
        def month(time) = Date.new(time.year, time.month, 1)
        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
      end
    end
  end
end
