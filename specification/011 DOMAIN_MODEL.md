# 011 DOMAIN_MODEL

## Status

- Status: Accepted
- Foundation Version: 1.0
- Last Updated: 2026-07-15

## Authority

This document is a constitutional foundation document for Project F1.

All downstream specifications MUST use this domain model as the canonical business and platform model unless an ADR explicitly supersedes a specific requirement.

## Purpose

Define the canonical business and platform domain model independently of persistence technology.

## Scope

This document defines:

- core domain entities
- entity responsibilities
- ownership boundaries
- relationships and cardinality
- aggregate boundaries
- identity and lifecycle rules
- invariants
- domain events
- explicit non-domain concepts

This document MUST NOT define database tables, migration strategies, or storage-engine-specific behavior.

## Dependencies

- [000 OVERVIEW.md](000%20OVERVIEW.md)
- [001 PRODUCT_ARCHITECTURE_MANUAL.md](001%20PRODUCT_ARCHITECTURE_MANUAL.md)
- [002 GLOSSARY.md](002%20GLOSSARY.md)
- [003 TERMINOLOGY.md](003%20TERMINOLOGY.md)
- [005 PRODUCT_PRINCIPLES.md](005%20PRODUCT_PRINCIPLES.md)
- [007 ARCHITECTURE_PRINCIPLES.md](007%20ARCHITECTURE_PRINCIPLES.md)
- [009 DECISION_FRAMEWORK.md](009%20DECISION_FRAMEWORK.md)
- [012 SYSTEM_BOUNDARIES.md](012%20SYSTEM_BOUNDARIES.md)
- [016 STATE_MODEL.md](016%20STATE_MODEL.md)
- [017 ERROR_MODEL.md](017%20ERROR_MODEL.md)

## Definitions

- Domain Entity: A business concept with identity and lifecycle.
- Aggregate: A consistency boundary with one aggregate root.
- Aggregate Root: The entity through which all writes to an aggregate MUST occur.
- Lifecycle Owner: The bounded context that controls state transitions for an entity.
- Canonical Identifier: The immutable identifier format used across contexts.

Canonical term meanings inherit from [002 GLOSSARY.md](002%20GLOSSARY.md).

## Assumptions

- Project F1 remains a Discoverability Intelligence Platform.
- The non-invasive remediation model remains in effect.
- Multi-tenant operation remains required.
- Domain model granularity MUST support traceability from recommendation to evidence.

## Constraints

- Domain definitions MUST remain independent from framework internals.
- Entity boundaries MUST align with ownership and state transitions.
- Entity identity MUST be immutable after creation.
- Cross-aggregate writes MUST occur through explicit orchestration.

## Normative Requirements

### Core Entities

DM-REQ-001: The canonical core entities MUST include Organization, Account, Project, Source, Document, Crawl, IngestionJob, ParsingJob, IndexingJob, Evaluation, Issue, RecommendationArtifact, AIResponse, Citation, Export, BillingEntity, Integration, and Credential.

DM-REQ-002: Every core entity MUST define a single lifecycle owner.

DM-REQ-003: Every core entity MUST define a canonical identifier namespace.

DM-REQ-004: Every entity MUST define at least one invariant that is test-validated.

### Entity Responsibilities And Ownership

| Entity | Responsibility | Lifecycle Owner | Canonical Identifier |
| --- | --- | --- | --- |
| Organization | Tenant boundary, policy boundary, ownership root | Tenant Governance Context | org_id |
| Account | User identity and account-level preferences | Identity and Access Context | acct_id |
| Project | Discoverability program boundary for a business initiative | Project Context | prj_id |
| Source | Input location for crawl or ingestion | Intake Context | src_id |
| Document | Parsed content unit and provenance unit | Intake Context | doc_id |
| Crawl | Scheduled or ad hoc crawl execution | Intake Context | crw_id |
| IngestionJob | Structured ingestion execution state | Intake Context | ing_id |
| ParsingJob | Parsing execution state and parse diagnostics | Intake Context | prs_id |
| IndexingJob | Index update execution state | Retrieval Context | idx_id |
| Evaluation | Scoring and issue evaluation run | Evaluation Context | eval_id |
| Issue | Prioritized discoverability deficiency | Evaluation Context | iss_id |
| RecommendationArtifact | Actionable output for remediation | Recommendation Context | rec_id |
| AIResponse | AI-generated explanation or guidance payload | AI Orchestration Context | air_id |
| Citation | Evidence pointer linked to recommendation or AI output | Evidence Context | cit_id |
| Export | Outbound report or data package | Delivery Context | exp_id |
| BillingEntity | Commercial contract and billing linkage | Commercial Context | bill_id |
| Integration | External system connection contract | Integration Context | int_id |
| Credential | Secret reference or delegated token handle | Identity and Access Context | cred_id |

