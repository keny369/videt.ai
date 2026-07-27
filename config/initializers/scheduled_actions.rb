# frozen_string_literal: true

# The closed ScheduledAction dispatch table for this build.
#
# Registration is explicit and validated: `Registry#register` refuses a kind
# outside the ratified catalogue and refuses an operation that disagrees with the
# ratified `scheduled_action_dispatch` mapping (BACKGROUND_PROCESSING.md
# :399-421). An action kind absent from this file has no handler, so the worker
# quarantines it as `scheduled_work_mapping_mismatch` and performs no product
# work — the baseline is fail-closed, and adding a kind is a deliberate change
# here plus a registered handler, never reflection over the action row.
#
# `to_prepare` so a development reload rebinds the reloadable handler constants.
Rails.application.config.to_prepare do
  registry = Platform::ScheduledActions::Registry.default
  registry.reset!
  registry.register(
    action_kind: "invitation_expire",
    action_schema_version: "1.0",
    operation: "ExpireInvitation",
    handler: Workflows::Wf001::Handlers::ExpireInvitation,
    command: Workflows::Wf001::Commands::ExpireInvitation
  )
  registry.register(
    action_kind: "role_assignment_expire",
    action_schema_version: "1.0",
    operation: "ExpireRoleAssignment",
    handler: Workflows::Wf013::Handlers::ExpireRoleAssignment,
    command: Workflows::Wf013::Commands::ExpireRoleAssignment
  )
  registry.register(
    action_kind: "verification_request_expire",
    action_schema_version: "1.0",
    operation: "ExpireVerificationRequest",
    handler: Workflows::Wf003::Handlers::ExpireVerificationRequest,
    command: Workflows::Wf003::Commands::ExpireVerificationRequest
  )
  registry.register(
    action_kind: "verification_observation_slot",
    action_schema_version: "1.0",
    operation: "ObserveAutomatedSlot",
    handler: Workflows::Wf003::Handlers::ObserveAutomatedSlot,
    command: Workflows::Wf003::Commands::ObserveAutomatedSlot
  )
  registry.register(
    action_kind: "source_scope_request_expire",
    action_schema_version: "1.0",
    operation: "ExpireSourceScopeChange",
    handler: Workflows::Wf004::Handlers::ExpireSourceScopeChange,
    command: Workflows::Wf004::Commands::ExpireSourceScopeChange
  )
end
