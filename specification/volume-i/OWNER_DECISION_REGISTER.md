# Volume I Owner Decision Register

## Status

- Status: Accepted register; thirty-three owner decisions comprising one resolved objectively, twenty-one ratified or resolved by owner decision on 2026-07-17 and integrated under ADR-019, one withdrawn, and ten pending with deterministic interim behaviour. OD-001 through OD-011 predate the RC1 review; OD-012 through OD-032 were registered by the RC1 correction programme under ADR-018 because the RC1 derivation proved that existing authority does not force a unique answer for them. The ten pending decisions are OD-011, OD-013, OD-014, OD-023, OD-027, OD-029, OD-030, OD-031, OD-032 and OD-033; OD-011, OD-029, OD-030 and OD-033, together with the customer-notification limb of OD-012, await qualified legal review, and OD-013 awaits an explicit Chief Architect decision. This register is not finally frozen while those gates remain open.
- Last Updated: 2026-07-17
- Owner: Chief Architect
- Foundation Version Dependency: 1.0

## Purpose

Capture owner-level decisions required to finalize Volume I without silently resolving policy choices.

Two distinct orderings apply, and they must not be conflated.

**Authority precedence** is fixed by PM-REQ-003 in [../001 PRODUCT_ARCHITECTURE_MANUAL.md](../001%20PRODUCT_ARCHITECTURE_MANUAL.md): constitution and governance, then foundation layer 000 through 020, then the ADR registry, then Volume specifications, then derived implementation artifacts. This register and every decision in it is a Volume specification artifact at rank 4. An accepted ADR never outranks an unchanged foundation requirement. An owner decision cannot override a foundation requirement, and an option whose approval would conflict with one requires the PM-REQ-009 controlled foundation change before it may be approved.

**Evidence preference** is the separate ordering used when weighing inputs to an owner decision, applied only where the authority precedence above does not already settle the question:

1. Foundation documents 000 through 020
2. Accepted ADRs
3. Canonical research and business-case material
4. Roadmap and project-state documents
5. Supporting notes

PM-REQ-003 assigns no authority rank to canonical research, business-case material, roadmap, project-state, or supporting notes, and no foundation document grants them one. They carry evidentiary weight only. None of them overrides a normative Volume I contract, and this evidence ordering never inverts the authority precedence above.

## Classification Keys

- A: Objectively resolvable
- B: Evidence-preferred
- C: Strategic owner decision
- D: Premature decision

## Conflict Log

| Conflict ID | Sources In Conflict | Resolution Rule Applied | Outcome |
| --- | --- | --- | --- |
| ODCF-001 | OD-006 Option 1 hard-only enforcement vs QA-REQ-010 requiring hard and soft limits | Foundation quality requirement precedence | Option 1 is treated as unsupported unless soft-limit behavior is also documented. |
| ODCF-002 | Non-normative research note naming Postmark vs product-owner direction on 2026-07-16 selecting Mailgun | Current explicit owner direction governs the Volume I provider selection while foundation provider boundaries remain unchanged | Mailgun is the baseline email provider through a versioned adapter; Postmark is not baseline. |

## Decisions Resolved Objectively

### OD-004 Notification Channel Baseline

- Decision ID: OD-004
- Exact Question: Which outbound channels are in baseline support scope for actionable notifications?
- Classification: A
- Current Status: Resolved objectively on 2026-07-16
- Why The Decision Exists: Baseline channel scope must align with boundary and provider assumptions before implementation.
- Affected Capabilities: CAP-021
- Affected Workflows: WF-014
- Affected Product Rules: PRULE-034
- Affected Foundation Requirements: SB-REQ-008, SB-REQ-017, OBS-REQ-019
- Affected Volume I Requirements: PR-REQ-025
- Affected Acceptance Criteria: AC-CAP-021, AC-WF-014, AC-PRULE-034; all are already deterministic under the resolved baseline and none remains owner-gated by OD-004.
- Options Considered:
  1. In-app notifications only.
  2. In-app plus email.
  3. In-app, email, and webhook callbacks.
- Resolved Option: Option 2
- Selected Baseline Email Provider: Mailgun through adapter policy `mailgun-email-v1`; Postmark is excluded from baseline.
- Evidence Supporting Resolution:
  - [../012 SYSTEM_BOUNDARIES.md](../012%20SYSTEM_BOUNDARIES.md) requires an email and notification provider class in baseline scope.
  - [PRODUCT_DEFINITION.md](PRODUCT_DEFINITION.md) establishes external provider assumptions for notifications.
  - No accepted authority requires webhook callbacks in baseline scope.
- ADR Threshold: Not met for Option 2 because this resolution aligns with accepted baseline authority. ADR required only if baseline changes to Option 1 or Option 3.
- Owner Required: None; objective closure by authority alignment.
- Blocking Impact: None. OD-004 is resolved and blocks neither Volume II, implementation, production use, nor baseline notification behavior.
- Deterministic Delivery Behavior: WF-014 and `notification-policy-v1` define routing, authorization, redaction, at-least-once application attempt processing, local attempt deduplication, no provider exactly-once claim, acceptance-unknown state, definitive-nonacceptance-only retry, read-only reconciliation, user-visible duplicate tolerance, acknowledged administrative replay, bounce, aggregate status, Audit Evidence, and escalation. Channel resolution alone does not permit unspecified delivery behavior.

## Pending Decision Briefs

### OD-001 Verification Method Set

- Decision ID: OD-001
- Exact Question: Which verification methods are approved for source ownership or control verification in baseline scope?
- Classification: B
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; ratified as specified
- Approved Option: Option 2 — DNS TXT and HTTPS file source-ownership verification
- Why The Decision Exists: Verification channels affect onboarding friction and security exposure.
- Affected Capabilities: CAP-005
- Affected Workflows: WF-003
- Affected Product Rules: PRULE-005, PRULE-020
- Affected Foundation Requirements: SEC-REQ-010, SEC-REQ-011, SM-REQ-002, SM-REQ-003, SB-REQ-010
- Affected Acceptance Criteria: AC-CAP-005, AC-WF-003, AC-PRULE-005, AC-PRULE-020, AC-SM-008
- Options:
  1. DNS record verification only.
  2. DNS plus HTTP file verification.
  3. DNS, HTTP file, and meta-tag verification.
- Recommended Option: Option 2
- Evidence Supporting The Recommendation:
  - Source activation is state-gated and cannot bypass verification pathways.
  - Security model requires explicit administrative controls and auditable workflows for boundary-sensitive operations.
  - Baseline scope and operational simplicity are preserved without adding a third verification surface.
- Benefits: Balanced onboarding and security posture; lower implementation and support complexity than Option 3.
- Costs: Slightly higher onboarding friction than Option 3.
- Risks: Option 1 may reduce successful onboarding; Option 3 expands policy and abuse surfaces.
- Security Implications: Verification method expansion increases spoofing and misuse surface area.
- Data Implications: Each method introduces additional evidence payload handling and retention obligations.
- AI Implications: None directly.
- Operational Implications: Support runbooks and incident handling expand with each additional method.
- Commercial Implications: Onboarding conversion can be impacted by method friction.
- Reversibility: Medium; method policy can change but requires workflow, controls, and support updates.
- Ratified Behavior: DNS TXT and HTTPS file methods are allowed; every field, location, exact-match predicate, 24-hour lifetime, attempt schedule, timeout, idempotency rule, Source state outcome, retained Evidence field, and recovery path is mandatory under [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md#ownership-verification-evidence-contract). Other methods are blocked.
- Latest Responsible Decision Point (met on 2026-07-17): Before Volume IV acceptance.
- Blocking Impact: None. OD-001 is ratified; the DNS TXT and HTTPS file method set is the approved baseline and blocks neither Volume II, implementation, production use, nor baseline verification behaviour. Methods outside the approved set are out of baseline scope rather than blocked pending approval.
- ADR Threshold: Not met. The approved method set is identical to the previously specified behaviour and changes no security threat assumption. The decision is recorded in ADR-019.
- Owner Required: Chief Architect
- Approval Record: Ratified in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). Integrated by ADR-019.

### OD-002 Discoverability Score Weight Distribution

- Decision ID: OD-002
- Exact Question: What is the final weight distribution across Discoverability Score pillars?
- Classification: C
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; ratified as specified
- Approved Option: Option 1 — equal weighting of applicable score pillars as the Version 1 baseline scoring policy
- Why The Decision Exists: Weighting changes product interpretation, commercial expectations, and prioritization behavior.
- Affected Capabilities: CAP-015, CAP-017, CAP-018
- Affected Workflows: WF-008, WF-010, WF-012
- Affected Product Rules: PRULE-024, PRULE-025, PRULE-028, PRULE-029, PRULE-032, PRULE-045
- Affected Foundation Requirements: QA-REQ-001, VER-REQ-014, DM-REQ-015
- Affected Acceptance Criteria: AC-CAP-015, AC-CAP-017, AC-CAP-018, AC-WF-008, AC-WF-010, AC-WF-012, AC-PRULE-024, AC-PRULE-025, AC-PRULE-028, AC-PRULE-029, AC-PRULE-032, AC-PRULE-045, AC-SM-002
- Options:
  1. Equal pillar weighting.
  2. Product-priority weighted distribution by pillar.
  3. Segment-adaptive weighting with policy constraints.
- Recommended Option: Option 2
- Evidence Supporting The Recommendation:
  - Product principles require economic and explainable prioritization.
  - Current Volume I scope targets one baseline model before segment-specialized expansion.
  - Versioning requirements already mandate explicit model-version lineage.
- Benefits: Clear baseline behavior with explainable governance and manageable change control.
- Costs: Less segment customization than Option 3.
- Risks: Poorly chosen weights can bias prioritization and customer interpretation.
- Security Implications: None direct; indirect trust impact if weighting is opaque.
- Data Implications: Requires stable score model version and migration handling.
- AI Implications: AI explanations must reflect deterministic score semantics.
- Operational Implications: Requires regression and compatibility controls for score changes.
- Commercial Implications: Direct impact on perceived product value and packaging differentiation.
- Reversibility: Medium; reversible with version migration and communication plan.
- Ratified Behavior: Apply `score-policy-v1`: equal exact rational weight across applicable pillars, exact penalty/contribution and applicability rules, base-10 score arithmetic, round-half-up to one decimal, clamping, completeness behavior, immutable snapshots, and normative fixtures in [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md#interim-discoverability-score-policy).
- Latest Responsible Decision Point (met on 2026-07-17): Before Volume V commercial architecture acceptance.
- Blocking Impact: None. OD-002 is ratified; equal weighting of applicable pillars is the approved Version 1 scoring policy. Any later weighting change requires a new scoring-policy version and MUST NOT reinterpret historical Score Snapshots.
- ADR Threshold: Met; this decision is recorded in ADR-019.
- Owner Required: Chief Product
- Approval Record: Ratified in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). Integrated by ADR-019.

### OD-003 Confidence Band Definitions For Prioritization

- Decision ID: OD-003
- Exact Question: What canonical confidence-band model should recommendation prioritization use?
- Classification: D
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; ratified as specified
- Approved Option: Option 3 — numeric confidence `0.0000`-`1.0000` with displayed Low/Medium/High bands
- Why The Decision Exists: Confidence semantics affect ranking behavior and user trust.
- Affected Capabilities: CAP-010, CAP-015, CAP-017
- Affected Workflows: WF-007, WF-008, WF-010
- Affected Product Rules: PRULE-012, PRULE-024, PRULE-025, PRULE-028, PRULE-029, PRULE-032, PRULE-045
- Affected Foundation Requirements: QA-REQ-002, VER-REQ-014, ENG-REQ-010
- Affected Acceptance Criteria: AC-CAP-010, AC-CAP-015, AC-CAP-017, AC-WF-007, AC-WF-008, AC-WF-010, AC-PRULE-012, AC-PRULE-024, AC-PRULE-025, AC-PRULE-028, AC-PRULE-029, AC-PRULE-032, AC-PRULE-045, AC-SM-002
- Options:
  1. Three-band model (Low, Medium, High).
  2. Four-band model (Low, Medium, High, Very High).
  3. Numeric confidence value with displayed bands.
- Recommended Option: Option 3
- Evidence Supporting The Recommendation:
  - Existing artifacts already preserve confidence metadata for downstream decisions.
  - Versioning and reproducibility controls support internal numeric precision with stable display mapping.
  - Deterministic prioritization requires explicit policy versioning and stable translation from confidence inputs.
- Benefits: Internal precision with user-friendly presentation.
- Costs: Additional policy definition and calibration effort.
- Risks: Premature calibration can create false precision.
- Security Implications: None direct.
- Data Implications: Requires durable confidence metadata and mapping version capture.
- AI Implications: AI-derived confidence must not bypass deterministic policy mapping.
- Operational Implications: Needs calibration reviews and drift monitoring.
- Commercial Implications: Impacts how strongly recommendations are trusted by buyers and operators.
- Reversibility: High with policy-versioned display mappings.
- Ratified Behavior: Persist confidence on `0.0000..1.0000` using round-half-up to four decimals and policy `confidence-policy-v1`; display Low for `[0.0000,0.6000)`, Medium for `[0.6000,0.8500)`, and High for `[0.8500,1.0000]`. Missing or invalid confidence is recorded explicitly, displays Low, and routes the Issue to review_required.
- Latest Responsible Decision Point (met on 2026-07-17): Before Volume V commercial architecture acceptance and after at least two full reassessment cycles.
- Blocking Impact: None. OD-003 is ratified; numeric confidence with displayed Low/Medium/High bands is approved baseline behaviour.
- ADR Threshold: Not met. The approved confidence policy changes no score or prioritization semantics. The decision is recorded in ADR-019.
- Owner Required: Chief Product
- Approval Record: Ratified in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). Integrated by ADR-019.

### OD-005 Provisional Quality Threshold Finalization

- Decision ID: OD-005
- Exact Question: Which final values and acceptance gates should replace provisional QA thresholds?
- Classification: D
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; ratified as specified
- Approved Option: No option number — QA and operational thresholds are approved subject to the commercial clarification; numeric values are versioned policy configuration bound to an approved policy version rather than immutable Volume I constants.
- Why The Decision Exists: Foundation quality requirements intentionally use provisional ranges pending measured baseline telemetry.
- Affected Capabilities: CAP-007, CAP-008, CAP-015, CAP-024
- Affected Workflows: WF-005, WF-008, WF-011, WF-015
- Affected Product Rules: PRULE-008, PRULE-009, PRULE-024, PRULE-025, PRULE-039, PRULE-040, PRULE-045
- Affected Foundation Requirements: QA-REQ-001 through QA-REQ-007, QA-REQ-009, QA-REQ-010, QA-REQ-021 through QA-REQ-025
- Affected Acceptance Criteria: AC-CAP-007, AC-CAP-008, AC-CAP-015, AC-CAP-024, AC-WF-005, AC-WF-008, AC-WF-011, AC-WF-015, AC-PRULE-008, AC-PRULE-009, AC-PRULE-024, AC-PRULE-025, AC-PRULE-039, AC-PRULE-040, AC-PRULE-045, AC-SM-002
- Options:
  1. Accept provisional thresholds as final.
  2. Adjust thresholds using measured baseline telemetry.
  3. Redefine threshold model by service class.
- Recommended Option: Option 2
- Evidence Supporting The Recommendation:
  - Foundation requires provisional thresholds to resolve before release gates, not immediately.
  - Quality verification requirements require evidence-backed thresholds with retained telemetry.
  - Architectural fitness policy explicitly supports provisional gates with owner deadlines.
- Benefits: Evidence-backed targets and lower false-precision risk.
- Costs: Requires structured measurement and review cycles before closure.
- Risks: Decision delay can block downstream acceptance gates.
- Security Implications: RTO and reliability choices affect incident and response posture.
- Data Implications: RPO and durability choices affect lifecycle controls and restore obligations.
- AI Implications: AI quality and latency thresholds constrain model/provider behavior.
- Operational Implications: Breach policies and escalation paths must be rehearsed before finalization.
- Commercial Implications: Cost and availability commitments shape package viability and enterprise commitments.
- Reversibility: Medium; threshold changes are possible with governance but may require contract or gate updates.
- Ratified Behavior: The QA and operational threshold model is approved as the Volume I baseline. Foundation threshold values are versioned policy configuration bound to an approved policy version rather than immutable Volume I product constants: Volume I fixes what is measured, when the gate is evaluated and how it behaves, and a numeric change is a policy-version change rather than a Volume I revision. For product behaviour that cannot safely remain unbounded, the `crawl-policy-v1` soft and hard bounds and the exact limit-hit contract in WF-005 apply until a superseding policy version activates. Existing numeric values remain valid as the approved current policy version or as test fixtures and MUST NOT be read as permanent product invariants.
- Latest Responsible Decision Point (met on 2026-07-17): Each threshold by its foundation deadline and gate.
- Blocking Impact: None for Volume I. OD-005 is ratified subject to the commercial clarification: threshold numerals are versioned policy configuration, so changing a value is a policy-version change rather than a Volume I revision or a release gate.
- ADR Threshold: Met; this decision is recorded in ADR-019.
- Owner Required: Mixed per QA owner in table below.
- Approval Record: Ratified in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). Integrated by ADR-019.

#### OD-005 Sub-Decision Matrix

| Sub-Decision | Requirement Type | Metric | Measurement Point | Sampling Method | Test Environment | Owner | Gate | Review Milestone | Breach Behavior |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OD-005A (QA-REQ-001 Availability) | Operational target plus release gate | Monthly uptime percent | Edge synthetic checks plus request telemetry | 1-minute synthetic checks and rolling monthly aggregation | Production and pre-release synthetic path validation | Chief Rails | Volume III acceptance | 2026-08-15 quality review | Trigger reliability incident and release hold when below approved threshold |
| OD-005B (QA-REQ-002 Reliability) | Operational target plus release gate | Failed critical workflow rate per 7 days | Workflow completion telemetry | 7-day rolling window over critical workflow set | Production plus replayed failure scenarios | Chief Rails | Volume III acceptance | 2026-08-15 quality review | Trigger corrective action plan and release hold for sustained breach |
| OD-005C (QA-REQ-003 RTO) | Architecture and operations requirement | Restore duration for critical service | Incident timeline records | Per-incident measurement with quarterly drill summary | Staging and controlled production incident drills | Chief Security | Operations architecture sign-off | 2026-08-20 operations review | Escalate to critical operations review and block sign-off |
| OD-005D (QA-REQ-004 RPO) | Data lifecycle requirement | Maximum recoverable data loss window | Backup and restore verification logs | Per-drill and per-incident measurement | Staging restore drills and sampled production verification | Chief Rails | Data lifecycle sign-off | 2026-08-20 data review | Suspend destructive changes and require backup remediation |
| OD-005E (QA-REQ-005 API Latency) | Architecture and performance requirement | p95 synchronous request latency | Route-level distributed traces | 5-minute windows with route histogram aggregation | Staging load tests and production telemetry | Chief Rails | Volume IV API acceptance | 2026-08-20 API review | Rate-limit non-critical workloads and hold API gate |
| OD-005F (QA-REQ-006 Background Latency) | Architecture and performance requirement | p95 evaluation-job completion latency | Queue duration and job completion telemetry | Hourly aggregation with p95 trend checks | Staging workload replay and production queue telemetry | Chief Rails | Volume IV acceptance | 2026-08-25 background job review | Prioritize backlog remediation and suspend scale-down actions |
| OD-005G (QA-REQ-007 Throughput) | Architecture capacity requirement | Sustained onboarding and monitoring throughput | Capacity telemetry by workflow | Fixed-duration load tests and production peak-window sampling | Staging stress tests plus production peak analysis | Chief Architect | Volume III acceptance | 2026-08-25 capacity review | Capacity incident escalation and gate hold |
| OD-005H (QA-REQ-009 Cost Constraint) | Commercial requirement plus finance gate | Cost per workflow and organization against budget envelope | Cost telemetry and finance rollups | Weekly rollup and monthly budget-cycle review | Production telemetry and finance reconciliation | Chief Product | Volume V finance gate | 2026-08-30 finance review | Trigger packaging review and non-essential feature freeze |
| OD-005I (QA-REQ-010 Capacity Limits) | Per-workflow safety and package constraint | Soft/hard limit value, unit, scope, and limit-hit outcome for every bounded workflow | Policy snapshots, limit counters, and boundary-fixture results | Every policy version plus rolling weekly limit-hit distribution | Deterministic boundary fixtures and production telemetry | Chief Rails | Volume III acceptance | 2026-08-30 capacity review | Retain the conservative interim bound, block increases, and hold the gate until an evidenced replacement is approved |

### OD-006 Entitlement Enforcement And Grace Policy

- Decision ID: OD-006
- Exact Question: Which entitlement-enforcement policy applies when usage crosses plan limits?
- Classification: C
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; ratified as specified
- Approved Option: Option 3 as implemented — entitlement enforcement semantics, subject to the commercial clarification
- Why The Decision Exists: Entitlement behavior sets customer experience, risk tolerance, and commercial policy.
- Affected Capabilities: CAP-024
- Affected Workflows: WF-015
- Affected Product Rules: PRULE-039, PRULE-040, PRULE-045
- Affected Foundation Requirements: QA-REQ-010, SB-REQ-014, SEC-REQ-005, SEC-REQ-006
- Affected Acceptance Criteria: AC-CAP-024, AC-WF-015, AC-PRULE-039, AC-PRULE-040, AC-PRULE-045
- Options:
  1. Immediate hard block at limit.
  2. Time-bound grace window with warning and escalation.
  3. Progressive degradation by operation type.
- Recommended Option: Option 2
- Evidence Supporting The Recommendation:
  - Hard and soft limit behavior is a constitutional quality requirement.
  - Product principles emphasize predictable value and actionable guidance over surprise breakage.
  - Security and audit requirements require explicit, server-side, auditable policy enforcement.
