# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf007
    module Handlers
      # One attempt of one materialized expected key (`check-executor-interim-v1`; PRULE-010).
      #
      # THE ATTEMPT MAKES NO EXTERNAL CALL, so there is no window in which a transaction is
      # held open across a network round trip. The Evidence payloads are revealed, the pure
      # rule decides, and the semantic output is committed onto the identity the Slot already
      # preallocated — all in one transaction, which is stronger than the contract's minimum
      # ("the attempt runs outside any transaction and only its semantic output is committed")
      # and is available precisely BECAUSE no Check calls anything.
      #
      # WHY THE RETRY IS ABSENT RATHER THAN UNIMPLEMENTED. The bounded retry exists for
      # exactly two reasons — `check_dependency_unavailable` and `check_internal_timeout` —
      # and both are properties of a call this executor does not make. Every other reason,
      # including every semantic input problem, persists a ONE-ATTEMPT error by contract. So
      # the code that would schedule a second attempt would be unreachable, and writing
      # unreachable recovery is how a retry policy comes to be believed rather than tested.
      # `CheckAttemptSchedule` carries the attempt number for the day a retryable reason
      # exists, and the schema admits `execution_attempt_count` of 2.
      #
      # A LATE OR DUPLICATE DELIVERY WRITES NOTHING. A Slot that is already `terminal` records
      # the visit and returns; it cannot create or replace a Check Result.
      class ExecuteCheckAttempt
        include StageLedger

        TARGET_TYPE = "check_result_slot"
        ACTION = "evaluation.advance"
        STAGE = "execute_check_result"
        ATTEMPT_CEILING_SECONDS = 5

        def call(command:, request_context:)
          ctx = request_context
          return in_memory_failure(command, ctx, "command_schema_unsupported") unless supported_schema?(command.schema_version)
          return in_memory_failure(command, ctx, "scheduled_action_target_mismatch") unless command.target_type == TARGET_TYPE

          Platform::UnitOfWork.run { |conn| resolve(conn.raw_connection, command, ctx) }
        end

        private

        def target_id_of(command) = command.slot_id

        def resolve(pg, command, ctx)
          now = ctx.now_utc.floor(6)
          store = IdentityAccess::Infrastructure::CheckExecutionStore.new(pg)
          org = command.organization_id
          store.enter_org_context(org:, correlation_id: ctx.correlation_id)
          d = { store:, command:, ctx:, org:, now: }

          slot = store.read_slot(command.slot_id)
          return deny(d, "scheduled_action_target_mismatch") if slot.nil? || slot["organization_id"] != org

          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org:, command_type: command.command_type, target_type: TARGET_TYPE,
                                            target_id: command.slot_id, key_digest:)
          return rebuild(store, existing, command) if existing

          store.serialize_on("check-slot:#{command.slot_id}")
          slot = store.read_slot(command.slot_id)
          return settle_void(d, slot, key_digest) if slot["state"] == "terminal"

          attempt(d, slot, key_digest)
        end

        def attempt(d, slot, key_digest)
          store = d[:store]
          ctx = d[:ctx]
          org = d[:org]
          now = d[:now]

          version = slot["state_version"].to_i
          raise LostRace if store.start_slot(slot["id"], version, now).to_i.zero?

          entry = store.read_entry(slot["applicability_entry_id"])
          snapshot = store.applicability_snapshot_for(slot["evaluation_id"])
          definition = CheckCatalog.definition(entry["check_definition_id"])
          selected = JSON.parse(entry["selected_evidence"])
          entry_view = entry.merge(
            "absence_selector" => JSON.parse(entry["absence_selector"]),
            "selected_evidence" => selected,
            "applicable" => pg_bool(entry["applicable"])
          )

          input = Executor.input_tuple(
            organization_id: org, project_id: entry["project_id"],
            input_snapshot_id: snapshot["evaluation_input_snapshot_id"],
            catalog_version: snapshot["check_catalog_version"], catalog_sha256: snapshot["check_catalog_sha256"],
            applicability_snapshot_id: snapshot["id"], applicability_sha256: snapshot["content_sha256"],
            definition:, entry: entry_view
          )
          decision = Executor.run(
            entry: entry_view, definition:, input:,
            evidence_payloads: reveal_evidence(store, selected, org),
            project_profile_version: snapshot["project_profile_version"]
          )

          persist(d, slot, entry, snapshot, definition, selected, decision, version + 1, key_digest)
        rescue LostRace
          raise Platform::InvariantViolation, "check slot claimed concurrently"
        end

        # The Evidence a Check may read is exactly what its frozen applicability entry
        # selected — nothing is looked up by any other route, which is what makes "selects no
        # Evidence" a determinate outcome rather than a failed search.
        def reveal_evidence(store, selected, org)
          selected.each_with_object({}) do |item, map|
            row = store.read_evidence_payload(item["evidence_id"])
            next if row.nil? || row["organization_id"] != org

            aad = Platform::Encryption::Aad.for(**payload_aad(row), record_id: row["attempt_id"], tenant: org)
            map[item["evidence_id"]] = JSON.parse(Platform::Encryption.reveal(row["payload_reference"], aad:))
          end
        end

        # THE AAD IS CHOSEN BY THE EVIDENCE'S OWN TYPE, because the AAD is what binds a payload to
        # the producer that sealed it. A platform-derived observation and an externally submitted
        # measurement are sealed under different bindings on purpose: a derived-observation AAD
        # cannot open an external-measurement payload, so a reader that guessed one binding for
        # everything would fail authentication rather than silently read the wrong thing. Guessing
        # a single AAD is exactly what this did at first, and the cipher refused it — correctly.
        def payload_aad(row)
          case row["evidence_type"]
          when "external_measurement" then Wf006::MeasurementIntake::OBSERVATION_AAD
          else Wf006::EvidenceDerivation::EVIDENCE_AAD
          end
        end

        def persist(d, slot, entry, snapshot, definition, selected, decision, slot_version, key_digest)
          store = d[:store]
          ctx = d[:ctx]
          org = d[:org]
          now = d[:now]
          ids = ledger_ids(ctx, :attempt, :created)
          result_id = slot["check_result_id"]

          store.insert_check_result(
            id: result_id, schema_version: Executor::SCHEMA_VERSION, now:,
            correlation_id: ctx.correlation_id, organization_id: org, project_id: entry["project_id"],
            evaluation_id: slot["evaluation_id"],
            evaluation_input_snapshot_id: snapshot["evaluation_input_snapshot_id"],
            applicability_snapshot_id: snapshot["id"], applicability_entry_id: entry["id"],
            slot_id: slot["id"], check_result_key_id: slot["check_result_key_id"],
            check_result_key_sha256: unhex_bytea(entry["expected_key_sha256"]),
            check_result_key_preimage: unhex_bytea(entry["expected_key_preimage"]),
            check_catalog_version: snapshot["check_catalog_version"],
            check_definition_row_id: entry["check_definition_row_id"],
            check_definition_id: entry["check_definition_id"],
            check_definition_version: entry["definition_version"], pillar_id: entry["pillar_id"],
            subject_scope: entry["subject_scope"], canonical_subject_type: entry["canonical_subject_type"],
            canonical_subject_key: entry["canonical_subject_key"], source_id: entry["source_id"],
            document_id: entry["document_id"], absence_coverage_selector: entry["absence_selector"],
            subject_set_complete: decision.subject_set_complete,
            evidence_set_sha256: evidence_set_digest(selected),
            execution_status: decision.execution_status, outcome_code: decision.outcome_code,
            error_reason_code: decision.error_reason_code,
            normalized_observation: JSON.generate(decision.observation),
            impact_band: decision.impact_band, impact_rule_version: decision.impact_rule_version,
            confidence_value: decision.confidence["confidence_value"],
            confidence_status: decision.confidence["confidence_status"],
            confidence_band: decision.confidence["confidence_band"],
            confidence_policy_version: decision.confidence["confidence_policy_version"],
            effort_band: decision.effort["effort_band"], effort_basis: decision.effort["effort_basis"],
            recommendation_template_id: decision.recommendation_template_id,
            rule_or_model_version: decision.rule_or_model_version,
            execution_attempt_count: d[:command].attempt_number,
            deterministic_input_sha256: decision.input_sha256,
            deterministic_output_sha256: decision.output_sha256
          )

          # The Evidence references and their FROZEN Validation Decision statuses, as of Check
          # creation. A later Decision never changes them.
          selected.each_with_index do |item, index|
            store.insert_check_result_evidence(
              id: ctx.generate_id, now:, organization_id: org, project_id: entry["project_id"],
              check_result_id: result_id, evidence_id: item["evidence_id"],
              evidence_sha256: item["evidence_sha256"],
              validation_decision_id: item["validation_decision_id"],
              validation_status: item["validation_status"], ordering: index + 1
            )
          end

          store.insert_attempt(
            id: ids[:attempt], now:, organization_id: org, project_id: entry["project_id"],
            evaluation_id: slot["evaluation_id"], slot_id: slot["id"],
            attempt_number: d[:command].attempt_number,
            retry_of_attempt_number: d[:command].attempt_number > 1 ? d[:command].attempt_number - 1 : nil,
            check_catalog_version: snapshot["check_catalog_version"],
            check_definition_id: entry["check_definition_id"], definition_version: entry["definition_version"],
            applicability_sha256: unhex_bytea(snapshot["content_sha256"]),
            result_key_sha256: unhex_bytea(entry["expected_key_sha256"]),
            deterministic_input_sha256: decision.input_sha256, scheduled_at: d[:command].due_at,
            started_at: now, completed_at: now, deadline_at: now + ATTEMPT_CEILING_SECONDS,
            produced_check_result_id: result_id, output_sha256: decision.output_sha256,
            execution_status: decision.execution_status, elapsed_ms: 0,
            reason_code: decision.error_reason_code
          )

          raise LostRace if store.terminalize_slot(slot["id"], slot_version, now, result_id).to_i.zero?

          # THE HANDOFF BACK TO THE STAGE CHAIN. Scheduling from the LAST terminal slot rather
          # than from every one means one seal visit per Evaluation instead of one per Check.
          #
          # "LAST" IS ONLY A FACT UNDER A LOCK ON THE EVALUATION, and this is the defect a live
          # run found that the suite did not. The Checks execute on a pool of five workers, so
          # several attempts commit at once; each transaction reads a snapshot in which the
          # others' terminalizations are still uncommitted, every one of them counts an
          # outstanding sibling, and NOBODY schedules the seal. The Evaluation then holds seven
          # terminal Results, stays `running` for ever, and keeps the OD-018 guard latched —
          # the exact failure this whole chain exists to prevent, reached from a new direction.
          #
          # Taking the Evaluation's advisory lock here serializes only this decision, not the
          # execution: whoever acquires it last re-reads a snapshot in which every earlier
          # sibling has committed, sees zero outstanding, and schedules exactly once. The lock
          # is taken AFTER the slot lock, and `AdvanceEvaluationStage` takes the Evaluation
          # lock alone and no slot lock, so there is no cycle to deadlock on.
          store.serialize_on("evaluation:#{slot['evaluation_id']}")
          outstanding = store.slots_for_evaluation(slot["evaluation_id"])
                             .reject { |s| s["id"] == slot["id"] }
                             .count { |s| s["state"] != "terminal" }
          if outstanding.zero?
            EvaluationStageSchedule.schedule_issue_set(
              pg: store.connection, organization_id: org, project_id: entry["project_id"],
              evaluation_id: slot["evaluation_id"], due_at: now, now:,
              correlation_id: ctx.correlation_id, command_id: d[:command].command_id
            )
          end

          payload = {
            "check_result_id" => result_id, "slot_id" => slot["id"],
            "evaluation_id" => slot["evaluation_id"], "organization_id" => org, "stage" => STAGE,
            "check_definition_id" => entry["check_definition_id"],
            "canonical_subject_key" => entry["canonical_subject_key"],
            "execution_status" => decision.execution_status, "outcome_code" => decision.outcome_code,
            "error_reason_code" => decision.error_reason_code, "impact_band" => decision.impact_band,
            "subject_set_complete" => decision.subject_set_complete,
            "outstanding_slots" => outstanding
          }
          write_ledger(d, ids, key_digest, entity_id: slot["evaluation_id"], to_state: nil,
                       outcome: "success", reason_code: decision.outcome_code, payload:)
          emit_created(store, ids, org, ctx, d[:command], now, slot, entry, decision, result_id)
          succeeded(d, ids, payload)
        end

        # `CheckResultCreated` is emitted ONLY with the one persisted Result. Retrying or
        # completing late cannot duplicate it, because a terminal Slot never reaches here.
        # The per-attempt telemetry row is implementation-owned infrastructure and is
        # deliberately NOT emitted as a domain event.
        def emit_created(store, ids, org, ctx, command, now, slot, entry, decision, result_id)
          emit(store, ids, org, ctx, command, now, id: ids[:created], event_type: "CheckResultCreated",
               profile: "created", aggregate_type: "check_result", aggregate_id: result_id,
               aggregate_version: 0,
               extra: { "evaluation_id" => slot["evaluation_id"], "project_id" => entry["project_id"],
                        "check_result_id" => result_id,
                        "check_catalog_version" => CheckCatalog::CATALOG_VERSION,
                        "check_definition_id" => entry["check_definition_id"],
                        "check_definition_version" => entry["definition_version"],
                        "canonical_subject_type" => entry["canonical_subject_type"],
                        "canonical_subject_key" => entry["canonical_subject_key"],
                        "attempt_number" => command.attempt_number,
                        "deterministic_input_sha256" => decision.input_sha256.unpack1("H*"),
                        "execution_status" => decision.execution_status,
                        "outcome_code" => decision.outcome_code, "retry_of_attempt" => nil,
                        "elapsed_ms" => 0, "outcome" => "success" })
        end

        def settle_void(d, slot, key_digest)
          ids = ledger_ids(d[:ctx])
          payload = { "slot_id" => slot["id"], "evaluation_id" => slot["evaluation_id"],
                      "organization_id" => d[:org], "stage" => STAGE, "outcome" => "void",
                      "slot_state" => slot["state"] }
          write_ledger(d, ids, key_digest, entity_id: slot["evaluation_id"], to_state: nil,
                       outcome: "success", reason_code: "check_attempt_void", payload:)
          succeeded(d, ids, payload)
        end

        # The `evidence_set_hash` over the ordered selected Evidence identities and digests.
        # An empty selection still has a digest — the hash of "nothing was selected" — so a
        # baseline `input_evidence_missing` Result carries a real value rather than a null.
        def evidence_set_digest(selected)
          Platform::CanonicalJson.digest(
            selected.sort_by { |e| e["evidence_id"].to_s }
                    .map { |e| { "evidence_id" => e["evidence_id"], "evidence_sha256" => e["evidence_sha256"] } }
          )
        end

        def pg_bool(value) = [true, "t", "true"].include?(value)
        def unhex_bytea(value) = [value.to_s.sub(/\A\\x/, "")].pack("H*")

        class LostRace < StandardError; end
      end
    end
  end
end
