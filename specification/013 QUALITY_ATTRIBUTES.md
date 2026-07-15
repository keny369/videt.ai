# 013 QUALITY_ATTRIBUTES

## Status

- Status: Accepted
- Foundation Version: 1.0
- Last Updated: 2026-07-15

## Authority

This document defines constitutional non-functional requirements for F1.

All architecture and implementation specifications MUST satisfy these quality attributes or document approved exceptions.

## Purpose

Define measurable quality attributes, provisional ranges, and release gates for unresolved thresholds.

## Scope

This document covers:

- availability and reliability
- recovery objectives
- performance and latency budgets
- throughput and scalability assumptions
- cost and capacity constraints
- durability and consistency expectations
- accessibility, maintainability, portability, testability, operability
- security, privacy, and AI quality attributes

## Dependencies

- [001 PRODUCT_ARCHITECTURE_MANUAL.md](001%20PRODUCT_ARCHITECTURE_MANUAL.md)
- [006 ENGINEERING_PRINCIPLES.md](006%20ENGINEERING_PRINCIPLES.md)
- [007 ARCHITECTURE_PRINCIPLES.md](007%20ARCHITECTURE_PRINCIPLES.md)
- [008 AI_PRINCIPLES.md](008%20AI_PRINCIPLES.md)
- [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md)
- [018 OBSERVABILITY.md](018%20OBSERVABILITY.md)
- [019 VERSIONING.md](019%20VERSIONING.md)

## Definitions

- SLO: Service-level objective measured over a defined time window.
- Error Budget: Allowed failure amount relative to the SLO target.
- RTO: Recovery time objective.
- RPO: Recovery point objective.

## Assumptions

- Baseline architecture is modular monolith with asynchronous job execution.
- Critical workflows include crawl, evaluation, recommendation generation, and reporting.
- Initial release phases need provisional ranges for selected attributes.

## Constraints

- Quality targets MUST remain consistent with cost constraints and stack choices.
- Any quality target change MUST include impact analysis and ADR reference.
- Unresolved thresholds MUST include owner, deadline, and release gate.

## Normative Requirements

### Quality Attribute Catalog