- Benefits: Supports continuity while maintaining controlled enforcement.
- Costs: Additional policy complexity and communication requirements.
- Risks: Poorly bounded grace windows can erode cost controls.
- Security Implications: Grace policy must not bypass server-side authorization and audit obligations.
- Data Implications: Requires durable usage counter and policy-state recording.
- AI Implications: None direct.
- Operational Implications: Requires reliable overage telemetry and escalation operations.
- Commercial Implications: Directly affects retention, upgrade conversion, and margin control.
- Reversibility: Medium; policy changes affect customer expectations and support workflows.
- Ratified Behavior: High-cost operations are crawl start, reassessment start, AI generation, and export generation; they hard-block only when committed plus active-reserved plus requested units would exceed the active hard limit, while equality is allowed, after an atomic server-side check/reservation. Low-cost report, history, Issue, recommendation, and score reads remain warning-only at the usage hard limit while the Organization and human Account or tenant service identity remain active. The exact multi-operation policy, negative/cached Decision fields, resolved reservation/lease, nested-operation, commit/release, queued recheck, outage, replay, and linked-retry behavior is defined in WF-015.
- Latest Responsible Decision Point (met on 2026-07-17): Before commercial packaging finalization.
- Blocking Impact: None. OD-006 is ratified; entitlement enforcement semantics are approved, with soft-limit and hard-limit behaviour deterministic and numeric thresholds held as versioned policy configuration.
- ADR Threshold: Not met for the approved option, which changes no package behaviour or quality gate assumption. The decision is recorded in ADR-019.
- Owner Required: Chief Product
- Approval Record: Ratified in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). Integrated by ADR-019.

### OD-007 Citation Linkage Scope

- Decision ID: OD-007
- Exact Question: Should Citation support many-to-many linkage to Evaluation and AIResponse simultaneously?
- Classification: B
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; ratified as specified
- Approved Option: Option 1 — one-directional Citation: exactly one AIResponse, exactly one Evidence, no direct Evaluation write link
- Why The Decision Exists: Foundation domain model marks this as unresolved and downstream evidence traceability depends on the linkage policy.
- Affected Capabilities: CAP-012, CAP-013
- Affected Workflows: WF-009
- Affected Product Rules: PRULE-014, PRULE-027
- Affected Foundation Requirements: DM-REQ-019, DM-REQ-009, DM-REQ-011, VER-REQ-014
- Affected Acceptance Criteria: AC-CAP-012, AC-CAP-013, AC-WF-009, AC-PRULE-014, AC-PRULE-027, AC-SM-001
- Options:
  1. Keep Citation linked through AIResponse context only.
  2. Introduce many-to-many Citation linkage to both Evaluation and AIResponse.
  3. Keep current model and add denormalized read-model projection only.
- Recommended Option: Option 1 for baseline, with Option 3 allowed for read-model projection if needed.
- Evidence Supporting The Recommendation:
  - Accepted aggregate model already places AIResponse and Citation lineage under recommendation flow.
  - Cross-aggregate write expansion would increase orchestration complexity.
  - Current score and recommendation traceability can be satisfied without many-to-many writes.
- Benefits: Preserves aggregate clarity and reduces coordination complexity.
- Costs: Some analytical queries may require projection or traversal.
- Risks: Direct evaluation-link analytics may require additional read-model work.
- Security Implications: Fewer linkage pathways reduce unauthorized relationship mutation risk.
- Data Implications: Preserves lineage stability and avoids many-to-many mutation complexity in core domain.
- AI Implications: Citation grounding remains tied to AI output context.
- Operational Implications: Simpler incident and audit reconstruction paths.
- Commercial Implications: Minimal direct impact.
- Reversibility: Medium; adding many-to-many later is possible with ADR and migration planning.
- Ratified Behavior: Apply `citation-policy-v1` in [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md#airesponse-and-citation-contract-citation-interim-v1). Each Citation has exactly one AIResponse and one Evidence parent, no direct Evaluation write link, the exact logical fields and full-preimage fingerprint, idempotent replay/collision behavior, exhaustive state/reason transitions, origin-Issue Evidence-lineage validation, and complete claim coverage before AIResponse validation or Artifact publication. Evaluation traversal is read-only through Recommendation origin Issue and Check/Evidence; an optional denormalized read projection has no write authority.
- Latest Responsible Decision Point (met on 2026-07-17): 2026-08-01, the exact deadline fixed by DM-REQ-019 in [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md), and before Volume IV acceptance. The foundation deadline governs; a volume gate may not extend it, and lapsing it is a governance breach rather than a deferral.
- Blocking Impact: None. OD-007 is ratified; the one-directional Citation contract is the approved baseline.
- ADR Threshold: Not met. Option 1 was approved. The decision is recorded in ADR-019.
- Owner Required: Chief Architect
- Approval Record: Ratified in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). Integrated by ADR-019.

### OD-008 BillingEntity Decomposition Scope

- Decision ID: OD-008
- Exact Question: Should BillingEntity include invoice and payment sub-entities in core domain or remain adapter-level?
- Classification: C
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; ratified as specified
- Approved Option: Option 2 — BillingEntity core with invoice and payment detail adapter-level
- Why The Decision Exists: Foundation domain model marks this as unresolved and the outcome changes commercial-domain scope.
- Affected Capabilities: CAP-024
- Affected Workflows: WF-015
- Affected Product Rules: PRULE-039, PRULE-040
- Affected Foundation Requirements: DM-REQ-019, SB-REQ-017, SB-REQ-018, QA-REQ-009
- Affected Acceptance Criteria: AC-CAP-024, AC-WF-015, AC-PRULE-039, AC-PRULE-040
- Options:
  1. Add invoice and payment sub-entities to core domain now.
  2. Keep BillingEntity core and retain invoice/payment detail in adapters.
  3. Hybrid model with invoice summary in core and payment detail in adapters.
- Recommended Option: Option 2
- Evidence Supporting The Recommendation:
  - Baseline boundaries favor buying commodity billing capabilities.
  - Current Volume I scope does not require invoice-level domain behavior for discoverability workflows.
  - Core-domain expansion increases persistence and lifecycle complexity without immediate product need.
- Benefits: Keeps baseline scope focused and reduces commercial-domain complexity.
- Costs: Fine-grained billing behavior remains outside core-domain model.
- Risks: Future enterprise billing requirements may require domain expansion.
- Security Implications: Adapter-level handling keeps payment-sensitive data outside expanded core pathways.
- Data Implications: Limits core-domain retention and lifecycle burden for billing detail.
- AI Implications: None direct.
- Operational Implications: Simpler baseline support and change management.
- Commercial Implications: Enables packaging now while deferring deeper billing architecture.
- Reversibility: Medium; can be expanded later with ADR and migration planning.
- Ratified Behavior: WF-001 always creates the core baseline BillingEntity pending, links its same-Organization Plan Assignment, and activates it before Organization activation without a provider call. Keep invoice and payment details adapter-level. OD-008 controls only future decomposition of those details and does not gate or alter BillingEntity creation, identity, linkage, lifecycle, retention, or entitlement use.
- Latest Responsible Decision Point (met on 2026-07-17): 2026-08-15, the exact deadline fixed by DM-REQ-019 in [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md), and before Volume V commercial architecture acceptance. The foundation deadline governs; a volume gate may not extend it, and lapsing it is a governance breach rather than a deferral.
- Blocking Impact: None. OD-008 is ratified; adapter-level billing detail and the current BillingEntity scope are approved. No invoice or payment sub-entity is introduced.
- ADR Threshold: Not met. Option 2 was approved. The decision is recorded in ADR-019.
- Owner Required: Chief Product
- Approval Record: Ratified in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). Integrated by ADR-019.

### OD-009 Disputed Issue Score Eligibility

- Decision ID: OD-009
- Exact Question: Should Issues flagged as review_required or disputed contribute to score and prioritization before adjudication?
- Classification: B
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; ratified as specified
- Approved Option: Option 2 — disputed and review-required Issues excluded from published scoring and prioritisation until eligible
- Why The Decision Exists: Current scoring chain requires deterministic score eligibility rules to avoid implementation ambiguity.
- Affected Capabilities: CAP-014, CAP-015, CAP-017
- Affected Workflows: WF-007, WF-008, WF-010, WF-012
- Affected Product Rules: PRULE-025, PRULE-027, PRULE-029, PRULE-032, PRULE-043
- Affected Foundation Requirements: QA-REQ-002, SM-REQ-003, VER-REQ-014, DM-REQ-011
- Affected Acceptance Criteria: AC-CAP-014, AC-CAP-015, AC-CAP-017, AC-WF-007, AC-WF-008, AC-WF-010, AC-WF-012, AC-PRULE-025, AC-PRULE-027, AC-PRULE-029, AC-PRULE-032, AC-PRULE-043, AC-SM-002, AC-SM-004, AC-SM-005
- Options:
  1. Include disputed Issues with reduced contribution.
  2. Exclude disputed Issues until adjudication.
  3. Include disputed Issues but mark uncertainty in score output.
- Recommended Option: Option 2
- Evidence Supporting The Recommendation:
  - Deterministic and explainable scoring is a baseline requirement.
  - Confidence and quality controls already require explicit validation before downstream decisions.
  - Exclusion prevents score volatility from unresolved adjudication states.
- Benefits: Maximizes explainability and determinism.
- Costs: Potentially delays score reflection for emerging issues.
- Risks: Backlog in adjudication can temporarily suppress true impact.
- Security Implications: None direct.
- Data Implications: Requires explicit Issue lifecycle, adjudication, publication, state-version, and timestamp fields.
- AI Implications: AI recommendations must not override adjudication-state policy.
- Operational Implications: Requires support and operator adjudication workflow discipline.
- Commercial Implications: Improves trust in score stability but may reduce perceived responsiveness.
- Reversibility: High with versioned scoring policy.
- Ratified Behavior: Apply the Issue eligibility predicate in [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md#score-contribution-contract). Candidate, review_required, disputed, in_review, terminal, superseded, and non-current Issues receive zero score and priority contribution. Upheld or withdrawn current open Issues become eligible; rejected Issues remain ineligible. Every eligibility change creates or reuses an immutable ScoreSnapshot and deterministically suppresses or republishes governed recommendations.
- Latest Responsible Decision Point (met on 2026-07-17): Before Volume IV acceptance.
- Blocking Impact: None. OD-009 is ratified; disputed and review-required Issues are excluded from published scoring and prioritisation until eligible, deterministically across rules, workflows and acceptance criteria.
- ADR Threshold: Not met. Disputed Issues are excluded from score before adjudication. The decision is recorded in ADR-019.
- Owner Required: Chief Product and Chief Architect
- Approval Record: Ratified in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). Integrated by ADR-019.

### OD-010 Baseline Check Catalog And Measurement Scope

- Decision ID: OD-010
- Exact Question: Which measured signals, external observation channels, applicability rules, pass/fail thresholds, impact mappings, and default remediation/effort semantics form the owner-approved baseline Check Catalog?
- Classification: C
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; ratified as specified
- Approved Option: Option 1 — the seven-check baseline catalogue, thresholds, impact mappings and measurement contracts
- Why The Decision Exists: A score requires at least one deterministic score-capable Check for every applicable pillar; selecting what the product measures and what constitutes a deficiency is product strategy, not an architectural inference.
- Affected Capabilities: CAP-009, CAP-010, CAP-011, CAP-015, CAP-016, CAP-017
- Affected Workflows: WF-007, WF-008, WF-009, WF-010, WF-011
- Affected Product Rules: PRULE-010 through PRULE-013, PRULE-024 through PRULE-026, PRULE-028, PRULE-029
- Affected Foundation Requirements: DM-REQ-009, DM-REQ-011, SM-REQ-003, VER-REQ-014, QA-REQ-010, AI-REQ-002, AI-REQ-005, AI-REQ-011
- Foundation Requirement Basis Note: this brief originally cited `AI-REQ-005` at a time when [../008 AI_PRINCIPLES.md](../008%20AI_PRINCIPLES.md) defined no requirement identifiers, so the token had no referent and the intended requirement cannot be established from repository evidence. Under the identifier convention now defined in that document, the citation set above is derived from this brief's own stated AI and Security Implications rather than from an assumed ordinal: `AI-REQ-002` (AI outputs affecting customer guidance must pass deterministic policy and schema checks) governs the rule that AI-presence observation is measurement input only; `AI-REQ-005` (unsafe or policy-violating outputs blocked before presentation) governs reducing external provider responses to validated immutable Measurement Evidence before Check execution and failing closed on missing, stale, indeterminate, or cross-tenant input; and `AI-REQ-011` (AI outputs are advisory artifacts, not autonomous writes) governs the rule that AI-presence observation cannot supply a product recommendation or alter another Check. Chief AI and Chief Architect MUST confirm this basis set when OD-010 is approved; it is a traceability correction and changes no OD-010 behaviour, option, or interim.
- Affected Acceptance Criteria: AC-CAP-009, AC-CAP-010, AC-CAP-011, AC-CAP-015, AC-CAP-016, AC-CAP-017, AC-WF-007, AC-WF-008, AC-WF-009, AC-WF-010, AC-WF-011, AC-PRULE-010, AC-PRULE-011, AC-PRULE-012, AC-PRULE-013, AC-PRULE-024, AC-PRULE-025, AC-PRULE-026, AC-PRULE-028, AC-PRULE-029, AC-SM-001, AC-SM-002, AC-SM-003
- Options:
  1. Approve the seven-definition provider-neutral baseline in `check-catalog-v1`.
  2. Approve an expanded or provider-bound catalog with separately supplied definitions, channels, thresholds, impact, effort, and fixtures.
  3. Defer catalog activation and ship no score or recommendation publication until a later owner-approved catalog exists.
- Recommended Option: Option 1, replacing individual interim values only through a complete immutable successor catalog.
- Evidence Supporting The Recommendation:
  - Seven applicable score pillars require at least seven single-pillar Check Definitions.
  - One minimal definition per pillar removes implementation disagreement without promoting the non-normative research inventory into product scope.
  - Provider-neutral frozen observations preserve deterministic evaluation while keeping provider procurement replaceable.
- Benefits: Makes the baseline Evaluation, score-coverage, Issue, recommendation, and acceptance paths executable now.
- Costs: The minimal catalog intentionally supplies only one score-capable signal per pillar and may not match final commercial differentiation.
- Risks: Interim thresholds can shape early customer expectations; every output therefore retains catalog/definition/policy versions.
- Security Implications: External provider responses are reduced to validated immutable Measurement Evidence before Check execution; Checks make no network call and fail closed on missing, stale, indeterminate, or cross-tenant input.
- Data Implications: Requires exact subject, applicability, Evidence, freshness, and version lineage on every Check Result.
- AI Implications: AI-presence observation is measurement input only; it cannot supply a product recommendation or alter another Check.
- Operational Implications: External observation collection must either satisfy `external-observation-v1` or produce the catalog-defined `error` result and unavailable score.
- Commercial Implications: Final catalog breadth, provider selection, and thresholds remain owner-controlled packaging choices.
- Reversibility: High through immutable catalog/definition versions and reassessment; historical results never mutate.
- Ratified Behavior: Activate exact `check-catalog-v1` with `CHK-TI-001`, `CHK-CQ-001`, `CHK-TR-001`, `CHK-SP-001`, `CHK-AIP-001`, `CHK-AS-001`, and `CHK-LP-001` as defined in [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md). Bind tenant Source/subject instances only in each frozen Evaluation Applicability Set. `external-measurement-v1` bundles no query, intent, listing, provider, or adapter set before approval, so implementations do not invent one: the three always-applicable external entries for `CHK-SP-001`, `CHK-AIP-001`, and `CHK-AS-001` persist handled `input_evidence_missing` errors; `CHK-LP-001` does the same only when its frozen applicability decision is true and otherwise persists its canonical `not_applicable` Result. The numeric score therefore remains unavailable. An approved Measurement Set later activates as exact signed configuration and accepts only exact frozen provider-neutral Measurement Evidence before snapshot sealing; Check execution still makes no provider call. A missing/invalid catalog fails Evaluation before Check side effects; handled missing/stale/indeterminate observations create no Issue. No Recommendation or Priority Decision publishes from an unavailable calculation.
- Required Owner Approval Package: OD-010 approval is valid only for one immutable Measurement Set package whose owner-supplied content includes all of the following; omission leaves the no-set safe interim active and authorizes no inferred value:
  - package identity, schema version, immutable version, complete canonical bytes, SHA-256 of those exact bytes, predecessor or null, creation time, and proposed effective time
  - the exact provider identities and allowed measurement kinds, plus each bound collector adapter ID, immutable adapter version and digest, and deterministic provider-selection/fallback order when more than one provider is allowed
  - the complete ordered search-query keys and exact query text, AI-intent keys and exact intent content, authority-reference collection scope/selection rules, and required local-listing keys with their exact canonical business-profile field source and version
  - every applicability rule and exact pass/fail/error, impact, confidence, effort, and score-contribution threshold, either by binding unchanged immutable Check Definition/Catalog digests or by supplying an immutable successor definition package
  - activation prerequisites, exact effective-time rule, currently active predecessor, failure outcome, and the rule that rollback is activation of a separately approved immutable successor package rather than mutation or reactivation of unapproved bytes
  - separate signatures from Chief Product and Chief Architect over the same package SHA-256, with signer identity, authority, signed time, and decision; one signature or signatures over different bytes do not authorize activation
  - the pinning rule that every Evaluation records the Measurement Set, Catalog, Definition, provider, and adapter identities/versions/digests it consumed, plus the retention/access location for the exact approved canonical bytes needed to reproduce that Evaluation
- Latest Responsible Decision Point (met on 2026-07-17): Before Volume I catalog values become a customer contractual claim.
- Blocking Impact: None. OD-010 is ratified; the Version 1 check catalogue, measurement contract, thresholds, impact mappings and effort semantics are approved. The catalogue is not broadened by this ratification.
- ADR Threshold: Not met. The approved model permits no Check to contribute to multiple pillars, no nondeterministic evaluation and no new external trust boundary. The decision is recorded in ADR-019.
- Owner Required: Chief Product and Chief Architect
- Approval Record: Ratified in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). Integrated by ADR-019.

### OD-011 Retention, Legal Hold, And Deletion Policy

- Decision ID: OD-011
- Exact Question: Which retention windows, customer-configurable choices, legal-hold authority, backup deletion deadlines, and destruction evidence rules apply to Volume I data classes?
- Classification: C
- Current Status: Pending owner approval
- Why The Decision Exists: Foundation requirements mandate per-class minimum/maximum retention and auditable hold/destruction, but the values and customer flexibility are legal, commercial, and risk choices.
- Affected Capabilities: CAP-013, CAP-018, CAP-022, CAP-023, CAP-025
- Affected Workflows: WF-003, WF-005, WF-006, WF-009, WF-013, WF-016, WF-018
- Affected Product Rules: PRULE-016, PRULE-035, PRULE-036, PRULE-037, PRULE-042, PRULE-043
- Affected Foundation Requirements: DLC-REQ-011 through DLC-REQ-016, DLC-REQ-024 through DLC-REQ-032, SEC-REQ-010, SEC-REQ-013
- Affected Acceptance Criteria: AC-CAP-013, AC-CAP-018, AC-CAP-022, AC-CAP-023, AC-CAP-025, AC-WF-003, AC-WF-005, AC-WF-006, AC-WF-009, AC-WF-013, AC-WF-016, AC-WF-018, AC-PRULE-016, AC-PRULE-035, AC-PRULE-036, AC-PRULE-037, AC-PRULE-042, AC-PRULE-043, AC-SM-001, AC-SM-003, AC-SM-007
- Options:
  1. Approve `retention-interim-v1` as the fixed baseline.
  2. Supply a legally reviewed fixed replacement class/window policy before launch.
  3. Add customer-configurable windows within owner-approved class-specific bounds.
- Recommended Option: Option 2 before external launch; use Option 1 for deterministic implementation and prelaunch operation.
- Evidence Supporting The Recommendation:
  - A single fixed interim prevents teams from inventing divergent deletion/backup behavior.
  - Legal and contractual obligations can vary by market and customer, so launch values need qualified review.
  - Customer configurability expands authorization, billing, UX, and migration scope and should not be inferred.
