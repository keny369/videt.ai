# Volume I Product Specification Index

## Status

- Status: Draft for owner review
- Foundation Version Dependency: 1.0
- Last Updated: 2026-07-16
- Owner: Chief Architect

## Authority

This index is the canonical navigation and control document for Volume I.

Volume I remains subordinate to:

1. Accepted ADRs
2. Foundation documents 000 through 020
3. Canonical research and business-case material

## Purpose

Define an implementation-ready product specification for F1 while preserving the Volume II pause gate.

## Scope

Volume I defines product behavior, product rules, capability model, workflows, score and evidence model, acceptance criteria, and decision requirements for unresolved owner-level choices.

Volume I does not define:

- Volume II content
- implementation code
- API contract wire formats
- physical data schemas
- deployment implementation steps

## Canonical Documents

- [PRODUCT_DEFINITION.md](PRODUCT_DEFINITION.md)
- [CAPABILITY_MODEL.md](CAPABILITY_MODEL.md)
- [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md)
- [PRODUCT_RULES.md](PRODUCT_RULES.md)
- [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md)
- [ACCEPTANCE_AND_TEST_MAPPING.md](ACCEPTANCE_AND_TEST_MAPPING.md)
- [TRACEABILITY_MATRIX.md](TRACEABILITY_MATRIX.md)
- [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md)
- [INDEPENDENT_REVIEW.md](INDEPENDENT_REVIEW.md)

## Identifier Conventions

- Product Requirements: PR-REQ-XXX
- Capabilities: CAP-XXX
- Workflows: WF-XXX
- Product Rules: PRULE-XXX
- Acceptance Criteria: AC-CAP-XXX and AC-WF-XXX
- Owner Decisions: OD-XXX

## Volume I Review Gate

Volume I is ready for owner review only when all are true:

1. all CAP and WF items have explicit acceptance criteria
2. all PRULE items map to at least one CAP and WF
3. traceability matrix rows map through to planned test types and operational evidence
4. unresolved owner choices are explicitly recorded in [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md)
5. Volume II remains paused in control documents

## Dependencies

- [../000 OVERVIEW.md](../000%20OVERVIEW.md)
- [../001 PRODUCT_ARCHITECTURE_MANUAL.md](../001%20PRODUCT_ARCHITECTURE_MANUAL.md)
- [../002 GLOSSARY.md](../002%20GLOSSARY.md)
- [../003 TERMINOLOGY.md](../003%20TERMINOLOGY.md)
- [../005 PRODUCT_PRINCIPLES.md](../005%20PRODUCT_PRINCIPLES.md)
- [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md)
- [../012 SYSTEM_BOUNDARIES.md](../012%20SYSTEM_BOUNDARIES.md)
- [../013 QUALITY_ATTRIBUTES.md](../013%20QUALITY_ATTRIBUTES.md)
- [../014 SECURITY_MODEL.md](../014%20SECURITY_MODEL.md)
- [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md)
- [../016 STATE_MODEL.md](../016%20STATE_MODEL.md)
- [../017 ERROR_MODEL.md](../017%20ERROR_MODEL.md)
- [../018 OBSERVABILITY.md](../018%20OBSERVABILITY.md)
- [../019 VERSIONING.md](../019%20VERSIONING.md)
- [../020 EXTENSIBILITY.md](../020%20EXTENSIBILITY.md)
- [../../research/000-initial-concept.md](../../research/000-initial-concept.md)
- [../../ROADMAP.md](../../ROADMAP.md)
- [../../PROJECT_STATE.md](../../PROJECT_STATE.md)

## Change Control

Any normative change in this document MUST:

1. update affected Volume I documents in the same change set
2. update [TRACEABILITY_MATRIX.md](TRACEABILITY_MATRIX.md)
3. update [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md) if owner-level decisions are affected
4. update control-plane documents when sequencing or readiness gates change
