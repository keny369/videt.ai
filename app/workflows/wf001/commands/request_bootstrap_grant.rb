# frozen_string_literal: true

module Workflows
  module Wf001
    module Commands
      # The logical command for the grant-issuance branch of WF-001. The principal
      # is never client-supplied: it is derived from the receipt the digest
      # resolves. Immutable, canonicalized values only.
      RequestBootstrapGrant = Data.define(:command_id, :idempotency_key, :schema_version,
                                          :receipt_digest, :requested_at_utc) do
        TYPE = "wf001.request_bootstrap_grant"

        def command_type = TYPE
      end
    end
  end
end
