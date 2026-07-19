# frozen_string_literal: true

require "digest"
require "time"
require "json"

module Workflows
  module Wf001
    module Handlers
      # WF-001 grant-issuance branch (APPLICATION_LAYER.md § WF-001). The approved
      # identity/bootstrap service issues one 15-minute Bootstrap Grant for a
      # validated principal, consuming the receipt nonce and emitting exactly one
      # BootstrapGrantIssued, writing no tenant record. Exact replay returns the
      # stored grant and emits no event; a concurrent different-key request or an
      # already-completed principal is rejected. Runs one unit of work; the grant
      # guard is a tier-zero advisory lock on the not-yet-existing principal.
      class RequestBootstrapGrant
        SUPPORTED_SCHEMA_MAJOR = "1"
        POLICY_VERSION = "onboarding-interim-v1"
        TARGET_TYPE = "bootstrap_grant"
        ACTION = "organization.bootstrap"
        SCOPE_KIND = "bootstrap_principal"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          Platform::UnitOfWork.run do |conn|
            store = IdentityAccess::Infrastructure::PretenantGrantStore.new(conn.raw_connection)
            receipt_row = store.enter_bootstrap_context(receipt_digest: command.receipt_digest,
                                                        correlation_id: ctx.correlation_id)
            if receipt_row.nil?
              # An unresolved digest carries no principal and no ledger context.
              unresolved_receipt_failure(command, ctx)
            else
              issue_or_reject(command:, ctx:, store:, receipt_row:)
            end
          end
        end

        private

        # ---- main branch, executed under proved principal context --------------

        def issue_or_reject(command:, ctx:, store:, receipt_row:)
          principal_hex = receipt_row["principal_hex"]
          context_org = receipt_row["context_org"]
          now = ctx.now_utc.floor(6)
          request_sha256 = request_hash(command:, ctx:, principal_hex:)
          key_digest = Digest::SHA256.digest(command.idempotency_key)

          store.lock_principal(principal_hex)

          existing = store.find_idempotency(scope_kind: SCOPE_KIND, principal_hex:,
                                            command_type: command.command_type,
                                            target_type: TARGET_TYPE, key_digest:)
          if existing
            return replay(store, existing, command, request_sha256) if existing["request_hex"] == hex(request_sha256)

            return reject(store:, command:, ctx:, receipt_row:, principal_hex:, context_org:, now:,
                          request_sha256:, key_digest:, reason: "idempotency_conflict", consume_nonce: false)
          end

          receipt = build_receipt(receipt_row)
          if (reason = receipt.grant_request_reason(now_utc: now))
            return reject(store:, command:, ctx:, receipt_row:, principal_hex:, context_org:, now:,
                          request_sha256:, key_digest:, reason:)
          end

          if store.consumed_grant_exists?
            return reject(store:, command:, ctx:, receipt_row:, principal_hex:, context_org:, now:,
                          request_sha256:, key_digest:, reason: "bootstrap_already_completed")
          end
          if store.issued_grant_id
            return reject(store:, command:, ctx:, receipt_row:, principal_hex:, context_org:, now:,
                          request_sha256:, key_digest:, reason: "bootstrap_grant_already_issued")
          end

          issue(store:, command:, ctx:, receipt_row:, principal_hex:, context_org:, now:,
                request_sha256:, key_digest:)
        end

        def issue(store:, command:, ctx:, receipt_row:, principal_hex:, context_org:, now:, request_sha256:, key_digest:)
          ids = { execution: ctx.generate_id, grant: ctx.generate_id, authz: ctx.generate_id,
                  audit: ctx.generate_id, event: ctx.generate_id, result: ctx.generate_id,
                  consumption: ctx.generate_id, idem: ctx.generate_id }
          causation = ctx.correlation_id

          write_execution(store, command, ctx, principal_hex, ids[:execution], request_sha256, key_digest, now, causation, ids[:grant])
          store.insert_pretenant_authorization(
            id: ids[:authz], created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: causation,
            command_id: command.command_id, principal_hex:, receipt_id: receipt_row["receipt_id"],
            service_identity_id: ctx.service_identity_id, action: ACTION, decision: "allow",
            reason_code: "bootstrap_eligibility_satisfied", policy_versions: policy_versions_json, decided_at: iso(now)
          )
          store.insert_bootstrap_grant(
            id: ids[:grant], created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: causation,
            command_id: command.command_id, principal_hex:, issuer_service_identity_id: ctx.service_identity_id,
            policy_version: POLICY_VERSION, issued_at: iso(now), expires_at: iso(now + IdentityAccess::Domain::BootstrapGrant::LIFETIME_SECONDS)
          )
          consumed = store.consume_nonce(
            id: ids[:consumption], created_at: iso(now), receipt_id: receipt_row["receipt_id"],
            receipt_digest: command.receipt_digest, command_execution_id: ids[:execution],
            consumed_at: iso(now), outcome: "consumed", reason_code: nil
          )
          # The receipt was already consumed by another command: reject, rolling back.
          raise Consumed if consumed == "already_consumed"

          audit_payload = { "branch" => "bootstrap_grant_issuance", "grant_id" => ids[:grant] }
          write_audit(store, ids[:audit], context_org, ctx, causation, command, ids[:grant],
                      to_state: "issued", outcome: "success", reason_code: nil, payload: audit_payload, now:)
          write_event(store, ids, context_org, ctx, causation, command, now, request_sha256, key_digest)
          write_result_success(store, ids, command, ctx, context_org, now, grant_id: ids[:grant], expires_at: now + IdentityAccess::Domain::BootstrapGrant::LIFETIME_SECONDS)
          write_idempotency(store, ids[:idem], principal_hex, command, key_digest, request_sha256, ids[:execution], ids[:result], now)

          Platform::CommandResult.success(
            result_id: ids[:result], command_type: command.command_type, audit_record_id: ids[:audit],
            correlation_id: ctx.correlation_id,
            payload: { grant_id: ids[:grant], state_version: 0,
                       expires_at_utc: (now + IdentityAccess::Domain::BootstrapGrant::LIFETIME_SECONDS).iso8601(6) }
          )
        rescue Consumed
          # Re-run as a rejection in the same transaction is impossible (rows written);
          # the transaction rolls back and the caller submits a fresh receipt.
          raise Platform::InvariantViolation, "receipt nonce consumed concurrently"
        end

        def reject(store:, command:, ctx:, receipt_row:, principal_hex:, context_org:, now:, request_sha256:, key_digest:, reason:, consume_nonce: true)
          execution_id = ctx.generate_id
          audit_id = ctx.generate_id
          result_id = ctx.generate_id
          causation = ctx.correlation_id
          write_execution(store, command, ctx, principal_hex, execution_id, request_sha256, key_digest, now, causation, nil)
          if consume_nonce
            store.consume_nonce(id: ctx.generate_id, created_at: iso(now), receipt_id: receipt_row["receipt_id"],
                                receipt_digest: command.receipt_digest, command_execution_id: execution_id,
                                consumed_at: iso(now), outcome: "rejected", reason_code: reason)
          end
          write_audit(store, audit_id, context_org, ctx, causation, command, receipt_row["receipt_id"],
                      to_state: nil, outcome: "failure", reason_code: reason,
                      payload: { "branch" => "bootstrap_grant_issuance", "rejected" => reason }, now:, entity_type: "identity_receipt")
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          write_result_failure(store, result_id, execution_id, command, ctx, context_org, audit_id, failure, now)
          # idempotency_conflict never writes a new idempotency row (the key exists).
          unless reason == "idempotency_conflict"
            write_idempotency(store, ctx.generate_id, principal_hex, command, key_digest, request_sha256, execution_id, result_id, now)
          end
          Platform::CommandResult.failure(result_id:, command_type: command.command_type, failure:,
                                          audit_record_id: audit_id, correlation_id: ctx.correlation_id)
        end

        def replay(store, existing, command, _request_sha256)
          stored = store.load_command_result(existing["command_result_id"])
          if stored["outcome"] == "success"
            payload = JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym)
            Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type,
                                            payload:, audit_record_id: stored["audit_record_id"],
                                            correlation_id: stored["correlation_id"], replayed: true)
          else
            failure = Platform::Failure.new(
              error_class: stored["error_class"], error_code: stored["error_code"], reason_code: stored["reason_code"],
              severity: stored["severity"], retryable: stored["retryable"] == "t" || stored["retryable"] == true,
              recovery_action: stored["recovery_action"], support_reference: stored["support_reference"]
            )
            Platform::CommandResult.failure(result_id: stored["id"], command_type: command.command_type, failure:,
                                            audit_record_id: stored["audit_record_id"],
                                            correlation_id: stored["correlation_id"], replayed: true)
          end
        end

        # ---- ledger writers ----------------------------------------------------

        def write_execution(store, command, ctx, principal_hex, id, request_sha256, key_digest, now, causation, target_id)
          store.insert_command_execution(
            id:, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: causation,
            command_id: command.command_id, idempotency_key_digest: key_digest, command_type: command.command_type,
            command_schema_version: command.schema_version, service_identity_id: ctx.service_identity_id,
            principal_hex:, target_type: TARGET_TYPE, target_id:, action: ACTION,
            requested_at: iso(command.requested_at_utc), authorization_check_at: iso(now),
            policy_versions: policy_versions_json, canonical_payload: canonical_payload_json(command),
            request_sha256:
          )
        end

        def write_audit(store, id, org, ctx, causation, command, entity_id, to_state:, outcome:, reason_code:, payload:, now:, entity_type: "bootstrap_grant")
          content = Platform::CanonicalJson.digest(payload)
          store.insert_audit(
            id:, occurred_at: iso(now), partition_month: month(now), organization_id: org,
            service_identity_id: ctx.service_identity_id, correlation_id: ctx.correlation_id, causation_id: causation,
            command_id: command.command_id, entity_type:, entity_id:, to_state:, outcome:, reason_code:,
            payload: JSON.generate(payload), content_sha256: content
          )
        end

        def write_event(store, ids, org, ctx, causation, command, now, request_sha256, key_digest)
          envelope = {
            "affected_entity_id" => ids[:grant], "affected_entity_type" => "bootstrap_grant",
            "aggregate_version" => 0, "audit_record_id" => ids[:audit], "causation_id" => causation,
            "command_id" => command.command_id, "correlation_id" => ctx.correlation_id, "event_id" => ids[:event],
            "event_profile" => "created", "event_type" => "BootstrapGrantIssued", "from_state" => nil,
            "idempotency_identity_hash" => hex(key_digest), "input_hash" => hex(request_sha256),
            "occurred_at_utc" => now.iso8601(6), "organization_id" => org, "outcome" => "success",
            "project_id" => nil, "reason_code" => nil, "schema_version" => "1.0",
            "service_identity_id" => ctx.service_identity_id, "to_state" => "issued", "workflow_id" => "WF-001"
          }
          bytes = Platform::CanonicalJson.encode(envelope)
          store.insert_event(
            id: ids[:event], created_at: iso(now), event_type: "BootstrapGrantIssued", occurred_at: iso(now),
            organization_id: org, aggregate_type: "bootstrap_grant", aggregate_id: ids[:grant],
            partition_month: month(now), correlation_id: ctx.correlation_id, causation_id: causation,
            command_id: command.command_id, audit_record_id: ids[:audit],
            event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
          )
        end

        def write_result_success(store, ids, command, ctx, org, now, grant_id:, expires_at:)
          store.insert_command_result(
            id: ids[:result], created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, command_execution_id: ids[:execution], outcome: "success",
            organization_id: org, service_identity_id: ctx.service_identity_id, completed_at: iso(now),
            authorization_check_at: iso(now), target_refs: JSON.generate({ "bootstrap_grant" => grant_id }),
            governing_policy_versions: policy_versions_json, failure: nil,
            authorized_payload: JSON.generate({ "grant_id" => grant_id, "state_version" => 0, "expires_at_utc" => expires_at.iso8601(6) }),
            audit_record_id: ids[:audit]
          )
        end

        def write_result_failure(store, result_id, execution_id, command, ctx, org, audit_id, failure, now)
          store.insert_command_result(
            id: result_id, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, command_execution_id: execution_id, outcome: "failure",
            organization_id: org, service_identity_id: ctx.service_identity_id, completed_at: iso(now),
            authorization_check_at: iso(now), target_refs: JSON.generate({}),
            governing_policy_versions: policy_versions_json, failure:,
            authorized_payload: JSON.generate({}), audit_record_id: audit_id
          )
        end

        def write_idempotency(store, id, principal_hex, command, key_digest, request_sha256, execution_id, result_id, now)
          store.insert_idempotency(
            id:, created_at: iso(now), principal_hex:, command_type: command.command_type, target_type: TARGET_TYPE,
            target_id: nil, key_digest:, request_sha256:, command_execution_id: execution_id,
            command_result_id: result_id, retain_until: iso(now + (30 * 24 * 3600))
          )
        end

        # ---- degenerate / early failures --------------------------------------

        def schema_failure(command, ctx)
          in_memory_failure(command, ctx, "command_schema_unsupported")
        end

        def unresolved_receipt_failure(command, ctx)
          in_memory_failure(command, ctx, "identity_receipt_invalid")
        end

        def in_memory_failure(command, ctx, reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                          failure:, audit_record_id: ctx.generate_id, correlation_id: ctx.correlation_id)
        end

        # ---- helpers -----------------------------------------------------------

        def build_receipt(row)
          IdentityAccess::Domain::IdentityValidationReceipt.new(
            receipt_id: row["receipt_id"], purpose: row["purpose"],
            validated_at: to_time(row["validated_at"]), expires_at: to_time(row["expires_at"]),
            email_verified: truthy(row["email_verified"]),
            issuer_key: row["issuer_key"], schema_version: row["receipt_schema_version"],
            bootstrap_principal_digest: row["principal_hex"], context_org: row["context_org"]
          )
        end

        def to_time(value)
          return value.getutc if value.respond_to?(:getutc)

          Time.parse(value).getutc
        end

        def truthy(value) = value == true || value == "t"

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
        def policy_versions_json = JSON.generate({ "onboarding" => POLICY_VERSION })
        def canonical_payload_json(command) = JSON.generate({ "receipt_digest" => hex(command.receipt_digest) })
        def iso(time) = time.getutc.iso8601(6)
        def month(time) = Date.new(time.year, time.month, 1).iso8601
        def hex(bytes) = bytes.unpack1("H*")

        def request_hash(command:, ctx:, principal_hex:)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "bootstrap_principal" => principal_hex,
            "command_payload" => { "receipt_digest" => hex(command.receipt_digest) },
            "command_schema_version" => command.schema_version, "command_type" => command.command_type,
            "expected_state_version" => nil, "organization_id" => nil,
            "policy_versions" => [POLICY_VERSION], "project_id" => nil,
            "service_identity_id" => ctx.service_identity_id, "target_id" => nil, "target_type" => TARGET_TYPE
          })
        end

        class Consumed < StandardError; end
      end
    end
  end
end
