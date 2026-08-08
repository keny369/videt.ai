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
      # readiness derivation over persisted facts, and every branch of that derivation is
      # now reachable:
      #
      #   * `blocked` runs its own fully specified terminal transaction — atomically
      #     Pending -> Running -> Failed, emitting one EvaluationStarted, one
      #     EvaluationInputsBlocked and one EvaluationFailed with
      #     `evaluation_inputs_unavailable`, and performing NO Check or provider side effect.
      #   * `ready_full`/`ready_partial` seal the immutable snapshot, freeze the three
      #     baseline platform-derived Evidence payloads S-09's Checks consume, schedule
      #     WF-007's first stage, and LEAVE THE EVALUATION PENDING (:510). Starting it here
      #     would take WF-007's single start transition away from it.
      #
      # It still decides nothing about a Check, an Issue or a score. Those are WF-007's, and
      # the boundary is what keeps this stage a statement about INPUTS.
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

          manifest = seal_manifest(store, command, org)
          # An invalid manifest blocks readiness without any parse being attempted: :470's
          # "an implementation cannot silently drop it" means the run stops, not that the
          # good members proceed. The offending member might have been the Source root.
          unless manifest.valid?
            return fail_inputs(d, crawl, evaluation, blocked_by(ParseManifest::INVALID_REASON, manifest),
                               key_digest, manifest:)
          end

          jobs = store.parsing_jobs_for_evaluation(evaluation["id"])
          # AN EMPTY MANIFEST DERIVES NOW. A Crawl that ingested nothing has nothing to
          # parse, so `no_parsed_artifact_succeeded` already holds and waiting would leave
          # the Evaluation pending for ever — which is the latch this whole gate exists to
          # prevent. This is checked BEFORE `open_parsing` because opening zero jobs would
          # schedule nothing, and nothing would ever come back to seal the snapshot.
          if manifest.size.zero?
            return fail_inputs(d, crawl, evaluation, derive(store, command, crawl, manifest, []),
                               key_digest, manifest:)
          end
          # FIRST VISIT: create one ParsingJob per manifest tuple and schedule each. The
          # Evaluation stays pending, because it is now genuinely waiting for work rather
          # than blocked on the absence of any.
          return open_parsing(d, crawl, evaluation, manifest, key_digest) if jobs.empty?
          # A LATER VISIT while work is outstanding. Recording the checkpoint and returning
          # is the whole behaviour: the last job to terminalize schedules the next visit.
          return settle_waiting(d, evaluation, jobs, key_digest) unless terminal?(jobs)

          readiness = derive(store, command, crawl, manifest, jobs)
          return seal_ready(d, crawl, evaluation, manifest, jobs, readiness, key_digest) if readiness.ready?

          fail_inputs(d, crawl, evaluation, readiness, key_digest, manifest:)
        end

        # :470 read from the Crawl's own succeeded IngestionJobs, then validated against an
        # INDEPENDENT reading of the same fact — see `ParseManifest` for why the second
        # reading is what makes the omission predicate enforceable.
        def seal_manifest(store, command, org)
          ParseManifest.build(rows: store.manifest_rows(command.crawl_id), organization_id: org,
                              succeeded_ingestion_job_ids: store.succeeded_ingestion_job_ids(command.crawl_id))
        end

        def terminal?(jobs) = jobs.all? { |job| %w[succeeded dead_letter].include?(job["status"]) }

        # The ratified derivation, now over real Parsed Artifacts.
        def derive(store, command, crawl, manifest, jobs)
          roots = store.source_root_counts(command.crawl_id)
          succeeded = jobs.count { |job| job["status"] == "succeeded" }
          root_succeeded = jobs.count { |job| job["status"] == "succeeded" && truthy(job["source_root"]) }
          EvaluationInputReadiness.derive(
            manifest_valid: true,
            parser_policy_available: ParserPolicy.available?(command.organization_id, crawl["project_id"]),
            parsed_artifacts_succeeded: succeeded,
            source_root_artifacts_succeeded: root_succeeded,
            manifest_entries: manifest.size, jobs_succeeded: succeeded,
            crawl_coverage: crawl["coverage_status"]
          ).then { |result| Facts.new(result:, roots:) }
        end

        def blocked_by(_reason, manifest)
          Facts.new(result: EvaluationInputReadiness.blocked(manifest.invalid_detail),
                    roots: { "total" => 0, "with_root_document" => 0 })
        end

        def truthy(value) = value == true || value == "t" || value == "true"

        # The derivation plus the counts it was made from, so the audit record lets a
        # reader re-derive the decision rather than trust it.
        Facts = Data.define(:result, :roots) do
          def blocked? = result.blocked?
          def ready? = result.ready?
          def readiness_status = result.readiness_status
          def coverage_status = result.coverage_status
          def reason = result.reason
          def blocked_predicate = result.blocked_predicate
        end

        # ---- the blocked terminal transaction ---------------------------------------

        def fail_inputs(d, crawl, evaluation, readiness, key_digest, manifest: nil)
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
            "manifest_entries" => manifest&.size || 0,
            "source_roots" => readiness.roots["total"].to_i,
            "source_roots_with_document" => readiness.roots["with_root_document"].to_i,
            "parsed_artifacts_succeeded" => 0
          }

          # :439 the stage's outcome is the "immutable snapshot/BLOCKED RESULT transaction" —
          # a blocked derivation still seals a snapshot, carrying the manifest it was made
          # from, so the decision is re-derivable from a row rather than only from an event.
          snapshot_id = seal_snapshot(d, crawl, evaluation, manifest, readiness, [])
          payload["evaluation_input_snapshot_id"] = snapshot_id

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

        # ---- opening the parse ---------------------------------------------------------

        # One ParsingJob per manifest tuple, and one `parsing_attempt_due` per job, on this
        # transaction. :474 keys a job on `(document_id, content_digest,
        # parser_definition_version)`, so a re-crawl that fetched the SAME bytes returns the
        # existing job and a changed body creates a distinct one — which is what makes a
        # second crawl produce a second Artifact rather than overwrite the first.
        def open_parsing(d, crawl, evaluation, manifest, key_digest)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]
          ids = %i[execution audit result idem].to_h { |k| [k, ctx.generate_id] }
          request_sha256 = request_hash(command, ctx)

          created = manifest.entries.map do |entry|
            job_id = ctx.generate_id
            store.insert_parsing_job(
              id: job_id, now:, correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
              command_id: command.command_id, schema_version: ParsingContract::SCHEMA_VERSION,
              organization_id: org, project_id: entry["project_id"], source_id: entry["source_id"],
              crawl_id: command.crawl_id, evaluation_id: evaluation["id"],
              document_id: entry["document_id"], ingestion_job_id: entry["ingestion_job_id"],
              input_evidence_id: entry["input_evidence_id"], canonical_url: entry["canonical_url"],
              source_root: truthy(entry["source_root"]), media_type: entry["media_type"],
              content_digest: entry["content_digest"], data_classification: entry["data_classification"],
              parser_definition_version: ParserPolicy::DEFINITION_VERSION,
              normalization_schema_version: ParserPolicy::NORMALIZATION_SCHEMA_VERSION,
              idempotency_key: "#{entry["document_id"]}:#{entry["content_digest"]}"
            )
            job_id
          end

          # Re-read rather than trusting the ids: `ON CONFLICT DO NOTHING` means a tuple whose
          # job already existed inserted nothing, and the schedule must follow the rows that
          # are actually there.
          jobs = store.parsing_jobs_for_evaluation(evaluation["id"])
          jobs.each do |job|
            ParsingAttemptSchedule.schedule(
              pg: d[:store].connection, organization_id: org, project_id: evaluation["project_id"],
              parsing_job_id: job["id"], due_at: now, now:, correlation_id: ctx.correlation_id,
              command_id: command.command_id
            )
          end

          payload = {
            "evaluation_id" => evaluation["id"], "crawl_id" => command.crawl_id,
            "organization_id" => org, "stage" => STAGE, "outcome" => "parsing_opened",
            "manifest_entries" => manifest.size, "parsing_jobs" => jobs.length,
            "created" => created.compact.length
          }
          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          write_audit(store, ids[:audit], org, ctx, command, evaluation["id"], to_state: nil,
                      outcome: "success", reason_code: "parsing_opened", payload:, now:)
          write_result(store, ids, command, ctx, org, now, payload)
          write_idempotency(store, ids[:idem], org, command, key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

        # Work is still outstanding. Nothing is decided, and the checkpoint says so.
        def settle_waiting(d, evaluation, jobs, key_digest)
          record_checkpoint(d, evaluation, key_digest, reason: "parsing_in_progress", extra: {
            "outcome" => "waiting", "parsing_jobs" => jobs.length,
            "terminal" => jobs.count { |j| %w[succeeded dead_letter].include?(j["status"]) }
          })
        end

        # ---- the ready seal ------------------------------------------------------------

        # :510 "`ready_full` or `ready_partial` LEAVES IT PENDING for WF-007's single start
        # transition." So this seals the snapshot, freezes the derived Evidence, schedules
        # WF-007's first stage — and stops. Starting the Evaluation here would be taking
        # WF-007's one start away from it.
        def seal_ready(d, crawl, evaluation, manifest, jobs, readiness, key_digest)
          failed = jobs.reject { |job| job["status"] == "succeeded" }
                       .map { |job| { "document_id" => job["document_id"], "reason" => job["last_reason_code"] } }
          snapshot_id = seal_snapshot(d, crawl, evaluation, manifest, readiness, failed)
          # BEFORE the Evaluation can be evaluated, not after: a Check is a pure function of
          # frozen Evidence, so the observations it will read must exist and be immutable by
          # the time WF-007's first stage can run. They are produced on THIS transaction,
          # beside the snapshot they describe.
          evidence = derive_evidence(d, crawl, evaluation, snapshot_id)
          Wf007::EvaluationStageSchedule.schedule_applicability(
            pg: d[:store].connection, organization_id: d[:org], project_id: evaluation["project_id"],
            evaluation_id: evaluation["id"], due_at: d[:now], now: d[:now],
            correlation_id: d[:ctx].correlation_id, command_id: d[:command].command_id
          )

          record_checkpoint(d, evaluation, key_digest, reason: readiness.readiness_status, extra: {
            "outcome" => "inputs_ready", "evaluation_input_snapshot_id" => snapshot_id,
            "readiness_status" => readiness.readiness_status, "coverage_status" => readiness.coverage_status,
            "manifest_entries" => manifest.size,
            "parsed_artifacts_succeeded" => jobs.count { |job| job["status"] == "succeeded" },
            "failed_count" => failed.length, "derived_evidence" => evidence
          })
        end

        # The three baseline platform-derived payloads (SCORE_EVIDENCE_MODEL.md § Baseline
        # Platform-Derived Evidence Payloads). NO `external_measurement` is derived, because
        # `external-measurement-v1` bundles no query, intent, listing, provider or adapter set
        # and OD-010 ratified that state together with its consequence. Returns the produced
        # counts, so the checkpoint records what was frozen rather than that something was.
        def derive_evidence(d, crawl, evaluation, snapshot_id)
          store = d[:store]
          artifacts = store.parsed_artifacts_for_evaluation(evaluation["id"])
                           .map { |a| [a, EvidenceDerivation.artifact_payload(a)] }
          sources = store.active_crawl_sources(crawl["id"])
          outcomes = store.crawl_url_outcomes(crawl["id"])
          org_name = store.organization_display_name(d[:org])
          counts = Hash.new(0)

          common = { evaluation_id: evaluation["id"], organization_id: d[:org],
                     project_id: evaluation["project_id"], observed_at: d[:now], captured_at: d[:now],
                     correlation_id: d[:ctx].correlation_id }

          artifacts.each do |artifact, payload|
            EvidenceDerivation.produce(
              **common, source_id: artifact["source_id"], evidence_type: "parsed_content",
              schema_version: EvidenceDerivation::TITLE_SCHEMA, subject_key: artifact["canonical_url"],
              data_classification: artifact["data_classification"],
              payload: EvidenceDerivation.title_observation(artifact:, payload:, evaluation_id: evaluation["id"])
            )
            counts["document_title"] += 1
          end

          sources.each do |source|
            of_source = artifacts.select { |a, _| a["source_id"] == source["id"] }
            EvidenceDerivation.produce(
              **common, source_id: source["id"], evidence_type: "crawl_observation",
              schema_version: EvidenceDerivation::LINK_SCHEMA, subject_key: source["id"],
              payload: EvidenceDerivation.link_observation(
                source:, artifacts: of_source, evaluation_id: evaluation["id"], crawl_id: crawl["id"],
                crawl_coverage: crawl["coverage_status"], outcomes:
              )
            )
            counts["internal_link"] += 1

            # A Source whose ROOT was not parsed produces no identity observation at all,
            # which is not an omission: CHK-TR-001 still has an expected entry for that
            # Source and reaches an explicit handled `input_evidence_missing` error rather
            # than disappearing from the applicability set.
            root = of_source.find { |a, _| truthy(a["source_root"]) }
            next if root.nil?

            EvidenceDerivation.produce(
              **common, source_id: source["id"], evidence_type: "parsed_content",
              schema_version: EvidenceDerivation::IDENTITY_SCHEMA, subject_key: source["id"],
              data_classification: root[0]["data_classification"],
              payload: EvidenceDerivation.identity_observation(
                artifact: root[0], payload: root[1], evaluation_id: evaluation["id"],
                organization_name: org_name, canonical_root: source["canonical_root_uri"]
              )
            )
            counts["organization_identity"] += 1
          end

          counts.merge("evaluation_input_snapshot_id" => snapshot_id)
        end

        # The immutable snapshot :501 requires, with the canonical hash over its own content
        # so a reader can re-derive the readiness decision instead of trusting the status.
        def seal_snapshot(d, crawl, evaluation, manifest, readiness, failed)
          entries = manifest ? manifest.entries : []
          content = {
            "evaluation_id" => evaluation["id"], "crawl_id" => d[:command].crawl_id,
            "readiness_status" => readiness.readiness_status, "coverage_status" => readiness.coverage_status,
            "blocked_predicate" => readiness.blocked_predicate,
            "manifest" => entries, "failed_entries" => failed
          }
          id = Platform::DerivedUuid.v8(Platform::CanonicalJson.digest(content))
          d[:store].insert_evaluation_input_snapshot(
            id:, now: d[:now], correlation_id: d[:ctx].correlation_id, organization_id: d[:org],
            project_id: evaluation["project_id"], evaluation_id: evaluation["id"],
            crawl_id: d[:command].crawl_id, crawl_coverage_status: crawl["coverage_status"],
            crawl_completion_reason: crawl["completion_reason"],
            parser_policy_version: ParserPolicy.version,
            parser_definition_version: ParserPolicy::DEFINITION_VERSION,
            normalization_schema_version: ParserPolicy::NORMALIZATION_SCHEMA_VERSION,
            manifest: JSON.generate(entries), failed_entries: JSON.generate(failed),
            readiness_status: readiness.readiness_status, coverage_status: readiness.coverage_status,
            blocked_predicate: readiness.blocked_predicate,
            successful_count: entries.length - failed.length, failed_count: failed.length,
            source_roots_total: readiness.roots["total"].to_i,
            source_roots_succeeded: readiness.roots["with_root_document"].to_i,
            content_sha256: Platform::CanonicalJson.digest(content),
            schema_version: "evaluation-input-snapshot-v1"
          )
          id
        end

        # A checkpoint that decided nothing about the Evaluation's state but must still leave
        # a record that it ran and what it saw.
        def record_checkpoint(d, evaluation, key_digest, reason:, extra:)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]
          ids = %i[execution audit result idem].to_h { |k| [k, ctx.generate_id] }
          request_sha256 = request_hash(command, ctx)
          payload = { "evaluation_id" => evaluation["id"], "crawl_id" => command.crawl_id,
                      "organization_id" => org, "stage" => STAGE }.merge(extra)

          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          write_audit(store, ids[:audit], org, ctx, command, evaluation["id"], to_state: nil,
                      outcome: "success", reason_code: reason, payload:, now:)
          write_result(store, ids, command, ctx, org, now, payload)
          write_idempotency(store, ids[:idem], org, command, key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        end

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
