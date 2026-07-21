# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf001
    module Handlers
      # WF-001 invitation-decline branch (WORKFLOW_SPECIFICATIONS.md § invitation
      # decline). The intended recipient declines an active Invitation. On success it
      # atomically transitions the Invitation active->declined (recording time+reason),
      # consumes the receipt nonce, and emits exactly one InvitationDeclined
      # state-transition event — creating no Account, Role Assignment, Membership, or
      # Session (:250). Authorized by the same invitation-bound recipient capability as
      # acceptance, not a role permission.
      #
      # First-match order: exact replay; input-shape (reason bounds); ordinary
      # active-only resolution; receipt validity; Invitation active state;
      # receipt-to-target binding; expected state version; then commit. A wrong-identity
      # attempt binds the nonce and emits no event. Generic terminal-command plumbing
      # lives in InvitationTerminalSupport; only decline policy is here.
      class DeclineInvitation
        include Workflows::Wf001::InvitationTerminalSupport

        ACTION = "invitation.decline"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          reason = normalize_reason(command.reason)
          return in_memory_failure(command, ctx, "invitation_reason_invalid") if reason == :invalid

          reference_digest = Digest::SHA256.digest(command.invitation_reference)
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          request_sha256 = request_hash(command:, ctx:, reference_digest:, reason:)

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
                    invitation_id: binding[:invitation_id], now:, request_sha256:, key_digest:, reason:)
          end
        end

        private

        # ---- decline policy -----------------------------------------------------

        def branch = "invitation_decline"

        # nil (no reason) | :invalid | the trimmed 1-2,000-scalar reason.
        def normalize_reason(raw)
          return nil if raw.nil?

          trimmed = raw.to_s.strip
          return :invalid if trimmed.empty? || trimmed.length > 2000

          trimmed
        end

        def request_hash(command:, ctx:, reference_digest:, reason:)
          request_digest(command, ctx, reference_digest,
                         { "expected_state_version" => command.expected_state_version, "reason" => reason })
        end

        def process(command:, ctx:, store:, receipt:, org:, invitation_id:, now:, request_sha256:, key_digest:, reason:)
          store.lock_invitation(invitation_id)
          d = { store:, command:, ctx:, now:, org:, invitation_id:, request_sha256:, key_digest: }

          internal = receipt_invalid_reason(receipt, now)
          return deny(**d, outward: internal, internal:, account_id: nil) if internal

          inv = store.read_invitation(invitation_id)
          # Terminal by the time we hold the lock (a concurrent transition won): the
          # non-disclosing outcome, no ledger writes — the winner already recorded it.
          return invitation_not_active_in_memory(command, ctx) unless inv && inv["state"] == "active"

          return wrong_identity(**d, receipt:) unless target_matches?(receipt, inv)

          if command.expected_state_version != inv["state_version"].to_i
            return deny(**d, outward: "stale_state_version", internal: "stale_state_version", account_id: nil)
          end

          succeed(**d, receipt:, inv:, reason:)
        end

        def succeed(store:, command:, ctx:, now:, org:, invitation_id:, request_sha256:, key_digest:, receipt:, inv:, reason:)
          ids = %i[execution audit result consumption idem].to_h { |k| [k, ctx.generate_id] }
          causation = ctx.correlation_id
          new_version = inv["state_version"].to_i + 1

          write_execution(store, command, ctx, org, ids[:execution], invitation_id, request_sha256, key_digest, now, causation)

          changed = store.decline_invitation(invitation_id, inv["state_version"].to_i, now, reason)
          raise LostRace if changed.to_i.zero?

          store.update_registry_terminal(invitation_id, "declined", now)

          consumed = store.consume_nonce(
            id: ids[:consumption], created_at: iso(now), receipt_id: receipt["receipt_id"],
            receipt_digest: command.receipt_digest, command_execution_id: ids[:execution],
            consumed_at: iso(now), outcome: "consumed", reason_code: nil
          )
          raise Consumed if consumed == "already_consumed"

          payload = { "invitation_id" => invitation_id, "organization_id" => org, "state" => "declined" }
          write_audit(store, ids[:audit], org, ctx, causation, command, invitation_id, entity_type: "invitation",
                      to_state: "declined", outcome: "success", reason_code: nil,
                      payload: payload.merge("branch" => branch, "outcome" => "success", "reason" => reason), now:)
          events = [event_spec("InvitationDeclined", "state_transition", "invitation", invitation_id, new_version,
                               "active", "declined", { "reason" => reason })]
          write_events(store, events, org, ctx, causation, command, now, ids[:audit], nil, invitation_id, request_sha256, key_digest)
          write_result_success(store, ids[:result], ids[:execution], ids[:audit], command, ctx, org, now, payload,
                               { "invitation" => invitation_id })
          write_idempotency(store, ids[:idem], org, command, invitation_id, key_digest, request_sha256, ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        rescue Consumed
          raise Platform::InvariantViolation, "receipt nonce consumed concurrently"
        rescue LostRace
          raise Platform::InvariantViolation, "invitation transitioned concurrently"
        end
      end
    end
  end
end