- Benefits: Executable lifecycle, hold, deletion job, restore-tombstone, and completion-evidence behavior now.
- Costs: Conservative history retention and backup deadlines create storage/operations cost.
- Risks: Interim values may not satisfy every launch jurisdiction or enterprise contract and therefore are not a legal conclusion.
- Security Implications: Holds and security/audit destruction require protected two-person authority; access revocation remains immediate even while bytes are held.
- Data Implications: Every data class has one exact class, cursor, minimum/maximum, deletion mode, backup behavior, and evidence record.
- AI Implications: Expired/quarantined Evidence cannot ground AI output; historical lineage retains only metadata/digests after payload destruction.
- Operational Implications: Requires deadline escalation, tombstone-before-restore, 90-day restore drill, and idempotent deletion job recovery.
- Commercial Implications: Retention can affect packaging and enterprise commitments; no customer-configurable option is implied.
- Reversibility: Medium; a successor may lengthen future retention, while already destroyed bytes cannot be restored.
- Safe Interim Behavior: Apply exact `retention-interim-v1` in [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md). No customer may change its windows. Legal hold suspends irreversible destruction only, never access revocation or product-validity expiry. Account/Organization deletion uses the exact LifecycleDeletionJob, 30-day primary and 35-day post-primary backup deadline, restore tombstones, and immutable deletion evidence. A conflicting legal obligation fails closed, blocks destruction, and requires owner/legal policy replacement; F1 does not provide a legal conclusion.
- Required Owner And Legal Approval Package: The approved policy package MUST identify one immutable version and digest and record each decision below separately; approval of one item does not imply approval of another:
  - Prelaunch implementation: whether and where `retention-interim-v1` may be used for development, testing, demonstrations, and other non-production operation, including the permitted data classes and prohibition or conditions for real customer data.
  - Production and contractual gate: approved jurisdictions, markets, customer/contract scope, production effective time, and the exact claims that may be made; no prelaunch permission opens this gate.
  - Legal hold: who may request, approve, reject, and release a hold; required separation of duties; eligible scope and reasons; precedence for conflicts; evidence fields; and the invariant that hold never restores access or product validity.
  - Primary destruction: each data class's minimum/maximum window, trigger, destruction mode, deadline, retry/escalation behavior, and immutable destruction evidence.
  - Backup: each data class's backup retention and deletion deadline, restore-tombstone behavior, restore-after-request prevention, verification, and missed-deadline escalation.
  - Audit: security/audit and lifecycle-evidence retention windows, access/classification constraints, integrity proof, hold interaction, and the metadata retained after payload destruction.
  - Customer configuration: an explicit disabled decision or the exact per-class selectable bounds, authorized actor, validation, effective-time, existing-data migration, rollback, and contractual behavior; configurability is never inferred from a fixed policy.
  - Qualified legal approval: reviewer identity and capacity, jurisdictions and material legal assumptions reviewed, package identity/version/digest, approval or conditions, signed UTC time, and separate Chief Security and Chief Product signatures over that same digest.
- Latest Responsible Decision Point: Before storing production customer data or making a contractual retention claim.
- Blocking Impact: Volume II — no; prelaunch implementation and non-production testing — no under the exact interim and its data restrictions; production — storing production customer data is blocked; contractual gate — every retention, hold, deletion, backup, audit, or configurability claim is blocked; feature — customer-configurable retention is disabled unless expressly approved; these gates open only when qualified legal review and both named owners approve one identical immutable package.
- ADR Threshold: Required for customer-configurable retention, a new legal authority role, or materially different backup/destruction architecture.
- Owner Required: Chief Security and Chief Product following qualified legal review
- Exact Approval Wording: Each required owner signs the identical statement: “I approve OD-011 Option [selected], policy package [identity and immutable version], canonical SHA-256 [digest], for [jurisdictions, markets, customer/contract scope] effective [UTC time]. I separately approve its recorded prelaunch, production/contractual, legal-hold, primary-destruction, backup, audit, and customer-configuration decisions; qualified legal reviewer [identity and capacity] approved this same digest on [UTC time].”

### OD-012 Emergency Cross-Organization Support Access

- Decision ID: OD-012
- Exact Question: Under what authority, predicate, scope, and evidence may a SecurityOperator obtain cross-Organization support access without the affected tenant's OrganizationAdmin approval during a severity-critical Incident?
- Classification: C
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; resolved by replacement
- Approved Option: Option 3 — emergency access is authorized outside the Incident record by a dedicated break-glass artifact and workflow, with an explicit predicate, separate requesting and approving actors, least privilege, explicit resource and action scope, immutable Audit Evidence, a canonical emergency-access event contract, and a bounded lifetime. There is no standing cross-tenant support access. Option 1 is rejected; the no-break-glass posture is superseded, not ratified. Customer notification remains outstanding pending qualified legal review
- Why The Decision Exists: WF-018 and the Support Session contract permit the affected tenant's approval to be bypassed when an open severity-critical Incident names that Organization, the requested resource/action scope, and `emergency_customer_access=true`. The Incident contract's field list is exhaustive and contains no such field, and Volume I defines no command, actor, approval, event, or state rule that could set one. Whether break-glass access exists at all, who may authorize it, and what it may reach are security and operational risk choices, not architectural inferences.
- Affected Capabilities: CAP-023
- Affected Workflows: WF-017, WF-018
- Affected Product Rules: PRULE-037, PRULE-038, PRULE-044
- Affected Foundation Requirements: SEC-REQ-004, SEC-REQ-005, SEC-REQ-006, SEC-REQ-020, SEC-REQ-021, OBS-REQ-007
- Affected Acceptance Criteria: AC-CAP-023, AC-WF-017, AC-WF-018, AC-PRULE-037, AC-PRULE-038, AC-PRULE-044
- Options:
  1. Remove the bypass entirely; cross-Organization support access always requires the affected tenant's OrganizationAdmin approval.
  2. Define an emergency bypass on the Incident with an explicit authority, scope, approval, and evidence contract.
  3. Define an emergency bypass authorized outside the Incident record by a separate break-glass artifact.
- Recommended Option: Option 2, defined narrowly, with Option 1 as the deterministic interim until it is approved.
- Evidence Supporting The Recommendation:
  - The Support Session contract already anticipates emergency access, so removing it outright discards a deliberate design intent that only the owner can withdraw.
  - The security model requires explicit, auditable, server-side authority for every protected action, which an undefined predicate cannot provide.
  - Distinct SecurityOperator approval is already mandatory for every Support Session and is unaffected by this decision.
- Benefits: Restores a bounded break-glass path with named authority and auditable evidence.
- Costs: Requires an explicit Incident field, authority model, approval ceremony, scope binding, and event contract.
- Risks: An unbounded or weakly approved bypass is the strongest available path to cross-tenant customer data.
- Security Implications: This is the only route to customer data without tenant consent. Its authority model, scope binding, immutability, and Audit Evidence are the controlling security choices.
- Data Implications: Emergency access reaches tenant Evidence and payload data under the existing classification ceilings; access-trail retention follows `security_audit`.
- AI Implications: None.
- Operational Implications: Without a bypass, a severity-critical cross-tenant incident cannot be investigated until an available OrganizationAdmin in the affected tenant approves. That is a real operational exposure and is the substance of this decision.
- Commercial Implications: Enterprise customers may require either a contractual guarantee that no bypass exists, or a documented, evidenced one. Both are viable and only the owner can choose.
- Reversibility: Medium; adding a bypass later is possible, but any access already taken under one cannot be undone.
- Ratified Behavior: There is no standing cross-tenant support access and normal support operations retain no tenant access. Emergency cross-Organization access is authorized outside the Incident record by a dedicated break-glass artifact and workflow; the Incident aggregate carries no `emergency_customer_access` field and no authority may set, default, infer or synthesize one. Emergency access is permitted only when all of the following hold: an explicit emergency predicate on the break-glass artifact; a requesting actor and a distinct approving actor; least privilege; an explicit resource scope; an explicit action scope; a bounded lifetime bound to an approved policy version; a recorded reason; and immutable Audit Evidence retained under `security_audit`. Any cross-Organization Support Session not authorized by an active break-glass grant continues to require the affected tenant's OrganizationAdmin `support.session.customer_approve` in addition to the mandatory distinct SecurityOperator approval. Customer notification on emergency access is not approved and remains outstanding pending qualified legal review; it MUST NOT be specified as approved behaviour.
- Latest Responsible Decision Point (met on 2026-07-17): Before the first production severity-critical incident response, and before any contractual claim about emergency access.
- Blocking Impact: Partially outstanding. The emergency-access architecture is ratified and integrated. Customer notification on emergency access remains blocked pending qualified legal review under the retention and deletion legal package; no contractual claim about emergency-access notification may be made until that review completes.
- ADR Threshold: Met; this decision is recorded in ADR-019.
- Owner Required: Chief Security and Chief Product
- Approval Record: Resolved by replacement in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). The previous posture is superseded, not ratified. Integrated by ADR-019.

### OD-013 Event Tenant Identity For Non-Organization Event Scopes