DM-REQ-005: Identifier values MUST be opaque, immutable, and globally unique within their namespace.

DM-REQ-006: Identifier namespaces MUST appear in logs, audit events, and telemetry labels.

### Relationships And Cardinality

| Relationship | Cardinality | Constraint |
| --- | --- | --- |
| Organization to Account | 1 to many | Account MUST belong to exactly one Organization. |
| Organization to Project | 1 to many | Project MUST belong to exactly one Organization. |
| Project to Source | 1 to many | Source MUST belong to exactly one Project. |
| Source to Document | 1 to many | Document MUST belong to exactly one Source. |
| Project to Crawl | 1 to many | Crawl MUST belong to exactly one Project. |
| Crawl to IngestionJob | 1 to many | IngestionJob MUST reference one Crawl attempt. |
| IngestionJob to ParsingJob | 1 to many | ParsingJob MUST reference one IngestionJob. |
| ParsingJob to IndexingJob | 1 to many | IndexingJob MUST reference one ParsingJob outcome batch. |
| Project to Evaluation | 1 to many | Evaluation MUST reference one Project snapshot scope. |
| Evaluation to Issue | 1 to many | Issue MUST reference one Evaluation origin. |
| Issue to RecommendationArtifact | 1 to many | RecommendationArtifact MUST reference one Issue origin. |
| RecommendationArtifact to AIResponse | 0 to many | AIResponse MUST reference one RecommendationArtifact context when generated for remediation. |
| AIResponse to Citation | 0 to many | Citation MUST reference one evidence object. |
| Organization to BillingEntity | 1 to many | BillingEntity MUST reference one Organization. |
| Organization to Integration | 1 to many | Integration MUST reference one Organization. |
| Integration to Credential | 1 to many | Credential MUST reference one Integration owner. |

DM-REQ-007: Cardinality exceptions MUST be documented with ADR traceability.

### Aggregate Boundaries

The canonical aggregates are:

- Tenant Aggregate: Organization root with Account membership policy.
- Project Aggregate: Project root with Source membership policy.
- Intake Aggregate: Crawl root with ingestion, parsing, and indexing execution lineage.
- Evaluation Aggregate: Evaluation root with Issue lineage.
- Recommendation Aggregate: RecommendationArtifact root with AIResponse and Citation lineage.
- Commercial Aggregate: BillingEntity root with contract and billing state.
- Integration Aggregate: Integration root with Credential lifecycle.

DM-REQ-008: Writes that affect an aggregate MUST enter through the aggregate root.

DM-REQ-009: Cross-aggregate coordination MUST use explicit orchestration with audit events.

### Lifecycle Ownership And Invariants

DM-REQ-010: Lifecycle state transitions MUST be authorized by the lifecycle owner defined in this document.

DM-REQ-011: The following invariants MUST hold:

- An Issue MUST reference a valid Evaluation.
- A RecommendationArtifact MUST reference a valid Issue.
- An AIResponse used in customer output MUST include citation coverage.
- A Credential MUST NOT exist without an owning Integration.
- A Project MUST NOT transition to active without one active Source.

DM-REQ-012: Invariant checks MUST be represented in automated tests before implementation changes merge.

### Domain Events

The canonical domain event set includes:

