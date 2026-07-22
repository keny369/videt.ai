# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf001
    module Handlers
      # WF-001 ExpireInvitation (WORKFLOW_SPECIFICATIONS.md :242 "Active expiry is
      # exactly seven days after activation, and at equality expiry wins over
      # acceptance or decline. Decline, rejection, revocation, expiry, and
      # acceptance are terminal"; :250 "concurrent accept/decline/expiry has one
      # winner under current state, with expiry winning at equality";
      # APPLICATION_LAYER.md :371 and contracts/S-01.json — a service-only
      # ScheduledAction transition, NOT a principal command;
      # BACKGROUND_PROCESSING.md :405 `invitation_expire` -> `ExpireInvitation`).
      #
      # Authority. There is none to check. Expiry is not a Role permission held by
      # anyone: it is the identity service's own timer, so this handler deliberately
      # does not touch the Permission Baseline, CommandAuthorizer, Session
      # authentication or any ad-hoc role test, and it never constructs a Session.
      # Its only authorization-shaped act is entering the Organization context
      # named by the claimed ScheduledAction — data scoping, not authorization.
      #
      # Order (first match): schema; the action/target binding; enter the action's
      # Organization context; take the per-invitation advisory lock the other three
      # terminal commands take; read the target (a cross-Organization target is
      # simply not visible); exact replay; due-boundary recheck at transaction
      # time; active state; then the guarded transition.
      #
      # Idempotency is the ScheduledAction identity digest, not a caller key, which
      # is what makes the expiry idempotent independently of scheduler redelivery:
      # a duplicate claim, a worker retry and a replay all carry the same key, and
      # only the first emits `InvitationExpired`.
      #
      # It creates no Account, Role Assignment, Assignment, membership or Session,
      # and consumes no invitation receipt nonce — the canonical contract binds a
      # nonce only to a receipt-bound recipient response, and a timer has no
      # receipt.
      class ExpireInvitation
        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "invitation"
        ACTION = "invitation.expire"
        POLICY_VERSION = "onboarding-interim-v1"
        # The exact retained machine transition reason copied into the event's
        # `reason_code` (API_CONTRACTS.md :773 reason source `transition`, :938).
        TRANSITION_REASON_CODE = "invitation_expired"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)
          # A misrouted action must never expire an unrelated row.
          return in_memory_failure(command, ctx, "scheduled_action_target_mismatch") unless command.target_type == TARGET_TYPE

          key_digest = Digest::SHA256.digest(command.action_identity_sha256)

          Platform::UnitOfWork.run do |conn|
            now = ctx.now_utc.floor(6)
            store = IdentityAccess::Infrastructure::ExpireInvitationStore.new(conn.raw_connection)

            # 1. Enter the action's Organization context. Every read and write
            #    below is row-level-security scoped to it.
            store.enter_org_context(org: command.organization_id, correlation_id: ctx.correlation_id)

            # 2. Serialize against accept/decline/revoke on the shared lock.
            store.lock_invitation(command.invitation_id)

            process(command:, ctx:, store:, now:, key_digest:)
          end
        end

        private

        def branch = "invitation_expire"

        def process(command:, ctx:, store:, now:, key_digest:)
          org = command.organization_id
          request_sha256 = request_hash(command, ctx)
          d = { store:, command:, ctx:, now:, org:, request_sha256:, key_digest: }

          # 3. Read the target under the proved context. Not visible (unknown, or
          #    another Organization's) => the single non-disclosing outcome, with
          #    no ledger write that would confirm anything about it.
          inv = store.read_invitation(command.invitation_id)
          return in_memory_failure(command, ctx, "invitation_not_active") if inv.nil?

          # 4. Exact replay: a redelivered action returns the stored result and
          #    emits nothing.
          existing = store.find_idempotency(org:, command_type: command.command_type, target_type: TARGET_TYPE,
                                            target_id: command.invitation_id, key_digest:)
          if existing
            return rebuild_stored_result(store, existing, command) if existing["request_hex"] == hex(request_sha256)

            # A different command already owns this identity: record the outcome
            # but never a second idempotency record for the same key.
            return deny(**d, outward: "idempotency_conflict", internal: "idempotency_conflict", replayable: false)
          end

          # 5. Recheck the product deadline at transaction time
          #    (BACKGROUND_PROCESSING.md :121). The action's due instant must be
          #    the Invitation's expiry instant, and that instant must have arrived.
          #    Either deviation is a transport-integrity fault: it fails closed and
          #    the worker quarantines the action rather than expiring early.
          expires_at = inv["expires_at"] && to_time(inv["expires_at"])
          if expires_at.nil? || command.due_at != expires_at
            return deny(**d, outward: "scheduled_action_target_mismatch",
                        internal: "scheduled_action_target_mismatch", replayable: false)
          end
          if now < expires_at
            return deny(**d, outward: "scheduled_action_not_due",
                        internal: "scheduled_action_not_due", replayable: false)
          end

          # 6. Only active -> expired may succeed. Already accepted, declined,
          #    rejected, revoked or expired is the canonical harmless terminal
          #    outcome: one audited no-state command outcome, no second event, no
          #    reopening.
          return deny(**d, outward: "invitation_not_active", internal: "invitation_not_active") unless inv["state"] == "active"

          succeed(**d, inv:)
        end

        # ---- success ------------------------------------------------------------

        def succeed(store:, command:, ctx:, now:, org:, request_sha256:, key_digest:, inv:)
          ids = %i[execution audit event result idem].to_h { |k| [k, ctx.generate_id] }
          causation = ctx.correlation_id
          new_version = inv["state_version"].to_i + 1
          epoch = store.organization_epoch(org).to_i

          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now, causation)

          changed = store.expire_invitation(command.invitation_id, inv["state_version"].to_i, now, TRANSITION_REASON_CODE)
          raise LostRace if changed.to_i.zero?

          store.update_registry_terminal(command.invitation_id, "expired", now)

          payload = { "invitation_id" => command.invitation_id, "organization_id" => org, "state" => "expired" }
          write_audit(store, ids[:audit], org, ctx, causation, command, command.invitation_id,
                      to_state: "expired", outcome: "success", reason_code: TRANSITION_REASON_CODE,
                      payload: payload.merge("branch" => branch, "outcome" => "success",
                                             "scheduled_action_id" => command.action_id,
                                             "requester_account_id" => inv["requester_account_id"]), now:)
          write_event(store, ids, org, ctx, causation, command, now, new_version, epoch,
                      request_sha256, key_digest, inv["requester_account_id"])
          write_result_success(store, ids, command, ctx, org, now, payload)
          write_idempotency(store, ids[:idem], org, command, key_digest, request_sha256, ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        rescue LostRace
          raise Platform::InvariantViolation, "invitation transitioned concurrently"
        end

        # ---- audited no-state outcome -------------------------------------------

        # The canonical harmless/terminal result: one audited command outcome, no
        # Invitation event, no state change ("A rejected no-state command emits
        # only the standard audited command outcome", contracts/S-01.json
        # audit_record).
        #
        # `replayable` binds the outcome to the action identity so a redelivery
        # returns it instead of writing a second denial. It is false for a
        # transport-integrity deviation, which is not a product outcome and whose
        # action the worker quarantines, and for an idempotency conflict, whose
        # key is already owned by another command.
        def deny(store:, command:, ctx:, now:, org:, request_sha256:, key_digest:, outward:, internal:, replayable: true)
          execution_id = ctx.generate_id
          audit_id = ctx.generate_id
          result_id = ctx.generate_id
          causation = ctx.correlation_id

          write_execution(store, command, ctx, org, execution_id, request_sha256, key_digest, now, causation)
          write_audit(store, audit_id, org, ctx, causation, command, command.invitation_id,
                      to_state: nil, outcome: "failure", reason_code: internal,
                      payload: { "branch" => branch, "outcome" => "failure", "internal_reason" => internal,
                                 "outward_reason" => outward, "invitation_id" => command.invitation_id,
                                 "organization_id" => org, "scheduled_action_id" => command.action_id }, now:)
          failure = Platform::ErrorCatalog.failure(outward, support_reference: ctx.correlation_id)
          write_result_failure(store, result_id, execution_id, command, ctx, org, audit_id, failure, now)
          if replayable
            write_idempotency(store, ctx.generate_id, org, command, key_digest, request_sha256, execution_id, result_id, now)
          end
          Platform::CommandResult.failure(result_id:, command_type: command.command_type, failure:,
                                          audit_record_id: audit_id, correlation_id: ctx.correlation_id)
        end

        def rebuild_stored_result(store, existing, command)
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

        # ---- writers -------------------------------------------------------------

        def write_execution(store, command, ctx, org, id, request_sha256, key_digest, now, causation)
          store.insert_command_execution(
            id:, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: causation,
            command_id: command.command_id, idempotency_key_digest: key_digest, command_type: command.command_type,
            command_schema_version: command.schema_version, service_identity_id: ctx.service_identity_id,
            organization_id: org, target_type: TARGET_TYPE, target_id: command.invitation_id, action: ACTION,
            requested_at: iso(command.requested_at_utc), authorization_check_at: iso(now),
            policy_versions: policy_versions_json, canonical_payload: canonical_payload_json(command),
            request_sha256:
          )
        end

        def write_audit(store, id, org, ctx, causation, command, entity_id, to_state:, outcome:, reason_code:, payload:, now:)
          store.insert_audit(
            id:, occurred_at: iso(now), partition_month: month(now), organization_id: org,
            service_identity_id: ctx.service_identity_id, correlation_id: ctx.correlation_id, causation_id: causation,
            command_id: command.command_id, entity_type: TARGET_TYPE, entity_id:, to_state:, outcome:, reason_code:,
            payload: JSON.generate(payload), content_sha256: Platform::CanonicalJson.digest(payload)
          )
        end

        # Exactly one `InvitationExpired` state-transition event. Attribution is
        # the executing service identity with a null actor, preserving the
        # exactly-one-actor-or-service invariant; the envelope carries the
        # Organization authorization epoch, the from/to states, the retained
        # machine transition reason and the Invitation's requester reference.
        def write_event(store, ids, org, ctx, causation, command, now, new_version, epoch, request_sha256, key_digest, requester)
          envelope = {
            "account_id" => nil, "actor_id" => nil, "affected_entity_id" => command.invitation_id,
            "affected_entity_type" => TARGET_TYPE, "aggregate_version" => new_version,
            "audit_record_id" => ids[:audit], "causation_id" => causation, "command_id" => command.command_id,
            "correlation_id" => ctx.correlation_id, "event_id" => ids[:event],
            "event_profile" => "state_transition", "event_type" => "InvitationExpired",
            "from_state" => "active", "idempotency_identity_hash" => hex(key_digest),
            "input_hash" => hex(request_sha256), "invitation_id" => command.invitation_id,
            "occurred_at_utc" => now.iso8601(6), "organization_epoch" => epoch, "organization_id" => org,
            "outcome" => "success", "project_id" => nil, "reason" => nil,
            "reason_code" => TRANSITION_REASON_CODE, "requester_account_id" => requester,
            "schema_version" => "1.0", "scheduled_action_id" => command.action_id,
            "service_identity_id" => ctx.service_identity_id, "to_state" => "expired",
            "transition_reason_code" => TRANSITION_REASON_CODE, "workflow_id" => "WF-001"
          }
          bytes = Platform::CanonicalJson.encode(envelope)
          store.insert_event(
            id: ids[:event], created_at: iso(now), event_type: "InvitationExpired",
            event_profile: "state_transition", occurred_at: iso(now), organization_id: org,
            aggregate_type: TARGET_TYPE, aggregate_id: command.invitation_id, aggregate_version: new_version,
            partition_month: month(now), correlation_id: ctx.correlation_id, causation_id: causation,
            command_id: command.command_id, audit_record_id: ids[:audit],
            event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
          )
        end

        def write_result_success(store, ids, command, ctx, org, now, payload)
          store.insert_command_result(
            id: ids[:result], created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, command_execution_id: ids[:execution], outcome: "success",
            organization_id: org, service_identity_id: ctx.service_identity_id, completed_at: iso(now),
            authorization_check_at: iso(now), target_refs: JSON.generate({ "invitation" => command.invitation_id }),
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

        def write_idempotency(store, id, org, command, key_digest, request_sha256, execution_id, result_id, now)
          store.insert_idempotency(
            id:, created_at: iso(now), organization_id: org, command_type: command.command_type,
            target_type: TARGET_TYPE, target_id: command.invitation_id, key_digest:, request_sha256:,
            command_execution_id: execution_id, command_result_id: result_id, retain_until: iso(now + (30 * 24 * 3600))
          )
        end

        # ---- helpers -------------------------------------------------------------

        def schema_failure(command, ctx) = in_memory_failure(command, ctx, "command_schema_unsupported")

        def in_memory_failure(command, ctx, reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                          failure:, audit_record_id: ctx.generate_id, correlation_id: ctx.correlation_id)
        end

        # The canonical command digest. It is computed from the action identity
        # alone — no clock, no correlation id — so every delivery of the same
        # action produces the same digest and an exact replay is recognizable.
        def request_hash(command, ctx)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version,
            "service_identity_id" => ctx.service_identity_id,
            "organization_id" => command.organization_id, "project_id" => nil,
            "target_type" => TARGET_TYPE, "target_id" => command.invitation_id,
            "policy_versions" => [POLICY_VERSION],
            "command_payload" => { "scheduled_action_identity_sha256" => hex(command.action_identity_sha256),
                                   "due_at" => command.due_at.getutc.iso8601(6) }
          })
        end

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
        def policy_versions_json = JSON.generate({ "onboarding" => POLICY_VERSION })
        def canonical_payload_json(command) = JSON.generate({ "scheduled_action_id" => command.action_id })
        def to_time(value) = value.respond_to?(:getutc) ? value.getutc : Time.parse(value).getutc
        def iso(time) = time.getutc.iso8601(6)
        def month(time) = Date.new(time.year, time.month, 1).iso8601
        def hex(bytes) = bytes.unpack1("H*")

        class LostRace < StandardError; end
      end
    end
  end
end
