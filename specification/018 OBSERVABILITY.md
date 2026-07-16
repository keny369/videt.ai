# 018 OBSERVABILITY

## Status

- Status: Accepted
- Foundation Version: 1.0
- Last Updated: 2026-07-16

## Authority

This document defines the canonical observability architecture for F1.

All critical workflows MUST satisfy observability requirements defined here.

## Purpose

Define logging, metrics, tracing, audit, telemetry, alerting, and investigation requirements.

## Scope

This document covers:

- logging, metrics, distributed tracing
- audit events and health signals
- readiness and liveness checks
- synthetic monitoring
- business, product, security, AI, cost, usage, and data-quality telemetry
- correlation and sampling rules
- retention and redaction
- dashboards, ownership, and incident investigation

## Dependencies

- [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md)
- [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md)
- [016 STATE_MODEL.md](016%20STATE_MODEL.md)
- [017 ERROR_MODEL.md](017%20ERROR_MODEL.md)

## Definitions

- Observable Success Condition: A measurable signal proving workflow completion.
- Observable Failure Condition: A measurable signal proving workflow failure.
- Telemetry Contract: Required event and metric fields for a workflow.

## Assumptions

- Critical workflows include onboarding, crawl, ingestion, evaluation, recommendation generation, AI response generation, citation validation, and export.
- Observability data is itself subject to security and privacy controls.

## Constraints

- Every critical workflow MUST have observable success and failure conditions.
- Telemetry MUST remain consistent with canonical identifiers.
- Sensitive data MUST be redacted from telemetry payloads.

## Normative Requirements

### Logging, Metrics, Tracing, Audit

OBS-REQ-001: Structured logs MUST include correlation_id, organization_id, workflow_id, severity, and timestamp_utc.

OBS-REQ-002: Metrics MUST include workflow throughput, latency, error rate, and retry counts for critical paths.

OBS-REQ-003: Distributed tracing MUST cover cross-boundary requests and async workflow hops.

OBS-REQ-004: Audit events MUST capture authorization decisions, state transitions, data export actions, and security-sensitive operations.

### Health, Readiness, Liveness, Synthetic Monitoring

OBS-REQ-005: Services MUST expose liveness and readiness checks.

OBS-REQ-006: Synthetic monitoring MUST validate user-critical availability paths.

OBS-REQ-007: Health checks MUST be mapped to alert policies with ownership.

### Telemetry Domains

OBS-REQ-008: Business telemetry MUST include score movement and issue closure progression.

OBS-REQ-009: Product telemetry MUST include feature adoption and workflow completion rates.

OBS-REQ-010: Security telemetry MUST include authorization failures, privilege changes, and suspicious access patterns.

OBS-REQ-011: AI telemetry MUST include model version, prompt version, citation coverage, safety outcomes, latency, and cost.

OBS-REQ-012: Cost telemetry MUST include per-workflow and per-organization cost dimensions.

OBS-REQ-013: Usage telemetry MUST include active users, active projects, and monitoring run cadence.

OBS-REQ-014: Data-quality telemetry MUST include parse success rates, indexing freshness, and citation validity rates.

### Correlation, Sampling, Retention, Redaction

OBS-REQ-015: Correlation identifiers MUST propagate across logs, traces, metrics, and audit records.

OBS-REQ-016: Sampling policies MUST preserve error and security events at full fidelity.

OBS-REQ-017: Retention windows MUST align with data lifecycle and security policy.

OBS-REQ-018: Redaction rules MUST remove secrets and sensitive personal data from telemetry.

### Alerting, Dashboards, Ownership

OBS-REQ-019: Alert definitions MUST include severity, owner, response target, and escalation path.

OBS-REQ-020: Dashboards MUST include quality, reliability, security, and AI evaluation views.

OBS-REQ-021: Dashboard ownership MUST be explicit per domain.

### Critical Workflow Observability Coverage

| Workflow | Success Condition | Failure Condition | Owner |
| --- | --- | --- | --- |
| WF-001 Domain Onboarding | Self-service emits `OrganizationActivated` and `ProjectCreated` with `project_state=draft`; invitation acceptance emits `InvitationAccepted`. `SourceActivated` and `ProjectActivated` are separate later WF-003 and WF-002 outcomes, not WF-001 success signals. | Audited rejected command outcome with the exact reason and no partial branch writes; transaction timeout/exhaustion reports `onboarding_transaction_unavailable`. No failure-only Organization, Account, or Project state is created. | Chief Product |
| Crawl Execution | CrawlCompleted event and successful URL coverage metrics | CrawlFailed event or timeout | Chief Rails |
| Ingestion and Parsing | ParsingSucceeded event and parse_success_rate above release threshold | ParsingDeadLettered event or repeated ParsingFailed events | Chief Rails |
| Evaluation | EvaluationCompleted with score snapshot persisted | EvaluationFailed event | Chief Architect |
| Recommendation Generation | RecommendationArtifactGenerated event with origin Issue linkage and Artifact version | Audited generation or publication-validation rejection with exact reason and correlation_id, with no `RecommendationPublished` event | Chief Product |
| AI Response Generation | AIResponseValidated event with citation coverage metric | AIResponseRejected event with exact generation or validation reason | Chief AI |
| Citation Validation | CitationVerified event and validity metric | CitationInvalidated event | Chief AI |
| Export Delivery | ExportAvailable event | ExportFailed or ExportRevoked event | Chief Rails |

OBS-REQ-022: Coverage table workflows MUST remain synchronized with state and error models.

### Incident Investigation Requirements

OBS-REQ-023: Incident investigations MUST reconstruct event sequence from correlation identifiers.

OBS-REQ-024: Incident investigations MUST produce a telemetry-gap assessment.

## Decisions

- DEC-018-01: Observability is a release gate requirement for critical workflows.
- DEC-018-02: Security and AI telemetry are first-class telemetry domains.

## Non-goals

- This document does not prescribe dashboard visualization style.
- This document does not define vendor product configuration syntax.

## Risks

- Risk: blind spots in critical workflow telemetry.
  Mitigation: coverage checks MUST block releases.
- Risk: sensitive data leakage through telemetry payloads.
  Mitigation: redaction controls and security review MUST be enforced.

## Verification

| Requirement Scope | Verification Method | Owner | Stage |
| --- | --- | --- | --- |
| Telemetry contracts | Automated schema and field presence checks | Chief Rails | CI |
| Workflow coverage | Observability fitness function checks | Chief Architect | CI and release |
| Security redaction | Security telemetry tests | Chief Security | CI |

## Volume I Interim Resolutions

- Customer-facing transparency is limited to the authorized product projections, Evidence lineage, coverage, reason codes, and operational statuses explicitly named by Volume I. Internal metrics, traces, alerts, and provider diagnostics are not customer-facing.
- Volume I synthetic checks have no customer-visible regional differentiation. An implementation may run private regional probes for operations, but those probes MUST NOT change a Check Result, score, entitlement, or customer-visible status unless a later versioned product contract defines the region dimension.

## Related Documents

- [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md)
- [017 ERROR_MODEL.md](017%20ERROR_MODEL.md)
- [019 VERSIONING.md](019%20VERSIONING.md)
- [diagrams/CONTAINER_ARCHITECTURE.md](../diagrams/CONTAINER_ARCHITECTURE.md)

## Change Control

Any normative change MUST:

1. Update telemetry contracts and dashboard ownership mappings.
2. Update alert policies and escalation owners.
3. Update traceability matrix entries.
4. Include ADR reference.
