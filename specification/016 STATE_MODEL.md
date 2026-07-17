# 016 STATE_MODEL

## Status

- Status: Accepted
- Foundation Version: 1.0
- Last Updated: 2026-07-16

## Authority

This document is the canonical state and transition model for lifecycle-bearing concepts in F1.

All workflow specifications and implementation plans MUST conform to these state rules.

## Purpose

Define canonical states, transitions, authorities, retry behavior, timeout behavior, failure handling, and audit event requirements.

## Scope

This document defines state models for:

- Accounts
- Sessions
- Organizations
- Projects
- Sources
- Documents
- Crawls
- Ingestion jobs
- Parsing jobs
- Indexing jobs
- Evaluations
- Evidence validation
- Issues
- Recommendation artifacts
- Legal holds
- Lifecycle deletion jobs
- AI responses
- Citations
- Exports
- Notifications and Deliveries
- Billing entities
- Integrations
- Credentials

## Dependencies

- [011 DOMAIN_MODEL.md](011%20DOMAIN_MODEL.md)
- [012 SYSTEM_BOUNDARIES.md](012%20SYSTEM_BOUNDARIES.md)
- [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md)
- [015 DATA_LIFECYCLE.md](015%20DATA_LIFECYCLE.md)
- [017 ERROR_MODEL.md](017%20ERROR_MODEL.md)
- [018 OBSERVABILITY.md](018%20OBSERVABILITY.md)

## Definitions

- State: Named lifecycle condition for an entity.
- Transition: A valid movement from one state to another.
- Terminal State: A state with no forward progression in the current lifecycle.
- Recovery Path: Authorized transition from failure state to resumed flow.

## Assumptions

- State transitions are initiated by user action, automation workflows, or policy controls.
- Transition authority is role-based and system-context aware.
- Retryable workflows require idempotency guarantees.

## Constraints

- Each lifecycle-bearing concept MUST define valid and invalid transitions.
- Transition authorization MUST be explicit.
- State changes MUST generate audit events.

## Normative Requirements

### Global State Rules

SM-REQ-001: Every state machine MUST include explicit states, entry conditions, and exit conditions.

SM-REQ-002: Every state machine MUST define valid and invalid transitions.

SM-REQ-003: Every transition MUST define authority, idempotency behavior, retry behavior, timeout behavior, failure states, terminal states, and recovery paths.

SM-REQ-004: Every transition attempt MUST emit an audit event with exactly one of `actor_id` or `service_identity_id`, plus `entity_id`, `from_state`, `to_state`, `outcome`, and `timestamp_utc`. Both identity fields being present or both being absent is invalid.

SM-REQ-005: Retryable transitions MUST be idempotent.

SM-REQ-006: Timeout behavior MUST map to a deterministic failure, retry, or explicit provider-response-uncertainty transition. Uncertainty is mandatory when an external side effect may have occurred and acceptance cannot be disproved; automatic re-execution is prohibited while that uncertainty remains.

### Canonical State Machines

