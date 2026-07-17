# Volume I Product Specification Index

## Status

- Status: Accepted as the behavioural baseline; NOT frozen. The ADR-017 corrections are committed and tagged; an RC1 release-candidate review subsequently recorded open normative defects that block a successor freeze.
- Foundation Version Dependency: 1.0
- Last Updated: 2026-07-16
- Owner: Chief Architect
- Current Baseline Tag: `v1.3-volume-i-corrected` at commit `5d725fa`
- Superseded Baseline Tags: `v1.2-volume-i-frozen` and `v1.1-implementation-ready` are retained as history only. They predate the ADR-017 corrections and MUST NOT be used as an implementation baseline.
- Freeze Status: NOT frozen. The Volume I ratified pre-legal baseline is `v1.4-volume-i-ratified-prelegal`, integrating the 2026-07-17 owner ratification under ADR-019. The successor Volume I freeze requires qualified legal review of the retention, deletion and notification package and an explicit Chief Architect decision on OD-013 event tenant identity; neither is resolvable by specification work. Implementation remains gated by PM-REQ-010.

## Authority

This index is the canonical navigation and control document for Volume I.

Authority precedence is fixed by PM-REQ-003 in [../001 PRODUCT_ARCHITECTURE_MANUAL.md](../001%20PRODUCT_ARCHITECTURE_MANUAL.md) and is exactly:

1. Constitution and governance
2. Foundation layer 000 through 020
3. ADR registry
4. Volume specifications
5. Derived implementation artifacts

Volume I is a Volume specification at rank 4. It is therefore subordinate to the constitution and governance, to foundation documents 000 through 020, and to the ADR registry, and it outranks derived implementation artifacts.

An accepted ADR does not outrank an unchanged foundation requirement. Per [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md), an ADR authorizes the PM-REQ-009 controlled-change process but does not by itself supersede a foundation requirement; a changed requirement becomes authoritative only when the foundation document and every required affected artifact are updated and accepted through that process. The ADR registry's rank 3 position governs conflicts among artifacts at rank 4 and below; it does not invert rank 2.

PM-REQ-003 assigns no rank to canonical research or business-case material, and no foundation document grants it one. It is therefore not an authority layer: it is evidence input to a decision, it never overrides a normative contract at any rank, and a Volume I document MUST NOT position itself as subordinate to it. The evidence-preference ordering used when weighing decision inputs is recorded separately in [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md) and is subordinate to this precedence.

## Purpose

Define an implementation-ready product specification for F1 while preserving the sequencing gates in [../../ROADMAP.md](../../ROADMAP.md).

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
- Check Definitions: CHK-TI-001, CHK-CQ-001, CHK-TR-001, CHK-SP-001, CHK-AIP-001, CHK-AS-001, and CHK-LP-001 under `check-catalog-v1`
- Product Rules: PRULE-XXX
- Acceptance Criteria: AC-CAP-XXX, AC-WF-XXX, AC-SM-XXX, and AC-PRULE-XXX
- Owner Decisions: OD-001 through OD-032; OD-004 is resolved and the others remain approval items with deterministic interim behavior. OD-012 through OD-032 were registered by the RC1 correction programme under ADR-018.

## Volume I Review Gate

Volume I is ready for owner review only when all are true:

1. all CAP, WF, Score Model, and PRULE items, and every active Check Definition through its owning CAP/WF/Score/PRULE assertion, have explicit objective acceptance criteria
2. all PRULE items map to at least one CAP and WF and to the same-numbered AC-PRULE assertion
3. traceability matrix rows map through to planned test types
4. unresolved owner choices are explicitly recorded in [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md)
5. Volume II sequencing matches the control documents: Gate B is satisfied, Gate C permits implementation-architecture work, and no Volume II artifact resolves an open Volume I ambiguity on Volume I's behalf

This review gate is distinct from the Volume I acceptance gate below.

## Volume I Acceptance Checklist

Volume I acceptance MUST NOT be marked passed unless every blocking item below is in Pass state.