| ID | Attribute | Target Or Provisional Range | Measurement Method | Owner | Decision Deadline | Release Gate |
| --- | --- | --- | --- | --- | --- | --- |
| QA-REQ-001 | Availability | Provisional: 99.5% to 99.9% monthly for customer-facing services | Uptime SLI from synthetic and request telemetry | Chief Rails | 2026-08-15 | Volume III acceptance |
| QA-REQ-002 | Reliability | Provisional: failed critical workflow rate under 1.0% per 7-day window | Workflow success/failure counters | Chief Rails | 2026-08-15 | Volume III acceptance |
| QA-REQ-003 | RTO | Provisional: 4h for critical service restoration | Incident timeline audit | Chief Security | 2026-08-20 | Operations architecture sign-off |
| QA-REQ-004 | RPO | Provisional: 1h for critical data classes | Backup and restore verification logs | Chief Rails | 2026-08-20 | Data lifecycle sign-off |
| QA-REQ-005 | API Latency Budget | Provisional: p95 under 500ms for synchronous user-facing requests | Distributed tracing and route histograms | Chief Rails | 2026-08-20 | Volume IV API acceptance |
| QA-REQ-006 | Background Latency Budget | Provisional: p95 under 5m for standard evaluation jobs | Job telemetry and queue duration metrics | Chief Rails | 2026-08-25 | Volume IV acceptance |
| QA-REQ-007 | Throughput | Provisional: sustain target onboarding and monitoring load defined in capacity model | Load test and production telemetry | Chief Architect | 2026-08-25 | Volume III acceptance |
| QA-REQ-008 | Scalability | Horizontal scaling plan MUST support 10x baseline load without architecture rewrite | Capacity rehearsal and architecture review | Chief Architect | 2026-09-01 | Volume III acceptance |
| QA-REQ-009 | Cost Constraint | Provisional: unit economics MUST remain within approved budget envelope | Cost telemetry per workflow and account | Chief Product | 2026-08-30 | Volume V finance gate |
| QA-REQ-010 | Capacity Limits | Hard and soft limits MUST be documented per workflow | Capacity policy and quota tests | Chief Rails | 2026-08-30 | Volume III acceptance |
| QA-REQ-011 | Durability | Critical records MUST have verified backup and restore coverage | Restore drill and checksum validation | Chief Rails | 2026-08-25 | Data lifecycle acceptance |
| QA-REQ-012 | Consistency | Domain invariants MUST be preserved under retries and partial failure | Invariant tests and reconciliation audits | Chief Architect | 2026-08-25 | State model acceptance |
| QA-REQ-013 | Accessibility | Product surfaces MUST satisfy documented accessibility checks from design principles | Accessibility test suite and manual audit | Chief UX | 2026-08-20 | Volume II gate |
| QA-REQ-014 | Maintainability | Architecture rules MUST enforce bounded module dependencies | Architecture fitness functions | Chief Architect | 2026-08-20 | Volume III gate |
| QA-REQ-015 | Portability | Critical adapters MUST support provider substitution path | Adapter contract tests and migration drills | Chief AI | 2026-09-01 | Volume IV gate |
| QA-REQ-016 | Testability | Critical workflows MUST have deterministic test harnesses | CI test coverage reports and flake-rate reports | Chief Rails | 2026-08-15 | Engineering gate |
| QA-REQ-017 | Operability | Every critical workflow MUST expose success and failure signals | Observability coverage review | Chief Security | 2026-08-20 | Operations gate |
| QA-REQ-018 | Security Quality | Security controls MUST meet threat-model verification coverage | Security tests and review evidence | Chief Security | 2026-08-20 | Security gate |
| QA-REQ-019 | Privacy Quality | Data minimization and retention controls MUST be enforceable and auditable | Privacy review and retention verification | Chief Security | 2026-08-25 | Privacy gate |
| QA-REQ-020 | AI Quality | AI outputs MUST satisfy grounding, citation, safety, latency, and cost checks | AI evaluation suite and citation validation | Chief AI | 2026-08-30 | Volume IV AI gate |

QA-REQ-021: Every provisional range MUST resolve to an accepted threshold before its release gate closes.

QA-REQ-022: Quality attribute telemetry MUST be retained and auditable according to [018 OBSERVABILITY.md](018%20OBSERVABILITY.md).

## Decisions

- DEC-013-01: Provisional ranges are accepted only with explicit deadlines and release gates.
- DEC-013-02: Quality targets are constitutional requirements, not optional implementation goals.

## Non-goals

- This document does not define user-facing feature details.
- This document does not define vendor-specific performance tuning.

## Risks

- Risk: unresolved thresholds may block downstream volume acceptance.
  Mitigation: owners MUST resolve targets by deadlines listed in QA-REQ table.
- Risk: telemetry gaps may hide quality regressions.
  Mitigation: observability coverage checks MUST run in release gates.

## Verification

QA-REQ-023: Every quality attribute MUST have at least one automated or manual verification method with recorded evidence.

QA-REQ-024: Release reviews MUST fail when required quality evidence is missing.

QA-REQ-025: Quality trend reports MUST be reviewed at least once per planning cycle.

## Open Questions

- Which customer segments require stricter availability targets before enterprise expansion?
- Which AI workloads require separate latency SLOs by model class?

## Related Documents

- [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md)
- [015 DATA_LIFECYCLE.md](015%20DATA_LIFECYCLE.md)
- [018 OBSERVABILITY.md](018%20OBSERVABILITY.md)
- [FOUNDATION_TRACEABILITY_MATRIX.md](FOUNDATION_TRACEABILITY_MATRIX.md)

## Change Control

Changes to quality targets MUST:

1. Include a compatibility and cost impact analysis.
2. Update related fitness functions and verification gates.
3. Include ADR references and updated owner accountability.
