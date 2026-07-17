# Volume II Application Layer

## Status And Authority

- Status: Volume II Implementation Architecture Pass 001
- Behavioural baseline: frozen Volume I at `v1.5-volume-i-frozen` (commit `c6b3853`, ADR-020). Historical `v1.3-volume-i-corrected` is retained as predecessor history and is not the baseline.
- Engineering-practice baseline: accepted Engineering Manual at `v1.7-engineering-manual-accepted` (commit `b049a41`, ADR-022), normative for engineering practice only.
- Application shape: Rails 8.1 modular monolith
- Change boundary: implementation architecture only

This document translates the accepted logical commands, queries, events and workflows into application-layer boundaries. It inherits [011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md), [014 SECURITY_MODEL.md](../014%20SECURITY_MODEL.md), the [Volume I capability model](../volume-i/CAPABILITY_MODEL.md), the [Volume I workflows](../volume-i/WORKFLOW_SPECIFICATIONS.md), the [Rails application architecture](../../architecture/RAILS_APPLICATION_ARCHITECTURE.md), and the [PostgreSQL schema](../../schemas/POSTGRESQL_SCHEMA.md). If this document appears to change product behaviour, Volume I wins and the difference MUST be reported.

## Application Package Layout

The application MUST use these roots and constants:

| Filesystem root | Constant root | Purpose |
| --- | --- | --- |
| `app/workflows` | `Workflows` | The only outer application package permitted to coordinate more than one context |
| `app/contexts/<context>/public` | `<Context>::Public` | Frozen public command, query and DTO interfaces |
| `app/contexts/<context>/domain` | `<Context>::Domain` | Aggregate roots, children, values, invariant and transition policies |
| `app/contexts/<context>/application` | `<Context>::Application` | Context-local command/query handlers and owned ports |
| `app/contexts/<context>/infrastructure` | `<Context>::Infrastructure` | Private Active Record repositories and adapters |
| `app/contexts/<context>/presentation` | `<Context>::Presentation` | Pure presenter objects over authorized DTOs |
| `app/platform` | `Platform` | Unit of work, authenticated request, result, time, ID, audit, outbox and telemetry primitives |

`app/contexts` is an explicit Zeitwerk root. The ordinary Rails `app` root maps `app/platform/...` to `Platform::*`; `app/platform` MUST NOT be pushed as an unnamespaced Zeitwerk root. Each context and `Workflows` has one `package.yml`. Only constants below a package's `public` directory may be imported by `Workflows`; one context MUST NOT import another context.

No generic `app/services` directory is permitted. A class that changes state is a command handler, a class that reads is a query handler, a pure cross-entity calculation is a named domain service, and a vendor operation is an application port plus infrastructure adapter.

## Aggregate, Lifecycle Owner And Serialization

The following terms are not interchangeable:

- **Canonical aggregate root** is the only write entry required by DM-REQ-008.
- **Lifecycle-policy owner** is the bounded context that validates an entity transition.
- **Persistence owner** is the context containing the private repository implementation.
- **Serialization guard** is a row or advisory-lock identity used to order a race. It is not an aggregate root.
- **Workflow orchestrator** coordinates canonical roots without acquiring independent product authority.

A command targeting a child entity MUST enter through its canonical root coordinator. Where the lifecycle-policy owner is another context, `Workflows` obtains that owner's frozen decision DTO and passes it into the root command inside one unit of work. The lifecycle owner MUST NOT save the child independently.

### Canonical write-entry registry

| Entity or state group | Canonical write entry | Lifecycle-policy owner | Persistence/serialization rule |
| --- | --- | --- | --- |
| Organization, Account-membership policy, authorization epoch | Organization | `TenantGovernance`; `IdentityAccess` supplies identity/access decisions | Organization repository; Organization row is the epoch guard |
| Project and Source membership | Project | `Projects`; `Intake` supplies Source transition decisions | Project repository; Project/source-set row is the membership guard |
| Crawl, Document execution lineage, IngestionJob, ParsingJob, IndexingJob | Crawl | `Intake`; `Retrieval` supplies indexing decision | Crawl repository loads the child graph; child attempt rows are checkpoints, not roots |
| Evaluation, applicability, Check Result, Issue, Adjudication Case and score publication plan | Evaluation | `Evaluation` | Evaluation repository; Issue lineage head and calculation sequence are serialization guards |
| RecommendationArtifact, AIResponse and Citation lineage | RecommendationArtifact | `Recommendations`; `AiOrchestration` and `Evidence` supply validated decisions | Recommendation repository; family and request-fingerprint rows are serialization guards |
| Billing and approved commercial linkage | BillingEntity | `Commercial` | BillingEntity repository; Plan Assignment is committed through the BillingEntity command |
| Integration and Credential lifecycle | Integration | `Integrations`; `IdentityAccess` supplies secret-access policy decision | Integration repository; Credential/material rows are children |
| Evidence and Validation Decisions | Evidence record lifecycle specified by Volume I | `Evidence` | Evidence repository appends immutable Evidence and Validation Decisions; no payload/provenance alias becomes a root |
| Notification, recipient and Delivery attempts | Notification | `Delivery` | Notification repository; Delivery/attempt rows are aggregate children and checkpoints |
| Export, approval, manifest and retrieval attempts | Export | `Delivery` | Export repository; package bytes remain external objects |
| Incident, playbook attempts, approvals and restoration checks | Incident | `SecurityOperations` | Incident repository; attempt and approval rows are children |
| Investigation, required inputs, custody, gaps and reports | Investigation | `SecurityOperations` | Investigation repository; per-Organization access remains separately authorized |
| SupportSession, approvals and permitted scope | SupportSession | `SecurityOperations` | SupportSession repository; request/approval rows are children and the SupportSession row is the lifecycle guard |
| LegalHold and its approvals/scope | LegalHold | `DataLifecycle` | LegalHold repository |
| LifecycleDeletionJob, manifest, outcomes, Deletion Evidence and backup tombstone | LifecycleDeletionJob | `DataLifecycle` | Deletion-job repository; manifest entries are checkpoint children |

Every mutable table in the PostgreSQL catalogue MUST map to exactly one row above or to a Platform mechanism explicitly listed below. Adding a mutable table without declaring its root, lifecycle owner, repository and lock rank fails architecture review.

Platform mutable records (`idempotency_records`, outbox claims, dead letters, scheduled actions, stored-object checkpoints and release-artifact activation) are infrastructure state machines. They MUST NOT publish an invented product lifecycle event or be called directly from a controller.

## Workflow Orchestration And Unit Of Work

`Workflows` is the only package that may coordinate multiple contexts. A state-changing transport entry point invokes exactly one `Workflows::<Workflow>::Handlers::<Operation>` object. That handler:

1. validates the physical transport and constructs the immutable logical command;
2. performs a nonlocking digest lookup only to discover the candidate Session/tenant identities and declares the complete tier-zero-through-tier-fourteen lock set;
3. opens the sole `Platform::UnitOfWork` at the registered isolation level;
4. acquires the command-idempotency advisory identity at tier zero, then invokes `Platform::AuthenticatedRequest` or the service equivalent inside that unit of work;
5. establishes proved RLS context and acquires Organization tier one, Account/Session tier two, and every declared aggregate/serialization lock in the Rails total order;
6. returns a currently reauthorized/redacted retained result for exact replay, or resolves permission, policy, entitlement and lifecycle-owner decisions under those locks;
7. invokes every canonical root through its public command facade and collects changes without flushing them independently;
8. at tier fourteen inserts/validates the idempotency record and commits product rows, command result, authorization decision, audit record, domain events, any required Notification-consumer outbox route and any next ScheduledAction atomically;
9. returns one deeply frozen `Platform::CommandResult`;
10. permits enqueue, render or provider work only after commit.

The candidate Session/tenant discovery read grants no authority, changes no activity and holds no row lock. The tier-zero advisory key is the stable idempotency scope plus key digest; a duplicate waits behind that same key and observes the committed result. No idempotency row lock is held before a lower-tier row. The tier-fourteen insert occurs before the unit of work flushes any product mutation, and its unique constraint remains the final duplicate guard.

Context handlers MUST NOT call `transaction`, `requires_new`, `after_commit`, `perform_async`, a provider, another context, or another workflow. `Platform::UnitOfWork` rejects a nested transaction. A workflow that needs a durable boundary ends the first unit of work and continues only from its explicitly committed ScheduledAction. Domain-event outbox consumption is reserved to `notification_route_v1` and is never a generic continuation mechanism.

