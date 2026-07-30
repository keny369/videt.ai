# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf005
    module Handlers
      # WF-005 RecordFetchAttempt — the service execution behind the ratified `crawl_fetch_due`
      # ScheduledAction, and :378's only permitted operation for the `crawl_fetch` work type.
      #
      # ONE ACTION IS ONE PASS OF THE RUN. The handler owns the ledger ceremony and nothing else:
      # `Wf005::CrawlDriver` decides and performs, and every product effect it produces belongs to the
      # accepted surfaces it drives. THREE PHASES, because MTX-030 ends "No external call sits inside a
      # database transaction":
      #
      #   1. PREPARE, in its own transaction: prove the Organization and the targeted frontier entry
      #      exist, replay an identical delivery from the idempotency record, refuse a differing one,
      #      and check the due-at gate. Nothing is decided and nothing is spent before this passes.
      #   2. THE PASS, holding NO transaction: robots, sitemap discovery, admission and the fetch, each
      #      opening and committing its own.
      #   3. THE TERMINAL TRANSACTION: the next-frontier link and the execution/audit/result/
      #      idempotency records, together. :378 — "its terminal transaction creates the exact
      #      ingestion or next-frontier action" — so a pass that records its result and a pass that
      #      schedules the next one are the same commit, and a rolled-back pass leaves no link.
      #
      # THE TARGET IS THE FRONTIER ENTRY (DECISIONS ADR-085). The ledger therefore attributes the
      # execution, the audit record and the result to the row the pass actually claimed, which is only
      # true because `Admission#claim_entry` refuses to claim anything else.
      class RecordFetchAttempt
        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "crawl_frontier_entry"
        ACTION = "crawl.fetch"
        POLICY_VERSION = "permission-baseline-v1"

        def call(command:, request_context:, outbound: Platform::Outbound, pacer: nil)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)
          return in_memory_failure(command, ctx, "scheduled_action_target_mismatch") unless command.target_type == TARGET_TYPE

          prepared = prepare_execution(command, ctx)
          return prepared if prepared.is_a?(Platform::CommandResult)

          pass = Workflows::Wf005::CrawlDriver.new(
            outbound:, ids: ctx.ids, correlation_id: ctx.correlation_id, pacer:
          ).advance(organization_id: prepared[:org], entry: prepared[:entry], now: prepared[:now])

          finalize_execution(command, ctx, prepared, pass)
        end

        private

        def prepare_execution(command, ctx)
          Platform::UnitOfWork.run do |conn|
            raw = conn.raw_connection
            store = IdentityAccess::Infrastructure::CrawlStartStore.new(raw)
            org = command.organization_id
            now = ctx.now_utc.floor(6)
            store.enter_org_context(org:, correlation_id: ctx.correlation_id)
            return in_memory_failure(command, ctx, "scheduled_action_target_mismatch") if store.organization(org).nil?

            frontier = IdentityAccess::Infrastructure::CrawlFrontierStore.new(raw)
            frontier.enter_org_context(org:, correlation_id: ctx.correlation_id)
            entry = frontier.entry(org, command.frontier_entry_id)
            return deny(store, command, ctx, org, now, "scheduled_action_target_mismatch") if entry.nil?

            key_digest = Digest::SHA256.digest(command.action_identity_sha256)
            request_sha256 = request_hash(command)
            existing = store.find_idempotency(org:, command_type: command.command_type,
                                              target_type: TARGET_TYPE, target_id: command.frontier_entry_id,
                                              key_digest:)
            if existing
              return rebuild(store, existing, command) if existing["request_hex"] == hex(request_sha256)

              return deny(store, command, ctx, org, now, "idempotency_conflict")
            end
            return deny(store, command, ctx, org, now, "scheduled_action_not_due") if now < command.due_at

            { store:, org:, now:, entry:, key_digest:, request_sha256: }
          end
        end

        def finalize_execution(command, ctx, prepared, pass)
          Platform::UnitOfWork.run do |conn|
            raw = conn.raw_connection
            store = IdentityAccess::Infrastructure::CrawlStartStore.new(raw)
            store.enter_org_context(org: prepared[:org], correlation_id: ctx.correlation_id)
            link = schedule_next(raw, command, ctx, prepared, pass)

            ids = %i[execution audit result idem].to_h { |k| [k, ctx.generate_id] }
            payload = payload_for(prepared[:entry], pass, link)
            write_execution(store, command, ctx, prepared[:org], ids[:execution],
                            prepared[:request_sha256], prepared[:key_digest], prepared[:now])
            write_audit(store, ids[:audit], prepared[:org], ctx, command, payload, prepared[:now])
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

        # :378's "its terminal transaction creates the exact ... next-frontier action", on the
        # terminal transaction's own connection.
        #
        # A HALTED pass creates NOTHING, and that is the whole of :442's "stop scheduling affected
        # work": a run that has hit a hard byte limit, run out its wall clock, lost its authorization
        # or fail-closed on robots must not be handed more work. The chain ends and the Crawl's
        # terminal checkpoint reports what happened.
        def schedule_next(raw, command, ctx, prepared, pass)
          entry = prepared[:entry]
          common = { pg: raw, organization_id: prepared[:org], project_id: entry["project_id"],
                     now: prepared[:now], correlation_id: ctx.correlation_id,
                     causation_id: ctx.correlation_id, command_id: command.command_id }
          if pass.reenters?
            return Workflows::Wf005::CrawlFetchDueSchedule.reenter(
              **common, entry_id: entry["id"], at: pass.reenter_at
            )
          end
          return {} unless pass.advances?

          Workflows::Wf005::CrawlFetchDueSchedule.link_next(**common, crawl_id: entry["crawl_id"])
        end

        def payload_for(entry, pass, link)
          result = pass.fetch
          {
            "frontier_entry_id" => entry["id"],
            "crawl_id" => entry["crawl_id"],
            "canonical_url" => entry["canonical_url"],
            "pass_outcome" => pass.outcome,
            "outcome" => result&.outcome,
            "reason_code" => pass.reason_code,
            "http_status" => result&.http_status,
            "accounted_response_bytes" => result && result.accounted_bytes.to_i,
            "retryable" => result&.retryable,
            # The run's forward link, or its absence, which is the fact a reader needs most: an empty
            # link on an advancing pass means the frontier had nothing selectable left.
            "next_frontier_entry_id" => link[:entry_id],
            "next_action_id" => link[:action_id],
            "next_due_at_utc" => link[:due_at]&.getutc&.iso8601(6),
            "frontier_drained" => pass.advances? && link[:entry_id].nil?,
            # Whether this pass retired the entry it claimed and so released :454's depth seal. False on
            # a pass that claimed nothing, and false on a redelivery whose entry another pass retired —
            # the compare-and-set reports that rather than rewriting a decision.
            "frontier_seal_released" => pass.released
          }
        end

        def deny(store, command, ctx, org, now, reason)
          ids = %i[execution audit result].to_h { |k| [k, ctx.generate_id] }
          request_sha256 = request_hash(command)
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          write_audit(store, ids[:audit], org, ctx, command,
                      { "frontier_entry_id" => command.frontier_entry_id, "reason_code" => reason }, now,
                      outcome: "failure", reason_code: reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          write_result(store, ids, command, ctx, org, {}, now, failure:)

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
            target_id: command.frontier_entry_id, action: ACTION, requested_at: iso(command.requested_at_utc),
            authorization_check_at: iso(now),
            policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            canonical_payload: JSON.generate({ "scheduled_action_id" => command.action_id }), request_sha256:
          )
        end

        def write_audit(store, id, org, ctx, command, payload, now, outcome: "success", reason_code: payload["reason_code"])
          store.insert_audit(
            id:, occurred_at: iso(now), partition_month: month(now), organization_id: org,
            service_identity_id: ctx.service_identity_id, correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id, entity_type: TARGET_TYPE,
            entity_id: command.frontier_entry_id, to_state: nil, outcome:, reason_code:,
            payload: JSON.generate(payload), content_sha256: Platform::CanonicalJson.digest(payload)
          )
        end

        def write_result(store, ids, command, ctx, org, payload, now, failure: nil)
          store.insert_command_result(
            id: ids[:result], created_at: iso(now), correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id,
            command_execution_id: ids[:execution], outcome: failure ? "failure" : "success",
            organization_id: org, service_identity_id: ctx.service_identity_id,
            completed_at: iso(now), authorization_check_at: iso(now),
            target_refs: JSON.generate({ "crawl_frontier_entry_id" => command.frontier_entry_id }),
            governing_policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            failure:, authorized_payload: JSON.generate(payload), audit_record_id: ids[:audit]
          )
        end

        def write_idempotency(store, id, command, org, key_digest, request_sha256, execution_id, result_id, now)
          store.insert_idempotency(
            id:, created_at: iso(now), organization_id: org, command_type: command.command_type,
            target_type: TARGET_TYPE, target_id: command.frontier_entry_id, key_digest:, request_sha256:,
            command_execution_id: execution_id, command_result_id: result_id,
            retain_until: iso(now + 86_400)
          )
        end

        def request_hash(command)
          Platform::CanonicalJson.digest(
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "organization_id" => command.organization_id,
            "target_type" => TARGET_TYPE, "target_id" => command.frontier_entry_id,
            "command_payload" => { "scheduled_action_id" => command.action_id }
          )
        end

        def schema_failure(command, ctx) = in_memory_failure(command, ctx, "command_schema_unsupported")

        def in_memory_failure(command, ctx, reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                          failure:, audit_record_id: ctx.generate_id, correlation_id: ctx.correlation_id)
        end

        def hex(bytes) = bytes.unpack1("H*")
        def iso(time) = time.getutc.floor(6).iso8601(6)
        def month(time) = Date.new(time.year, time.month, 1)
        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
      end
    end
  end
end
