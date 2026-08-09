# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf006
    # THE OWNER-APPROVAL RELEASE SERVICE — the principal the ratified Permission Baseline names for
    # `measurement_set.activate`, and the step that had never existed.
    #
    # Everything either side of it was already built. `MeasurementIntake.import` stages a package as
    # `proposed`; `MeasurementIntake.activate` checks two owner signatures over the exact package
    # digest and turns the row `active`; `MeasurementIntake.submit` refuses every observation until
    # a set is active. What was missing was the thing entitled to call the middle one. The
    # specification says so in as many words — IMPLEMENTATION_MATRIX.md :1579 and contracts/S-08.json,
    # "`measurement_set.activate` for the owner-approval release service" — and searching the code for
    # that service returned only comments pointing at it. A staged package could therefore never
    # become usable by any path the platform owned.
    #
    # THIS IS NOT A SCREEN AND IT HAS NO ROUTE, BY CONSTRUCTION AND NOT BY OVERSIGHT.
    # WORKFLOW_SPECIFICATIONS.md :168 denies `measurement_set.activate` to all six actor columns —
    # OrganizationAdmin included — and gives it to this service alone. `config/routes.rb` states the
    # consequence at the boundary ("there is deliberately no activate route"), and
    # `Platform::PermissionBaseline` now transcribes the row as an empty, CONSULTED allow-list, so no
    # value of `roles` and no `permission_mode` makes `permits?` answer true. Nothing here gives a
    # human a button; the caller is an operator running the release task with bytes two owners signed.
    #
    # ATTRIBUTION IS THE POINT OF THE SERVICE. Activation writes a `command_executions`,
    # `audit_record_registry` and `command_results` row under
    # `Platform::ServiceIdentity::RELEASE_SERVICE`, whose `permission_scope` names
    # `measurement_set.activate` and nothing else. `exactly_one_actor_or_service` means `actor_id`
    # stays null on all three, so the ledger records that a service — this one, identified — acted,
    # and `f1_service_identity_active` is re-checked by the same foreign keys that guard every other
    # service path. Suspending this one row stops activation without touching anything else.
    #
    # IT EMITS NO DOMAIN EVENT, AND THAT IS A DELIBERATE REFUSAL RATHER THAN AN OMISSION.
    # API_CONTRACTS.md :703 closes the event catalogue — "unknown members, EVENT TYPES, type/profile
    # pairs and extra-schema combinations are prohibited" — and the inline catalogue at :781-:911
    # contains no event for measurement-set activation. `measurement_set` appears only as an
    # `EventArtifactType` (:712), which is the vocabulary of a `policy_activation` PAYLOAD, and no
    # event type in the catalogue carries it. Emitting a `MeasurementSetActivated` would be inventing
    # a contract member; the audit record is the ratified record of the act, exactly as it is for the
    # WF-006 checkpoints that decide something and emit nothing.
    class OwnerApprovalRelease
      SERVICE_IDENTITY = Platform::ServiceIdentity::RELEASE_SERVICE
      COMMAND_TYPE = "wf006.activate_measurement_set"
      COMMAND_SCHEMA_VERSION = "1.0"
      # The ratified `EventEntityType` for a global immutable artifact activatable only by its named
      # owner-approval release service (API_CONTRACTS.md :709; IMPLEMENTATION_MATRIX.md :4478 sorts
      # every artifact type into "tenant-scoped mutable policy ... or a global immutable release
      # artifact"). A Measurement Set is the latter, so it is not `policy_artifact`.
      TARGET_TYPE = "release_artifact"
      ACTION = "measurement_set.activate"
      POLICY_VERSION = "permission-baseline-v1"
      # A package's row identity is derived from its own bytes, so the target and the idempotency
      # identity are both computable BEFORE anything is read. A replay therefore finds its stored
      # result even when the row it names has since moved on.
      IDEMPOTENCY_RETENTION_SECONDS = 30 * 24 * 3600

      # Activate one signed package. Returns a `Platform::CommandResult`: success carries the
      # approval record, failure carries the ratified reason.
      def call(package:, organization_id:, now:, correlation_id:, ids: Platform::Ids.system)
        digest = MeasurementPackage.digest(package)
        set_id = MeasurementIntake.derived_id(digest)
        idempotency_key = digest.unpack1("H*")

        Platform::UnitOfWork.run do |conn|
          store = IdentityAccess::Infrastructure::EvaluationInputStore.new(conn.raw_connection)
          store.enter_org_context(org: organization_id, correlation_id:)
          resolve(store:, package:, organization_id:, now: now.getutc.floor(6), correlation_id:, ids:,
                  set_id:, idempotency_key:)
        end
      end

      private

      def resolve(store:, package:, organization_id:, now:, correlation_id:, ids:, set_id:, idempotency_key:)
        # ONE ACTIVATION AT A TIME, PER SET. `activate_measurement_set` is already guarded on
        # `status = 'proposed' AND state_version = $2`, so a lost race changes nothing — but without
        # this lock both callers would read `proposed`, both would write their ledger rows, and the
        # loser's would describe an activation that did not happen. The lock makes the read and the
        # decision it drives one critical section, exactly as the Evaluation input gate does.
        store.serialize_on("measurement_set:#{set_id}")

        key_digest = Digest::SHA256.digest(idempotency_key)
        request_sha256 = request_hash(organization_id, set_id, idempotency_key)
        existing = store.find_idempotency(org: organization_id, command_type: COMMAND_TYPE,
                                          target_type: TARGET_TYPE, target_id: set_id, key_digest:)
        if existing
          # ALTERED BYTES UNDER THE SAME KEY CANNOT HAPPEN HERE, and the check stays anyway. The key
          # IS the digest of the bytes, so a different package is a different key by construction;
          # asserting it is what makes that property observable rather than assumed.
          if existing["request_hex"] != request_sha256.unpack1("H*")
            return conflict(store, organization_id, now, correlation_id, ids, set_id, key_digest,
                            request_sha256)
          end

          return rebuild(store, existing)
        end

        result = MeasurementIntake.activate(store:, package:, organization_id:, now:, correlation_id:)
        unless result.ok?
          return deny(store, organization_id, now, correlation_id, ids, set_id, key_digest,
                      request_sha256, result.reason, result.detail)
        end

        settle(store:, organization_id:, now:, correlation_id:, ids:, set_id:, key_digest:,
               request_sha256:, row: result.record, package:)
      end

      # ---- the activation record ----------------------------------------------------------

      # WHO APPROVED IT, AND WHEN. The row already carries both signature blobs and
      # `owner_approval_reference` — the database's `activation_requires_both_signatures` CHECK
      # refuses an active row without them — so this payload records the READABLE form of the same
      # facts: which two people signed, under what authority, when they signed, and which approval
      # decision the package cites. It is derived from the ACTIVATED ROW rather than from the
      # submitted package wherever both could supply it, so the ledger describes what was committed.
      def settle(store:, organization_id:, now:, correlation_id:, ids:, set_id:, key_digest:,
                 request_sha256:, row:, package:)
        allocated = %i[command execution audit result idem].to_h { |k| [k, ids.generate] }
        payload = approval_payload(row, package)

        write_execution(store, organization_id, now, correlation_id, allocated, set_id, key_digest,
                        request_sha256, payload)
        write_audit(store, organization_id, now, correlation_id, allocated, set_id,
                    to_state: "active", outcome: "success", reason_code: nil, payload:)
        write_result(store, organization_id, now, correlation_id, allocated, set_id, payload)
        store.insert_idempotency(
          id: allocated[:idem], created_at: iso(now), organization_id:, command_type: COMMAND_TYPE,
          target_type: TARGET_TYPE, target_id: set_id, key_digest:, request_sha256:,
          command_execution_id: allocated[:execution], command_result_id: allocated[:result],
          retain_until: iso(now + IDEMPOTENCY_RETENTION_SECONDS)
        )

        Platform::CommandResult.success(
          result_id: allocated[:result], command_type: COMMAND_TYPE, audit_record_id: allocated[:audit],
          correlation_id:, payload: payload.transform_keys(&:to_sym)
        )
      end

      def approval_payload(row, package)
        {
          "measurement_set_row_id" => row["id"],
          "measurement_set_id" => row["measurement_set_id"],
          "measurement_set_version" => row["measurement_set_version"],
          "measurement_kind" => row["measurement_kind"],
          "package_sha256" => hex(row["package_sha256"]),
          "status" => row["status"],
          # NORMALIZED TO A STRING BECAUSE THE PAYLOAD IS HASHED. `RETURNING *` gives back whatever
          # the connection's type map decodes the column to — a `Time` here, a string elsewhere — and
          # canonical JSON refuses to encode a `Time` outright rather than guessing a format. Two
          # activations must produce the same bytes for the same facts, so the instant is written in
          # one representation at the one place that decides it.
          "activated_at" => instant(row["activated_at"]),
          "state_version" => row["state_version"].to_i,
          "owner_approval_reference" => row["owner_approval_reference"],
          # Sorted by signer key so two activations of the same package produce the same bytes.
          "signers" => MeasurementPackage::SIGNERS.sort.map do |signer|
            signature = package.dig("signatures", signer) || {}
            { "signer" => signer, "signer_identity" => signature["signer_identity"],
              "authority" => signature["authority"], "signed_at" => signature["signed_at"] }
          end
        }
      end

      # ---- refusals -----------------------------------------------------------------------

      # A refused activation still records that the release service tried and what it was told.
      # It writes NO idempotency record: a package refused today for want of a second signature
      # must be activatable tomorrow when that signature arrives, and a stored refusal keyed on the
      # unchanged bytes would replay the refusal for ever.
      def deny(store, organization_id, now, correlation_id, ids, set_id, key_digest, request_sha256, reason, detail)
        failure(store, organization_id, now, correlation_id, ids, set_id, key_digest, request_sha256, reason,
                { "outcome" => "failure", "measurement_set_row_id" => set_id,
                  "internal_reason" => reason, "detail" => Array(detail) })
      end

      def conflict(store, organization_id, now, correlation_id, ids, set_id, key_digest, request_sha256)
        failure(store, organization_id, now, correlation_id, ids, set_id, key_digest, request_sha256,
                "idempotency_conflict",
                { "outcome" => "failure", "measurement_set_row_id" => set_id,
                  "internal_reason" => "idempotency_conflict" })
      end

      # The execution row carries the REQUEST's identity even when the request is refused. Digesting
      # the refusal payload instead would make `request_sha256` describe the outcome rather than what
      # was asked, and a reader comparing two executions could not tell that they asked the same thing.
      def failure(store, organization_id, now, correlation_id, ids, set_id, key_digest, request_sha256,
                  reason, payload)
        allocated = %i[command execution audit result].to_h { |k| [k, ids.generate] }

        write_execution(store, organization_id, now, correlation_id, allocated, set_id, key_digest,
                        request_sha256, payload)
        write_audit(store, organization_id, now, correlation_id, allocated, set_id,
                    to_state: nil, outcome: "failure", reason_code: reason, payload:)
        refusal = Platform::ErrorCatalog.failure(reason, support_reference: correlation_id)
        write_result(store, organization_id, now, correlation_id, allocated, set_id, {}, failure: refusal)

        Platform::CommandResult.failure(result_id: allocated[:result], command_type: COMMAND_TYPE,
                                        failure: refusal, audit_record_id: allocated[:audit], correlation_id:)
      end

      def rebuild(store, existing)
        stored = store.load_command_result(existing["command_result_id"])
        if stored["outcome"] == "success"
          Platform::CommandResult.success(
            result_id: stored["id"], command_type: COMMAND_TYPE,
            payload: JSON.parse(stored["authorized_payload"]).transform_keys(&:to_sym),
            audit_record_id: stored["audit_record_id"], correlation_id: stored["correlation_id"],
            replayed: true
          )
        else
          Platform::CommandResult.failure(
            result_id: stored["id"], command_type: COMMAND_TYPE,
            failure: Platform::Failure.new(
              error_class: stored["error_class"], error_code: stored["error_code"],
              reason_code: stored["reason_code"], severity: stored["severity"],
              retryable: stored["retryable"] == "t" || stored["retryable"] == true,
              recovery_action: stored["recovery_action"], support_reference: stored["support_reference"]
            ),
            audit_record_id: stored["audit_record_id"], correlation_id: stored["correlation_id"], replayed: true
          )
        end
      end

      # ---- writers ------------------------------------------------------------------------

      def write_execution(store, organization_id, now, correlation_id, ids, set_id, key_digest,
                          request_sha256, payload)
        store.insert_command_execution(
          id: ids[:execution], created_at: iso(now), correlation_id:, causation_id: correlation_id,
          command_id: ids[:command], idempotency_key_digest: key_digest, command_type: COMMAND_TYPE,
          command_schema_version: COMMAND_SCHEMA_VERSION, service_identity_id: SERVICE_IDENTITY,
          organization_id:, target_type: TARGET_TYPE, target_id: set_id, action: ACTION,
          requested_at: iso(now), authorization_check_at: iso(now),
          policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
          canonical_payload: JSON.generate(canonical_payload(payload)), request_sha256:
        )
      end

      # The command's own payload, NOT the package. The approved bytes are already persisted behind
      # F-02 and named by their digest; copying key content into an unencrypted ledger column would
      # put the owner's approved query text somewhere the retention rules for that column never
      # described.
      def canonical_payload(payload)
        payload.slice("measurement_set_row_id", "measurement_set_id", "measurement_set_version",
                      "measurement_kind", "package_sha256")
      end

      def write_audit(store, organization_id, now, correlation_id, ids, set_id,
                      to_state:, outcome:, reason_code:, payload:)
        store.insert_audit(
          id: ids[:audit], occurred_at: iso(now), partition_month: month(now), organization_id:,
          service_identity_id: SERVICE_IDENTITY, correlation_id:, causation_id: correlation_id,
          command_id: ids[:command], entity_type: TARGET_TYPE, entity_id: set_id,
          to_state:, outcome:, reason_code:, payload: JSON.generate(payload),
          content_sha256: Platform::CanonicalJson.digest(payload)
        )
      end

      def write_result(store, organization_id, now, correlation_id, ids, set_id, payload, failure: nil)
        store.insert_command_result(
          id: ids[:result], created_at: iso(now), correlation_id:, causation_id: correlation_id,
          command_id: ids[:command], command_execution_id: ids[:execution],
          outcome: failure ? "failure" : "success", organization_id:,
          service_identity_id: SERVICE_IDENTITY, completed_at: iso(now), authorization_check_at: iso(now),
          target_refs: JSON.generate(failure ? {} : { TARGET_TYPE => set_id }),
          governing_policy_versions: JSON.generate({ "permission_baseline" => POLICY_VERSION }),
          failure:, authorized_payload: JSON.generate(payload), audit_record_id: ids[:audit]
        )
      end

      # The request identity a replay must reproduce exactly. It names the digest rather than the
      # package, for the same reason `canonical_payload` does.
      def request_hash(organization_id, set_id, idempotency_key)
        Platform::CanonicalJson.digest({
                                         "action" => ACTION, "command_type" => COMMAND_TYPE,
                                         "command_schema_version" => COMMAND_SCHEMA_VERSION,
                                         "service_identity_id" => SERVICE_IDENTITY,
                                         "organization_id" => organization_id,
                                         "target_type" => TARGET_TYPE, "target_id" => set_id,
                                         "policy_versions" => [POLICY_VERSION],
                                         "package_sha256" => idempotency_key
                                       })
      end

      def hex(value) = value.to_s.sub(/\A\\x/, "")
      def instant(value) = value.respond_to?(:getutc) ? iso(value) : value&.to_s
      def iso(time) = time&.getutc&.iso8601(6)
      def month(time) = Date.new(time.year, time.month, 1).iso8601
    end
  end
end
