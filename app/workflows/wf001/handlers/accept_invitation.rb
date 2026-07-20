# frozen_string_literal: true

require "digest"
require "time"
require "json"

module Workflows
  module Wf001
    module Handlers
      # WF-001 invitation-acceptance branch (WORKFLOW_SPECIFICATIONS.md § invitation
      # acceptance; APPLICATION_LAYER.md § WF-001). One atomic multi-root commit:
      # resolve the opaque reference to its Organization, enter that context, and —
      # on success — create-or-bind the Account, create-or-reuse the exact offered
      # Role Assignment, transition the Invitation active->accepted, consume the
      # receipt nonce, and create a Session, emitting the causal event set. It never
      # creates or changes an Organization or Project.
      #
      # First-match order (:631): exact replay; receipt validity; Invitation
      # state/version; receipt-to-target binding; offered tuple; Account uniqueness /
      # ineligibility; idempotency-envelope conflict; then commit. An unresolved,
      # terminal, or expired reference is the single non-disclosing invitation_not_active
      # (the resolver's fixed projection). A wrong-identity attempt leaves the
      # Invitation active, binds the nonce to the denied command, emits no Invitation
      # event, and audits without revealing the intended email or identity.
      #
      # Event orders (:642): new Account — AccountProvisionRequested, AccountActivated,
      # RoleGranted, InvitationAccepted, SessionCreated; existing Account — RoleGranted
      # only when a new Assignment is created, then InvitationAccepted, SessionCreated.
      # Exact replay emits none.
      class AcceptInvitation
        SUPPORTED_SCHEMA_MAJOR = "1"
        POLICY_VERSION = "onboarding-interim-v1"
        TARGET_TYPE = "invitation"
        ACTION = "invitation.accept"
        CREATION_REASON = "invitation_acceptance"
        SESSION_IDLE_SECONDS = 30 * 60
        SESSION_ABSOLUTE_SECONDS = 12 * 60 * 60

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          reference_digest = Digest::SHA256.digest(command.invitation_reference)
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          request_sha256 = request_hash(command:, ctx:, reference_digest:)

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            store = IdentityAccess::Infrastructure::InvitationStore.new(pg)

            # Restricted exact-replay / idempotency recognition BEFORE ordinary
            # resolution, so a prior command (success or failure) replays through the
            # existing command/result ledger even when the non-disclosing resolver
            # (correctly) refuses the now-terminal Invitation.
            replayed = try_exact_replay(store, pg, command, ctx, reference_digest, key_digest, request_sha256)
            return replayed if replayed

            binding = IdentityAccess::Infrastructure::InvitationResolver.new(pg).resolve(reference_digest:, now:)
            # Unresolved / terminal / expired reference: the single non-disclosing outcome.
            return invitation_not_active_in_memory(command, ctx) if binding.nil?

            receipt = store.enter_context(receipt_digest: command.receipt_digest,
                                          org: binding[:organization_id], correlation_id: ctx.correlation_id)
            process(command:, ctx:, store:, receipt:, org: binding[:organization_id],
                    invitation_id: binding[:invitation_id], now:, request_sha256:, key_digest:)
          end
        end

        # Restricted exact replay through the existing ledger (WORKFLOW_SPECIFICATIONS.md
        # :248; APPLICATION_LAYER.md § replay). Bootstraps context from the any-state
        # registry (never the public resolver), then reads the restricted
        # idempotency/command-result ledger IN-CONTEXT: exact command-digest equality
        # replays the stored result; a reused key with changed input conflicts. A
        # replayed success is reauthorized against current state. No events, no domain
        # writes. Returns a CommandResult, or nil when this is not a replay.
        def try_exact_replay(store, pg, command, ctx, reference_digest, key_digest, request_sha256)
          org_binding = IdentityAccess::Infrastructure::InvitationResolver.new(pg).resolve_org(reference_digest:)
          return nil if org_binding.nil?

          org = org_binding[:organization_id]
          store.enter_context(receipt_digest: command.receipt_digest, org:, correlation_id: ctx.correlation_id)
          existing = store.find_idempotency(org:, command_type: command.command_type, target_type: TARGET_TYPE,
                                            target_id: org_binding[:invitation_id], key_digest:)
          return nil if existing.nil?

          return in_memory_failure(command, ctx, "idempotency_conflict") unless existing["request_hex"] == hex(request_sha256)

          stored = store.load_command_result(existing["command_result_id"])
          if stored["outcome"] == "success"
            account = store.account_by_id(JSON.parse(stored["authorized_payload"])["account_id"])
            return in_memory_failure(command, ctx, "reauthorization_denied") if account.nil? || account["status"] != "active"
          end
          rebuild_stored_result(stored, command)
        end

        private

        # ---- first-match order --------------------------------------------------

        def process(command:, ctx:, store:, receipt:, org:, invitation_id:, now:, request_sha256:, key_digest:)
          store.lock_invitation(invitation_id)
          d = { store:, command:, ctx:, now:, org:, invitation_id:, request_sha256:, key_digest: }

          internal = receipt_invalid_reason(receipt, now)
          return deny(**d, outward: internal, internal:, account_id: nil) if internal

          inv = store.read_invitation(invitation_id)
          # Terminal by the time we hold the lock (a concurrent acceptance won): the
          # non-disclosing outcome, with no ledger writes — the winner already recorded it.
          return invitation_not_active_in_memory(command, ctx) unless inv && inv["state"] == "active"

          return wrong_identity(**d, receipt:) unless target_matches?(receipt, inv)

          unless tuple_matches?(command, inv)
            return deny(**d, outward: "invitation_role_scope_changed", internal: "invitation_role_scope_changed", account_id: nil)
          end

          account = store.resolve_account(issuer_key: receipt["issuer_key"], subject: receipt["issuer_subject"])
          if command.supplied_account_id
            supplied = store.account_by_id(command.supplied_account_id)
            if supplied.nil? || account.nil? || supplied["id"] != account["id"]
              return deny(**d, outward: "account_identity_conflict", internal: "account_identity_conflict",
                          account_id: account&.dig("id"))
            end
          end
          if account && %w[suspended revoked].include?(account["status"])
            return deny(**d, outward: "invitation_account_ineligible", internal: "account_#{account['status']}",
                        account_id: account["id"])
          end

          succeed(**d, receipt:, inv:, account:)
        end

        # ---- success ------------------------------------------------------------

        def succeed(store:, command:, ctx:, now:, org:, invitation_id:, request_sha256:, key_digest:, receipt:, inv:, account:)
          ids = %i[execution account assignment session audit result consumption idem].to_h { |k| [k, ctx.generate_id] }
          causation = ctx.correlation_id
          idle_exp = now + SESSION_IDLE_SECONDS
          abs_exp = now + SESSION_ABSOLUTE_SECONDS
          new_account = account.nil?
          account_id = new_account ? ids[:account] : account["id"]
          events = []

          write_execution(store, command, ctx, org, ids[:execution], invitation_id, request_sha256, key_digest, now, causation)

          if new_account
            store.insert_account_pending(
              id: account_id, created_at: iso(now), correlation_id: ctx.correlation_id, organization_id: org,
              issuer_key: receipt["issuer_key"], subject: receipt["issuer_subject"],
              normalized_email: receipt["normalized_email"], normalized_email_sha256: unhex(receipt["email_hex"]),
              display_name: receipt["display_name"], identity_receipt_digest: command.receipt_digest
            )
            store.activate_account(account_id, now)
            events << event_spec("AccountProvisionRequested", "created", "account", account_id, 0, nil, "pending")
            events << event_spec("AccountActivated", "state_transition", "account", account_id, 1, "pending", "active")
          end

          scope_bytes = inv["scope_hex"] ? unhex(inv["scope_hex"]) : nil
          existing_assignment = store.find_effective_assignment(
            account_id:, canonical_role: inv["canonical_role"], permission_mode: inv["permission_mode"],
            persona: inv["persona"], scope_hex: inv["scope_hex"], now:
          )
          new_assignment = existing_assignment.nil?
          assignment_id = new_assignment ? ids[:assignment] : existing_assignment
          if new_assignment
            store.insert_role_assignment(
              id: assignment_id, created_at: iso(now), correlation_id: ctx.correlation_id, organization_id: org,
              account_id:, canonical_role: inv["canonical_role"], permission_mode: inv["permission_mode"],
              persona: inv["persona"], scope_sha256: scope_bytes, effective_at: iso(now)
            )
            events << event_spec("RoleGranted", "created", "role_assignment", assignment_id, 0, nil, "active")
          end

          changed = store.accept_invitation(invitation_id, inv["state_version"].to_i, assignment_id, now)
          raise LostRace if changed.to_i.zero?

          store.update_registry_accepted(invitation_id, now)
          events << event_spec("InvitationAccepted", "state_transition", "invitation", invitation_id,
                               inv["state_version"].to_i + 1, "active", "accepted")

          consumed = store.consume_nonce(
            id: ids[:consumption], created_at: iso(now), receipt_id: receipt["receipt_id"],
            receipt_digest: command.receipt_digest, command_execution_id: ids[:execution],
            consumed_at: iso(now), outcome: "consumed", reason_code: nil
          )
          raise Consumed if consumed == "already_consumed"

          epoch = (store.organization_epoch(org) || 0).to_i
          store.insert_session(
            id: ids[:session], created_at: iso(now), correlation_id: ctx.correlation_id, organization_id: org,
            account_id:, identity_receipt_digest: command.receipt_digest, authorization_context_version: epoch,
            creation_reason: CREATION_REASON, issued_at: iso(now), last_activity_at: iso(now),
            idle_expires_at: iso(idle_exp), absolute_expires_at: iso(abs_exp)
          )
          events << event_spec("SessionCreated", "created", "session", ids[:session], 0, nil, "active")

          payload = success_payload(account_id, assignment_id, invitation_id, ids[:session], org)
          write_audit(store, ids[:audit], org, ctx, causation, command, ids[:session], entity_type: "session",
                      to_state: "active", outcome: "success", reason_code: nil,
                      payload: success_audit_payload(payload, new_account, new_assignment), now:)
          write_events(store, events, org, ctx, causation, command, now, ids[:audit], account_id, invitation_id, request_sha256, key_digest)
          write_result_success(store, ids, command, ctx, org, now, payload)
          write_idempotency(store, ids[:idem], org, command, invitation_id, key_digest, request_sha256, ids[:execution], ids[:result], now)

          Platform::CommandResult.success(
            result_id: ids[:result], command_type: command.command_type, audit_record_id: ids[:audit],
            correlation_id: ctx.correlation_id, payload: payload.transform_keys(&:to_sym)
          )
        rescue Consumed
          raise Platform::InvariantViolation, "receipt nonce consumed concurrently"
        rescue LostRace
          raise Platform::InvariantViolation, "invitation transitioned concurrently"
        end

        # ---- denials ------------------------------------------------------------

        # A still-active-Invitation denial: records the command outcome so an exact
        # replay (recognized upstream) returns the same stored failure.
        def deny(store:, command:, ctx:, now:, org:, invitation_id:, request_sha256:, key_digest:, outward:, internal:, account_id:)
          execution_id = ctx.generate_id
          audit_id = ctx.generate_id
          result_id = ctx.generate_id
          causation = ctx.correlation_id

          write_execution(store, command, ctx, org, execution_id, invitation_id, request_sha256, key_digest, now, causation)
          write_audit(store, audit_id, org, ctx, causation, command, invitation_id, entity_type: "invitation",
                      to_state: nil, outcome: "failure", reason_code: internal,
                      payload: denial_audit_payload(internal, outward, account_id, invitation_id, org), now:)
          failure = Platform::ErrorCatalog.failure(outward, support_reference: ctx.correlation_id)
          write_result_failure(store, result_id, execution_id, command, ctx, org, audit_id, failure, now)
          write_idempotency(store, ctx.generate_id, org, command, invitation_id, key_digest, request_sha256, execution_id, result_id, now)
          Platform::CommandResult.failure(result_id:, command_type: command.command_type, failure:,
                                          audit_record_id: audit_id, correlation_id: ctx.correlation_id)
        end

        # A valid receipt whose target does not match: the Invitation stays active,
        # the nonce binds to this denied command, no Invitation event is emitted, and
        # the audit reveals neither the intended email nor identity (:248).
        def wrong_identity(store:, command:, ctx:, now:, org:, invitation_id:, request_sha256:, key_digest:, receipt:)
          execution_id = ctx.generate_id
          audit_id = ctx.generate_id
          result_id = ctx.generate_id
          causation = ctx.correlation_id

          write_execution(store, command, ctx, org, execution_id, invitation_id, request_sha256, key_digest, now, causation)
          store.consume_nonce(id: ctx.generate_id, created_at: iso(now), receipt_id: receipt["receipt_id"],
                              receipt_digest: command.receipt_digest, command_execution_id: execution_id,
                              consumed_at: iso(now), outcome: "rejected", reason_code: "invitation_target_mismatch")
          write_audit(store, audit_id, org, ctx, causation, command, invitation_id, entity_type: "invitation",
                      to_state: nil, outcome: "failure", reason_code: "invitation_target_mismatch",
                      payload: { "branch" => "invitation_acceptance", "outcome" => "failure",
                                 "internal_reason" => "invitation_target_mismatch",
                                 "outward_reason" => "invitation_target_mismatch",
                                 "invitation_id" => invitation_id, "organization_id" => org }, now:)
          failure = Platform::ErrorCatalog.failure("invitation_target_mismatch", support_reference: ctx.correlation_id)
          write_result_failure(store, result_id, execution_id, command, ctx, org, audit_id, failure, now)
          write_idempotency(store, ctx.generate_id, org, command, invitation_id, key_digest, request_sha256, execution_id, result_id, now)
          Platform::CommandResult.failure(result_id:, command_type: command.command_type, failure:,
                                          audit_record_id: audit_id, correlation_id: ctx.correlation_id)
        end

        # Rebuild a CommandResult from a stored command_results row (replayed: true) —
        # the original success payload or the original failure.
        def rebuild_stored_result(stored, command)
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

        # ---- writers ------------------------------------------------------------

        def write_execution(store, command, ctx, org, id, invitation_id, request_sha256, key_digest, now, causation)
          store.insert_command_execution(
            id:, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: causation,
            command_id: command.command_id, idempotency_key_digest: key_digest, command_type: command.command_type,
            command_schema_version: command.schema_version, service_identity_id: ctx.service_identity_id,
            organization_id: org, target_type: TARGET_TYPE, target_id: invitation_id, action: ACTION,
            requested_at: iso(command.requested_at_utc), authorization_check_at: iso(now),
            policy_versions: policy_versions_json, canonical_payload: canonical_payload_json(command), request_sha256:
          )
        end

        def write_audit(store, id, org, ctx, causation, command, entity_id, entity_type:, to_state:, outcome:, reason_code:, payload:, now:)
          store.insert_audit(
            id:, occurred_at: iso(now), partition_month: month(now), organization_id: org,
            service_identity_id: ctx.service_identity_id, correlation_id: ctx.correlation_id, causation_id: causation,
            command_id: command.command_id, entity_type:, entity_id:, to_state:, outcome:, reason_code:,
            payload: JSON.generate(payload), content_sha256: Platform::CanonicalJson.digest(payload)
          )
        end

        def write_events(store, events, org, ctx, causation, command, now, audit_id, account_id, invitation_id, request_sha256, key_digest)
          events.each_with_index do |e, index|
            event_id = ctx.generate_id
            # Same logical occurred_at (fixed commit instant); created_at carries the
            # causal index so the emitted order is deterministically recoverable.
            created = now + (index * 0.000001)
            envelope = {
              "account_id" => account_id, "affected_entity_id" => e[:aggregate_id],
              "affected_entity_type" => e[:aggregate_type], "aggregate_version" => e[:aggregate_version],
              "audit_record_id" => audit_id, "causation_id" => causation, "command_id" => command.command_id,
              "correlation_id" => ctx.correlation_id, "event_id" => event_id, "event_profile" => e[:profile],
              "event_type" => e[:type], "from_state" => e[:from_state], "idempotency_identity_hash" => hex(key_digest),
              "input_hash" => hex(request_sha256), "invitation_id" => invitation_id, "occurred_at_utc" => now.iso8601(6),
              "organization_id" => org, "outcome" => "success", "project_id" => nil, "reason_code" => nil,
              "schema_version" => "1.0", "service_identity_id" => ctx.service_identity_id, "to_state" => e[:to_state],
              "workflow_id" => "WF-001"
            }
            bytes = Platform::CanonicalJson.encode(envelope)
            store.insert_event(
              id: event_id, created_at: iso(created), event_type: e[:type], event_profile: e[:profile], occurred_at: iso(now),
              organization_id: org, aggregate_type: e[:aggregate_type], aggregate_id: e[:aggregate_id],
              aggregate_version: e[:aggregate_version], partition_month: month(now), correlation_id: ctx.correlation_id,
              causation_id: causation, command_id: command.command_id, audit_record_id: audit_id,
              event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
            )
          end
        end

        def write_result_success(store, ids, command, ctx, org, now, payload)
          store.insert_command_result(
            id: ids[:result], created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, command_execution_id: ids[:execution], outcome: "success",
            organization_id: org, service_identity_id: ctx.service_identity_id, completed_at: iso(now),
            authorization_check_at: iso(now),
            target_refs: JSON.generate({ "account" => payload["account_id"], "role_assignment" => payload["role_assignment_id"],
                                         "invitation" => payload["invitation_id"], "session" => payload["session_id"] }),
            governing_policy_versions: policy_versions_json, failure: nil,
            authorized_payload: JSON.generate(payload), audit_record_id: ids[:audit]
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

        def write_idempotency(store, id, org, command, invitation_id, key_digest, request_sha256, execution_id, result_id, now)
          store.insert_idempotency(
            id:, created_at: iso(now), organization_id: org, command_type: command.command_type,
            target_type: TARGET_TYPE, target_id: invitation_id, key_digest:, request_sha256:,
            command_execution_id: execution_id, command_result_id: result_id, retain_until: iso(now + (30 * 24 * 3600))
          )
        end

        # ---- degenerate ---------------------------------------------------------

        def schema_failure(command, ctx)
          in_memory_failure(command, ctx, "command_schema_unsupported")
        end

        def invitation_not_active_in_memory(command, ctx)
          in_memory_failure(command, ctx, "invitation_not_active")
        end

        def in_memory_failure(command, ctx, reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                          failure:, audit_record_id: ctx.generate_id, correlation_id: ctx.correlation_id)
        end

        # ---- payloads -----------------------------------------------------------

        def success_payload(account_id, assignment_id, invitation_id, session_id, org)
          { "account_id" => account_id, "role_assignment_id" => assignment_id, "invitation_id" => invitation_id,
            "session_id" => session_id, "organization_id" => org }
        end

        def success_audit_payload(payload, new_account, new_assignment)
          payload.merge("branch" => "invitation_acceptance", "outcome" => "success",
                        "account_created" => new_account, "assignment_created" => new_assignment)
        end

        def denial_audit_payload(internal, outward, account_id, invitation_id, org)
          { "branch" => "invitation_acceptance", "outcome" => "failure", "internal_reason" => internal,
            "outward_reason" => outward, "account_id" => account_id, "invitation_id" => invitation_id,
            "organization_id" => org }
        end

        # ---- helpers ------------------------------------------------------------

        def event_spec(type, profile, aggregate_type, aggregate_id, aggregate_version, from_state, to_state)
          { type:, profile:, aggregate_type:, aggregate_id:, aggregate_version:, from_state:, to_state: }
        end

        def receipt_invalid_reason(receipt, now)
          return "identity_receipt_invalid" unless truthy(receipt["receipt_found"])
          return "identity_receipt_purpose_mismatch" unless receipt["purpose"] == "invitation_response"
          return "identity_email_unverified" unless truthy(receipt["email_verified"])
          return "identity_receipt_expired" if now >= to_time(receipt["expires_at"])

          nil
        end

        def target_matches?(receipt, inv)
          return false unless receipt["email_hex"] == inv["target_email_hex"]
          return true if inv["target_identity_issuer_key"].nil?

          receipt["issuer_key"] == inv["target_identity_issuer_key"] &&
            receipt["issuer_subject"] == inv["target_identity_subject"]
        end

        def tuple_matches?(command, inv)
          command.accepted_canonical_role == inv["canonical_role"] &&
            command.accepted_permission_mode == inv["permission_mode"] &&
            norm(command.accepted_persona) == norm(inv["persona"]) &&
            accepted_scope_hex(command) == inv["scope_hex"]
        end

        def accepted_scope_hex(command)
          command.accepted_scope_sha256 && hex(command.accepted_scope_sha256)
        end

        # Computed from the command alone (Organization and Invitation are implied by
        # the opaque-reference digest), so it is the canonical command digest both
        # before resolution (restricted replay) and after (in-context idempotency).
        def request_hash(command:, ctx:, reference_digest:)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version,
            "target_type" => TARGET_TYPE, "policy_versions" => [POLICY_VERSION],
            "service_identity_id" => ctx.service_identity_id, "project_id" => nil,
            "command_payload" => {
              "invitation_reference_sha256" => hex(reference_digest), "receipt_digest" => hex(command.receipt_digest),
              "accepted_canonical_role" => command.accepted_canonical_role,
              "accepted_permission_mode" => command.accepted_permission_mode,
              "accepted_persona" => command.accepted_persona,
              "accepted_scope_sha256" => accepted_scope_hex(command),
              "supplied_account_id" => command.supplied_account_id
            }
          })
        end

        def to_time(value)
          return value.getutc if value.respond_to?(:getutc)

          Time.parse(value).getutc
        end

        def norm(value) = (value.nil? || value == "") ? nil : value
        def truthy(value) = value == true || value == "t"
        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
        def policy_versions_json = JSON.generate({ "onboarding" => POLICY_VERSION })
        def canonical_payload_json(command) = JSON.generate({ "receipt_digest" => hex(command.receipt_digest) })
        def iso(time) = time.getutc.iso8601(6)
        def month(time) = Date.new(time.year, time.month, 1).iso8601
        def hex(bytes) = bytes.unpack1("H*")
        def unhex(hex_string) = [hex_string].pack("H*")

        class Consumed < StandardError; end
        class LostRace < StandardError; end
      end
    end
  end
end