| Concept | States | Entry Conditions | Exit Conditions | Valid Transitions | Invalid Transitions | Transition Authority | Idempotency, Retry, Timeout | Failure and Terminal States | Recovery Paths | Audit Events |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Account | pending, active, suspended, revoked | pending exists only inside the authorized tenant-scoped provisioning transaction and is not product-readable or permission-bearing | the provisioning transaction commits pending to active atomically or rolls back the Account; revoked when access is permanently removed | pending to active in the provisioning commit; active to suspended; suspended to active; active to revoked; suspended to revoked | any product-visible or separately committed pending Account; pending to suspended or revoked; revoked to active | Identity and Access Context plus OrganizationAdmin for tenant-managed suspend and reactivate | provisioning and suspension commands are idempotent; provisioning failure or timeout rolls back the whole transaction and exposes no Account, Assignment, Session, or lifecycle event; suspension returns only after session revocation commits | pending has no persisted failure state or reason; terminal state revoked | correct the cause and submit a new provisioning command; no failed pending Account is reused; revoked requires a new Account | AccountProvisionRequested, AccountActivated, AccountSuspended, AccountReactivated, AccountRevoked |
| Session | active, revoked, expired | active only when WF-001 atomically consumes a valid purpose-bound Identity Validation Receipt after the exact Account/Organization/assurance checks | revoked on Account/Organization suspension, revocation, or closure; on termination by the Session's own authenticated subject; or on explicit security revocation of one identified Session; expired when server time reaches idle or absolute expiry | active to revoked; active to expired | revoked or expired to any state; extension of absolute expiry; refresh of the same Session | Identity and Access Context; the Session's own authenticated subject holding `session.terminate` for that Session only; a SecurityOperator holding `session.revoke` for one identified Session; session lifecycle service performs timed expiry | exact sign-in replay returns the same Session; distinct fresh receipts may create concurrent Sessions without a count limit and do not revoke one another; termination and revocation act on exactly one identified Session and never cascade to concurrent Sessions of the same Account; terminating or revoking an already terminal Session is idempotent and changes no state; accepted activity advances idle expiry only; at equality expiry wins; no automatic sign-in retry or Session refresh exists | revoked and expired are terminal | reauthentication with a fresh receipt creates a distinct Session; no terminal Session reopens | SessionCreated, SessionRevoked, SessionExpired |
| Organization | pending, active, suspended, closed | pending within an authorized bootstrap transaction | closed when dual-controlled closure atomically revokes access and creates the lifecycle job; retained/held destruction may continue afterward | pending to active; active to suspended; suspended to active; active to closed; suspended to closed | pending to closed without validation; closed to active | Tenant Governance Context under WF-013 | activation/suspension/closure commands use expected state and authorization versions; closure exact replay returns the same job; closure failure leaves prior state with the exact WF-013 reason code for the failed predicate, such as `billing_entity_state_invalid` for a missing or nonactive current BillingEntity | failure reasons do not create states; terminal state closed | correct input/authority and submit against current state; hold release resumes the deletion job but never reopens Organization | OrganizationCreated, OrganizationActivated, OrganizationSuspended, OrganizationReactivated, OrganizationClosed |
| LegalHold | pending, active, rejected, released | pending after a protected two-person hold request is persisted | rejected or released after the distinct decision | pending to active; pending to rejected; active to released | active to rejected; released or rejected to any state | Security Context with `legal_hold.manage`, Support Session and distinct requester/approver | expected version and idempotency mandatory; no automatic expiry; stale/self-approved request has no transition | rejected and released terminal | correction creates a new Hold; release queues each intersecting blocked deletion job once | LegalHoldRequested, LegalHoldActivated, LegalHoldRejected, LegalHoldReleased |
| EmergencyAccessGrant | pending, active, rejected, revoked, expired | pending after a SecurityOperator holding `emergency_access.request` persists a request naming an open severity-critical Incident, exactly one Organization, an enumerated resource scope, an enumerated action scope, and a reason | rejected on a distinct approver's denial; revoked by `emergency_access.revoke` before expiry; expired when server time reaches the bound resolved from the active `emergency-access-v1` policy version | pending to active; pending to rejected; active to revoked; active to expired | active to rejected; rejected, revoked, or expired to any state; extension of an approved lifetime; approval by the requester | Security Context with `emergency_access.request` plus a distinct approver holding `emergency_access.approve`; emergency-access lifecycle service holding `emergency_access.expire` performs timed expiry | expected version and idempotency mandatory; a stale or self-approved request commits no transition; exercising an expired or revoked Grant performs no side effect and commits no transition | rejected, revoked, and expired are terminal | correction creates a new Grant under a new approval; no terminal Grant reopens and no approved Grant is extended | EmergencyAccessRequested, EmergencyAccessApproved, EmergencyAccessRejected, EmergencyAccessRevoked, EmergencyAccessExpired |
| LifecycleDeletionJob | queued, running, blocked, failed, completed | queued from accepted Account deletion or Organization closure | completed only from running with immutable Deletion Evidence; blocked on active hold; failed on exhausted/nonretryable work or deadline | queued to running; queued or running to blocked or failed; running to completed; blocked to queued after hold release; failed to queued by authorized replay | queued to completed; completed to any state; blocked to running before hold release | Data Lifecycle Context; deletion service executes, `deletion.retry` requests failed replay | attempts/replay/deadlines follow `retention-interim-v1`; exact replay duplicates no deletion; timeout/deadline never fabricates completion | failed is recoverable only by new generation; completed terminal; blocked is nonfailure hold state | release exact hold or submit authorized retry; irreversibly deleted bytes cannot recover | AccountDeletionRequested, OrganizationDeletionRequested, AccountDeletionBlocked, OrganizationDeletionBlocked, LifecycleDeletionFailed, AccountDeletionCompleted, OrganizationDeletionCompleted |
| Project | draft, active, paused, archived | draft on project creation | archived when no further monitoring is allowed | draft to active; active to paused; paused to active; active to archived; paused to archived | draft to archived; archived to active | Project Context with the Volume I permission contract | activation is idempotent; any prerequisite, authority, policy, race, dependency, or timeout failure leaves Project draft, records lifecycle outcome class `activation_failure` with the exact WF-002 reason code, and emits no activation event | `activation_failure` is an outcome class while draft, not a state or substitute reason code; terminal state archived | remediate the exact WF-002 reason and submit a new activation command against the current Project and Source-membership versions | ProjectCreated, ProjectActivated, ProjectPaused, ProjectReactivated, ProjectArchived |
| Source | proposed, verified, active, disabled, removed | proposed on source registration | removed after cleanup | proposed to verified; verified to active; active to disabled; disabled to active; disabled to removed | proposed to active without verification; removed to active | Intake Context | Verification Request retries MUST be idempotent; observation timeout leaves Source proposed and follows the bounded Request schedule; Request expiry/cancel/failure also leaves Source proposed | verification failure is retained on the Verification Request rather than invented as a Source state; terminal: removed | a new Verification Request may be created while Source remains proposed | SourceRegistered, SourceVerified, SourceActivated, SourceDisabled, SourceRemoved |
| Document | discovered, ingested, parsed, indexed | discovered after an accepted crawl/import fetch creates the Document and its ingestion lineage | indexed is terminal; a Document leaves product use only through the separate retention and deletion lifecycle, which destroys the record rather than transitioning it | discovered to ingested; ingested to parsed; parsed to indexed | discovered to parsed or indexed; ingested to indexed; same-state transitions; any transition out of indexed | Intake and Retrieval Contexts | ingestion, parsing, and indexing retries occur on their Job records and never move or regress a Document on failure; each failed Job retains the exact workflow reason while the Document remains at its last committed state | Job failure is not a Document state; terminal state indexed | a successful authorized replacement Job advances from the last committed state; corrected bytes create a new immutable Document version | DocumentDiscovered, DocumentIngested, DocumentParsed, DocumentIndexed |
| Crawl | queued, running, completed, failed, canceled | queued on schedule or manual request | completed, failed, canceled | queued to running; queued to failed only when the immediate pre-execution policy, entitlement, or integrity gate denies start; running to completed; running to failed; queued or running to canceled | completed to running | Intake Context | retries from failed MUST be a new attempt with idempotency key; timeout from running to failed; a queued gate failure performs no fetch/provider side effect | failure: failed; terminal: completed, canceled | failed to queued through a new linked retry request | CrawlQueued, CrawlStarted, CrawlCompleted, CrawlFailed, CrawlCanceled |
| IngestionJob | queued, running, succeeded, failed, dead_letter | queued by crawl output | succeeded, failed, dead_letter | queued to running; running to succeeded; running to failed; failed to queued; failed to dead_letter | succeeded to running | Intake Context | failed retries MUST use same idempotency key; timeout from running to failed | failure: failed; terminal: succeeded, dead_letter | dead_letter to queued only by authorized operator replay | IngestionQueued, IngestionStarted, IngestionSucceeded, IngestionFailed, IngestionDeadLettered |
| ParsingJob | queued, running, succeeded, failed, dead_letter | queued after ingestion success | succeeded, failed, dead_letter | queued to running; running to succeeded; running to failed; failed to queued; failed to dead_letter | succeeded to queued | Intake Context | retries MUST be idempotent by document hash and parser version; timeout to failed | failure: failed; terminal: succeeded, dead_letter | dead_letter to queued with approved replay | ParsingQueued, ParsingStarted, ParsingSucceeded, ParsingFailed, ParsingDeadLettered |
| IndexingJob | queued, running, succeeded, failed, dead_letter | queued after parse success | succeeded, failed, dead_letter | queued to running; running to succeeded; running to failed; failed to queued; failed to dead_letter | succeeded to running | Retrieval Context | retries MUST be idempotent by index target and source snapshot | failure: failed; terminal: succeeded, dead_letter | dead_letter to queued with approved replay | IndexingQueued, IndexingStarted, IndexingSucceeded, IndexingFailed, IndexingDeadLettered |
| Evaluation | pending, running, completed, failed, superseded | pending only when an authorized trigger creates a new Evaluation instance; `superseded_policy`, `inactive_scope`, `active_evaluation_conflict`, or `ineligible` schedule decisions create none, and coalescing is only decision metadata | completed or failed when execution ends; superseded only when successful reassessment publication atomically replaces the current completed predecessor | pending to running; running to completed; running to failed; completed to superseded in the replacement publication commit | failed to pending, running, completed, or superseded; superseded to any state; completed to superseded outside a valid atomic replacement publication; a second pending/running or completed-awaiting-publication reassessment for one Project | Evaluation Context under WF-011 for replacement publication | exact manual command or schedule-slot replay returns the same outcome; the Project orchestration guard admits at most one pending/running or completed-awaiting-publication reassessment; a retry after failure creates a new pending Evaluation linked by `retry_of_evaluation_id`; a running timeout moves that instance to failed; supersession uses the locked predecessor/current-pointer versions and exact replay emits no second transition | failed is terminal failure for that instance; superseded is terminal; completed is stable but may become superseded only by a successfully published completed replacement | no failed or superseded instance reopens; correct a failed cause and create a linked retry Evaluation; failed/canceled replacement publication leaves the completed predecessor unchanged | EvaluationPending, EvaluationStarted, EvaluationCompleted, EvaluationFailed, EvaluationSuperseded |
| Evidence effective validation | valid, quarantined, invalid | creation-time validation produces valid, invalid, or quarantined under the Evidence contract | a new immutable Validation Decision changes the effective status; the Evidence envelope and Payload never mutate | valid to quarantined; quarantined to valid; valid to invalid; quarantined to invalid | same-status decision; invalid to any state; any transition by an unnamed authority/reason | Evidence Context integrity-validation service; SecurityOperator may request only the explicitly permitted quarantine reasons | decision command uses expected state version and idempotency; exact replay returns the same Decision; a failed revalidation leaves prior effective status; timeout creates no Decision or inferred status | invalid is terminal; quarantined is nondecision-grade but recoverable only by complete revalidation | corrected content creates new Evidence; quarantined may return to valid only after every retained-byte/digest/schema/tenant/consent/retention/authority predicate passes | EvidenceValidationChanged |
| Issue | candidate, open, resolved, dismissed, superseded | candidate or open from a failed Check Result under the active confidence policy | resolved, dismissed, superseded | candidate to open, resolved, dismissed, or superseded; open to resolved, dismissed, or superseded | any terminal record to candidate or open; cross-Organization or cross-Project transition | Evaluation Context under the Volume I Issue lifecycle, adjudication, and supersession contract | commands require expected state version and idempotency; reassessment creates immutable successor records and never reopens a terminal record | terminal: resolved, dismissed, superseded | recurrence creates a new linked Issue; incomplete coverage leaves the current Issue unchanged | IssueCreated, IssueDisputed, IssueAdjudicated, IssueResolved, IssueSuperseded |
| RecommendationArtifact | draft, published, suppressed, retired | draft when the Recommendation Context persists a new immutable Artifact version linked to exactly one origin Issue | published after complete schema, origin-eligibility, Evidence, and policy validation; suppressed when publication is withheld or a published origin becomes ineligible; retired when the version is permanently withdrawn or replaced | draft to published; draft to suppressed; published to suppressed; suppressed to published only after current origin eligibility and complete validation are re-established; draft, published, or suppressed to retired | published or suppressed to draft; retired to any state; any transition based only on informational related Issues | Recommendation Context; generation service creates drafts, the deterministic publication service or an OrganizationAdmin or MarketingOperator holding `recommendation.publish` publishes, and the lifecycle service suppresses or retires only from the governing origin, Evidence, or version rule | creation and transition commands require artifact-version preconditions and idempotency; exact replay returns the same outcome; generation timeout creates no partial version or leaves an existing draft unchanged with its exact reason; changed content creates a new linked draft version rather than mutating a version | publication-validation failure is retained as an exact reason while draft or suppressed and is not a state; retired is terminal | revalidate an unchanged suppressed version after its origin becomes eligible to republish it; schema/content correction or failed generation creates a new linked draft version; retired never reopens | RecommendationArtifactGenerated, RecommendationPublished, RecommendationSuppressed, RecommendationRetired |
| AIResponse | requested, generated, validated, rejected, expired | requested from recommendation workflow | validated, rejected, expired | requested to generated; requested to rejected; generated to validated; generated to rejected; unpublished validated to expired | rejected to validated without a new attempt; expired to validated | AI Orchestration Context | generation is idempotent by request fingerprint; generation timeout moves requested to rejected with reason `generation_timeout`; validation timeout moves generated to rejected with reason `validation_timeout` | terminal states rejected and expired; validated is terminal after publication binding | provider or validation retry creates a new linked requested AIResponse and never reopens the terminal record | AIResponseRequested, AIResponseGenerated, AIResponseValidated, AIResponseRejected, AIResponseExpired |
| Citation | proposed, verified, invalid, superseded | proposed when AI output includes source references | verified, invalid, superseded | proposed to verified; proposed to invalid; verified to superseded | invalid to verified; superseded to verified | Evidence Context | verification is idempotent by the retained citation fingerprint; validation failure moves proposed to invalid with its exact reason | terminal states invalid and superseded | corrected linkage creates a new Citation; no terminal Citation is reopened | CitationProposed, CitationVerified, CitationInvalidated, CitationSuperseded |
| Export | pending, generating, available, failed, expired, revoked | pending when export requested | available, failed, expired, revoked | pending to generating; generating to available; generating to failed; available to expired; available to revoked | failed to available without regeneration | Delivery Context | generation retries MUST be idempotent per export request token; timeout to failed | failure: failed; terminal: expired, revoked | failed to pending via retry | ExportRequested, ExportGenerating, ExportAvailable, ExportFailed, ExportExpired, ExportRevoked |
| Notification | pending, uncertain, sent, partial, failed, suppressed | pending when one logical generation is created from a routed event | sent/partial/failed/suppressed when all required Delivery outcomes are known; uncertain while any required nonsuppressed Delivery is acceptance_unknown | pending to uncertain, sent, partial, failed, or suppressed; uncertain to sent, partial, or failed only after exact provider evidence resolves every unknown Delivery; sent to partial or failed and partial to failed only on a later authenticated permanent provider event | uncertain to a known aggregate state without exact Delivery evidence; treating uncertainty as success or failure; reopening a terminal known generation by replay | Delivery Context under WF-014 | event redelivery creates no second logical generation; aggregate recomputation is idempotent; uncertain takes precedence over every known aggregate state and never schedules an automatic resend; replay creates a new linked generation and never changes the old generation | failed and suppressed are terminal known outcomes; uncertain is nonterminal operational uncertainty, not success or terminal failure | consume exact authenticated provider evidence, or create an explicitly acknowledged administrative replay generation while leaving the uncertain generation immutable | NotificationCreated, NotificationUncertain, NotificationSent, NotificationPartial, NotificationFailed, NotificationSuppressed, NotificationReplayRequested |
| Delivery | pending, attempting, accepted, delivered, retry_scheduled, acceptance_unknown, terminal_failed, suppressed | pending when a Notification generation resolves an authorized recipient/channel | delivered or suppressed; terminal_failed on known permanent failure/exhausted provably nonaccepted attempts; acceptance_unknown when provider acceptance cannot be disproved | pending to attempting, terminal_failed, or suppressed; attempting to accepted, delivered, retry_scheduled, acceptance_unknown, terminal_failed, or suppressed; retry_scheduled to attempting, accepted, delivered, terminal_failed, or suppressed; acceptance_unknown to accepted, delivered, or terminal_failed only from exact authenticated provider evidence; accepted to delivered or terminal_failed; delivered to terminal_failed only on authenticated permanent failure | automatic resend or failure inference from acceptance_unknown; terminal_failed or suppressed to any state; accepted/delivered regression except authenticated permanent failure | Delivery Context and Mailgun adapter under WF-014; support authority may create only a linked replay generation | application processing is at least once, but a durable unique attempt claim occurs before Integration/Credential validation and suppresses duplicate application submission from event/job redelivery or concurrency; one serialized executor may resume a claimed attempt only while its dispatch checkpoint remains `prepared` and then perform exactly its one first submission; the adapter/client has no implicit transport retry and no executor may submit that attempt at or after `submission_started`; exhausted retryable initialization or provably no network submission uses bounded retry, while nonretryable Integration/Credential failure terminalizes the claimed attempt; any uncertain boundary result suppresses resend and uses read-only reconciliation | terminal_failed and suppressed are absorbing; acceptance_unknown persists until exact evidence and is neither terminal failure nor success | exact authenticated provider evidence may resolve uncertainty; administrative replay requires the old generation, reason, support authority, and explicit duplicate-delivery-risk acknowledgement and creates a new generation | NotificationDeliveryAttempted, NotificationDeliveryAccepted, NotificationDelivered, NotificationRetryScheduled, NotificationDeliveryAcceptanceUnknown, NotificationDeliveryReconciled, NotificationDeliveryFailed, NotificationDeliverySuppressed |
| BillingEntity | pending, active, past_due, suspended, closed; `past_due` and `suspended` are reserved and unreachable in the accepted baseline | pending only inside WF-001 self-service bootstrap after Organization creation and before same-Organization Plan Assignment linkage | active in that same atomic commit after Plan/Entitlement activation and before Organization activation; closed in the Organization closure transaction | accepted baseline: pending to active and active to closed; reserved future edges require controlled Volume I change before execution | separately committed/product-readable pending; pending to a failure state; any edge into or out of past_due/suspended without the approved successor contract; closed to any state | approved identity/bootstrap service for pending-to-active; tenant lifecycle service for active-to-closed; no baseline authority for reserved states | bootstrap exact replay returns the same BillingEntity and timeout rolls back the whole tenant transaction; no provider call or lazy/background creation is allowed; an unapproved provider event changes nothing | pending has no persisted failure state; past_due/suspended are recognized but unreachable in the accepted baseline; closed is terminal | bootstrap failure uses a new/replayed whole bootstrap command, never the pending record; reserved-state enablement requires controlled Volume I change rather than implementation choice | BillingStateChanged with exact from/to states and lifecycle reason |
| Integration | proposed, connected, degraded, disconnected, retired | proposed only when `integration-interim-v1` materializes an approved adapter-policy version | disconnected after explicit isolation or retired after policy withdrawal | proposed to connected; connected to degraded; degraded to connected; connected or degraded to disconnected; disconnected to connected after authorized recovery; disconnected to retired | proposed to disconnected or retired; retired to connected; degraded to retired | Integration Context under `integration-interim-v1` | materialization/initialization/recovery is idempotent by Integration and attempt generation; 10-second initialization and exact one-second bounded retry apply; failure leaves a new Integration proposed or moves an existing connected Integration to degraded with its exact reason | failure reasons remain record fields rather than states; retired is terminal | correct policy/Credential/dependency and submit the named recovery against current state; retire never reopens | IntegrationProposed, IntegrationConnected, IntegrationDegraded, IntegrationDisconnected, IntegrationRetired |
| Credential | pending, active, rotating, revoked, expired | pending only from approved Integration credential materialization | revoked or expired | pending to active; active to rotating; rotating to active; pending, active, or rotating to revoked; active or rotating to expired | revoked to active; expired to active; rotating to pending | Identity and Access Context under `integration-interim-v1` | materialization and rotation are idempotent by content/rotation token; rotation has a 10-second attempt deadline and exact 1/5-minute bounded retries; failure leaves rotating with `rotation_failed` while prior active material remains the only usable version until expiry/revocation | `rotation_failed` is a reason while rotating; revoked and expired are terminal and prohibit new provider checkpoints | authorized retry retains rotating and uses a fresh rotation token; success returns rotating to active; terminal states require a new Credential | CredentialProvisioned, CredentialActivated, CredentialRotationStarted, CredentialRotated, CredentialRevoked, CredentialExpired |

