# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf006
    module Handlers
      # WF-006 SealEvaluationInputs — the Evaluation input gate
      # (WORKFLOW_SPECIFICATIONS.md § Readiness derivation is exact, :503-511;
      # BACKGROUND_PROCESSING.md :439 `seal_input_snapshot`).
      #
      # WHY THIS EXISTS AT ALL. A started Crawl opens a pending `initial` Evaluation, and
      # OD-018 refuses another root Crawl for the Project while one is pending or running.
      # Nothing resolved that Evaluation, so the first Crawl of a Project was permanently
      # its last: the guard latched and never released. This is the limb that resolves it.
      #
      # WHAT IT DECIDES, AND WHAT IT REFUSES TO DECIDE. It runs exactly the ratified
      # readiness derivation over persisted facts. Today that derivation returns `blocked`
      # — truthfully, on two of its four predicates: no parser policy version can be
      # resolved and no Parsed Artifact has succeeded, because the parsing pipeline is not
      # in this build (see `Wf006::ParserPolicy`). `blocked` has its own fully specified
      # terminal transaction, and that transaction is all this runs:
      #
      #     atomically Pending -> Running -> Failed, emitting one EvaluationStarted, one
      #     EvaluationInputsBlocked and one EvaluationFailed with
      #     `evaluation_inputs_unavailable`, and performing NO Check or provider side
      #     effect.
      #
      # So no check is executed, no Issue is derived, no score is computed and no
      # recommendation is generated — none of which has resolved semantics, and none of
      # which is invented here. The Evaluation reaches a terminal state on the strength of
      # a fact about its inputs, which is the one thing that can be said honestly today.
      #
      # WHEN THE PARSER LANDS. `ready_full`/`ready_partial` become reachable and this
      # handler must NOT be the thing that acts on them: sealing a real snapshot is S-08's
      # transaction and starting the Evaluation is WF-007's single start. Reaching a ready
      # status here therefore raises rather than guessing — see `unreachable_ready`.
      class SealEvaluationInputs
        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "crawl"
        AGGREGATE_TYPE = "evaluation"
        SNAPSHOT_AGGREGATE_TYPE = "evaluation_input_snapshot"
        ACTION = "evaluation.advance"
        POLICY_VERSION = "permission-baseline-v1"
        WORKFLOW_ID = "WF-006"
        STAGE = "seal_input_snapshot"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)
          return in_memory_failure(command, ctx, "scheduled_action_target_mismatch") unless command.target_type == TARGET_TYPE

          Platform::UnitOfWork.run { |conn| resolve(conn.raw_connection, command, ctx) }
        end

        private

        def resolve(pg, command, ctx)
          now = ctx.now_utc.floor(6)
          store = IdentityAccess::Infrastructure::EvaluationInputStore.new(pg)
          org = command.organization_id
          store.enter_org_context(org:, correlation_id: ctx.correlation_id)

          crawl = store.read_crawl(command.crawl_id)
          d = { store:, command:, ctx:, org:, now: }
          # Not visible under the action's Organization context: the action and its target
          # disagree, which a correctly created action cannot do.
          return deny(**d, reason: "scheduled_action_target_mismatch") if crawl.nil? || crawl["organization_id"] != org

          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org:, command_type: command.command_type, target_type: TARGET_TYPE,
                                            target_id: command.crawl_id, key_digest:)
          return rebuild(store, existing, command) if existing

          store.lock_evaluation("crawl:#{command.crawl_id}")
          evaluation = store.initial_evaluation_for_crawl(command.crawl_id)
          # A Crawl that failed before it was accepted never created an Evaluation, and a
          # Crawl whose Evaluation is already terminal has nothing left to resolve. Both
          # are ordinary outcomes of a correctly scheduled action, not errors: record the
          # checkpoint and write no transition. This is the harmless-terminal-execution
          # pattern the WF-003 slots already use.
          return settle_void(d, evaluation, key_digest) if evaluation.nil? || evaluation["state"] != "pending"

          readiness = derive(store, command, crawl)
          raise unreachable_ready(evaluation, readiness) unless readiness.blocked?

          fail_inputs(d, crawl, evaluation, readiness, key_digest)
        end

        # The ratified derivation over persisted facts. `manifest_valid` is true here
        # because the manifest is READ from the Crawl's own succeeded IngestionJobs rather
        # than supplied — there is no tuple to be missing, no duplicate to admit and no
        # cross-Organization member to smuggle in, so the five `input_manifest_invalid`
        # fixtures S-08 owns cannot arise from this query. S-08 supplies the sealed
        # manifest and its validation; this reads a count.
        def derive(store, command, crawl)
          roots = store.source_root_counts(command.crawl_id)
          EvaluationInputReadiness.derive(
            manifest_valid: true,
            parser_policy_available: ParserPolicy.available?(command.organization_id, crawl["project_id"]),
            # No parsing pipeline exists, so no Parsed Artifact can have succeeded. Read as
            # the literal zero it is rather than counted from a table that does not exist.
            parsed_artifacts_succeeded: 0,
            source_root_artifacts_succeeded: 0,
            manifest_entries: store.manifest_entry_count(command.crawl_id),
            jobs_succeeded: store.manifest_entry_count(command.crawl_id),
            crawl_coverage: crawl["coverage_status"]
          ).then { |result| Facts.new(result:, roots:) }
        end

        # The derivation plus the counts it was made from, so the audit record lets a
        # reader re-derive the decision rather than trust it.
        Facts = Data.define(:result, :roots) do
          def blocked? = result.blocked?
          def readiness_status = result.readiness_status
          def coverage_status = result.coverage_status
          def reason = result.reason
          def blocked_predicate = result.blocked_predicate
        end

        # ---- the blocked terminal transaction ---------------------------------------

        def fail_inputs(d, crawl, evaluation, readiness, key_digest)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]

          ids = %i[execution audit result idem started blocked failed].to_h { |k| [k, ctx.generate_id] }
          request_sha256 = request_hash(command, ctx)
          # The Evaluation passes through `running` inside this one statement, so the
          # aggregate advances by one version and the two transition events are ordered
          # against it: `started` names the version it entered running at, `failed` the
          # version it left at.
          running_version = evaluation["state_version"].to_i + 1

          raise LostRace if store.fail_on_blocked_inputs(
            evaluation["id"], evaluation["state_version"].to_i, now, readiness.reason
          ).to_i.zero?

          payload = {
            "evaluation_id" => evaluation["id"], "crawl_id" => command.crawl_id,
            "project_id" => evaluation["project_id"], "organization_id" => org,
            "stage" => STAGE, "readiness_status" => readiness.readiness_status,
            "coverage_status" => readiness.coverage_status,
            "blocked_predicate" => readiness.blocked_predicate,
            "reason_code" => readiness.reason,
            "evaluation_state" => "failed",
            "crawl_coverage_status" => crawl["coverage_status"],
            "crawl_completion_reason" => crawl["completion_reason"],
            "manifest_entries" => manifest_entries(store, command),
            "source_roots" => readiness.roots["total"].to_i,
            "source_roots_with_document" => readiness.roots["with_root_document"].to_i,
            "parsed_artifacts_succeeded" => 0
          }

          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          write_audit(store, ids[:audit], org, ctx, command, evaluation["id"], to_state: "failed",
                      outcome: "failure", reason_code: readiness.reason, payload:, now:)
          write_started(store, ids, org, ctx, command, now, evaluation, running_version)
          write_inputs_blocked(store, ids, org, ctx, command, now, evaluation, readiness, payload)
          write_failed(store, ids, org, ctx, command, now, evaluation, readiness, running_version + 1)
          write_result(store, ids, command, ctx, org, now, payload)
          write_idempotency(store, ids[:idem], org, command, key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        rescue LostRace
          raise Platform::InvariantViolation, "evaluation input gate resolved concurrently"
        end

        def manifest_entries(store, command) = store.manifest_entry_count(command.crawl_id)

        # A checkpoint that had nothing to resolve. It still records that it ran — a
        # silent no-op would leave a scheduled action with no trace of its execution —
        # and writes no transition and no domain event.
        def settle_void(d, evaluation, key_digest)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]

          ids = %i[execution audit result idem].to_h { |k| [k, ctx.generate_id] }
          request_sha256 = request_hash(command, ctx)
          payload = {
            "crawl_id" => command.crawl_id, "organization_id" => org, "stage" => STAGE,
            "outcome" => "void",
            "evaluation_id" => evaluation&.fetch("id"),
            "evaluation_state" => evaluation&.fetch("state")
          }
          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          write_audit(store, ids[:audit], org, ctx, command, evaluation&.fetch("id") || command.crawl_id,
                      to_state: nil, outcome: "success", reason_code: "evaluation_stage_void", payload:, now:)
          write_result(store, ids, command, ctx, org, now, payload)
          write_idempotency(store, ids[:idem], org, command, key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        # ---- events ------------------------------------------------------------------

        def write_started(store, ids, org, ctx, command, now, evaluation, version)
          emit(store, ids, org, ctx, command, now, id: ids[:started], event_type: "EvaluationStarted",
               profile: "state_transition", aggregate_type: AGGREGATE_TYPE, aggregate_id: evaluation["id"],
               aggregate_version: version,
               extra: { "from_state" => "pending", "to_state" => "running", "reason_code" => nil,
                        "evaluation_id" => evaluation["id"], "crawl_id" => command.crawl_id,
                        "project_id" => evaluation["project_id"], "stage" => STAGE, "outcome" => "success" })
        end

        # `EvaluationInputsBlocked` is created on the `evaluation_input_snapshot` aggregate
        # (API_CONTRACTS.md :826) and carries the literal reason
        # `evaluation_inputs_unavailable`. The snapshot ROW is S-08's — a blocked snapshot
        # still records parser and manifest members that do not exist yet — so the identity
        # is DERIVED from the canonical content of this blocked result, exactly as
        # `Platform::DerivedUuid` already does for the global Crawl Policy artifact that a
        # contract requires to be named by a uuid but that is not a row. It is stable and
        # reproducible: two references are equal precisely when the content is, and when the
        # snapshot becomes a real row it can adopt this identity with no event-stream break.
        def write_inputs_blocked(store, ids, org, ctx, command, now, evaluation, readiness, payload)
          snapshot_id = snapshot_identity(org, evaluation, command, readiness)
          emit(store, ids, org, ctx, command, now, id: ids[:blocked], event_type: "EvaluationInputsBlocked",
               profile: "created", aggregate_type: SNAPSHOT_AGGREGATE_TYPE, aggregate_id: snapshot_id,
               aggregate_version: 0,
               extra: { "to_state" => "blocked", "reason_code" => readiness.reason,
                        "readiness_status" => readiness.readiness_status,
                        "coverage_status" => readiness.coverage_status,
                        "successful_count" => 0, "failed_count" => payload["manifest_entries"],
                        "failed_entries" => [], "evaluation_id" => evaluation["id"],
                        "evaluation_input_snapshot_id" => snapshot_id,
                        "crawl_id" => command.crawl_id, "project_id" => evaluation["project_id"],
                        "blocked_predicate" => readiness.blocked_predicate, "outcome" => "success" })
        end

        def snapshot_identity(org, evaluation, command, readiness)
          Platform::DerivedUuid.v8(Platform::CanonicalJson.digest({
            "organization_id" => org, "evaluation_id" => evaluation["id"], "crawl_id" => command.crawl_id,
            "readiness_status" => readiness.readiness_status, "coverage_status" => readiness.coverage_status,
            "blocked_predicate" => readiness.blocked_predicate, "stage" => STAGE
          }))
        end

        def write_failed(store, ids, org, ctx, command, now, evaluation, readiness, version)
          emit(store, ids, org, ctx, command, now, id: ids[:failed], event_type: "EvaluationFailed",
               profile: "state_transition", aggregate_type: AGGREGATE_TYPE, aggregate_id: evaluation["id"],
               aggregate_version: version,
               extra: { "from_state" => "running", "to_state" => "failed", "reason_code" => readiness.reason,
                        "evaluation_id" => evaluation["id"], "crawl_id" => command.crawl_id,
                        "project_id" => evaluation["project_id"], "outcome" => "failure" })
        end

        def emit(store, ids, org, ctx, command, now, id:, event_type:, profile:, aggregate_type:,
                 aggregate_id:, aggregate_version:, extra:)
          envelope = {
            "account_id" => nil, "actor_id" => nil, "affected_entity_id" => aggregate_id,
            "affected_entity_type" => aggregate_type, "aggregate_version" => aggregate_version,
            "audit_record_id" => ids[:audit], "causation_id" => ctx.correlation_id,
            "command_id" => command.command_id, "correlation_id" => ctx.correlation_id,
            "event_id" => id, "event_profile" => profile, "event_type" => event_type,
            "occurred_at_utc" => now.iso8601(6), "organization_id" => org,
            "schema_version" => "1.0", "service_identity_id" => ctx.service_identity_id,
            "workflow_id" => WORKFLOW_ID
          }.merge(extra)
          bytes = Platform::CanonicalJson.encode(envelope)
          store.insert_event(
            id:, created_at: iso(now), event_type:, event_profile: profile, occurred_at: iso(now),
            organization_id: org, aggregate_type:, aggregate_id:, aggregate_version:,
            partition_month: month(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, audit_record_id: ids[:audit],
            event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
          )
        end

        # ---- outcomes ----------------------------------------------------------------

        def deny(store:, command:, ctx:, org:, now:, reason:)
          ids = %i[execution audit result].to_h { |k| [k, ctx.generate_id] }
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          request_sha256 = request_hash(command, ctx)
          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          write_audit(store, ids[:audit], org, ctx, command, command.crawl_id, to_state: nil,
                      outcome: "failure", reason_code: reason,
                      payload: { "outcome" => "failure", "internal_reason" => reason,
                                 "crawl_id" => command.crawl_id, "organization_id" => org }, now:)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          write_result(store, ids, command, ctx, org, now, {}, failure:)
          Platform::CommandResult.failure(result_id: ids[:result], command_type: command.command_type,
                                          failure:, audit_record_id: ids[:audit], correlation_id: ctx.correlation_id)
        end

        # A ready status means a Parsed Artifact succeeded, which means the parsing
        # pipeline exists — and then sealing the snapshot is S-08's transaction and
        # starting the Evaluation is WF-007's single start, neither of which lives here.
        # Failing loudly is the fail-closed answer: this handler must never be the thing
        # that decides what a ready Evaluation does.
        def unreachable_ready(evaluation, readiness)
          Platform::InvariantViolation.new(
            "evaluation #{evaluation["id"]} derived #{readiness.readiness_status}, which requires the " \
            "S-08 parsing pipeline; the input gate cannot seal a snapshot or start an Evaluation"
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
              retryable: stored["retryable"] == "t" || stored["retryable"] == true,
              recovery_action: stored["recovery_action"], support_reference: stored["support_reference"]
            )
            Platform::CommandResult.failure(result_id: stored["id"], command_type: command.command_type,
                                            failure:, audit_record_id: stored["audit_record_id"],
                                            correlation_id: stored["correlation_id"], replayed: true)
          end
        end

        # ---- writers -------------------------------------------------------------------

        def write_execution(store, command, ctx, org, id, request_sha256, key_digest, now)
          store.insert_command_execution(
            id:, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, idempotency_key_digest: key_digest,
            command_type: command.command_type, command_schema_version: command.schema_version,
            service_identity_id: ctx.service_identity_id, organization_id: org, target_type: TARGET_TYPE,
            target_id: command.crawl_id, action: ACTION,
            requested_at: iso(command.requested_at_utc), authorization_check_at: iso(now),
            policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            canonical_payload: JSON.generate({ "stage" => STAGE }), request_sha256:
          )
        end

        def write_audit(store, id, org, ctx, command, entity_id, to_state:, outcome:, reason_code:, payload:, now:)
          store.insert_audit(
            id:, occurred_at: iso(now), partition_month: month(now), organization_id: org,
            service_identity_id: ctx.service_identity_id, correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id, entity_type: AGGREGATE_TYPE,
            entity_id:, to_state:, outcome:, reason_code:, payload: JSON.generate(payload),
            content_sha256: Platform::CanonicalJson.digest(payload)
          )
        end

        def write_result(store, ids, command, ctx, org, now, payload, failure: nil)
          store.insert_command_result(
            id: ids[:result], created_at: iso(now), correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id,
            command_execution_id: ids[:execution], outcome: failure ? "failure" : "success",
            organization_id: org, service_identity_id: ctx.service_identity_id, completed_at: iso(now),
            authorization_check_at: iso(now),
            target_refs: JSON.generate(failure ? {} : { TARGET_TYPE => command.crawl_id }),
            governing_policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            failure:, authorized_payload: JSON.generate(payload), audit_record_id: ids[:audit]
          )
        end

        def write_idempotency(store, id, org, command, key_digest, request_sha256, execution_id, result_id, now)
          store.insert_idempotency(
            id:, created_at: iso(now), organization_id: org, command_type: command.command_type,
            target_type: TARGET_TYPE, target_id: command.crawl_id, key_digest:, request_sha256:,
            command_execution_id: execution_id, command_result_id: result_id,
            retain_until: iso(now + (30 * 24 * 3600))
          )
        end

        def request_hash(command, ctx)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "service_identity_id" => ctx.service_identity_id,
            "organization_id" => command.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => command.crawl_id, "policy_versions" => [POLICY_VERSION],
            "command_payload" => { "stage" => STAGE }
          })
        end

        def schema_failure(command, ctx) = in_memory_failure(command, ctx, "command_schema_unsupported")

        def in_memory_failure(command, ctx, reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                          failure:, audit_record_id: ctx.generate_id, correlation_id: ctx.correlation_id)
        end

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
        def iso(time) = time&.getutc&.iso8601(6)
        def month(time) = Date.new(time.year, time.month, 1).iso8601

        class LostRace < StandardError; end
      end
    end
  end
end
