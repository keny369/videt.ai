# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf003
    module Handlers
      # WF-003 CompleteVerificationAttempt (APPLICATION_LAYER.md § WF-003; CAP-005
      # MTX-028/051/056; SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And Evidence;
      # contracts/S-05.json). The service-executed observation-recording limb: it runs a
      # reserved attempt's DNS/HTTP observation through the S-05-003 engine and records
      # the outcome — exactly one restricted `verification_observation` Evidence (F-03),
      # one `SourceVerificationObserved` referencing it, the attempt `reserved ->
      # completed`, and the Request last-observed / marker update — all atomically.
      #
      # The provider call is OUTSIDE every transaction (contracts/S-05.json
      # transaction_boundary): a read-and-reveal transaction resolves the inputs and
      # decrypts the challenge behind F-02, then the engine runs with no transaction
      # held, then a completion transaction commits only the recorded outcome. Completion
      # is idempotent by the reserved attempt identity: a persisted completion replays;
      # a completion-persistence failure leaves the attempt reserved and a retry re-runs
      # the observation under the SAME reserved attempt and consumes no second count
      # (`attempt_count` was incremented at reservation, never here).
      #
      # This limb only RECORDS. A matched observation is recorded like any other, and the
      # Source is LEFT `proposed` and the Request `pending`: the matched success commit
      # (Request `verified` + `SourceVerified` + `Source.Proposed -> Source.Verified` +
      # scope materialization) is S-05-006.
      class CompleteVerificationAttempt
        SUPPORTED_SCHEMA_MAJOR = "1"
        TARGET_TYPE = "verification_attempt"
        AGGREGATE_TYPE = "verification_request"
        ACTION = "verification.observe"
        POLICY_VERSION = "permission-baseline-v1"
        WORKFLOW_ID = "WF-003"
        EVENT_TYPE = "SourceVerificationObserved"
        # An observation attempt recording, per the fixed event_registry profile set.
        EVENT_PROFILE = "attempt"

        # F-03 Evidence producer/provenance. `producer_id` is stable so the Evidence
        # append is idempotent on (organization_id, producer_id, attempt_id).
        PRODUCER_ID = "wf003.verification_observation"
        EVIDENCE_SCHEMA = "verification-observation-v1"
        COLLECTOR_VERSION = "verification-observer-v1"
        SOURCE_SYSTEM = "f1-verification"

        # F-02 AAD bindings. The challenge token binding MUST match IssueVerificationChallenge;
        # the Evidence-payload binding scopes the redacted observation to its attempt.
        TOKEN_AAD = { application: "verification", record_type: "verification_request", purpose: "challenge_token" }.freeze
        PAYLOAD_AAD = { application: "evidence", record_type: "verification_observation", purpose: "observation_payload" }.freeze

        def call(command:, request_context:, outbound: Platform::Outbound)
          ctx = request_context
          return schema_failure(command, ctx) unless supported_schema?(command.schema_version)

          # Phase 1 — read and reveal (transaction-local proved context). Decides the
          # outcome path and, on the happy path, returns the observation inputs.
          prep = Platform::UnitOfWork.run { |conn| load_for_completion(conn.raw_connection, command, ctx) }
          return prep[:result] if prep[:result]

          # Phase 2 — the provider call, OUTSIDE every transaction.
          observation = VerificationObservation.observe(
            method: prep[:method], canonical_host: prep[:canonical_host], token: prep[:token], outbound:
          )

          # Phase 3 — record the outcome atomically.
          Platform::UnitOfWork.run { |conn| commit(conn.raw_connection, command, ctx, observation) }
        end

        private

        # ---- phase 1: read + reveal ----------------------------------------------

        def load_for_completion(pg, command, ctx)
          now = ctx.now_utc.floor(6)
          store = IdentityAccess::Infrastructure::VerificationObservationStore.new(pg)
          org = command.organization_id
          store.enter_org_context(org:, correlation_id: ctx.correlation_id)

          attempt = store.read_attempt(command.verification_attempt_id)
          request = store.read_request(command.verification_request_id)
          d = { store:, command:, ctx:, org:, now: }

          # The attempt and Request must exist in this Organization and name each other; a
          # correctly built completion cannot violate this.
          if attempt.nil? || request.nil? ||
             attempt["organization_id"] != org || attempt["verification_request_id"] != command.verification_request_id
            return { result: deny(**d, reason: "verification_attempt_target_mismatch") }
          end

          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org:, command_type: command.command_type, target_type: TARGET_TYPE,
                                            target_id: command.verification_attempt_id, key_digest:)
          return { result: rebuild(store, existing, command) } if existing

          # A completed attempt with no idempotency record cannot occur (both commit
          # together); any non-reserved attempt here is a stale or double completion.
          return { result: deny(**d, reason: "verification_attempt_not_reserved") } unless attempt["state"] == "reserved"
          return { result: deny(**d, reason: "verification_request_not_pending") } unless request["request_status"] == "pending"

          token = reveal_token(request, org)
          return { result: deny(**d, reason: "challenge_redelivery_unavailable") } if token.nil?

          { method: request["method"], canonical_host: request["canonical_host"], token: }
        end

        def reveal_token(request, org)
          reference = request["challenge_ciphertext_reference"]
          return nil if reference.nil?

          aad = Platform::Encryption::Aad.for(**TOKEN_AAD, record_id: request["id"], tenant: org)
          Platform::Encryption.reveal(reference, aad:)
        rescue Platform::Encryption::Error
          nil
        end

        # ---- phase 3: record the outcome -----------------------------------------

        def commit(pg, command, ctx, observation)
          now = ctx.now_utc.floor(6)
          store = IdentityAccess::Infrastructure::VerificationObservationStore.new(pg)
          org = command.organization_id
          store.enter_org_context(org:, correlation_id: ctx.correlation_id)
          store.lock_verification_request(command.verification_request_id)

          # Re-read under the lock: a concurrent completion may have won.
          attempt = store.read_attempt(command.verification_attempt_id)
          request = store.read_request(command.verification_request_id)
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          existing = store.find_idempotency(org:, command_type: command.command_type, target_type: TARGET_TYPE,
                                            target_id: command.verification_attempt_id, key_digest:)
          return rebuild(store, existing, command) if existing

          d = { store:, command:, ctx:, org:, now: }
          return deny(**d, reason: "verification_attempt_not_reserved") unless attempt && attempt["state"] == "reserved"
          return deny(**d, reason: "verification_request_not_pending") unless request && request["request_status"] == "pending"

          record(store, command, ctx, org, now, attempt, request, observation, key_digest)
        end

        def record(store, command, ctx, org, now, attempt, request, observation, key_digest)
          ids = %i[execution audit event result idem].to_h { |k| [k, ctx.generate_id] }
          on_demand = attempt["origin"] == "on_demand"
          request_sha256 = request_hash(command, ctx)
          matched = observation.match_decision == "matched"
          # Expiry wins at the boundary (SCORE_EVIDENCE_MODEL.md § Attempts; contracts/
          # S-05.json test_contracts: "an observation completing at or after expires_at_utc
          # cannot verify; at exact equality expiry wins"). A matched observation whose
          # completion commits AT OR AFTER expires_at_utc is recorded like any observation
          # but does NOT verify — the Source stays proposed and a later expiry terminates it.
          verifies = matched && now < to_time(request["expires_at_utc"])

          evidence_id = produce_evidence(command, ctx, org, now, attempt, request, observation)

          raise LostRace if store.complete_attempt(
            command.verification_attempt_id, attempt["state_version"].to_i,
            attempt_outcome(observation, now)
          ).to_i.zero?

          # S-05-006: a MATCH BEFORE EXPIRY commits, in one transaction, the Request and
          # Source verification and the interim scope policy — none without the others.
          # Every other outcome (non-match, or matched-at/after-expiry) records only
          # (S-05-005): Source proposed, Request pending.
          success = verifies ? commit_success(store, command, ctx, org, now, request, on_demand:) : nil
          unless verifies
            raise LostRace if store.record_observation_on_request(
              command.verification_request_id, request["state_version"].to_i, on_demand:, now:
            ).to_i.zero?
          end

          payload = {
            "verification_request_id" => command.verification_request_id,
            "verification_attempt_id" => command.verification_attempt_id, "evidence_id" => evidence_id,
            "attempt_number" => attempt["attempt_number"].to_i, "attempt_state" => "completed",
            "request_status" => verifies ? "verified" : "pending",
            "source_state" => verifies ? "verified" : "proposed",
            "source_scope_policy_id" => success&.fetch(:policy_id),
            "network_outcome" => observation.network_outcome,
            "match_decision" => observation.match_decision, "reason_code" => observation.reason_code
          }
          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          write_audit(store, ids[:audit], org, ctx, command, command.verification_attempt_id,
                      to_state: "completed", outcome: "success", reason_code: observation.reason_code, payload:, now:)
          write_event(store, ids, org, ctx, command, now, request, attempt, observation, evidence_id, request_sha256, key_digest)
          write_source_verified_event(store, ids, org, ctx, command, now, request, success) if verifies
          write_result(store, ids, command, ctx, org, now, payload)
          write_idempotency(store, ids[:idem], org, command, key_digest, request_sha256, ids[:execution], ids[:result], now)

          Platform::CommandResult.success(result_id: ids[:result], command_type: command.command_type,
                                          audit_record_id: ids[:audit], correlation_id: ctx.correlation_id,
                                          payload: payload.transform_keys(&:to_sym))
        rescue LostRace
          raise Platform::InvariantViolation, "verification attempt completed concurrently"
        end

        # The atomic matched success commit (SCORE_EVIDENCE_MODEL.md :155; contracts/
        # S-05.json MTX-028/051; WORKFLOW_SPECIFICATIONS.md § WF-003): materialize the
        # interim scope policy, transition the Request pending -> verified/matched with
        # the challenge erased, and transition the Source proposed -> verified with the
        # policy pinned — all guarded on the expected state versions, so concurrent
        # matched completions transition once and a stale version raises LostRace (the
        # whole completion rolls back). Runs inside the completion transaction.
        def commit_success(store, command, ctx, org, now, request, on_demand:)
          source = store.read_source(request["source_id"])
          raise LostRace unless source && source["state"] == "proposed"

          policy_id = ctx.generate_id
          materialize_interim_policy(store, ctx, org, now, request, source, policy_id)

          raise LostRace if store.verify_request_on_match(
            command.verification_request_id, request["state_version"].to_i, on_demand:, now:
          ).to_i.zero?
          # Redelivery disablement: the F-02 challenge material is destroyed, atomic with
          # the transition (the ciphertext reference was nulled above); the digest survives.
          reference = request["challenge_ciphertext_reference"]
          Platform::Encryption.erase(reference) if reference

          raise LostRace if store.verify_source(source["id"], source["state_version"].to_i, policy_id, now:).to_i.zero?

          { policy_id:, source_version: source["state_version"].to_i + 1 }
        end

        # source-scope-interim-v1 (WORKFLOW_SPECIFICATIONS.md :412): HTTPS, its default
        # port, the verified canonical host only, include prefix "/", no exclude prefix,
        # retain_all. Modelled to the canonical Source Scope Policy schema so S-06 extends it.
        INTERIM_POLICY_VERSION = "source-scope-interim-v1"
        INTERIM_POLICY = { allowed_schemes: ["https"], allowed_ports: [443], include_prefixes: ["/"],
                           exclude_prefixes: [], query_handling: "retain_all" }.freeze

        def materialize_interim_policy(store, ctx, org, now, request, source, policy_id)
          host = source["canonical_host"]
          store.insert_source_scope_policy(
            id: policy_id, now:, correlation_id: ctx.correlation_id, organization_id: org,
            project_id: request["project_id"], source_id: source["id"],
            policy_version: INTERIM_POLICY_VERSION, scope: "source", canonical_host: host,
            allowed_schemes: INTERIM_POLICY[:allowed_schemes], allowed_ports: INTERIM_POLICY[:allowed_ports],
            include_prefixes: INTERIM_POLICY[:include_prefixes], exclude_prefixes: INTERIM_POLICY[:exclude_prefixes],
            query_handling: INTERIM_POLICY[:query_handling], content_sha256: interim_policy_digest(host)
          )
        end

        def interim_policy_digest(host)
          Platform::CanonicalJson.digest({
            "canonical_host" => host, "scope" => "source", "policy_version" => INTERIM_POLICY_VERSION,
            "allowed_schemes" => INTERIM_POLICY[:allowed_schemes], "allowed_ports" => INTERIM_POLICY[:allowed_ports],
            "include_prefixes" => INTERIM_POLICY[:include_prefixes], "exclude_prefixes" => INTERIM_POLICY[:exclude_prefixes],
            "query_handling" => INTERIM_POLICY[:query_handling]
          })
        end

        # SourceVerified, on the Source aggregate, inside the success transaction.
        def write_source_verified_event(store, ids, org, ctx, command, now, request, success)
          event_id = ctx.generate_id
          envelope = {
            "account_id" => nil, "actor_id" => nil, "affected_entity_id" => request["source_id"],
            "affected_entity_type" => "source", "aggregate_version" => success[:source_version],
            "audit_record_id" => ids[:audit], "causation_id" => ctx.correlation_id, "command_id" => command.command_id,
            "correlation_id" => ctx.correlation_id, "event_id" => event_id, "event_profile" => "state_transition",
            "event_type" => "SourceVerified", "from_state" => "proposed", "occurred_at_utc" => now.iso8601(6),
            "organization_id" => org, "outcome" => "success", "project_id" => request["project_id"],
            "reason_code" => "matched", "schema_version" => "1.0", "service_identity_id" => ctx.service_identity_id,
            "source_id" => request["source_id"], "source_scope_policy_id" => success[:policy_id],
            "to_state" => "verified", "verification_request_id" => command.verification_request_id,
            "workflow_id" => WORKFLOW_ID
          }
          bytes = Platform::CanonicalJson.encode(envelope)
          store.insert_event(
            id: event_id, created_at: iso(now), event_type: "SourceVerified", event_profile: "state_transition",
            occurred_at: iso(now), organization_id: org, aggregate_type: "source", aggregate_id: request["source_id"],
            aggregate_version: success[:source_version], partition_month: month(now),
            correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, audit_record_id: ids[:audit],
            event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
          )
        end

        # Exactly one restricted verification_observation Evidence (F-03), its redacted
        # payload behind an F-02 reference — never the plaintext token or raw content.
        # Idempotent on (org, PRODUCER_ID, attempt_id): a retried completion writes none.
        # The F-03 producer surface is `Platform::Evidence.produce`; its default store
        # runs on `ActiveRecord::Base.connection`, which is exactly this UnitOfWork's
        # connection, so the Evidence commits atomically with the completion. Referencing
        # the internal EvidenceStore here would break the single-surface fitness.
        def produce_evidence(command, ctx, org, now, attempt, request, observation)
          payload = Platform::CanonicalJson.encode(evidence_payload(command, now, attempt, request, observation)).b
          aad = Platform::Encryption::Aad.for(**PAYLOAD_AAD, record_id: command.verification_attempt_id, tenant: org)
          protected_payload = Platform::Encryption.protect(plaintext: payload, aad:)

          record = Platform::Evidence::Record.build(
            schema_version: EVIDENCE_SCHEMA, organization_id: org, project_id: request["project_id"],
            source_id: request["source_id"], evaluation_id: nil, evidence_type: "verification_observation",
            producer_id: PRODUCER_ID, attempt_id: command.verification_attempt_id,
            payload_reference: protected_payload.reference, content_sha256: protected_payload.content_digest.unpack1("H*"),
            captured_at_utc: now, observed_at_utc: now, source_system: SOURCE_SYSTEM,
            collection_method: request["method"], collector_version: COLLECTOR_VERSION,
            validation_status: "valid", validation_reason_code: nil,
            data_classification: "restricted", payload_retention_class: "product_evidence_payload",
            correlation_id: ctx.correlation_id
          )
          Platform::Evidence.produce(record)
        end

        # The redacted observation payload (SCORE_EVIDENCE_MODEL.md :160): enums, counts
        # and the HASH of the observed value — never the token or raw DNS/HTTP content.
        def evidence_payload(command, now, attempt, request, observation)
          {
            "verification_request_id" => command.verification_request_id, "method" => request["method"],
            "observation_location" => observation.observation_location,
            "attempt_number" => attempt["attempt_number"].to_i, "attempt_origin" => attempt["origin"],
            "automated_slot_offset" => attempt["automated_slot_offset_minutes"]&.to_i,
            "started_at_utc" => iso(now), "completed_at_utc" => iso(now),
            "network_outcome" => observation.network_outcome, "http_status" => observation.http_status,
            "dns_response_code" => observation.dns_response_code, "received_byte_count" => observation.received_byte_count,
            "observed_value_sha256" => observation.observed_value_sha256&.unpack1("H*"),
            "match_decision" => observation.match_decision, "reason_code" => observation.reason_code
          }
        end

        def attempt_outcome(observation, now)
          { started_at: iso(now), completed_at: iso(now), network_outcome: observation.network_outcome,
            http_status: observation.http_status, dns_response_code: observation.dns_response_code,
            received_byte_count: observation.received_byte_count,
            observed_value_sha256: observation.observed_value_sha256, match_decision: observation.match_decision,
            reason_code: observation.reason_code, now: }
        end

        # ---- audited no-record outcome -------------------------------------------

        def deny(store:, command:, ctx:, org:, now:, reason:)
          ids = %i[execution audit result].to_h { |k| [k, ctx.generate_id] }
          key_digest = Digest::SHA256.digest(command.idempotency_key)
          request_sha256 = request_hash(command, ctx)
          write_execution(store, command, ctx, org, ids[:execution], request_sha256, key_digest, now)
          write_audit(store, ids[:audit], org, ctx, command, command.verification_attempt_id, to_state: nil,
                      outcome: "failure", reason_code: reason,
                      payload: { "outcome" => "failure", "internal_reason" => reason,
                                 "verification_request_id" => command.verification_request_id,
                                 "verification_attempt_id" => command.verification_attempt_id,
                                 "organization_id" => org }, now:)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          write_result(store, ids, command, ctx, org, now, {}, failure:)
          Platform::CommandResult.failure(result_id: ids[:result], command_type: command.command_type,
                                          failure:, audit_record_id: ids[:audit], correlation_id: ctx.correlation_id)
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
              retryable: stored["retryable"] == "t" || stored["retryable"] == true,
              recovery_action: stored["recovery_action"], support_reference: stored["support_reference"]
            )
            Platform::CommandResult.failure(result_id: stored["id"], command_type: command.command_type,
                                            failure:, audit_record_id: stored["audit_record_id"],
                                            correlation_id: stored["correlation_id"], replayed: true)
          end
        end

        # ---- writers -------------------------------------------------------------

        def write_execution(store, command, ctx, org, id, request_sha256, key_digest, now)
          store.insert_command_execution(
            id:, created_at: iso(now), correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, idempotency_key_digest: key_digest,
            command_type: command.command_type, command_schema_version: command.schema_version,
            service_identity_id: ctx.service_identity_id, organization_id: org, target_type: TARGET_TYPE,
            target_id: command.verification_attempt_id, action: ACTION,
            requested_at: iso(command.requested_at_utc), authorization_check_at: iso(now),
            policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            canonical_payload: JSON.generate({ "verification_request_id" => command.verification_request_id }),
            request_sha256:
          )
        end

        def write_audit(store, id, org, ctx, command, entity_id, to_state:, outcome:, reason_code:, payload:, now:)
          store.insert_audit(
            id:, occurred_at: iso(now), partition_month: month(now), organization_id: org,
            service_identity_id: ctx.service_identity_id, correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id, entity_type: TARGET_TYPE,
            entity_id:, to_state:, outcome:, reason_code:, payload: JSON.generate(payload),
            content_sha256: Platform::CanonicalJson.digest(payload)
          )
        end

        def write_event(store, ids, org, ctx, command, now, request, attempt, observation, evidence_id, request_sha256, key_digest)
          aggregate_version = request["state_version"].to_i + 1
          envelope = {
            "account_id" => nil, "actor_id" => nil, "affected_entity_id" => command.verification_request_id,
            "affected_entity_type" => AGGREGATE_TYPE, "aggregate_version" => aggregate_version,
            "attempt_number" => attempt["attempt_number"].to_i, "audit_record_id" => ids[:audit],
            "causation_id" => ctx.correlation_id, "command_id" => command.command_id,
            "correlation_id" => ctx.correlation_id, "evidence_id" => evidence_id, "event_id" => ids[:event],
            "event_profile" => EVENT_PROFILE, "event_type" => EVENT_TYPE,
            "idempotency_identity_hash" => hex(key_digest), "input_hash" => hex(request_sha256),
            "match_decision" => observation.match_decision, "network_outcome" => observation.network_outcome,
            "occurred_at_utc" => now.iso8601(6), "organization_id" => org, "outcome" => "success",
            "project_id" => request["project_id"], "reason_code" => observation.reason_code,
            "schema_version" => "1.0", "service_identity_id" => ctx.service_identity_id,
            "source_id" => request["source_id"], "verification_attempt_id" => command.verification_attempt_id,
            "verification_request_id" => command.verification_request_id, "workflow_id" => WORKFLOW_ID
          }
          bytes = Platform::CanonicalJson.encode(envelope)
          store.insert_event(
            id: ids[:event], created_at: iso(now), event_type: EVENT_TYPE, event_profile: EVENT_PROFILE,
            occurred_at: iso(now), organization_id: org, aggregate_type: AGGREGATE_TYPE,
            aggregate_id: command.verification_request_id, aggregate_version:, partition_month: month(now),
            correlation_id: ctx.correlation_id, causation_id: ctx.correlation_id,
            command_id: command.command_id, audit_record_id: ids[:audit],
            event_bytes: bytes, event_sha256: Digest::SHA256.digest(bytes)
          )
        end

        def write_result(store, ids, command, ctx, org, now, payload, failure: nil)
          store.insert_command_result(
            id: ids[:result], created_at: iso(now), correlation_id: ctx.correlation_id,
            causation_id: ctx.correlation_id, command_id: command.command_id,
            command_execution_id: ids[:execution], outcome: failure ? "failure" : "success",
            organization_id: org, service_identity_id: ctx.service_identity_id, completed_at: iso(now),
            authorization_check_at: iso(now),
            target_refs: JSON.generate(failure ? {} : { TARGET_TYPE => command.verification_attempt_id }),
            governing_policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
            failure:, authorized_payload: JSON.generate(payload), audit_record_id: ids[:audit]
          )
        end

        def write_idempotency(store, id, org, command, key_digest, request_sha256, execution_id, result_id, now)
          store.insert_idempotency(
            id:, created_at: iso(now), organization_id: org, command_type: command.command_type,
            target_type: TARGET_TYPE, target_id: command.verification_attempt_id, key_digest:, request_sha256:,
            command_execution_id: execution_id, command_result_id: result_id,
            retain_until: iso(now + (30 * 24 * 3600))
          )
        end

        def request_hash(command, ctx)
          Platform::CanonicalJson.digest({
            "action" => ACTION, "command_type" => command.command_type,
            "command_schema_version" => command.schema_version, "service_identity_id" => ctx.service_identity_id,
            "organization_id" => command.organization_id, "target_type" => TARGET_TYPE,
            "target_id" => command.verification_attempt_id, "project_id" => nil,
            "policy_versions" => [POLICY_VERSION],
            "command_payload" => { "verification_request_id" => command.verification_request_id }
          })
        end

        def schema_failure(command, ctx) = in_memory_failure(command, ctx, "command_schema_unsupported")

        def in_memory_failure(command, ctx, reason)
          failure = Platform::ErrorCatalog.failure(reason, support_reference: ctx.correlation_id)
          Platform::CommandResult.failure(result_id: ctx.generate_id, command_type: command.command_type,
                                          failure:, audit_record_id: ctx.generate_id, correlation_id: ctx.correlation_id)
        end

        def supported_schema?(version) = version.to_s.split(".").first == SUPPORTED_SCHEMA_MAJOR
        def iso(time) = time&.getutc&.iso8601(6)
        def month(time) = Date.new(time.year, time.month, 1).iso8601
        def hex(bytes) = bytes.unpack1("H*")
        def to_time(value) = value.respond_to?(:getutc) ? value.getutc : Time.parse(value).getutc

        class LostRace < StandardError; end
      end
    end
  end
end
