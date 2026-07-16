# Volume I Product Specification Index

## Status

- Status: Accepted; acceptance change set pending commit and tag
- Foundation Version Dependency: 1.0
- Last Updated: 2026-07-16
- Owner: Chief Architect
- Prior Implementation-Ready Tag: `v1.1-implementation-ready`

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
- Check Definitions: CHK-TI-001, CHK-CQ-001, CHK-TR-001, CHK-SP-001, CHK-AIP-001, CHK-AS-001, and CHK-LP-001 under `check-catalog-interim-v1`
- Product Rules: PRULE-XXX
- Acceptance Criteria: AC-CAP-XXX, AC-WF-XXX, AC-SM-XXX, and AC-PRULE-XXX
- Owner Decisions: OD-001 through OD-011; OD-004 is resolved and the others remain approval items with deterministic interim behavior

## Volume I Review Gate

Volume I is ready for owner review only when all are true:

1. all CAP, WF, Score Model, and PRULE items, and every active Check Definition through its owning CAP/WF/Score/PRULE assertion, have explicit objective acceptance criteria
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
| Capability coverage | Pass | [CAPABILITY_MODEL.md](CAPABILITY_MODEL.md) covers CAP-001 through CAP-025; onboarding, source, seven-Check ownership, scoring, recommendation, delivery, entitlement, and tenant-lifecycle behavior each resolve to a named normative contract and acceptance oracle. |
| Workflow coverage | Pass | [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md) covers WF-001 through WF-018 with deterministic interim onboarding, source, ingestion/indexing, seven-Check execution, scoring/adjudication, recommendation, entitlement, notification, export, incident, and lifecycle paths. |
| Rule coverage | Pass | [PRODUCT_RULES.md](PRODUCT_RULES.md) covers PRULE-001 through PRULE-046; every rule has Capability, Workflow, same-numbered AC-PRULE, trace, test-type, and decision-dependency coverage, and identifier/source/cross-reference validation passes. |
| Acceptance criteria coverage | Pass | Every AC-CAP-001 through AC-CAP-025, AC-WF-001 through AC-WF-018, AC-SM-001 through AC-SM-008, and AC-PRULE-001 through AC-PRULE-046 identifier has one conjunctive measurable assertion; active Checks are covered through their owning CAP/WF/Score/PRULE assertions. |
| Traceability completeness | Pass | [TRACEABILITY_MATRIX.md](TRACEABILITY_MATRIX.md) covers every PR-REQ, CAP, WF, PRULE, and Acceptance ID; expanded-range, planned test-type, and Product Rule owner-decision dependency validation passes. |
| Security alignment | Pass | Bootstrap, invitation, Session, Access Policy, effective-permission resolution, anti-SSRF/XML, support scope, redaction, legal hold, high-risk approvals, and platform-managed Integration/Credential authority, rotation, expiry, revocation, checkpoint, and secret-nonpersistence behavior are explicit. |
| Data lifecycle alignment | Pass | [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md) defines `retention-interim-v1`, exact classes/windows, legal hold, deletion jobs, backup tombstones, evidence expiry, recovery, and completion evidence; Volume I workflows and assertions reference the same contract. |
| State alignment | Pass | Named Volume I paths match [../016 STATE_MODEL.md](../016%20STATE_MODEL.md), including Project activation, Evaluation retry/supersession, RecommendationArtifact, LegalHold, LifecycleDeletionJob, Integration reconnect/degradation/retirement, and Credential rotation/expiry/revocation. |
| Error alignment | Pass | The shared envelope fixes first-match subsystem/class precedence, code, severity, retry default, recovery action, safe unmapped behavior, and support reference; workflow contracts supply bounded timeout/retry/terminal behavior and exact narrower overrides. |
| Observability alignment | Pass | The event envelope fixes actor/service attribution, profile-specific required fields, related-entity/version ordering, transition/attempt/decision/policy/projection/failure/recovery payloads, schema compatibility, redelivery, notification context, correlation, escalation, and secret/redaction rules. |
| Owner decisions resolved or decision-ready | Pass | [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md) gives every pending decision deterministic interim behavior and exact blocking impact. None blocks Volume II; OD-010 blocks complete customer-facing numeric scoring and OD-011 blocks production customer-data use until their approval packages are complete. |
| ADR completeness for accepted architecture-impacting decisions | Pass | No currently approved Volume I outcome has an unmet ADR trigger; each pending owner decision states the exact threshold that would require an ADR if that option is approved. |
| Terminology consistency | Pass | Canonical Issue terminology is used as the sole deficiency entity across the canonical Volume I files; no Finding domain entity remains. |
| Volume II pause preserved | Pass | Volume II remains paused in [../../ROADMAP.md](../../ROADMAP.md) and [../../PROJECT_STATE.md](../../PROJECT_STATE.md). |

Current Acceptance Gate Outcome: Pass. Volume I is accepted as the behavioural baseline. Pending owner decisions remain only the precise feature, contractual, implementation-stage, or production gates stated in [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md); they do not reopen defined interim behaviour and do not block Volume II.

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

Volume I is accepted by this change set over the prior `v1.1-implementation-ready` baseline. After the accepted-baseline commit and tag, a normative Volume I edit is permitted only to correct a demonstrated defect—a contradiction, non-executable contract, unsafe behavior, or acceptance oracle that cannot test the stated behavior—or to incorporate an approved owner decision through controlled change. Preference changes, scope expansion, new capabilities, speculative refinement, governance expansion, and silent replacement of deterministic interim behavior are not defect corrections.

Pending owner approvals remain explicit release gates. Approval of the already-specified interim behavior may be recorded without reopening product scope. An owner choice that would replace frozen behavior requires explicit product-owner authorization to unfreeze and version Volume I; it MUST NOT be disguised as a defect correction.

Every permitted defect correction MUST:

1. update affected Volume I documents in the same change set
2. update [TRACEABILITY_MATRIX.md](TRACEABILITY_MATRIX.md)
3. update [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md) if owner-level decisions are affected
4. update control-plane documents when sequencing or readiness gates change
5. cite the implementation evidence that demonstrates the defect and receive a successor implementation-baseline tag