- OrganizationCreated
- OrganizationPolicyUpdated
- AccountProvisioned
- ProjectCreated
- SourceRegistered
- CrawlStarted
- CrawlCompleted
- IngestionJobFailed
- ParsingJobFailed
- IndexingJobCompleted
- EvaluationCompleted
- IssueCreated
- RecommendationArtifactGenerated
- AIResponseGenerated
- CitationValidated
- ExportGenerated
- IntegrationConnected
- CredentialRotated
- BillingStateChanged

DM-REQ-013: Each domain event MUST include event_id, event_type, occurred_at_utc, actor_id, organization_id, and affected_entity_id.

DM-REQ-014: Event payload schemas MUST be versioned under [019 VERSIONING.md](019%20VERSIONING.md).

### Cross-Domain References

DM-REQ-015: State transition rules MUST be defined in [016 STATE_MODEL.md](016%20STATE_MODEL.md).

DM-REQ-016: Error behavior for each domain event pathway MUST be defined in [017 ERROR_MODEL.md](017%20ERROR_MODEL.md).

DM-REQ-017: Observability coverage for each domain event pathway MUST be defined in [018 OBSERVABILITY.md](018%20OBSERVABILITY.md).

### Explicit Non-Domain Concepts

DM-REQ-018: The following concepts MUST NOT be treated as domain entities:

- database table names
- queue names
- framework classes
- deployment units
- vendor product names
- dashboard widget names

### Known Unresolved Modeling Questions

DM-REQ-019: Unresolved modeling questions MUST include owner, decision deadline, and ADR trigger.

Current unresolved questions:

- Should Citation support many-to-many linkage to Evaluation and AIResponse simultaneously?
  Owner: Chief Architect. Deadline: 2026-08-01. ADR Trigger: before Volume IV acceptance.
- Should BillingEntity include invoice and payment sub-entities in core domain or remain adapter-level?
  Owner: Chief Product. Deadline: 2026-08-15. ADR Trigger: before Volume V commercial architecture acceptance.

## Decisions

- DEC-011-01: Domain model remains persistence-agnostic.
- DEC-011-02: Aggregate boundaries are defined by consistency and lifecycle ownership, not by storage convenience.
- DEC-011-03: Domain events are canonical integration touchpoints.

## Non-goals

- This document does not define physical schemas.
- This document does not define API endpoint shapes.
- This document does not define vendor-specific integration payloads.

## Risks

- Risk: Aggregate boundaries may drift during implementation planning.
  Mitigation: Architecture tests MUST enforce boundary rules.
- Risk: Identifier namespace collisions.
  Mitigation: Namespace validation MUST run in CI gate checks.

## Verification

| Requirement Scope | Verification Method | Owner | Stage |
| --- | --- | --- | --- |
| Entity set and ownership | Architecture review checklist | Chief Architect | Spec review |
| Cardinality and invariants | Architecture tests and contract tests | Chief Rails | CI |
| Event schema completeness | Schema lint and event contract tests | Chief AI and Chief Rails | CI |
| Non-domain concept exclusion | Documentation review gate | Chief Architect | PR review |

## Open Questions

- Should Account and Organization support delegated administration scopes beyond role-based access?
- Should RecommendationArtifact lifecycle include approval states in baseline scope?

## Related Documents

- [012 SYSTEM_BOUNDARIES.md](012%20SYSTEM_BOUNDARIES.md)
- [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md)
- [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md)
- [015 DATA_LIFECYCLE.md](015%20DATA_LIFECYCLE.md)
- [016 STATE_MODEL.md](016%20STATE_MODEL.md)
- [018 OBSERVABILITY.md](018%20OBSERVABILITY.md)
- [019 VERSIONING.md](019%20VERSIONING.md)
- [diagrams/DOMAIN_MODEL.md](../diagrams/DOMAIN_MODEL.md)

## Change Control

Any normative change to this document MUST:

1. Include an ADR update.
2. Identify downstream affected specifications.
3. Identify affected tests, contracts, and diagrams.
4. Include compatibility and migration impact assessment.
5. Update the traceability matrix in [FOUNDATION_TRACEABILITY_MATRIX.md](FOUNDATION_TRACEABILITY_MATRIX.md).
