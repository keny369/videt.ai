# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf013
    module Handlers
      # WF-013 ReactivateOrganization under the ratified `reactivation-proof-v1`
      # decision (WORKFLOW_SPECIFICATIONS.md :270-289).
      #
      # NOT Session-authenticated, and that is the point. Suspension revoked every
      # human Session, so there is none left to present; ":278 Session: the command
      # creates no Session. Reactivation is not authentication." Authority is proved
      # by a fresh purpose-bound Identity Validation Receipt that carries
      # `mfa_satisfied=true` and binds exactly one target Organization, and the
      # acting Account is resolved from that receipt's issuer/subject INSIDE the
      # bound Organization. It is the express exemption to ":931 Organization is
      # active", which is why it is the one command a suspended Organization admits.
      #
      # First-match order, exactly as ratified: schema; the Organization is
      # suspended; exact replay; receipt validity (purpose, MFA, Organization
      # binding, freshness, nonce); the actor's Account and its
      # `organization.reactivate` authority; the reactivation predicates
      # `access_policy_unavailable` then `organization_admin_unavailable`; expected
      # state version; expected authorization epoch; then the guarded transition.
      #
      # It restores the Organization's ability to issue NEW authority. It does not
      # revive anything suspension invalidated: a revoked Session is terminal (016
      # STATE_MODEL.md :96), and the contract nowhere restores one.
      class ReactivateOrganization
        include InvitationLedger

        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "organization"
        ACTION = "organization.reactivate"
        CAPABILITY = "organization.reactivate"
        RECEIPT_PURPOSE = "organization_reactivation"
        ADMIN_ROLE = "OrganizationAdmin"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          key_digest = Digest::SHA256.digest(command.idempotency_key)

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            store = IdentityAccess::Infrastructure::OrganizationLifecycleStore.new(pg)
            org = command.organization_id

            # The receipt names its Organization; entering that context is data
            # scoping, and the receipt is read in the same call.
            receipt = store.enter_context(receipt_digest: command.receipt_digest, org:,
                                          correlation_id: ctx.correlation_id)
            store.lock_organization(org)

            request_sha256 = request_hash(command, ctx)
            existing = store.find_idempotency(org:, command_type: command.command_type,
                                              target_type: TARGET_TYPE, target_id: org, key_digest:)
            if existing
              return replay(store, command, existing) if existing["request_hex"] == hex(request_sha256)

              return in_memory_failure(command, ctx, "idempotency_conflict")
            end

            row = store.read_organization(org)
            unless row && row["status"] == "suspended"
              return in_memory_failure(command, ctx, "organization_state_invalid")
            end

            invalid = receipt_invalid_reason(receipt, now)
            return in_memory_failure(command, ctx, invalid) if invalid

            actor = store.account_by_identity(issuer_key: receipt["issuer_key"],
                                              subject: receipt["issuer_subject"])
            return in_memory_failure(command, ctx, "organization_admin_unavailable") if actor.nil? || actor["status"] != "active"

            process(store:, command:, ctx:, org:, now:, row:, receipt:, actor:, key_digest:, request_sha256:)
          end
        end

        private

        # ":274 the receipt … MUST carry `mfa_satisfied=true`"; ":276 freshness …
        # Acceptance MUST commit strictly before expiry; at equality expiry wins."
        def receipt_invalid_reason(receipt, now)
          return "identity_receipt_invalid" unless truthy(receipt["receipt_found"])
          return "identity_receipt_purpose_mismatch" unless receipt["purpose"] == RECEIPT_PURPOSE
          return "identity_assurance_failed" unless truthy(receipt["mfa_satisfied"]) && receipt["assurance_version"]
          return "identity_receipt_expired" if now >= to_time(receipt["expires_at"])

          nil
        end

        def process(store:, command:, ctx:, org:, now:, row:, receipt:, actor:, key_digest:, request_sha256:)
          assignments = store.effective_role_assignments(account_id: actor["id"], now:)
          roles = assignments.map { |a| a["canonical_role"] }
          unless roles.include?(ADMIN_ROLE) && Platform::PermissionBaseline.permits?(CAPABILITY, roles)
            return in_memory_failure(command, ctx, "organization_admin_unavailable")
          end

          # The ratified first-match predicate order for a failed reactivation.
          policy_id = store.active_access_policy(org)
          return in_memory_failure(command, ctx, "access_policy_unavailable") if policy_id.nil?

          unless command.expected_state_version == row["state_version"].to_i
            return in_memory_failure(command, ctx, "stale_state_version")
          end
          unless command.expected_authorization_epoch == row["authorization_epoch"].to_i
            return in_memory_failure(command, ctx, "stale_authorization_epoch")
          end

          commit(store:, command:, ctx:, org:, now:, row:, receipt:, actor:, assignments:, policy_id:,
                 key_digest:, request_sha256:)
        end

        def commit(store:, command:, ctx:, org:, now:, row:, receipt:, actor:, assignments:, policy_id:,
                   key_digest:, request_sha256:)
          ids = %i[execution audit event result decision idem consumption].to_h { |k| [k, ctx.generate_id] }
          new_version = row["state_version"].to_i + 1
          new_epoch = row["authorization_epoch"].to_i + 1
          principal = Struct.new(:account_id, :organization_id, :authorization_epoch)
                            .new(actor["id"], org, row["authorization_epoch"].to_i)

          write_execution(store, command, ctx, org, ids[:execution], org, principal, request_sha256,
                          key_digest, now, ACTION)
          write_authorization_decision(
            IdentityAccess::Infrastructure::AuthorizationStore.new(store_connection(store)), ids[:decision],
            ctx, command, principal, allow_decision(row, policy_id, assignments), now, org, ACTION
          )

          changed = store.reactivate(org, row["state_version"].to_i, row["authorization_epoch"].to_i, now)
          raise LostRace if changed.to_i.zero?

          # ":277 the receipt is nonce-consumed by the reactivation command alone."
          consumed = store.consume_nonce(id: ids[:consumption], created_at: iso(now),
                                         receipt_id: receipt["receipt_id"], receipt_digest: command.receipt_digest,
                                         command_execution_id: ids[:execution], consumed_at: iso(now),
                                         outcome: "consumed", reason_code: nil)
          raise Consumed if consumed == "already_consumed"

          payload = { "organization_id" => org, "state" => "active", "state_version" => new_version,
                      "authorization_epoch" => new_epoch }
          write_audit(store, ids[:audit], org, ctx, command, org, principal, to_state: "active",
                      outcome: "success", reason_code: nil,
                      payload: payload.merge("assurance_version" => receipt["assurance_version"],
                                             "receipt_digest" => hex(command.receipt_digest)), now:)
          write_event(store, ids, org, ctx, command, principal, now, new_version, org, request_sha256,
                      key_digest, principal.account_id, "OrganizationReactivated", "state_transition",
                      { "from_state" => "suspended", "to_state" => "active", "organization_epoch" => new_epoch })
          write_result_success(store, ids, command, ctx, org, principal, now, payload, org)
          write_idempotency(store, ids[:idem], org, command, org, key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        rescue Consumed
          raise Platform::InvariantViolation, "reactivation receipt nonce consumed concurrently"
        rescue LostRace
          raise Platform::InvariantViolation, "organization transitioned concurrently"
        end

        def allow_decision(row, policy_id, assignments)
          IdentityAccess::Authorization::Decision.new(
            allowed: true, reason: "authorized", organization_epoch: row["authorization_epoch"].to_i,
            policy_snapshot_id: policy_id,
            role_assignment_versions: assignments.map { |a| { "id" => a["id"], "state_version" => a["state_version"].to_i } }
          )
        end

        def replay(store, command, existing)
          stored = store.load_command_result(existing["command_result_id"])
          payload = JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym)
          Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type, payload:,
                                          audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end

        def store_connection(store) = store.instance_variable_get(:@pg)

        def request_hash(command, ctx)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version,
            "organization_id" => command.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => command.organization_id, "project_id" => nil,
            "expected_version" => command.expected_state_version,
            "expected_authorization_epoch" => command.expected_authorization_epoch,
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => { "receipt_digest" => hex(command.receipt_digest) }
          })
        end

        def canonical_payload_json(command)
          JSON.generate({ "receipt_digest" => hex(command.receipt_digest) })
        end

        def truthy(value) = value == true || value == "t"
        def to_time(value) = value.respond_to?(:getutc) ? value.getutc : Time.parse(value).getutc

        class Consumed < StandardError; end
        class LostRace < StandardError; end
      end
    end
  end
end
