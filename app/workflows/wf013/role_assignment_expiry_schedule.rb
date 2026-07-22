# frozen_string_literal: true

module Workflows
  module Wf013
    # The canonical creation point of a Role Assignment's expiry timer: the
    # transaction that makes the Assignment ACTIVE (:316 "Its active expiry is
    # mandatory and no later than 30 days after effectiveness" for a protected
    # Assignment; a nonprotected one may have none).
    #
    # It is the Invitation expiry pattern applied to a second action kind, using
    # the same ScheduledAction platform rather than a second scheduler:
    # `role_assignment_expire` is already in the ratified 53-kind catalogue and
    # maps to `ExpireRoleAssignment`. Scheduling happens on the activating
    # transaction's connection, so the Assignment and its timer commit or roll
    # back together.
    module RoleAssignmentExpirySchedule
      module_function

      ACTION_KIND = "role_assignment_expire"
      ACTION_SCHEMA_VERSION = "1.0"
      TARGET_TYPE = "role_assignment"

      def schedule(pg:, organization_id:, role_assignment_id:, expires_at:, now:, state_version: 0,
                   correlation_id:, causation_id: nil, command_id: nil, schedule_generation: 1)
        Platform::ScheduledActions::Store.new(pg).create(
          id: Platform::Ids.system.generate, action_kind: ACTION_KIND,
          action_schema_version: ACTION_SCHEMA_VERSION, organization_id:,
          target_type: TARGET_TYPE, target_id: role_assignment_id,
          product_generation: state_version, schedule_generation:,
          due_at: expires_at, now:, correlation_id:, causation_id: causation_id || correlation_id,
          command_id:, executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor
        )[:id]
      end
    end
  end
end
