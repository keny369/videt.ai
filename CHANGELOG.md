# Changelog

## 2026-07-17 — Engineering Manual Governance Pass 001 (ADR-021)

- reconciled three mutually contradictory authority hierarchies onto one canonical scoped model. PM-REQ-003, `engineering/manual/MANUAL_AUTHORITY.md` and EM-I-003 each stated a different precedence; MANUAL_AUTHORITY ranked ratified ADRs and Owner Decisions above Engineering Manual content while EM-I-003 ranked the Engineering Manual above both, so an engineer got opposite answers depending on which document was opened first
- amended PM-REQ-003 by PM-REQ-009 controlled foundation change: authority is now resolved by scope before rank. The accepted five-tier ordering is preserved verbatim as the product-behavior ladder; an engineering-practice ladder is added; PM-REQ-003.4 excludes the Engineering Manual from product-behavior authority absolutely rather than by rank. No tier is reordered, renumbered or removed
- corrected the two structural defect classes that prevented authority metadata from being parsed, in the two authority chapters carrying them. Every one of the 249 chapters and appendices carried one: 70 with a path heading before the front matter, 177 with indented front matter. The validator passed only because it was written around both defects. The outstanding 247 files are recorded in `scripts/front_matter_baseline.txt` as registered debt; frozen Volume I is not reformatted wholesale
- restated Roadmap Gate C on implementation-blocking status rather than a literal count of thirteen upstream blockers. Eleven are retired under ADR-019 and ADR-020, so the count could never be satisfied. OD-014 and OD-023 remain pending under their deterministic neutral interims and are expressly not resolved
- added front matter structure checks and three negative controls to the manual validator; both suites pass and the new controls are proved load-bearing by mutation testing
- recorded a CONFLICT: Engineering Manual Volume III establishes product behaviour it does not own, including `Project#archive!` examples that pre-empt pending OD-014, and an invented `Assessment` entity presented as canonical terminology that DM-REQ-001 does not define. Remediation requires its own controlled change and did not occur in this pass

## 2026-07-17 — Volume I frozen (ADR-020)

- closed the six decisions that blocked the freeze — OD-011, the OD-012 notification limb, OD-013, OD-029, OD-030 and OD-033 — on explicit owner decision recorded in the new append-only `specification/volume-i/OWNER_DECISION_RECORD_2026-07-17_LEGAL_AND_CLOSURE.md`; the earlier legal-review record is superseded on the evidence-standard point only and is not rewritten
- OD-011 Option 1: `retention-interim-v1` is the approved fixed Volume I retention baseline for worldwide availability, with principal initial English-speaking markets United States, United Kingdom, Australia, New Zealand, Canada and South Africa. Qualified external legal counsel reviewed the product and retention position and raised no objection. Customer-configurable retention is not approved. No retention window changed and no price, jurisdiction-specific conclusion or contractual promise was invented
- narrowly amended OD-011's Qualified Legal Approval element, which had demanded repository-hosted counsel signatures, reviewer identities and package digests, to accept an append-only owner approval record, a factual counsel-review record, the identified baseline and the applicable product/market scope. Privileged legal material is excluded by design; no signature, reviewer identity, digest or legal opinion is fabricated, and no record is presented as a legal opinion. No other element of the package is relaxed
- OD-013 Option 1 for every sub-decision: all events, Incidents and Investigations remain Organization-owned; WF-001 now expressly permits the DM-REQ-013 bootstrap substitution for `BootstrapGrantIssued` and `BootstrapGrantExpired` only; a platform-wide Incident and a cross-Organization Investigation are represented as coordinated per-Organization records linked by `correlation_id`. No `event_scope` discriminator, no platform-owned canonical record, and no change to DM-REQ-013. `UPSTREAM-V1-EVENT-SCOPE-001` is retired
- OD-033 Option 3: the direct `Queued -> Completed` LifecycleDeletionJob edge is treated as unintended and removed from `016 STATE_MODEL.md` by PM-REQ-009 controlled change; every job enters the existing `running` state before completing, and WF-013 no longer asserts the edge is required
- OD-029 Option 2 and OD-030 Option 3: WF-007 produces `EvidenceRetentionExpiring` under the integrity-validation service authority, satisfying `AC-CAP-013`'s previously unsatisfiable 30-day criterion; already-invalid Evidence Payload destruction stays on the capture cursor and 24-month maximum and is proved by a distinct immutable `security_audit` deletion audit record
- three PM-REQ-009 controlled foundation changes landed in the same change set: the LifecycleDeletionJob row of `016 STATE_MODEL.md`, and the retention-warning producer and already-invalid destruction path of `015 DATA_LIFECYCLE.md`
- Volume I is FROZEN at `v1.5-volume-i-frozen` and is the authoritative implementation baseline; the PM-REQ-010 gate for Volume I is satisfied. Five decisions remain pending and none blocks the freeze: OD-014, OD-023 and OD-031 are implementation-blocking with deterministic neutral interims, and OD-027 and OD-032 are Volume II-blocking

