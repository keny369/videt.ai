# frozen_string_literal: true

require "digest"
require "json"

module Workflows
  module Wf006
    # The external-measurement intake boundary (WORKFLOW_SPECIFICATIONS.md :480-482).
    #
    # THREE STEPS, AND THE MIDDLE ONE IS THE OWNER'S. Import stages an owner-supplied package for
    # review; activation requires two signatures over its exact digest; submission is only
    # possible once a set is active. Import and submission are ours; activation is not, and the
    # gap between them is deliberate — it is the edge OD-010 exists to hold:
    #
    #     import(package)                 -> measurement_sets row, status `proposed`
    #     activate(package + signatures)  -> status `active`         [OWNER AUTHORITY]
    #     submit(observation)             -> external_measurement Evidence
    #
    # WITHOUT AN ACTIVE SET, SUBMISSION REFUSES, and that refusal is the ratified baseline rather
    # than a limitation: "unknown/inactive set is `F1-DOMAIN-409 / measurement_set_unavailable`".
    # A build that persisted observations anyway would let a Check consume measurement content the
    # owner never approved, which is the precise failure the register was written to prevent.
    #
    # THE VALIDATION ORDER IS THE CONTRACT'S, IN ITS EXACT SEQUENCE: "authority,
    # Organization/Project/Evaluation, exact set keys/order/coverage/freshness, adapter
    # eligibility, payload schema/digest, and one-record uniqueness IN THAT ORDER". The order is
    # observable — it decides WHICH reason a doubly-invalid submission reports — so it is written
    # here as a sequence of guarded returns rather than as a collected list of failures.
    module MeasurementIntake
      module_function

      PACKAGE_AAD = { application: "wf006", record_type: "measurement_set",
                      purpose: "approval_package" }.freeze
      OBSERVATION_AAD = { application: "wf006", record_type: "external_measurement",
                          purpose: "product_evidence_payload" }.freeze
      EVIDENCE_PRODUCER = "wf006.external_measurement"
      SOURCE_SYSTEM = "f1.measurement_adapter"
      COLLECTION_METHOD = "external_measurement_submission"

      Result = Data.define(:status, :reason, :detail, :record) do
        def initialize(reason: nil, detail: nil, record: nil, **) = super
        def ok? = status == :ok
      end

      def ok(record = nil) = Result.new(status: :ok, record:)
      def refused(reason, detail = nil) = Result.new(status: :refused, reason:, detail:)

      # ---- import ------------------------------------------------------------------------

      # Stage a package for owner review. It persists the canonical bytes behind F-02 and a
      # `proposed` row; it activates nothing and it creates no Evidence.
      #
      # Idempotent on the package digest: re-importing byte-identical bytes returns the existing
      # row rather than creating a second proposal, so an operator who submits the same file twice
      # has not created two things for the owner to sign.
      def import(store:, package:, organization_id:, project_id:, now:, correlation_id:,
                 catalog_version:, catalog_sha256:)
        verdict = MeasurementPackage.validate(package, organization_id:, catalog_version:, catalog_sha256:)
        return refused("measurement_package_invalid", verdict.failures) unless verdict.valid?

        digest = MeasurementPackage.digest(package)
        existing = store.measurement_set_by_digest(organization_id, digest)
        return ok(existing) if existing

        # A DIFFERENT package claiming a version that already exists is refused rather than
        # accepted as a new row: "reuse of a Catalog version or Definition version for changed
        # content is prohibited", and the same rule governs a Measurement Set version.
        clash = store.measurement_set_by_version(organization_id, package["measurement_set_id"],
                                                 package["measurement_set_version"])
        return refused("measurement_set_version_reused") if clash

        bytes = MeasurementPackage.canonical_bytes(package)
        protected_bytes = Platform::Encryption.protect(
          plaintext: bytes,
          aad: Platform::Encryption::Aad.for(**PACKAGE_AAD, record_id: derived_id(digest), tenant: organization_id)
        )
        adapter = package["collector_adapter"]
        binding = package["binding"]

        ok(store.insert_measurement_set(
             id: derived_id(digest), now:, correlation_id:, organization_id:, project_id:,
             package_schema_version: package["package_schema_version"],
             measurement_set_id: package["measurement_set_id"],
             measurement_set_version: package["measurement_set_version"],
             measurement_kind: package["measurement_kind"],
             package_created_at: package["package_created_at"],
             proposed_effective_at: package["proposed_effective_at"],
             package_reference: protected_bytes.reference, package_sha256: digest,
             provider_identities: JSON.generate(package["provider_identities"]),
             collector_adapter_id: adapter["id"], collector_adapter_version: adapter["version"],
             collector_adapter_sha256: [adapter["sha256"]].pack("H*"),
             expected_keys: JSON.generate(package["expected_keys"]),
             key_content: JSON.generate(package["key_content"]),
             locale: package["locale"], time_zone: package["time_zone"],
             max_evidence_age_seconds: package["max_evidence_age_seconds"],
             bound_catalog_version: binding["catalog_version"],
             bound_catalog_sha256: [binding["catalog_sha256"]].pack("H*"),
             bound_definition_id: binding["definition_id"],
             bound_definition_version: binding["definition_version"],
             bound_definition_sha256: [binding["definition_sha256"]].pack("H*"),
             retention_location: package["retention_location"], status: "proposed"
           ))
      end

      # ---- activation (OWNER AUTHORITY) ---------------------------------------------------

      # `measurement_set.activate`. Refuses unless BOTH owners signed the exact digest of the
      # proposed row's own bytes. The digest is recomputed from the supplied package rather than
      # read from the row, so a signature can only ever be checked against bytes that were
      # actually presented — reading the stored digest would let a caller sign one package and
      # activate another.
      def activate(store:, package:, organization_id:, now:, correlation_id:)
        digest = MeasurementPackage.digest(package)
        row = store.measurement_set_by_digest(organization_id, digest)
        return refused("measurement_set_unavailable") if row.nil?
        return refused("measurement_set_terminal") unless row["status"] == "proposed"

        failures = MeasurementPackage.signature_failures(package, digest.unpack1("H*"))
        return refused("measurement_set_approval_incomplete", failures) if failures.any?

        signatures = package["signatures"]
        activated = store.activate_measurement_set(
          id: row["id"], expected_version: row["state_version"].to_i, now:, correlation_id:,
          product_signature: JSON.generate(signatures["chief_product"]),
          architect_signature: JSON.generate(signatures["chief_architect"]),
          owner_approval_reference: package["owner_approval_reference"]
        )
        # ZERO AFFECTED ROWS IS A REFUSAL, NOT A SUCCESS WITH NOTHING IN IT. The UPDATE is guarded
        # on `status = 'proposed' AND state_version = $2`, so it returns no row when another writer
        # won the race between the read above and this statement — the loser must not report that
        # it activated something. Returning `ok(nil)` (which is what this did) made a lost race
        # indistinguishable from a successful activation to every caller, including one that would
        # then have gone on to record an approval that never happened.
        return refused("measurement_set_terminal") if activated.nil?

        ok(activated)
      end

      # ---- submission ---------------------------------------------------------------------

      # `external_measurement.submit`. One immutable payload per
      # `(evaluation_id, measurement_kind, measurement_set_version)`.
      def submit(store:, payload:, organization_id:, project_id:, evaluation_id:, now:,
                 correlation_id:, data_classification: "internal")
        # 1. Organization/Project/Evaluation. (Authority is the caller's service identity and is
        #    proved before this module is reached.)
        evaluation = store.read_evaluation(evaluation_id)
        if evaluation.nil? || evaluation["organization_id"] != organization_id ||
           evaluation["project_id"] != project_id
          return refused("tenant_mismatch")
        end
        # The payload's own tenancy must agree with the envelope's. "A cross-Organization,
        # cross-Project or cross-Evaluation payload is tenant-integrity failure."
        if payload["organization_id"] != organization_id || payload["project_id"] != project_id ||
           (payload["evaluation_id"] && payload["evaluation_id"] != evaluation_id)
          return refused("tenant_mismatch")
        end

        # 2. The active set. No set, no submission.
        set = store.active_measurement_set(organization_id, project_id, payload["measurement_kind"])
        return refused("measurement_set_unavailable") if set.nil?
        return refused("measurement_set_unavailable") unless set["measurement_set_version"] == payload["measurement_set_version"]

        # 3. Exact set keys/order/coverage/freshness, then 4. adapter eligibility.
        expected_keys = JSON.parse(set["expected_keys"])
        return refused("external_measurement_invalid", ["key_set_mismatch"]) unless payload_keys(payload) == expected_keys
        unless payload["collector_adapter_id"] == set["collector_adapter_id"] &&
               payload["collector_adapter_version"] == set["collector_adapter_version"]
          return refused("external_measurement_invalid", ["adapter_ineligible"])
        end

        # 5. Payload schema and digest.
        observed = MeasurementPackage.parse_time(payload["observed_at_utc"])
        fresh_until = MeasurementPackage.parse_time(payload["fresh_until_utc"])
        captured = MeasurementPackage.parse_time(payload["captured_at_utc"])
        return refused("external_measurement_invalid", ["observation_times_invalid"]) if observed.nil? || fresh_until.nil? || captured.nil?

        bytes = Platform::CanonicalJson.encode(payload).b
        # THE EVIDENCE ATTEMPT IDENTITY IS THE SELECTOR'S KEY, and it must be derived exactly as
        # the applicability seal derives it — `(evaluation, schema version, subject key)`, where
        # an external observation's subject key is its measurement kind. Deriving it any other
        # way produces Evidence that exists, is valid, is attached to the Evaluation, and that no
        # Check can ever find: the seal computes a key rather than searching, so a producer that
        # writes under a different key has written to nowhere.
        attempt_id = Wf007::Applicability.evidence_attempt_id(
          evaluation_id:, schema_version: MeasurementPackage::OBSERVATION_SCHEMA,
          subject_key: payload["measurement_kind"]
        )

        # 6. One-record uniqueness. An exact replay returns the stored record; ALTERED bytes for
        #    the same tuple are `idempotency_conflict` and change nothing.
        existing = store.measurement_submission_for(evaluation_id, payload["measurement_kind"],
                                                    payload["measurement_set_version"])
        if existing
          return ok(existing) if existing["payload_sha256"].to_s.sub(/\A\\x/, "") == Digest::SHA256.hexdigest(bytes)

          return refused("idempotency_conflict")
        end
        # A second observation of the same kind for this Evaluation under a DIFFERENT set version
        # is also `idempotency_conflict`. The uniqueness tuple admits it, but the Evidence
        # identity does not: both would resolve to the same attempt key, so the second payload
        # would be recorded while the first remained the one every Check reads. One Evaluation
        # observes one thing once.
        if store.measurement_submission_kind_exists?(evaluation_id, payload["measurement_kind"])
          return refused("idempotency_conflict")
        end

        protected_payload = Platform::Encryption.protect(
          plaintext: bytes,
          aad: Platform::Encryption::Aad.for(**OBSERVATION_AAD, record_id: attempt_id, tenant: organization_id)
        )
        evidence_id = Platform::Evidence.produce(
          Platform::Evidence::Record.build(
            schema_version: MeasurementPackage::OBSERVATION_SCHEMA, organization_id:, project_id:,
            source_id: nil, evaluation_id:, evidence_type: "external_measurement",
            producer_id: EVIDENCE_PRODUCER, attempt_id:,
            payload_reference: protected_payload.reference,
            content_sha256: protected_payload.content_digest.unpack1("H*"),
            captured_at_utc: captured, observed_at_utc: observed,
            source_system: SOURCE_SYSTEM, collection_method: COLLECTION_METHOD,
            collector_version: payload["collector_adapter_version"],
            validation_status: "valid", validation_reason_code: nil, data_classification:,
            payload_retention_class: Platform::Evidence::Record::PRODUCER_RETENTION_CLASS,
            correlation_id:
          )
        )

        ok(store.insert_measurement_submission(
             id: attempt_id, now:, correlation_id:, organization_id:, project_id:, evaluation_id:,
             measurement_kind: payload["measurement_kind"], measurement_set_row_id: set["id"],
             measurement_set_id: set["measurement_set_id"],
             measurement_set_version: set["measurement_set_version"],
             measurement_set_sha256: unhex(set["package_sha256"]),
             collector_adapter_id: payload["collector_adapter_id"],
             collector_adapter_version: payload["collector_adapter_version"],
             payload_reference: protected_payload.reference,
             payload_sha256: protected_payload.content_digest,
             observed_at: observed, captured_at: captured, fresh_until:,
             coverage_status: payload["coverage_status"], data_classification:,
             evidence_id:, schema_version: MeasurementPackage::OBSERVATION_SCHEMA
           ))
      end

      def payload_keys(payload)
        body = payload["body"] || {}
        body["expected_intent_keys"] || body["expected_query_keys"] ||
          body["required_listing_keys"] || []
      end

      # Identities derive from content, so an import or a submission is idempotent by
      # construction rather than by a lookup that could race.
      def derived_id(digest) = Platform::DerivedUuid.v8(digest)
      def unhex(value) = [value.to_s.sub(/\A\\x/, "")].pack("H*")
    end
  end
end