- Decision ID: OD-013
- Exact Question: What tenant identity MUST a workflow event and its audit record carry when the producing workflow has no single Organization — a pre-Organization Bootstrap Grant event, a platform-wide Incident, or a cross-Organization Investigation?
- Classification: C
- Current Status: Pending owner approval
- Why The Decision Exists: [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md#logical-event-envelope) makes `organization_id` the sole event tenant identity with "no separate tenant value may be supplied", and [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md) DM-REQ-013 permits substitution only for "a pre-Organization bootstrap event ... where the named onboarding contract expressly permits it"; yet WF-001 emits `BootstrapGrantIssued` before any Organization exists, the WF-017 Incident contract permits "explicit platform-wide scope", and the WF-018 Investigation contract permits "an approved cross-Organization Organization set". No permitted substitution or representation covers the latter two producers, all conflicting sentences are tier 4 so PM-REQ-003 orders nothing between them, and null, a sentinel, an invented platform tenant, one selected Organization, per-Organization duplication, and omission have observably different tenant, authorization, retention, and consumer semantics.
- Affected Capabilities: CAP-001, CAP-023
- Affected Workflows: WF-001, WF-017, WF-018
- Affected Product Rules: PRULE-001, PRULE-037, PRULE-044, PRULE-046
- Affected Foundation Requirements: DM-REQ-005, DM-REQ-006, DM-REQ-013, SEC-REQ-004, SEC-REQ-012, OBS-REQ-023, OBS-REQ-024
- Affected Acceptance Criteria: AC-CAP-001, AC-CAP-023, AC-WF-001, AC-WF-017, AC-WF-018, AC-PRULE-001, AC-PRULE-037, AC-PRULE-044, AC-PRULE-046
- Options:
  1. Substitution plus per-Organization decomposition: amend WF-001 to expressly permit the DM-REQ-013 bootstrap substitution, and require WF-017/WF-018 to emit one Organization-scoped event per affected Organization, extending the separately approved per-Organization Export pattern WF-018 already establishes. No foundation change.
  2. Foundation-level event scope discriminator: a PM-REQ-009 controlled change to DM-REQ-013 adding an explicit `event_scope` (`organization` | `pre_organization` | `platform` | `organization_set`), with `organization_id` nonnull only for `organization` and a foundation-defined non-tenant principal field otherwise, aligning the event envelope with the command envelope's existing null-plus-separate-field mechanism.
  3. Tenant-scope restriction: delete platform-wide Incident scope and the cross-Organization Investigation set permanently; a platform event becomes N Incidents and a cross-Organization forensic becomes N Investigations linked by `correlation_id`.
- Recommended Option: Option 1 for the pre-Organization bootstrap sub-decision only, because DM-REQ-013 already provides the gate and WF-001 need only name it; the platform-wide Incident and cross-Organization Investigation sub-decisions are OWNER INPUT REQUIRED, as they are genuine strategic choices that may legitimately resolve differently and no accepted authority selects among them.
- Evidence Supporting The Recommendation:
  - DM-REQ-013 expressly reserves the bootstrap substitution for "the named onboarding contract", so Option 1's bootstrap leg consumes an existing foundation gate and requires no PM-REQ-009 change.
  - Option 2 alters the event envelope and the tenancy model, and per this register an option conflicting with a foundation requirement requires the PM-REQ-009 controlled change before it may be approved; no Volume I decision may approve it directly.
  - Option 3 preserves the one-Organization invariant with no foundation change but discards capability SEC-REQ-012 contemplates and WF-018 exists to provide, which only the owner may withdraw.
  - [../volume-ii/API_CONTRACTS.md](../volume-ii/API_CONTRACTS.md), [../volume-ii/APPLICATION_LAYER.md](../volume-ii/APPLICATION_LAYER.md), [../volume-ii/INDEX.md](../volume-ii/INDEX.md), and [../../schemas/POSTGRESQL_SCHEMA.md](../../schemas/POSTGRESQL_SCHEMA.md) already froze this as `UPSTREAM-V1-EVENT-SCOPE-001` and expressly refuse to select silently.
- Benefits: Replaces an unselectable envelope with one deterministic tenant identity per producer and lifts the existing tier-5 blocker into Volume I as normative, correcting the inversion where only derived artifacts enforce it.
- Costs: Option 1 makes `organization_id` hold a non-org_id value, straining DM-REQ-005/DM-REQ-006 namespace rules and every RLS predicate, and gives a genuinely platform-wide Incident unbounded fan-out with no natural Organization set; Option 2 gates every downstream artifact behind a foundation change.
- Risks: Any option that leaves the envelope ambiguous invites implementations to fabricate a tenant; tier 5 has already invented a "primary Organization" concept no tier-2 or tier-4 document defines.
- Security Implications: `organization_id` is the tenant context SEC-REQ-004 requires authorization to evaluate; a sentinel, null, or fabricated tenant weakens every RLS predicate and every cross-tenant control under SEC-REQ-012.
- Data Implications: Controls the final `domain_events`, `event_registry`, `audit_records`, `audit_record_registry`, `incidents`, and `investigations` DDL, all of which are blocked until approval; the pre-Organization Grant audit row cannot be assigned any value today.
- AI Implications: None.
- Operational Implications: The interim leaves F1 unable to declare a platform-wide Incident or run cross-Organization forensics, and suppresses two bootstrap events that OBS-REQ-023/OBS-REQ-024 incident reconstruction would otherwise consume; that is a real capability loss, not a cosmetic one.
- Commercial Implications: None direct; indirect enterprise trust impact if cross-Organization investigation capability is withdrawn permanently under Option 3.
- Reversibility: Low for Option 2 once the envelope ships, because event history is immutable and cannot be re-scoped retroactively; medium for Options 1 and 3 before first production event emission.
- Safe Interim Behavior: Apply `event-scope-interim-v1`. Every workflow event and audit record MUST carry a nonnull `organization_id` resolving to an existing Organization; no producer may emit with null, a sentinel, an invented platform tenant, an arbitrarily selected Organization, per-Organization duplication, or an omitted tenant field. WF-001 grant issuance stays executable and returns Grant ID, state version, and expiry, but `BootstrapGrantIssued` and `BootstrapGrantExpired` are not emitted and each suppression is recorded as one explicit enumerated telemetry gap, never a silent omission; `BootstrapGrantConsumed` is unaffected because the Organization exists in the same atomic commit. WF-017 Incident creation is restricted to explicit single-Organization scope; a candidate matching a platform-wide predicate creates no Incident, returns `F1-DOMAIN-409 / event_scope_unavailable`, and raises exactly one critical operational escalation record, reusing the shape WF-017 already defines for `recovery_playbook_unavailable`. WF-018 OpenInvestigation is restricted to one Organization; a cross-Organization request returns `F1-DOMAIN-409 / event_scope_unavailable`, changes no state, and records the WF-018 denial/integrity outcome. `event_scope_unavailable` is added to the reason-code registry so the denial is contract-defined rather than invented. This interim does not approve any OD-013 option.
- Latest Responsible Decision Point: Before Volume II acceptance, and ahead of the other pending decisions rather than at the deadline, because every further Volume II event, audit, or tenant-scope section written against the unresolved envelope widens the correction surface.
- Blocking Impact: Volume II — yes; the logical event/audit envelope, the `domain_events`/`audit_records` DDL, and the WF-017/WF-018 scope columns are frozen behind `UPSTREAM-V1-EVENT-SCOPE-001` and cannot be written. Implementation — no under `event-scope-interim-v1` for grant issuance, single-Organization Incidents, and single-Organization Investigations. Production — no for those paths, but the owner MUST expressly accept that no platform-wide Incident and no cross-Organization forensic capability exists under SEC-REQ-012. Feature — every platform-wide Incident, every cross-Organization Investigation, and `BootstrapGrantIssued`/`BootstrapGrantExpired` emission are blocked until approval.
- ADR Threshold: Required before Volume II acceptance and for any option altering the event envelope or the tenancy model; Option 2 additionally requires the PM-REQ-009 controlled foundation change to DM-REQ-013 before it may be approved.
- Owner Required: Chief Architect and Chief Security
- Exact Approval Wording: "I approve OD-013 Option [selected] for the pre-Organization bootstrap, platform-wide Incident, and cross-Organization Investigation sub-decisions respectively, and I approve the exact tenant identity, envelope representation, and audit record each emits. I accept that no approval of Option 2 is valid until the PM-REQ-009 controlled change to DM-REQ-013 is accepted, and that approval of Option 3 permanently withdraws platform-wide Incident scope and cross-Organization Investigation capability."

### OD-014 Project Pause, Resume, And Archive Command Authority

- Decision ID: OD-014
- Exact Question: Which actors, holding which permissions and through which commands, may execute the Project active-to-paused, paused-to-active, active-to-archived, and paused-to-archived transitions that the foundation state model names but for which Volume I defines no command?
- Classification: C
- Current Status: Pending owner approval
- Why The Decision Exists: [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) declares four Project transitions and names `ProjectPaused`, `ProjectReactivated`, and `ProjectArchived`, but delegates transition authority to the Volume I permission contract, which defines only `project.create` and `project.activate`; whether operators or only administrators may pause, resume, and archive, and whether a terminal archive warrants a second control, are risk and product choices rather than architectural inferences.
- Affected Capabilities: CAP-003
- Affected Workflows: WF-002
- Affected Product Rules: PRULE-003, PRULE-004; PRULE-003 governs only creation and activation, so approval also requires a new Project lifecycle authority rule for traceability parity with PRULE-005 and PRULE-020.
- Affected Foundation Requirements: SM-REQ-003, SM-REQ-004, SM-REQ-007, SM-REQ-010, SEC-REQ-013
- Affected Acceptance Criteria: AC-CAP-003, AC-WF-002, AC-PRULE-003, AC-PRULE-004
- Options:
  1. One combined `project.lifecycle.manage` permission covering all four edges, allowed to OrganizationAdmin and MarketingOperator, mirroring `source.lifecycle.manage`.
  2. Split by reversibility: `project.pause` and `project.resume` allowed to OrganizationAdmin and MarketingOperator; `project.archive` allowed to OrganizationAdmin only.
  3. As Option 2, but `project.archive` additionally requires a distinct requester and approver under `protected-permissions-v1`, mirroring `organization.close`.
- Recommended Option: Option 2
- Evidence Supporting The Recommendation:
  - [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) makes paused-to-active valid and archived-to-active invalid, so the foundation itself already draws the reversible/terminal boundary this option follows.
  - The Permission Baseline in [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md#permission-baseline) already treats a combined lifecycle grant and a terminal tenant action differently; a Project-scoped resource sits between those two templates.
  - SEC-REQ-013 requires least privilege but no foundation requirement mandates dual control for irreversible operations, which the foundation reserves for Organization-scope and legal-scope actions.
- Benefits: Routine pausing stays with the operators who create and activate Projects; the single irreversible edge is held by the accountable administrator; no dual-control machinery is introduced.
- Costs: Two permission rows and two authorization branches instead of one; MarketingOperator must escalate to archive.
- Risks: Option 1 grants an unrecoverable archive to MarketingOperator with no second control; Option 3 is disproportionate to a Project-scoped resource and is the option most likely to stall.
- Security Implications: Every option requires a successor `permission-baseline-v2` profile and matching Access Policy because `permission-baseline-v1` is declared the complete baseline table; Service Identity MUST be deny under every option because the foundation permits no scheduled pause or resume; Option 3 additionally changes protected status, which tenant policy may not express and which must therefore land in the baseline profile itself.
- Data Implications: Requires Project lifecycle timestamp and reason columns and a transition function; the `projects.state` CHECK already admits `paused` and `archived` and needs no change.
- AI Implications: None.
- Operational Implications: Pause and archive become product commands and remain unavailable as operational recovery tools; no timer or job is added even after approval.
- Commercial Implications: Until approval the baseline offers no in-product way to stop monitoring a Project short of Organization closure.
- Reversibility: Medium; the permission split can change through a successor permission profile, but any Project archived under an approved option can never return to active.
- Safe Interim Behavior: No `project.pause`, `project.resume`, or `project.archive` command is accepted and no corresponding permission exists in `permission-baseline-v1`, so all four edges are unreachable and every Project rests only in draft or active. Any such request is denied by default under [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md#permission-baseline) as an undefined permission, changes no state, and emits no `ProjectPaused`, `ProjectReactivated`, or `ProjectArchived` event; no implementer may route these to `project.activate`, whose WF-002 precondition binds it to draft, or to any service identity. The three events remain named with no producer and stay excluded from every executable event registry. All existing paused and archived consumer branches, including the Source-registration and schedule-policy predicates and the `projects.state` CHECK, are retained unchanged and become live once a producer is approved. This interim is compelled by the deny-by-default rule given an undefined permission; it does not approve any option.
- Latest Responsible Decision Point: Before external launch, and before any contractual claim that monitoring of a Project can be stopped.
- Blocking Impact: Volume II — no; the path is absent rather than ambiguous and stays gated under `UPSTREAM-V1-PROJECT-LIFECYCLE-003`; implementation — no under the fail-closed interim; production — the interim is operable but leaves no in-product way to stop monitoring a Project short of Organization closure, so the owner MUST accept that limitation explicitly before external launch; feature — every Project pause, resume, and archive behavior is blocked until approval.
- ADR Threshold: Required for every option, because SM-REQ-010 mandates ADR governance for transition authority changes and no ADR currently names Project lifecycle authority; approval additionally triggers a PM-REQ-009 controlled foundation change, because the state model's Project row defines idempotency, failure, and recovery for activation only and is already incomplete against SM-REQ-003.
- Owner Required: Chief Architect and Chief Product
- Exact Approval Wording: I approve OD-014 Option [selected] as the Project pause, resume, and archive authority for Volume I, including its per-edge permissions, its mandatory Service Identity deny, and the successor permission profile and Access Policy versions it requires, and I authorize the PM-REQ-009 foundation change and the ADR that record it.

### OD-015 Document Quarantine And Retirement Authority

- Decision ID: OD-015
- Exact Question: Which authority, trigger, actor, and evidence contract may transition a Document into `quarantined` or `retired`, and does either state exist in the accepted baseline at all?
- Classification: C
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; resolved by owner decision
- Approved Outcome: The `quarantined` and `retired` Document states and the `DocumentQuarantined` and `DocumentRetired` events are removed. The Document lifecycle is `discovered -> ingested -> parsed -> indexed` only. Evidence quarantine is a separate, unaffected state machine. Applied to [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) as a PM-REQ-009 controlled foundation change under ADR-019.
- Why The Decision Exists: [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) admits `quarantined` and `retired` as Document states and names `DocumentQuarantined` and `DocumentRetired`, but Volume I defines no permission, command, actor, service authority, job, or event that could produce either; the row also assigns Document transitions to an undefined "Data Lifecycle Context" and names two competing retirement producers. Whether a content-withdrawal control exists, who may command it, and what retires a Document are security, legal, and product risk choices, not architectural inferences.
- Affected Capabilities: CAP-008
- Affected Workflows: WF-005, WF-006, WF-013
- Affected Product Rules: PRULE-009
- Affected Foundation Requirements: SM-REQ-002, SM-REQ-003, SM-REQ-007, SM-REQ-010, DM-REQ-002
- Affected Acceptance Criteria: AC-CAP-008, AC-WF-005, AC-WF-006, AC-PRULE-009
- Options:
  1. Security/legal-commanded quarantine with disposition-driven retirement: add `document.quarantine` and `document.retire` permissions modelled on the existing `evidence.validation.manage` row, executed by a named lifecycle service under an active Support Session, with an explicit authorized disposition retiring the Document.
  2. Terminal-invalidation-derived quarantine with Evidence-payload-expiry retirement: the lifecycle service quarantines a Document when its governing `source_document`/`parsed_content` Evidence reaches the terminal `invalid` state, yielding automatic retirement at the 24-month payload maximum.
  3. Reserve both states with no baseline producer, mirroring the accepted BillingEntity `past_due`/`suspended` precedent; retention and revocation continue through the existing LifecycleDeletionJob.
- Recommended Option: Option 3 as the deterministic interim baseline only; the destination between Option 1 and Option 2 is OWNER INPUT REQUIRED, because no accepted authority in the repository prefers either and each contradicts a different frozen document.
- Evidence Supporting The Recommendation:
  - Both edges currently violate SM-REQ-003, which requires authority, idempotency, retry, timeout, failure/terminal states, and recovery paths for every transition.
  - [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) already reserves BillingEntity `past_due` and `suspended` as unreachable in the accepted baseline, supplying a foundation-blessed precedent that invents no product behaviour.
  - Option 1 needs a reason vocabulary and precedence authored from scratch; Option 2 contradicts [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md), which names only an Evidence-validation change at the payload boundary and destruction rather than retirement at the `product_history` maximum.
  - Volume II, the frontend, background processing, and the schema manifest already fail closed under `UPSTREAM-V1-DOCUMENT-LIFECYCLE-012`, so the interim ratifies the position downstream already holds.
- Benefits: Restores internal consistency and unblocks Volume II and schema acceptance immediately while preserving every destination option.
- Costs: Leaves the product with no way to withdraw a harmful indexed Document short of full Account or Organization deletion.
- Risks: Option 1 is manual only, so unsafe indexed content persists until a human acts; Option 2 couples Document lifetime to the 24-month payload class while Document is itself a 7-year `product_history` record and offers no security-driven quarantine path.
- Security Implications: Quarantine is the only content-withdrawal control short of destruction; its authority model, one-way binding, and Audit Evidence are the controlling security choices. Under the interim no such control exists.
- Data Implications: Document belongs to `product_history` with a 7-year maximum while its Evidence payload belongs to `product_evidence_payload` with a 24-month maximum; whether a Document outlives its payload is unresolved and is a product decision.
- AI Implications: None direct; Evidence-level quarantine already governs AI grounding independently of Document state.
- Operational Implications: No operator path exists to withdraw a harmful indexed Document; retention, legal hold, and LifecycleDeletionJob behaviour are unchanged by this decision.
- Commercial Implications: Content withdrawal may be a contractual expectation; no quarantine or retirement claim may be made while the interim is active.
- Reversibility: High while the interim holds, because reserved states preserve every option; medium once enabled, because quarantine is one-way and `retired` never reopens.
- Ratified Behavior: The `quarantined` and `retired` Document states and the `DocumentQuarantined` and `DocumentRetired` events are removed from [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) by the PM-REQ-009 controlled foundation change recorded in ADR-019. The canonical Document lifecycle is `discovered -> ingested -> parsed -> indexed` and `indexed` is terminal. No Document state admits quarantine or retirement, and neither removed event has any producer, route, manifest entry or acceptance claim. The Evidence quarantine model is a separate state machine and is unaffected. Legal-retention behaviour is not absorbed into the Document state machine: a Document leaves product use only through the separate retention and deletion lifecycle, which destroys the record rather than transitioning it, and which remains governed by the outstanding legal package. Existing discovered-to-ingested-to-parsed-to-indexed execution, retention, legal hold and LifecycleDeletionJob behaviour are otherwise unchanged.
- Latest Responsible Decision Point (met on 2026-07-17): Before the first production need to withdraw an indexed Document, and before any contractual claim about Document quarantine or retirement.
- Blocking Impact: None. OD-015 is resolved; the Document lifecycle is simplified and the foundation change has landed in the same change set.
- ADR Threshold: Met; this decision is recorded in ADR-019.
- Owner Required: Chief Product and Chief Security
- Approval Record: Resolved by owner decision in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). Integrated by ADR-019.

### OD-016 Standalone Session Revocation And Sign-Out Scope

- Decision ID: OD-016
- Exact Question: Does a standalone Session revocation command exist independently of Account and Organization lifecycle transitions, and does self-service sign-out exist?
- Classification: C
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; resolved by replacement
- Approved Option: Option 3 — every authenticated user may terminate their current Session; a SecurityOperator may revoke one identified Session. Sign-out-everywhere remains deferred. The no-sign-out posture is superseded, not ratified
- Why The Decision Exists: The Session row in [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) permits `active` to `revoked` on "explicit security revocation", but its Transition Authority names a bounded context rather than an actor or permission, and Volume I defines no standalone command, actor, permission, trigger, error result, audit reason, or acceptance oracle for one; no `session.*` permission exists anywhere in the baseline. The clause may already be realized by the SecurityOperator's `account.suspend` and `account.revoke` "for security action", so whether a per-Session revocation command exists at all, and whether users may sign themselves out, are product and security scope choices rather than architectural inferences.
- Affected Capabilities: CAP-001, CAP-025
- Affected Workflows: WF-001, WF-013
- Affected Product Rules: PRULE-001, PRULE-018, PRULE-041
- Affected Foundation Requirements: SEC-REQ-021, SEC-REQ-023, SEC-REQ-024, SM-REQ-003, SM-REQ-004, OBS-REQ-004
- Affected Acceptance Criteria: AC-CAP-001, AC-CAP-025, AC-WF-001, AC-WF-013, AC-PRULE-001, AC-PRULE-018, AC-PRULE-041
- Options:
  1. No standalone command; annotate the "explicit security revocation" clause as already realized by Account and Organization security suspension, revocation, and closure.
  2. Define a security-scoped standalone `session.revoke` for SecurityOperator only, with no self-service sign-out.
  3. Option 2 plus self-service sign-out, including whether it revokes one Session or every concurrent Session of that Account.
- Recommended Option: Option 1, with Option 2 or 3 available only as an owner-selected capability addition.
- Evidence Supporting The Recommendation:
  - SEC-REQ-021's expiry, revocation, and idle-timeout controls are already satisfied without a standalone command: revocation commits on Account or Organization suspension, and 30-minute idle and 12-hour absolute expiry are already specified in the Session contract.
  - The SecurityOperator already holds `account.suspend` and `account.revoke` "for security action", and suspension returns only after Session revocation commits, so incident response has an existing authoritative path.
  - Options 2 and 3 add a product capability, which the active correction ADR's constraint set forbids and which no accepted authority requires; sign-out is a mainstream expectation but no repository authority mandates it, which is the latitude that makes this strategic.
- Benefits: Option 1 closes the defect with one foundation-wording change and no implementation surface; Options 2 and 3 give finer-grained incident response than account suspension, and Option 3 materially improves shared-device posture.
- Costs: Option 1 leaves no way to terminate one Session without suspending the whole Account and no sign-out, so a user's only exit is idle or absolute expiry; Options 2 and 3 each require a new permission row, actor, precondition, expected-state-version, idempotency, error reason, audit reason, and acceptance oracle to satisfy SM-REQ-003.
- Risks: Option 1 keeps a compromised Session usable until expiry unless its Account is suspended; Option 3 adds a user-facing capability the frozen baseline never contemplated and must resolve concurrent-Session semantics, which currently state that concurrent Sessions do not revoke one another.
- Security Implications: Under Options 1 and 2 the only user-visible termination is expiry or Account suspension; Options 2 and 3 create a new protected action whose authority, scope binding, audit reason, and event contract are the controlling security choices, and the decision touches SEC-REQ-021 scope directly.
- Data Implications: Options 2 and 3 extend the Session revoke-reason vocabulary and its schema enum; Option 1 admits no new revoke-reason value and adds no field.
- AI Implications: None.
- Operational Implications: Under Option 1, terminating a compromised actor's access requires SecurityOperator Account suspension or revocation, which is coarser than per-Session termination and is the substance of this decision.
- Commercial Implications: The absence of sign-out is customer-visible and may be raised in enterprise review; no accepted authority requires it, so adding it is an owner packaging choice.
- Reversibility: High for Option 1; medium for Option 2; low for Option 3 once a user-facing sign-out control ships.
- Ratified Behavior: An authenticated user may terminate the Session they are acting in, and a SecurityOperator may revoke one identified Session. Both act on exactly one identified Session and never cascade to concurrent Sessions of the same Account; sign-out-everywhere remains deferred and is not baseline behaviour. The Session state set is unchanged at `active`, `revoked` and `expired`, and the existing `active -> revoked` edge carries both paths under distinct revoke reasons. The transition authority is named in [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) by the PM-REQ-009 controlled foundation change recorded in ADR-019, which is a transition-authority change under SM-REQ-010. Terminating or revoking an already terminal Session is idempotent and changes no state. The previous no-sign-out posture is superseded, not ratified.
- Latest Responsible Decision Point (met on 2026-07-17): Before Volume II application-layer acceptance, where this is already blocking as `UPSTREAM-V1-SESSION-REVOCATION-002`.
- Blocking Impact: None. OD-016 is resolved by replacement; current-session sign-out and single-Session security revocation are approved baseline behaviour. Sign-out-everywhere remains deferred and is out of baseline scope rather than blocked pending approval.
- ADR Threshold: Met; this decision is recorded in ADR-019.
- Owner Required: Chief Product and Chief Security
- Approval Record: Resolved by replacement in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). The previous posture is superseded, not ratified. Integrated by ADR-019.

### OD-017 Issue Fingerprint Collision Second-Issue Persistence And Evaluation Continuation

- Decision ID: OD-017
- Exact Question: When an Issue fingerprint hash matches but the retained preimage differs, MUST or MUST NOT the second Issue be created, and does the affected Evaluation continue or fail?
- Classification: C
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; resolved by owner decision
- Approved Outcome: On an Issue fingerprint collision the second Issue MUST NOT be created and the affected Evaluation fails closed using the existing canonical collision outcome and telemetry. No alternative duplicate Issue may be silently persisted.
- Why The Decision Exists: [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md) says the second full tuple "may create" its own Issue, a permissive keyword where DOC-REQ-007 requires an RFC-style normative choice; PRULE-023's only MUST (never merge) is satisfied by every branch, no foundation requirement selects one, the WF-007 failure-path and event lists are provably non-exhaustive, and the WF-007 recovery path points circularly back to the ambiguous clause. Whether a customer-visible finding is persisted from a fingerprint scheme that has demonstrably failed is a product risk choice, not an architectural inference.
- Affected Capabilities: CAP-014, CAP-015
- Affected Workflows: WF-007, WF-008
- Affected Product Rules: PRULE-023
- Affected Foundation Requirements: DM-REQ-005, QA-REQ-012, SM-REQ-005, ERR-REQ-001; no option changes any of them, so no PM-REQ-009 controlled foundation change is triggered.
- Affected Acceptance Criteria: AC-CAP-014, AC-CAP-015, AC-WF-007, AC-WF-008, AC-PRULE-023, AC-SM-006
- Options:
  1. Persist and continue: MUST create the second Issue keyed by its full preimage, both Issues become distinct current leaves ordered by preimage, `IssueFingerprintCollision` is restricted telemetry with no product effect, and the Evaluation completes, scores, recommends, and publishes history normally.
  2. Do not persist and fail closed: MUST NOT create the second Issue; detect at Issue derivation before any Issue write, record the collision, emit restricted telemetry, and fail the affected Evaluation as `F1-DATA-409 / issue_fingerprint_key_collision`, publishing no Issue Set, score, Recommendation, or history.
  3. Persist but withhold the projection: create the second Issue and seal the Issue Set, but atomically mark the Current Score Projection unavailable under a new fixed reason and suppress every affected origin Recommendation.
- Recommended Option: Option 2, on the 009 DECISION_FRAMEWORK reversibility test alone; no evidence forces a final branch, so this recommendation is advisory and Options 1 and 3 remain open to the owner's strategic judgement.
- Evidence Supporting The Recommendation:
  - Option 2 gives exact structural parity with the already-accepted Check Result collision rule, which never merges, records the collision, and fails the affected Evaluation before Check execution.
  - A SHA-256 collision realistically means the canonicalization is defective, so the preimages themselves may be untrustworthy and nothing customer-visible should derive from the scheme.
  - Option 2 is the only branch whose error is fully recoverable: if Option 1 is later approved, only a failed Evaluation must be re-run and no persisted data must be unwound.
- Benefits: Parity with the accepted sibling rule; no score, Recommendation, or history is published from a fingerprint scheme known to be broken; fully recoverable.
- Costs: Discards an entire valid Evaluation after every Check has already executed, which is strictly more destructive than the Check Result case.
- Risks: Option 1 writes irreversible customer-visible data from a possibly defective canonicalization; Option 2 loses a valid finding over an astronomically improbable and diagnosable event; Option 3 leaves a permanently unscorable Project pending operator intervention and adds a fourth Evaluation outcome shape.
- Security Implications: Collision telemetry and retained preimages remain restricted and absent from the event envelope under every option.
- Data Implications: No migration or unwind today because Volume II is pre-implementation and every dependent path is gated; `fingerprint_collision_decisions` already reserves the `issue` arm.
- AI Implications: None direct; the Volume II AI evaluation note over-reads AC-SM-006 as requiring a distinct Issue in the same-hash case and must be corrected alongside whichever option is approved.
- Operational Implications: Under Option 2 recovery is a new linked Evaluation attempt with no automatic retry; Option 3 would additionally require a new unavailability reason code and a defined operator re-entry path.
- Commercial Implications: Issue-set membership is customer-visible, so losing a finding and publishing a score from a suspect index are both customer-visible outcomes the owner must choose between.
- Reversibility: High now while every dependent path is gated and no persisted data exists; Option 1 becomes effectively irreversible once Issues, sealed Issue Sets, and published customer-visible history depend on it.
- Ratified Behavior: Apply `issue-collision-v1`. Detection is at Issue derivation, before any Issue write, on the predicate `fingerprint_sha256` equal AND retained preimage unequal within the same `(evaluation_id, fingerprint_version)`. The conflicting Issue identity is preallocated in the derivation slot exactly as the Check Result slot identity is preallocated, and is the collision Decision subject and root affected entity; no Issue row is ever written under it. One `fingerprint_collision_decisions` row records `fingerprint_kind='issue'` with the prior bucket Issue as `existing_record` and the preallocated slot as `conflicting_record`, roles semantic and never reordered by UUID. Restricted `IssueFingerprintCollision` is emitted in the same transaction as the collision row and the Evaluation failure, one event per attempted conflicting create, before the Evaluation terminalizes; retained preimages stay restricted and absent from the envelope. The affected Evaluation fails as `F1-DATA-409 / issue_fingerprint_key_collision` with `retryable=false`, publishing no Issue Set as current and no score, Recommendation, or history; the prior current Evaluation, Issue Set, ScoreSnapshot, and bucket member are untouched. Recovery is a new pending Evaluation linked by `retry_of_evaluation_id`, with no automatic retry.
- Latest Responsible Decision Point (met on 2026-07-17): Before Volume II implementation architecture acceptance.
- Blocking Impact: None. OD-017 is resolved; the collision outcome is deterministic and fails closed.
- ADR Threshold: Met; this decision is recorded in ADR-019.
- Owner Required: Chief Product and Chief Architect
- Approval Record: Resolved by owner decision in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). Integrated by ADR-019.

### OD-018 Concurrent Initial Evaluation Serialization

- Decision ID: OD-018
- Exact Question: How are two concurrent root Crawl starts for one Project serialized, given that WF-005's root branch gates only on an existing promoted pair and therefore admits more than one pending initial Evaluation?
- Classification: C
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; resolved by owner decision
- Approved Outcome: Only one initial Evaluation orchestration may exist per Project. A second root Crawl request that would initiate another initial Evaluation while one is pending or running is rejected deterministically, reusing the accepted WF-011 single-orchestration guard.
- Why The Decision Exists: WF-011 serializes reassessment on an explicit Project orchestration guard, but WF-005's root precondition rejects a root start only when a current promoted Evaluation/Issue-set/ScoreSnapshot pair already exists, so two simultaneous root starts each create a pending initial Evaluation; initial assessment has no reconciliation pass, so both promote duplicate current leaves for the same fingerprint. Whether the losing request is rejected, joined to the running run, or allowed to execute is a customer-experience and commercial choice, not an architectural inference.
- Affected Capabilities: CAP-007
- Affected Workflows: WF-005, WF-007, WF-008, WF-011
- Affected Product Rules: PRULE-007
- Affected Foundation Requirements: SM-REQ-002, SM-REQ-003, SM-REQ-005, SM-REQ-007, ERR-REQ-002, ERR-REQ-003
- Affected Acceptance Criteria: AC-CAP-007, AC-WF-005, AC-PRULE-007
- Options:
  1. Admission guard: extend WF-005's root precondition to also require no pending or running initial-assessment Evaluation for the Project; the losing root start is rejected before any queue, Entitlement Decision/reservation, or Evaluation is created.
  2. Coalescing join: a second root request binds to and returns the existing pending or running initial Evaluation and Crawl, creating no second Crawl, no second `crawl.start` unit, and no error.
  3. Late promotion guard: admit concurrent root Crawls up to the entitlement hard bound; the first promotion wins and later initial Evaluations terminate without promoting, advancing only `latest_calculation_*` and never superseding.
- Recommended Option: Option 1
- Evidence Supporting The Recommendation:
  - [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md) requires exactly one current leaf per full fingerprint identity; Option 1 bars initial-versus-initial duplication at admission, which is the only point where no Issue lineage yet exists to reconcile.
  - Option 1 byte-for-byte mirrors the already-accepted WF-011 guard and its `F1-DOMAIN-409 / reassessment_already_running` envelope, so it adds no new vocabulary.
  - The guard lives in the WF-005 precondition, which is Volume I, so no PM-REQ-009 controlled foundation change is required to adopt it.
  - Option 3 does not resolve the one-current-leaf invariant, since the loser's Issues become permanent duplicate current leaves the moment WF-007 creates them, forcing a second fix that migrates the guard back to Option 1's position.
- Benefits: Fails closed with no Crawl, reservation, Evaluation, or second Issue lineage created; reuses an accepted guard shape; costs the losing request zero entitlement.
- Costs: An accidental double-trigger surfaces an error rather than silently joining the run, which Option 2 would avoid.
- Risks: A guard keyed on Evaluation existence rather than pending/running state would wrongly block a legitimate root `crawl.recover` after a failed attempt; leaving the STATE_MODEL idempotency column reading as reassessment-only remains misleading unless a non-normative clarifying note is added.
- Security Implications: None direct; this is a domain-conflict serializer rather than an authorization boundary, and the rejection is logged under SM-REQ-007.
- Data Implications: The `evaluations` row is the physical fix point; its existing partial unique `(organization_id, project_id, crawl_id) WHERE kind='initial'` is crawl-keyed and does not serialize, so a Project-scoped uniqueness guard over pending/running initial Evaluations is required and must not be inferred from the current index.
- AI Implications: None direct; duplicate current leaves would corrupt the Issue set that grounds recommendations, which the interim prevents.
- Operational Implications: Support and telemetry must treat `initial_evaluation_already_running` as expected contention rather than a fault, and the guard must remain keyed on pending/running so recovery paths stay admissible.
- Commercial Implications: Option 1 and Option 2 charge the loser nothing; Option 3 commits a `crawl.start` unit for a run that can never promote, charging for guaranteed-discarded work.
- Reversibility: High while the interim holds, because no duplicate lineage can accrue and relaxing to Option 2 or Option 3 later requires only Volume I changes; duplicate leaves already promoted under a weaker guard could not be cleanly undone.
- Ratified Behavior: Option 1 applies and fails closed. WF-005's root precondition additionally requires no pending or running initial-assessment Evaluation for the Project, re-checked at the `Queued -> Running` commit alongside policy and entitlement re-resolution. A losing root request returns `F1-DOMAIN-409 / initial_evaluation_already_running`, severity `warning`, `retryable=false`, recovery `await_running_initial_evaluation_or_submit_new_command`, and creates no Crawl, Entitlement Decision/reservation, or Evaluation. The guard keys on pending/running only, never on existence, so a root `crawl.recover` after a failed initial Evaluation remains admissible. If two initial Evaluations ever reach promotion by that recovery path, the first promotion wins; a later initial promotion is refused, advances only `latest_calculation_*`, and never supersedes its predecessor.
- Latest Responsible Decision Point (met on 2026-07-17): Before Volume II acceptance freezes the `evaluations` uniqueness constraints.
- Blocking Impact: None. OD-018 is resolved; initial Evaluation orchestration is serialized per Project and a conflicting root Crawl request is rejected deterministically.
- ADR Threshold: Not met. The approved outcome mirrors the accepted WF-011 single-orchestration guard. The decision is recorded in ADR-019.
- Owner Required: Chief Architect
- Approval Record: Resolved by owner decision in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). Integrated by ADR-019.

