# frozen_string_literal: true

module Workflows
  module Wf001
    module Commands
      # The logical command for the WF-001 timed Invitation expiry
      # (WORKFLOW_SPECIFICATIONS.md :242 "Active expiry is exactly seven days after
      # activation, and at equality expiry wins over acceptance or decline";
      # APPLICATION_LAYER.md :371 and contracts/S-01.json — `ExpireInvitation` is a
      # service-only ScheduledAction transition, not a principal command;
      # BACKGROUND_PROCESSING.md :405 `invitation_expire` -> `ExpireInvitation`).
      #
      # It is constructed only from a claimed ScheduledAction, never from a request:
      # there is no receipt, no Session, no caller-supplied Organization and no
      # caller-supplied expected state version. Every field is a scalar identifier
      # copied from the action (BACKGROUND_PROCESSING.md :42), and the handler
      # reloads all product state from PostgreSQL under the action's Organization
      # context.
      #
      # `action_identity_sha256` is the action's immutable identity digest. It is
      # this command's idempotency key, which is what makes the expiry idempotent
      # independently of scheduler redelivery: however many times the transport
      # delivers the action, every delivery carries the same key and the second
      # returns the stored result.
      ExpireInvitation = Data.define(:command_id, :schema_version, :organization_id,
                                     :target_type, :invitation_id, :due_at, :action_id,
                                     :action_identity_sha256, :requested_at_utc)

      # Reopened so TYPE is a constant of this class, not the enclosing module.
      class ExpireInvitation
        TYPE = "wf001.expire_invitation"

        # The Registry's construction interface. `action.target_type` is validated
        # by the handler against its own TARGET_TYPE, so a misrouted action fails
        # closed rather than expiring an unrelated row.
        def self.from_scheduled_action(action:, command_id:, requested_at_utc:)
          new(command_id:, schema_version: action.action_schema_version,
              organization_id: action.organization_id, target_type: action.target_type,
              invitation_id: action.target_id, due_at: action.due_at, action_id: action.id,
              action_identity_sha256: action.identity_sha256, requested_at_utc:)
        end

        def command_type = TYPE
        def idempotency_key = action_identity_sha256
      end
    end
  end
end
