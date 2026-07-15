# 019 VERSIONING

## Status

- Status: Accepted
- Foundation Version: 1.0
- Last Updated: 2026-07-15

## Authority

This document defines canonical versioning and compatibility policy across F1 specifications, interfaces, events, schemas, and AI assets.

All downstream specifications MUST comply with this policy.

## Purpose

Define version identifiers, compatibility expectations, migration rules, deprecation policy, and rollback rules.

## Scope

This document covers:

- API versioning
- schema and event versioning
- domain model versioning
- prompt and model versioning
- evaluation and adapter versioning
- integration versioning
- documentation versioning
- migration and compatibility rules
- deprecation and sunset policy
- feature flags, reproducibility, and audit traceability

## Dependencies

- [011 DOMAIN_MODEL.md](011%20DOMAIN_MODEL.md)
- [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md)
- [015 DATA_LIFECYCLE.md](015%20DATA_LIFECYCLE.md)
- [018 OBSERVABILITY.md](018%20OBSERVABILITY.md)

## Definitions

- Backward Compatibility: Existing consumers continue to function without required changes.
- Forward Compatibility: Older consumers tolerate newer fields or event variants safely.
- Sunset Period: Time window between deprecation notice and removal.

## Assumptions

- Multiple versioned artifacts evolve independently.
- Compatibility strategy must support phased customer migration.
- Version metadata must be queryable in logs and audit records.

## Constraints

- Version changes MUST be explicit and documented.
- Breaking changes MUST include migration and communication plans.
- Reproducibility requirements MUST apply to AI and evaluation workflows.

## Normative Requirements

### Versioning Domains

VER-REQ-001: The following domains MUST carry explicit versions:

- API contracts
- schema definitions
- event contracts
- domain model definitions
- prompt templates
- model configurations
- evaluation suites
- adapters and integrations
- canonical documentation

VER-REQ-002: Every versioned artifact MUST include owner and release date metadata.

### Compatibility Rules

VER-REQ-003: Backward compatibility MUST be default for stable interfaces.

VER-REQ-004: Breaking changes MUST require ADR reference and migration plan.

VER-REQ-005: Forward compatibility handling rules MUST be documented for event and API consumers.

### Migration Rules

VER-REQ-006: Data migrations MUST define rollback strategy and validation checks.

VER-REQ-007: Migration execution MUST include pre-check, execution, and post-check evidence.

VER-REQ-008: Migration reversibility classification MUST be recorded in ADRs.

### Deprecation And Sunset

VER-REQ-009: Deprecation notices MUST include replacement path and sunset date.

VER-REQ-010: Sunset periods MUST be published before removal actions.

VER-REQ-011: Consumer notification MUST be tracked and auditable.

### Feature Flags And Rollback

VER-REQ-012: Feature flags MUST include owner, default state, and removal deadline.

VER-REQ-013: Rollback plans MUST exist for all high-impact changes.

### Reproducibility

VER-REQ-014: Evaluation and AI outputs MUST store prompt version, model version, and input snapshot identifier.

VER-REQ-015: Reproducing prior outputs MUST be possible from stored version metadata and lineage.

### Logs And Audit

VER-REQ-016: Version identifiers MUST appear in logs and audit trails for relevant workflows.

VER-REQ-017: Missing version metadata MUST fail release verification.

## Decisions

- DEC-019-01: Versioning applies equally to software interfaces and AI assets.
- DEC-019-02: Breaking changes require explicit migration governance.

## Non-goals

- This document does not define semantic version syntax details per artifact.
- This document does not define customer-specific contract negotiations.

## Risks

- Risk: undocumented breaking changes cause consumer failures.
  Mitigation: compatibility gates and migration evidence requirements.
- Risk: non-reproducible AI outputs weaken trust.
  Mitigation: mandatory prompt and model version capture.

## Verification

| Requirement Scope | Verification Method | Owner | Stage |
| --- | --- | --- | --- |
| Version metadata presence | Static checks and contract tests | Chief Rails | CI |
| Compatibility policy compliance | API and event compatibility tests | Chief Architect | CI and release |
| Migration and rollback evidence | Release checklist and migration drills | Chief Rails | Release gate |

## Open Questions

- Which artifact classes require long-term support windows beyond standard sunset policy?
- Which integrations require customer-specific compatibility contracts?

## Related Documents

- [015 DATA_LIFECYCLE.md](015%20DATA_LIFECYCLE.md)
- [018 OBSERVABILITY.md](018%20OBSERVABILITY.md)
- [020 EXTENSIBILITY.md](020%20EXTENSIBILITY.md)
- [FOUNDATION_TRACEABILITY_MATRIX.md](FOUNDATION_TRACEABILITY_MATRIX.md)

## Change Control

Any normative change MUST:

1. Include compatibility impact analysis.
2. Include migration and rollback impact analysis.
3. Include updated consumer notification obligations.
4. Include ADR reference.