The default isolation level is PostgreSQL `READ COMMITTED` with explicit row/advisory locks and uniqueness constraints. A different level is allowed only in the command registry. No baseline operation uses implicit `SERIALIZABLE`. Deadlock or serialization retries reuse the same command/idempotency claim and follow the physical retry rule in the Rails architecture; they never become a new product attempt.

## Command Type And Handler Contract

Physical command objects are `Data` classes whose constructor canonicalizes every nested value into the registered scalar, immutable Value Object, or recursively frozen Array/Hash value tree before the object becomes visible. Their fields are the complete Volume I logical command envelope plus one typed payload; they contain no mutable String, Active Record object, IO object, request object, secret, provider SDK value or callable. The class name and `command_type` registry entry are one-to-one. A shallow-frozen `Data` containing a mutable child fails the command contract.

Every handler exposes only:

```text
call(command:, request_context:) -> Platform::CommandResult
```

It MUST return a result for an accepted success or contract failure and MUST raise only a `Platform::InvariantViolation` for an unmapped implementation defect. Controllers and jobs MUST NOT rescue database/provider exceptions into invented reason codes; the workflow error mapper applies the Volume I precedence.

### State-changing operation registry

The following registry is exhaustive at the workflow-family level. Each comma-separated operation is a distinct immutable command class and handler beneath the named namespace. Service and timed operations use the same contract with `service_identity_id`.

| Namespace | Registered operations | Canonical entries and transaction rule |
| --- | --- | --- |
| `Workflows::Wf001` | `RequestBootstrapGrant`, `BootstrapOrganization`, `AcceptInvitation`, `DeclineInvitation`, `SignInExistingAccount`, `ExpireBootstrapGrant`, `ExpireInvitation`, `ExpireSession` | Grant-only uses bootstrap guard; the other branches use the exact WF-001 multi-root transaction; the three expiry operations are service-only ScheduledAction transitions |
| `Workflows::Wf002` | `CreateProject`, `ActivateProject` | Project; activation locks Project and source-set guard |
| `Workflows::Wf003` | `IssueVerificationChallenge`, `ReserveVerificationAttempt`, `CompleteVerificationAttempt`, `CancelVerificationRequest`, `ExpireVerificationRequest`, `FailVerificationRequest` | Project/Crawl-family Source membership entry; verification success atomically appends Verification Evidence and source-scope policy |
| `Workflows::Wf004` | `RegisterSource`, `RequestSourceScopeChange`, `ApproveSourceScopeChange`, `RejectSourceScopeChange`, `CancelSourceScopeChange`, `ExpireSourceScopeChange`, `ActivateSource`, `DisableSource`, `ReactivateSource`, `RemoveSource` | Project membership entry plus Source lifecycle decision; policy activation is atomic with approval |
| `Workflows::Wf005` | `QueueCrawl`, `StartCrawl`, `RecordFetchAttempt`, `CompleteIngestion`, `FailIngestion`, `RequestIngestionReplay`, `CompleteCrawl`, `FailCrawl`, `CancelCrawl`, `RecoverCrawl`, `ActivateCrawlPolicy` | Crawl; root start includes Entitlement reservation and initial Evaluation exactly when Volume I requires; ingestion completion/failure/replay owns the WF-005 atomic Document/Evidence transition; terminal orchestration chooses exactly complete/fail/cancel from frozen run state |
| `Workflows::Wf006` | `CompleteParsing`, `FailParsing`, `CompleteIndexing`, `FailIndexing`, `ReplayPipelineStage`, `SealEvaluationInputs`, `FailEvaluation`, `SubmitMeasurementEvidence` | Crawl entry with Evidence append; Indexing is a Retrieval-owned transition decision inside the Crawl unit of work; stage/Evaluation terminal failure uses the matching service-only operation |
| `Workflows::Wf007` | `MaterializeCheckApplicability`, `MaterializeCheckResultKeys`, `ExecuteChecks`, `SealIssueSet`, `ResolveAdjudicationGate`, `RequestAdjudication`, `AssignAdjudication`, `DecideAdjudication`, `WithdrawAdjudication`, `MarkAdjudicationOverdue`, `ChangeEvidenceValidation` | Evaluation; the three Check preparation/execution operations own distinct sealed stage checkpoints; Issue and Case are children; accepted adjudication/Evidence-validation invalidation atomically marks the current projection unavailable and creates one due-now `score_recalculation_due` action keyed by Project, prior projection version and complete new source-input digest; overdue records/escalates without automatic decision. The same-hash/different-preimage Issue branch cannot persist its second Issue, emit `IssueFingerprintCollision`, seal an Issue Set or continue downstream under `UPSTREAM-V1-ISSUE-COLLISION-013`; Check Result key collision keeps its separate accepted fail-closed path. |
| `Workflows::Wf008` | `CalculateScore`, `PublishScore`, `RecalculateScore` | Evaluation plus project calculation guard and current projection |
| `Workflows::Wf009` | `GenerateRecommendation`, `RecordAiResponse`, `ValidateAiResponse`, `PublishRecommendation`, `SuppressRecommendation`, `ExpireAiResponse` | RecommendationArtifact; network generation is bracketed by external-effect checkpoints and never occurs in the unit of work; expiry is service-only and dormant without an approved AI artifact |
| `Workflows::Wf010` | `PublishActionQueue`, `OverridePriority` | RecommendationArtifact family decisions and action-queue projection |
| `Workflows::Wf011` | `ActivateReassessmentSchedule`, `EvaluateReassessmentSlot`, `StartReassessment`, `CancelReassessment`, `PublishReassessment`, `FailReassessment` | Project orchestration guard plus the exact staged multi-root transactions in WF-011; `FailReassessment` is the sole terminal failure UoW for a reassessment Evaluation and atomically owns Evaluation failure, ReassessmentResult, guard cleanup, reservation release and event set rather than chaining `FailEvaluation`. Schedule activation, slot evaluation and start remain registered but deferred under `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010`; cancellation/publication/failure can operate only on an already-existing orchestration created after that blocker is corrected. |
| `Workflows::Wf012` | `RebaseHistoricalComparison` | Rebase writes immutable noncurrent snapshots; historical projection rebuilding is a Platform projection recovery operation, not a product command |
| `Workflows::Wf013` | `CreateInvitation`, `DecideInvitation`, `RevokeInvitation`, `ReissueInvitation`, `RequestRoleAssignment`, `DecideRoleAssignment`, `RevokeRoleAssignment`, `ExpireRoleAssignment`, `ActivateAccessPolicy`, `SuspendAccount`, `ReactivateAccount`, `RevokeAccount`, `DeleteAccount`, `SuspendOrganization`, `ReactivateOrganization`, `RequestOrganizationClosure`, `DecideOrganizationClosure`, `ExpireOrganizationClosure`, `ExecuteOrganizationClosure`, `RequestSupportSession`, `DecideSupportSession`, `RevokeSupportSession`, `ExpireSupportSession`, `RequestLegalHold`, `DecideLegalHold`, `RequestLegalHoldRelease`, `DecideLegalHoldRelease`, `RecordEvidenceRetentionWarning`, `RetryDeletion` | Organization/Identity roots plus the specific lifecycle root; an approving `DecideLegalHoldRelease` atomically moves the Hold to released and creates/replays each exact blocked-deletion due-now action, while reject changes no Hold; there is no second release command. Expiry/warning operations are service-only. `ExpireRoleAssignment` may perform an ordinary expiry, but its last-OrganizationAdmin block branch is deferred under `UPSTREAM-V1-ROLE-EXPIRY-BLOCKED-EVENT-011`. |
| `Workflows::Wf014` | `CreateNotification`, `DispatchDeliveryAttempt`, `RecordProviderEvent`, `ReconcileDelivery`, `EscalateNotification`, `ReplayDelivery`, `ActivateNotificationPolicy` | Notification; provider calls occur only after `submission_started` commits and uncertainty never resubmits the same attempt; escalation is the idempotent five-minute service transition |
| `Workflows::Wf015` | `DecideEntitlement`, `ReserveEntitlement`, `HeartbeatEntitlement`, `CommitEntitlement`, `ReleaseEntitlement`, `RecordLowCostUsage`, `ActivateEntitlementPolicy` | BillingEntity/counter-window serialization; each decision/usage identity commits once |
| `Workflows::Wf016` | `RequestExportApproval`, `DecideExportApproval`, `CreateExport`, `StartExportGeneration`, `CompleteExportGeneration`, `FailExportGeneration`, `RetryExport`, `RevokeExport`, `ExpireExport`, `ReevaluateExportPolicy`, `BeginExportRetrieval`, `CompleteExportRetrieval`, `ActivateExportPolicy` | Export; `CreateExport` or `RetryExport` validates and atomically consumes the exact already-approved single-use approval in its pending/generation-start transaction; there is no separate approval-consumption command. Object rendering/storage and streaming occur outside transactions at registered checkpoints. |
| `Workflows::Wf017` | `DeclareIncident`, `RunIncidentStep`, `ObserveRestoration`, `ResolveIncident` | Incident; the route-fixed `RunIncidentStep(step=link_named_remediation)` branch atomically links an already committed separately authorized remediation Command Result and does not invoke a second Incident command |
| `Workflows::Wf018` | `OpenInvestigation`, `CollectInvestigationInput`, `PublishInvestigationReport`, `CloseInvestigation` | Investigation; `OpenInvestigation` persists one immediate `investigation_input_collect` ScheduledAction/checkpoint per frozen required input; the service-only collector executes bounded pages in one Organization-authorized transaction at a time under that Organization's frozen Support Session, and has no HTTP route |
| `Workflows::IntegrationLifecycle` | `DisconnectIntegration`, `RecoverIntegration`, `RetireIntegration`, `BeginCredentialRotation`, `CompleteCredentialRotation`, `ExpireCredential`, `RevokeCredential` | Integration root; each operator/service action is reachable only through the exact foundation Integration/Credential permission, Support Session, state, deadline and retry contract. `BeginCredentialRotation` is registered but unreachable under `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009`; completion has no independent entry and can run only after a valid begin. Adapter-policy activation is the single `ActivateReleaseArtifact` operation, not a second Integration command; `RetireIntegration` remains the accepted service route after withdrawal/supersession. |
| `Workflows::ReleaseLifecycle` | `ActivateReleaseArtifact` | global immutable release artifact; only the exact approved release-service identity may atomically activate/supersede a verified signed artifact |
| `Workflows::DataLifecycle` | `StartLifecycleDeletion`, `ExecuteLifecycleDeletionCheckpoint`, `FailLifecycleDeletion`, `VerifyBackupTombstone` | service-only execution of the accepted LifecycleDeletionJob/manifest/checkpoint contracts; object work remains outside the transaction and no operation bypasses LegalHold |