| Checklist Item | Status | Verification Basis |
| --- | --- | --- |
| Product definition completeness | Pass | [PRODUCT_DEFINITION.md](PRODUCT_DEFINITION.md) covers PR-REQ-001 through PR-REQ-030. |
| Capability coverage | Pass | [CAPABILITY_MODEL.md](CAPABILITY_MODEL.md) covers CAP-001 through CAP-025; onboarding, source, seven-Check ownership, scoring, recommendation, deterministic structured dashboard/history output with no AI narrative, delivery, entitlement, and tenant-lifecycle behavior each resolve to a named normative contract and acceptance oracle. |
| Workflow coverage | Pass | [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md) covers WF-001 through WF-018 with deterministic interim onboarding, source, ingestion/indexing, seven-Check execution, scoring/adjudication, recommendation, structured-only history comparison with no AI-provider narrative call, entitlement, notification, export, incident, and lifecycle paths. |
| Rule coverage | Pass | [PRODUCT_RULES.md](PRODUCT_RULES.md) covers PRULE-001 through PRULE-046; every rule has Capability, Workflow, same-numbered AC-PRULE, trace, test-type, and decision-dependency coverage, and identifier/source/cross-reference validation passes. |
| Acceptance criteria coverage | Pass | Every AC-CAP-001 through AC-CAP-025, AC-WF-001 through AC-WF-018, AC-SM-001 through AC-SM-008, and AC-PRULE-001 through AC-PRULE-046 identifier has one conjunctive measurable assertion; active Checks are covered through their owning CAP/WF/Score/PRULE assertions, and AC-CAP-018, AC-WF-012 and AC-PRULE-030 prohibit AI dashboard/history narrative, placeholders and provider calls while requiring complete success without narrative. |
| Traceability completeness | Pass | [TRACEABILITY_MATRIX.md](TRACEABILITY_MATRIX.md) covers every PR-REQ, CAP, WF, PRULE, and Acceptance ID; expanded-range, planned test-type, and Product Rule owner-decision dependency validation passes. |
| Security alignment | Pass | Bootstrap, invitation, purpose-bound existing-Account sign-in, concurrent Session behavior, Access Policy, effective-permission resolution, anti-SSRF/XML, support scope, redaction, legal hold, high-risk approvals, and platform-managed Integration/Credential authority, rotation, expiry, revocation, checkpoint, and secret-nonpersistence behavior are explicit. |
| Data lifecycle alignment | Pass | [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md) defines `retention-interim-v1`, exact classes/windows, BillingEntity retention, the canonical Evidence/Payload/Audit Evidence split, legal hold, deletion jobs, backup tombstones, Evidence expiry, recovery, and completion evidence; Volume I workflows and assertions reference the same contract. |
| State alignment | Pass | Named Volume I paths match [../016 STATE_MODEL.md](../016%20STATE_MODEL.md), including Session creation/expiry, BillingEntity bootstrap/closure, policy-scheduled reassessment, explicit Mailgun acceptance uncertainty, Project activation, Evaluation retry/supersession, RecommendationArtifact, LegalHold, LifecycleDeletionJob, Integration reconnect/degradation/retirement, and Credential rotation/expiry/revocation. |
| Error alignment | Pass | The shared envelope fixes first-match subsystem/class precedence, code, severity, retry default, recovery action, safe unmapped behavior, and support reference; workflow contracts supply bounded timeout/retry/terminal behavior and exact narrower overrides. |
| Observability alignment | Pass | The event envelope fixes actor/service attribution, sign-in outcomes, reassessment schedule decisions, BillingEntity lifecycle, Mailgun attempts/uncertainty/reconciliation/replay, profile-specific required fields, related-entity/version ordering, transition/decision/policy/projection/failure/recovery payloads, schema compatibility, redelivery, correlation, escalation, and secret/redaction rules. |
| Owner decisions resolved or decision-ready | Pass for decision-readiness; the count is materially larger than at ADR-017 | [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md) gives every pending decision deterministic fail-closed interim behavior and exact blocking impact. Thirty-one decisions are pending and one is resolved. OD-010 blocks complete customer-facing numeric scoring and OD-011 blocks production customer-data use. OD-013 blocks `BootstrapGrantIssued`/`BootstrapGrantExpired` emission, platform-wide Incidents, and cross-Organization Investigations; OD-012 leaves no emergency cross-tenant support path; and OD-014 through OD-032 each block their named path. Four fields across OD-013, OD-015, OD-028, and OD-032 are marked `OWNER INPUT REQUIRED` because no accepted authority supplies them; OD-028's entire Recommended Option is so marked. |
| ADR completeness for accepted architecture-impacting decisions | Pass | ADR-017 governs the six demonstrated post-freeze corrections; no currently approved Volume I outcome has an unmet ADR trigger, and each pending owner decision states the exact threshold that would require another ADR if that option is approved. |
| Terminology consistency | Pass | Canonical Issue terminology is the sole deficiency entity, and canonical Evidence vocabulary distinguishes Evidence, Type, Source, Payload, Provenance, Classification, Measurement Evidence, Verification Evidence, and Audit Evidence without duplicate concepts. |
| Volume II sequencing | Pass | Gate B was satisfied by `v1.3-volume-i-corrected`, so Volume II implementation-architecture work is permitted under Gate C in [../../ROADMAP.md](../../ROADMAP.md) and [../../PROJECT_STATE.md](../../PROJECT_STATE.md). Volume II Pass 001 is complete for unblocked behaviour; its architecture baseline and broad implementation remain blocked by the upstream Volume I defects it records. Volume I is no longer claimed to be paused-and-unexpanded downstream. |