## 2026-07-17 — Legal review record; Volume I freeze NOT achieved

- recorded the owner's approval of the presently recorded proposals and the fact of counsel consultation with no objection, in the new append-only `specification/volume-i/LEGAL_REVIEW_RECORD_2026-07-17.md`
- did not close OD-011. Its own standard requires reviewer identity and capacity, jurisdictions and material legal assumptions reviewed, a policy package identity/version/canonical digest, signed UTC time, and separate Chief Security and Chief Product signatures over that same digest. None exists in the repository or was supplied, and the owner's own constraint forbids inventing jurisdictions or markets to obtain closure. The requirement binds every OD-011 option, including Option 1
- did not close OD-013. Contrary to the ratification session's summary, the Owner Decision Register recommends Option 1 for the pre-Organization bootstrap sub-decision only and records the platform-wide Incident and cross-Organization Investigation sub-decisions as owner input required, stating that no accepted authority selects among them. `UPSTREAM-V1-EVENT-SCOPE-001` therefore remains a genuine blocker
- did not close OD-033, whose own text states the choice is genuinely open and that no accepted authority prefers either option
- no freeze tag was created. Volume I remains at `v1.4-volume-i-ratified-prelegal`; implementation remains gated by PM-REQ-010

## 2026-07-17 — Volume I owner ratification integration (ADR-019)

