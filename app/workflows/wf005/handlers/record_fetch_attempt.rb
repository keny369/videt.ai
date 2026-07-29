# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf005
    module Handlers
      # WF-005 RecordFetchAttempt — the service execution behind the ratified `crawl_fetch_due`
      # ScheduledAction. This checkpoint makes the persisted fetch-attempt surface executable
      # without yet changing StartCrawl's accepted "seed frontier, no fetch handoff" shape.
      class RecordFetchAttempt
        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "fetch_attempt"
        ACTION = "crawl.fetch"
        POLICY_VERSION = "permission-baseline-v1"

        def call(command:, request_context:, outbound: Platform::Outbound)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)
          return in_memory_failure(command, ctx, "scheduled_action_target_mismatch") unless command.target_type == TARGET_TYPE

          prepared = prepare_execution(command, ctx)
          return prepared if prepared.is_a?(Platform::CommandResult)

          execution = Workflows::Wf005::FetchContent.new(
            outbound:, ids: ctx.ids, correlation_id: ctx.correlation_id
          ).record_persisted_attempt(
            organization_id: prepared[:org], crawl_id: prepared[:attempt]["crawl_id"],
            attempt: prepared[:attempt], now: prepared[:now]
          )

          finalize_execution(command, ctx, prepared, execution)
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

            attempts = IdentityAccess::Infrastructure::FetchAttemptStore.new(raw)
            attempts.enter_org_context(org:, correlation_id: ctx.correlation_id)
            attempt = attempts.attempt(org, command.attempt_id)
            return deny(store, command, ctx, org, now, "scheduled_action_target_mismatch") if attempt.nil?

            key_digest = Digest::SHA256.digest(command.action_identity_sha256)
            request_sha256 = request_hash(command)
            existing = store.find_idempotency(org:, command_type: command.command_type,
                                              target_type: TARGET_TYPE, target_id: command.attempt_id,
                                              key_digest:)
            if existing
              return rebuild(store, existing, command) if existing["request_hex"] == hex(request_sha256)

              return deny(store, command, ctx, org, now, "idempotency_conflict")
            end
            return deny(store, command, ctx, org, now, "scheduled_action_not_due") if now < command.due_at

            { store:, org:, now:, attempt:, key_digest:, request_sha256: }
          end
        end

        def finalize_execution(command, ctx, prepared, execution)
          Platform::UnitOfWork.run do |conn|
            raw = conn.raw_connection
            store = IdentityAccess::Infrastructure::CrawlStartStore.new(raw)
            store.enter_org_context(org: prepared[:org], correlation_id: ctx.correlation_id)
            attempts = IdentityAccess::Infrastructure::FetchAttemptStore.new(raw)
            attempts.enter_org_context(org: prepared[:org], correlation_id: ctx.correlation_id)
            attempt = attempts.attempt(prepared[:org], command.attempt_id)
            retry_info = schedule_retry(raw, command, ctx, attempt, execution)

            ids = %i[execution audit result idem].to_h { |k| [k, ctx.generate_id] }
            payload = payload_for(attempt, execution.result, retry_info)
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
        rescue Workflows::Wf005::FetchContent::AttemptStillInProgress
          raise
        end

        def schedule_retry(raw, command, ctx, attempt, execution)
          return {} unless execution.result.retryable
          return {} unless attempt["attempt_number"].to_i < Workflows::Wf005::FetchContent::MAX_ATTEMPTS
          return {} unless execution.remaining_reserved.to_i.positive?

          due_at = ctx.now_utc.floor(6) + (execution.retry_delay_ms.to_i / 1000.0)
          prepared = Workflows::Wf005::FetchAttemptDueSchedule.retry(
            pg: raw, attempt:, reserved_bytes: execution.remaining_reserved, due_at:, now: ctx.now_utc.floor(6),
            correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id, command_id: command.command_id
          )
          {
            "scheduled_retry_fetch_attempt_id" => prepared[:attempt_id],
            "scheduled_retry_action_id" => prepared[:action_id],
            "scheduled_retry_due_at_utc" => due_at.iso8601(6)
          }
        end

        def payload_for(attempt, result, retry_info)
          {
            "fetch_attempt_id" => attempt["id"],
            "crawl_id" => attempt["crawl_id"],
            "frontier_entry_id" => attempt["crawl_frontier_entry_id"],
            "attempt_number" => attempt["attempt_number"].to_i,
            "outcome" => result.outcome,
            "reason_code" => result.reason_code,
            "http_status" => result.http_status,
            "retryable" => result.retryable
          }.merge(retry_info)
        end

        def deny(store, command, ctx, org, now, reason)
          ids = %i[execution audit result].to_h { |k| [k, ctx.generate_id] }
          request_sha256 = request_hash(command)
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          write_audit(store, ids[:audit], org, ctx, command,
                      { "fetch_attempt_id" => command.attempt_id, "reason_code" => reason }, now,
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
            target_id: command.attempt_id, action: ACTION, requested_at: iso(command.requested_at_utc),
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
            entity_id: command.attempt_id, to_state: nil, outcome:, reason_code:,
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
            target_refs: JSON.generate({ "fetch_attempt_id" => command.attempt_id }),
            governing_policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            failure:, authorized_payload: JSON.generate(payload), audit_record_id: ids[:audit]
          )
        end

        def write_idempotency(store, id, command, org, key_digest, request_sha256, execution_id, result_id, now)
          store.insert_idempotency(
            id:, created_at: iso(now), organization_id: org, command_type: command.command_type,
            target_type: TARGET_TYPE, target_id: command.attempt_id, key_digest:, request_sha256:,
            command_execution_id: execution_id, command_result_id: result_id,
            retain_until: iso(now + 86_400)
          )
        end

        def request_hash(command)
          Platform::CanonicalJson.digest(
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "organization_id" => command.organization_id,
            "target_type" => TARGET_TYPE, "target_id" => command.attempt_id,
            "command_payload" => { "scheduled_action_id" => command.action_id }
          )
        end

        def hex(bytes) = bytes.unpack1("H*")
        def iso(time) = time.getutc.floor(6).iso8601(6)
        def month(time) = Date.new(time.year, time.month, 1)
        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
      end
    end
  end
end
