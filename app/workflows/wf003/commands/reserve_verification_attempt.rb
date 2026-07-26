# frozen_string_literal: true

module Workflows
  module Wf003
    module Commands
      # WF-003 ReserveVerificationAttempt — the on-demand path of the canonical WF-003
      # command vocabulary (APPLICATION_LAYER.md § WF-003, DECISIONS.md ADR-024 DEF-1;
      # SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And Evidence; CAP-005 MTX-028;
      # contracts/S-05.json). An authorized Organization actor requests one on-demand
      # observation of a pending Verification Request: the accepted command reserves the
      # next attempt slot atomically (assigns the attempt ID, increments the on-demand
      # and total attempt counts and stores the in-progress marker) before any provider
      # call, so concurrent commands cannot reserve the same slot.
      #
      # The caller supplies only semantic input (request_schema on-demand row): the
      # Session it acts through, the intended Organization (checked against the Session,
      # never trusted as authority), the target Project, the Verification Request and
      # its expected state version. Everything else — the Source, the attempt number,
      # the reservation instant — is DERIVED from the Request under the per-Request
      # lock, never supplied.
      #
      # This limb only RESERVES an attempt. It does not run the DNS/HTTP observation,
      # produce Evidence, emit `SourceVerificationObserved`, complete or quarantine the
      # attempt, or transition the Request or Source; each is a later WF-003 limb.
      ReserveVerificationAttempt = Data.define(
        :command_id, :idempotency_key, :schema_version, :session_id, :organization_id,
        :project_id, :verification_request_id, :expected_state_version, :requested_at_utc
      )

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class ReserveVerificationAttempt
        TYPE = "wf003.reserve_verification_attempt"

        def command_type = TYPE
      end
    end
  end
end
