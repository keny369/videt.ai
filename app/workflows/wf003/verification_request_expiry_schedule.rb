# frozen_string_literal: true

module Workflows
  module Wf003
    # The canonical creation point of a Verification Request's 24-hour expiry timer:
    # the transaction that issues the challenge (SCORE_EVIDENCE_MODEL.md: "expires_at_utc,
    # exactly 24 hours after issued_at_utc"; CAP-005 Failure Condition: "an unresolved
    # request expires after exactly 24 hours").
    #
    # It is the Invitation/Role-Assignment expiry pattern applied to a third action
    # kind, using the same ScheduledAction platform (F-04) rather than a second
    # scheduler: `verification_request_expire` is already in the ratified catalogue
    # and maps to `ExpireVerificationRequest`. Scheduling happens on the issuing
    # transaction's connection, so the Request and its timer commit or roll back
    # together. Consuming F-04 through its frozen surfaces only, this limb schedules
    # the timer; the `ExpireVerificationRequest` handler that runs when it is due is a
    # later limb.
    module VerificationRequestExpirySchedule
      module_function

      ACTION_KIND = "verification_request_expire"
      ACTION_SCHEMA_VERSION = "1.0"
      TARGET_TYPE = "verification_request"

      def schedule(pg:, organization_id:, project_id:, verification_request_id:, expires_at:, now:,
                   correlation_id:, causation_id: nil, command_id: nil, state_version: 0, schedule_generation: 1)
        Platform::ScheduledActions::Store.new(pg).create(
          id: Platform::Ids.system.generate, action_kind: ACTION_KIND,
          action_schema_version: ACTION_SCHEMA_VERSION, organization_id:, project_id:,
          target_type: TARGET_TYPE, target_id: verification_request_id,
          product_generation: state_version, schedule_generation:,
          due_at: expires_at, now:, correlation_id:, causation_id: causation_id || correlation_id,
          command_id:, executing_service_identity_id: Platform::ServiceIdentity.scheduled_action_executor
        )[:id]
      end
    end
  end
end