### OD-019 Low-Cost Read Metering Unit And Response Identity

- Decision ID: OD-019
- Exact Question: What is the metering unit for a low-cost read, and what durable response identity deduplicates its Entitlement Decision and LowCostUsageRecord?
- Classification: C
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; ratified as specified
- Approved Option: Option 1 — the metered-read unit, subject to the commercial clarification
- Why The Decision Exists: WF-015 names five low-cost operations and charges exactly one LowCostUsageRecord per allowed "response" at the durable response checkpoint, but no document defines what a response is; a server-rendered page plus its independently requested Turbo Frames can reasonably be one unit or several, and the same navigation can reasonably resolve to `report.view` or `score.read`. The unit determines what the shared 800/1,000 `baseline_reads` bounds mean to a customer, which is a commercial and packaging choice rather than an architectural inference.
- Affected Capabilities: CAP-024
- Affected Workflows: WF-015
- Affected Product Rules: PRULE-039, PRULE-040, PRULE-046
- Affected Foundation Requirements: QA-REQ-009, QA-REQ-010, QA-REQ-012, SEC-REQ-006, OBS-REQ-004, SM-REQ-005
- Affected Acceptance Criteria: AC-CAP-024, AC-WF-015, AC-PRULE-039, AC-PRULE-040, AC-PRULE-046
- Options:
  1. Root-request subsumption: exactly one record per accepted top-level document read, charged to that route's single declared operation, with Frames and partials carrying the root Decision ID.
  2. Per transmitted response: every allowed response on a marked read route is one record, so a page plus four Frames is five records.
  3. Per distinct logical operation class exercised, deduplicated within the request, so a dashboard charges `score.read` plus `issue.read` plus `recommendation.read`.
- Recommended Option: Option 1, with `read-metering-v1` active until approval.
- Evidence Supporting The Recommendation:
  - WF-015 already establishes root subsumption for high-cost nesting so that "nesting cannot double meter"; the low-cost analogue is the only boundary consistent with CAP-024's never-double-count Success Condition and its duplicate-low-cost-consumption Failure Condition.
  - Cost per navigation stays stable and explicable to a customer, and front-end recomposition cannot silently change a bill.
  - Option 2 makes one navigation cost four to six units, changing what the shared 800/1,000 `baseline_reads` bounds mean from what the OD-006 interim assumed; Option 3 contradicts PRULE-040's one-record-per-response text unless PRULE-040 is amended.
- Benefits: Stable and explicable cost per navigation; mirrors the existing root/nesting invariant; UI recomposition does not change customer billing or warning timing.
- Costs: Requires a new normative exhaustive route-to-operation declaration table, and `report.view` must be given a defined read surface.
- Risks: A wrong or absent route declaration changes charging silently; page composition changes cost if declarations are not maintained.
- Security Implications: The undeclared-route leg MUST Block server-side through `operation_unknown` with `contact_support` and emit the standard denial audit event; metering resolution is never a client-side or implementation choice.
- Data Implications: Requires a defined durable response identity as the LowCostUsageRecord uniqueness key; `low_cost_usage_records` already carries a durable response hash and unique Decision that presuppose a term Volume I has not defined.
- AI Implications: None direct; `ai.generate` remains a separate high-cost operation.
- Operational Implications: Route-to-operation declarations become a maintained normative artifact, and conditional-response handling must be placed relative to the metering checkpoint.
- Commercial Implications: The unit determines what the shared `baseline_reads` limit means and therefore packaging, overage warning timing, and margin control.
- Reversibility: Medium; the unit can change through a versioned policy, but any change restates the meaning of every customer's recorded usage and limits.
- Ratified Behavior: Apply `read-metering-v1`. Exactly one LowCostUsageRecord is appended per accepted top-level document read that reaches the durable response checkpoint, with Decision ID as its uniqueness key. Every metered read route carries a static declaration of exactly one of the five low-cost operations; a read route with no declaration resolves `operation_unknown` and returns Block with `contact_support`, so an undeclared metered route is unreachable rather than silently unmetered. Turbo Frames and partials of a declared root carry the root Decision ID and MUST NOT append a second record; a Frame reached by direct navigation is itself a root. A request that never reaches the durable authorized-response checkpoint, including a conditional response returning no representation, creates no record. Read Decision IDs are server-minted deterministically from Organization, human Account or service identity, declared operation, resolved target identity and state version, and counter window; client-supplied idempotency keys remain prohibited on GET, and a repeated tuple within the window replays the stored record without another increment or event. Evidence and entitlement-notice reads are not among the five operations, so they are unmetered standalone and subsumed when nested.
- Latest Responsible Decision Point (met on 2026-07-17): Before Volume II acceptance, and before commercial packaging finalization.
- Blocking Impact: None. OD-019 is ratified; the metered-read unit is approved and defined consistently across product rules, workflow behaviour, entitlement evaluation, acceptance criteria and policy configuration. Numeric read limits are versioned policy configuration.
- ADR Threshold: Met; this decision is recorded in ADR-019.
- Owner Required: Chief Product
- Approval Record: Ratified in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). Integrated by ADR-019.

### OD-020 Read Authority Baseline For Undefined Read Actions

- Decision ID: OD-020
- Exact Question: By what mechanism does an actor acquire read authority over object classes that have no read row in `permission-baseline-v1`?
- Classification: C
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; resolved by replacement
- Approved Option: Option 1 — explicit read rows are added to the Permission Baseline for Organization home data, Project, Source, Crawl, Evaluation, Notification inbox and Export enumeration, mirroring their existing mutation permissions. Deny-by-default is not accepted for customer-facing objects. Security and administrative objects remain deny-by-default pending a separate decision
- Why The Decision Exists: The Permission Baseline table is a closed enumeration whose only reads are `issue.read`, `score.summary.read`, `score.detail.read`, `history.read`, `recommendation.read`, `evidence.metadata.read`, `evidence.payload.read`, `evidence.restricted.read`, `entitlement.notice.read`, `security.notice.read`, and `export.retrieve`. No row exists for Organization, Project, Source, Crawl, Evaluation, Notification, billing, Integration, Support Session, investigation, legal hold, deletion, Account, or policy reads, so deny-by-default denies them. Whether read authority is granted explicitly, derived from write authority, or versioned separately is a security and product choice, not an architectural inference.
- Affected Capabilities: CAP-002, CAP-003, CAP-008, CAP-018, CAP-019, CAP-021, CAP-022, CAP-023, CAP-024, CAP-025
- Affected Workflows: WF-002, WF-003, WF-004, WF-005, WF-006, WF-013, WF-014, WF-015, WF-016, WF-017, WF-018
- Affected Product Rules: PRULE-034, PRULE-044
- Affected Foundation Requirements: SEC-REQ-004, SEC-REQ-008, SEC-REQ-013, SEC-REQ-027
- Affected Acceptance Criteria: AC-CAP-002, AC-CAP-003, AC-CAP-008, AC-CAP-018, AC-CAP-019, AC-CAP-021, AC-CAP-022, AC-CAP-023, AC-CAP-024, AC-CAP-025, AC-WF-002, AC-WF-003, AC-WF-004, AC-WF-005, AC-WF-006, AC-WF-013, AC-WF-014, AC-WF-015, AC-WF-016, AC-WF-017, AC-WF-018, AC-PRULE-034, AC-PRULE-044
- Options:
  1. Add explicit per-object read rows to `permission-baseline-v1`, each with a full role/action matrix.
  2. Derive read from write: holding a manage/trigger/recover permission on an object class implies read on that class within the same scope, plus explicit rows only for classes with no companion write.
  3. Introduce a separate versioned `read_profile_version` artifact alongside the existing `permission_profile_version` / `classification_profile_version` / `protected_permission_profile_version` triple, enumerating object class to minimum role set.
- Recommended Option: Option 1 for customer-facing classes (Organization, Project, Source, Crawl, Evaluation, Notification, Export), with Option 3's profile mechanism only if support, incident, investigation, legal-hold, and deletion reads must version separately from tenant reads; Option 2 is not recommended.
- Evidence Supporting The Recommendation:
  - SEC-REQ-008 requires roles to map to explicit permission sets with deny-by-default behavior, which an implied grant does not provide.
  - Option 2 couples read to write, so a read-only persona receives nothing, yet CAP-018 and CAP-019 already place a read-only Executive Buyer in read paths.
  - Option 1 extends the table's accepted shape rather than introducing a new authorization mechanism, keeping PRULE-044's permission-matrix fixtures satisfiable.
  - CAPABILITY_MODEL.md:16 states an `Actor` line never grants authority, closing the only alternative source of the missing read.
- Benefits: Restores deterministic, auditable read authority for every object class and makes PRULE-044's complete allow/deny fixture requirement satisfiable.
- Costs: Option 1 requires roughly 98 owner-decided matrix cells and full fixture coverage; Options 1 and 2 change the table referenced by `permission_profile_version=permission-baseline-v1`, forcing a new profile version and a re-baselined byte-equivalent `access-policy-v1` payload; Option 3 adds a fourth profile axis to resolve, version, and test.
- Risks: A re-baselined permission profile that is not byte-equivalent renders every existing Organization's bootstrap policy `access_policy_invalid`; Option 2 additionally weakens SEC-REQ-013 least privilege by making read a side effect of write.
- Security Implications: This decision sets the read half of the authorization model; an implied or over-broad grant widens tenant data exposure, while the interim denies and exposes nothing.
- Data Implications: Any new read class carrying classified fields must resolve against the `classification_profile_version=score-visibility-v1` ceilings; billing, Integration, and investigation classes almost certainly do.
- AI Implications: None directly.
- Operational Implications: Under the interim, no operator or administrator can read Project, Source, Crawl, Notification, billing, or support object state through a defined permission, so operational visibility depends on approval.
- Commercial Implications: Read-only personas and the Executive Buyer have no product surface until read authority exists, which affects packaging claims that depend on read-only access.
- Reversibility: High while the interim holds because nothing is disclosed; once read authority is granted, data already disclosed cannot be un-disclosed.
- Ratified Behavior: The Permission Baseline carries explicit read rows for Organization home data, Project, Source, Crawl, Evaluation, Notification inbox and Export enumeration, mirroring the existing mutation permissions for the same objects and extending the accepted table shape rather than introducing a new authorization mechanism. Every such read is tenant-scoped, least-privilege, and denied outside an explicit grant. No wildcard read permission exists. Security, administrative and internal operational objects, including Support Session, Incident, Investigation, Legal Hold, LifecycleDeletionJob and other deletion jobs, and privileged Billing surfaces, remain deny-by-default pending a separate decision. Deny-by-default is no longer the answer for customer-facing objects.
- Latest Responsible Decision Point (met on 2026-07-17): Before any Volume II read surface — logical API index or show action, UI list or detail screen, export, or notification inbox — is designed.
- Blocking Impact: None for the approved customer-facing read set. Read authority for security, administrative and internal operational objects remains deny-by-default pending a separate owner decision, and is out of scope for this decision rather than resolved by it.
- ADR Threshold: Not met. Option 1 extends the accepted permission table shape and introduces no new authorization mechanism. The decision is recorded in ADR-019.
- Owner Required: Chief Product and Chief Security
- Approval Record: Resolved by replacement in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). The previous posture is superseded, not ratified. Integrated by ADR-019.

### OD-021 Account Reactivation Identity Proof

- Decision ID: OD-021
- Exact Question: For `account.reactivate`, whose identity must be proven, by what artifact, at what freshness, and bound to which subject?
- Classification: C
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; ratified as specified
- Approved Option: Option 1 — Account reactivation proves only the acting administrator's current MFA-satisfied Session; restores state, creates no Session, consults no target identity
- Why The Decision Exists: WF-013 requires Account reactivation to have "valid identity" without naming a proof artifact, freshness, subject binding, failure reason, or precedence, while the sibling Organization reactivation in the same subflow explicitly chose a step-up; assurance posture for a privileged security-relevant action is an owner risk choice, not an inference.
- Affected Capabilities: CAP-025
- Affected Workflows: WF-001, WF-013
- Affected Product Rules: PRULE-001, PRULE-019
- Affected Foundation Requirements: SEC-REQ-001, SEC-REQ-002, SM-REQ-002, SM-REQ-003
- Affected Acceptance Criteria: AC-CAP-025, AC-WF-013, AC-PRULE-019
- Options:
  1. Session-only: "valid identity" is the acting human's current active, MFA-satisfied Session and resolved authorization context; no additional artifact and no target-identity consultation.
  2. Actor step-up: a fresh Identity Validation Receipt under a new fifth purpose `account_reactivation`, bound to the acting administrator's `(issuer_key, subject)`, `mfa_satisfied=true`, 10-minute freshness, nonce-consumed.
  3. Target binding: a fresh receipt bound to the suspended target's `(organization_id, identity_issuer_key, identity_subject)`, proving the target still exists and is not disabled at the identity service before state is restored.
- Recommended Option: Option 1; this is a recommendation, not a derivation, and Options 2 and 3 remain legitimately available.
- Evidence Supporting The Recommendation:
  - MFA is already discharged by the Session: an OrganizationAdmin-capable context requires `mfa_satisfied=true` under SEC-REQ-002, so Option 1 adds no assurance gap the Session does not already close.
  - The disabled-provider risk fails closed without a new artifact: reactivation restores state, not access, and a target disabled at the identity service cannot obtain a receipt and so cannot sign in.
  - Receipt purposes are exclusive to WF-001 and none admits reactivation; the 016 STATE_MODEL Session row binds receipt consumption to WF-001, so a fifth purpose consumed outside WF-001 would require a PM-REQ-009 controlled foundation change.
  - Options 2 and 3 are not foreclosed: foundation enumerates no receipt purposes, so a fifth purpose is a Volume I-level choice, and Option 2 could clear the coupled `UPSTREAM-V1-ORGANIZATION-REACTIVATION-PROOF-008` blocker in the same change.
- Benefits: Reachable immediately with no new artifact, no foundation amendment, and no addition to `onboarding-interim-v1`.
- Costs: No re-authentication for a privileged security-relevant action; "valid identity" carries less content than the Organization reactivation step-up it sits beside.
- Risks: A hijacked administrator Session can reactivate under Option 1; Option 3 makes reactivation impossible without the target's live cooperation, conflicting with the admin-driven authority in 016 STATE_MODEL and the SecurityOperator security-action path.
- Security Implications: This sets the assurance posture for restoring a suspended Account; the containment that a disabled identity still cannot obtain access rests entirely on reactivation creating no Session.
- Data Implications: Requires Account state version, Organization authorization epoch, and audit fields for assurance result and proof decision; Options 2 and 3 add receipt lineage.
- AI Implications: None.
- Operational Implications: Option 1 adds no step to reactivation; Option 2 adds a re-authentication step to every reactivation; Option 3 requires the target to be live and cooperative at the identity service.
- Commercial Implications: None direct; any contractual claim that privileged reactivation requires step-up is unavailable while actor-only proof is active.
- Reversibility: High under Option 1; medium under Option 2; low under Option 3, because a fifth purpose consumed outside WF-001 requires a foundation amendment before it may be approved.
- Ratified Behavior: Apply `reactivation-proof-v1`. "Valid identity" resolves to the acting actor only; the command MUST NOT consult the target's managed identity or identity-service state, accepts no Identity Validation Receipt, and returns `F1-VALIDATION-400` if one is supplied. Required inputs are the actor's current active Session with `mfa_satisfied=true`, `account.reactivate` in the target's Organization, expected Account state version, expected Organization authorization epoch, and a 20-2,000 character reason; a SecurityOperator additionally requires one active Support Session naming the Account and exact action. Failures resolve by first-match order `F1-AUTHN-401 / authentication_failed`, `F1-AUTH-403 / organization_inactive`, `F1-AUTH-403 / account_reactivate_forbidden`, `F1-AUTHN-401 / identity_assurance_failed`, `F1-DOMAIN-409 / stale_authorization_epoch`, `F1-DOMAIN-409 / stale_state_version`, `F1-DOMAIN-409 / account_state_invalid`, `F1-VALIDATION-400`, `F1-DOMAIN-409 / idempotency_conflict`, each leaving the Account suspended with no side effect. Success atomically moves suspended to active, increments the Account state version and Organization authorization epoch, restores only still-active unexpired explicit Assignments, and emits `AccountReactivated`. Reactivation restores state and never access: it creates no Session, and the target must complete `existing_account_sign_in` with a fresh MFA-satisfied receipt. Any step-up purpose and any target-identity or identity-service liveness binding are denied.

  Disclosure, because this interim is not neutral between the options: its observable behaviour is identical to Option 1. Unlike a fail-closed interim that withholds a path until it is decided, this one keeps `account.reactivate` reachable, so operating it is operating Option 1's assurance posture in fact if not in name. It is stated this way because "valid identity" cannot be evaluated without selecting its content, and withholding reactivation entirely would make a suspended Account unrecoverable — a consequence no accepted requirement compels. The owner MUST therefore treat approval of Option 2 or Option 3 as a behavioural change that removes live behaviour, not as a refinement of an undecided path, and MUST NOT read continued operation of this interim as evidence that Option 1 was decided on its merits.
- Latest Responsible Decision Point (met on 2026-07-17): Before Volume II API_CONTRACTS acceptance.
- Blocking Impact: None. OD-021 is ratified as Option 1 knowingly; it is approved behaviour and MUST NOT be described as a neutral interim.
- ADR Threshold: Not met. Option 1 was approved. The decision is recorded in ADR-019.
- Owner Required: Chief Security
- Approval Record: Ratified in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). Integrated by ADR-019.

### OD-022 Organization Reactivation Identity Proof

- Decision ID: OD-022
- Exact Question: Which identity proof artifact satisfies the fresh managed identity and MFA predicate for OrganizationAdmin `organization.reactivate` against a suspended Organization, and how is it bound, issued, and consumed?
- Classification: C
- Current Status: Resolved on 2026-07-17 by explicit Product Owner decision recorded in [OWNER_DECISION_SUPPLEMENT_2026-07-17.md](OWNER_DECISION_SUPPLEMENT_2026-07-17.md)
- Approved Option: Option 1 — add a fifth purpose-bound Identity Validation Receipt purpose `organization_reactivation` carrying the assurance version and `mfa_satisfied=true`, bound to Organization ID, issuer, and subject, 10-minute expiry, nonce-consumed only by the reactivation command, creating no Session
- Why The Decision Exists: WF-013 admits reactivation as the sole ordinary mutation while suspended and can fail it with `identity_assurance_failed`, but Volume I defines no proof artifact that could satisfy or fail that predicate; the only receipt purpose carrying MFA evidence is `existing_account_sign_in`, which is the one purpose that rejects an inactive Organization. Whether a new proof exists, what it binds to, and who may present it are security and product-risk choices, not architectural inferences. This decision governs the `organization.reactivate` predicate only. The separate `account.reactivate` predicate is governed solely by OD-021; the two are independent because WF-013 states them differently — Organization reactivation requires "fresh managed identity and MFA" and can fail `identity_assurance_failed`, while Account reactivation requires only "valid identity". Neither decision governs the other, and neither interim constrains the other's options. If both owners select a receipt-based artifact, they SHOULD align its binding and freshness to avoid divergence, but OD-022 confers no authority over OD-021 and approving OD-022 decides nothing about Account reactivation.
- Affected Capabilities: CAP-001, CAP-002, CAP-025
- Affected Workflows: WF-001, WF-013
- Affected Product Rules: PRULE-019
- Affected Foundation Requirements: SEC-REQ-001, SEC-REQ-002, SEC-REQ-004, SEC-REQ-005, SM-REQ-002, SM-REQ-003
- Affected Acceptance Criteria: AC-CAP-001, AC-CAP-002, AC-CAP-025, AC-WF-001, AC-WF-013, AC-PRULE-019
- Options:
  1. Add a fifth purpose-bound Identity Validation Receipt purpose `organization_reactivation` carrying the assurance version and `mfa_satisfied=true`, bound to Organization ID, issuer, and subject, 10-minute expiry, nonce-consumed only by the reactivation command, creating no Session.
  2. Permit an `existing_account_sign_in` receipt with `mfa_satisfied=true` to be consumed by the reactivation command only, relaxing the inactive-Organization rejection for exactly that command.
  3. Issue a short-lived `organization.reactivate` Grant from the approved identity/bootstrap service as a Bootstrap Grant analogue, keyed to subject and target Organization, MFA-attested, consumed by the command.
- Recommended Option: Option 1
- Evidence Supporting The Recommendation:
  - WF-013 requires reactivation "through fresh managed identity and MFA" and lists `identity_assurance_failed` in its first-match order, so a proof artifact is presupposed but never named.
  - The WF-001 receipt purpose enum carries MFA evidence only on `existing_account_sign_in`, whose first-match order rejects a suspended Account and an inactive Organization categorically.
  - Option 1 creates no Session, so the [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) rule binding Session creation to WF-001 and the [../017 ERROR_MODEL.md](../017%20ERROR_MODEL.md) exhaustive seven outward sign-in reasons are both untouched, and no PM-REQ-009 controlled foundation change is required.
  - [../014 SECURITY_MODEL.md](../014%20SECURITY_MODEL.md) delegates receipt issuance to the approved identity service and prohibits no additional purpose; the Permission Baseline `organization.reactivate` grant to OrganizationAdmin is preserved literally.
