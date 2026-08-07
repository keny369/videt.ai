# frozen_string_literal: true

require "digest"
require "time"
require "json"

module Workflows
  module Wf001
    module Handlers
      # WF-001 existing-account sign-in branch (WORKFLOW_SPECIFICATIONS.md §
      # existing-account sign-in; APPLICATION_LAYER.md § WF-001). The approved
      # identity service resolves the exact (organization, issuer, subject) Account
      # inside its Organization and, on success, consumes the receipt nonce and
      # creates exactly one active Session emitting one SessionCreated with
      # creation_reason=existing_account_sign_in. It changes no Account or
      # Organization state, selects no Organization implicitly, and a new sign-in
      # never revokes an earlier Session. The organization_id is the real tenant
      # Organization (OD-013's bootstrap substitution does not apply).
      #
      # Failures are the seven exhaustive outward reasons. Every invalid-receipt
      # reason is normalized to authentication_failed outward while the exact
      # internal reason is retained in the restricted audit. The first-match order
      # is: exact replay; receipt validity; Account binding; suspended Account;
      # inactive Organization; authentication assurance; idempotency-envelope
      # conflict (before nonce consumption); then authorization-context init.
      #
      # Thin slice: the authorization context resolves effective Role Assignments
      # (for the admin-role-capable MFA gate and the organization_home /
      # access_unavailable destination) and the single active Access Policy (for
      # policy_unavailable). The full permission-baseline effective-permission
      # engine and authorized-target destination resolution are deferred.
      class SignInExistingAccount
        SUPPORTED_SCHEMA_MAJOR = "1"
        POLICY_VERSION = "onboarding-interim-v1"
        TARGET_TYPE = "session"
        ACTION = "account.sign_in"
        CREATION_REASON = "existing_account_sign_in"
        ADMIN_ROLES = %w[OrganizationAdmin SecurityOperator].freeze
        SESSION_IDLE_SECONDS = 30 * 60
        SESSION_ABSOLUTE_SECONDS = 12 * 60 * 60

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          Platform::UnitOfWork.run do |conn|
            store = IdentityAccess::Infrastructure::TenantSignInStore.new(conn.raw_connection)
            receipt = store.enter_context(receipt_digest: command.receipt_digest,
                                          org: command.organization_id, correlation_id: ctx.correlation_id)
            process(command:, ctx:, store:, receipt:)
          end
        end

        private

        # ---- first-match order --------------------------------------------------

        def process(command:, ctx:, store:, receipt:)
          now = ctx.now_utc.floor(6)
          org = command.organization_id
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          request_sha256 = request_hash(command:, ctx:)

          store.lock_idempotency(org, key_digest)
          existing = store.find_idempotency(org:, command_type: command.command_type,
                                            target_type: TARGET_TYPE, key_digest:)
          return replay(store, existing, command) if existing && existing["request_hex"] == hex(request_sha256)

          conflict = !existing.nil? # exists but a different canonical command
          d = { store:, command:, ctx:, now:, org:, request_sha256:, key_digest: }

          internal = receipt_internal_reason(receipt, now)
          return deny(**d, outward: "authentication_failed", internal:, account_id: nil) if internal

          account = store.resolve_account(issuer_key: receipt["issuer_key"], subject: receipt["issuer_subject"])
          if account.nil? || %w[revoked pending].include?(account["status"])
            reason = account.nil? ? "account_absent" : "account_#{account['status']}"
            return deny(**d, outward: "authentication_failed", internal: reason, account_id: account&.dig("id"))
          end
          return deny(**d, outward: "account_suspended", internal: "account_suspended",
                      account_id: account["id"]) if account["status"] == "suspended"

          org_row = store.organization(org)
          unless org_row && org_row["status"] == "active"
            return deny(**d, outward: "organization_inactive",
                        internal: "organization_#{org_row&.dig('status') || 'absent'}", account_id: account["id"])
          end

          roles = store.effective_roles(account_id: account["id"], now:)
          admin_capable = roles.any? { |r| ADMIN_ROLES.include?(r) }
          if admin_capable && !truthy(receipt["mfa_satisfied"])
            return deny(**d, outward: "identity_assurance_failed", internal: "mfa_required", account_id: account["id"])
          end

          # Only after every earlier check passes, and before receipt consumption.
          return deny(**d, outward: "idempotency_conflict", internal: "idempotency_conflict",
                      account_id: account["id"], existing_conflict: true) if conflict

          policy_version = store.active_access_policy_version(org)
          return deny(**d, outward: "policy_unavailable", internal: "access_policy_unavailable",
                      account_id: account["id"]) if policy_version.nil?

          destination = roles.empty? ? "access_unavailable" : "organization_home"
          succeed(store:, command:, ctx:, now:, org:, account:, receipt:, destination:,
                  authz_version: org_row["authorization_epoch"].to_i, request_sha256:, key_digest:, policy_version:)
        end

        # ---- success ------------------------------------------------------------

        def succeed(store:, command:, ctx:, now:, org:, account:, receipt:, destination:, authz_version:,
                    request_sha256:, key_digest:, policy_version:)
          ids = %i[execution session audit event result consumption idem].to_h { |k| [k, ctx.generate_id] }
          causation = ctx.correlation_id
          idle_exp = now + SESSION_IDLE_SECONDS
          abs_exp = now + SESSION_ABSOLUTE_SECONDS

          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now, causation)
          # Only the digest is stored; `token.raw` leaves through the CommandResult so
          # the transport can set the cookie, and is never persisted or audited.
          token = Platform::SessionToken.mint
          store.insert_session(
            id: ids[:session], created_at: iso(now), correlation_id: ctx.correlation_id, organization_id: org,
            account_id: account["id"], identity_receipt_digest: command.receipt_digest,
            authorization_context_version: authz_version, creation_reason: CREATION_REASON,
            issued_at: iso(now), last_activity_at: iso(now), idle_expires_at: iso(idle_exp),
            absolute_expires_at: iso(abs_exp), token_sha256: token.digest
          )
          consumed = store.consume_nonce(
            id: ids[:consumption], created_at: iso(now), receipt_id: receipt["receipt_id"],
            receipt_digest: command.receipt_digest, command_execution_id: ids[:execution],
            consumed_at: iso(now), outcome: "consumed", reason_code: nil
          )
          raise Consumed if consumed == "already_consumed"

          write_audit(store, ids[:audit], org, ctx, causation, command, ids[:session], entity_type: "session",
                      to_state: "active", outcome: "success", reason_code: nil,
                      payload: success_audit_payload(account, org, receipt, destination, authz_version, ids[:session]), now:)
          write_event(store, ids, org, ctx, causation, command, now, request_sha256, key_digest, account, destination)
          write_result_success(store, ids, command, ctx, org, now, account, destination, idle_exp, abs_exp, policy_version)
          write_idempotency(store, ids[:idem], org, command, key_digest, request_sha256, ids[:execution], ids[:result], now)

          Platform::CommandResult.success(
            result_id: ids[:result], command_type: command.command_type, audit_record_id: ids[:audit],
            correlation_id: ctx.correlation_id,
            payload: success_payload(ids[:session], account, org, destination, now, idle_exp, abs_exp).transform_keys(&:to_sym),
            session_token: token
          )
        rescue Consumed
          raise Platform::InvariantViolation, "receipt nonce consumed concurrently"
        end

        # ---- denial -------------------------------------------------------------

        def deny(store:, command:, ctx:, now:, org:, request_sha256:, key_digest:, outward:, internal:,
                 account_id:, existing_conflict: false)
          execution_id = ctx.generate_id
          audit_id = ctx.generate_id
          result_id = ctx.generate_id
          causation = ctx.correlation_id

          write_execution(store, command, ctx, org, execution_id, request_sha256, key_digest, now, causation)
          write_audit(store, audit_id, org, ctx, causation, command, command.command_id, entity_type: "identity",
                      to_state: nil, outcome: "failure", reason_code: internal,
                      payload: denial_audit_payload(internal, outward, account_id, org), now:)
          failure = Platform::ErrorCatalog.failure(outward, support_reference: ctx.correlation_id)
          write_result_failure(store, result_id, execution_id, command, ctx, org, audit_id, failure, now)
          # An idempotency-envelope conflict already has its stored idempotency row;
          # every other denial records one so exact replay returns the stored failure.
          unless existing_conflict
            write_idempotency(store, ctx.generate_id, org, command, key_digest, request_sha256, execution_id, result_id, now)
          end
          Platform::CommandResult.failure(result_id:, command_type: command.command_type, failure:,
                                          audit_record_id: audit_id, correlation_id: ctx.correlation_id)
        end

        def replay(store, existing, command)
          stored = store.load_command_result(existing["command_result_id"])
          if stored["outcome"] == "success"
            payload = JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym)
            Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type, payload:,
                                            audit_record_id: stored["audit_record_id"],
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

        # ---- ledger writers -----------------------------------------------------

        def write_execution(store, command, ctx, org, id, request_sha256, key_digest, now, causation)
          store.insert_command_execution(
            id:, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: causation,
            command_id: command.command_id, idempotency_key_digest: key_digest, command_type: command.command_type,
            command_schema_version: command.schema_version, service_identity_id: ctx.service_identity_id,
            organization_id: org, target_type: TARGET_TYPE, target_id: nil, action: ACTION,
            requested_at: iso(command.requested_at_utc), authorization_check_at: iso(now),
            policy_versions: policy_versions_json, canonical_payload: canonical_payload_json(command),
            request_sha256:
          )
        end

        def write_audit(store, id, org, ctx, causation, command, entity_id, entity_type:, to_state:, outcome:,
                        reason_code:, payload:, now:)
          store.insert_audit(
            id:, occurred_at: iso(now), partition_month: month(now), organization_id: org,
            service_identity_id: ctx.service_identity_id, correlation_id: ctx.correlation_id, causation_id: causation,
            command_id: command.command_id, entity_type:, entity_id:, to_state:, outcome:, reason_code:,
            payload: JSON.generate(payload), content_sha256: Platform::CanonicalJson.digest(payload)
          )
        end

        def write_event(store, ids, org, ctx, causation, command, now, request_sha256, key_digest, account, destination)
          envelope = {
            "account_id" => account["id"], "affected_entity_id" => ids[:session], "affected_entity_type" => "session",
            "aggregate_version" => 0, "audit_record_id" => ids[:audit], "causation_id" => causation,
            "command_id" => command.command_id, "correlation_id" => ctx.correlation_id,
            "creation_reason" => CREATION_REASON, "destination" => destination, "event_id" => ids[:event],
            "event_profile" => "created", "event_type" => "SessionCreated", "from_state" => nil,
            "idempotency_identity_hash" => hex(key_digest), "input_hash" => hex(request_sha256),
            "occurred_at_utc" => now.iso8601(6), "organization_id" => org, "outcome" => "success",
            "project_id" => nil, "reason_code" => nil, "schema_version" => "1.0",
            "service_identity_id" => ctx.service_identity_id, "to_state" => "active", "workflow_id" => "WF-001"
          }
          bytes = Platform::CanonicalJson.encode(envelope)
          store.insert_event(
            id: ids[:event], created_at: iso(now), event_type: "SessionCreated", occurred_at: iso(now),
            organization_id: org, aggregate_type: "session", aggregate_id: ids[:session], partition_month: month(now),
            correlation_id: ctx.correlation_id, causation_id: causation, command_id: command.command_id,
            audit_record_id: ids[:audit], event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
          )
        end

        def write_result_success(store, ids, command, ctx, org, now, account, destination, idle_exp, abs_exp, policy_version)
          store.insert_command_result(
            id: ids[:result], created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, command_execution_id: ids[:execution], outcome: "success",
            organization_id: org, service_identity_id: ctx.service_identity_id, completed_at: iso(now),
            authorization_check_at: iso(now),
            target_refs: JSON.generate({ "session" => ids[:session], "account" => account["id"] }),
            governing_policy_versions: governing_policy_versions_json(policy_version), failure: nil,
            authorized_payload: JSON.generate(success_payload(ids[:session], account, org, destination, now, idle_exp, abs_exp)),
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

        def write_idempotency(store, id, org, command, key_digest, request_sha256, execution_id, result_id, now)
          store.insert_idempotency(
            id:, created_at: iso(now), organization_id: org, command_type: command.command_type,
            target_type: TARGET_TYPE, target_id: nil, key_digest:, request_sha256:,
            command_execution_id: execution_id, command_result_id: result_id, retain_until: iso(now + (30 * 24 * 3600))
          )
        end

        # ---- degenerate / early failures ---------------------------------------

        def schema_failure(command, ctx)
          failure = Platform::ErrorCatalog.failure("command_schema_unsupported", support_reference: ctx.correlation_id)
          Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                          failure:, audit_record_id: ctx.generate_id, correlation_id: ctx.correlation_id)
        end

        # ---- payloads -----------------------------------------------------------

        def success_payload(session_id, account, org, destination, now, idle_exp, abs_exp)
          {
            "session_id" => session_id, "account_id" => account["id"], "organization_id" => org,
            "destination" => destination, "creation_reason" => CREATION_REASON,
            "issued_at_utc" => now.iso8601(6), "idle_expires_at_utc" => idle_exp.iso8601(6),
            "absolute_expires_at_utc" => abs_exp.iso8601(6)
          }
        end

        def success_audit_payload(account, org, receipt, destination, authz_version, session_id)
          {
            "branch" => "existing_account_sign_in", "outcome" => "success", "session_id" => session_id,
            "account_id" => account["id"], "organization_id" => org, "destination" => destination,
            "authorization_context_version" => authz_version, "account_state" => account["status"],
            "assurance_satisfied" => truthy(receipt["mfa_satisfied"]), "subject_digest" => receipt["principal_hex"],
            "receipt_id" => receipt["receipt_id"]
          }
        end

        def denial_audit_payload(internal, outward, account_id, org)
          {
            "branch" => "existing_account_sign_in", "outcome" => "failure", "internal_reason" => internal,
            "outward_reason" => outward, "account_id" => account_id, "organization_id" => org
          }
        end

        # ---- helpers ------------------------------------------------------------

        def receipt_internal_reason(receipt, now)
          return "identity_receipt_invalid" unless truthy(receipt["receipt_found"])
          return "identity_receipt_purpose_mismatch" unless receipt["purpose"] == CREATION_REASON
          return "identity_email_unverified" unless truthy(receipt["email_verified"])
          return "identity_receipt_expired" if now >= to_time(receipt["expires_at"])

          nil
        end

        def request_hash(command:, ctx:)
          Platform::CanonicalJson.digest({
            "action" => ACTION,
            "command_payload" => { "organization_id" => command.organization_id, "receipt_digest" => hex(command.receipt_digest) },
            "command_schema_version" => command.schema_version, "command_type" => command.command_type,
            "expected_state_version" => nil, "organization_id" => command.organization_id,
            "policy_versions" => [POLICY_VERSION], "project_id" => nil,
            "service_identity_id" => ctx.service_identity_id, "target_id" => nil, "target_type" => TARGET_TYPE
          })
        end

        def to_time(value)
          return value.getutc if value.respond_to?(:getutc)

          Time.parse(value).getutc
        end

        def truthy(value) = value == true || value == "t"
        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
        def policy_versions_json = JSON.generate({ "onboarding" => POLICY_VERSION })
        def governing_policy_versions_json(access_version) = JSON.generate({ "onboarding" => POLICY_VERSION, "access" => access_version })
        def canonical_payload_json(command) = JSON.generate({ "organization_id" => command.organization_id, "receipt_digest" => hex(command.receipt_digest) })
        def iso(time) = time.getutc.iso8601(6)
        def month(time) = Date.new(time.year, time.month, 1).iso8601
        def hex(bytes) = bytes.unpack1("H*")

        class Consumed < StandardError; end
      end
    end
  end
end
