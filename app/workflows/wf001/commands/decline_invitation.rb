# frozen_string_literal: true

module Workflows
  module Wf001
    module Commands
      # The logical command for the invitation-decline branch of WF-001
      # (WORKFLOW_SPECIFICATIONS.md § invitation decline). The intended recipient
      # declines an active Invitation with its opaque reference (32 random bytes; F1
      # stores only its SHA-256), the expected Invitation state version, a fresh
      # matching Identity Validation Receipt (purpose invitation_response), and an
      # optional reason that is null or 1-2,000 trimmed Unicode scalar values.
      # Authorized by the same invitation-bound recipient capability as acceptance,
      # not a role permission. Immutable, canonicalized values only.
      DeclineInvitation = Data.define(:command_id, :idempotency_key, :schema_version,
                                      :invitation_reference, :receipt_digest,
                                      :expected_state_version, :reason, :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class DeclineInvitation
        TYPE = "wf001.decline_invitation"

        def command_type = TYPE
      end
    end
  end
end
