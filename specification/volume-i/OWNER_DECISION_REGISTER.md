# Volume I Owner Decision Register

## Status

- Status: Accepted register; one resolved and ten pending owner decisions with deterministic interim behaviour
- Last Updated: 2026-07-16
- Owner: Chief Architect
- Foundation Version Dependency: 1.0

## Purpose

Capture owner-level decisions required to finalize Volume I without silently resolving policy choices.

Authority precedence for decision evidence and conflict resolution:

1. Accepted ADRs
2. Foundation documents 000 through 020
3. Canonical research and business-case material
4. Volume I canonical documents
5. Roadmap and project-state documents
6. Supporting notes

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
- Deterministic Delivery Behavior: WF-014 and `notification-interim-v1` define routing, authorization, redaction, Mailgun adapter invariants, timeout, retry, bounce, aggregate status, replay, and terminal escalation. Channel resolution alone does not permit unspecified delivery behavior.

## Pending Decision Briefs

### OD-001 Verification Method Set

- Decision ID: OD-001
- Exact Question: Which verification methods are approved for source ownership or control verification in baseline scope?
- Classification: B
- Current Status: Pending owner approval
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
- Safe Interim Behavior: DNS TXT and HTTPS file methods are allowed; every field, location, exact-match predicate, 24-hour lifetime, attempt schedule, timeout, idempotency rule, Source state outcome, retained Evidence field, and recovery path is mandatory under [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md#ownership-verification-evidence-contract). Other methods are blocked.
- Latest Responsible Decision Point: Before Volume IV acceptance.
- Blocking Impact: Volume II — no; implementation — no while the safe interim remains active; production — no for the DNS TXT and HTTPS file baseline; feature — every other verification method and Volume IV acceptance are blocked until approval.
- ADR Threshold: Required if approved method set differs from interim behavior or changes security threat assumptions.
- Owner Required: Chief Architect
- Exact Approval Wording: I approve OD-001 Option 2 as the baseline verification method set for Volume I and authorize corresponding specification updates.

### OD-002 Discoverability Score Weight Distribution

- Decision ID: OD-002
- Exact Question: What is the final weight distribution across Discoverability Score pillars?
- Classification: C
- Current Status: Pending owner approval
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
- Safe Interim Behavior: Apply `score-interim-v1`: equal exact rational weight across applicable pillars, exact penalty/contribution and applicability rules, base-10 score arithmetic, round-half-up to one decimal, clamping, completeness behavior, immutable snapshots, and normative fixtures in [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md#interim-discoverability-score-policy). This is an interim implementation baseline and does not approve the final OD-002 distribution.
- Latest Responsible Decision Point: Before Volume V commercial architecture acceptance.
- Blocking Impact: Volume II — no; implementation — no under `score-interim-v1`; production — no for explicitly versioned interim scores; feature — any non-equal or contractually final weight policy and Volume V commercial architecture acceptance are blocked until approval.
- ADR Threshold: Required when final weights are accepted.
- Owner Required: Chief Product
- Exact Approval Wording: I approve OD-002 Option 2 and authorize publication of a versioned baseline score-weight policy.

### OD-003 Confidence Band Definitions For Prioritization

- Decision ID: OD-003
- Exact Question: What canonical confidence-band model should recommendation prioritization use?
- Classification: D
- Current Status: Pending owner approval
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
- Safe Interim Behavior: Persist confidence on `0.0000..1.0000` using round-half-up to four decimals and policy `confidence-interim-v1`; display Low for `[0.0000,0.6000)`, Medium for `[0.6000,0.8500)`, and High for `[0.8500,1.0000]`. Missing or invalid confidence is recorded explicitly, displays Low, and routes the Issue to review_required. This interim mapping does not approve the final OD-003 model.
- Latest Responsible Decision Point: Before Volume V commercial architecture acceptance and after at least two full reassessment cycles.
- Blocking Impact: Volume II — no; implementation — no under `confidence-interim-v1`; production — no for explicitly versioned interim bands; feature — any alternative display/ranking mapping and Volume V commercial architecture acceptance are blocked until approval after the required reassessment evidence exists.
- ADR Threshold: Required if confidence policy changes score or prioritization semantics.
- Owner Required: Chief Product
- Exact Approval Wording: I approve OD-003 Option 3 and authorize a versioned confidence mapping policy for ranking.

### OD-005 Provisional Quality Threshold Finalization

- Decision ID: OD-005
- Exact Question: Which final values and acceptance gates should replace provisional QA thresholds?
- Classification: D
- Current Status: Pending owner approvals by QA requirement owner
- Why The Decision Exists: Foundation quality requirements intentionally use provisional ranges pending measurement evidence.
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
- Safe Interim Behavior: Treat foundation provisional values as planning constraints and non-final implementation gates. For product behavior that cannot safely remain unbounded, enforce `crawl-interim-v1` soft/hard constants and the exact limit-hit contract in WF-005 until an approved replacement policy activates; this does not finalize the foundation QA targets.
- Latest Responsible Decision Point: Each threshold by its foundation deadline and gate.
- Blocking Impact: Volume II — no; implementation — no against the provisional requirements and named safe interim; production/release — each OD-005 sub-decision blocks only its named gate at its latest responsible point; feature — limit increases, service commitments, or release claims beyond the active provisional/interim value are blocked until the responsible owner approves measured replacements.
- ADR Threshold: Required if threshold changes alter release gates, contractual posture, or architecture constraints.
- Owner Required: Mixed per QA owner in table below.
- Exact Approval Wording: I approve OD-005 for my assigned QA requirement and authorize replacing the provisional threshold with the approved value and breach policy.

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
- Current Status: Pending owner approval
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
- Safe Interim Behavior: High-cost operations are crawl start, reassessment start, AI generation, and export generation; they hard-block only when committed plus active-reserved plus requested units would exceed the active hard limit, while equality is allowed, after an atomic server-side check/reservation. Low-cost report, history, Issue, recommendation, and score reads remain warning-only at the usage hard limit while the Organization and human Account or tenant service identity remain active. The exact multi-operation policy, negative/cached Decision fields, resolved reservation/lease, nested-operation, commit/release, queued recheck, outage, replay, and linked-retry behavior is defined in WF-015. This does not approve the final grace strategy.
- Latest Responsible Decision Point: Before commercial packaging finalization.
- Blocking Impact: Volume II — no; implementation — no under the exact safe interim; production — no while the interim operation classes and bounds are disclosed and enforced; feature — any grace-window or progressive-degradation behavior outside the interim and commercial packaging finalization are blocked until approval.
- ADR Threshold: Required if policy materially changes package behavior or quality gate assumptions.
- Owner Required: Chief Product
- Exact Approval Wording: I approve OD-006 Option 2 and authorize documented grace-policy enforcement boundaries by operation class.

### OD-007 Citation Linkage Scope

- Decision ID: OD-007
- Exact Question: Should Citation support many-to-many linkage to Evaluation and AIResponse simultaneously?
- Classification: B
- Current Status: Pending owner approval
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
- Safe Interim Behavior: Apply `citation-interim-v1` in [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md#airesponse-and-citation-contract-citation-interim-v1). Each Citation has exactly one AIResponse and one Evidence parent, no direct Evaluation write link, the exact logical fields and full-preimage fingerprint, idempotent replay/collision behavior, exhaustive state/reason transitions, origin-Issue Evidence-lineage validation, and complete claim coverage before AIResponse validation or Artifact publication. Evaluation traversal is read-only through Recommendation origin Issue and Check/Evidence; an optional denormalized read projection has no write authority. This deterministic interim does not approve final OD-007 linkage.
- Latest Responsible Decision Point: Before Volume IV acceptance.
- Blocking Impact: Volume II — no; implementation — no under `citation-interim-v1`; production — no for the baseline one-AIResponse/one-Evidence linkage; feature — direct many-to-many Citation writes and Volume IV acceptance are blocked until approval if the owner selects that expansion.
- ADR Threshold: Required if Option 2 is approved.
- Owner Required: Chief Architect
- Exact Approval Wording: I approve OD-007 Option 1 as the baseline citation-linkage scope for Volume I.

### OD-008 BillingEntity Decomposition Scope

- Decision ID: OD-008
- Exact Question: Should BillingEntity include invoice and payment sub-entities in core domain or remain adapter-level?
- Classification: C
- Current Status: Pending owner approval
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
- Safe Interim Behavior: Keep invoice and payment details adapter-level.
- Latest Responsible Decision Point: Before Volume V commercial architecture acceptance.
- Blocking Impact: Volume II — no; implementation — no with adapter-level invoice/payment detail; production — no for baseline entitlement and billing-provider integration; feature — core invoice/payment entities, hybrid summaries, and Volume V commercial architecture acceptance are blocked until approval if the owner selects expanded scope.
- ADR Threshold: Required if Option 1 or Option 3 is approved.
- Owner Required: Chief Product
- Exact Approval Wording: I approve OD-008 Option 2 and confirm adapter-level billing-detail scope for Volume I.

### OD-009 Disputed Issue Score Eligibility

- Decision ID: OD-009
- Exact Question: Should Issues flagged as review_required or disputed contribute to score and prioritization before adjudication?
- Classification: B
- Current Status: Pending owner approval
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
- Safe Interim Behavior: Apply the Issue eligibility predicate in [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md#score-contribution-contract). Candidate, review_required, disputed, in_review, terminal, superseded, and non-current Issues receive zero score and priority contribution. Upheld or withdrawn current open Issues become eligible; rejected Issues remain ineligible. Every eligibility change creates or reuses an immutable ScoreSnapshot and deterministically suppresses or republishes governed recommendations.
- Latest Responsible Decision Point: Before Volume IV acceptance.
- Blocking Impact: Volume II — no; implementation — no under the zero-contribution interim; production — no while unresolved Issues remain excluded; feature — contribution from review_required, disputed, or in_review Issues and Volume IV acceptance are blocked until approval if the owner selects inclusion.
- ADR Threshold: Required if disputed Issues are included in score before adjudication.
- Owner Required: Chief Product and Chief Architect
- Exact Approval Wording: I approve OD-009 Option 2 and authorize score eligibility to exclude disputed Issues until adjudicated.

### OD-010 Baseline Check Catalog And Measurement Scope

- Decision ID: OD-010
- Exact Question: Which measured signals, external observation channels, applicability rules, pass/fail thresholds, impact mappings, and default remediation/effort semantics form the owner-approved baseline Check Catalog?
- Classification: C
- Current Status: Pending owner approval
- Why The Decision Exists: A score requires at least one deterministic score-capable Check for every applicable pillar; selecting what the product measures and what constitutes a deficiency is product strategy, not an architectural inference.
- Affected Capabilities: CAP-009, CAP-010, CAP-011, CAP-015, CAP-016, CAP-017
- Affected Workflows: WF-007, WF-008, WF-009, WF-010, WF-011
- Affected Product Rules: PRULE-010 through PRULE-013, PRULE-024 through PRULE-026, PRULE-028, PRULE-029
- Affected Foundation Requirements: DM-REQ-009, DM-REQ-011, SM-REQ-003, VER-REQ-014, QA-REQ-010, AI-REQ-005
- Affected Acceptance Criteria: AC-CAP-009, AC-CAP-010, AC-CAP-011, AC-CAP-015, AC-CAP-016, AC-CAP-017, AC-WF-007, AC-WF-008, AC-WF-009, AC-WF-010, AC-WF-011, AC-PRULE-010, AC-PRULE-011, AC-PRULE-012, AC-PRULE-013, AC-PRULE-024, AC-PRULE-025, AC-PRULE-026, AC-PRULE-028, AC-PRULE-029, AC-SM-001, AC-SM-002, AC-SM-003
- Options:
  1. Approve the seven-definition provider-neutral baseline in `check-catalog-interim-v1`.
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
- Security Implications: External provider responses are reduced to validated immutable observation Evidence before Check execution; Checks make no network call and fail closed on missing, stale, indeterminate, or cross-tenant input.
- Data Implications: Requires exact subject, applicability, Evidence, freshness, and version lineage on every Check Result.
- AI Implications: AI-presence observation is measurement input only; it cannot supply a product recommendation or alter another Check.
- Operational Implications: External observation collection must either satisfy `external-observation-v1` or produce the catalog-defined `error` result and unavailable score.
- Commercial Implications: Final catalog breadth, provider selection, and thresholds remain owner-controlled packaging choices.
- Reversibility: High through immutable catalog/definition versions and reassessment; historical results never mutate.
- Safe Interim Behavior: Activate exact `check-catalog-interim-v1` with `CHK-TI-001`, `CHK-CQ-001`, `CHK-TR-001`, `CHK-SP-001`, `CHK-AIP-001`, `CHK-AS-001`, and `CHK-LP-001` as defined in [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md). Bind tenant Source/subject instances only in each frozen Evaluation Applicability Set. `external-measurement-interim-v1` bundles no query, intent, listing, provider, or adapter set before approval, so implementations do not invent one: the three always-applicable external entries for `CHK-SP-001`, `CHK-AIP-001`, and `CHK-AS-001` persist handled `input_evidence_missing` errors; `CHK-LP-001` does the same only when its frozen applicability decision is true and otherwise persists its canonical `not_applicable` Result. The numeric score therefore remains unavailable. An approved Measurement Set later activates as exact signed configuration and accepts only exact frozen provider-neutral Evidence before snapshot sealing; Check execution still makes no provider call. A missing/invalid catalog fails Evaluation before Check side effects; handled missing/stale/indeterminate observations create no Issue. No Recommendation or Priority Decision publishes from an unavailable calculation. This interim is deterministic but does not approve the final measurement strategy.
- Required Owner Approval Package: OD-010 approval is valid only for one immutable Measurement Set package whose owner-supplied content includes all of the following; omission leaves the no-set safe interim active and authorizes no inferred value:
  - package identity, schema version, immutable version, complete canonical bytes, SHA-256 of those exact bytes, predecessor or null, creation time, and proposed effective time
  - the exact provider identities and allowed measurement kinds, plus each bound collector adapter ID, immutable adapter version and digest, and deterministic provider-selection/fallback order when more than one provider is allowed
  - the complete ordered search-query keys and exact query text, AI-intent keys and exact intent content, authority-reference collection scope/selection rules, and required local-listing keys with their exact canonical business-profile field source and version
  - every applicability rule and exact pass/fail/error, impact, confidence, effort, and score-contribution threshold, either by binding unchanged immutable Check Definition/Catalog digests or by supplying an immutable successor definition package
  - activation prerequisites, exact effective-time rule, currently active predecessor, failure outcome, and the rule that rollback is activation of a separately approved immutable successor package rather than mutation or reactivation of unapproved bytes
  - separate signatures from Chief Product and Chief Architect over the same package SHA-256, with signer identity, authority, signed time, and decision; one signature or signatures over different bytes do not authorize activation
  - the pinning rule that every Evaluation records the Measurement Set, Catalog, Definition, provider, and adapter identities/versions/digests it consumed, plus the retention/access location for the exact approved canonical bytes needed to reproduce that Evaluation
- Latest Responsible Decision Point: Before Volume I catalog values become a customer contractual claim.
- Blocking Impact: Volume II — no for the logical Measurement Set contract and no-set path; implementation — no for the interim catalog, internal Checks, and deterministic missing-input path; production — customer-facing complete numeric score, score-derived Recommendation/Priority publication, and any contractual measurement claim are blocked; feature — external Measurement Set activation and successful external Check outcomes are blocked until both named owners sign one complete immutable package.
- ADR Threshold: Required if the approved model permits one Check to contribute to multiple pillars, nondeterministic evaluation, or a new external trust boundary.
- Owner Required: Chief Product and Chief Architect
- Exact Approval Wording: Each required owner signs the identical statement: “I approve OD-010 Option [selected] and Measurement Set [package identity and immutable version], canonical SHA-256 [digest], effective [UTC time], including its exact provider/adapter bindings, query, intent, authority-reference and listing sets, applicability and threshold mappings. I authorize activation only when both required signatures bind this same digest, every Evaluation pins the approved versions and digests for reproduction, and any rollback occurs only through a separately approved immutable successor.”

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
