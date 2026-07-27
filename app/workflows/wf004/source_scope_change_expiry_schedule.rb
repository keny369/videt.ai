# frozen_string_literal: true

module Workflows
  module Wf004
    # The canonical creation point of a Source Scope Change Request's 24-hour expiry
    # timer (WORKFLOW_SPECIFICATIONS.md § Source Scope Change Contract :414:
    # "`due_at_utc = requested_at_utc + 24 hours`"; :419: at exactly due_at the expiry
    # transition wins).
    #
    # It is the Verification-Request/Invitation/Role-Assignment expiry pattern applied
    # to the source-scope-change action kind, using the same F-04 ScheduledAction
    # platform rather than a second scheduler: `source_scope_request_expire` is already
    # in the ratified catalogue and maps to `ExpireSourceScopeChange`. Scheduling
    # happens on the proposing transaction's connection, so the pending request and its
    # timer commit or roll back together. Consuming F-04 through its frozen surfaces
    # only, this limb SCHEDULES the timer; the `ExpireSourceScopeChange` handler that
    # runs when it is due is S-06-005.
    module SourceScopeChangeExpirySchedule
      module_function

      ACTION_KIND = "source_scope_request_expire"
      ACTION_SCHEMA_VERSION = "1.0"
      TARGET_TYPE = "source_scope_change_request"

      def schedule(pg:, organization_id:, project_id:, request_id:, due_at:, now:,
                   correlation_id:, causation_id: nil, command_id: nil, state_version: 0, schedule_generation: 1)
        Platform::ScheduledActions::Store.new(pg).create(
          id: Platform::Ids.system.generate, action_kind: ACTION_KIND,
          action_schema_version: ACTION_SCHEMA_VERSION, organization_id:, project_id:,
          target_type: TARGET_TYPE, target_id: request_id,
          product_generation: state_version, schedule_generation:,
          due_at:, now:, correlation_id:, causation_id: causation_id || correlation_id,
          command_id:, executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor
        )[:id]
      end
    end
  end
end
