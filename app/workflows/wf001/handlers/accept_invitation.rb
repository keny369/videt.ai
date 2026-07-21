# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf001
    module Handlers
      # WF-001 invitation-acceptance branch (WORKFLOW_SPECIFICATIONS.md § invitation
      # acceptance; APPLICATION_LAYER.md § WF-001). One atomic multi-root commit:
      # resolve the opaque reference to its Organization, enter that context, and — on
      # success — create-or-bind the Account, create-or-reuse the exact offered Role
      # Assignment, transition the Invitation active->accepted, consume the receipt
      # nonce, and create a Session, emitting the causal event set. It never creates or
      # changes an Organization or Project.
      #
      # First-match order (:631): exact replay; receipt validity; Invitation
      # state/version; receipt-to-target binding; offered tuple; Account uniqueness /
      # ineligibility; then commit. Event orders (:642): new Account —
      # AccountProvisionRequested, AccountActivated, RoleGranted, InvitationAccepted,
      # SessionCreated; existing Account — RoleGranted only when a new Assignment is
      # created, then InvitationAccepted, SessionCreated. Exact replay emits none.
      #
      # Generic terminal-command plumbing (context, replay, ledger writers, denials,
      # request digest) lives in InvitationTerminalSupport; only acceptance policy is here.
      class AcceptInvitation
        include Workflows::Wf001::InvitationTerminalSupport

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

            replayed = try_exact_replay(store, pg, command, ctx, reference_digest, key_digest, request_sha256)
            return replayed if replayed

            binding = IdentityAccess::Infrastructure::InvitationResolver.new(pg).resolve(reference_digest:, now:)
            return invitation_not_active_in_memory(command, ctx) if binding.nil?

            receipt = store.enter_context(receipt_digest: command.receipt_digest,
                                          org: binding[:organization_id], correlation_id: ctx.correlation_id)
            process(command:, ctx:, store:, receipt:, org: binding[:organization_id],
                    invitation_id: binding[:invitation_id], now:, request_sha256:, key_digest:)
          end
        end

        private

        # ---- acceptance policy --------------------------------------------------

        def branch = "invitation_acceptance"

        # Replay of a successful acceptance is permitted only while the fulfilled
        # Account remains active (idempotency is not permanent authority).
        def reauthorize_replay(store, stored)
          return nil unless stored["outcome"] == "success"

          account = store.account_by_id(JSON.parse(stored["authorized_payload"])["account_id"])
          (account.nil? || account["status"] != "active") ? "reauthorization_denied" : nil
        end

        def request_hash(command:, ctx:, reference_digest:)
          request_digest(command, ctx, reference_digest, {
            "accepted_canonical_role" => command.accepted_canonical_role,
            "accepted_permission_mode" => command.accepted_permission_mode,
            "accepted_persona" => command.accepted_persona,
            "accepted_scope_sha256" => accepted_scope_hex(command),
            "supplied_account_id" => command.supplied_account_id
          })
        end

        def process(command:, ctx:, store:, receipt:, org:, invitation_id:, now:, request_sha256:, key_digest:)
          store.lock_invitation(invitation_id)
          d = { store:, command:, ctx:, now:, org:, invitation_id:, request_sha256:, key_digest: }

          internal = receipt_invalid_reason(receipt, now)
          return deny(**d, outward: internal, internal:, account_id: nil) if internal

          inv = store.read_invitation(invitation_id)
          # Terminal by the time we hold the lock (a concurrent transition won): the
          # non-disclosing outcome, no ledger writes — the winner already recorded it.
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

          store.update_registry_terminal(invitation_id, "accepted", now)
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
          write_result_success(store, ids[:result], ids[:execution], ids[:audit], command, ctx, org, now, payload,
                               { "account" => account_id, "role_assignment" => assignment_id,
                                 "invitation" => invitation_id, "session" => ids[:session] })
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

        # ---- acceptance-specific values -----------------------------------------

        def tuple_matches?(command, inv)
          command.accepted_canonical_role == inv["canonical_role"] &&
            command.accepted_permission_mode == inv["permission_mode"] &&
            norm(command.accepted_persona) == norm(inv["persona"]) &&
            accepted_scope_hex(command) == inv["scope_hex"]
        end

        def accepted_scope_hex(command) = command.accepted_scope_sha256 && hex(command.accepted_scope_sha256)

        def success_payload(account_id, assignment_id, invitation_id, session_id, org)
          { "account_id" => account_id, "role_assignment_id" => assignment_id, "invitation_id" => invitation_id,
            "session_id" => session_id, "organization_id" => org }
        end

        def success_audit_payload(payload, new_account, new_assignment)
          payload.merge("branch" => branch, "outcome" => "success",
                        "account_created" => new_account, "assignment_created" => new_assignment)
        end
      end
    end
  end
end