- integrated the 2026-07-17 owner ratification session recorded in `specification/volume-i/RATIFICATION_SESSION_2026-07-17.md`, together with the three decisions that session left indeterminate, recorded in the new dated `specification/volume-i/OWNER_DECISION_SUPPLEMENT_2026-07-17.md`; the append-only ratification record was not edited
- accepted ADR-019 authorizing the integration and recording all 21 decisions: 11 ratified as specified, 5 resolved by owner decision, 3 resolved by replacement, and 2 resolved by supplemental owner decision
- applied four PM-REQ-009 controlled foundation changes in the same change set: the Document row of `016 STATE_MODEL.md` loses the `quarantined` and `retired` states and the `DocumentQuarantined` and `DocumentRetired` events under OD-015; the Session row names the actor and permission for termination and single-Session revocation under OD-016 and SM-REQ-010; a new EmergencyAccessGrant row is added under OD-012; and the WF-011 coverage row of `018 OBSERVABILITY.md` is amended under OD-025. Three of the four were not named by the ratification session and were established from the repository's own governance requirements
- removed `ComparisonGenerated` (OD-024) and `ReassessmentTriggered` (OD-025) as canonical domain events; comparison and reassessment remain fully functional and observable through already-accepted events, records and Audit Evidence, and no replacement event was invented
- added current-Session sign-out and single-Session security revocation (OD-016), customer-facing read rows to `permission-baseline-v1` (OD-020), a dedicated emergency-access break-glass workflow outside the Incident aggregate (OD-012 Option 3), the `organization_reactivation` receipt purpose (OD-022), and the immutable `RoleExpiryBlockDecision` record with its mandatory `RoleExpiryBlocked` route (OD-026)
- made deterministic the Issue fingerprint collision outcome (OD-017) and the single initial Evaluation orchestration per Project (OD-018); both were ratified but had never been wired into WF-007 and WF-005 respectively, and would have produced behaviour inconsistent with the ratified decisions
- separated commercial policy from product architecture: daily read limits, crawl quotas, entitlement and warning thresholds, grace periods and similar numerals are versioned policy configuration bound to an approved policy version, not immutable Volume I constants. No price or packaging tier was invented
- renamed 11 interim policy identifiers to their approved Version 1 identity across 56 references; identifiers owned by pending decisions and the 12 ADR-018 interim contracts with no owning owner decision retain their interim identity
- corrected the `documents` CHECK constraint, which still admitted the removed `quarantined` and `retired` states after the canonical model removed them, and 14 negative assertions across Volume II, the schema and Volume I that asserted behaviour was unreachable because of decisions since ratified
- retired 10 upstream blockers whose upstream decision is now resolved, while `UPSTREAM-V1-EVENT-SCOPE-001`, `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` and `UPSTREAM-V1-PROJECT-LIFECYCLE-003` remain genuine blockers. Volume II exposure is intentionally deferred to the Volume II baseline; no route, endpoint, command, serializer or transport was defined
- recorded assurance evidence in `specification/volume-i/SPECIFICATION_ASSURANCE_REPORT_2026-07-17.md`, including validator negative-control results
- outstanding external gates: qualified legal review of the retention, deletion and notification package (OD-011, OD-029, OD-030, OD-033, and OD-012's notification limb), which additionally requires prerequisite owner input the repository does not contain; and OD-013 event tenant identity, which requires an explicit Chief Architect decision
- this is the Volume I ratified pre-legal baseline, committed and tagged `v1.4-volume-i-ratified-prelegal`. It is not the final Volume I freeze, and implementation remains gated by PM-REQ-010

## 2026-07-16 — RC1 correction programme (ADR-018)

- accepted ADR-018 authorizing the RC1 correction programme after a release-candidate review of Volume I recorded 47 defects, and deferred the successor Volume I freeze until an RC2 regression audit returns no Critical or High finding
- corrected the authority precedence in `specification/volume-i/INDEX.md` and `OWNER_DECISION_REGISTER.md`, which ranked accepted ADRs above foundation documents 000-020 and so inverted PM-REQ-003; the foundation outranks the ADR registry and an ADR does not by itself supersede an unchanged foundation requirement
- corrected the Volume I baseline identity: the current baseline is `v1.3-volume-i-corrected` at `5d725fa`, not `v1.2-volume-i-frozen`, and the status no longer claims the ADR-017 corrections are pending commit; `v1.2` and `v1.1` are superseded history and are not implementation baselines
- replaced the acceptance-gate outcome and the false "Volume II pause preserved" row, which cited two documents that state the opposite, with a conditional pass for behavioural content, a fail for freeze readiness, and an Open Defect Status section
- established stable `AI-REQ-001` through `AI-REQ-025` identifiers in `specification/008 AI_PRINCIPLES.md`, added it to the foundation traceability matrix and to Volume I's declared dependencies, and resolved OD-010's dangling `AI-REQ-005` citation; no AI policy, wording, modal force, or capability changed, and the deterministic no-AI-narrative boundary is unchanged
- brought the normative AI boundary added by `1e57f47` under ADR governance, correcting a foundation change made with no ADR in its change set contrary to ADR-006, ADR-012, and Gate D
- corrected security defects that the foundation already compelled: MFA now gates every administrative-role-capable context rather than OrganizationAdmin alone under SEC-REQ-002, and `legal_hold.manage`, `credential.rotate`, `credential.revoke`, and the SecurityOperator `organization.close` approval grant are now in the enumeration that defines protected status, matching their own baseline cells
- aligned the score-visibility contract to the Permission Baseline: an active Support Session scopes an already-permitted action and is not itself a read grant
- corrected `close_failed`, the `LifecycleDeletionJob` `Queued -> Completed` edge, the `Evidence to Citation` cardinality label, the `Check Result` severity/impact-band glossary definition, the `ScoreSnapshot` glossary spelling, the missing `IngestionQueued`/`ParsingQueued` domain events, the unassigned `operational_telemetry` backup class, the OD-004 record schema, and the OD-007/OD-008 foundation deadlines that Volume I had silently extended
- corrected three canonical diagrams that drew active Billing, Search, and AI provider edges the accepted baseline never exercises, and recorded the edge notation
- registered OD-012 through OD-032 with deterministic fail-closed interim behaviour after an adversarial derivation proved that 19 of 20 analysed behavioural defects admit more than one conformant answer and are therefore product-owner decisions, not architectural inferences; this includes the thirteen upstream blockers Volume II recorded
- closed the Crawl-keyed initial Evaluation finding as not-a-defect: a uniqueness key is not a canonical identity and the design is conformant as written

## 2026-07-16

- committed the six controlled Volume I corrections at `5d725fa` and created immutable successor tag `v1.3-volume-i-corrected` without moving `v1.2-volume-i-frozen`
- committed the two pre-existing Volume II drafts separately at `7213e9a`, then completed Implementation Architecture Pass 001 across Rails boundaries, PostgreSQL, application services, jobs, integrations, physical API/event contracts, Hotwire, security/performance, deployment/observability, search/retrieval, AI/evaluation, and testing
- withheld every physical behavior affected by thirteen newly demonstrated frozen-Volume-I ambiguities, including the undefined Credential-rotation token/material binding, reassessment-trigger event, Role-expiry-blocked event/notification, Document quarantine/retirement paths and the contradictory Issue-fingerprint collision outcome; Volume II reports those blockers and does not silently change product behavior
- corrected DEF-V1-001 by replacing impossible exactly-once Mailgun delivery implications with at-least-once application attempts, durable local submission deduplication, explicit provider-acceptance uncertainty, resend suppression, read-only reconciliation, duplicate-tolerant user behavior, acknowledged administrative replay, terminal known-failure behavior, and complete Audit Evidence
- corrected DEF-V1-002 by defining existing-Account sign-in through a purpose-bound managed-identity receipt, exact Organization and lifecycle/assurance checks, current authorization-context initialization, independent concurrent Sessions, deterministic destination selection, audited failures, and no framework-specific authentication choice
- corrected DEF-V1-003 by retaining manual reassessment and permitting scheduled reassessment only through an active Project policy with an explicit anchored cadence input, exact due-slot identity, active-run conflict suppression, inactive-scope skipping, outage coalescing, no entitlement-derived cadence, no schedule-only customer Notification, and auditable decisions
- corrected DEF-V1-004 by making atomic WF-001 self-service the sole baseline BillingEntity creation path, linking the initial Plan Assignment before activation, requiring exactly one current nonclosed entity per Organization, defining provider-independent bootstrap and closure/retention behavior, and adding no invoice or payment entity
- corrected DEF-V1-005 by establishing Evidence, Evidence Type, Evidence Source, Evidence Payload, Evidence Provenance, Evidence Classification, Measurement Evidence, Verification Evidence, and Audit Evidence as the sole canonical vocabulary and removing conflicting aliases across foundation, Volume I, and diagrams
- corrected DEF-V1-006 by aligning CAP-019 and its acceptance/traceability contracts to the frozen deterministic structured-only dashboard/history baseline with no AI narrative, placeholder, presentation region, hidden enablement, or AI-provider call
- added ADR-017 for the six demonstrated post-freeze defect corrections, paused further Volume II expansion, and retained only the two existing Volume II drafts with reference-level alignment
- resolved the final dashboard/history ambiguity by prohibiting AI-generated narrative, narrative placeholders and AI-provider calls in accepted Volume I while requiring complete deterministic structured responses
- completed the final Volume I acceptance and closure pass without beginning Volume II
- accepted Volume I as the behavioural baseline after making every pending owner decision deterministic and classifying its exact downstream blocking impact
- recorded OD-010 as a complete customer-facing numeric-score and external-measurement production gate, and OD-011 as a production customer-data and contractual-retention gate; neither blocks Volume II
- aligned onboarding, invitation, effective-permission, lifecycle, retention, logical-envelope, Check catalogue, acceptance, traceability, terminology, diagrams, and control-plane contracts
- defined the Volume II implementation-facing boundary and preserved its pause until the accepted Volume I change set is committed and tagged
- decomposed Volume I into canonical implementation-ready specification set under specification/volume-i
- added product definition with stable PR-REQ identifiers and foundation-aligned boundaries
- added capability model with CAP-001 through CAP-025 and explicit dependency/acceptance mapping
- added workflow specifications WF-001 through WF-018 with primary, alternate, failure, and recovery paths
- added product rule catalog PRULE-001 through PRULE-042 with source references and verification intent
- added conceptual score and evidence chain model from evidence through reassessment without invented numeric formulas
- added acceptance and planned test-type mapping across capabilities, workflows, and score model criteria
- added Volume I traceability matrix linking requirements, capabilities, workflows, rules, acceptance, and verification
- added canonical owner decision register OD-001 through OD-006 baseline set including provisional 013 quality threshold handling
- added independent multi-role review record with findings, resolutions, and residual risks
- updated control-plane docs to treat specification/volume-i/INDEX.md as canonical Volume I detail set while preserving Volume II pause gate
- resolved OD-004 objectively to baseline in-app plus email notification channels
- converted unresolved owner decisions to decision-ready briefs with explicit approval wording and latest-responsible decision points
- added domain-model owner decisions for citation linkage scope and billing-entity decomposition scope
- added scoring owner decision for disputed Issue score eligibility and synchronized scoring behavior artifacts
- corrected objective traceability defects in Volume I product-rule source requirement references
- added explicit Volume I acceptance checklist with pass and blocked conditions in specification/volume-i/INDEX.md

## 2026-07-15

- upgraded repository control documents: README, ROADMAP, PROJECT_STATE, DECISIONS
- expanded manual navigation and domain coverage map in specification/INDEX.md
- authored initial Product Architecture Manual Volume I
- aligned research baseline with canonical manual authority model
- extended immutable foundation layer from 000-010 to 000-020
- authored canonical foundation documents 011 through 020
- established canonical diagrams for system context, domain model, containers, components, AI pipeline, and data lifecycle
- added architecture fitness-function catalog and governance policy
- added constitutional TDD and documentation-as-code policies
- added foundation traceability matrix and dependency graph governance
- declared foundation baseline version 1.0 with controlled change policy
- completed architecture review consistency corrections across governance, terminology, and traceability
- added centralized foundation section mapping registry for structural conformance
- added ADR-014 and ADR-015 for mapping governance and canonical event naming alignment
- added ADR-016 to preserve authority precedence under intra-foundation dependency cycles
- synchronized volume, domain, observability, and container diagram terminology