An operation name does not create product authority. It MUST be unreachable unless the corresponding Volume I trigger, actor/service, state, permission and policy contract admits it. Adding an operation requires a trace to an existing Volume I state-changing behaviour; otherwise it is a product change.

## Query Contract And Registry

A query is an immutable `Data` object handled by `<Context>::Application::Queries::<Name>Handler`. A handler:

- executes only inside `Platform::AuthenticatedRequest`;
- receives an already authenticated request context but performs the named object/field authorization through the sole authorization facade;
- reads only repositories/read stores and never calls a command, provider, Sidekiq or outbox;
- returns a deeply frozen `AuthorizedDTO` containing no Active Record model, lazy enumerator, Relation, unredacted alternate field or callable;
- uses stable cursor ordering with the canonical UUID tie-breaker;
- performs no SQL after it returns.

The handler itself remains read-only even when Volume I requires request-attributable evidence. No query may supply a product-event intent unless Volume I names that event. `QRY-008` supplies no product-event intent: OD-024 removes the comparison domain event entirely under ADR-019, so the comparison read is unambiguously side-effect-free. Its application-layer exposure remains intentionally deferred until the Volume II baseline under `UPSTREAM-V1-COMPARISON-EVENT-007`.

A query classified by WF-015 as a low-cost read must eventually execute through `Workflows::Wf015::LowCostRead`, not directly through a controller. The coordinator contract is to authenticate and authorize, obtain the immutable Entitlement Decision, materialize the AuthorizedDTO with the context query handler, then atomically append the one LowCostUsageRecord, `EntitlementCommitted`, required query event intent, authorization/audit evidence and Session activity at the durable response checkpoint. A Block commits its Decision but no usage record and returns no DTO. If response materialization or that commit fails, no response is returnable and no usage record commits. Exact replay must reuse the stored Decision, DTO result identity and usage record.

That coordinator is not executable until `UPSTREAM-V1-LOW-COST-METERING-005` resolves its durable-response identity. Every `report.view`, `history.view`, `issue.read`, `recommendation.read` and `score.read` GET/Turbo response remains disabled, including the apparently single-purpose query mappings; no transport retry may be counted or deduplicated by implementation choice. No other query is metered merely because it uses HTTP GET.

The mandatory first-party query registry is:

