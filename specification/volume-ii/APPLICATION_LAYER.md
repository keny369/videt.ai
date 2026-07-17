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

## WF-004 Manage Source Scope

Matrix rows: MTX-006 (AC-CAP-006), MTX-029 (AC-WF-004). Slice: S-06.
Structured contract: `specification/volume-ii/contracts/S-06.json`.
Governing authority: CAP-006, WF-004, the Source Scope Change Contract, PRULE-006, PRULE-021,
and the WF-004 limb of PRULE-004.

This section is the canonical owner of the WF-004 application contract. Registration is WF-004's
first path but is owned by [CAP-004](#cap-004-website-or-property-onboarding) in S-04.

### Discovery here means scope, not crawling

CAP-006 Product Behavior is "Resolve scope as the intersection of verified Source, Organization,
and Project policy". WF-004 performs no outbound retrieval: its paths are registration, scope
change and Source lifecycle. Outbound crawling is CAP-007/WF-005 and belongs to S-07.

"Discovered canonical URLs" is an **input** to the scope predicate, produced by the S-07 crawler
and evaluated against the policy this slice owns. S-06 therefore defines no crawler, sitemap,
redirect-following or URL-expansion behaviour. Importing generic crawler conventions here would
invent product behaviour that Volume I does not define.

### Dual control is asymmetric

A contraction within an already verified boundary, submitted by an OrganizationAdmin or
MarketingOperator, may be approved and activated atomically in its creation transaction, without
dual control. Narrowing scope cannot leak a boundary, so it needs no second party.

A same-host expansion by a non-admin remains pending for an OrganizationAdmin decision, and the
approving OrganizationAdmin MUST be a different Account. An OrganizationAdmin requester may
approve its own expansion atomically. A TechnicalImplementer may propose either but can neither
approve nor activate a policy, and cannot mutate Source lifecycle at all.

The dual-control predicate lives in `DecideSourceScopeChange`, not at a transport edge, so no
service or job path can reach an approval without it.

### A new host is never an expansion

A new host is a new Source and MUST pass WF-003 verification. It cannot be approved as a policy
expansion. HTTP or any other scheme is `unsupported_source_scheme` and does not create a second
same-host Source. This, plus the one-exact-`canonical_host` rule, is what makes scope incapable
of crossing a tenant boundary by URL rather than by permission.

### Expiry wins

At exactly `due_at_utc` the source-scope lifecycle service's expiry transition wins over
approval, rejection and cancellation. It emits `SourceScopeChangeExpired` once and changes no
policy or Source state. Every terminal request is immutable.

### Valid Source paths only

`Verified -> Active`; `Active -> Disabled`; `Disabled -> Active` or `Disabled -> Removed`.
Direct `Active -> Removed` and `Active -> Verified` are invalid. Removal is allowed only from
disabled, and re-registration never attaches to the removed lineage.

Disable and remove apply the same next-checkpoint restriction semantics as a scope contraction:
no new URL is scheduled, in-flight content is discarded from Evaluation input, and already
immutable history remains. The affected running Crawls are recorded in the decision record rather
than reached into.

### PRULE-004's second limb closes here

S-03 owns MTX-055 (AC-PRULE-004) and contracted its WF-002 limb -- a Project may not activate
outside verified Source boundaries -- deferring the WF-004 limb to this slice. MTX-029 owns that
limb: a Source Scope Policy may not be widened outside the verified boundary. The rule is not
copied into both slices; each owns one limb, and both use the same canonical terms and version
semantics.

## CAP-006 Source Discovery And Scope Control

Matrix row: MTX-006 (AC-CAP-006). Slice: S-06.
Structured contract: `specification/volume-ii/contracts/S-06.json`.

CAP-006 defines no interface of its own; its obligations are discharged by the WF-004 contract
above. Its Failure Condition is that the Source remains disabled or removed -- both canonical
Source states, neither an invented failure state.

## PRULE-006 Source Lifecycle Transitions

Matrix row: MTX-057 (AC-PRULE-006). Slice: S-06.
Structured contract: `specification/volume-ii/contracts/S-06.json`.
Governing authority: PRULE-006, sourced from SM-REQ-001.

Source lifecycle transitions MUST follow defined valid state paths only. Every allowed
transition succeeds exactly once; every unlisted or stale transition is denied **and audited**.
The audit obligation is part of the rule, not an addition: a silently rejected transition would
satisfy the first clause and breach the second.

## WF-005 Execute Crawl And Ingestion

Matrix rows: MTX-007 (AC-CAP-007), MTX-030 (AC-WF-005). Slice: S-07.
Structured contract: `specification/volume-ii/contracts/S-07.json`.
Governing authority: CAP-007, CAP-008, WF-005, `crawl-policy-v1`, `destination-safety-v1`, the
robots and sitemap contracts, PRULE-007, PRULE-008, PRULE-009, PRULE-022.

This section is the canonical owner of the WF-005 application contract. S-07 owns the outbound
crawl surface; the scope predicate it evaluates against is owned by
[PRULE-021](SECURITY_PERFORMANCE.md#prule-021-source-scope-predicate) in S-06 and is consumed
here without redefinition.

### The gate is at the running transition, not at queueing

Queueing persists an authorized no-usage Crawl: no reservation, no Evaluation, no fetch.
Immediately before `Queued -> Running` the workflow re-resolves policy and either atomically
obtains the `crawl.start` Decision and reservation for a root, or validates the parent
`reassessment.start` reservation. An accepted root start creates exactly one pending Evaluation
keyed by `(crawl_id, evaluation_kind=initial_assessment)` **in that same commit**.

An authorization or scope result from queue time is never trusted at execution time. Every URL is
validated against the **pinned and current restrictive** scope, and a new restriction affects
queued work immediately and running work at the next checkpoint.

### Two distinct root guards

`reassessment_required` keys on an existing promoted Evaluation/Issue-set/ScoreSnapshot pair.
Under OD-018 a second guard keys on a **pending or running** initial Evaluation and returns
`F1-DOMAIN-409 / initial_evaluation_already_running`. They are different: the second never keys
on a completed Evaluation, so a root `crawl.recover` after a *failed* initial Evaluation stays
admissible. It is re-checked at the running commit, and a replayed root command returns its
stored result rather than a rejection.

### Recovery creates, never reopens

`crawl.recover` creates a **new linked** `Crawl.Queued` attempt; it does not transition the old
record. A root recovery creates a new linked pending Evaluation only at its accepted start.
`ingestion.recover` replays only a retained dead-letter job within its 24-hour staging bound.
Neither moves a terminal Crawl or a succeeded job backward. Recovery completion carries
`recovery_of_id` and the replay generation.

### Technical records are not product entities

The crawl frontier, the per-URL attempt, the worker lease and the byte reservation are
implementation-owned infrastructure. Volume I names no frontier, lease or reservation entity and
DM-REQ-001 defines none, so none may be promoted into the domain model. Queue depth, lease state
and scheduler timing are technical telemetry and MUST NOT be emitted as domain events.

## CAP-007 Crawl Initiation

Matrix row: MTX-007 (AC-CAP-007). Slice: S-07.
Structured contract: `specification/volume-ii/contracts/S-07.json`.

CAP-007 defines no interface of its own; its obligations are discharged by the WF-005 contract
above. Its Failure Condition is exact: zero valid Documents, all Source roots fail, or a
nonrecoverable pre-output policy or integrity failure produces failed, and no terminal Crawl is
moved back to running.

## CAP-008 Crawl Progress And Recovery

Matrix row: MTX-008 (AC-CAP-008). Slice: S-07.
Structured contract: `specification/volume-ii/contracts/S-07.json`.
Governing authority: CAP-008, WF-005, PRULE-009, PRULE-022, and OD-027 (pending).

This section owns the crawl-side progress and recovery obligations and the durable handoff into
parsing. Parsing and indexing execution is WF-006, owned by S-08.

### The durable handoff is the succeeded job

`ingestion-interim-v1` requires that only a succeeded IngestionJob with valid `source_document`
Evidence enters parsing. The job record with its Evidence **is** the handoff; there is no
separate queue message to lose. That is what makes the crash matrix answerable: a crash after
retrieval but before the job succeeds leaves nothing for parsing to observe and the fetch is
retried; a crash after it succeeds leaves a committed job whose redelivery re-enters the same
identity and advances the Document no more than once.

### Readiness does not wait for the projection

Ready-full, ready-partial and blocked derive from the complete parse and Evidence manifest
**without waiting for the Retrieval projection**. A lagging projection therefore never blocks or
falsifies readiness, and concurrent completion or replay cannot change an earlier Evaluation
Input Snapshot.

### Withheld under OD-027

OD-027 asks whether ParsingJob-to-IndexingJob persists as one-to-many keyed by
`(parsed_artifact_id, content_sha256, index_target_id, index_schema_version)` or as at most one
keyed by `parsing_job_id`. Its Blocking Impact records Volume II **no**, implementation **no**
under the safe interim, production **no** while `indexing-interim-v1` pins both index keys, and
feature-blocks exactly three artifacts:

- a `has_one` narrowing,
- a `unique (parsing_job_id)` constraint,
- any second IndexingJob per ParsingJob.

Those three are withheld and MUST NOT be implemented, migrated or tested as settled. Everything
else in CAP-008 is contracted. The slice is **not** blocked: `indexing-interim-v1` pins both
index keys, which is a working interim, and completing the withheld limb requires ratification
plus controlled Volume I integration rather than an implementation choice.

## PRULE-007 Crawl Command And Reservation Contract

Matrix row: MTX-058 (AC-PRULE-007). Slice: S-07.
Structured contract: `specification/volume-ii/contracts/S-07.json`.

Queueing may persist an authorized no-usage Crawl, but current policy **and** an allowed root or
parent entitlement reservation are mandatory before `Queued -> Running` or any fetch or provider
side effect. An accepted root start atomically creates one pending initial Evaluation; an
existing promoted pair requires WF-011 and creates no root Crawl or Evaluation.

## PRULE-009 Partial Outcome Preservation

Matrix row: MTX-060 (AC-PRULE-009). Slice: S-07 (WF-005 limb).
Structured contract: `specification/volume-ii/contracts/S-07.json`.

Partial outcomes preserve successful subsets. Every failed Source, URL, Document, ParsingJob,
count and reason is retained rather than collapsed. Successful same-version Documents advance
ingested-to-parsed and parsed-to-indexed **exactly once**, guarded on the Document by its version
rather than by delivery deduplication. Coverage, completion and readiness derive exactly from the
retained manifest, partial or blocked input is never presented as full, and **Indexing does not
gate Evaluation**.

The WF-006 parsing limb is owned by S-08 and the WF-017 incident limb by S-24. The OD-027 limb is
withheld: the parsed-to-indexed exactly-once clause is contracted for the interim keys
`indexing-interim-v1` pins, and the final multiplicity is not implemented.

## WF-006 Process Parsing And Validation Pipeline

Matrix row: MTX-031 (AC-WF-006). Slice: S-08.
Structured contract: `specification/volume-ii/contracts/S-08.json`.
Governing authority: WF-006, `parsing-interim-v1`, `indexing-interim-v1`, and the OD-027
boundary established by S-07.

This section is the canonical owner of the WF-006 application contract. It consumes the durable
handoff owned by [CAP-008](#cap-008-crawl-progress-and-recovery): a succeeded IngestionJob with
valid `source_document` Evidence.

### Indexing never gates Evaluation

This is the load-bearing separation. Readiness derives from the complete parse and Evidence
manifest **without waiting for IndexingJob completion**, and an IndexingJob's result **never
mutates the sealed snapshot**. Indexing is an asynchronous Retrieval Context projection: a
missing or dead-letter index never disappears from telemetry and may block an explicitly
retrieval-dependent future action, but cannot change a sealed Evaluation.

Volume I closes the obvious loophole itself: an implementation **MUST NOT wait for indexing in
one code path and bypass it in another**.

### Two pinned keys, one withheld limb

`parsing-interim-v1` pins exactly one ParsingJob per
`(document_id, content_digest, parser_definition_version)`. `indexing-interim-v1` pins exactly
one IndexingJob per `(parsed_artifact_id, normalized_payload_sha256, index_target_id=tenant-retrieval,
index_schema_version=retrieval-index-interim-v1)`.

OD-027 asks whether the final relation is that four-part key or `parsing_job_id`. Its withheld
limb -- a `has_one` narrowing, a `unique (parsing_job_id)` constraint, any second IndexingJob per
ParsingJob -- is carried forward from S-07 unchanged and is **not reopened here**. Both interim
keys are pinned and working, so S-08 reaches its outcome and is not blocked.

### The parser consumes attacker-controlled bytes

Input sanitation and untrusted-content isolation are mandatory. JSON-LD remote contexts are
**never** fetched; DTDs and external entities are disabled; malformed JSON-LD produces one
malformed item with null name and url **rather than disappearing**. Quarantined or invalid
Evidence cannot produce a Parsed Artifact.

### Nothing is silently dropped

An `input_manifest_invalid` predicate -- a missing tuple, duplicate Document, cross-Organization
reference, digest mismatch, or a manifest omitting a succeeded IngestionJob -- **blocks readiness
rather than dropping the member**. A derivation or schema failure is recorded by Document, Source
and reason, creates no substitute Evidence, and becomes a handled Check input error rather than
silently omitting the expected result key.

### Sealed means sealed

Later parsing success is visible **only** to a new Evaluation Input Snapshot and Evaluation;
later indexing success advances **only** the Retrieval projection. Neither reaches back. The
initial Evaluation starts only in WF-007, and reassessment emits no second start.

## WF-014 Deliver Notifications

Matrix rows: MTX-021 (AC-CAP-021), MTX-039 (AC-WF-014). Slice: S-19.
Structured contract: `specification/volume-ii/contracts/S-19.json`.
Governing authority: CAP-021, WF-014, `notification-policy-v1`, PRULE-034, and OD-023 (pending).

This section is the canonical owner of the WF-014 application contract.

### Withheld under OD-023

OD-023 is pending. The register maps it to CAP-021 and WF-014 because this is the capability
whose Integration holds the Mailgun Credential -- not because notification delivery is itself
undecided. The withheld limb is exactly credential rotation **begin** and **complete** under
`UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009`.

Permitted and contracted: delivery, routing, retry and observability against an already-active
Credential; representing a Credential; read-only status where Volume I authorises it.

Prohibited: rotation initiation, rotation completion, token semantics that pre-empt the decision,
and any route, command, job or event performing the withheld behaviour.

Delivery is therefore fully contracted and the slice is **not** blocked.

### Provider semantics are not product semantics

Mailgun supplies no exactly-once guarantee, so none is promised. Product outcome semantics stay
separate from provider transport semantics: a provider acceptance ambiguity is contracted as an
ambiguous outcome with its reconciliation, never as a delivered fact. Provider webhooks, queue
depth and delivery metrics are technical telemetry and are not domain events.

## WF-017 Handle Incident And Recovery

Matrix row: MTX-042 (AC-WF-017). Slice: S-24.
Structured contract: `specification/volume-ii/contracts/S-24.json`.
Governing authority: WF-017, the Incident Contract, the High-Risk Remediation Approval Contract,
`emergency-access-v1`, PRULE-037, PRULE-038, and OD-012, OD-013 and OD-020 (all resolved).

This section is the canonical owner of the WF-017 application contract.

### "Recovery" here is diagnostic, not executional

Despite the slice title, S-24 contracts no recovery command of its own. WF-017's
`link_named_remediation` **links** an already-committed WF-005/006/013/014/016 result; it invokes
nothing. `crawl.recover` and `ingestion.recover` belong to
[WF-005](#wf-005-execute-crawl-and-ingestion) in S-07. The "Recovery" in this workflow is the
diagnostic playbook's Recovery Path, which is operator-driven and carries no retry schedule.

### Incident scope is Organization-owned

Under OD-013 Option 1 there is no platform-owned canonical record. A platform-wide Incident is
represented as coordinated per-Organization records linked by `correlation_id`. WF-017's Incident
Contract field list still opens "Organization scope or explicit platform-wide scope", which is
pre-ratification prose; its own Domain Events paragraph and AC-WF-017 impose Option 1, and Option
1 prevails.

### The operational escalation record has no defined home

WF-017 requires exactly one operational escalation record per failed-step generation but names no
table, event or permission for it. The obligation and its uniqueness key are contracted; the
physical record is deferred to the Volume II baseline rather than invented here.

## PRULE-010 Check Materialization, Canonical Order And Determinism


Matrix row: MTX-061 (AC-PRULE-010). Slice: S-09.
Structured contract: `specification/volume-ii/contracts/S-09.json`.
Governing authority: PRULE-010, CAP-009, CAP-010, CAP-011, WF-007 Primary Path steps 1-3, the Check
Result Contract, the Check Definition And Check Catalog Contract, the Frozen Check Applicability
Snapshot, `check-executor-interim-v1`, and OD-010 (**ratified**).

This section is the canonical owner of the Check catalogue, applicability, identity and executor
contract. It consumes the sealed Evaluation Input Snapshot owned by
[WF-006](#wf-006-process-parsing-and-validation-pipeline) in S-08 and is consumed by
[WF-007](#wf-007-generate-issues-from-checks-and-adjudicate) in S-12.

### The ownership line between S-09 and S-12

WF-007 spans two slices. S-09 owns Primary Path steps 1 through 3 — catalogue validation,
applicability sealing, result-key materialization and pure execution. S-12 owns everything the
orchestration does around them: the Evaluation lifecycle transitions, Issue derivation and
fingerprinting, the adjudication subflow and the Issue-set seal. Both use the `Workflows::Wf007::`
command namespace and neither redefines the other's commands.

### OD-010 is ratified; the unavailable score is the approved baseline

`Current Status` records OD-010 **Ratified 2026-07-17, ratified as specified. Blocking Impact:
None.** Option 1 is approved: `check-catalog-v1` with exactly `CHK-TI-001`, `CHK-CQ-001`,
`CHK-TR-001`, `CHK-SP-001`, `CHK-AIP-001`, `CHK-AS-001` and `CHK-LP-001`.

Read the ratified behaviour precisely. It **approves** the bundle-nothing state *and its
consequence*: `external-measurement-v1` bundles no query, intent, listing, provider or adapter set,
so implementations do not invent one, and **the numeric score therefore remains unavailable**. That
is settled baseline behaviour, not a withheld limb. Concretely:

- `CHK-SP-001`, `CHK-AIP-001` and `CHK-AS-001` are always applicable, deterministically select no
  Evidence, and each persists a handled one-attempt `input_evidence_missing` error.
- `CHK-LP-001` does the same **only** when its frozen applicability decision is true, and otherwise
  persists its canonical `not_applicable/local_presence_not_applicable` Result without Evidence.
- Those insufficient pillars make the overall score unavailable, and no Recommendation or Priority
  Decision publishes from an unavailable calculation.

Frozen prose calling the catalogue `status: active_interim` or "the mandatory deterministic interim
Catalog pending OD-010 approval" is pre-ratification wording. It does **not** reopen the decision,
and a contract that withholds behaviour on its authority withholds behaviour the owner approved.
Equally, the ratification does **not** broaden the catalogue: seven Definitions, no more.

A Measurement Set may later activate as exact signed configuration. Check execution still makes no
provider call.

### The preimage is the authority; the hash is an index

The Check Result uniqueness preimage is exactly Evaluation ID, Evaluation Input Snapshot ID, Check
Applicability Snapshot ID, Check Catalog version, Check Definition ID and version, canonical subject
type and key, and pillar ID **in that order**. `check_result_key_sha256` is its canonical-JSON
SHA-256. The **complete retained preimage, not the hash**, is uniqueness authority within the
Evaluation, so the unique index MUST NOT be built on the hash alone.

Materialization atomically creates or returns one Check Result identity for that preimage **before
execution**. Exact or concurrent replay with the same deterministic input returns that identity and
its terminal semantic output and emits no second `CheckResultCreated`. A *different* deterministic
input for the same preimage is `F1-DATA-409 / check_result_input_conflict` and changes neither
Result. A same hash with a *different* retained preimage never merges: it creates distinct collision
records, emits restricted `CheckResultFingerprintCollision` telemetry, and fails the affected
Evaluation as `check_result_key_collision` **before** Check execution.

### Checks make no provider call. Ever.

This is product authority, not a performance preference. `check-executor-interim-v1` states that
Checks are pure evaluations of the frozen applicability entry and Evidence and MUST NOT perform a
network request, provider call, mutable read, clock-dependent query or tenant-policy mutation.
CAP-010's Non-goal names external-provider selection and network collection during Check execution.
`external-observation-v1` opens "No Check selects or calls a network provider." Collection is WF-006
intake, owned by S-08; S-09 consumes only frozen Evidence.

### Two error classes that must not be confused

A **handled** Check error is terminal and does **not** fail the Evaluation: the first-match semantic
order `input_evidence_missing`, `input_evidence_stale`, `input_evidence_indeterminate`,
`input_evidence_invalid`, `normalized_input_invalid`, `output_schema_invalid`, plus retryable
`check_dependency_unavailable` and `check_internal_timeout`. It makes its pillar insufficient and the
overall score unavailable, and creates no Issue.

A **boundary** failure fails the Evaluation before any Check or Issue write:
`check_catalog_unavailable`, `check_catalog_integrity_failure`,
`check_applicability_snapshot_invalid`, `check_result_input_conflict`, `check_result_key_collision`,
`check_nondeterministic_output`, `idempotency_conflict`, and any cross-Organization reference. No
partially validated Catalog executes.

The distinction is load-bearing: an implementation that promotes a handled error into an Evaluation
failure destroys the eligible subset, and one that demotes a boundary failure into a handled error
publishes a finding from a scheme that has demonstrably failed.

### The bounded retry is the only retry inside an Evaluation

Each attempt has five elapsed seconds; at exactly five seconds `check_internal_timeout` wins over
completion and a later completion is discarded. Only `check_dependency_unavailable` and
`check_internal_timeout` retry — one initial attempt plus exactly one retry starting one second
after the failed attempt completes, reusing the identical applicability entry, Evidence tuple, input
hash and attempt identity lineage. No other reason retries.

### Technical records are not product entities

The executor's per-attempt telemetry record is implementation-owned infrastructure. It carries
Definition, subject, attempt number, queued, started and completed times, terminal reason, input hash
and correlation ID, and it MUST NOT be emitted as a domain event. `CheckResultCreated` is emitted
only with the one persisted Result; retrying or completing late cannot duplicate it.


## CAP-009 Technical Inspection


Matrix row: MTX-009 (AC-CAP-009). Slice: S-09.
Structured contract: `specification/volume-ii/contracts/S-09.json`.

CAP-009 defines no interface of its own; its obligations are discharged by the PRULE-010 contract
above. It executes `CHK-TI-001@1.0.0` once per active Source, subject type `source`, key the opaque
Source ID unchanged, pillar `technical_integrity`.

Its outcome order is exact and the error **precedes** failed and pass evaluation:
`error/internal_link_coverage_incomplete` with `error_reason_code=input_evidence_indeterminate` when
relevant coverage is partial or any target is unobserved; `failed/broken_internal_links` when
coverage is full and one or more targets are absent; `passed/internal_links_resolve` when coverage is
full, every target is reachable and the absent set is empty. An implementation that evaluates the
absent set before checking coverage reports a pass on a partial crawl.

CAP-009's Failure Condition is exact: missing, invalid or cross-tenant input yields the
catalog-defined `error`; catalog, integrity or cardinality failure follows the WF-007 Evaluation
failure path and never silently omits a Result.


## CAP-010 Content And External Presence Inspection


Matrix row: MTX-010 (AC-CAP-010). Slice: S-09.
Structured contract: `specification/volume-ii/contracts/S-09.json`.
Governing authority: CAP-010, `CHK-CQ-001`, `CHK-SP-001`, `CHK-AIP-001`, `CHK-AS-001`, `CHK-LP-001`,
`external-observation-v1`, and OD-010 (**ratified**).

CAP-010 defines no interface of its own. It owns five Definitions: `CHK-CQ-001` one Result per
successfully parsed Document with subject type `url`, and `CHK-SP-001`, `CHK-AIP-001`, `CHK-AS-001`
and `CHK-LP-001` one Project Result each with Source and Document IDs null.

### CAP-009 is not a prerequisite

CAP-010's Preconditions say so expressly: CAP-009 completion is not a prerequisite and concurrent
completion order is irrelevant. Each Definition is materialized on its own key and executes against
its own frozen tuple, so the two capabilities may interleave freely without changing either output.

### Four Definitions read a Measurement Set that the baseline does not bundle

Under the ratified OD-010 baseline this is the approved outcome, described in full at
[PRULE-010](#prule-010-check-materialization-canonical-order-and-determinism). The intake mapping is
exact and is the reason the outcome is *deterministic* rather than merely absent: a missing payload
is `input_evidence_missing`; a stale payload is `input_evidence_stale`; partial coverage, any
indeterminate item or a key-set mismatch is `input_evidence_indeterminate`; invalid same-tenant
digest, schema or provenance is `input_evidence_invalid`. All four are handled errors with no Issue
that make the applicable pillar insufficient.

Freshness is an equality boundary, not an approximation: an Evaluation Input Snapshot may consume an
observation only when `observed_at_utc <= snapshot_sealed_at_utc < fresh_until_utc`, and equality at
`fresh_until_utc` is **stale**.

The one place the measurement path escalates instead of degrading: a cross-Organization,
cross-Project or cross-Evaluation `external-observation-v1` payload is tenant-integrity failure and
fails the Evaluation through the applicability boundary rather than creating a handled Result.

`external_measurement.submit` and `measurement_set.activate` govern WF-006 intake and are owned by
S-08. Neither is reachable from Check execution.

### `not_applicable` belongs to exactly one Definition

`not_applicable` is valid only for `CHK-LP-001`, and only from a validly false frozen applicability
decision carrying its nonblank reason. `CHK-TI-001`, `CHK-CQ-001`, `CHK-TR-001`, `CHK-SP-001`,
`CHK-AIP-001` and `CHK-AS-001` MUST return passed, failed or error, and an attempted not-applicable
from any of them is `check_catalog_integrity_failure`.


## CAP-011 Structured-Data Inspection


Matrix row: MTX-011 (AC-CAP-011). Slice: S-09.
Structured contract: `specification/volume-ii/contracts/S-09.json`.

CAP-011 defines no interface of its own. It executes `CHK-TR-001@1.0.0` once per active Source,
subject type `source`, key the Source ID, pillar `trust_signals`.

Its outputs are **first-match ordered**: `failed/organization_schema_missing` for zero nodes;
`passed/organization_identity_consistent` when at least one node is schema-valid and both normalized
values exactly match; `failed/organization_schema_invalid` when no node is schema-valid; otherwise
`failed/organization_identity_mismatch`. The order matters where two branches would both match.

Zero observed nodes is a **valid observation**, not an invalid payload: it produces a failed Result
at `medium` impact. What invalidates the payload is different — missing expected identity or profile
values, an ambiguous profile version, an invalid locator, or inconsistent normalization.

A Source whose root input is missing still has an expected entry, so it produces an explicit handled
error rather than disappearing from the applicability set.


## PRULE-013 CHK-TR-001 Result Context


Matrix row: MTX-064 (AC-PRULE-013). Slice: S-09.
Structured contract: `specification/volume-ii/contracts/S-09.json`.

Every `CHK-TR-001` Check Result MUST persist its exact subject, outcome code, normalized identity
observation, catalog, definition and schema versions, input hash, and valid Source-root Evidence
context. Any omission prevents decision-grade status and is `output_schema_invalid`.

The rule's point is that the persisted context is the **sole** authority for that Result's history:
`impact-CHK-TR-001-v1` mapping and `REC-CHK-TR-001-v1` rendering resolve entirely from
`outcome_code`, `canonical_subject_key` and the normalized observation on this record, so a later
public-identity-profile change cannot retroactively reinterpret it. Completeness is therefore asserted
one required field at a time, because an aggregate fixture passes while a single field is silently
defaulted.


## PRULE-012 Impact And Confidence Metadata


Matrix row: MTX-063 (AC-PRULE-012). Slice: S-09 (owner). Consumed by S-12 at Issue derivation.
Structured contract: `specification/volume-ii/contracts/S-09.json`.
Governing authority: PRULE-012, `confidence-policy-v1`, `effort-interim-v1`, the impact rule of each
Definition, OD-003 (**ratified**) and OD-010 (**ratified**).

Every failed catalog Check used for Issue creation or downstream decisioning carries the Definition's
exact impact and valid interim confidence metadata, or the explicit missing/invalid fallback, with
exact band boundaries and policy versions.

### OD-003 as ratified

Numeric confidence `0.0000`-`1.0000`, rounded half up to four decimal places **before** band mapping:
`low` for `0.0000 <= value < 0.6000`, `medium` for `0.6000 <= value < 0.8500`, `high` for
`0.8500 <= value <= 1.0000`. All seven catalog Definitions use `1.0000`, `confidence_status=valid`,
band `high` for passed, failed and not-applicable results; handled errors use the null value,
`confidence_status=missing`, band `low` fallback.

Missing or invalid confidence maps to display band `low`, creates an Issue with adjudication status
`review_required`, and records `confidence_status`. The raw invalid value MUST NOT be used
downstream. Under the ratified OD-009 policy that withheld candidate contributes zero to score and
priority until it becomes eligible.

All decimal calculations use base-10 decimal arithmetic. Binary floating-point output MUST NOT
determine a persisted score.

### The metadata is copied, never re-derived

`impact_band` is required for `failed` and null for `passed`, `not_applicable` and `error`. It is
frozen on the Check Result and copied onto the Issue, and from the Issue onto the Recommendation
Artifact — `expected_impact_band`, `confidence_value` and `confidence_band` equal the origin Issue
values and are not independently inferred. Mutating a Definition's rule after Issue creation
therefore changes nothing already persisted.

Manual and AI post-hoc impact changes are **prohibited**. No actor — including one holding
`issue.adjudicate` — may alter a persisted `impact_band` or `confidence_value`. Adjudication changes
`adjudication_status` and eligibility, never the metadata. A changed mapping requires a new Check
Definition version, a new impact-rule version, and a new Evaluation or explicit policy recalculation.

### Two failures that stop different things

A Definition with a missing or nonexhaustive impact mapping cannot enter an active Catalog; an
unmapped failed outcome discovered after activation is `check_catalog_integrity_failure`, fails the
Evaluation, creates no Issue and does **not** silently downgrade the outcome.

An unlisted failed outcome under `effort-interim-v1` is `effort_policy_unavailable`. It blocks
Recommendation publication and Priority Decision creation **without changing the Issue or the
score**. `effort_basis` is exactly `effort-interim-v1:<check_definition_id>:<outcome_code>:<matched-rule>`.

---


## CAP-012 AI Discoverability Analysis


Matrix row: MTX-012 (AC-CAP-012). Slice: S-10.
Structured contract: `specification/volume-ii/contracts/S-10.json`.
Governing authority: CAP-012, `citation-policy-v1`, the Interim Entitlement Contract's `ai.generate`
operation rule, PRULE-014, PRULE-015, and OD-007 (**ratified**).

This section is the canonical owner of the AIResponse and Citation contract. It consumes the origin
Issue owned by [CAP-014](#cap-014-issue-creation-adjudication-deduplication-and-supersession) in S-12
and the Check Result metadata owned by
[PRULE-012](#prule-012-impact-and-confidence-metadata) in S-09. Recommendation Artifact families,
versions, templates and publication are WF-009 and CAP-016, owned by S-14; the binding point is the
only place the two meet.

### The `ai_assisted` path is gated closed, and that is settled Volume I behaviour

`citation-policy-v1` states it directly. AI-assisted generation requires active signed
`ai-response-interim-v1` and `ai-safety-interim-v1` artifacts naming an approved provider adapter and
model, data-handling approval, allowed Evidence Classifications, prompt-template hash, output schema,
prohibited-content scanner and contract-review reference. **No such provider artifact is bundled**
while provider, model and data-handling selection remains unapproved. The deterministic interim
behaviour is therefore `deterministic_template` generation from the exact catalog templates, and an
`ai_assisted` request fails **before entitlement reservation or provider call** as
`F1-AI-422 / ai_provider_unapproved`, creates no AIResponse or Citation, and may recover only by
selecting deterministic generation or by activating an approved signed artifact.

This is **not** a pending owner decision and **not** a withheld limb. The register lists exactly
OD-014, OD-023, OD-027, OD-031 and OD-032 as pending; none of them is this gate. So S-10 contracts
the **complete** AIResponse and Citation contract — it is fully specified normative behaviour that
the gate protects — plus the gate itself. Its acceptance fixtures are mandatory now, because the
contract is specified now and the gate defers only its reachability.

An implementation MUST NOT choose a provider, send Evidence, or silently weaken the gate. No feature
flag, tenant setting, configuration value or implementation choice opens it.

### OD-007 as ratified: the missing column is structural

One-directional Citation: exactly one AIResponse, exactly one Evidence, **no direct Evaluation write
link**. Evaluation traversal is `AIResponse -> Recommendation Artifact -> origin Issue -> Check
Result/Evidence`. A read-model projection MAY denormalize that traversal but MUST NOT become write
authority.

The `evaluation_id` column is therefore asserted **absent** from `ai_responses` and `citations`, not
merely null. A nullable column invites the join the decision removed.

### The preimage is the authority; the hash is an index

As with the Check Result in [PRULE-010](#prule-010-check-materialization-canonical-order-and-determinism),
both fingerprints here retain their preimage and it is the uniqueness authority. Exact preimage
replay returns the original attempt and never calls the provider or validates twice. Idempotency-key
reuse with a different preimage is `idempotency_conflict`. A same hash with a different retained
preimage never merges and emits restricted `AIResponseFingerprintCollision` or
`CitationFingerprintCollision` telemetry.

### Four instants, four boundaries, and the equality rule for each

- `generation_due_at_utc` is exactly 90 seconds after request. At exactly that instant **timeout
  wins** over provider completion.
- `validation_due_at_utc` is exactly two minutes after request. Validation **and** the `ai.generate`
  durable entitlement commit must commit **strictly before** it. At exactly that maximum-execution
  instant, lease expiry and `validation_timeout` win over validation.
- `publication_expires_at_utc` is exactly 24 hours after validation. At exactly that instant expiry
  wins over publication.
- Publication atomically binds the validated AIResponse to the target Artifact version and cancels
  expiry; a bound response remains `validated` as immutable lineage.

### One validation transaction decides every Citation

The validation transaction persists a terminal decision for **every** proposed Citation and changes
the response to `validated` on full coverage or `rejected` on failure. A partially decided set is not
observable. AIResponse rejection or validation timeout changes any remaining proposed Citation to
`invalid` with `response_rejected` or `validation_timeout` in that same transaction — so no Citation
is ever left proposed behind a terminal response.

Coverage passes only when every claim has at least one verified Citation, **and** every Citation
targets a manifest claim, **and** no Citation for the response remains proposed or invalid. Three
clauses, three independent failures.

### No customer-visible value exists outside the claim manifest

The manifest has exactly one entry per customer-visible value — `problem_statement`, `rationale`,
`expected_impact_band`, `confidence_value`, `confidence_band`, `effort_band`, `effort_basis`,
`platform_applicability`, and each `implementation_steps[i]` and `verification_steps[i]` — each with a
unique `claim_key` equal to that logical path and `claim_sha256` over its canonical UTF-8 value. That
is what makes citation coverage a decidable property rather than a review opinion.

### Provider semantics stay out of the domain event stream

Provider text, prompts, unrestricted responses, credentials and opaque error strings are never
retained in a payload and never appear in an event or customer output. Provider latency, queue depth
and lease state are technical telemetry and are not domain events. No hidden provider retry exists:
every retry is a new attempt linked by causation ID and visible in the audit trace.


## PRULE-014 AIResponse And Citation Integrity


Matrix row: MTX-065 (AC-PRULE-014). Slice: S-10.
Structured contract: `specification/volume-ii/contracts/S-10.json`.

AI-assisted output applies `citation-policy-v1`: one fingerprinted, replay-safe AIResponse attempt;
one AIResponse and one Evidence per Citation; no direct Evaluation write link; complete claim
coverage; exhaustive decisions and states; and a validated, unexpired response before publication.

The rule's one-parent clause is what fixes the aggregate boundary. A Citation cannot be a join table,
and with the Evaluation link absent, evaluation traversal must go through the Artifact and the origin
Issue. No grant authorizes a Citation with two parents, a direct Evaluation link, or an uncovered
claim: PRULE-014 is an invariant on the records, not a check in one command.

No **incomplete** response supplies published content. Only a validated, unexpired, **bound**
response with complete verified coverage may supply an AI-assisted Artifact — and the expired case is
asserted separately, because expiry wins at exactly `publication_expires_at_utc`.

---


## CAP-013 Evidence Capture And Provenance


Matrix row: MTX-013 (AC-CAP-013). Slice: S-11.
Structured contract: `specification/volume-ii/contracts/S-11.json`.
Governing authority: CAP-013, the Evidence Contract, PRULE-011, PRULE-016, OD-011, OD-029 and OD-030
(**all resolved**), and OD-032 (**pending**).

This section is the canonical owner of the Evidence envelope, validation authority and propagation
contract. The producer contracts for each `evidence_type` are owned by the workflows that observe
them — WF-003 in S-05, WF-005 in S-07, WF-006 in S-08 — and are consumed here without redefinition.
The origination predicate that governs which Evidence may support an Issue is
[PRULE-011](SECURITY_PERFORMANCE.md#prule-011-issue-origination-and-evidence-integrity), owned by
S-09.

### There is no Evidence-creation command

Evidence creation is producer-driven: each producer-enabled type is created by the workflow that
observes it, and CAP-013 contributes the envelope contract those producers must satisfy. The only
principal-reachable path in this capability is the Evidence Validation Decision command. An
out-of-band creation endpoint would bypass the producer contract that binds each type to its
observing workflow, so none exists.

### Two type literals that fail differently

`operator_attestation` is **recognized but reserved**: Volume I defines no creation command, actor
authority, applicability, payload schema, provenance profile, validation rule or downstream
eligibility for it, so every attempted creation returns `F1-DOMAIN-409 / evidence_type_unavailable`
and creates no Evidence. Enabling it requires controlled Volume I change defining all those
contracts.

An unknown or legacy alias, **including `operator_submission`**, returns
`F1-VALIDATION-400 / evidence_type_invalid`. No implementation may normalize an alias into a
recognized type.

The two produce different error classes, so they are asserted separately. Collapsing them is the
defect.

### `validation_status` is immutable; effective status is the Decision history

`validation_status` is the creation-time decision made by the tenant-scoped integrity-validation
service and never changes. A later determination **appends** an immutable Evidence Validation
Decision. The transition and authority table is exhaustive:

- `valid -> quarantined` for `security_restriction`, `consent_review`, `retention_review`,
  `digest_recheck_required` or `schema_recheck_required`. The integrity-validation service may use
  **any** listed reason; a SecurityOperator in authorized scope may use **only the first three**.
- `quarantined -> valid` only by the integrity-validation service, reason `revalidation_passed`, and
  only after retained bytes, digest, schema, tenant references, consent and retention state, and
  authority all pass again.
- `valid -> invalid` and `quarantined -> invalid` only by the integrity-validation service, for
  `immutable_bytes_missing`, `digest_mismatch`, `schema_unsupported` or `legal_deletion_completed`,
  after the condition is conclusive.

No same-status Decision is created. `invalid` is terminal; corrected content is new Evidence. A
SecurityOperator attempting `digest_recheck_required` is denied — asserted separately, because it is
the boundary a permissive implementation crosses.

### The commit is deliberately wide

A transition away from `valid` performs **every applicable current effect before the Decision
commits**. A narrow commit would leave a window in which a current read returns a numeric score
supported by Evidence the system has already decided is not valid.

Two suppression limbs run and neither subsumes the other:

1. If the Evidence supports a selected current Issue **or** any passed/failed Check Result supplying
   current pillar coverage: mark the Current Score Projection unavailable, add `invalid_evidence` to
   its de-duplicated fixed-precedence reason set, and suppress every published Recommendation
   Artifact whose **origin Issue** is affected.
2. **Independently**, suppress every published Artifact whose **rationale or Citation** references
   that Evidence.

The event then triggers idempotent recalculation, which **replaces** the complete reason set with all
and only reasons applicable to the recalculated inputs — it does not subtract one code and leave the
rest. A later `quarantined -> valid` removes `invalid_evidence` only when no selected score input has
invalid Evidence, and no automatic republication occurs until every publication predicate passes
again.

Check Results and historical snapshots retain the Validation Decision IDs and statuses **frozen when
they were created** and never mutate.

### The retention split

`payload_retention_class` classifies **only** the referenced Evidence Payload, and for every
producer-enabled type it is exactly `product_evidence_payload` — no caller may choose another value
and an unknown class rejects Evidence creation. The envelope, digest, provenance, Validation
Decisions and downstream lineage are always `product_history`, **including after payload
destruction**. Staging bytes before Evidence creation use `temporary_processing`; Verification
challenge plaintext remains `ephemeral_secret` and is never part of Evidence.

### OD-029 and OD-030 as resolved

Under **OD-029 Option 2**, `EvidenceRetentionExpiring` has exactly one producer — WF-007 under the
integrity-validation service authority — and is emitted once per Evidence Payload at 30 days before
its current `product_evidence_payload` retention maximum, carrying the Evidence identity, its
Organization, the capture cursor, the maximum instant and the correlation ID. It requests
reassessment through the accepted WF-011 path when the Project remains active, and creates no new
workflow, capability, decision record, Payload state or notification route variant.

Under **OD-030 Option 3**, destruction of an already-`invalid` payload happens at the 24-month
elapsed maximum on the capture cursor, is **not** accelerated to the accrued 30-day minimum, appends
**no** Evidence Validation Decision — `invalid` is terminal and a same-status Decision is forbidden —
and is proved by exactly one immutable `security_audit` deletion audit record. The LifecycleDeletionJob
and its Deletion Evidence stay the Account-deletion and Organization-closure mechanism only and are
asserted **absent** from this path. A legal hold suspends destruction; the payload is destroyed at the
first eligible instant after release.

### Withheld under OD-032

OD-032 is pending. Its question is which lifecycle owner and canonical identifier namespace
011 DOMAIN_MODEL.md assigns to the lifecycle-bearing records DM-REQ-001 does not name, and which
bounded context owns LegalHold — 016 STATE_MODEL.md names a "Security Context" that 011 does not
define. Its Blocking Impact records Volume II **no for behaviour, yes for any artifact requiring a
canonical namespace**; implementation **no** under the interim; production **no**; feature **no**.

The withheld limb at S-11 is exactly:

- a canonical identifier namespace declared for LegalHold or Check Result,
- a lifecycle owner inferred for either,
- a bounded-context assignment for LegalHold.

Those are withheld and MUST NOT be implemented, migrated, logged as telemetry labels, or tested as
settled. **Evidence itself is not affected**: OD-032's own text records that 011 DOMAIN_MODEL.md
already admits Evidence as a lifecycle-bearing auxiliary record with owner Evidence Context and
namespace `evd_id`, and cites that admission as the precedent the pending decision would follow.
Where 016 already names a lifecycle owner, that assignment stands and is not reopened.

Everything else in CAP-013 is contracted, and the slice is **not** blocked: behaviour is permitted
under the interim and Volume I's existing logical field names remain authoritative for it. Completing
the limb requires ratification plus a PM-REQ-009 controlled change to 011 DOMAIN_MODEL.md rather than
an implementation choice.

### Declassification does not exist

Classification order is `public < internal < confidential < restricted`. A derived field inherits the
**strongest** classification of any source value or Evidence used to derive it. Unknown classification
is treated as `restricted`. Volume I defines no declassification permission or workflow, so
declassification is prohibited: no actor, service or policy may lower a persisted or derived
classification, and a future capability would need its own protected authority, approval, transition,
expiry/recalculation, event and acceptance contract before use.

`evidence.restricted.read` is not an exception to this. It raises **only** the granted
OrganizationAdmin's Evidence payload access to `restricted`; it broadens no resource scope, no other
field permission, and authorizes no validation transition.

---


## WF-018 Investigate And Audit Security Or Compliance Events


Matrix rows: MTX-023 (AC-CAP-023), MTX-043 (AC-WF-018). Slice: S-21.
Structured contract: `specification/volume-ii/contracts/S-21.json`.
Governing authority: CAP-023, WF-018, the Investigation Contract, the Support Session Lifecycle,
`emergency-access-v1`, PRULE-037, PRULE-038, and OD-011, OD-012, OD-013 and OD-020.

This section is the canonical owner of the WF-018 application contract. S-21 owns the
investigation surface and the Emergency Access Grant; the WF-017 limb of CAP-023 is owned by
[WF-017](#wf-017-handle-incident-and-recovery) in S-24 and is consumed here without redefinition.

### Entry point and authority

`OpenInvestigation`, `CollectInvestigationInput`, `PublishInvestigationReport` and
`CloseInvestigation` under `Workflows::Wf018`. Volume I fixes their permissions and envelopes but
no HTTP path; transport is owned by API_CONTRACTS.md. The collector is service-only and has no
route at all.

Authority is `security.investigate`, Organization-scoped and protected. A one-Organization request
is confined to that permission scope; a cross-Organization request additionally requires one
active Support Session **per affected Organization**. Closure always requires a different holder
of protected `security.investigation.approve`. The canonical tokens across the investigation and
incident surfaces are exactly `incident.respond`, `security.investigate`,
`security.investigation.approve` and `security.notice.read`; no broader management token exists.

### Authority is resolved per query, not per Investigation

The non-obvious finding. Every page revalidates the frozen Support Session, `security.investigate`,
the Organization and resource set, the interval, the classification ceiling and the query hash at
the read transaction's server timestamp. A session valid at open and expired at collection denies
**that query** and creates its explicit gap; another Organization's session never substitutes. A
report therefore becomes `partial` or `insufficient` rather than complete, and no out-of-session
read ever occurs. Degradation is the mechanism by which the boundary holds.

### The Support Session lifecycle is not owned here

`SupportSessionRequested`, `SupportSessionActivated`, `SupportSessionRejected`,
`SupportSessionExpired` and `SupportSessionRevoked` are enumerated in **WF-013's** Domain Events,
so the session's own transitions and events land with WF-013 on MTX-038 in S-23. S-21 freezes an
already-active session as the per-Organization collection authority and emits none of them.

The Emergency Access Grant is different and **is** owned here on MTX-023: no workflow's Domain
Events enumeration claims the five `EmergencyAccess*` events, and AC-CAP-023 carries the whole
OD-012 Option 3 clause.

### OD-012: architecture ratified, notification withheld

Option 3 is settled and permanent, not interim. Emergency access is authorized **outside** the
Incident by the Grant: distinct requesting and approving SecurityOperators, an open
severity-critical Incident predicate, enumerated resource and action scope within exactly one
Organization, a bounded lifetime resolved from the active `emergency-access-v1` policy version,
revocation, immutability, and immutable `security_audit` Audit Evidence written in the same
transaction as its transition. `emergency_customer_access` does not exist and the fail-closed
outcome is permanent baseline. The Grant substitutes for exactly one thing — the affected tenant's
`support.session.customer_approve` — and never for the mandatory distinct SecurityOperator
approval or any target-workflow permission.

**Withheld limb:** customer notification on emergency access, blocked pending qualified legal
review. S-21 asserts no customer-notification behaviour on any emergency-access path and makes no
contractual claim about it. This is the only limb S-21 withholds.

### Recorded, not corrected

Six Volume II artifacts diverge from ratified Volume I and are outside S-21's authority: the
pre-OD-013 nullable-Organization and cross-org shape on `investigations`; the checkpoint-creation
gate citing the retired `UPSTREAM-V1-EVENT-SCOPE-001`; the three investigation routes and five
Investigation events deferred under that same retired blocker; BACKGROUND_PROCESSING.md's
"blocked by event-scope ambiguity"; APPLICATION_LAYER.md's deferral of cross-Organization
Investigation event persistence; and the complete absence of an `emergency_access_grants` table,
of `emergency_access_grant` in `EventEntityType`, of the five `EmergencyAccess*` names in
`EventType`, and of any emergency-access policy type to back `emergency-access-v1`. The Grant is
not implementable until its owning documents close those gaps. That is a completeness gap, not a
withheld limb — nothing about it awaits an owner.


## WF-015 Enforce Entitlements


Matrix rows: MTX-024 (AC-CAP-024), MTX-040 (AC-WF-015). Slice: S-22.
Structured contract: `specification/volume-ii/contracts/S-22.json`.
Governing authority: CAP-024, WF-015, the Interim Entitlement Contract (`entitlement-interim-v1`,
`interim-baseline-plan-v1`, `plan-approval-interim-baseline-v1`), PRULE-039, PRULE-040, OD-006,
OD-019, OD-005, OD-008, OD-020.

### Entry point and authority

Two surfaces, one workflow, no shared authority.

**Enforcement** has no actor-facing entry point and must not acquire one. The tenant-scoped
entitlement service identity is the only actor that makes a Decision; the human Account or service
identity in the envelope is the Decision's *subject*, not its author. WF-015's Security Notes admit
no client-side trust, and CAP-024 lists a client-side decision as a Failure Condition rather than a
quality concern. The checkpoints — `DecideEntitlement`, `ReserveEntitlement`,
`HeartbeatEntitlement`, `CommitEntitlement`, `ReleaseEntitlement`, `RecordLowCostUsage` — are
internal to the operation being gated.

**Policy management** is a routed command: `POST /api/v1/organizations/:organization_id/entitlement-policies`
→ `ActivateEntitlementPolicy`, `policy.entitlement.manage`, policy-conditional `If-Match`, `201`,
`ATTR-ActivateEntitlementPolicy`. The Permission Baseline grants `policy.entitlement.manage` to
**BillingOperator alone**. An OrganizationAdmin has no entitlement-policy mutation authority at all
and reaches this area only through `entitlement.notice.read`.

Entitlement is not authorization. A read is authorized by its own named permission and metered
separately by its declared operation; a Block is a capacity outcome, not a denial of authority.

### Non-obvious findings

**The five low-cost operation strings are not permissions.** `report.view`, `history.view` and
`score.read` do not exist in the Permission Baseline at all — its reads are `issue.read`,
`score.summary.read`, `score.detail.read`, `history.read`, `recommendation.read`, the three Evidence
reads, `entitlement.notice.read`, `security.notice.read`, `export.retrieve`, plus the OD-020 rows.
That `issue.read` and `recommendation.read` appear in both maps is a coincidence, and inferring a
permission from an operation name would grant authority Volume I never wrote.

**Rejection and Decision are different outcomes.** An inactive Organization, inactive actor,
unauthorized service, unknown operation, inactive entitlement, missing policy or unavailable counter
is *evaluated into an immutable Block Decision* and is auditable. Only an invalid tenant reference,
both or neither actor form, malformed units, or a malformed envelope is a request-schema rejection
that creates no Decision. Collapsing the first set into the second would destroy the audit trail
CAP-024 requires.

**The counter window row is the whole concurrency story.** Unique per
`(organization_id, counter_group, window_start, window_end)`, it is what makes "never reserve or
commit above hard limits" true under concurrency rather than true on average. The check and the
reserve are one serialized operation against it.

**Reservation races have fixed winners, not arrival order.** At exactly the prestart expiry,
execution-start loses to expiry. At exactly 15 minutes since the last accepted heartbeat, and at the
maximum execution instant, the lease-expiry handler wins over both a new heartbeat and a protected
side effect. It commits exactly once **only if** the durable commit point committed *strictly
before* that instant; otherwise it releases exactly once. A commit point reached exactly at the
instant releases.

**A partial artifact is not a usage commitment.** Cancellation or terminal failure before the listed
durable commit point releases even when Documents or other partial artifacts exist.

**The Decision is immutable and the reservation is not** — hence separate rows. The Decision records
counters *as decided* and never mutates to reflect a later commit, release or expiry.

**Nesting cannot double meter.** `reassessment.start` subsumes its internal WF-005–WF-008 core, and
those stages MUST NOT also reserve or commit `crawl.start`. Every stage records the root
Decision/reservation ID. S-07's MTX-058 already contracts the `crawl.start` Decision and reservation
at the `Queued -> Running` commit; S-22 supplies the machinery it consumes and does not redefine
when a Crawl reserves.

### OD-006 and OD-019 are ratified — implemented, not withheld

Both carry `Current Status: Ratified 2026-07-17 … ratified as specified` and `Blocking Impact: None`.

WF-015's own prose still says "the OD-006 **interim** policy" and "this interim classification does
not approve the final grace policy". That prose predates the ratification session and is not a status
source. **Low-cost reads at and above the 1,000 hard limit remain allowed with an over-limit warning**
— approved baseline behaviour, implemented exactly. High-cost blocks only when
`committed + active_reserved + requested` would *exceed* the hard limit; **equality is allowed**.

OD-019's `read-metering-v1` is likewise settled: one record per accepted top-level document read;
every metered read route statically declares exactly one of the five operations; an undeclared route
resolves `operation_unknown` → Block → `contact_support`, so it is unreachable rather than silently
unmetered; Turbo Frames and partials carry the root Decision ID and append nothing, while a Frame
reached by direct navigation is itself a root; Decision IDs are server-minted deterministically from
Organization, human Account or service identity, declared operation, resolved target identity and
state version, and counter window, so **no client idempotency key exists on GET** and a transport
retry cannot be counted twice.

OD-005 makes the numerals versioned policy configuration bound to an approved policy version, not
Volume I constants. The current approved values are `entitlement-interim-v1`'s.

### Recorded contradiction — `UPSTREAM-V1-LOW-COST-METERING-005`

`APPLICATION_LAYER.md` states that composite page/frame charging and the physical metered-read replay
identity "remain disabled until controlled Volume I clarification", and that
`Workflows::Wf015::LowCostRead` "is not executable until `UPSTREAM-V1-LOW-COST-METERING-005` resolves
its durable-response identity". **OD-019's Ratified Behavior supplies every one of those answers.**
`API_CONTRACTS.md` already reads the register correctly: "deferred under
`UPSTREAM-V1-LOW-COST-METERING-005`, which OD-019 resolves by ratifying the metered-read unit; their
transport exposure is intentionally deferred to the Volume II baseline."

S-22 adopts that division: the metering **semantics** are ratified and are contracted here in full;
only the physical GET path exposure is deferred to the Volume II transport baseline owned by
`API_CONTRACTS.md` — the ordinary route answer, not an owner-decision block. Treating the stale
blocker prose as a live gate would withhold behaviour the owner approved, which is precisely the
failure mode `RATIFICATION_STATUS_OVERLAY.md` exists to prevent. Correcting the two
`APPLICATION_LAYER.md` paragraphs is a separate governed edit and is not performed by this contract.

### Withheld

**Nothing.** No decision governing these rows is pending. MTX-024 and MTX-040 cite OD-005, OD-006,
OD-008, OD-019 and OD-020; every one is ratified in the register with `Blocking Impact: None`, and
none of the five pending decisions (OD-014, OD-023, OD-027, OD-031, OD-032) touches this slice.


## WF-013 Manage Tenant Lifecycle


Matrix rows: MTX-025 (AC-CAP-025), MTX-038 (AC-WF-013). Slice: S-23.
Structured contract: `specification/volume-ii/contracts/S-23.json`.
Governing authority: CAP-025, WF-013 and its five subflows, the Support Session Lifecycle,
`onboarding-interim-v1`, `organization-reactivation-v1`, `session-termination-v1`,
`role-expiry-block-v1`, `emergency-access-v1`, the Permission Baseline, PRULE-018, PRULE-041,
PRULE-042, and `retention-interim-v1` in [015 DATA_LIFECYCLE.md](../../015%20DATA_LIFECYCLE.md).

This section is the canonical owner of the WF-013 application contract. S-23 owns the
transitions. It does not own the gate those transitions move state behind: that is
[PRULE-019](SECURITY_PERFORMANCE.md#prule-019-organization-state-authorization-gate), MTX-070 in
S-02, consumed here without redefinition. It does not own notification delivery: that is
[PRULE-034](SECURITY_PERFORMANCE.md#prule-034-notification-delivery-authority), MTX-085 in S-19,
invoked at the WF-014 boundary. MTX-085 lists S-23 among its slices but is complete and owned by
S-19 — it is referenced here and is not contracted.

### Interfaces

None. Volume I defines WF-013's commands, permissions, envelopes and persisted deadlines and
defines no HTTP path, method or transport. Nothing in WF-013 demands an interface: every
trigger is an authorized actor's command or a deadline reached by a named lifecycle service.
Transport exposure is owned by [API_CONTRACTS.md](API_CONTRACTS.md) at the Volume II baseline.

### The five subflows

- **Invitation** — creation, open-tuple duplicate handling, existing-member and ineligible-Account
  checks, protected approval, rejection, revocation, acceptance, recipient decline, reissue,
  expiry and wrong-identity handling, per `onboarding-interim-v1`. The invitation lifecycle
  service alone writes timed expiry. Equality belongs to expiry. A failed Delivery does not roll
  back or extend an active Invitation.
- **Account** — suspend, reactivate, revoke, delete. Suspension revokes Sessions **before success
  returns**. Under ratified OD-021, `ReactivateAccount` applies `reactivation-proof-v1`: it proves
  only the **acting** administrator's MFA-satisfied Session, consults no target identity, accepts
  no Identity Validation Receipt, and creates no Session.
- **Organization** — suspend, reactivate, request closure, decide closure, execute closure.
  Reactivation is the sole ordinary mutation admitted while suspended and requires an
  `organization_reactivation` receipt bound to the target Organization with `mfa_satisfied=true`
  under OD-022. Closure emits `BillingStateChanged(from_state=active,to_state=closed)` **before**
  `OrganizationClosed`; that order is normative. Closed is terminal.
- **Legal Hold and Deletion** — two-person `legal_hold.manage` authority, exact scope intersection
  re-evaluated at **every** destructive checkpoint, and the idempotent LifecycleDeletionJob under
  `retention-interim-v1`.
- **Support Session** — 24-hour approval due, four-hour active life on the final approval, expiry
  winning at equality, and no standing cross-tenant access.

### Load-bearing invariants

- Every command on an existing record carries its **expected record state version**, and its
  **expected Organization authorization epoch** whenever effective access could change.
- The authorization epoch serializes the last-admin invariant, so competing commands against
  different Accounts cannot both pass from the same epoch. Every accepted effective-access
  mutation increments it exactly once.
- No actor approves its own protected request. A SecurityOperator Account action additionally
  requires one active Support Session naming the Account and exact action; an Incident without
  such a session is insufficient.
- Under ratified OD-026, a timed expiry that would remove the last effective OrganizationAdmin
  writes one immutable `RoleExpiryBlockDecision` and leaves the Assignment `active` and effective
  past `expires_at_utc`. `expiry_blocked_last_admin` is a block reason, never an Assignment status.
- Under ratified OD-033, no LifecycleDeletionJob transitions `queued` directly to `completed`.
  Every job enters `running` first — including one whose manifest is empty or already destroyed.
- Under ratified OD-016, `RevokeSession` revokes exactly one identified Session with reason
  `security_revocation` and never cascades. Sign-out-everywhere is absent from baseline behaviour.

### Stale prose not treated as authority

Owner Decision status comes only from `Current Status` in the register. Three Volume II
statements are stale and are corrected in the contract rather than obeyed: `ReactivateAccount` is
**not** unreachable (OD-021 is ratified and supplies the proof contract); the last-admin expiry
block is **not** deferred (`UPSTREAM-V1-ROLE-EXPIRY-BLOCKED-EVENT-011` is retired under ADR-019);
and `retention-interim-v1` is **not** interim (OD-011 resolved it as the fixed baseline).

### Withheld under OD-031

Routine retention-expiry destruction, under `retention-destruction-trigger-interim-v1`. When a
`product_history`, `identity_commercial` or `security_audit` record reaches its 7-year maximum
**with no accepted Account deletion or Organization closure request**, the lifecycle service
performs no destruction, creates no job, produces no Deletion Evidence and emits no domain event.
The record is retained in full subject to legal hold; the condition is recorded as Audit Evidence
and operational telemetry and raises one critical compliance escalation. Retention-cursor-driven
partition drop is blocked by the same limb. Everything else — the LifecycleDeletionJob created by
accepted deletion or closure, its manifest, deadlines, tombstones, recovery and Deletion Evidence
— is contracted in full.

### Withheld under OD-032 (MTX-025)

The canonical DM-REQ-001 identifier namespace and lifecycle owner for Session, LegalHold and
LifecycleDeletionJob. Behaviour is permitted and contracted in full; only the namespace is
withheld. The lifecycle owners [016 STATE_MODEL.md](../../016%20STATE_MODEL.md) already names
stand and are not reopened.

### Referenced, not restated

OD-023 (credential rotation begin and complete) is owned and withheld by S-19 under
`UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009`. No S-23 command touches a Credential.

## WF-007 Generate Issues From Checks And Adjudicate


Matrix rows: MTX-014 (AC-CAP-014), MTX-032 (AC-WF-007). Slice: S-12.
Structured contract: `specification/volume-ii/contracts/S-12.json`.
Governing authority: WF-007, CAP-014, the Issue Contract, the Adjudication Case Contract, the
Lifecycle And Adjudication State Machine, `issue-fingerprint-v1`, PRULE-011, PRULE-012, PRULE-017,
PRULE-023, and OD-009, OD-010, OD-017 and OD-018 (**all ratified**).

This section is the canonical owner of the WF-007 orchestration. It consumes the Check catalogue,
applicability seal, Check Result identity and executor owned by
[PRULE-010](#prule-010-check-materialization-canonical-order-and-determinism) in S-09, and the
Evidence validity predicate owned by
[CAP-013](#cap-013-evidence-capture-and-provenance) in S-11.

### WF-007 spans two slices

S-09 owns Primary Path steps 1 through 3. S-12 owns steps 4 and 5 and everything around them: the
Evaluation lifecycle transitions, Issue derivation and fingerprinting, the Issue-set seal, and the
adjudication subflow. The Evidence Validation Subflow WF-007 names is CAP-013's and belongs to S-11.
Scoring and promotion are WF-008 and CAP-015 in S-13.

### The initial path starts; the reassessment path does not

For an initial pending Evaluation, WF-007 transitions it to running after input readiness and emits
exactly one `EvaluationStarted`. For a reassessment Evaluation **already running under WF-011**, it
validates the matching immutable orchestration and readiness snapshots and continues **without
another transition and without a second `EvaluationStarted`**. Emitting a second start is the natural
implementation error, so the assertion is on event count.

The pending initial Evaluation itself is created by
[WF-005](#wf-005-execute-crawl-and-ingestion) at its accepted root start, and the OD-018
single-orchestration guard is enforced and re-checked there. S-12 consumes that Evaluation and does
not re-implement the guard.

### Completion is not promotion

After every expected Check Result is terminal **and** the Issue set is internally consistent, WF-007
seals the immutable Issue Set and transitions the Evaluation to completed. The completed Evaluation
**remains staged** and advances no current Issue-set pointer until WF-008 can atomically promote it
with a scorable ScoreSnapshot.

That separation is why the ratified OD-010 baseline — an unavailable numeric score, because
`external-measurement-v1` bundles no active Measurement Set — does not fail WF-007. Handled `error`
Check Results are terminal, the Evaluation completes and seals its Issue Set, and the affected pillars
are insufficient. A scoreless Evaluation is a **completed Evaluation with an unpromoted pointer**, not
a failure.

Any expected `error` makes its applicable pillar insufficient **regardless of other Results** — no
successful sibling Result masks it.

### OD-017 as ratified, and the Volume I clause it corrects

OD-017 is ratified: on an Issue fingerprint collision the second Issue **MUST NOT** be created and the
affected Evaluation **fails closed**, using the existing canonical collision outcome and telemetry.
No alternative duplicate Issue may be silently persisted.

The frozen `SCORE_EVIDENCE_MODEL.md` Replay And Collision Behavior section still reads "The second
full tuple **may create** its own Issue in the hash bucket". That is pre-ratification prose, and
OD-017's own `Why The Decision Exists` names it as the exact defect the decision was raised to fix —
"a permissive keyword where DOC-REQ-007 requires an RFC-style normative choice". **WF-007 Primary Path
step 4 carries the ratified text and prevails.** PRULE-023's only MUST is *never merge*, which every
enumerated option satisfied, which is precisely why an owner decision was required and why
implementing the ratified branch breaches no rule.

Concretely: detection is at Issue derivation, **before any Issue write**; exactly one
`fingerprint_collision_decisions` row records `fingerprint_kind='issue'` with the prior bucket Issue
as `existing_record` and the preallocated derivation-slot identity as `conflicting_record`; exactly
one `IssueFingerprintCollision` is emitted; and no Issue row is ever written under the conflicting
slot. Exact-preimage replay remains enabled and is **not** a collision.

### The two adjudication permissions are disjoint

`issue.dispute` allows OrganizationAdmin, MarketingOperator and TechnicalImplementer and denies
SecurityOperator, BillingOperator and every service identity. `issue.adjudicate` allows only a
SecurityOperator, including an approved support session, and denies everyone else. Their Permission
Baseline cells do not overlap, which is what makes requester/adjudicator separation **structural**
rather than a runtime comparison alone. The runtime comparison still runs, and it runs **at
assignment** — an assignment to the requester would already have consumed the separation.

### Version discipline is asymmetric, and the two stale reasons are not interchangeable

Dispute carries the expected **Issue** state version. Assignment, decision and withdrawal carry
**both** the expected Issue **and** the expected Adjudication Case version. A stale required version,
a terminal Issue target, or a non-current lineage leaf is `stale_issue_version`; a *current* Issue
with a stale Case version is `stale_case_version`.


## CAP-014 Issue Creation, Adjudication, Deduplication, And Supersession


Matrix row: MTX-014 (AC-CAP-014). Slice: S-12.
Structured contract: `specification/volume-ii/contracts/S-12.json`.

CAP-014 defines no interface of its own; its obligations are discharged by the WF-007 contract above,
by [PRULE-017](#prule-017-issue-supersession-and-issue-set-membership) for supersession, and by
[PRULE-033](#prule-033-reassessment-publication-atomicity) for the publication commit.

### An Adjudication Case is not a second deficiency entity

`Issue` is the only persisted product deficiency object. No second persisted deficiency entity or
identifier exists. An Adjudication Case is the immutable-history logical record for one review or
dispute, and the Issue's `adjudication_status` is the **current projection** of its active or latest
case — requested system review maps to `review_required`, requested customer dispute to `disputed`,
assigned to `in_review`, and the four closed outcomes to the same-named Issue status. Setting it
independently is not possible.

### The SLA cursor carries; the SLA clock does not restart

When reassessment observes the same fingerprint while a predecessor Case is open, that Case becomes
`obsolete` and a successor Case is created carrying, field for field, `preceding_case_id` **and**
`carried_from_case_id` equal to the predecessor, the same case type, original requester, request
reason, `requested_at_utc`, `due_at_utc`, SLA status, `overdue_event_emitted_at_utc`,
`critical_event_emitted_at_utc` and `last_reminder_sequence`. Already-emitted overdue, critical and
reminder events are **never re-emitted** for the successor; future reminders continue at the next
sequence from the **original** request time. **No new SLA clock starts.**

A *later valid dispute* is the opposite case: it creates a new Case with `preceding_case_id` to the
prior latest Case and a **new** 24-hour SLA, inheriting nothing. Confusing the two is how an SLA gets
silently reset.

### The critical event replaces a reminder without losing the sequence

At exactly 168 elapsed hours after the original request, `sla_status` becomes `critical` and exactly
one `IssueAdjudicationCritical` **replaces** any reminder due at that same instant — while
`last_reminder_sequence` still advances past the replaced sequence, so it is never emitted later.
Later daily reminders continue. No automatic uphold or dismissal is ever permitted.


## Issue Creation Evidence Preconditions


Matrix row: MTX-046 (AC-SM-003). Slice: S-12.
Structured contract: `specification/volume-ii/contracts/S-12.json`.

Creating any Issue fails when Evidence is absent, invalid, quarantined, digest-mismatched, missing a
required field, or cross-Organization. The governing **rule** is
[PRULE-011](SECURITY_PERFORMANCE.md#prule-011-issue-origination-and-evidence-integrity), owned by
S-09; this section owns its enforcement at CAP-014's write path and does not restate it.

Two things are asserted that an implementation tends to skip. First, **quarantined** is asserted
separately from invalid, because quarantined is a recoverable status and reads as acceptable.
Second, all six conditions hold identically for a **withheld review candidate** — AC-SM-003 names the
inclusion expressly, and the withheld path is the one a permissive implementation exempts. The
reassessment service creating a successor is bound by the same six.

The predicate reads the Check Result's **frozen** Validation Decision statuses. An exact fingerprint
replay after the Evidence has since become invalid returns the stored Issue unchanged rather than
re-running the precondition — otherwise a valid Issue would disappear on replay.


## Issue Deduplication And Fingerprint Collision


Matrix row: MTX-049 (AC-SM-006). Slice: S-12.
Structured contract: `specification/volume-ii/contracts/S-12.json`.
Governing authority: AC-SM-006, `issue-fingerprint-v1`, Replay And Collision Behavior, and OD-017
(**ratified**).

The fingerprint preimage is canonical JSON containing **exactly** `organization_id`, `project_id`,
`source_id`, `check_definition_id`, `issue_type`, `canonical_subject_type`, `canonical_subject_key`.
Within one Evaluation, uniqueness authority is the full tuple
`(evaluation_id, fingerprint_version, fingerprint_preimage)` — **not** the hash. A unique constraint
on `fingerprint_sha256` alone MUST NOT exist: it would merge exactly the records the model requires
to stay distinct.

Exact replay returns the existing Issue and the stored command result with no second Issue and no
second `IssueCreated`. **Concurrent** exact creates have the same result as sequential replay — both
are asserted, because a sequential-only fixture passes while the concurrent path double-writes.

Cross-Evaluation fingerprint equality is a **reassessment match**, not same-run deduplication, and
follows [PRULE-017](#prule-017-issue-supersession-and-issue-set-membership).

Collision behaviour is the ratified OD-017 branch described at
[WF-007](#wf-007-generate-issues-from-checks-and-adjudicate) above.


## Issue Eligibility And Adjudication Recalculation


Matrix row: MTX-048 (AC-SM-005). Slice: S-12.
Structured contract: `specification/volume-ii/contracts/S-12.json`.
Governing authority: AC-SM-005, the Score Contribution Contract's inclusion and exclusion rules, the
Current Score Projection, and OD-009 (**ratified**).

Under the ratified OD-009, review-required, disputed and in-review Issues contribute **zero to both
score and priority** until eligible. Inclusion is conjunctive over exactly five clauses:
`lifecycle_status=open`; `adjudication_status` in `not_required`, `upheld` or `withdrawn`;
`publication_status=published`; it is the prospective current lineage leaf; and every referenced
Evidence record is valid and same-Organization.

Exclusion uses a **first-match precedence**: `superseded`, `not_current`, `invalid_evidence`,
`dismissed`, `resolved`, `in_review`, `disputed`, `review_required`. A state that fails inclusion but
matches none of them is `contribution_mismatch` and makes the calculation unavailable **rather than
inventing a reason**.

`penalty_points` always equals the impact-table value even when excluded; only
`signed_contribution_value` becomes `0.0`. Penalties are not multiplied by confidence, occurrence
count, source count or Recommendation count.

### The second wide commit

Like the Evidence transition in [CAP-013](#cap-013-evidence-capture-and-provenance), this commit is
deliberately wide and for the same reason. **Before** an accepted dispute, uphold, reject or
withdrawal commits, the same transaction marks the Current Score Projection `unavailable`, retains its
current and last-promoted pointers **for history only**, unions `issue_set_incomplete` into the
fixed-precedence unavailable-reason set, sets `recommendation_suppression_required=true`, and
suppresses every published Artifact whose `origin_issue_id` is the affected Issue.

**No current read may return the stale pre-transition numeric score** between the Issue transition and
recalculation. The event then triggers idempotent recalculation, which creates or reuses an immutable
ScoreSnapshot, **replaces** the reason set with all and only then-applicable reasons, and refreshes
downstream projections. It never mutates an earlier snapshot.

A Recommendation Artifact may be **drafted** for a withheld origin Issue but MUST NOT be published or
prioritized. Related Issues never govern this transition.


## PRULE-017 Issue Supersession And Issue-Set Membership


Matrix row: MTX-068 (AC-PRULE-017). Slice: S-12 (owner for S-12 and S-18).
Structured contract: `specification/volume-ii/contracts/S-12.json`.
Governing authority: PRULE-017, Supersession And Reassessment Semantics, CAP-014, CAP-020, WF-007,
WF-011, WF-012. Decision Dependency: None.

Issue Set membership is exactly every Issue in the Project lineage graph that existed at the seal
checkpoint and is **either a current leaf or an ancestor of a current leaf** — so it includes terminal
current leaves and non-current ancestors, and exactly one current leaf per full fingerprint identity.
Later-created Issues never enter an earlier set. Both ordered lists sort by fingerprint preimage, then
Issue originating-Evaluation creation time, then Issue ID.

### Two ordered passes, and the pass that is not repeated

The first pass processes each current predecessor **exactly once** in fingerprint-preimage then
Issue-ID order, through four branches: `condition_persisted`,
`condition_recurred_after_dismissal` / `condition_recurred_after_resolution`, proved absence, and
`resolution_unverified`. The second pass processes the observed fingerprints in canonical order and
creates one new current Issue per fingerprint unmatched in the first pass — and **this pass is not
repeated per predecessor**.

The terminal-recurrence branches **link without mutating**: the dismissed or resolved predecessor is
asserted byte-unchanged, and a dismissed recurrence gets a *new* system-review Case with reason
`recurrence_after_dismissal` and a fresh 48-hour due time, **not** the predecessor's SLA.

### Incomplete coverage never falsely resolves

`not_applicable`, `error`, a missing Check Result for the predecessor's Definition or selector,
incomplete relevant coverage, invalid Evidence, and a Definition without a recognized mode **never**
prove absence. Each instead produces one `resolution_unverified` entry with exactly one reason in the
precedence `absence_mode_never_automatic`, `check_not_applicable`, `check_error`, `check_missing`,
`coverage_incomplete`, `evidence_invalid`, `absence_mode_unknown`.

"Full relevant coverage" is exact: the replacement coverage inputs contain a terminal covered outcome
for **every** admitted candidate matching that exact bound selector **and** contain **no** matching
failed, omitted, indeterminate, stale or limit-discarded candidate. Every disqualifier is asserted
independently.

A non-observed terminal `resolved` or `dismissed` current leaf remains unchanged and creates **no**
`resolution_unverified` entry.

### The scope race is revalidated at publication, not trusted from the freeze

Reassessment execution freezes the active Source-set version and the normalized full-scope definition
hash; the publication commit **atomically revalidates both**. Any Source activation, disable or
removal, or any normalized scope-policy change, produces `source_scope_changed_during_reassessment`,
publishes **none** of the staged result, and requires a new full-scope attempt. Equality of prior and
current `scope_snapshot_id` is **not** required when the normalized full-Project scope-definition hash
is unchanged.


## PRULE-033 Reassessment Publication Atomicity


Matrix row: MTX-084 (AC-PRULE-033, CAP-014 limb). Slice: S-12. The CAP-020 limb is owned by S-18.
Structured contract: `specification/volume-ii/contracts/S-12.json`.
Governing authority: PRULE-033, CAP-014, WF-011, and OD-025 (**ratified**).

This section owns **only** the CAP-014 limb: the Issue-side members of the atomic publication commit
and the Evaluation-state reuse that precedes it. Schedule policy, anchored cadence, slot identity and
deduplication, due-time and scope eligibility, one-active-or-awaiting-publication serialization,
inactive-scope skipping, outage coalescing, zero schedule-only Notification, the entitlement gates,
the publication commit itself and the Reassessment Result are the CAP-020 limb and belong to S-18.

Every admitted run uses **one new Evaluation already Running before the nested Crawl**. Nested stages
start once and stage reuse emits **one** `EvaluationStarted` — which is exactly why
[WF-007](#wf-007-generate-issues-from-checks-and-adjudicate) reuses the running Evaluation rather than
starting a second. Reassessment is orchestration over a new canonical Evaluation, **not** a separate
mutable state machine.

### Failure splits into two groups, and collapsing them is the defect

Pipeline timeout or failure, and accepted cancellation **while the Evaluation is running**, transition
it to failed. Unavailable scoring, a Source or scope race, publication failure, and accepted
**post-completion** cancellation leave the Evaluation **completed** and record only the failed or
canceled Reassessment Result. Collapsing the two groups retroactively fails a completed Evaluation.

Every nonsuccess preserves every prior projection field and releases the reservation exactly once.
Retry creates a new Evaluation attempt linked by causation ID; completed stages are reused only by
immutable input hash.

Under the ratified **OD-025**, `ReassessmentTriggered` is **removed** as a canonical domain event.
Reassessment executes deterministically and emits no trigger event. Its absence is ratified behaviour,
not an omission, and none may be invented.

---

## WF-011 Trigger Reassessment


Matrix row: MTX-036 (AC-WF-011). Slice: S-18.
Structured contract: `specification/volume-ii/contracts/S-18.json`.
Governing authority: WF-011, CAP-020, PRULE-033, PRULE-045, the Supersession And Reassessment
Semantics and Reassessment Result contracts of `SCORE_EVIDENCE_MODEL.md`, the `017 ERROR_MODEL.md`
WF-011 mapping, the `018 OBSERVABILITY.md` WF-011 coverage row, and OD-025 (**ratified**).

This section is the canonical owner of reassessment scheduling, execution, publication and
cancellation. It consumes the reconciliation owned by
[PRULE-017](#prule-017-issue-supersession-and-issue-set-membership) in S-12, the `reassessment.start`
Decision and reservation owned by [WF-015](#wf-015-enforce-entitlements) in S-22, and the staged
calculation owned by S-13.

### The ownership line between S-18 and S-12

WF-011 and PRULE-033 span two slices, and S-12's contract already draws the line. S-12 owns MTX-068
— the PRULE-017 two-pass reconciliation, Issue-set membership and ordering, the absence-proof modes
and the `resolution_unverified` reason precedence — and MTX-084, the CAP-014 Issue-side limb of
PRULE-033: the predecessor lifecycle and Case transitions, the successor and new Issues, and the
sealed replacement `issue_set_id`.

S-18 owns the CAP-020 limb: schedule policy, anchored cadence, slot identity and deduplication,
due-time and scope eligibility, orchestration serialization, outage coalescing, notification
suppression, the entitlement gates, the atomic publication commit itself, the `EvaluationSuperseded`
transition, the pointer advances, the Reassessment Result and the durable entitlement-commit intent.
`Workflows::Wf011::` is S-18's namespace; `Workflows::Wf007::` is S-09's and S-12's. Neither slice
redefines the other's rows.

### OD-025 is ratified, and what it ratified was a removal

`Current Status` records OD-025 **Ratified 2026-07-17, resolved by owner decision. Blocking Impact:
None.** `ReassessmentTriggered` is **removed** as a canonical domain event through the PM-REQ-009
controlled foundation change to the WF-011 coverage row in `018 OBSERVABILITY.md` recorded in
ADR-019, and **no replacement event is invented**. Volume II MUST NOT serialize the removed name.

Reassessment stays fully observable through mechanisms that were already accepted:

- `ReassessmentScheduleEvaluated` for every ordinary or latest-coalesced due slot.
- The manual command's Audit Evidence under SM-REQ-004 for manual provenance.
- `EvaluationStarted` inside the atomic Evaluation-creation commit, for a run that executes.
- `ReassessmentCompleted` for successful replacement.
- `ReassessmentFailed`, `ReassessmentCanceled` and the linked Entitlement Decision for the
  non-executing branches.

Trigger provenance — `trigger_kind`, nullable policy identity, version and content hash, slot number
and due time — is retained on the **Reassessment Result record and its Audit Evidence**, not on an
event. This is why the audit record is load-bearing here rather than incidental: it is the only
carrier of provenance, so a run whose provenance cannot be reconstructed from its own persisted
fields is itself the defect.

The Entitlement-blocked branch emits no trigger event because no trigger event exists. The question
that blocked this decision — whether an admitted trigger later blocked by Entitlement emits one —
does not arise.

### The retired blocker, recorded

`INDEX.md` lists `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010` as **Retired under ADR-019**, and
`API_CONTRACTS.md` records `Status: Resolved by ADR-019 … The semantic contract is now canonical in
Volume I`, deferring only "any corresponding API surface, transport contract, routing, serialization
or application-layer exposure … until the Volume II baseline".

Four Volume II passages still read that retired blocker as a live gate and are stale:

- `FRONTEND_ARCHITECTURE.md` — manual reassessment and schedule controls "MUST NOT render while
  `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010` leaves the mandatory trigger-event occurrence and
  affected record undefined". OD-025 has since defined both.
- The `APPLICATION_LAYER.md` `Workflows::Wf011` registry row — schedule activation, slot evaluation
  and start "remain registered but deferred".
- `BACKGROUND_PROCESSING.md` — `reassessment_slot` is a "reserved mapping only" whose insertion and
  dispatch are deferred "after correction".
- `schemas/POSTGRESQL_SCHEMA.md` — the policy activation function "rejects
  `policy_type=reassessment_schedule`", no `reassessment_slot` row "may be inserted or dispatched",
  and the columns are "migration shape only until Volume I fixes the mandatory trigger event".

The correction all four await **is ADR-019, which has occurred**. S-18 therefore adopts the division
API_CONTRACTS.md itself already draws, exactly as S-22 did for `UPSTREAM-V1-LOW-COST-METERING-005`:
the reassessment **semantics** are ratified and are contracted here in full, while the physical
transport exposure of the start and schedule-activation routes is deferred to the Volume II transport
baseline. That deferral is the ordinary route answer, not an owner-decision block, and no limb is
withheld on its authority. Treating the retired blocker as live would withhold behaviour the owner
approved. Correcting those four passages is a separate governed edit and is not performed here.

### OD-014 is pending; the state is read, never effected

OD-014's withheld limb is the Project pause/resume/archive **transition**. WF-011 **reads** Project
lifecycle state — at the due instant to select `inactive_scope / project_draft`, `project_paused` or
`project_archived`; as the `active or paused` schedule-management predicate; and as the `draft` or
`archived` rejection `F1-DOMAIN-409 / reassessment_schedule_project_ineligible`. No S-18 command
effects any of those transitions and none may be added.

OD-014's own Affected Acceptance Criteria are AC-CAP-003, AC-WF-002, AC-PRULE-003 and AC-PRULE-004 —
none of this slice's — so no row here is withheld and the matrix correctly records `None`.

One consequence must be stated precisely. Subflow step 6 admits only the first anchored slot strictly
later than a scope-restoration commit arising from "Organization reactivation or a Project
transition/resumption to active". The **Organization-reactivation limb is reachable** today. The
**Project-resumption limb is unreachable** while OD-014 is pending — not because S-18 withholds it,
but because no in-product Project resume exists to produce the commit it keys on. The predicate is
contracted, the guard is read, the transition is never effected.

### Manual reassessment does not depend on the schedule

PRULE-045 is explicit and it is two independent claims, not one: absence or disablement of the
optional `reassessment_schedule` **creates no scheduled request** *and* **does not block manual
reassessment**. Scheduled reassessment exists only when exactly one active Project-scoped
`reassessment_schedule` Policy Artifact using schema `reassessment-schedule-v1` has `enabled=true`.
No active policy, `enabled=false`, or a policy failing validation creates no scheduled request.

Entitlement and plan state **never** infer, select, shorten, extend or shift cadence. Entitlement
gates each eligible execution; it has no opinion about when the next one is due.

### The anchor is a commit instant, and only a policy change moves it

Activation commit time is the anchor. Slot `n`, for integer `n >= 1`, is due at
`effective_at_utc + n * cadence_seconds` elapsed UTC seconds. The arithmetic is exact; a payload
whose first due instant is later than `9999-12-31T23:59:59Z` is invalid. A new immediate policy
version — **including a cadence change or a re-enable** — replaces the prior version and **resets the
anchor**. Manual runs and Entitlement outcomes never shift it.

`ReassessmentScheduleRules` is exactly `project_id`, `enabled` and `cadence_seconds`: enabled requires
a positive whole decimal integer cadence, disabled requires null, and no other scheduling field
exists. No client-supplied effective or expiry time is accepted; activation is immediate with null
expiry under PRULE-045.

### A decision is always made and always recorded

The due-slot identity is `(project_id, schedule_policy_id, schedule_policy_version, slot_number,
due_at_utc)`, physically unique as `(project_id,policy_id,policy_version,slot_number,due_at)` on
`scheduled_actions`. Duplicate delivery returns the **one** stored decision and cannot create another
Entitlement Decision, Evaluation, Reassessment Result or event.

CAP-020 draws a distinction worth restating: an admitted reassessment requires the full precondition
set, but a **due-slot evaluation itself requires only its exact active-policy slot identity**, and a
missing execution precondition **records the specified nonadmitted schedule decision rather than
suppressing that decision**. The slot is never silently dropped.

The precedence is exact, total, and evaluated **before any entitlement side effect**:

1. Policy ID/version no longer the active enabled Project schedule → `superseded_policy /
   schedule_policy_superseded`.
2. Organization status at the due instant other than active → `inactive_scope /
   organization_suspended` or `organization_closed`; otherwise Project state at the due instant of
   draft, paused or archived → `inactive_scope / project_draft`, `project_paused` or
   `project_archived`. If due-time scope was eligible, the same Organization-then-Project reasons are
   applied to **current** state.
3. An existing pending/running Evaluation or completed reassessment awaiting publication →
   `active_evaluation_conflict / reassessment_already_running`.
4. In order: zero active Sources → `ineligible / active_source_required`; no current promoted
   completed Evaluation, Issue Set and ScoreSnapshot → `ineligible / initial_evaluation_required`; an
   active-Source-set membership/version that cannot be frozen consistently → `ineligible /
   source_set_unavailable`; missing, invalid or mutually conflicting required Source Scope, Crawl,
   score, confidence, eligibility or fingerprint policy context → `ineligible / policy_unavailable`.

Only after all pass does the decision record `admitted` and proceed to Entitlement. An Entitlement
Block belongs to the **admitted Reassessment Result** and does not change the schedule decision.

Equality at the boundary is decided, not approximated: a state transition committed **exactly at**
`due_at_utc` does **not** make that slot eligible, because an active state must have become effective
**strictly before** the due instant.

### A schedule decision is not a command error

`017 ERROR_MODEL.md` is explicit: `superseded_policy`, `inactive_scope`, `active_evaluation_conflict`
and `ineligible` are **immutable schedule-decision results, not command errors or retry
instructions**, and coalescing is decision metadata, never a result. The same race produces two
different outcomes by trigger kind, and that asymmetry is deliberate — a command may be told to
re-read current state, a slot may not be replayed:

- A losing **manual** start returns `F1-DOMAIN-409 / reassessment_already_running`.
- A losing **scheduled** slot records `active_evaluation_conflict / reassessment_already_running` and
  is never retried before the next ordinary slot.

Every non-admitted decision creates no Entitlement Decision, Evaluation or Reassessment Result and is
**never caught up**.

### Outage recovery coalesces; it does not catch up

After scheduler unavailability, compute every unprocessed anchored slot of the **currently active
enabled** policy whose due time is not later than recovery time. Persist exactly **one**
`ReassessmentScheduleEvaluated` decision for the **latest** elapsed slot, carrying the first coalesced
slot number and due time and a `coalesced_missed_count` covering every earlier unprocessed slot, and
evaluate only that latest slot once under the same due-time-and-current-state precedence and result
vocabulary. Earlier summarized slots are thereby **processed** and never evaluated separately.

There is no per-slot catch-up run, no `coalesced` result and no early replacement slot. A latest slot
due while its Organization or Project was inactive records `inactive_scope` **even if the scope was
restored before recovery**; if a later post-restoration slot has also elapsed, only that later slot is
evaluated and may be admitted.

### One orchestration per Project, enforced by a partial unique index

`evaluations` carries `orchestration_slot_active boolean NOT NULL` under partial unique
`(organization_id,project_id) WHERE orchestration_slot_active`, and the slot may be true only for a
reassessment or retry that is pending, running or completed-awaiting-publication. That index is why
"only one reassessment orchestration may be pending, running, or completed-awaiting-publication per
Project" is true under concurrency rather than true on average.

This guard mirrors the OD-018 single-orchestration guard WF-005 applies to initial Evaluations, which
is ratified and keys on pending/running only, never on existence — the two guards are siblings, not
duplicates, and neither substitutes for the other.

### Creation and start are one commit

An admitted start serializes the Project orchestration guard, records provenance, re-resolves policy
immediately before execution, obtains the high-cost `reassessment.start` Decision and reservation,
freezes the active Source-set version and normalized full-scope hash, and **atomically creates the new
Evaluation and moves it `Pending -> Running`** with its immutable orchestration context linked to the
prior completed Evaluation. That atomicity is why a targetable Evaluation is never durably visible in
`pending`, which in turn is why the Cancellation Path never needs a pending case.

The Evaluation is running **before** its nested Crawl, and WF-006/WF-007 **reuse** that Running state:
stage reuse emits exactly **one** `EvaluationStarted`, because WF-007 continues the already-running
reassessment Evaluation without another start transition or event.

`reassessment.start` subsumes the nested WF-005 through WF-008 core; those stages MUST NOT also
reserve or commit `crawl.start`, and every stage records the root Decision/reservation ID so nesting
cannot double meter.

### Publication is one commit, and its width is the requirement

Immediately before publication, re-resolve the active Source-set version and normalized full-scope
hash. Any difference is `source_scope_changed_during_reassessment` and publishes **none** of the
staged result. Equality of prior and current `scope_snapshot_id` is **not** required when the
normalized full-Project scope-definition hash is unchanged.

Otherwise one atomic domain commit contains: the prior current Evaluation's completed-to-superseded
transition and `EvaluationSuperseded`; every predecessor lifecycle and Case transition; every
successor and new Issue; the sealed replacement `issue_set_id`; all staged Score Contributions and the
ScoreSnapshot; current Issue-set, ScoreSnapshot and Current Score Projection pointers; Recommendation
suppression and publication deltas; the terminal completed Reassessment Result; and **one durable
entitlement-commit intent**. WF-008 in reassessment staging mode advances **no** pointer before it.

The width is not incidental. Any narrower boundary would let a replacement Issue set become current
while the prior ScoreSnapshot stayed promoted — a Project whose score no longer describes its Issues.

### Nonsuccess preserves everything

The mapping is exhaustive and no other customer-visible pair is allowed: Entitlement Block →
`entitlement / entitlement_blocked`; Crawl failure → `crawl / crawl_failed`; parsing or check pipeline
failure → `evaluation / evaluation_pipeline_failed`; stage timeout → the active stage plus
`stage_timeout`; unavailable score → `scoring / score_unavailable`; Source/scope mismatch →
`publication / source_scope_changed_during_reassessment`; atomic validation, conflict or write failure
→ `publication / publication_failed`; accepted cancellation → `cancellation / canceled_by_actor`.

The Evaluation-state consequence is asymmetric and both sides matter: pipeline failure or timeout
**before** Evaluation completion transitions running to failed, while unavailable score, scope race,
publication failure and post-completion cancellation leave the Evaluation **completed** and record
only the failed or canceled Reassessment Result. A precreation Entitlement Block creates no Evaluation
at all — its Result carries null `current_evaluation_id` and null `current_scope_snapshot_id`.

Every nonsuccess records its Result **outside** the failed publication transaction, emits no
entitlement commit intent, releases the reservation exactly once, and leaves every prior current
pointer and every Current Score Projection field unchanged. An unavailable staged ScoreSnapshot is
diagnostic only and never becomes latest or current.

### Cancellation races are decided by fixed winners

At the exact Evaluation-completion checkpoint **completion wins**, and the cancellation is then
evaluated in the post-completion window. At the exact publication commit **publication wins** and
cancellation is rejected as `reassessment_already_terminal`. Running cancellation transitions the
Evaluation to failed with `canceled_by_actor` and releases; post-completion pre-publication
cancellation leaves it completed, records the canceled Result, discards staged publication and
releases. Cancellation before an Evaluation identifier exists or after a terminal Result is rejected
with no state change.

### Retry is a new attempt, never a reopened one

Retry creates a **new Evaluation attempt linked by causation ID**. A completed immutable stage may be
reused **only** when its full input hash matches, so replay cannot duplicate Issues, usage, snapshots
or events. There is no slot retry at all: a non-admitted slot is terminal, an Entitlement Block
creates no early retry and does not shift the anchor, and the next ordinary slot is evaluated
normally.

### Schedule evaluation is silent to the customer

Schedule evaluation itself creates **no** customer Notification. A scheduled run uses the same nested
Crawl, entitlement, score and failure routes as a manual run, and a clean full reassessment creates no
dedicated schedule notification. Skipped and conflicting decisions, and the summarized coalesced slot
range retained on the latest-slot decision, create Audit Evidence and operational telemetry only.

Schedule decisions are measured **separately** from `ReassessmentFailed`: a skipped slot is not a
failed run, and conflating them would report an idle Project as broken.


## CAP-020 Reassessment


Matrix row: MTX-020 (AC-CAP-020). Slice: S-18.
Structured contract: `specification/volume-ii/contracts/S-18.json`.

CAP-020 defines no interface of its own; its obligations are discharged by the WF-011 contract above.
Its Dependencies are WF-011 and WF-012, so the historical-comparison surface it feeds is S-17's. Its
Business Rule is PRULE-033, whose CAP-014 Issue-side limb is S-12's MTX-084 and whose CAP-020 limb is
contracted at [WF-011](#wf-011-trigger-reassessment).

Its Failure Condition is the assertion set, not a description. A missing, disabled or invalid schedule
creates no scheduled request. A superseded-policy, inactive-scope, active-Evaluation-conflicting or
ineligible latest slot records exactly **one** terminal schedule decision and no Entitlement,
Evaluation or Result, while any earlier missed slots exist **only as its coalescing metadata**.
Duplicate delivery returns that decision. An Entitlement Block, Source/scope race,
pipeline/scoring/publication failure or running/post-completion cancellation produces the exact
Evaluation/Result/reservation outcome, changes **no** prior Current Score Projection field, and emits
one terminal event. Unavailable staged diagnostics never become latest or current.

CAP-020's Non-goal is worth naming because a scheduler is exactly the mechanism that would breach it:
**no automatic policy override of previous operator decisions**. A scheduled run cannot reverse an
adjudication. A prior `upheld` or `withdrawn` remains historical; the successor derives its state
afresh from current confidence rather than inheriting a decision an operator made about a different
observation.

Its AI Implication is narrow and stays narrow: AI recommendation refresh uses current evidence and
versions, and remains a separately metered `ai.generate` operation rather than a limb of
`reassessment.start`.

---

## WF-012 Compare Historical Results


Matrix row: MTX-037 (AC-WF-012). Slice: S-17.
Structured contract: `specification/volume-ii/contracts/S-17.json`.
Governing authority: WF-012, CAP-019, PRULE-032, the Reassessment Result And Historical Comparison
contract and the Score Visibility And Redaction contract in `SCORE_EVIDENCE_MODEL.md`, the Permission
Baseline, and OD-024 (**ratified**), OD-020 (**ratified**), OD-019 (**ratified**), OD-002, OD-003 and
OD-009 (all **ratified**).

This section is the canonical owner of the historical comparison read. It consumes promoted
ScoreSnapshots and their immutable Score Contributions, owned by S-13, and the visibility rules owned
by S-16, and it is consumed by nothing: S-17 gates no slice.

### No pending decision touches this slice

S-17's three rows cite OD-002, OD-003, OD-009, OD-020 and OD-024. Every one is ratified. None of the
five pending decisions — OD-014, OD-023, OD-027, OD-031, OD-032 — appears on any S-17 row, and none
of their withheld limbs is reachable from a comparison read. `SLICE_REGISTER.md` records S-17's OD
limbs as `none`. **This slice withholds nothing.**

### OD-024 is ratified; the missing event is the approved baseline

`Current Status` records OD-024 **ratified 2026-07-17, resolved by owner decision**, with
`Blocking Impact`: **"None. OD-024 is resolved; comparison reads are unblocked and emit no domain
event."** Approved Option 2: `ComparisonGenerated` is **removed** as a Volume I domain event.

Read that precisely, because the shape is the same as OD-010's. The ratification does not withhold an
event pending a later decision — it **approves the state in which no event exists**, and approves its
consequence: the comparison read persists no record, moves no current pointer, and emits nothing. The
workflow's audit obligations are discharged **entirely** by Audit Evidence with correlation ID, which
is exactly why the removal costs the workflow nothing. Concretely:

- Every outcome — `comparable`, `not_comparable`, `insufficient_history`, `comparison_unavailable` —
  remains fully deterministic under `SCORE_EVIDENCE_MODEL.md`.
- `ComparisonGenerated` is permanently excluded from the executable event-registry manifest, so no
  generic Event row may admit it and no migration may reintroduce it without controlled Volume I
  change.
- Volume II MUST NOT emit, suppress, deduplicate or **meter** the removed name.

The questions that once made the event undefinable — whether it occurred for each outcome, whether
reload, Turbo prefetch or repeated selection re-emitted it, what its idempotency identity was — no
longer arise, because no event exists. This slice contracts **zero** domain events and asserts their
absence as a test obligation rather than leaving it implied.

### The two "disabled" cells are stale, and this slice does not honour them

Two Volume II table cells describe `QRY-008` as switched off. `APPLICATION_LAYER.md` line 159 names
two tags as disabling the query, and `API_CONTRACTS.md` line 593 names the same two as deferring the
physical path. Both tags are `UPSTREAM-V1-LOW-COST-METERING-005` (OD-019) and
`UPSTREAM-V1-COMPARISON-EVENT-007` (OD-024), and both are **Retired under ADR-019**. **Both cells are
therefore stale Pass-A-era prose that this section supersedes.** The evidence is executable rather
than interpretive:

1. `INDEX.md`'s canonical blocker registry records **both** tags **"Retired under ADR-019"**. Only
   `UPSTREAM-V1-PROJECT-LIFECYCLE-003` (OD-014) and `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009`
   (OD-023) are marked **LIVE**.
2. OD-024's `Blocking Impact` is affirmative, not merely absent: **"comparison reads are unblocked"**.
   OD-019's is `None`.
3. Decisively: the matrix is **generated**, and its `Blocker` column is computed by
   `scripts/build_volume_ii_matrix.py` from each cited decision's `Current Status` **alone** — a row
   is blocked if and only if one of its decisions is pending. MTX-019, MTX-037 and MTX-083 each carry
   `Blocker: None`, `Status: Pass B required`. **Neither retired tag appears as a blocker on any row
   in the corpus**; the only blockers present anywhere are the five pending decisions and their two
   live tags. The matrix is "the controlling source for Pass B".
4. The `INDEX.md` prose reserves the word **unreachable** for what is genuinely withheld —
   "Rotation begin/completion remains unreachable" — and the `UPSTREAM-V1-COMPARISON-EVENT-007`
   section uses no such word.

Honouring those two cells would withhold behaviour the owner **affirmatively unblocked**. That is the
OD-001 failure mode the ratification overlay exists to prevent, and it is as wrong as pre-empting an
open decision.

**The boundary matters.** "Deferred until the Volume II baseline" resolves **to** this pass — but it
is a *document-ownership* statement, not a grant to a slice contract. The exposure is deferred to
`API_CONTRACTS.md` and this document, which own transport and the query registry; it is not deferred
to `contracts/S-17.json`. So this slice defines **no route**, exactly as every completed slice did.
Nothing needs inventing in any case: `API_CONTRACTS.md` **already** carries the project-scoped
history-compare GET against `QRY-008` and `history.read`. The transport was authorized; only the
deferral marker on it is stale.

### Clearing the marker is not sufficient — the metered operation must be declared

The comparison read is a metered low-cost read: WF-015 enumerates `history.view` among exactly five
low-cost operations. OD-019's Ratified Behavior requires that **"every metered read route carries a
static declaration of exactly one of the five low-cost operations; a read route with no declaration
resolves `operation_unknown` and returns Block with `contact_support`, so an undeclared metered route
is unreachable rather than silently unmetered."**

`API_CONTRACTS.md`'s route table has columns `Route | Query | Permission | Enablement` and **no
operation-declaration column**; no route in Volume II carries such a declaration. The
`operation_unknown` reason code and `contact_support` recovery action already exist in
`EntitlementNoticeDTO`, so the Block-on-undeclared path is modelled while the declaration that avoids
it is not.

This gap is **not S-17's to close**: it spans all five low-cost operations across every metered read
route, the metering contract is WF-015 and CAP-024 owned by S-22 on MTX-040 and MTX-024, and
inventing a declaration mechanism would mint a transport contract no one authorized. Note too that
the five low-cost operation strings are **not permissions** — `history.view` does not exist in the
Permission Baseline, whose read is `history.read` — so the declaration cannot be inferred from the
route's permission cell. This section names `history.view` as the operation the comparison read
declares and stops there.

### The read is side-effect-free; the metering record is not its side effect

WF-012 declares no domain entity transition and is triggered by a safe read. The comparison writes
nothing: no comparison record, no pointer move, no event, no mutation of any snapshot, Contribution,
Issue, Case, Evidence record or Current Score Projection.

One record does get appended on the path, and it is worth naming precisely so it is not mistaken for
a breach of that property. Under `read-metering-v1` exactly one LowCostUsageRecord is appended per
accepted top-level document read reaching the durable response checkpoint, keyed by a server-minted
Decision ID over Organization, actor or service identity, declared operation, resolved target
identity and state version, and counter window. That is **WF-015's** side effect under **S-22's**
contract, not WF-012's, and Turbo Frames of a declared root carry the root Decision ID and append no
second record. Client-supplied idempotency keys remain prohibited on the read.

### The rebase spans two slices

WF-012's Alternate Path is the one place the comparison reaches a command, and this section owns only
half of it.

**S-17 owns the request**: the `score.rebase` authorization, the requirement of an exact target
version for every one of the seven versioned dimensions available to **both** retained input sets,
the rejection of omission or ambiguity, and the rule that rebase can never overcome different
normalized `scope_definition_hash` values.

**S-13 owns what an admitted request creates**: the ScoreSnapshot contract on
[MTX-076](#prule-025-score-recalculation-and-snapshot-lineage) supplies the `historical_rebase`
creation reason, the immutability and idempotency tuple, the `prior_score_snapshot_id` lineage, the
per-Project serialization, the two-snapshot creation order (earlier Evaluation by `created_at_utc`,
then Evaluation ID, first), and the rule that a rebase snapshot is **permanently noncurrent** and
advances no Current Score Projection pointer.

Volume I fixes the rebase's actor, permission, predicate and rejection outcomes but names no command
identifier and no owning command namespace, so this section contracts the request contract and does
**not** mint a `Workflows::Wf012::` command name for it.

### Four outcomes, no fifth, and two of them are not errors

Every request reaches exactly one of four statuses:

- `comparable` — all eight dimensions matched; carries `overall_delta` and one `PillarDeltaDTO` per
  applicable pillar.
- `not_comparable` — carries **every** applicable mismatch code in fixed order and **no** numeric
  score delta.
- `insufficient_history` — fewer than two completed Evaluations with promoted ScoreSnapshots; carries
  `available_run_count` of exactly 0 or 1 and `next_action_code=complete_initial_evaluation` for zero
  or `complete_next_evaluation` for one; returns null selected items and no empty or synthetic delta.
- `comparison_unavailable` — carries a correlation ID and synthesizes no values.

The distinction that carries this row: **`not_comparable` and `insufficient_history` are successful
deterministic outcomes carrying reason codes, not errors.** Returning `F1-VALIDATION-400` for an
incompatible pair would destroy the mismatch-code contract that tells a caller what to fix, and
returning an error for zero completed Evaluations would contradict CAP-019's Preconditions, which
state expressly that zero or one completed Evaluation is a **valid** insufficient-history query.

### The projection rebuild names an obligation with no surface

Volume I states an obligation here for which it supplies no implementation surface, and this section
**reports the gap rather than closing it**.

WF-012's Failure Path returns `comparison_unavailable` for "Missing projection data" and its Recovery
Path offers "retry projection generation", bounded to one initial attempt plus two retries at 1 and 5
minutes before terminal `comparison_unavailable` and escalation to support.

But under OD-024 Option 2 **nothing is persisted by the comparison read**, so there is no comparison
projection to be missing or to rebuild, and no comparison table, job or read model exists in
`schemas/POSTGRESQL_SCHEMA.md` or `BACKGROUND_PROCESSING.md`. OD-024's own Operational Implications
flagged exactly this — *"every option must reconcile WF-012's 'Missing projection data' and
'Projection rebuild' language with the chosen model or clarify that it refers to the Current Score
Projection"* — and the Ratified Behavior **does not perform that reconciliation**. The Current Score
Projection is the only projection Volume I defines that can be unavailable, but historical comparison
selects two immutable promoted ScoreSnapshots by ID and reads it for neither side, so it cannot be
the referent without a controlled change that says so.

This section therefore contracts what **is** fixed — `comparison_unavailable` is a reachable terminal
outcome carrying a correlation ID, it synthesizes no values, and the retry bound is exactly one
attempt plus two retries at 1 and 5 minutes then terminal plus support escalation — and invents no
comparison projection entity, table, job or rebuild command to sit behind them. The slice still
reaches its outcome: `comparable`, `not_comparable` and `insufficient_history` are each fully
determined without any projection artifact.

### History is read, never rewritten

Historical views reconstruct Issue and adjudication state **only** from each ScoreSnapshot's
immutable Contributions — captured Issue state version, lifecycle, publication and adjudication
values, Case references, Evidence IDs and Validation Decision IDs and statuses. Later Issue or
Evidence decisions do not rewrite historical state.

This is what makes the read raceless. A concurrent adjudication, dispute or Evidence validation change
marks the **Current Score Projection** unavailable with `invalid_evidence` or `issue_set_incomplete`
and may suppress published Recommendation Artifacts, but it rewrites no historical Contribution and
therefore cannot change a comparison already determined from frozen state. The same ordered pair
returns the same status, codes and deltas forever.

Redaction runs the other way. It is applied at serialization against the **current** actor and the
strongest classification among each derived field's originating Evidence records — never against the
actor or classification frozen at snapshot time. A historical snapshot does not carry forward the
visibility of whoever created it.


## CAP-019 Historical Comparison


Matrix row: MTX-019 (AC-CAP-019). Slice: S-17.
Structured contract: `specification/volume-ii/contracts/S-17.json`.
Governing authority: CAP-019, discharged by [WF-012](#wf-012-compare-historical-results) on MTX-037
and [PRULE-032](#prule-032-comparison-compatibility-and-rebase) on MTX-083, with OD-020 and OD-024
(both **ratified**).

CAP-019 defines no interface of its own. It fixes the actor set, the four outputs, the success and
failure conditions, and one prohibition this row owns outright.

### OD-020's answer here is a grant, not a denial

OD-020 is ratified, Approved Option 1: explicit read rows are added for Organization home data,
Project, Source, Crawl, Evaluation, Notification inbox and Export enumeration, and **"deny-by-default
is not accepted for customer-facing objects"**.

Its effect on this capability was never in doubt. `history.read` is **already** one of the Permission
Baseline's enumerated read actions — OD-020's own Why-The-Decision-Exists names it among the closed
set of existing reads — so the comparison read has canonical read authority and needs none inferred.
OD-020 additionally makes `project.read` canonical, which is what lets the Project-scoped target
resolve. Nothing in this slice reads a security or administrative object, so OD-020's remaining
deny-by-default limb is never reached here.

### The AI-narrative prohibition is capability-level authority

This is product authority, not a presentation preference, and it is stated three times over — in
CAP-019's AI Implications, WF-012 Primary Path step 3, and PRULE-030. Historical comparison returns
deterministic structured data only and MUST NOT **create, request, return, display, reserve a
presentation region for, or imply** AI-generated dashboard or history narrative, and MUST make **no
AI-provider call** for that purpose.

Read the verb list precisely, because it is broader than "do not render narrative":

- **Reserving a presentation region** for narrative is itself a breach. A reserved-but-empty slot
  fails the rule as surely as a populated one.
- **Narrative absence is a complete successful response** — not an error, degraded state, incomplete
  response, or fallback. There is no error code for a missing narrative because none is ever
  attempted.
- **No hidden enablement path may exist.** No feature flag, provider availability, model capability,
  tenant setting, UI layout or implementation choice may enable narrative. The prohibition is
  *unreachability*, not a disabled default — a disabled default is one flag away from a prohibited
  behaviour.
- `QRY-008` MUST NOT reference `AiOrchestration`, expose a narrative field, reserve a narrative slot,
  **enqueue narrative work**, or call a provider.

Equally, the rule must not be over-applied. Deterministic human-authored labels, already-defined
templates, and existing deterministic score, trend, Issue, Evidence and Recommendation explanations
remain **permitted and unchanged**, and are asserted present. Future AI narrative support requires a
separately accepted capability and controlled Volume I change under PRULE-030 with explicit
requirements, evaluation, grounding and provenance, latency and cost, failure and fallback, and
acceptance contracts.

### The Failure Condition is four asserted impossibilities

CAP-019 fails if **silent cross-version comparison, synthetic missing data, later-state rewrite of
history, or unbounded projection rebuild** occurs. Each maps to exactly one contracted guard:

| Failure Condition | Guard | Owner |
| --- | --- | --- |
| Silent cross-version comparison | the eight-dimension compatibility predicate | MTX-083 |
| Synthetic missing data | no-synthesis on every outcome | MTX-037 |
| Later-state rewrite of history | state-at-snapshot reconstruction from immutable Contributions | MTX-037 |
| Unbounded projection rebuild | one attempt plus two retries at 1 and 5 minutes, then terminal | MTX-037 |

Predictive forecasting is a Non-goal and sits outside the boundary entirely: no forecast,
extrapolation or projection-forward field exists in any response.

---

