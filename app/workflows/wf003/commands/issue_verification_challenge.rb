# frozen_string_literal: true

module Workflows
  module Wf003
    module Commands
      # WF-003 IssueVerificationChallenge (APPLICATION_LAYER.md § WF-003, the
      # canonical WF-003 command vocabulary per DECISIONS.md ADR-024 DEF-1;
      # SCORE_EVIDENCE_MODEL.md § Ownership-Verification Evidence Contract; CAP-005
      # MTX-028; contracts/S-05.json). The command that opens ownership verification
      # for a proposed Source: it creates exactly one pending Verification Request
      # and issues one challenge token.
      #
      # The caller supplies only semantic input: the Session it acts through, the
      # intended Organization (checked against the Session, never trusted as
      # authority), the target Project and Source, the Source's expected state
      # version, the verification `method` (`dns_txt` or `http_file`), and the
      # transport envelope. The request initiator, canonical host, challenge material
      # and every issuance instant are DERIVED from the command, the Source and the
      # authorization decision — never supplied — so every Request carries proof of
      # the decision that created it and the plaintext token exists only in the
      # authorized response.
      #
      # This limb only ISSUES a challenge. It never observes DNS/HTTP, reserves or
      # completes an observation, expires, cancels or fails a Request, or transitions
      # the Source; each is a separate WF-003 command or scheduled job in a later
      # slice.
      IssueVerificationChallenge = Data.define(
        :command_id, :idempotency_key, :schema_version, :session_id, :organization_id,
        :project_id, :source_id, :method, :expected_state_version, :requested_at_utc
      )

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class IssueVerificationChallenge
        TYPE = "wf003.issue_verification_challenge"

        def command_type = TYPE
      end
    end
  end
end