| Query ID and handler | Required authorization | Source | Result DTO |
| --- | --- | --- | --- |
| `QRY-000 CurrentSession` | exact currently authenticated Session only | authenticated request context; no cross-Session lookup | `CurrentSessionDTO` |
| `QRY-001 OrganizationHome` | current Session's `organization_home` logical destination only; every product-data region requires its exact named read contract | Session-bound destination shell; no Project, notice or administration collection | `OrganizationHomeDTO` |
| `QRY-002 ProjectCollection` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; no `project.read` action exists | Project read store | `ProjectCollectionDTO` |
| `QRY-003 ProjectOverview` | named field actions exist; response disabled by `UPSTREAM-V1-LOW-COST-METERING-005` | current score, issue, action-queue and coverage projections | `ProjectOverviewDTO` |
| `QRY-004 SourceCollection` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; management actions are not inferred as read authority | Source/scope/verification read store | `SourceCollectionDTO` |
| `QRY-005 SourceDetail` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; management actions are not inferred as read authority | Source, policy and immutable run references | `SourceDetailDTO` |
| `QRY-006 EvaluationCollection` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004` and `UPSTREAM-V1-LOW-COST-METERING-005` | Evaluation/readiness/coverage read store | `EvaluationCollectionDTO` |
| `QRY-007 EvaluationDetail` | field actions exist; response disabled by `UPSTREAM-V1-LOW-COST-METERING-005` | immutable input, Result, Issue Set and score records | `EvaluationDetailDTO` |
| `QRY-008 HistoryComparison` | `history.read`; disabled by `UPSTREAM-V1-LOW-COST-METERING-005` and `UPSTREAM-V1-COMPARISON-EVENT-007` | promoted snapshots and comparison projection | `HistoryComparisonDTO` |
| `QRY-009 IssueCollection` | `issue.read`; response disabled by `UPSTREAM-V1-LOW-COST-METERING-005` | Issue projection with state-at-snapshot fields | `IssueCollectionDTO` |
| `QRY-010 IssueDetail` | `issue.read`; Evidence fields separately authorized; response disabled by `UPSTREAM-V1-LOW-COST-METERING-005` | Issue, Case, Check Result and Evidence metadata | `IssueDetailDTO` |
| `QRY-011 RecommendationCollection` | `recommendation.read`; response disabled by `UPSTREAM-V1-LOW-COST-METERING-005` | published/suppressed Artifact projection | `RecommendationCollectionDTO` |
| `QRY-012 RecommendationDetail` | `recommendation.read`; Evidence fields separately authorized; response disabled by `UPSTREAM-V1-LOW-COST-METERING-005` | Artifact, origin Issue and validated lineage | `RecommendationDetailDTO` |
| `QRY-013 ActionQueue` | `recommendation.read`; response disabled by `UPSTREAM-V1-LOW-COST-METERING-005` | action-queue projection | `ActionQueueDTO` |
| `QRY-014 NotificationCollection` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; recipient status and route permission are not inbox-read authority | Notification/recipient/Delivery projection | `NotificationCollectionDTO` |
| `QRY-015 ExportCollection` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; `export.retrieve` authorizes one known retrieval, not enumeration | Export state and manifest metadata | `ExportCollectionDTO` |
| `QRY-016 ExportDetail` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; exact command result/retrieval remains available to its requester | Export, approval and manifest read store | `ExportDetailDTO` |
| `QRY-017 AccessAdministration` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; exact command-result reads remain scoped to their actor | Identity/access projections | `AccessAdministrationDTO` |
| `QRY-018 EntitlementNoticeCollection` | `entitlement.notice.read`; returns only the separately defined actor-visible notice fields | immutable entitlement notices addressed to the authorized Account/Organization scope | `EntitlementNoticeCollectionDTO` |
| `QRY-019 LifecycleAdministration` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; exact command/audit results remain available only in their expressly defined scope | closure, hold, deletion and tombstone projections | `LifecycleAdministrationDTO` |
| `QRY-020 SecurityOperations` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; mutation/support authority is not inferred as collection read authority | restricted security projections | `SecurityOperationsDTO` |
| `QRY-021 PendingVerificationChallenge` | exact request initiator or OrganizationAdmin holding `source.verify`, under the restricted retrieval contract | pending Verification Request and challenge delivery metadata | `PendingVerificationChallengeDTO` |
| `QRY-022 CrawlCollection` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; `crawl.trigger` is not inferred as read authority | Crawl/coverage projection | `CrawlCollectionDTO` |
| `QRY-023 CrawlDetail` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004` | Crawl, Source/URL outcome and stage summary projection | `CrawlDetailDTO` |
| `QRY-024 CurrentScore` | `score.summary.read` or `score.detail.read` by field; response disabled by `UPSTREAM-V1-LOW-COST-METERING-005` | Current Score Projection and promoted immutable Snapshot | `CurrentScoreDTO` |
| `QRY-025 HistoryCollection` | `history.read`; response disabled by `UPSTREAM-V1-LOW-COST-METERING-005` | promoted Evaluation/Snapshot history | `HistoryCollectionDTO` |
| `QRY-026 AccountAdministration` | blocked for broad collection disclosure; exact Account command-result scope only | Account/Assignment projection | `AccountAdministrationDTO` |
| `QRY-027 PolicyAdministration` | blocked for broad collection disclosure; a matching policy-manage action permits only its defined command inputs/results | active/historical Policy Artifact projection | `PolicyAdministrationDTO` |
| `QRY-028 IntegrationStatus` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; Integration mutation/support authority is not read authority | Integration/Credential metadata projection with no secret reference | `IntegrationStatusDTO` |
| `QRY-029 SupportSessionCollection` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; exact command results remain available to their submitting/deciding actors | Support Session projection | `SupportSessionCollectionDTO` |
| `QRY-030 IncidentCollection` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; `incident.respond` is not inferred as collection read authority | Incident projection | `IncidentCollectionDTO` |
| `QRY-031 IncidentDetail` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; exact command results remain actor-scoped | Incident/playbook/attempt/restoration projection | `IncidentDetailDTO` |
| `QRY-032 InvestigationDetail` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; Support Sessions authorize named investigation input reads, not an undefined general detail response | Investigation/custody/gap/report projection | `InvestigationDetailDTO` |
| `QRY-033 LegalHoldCollection` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; `legal_hold.manage` is not inferred as collection read authority | LegalHold projection; no held payload | `LegalHoldCollectionDTO` |
| `QRY-034 DeletionJobCollection` | deferred under `UPSTREAM-V1-READ-AUTHORIZATION-004`; an own-Organization `deletion.retry` command result does not authorize a collection | deletion-job/manifest-outcome projection | `DeletionJobCollectionDTO` |
| `QRY-035 CommercialSummary` | blocked for BillingEntity/Plan/usage disclosure by `UPSTREAM-V1-READ-AUTHORIZATION-004`; `entitlement.notice.read` does not authorize this broader data | BillingEntity, Plan Assignment and usage summary | `CommercialSummaryDTO` |
| `QRY-036 IssueEvidenceCollection` | `issue.read` plus exact Evidence metadata/payload/restricted action per returned field; disabled by `UPSTREAM-V1-LOW-COST-METERING-005` | one Issue's ordered supporting Evidence references | `IssueEvidenceCollectionDTO` |
| `QRY-037 IssueClosureEvidenceCollection` | same Issue/Evidence field authorization and metering blocker | one resolved Issue's ordered closure Evidence references | `IssueClosureEvidenceCollectionDTO` |
| `QRY-038 IssueAdjudicationCaseCollection` | `issue.read`; disabled by `UPSTREAM-V1-LOW-COST-METERING-005` | one Issue's Case history | `IssueAdjudicationCaseCollectionDTO` |
| `QRY-039 RecommendationRationaleEvidenceCollection` | `recommendation.read` plus exact Evidence field authorization; disabled by `UPSTREAM-V1-LOW-COST-METERING-005` | one RecommendationArtifact's ordered rationale Evidence references | `RecommendationRationaleEvidenceCollectionDTO` |

`QRY-010 IssueDetail` and `QRY-012 RecommendationDetail` contain scalar/detail fields and child counts only; they never embed an unbounded or first-page child collection. QRY-036 through QRY-039 each own one closed cursor-paginated child DTO and cannot be selected as a result variant under another Query ID.

CAP-018 and WF-012 DTOs contain deterministic structured fields only. `QRY-003` and `QRY-008` MUST NOT reference `AiOrchestration`, expose a narrative field, reserve a narrative slot, enqueue narrative work or call a provider.

## Repository Contracts

Each canonical aggregate has one application-owned repository port and one private Active Record implementation. Mutable aggregate repositories expose only:

```text
load(id:, organization_id:)
load_for_update(id:, organization_id:, expected_state_version:)
add(aggregate:)
save(aggregate:, expected_lock_version:)
```

An aggregate-specific method may be added only for a named uniqueness allocation or serialization guard. Repositories MUST NOT expose Active Record scopes, `Relation`, `where`, arbitrary SQL fragments, `update_all`, model callbacks or child `save` methods to application/domain code. `save` persists the complete changed aggregate and its collected events in the caller's existing unit of work.

Immutable stores expose `append` and identity/content-hash lookup only. Query read stores are separate interfaces optimized for authorized DTO materialization; they cannot be passed into a command handler. Cross-context foreign keys remain opaque typed identifiers in domain objects.

## Domain And Authorization Policies

Domain policies are pure deterministic functions of explicit values. They MUST NOT read a repository, current time, current actor, Rails configuration or global state. Time, ID generation and canonicalization are injected Platform ports.

The exact Volume I effective-authorization algorithm has one implementation facade: `IdentityAccess::Public::Authorize`. Web, API, service, job and workflow handlers MUST NOT instantiate role-specific Rails policies or infer permission from controller/action names. The facade returns a frozen decision DTO containing all governing versions and causes Platform to persist the corresponding Authorization Decision.

Lifecycle-owner decisions are also frozen DTOs. They contain input state/version, proposed transition, allow/deny, exact reason, policy versions and a semantic input hash. A root handler MUST reject a decision whose input state/version/hash no longer matches under its lock.

## Presenter Contract

A presenter accepts one `AuthorizedDTO` and locale. It may select a registered deterministic human-authored label or template and format display-only values. It MUST NOT:

- issue SQL or call a repository/provider;
- authorize, broaden, suppress or restore a field;
- inspect an Active Record model;
- derive a product state, score, recommendation or comparison result;
- create AI narrative or a narrative placeholder;
- enqueue work or mutate Session activity.

HTML presenters and JSON serializers consume the same DTO field allowlist and redaction codes. A presenter trying to access a field not declared in its DTO schema fails in test and development.

## Authenticated Request Transaction

Every protected HTML, Turbo or first-party JSON request runs through `Platform::AuthenticatedRequest` inside the caller-owned `Platform::UnitOfWork`; the wrapper never opens or nests a transaction:

1. validate the physical request, hash the opaque Session token and perform only the nonauthoritative lookup needed to declare candidate lock identities;
2. after the unit of work begins, establish safe RLS context without taking a row lock;
3. acquire the Organization row at tier one, then Account and Session rows at tier two in the global total order;
4. apply the exact idle/absolute-expiry equality rule and deny or terminalize when required;
5. acquire every remaining predeclared lock, then resolve authorization epoch, Assignments, policies, support scope and classification through `IdentityAccess::Public::Authorize`;
6. execute one command handler or fully materialize one query DTO;
7. for accepted protected activity, update only the Session last-activity and idle-expiry fields required by Volume I;
8. persist the authorization/audit/outbox and any declared low-cost response checkpoint at tier fourteen; the caller commits, clears transaction-local context, and only then renders/serializes.

