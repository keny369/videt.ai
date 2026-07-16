# 011 DOMAIN_MODEL

## Status

- Status: Accepted
- Foundation Version: 1.0
- Last Updated: 2026-07-16

## Authority

This document is a constitutional foundation document for Project F1.

All downstream specifications MUST use this domain model as the canonical business and platform model. Under PM-REQ-003, an Architecture Decision Record (ADR) is subordinate to the unchanged foundation layer: an accepted ADR authorizes the controlled-change process in PM-REQ-009 but does not by itself supersede a requirement in this document. A changed requirement becomes authoritative only when this document and every required affected artifact are updated and accepted through that process.

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

Evidence is the immutable governed record defined by the glossary and the Volume I Evidence contract. Evidence Type, Evidence Payload, Evidence Provenance, and Evidence Classification are attributes or referenced content of that record, not separate entities. Evidence Source is the conceptual origin view over `source_system` and applicable `source_id` within Evidence Provenance, not another field or entity. Measurement Evidence means Evidence with `evidence_type=external_measurement`; Verification Evidence means Evidence with `evidence_type=verification_observation`. Audit Evidence is a separate audit/security record and MUST NOT be modeled as Evidence or used as score input solely because it proves an action.

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
| Organization to Account | 1 to many | Account MUST belong to exactly one Organization. One external identity principal MAY bind to a separate Account in each Organization, but an Account and its Session never span Organizations. |
| Organization to Project | 1 to many | Project MUST belong to exactly one Organization. |
| Project to Source | 1 to many | Source MUST belong to exactly one Project. |
| Source to Document | 1 to many | Document MUST belong to exactly one Source. |
| Project to Crawl | 1 to many | Crawl MUST belong to exactly one Project. |
| Crawl to IngestionJob | 1 to many | IngestionJob MUST reference one Crawl attempt. |
| IngestionJob to ParsingJob | 1 to many | ParsingJob MUST reference one IngestionJob. |
| ParsingJob to IndexingJob | 1 to many | IndexingJob MUST reference one ParsingJob outcome batch. |
| Project to Evaluation | 1 to many | Evaluation MUST reference one Project snapshot scope. |
| Evaluation to Issue | 1 to many | Issue MUST reference one Evaluation origin. |
| Issue to RecommendationArtifact | 1 to many | RecommendationArtifact MUST reference exactly one origin Issue; optional related-Issue references are informational and never govern eligibility, priority, or lifecycle. |
| RecommendationArtifact to AIResponse | 0 to many | AIResponse MUST reference one RecommendationArtifact context when generated for remediation. |
| AIResponse to Citation | 0 to many | Citation MUST reference exactly one AIResponse and exactly one Evidence record; baseline writes contain no direct Evaluation link. |
| Project to Evidence | 1 to many | Every Evidence record belongs to exactly one Project; `source_id` and `evaluation_id` follow the exact nullable cases in the Volume I Evidence contract. |
| Evidence to Citation | 1 to many | Every Citation references exactly one Evidence record; an Evidence record may support zero or more Citations. |
| Organization to BillingEntity | 1 to many over retained history | BillingEntity MUST reference one Organization. WF-001 creates exactly one active baseline BillingEntity; at most one BillingEntity for that Organization may be nonclosed, and every Plan Assignment MUST reference a BillingEntity in the same Organization. |
| Organization to Integration | 1 to many | Integration MUST reference one Organization. |
| Integration to Credential | 1 to many | Credential MUST reference one Integration owner. |

DM-REQ-007: Cardinality exceptions MUST be documented with ADR traceability.

Evidence is a lifecycle-bearing auxiliary domain record rather than an additional DM-REQ-001 core entity. Its responsibility is immutable observation identity, payload digest/reference, provenance, classification, validation, and lineage; its lifecycle owner is Evidence Context and its canonical identifier namespace is `evd_id` exposed through the logical field `evidence_id`. Evidence Validation Decisions append to that record's effective validation lifecycle under the Volume I contract. This classification preserves the accepted core-entity catalogue while preventing Evidence from being mistaken for a payload, provenance field, Audit Evidence, or unnamed implementation object.

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
- A RecommendationArtifact MUST reference exactly one valid origin Issue; optional related Issue references are non-governing.
- An AIResponse used in customer output MUST include complete verified Citation coverage, with each Citation linked to exactly one AIResponse and one Evidence record and no direct Evaluation write link under the Volume I interim contract.
- A Credential MUST NOT exist without an owning Integration.
- An Account MUST reference exactly one Organization; pre-Organization identity receipts and Bootstrap Grants are authorization artifacts, not Accounts.
- Under the accepted baseline, an active Organization MUST have exactly one active BillingEntity linked to its active Plan Assignment; reserved `past_due`/`suspended` states have no executable transition until a controlled Volume I adapter change defines their consequences. No provider callback, first use, background action, or lazy read may create a BillingEntity.
- A Project MUST NOT transition to active without one active Source.

DM-REQ-012: Invariant checks MUST be represented in automated tests before implementation changes merge.

### Domain Events

The minimum canonical cross-context domain event set includes:

- OrganizationCreated
- OrganizationActivated
- AccessPolicyActivated
- AccountProvisionRequested
- AccountActivated
- ProjectCreated
- SourceRegistered
- CrawlStarted
- CrawlCompleted
- EvaluationCompleted
- IssueCreated
- RecommendationArtifactGenerated
- AIResponseGenerated
- AIResponseValidated
- CitationVerified
- ExportAvailable
- IntegrationConnected
- CredentialRotated
- BillingStateChanged

DM-REQ-013: Each domain event MUST include event_id, event_type, schema_version, workflow_id, event_profile, occurred_at_utc, organization_id, affected_entity_type, affected_entity_id, aggregate_version, correlation_id, causation_id, and exactly one of actor_id or service_identity_id, plus the profile-specific fields in the Volume I Logical Event Envelope. A pre-Organization bootstrap event substitutes the immutable bootstrap principal for organization_id only where the named onboarding contract expressly permits it.

DM-REQ-014: Event payload schemas MUST be versioned under [019 VERSIONING.md](019%20VERSIONING.md). Additional workflow-specific lifecycle and failure events MAY be defined in [016 STATE_MODEL.md](016%20STATE_MODEL.md) and [017 ERROR_MODEL.md](017%20ERROR_MODEL.md), and MUST follow event naming rules in [003 TERMINOLOGY.md](003%20TERMINOLOGY.md).

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

### Known Owner-Controlled Modeling Decisions

DM-REQ-019: Unresolved modeling questions MUST include owner, decision deadline, and ADR trigger.

Current pending decisions and deterministic interim behavior:

- OD-007 Citation linkage is pending Chief Architect approval by 2026-08-01; until approval, each Citation references exactly one AIResponse and one Evidence record, and no Citation writes a direct Evaluation link. ADR trigger: before Volume IV acceptance or before approving a many-to-many model.
- OD-008 BillingEntity decomposition is pending Chief Product approval by 2026-08-15; until approval, BillingEntity remains the core commercial aggregate and invoice/payment detail remains adapter-level with no inferred F1 sub-entity. ADR trigger: before Volume V commercial architecture acceptance or before approving core invoice/payment entities.

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

## Volume I Interim Resolutions

- Account and Organization administration uses only the Organization, Project, and exact resource scopes carried by the Volume I Role Assignment and Access Policy contracts. Volume I provides no delegated-administration scope outside that model.
- RecommendationArtifact has only `draft`, `published`, `suppressed`, and `retired` states. Volume I adds no approval state; publication is an authorized transition whose complete validation and authority rules are defined by WF-009 and the score/evidence model.

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