- Benefits: Satisfies the MFA predicate literally, keeps the OrganizationAdmin path, and resolves the defect entirely inside Volume I with the lowest blast radius.
- Costs: The identity service must issue a receipt against a tenant the actor cannot sign into, and Volume II must expose an inactive-tenant physical entry path; Option 2 collides with the frozen sign-in contract and requires a PM-REQ-009 change before it may be approved; Option 3 adds a second grant type for the same guarantee.
- Risks: A proof not bound to subject and target Organization, or reusable, admits an unapproved actor into a suspended tenant; leaving the defect open keeps `identity_assurance_failed` unreachable and lets the Account-reactivation twin drift.
- Security Implications: Reactivation is the only ordinary mutation admitted while suspended, so the proof's subject/Organization binding, freshness, single consumption, and MFA attestation are the controlling security choices; no option may let F1 receive, store, or validate raw credentials or factor values.
- Data Implications: Adds one receipt purpose or grant record to receipt/grant persistence and to the API forbidden-attributes list; the proof's plaintext must never surface in a response attribute.
- AI Implications: None.
- Operational Implications: Until approval no suspended Organization can be reactivated by its own admin, so the interim withholds suspension itself rather than allowing a tenant to enter a state it cannot leave.
- Commercial Implications: Organization suspension and self-service reactivation are unavailable as product behaviour, and no contractual claim about tenant suspension or recovery may be made until approval.
- Reversibility: Medium; purpose enum and binding are versioned, but any proof already accepted cannot be un-accepted.
- Ratified Behavior: A fifth purpose-bound Identity Validation Receipt purpose `organization_reactivation` exists, carrying the assurance version and `mfa_satisfied=true`, bound to Organization ID, issuer and subject, with a 10-minute expiry, nonce-consumed only by the reactivation command, and creating no Session. `ReactivateOrganization` is reachable through that receipt and through no other proof: no sign-in relaxation and no raw provider proof is admitted. This governs `organization.reactivate` only and decides nothing about the separate `account.reactivate` predicate governed by OD-021.
- Latest Responsible Decision Point (met on 2026-07-17): Before Volume II exposes any Organization lifecycle control, and before any contractual claim about tenant suspension or reactivation.
- Blocking Impact: None. OD-022 is resolved; `ReactivateOrganization` is reachable through the approved `organization_reactivation` receipt purpose.
- ADR Threshold: Met; this decision is recorded in ADR-019.
- Owner Required: Chief Architect and Chief Security
- Approval Record: The 2026-07-17 ratification session recorded this decision as ratified 'as specified' without naming an option; what was specified was an interim that approved no option and left the behaviour unreachable. The owner decided it explicitly in [OWNER_DECISION_SUPPLEMENT_2026-07-17.md](OWNER_DECISION_SUPPLEMENT_2026-07-17.md). Integrated by ADR-019.

### OD-023 Credential Rotation Token And Material Contract

