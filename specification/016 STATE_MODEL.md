# 016 STATE_MODEL

## Status

- Status: Accepted
- Foundation Version: 1.0
- Last Updated: 2026-07-15

## Authority

This document is the canonical state and transition model for lifecycle-bearing concepts in F1.

All workflow specifications and implementation plans MUST conform to these state rules.

## Purpose

Define canonical states, transitions, authorities, retry behavior, timeout behavior, failure handling, and audit event requirements.

## Scope

This document defines state models for:

- Accounts
- Organizations
- Projects
- Sources
- Documents
- Crawls
- Ingestion jobs
- Parsing jobs
- Indexing jobs
- Evaluations
- AI responses
- Citations
- Exports
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

SM-REQ-004: Every transition attempt MUST emit an audit event with actor_id, entity_id, from_state, to_state, outcome, and timestamp.

SM-REQ-005: Retryable transitions MUST be idempotent.

SM-REQ-006: Timeout behavior MUST map to deterministic failure or retry transition.

### Canonical State Machines

| Concept | States | Entry Conditions | Exit Conditions | Valid Transitions | Invalid Transitions | Transition Authority | Idempotency, Retry, Timeout | Failure and Terminal States | Recovery Paths | Audit Events |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Account | pending, active, suspended, revoked | pending on provisioning request | revoked when access permanently removed | pending to active; active to suspended; suspended to active; active to revoked; suspended to revoked | pending to revoked without review; revoked to active | Identity and Access Context plus OrganizationAdmin for suspend and reactivate | activation and suspension retries MUST be idempotent; timeout moves to suspended_review | failure: provisioning_failed; terminal: revoked | provisioning_failed to pending with approved retry | AccountProvisionRequested, AccountActivated, AccountSuspended, AccountRevoked |
| Organization | pending, active, suspended, closed | pending on organization creation | closed when contract and data lifecycle exit complete | pending to active; active to suspended; suspended to active; active to closed | pending to closed without validation; closed to active | Tenant Governance Context | activation retry MUST be idempotent; close timeout moves to close_failed | failure: close_failed; terminal: closed | close_failed to suspended for remediation | OrganizationCreated, OrganizationActivated, OrganizationSuspended, OrganizationClosed |
| Project | draft, active, paused, archived | draft on project creation | archived when no further monitoring allowed | draft to active; active to paused; paused to active; active to archived; paused to archived | draft to archived; archived to active | Project Context and OrganizationAdmin | activation MUST be idempotent; timeout on activation moves to activation_failed | failure: activation_failed; terminal: archived | activation_failed to draft after remediation | ProjectCreated, ProjectActivated, ProjectPaused, ProjectArchived |
| Source | proposed, verified, active, disabled, removed | proposed on source registration | removed after cleanup | proposed to verified; verified to active; active to disabled; disabled to active; disabled to removed | proposed to active without verification; removed to active | Intake Context | verification retry MUST be idempotent; timeout moves to verification_failed | failure: verification_failed; terminal: removed | verification_failed to proposed | SourceRegistered, SourceVerified, SourceActivated, SourceDisabled, SourceRemoved |
| Document | discovered, ingested, parsed, indexed, quarantined, retired | discovered after crawl or import | retired after retention or revocation | discovered to ingested; ingested to parsed; parsed to indexed; any to quarantined; indexed to retired | discovered to indexed directly; retired to indexed | Intake and Retrieval Contexts | ingestion and indexing retries MUST be idempotent; timeout moves to ingest_timeout or index_timeout | failure: ingest_failed, parse_failed, index_failed; terminal: retired | failure states to ingested or parsed with explicit retry token | DocumentDiscovered, DocumentIngested, DocumentParsed, DocumentIndexed, DocumentQuarantined, DocumentRetired |
| Crawl | queued, running, completed, failed, canceled | queued on schedule or manual request | completed, failed, canceled | queued to running; running to completed; running to failed; queued or running to canceled | completed to running | Intake Context | retries from failed MUST be new attempt with idempotency key; timeout from running to failed | failure: failed; terminal: completed, canceled | failed to queued through retry request | CrawlQueued, CrawlStarted, CrawlCompleted, CrawlFailed, CrawlCanceled |
| IngestionJob | queued, running, succeeded, failed, dead_letter | queued by crawl output | succeeded, failed, dead_letter | queued to running; running to succeeded; running to failed; failed to queued; failed to dead_letter | succeeded to running | Intake Context | failed retries MUST use same idempotency key; timeout from running to failed | failure: failed; terminal: succeeded, dead_letter | dead_letter to queued only by authorized operator replay | IngestionQueued, IngestionStarted, IngestionSucceeded, IngestionFailed, IngestionDeadLettered |
| ParsingJob | queued, running, succeeded, failed, dead_letter | queued after ingestion success | succeeded, failed, dead_letter | queued to running; running to succeeded; running to failed; failed to queued; failed to dead_letter | succeeded to queued | Intake Context | retries MUST be idempotent by document hash and parser version; timeout to failed | failure: failed; terminal: succeeded, dead_letter | dead_letter to queued with approved replay | ParsingQueued, ParsingStarted, ParsingSucceeded, ParsingFailed, ParsingDeadLettered |
| IndexingJob | queued, running, succeeded, failed, dead_letter | queued after parse success | succeeded, failed, dead_letter | queued to running; running to succeeded; running to failed; failed to queued; failed to dead_letter | succeeded to running | Retrieval Context | retries MUST be idempotent by index target and source snapshot | failure: failed; terminal: succeeded, dead_letter | dead_letter to queued with approved replay | IndexingQueued, IndexingStarted, IndexingSucceeded, IndexingFailed, IndexingDeadLettered |
| Evaluation | pending, running, completed, failed, superseded | pending on evaluation trigger | completed, failed, superseded | pending to running; running to completed; running to failed; completed to superseded | failed to completed without rerun | Evaluation Context | rerun MUST create new evaluation instance; timeout to failed | failure: failed; terminal: completed, superseded | failed to pending through rerun request | EvaluationPending, EvaluationStarted, EvaluationCompleted, EvaluationFailed, EvaluationSuperseded |
| AIResponse | requested, generated, validated, rejected, expired | requested from recommendation workflow | validated, rejected, expired | requested to generated; generated to validated; generated to rejected; validated to expired | rejected to validated without regeneration | AI Orchestration Context | generation retry MUST be idempotent by request fingerprint; timeout to generation_failed | failure: generation_failed; terminal: rejected, expired | generation_failed to requested with retry policy | AIResponseRequested, AIResponseGenerated, AIResponseValidated, AIResponseRejected, AIResponseExpired |
| Citation | proposed, verified, invalid, superseded | proposed when AI output includes source references | verified, invalid, superseded | proposed to verified; proposed to invalid; verified to superseded | invalid to verified without revalidation | Evidence Context | verification retries MUST be idempotent by citation fingerprint | failure: verification_failed; terminal: invalid, superseded | verification_failed to proposed after re-check | CitationProposed, CitationVerified, CitationInvalidated, CitationSuperseded |
| Export | pending, generating, available, failed, expired, revoked | pending when export requested | available, failed, expired, revoked | pending to generating; generating to available; generating to failed; available to expired; available to revoked | failed to available without regeneration | Delivery Context | generation retries MUST be idempotent per export request token; timeout to failed | failure: failed; terminal: expired, revoked | failed to pending via retry | ExportRequested, ExportGenerating, ExportAvailable, ExportFailed, ExportExpired, ExportRevoked |
| BillingEntity | pending, active, past_due, suspended, closed | pending at contract setup | closed at contract termination | pending to active; active to past_due; past_due to active; past_due to suspended; active to closed; suspended to closed | closed to active | Commercial Context | payment retries MUST be idempotent by billing event id; timeout to billing_failed | failure: billing_failed; terminal: closed | billing_failed to past_due with operator review | BillingPending, BillingActive, BillingPastDue, BillingSuspended, BillingClosed |
| Integration | proposed, connected, degraded, disconnected, retired | proposed at integration setup | disconnected, retired | proposed to connected; connected to degraded; degraded to connected; connected to disconnected; disconnected to retired | retired to connected | Integration Context | connect and reconnect retries MUST be idempotent per integration id | failure: connection_failed; terminal: retired | connection_failed to proposed or degraded to connected | IntegrationProposed, IntegrationConnected, IntegrationDegraded, IntegrationDisconnected, IntegrationRetired |
| Credential | pending, active, rotating, revoked, expired | pending on secret creation workflow | revoked, expired | pending to active; active to rotating; rotating to active; active to revoked; active to expired | revoked to active | Identity and Access Context | rotation retries MUST be idempotent by rotation token; timeout from rotating to rotation_failed | failure: rotation_failed; terminal: revoked, expired | rotation_failed to rotating with approved retry | CredentialProvisioned, CredentialActivated, CredentialRotating, CredentialRevoked, CredentialExpired |

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

## Open Questions

- Should Projects support scheduled pause and resume transitions?
- Should Credential states include grace period before expiry enforcement?

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
