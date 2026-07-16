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

## Identifier Conventions

- Product Requirements: PR-REQ-XXX
- Capabilities: CAP-XXX
- Workflows: WF-XXX
- Product Rules: PRULE-XXX
- Acceptance Criteria: AC-CAP-XXX, AC-WF-XXX, AC-SM-XXX, and AC-PRULE-XXX
- Owner Decisions: OD-XXX

## Volume I Review Gate

Volume I is ready for owner review only when all are true:

1. all CAP, WF, Score Model, and PRULE items have explicit objective acceptance criteria
2. all PRULE items map to at least one CAP and WF and to the same-numbered AC-PRULE assertion
3. traceability matrix rows map through to planned test types
4. unresolved owner choices are explicitly recorded in [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md)
5. Volume II remains paused in control documents

This review gate is distinct from the Volume I acceptance gate below.

## Volume I Acceptance Checklist

Volume I acceptance MUST NOT be marked passed unless every blocking item below is in Pass state.

| Checklist Item | Status | Evidence |
| --- | --- | --- |
| Product definition completeness | Pass | [PRODUCT_DEFINITION.md](PRODUCT_DEFINITION.md) covers PR-REQ-001 through PR-REQ-030. |
| Capability coverage | Blocked | [CAPABILITY_MODEL.md](CAPABILITY_MODEL.md) covers CAP-001 through CAP-025. CAP-009 through CAP-011 still lack the mandatory baseline Check Definition catalog and CAP-001 through CAP-004 still depend on incomplete onboarding, invitation, bootstrap, Access Policy, and Source-registration input contracts. |
| Workflow coverage | Blocked | [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md) covers WF-001 through WF-018. WF-001, WF-002, and WF-013 still lack complete bootstrap/invitation/access-resolution behavior; WF-007 cannot enumerate required execution outcomes until the baseline Check Definition catalog exists. |
| Rule coverage | Pass | [PRODUCT_RULES.md](PRODUCT_RULES.md) covers PRULE-001 through PRULE-046; every rule has Capability, Workflow, same-numbered AC-PRULE, trace, test-type, and decision-dependency coverage, and identifier/source/cross-reference validation passes. |
| Acceptance criteria coverage | Blocked | Every AC-CAP-001 through AC-CAP-025, AC-WF-001 through AC-WF-018, AC-SM-001 through AC-SM-008, and AC-PRULE-001 through AC-PRULE-046 identifier exists with an objective assertion, but onboarding/access/source-registration fixtures and CAP-009 through CAP-011 Check-catalog fixtures have no complete normative oracle yet. |
| Traceability completeness | Pass | [TRACEABILITY_MATRIX.md](TRACEABILITY_MATRIX.md) covers every PR-REQ, CAP, WF, PRULE, and Acceptance ID; expanded-range, planned test-type, and Product Rule owner-decision dependency validation passes. |
| Security alignment | Blocked | Runtime permissions, protected grants, support sessions, tenant scoping, and score redaction are explicit. The bootstrap grant, invitation authority, named baseline Access Policy payload, and deterministic multi-assignment/effective-permission resolution formula remain undefined. |
| Data lifecycle alignment | Blocked | Evidence, snapshot, lineage, export, and deletion assertions exist; retention-class and deletion-policy cross-check against [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md) remains required. |
| State alignment | Blocked | Source verification/scope, crawl/parsing, Evaluation, Issue/Case, score, notification, entitlement, export, incident, and investigation paths are explicit. WF-002 draft activation failure still conflicts with [../016 STATE_MODEL.md](../016%20STATE_MODEL.md), and onboarding grant/invitation transitions are absent. |
| Error alignment | Blocked | Priority workflow retry, timeout, terminal, precedence, and recovery behavior is explicit; onboarding, invitation, Access Policy, Source-registration, and baseline Check execution still lack exhaustive rejection/recovery codes. |
| Observability alignment | Blocked | Priority events, attempts, escalation, replay, and correlation evidence are explicit; the missing onboarding/invitation and baseline Check contracts leave their exact event sets incomplete. |
| Owner decisions resolved or decision-ready | Blocked | [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md) contains unresolved owner approvals. |
| ADR completeness for accepted architecture-impacting decisions | Blocked | Pending owner approvals include decisions with ADR thresholds not yet triggered by approved outcomes. |
| Terminology consistency | Pass | Canonical Issue terminology is used as the sole deficiency entity across the canonical Volume I files; no Finding domain entity remains. |
| Volume II pause preserved | Pass | Volume II remains paused in [../../ROADMAP.md](../../ROADMAP.md) and [../../PROJECT_STATE.md](../../PROJECT_STATE.md). |

Current Acceptance Gate Outcome: Blocked by every checklist item still marked Blocked above, including pending owner approvals.

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
