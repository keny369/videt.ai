# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf007
    module Handlers
      # WF-007's Evaluation stages (WORKFLOW_SPECIFICATIONS.md § WF-007 Primary Path;
      # S-09 owns steps 1-3, S-12 owns steps 4-5; OD-010 and OD-017 both **ratified**).
      #
      # WHICH STAGE RUNS IS DERIVED FROM THE EVALUATION, NOT FROM THE MESSAGE. A claimed
      # ScheduledAction hands a handler scalar identifiers only, so there is no payload to
      # carry a stage name — and that is the safer arrangement anyway: the Evaluation's own
      # persisted state answers the question unambiguously, and a stale or replayed action
      # therefore cannot instruct the pipeline to run a stage the Evaluation is not at.
      #
      #     no applicability snapshot          -> materialize_applicability
      #     slots outstanding                  -> record the visit and wait
      #     every slot terminal, no Issue Set  -> seal_issue_set
      #     Issue Set sealed                   -> void
      #
      # THE ORDER INSIDE `materialize_applicability` IS THE CONTRACT'S. Catalog validation is
      # a read-only precondition that commits nothing and runs FIRST, because "no partially
      # validated Catalog executes". Then the single start transition. Then the seal, after
      # which no expected entry may be added, removed or reordered. Then key materialization,
      # which "atomically creates or returns one Check Result identity for that preimage
      # BEFORE execution" — so a crash between materialization and execution leaves a
      # materialized key rather than a phantom Result.
      #
      # COMPLETION IS NOT PROMOTION. `seal_issue_set` transitions the Evaluation to completed
      # and seals the immutable Issue Set. The completed Evaluation REMAINS STAGED: no current
      # Issue-set pointer advances and no score is published, because promotion is WF-008's
      # atomic act and it needs a scorable ScoreSnapshot. That separation is exactly why the
      # ratified OD-010 baseline — an unavailable numeric score, because
      # `external-measurement-v1` bundles no active Measurement Set — does NOT fail WF-007. A
      # scoreless Evaluation is a completed Evaluation with an unpromoted pointer.
      class AdvanceEvaluationStage
        include StageLedger

        TARGET_TYPE = "evaluation"
        ACTION = "evaluation.advance"
        STAGE = "wf007_stage"

        def call(command:, request_context:)
          ctx = request_context
          return in_memory_failure(command, ctx, "command_schema_unsupported") unless supported_schema?(command.schema_version)
          return in_memory_failure(command, ctx, "scheduled_action_target_mismatch") unless command.target_type == TARGET_TYPE

          Platform::UnitOfWork.run { |conn| resolve(conn.raw_connection, command, ctx) }
        end

        private

        def target_id_of(command) = command.evaluation_id

        def resolve(pg, command, ctx)
          now = ctx.now_utc.floor(6)
          store = IdentityAccess::Infrastructure::CheckExecutionStore.new(pg)
          org = command.organization_id
          store.enter_org_context(org:, correlation_id: ctx.correlation_id)
          d = { store:, command:, ctx:, org:, now: }

          evaluation = store.read_evaluation(command.evaluation_id)
          return deny(d, "scheduled_action_target_mismatch") if evaluation.nil? || evaluation["organization_id"] != org

          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org:, command_type: command.command_type, target_type: TARGET_TYPE,
                                            target_id: command.evaluation_id, key_digest:)
          return rebuild(store, existing, command) if existing

          # The readiness derivation and the transition it decides are one critical section,
          # so two deliveries cannot both read the same state and both act on it.
          store.serialize_on("evaluation:#{command.evaluation_id}")
          evaluation = store.read_evaluation(command.evaluation_id)
          snapshot = store.applicability_snapshot_for(evaluation["id"])

          return settle_void(d, evaluation, key_digest) if terminal?(evaluation) && snapshot.nil?
          return materialize(d, evaluation, key_digest) if snapshot.nil?
          return settle_void(d, evaluation, key_digest) if store.issue_set_for(evaluation["id"])

          slots = store.slots_for_evaluation(evaluation["id"])
          return settle_waiting(d, evaluation, slots, key_digest) unless slots.all? { |s| s["state"] == "terminal" }

          seal_issue_set(d, evaluation, snapshot, key_digest)
        end

        def terminal?(evaluation) = %w[completed failed superseded].include?(evaluation["state"])

        # =================================================================================
        # STAGE 2-3 — validate, start, seal, materialize
        # =================================================================================

        def materialize(d, evaluation, key_digest)
          store = d[:store]
          ctx = d[:ctx]
          org = d[:org]
          now = d[:now]

          input_snapshot = store.read_input_snapshot(evaluation["id"])
          return fail_evaluation(d, evaluation, "evaluation_inputs_unavailable", key_digest) if input_snapshot.nil?
          # A ready snapshot is the precondition for evaluating at all; a blocked one has
          # already failed its Evaluation and cannot reach this stage.
          unless %w[ready_full ready_partial].include?(input_snapshot["readiness_status"])
            return fail_evaluation(d, evaluation, "evaluation_inputs_unavailable", key_digest)
          end
          # A reassessment Evaluation is ALREADY RUNNING under WF-011 and continues without a
          # second transition and without a second `EvaluationStarted`; only a pending initial
          # Evaluation is started here. Nothing else may enter the stage.
          unless %w[pending running].include?(evaluation["state"])
            return settle_void(d, evaluation, key_digest)
          end

          # READ-ONLY PRECONDITION, COMMITTING NOTHING. Recomputes the Catalog and Definition
          # digests and proves every mapping exhaustive. A failure here fails the Evaluation
          # BEFORE any Check or Issue write.
          catalog = store.active_catalog
          return fail_evaluation(d, evaluation, "check_catalog_unavailable", key_digest) if catalog.nil?

          begin
            CheckCatalog.validate!
            verify_catalog_digests!(catalog, store.catalog_entries(catalog["id"]))
          rescue Platform::InvariantViolation, Policies::CatalogIntegrityFailure
            return fail_evaluation(d, evaluation, "check_catalog_integrity_failure", key_digest)
          end

          profile = store.read_project_profile(evaluation["project_id"]) || {}
          entries = Applicability.build(
            organization_id: org, project_id: evaluation["project_id"], evaluation_id: evaluation["id"],
            sources: store.active_crawl_sources(evaluation["crawl_id"]),
            documents: store.parsed_documents(evaluation["id"]),
            evidence_index: store.evidence_index(evaluation["id"]),
            local_presence_applicable: pg_bool(profile["local_presence_applicable"]),
            local_presence_reason: profile["local_presence_reason"],
            # The freshness predicate is anchored on the INPUT SNAPSHOT'S sealed instant, not on
            # now: "an Evaluation Input Snapshot may consume an observation only when
            # `observed_at_utc <= snapshot_sealed_at_utc < fresh_until_utc`". Anchoring on the
            # current time would make a replay of the same Evaluation decide differently as the
            # clock moved, which is precisely the nondeterminism the sealed snapshot removes.
            snapshot_sealed_at: input_snapshot["created_at"]
          )

          ids = ledger_ids(ctx, :snapshot, :started)
          snapshot_id = ids[:snapshot]
          body = Applicability.content_body(
            catalog_version: CheckCatalog::CATALOG_VERSION,
            catalog_sha256: CheckCatalog.hex(CheckCatalog.catalog_digest),
            input_snapshot_id: input_snapshot["id"],
            project_profile_version: profile["project_profile_schema_version"],
            local_presence_applicable: pg_bool(profile["local_presence_applicable"]),
            local_presence_reason: profile["local_presence_reason"],
            active_source_ids: entries.filter_map(&:source_id).uniq, entries:
          )
          content_sha256 = Platform::CanonicalJson.digest(body)

          started_version = evaluation["state_version"].to_i + 1
          started = evaluation["state"] == "pending"
          if started && store.start_evaluation(evaluation["id"], evaluation["state_version"].to_i, now,
                                               snapshot_id, input_snapshot["id"]).to_i.zero?
            raise Platform::InvariantViolation, "evaluation started concurrently"
          end

          store.insert_applicability_snapshot(
            id: snapshot_id, now:, correlation_id: ctx.correlation_id, organization_id: org,
            project_id: evaluation["project_id"], evaluation_id: evaluation["id"],
            evaluation_input_snapshot_id: input_snapshot["id"], check_catalog_id: CheckCatalog.catalog_row_id,
            check_catalog_version: CheckCatalog::CATALOG_VERSION, check_catalog_sha256: CheckCatalog.catalog_digest,
            project_profile_version: profile["project_profile_schema_version"],
            local_presence_applicable: pg_bool(profile["local_presence_applicable"]),
            local_presence_reason: profile["local_presence_reason"],
            source_set_version: profile["source_set_version"].to_i,
            active_source_ids: pg_uuid_array(entries.filter_map(&:source_id).uniq),
            crawl_coverage_status: input_snapshot["coverage_status"],
            readiness_status: input_snapshot["readiness_status"], entry_count: entries.length,
            content_sha256:, schema_version: Applicability::SCHEMA_VERSION
          )

          scheduled = write_entries_and_slots(d, evaluation, input_snapshot, snapshot_id, content_sha256, entries)

          payload = {
            "evaluation_id" => evaluation["id"], "organization_id" => org,
            "stage" => "materialize_applicability", "outcome" => "applicability_sealed",
            "check_applicability_snapshot_id" => snapshot_id,
            "check_catalog_version" => CheckCatalog::CATALOG_VERSION,
            "expected_entries" => entries.length, "materialized_keys" => scheduled,
            "evaluation_started" => started
          }
          write_ledger(d, ids, key_digest, entity_id: evaluation["id"], to_state: started ? "running" : nil,
                       outcome: "success", reason_code: "applicability_sealed", payload:)
          if started
            emit_started(store, ids, org, ctx, d[:command], now, evaluation, started_version)
          end
          succeeded(d, ids, payload)
        end

        # One entry row, one result key, one slot and one `check_attempt_due` per expected
        # entry. The key and the slot are created BEFORE any execution is scheduled, so the
        # attempt that follows can only ever complete onto an identity that already exists.
        def write_entries_and_slots(d, evaluation, input_snapshot, snapshot_id, snapshot_sha256, entries)
          store = d[:store]
          ctx = d[:ctx]
          org = d[:org]
          now = d[:now]

          entries.each_with_index do |entry, index|
            entry_id = ctx.generate_id
            preimage = Applicability.key_preimage(
              evaluation_id: evaluation["id"], input_snapshot_id: input_snapshot["id"],
              applicability_snapshot_id: snapshot_id, catalog_version: CheckCatalog::CATALOG_VERSION,
              definition_id: entry.definition["check_definition_id"],
              definition_version: entry.definition["semantic_version"],
              subject_type: entry.canonical_subject_type, subject_key: entry.canonical_subject_key,
              pillar_id: entry.definition["pillar_id"]
            )
            digest = Applicability.key_digest(preimage)

            # A SAME HASH WITH A DIFFERENT RETAINED PREIMAGE NEVER MERGES. It is detected here,
            # before execution, and fails the Evaluation as `check_result_key_collision` — the
            # unique index is on the preimage, so the colliding record is findable rather than
            # silently refused.
            collision = store.colliding_result_key(evaluation["id"], digest, preimage)
            raise KeyCollision.new(collision, digest, preimage) if collision

            store.insert_applicability_entry(
              id: entry_id, now:, organization_id: org, project_id: evaluation["project_id"],
              snapshot_id:, catalog_entry_id: entry.catalog_entry_id,
              check_definition_row_id: entry.definition_row_id,
              check_definition_id: entry.definition["check_definition_id"],
              definition_version: entry.definition["semantic_version"],
              pillar_id: entry.definition["pillar_id"], subject_scope: entry.subject_scope,
              canonical_subject_type: entry.canonical_subject_type,
              canonical_subject_key: entry.canonical_subject_key, source_id: entry.source_id,
              document_id: entry.document_id, applicable: entry.applicable,
              inapplicable_reason: entry.inapplicable_reason,
              absence_selector: JSON.generate(entry.absence_selector),
              selected_evidence: JSON.generate(entry.selected_evidence),
              expected_key_preimage: preimage, expected_key_sha256: digest, ordering: index + 1
            )

            key_id = ctx.generate_id
            store.insert_result_key(
              id: key_id, now:, organization_id: org, project_id: evaluation["project_id"],
              evaluation_id: evaluation["id"], applicability_entry_id: entry_id, key_preimage: preimage,
              check_result_key_sha256: digest, collision_ordinal: 0, ordering: index + 1
            )
            slot_id = ctx.generate_id
            store.insert_result_slot(
              id: slot_id, now:, organization_id: org, project_id: evaluation["project_id"],
              evaluation_id: evaluation["id"], applicability_entry_id: entry_id,
              check_result_key_id: key_id,
              # The write-once preallocated Check Result identity. The Result row will be
              # inserted under exactly this id, which is why the two can never disagree.
              check_result_id: ctx.generate_id, ordering: index + 1
            )
            CheckAttemptSchedule.schedule(
              pg: store.connection, organization_id: org, project_id: evaluation["project_id"],
              slot_id:, due_at: now, now:, correlation_id: ctx.correlation_id,
              command_id: d[:command].command_id
            )
          end
          entries.length
        rescue KeyCollision => e
          record_key_collision(d, evaluation, e, snapshot_sha256)
          raise
        end

        # =================================================================================
        # STAGE 5 — derive Issues, seal the set, complete the Evaluation
        # =================================================================================

        def seal_issue_set(d, evaluation, snapshot, key_digest)
          store = d[:store]
          ctx = d[:ctx]
          org = d[:org]
          now = d[:now]
          ids = ledger_ids(ctx, :set, :completed)

          results = store.check_results_for_evaluation(evaluation["id"])
          # "After every expected Check Result is terminal AND the Issue set is internally
          # consistent" — an expected entry with no Result is not a set to seal, it is an
          # Evaluation that has not finished.
          if results.length != snapshot["entry_count"].to_i
            return fail_evaluation(d, evaluation, "check_result_set_incomplete", key_digest)
          end

          derived = derive_issues(d, evaluation, results, ids)
          members = store.project_issues(evaluation["project_id"]).map do |issue|
            issue.merge("current_leaf" => pg_bool(issue["current_leaf"]) == true,
                        "fingerprint_preimage" => unhex(issue["fingerprint_preimage"]))
          end
          ordered = IssueDerivation.order_members(members)
          root = IssueDerivation.membership_root(ordered)
          body = IssueDerivation.content_body(evaluation_id: evaluation["id"], ordered:, root_sha256: root)

          store.insert_issue_set(
            id: ids[:set], schema_version: IssueDerivation::ISSUE_SET_SCHEMA, now:,
            correlation_id: ctx.correlation_id, organization_id: org, project_id: evaluation["project_id"],
            evaluation_id: evaluation["id"], member_count: ordered.length,
            current_leaf_count: ordered.count { |m| m["current_leaf"] },
            membership_root_sha256: root, content_sha256: Platform::CanonicalJson.digest(body)
          )
          ordered.each_with_index do |member, index|
            store.insert_issue_set_membership(
              id: ctx.generate_id, now:, organization_id: org, project_id: evaluation["project_id"],
              issue_set_id: ids[:set], issue_id: member["id"], current_leaf: member["current_leaf"],
              frozen_state: member["state"], frozen_state_version: member["state_version"].to_i,
              ordering: index + 1
            )
          end

          completed_version = evaluation["state_version"].to_i + 1
          if store.complete_evaluation(evaluation["id"], evaluation["state_version"].to_i, now).to_i.zero?
            raise Platform::InvariantViolation, "evaluation completed concurrently"
          end

          payload = {
            "evaluation_id" => evaluation["id"], "organization_id" => org, "stage" => "seal_issue_set",
            "outcome" => "evaluation_completed", "issue_set_id" => ids[:set],
            "check_results" => results.length, "issues_created" => derived,
            "issue_set_members" => ordered.length,
            # The pillars whose Results are insufficient, so the approved unavailable score is
            # recorded as a derivation rather than asserted as a status.
            "insufficient_pillars" => results.select { |r| r["execution_status"] == "error" }
                                             .map { |r| r["pillar_id"] }.uniq.sort,
            "score_availability" => "unavailable"
          }
          write_ledger(d, ids, key_digest, entity_id: evaluation["id"], to_state: "completed",
                       outcome: "success", reason_code: "evaluation_completed", payload:)
          emit_completed(store, ids, org, ctx, d[:command], now, evaluation, completed_version, payload)
          succeeded(d, ids, payload)
        end

        # Check-To-Issue Rules, applied once per terminal Result. `passed`, `not_applicable`
        # and `error` create nothing; a `failed` Result creates one Issue if and only if it
        # references at least one effectively valid same-Organization Evidence record.
        def derive_issues(d, evaluation, results, _ids)
          store = d[:store]
          ctx = d[:ctx]
          org = d[:org]
          now = d[:now]
          created = 0

          results.sort_by { |r| [r["check_definition_id"], r["canonical_subject_key"]] }.each do |result|
            evidences = store.check_result_evidences(result["id"])
            next unless IssueDerivation.derivable?(result, evidences)

            definition = CheckCatalog.definition(result["check_definition_id"])
            issue_type = IssueDerivation.issue_type(definition, result["outcome_code"])
            preimage = IssueDerivation.fingerprint_preimage(
              organization_id: org, project_id: evaluation["project_id"], source_id: result["source_id"],
              check_definition_id: result["check_definition_id"], issue_type:,
              canonical_subject_type: result["canonical_subject_type"],
              canonical_subject_key: result["canonical_subject_key"]
            )
            digest = IssueDerivation.fingerprint_digest(preimage)

            # OD-017 AS RATIFIED: detection is at derivation, BEFORE any Issue write. A
            # same-hash/different-preimage record records the collision, emits
            # `IssueFingerprintCollision`, writes NO second Issue, and fails the Evaluation
            # closed. Exact-preimage replay is not a collision and remains enabled.
            collision = store.colliding_dedup_key(org, IssueDerivation::DEDUP_NAMESPACE, digest, preimage)
            raise IssueCollision.new(collision, digest, preimage, result) if collision

            key = store.allocate_dedup_key(id: ctx.generate_id, now:, organization_id: org,
                                           project_id: evaluation["project_id"],
                                           namespace: IssueDerivation::DEDUP_NAMESPACE,
                                           digest:, preimage:)
            disposition = IssueDerivation.disposition(result["confidence_status"], result["confidence_band"])
            issue_id = ctx.generate_id
            inserted = store.insert_issue(
              id: issue_id, schema_version: IssueDerivation::ISSUE_SCHEMA, now:,
              correlation_id: ctx.correlation_id, organization_id: org,
              project_id: evaluation["project_id"], evaluation_id: evaluation["id"],
              check_result_id: result["id"], source_id: result["source_id"],
              dedup_key_id: key["id"], issue_type:,
              fingerprint_version: IssueDerivation::FINGERPRINT_VERSION,
              fingerprint_preimage: preimage, fingerprint_sha256: digest,
              canonical_subject_type: result["canonical_subject_type"],
              canonical_subject_key: result["canonical_subject_key"],
              check_definition_id: result["check_definition_id"], pillar_id: result["pillar_id"],
              impact_band: result["impact_band"], confidence_value: result["confidence_value"],
              confidence_band: result["confidence_band"], confidence_status: result["confidence_status"],
              effort_band: result["effort_band"], effort_basis: result["effort_basis"],
              recommendation_template_id: result["recommendation_template_id"],
              state: disposition["state"], adjudication_status: disposition["adjudication_status"],
              publication_status: disposition["publication_status"],
              published_at: disposition["publication_status"] == "published" ? iso(now) : nil
            ).to_a.first
            # An exact-preimage replay inserted nothing and returns the stored Issue, which is
            # the ratified replay behaviour: one Issue, no second `IssueCreated`.
            next if inserted.nil?

            created += 1
            evidences.each_with_index do |evidence, index|
              store.insert_issue_evidence(
                id: ctx.generate_id, now:, organization_id: org, project_id: evaluation["project_id"],
                issue_id:, evidence_id: evidence["evidence_id"],
                evidence_sha256: evidence["evidence_sha256"].to_s.sub(/\A\\x/, ""),
                role: "origin", ordering: index + 1
              )
            end
            store.upsert_lineage_head(id: ctx.generate_id, now:, organization_id: org,
                                      project_id: evaluation["project_id"], dedup_key_id: key["id"],
                                      current_issue_id: issue_id)
          end
          created
        end

        # =================================================================================
        # outcomes
        # =================================================================================

        # The BOUNDARY failure path: the Evaluation transitions to failed, publishes no Issue
        # Set and leaves no partial Result behind. It is deliberately NOT the handled-error
        # path — promoting a handled Check error to here would destroy the eligible subset,
        # and demoting a boundary failure to a handled error would publish a finding from a
        # scheme that has demonstrably failed.
        def fail_evaluation(d, evaluation, reason, key_digest)
          store = d[:store]
          ids = ledger_ids(d[:ctx], :failed)
          version = evaluation["state_version"].to_i + 1
          if store.fail_evaluation(evaluation["id"], evaluation["state_version"].to_i, d[:now], reason).to_i.zero?
            raise Platform::InvariantViolation, "evaluation resolved concurrently"
          end

          payload = { "evaluation_id" => evaluation["id"], "organization_id" => d[:org],
                      "stage" => STAGE, "outcome" => "evaluation_failed", "reason_code" => reason }
          write_ledger(d, ids, key_digest, entity_id: evaluation["id"], to_state: "failed",
                       outcome: "failure", reason_code: reason, payload:)
          emit(store, ids, d[:org], d[:ctx], d[:command], d[:now], id: ids[:failed],
               event_type: "EvaluationFailed", profile: "state_transition", aggregate_type: "evaluation",
               aggregate_id: evaluation["id"], aggregate_version: version,
               extra: { "from_state" => evaluation["state"], "to_state" => "failed",
                        "reason_code" => reason, "evaluation_id" => evaluation["id"],
                        "project_id" => evaluation["project_id"], "outcome" => "failure" })
          succeeded(d, ids, payload)
        end

        def settle_waiting(d, evaluation, slots, key_digest)
          ids = ledger_ids(d[:ctx])
          payload = { "evaluation_id" => evaluation["id"], "organization_id" => d[:org],
                      "stage" => STAGE, "outcome" => "waiting",
                      "expected" => slots.length,
                      "terminal" => slots.count { |s| s["state"] == "terminal" } }
          write_ledger(d, ids, key_digest, entity_id: evaluation["id"], to_state: nil, outcome: "success",
                       reason_code: "check_execution_in_progress", payload:)
          succeeded(d, ids, payload)
        end

        # A visit with nothing left to resolve. It still records that it ran: a silent no-op
        # would leave a scheduled action with no trace of its execution.
        def settle_void(d, evaluation, key_digest)
          ids = ledger_ids(d[:ctx])
          payload = { "evaluation_id" => evaluation["id"], "organization_id" => d[:org],
                      "stage" => STAGE, "outcome" => "void", "evaluation_state" => evaluation["state"] }
          write_ledger(d, ids, key_digest, entity_id: evaluation["id"], to_state: nil, outcome: "success",
                       reason_code: "evaluation_stage_void", payload:)
          succeeded(d, ids, payload)
        end

        # =================================================================================
        # events and helpers
        # =================================================================================

        def emit_started(store, ids, org, ctx, command, now, evaluation, version)
          emit(store, ids, org, ctx, command, now, id: ids[:started], event_type: "EvaluationStarted",
               profile: "state_transition", aggregate_type: "evaluation", aggregate_id: evaluation["id"],
               aggregate_version: version,
               extra: { "from_state" => "pending", "to_state" => "running", "reason_code" => nil,
                        "evaluation_id" => evaluation["id"], "crawl_id" => evaluation["crawl_id"],
                        "project_id" => evaluation["project_id"], "outcome" => "success" })
        end

        def emit_completed(store, ids, org, ctx, command, now, evaluation, version, payload)
          emit(store, ids, org, ctx, command, now, id: ids[:completed], event_type: "EvaluationCompleted",
               profile: "state_transition", aggregate_type: "evaluation", aggregate_id: evaluation["id"],
               aggregate_version: version,
               extra: { "from_state" => "running", "to_state" => "completed", "reason_code" => nil,
                        "evaluation_id" => evaluation["id"], "project_id" => evaluation["project_id"],
                        "issue_set_id" => payload["issue_set_id"],
                        "expected_result_count" => payload["check_results"],
                        "actual_result_count" => payload["check_results"],
                        "score_availability" => "unavailable", "outcome" => "success" })
        end

        # Both fail-closed collision branches record their decision and re-raise, so the whole
        # transaction — including the Evaluation's own writes — rolls back and the Evaluation
        # is failed by the retry that follows rather than half-committed by this one.
        def record_key_collision(d, evaluation, error, snapshot_sha256)
          d[:store].insert_collision_decision(
            id: d[:ctx].generate_id, now: d[:now], correlation_id: d[:ctx].correlation_id,
            organization_id: d[:org], project_id: evaluation["project_id"],
            evaluation_id: evaluation["id"], fingerprint_kind: "check_result",
            fingerprint_sha256: error.digest, existing_record_type: "check_result",
            existing_record_id: error.collision["id"], conflicting_record_type: "check_result",
            conflicting_record_id: d[:ctx].generate_id,
            detecting_service_identity_id: d[:ctx].service_identity_id,
            definition_versions: CheckCatalog::DEFINITION_IDS.sort,
            input_sha256: snapshot_sha256, output_sha256: error.digest,
            collision_identity_sha256: Digest::SHA256.digest(error.preimage)
          )
        end

        # "Activation validation RECOMPUTES the Catalog and Definition digests" — against the
        # persisted rows, not against the constant that produced them. Recomputing the
        # constant against itself would prove nothing; this proves the database still holds
        # the catalogue the code believes it activated, which is the condition
        # `check_catalog_integrity_failure` exists to catch.
        def verify_catalog_digests!(row, entries)
          unless row["catalog_version"] == CheckCatalog::CATALOG_VERSION &&
                 row["content_sha256"] == CheckCatalog.hex(CheckCatalog.catalog_digest)
            raise Policies::CatalogIntegrityFailure, "catalog_digest_mismatch"
          end
          unless entries.length == CheckCatalog::DEFINITIONS.length
            raise Policies::CatalogIntegrityFailure, "catalog_membership_mismatch"
          end

          entries.each_with_index do |entry, index|
            definition = CheckCatalog::DEFINITIONS[index]
            expected = CheckCatalog.hex(CheckCatalog.definition_digest(definition))
            next if entry["check_definition_id"] == definition["check_definition_id"] &&
                    entry["definition_version"] == definition["semantic_version"] &&
                    entry["pillar_id"] == definition["pillar_id"] &&
                    entry["definition_sha256"] == expected &&
                    # The entry's denormalized digest and the Definition ROW's own digest must
                    # be byte-equal. A drift between them is the cross-version semantic reuse
                    # the contract names, and it is invisible unless both are compared.
                    entry["row_sha256"] == expected

            raise Policies::CatalogIntegrityFailure, "definition_digest_mismatch:#{entry['check_definition_id']}"
          end
        end

        def pg_bool(value)
          return nil if value.nil?

          [true, "t", "true"].include?(value)
        end

        def pg_uuid_array(ids) = "{#{ids.sort.join(',')}}"
        def unhex(value) = [value.to_s.sub(/\A\\x/, "")].pack("H*")

        class KeyCollision < StandardError
          attr_reader :collision, :digest, :preimage

          def initialize(collision, digest, preimage)
            @collision = collision
            @digest = digest
            @preimage = preimage
            super("check_result_key_collision")
          end
        end

        class IssueCollision < StandardError
          attr_reader :collision, :digest, :preimage, :result

          def initialize(collision, digest, preimage, result)
            @collision = collision
            @digest = digest
            @preimage = preimage
            @result = result
            super("issue_fingerprint_collision")
          end
        end
      end
    end
  end
end
