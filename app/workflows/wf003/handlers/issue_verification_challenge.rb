# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf003
    module Handlers
      # WF-003 IssueVerificationChallenge (APPLICATION_LAYER.md § WF-003; CAP-005
      # MTX-028; SCORE_EVIDENCE_MODEL.md § Ownership-Verification Evidence Contract;
      # contracts/S-05.json). One pending Verification Request is created for a
      # proposed Source and one challenge token is issued, idempotently, with exactly
      # one SourceVerificationRequested event and immutable issuance provenance.
      #
      # The first-match order (contracts/S-05.json error_contract) is honoured as:
      # the envelope-schema and `unsupported_method` rejections (decided from input
      # alone, before any tenant read and before any token is generated — PRULE-020),
      # then the authentication reasons, then `tenant_mismatch`, the capability
      # (`source_verify_unauthorized`), `stale_state_version`, and finally — under the
      # per-Source lock — the exact-replay, `verification_in_progress`,
      # `source_not_proposed` and `idempotency_conflict` outcomes.
      #
      # This is issuance only. It creates one Request in `pending`, encrypts the
      # challenge behind F-02 and schedules the 24-hour expiry through F-04; it never
      # observes DNS/HTTP, reserves/completes an observation, expires/cancels/fails a
      # Request or transitions the Source. The plaintext token exists only in the
      # authorized response (and, on an exact pending replay, is re-decrypted for the
      # original actor); it is never a column, log, event or audit field.
      class IssueVerificationChallenge
        include VerificationLedger

        TARGET_TYPE = "verification_request"
        ACTION = "source.verify"
        CAPABILITY = "source.verify"
        WORKFLOW_ID = "WF-003"

        # F-02 AAD binding for the challenge ciphertext: application/record/purpose,
        # bound to the tenant. Relocating the ciphertext to another Request, purpose or
        # Organization changes the AAD and fails authentication.
        AAD_APPLICATION = "verification"
        AAD_PURPOSE = "challenge_token"
        # The F-02 façade manages wrapping-key versions internally and exposes only an
        # opaque reference (Consumption Rule: the consumer must not reach around the
        # façade for the key version). `challenge_key_id` therefore records the stable,
        # non-secret protection-profile identifier of how the token was protected,
        # nulled alongside the ciphertext reference on the later cryptographic-deletion
        # limb.
        CHALLENGE_KEY_ID = "challenge-token-envelope-v1"

        def call(command:, request_context:)
          ctx = request_context
          return schema_failure(command, ctx) unless VerificationChallenge.supported_schema?(command.schema_version)
          # PRULE-020 / MTX-071: an unsupported method is rejected before any token is
          # generated, before authentication, and creates no Request.
          return in_memory_failure(command, ctx, "unsupported_method") unless VerificationChallenge.supported_method?(command.method)

          Platform::UnitOfWork.run do |conn|
            pg = conn.raw_connection
            now = ctx.now_utc.floor(6)
            auth_store = IdentityAccess::Infrastructure::AuthorizationStore.new(pg)
            auth = IdentityAccess::Authorization::CommandAuthorizer.new(auth_store)
            store = IdentityAccess::Infrastructure::VerificationRequestStore.new(pg)

            actor = auth.authenticate(session_id: command.session_id, now:, correlation_id: ctx.correlation_id)
            return in_memory_failure(command, ctx, actor.to_s) if actor.is_a?(Symbol)

            request_sha256 = request_hash(command, actor)
            d = { command:, ctx:, store:, auth_store:, actor:, org: actor.organization_id, now:, request_sha256:, pg: }
            process(d, auth)
          end
        end

        private

        def process(d, auth)
          command = d[:command]
          store = d[:store]
          actor = d[:actor]
          now = d[:now]

          source = store.source(command.source_id)
          # Not found in the actor's proved context: another Organization's or
          # nonexistent, refused without disclosure.
          return denied(d, "tenant_mismatch") if source.nil? || source["organization_id"] != actor.organization_id
          return denied(d, "tenant_mismatch") unless command.organization_id == actor.organization_id
          return denied(d, "tenant_mismatch") unless command.project_id == source["project_id"]

          decision = auth.authorize(actor:, capability: CAPABILITY, now:)
          d = d.merge(decision:)
          unless decision.allowed?
            outward = decision.reason == "missing_authority" ? "source_verify_unauthorized" : decision.reason
            return deny(**denial_args(d), resource_id: command.source_id, outward:, internal: outward)
          end

          unless source["state_version"].to_i == command.expected_state_version
            return denied(d, "stale_state_version")
          end

          store.lock_source(command.source_id)

          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org: d[:org], command_type: command.command_type,
                                            target_type: TARGET_TYPE, target_id: command.source_id, key_digest:)
          return replay(d, existing) if existing && existing["request_hex"] == hex(d[:request_sha256])

          # A different, non-replay request while one is pending — before token issuance.
          return denied(d, "verification_in_progress") if store.pending_exists?(command.source_id)
          # A verified, active, disabled or removed Source is not verification-eligible.
          return denied(d, "source_not_proposed") unless source["state"] == "proposed"
          return denied(d, "idempotency_conflict") if existing

          commit(d, source["canonical_host"], key_digest)
        end

        def commit(d, canonical_host, key_digest)
          command = d[:command]
          ctx = d[:ctx]
          store = d[:store]
          org = d[:org]
          now = d[:now]
          actor = d[:actor]
          request_sha256 = d[:request_sha256]

          ids = %i[verification execution audit event result decision idem].to_h { |k| [k, ctx.generate_id] }
          issued_at = now
          expires_at = now + (24 * 3600)

          token = VerificationChallenge.generate_challenge_token
          # F-02 protect runs on this transaction's connection (UnitOfWork uses
          # ActiveRecord::Base.connection), so the encrypted record commits or rolls
          # back atomically with the Request. content_digest is SHA-256 of the token —
          # the immutable challenge digest that survives cryptographic deletion.
          aad = Platform::Encryption::Aad.for(application: AAD_APPLICATION, record_type: TARGET_TYPE,
                                              record_id: ids[:verification], purpose: AAD_PURPOSE, tenant: org)
          protected_token = Platform::Encryption.protect(plaintext: token, aad:)

          write_execution(store, command, ctx, org, ids[:execution], ids[:verification], actor, request_sha256,
                          key_digest, now, ACTION)
          write_authorization_decision(d[:auth_store], ids[:decision], ctx, command, actor, d[:decision], now,
                                       ids[:verification], ACTION)
          store.insert_verification_request(
            id: ids[:verification], now:, correlation_id: ctx.correlation_id,
            schema_version: VerificationChallenge::REQUEST_SCHEMA_VERSION, organization_id: org,
            project_id: command.project_id, source_id: command.source_id,
            request_initiator_account_id: actor.account_id, method: command.method, canonical_host:,
            challenge_token_sha256: protected_token.content_digest,
            challenge_ciphertext_reference: protected_token.reference, challenge_key_id: CHALLENGE_KEY_ID,
            issued_at:, expires_at:, idempotency_key_digest: key_digest
          )

          # The 24-hour expiry timer, scheduled on the same transaction through F-04.
          VerificationRequestExpirySchedule.schedule(
            pg: d[:pg], organization_id: org, project_id: command.project_id,
            verification_request_id: ids[:verification], expires_at:, now:, correlation_id: ctx.correlation_id,
            command_id: command.command_id
          )

          public_payload = {
            "verification_request_id" => ids[:verification], "source_id" => command.source_id,
            "project_id" => command.project_id, "organization_id" => org, "method" => command.method,
            "canonical_host" => canonical_host, "request_status" => "pending",
            "issued_at_utc" => iso(issued_at), "expires_at_utc" => iso(expires_at)
          }
          write_audit(store, ids[:audit], org, ctx, command, ids[:verification], actor,
                      to_state: "pending", outcome: "success", reason_code: nil, payload: public_payload, now:)
          write_event(store, ids, org, ctx, command, actor, now, 0, ids[:verification], request_sha256, key_digest,
                      "SourceVerificationRequested", "created",
                      { "method" => command.method, "canonical_host" => canonical_host,
                        "expires_at_utc" => iso(expires_at), "request_status" => "pending" })
          write_result_success(store, ids, command, ctx, org, actor, now, public_payload, ids[:verification])
          write_idempotency(store, ids[:idem], org, command, command.source_id, key_digest, request_sha256,
                            ids[:execution], ids[:result], now)

          # The plaintext token is returned ONLY here, never persisted.
          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: public_payload.transform_keys(&:to_sym).merge(challenge_token: token))
        end

        # An exact creation-command replay by the original actor. While the Request is
        # pending the same token is re-decrypted and returned without changing the
        # Request, expiry, counts, idempotent result or event set; a terminal Request
        # returns identifiers and status but never challenge material. A decryption
        # failure yields `challenge_redelivery_unavailable` and changes no state.
        def replay(d, existing)
          store = d[:store]
          command = d[:command]
          org = d[:org]
          stored = store.load_command_result(existing["command_result_id"])
          payload = JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym)

          vr = store.load_verification_request(payload[:verification_request_id])
          if vr && vr["request_status"] == "pending"
            token = redeliver_token(vr, org)
            return redelivery_unavailable(d) if token.nil?

            payload = payload.merge(challenge_token: token)
          end

          Platform::CommandResult.success(result_id: stored["id"], command_type: command.command_type,
                                          payload:, audit_record_id: stored["audit_record_id"],
                                          correlation_id: stored["correlation_id"], replayed: true)
        end

        # Re-decrypt the pending challenge under the same AAD binding. nil on unknown,
        # erased or a typed crypto failure.
        def redeliver_token(vr, org)
          aad = Platform::Encryption::Aad.for(application: AAD_APPLICATION, record_type: TARGET_TYPE,
                                              record_id: vr["id"], purpose: AAD_PURPOSE, tenant: org)
          Platform::Encryption.reveal(vr["challenge_ciphertext_reference"], aad:)
        rescue Platform::Encryption::Error
          nil
        end

        # Decryption failure on an authorized redelivery: a domain-state outcome that
        # changes no Request or Source state and no ledger row (the replay path has
        # written nothing), permitting authorized cancellation followed by a new
        # Request.
        def redelivery_unavailable(d)
          failure = Platform::ErrorCatalog.failure("challenge_redelivery_unavailable",
                                                   support_reference: d[:ctx].correlation_id)
          Platform::CommandResult.failure(result_id: d[:ctx].generate_id, command_type: d[:command].command_type,
                                          failure:, audit_record_id: d[:ctx].generate_id,
                                          correlation_id: d[:ctx].correlation_id)
        end

        # A denial whose authorization decision is an allow (a tenant/state/duplicate
        # refusal of an authorized actor) or precedes the capability evaluation, with
        # the real (or synthesized not-yet-evaluated) decision recorded.
        def denied(d, reason)
          decision = d[:decision] || pre_authorization_decision(d[:actor])
          deny(**denial_args(d.merge(decision:)), resource_id: d[:command].source_id, outward: reason, internal: reason)
        end

        def denial_args(d)
          { command: d[:command], ctx: d[:ctx], store: d[:store], auth_store: d[:auth_store], actor: d[:actor],
            decision: d[:decision], org: d[:org], now: d[:now], request_sha256: d[:request_sha256] }
        end

        def pre_authorization_decision(actor)
          IdentityAccess::Authorization::Decision.new(
            allowed: false, reason: "not_evaluated", organization_epoch: actor.authorization_epoch,
            policy_snapshot_id: nil, role_assignment_versions: [], granting_assignments: []
          )
        end

        # The canonical request hash: the shared envelope plus the method as
        # `command_payload` and the Source's expected state version in the envelope's
        # expected-version slot. Generated identifiers, the idempotency key, the
        # requested time and transport metadata are excluded, so a replay under a new
        # command_id is still a replay and a different method or Source under the same
        # key is a conflict.
        def request_hash(command, actor)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "actor_id" => actor.account_id,
            "organization_id" => actor.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => command.source_id, "project_id" => command.project_id,
            "source_id" => command.source_id, "expected_version" => command.expected_state_version,
            "policy_versions" => [Platform::PermissionBaseline::VERSION],
            "command_payload" => { "method" => command.method }
          })
        end
      end
    end
  end
end