The query handler itself remains read-only; Session activity is Platform security bookkeeping around it. No record or lazy query may escape the transaction. A query denial does not render from a partially materialized DTO. Session token/cookie and CSRF mechanics are fixed in [SECURITY_PERFORMANCE.md](SECURITY_PERFORMANCE.md).

## Read Projections

Each materialized projection MUST register:

- projection name and schema version;
- authoritative source record/event versions;
- synchronous or explicit-work update mode;
- consumer/work name and its durable idempotency identity;
- ordering and stale-event rejection rule;
- source-version and projection-version fields;
- unavailable/stale reason mapping;
- rebuild command, retry budget and terminal escalation;
- query IDs that consume it.

The baseline registry is closed:

| Projection | Mode and source identity | Writer or work identity | Queries | Recovery |
| --- | --- | --- | --- | --- |
| `current_score_v1` | synchronous authoritative pointer to one promoted immutable ScoreSnapshot plus calculation/input versions | `PublishScore` or `PublishReassessment` in the publication transaction; uniqueness is Project plus calculation sequence | `QRY-003`, `QRY-024` | `invariant_sweep` may create one `projection_build` work identity from Project, expected pointer version and source digest; compare-and-swap repair writes only byte-equal deterministic content and emits no product event |
| `action_queue_v1` | synchronous immutable queue version built from the exact published RecommendationArtifact set and priority rules | `PublishActionQueue` or `OverridePriority`; identity is Project plus source-artifact-version digest | `QRY-003`, `QRY-013` | same `projection_build` rule using queue version/source digest |
| `retrieval_document_v1` | explicit asynchronous IndexingJob output from one immutable Parsed Artifact generation | `index`; identity is IndexingJob, generation and semantic input digest | internal Retrieval used by the accepted Check pipeline; no first-party public search query | authorized `ReplayPipelineStage` creates the Volume I replay generation; no generic projection repair substitutes for it |

No other baseline query uses a materialized projection. Issue, Case, Recommendation, Notification, access, lifecycle, commercial and security DTOs read their normalized authoritative records; `history` compares immutable Snapshot/version records at request time; dashboard/project overview composes authorized structured fields at request time; and Crawl/Evaluation DTOs read their lifecycle/checkpoint records. The term “projection” in a query name does not permit a new table, cache authority or event consumer.

`projection_build` is limited to the two registered synchronous-pointer integrity repairs above. It is never created by a domain event: an `invariant_sweep` detecting a digest/version mismatch persists the single work identity, and a clean sweep creates none. It cannot create a missing product artifact, advance a lifecycle, choose a different current winner or publish a domain event. Out-of-order or mismatched source versions quarantine the repair and leave the prior pointer unchanged. The baseline has no domain-event-driven read projection and no asynchronous UI invalidation.

## Upstream Blockers And Ambiguities

### `UPSTREAM-V1-EVENT-SCOPE-001`

