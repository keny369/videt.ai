# frozen_string_literal: true

module Workflows
  module Wf001
    module Commands
      # The logical command for the invitation-acceptance branch of WF-001
      # (WORKFLOW_SPECIFICATIONS.md § invitation acceptance). The recipient submits
      # the opaque invitation reference (the 32 random bytes; F1 stores only its
      # SHA-256), a fresh matching Identity Validation Receipt, and the exact
      # offered grant tuple it is accepting; acceptance validates that tuple against
      # the current Invitation (a changed tuple is invitation_role_scope_changed).
      # `supplied_account_id` is the optional Account the recipient names; if it
      # does not equal the matching same-Organization identity Account, acceptance
      # changes nothing (account_identity_conflict). Immutable, canonicalized values.
      AcceptInvitation = Data.define(:command_id, :idempotency_key, :schema_version,
                                     :invitation_reference, :receipt_digest,
                                     :accepted_canonical_role, :accepted_permission_mode,
                                     :accepted_persona, :accepted_scope_sha256,
                                     :supplied_account_id, :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class AcceptInvitation
        TYPE = "wf001.accept_invitation"

        def command_type = TYPE
      end
    end
  end
end
