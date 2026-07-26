# frozen_string_literal: true

module Workflows
  module Wf003
    module Commands
      # WF-003 CompleteVerificationAttempt — the service-executed observation-recording
      # limb of the canonical WF-003 command vocabulary (APPLICATION_LAYER.md § WF-003,
      # DECISIONS.md ADR-024 DEF-1; SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And
      # Evidence; CAP-005 MTX-028/051/056; contracts/S-05.json). It runs a reserved
      # attempt's observation and records exactly one restricted verification_observation
      # Evidence + SourceVerificationObserved, atomically.
      #
      # Service-executed: authority was established at Request creation and at on-demand
      # acceptance (MTX-051 permission_checks — the transition is a consequence of a
      # matched predicate, not of an actor's permission), so there is no Session and no
      # human actor. Scalar identifiers only; the handler reloads every product value
      # from PostgreSQL and reveals the challenge token behind F-02.
      CompleteVerificationAttempt = Data.define(:command_id, :schema_version, :organization_id,
                                                :verification_request_id, :verification_attempt_id,
                                                :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class CompleteVerificationAttempt
        TYPE = "wf003.complete_verification_attempt"

        def command_type = TYPE
        # Idempotent by the reserved attempt identity (SCORE_EVIDENCE_MODEL.md § Attempts:
        # "Observation completion is idempotent by reserved slot/attempt identity").
        def idempotency_key = verification_attempt_id
      end
    end
  end
end