Current Acceptance Gate Outcome: Conditional Pass for behavioural content; FAIL for freeze readiness.

Volume I is accepted as the behavioural baseline and its behavioural content is stable enough to build against for unblocked slices. It is NOT ready to become the permanent implementation baseline.

Pending owner decisions remain the precise feature, contractual, implementation-stage, or production gates stated in [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md); they do not reopen defined interim behaviour.

Separately from those owner decisions, an RC1 release-candidate review recorded open normative defects — including contradictions, states with no command surface, and events whose mandatory envelope cannot be satisfied — which are tracked as upstream blockers in [../volume-ii/INDEX.md](../volume-ii/INDEX.md) and are being corrected under the RC1 correction programme. A successor freeze requires that programme to complete and an RC2 regression audit to return no Critical or High finding.

## Open Defect Status

Volume I carries open normative defects recorded by the RC1 review. This section exists so that no reader can infer completeness from the checklist above.

- Thirteen upstream product-behaviour ambiguities are enumerated in [../volume-ii/INDEX.md](../volume-ii/INDEX.md). Each blocks a named route, job, event, or write path. Volume II MUST NOT resolve them; they require controlled Volume I correction.
- Defects requiring a product determination are being registered as owner decisions in [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md) with deterministic fail-closed interim behaviour, rather than resolved by architectural inference.
- Defects that existing authority already forces are corrected in place, with the derivation cited.

No checklist row above may be read as evidence that these defects are absent.

## Dependencies

- [../000 OVERVIEW.md](../000%20OVERVIEW.md)
- [../001 PRODUCT_ARCHITECTURE_MANUAL.md](../001%20PRODUCT_ARCHITECTURE_MANUAL.md)
- [../002 GLOSSARY.md](../002%20GLOSSARY.md)
- [../003 TERMINOLOGY.md](../003%20TERMINOLOGY.md)
- [../005 PRODUCT_PRINCIPLES.md](../005%20PRODUCT_PRINCIPLES.md)
- [../008 AI_PRINCIPLES.md](../008%20AI_PRINCIPLES.md)
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

Volume I is not frozen. Its current baseline is `v1.4-volume-i-ratified-prelegal`, the ratified pre-legal baseline created by the ADR-019 integration of the 2026-07-17 owner ratification session. `v1.3-volume-i-corrected` at `5d725fa` is its immediate predecessor and is retained as history. This milestone is reviewable, not final: it is not implementation-ready, and no document may describe it as frozen.

ADR-018 authorizes the RC1 correction programme. Outside that programme, a normative Volume I edit remains permitted only to correct a demonstrated defect—a contradiction, non-executable contract, unsafe behavior, or acceptance oracle that cannot test the stated behavior—or to incorporate an approved owner decision through controlled change. Preference changes, scope expansion, new capabilities, speculative refinement, governance expansion, and silent replacement of deterministic interim behavior are not defect corrections.

Twenty-one owner decisions were ratified or resolved on 2026-07-17 and integrated under ADR-019; each names its approved option or outcome in [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md) and no ratified decision remains described as pending or interim. Ten owner decisions remain pending and remain explicit release gates: OD-011, OD-013, OD-014, OD-023, OD-027, OD-029, OD-030, OD-031, OD-032 and OD-033. Assurance evidence for this milestone is recorded in [SPECIFICATION_ASSURANCE_REPORT_2026-07-17.md](SPECIFICATION_ASSURANCE_REPORT_2026-07-17.md). Owner approval and counsel consultation of 2026-07-17 are recorded in [LEGAL_REVIEW_RECORD_2026-07-17.md](LEGAL_REVIEW_RECORD_2026-07-17.md); that record does not satisfy OD-011's closure standard and Volume I remains unfrozen.

Every permitted defect correction MUST:

1. update affected Volume I documents in the same change set
2. update [TRACEABILITY_MATRIX.md](TRACEABILITY_MATRIX.md)
3. update [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md) if owner-level decisions are affected
4. update control-plane documents when sequencing or readiness gates change
5. cite the implementation evidence that demonstrates the defect and receive a successor implementation-baseline tag