SM-REQ-007: Every invalid transition attempt MUST be rejected and logged.

SM-REQ-008: State machine definitions MUST be test-backed by deterministic transition tests.

SM-REQ-009: State machine diagrams MUST remain synchronized with canonical definitions.

SM-REQ-010: Transition authority changes MUST require ADR governance.

## Decisions

- DEC-016-01: State definitions are centralized to prevent lifecycle drift.
- DEC-016-02: Failure and recovery behavior is explicit for all critical lifecycles.

## Non-goals

- This document does not define queue implementation details.
- This document does not define UI labels for every state.

## Risks

- Risk: state explosion causing operational confusion.
  Mitigation: each state requires explicit authority and verification.
- Risk: undocumented recovery paths.
  Mitigation: release gate MUST fail for missing recovery definitions.

## Verification

| Requirement Scope | Verification Method | Owner | Stage |
| --- | --- | --- | --- |
| State transition validity | State transition test suite | Chief Rails | CI |
| Authorization for transitions | Security authorization tests | Chief Security | CI |
| Observability and audit events | Telemetry coverage checks | Chief AI and Chief Rails | CI and release |

## Volume I Interim Resolutions

- Project pause and resume are explicit authorized commands only; Volume I has no scheduled pause or resume behavior.
- Credential expiry has no grace period in Volume I. At the expiry instant the Credential becomes expired and MUST NOT authorize a new provider or integration operation; an operation that has not crossed its protected side-effect checkpoint stops, while a completed provider side effect is reconciled by its idempotent result contract.

## Related Documents

- [011 DOMAIN_MODEL.md](011%20DOMAIN_MODEL.md)
- [017 ERROR_MODEL.md](017%20ERROR_MODEL.md)
- [018 OBSERVABILITY.md](018%20OBSERVABILITY.md)
- [diagrams/COMPONENT_ARCHITECTURE.md](../diagrams/COMPONENT_ARCHITECTURE.md)

## Change Control

Any normative change MUST include:

1. Updated transition tests.
2. Updated observability and audit mappings.
3. Updated affected lifecycle documentation.
4. ADR reference.
