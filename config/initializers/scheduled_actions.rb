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
  # `crawl_dispatch` is a SPECIALIZED work type (`crawl_orchestrate`, BACKGROUND_PROCESSING.md
  # :197), so it is absent from the generic `scheduled_action_dispatch` operation table and the
  # registry's operation cross-check does not apply; :377 fixes its permitted operations to
  # StartCrawl / CompleteCrawl / FailCrawl / CancelCrawl "selected solely from persisted Crawl
  # state". S-07-003 registers the start; the three terminal operations are later tranches.
  registry.register(
    action_kind: "crawl_dispatch",
    action_schema_version: "1.0",
    operation: "StartCrawl",
    handler: Workflows::Wf005::Handlers::StartCrawl,
    command: Workflows::Wf005::Commands::StartCrawl
  )
  registry.register(
    action_kind: "crawl_fetch_due",
    action_schema_version: "1.0",
    operation: "RecordFetchAttempt",
    handler: Workflows::Wf005::Handlers::RecordFetchAttempt,
    command: Workflows::Wf005::Commands::RecordFetchAttempt
  )
  # The terminal checkpoint (S-07-009). Registered as `CompleteCrawl` because that is the operation
  # this kind's job performs when the run has anything to show for itself; :377 lets the SAME job
  # select `FailCrawl` instead "solely from persisted Crawl/deadline state", which the handler does
  # and which its audit record and event both name. `CancelCrawl` is deliberately not here: it is an
  # actor command with its own permission and route (API_CONTRACTS.md :279), and :458 settles a
  # cancellation by order of commit rather than at this checkpoint.
  # The ingestion limb (S-07-010). `ingestion_attempt_due` is a SPECIALIZED work type (`ingest`,
  # BACKGROUND_PROCESSING.md :200), so it is absent from the generic `scheduled_action_dispatch`
  # operation table and the registry's operation cross-check does not apply. One operation only:
  # :466 gives an ingestion attempt a single execution path, and its retry is another delivery of the
  # same kind rather than a different operation.
  registry.register(
    action_kind: "ingestion_attempt_due",
    action_schema_version: "1.0",
    operation: "RunIngestionJob",
    handler: Workflows::Wf005::Handlers::RunIngestionJob,
    command: Workflows::Wf005::Commands::RunIngestionJob
  )
  registry.register(
    action_kind: "crawl_terminal_deadline",
    action_schema_version: "1.0",
    operation: "CompleteCrawl",
    handler: Workflows::Wf005::Handlers::CompleteCrawl,
    command: Workflows::Wf005::Commands::CompleteCrawl
  )
  # The Evaluation stage chain. `evaluation_stage_advance` is a SPECIALIZED work type whose
  # cell in the generic `scheduled_action_dispatch` table is deliberately blank because
  # :245 fixes its work type from the Evaluation stage registry instead, so the registry's
  # operation cross-check does not apply.
  #
  # ONE KIND, ONE REGISTERED PAIR, TWO WORKFLOWS. The ratified catalogue gives the whole
  # chain one kind, and the chain spans two: WF-006 owns `seal_input_snapshot` and WF-007
  # owns `materialize_applicability`, `materialize_check_result_keys` and `seal_issue_set`.
  # `EvaluationStage::Router` is the registered pair and routes on the action's own target
  # type over a closed two-branch table; an unrecognized target type fails closed there in
  # the same shape the registry itself fails closed on an unregistered kind.
  #
  # `resolve_adjudication_gate` still has no handler. That is not an omission: under the
  # ratified baseline every failed Result carries valid `high` confidence, so no Issue enters
  # `review_required` and there is no gate to resolve. An action naming it quarantines as
  # `scheduled_work_mapping_mismatch` rather than being dispatched to a stage that would have
  # to invent an adjudication outcome.
  registry.register(
    action_kind: "evaluation_stage_advance",
    action_schema_version: "1.0",
    operation: "AdvanceEvaluationStage",
    handler: Workflows::EvaluationStage::Router,
    command: Workflows::EvaluationStage::Command
  )
  # One ParsingJob attempt. `parsing_attempt_due` is a SPECIALIZED work type (`parse`,
  # BACKGROUND_PROCESSING.md :199), so it is absent from the generic dispatch table and the
  # registry's operation cross-check does not apply. One operation only: :481 gives an
  # attempt a single execution path, and its retry is another delivery of the same kind.
  registry.register(
    action_kind: "parsing_attempt_due",
    action_schema_version: "1.0",
    operation: "ExecuteParsingJob",
    handler: Workflows::Wf006::Handlers::ExecuteParsingJob,
    command: Workflows::Wf006::Commands::ExecuteParsingJob
  )
  # One Check attempt, per materialized expected key. `check_attempt_due` is the ratified
  # SPECIALIZED work type (`check_execute`, BACKGROUND_PROCESSING.md), so it too is absent
  # from the generic dispatch table. The Slot is the target because the Slot exists before
  # execution and carries the preallocated Check Result identity.
  registry.register(
    action_kind: "check_attempt_due",
    action_schema_version: "1.0",
    operation: "ExecuteCheckAttempt",
    handler: Workflows::Wf007::Handlers::ExecuteCheckAttempt,
    command: Workflows::Wf007::Commands::ExecuteCheckAttempt
  )
end
