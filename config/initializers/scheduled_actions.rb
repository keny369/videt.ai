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
end