The [Volume I logical command contract](../volume-i/WORKFLOW_SPECIFICATIONS.md#logical-command-envelope-and-replay) permits a pre-Organization bootstrap command with null `organization_id`, and WF-001 emits `BootstrapGrantIssued` before an Organization exists. The [logical event envelope](../volume-i/WORKFLOW_SPECIFICATIONS.md#logical-event-envelope) instead requires every event to carry `organization_id` as tenant identity. WF-017 additionally permits a platform-wide Incident, and WF-018 permits one Investigation spanning an approved Organization set, for which no one tenant Organization is authoritative. The current physical event table is tenant-scoped and nonnull.

Null Organization, a sentinel Organization, one arbitrarily selected Organization and duplicated per-Organization events have different tenant, authorization, retention and consumer semantics. Volume II MUST NOT select one. `BootstrapGrantIssued`, platform-wide Incident and cross-Organization Investigation event persistence/wire contracts remain blocked pending controlled Volume I clarification; no implementation may fabricate a tenant to proceed.

### `UPSTREAM-V1-SESSION-REVOCATION-002`

The [foundation state model](../016%20STATE_MODEL.md) permits `Session.Active -> Session.Revoked` for explicit security revocation, but Volume I defines no standalone current-user sign-out/revoke command, actor, permission, precondition, idempotency, error, audit or acceptance contract. No `SignOut`, `RevokeCurrentSession` or session-management command or UI control may be added in Volume II. Existing Account/Organization lifecycle revocation and timed expiry remain implementable exactly as specified.

### `UPSTREAM-V1-PROJECT-LIFECYCLE-003`

The foundation state model names Project pause, resume/reactivate and archive transitions/events, but Volume I defines no workflow, actor, permission, command, error, idempotency or acceptance contract for them. Only Project create and draft-to-active are registered. Volume II MUST NOT expose or implement pause, resume or archive until controlled Volume I clarification supplies the missing behavior.

### `UPSTREAM-V1-READ-AUTHORIZATION-004`

The Volume I Permission Baseline defines score, Issue, history, Recommendation, Evidence and entitlement-notice reads, and OD-020 adds explicit customer-facing read rows for Organization home data, Project, Source, Crawl, Evaluation, Notification inbox and Export enumeration, each carrying a full role matrix and each tenant-scoped and least-privilege. Read authority is therefore canonical for the customer-facing set and is no longer acquired by inference from a companion mutation permission. Read authority over security, administrative and internal operational objects — Support Session, Incident, Investigation, Legal Hold, Emergency Access Grant, deletion jobs, Account and policy administration, Integration status and privileged Billing surfaces — remains deny-by-default pending a separate owner decision, so no query may expose them. The semantic contract is canonical in Volume I; the corresponding application-layer exposure remains intentionally deferred until the Volume II baseline and is not defined by this correction package.

### `UPSTREAM-V1-LOW-COST-METERING-005`

WF-015 charges one `read_request` for each allowed low-cost response and names `report.view`, `history.view`, `issue.read`, `recommendation.read` and `score.read`, but it does not map every accepted read surface to exactly one operation. A Project dashboard combines score, Issue and Recommendation regions; Evaluation summary/detail can reasonably be `report.view` or `score.read`; and a server-rendered page plus independently requested Turbo Frames can reasonably be one response unit or several. Those choices produce different Decisions, usage records and warnings for identical user navigation.

WF-015 also requires the enforcement request and LowCostUsageRecord to carry an idempotency key and exact replay to reuse one record, while the current physical query draft rejects idempotency keys on GET. Volume II MUST NOT choose a charging boundary or silently count transport retries. Every query mapped or potentially mapped to any of the five low-cost operations, composite page/frame charging, and the physical metered-read replay identity remain disabled until controlled Volume I clarification supplies the exhaustive query-to-operation and response-unit/replay contract. A matching action name does not resolve the missing durable-response replay identity.

### `UPSTREAM-V1-REACTIVATION-PROOF-006`

WF-013 requires Account reactivation to have “valid identity” but does not define whether that means only the reactivating administrator's current Session, a fresh managed-identity proof for the suspended target Account, or another artifact; it supplies no receipt purpose, freshness, subject binding, disabled-provider handling or outward failure precedence for that proof. Those implementations reactivate different Accounts from identical administrator inputs. `ReactivateAccount` remains registered but unreachable until controlled Volume I clarification defines the exact proof contract.

### `UPSTREAM-V1-COMPARISON-EVENT-007`

OD-024 removes `ComparisonGenerated` under ADR-019. The WF-012 comparison read emits no domain event, persists no comparison record and moves no current pointer; every outcome is deterministic under Volume I and the workflow's audit obligations are discharged entirely by Audit Evidence with correlation ID. The previously undefined questions — whether the event occurred for each outcome, whether reload, Turbo prefetch or repeated selection re-emitted it, and what its idempotency identity was — no longer arise, because no event exists. Volume II MUST NOT emit, suppress, deduplicate or meter the removed name. `QRY-008` and its physical routes carry the resolved semantic contract; their exposure remains intentionally deferred until the Volume II baseline and is not defined by this correction package.

### `UPSTREAM-V1-ORGANIZATION-REACTIVATION-PROOF-008`

WF-013 requires Organization reactivation through fresh managed identity plus MFA after suspension has revoked every human Session. OD-022 defines the proof: a fifth purpose-bound Identity Validation Receipt purpose `organization_reactivation`, carrying the assurance version and `mfa_satisfied=true`, bound to Organization ID, issuer and subject, with a 10-minute expiry, nonce-consumed only by the reactivation command, and creating no Session. No sign-in relaxation and no raw provider proof is admitted, and `existing_account_sign_in` continues to reject an inactive Organization. This governs `organization.reactivate` only and decides nothing about the separate `account.reactivate` predicate under OD-021. The semantic contract is canonical in Volume I; the corresponding application-layer exposure remains intentionally deferred until the Volume II baseline and is not defined by this correction package.

### `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009`

The frozen Integration/Credential lifecycle requires `BeginCredentialRotation` to receive a “fresh rotation token” and validate new material, but defines no issuer or creation authority, token form/entropy, lifetime/equality boundary, one-use and exact-replay behavior, or binding to the Organization, Integration, Credential, current policy and exact new material reference. It also does not say whether a retry after validation exhaustion reuses or replaces the pending material. A signed self-contained token, an opaque database capability and a direct secret-reference input therefore authorize materially different rotations while each appears compliant. `BeginCredentialRotation` remains registered but unreachable; `CompleteCredentialRotation` has no independently callable path. No token issuer, route, material intake or pending rotation may exist until a controlled Volume I correction supplies that behavioral contract.

### `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010`

OD-025 removes `ReassessmentTriggered` under ADR-019 through a PM-REQ-009 controlled foundation change to the WF-011 coverage row in `018 OBSERVABILITY.md`. The question of whether an admitted trigger subsequently blocked by Entitlement emits it no longer arises, because no trigger event exists: the Entitlement-blocked branch is observable through `ReassessmentFailed`, its linked Entitlement Decision and Audit Evidence, and the executing branch through `EvaluationStarted` inside the atomic Evaluation-creation commit. Provenance — `trigger_kind`, nullable policy identity, version and content hash, slot number and due time — is retained on the Reassessment Result record and its Audit Evidence, so no affected-entity or profile choice is required. Volume II MUST NOT serialize the removed name. `ActivateReassessmentSchedule`, `EvaluateReassessmentSlot` and `StartReassessment` carry the resolved semantic contract; their exposure remains intentionally deferred until the Volume II baseline and is not defined by this correction package.

### `UPSTREAM-V1-ROLE-EXPIRY-BLOCKED-EVENT-011`

WF-013 requires `RoleExpiryBlocked` when timed expiry would violate the last-OrganizationAdmin invariant. OD-026 supplies the record: an immutable `RoleExpiryBlockDecision` `decision` record carrying the decision ID, Organization, Role Assignment, `expires_at_utc`, authorization epoch, the block reason `expiry_blocked_last_admin` and the correlation ID, which satisfies the logical event profile fields. `RoleExpiryBlocked` has exactly one producer, the role-expiry lifecycle service, and routes a mandatory security and OrganizationAdmin notification requiring `security.notice.read` at severity `critical`. The Assignment remains `active` and effective past `expires_at_utc` until the guard clears, re-evaluated on each authorization-epoch advance; no lifecycle status is added and no terminal admin-less ceiling exists. The semantic contract is canonical in Volume I; the corresponding application-layer exposure remains intentionally deferred until the Volume II baseline and is not defined by this correction package.

### `UPSTREAM-V1-DOCUMENT-LIFECYCLE-012`

The foundation state model no longer admits Document quarantine or retirement: OD-015 removes the `quarantined` and `retired` states and the `DocumentQuarantined` and `DocumentRetired` events from `016 STATE_MODEL.md` through a PM-REQ-009 controlled foundation change under ADR-019. The canonical Document lifecycle is `discovered -> ingested -> parsed -> indexed` and `indexed` is terminal, which is exactly what WF-005 and WF-006 already execute, so no trigger, actor, permission, command, reason precedence, idempotency, recovery or acceptance contract is required for a transition that does not exist. No `QuarantineDocument` or `RetireDocument` operation, job, event, migration shape or DML grant may be introduced without controlled Volume I change. A Document leaves product use only through the separate retention and deletion lifecycle, which destroys the record rather than transitioning it; Evidence quarantine is a separate, unaffected state machine.

### `UPSTREAM-V1-ISSUE-COLLISION-013`

OD-017 fixes the Issue fingerprint collision outcome: on a same-hash/different-preimage tuple the second Issue MUST NOT be created and the affected Evaluation fails closed using the existing canonical collision outcome and telemetry. No alternative duplicate Issue may be silently persisted, so the previous divergence between the fingerprint body and AC-SM-006 no longer admits different Issue-set membership or downstream results. `ExecuteChecks` completes the accepted Check Result path, and Check Result key collision retains its accepted fail-closed execution and telemetry. The semantic contract is canonical in Volume I; the corresponding application-layer exposure remains intentionally deferred until the Volume II baseline and is not defined by this correction package.

## Fitness Requirements

CI architecture checks MUST fail when:

- a context imports another context;
- a nonpublic context constant is imported by `Workflows`;
- a controller/job calls a repository, Active Record model or context handler directly;
- a mutable table is not mapped to a canonical root or Platform state machine;
- a child repository exposes an independent `save`;
- a context handler opens a transaction or enqueues/provider-calls;
- a command/query type is missing from its registry;
- a query returns an Active Record object, Relation or lazy enumerable;
- a presenter issues SQL, authorizes, mutates or calls a provider;
- any CAP-018/WF-012 code references `AiOrchestration` or a narrative field;
- an outbox projection lacks source-version, consumer-idempotency and rebuild tests.

## Verification

The implementation MUST provide architecture specs for package imports, command and query registry completeness, aggregate/table ownership, no nested transactions, repository return types, presenter query count, projection idempotency/order, and authenticated-request Session behavior. These tests implement existing Volume I requirements; they do not add acceptance behavior.

## WF-001 Onboard Organization Or Invited Account

Matrix rows: MTX-001 (AC-CAP-001), MTX-026 (AC-WF-001). Slice: S-01.
Structured contract: `specification/volume-ii/contracts/S-01.json`.
Governing authority: CAP-001, WF-001, PRULE-001, PRULE-018 in `v1.5-volume-i-frozen`.

This section is the canonical owner of the WF-001 application contract. The matrix indexes
it and carries the same structured facts; it does not duplicate this narrative.

### Entry point and authority

WF-001 assigns grant issuance and self-service authority to the approved identity/bootstrap
service alone, and states expressly that these are not Role permissions held by the
registrant. There is therefore no registrant-facing route, and no controller. The service is
the only entry point, so authorization cannot be reduced to a transport-layer check.

### Commands

`RequestBootstrapGrant`, `BootstrapOrganization`, `AcceptInvitation`, `DeclineInvitation`,
`SignInExistingAccount`. These five are reconciled from the existing Pass 001 inventory
rather than renamed. `ExpireBootstrapGrant`, `ExpireInvitation` and `ExpireSession` are
service-only ScheduledAction transitions and are not principal commands.

### Transaction boundary

One transaction per branch, covering exactly the records that branch materializes. WF-001
requires one atomic product commit across multiple roots, so the single-aggregate default in
EM-III-011 does not apply. This is an explicit product-specific specialisation: EM-II-010
permits a multi-root transaction where higher authority requires atomicity, and WF-001
requires that no partial onboarding branch is ever visible and that pending Account,
Organization and BillingEntity states are never externally observable after failure.
Orchestration stays in the Application Layer, as EM-III-011 section 7 requires.

No billing provider is called; WF-001 states this expressly. No external effect sits inside
any of these transactions.

### Event order

The self-service order is exact and asserted by AC-WF-001:
`AccountProvisionRequested`, `OrganizationCreated`, `BillingStateChanged(to=pending)`,
`RoleGranted`, `AccessPolicyActivated`, `PlanAssigned`, `EntitlementPolicyActivated`,
`BillingStateChanged(pending->active)`, `AccountActivated`, `OrganizationActivated`,
`ProjectCreated`, `BootstrapGrantConsumed`, `SessionCreated`.

Under OD-013 Option 1, `BootstrapGrantIssued` and `BootstrapGrantExpired` alone substitute
the immutable `bootstrap_principal_id` into `organization_id`, because no Organization
exists at grant issuance or expiry. The substitution is confined to those two event types
and is never available once an Organization exists.

### Retry, timeout and failure

Grant, bootstrap and Invitation branches take the initial attempt plus exactly two service
retries at 1 second and 5 seconds, for transient transaction or dependency failure only, each
rechecking receipt and grant/invitation expiry. Exhaustion returns
`F1-DEPENDENCY-503 / onboarding_transaction_unavailable` with no partial write. Sign-in has
no automatic retry and returns `F1-TIMEOUT-504 / sign_in_timeout` on its 10-second deadline.
At grant or invitation expiry equality, the lifecycle transition wins.

### Withheld

Nothing in WF-001 is withheld. OD-014 governs Project pause/resume/archive, which WF-001
does not perform: it creates the first Project in `draft` and states that Project activation
is not part of WF-001.

## CAP-002 Organization Setup

Matrix row: MTX-002 (AC-CAP-002). Slice: S-02.
Structured contract: `specification/volume-ii/contracts/S-02.json`.
Governing authority: CAP-002, WF-001 self-service branch, WF-013 Organization limb, PRULE-002,
PRULE-019 in `v1.5-volume-i-frozen`.

This section is the canonical owner of the CAP-002 Organization-establishment contract. The
transaction that carries it is owned by
[WF-001](#wf-001-onboard-organization-or-invited-account); this section does not restate it.

### No separate creation path

CAP-002 Product Behavior places Organization establishment "In the self-service WF-001
transaction". There is therefore no Organization-creation command, route or transaction of its
own. This row contracts the Organization-specific obligations that transaction carries. The
Organization lifecycle limb -- suspend, reactivate, closure -- is reached through WF-013 and is
owned by S-23.

### The bootstrap-service-only exception

CAP-002 names the Organization Administrator as its actor, but that Assignment is created by
the same commit, so no administrator exists to authorize it. AC-CAP-002 resolves this with the
`bootstrap-service-only exception`: the approved bootstrap service is the only actor that may
create an Organization, and the first OrganizationAdmin Assignment is an output of the commit
rather than its authority. No Role permission authorizes Organization creation.

### Ordering inside the transaction

Organization pending; BillingEntity pending; Access and Entitlement policies and the
same-Organization Plan Assignment activated; BillingEntity activated; then Organization
activated only when every tenant invariant passes. `OrganizationCreated`, two ordered
`BillingStateChanged` transitions and `OrganizationActivated` occupy fixed positions in the
WF-001 thirteen-event order under one bootstrap correlation.

Activating Organization before `ProjectCreated` is what satisfies the WF-001 requirement that
the tenant boundary is established before Project creation.

### Prohibitions carried by AC-CAP-002

No provider call. No lazy, callback, background, first-use or Invitation path may create the
BillingEntity. Exactly one active baseline BillingEntity per Organization, linked to the
same-Organization active Plan Assignment. The reserved `past_due` and `suspended` BillingEntity
values have no baseline transition and MUST be unreachable. `pending` is never returned as
current state, though its immutable transition event is retained.

## PRULE-002 Organization Creation Invariants

Matrix row: MTX-053 (AC-PRULE-002). Slice: S-02.
Structured contract: `specification/volume-ii/contracts/S-02.json`.
Governing authority: PRULE-002, sourced from DM-REQ-001.

This section is the canonical owner of the PRULE-002 invariant for the WF-001 creation limb.
PRULE-002 also lists CAP-024, because the BillingEntity it creates is the entitlement subject;
that consumption limb is owned by S-22 and is not contracted here.

The rule is a conjunction, and its last clause is the load-bearing one:

- Organization creation MUST atomically assign an accountable administrator.
- Exactly one active baseline BillingEntity, linked to the active same-Organization Plan
  Assignment, with no provider call and no lazy creation.
- The first active Organization Membership MUST be derived from the active Account and the
  active Role Assignment.
- Account existence, or a separate mutable membership record, MUST NOT grant access.

### Membership is derived, never stored as a grant

The final clause forbids a mutable membership record from granting access. Membership is
therefore a projection of the active Account plus the active Role Assignment, resolved at
authorization time. It MUST NOT be a writable row, because a writable row can drift from the
Account and Assignment it is meant to reflect, and that drift would itself become a grant.
An implementation that caches Membership MUST treat the cache as non-authoritative.

## WF-002 Create And Activate Project Scope

Matrix rows: MTX-003 (AC-CAP-003), MTX-027 (AC-WF-002). Slice: S-03.
Structured contract: `specification/volume-ii/contracts/S-03.json`.
Governing authority: CAP-003, WF-002, PRULE-003, PRULE-004 in `v1.5-volume-i-frozen`.

This section is the canonical owner of the WF-002 application contract.

### Two distinct commands

`CreateProject` and `ActivateProject`. CAP-003 states activation is a distinct completion
condition and a later command after Source onboarding, so activation is never a continuation of
creation and the two permissions are never checked together. WF-002 Security Notes require
activation rights to be explicitly granted: holding `project.create` never implies
`project.activate`.

### Creation predicates

Display name NFC-normalized, Unicode-whitespace trimmed, 1-120 scalar values. `default_locale`
MUST equal `en-AU`. `reporting_time_zone` MUST equal `UTC`. Objective MUST equal
`discoverability_assessment`. Applicability false requires a 20-500 scalar reason and a null
profile; applicability true requires a null reason and a complete `local-business-profile-v1`.
Every other value is `project_local_profile_invalid`.

The profile's business name MUST equal the exact normalized Organization display name;
`address_text` is NFC with internal whitespace collapsed to one ASCII space, trimmed, 1-500
scalars; `telephone_e164` is `+` plus 8-15 ASCII digits with a first digit of 1-9;
`service_areas` is 1-50 distinct strings, each normalized by the display-name rule to 1-120
scalars and sorted by UTF-8 bytes. The profile records schema version, attesting Account,
server commit time and SHA-256 of canonical content.

The baseline Local Business Profile is immutable with the creation profile. Volume I defines no
silent provider-derived or administrator-amended replacement: a changed address, telephone,
service-area set or Organization display name requires a new Project in this baseline. A
profile-amendment capability would be a product change, not an implementation inference, and
MUST NOT be added here.

### Activation

One atomic transaction validating the current Project state version, the current
Source-membership version, the required fields, and at least one active same-Project Source,
then transitioning draft to active exactly once. Draft is the resting state on every failure:
no fixture creates an `activation_failed` state, and both WF-002 and AC-CAP-003 forbid
inventing one.

Only `activation_transaction_unavailable` retries, twice, at exactly 1 and 5 seconds, and every
retry rechecks current Source activity rather than reusing the earlier check.

### Error class mapping

Validation reasons to `F1-VALIDATION-400`; authority to `F1-AUTH-403`; state and race to
`F1-DOMAIN-409`; transaction dependency to `F1-DEPENDENCY-503`. The creation and activation
first-match orders are normative and are listed in the structured contract.

### Withheld under OD-014

WF-002 State Transitions define `Project.Draft -> Project.Active` and nothing else. Project
pause, resume and archive are named by 016 STATE_MODEL.md but have no command in Volume I, and
OD-014 reserves that choice under `UPSTREAM-V1-PROJECT-LIFECYCLE-003`.

S-03 therefore reaches its stated outcome -- a Project can be created and activated -- without
the withheld limb. No command, route, job, service path or entity method may effect a pause,
resume or archive transition, and `ProjectPaused`, `ProjectReactivated` and `ProjectArchived`
MUST NOT be emitted. The `projects` table recognizes `paused` and `archived` because the state
model defines them and guards elsewhere read them; no path may enter either.

## CAP-003 Project Setup

Matrix row: MTX-003 (AC-CAP-003). Slice: S-03.
Structured contract: `specification/volume-ii/contracts/S-03.json`.

CAP-003 defines no interface of its own; its obligations are discharged by the WF-002 contract
above. Recorded separately because the capability owns two conditions the workflow does not
restate: the Organization MUST be active and the actor MUST hold `project.create` at creation,
and activation is eligible only after CAP-004, CAP-005 and CAP-006 have produced at least one
active same-Project Source. Its Failure Condition is that activation fails or the Project
remains draft; draft is the resting state and there is no `activation_failed` state.

## PRULE-003 Project Profile And Activation Prerequisites

Matrix row: MTX-054 (AC-PRULE-003). Slice: S-03.
Structured contract: `specification/volume-ii/contracts/S-03.json`.
Governing authority: PRULE-003, sourced from DM-REQ-011 and SM-REQ-003.

Two obligations. Project creation MUST validate the complete local-applicability and profile
contract. Activation MUST remain draft until the exact onboarding and Source prerequisites pass
**under current versions**.

The "under current versions" clause is the load-bearing one: a prerequisite that passed a moment
ago is not a prerequisite that passes at commit. Both the Project state version and the
Source-membership version are validated inside the activation transaction, and each retry
rechecks current Source activity, so a Source deactivated between check and commit never
activates a Project.

## PRULE-004 Project Scope Within Verified Source Boundaries

Matrix row: MTX-055 (AC-PRULE-004). Slice: S-03.
Structured contract: `specification/volume-ii/contracts/S-03.json`.
Governing authority: PRULE-004, sourced from SB-REQ-003 and SM-REQ-002.

Project scope MUST remain within verified Source boundaries. This section owns the WF-002 limb,
enforced at activation; the WF-004 limb, Source scope management, is owned by S-06.

The invariant is evaluated inside the activation transaction and guarded by the
Source-membership version, so scope cannot widen between check and commit. A Source in another
Project or another Organization can never bound this Project, which makes the invariant a tenant
control as well as a scope control. The selected active Source IDs are logged at activation,
which is what makes the boundary auditable after the fact.

## CAP-004 Website Or Property Onboarding

Matrix row: MTX-004 (AC-CAP-004). Slice: S-04.
Structured contract: `specification/volume-ii/contracts/S-04.json`.
Governing authority: CAP-004 and the `source-registration-v1` contract in
`v1.5-volume-i-frozen`. PRULE-004 is owned by [S-03](#prule-004-project-scope-within-verified-source-boundaries);
PRULE-005 belongs to CAP-005/WF-003 and is owned by S-05.

This section is the canonical owner of the Source registration contract.

### One command, one outcome

`Workflows::Wf004::RegisterSource` produces exactly one proposed Source or one enumerated
no-Source rejection. Volume I states that no separate Onboarding Request and no plural candidate
entity is created, so no intermediate aggregate may stage a registration. Registration never
verifies, activates, crawls or creates Evidence; each is a separate command in a later slice.

### Grammar and normalization

`https://<host>` or `https://<host>/`, with an explicit `:443` accepted and removed. User
information, query, fragment, a nonroot path, wildcard, IP literal, bracketed literal, non-HTTPS
scheme, nondefault port, ASCII control or space, or any other URI component is rejected.

Host normalization is `ascii-host-v1`: lowercase A-Z, remove one terminal dot, require 1-253
remaining bytes and at least two dot-separated labels, and require every label to be 1-63 ASCII
letters, digits or hyphens without a leading or trailing hyphen. A pre-encoded `xn--` label is
allowed. Raw Unicode is `source_host_non_ascii` and MUST NOT be normalized: Volume I fixes that
reason precisely so implementations cannot diverge on IDNA handling, and normalizing it would be
an implementation choice changing product behaviour.

The canonical root URI is `https://<lowercase_host>/`.

### Provenance is the audit anchor

Registration provenance is exactly `origin=human_command`, registering Account ID, command ID,
idempotency key, Identity/Session authorization-decision ID, registered time and correlation ID.
It is immutable and derived from the command and the authorization decision rather than supplied
by the caller, so every Source carries proof of the decision that created it.

### Uniqueness and removal

The uniqueness key is `(project_id, canonical_host)` across every Source not `removed`, and the
check and insert serialize. Concurrent same-key commands create exactly one Source; the loser
receives `F1-DOMAIN-409 / source_host_already_registered`. A committed removed Source does not
reopen: a later command creates a new Source with a new ID and new provenance and never attaches
to the removed lineage.

### Reading paused Project state

Registration requires a same-Organization Project in `draft`, `active` or `paused`. Reading the
paused state as a precondition guard is exactly the use OD-014 permits: the state is represented
and read, never effected. Project activation is expressly not a prerequisite for registration.

## WF-003 Verify Property Ownership Or Control

Matrix rows: MTX-005 (AC-CAP-005), MTX-028 (AC-WF-003). Slice: S-05.
Structured contract: `specification/volume-ii/contracts/S-05.json`.
Governing authority: CAP-005, WF-003, the Ownership-Verification Evidence Contract in
SCORE_EVIDENCE_MODEL.md, PRULE-005, PRULE-020, and OD-001 (ratified, ADR-019).

This section is the canonical owner of the WF-003 application contract.

### OD-001 is ratified, not pending

OD-001's Current Status is "Ratified on 2026-07-17 ... ratified as specified", Approved Option 2
(DNS TXT and HTTPS file), Blocking Impact "None. OD-001 is ratified". It is not one of the five
pending decisions. There is therefore no interim to preserve and no undecided limb to withhold:
the ratified method set is implemented exactly. Methods outside `dns_txt` and `http_file` are
out of baseline scope rather than blocked pending approval, and adding a third would be a
controlled Volume I change.

The word "interim" survives in PRULE-005, PRULE-020 and the evidence-contract preamble as prose
written before ratification. ADR-019 integrated OD-001 "as specified", so the content those
documents carry is the ratified baseline. Volume I is frozen; the stale wording is recorded here
as an observation and is not corrected by this pass.

### No inbound route exists

Ownership verification requires no public HTTP route at all. The challenge is proved at the
customer's own DNS zone or HTTPS origin and F1 observes it outbound. Volume I defines no inbound
callback, webhook or confirmation endpoint, and inventing one would add an unauthenticated
attack surface to a security-sensitive flow.

### Challenge handling

The challenge token carries at least 128 bits of cryptographic entropy and is never persisted or
logged in plaintext. Creation envelope-encrypts it under a request-specific key and persists only
the restricted ciphertext reference, key identifier and digest, returning the plaintext through
the authorized creation response.

Exactly two redelivery paths exist: exact creation-command replay by the original actor while the
Request is pending, and a separate nonmutating retrieval requiring the initiator or an
OrganizationAdmin holding `source.verify` in the Request Organization. Both reauthorize every
read, append a restricted security access log, and change no domain state. Neither returns any
other Request's material.

On any terminal transition the same transaction disables redelivery immediately and schedules
cryptographic deletion; key and ciphertext are destroyed within 60 seconds while the digest and
access audit remain. Terminal replay returns identifiers and status but never challenge material.

### Success is inseparable

A matched observation commits, in one transaction: the `verification_observation` Evidence, the
Request completion fields, `SourceVerificationObserved`, Request `verified` with reason
`matched`, immediate redelivery disablement, `SourceVerified`, materialization of
`source-scope-interim-v1`, and `Source.Proposed -> Source.Verified`. Volume I states that none of
these may appear without the others, which is why this is a multi-root atomic commit and an
explicit specialisation of the EM-III-011 single-aggregate default.

### Failure never touches the Source

Mismatch, dependency failure, denial and expiry each leave the Source `proposed`. DNS, HTTP,
resolver, certificate, status, content and timeout outcomes never write `failed`; they remain
pending until success, cancellation or expiry. `failed` is writable only by the
integrity-validation service and only with `request_digest_unavailable` or
`request_schema_unsupported`, which are the exhaustive failed reasons.

A provider timeout is recorded as an observed outcome with network outcome `timeout`. It is never
treated as proof of absence.

## CAP-005 Ownership Or Control Verification

Matrix row: MTX-005 (AC-CAP-005). Slice: S-05.
Structured contract: `specification/volume-ii/contracts/S-05.json`.

CAP-005 defines no interface of its own; its obligations are discharged by the WF-003 contract
above. Recorded separately for its own Security Implication: verification prevents unauthorized
domain scanning. A Request may be created only for a same-Organization proposed Source, so F1
never observes a host a tenant has not registered.

## Source Verification State Transition

Matrix row: MTX-051 (AC-SM-008). Slice: S-05.
Structured contract: `specification/volume-ii/contracts/S-05.json`.
Governing authority: the canonical Source state machine and the Ownership-Verification Evidence
Contract.

`Source.Proposed -> Source.Verified`, and nothing else. The transition is effected only inside the
observation-completion transaction on a matched observation. No command, job, service or
administrative path may transition a Source to `verified` directly.

No intermediate `verifying` state and no Boolean `is_verified` flag exists. Volume I defines a
state machine, and collapsing it into a flag would lose the canonical state and its transition
event. The transition never occurs without `SourceVerified` and the event never occurs without
the transition.

It is naturally idempotent through its state guard: it fires only from `proposed`, so a repeated
matched observation after success does not re-transition, re-emit or re-materialize the scope
policy. A concurrent second completion finds the Source no longer proposed. A stale Source state
version rejects the completion with no side effect.
