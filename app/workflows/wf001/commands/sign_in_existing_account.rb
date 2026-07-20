# frozen_string_literal: true

module Workflows
  module Wf001
    module Commands
      # The logical command for the existing-account sign-in branch of WF-001
      # (WORKFLOW_SPECIFICATIONS.md § existing-account sign-in). The approved
      # identity service is the command service identity. The Organization is
      # supplied explicitly and never selected implicitly; the principal is derived
      # from the receipt the digest resolves. Immutable, canonicalized values only.
      #
      # `return_target` (the optional logical destination the caller requests) is
      # not part of this thin slice: authorized-target resolution is deferred, so
      # the destination is only organization_home or access_unavailable.
      SignInExistingAccount = Data.define(:command_id, :idempotency_key, :schema_version,
                                          :organization_id, :receipt_digest, :requested_at_utc)

      # Reopened rather than defined in a Data.define block so TYPE is a constant of
      # this class, not of the enclosing Commands module (a block passed to
      # Data.define assigns constants in its lexical scope, not on the class).
      class SignInExistingAccount
        TYPE = "wf001.sign_in_existing_account"

        def command_type = TYPE
      end
    end
  end
end
