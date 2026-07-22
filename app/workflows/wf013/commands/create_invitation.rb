# frozen_string_literal: true

module Workflows
  module Wf013
    module Commands
      # WF-013 CreateInvitation (WORKFLOW_SPECIFICATIONS.md :242, :244;
      # contracts/S-23.json MTX-038). An authenticated Organization actor holding
      # `invitation.create` offers a role/mode/persona/scope grant to a target
      # email. Authority derives from `session_id` — the acting Account and
      # Organization are resolved FROM the Session, never from caller input.
      #
      # The offer alone decides the branch: a grant containing no protected
      # permission is created directly active, one containing a protected
      # permission starts pending approval and grants nothing (:242). The caller
      # does not choose.
      #
      # `intended_assignment_expires_at` is the ":240 intended Role Assignment
      # expiry when required" and, like every other offer field, is part of the
      # open-invitation uniqueness preimage.
      CreateInvitation = Data.define(:command_id, :idempotency_key, :schema_version, :session_id,
                                     :target_email, :target_identity_issuer_key, :target_identity_subject,
                                     :canonical_role, :permission_mode, :persona, :scope_sha256,
                                     :intended_assignment_expires_at, :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class CreateInvitation
        TYPE = "wf013.create_invitation"

        def command_type = TYPE
      end
    end
  end
end
