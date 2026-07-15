# 015 DATA_LIFECYCLE

## Status

- Status: Accepted
- Foundation Version: 1.0
- Last Updated: 2026-07-15

## Authority

This document defines the canonical lifecycle policy for all major F1 data classes.

All downstream data and storage specifications MUST conform to these lifecycle requirements.

## Purpose

Define creation through destruction behavior for each major data class with ownership, control, and audit expectations.

## Scope

This document covers:

- creation, ingestion, validation, and classification
- storage, transformation, indexing, and retrieval
- export, archival, retention, and deletion
- legal hold and audit behavior
- provenance, lineage, and versioning
- derived, temporary, cached, and AI-generated data
- backup and restore behavior

## Dependencies

- [011 DOMAIN_MODEL.md](011%20DOMAIN_MODEL.md)
- [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md)
- [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md)
- [016 STATE_MODEL.md](016%20STATE_MODEL.md)
- [018 OBSERVABILITY.md](018%20OBSERVABILITY.md)
- [019 VERSIONING.md](019%20VERSIONING.md)

## Definitions

- Logical Deletion: Record is hidden from active use but still recoverable.
- Physical Deletion: Record bytes are removed from primary stores.
- Archival: Data moved to long-term storage class with controlled retrieval.
- Revocation: Access rights are removed while data may still exist.
- Irreversible Destruction: Data is removed and rendered non-recoverable from operational and backup paths after retention obligations end.

## Assumptions

- F1 stores discoverability evidence, evaluations, recommendations, and telemetry.
- Some data classes contain sensitive or regulated information.
- Restore capability is required for critical data classes.

## Constraints

- Data handling MUST follow classification and access policy.
- Retention and deletion rules MUST be auditable.
- Lifecycle controls MUST apply uniformly across primary and derived stores.

## Normative Requirements

### Data Class Ownership

DLC-REQ-001: Every major data class MUST have an owning team and lifecycle owner.

DLC-REQ-002: Data class ownership MUST be documented in canonical specifications.

### Creation, Ingestion, Validation, Classification

DLC-REQ-003: Data creation and ingestion events MUST include provenance metadata.

DLC-REQ-004: Ingested data MUST pass schema and policy validation before use.

DLC-REQ-005: Data classification MUST occur at or before first persistence write.

### Storage, Transformation, Indexing, Retrieval

DLC-REQ-006: Storage location and class MUST align with data classification.

DLC-REQ-007: Transformations MUST preserve lineage links to source records.

DLC-REQ-008: Indexing operations MUST record index version and source snapshot.

DLC-REQ-009: Retrieval operations MUST enforce access policy checks.

### Export, Archival, Retention, Deletion

DLC-REQ-010: Exports MUST include export scope, actor, and timestamp metadata.

DLC-REQ-011: Archival policy MUST define retention window and retrieval controls.

DLC-REQ-012: Retention policy MUST define minimum and maximum retention per class.

DLC-REQ-013: Deletion requests MUST specify logical deletion, physical deletion, archival, revocation, or irreversible destruction mode.

DLC-REQ-014: Irreversible destruction MUST include completion evidence and audit log record.

### Legal Hold

DLC-REQ-015: Legal hold MUST suspend irreversible destruction for affected data.

DLC-REQ-016: Legal hold release MUST be auditable and owner-approved.

### Provenance, Lineage, Versioning

DLC-REQ-017: Provenance metadata MUST include source system, ingest channel, and processing timestamp.

DLC-REQ-018: Lineage metadata MUST link derived outputs to source inputs and transformation steps.

DLC-REQ-019: Data version markers MUST follow [019 VERSIONING.md](019%20VERSIONING.md).

### Access Control And Audit

DLC-REQ-020: Access to Confidential and Restricted data MUST be role-limited and audited.

DLC-REQ-021: Lifecycle events MUST emit audit events with actor, reason, and outcome.

### Derived Data, AI-Generated Data, Temporary Data, Cached Data

DLC-REQ-022: Derived data MUST inherit or strengthen source data classification.

DLC-REQ-023: AI-generated data MUST carry model and prompt version metadata.

DLC-REQ-024: Temporary and cached data MUST define explicit expiration windows.

DLC-REQ-025: Expired temporary or cached data MUST be purged on policy schedule.

### Deleted Data Behavior

DLC-REQ-026: Logical deletion MUST remove records from user-visible workflows.

DLC-REQ-027: Physical deletion MUST remove records from active storage layers.

DLC-REQ-028: Revocation MUST disable access without implying deletion completion.

DLC-REQ-029: Deletion completion status MUST be queryable for audit and support workflows.

### Backup And Restore

DLC-REQ-030: Backup policy MUST cover all critical data classes.

DLC-REQ-031: Restore drills MUST run on a scheduled cadence with documented success criteria.

DLC-REQ-032: Restore operations MUST preserve lineage and audit metadata.

## Decisions

- DEC-015-01: Data lifecycle controls are mandatory release gates, not optional operations guidance.
- DEC-015-02: Deletion modes are explicitly differentiated to prevent policy ambiguity.

## Non-goals

- This document does not define physical database schema.
- This document does not define vendor-specific storage tier settings.

## Risks

- Risk: deletion ambiguity causing compliance exposure.
  Mitigation: explicit deletion-mode controls and audit evidence requirements.
- Risk: lineage gaps reducing trust in recommendations.
  Mitigation: mandatory provenance and lineage metadata.

## Verification

| Requirement Scope | Verification Method | Owner | Stage |
| --- | --- | --- | --- |
| Ingestion and classification | Data validation tests and policy checks | Chief Rails | CI |
| Retention and deletion controls | Lifecycle integration tests and audit review | Chief Security | CI and release |
| Backup and restore behavior | Restore drills and evidence logs | Chief Rails | Operations gate |

## Open Questions

- Which data classes require customer-configurable retention windows in baseline releases?
- Which export classes require cryptographic signing before delivery?

## Related Documents

- [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md)
- [016 STATE_MODEL.md](016%20STATE_MODEL.md)
- [018 OBSERVABILITY.md](018%20OBSERVABILITY.md)
- [019 VERSIONING.md](019%20VERSIONING.md)
- [diagrams/DATA_LIFECYCLE.md](../diagrams/DATA_LIFECYCLE.md)

## Change Control

Any change to this document MUST:

1. Include compatibility impact by data class.
2. Include migration and retention impact assessment.
3. Include updated verification evidence requirements.
4. Include ADR references.