- Decision ID: OD-023
- Exact Question: Which issuing authority, permission, entropy and wire format, TTL and equality boundary, one-use consumption point, binding tuple, retry/replay behavior, and new-material reference transport define the "fresh rotation token" that `integration-interim-v1` requires to rotate a Credential?
- Classification: C
- Current Status: Pending owner approval
- Why The Decision Exists: [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md#approved-integration-and-credential-contract-integration-interim-v1) requires "a fresh rotation token" to begin rotation and an "authorized new rotation token" to retry, but defines no issuer, operation, format, lifetime, consumption point, binding, or transport for the replacement material; deny-by-default forbids inferring any of them, and whether an operator may mint authority to replace a live provider secret is a security and operational risk choice, not an architectural inference.
- Affected Capabilities: CAP-021
- Affected Workflows: WF-014
- Affected Product Rules: PRULE-034
- Affected Foundation Requirements: SEC-REQ-004, SEC-REQ-005, SEC-REQ-006, SEC-REQ-015, SEC-REQ-016, SEC-REQ-020, SM-REQ-007, SM-REQ-010
- Affected Acceptance Criteria: AC-CAP-021, AC-WF-014, AC-PRULE-034
- Options:
  1. Opaque database capability token minted by a SecurityOperator in an active Support Session under a new explicit `credential.rotation_token.issue` permission, bound to Organization, Integration, Credential, Credential state version, adapter policy identity, and issuing actor, with the new secret-store material reference supplied as explicit `BeginCredentialRotation` input and the token consumed at the atomic `active -> rotating` commit.
  2. Signed self-contained token issued by the release/security service, embedding the binding tuple and material reference and verified by signature.
  3. Direct secret-reference input where the token is a pure authorization/idempotency nonce and the lifecycle service selects the new material from the secret store's staged version.
- Recommended Option: Option 1, with `credential-rotation-blocked-interim-v1` as the deterministic interim until approval; no option may introduce the prohibited `rotating to pending` edge without a PM-REQ-009 controlled foundation change.
- Evidence Supporting The Recommendation:
  - [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) already makes materialization and rotation "idempotent by content/rotation token" and requires an authorized retry to retain `rotating` with a fresh token, which a persisted opaque token satisfies directly.
  - The Credential record already carries a `rotation token` field distinct from the idempotency key, so exact replay requires the token in the database regardless of issuer; Option 2 therefore adds signing-key management and weak revocation without avoiding persistence.
  - Option 3 does not pin the authorized material at issue time, so what the token authorizes can change before commit, weakening the SEC-REQ-020 audit chain.
  - Deny-by-default in [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md#permission-baseline) requires any token-issuance permission to be added explicitly to the Permission Baseline rather than inferred from `credential.rotate`.
- Benefits: Restores a bounded, server-side revocable, replay-exact rotation path with named authority and the smallest new surface.
- Costs: Two operator round-trips, plus a new permission, token record, and token-specific error and event reasons.
- Risks: A weakly bound, long-lived, or non-consumed token authorizes replacement of a live provider secret; a signing-key issuer adds a key that itself needs rotation.
- Security Implications: The token is the sole authorization for replacing a live provider secret, so its binding tuple, one-use consumption point, revocability, and SEC-REQ-020 auditability are the controlling security choices.
- Data Implications: The token persists on the Credential as a reference only and never carries secret bytes; [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md#approved-integration-and-credential-contract-integration-interim-v1) currently contradicts [../../schemas/POSTGRESQL_SCHEMA.md](../../schemas/POSTGRESQL_SCHEMA.md), which states no rotation-token column, and the two MUST be reconciled on correction.
- AI Implications: None.
- Operational Implications: Without rotation, compromise response is revocation plus a new Credential, which is destructive and may end Organization email delivery until a controlled correction.
- Commercial Implications: No secret-rotation claim may be made until approval, and enterprise contracts commonly require a stated rotation and maximum age policy.
- Reversibility: Medium; the token contract is versioned and replaceable, but prior secret-store material destroyed within 60 seconds of a successful rotation cannot be restored.
- Safe Interim Behavior: Rotation is unreachable and fails closed under `credential-rotation-blocked-interim-v1`: no token issuer, permission, operation, route, wire format, or TTL exists, so every mint request is denied as an undefined permission under [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md#permission-baseline); `BeginCredentialRotation` remains registered but unreachable and `CompleteCredentialRotation` has no independent entry, so no path sets pending material, enters `rotating`, or accepts replacement material; no `CredentialRotationStarted` or `CredentialRotated` emission, outbox or Notification route, `credential_rotation_retry` scheduled action, or rotation DDL function or grant exists; `rotating` and the pending-material pointer remain reserved-but-unreachable exactly as [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) conceptually models them; Credential revocation, expiry, and Integration isolation remain fully available under their separate contracts; compromise response is revocation plus a new Credential, recorded explicitly as destructive, plausibly ending Organization email delivery until a controlled correction, and not an equivalent substitute for rotation. This interim does not satisfy SEC-REQ-016, is not a security conclusion, and does not approve any option.
- Latest Responsible Decision Point: Before storing a real Mailgun provider secret in production, and before any contractual secret-rotation claim.
- Blocking Impact: Volume II — no; the path is absent rather than ambiguous and `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` correctly refuses to resolve it; implementation — no under the fail-closed interim and prelaunch operation with synthetic secrets; production — storing a real Mailgun provider secret is blocked because SEC-REQ-016 requires a defined per-credential-class rotation and maximum age policy that the interim does not supply; feature — every rotation behaviour and any contractual secret-rotation claim are blocked until approval.
- ADR Threshold: Required if a new token-issuance authority role is created or the rotation architecture changes materially; SM-REQ-010 additionally requires ADR governance for any transition-authority change.
- Owner Required: Chief Security and Chief Product
- Exact Approval Wording: Each required owner signs the identical statement: “I approve OD-023 Option [selected] and the accompanying rotation token package [identity and immutable version], canonical SHA-256 [digest], effective [UTC time]. I separately approve its recorded issuing authority and permission, token entropy and wire format, TTL and equality boundary, one-use consumption point relative to the `active -> rotating` commit, exact binding tuple, exact-replay versus conflict behavior, new-material reference transport, retry material reuse-versus-replace rule, and the SEC-REQ-016 per-credential-class maximum age policy; approval of one item does not imply approval of another.”

### OD-024 Historical Comparison Event Occurrence And Identity

- Decision ID: OD-024
- Exact Question: Does WF-012 emit `ComparisonGenerated`, and under which event profile and identity, such that repeated reads of the same snapshot pair emit at most one event?
- Classification: C
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; resolved by owner decision
- Approved Outcome: `ComparisonGenerated` is removed as a Volume I domain event. Comparison behaviour remains; no domain event is emitted. This matches enumerated Option 2. It may be introduced in a later specification revision.
- Why The Decision Exists: WF-012 names `ComparisonGenerated` while declaring no domain entity transition, and no Comparison aggregate exists in the domain model or schema, so no event profile row can be satisfied and occurrence, identity, and replay behavior cannot be inferred.
- Affected Capabilities: CAP-019
- Affected Workflows: WF-012
- Affected Product Rules: PRULE-032, PRULE-046
- Affected Foundation Requirements: DM-REQ-013, DM-REQ-016, DM-REQ-017
- Affected Acceptance Criteria: AC-CAP-019, AC-WF-012, AC-PRULE-032, AC-PRULE-046
- Options:
  1. Persist an immutable Comparison Decision under the `decision` profile at precedence 6, keyed by organization, project, the ordered snapshot pair, the governing version set, and the nullable rebase snapshot pair; repeated reads of the same identity return the stored decision and emit nothing; `compatible` and `not_comparable` emit, `insufficient_history` and `comparison_unavailable` do not.
  2. Delete `ComparisonGenerated` from WF-012; the comparison read is audit-only and emits no domain event.
  3. Define a versioned comparison read model under the `projection` profile at precedence 7, keyed by the snapshot pair, emitting only on create or change.
- Recommended Option: Option 2, unless Chief Product establishes a durable comparison-usage signal as a product requirement, in which case Option 1.
- Evidence Supporting The Recommendation:
  - WF-012 declares no domain entity transition and is triggered by a safe read with no command; Option 2 alone leaves the read side-effect-free.
  - No Comparison aggregate exists in the domain model, state model, or schema, so neither the `decision` nor `projection` profile can be satisfied without a PM-REQ-009 controlled foundation change and a new ADR.
  - The foundation cross-context event list is a stated minimum under ADR-015 and never named `ComparisonGenerated`, so removal violates no foundation requirement.
  - WF-012's audit obligations are discharged entirely by Audit Evidence with correlation ID, so no comparison outcome depends on the event.
- Benefits: Keeps the comparison read side-effect-free, requires no new entity, table, lifecycle, error, or observability coverage, and closes the DM-REQ-016 and DM-REQ-017 coverage gap by removing the pathway.
- Costs: Loses a durable comparison-usage signal and the event as a future metering or analytics hook; Options 1 and 3 instead require a controlled foundation change across domain, state, error, observability, lifecycle, schema, and diagram documents.
- Risks: Emitting under a guessed identity double-counts on re-open, Turbo Frame fetch, or prefetch; removing the event forecloses a signal that any later reintroduction must obtain through controlled change.
- Security Implications: None direct; tenant scoping, `history.read` authorization, and field-level redaction on comparison reads are unchanged under every option.
- Data Implications: Options 1 and 3 persist a new record requiring a new table, with Option 1 writing into `product_history` under 7-year retention; Option 2 persists nothing.
- AI Implications: None; CAP-019's structured-only, no-AI-narrative baseline under ADR-017 is orthogonal and preserved verbatim under every option.
- Operational Implications: Options 1 and 3 add writes, and Option 3 adds cache invalidation, to a read path; every option must reconcile WF-012's "Missing projection data" and "Projection rebuild" language with the chosen model or clarify that it refers to the Current Score Projection.
- Commercial Implications: Option 1 preserves the event as a future metering or analytics hook; Option 2 removes it, so later usage-based comparison metering requires controlled reintroduction.
- Reversibility: Mixed; Option 2 is reversible by controlled change because nothing is persisted, while events emitted under Option 1 enter 7-year `product_history` retention and a wrong identity must be corrected in persisted tenant data.
- Ratified Behavior: `ComparisonGenerated` is removed as a Volume I domain event, matching enumerated Option 2. The WF-012 comparison read is audit-only and side-effect-free and emits no domain event; no comparison record is persisted and no current pointer moves. The `compatible`, `insufficient_history`, `not_comparable` and `comparison_unavailable` outcomes remain fully deterministic under [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md), and WF-012's audit obligations are discharged entirely by Audit Evidence with correlation ID. QRY-008 and WF-012 are unblocked read-only. The foundation cross-context event list is a stated minimum under ADR-015 and never named `ComparisonGenerated`, so this removal is not a foundation change. Reintroduction requires controlled change.
- Latest Responsible Decision Point (met on 2026-07-17): Before any `ComparisonGenerated` event is emitted into 7-year `product_history` retention.
- Blocking Impact: None. OD-024 is resolved; comparison reads are unblocked and emit no domain event.
- ADR Threshold: Not met. Option 2 was approved; the foundation never named `ComparisonGenerated`, so no controlled foundation change arises. The decision is recorded in ADR-019.
- Owner Required: Chief Product and Chief Architect
- Approval Record: Resolved by owner decision in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). Integrated by ADR-019.

### OD-025 ReassessmentTriggered Occurrence And Affected Entity Binding

- Decision ID: OD-025
- Exact Question: At which point does WF-011 emit `ReassessmentTriggered`, to which affected entity and event profile is it bound, and does the Entitlement-blocked branch emit it?
- Classification: C
- Current Status: Ratified on 2026-07-17 by the Product Owner exercising Chief Product, Chief Architect and Chief Security authority; resolved by owner decision
- Approved Outcome: `ReassessmentTriggered` is removed as a canonical domain event. Reassessment continues to execute deterministically; no trigger event is emitted. This outcome is not among the enumerated options, all of which retained the event, and is recorded as an owner decision rather than an option number. Applied to the WF-011 coverage row in [../018 OBSERVABILITY.md](../018%20OBSERVABILITY.md) as a PM-REQ-009 controlled foundation change under ADR-019.
- Why The Decision Exists: [../018 OBSERVABILITY.md](../018%20OBSERVABILITY.md) requires an admitted scheduled or manual run to emit one provenance-complete `ReassessmentTriggered` but defines no `admitted`; WF-011 records `admitted` at the schedule decision before Entitlement, while PRULE-033 binds every admitted run to one new Evaluation, so the Entitlement-blocked branch — which creates an Entitlement Decision and a failed Reassessment Result but no Evaluation — is either an admitted run that must emit or a branch with no representable affected entity for the mandatory nonnull envelope. Whether a blocked reassessment is observable as triggered is an observability and product choice, not an architectural inference.
- Affected Capabilities: CAP-007, CAP-015, CAP-019, CAP-020
- Affected Workflows: WF-011
- Affected Product Rules: PRULE-033
- Affected Foundation Requirements: OBS-REQ-022, DM-REQ-013, DM-REQ-014, SM-REQ-003
- Affected Acceptance Criteria: AC-CAP-020, AC-WF-011, AC-PRULE-033
- Options:
  1. Emit only for a run that creates an Evaluation: one `ReassessmentTriggered` inside the atomic Evaluation-creation commit with affected entity `evaluation` and profile `created`; the Entitlement-blocked branch emits one `ReassessmentFailed` with reason `entitlement_blocked` and the linked Entitlement Decision instead.
  2. Emit for every admitted trigger at the Entitlement checkpoint: one `ReassessmentTriggered` at the `reassessment.start` Decision in both the executable and blocked branches, with affected entity `entitlement_decision` and profile `decision`.
  3. Introduce a first-class reassessment run entity: persist the Project orchestration guard record as a named entity created at the trigger point, with affected entity `reassessment_run` and profile `created`, uniform across both branches and both provenances.
- Recommended Option: Option 1
- Evidence Supporting The Recommendation:
  - PRULE-033 binds every admitted run to one new Evaluation already Running before nested Crawl, which reads the emission point at Evaluation creation literally.
  - DM-REQ-013 and the `created` profile are satisfiable only where the affected aggregate exists; the literal trigger point in [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md#wf-011-trigger-reassessment) precedes any representable entity, and an immutable Reassessment Result cannot exist non-terminally at that point.
  - The `EventEntityType` enum in [../volume-ii/API_CONTRACTS.md](../volume-ii/API_CONTRACTS.md) admits no reassessment run entity in major 1, so Option 3 exceeds ADR-017's stated correction constraints and cannot ride that ADR.
- Benefits: Emits no event for a branch that produced no work, satisfies every envelope and profile field, and unblocks WF-011 execution within the existing event catalogue shape.
- Costs: An entitlement-blocked reassessment never appears as triggered in the domain-event stream.
- Risks: Option 2 is semantically strained, binds a trigger event to an entitlement artifact, and likely duplicates the entitlement decision event; Option 3 requires a new entity type, a new table, and its own ADR; under Option 1 blocked-run observability rests entirely on `ReassessmentFailed` and the linked Entitlement Decision.
- Security Implications: Domain events are immutable and retained, so an event emitted on the blocked branch permanently publishes plan-limit facts into customer-visible and audit-visible history that cannot be retracted.
- Data Implications: Every event MUST carry nonnull `affected_entity_type`, `affected_entity_id`, and `aggregate_version`; a declared semantics set matching none or more than one profile row fails production as `F1-DATA-409 / event_profile_unmapped` before publication; Option 3 additionally requires a new `EventEntityType` value, a new table, and lifting the event-registry manifest exclusion in [../../schemas/POSTGRESQL_SCHEMA.md](../../schemas/POSTGRESQL_SCHEMA.md).
- AI Implications: None.
- Operational Implications: Under Option 1, blocked-run investigation reconstructs from `ReassessmentFailed`, the linked Entitlement Decision, and Audit Evidence rather than from a uniform trigger event.
- Commercial Implications: Plan-limit and upgrade telemetry for blocked reassessments must be reconstructed from `ReassessmentFailed` plus the Entitlement Decision rather than read from one trigger event.
- Reversibility: Asymmetric; a not-yet-emitted event can be widened later through a versioned event-contract change under DM-REQ-014 and [../019 VERSIONING.md](../019%20VERSIONING.md) without rewriting history, while an already-emitted event is immutable and cannot be retracted.
- Ratified Behavior: `ReassessmentTriggered` is removed as a canonical domain event and the WF-011 coverage row in [../018 OBSERVABILITY.md](../018%20OBSERVABILITY.md) is amended by the PM-REQ-009 controlled foundation change recorded in ADR-019. Reassessment remains fully observable through already-accepted mechanisms and no replacement event is invented: `ReassessmentScheduleEvaluated` for every ordinary or latest-coalesced due slot; the manual command's Audit Evidence under SM-REQ-004 for manual provenance; `EvaluationStarted` inside the atomic Evaluation-creation commit for a run that executes; `ReassessmentCompleted` for successful replacement; and `ReassessmentFailed`, `ReassessmentCanceled` and the linked Entitlement Decision for the non-executing branches. Trigger provenance, comprising `trigger_kind`, nullable policy identity, version and content hash, slot number and due time, is retained on the Reassessment Result record and its Audit Evidence. The Entitlement-blocked branch emits no trigger event because no trigger event exists, so the previously unresolvable affected-entity question does not arise.
- Latest Responsible Decision Point (met on 2026-07-17): Before the first production reassessment run emits a retained `ReassessmentTriggered`, because emitted domain events are immutable and cannot be retracted.
- Blocking Impact: None. OD-025 is resolved; reassessment scheduling, manual and scheduled execution are unblocked and remain observable through accepted mechanisms.
- ADR Threshold: Met; this decision is recorded in ADR-019.
- Owner Required: Chief Architect and Chief Product
- Approval Record: Resolved by owner decision in the 2026-07-17 owner ratification session, [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md). Integrated by ADR-019.

### OD-026 Last-Administrator Expiry Block Record And Notification Route

- Decision ID: OD-026
- Exact Question: When a timed Role Assignment expiry would remove an Organization's last effective OrganizationAdmin, which record does the block write, does the Assignment stay effective past `expires_at_utc`, and on what mandatory route, permission, and severity is `RoleExpiryBlocked` notified?
- Classification: C
- Current Status: Resolved on 2026-07-17 by explicit Product Owner decision recorded in [OWNER_DECISION_SUPPLEMENT_2026-07-17.md](OWNER_DECISION_SUPPLEMENT_2026-07-17.md)
- Approved Option: Option 1 — define `RoleExpiryBlockDecision` as a `decision` record, amend the effectiveness predicate so an Assignment carrying `expiry_blocked_last_admin` stays effective past `expires_at_utc` until the guard clears, and re-evaluate on each Organization authorization-epoch advance, with the mandatory `RoleExpiryBlocked` route row added
- Why The Decision Exists: WF-013 mandates that the blocked expiry leave the Assignment active with `expiry_blocked_last_admin`, emit `RoleExpiryBlocked`, raise a mandatory security/OrganizationAdmin notification, and retry until a replacement is active, but the same contract's status set excludes that value, its effectiveness predicate makes the Assignment inactive at `expires_at_utc`, no record kind fills the `attempt` or `decision` profile fields the event envelope requires, and the baseline route table has no `RoleExpiryBlocked` row that any actor is authorized to add; whether an Assignment may outlive its stated expiry, or a tenant may be deliberately left admin-less, is a security and risk choice, not an architectural inference.
- Affected Capabilities: CAP-001, CAP-021, CAP-025
- Affected Workflows: WF-013, WF-014
- Affected Product Rules: PRULE-034, PRULE-042, PRULE-044, PRULE-045
- Affected Foundation Requirements: SM-REQ-001, SM-REQ-002, SM-REQ-003, SEC-REQ-004, SEC-REQ-005, SEC-REQ-006, SEC-REQ-013, OBS-REQ-019
- Affected Acceptance Criteria: AC-CAP-001, AC-CAP-021, AC-CAP-025, AC-WF-013, AC-WF-014, AC-PRULE-034, AC-PRULE-042, AC-PRULE-044, AC-PRULE-045
- Options:
  1. Immutable authorization-decision record plus epoch-driven retry: define `RoleExpiryBlockDecision` as a `decision` record, amend the effectiveness predicate so an Assignment carrying `expiry_blocked_last_admin` stays effective past `expires_at_utc` until the guard clears, and re-evaluate on each Organization authorization-epoch advance.
  2. Failed-timed-attempt record plus bounded retry with terminal ceiling: define a `role_assignment_expire` attempt record, keep the Assignment effective only for an owner-named grace window, then commit the expiry at the ceiling and leave the tenant admin-less pending platform support.
  3. Promote the block to a real lifecycle status: add `expiry_blocked` to the Assignment status set with edges `active -> expiry_blocked -> expired|active`, attaching effectiveness to the status rather than the clock.
- Recommended Option: Option 1, with the mandatory `RoleExpiryBlocked` route row added under every option.
- Evidence Supporting The Recommendation:
  - WF-013 deliberately mandates the block, the record, the route, and the retry, so withdrawing the behaviour is an owner decision rather than a derivation.
  - `expiry_blocked_last_admin` appears exactly once in Volume I and is defined nowhere as a status, record, or route, while the Role Assignment status set and effectiveness predicate contradict it directly.
  - Event profile mapping is first-match and fails production before publication as `F1-DATA-409 / event_profile_unmapped` when semantics match none or more than one row, so the record kind must be chosen before the event can exist.
  - No actor may add a mandatory route: `policy.notification.manage` permits OrganizationAdmin optional informational routes only, and SecurityOperator only security templates, the support-queue roster, and critical selectors.
  - Option 1 is the only repair that preserves the mandatory expiry no later than 30 days after effectiveness that makes the `role.manage` grant protected, and it never silently strands the tenant.
- Benefits: Keeps the tenant self-recoverable without a new lifecycle status or a controlled foundation change, and yields a well-formed `decision` event under the first-match profile order.
- Costs: Requires a Volume I change to the effectiveness predicate, one new immutable record contract, a named retry schedule, one baseline route row, and a Role trigger-specific notification context variant.
- Risks: Option 1 lets an Assignment outlive its stated expiry indefinitely; Option 2 requires an owner-named window and an explicit decision to strand the tenant, contradicting "never silently strands" unless that clause is amended; Option 3 carries the largest blast radius and needs a PM-REQ-009 controlled foundation change before approval.
- Security Implications: An Assignment effective past its stated expiry weakens the accountability ceiling that makes `role.manage` protected, and the route's recipients, required permission, and severity determine whether loss of that guarantee reaches an actor who can act on it.
- Data Implications: Adds either one immutable record carrying authority identity, policy versions, and nonnull `input_hash`/`output_hash`, or a new Assignment status that every consumer and the OrganizationMembership derivation must recognize.
- AI Implications: None.
- Operational Implications: Recovery depends on the authorization-epoch retry once approved, and until then on an operator escalation and the security-bootstrap path rather than tenant self-service.
- Commercial Implications: Tenant self-service recovery and platform-support recovery differ materially in support cost and outage duration; no packaging or contractual claim is implied.
- Reversibility: Medium; the record kind, retry schedule, and route may be re-versioned, but authority already extended past a stated expiry cannot be withdrawn retroactively and Option 3's status enters the foundation state registry.
- Ratified Behavior: A blocked last-administrator expiry writes an immutable `RoleExpiryBlockDecision` `decision` record. The effectiveness predicate is amended so an Assignment carrying the `expiry_blocked_last_admin` block reason stays effective past `expires_at_utc` until the guard clears, and is re-evaluated on each Organization authorization-epoch advance; the owner expressly accepted that an Assignment may remain effective beyond its stated expiry. `expiry_blocked_last_admin` is a block reason carried by the decision record, not an Assignment status: the Assignment status set remains `pending`, `active`, `rejected`, `revoked` and `expired`. The mandatory `RoleExpiryBlocked` notification route row exists with its recipients, required permission and severity. No tenant is deliberately left without an effective administrator.
- Latest Responsible Decision Point (met on 2026-07-17): Before any production tenant may revoke its null-expiry bootstrap OrganizationAdmin Assignment, that is, before production onboarding of a second administrator.
- Blocking Impact: None. OD-026 is resolved; the last-administrator expiry block is reachable, deterministic and audited.
- ADR Threshold: Met; this decision is recorded in ADR-019.
- Owner Required: Chief Security and Chief Product
- Approval Record: The 2026-07-17 ratification session recorded this decision as ratified 'as specified' without naming an option; what was specified was an interim that approved no option and left the behaviour unreachable. The owner decided it explicitly in [OWNER_DECISION_SUPPLEMENT_2026-07-17.md](OWNER_DECISION_SUPPLEMENT_2026-07-17.md). Integrated by ADR-019.

### OD-027 ParsingJob To IndexingJob Cardinality And Persistence Model

- Decision ID: OD-027
- Exact Question: Does ParsingJob to IndexingJob persist as one-to-many keyed by `(parsed_artifact_id, content_sha256, index_target_id, index_schema_version)`, or as at most one IndexingJob per ParsingJob keyed by `parsing_job_id`?
- Classification: C
- Current Status: Pending owner approval
- Why The Decision Exists: [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md) line 124 labels the relationship `1 to many` but imposes only a child-side MUST over an undefined "outcome batch", while `indexing-interim-v1` pins both index keys by CHECK so exactly one IndexingJob per successful ParsingJob is the only reachable Volume I shape; both persistence models satisfy every controlling text and differ in migration, association, query surface, caller code, and upgrade behaviour.
- Affected Capabilities: CAP-008
- Affected Workflows: WF-006
- Affected Product Rules: PRULE-009
- Affected Foundation Requirements: DM-REQ-007, SM-REQ-003, SM-REQ-005, PM-REQ-003
- Affected Acceptance Criteria: AC-CAP-008, AC-WF-006, AC-PRULE-009
- Options:
  1. `has_many :indexing_jobs` with unique `(parsed_artifact_id, content_sha256, index_target_id, index_schema_version)`, modelling the foundation's permanent shape.
  2. `has_one :indexing_job` with unique `(parsing_job_id)`, modelling the interim's provable at-most-one invariant.
- Recommended Option: Option 1
- Evidence Supporting The Recommendation:
  - DOMAIN_MODEL.md:124 states `1 to many` and its only MUST is child-side, which Option 1 satisfies without narrowing anything.
  - The same table writes `0 to many` at :131 and `1 to many over retained history` at :132, so the cardinality column marks narrowings explicitly; reducing :124 to `0..1` is the DM-REQ-007 exception Option 2 must carry.
  - [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) line 106 requires retries "idempotent by index target and source snapshot", which is the four-column key rather than `parsing_job_id`.
  - [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md) line 392 keeps the many-side reachable: "a changed Artifact digest or index version creates a distinct job and never replaces an earlier receipt".
  - [../../schemas/POSTGRESQL_SCHEMA.md](../../schemas/POSTGRESQL_SCHEMA.md) line 318 already implements Option 1, so it requires no migration and no frozen-text change under DECISIONS.md:296.
- Benefits: Preserves the index-version upgrade path without a later migration; leaves every rank-2 and rank-5 artifact as written.
- Costs: Permits a row shape Volume I can never produce, so callers must not assume singularity; Option 2 costs a uniqueness-key migration plus a DM-REQ-007 exception.
- Risks: If `1 to many` at :124 carries a minimum, Option 2 conflicts with a foundation requirement and cannot be approved without a PM-REQ-009 controlled foundation change; "outcome batch" is undefined repository-wide, so either approval rests on an unglossed term.
- Security Implications: None direct; both models retain WF-006 same-Organization reference and tenant-scoped service execution unchanged.
- Data Implications: Option 1 keeps POSTGRESQL_SCHEMA.md:318 as written; Option 2 migrates the uniqueness key and forecloses a second row per ParsingJob without a further migration.
- AI Implications: None directly; indexing is a non-gating Retrieval projection and never grounds a sealed Evaluation.
- Operational Implications: Option 2 narrows the replay and upgrade surface, since a future index-version upgrade would require a migration before it could create a distinct job.
- Commercial Implications: None direct.
- Reversibility: Medium; the two keys are extensionally identical while `indexing-interim-v1` remains active, but association shape, caller assumptions, and upgrade behaviour diverge once either is fixed in Volume II.
- Safe Interim Behavior: Persist `indexing_jobs` exactly as [../../schemas/POSTGRESQL_SCHEMA.md](../../schemas/POSTGRESQL_SCHEMA.md) already defines it, with unique `(parsed_artifact_id, content_sha256, index_target_id, index_schema_version)` and no `has_one` association and no `unique (parsing_job_id)` constraint. Because `indexing-interim-v1` pins `index_target_id` and `index_schema_version` by CHECK and STATE_MODEL.md:106 forbids `succeeded -> running`, each successful ParsingJob yields exactly one IndexingJob; any attempt to create a second IndexingJob for the same ParsingJob is rejected by that unique constraint and writes nothing. This forecloses neither model and does not approve any option.
- Latest Responsible Decision Point: Before the Volume II `indexing_jobs` association and migration are fixed.
- Blocking Impact: Volume II — no; implementation — no under the safe interim; production — no while `indexing-interim-v1` pins both index keys; feature — a `has_one` narrowing, a `unique (parsing_job_id)` constraint, and any second IndexingJob per ParsingJob are blocked until approval.
- ADR Threshold: Required if Option 2 is approved, because narrowing DOMAIN_MODEL.md:124's `1 to many` is a DM-REQ-007 cardinality exception; Option 1 requires none.
- Owner Required: Chief Architect and Chief Rails
- Exact Approval Wording: I approve OD-027 Option 1 as the Volume I ParsingJob-to-IndexingJob cardinality and persistence model and authorize corresponding specification updates.

### OD-028 Retention Expiry Reassessment Trigger Authority — WITHDRAWN

- Decision ID: OD-028
- Current Status: Withdrawn on 2026-07-17 by the RC1 correction programme under ADR-018. Superseded by OD-029; no owner approval is required or possible for this identifier.
- Reason For Withdrawal: OD-028 and OD-029 were registered independently against the same single clause in [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md): "At 30 days before a current `product_evidence_payload` maximum, the lifecycle service emits `EvidenceRetentionExpiring` once and requests reassessment when the Project remains active." That sentence states one obligation on one actor with two inseparable halves. Registering it twice produced two authoritative dispositions for one unresolved clause, with contradictory production gates, different owner sets, and mutually decidable approval paths — OD-028's Option 3 would have struck the reassessment request while OD-029's Option 2 would simultaneously approve one. A clause may have exactly one authoritative disposition.
- Authoritative Successor: OD-029, whose Exact Question already covers both halves of the clause. Every option, interim, owner, gate, and approval consequence for the retention-expiry warning and its reassessment request is governed solely by OD-029.
- Identifier Treatment: This identifier is retained as an auditable withdrawn record and MUST NOT be reused for a different decision. Later decisions are not renumbered. Existing references to OD-028 in [TRACEABILITY_MATRIX.md](TRACEABILITY_MATRIX.md) and elsewhere resolve here and are to be read as references to OD-029.
- Behavioural Effect Of Withdrawal: None. Both interims withheld the same behaviour, so no path changes state. The reconciled production gate is OD-029's — production is blocked, not permitted — because a foundation `MUST` in [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md) that is never satisfied cannot be shipped, and PM-REQ-003 places the foundation layer above Volume I. OD-028's contrary "production — no" reading is void.
- Audit Trail: the withdrawn brief's full text remains recoverable from version control; it is not retained here, because keeping its contradictory production gate and approval wording in the register is the defect this withdrawal corrects.
- Scope Formerly Claimed: CAP-013, CAP-020, CAP-021; WF-008, WF-011, WF-014; PRULE-016, PRULE-033, PRULE-034, PRULE-043; AC-CAP-013, AC-CAP-020, AC-CAP-021, AC-WF-008, AC-WF-011, AC-WF-014, AC-PRULE-016, AC-PRULE-033, AC-PRULE-034, AC-PRULE-043. This scope is now governed by OD-029. It is listed here only so that a reader arriving from a traceability row can see what moved.

- Withdrawn Record Ends: no option, interim, owner, gate, or approval wording applies to OD-028. See OD-029.

### OD-029 Evidence Retention Warning Producer Assignment

- Decision ID: OD-029
- Exact Question: Which workflow, service authority, and event profile own production of the `EvidenceRetentionExpiring` warning and its reassessment request 30 days before a current `product_evidence_payload` retention maximum?
- Classification: C
- Current Status: Pending owner approval
- Why The Decision Exists: [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md) line 191 mandates that "the lifecycle service emits `EvidenceRetentionExpiring` once and requests reassessment when the Project remains active", but no Volume I workflow declares the event, no decision record exists to resolve its `event_profile`, and [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md) lines 101 and 127 make an event without a `workflow_id` and `event_profile` unproducible; which workflow owns Evidence retention timing is a scope choice, not an architectural inference.
- Affected Capabilities: CAP-013
- Affected Workflows: WF-007, WF-011, WF-013
- Affected Product Rules: PRULE-016
- Affected Foundation Requirements: DLC-REQ-012
- Affected Acceptance Criteria: AC-CAP-013, AC-PRULE-016, AC-WF-007, AC-WF-011, AC-WF-013
- Options:
  1. Extend WF-013 to own Evidence Payload retention, broadening its Purpose, Actors, Related Capabilities, and Preconditions and adding the event to its domain events.
  2. Assign production to WF-007, extending its Trigger to include the Evidence Payload retention deadline and adding the event alongside `EvidenceValidationChanged`, with the integrity-validation service as authority.
  3. Create a new WF-019 Evidence Retention Lifecycle workflow owning the warning, expiry determination, hold quarantine, payload destruction, and reassessment request.
- Recommended Option: Option 2
- Evidence Supporting The Recommendation:
  - CAP-013 is WF-007's capability and carries the frozen AC-CAP-013 30-day-before-expiry criterion, so the warning and the expiry it warns about stay in one workflow.
  - [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) line 108 makes the Evidence Context integrity-validation service the sole Evidence authority and lists `EvidenceValidationChanged` as its only event.
  - The 24-month expiry itself produces a Validation Decision that already lands in WF-007, so one service and one aggregate own the whole retention transition.
  - WF-013's Related Capabilities exclude CAP-013 and its deletion-job machinery never fires for routine payload expiry, so its "retention deadline" trigger text does not reach this event.
  - Option 3 breaks the "18 canonical workflows" count and widens the closed `workflow_id` enum in [../volume-ii/API_CONTRACTS.md](../volume-ii/API_CONTRACTS.md) for one event.
- Benefits: Fewest frozen-document amendments; keeps a single Evidence authority; makes the frozen AC-CAP-013 and AC-PRULE-016 warning criteria executable.
- Costs: Requires reading "the lifecycle service" at 015:191 as generic and extends an evaluation workflow with a timed-deadline trigger.
- Risks: WF-007 gains a scheduling concern it was not designed for; Option 3 splits Evidence authority; Option 1 makes an Organization-scoped workflow Project-scoped and system-driven.
- Security Implications: Any producer requires a service-identity row in the Permission Baseline, or deny-by-default refuses it; the warning grants no new data access.
- Data Implications: Requires a defined `evidence_retention` decision record so the `decision` profile resolves, and an added event on the Evidence row of the state model.
- AI Implications: None direct; the expiry path preventing expired Evidence from grounding AI output is independently specified and unaffected.
- Operational Implications: `evidence_retention_warning` in [../volume-ii/BACKGROUND_PROCESSING.md](../volume-ii/BACKGROUND_PROCESSING.md) exists as a job but serializes no event, and WF-011's Trigger admits no lifecycle-originated reassessment request.
- Commercial Implications: Any customer claim of advance notice before evidence expiry depends on this producer existing.
- Reversibility: Medium; reassignment later requires a controlled change to frozen Volume I workflow, capability, rule, and acceptance documents.
- Safe Interim Behavior: The platform serializes no `EvidenceRetentionExpiring`, invents no retention-decision record, adds no Evidence Payload state, and guesses no notification route or context variant, following the exact `UPSTREAM-V1-ROLE-EXPIRY-BLOCKED-EVENT-011` precedent in [../volume-ii/API_CONTRACTS.md](../volume-ii/API_CONTRACTS.md); `evidence_retention_warning` remains reserved and non-dispatchable rather than removed; no reassessment is auto-requested because WF-011's Trigger admits no lifecycle-service origin and deny-by-default refuses it; the 30-day threshold still computes and records Audit Evidence and operational telemetry only, per the WF-011 precedent. Every protective effect at 015:158 and 015:191 remains fully executable: the exact 24-month maximum fires, expiry wins at the maximum instant, validation changes to `invalid`, legal hold forces `quarantined` with `retention_review`, destruction suppresses and recalculates affected scores and Recommendations before bytes become unreachable, and no current read may cite expired bytes. The withheld warning is advance notice only; it cannot extend retention, keep expired bytes decision-grade, or leave a stale score current. This interim does not approve any option.
- Latest Responsible Decision Point: Before the first production Evidence Payload reaches 23 months, that is, before any real payload crosses the 30-day threshold.
- Blocking Impact: Volume II — no, because the fail-closed reservation is conformant; implementation — no under the exact interim, including prelaunch and non-production testing; production — blocked, because shipping to customers while a foundation-mandated event is never emitted violates 015:191 and PM-REQ-003 places foundation documents above Volume I; feature — the warning event, its notification surface, the lifecycle-originated reassessment request, and any contractual advance-notice claim are blocked until approval.
- ADR Threshold: Required for Option 3 (new workflow and widened `workflow_id` enum) or for any new Evidence Payload state; an accepted ADR does not by itself supersede 015:191, so the foundation text must be reconciled under PM-REQ-009 either way.
- Owner Required: Chief Architect and Chief Product
- Exact Approval Wording: I approve OD-029 Option [selected] as the producer of `EvidenceRetentionExpiring`, and I approve the exact producing workflow, service authority, decision record, event profile, and reassessment-request path recorded in the accompanying change set, including the reconciliation of [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md) line 191 to name that producer.

### OD-030 Already-Invalid Evidence Payload Destruction Procedure

- Decision ID: OD-030
- Exact Question: When Evidence Payload destruction targets Evidence whose effective validation status is already `invalid`, which destruction procedure, destruction instant, and immutable audit artifact apply, given that no Evidence Validation Decision may be appended?
- Classification: C
- Current Status: Pending owner approval
- Why The Decision Exists: [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md) states that `product_evidence_payload` destruction appends an Evidence Validation Decision with `legal_deletion_completed`, but [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) forbids a same-status decision and any transition out of terminal `invalid`, so already-invalid payload destruction has no stated procedure, and the mechanism, instant, and evidencing artifact that fill the gap are owner choices on which two fully conformant readings differ.
- Affected Capabilities: CAP-013, CAP-025
- Affected Workflows: WF-007, WF-013
- Affected Product Rules: PRULE-016, PRULE-042
- Affected Foundation Requirements: DLC-REQ-012, DLC-REQ-013, DLC-REQ-014, DLC-REQ-021, SM-REQ-002, SM-REQ-007, PM-REQ-009
- Affected Acceptance Criteria: AC-CAP-013, AC-CAP-025, AC-WF-007, AC-WF-013, AC-PRULE-016, AC-PRULE-042
- Options:
  1. One uniform procedure: extend the LifecycleDeletionJob entry conditions to admit retention expiry so a single mechanism and a single immutable Deletion Evidence record prove every `product_evidence_payload` destruction at the 24-month maximum.
  2. Path-split with accelerated expiry: the LifecycleDeletionJob and its Deletion Evidence remain the Account-deletion and Organization-closure mechanism only, while retention-expiry destruction is proved by a distinct `security_audit` deletion audit record and performed at the first eligible instant at or after the accrued 30-day minimum.
  3. Path-split at the maximum instant: as Option 2, but destruction stays on the existing capture cursor and 24-month maximum rather than accelerating to the accrued minimum.
- Recommended Option: Option 3, with the safe interim active until it is approved.
- Evidence Supporting The Recommendation:
  - [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) admits the LifecycleDeletionJob only from an accepted Account deletion or Organization closure, so the retention-expiry path needs its own evidenced procedure rather than a widened job.
  - [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md) already enumerates deletion audit records as a `security_audit` item distinct from Deletion Evidence, so the expiry path can discharge DLC-REQ-014 and DLC-REQ-021 without a new class.
  - The payload cursor is capture and expiry wins at the maximum instant, so accelerating destruction to the accrued minimum is an irreversible choice that no accepted authority compels.
  - No option may append the Decision: a same-status decision and any exit from `invalid` are forbidden at foundation level, and approving one would require a PM-REQ-009 controlled foundation change first.
- Benefits: Gives already-invalid payload destruction one named mechanism, one destruction instant, and one immutable evidence record without weakening the Evidence immutability invariant.
- Costs: An expiry-path deletion audit record, its verification and escalation are separate from the LifecycleDeletionJob Deletion Evidence contract, and the correction to [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md) requires PM-REQ-009 controlled foundation change governance.
- Risks: An implementer reading the destruction text literally writes a forbidden same-status Decision and silently breaks the `invalid` is terminal guarantee that frozen Check Results and historical snapshots rely on; the opposite misreading blocks destruction and retains customer payload past a mandated maximum.
- Security Implications: The destruction record is the only proof that a mandated erasure occurred, so an expiry path with no evidenced record breaches DLC-REQ-014 and leaves erasure unprovable; relaxing the forbidden-transition column instead of correcting the lifecycle text is the wrong repair and weakens Evidence immutability.
- Data Implications: Payload bytes and key are destroyed on the exact `product_evidence_payload` schedule while the envelope, digest, provenance, existing Validation Decisions, and downstream lineage remain `product_history`; no new Decision row is written, and `legal_deletion_completed` is unreachable as a reason on Evidence already invalid for another reason.
- AI Implications: None new; invalid Evidence already cannot ground AI output or a customer-visible citation, and lineage retains only metadata and digests after payload destruction.
- Operational Implications: Requires an expiry-path destruction runner distinct from the LifecycleDeletionJob, idempotent no-op recording where bytes are already gone, and deadline escalation; already-invalid status must never route a job to `blocked`, whose only conformant reason is `deletion_blocked_legal_hold`.
- Commercial Implications: Which artifact proves destruction and when bytes are destroyed are enterprise and contractual claims; no customer-configurable behaviour is implied.
- Reversibility: Low; the mechanism and audit class can change for future destructions, but bytes already destroyed and evidence not recorded at destruction cannot be reconstructed.
- Safe Interim Behavior: Destruction of an already-invalid Evidence Payload proceeds on the exact `product_evidence_payload` schedule in [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md) under `retention-interim-v1`: minimum 30 days, maximum 24 elapsed months after capture, cursor at capture. Already-invalid status is not a hold and never defers, blocks, or accelerates destruction, which occurs at the maximum instant and never earlier. No Evidence Validation Decision is created and no `EvidenceValidationChanged` is emitted; the Evidence retains its existing `invalid` status and original reason code, and `legal_deletion_completed` is not recorded. No score or Recommendation suppression or recalculation runs, because those effects committed atomically at the original transition to `invalid`. The envelope, digest, provenance, existing Validation Decisions, and downstream lineage are retained as `product_history`. Destruction emits one immutable `security_audit` destruction record carrying every store, index, cache, key, and backup outcome and time, pre-destruction digests, tombstone ID, verifier service, and completion time, plus the DLC-REQ-021 lifecycle audit event with actor, reason, and outcome; where bytes are already gone the per-store outcome is recorded as a no-op and the job completes idempotently. The job never enters `blocked` for this reason. This interim is compelled by the forbidden-transition column in [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) and the mandatory maximum in [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md); it does not approve any option.
- Latest Responsible Decision Point: Before the first production Evidence Payload destruction on either the retention-expiry or Account-deletion and Organization-closure path, and before any contractual claim about destruction evidence.
- Blocking Impact: Volume II — no under the exact interim, though `ATTR-ChangeEvidenceValidation` in [../volume-ii/API_CONTRACTS.md](../volume-ii/API_CONTRACTS.md) MUST record the prior-status constraint so the contract cannot admit a forbidden same-status Decision; implementation — no under the exact interim; production — no for destruction performed under the exact interim, which remains gated by the OD-011 production and contractual gate; feature — any destruction of already-invalid payload earlier than the maximum instant, any separate expiry-path deletion audit record class, and every contractual claim about which artifact proves destruction are blocked until approval.
- ADR Threshold: Not met for the shared core, which is compelled by [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) and needs only the PM-REQ-009 correction to [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md); required if Option 1 changes LifecycleDeletionJob entry conditions under SM-REQ-010, or if Option 2 or 3 establishes a separate destruction mechanism and audit class.
- Owner Required: Chief Architect and Chief Security
- Exact Approval Wording: Each required owner signs the identical statement: “I approve OD-030 Option [selected] effective [UTC time]. I approve its exact destruction procedure, destruction instant, immutable audit artifact and its recorded fields, and the accompanying PM-REQ-009 controlled foundation correction to [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md), and I confirm that this option appends no Evidence Validation Decision to already-invalid Evidence and does not relax the forbidden-transition column in [../016 STATE_MODEL.md](../016%20STATE_MODEL.md).”

### OD-031 Routine Retention-Expiry Destruction Trigger

- Decision ID: OD-031
- Exact Question: What triggers, authorizes, and executes irreversible destruction when a `product_history`, `identity_commercial`, or `security_audit` record reaches its 7-year retention maximum with no accepted Account deletion or Organization closure request?
- Classification: C
- Current Status: Pending owner approval
- Why The Decision Exists: [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md) states a 7-year maximum and an irreversible-destruction mode for three data classes, but [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) queues the only Deletion Evidence producer solely from accepted Account deletion or Organization closure, so no authority, actor, deadline, or event exists to destroy a record that merely expires. Whether routine destruction happens at all, what triggers it, and what may execute it without a tenant request are legal, security, and risk choices, not architectural inferences.
- Affected Capabilities: CAP-025
- Affected Workflows: WF-013
- Affected Product Rules: PRULE-042
- Affected Foundation Requirements: DLC-REQ-012, DLC-REQ-013, DLC-REQ-014, DLC-REQ-015, SM-REQ-001, SM-REQ-003, SM-REQ-010, OBS-REQ-019
- Affected Acceptance Criteria: AC-CAP-025, AC-WF-013, AC-PRULE-042
- Options:
  1. Extend LifecycleDeletionJob with a policy-scheduled retention-expiry trigger: amend the 016 entry conditions and audit-event list, decouple the 30-day deadline so it runs from eligibility rather than acceptance, and add a retention-destruction service permission to the WF-013 permission table.
  2. Define a separate scheduled RetentionExpiryJob lifecycle root with its own state machine, reusing the immutable Deletion Evidence and hold-checkpoint contracts verbatim and leaving the 016 LifecycleDeletionJob entry conditions unchanged.
  3. Split by approval requirement: automated scheduled destruction for `product_history` only, with a dual-control approval queue for `security_audit` and `identity_commercial`.
- Recommended Option: None of Options 1 through 3 ahead of OD-011; retain `retention-destruction-trigger-interim-v1` and record the selected trigger as OD-011's primary-destruction trigger decision. Option 2 is the only option that leaves the 016 entry conditions and the 30-day acceptance deadline mutually coherent, but the choice is the owner's.
- Evidence Supporting The Recommendation:
  - Foundation 016 queues a LifecycleDeletionJob only from accepted Account deletion or Organization closure and lists no retention-expiry audit event, so no routine destruction path exists to be implemented.
  - The 30-elapsed-day primary deadline measured from acceptance in 015 cannot be reconciled with 7-year class maxima, so any retention-expiry trigger requires a PM-REQ-009 controlled foundation change rather than inference.
  - WF-013's permission table contains `deletion.retry` as its only deletion-related permission, and an undefined permission is denied by default under the Permission Baseline, so no actor or service may execute retention destruction today.
  - Destruction is irreversible and already-destroyed bytes cannot be restored under OD-011, so the fail-closed state is do-not-destroy; over-retention is escalated and remediable while wrongful destruction is neither.
- Benefits: Keeps the foundation unamended, adds no product surface, makes over-retention owner-visible, and ensures no byte is irreversibly destroyed without a named actor, named permission, and owner-approved trigger.
- Costs: Records may remain past their stated maxima, accruing storage cost and a standing compliance-exception queue until OD-011 names the trigger.
- Risks: Chronic over-retention past a stated maximum is a recorded compliance exception and not a legal conclusion; [../../schemas/POSTGRESQL_SCHEMA.md](../../schemas/POSTGRESQL_SCHEMA.md) already presumes retention-cursor-driven partition drop that no higher layer authorizes and must be corrected.
- Security Implications: `security_audit` destruction already requires two-person security approval, which no automated sweep may bypass; legal hold remains fully applicable to every retained record.
- Data Implications: Every retained-past-maximum record keeps its exact class, cursor, and hold status; no Deletion Evidence record is produced without an approved trigger.
- AI Implications: None direct; the `product_evidence_payload` expiry path that governs AI grounding is a separate contract in 015 and is unaffected.
- Operational Implications: Requires a critical compliance escalation with severity, owner, and escalation path per OBS-REQ-019, plus owner-visible over-retention reporting.
- Commercial Implications: No contractual retention or destruction claim may be made while over-retention past a stated maximum remains possible; that gate is already closed by OD-011.
- Reversibility: High while the interim holds because nothing is destroyed; Low once any option executes, since destroyed bytes cannot be restored.
- Safe Interim Behavior: Apply `retention-destruction-trigger-interim-v1`. No routine retention-expiry destruction executes in Volume I and the 016 entry conditions stand unchanged: a LifecycleDeletionJob is created only by accepted Account deletion or Organization closure. When a `product_history`, `identity_commercial`, or `security_audit` record reaches its 7-year maximum with no accepted deletion or closure request, the lifecycle service performs no destruction, creates no job, and produces no Deletion Evidence; it performs no destruction, creates no job, and produces no Deletion Evidence, and the record is retained in full subject to legal hold. No domain event is emitted, because Volume I defines none that can represent this condition: an event would require a producing `workflow_id`, an `event_profile`, and a nonnull affected-entity triple under the Logical Event Envelope, and no accepted profile admits a retention-cursor record with no aggregate. Minting one here would invent exactly what OD-029 and OD-024 refuse to invent for the same reason. The condition is instead recorded as Audit Evidence and operational telemetry under the existing `security_audit` and `operational_telemetry` classes, which need no event profile, and it raises one critical compliance escalation through the existing operational escalation path. Over-retention past a maximum is therefore a recorded, escalated, owner-visible compliance exception rather than a silent automated irreversible destruction or an inferred implementer-chosen sweep, but it is deliberately not a domain event. Whether this condition warrants a domain event, and its exact profile, affected entity, and route, is owner-dependent and forms part of this decision rather than its interim. This interim makes no legal conclusion and does not approve any option.
- Latest Responsible Decision Point: Before the OD-011 policy package is approved, because OD-011 requires its primary-destruction trigger to be named; and before any Volume II or schema artifact implements retention-cursor-driven destruction.
- Blocking Impact: Volume II — no; the retention-expiry path is absent rather than ambiguous. Implementation — no under `retention-destruction-trigger-interim-v1`. Production — no additional gate, because storing production customer data already blocks on OD-011. Feature — every routine retention-expiry destruction behaviour, and retention-cursor-driven partition drop, are blocked until approval.
- ADR Threshold: Required if Option 1, 2, or 3 is approved, because each creates a new destruction trigger and transition authority under SM-REQ-010 and a materially different destruction architecture under OD-011; an ADR alone cannot effect the required 016 change.
- Owner Required: Chief Security and Chief Product following qualified legal review; Chief Architect additionally required for the foundation state-model change under Option 1, 2, or 3.
- Exact Approval Wording: Each required owner signs the identical statement: “I approve OD-031 Option [selected] as the routine retention-expiry destruction trigger for Volume I, recorded as OD-011's primary-destruction trigger decision for data classes [classes], and I authorize the PM-REQ-009 controlled foundation change to [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) and [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md) that it requires. I accept that this authorizes automated irreversible destruction of customer data with no tenant request and that destroyed bytes cannot be restored.”

### OD-032 Canonical Domain Treatment Of Lifecycle-Bearing Auxiliary Records

- Decision ID: OD-032
- Exact Question: Which lifecycle owner and canonical identifier namespace does [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md) assign to the lifecycle-bearing records that [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) and Volume I depend on but DM-REQ-001 does not name?
- Classification: B
- Current Status: Pending owner approval
- Why The Decision Exists: DM-REQ-001's core-entity catalogue omits ScoreSnapshot, Check Result, Session, LegalHold, LifecycleDeletionJob, Notification, Delivery, Parsed Artifact, Index Receipt, and Issue Set, yet [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) grants several of them full state machines with entry/exit conditions and lifecycle owners, and Volume I builds mandatory field contracts on all of them. DM-REQ-002 requires every core entity to define a single lifecycle owner and DM-REQ-006 requires identifier namespaces to appear in logs, audit events, and telemetry labels; SM-REQ-004 requires every transition attempt to emit an audit event including `entity_id`. None of those obligations can be satisfied for a record with no assigned namespace. [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md) already demonstrates the correct treatment for exactly this situation by admitting Evidence as a lifecycle-bearing auxiliary record with owner Evidence Context and namespace `evd_id`, so the gap is coverage rather than method. Separately, [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) assigns LegalHold to a "Security Context" that [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md) does not define among its bounded contexts.
- Affected Capabilities: CAP-013, CAP-015, CAP-021, CAP-025
- Affected Workflows: WF-001, WF-008, WF-013, WF-014
- Affected Product Rules: PRULE-018, PRULE-024, PRULE-034, PRULE-042, PRULE-046
- Affected Foundation Requirements: DM-REQ-001, DM-REQ-002, DM-REQ-005, DM-REQ-006, SM-REQ-004
- Affected Acceptance Criteria: AC-CAP-013, AC-CAP-015, AC-CAP-021, AC-CAP-025, AC-PRULE-018, AC-PRULE-046, AC-SM-002
- Options:
  1. Admit each record as a lifecycle-bearing auxiliary record in [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md) with an explicit owner and namespace, following the accepted Evidence precedent and leaving DM-REQ-001's core catalogue unchanged.
  2. Extend DM-REQ-001 to name them as core entities, changing the accepted core-entity catalogue.
  3. Admit only those with a state machine in [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) and treat the remainder as value objects internal to an existing aggregate.
- Recommended Option: Option 1, because it satisfies DM-REQ-002 and DM-REQ-006 without altering the accepted core-entity catalogue and reuses the method [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md) already applies to Evidence. The specific owner and namespace assigned to each record remains OWNER INPUT REQUIRED, because [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) names no owner for ScoreSnapshot, Check Result, Parsed Artifact, Index Receipt, or Issue Set, and names a "Security Context" for LegalHold that [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md) does not define; selecting either would be architectural invention.
- Evidence Supporting The Recommendation:
  - [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md) already admits Evidence as an auxiliary lifecycle-bearing record with an explicit owner and namespace while expressly preserving the DM-REQ-001 catalogue.
  - DM-REQ-006 and SM-REQ-004 are unsatisfiable for a lifecycle-bearing record with no namespace, so the gap is a live foundation defect rather than a modelling preference.
  - The records concerned already carry identity, immutability, and uniqueness contracts in Volume I, so their existence is settled and only their domain classification is open.
- Benefits: Makes every audited transition emit a namespaced entity identifier and closes the DM-REQ-002/DM-REQ-006 gap without disturbing accepted behaviour.
- Costs: Requires a PM-REQ-009 controlled change to a foundation document and an owner or namespace decision for each record.
- Risks: Assigning an owner or namespace by inference would silently create domain ownership the foundation never accepted, which is the failure this register exists to prevent.
- Security Implications: None direct; identifier namespaces appear in audit and telemetry, so a missing namespace weakens incident reconstruction under OBS-REQ-007.
- Data Implications: Controls the canonical identifier field and aggregate membership for the records concerned; every persistence artifact inherits the outcome.
- AI Implications: None.
- Operational Implications: Audit and telemetry cannot label these records consistently until namespaces exist.
- Commercial Implications: None.
- Reversibility: Medium; a namespace becomes difficult to change once any artifact persists or logs it.
- Safe Interim Behavior: No record is added to DM-REQ-001, no namespace or lifecycle owner is inferred for an unassigned record, and no implementation may invent either. Volume I's existing logical field names and behavioural contracts for these records are unchanged and remain authoritative for behaviour. Where [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) already names a lifecycle owner, that assignment stands and is not reopened. Any Volume II or persistence artifact that requires a canonical namespace for an unassigned record remains blocked rather than choosing one. This interim does not approve any OD-032 option.
- Latest Responsible Decision Point: Before the Volume II architecture baseline is frozen, because every persistence and telemetry artifact binds these namespaces.
- Blocking Impact: Volume II — no for behaviour, yes for any artifact requiring a canonical namespace for an unassigned record; implementation — no under the interim; production — no; feature — no.
- ADR Threshold: Required, because the resolution is a PM-REQ-009 controlled change to a foundation document.
- Owner Required: Chief Architect
- Exact Approval Wording: “I approve OD-032 Option [selected] and authorize the PM-REQ-009 controlled change to [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md) assigning the lifecycle owner and canonical identifier namespace recorded in the accompanying package to each named record.”

### OD-033 LifecycleDeletionJob Direct-Completion Condition

- Decision ID: OD-033
- Exact Question: Under exactly which condition may a LifecycleDeletionJob transition `Queued -> Completed` without entering `running`?
- Classification: B
- Current Status: Pending owner approval
- Why The Decision Exists: [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) permits `queued or running to blocked, failed, or completed` and, as a foundation document, outranks WF-013 under PM-REQ-003; WF-013 previously enumerated `Queued -> Running, Blocked, or Failed` and declared all other transitions invalid. The contradiction is resolved in the foundation's favour, but no accepted authority states when a job may complete without executing. An empty resource/class manifest, a manifest whose every member is already destroyed, and a no-op replay of an already-completed job are each conformant readings with different Deletion Evidence content.
- Affected Capabilities: CAP-025
- Affected Workflows: WF-013
- Affected Product Rules: PRULE-042
- Affected Foundation Requirements: SM-REQ-001, SM-REQ-005, DLC-REQ-012, DLC-REQ-014
- Affected Acceptance Criteria: AC-CAP-025, AC-WF-013, AC-PRULE-042
- Options:
  1. Permit `Queued -> Completed` only when the frozen resource/class manifest is empty, with Deletion Evidence recording the empty manifest.
  2. Permit it whenever every manifest member is already provably destroyed at admission, with Deletion Evidence recording each member's prior destruction.
  3. Remove the edge by PM-REQ-009 controlled change to [../016 STATE_MODEL.md](../016%20STATE_MODEL.md), so every job enters `running`, and restore WF-013's original enumeration.
- Recommended Option: Option 3 if the foundation edge was unintended, because it restores the accepted WF-013 behaviour and removes the contradiction at its source; otherwise Option 1 as the narrowest reading. The choice is genuinely open and no accepted authority prefers either.
- Evidence Supporting The Recommendation:
  - WF-013's original enumeration excluded the edge deliberately and declared all other transitions invalid, so the foundation edge may be an oversight rather than an intended capability.
  - [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) requires completion "only with immutable Deletion Evidence", so any option must state what that Evidence records for a job that performed no destruction.
- Benefits: Removes a contradiction between a foundation state model and its owning workflow on a tenant-destructive path.
- Costs: Option 3 requires a controlled foundation change.
- Risks: Inferring the condition would let an implementation complete a deletion obligation without executing or evidencing it.
- Security Implications: A job that completes without executing must not be mistakable for a job that destroyed data; Deletion Evidence is the only artifact distinguishing them.
- Data Implications: Determines what Deletion Evidence records for a non-executing completion.
- AI Implications: None.
- Operational Implications: Affects deletion-deadline reporting and escalation for jobs that complete without work.
- Commercial Implications: None.
- Reversibility: High while no deletion job has executed.
- Safe Interim Behavior: No LifecycleDeletionJob may transition `Queued -> Completed`. Every job enters `running` before completion, exactly as WF-013 enumerated before this correction, and the accepted Account-deletion and Organization-closure behaviour is unchanged. The foundation edge is recorded as permitted but unreachable pending this decision; no implementation may infer a condition for it. This preserves the accepted behaviour rather than inventing a new one and does not approve any OD-033 option.
- Latest Responsible Decision Point: Before the Volume II architecture baseline is frozen, because the `lifecycle_deletion_jobs` state CHECK constraint binds it.
- Blocking Impact: Volume II — no; the edge is absent rather than ambiguous. Implementation — no under the interim. Production — no. Feature — direct completion without execution is blocked until approval.
- ADR Threshold: Required only if Option 3 is approved, because it is a PM-REQ-009 controlled foundation change.
- Owner Required: Chief Architect
- Exact Approval Wording: “I approve OD-033 Option [selected] as the LifecycleDeletionJob direct-completion condition, and where Option 3 is selected I authorize the PM-REQ-009 controlled change to [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) removing the `queued to completed` edge.”

## Decision Resolution Protocol

1. Owner records selected option and rationale in this document.
2. If ADR trigger condition is met, create or update ADR entry in [../../DECISIONS.md](../../DECISIONS.md).
3. Update impacted CAP, WF, PRULE, acceptance, and traceability references in the same change set.
4. Update control-plane documents if sequencing or readiness gates change.

## Dependencies

- [INDEX.md](INDEX.md)
- [CAPABILITY_MODEL.md](CAPABILITY_MODEL.md)
- [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md)
- [PRODUCT_RULES.md](PRODUCT_RULES.md)
- [TRACEABILITY_MATRIX.md](TRACEABILITY_MATRIX.md)
- [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md)
- [../013 QUALITY_ATTRIBUTES.md](../013%20QUALITY_ATTRIBUTES.md)
- [../../DECISIONS.md](../../DECISIONS.md)

## Change Control

Any decision update MUST preserve decision identifier stability and update all impacted references listed in the impacted artifacts section for the decision.
