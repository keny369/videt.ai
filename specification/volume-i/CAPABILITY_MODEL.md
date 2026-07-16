# Volume I Capability Model

## Status

- Status: Draft for owner review
- Last Updated: 2026-07-16
- Owner: Chief Product
- Foundation Version Dependency: 1.0

## Authority

This document defines the canonical product capability baseline for Volume I.

PRULE-044 (permission and scope), PRULE-045 (policy version and pinning), and PRULE-046 (idempotent command/event replay) apply to every capability in addition to each capability's listed business rules. Their omission from an individual `Business Rules` line does not make them optional.

Each `Actor` line identifies participating product personas or services; it never grants authority. The exact runtime role, permission, scope, read-only persona, support-session, and deny behavior is defined by the permission baseline in [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md#permission-baseline).

## Capability Definitions

### CAP-001 Registration And Access

- Identifier: CAP-001
- Name: Registration and Access
- Purpose: Allow a user to establish authenticated access to F1.
- Actor: Eligible self-service registrant or invited Account; Organization Administrator after bootstrap
- Preconditions: Identity validation succeeds and either a time-bounded bootstrap grant or active Organization invitation exists.
- Inputs: Identity attributes and authentication factors.
- Product Behavior: Platform atomically provisions Account and, for self-service bootstrap, Organization plus first OrganizationAdmin assignment; failed bootstrap leaves no partially active tenant.
- Outputs: Active authenticated session and account identity record.
- Success Condition: Account reaches active state and user can access permitted views.
- Failure Condition: Provisioning fails or account remains pending.
- Business Rules: PRULE-001, PRULE-018
- Security Implications: Must comply with SEC-REQ-001 through SEC-REQ-024.
- Data Implications: Account lifecycle events and audit records are persisted.
- AI Implications: None.
- Observability Requirements: AccountProvisionRequested and AccountActivated telemetry.
- Acceptance Criteria: AC-CAP-001
- Dependencies: WF-001, WF-013, [../014 SECURITY_MODEL.md](../014%20SECURITY_MODEL.md)
- Non-goals: Social growth features or non-business identity federation expansion.
- Release Classification: Baseline Core

### CAP-002 Organization Setup

- Identifier: CAP-002
- Name: Organization Setup
- Purpose: Establish a tenant boundary and governance context.
- Actor: Organization Administrator
- Preconditions: CAP-001 complete.
- Inputs: Organization profile, immutable baseline Access Policy version, accountable administrator assignment, idempotency key.
- Product Behavior: Create Organization state and activate exactly one versioned baseline Access Policy after validation.
- Outputs: Organization record, active policy version, administrator Role Assignment, and audit events.
- Success Condition: Organization reaches active state and supports project creation.
- Failure Condition: Organization remains pending or transitions to suspended.
- Business Rules: PRULE-002, PRULE-019
- Security Implications: Tenant isolation and role assignment controls apply.
- Data Implications: Organization metadata and policy history are auditable.
- AI Implications: None.
- Observability Requirements: OrganizationCreated and OrganizationActivated events.
- Acceptance Criteria: AC-CAP-002
- Dependencies: WF-001, WF-013
- Non-goals: Cross-tenant federation behavior.
- Release Classification: Baseline Core

### CAP-003 Project Setup

- Identifier: CAP-003
- Name: Project Setup
- Purpose: Create a bounded discoverability program within an organization.
- Actor: Organization Administrator or Marketing Operator
- Preconditions: CAP-002 complete.
- Inputs: Trimmed display name, locale, reporting time zone, local-presence applicability and conditional reason, fixed discoverability objective, idempotency key, then activation command.
- Product Behavior: Create any authorized Project in draft through WF-002, then activate only when exact metadata and active-Source prerequisites pass.
- Outputs: Project identity and lifecycle state.
- Success Condition: Project becomes active and eligible for audit execution.
- Failure Condition: Project activation fails or remains draft.
- Business Rules: PRULE-003, PRULE-004
- Security Implications: Authorization checks for project creation and activation.
- Data Implications: Project records and activation events are stored.
- AI Implications: None.
- Observability Requirements: ProjectCreated and ProjectActivated events.
- Acceptance Criteria: AC-CAP-003
- Dependencies: WF-001, WF-002, WF-004
- Non-goals: Portfolio-level optimization logic.
- Release Classification: Baseline Core

### CAP-004 Website Or Property Onboarding

- Identifier: CAP-004
- Name: Website or Property Onboarding
- Purpose: Register target web property context for discoverability analysis.
- Actor: Organization Administrator, Marketing Operator, or Technical Implementer
- Preconditions: CAP-003 complete.
- Inputs: Property root host, registration-scope version 1, onboarding provenance, and command idempotency data.
- Product Behavior: Register exactly one proposed Source per normalized same-Project host; verification later materializes its first active Source Scope Policy.
- Outputs: Onboarding request and source candidates.
- Success Condition: Property is ready for verification and source activation.
- Failure Condition: Onboarding fails validation.
- Business Rules: PRULE-004, PRULE-005
- Security Implications: Input validation and tenant-scoped access enforcement.
- Data Implications: Source registration metadata and provenance records.
- AI Implications: None.
- Observability Requirements: SourceRegistered and onboarding telemetry.
- Acceptance Criteria: AC-CAP-004
- Dependencies: WF-001, WF-003, WF-004
- Non-goals: Automated external account takeover or DNS management.
- Release Classification: Baseline Core

### CAP-005 Ownership Or Control Verification

- Identifier: CAP-005
- Name: Ownership or Control Verification
- Purpose: Ensure only authorized tenants can activate analysis scope for a property.
- Actor: Organization Administrator or Technical Implementer
- Preconditions: CAP-004 complete.
- Inputs: Versioned Verification Request using `dns_txt` or `http_file`, tenant and Source references, challenge and command idempotency data.
- Product Behavior: Apply the exact recoverable encrypted challenge delivery/deletion, 24-hour lifetime, half-open automated-slot/skip schedule, serialized completion-cursor on-demand limits, method-defined observation hashing, terminal reason/authority, validation, redaction, and evidence/event rules in [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md#ownership-verification-evidence-contract).
- Outputs: Verified, expired, canceled, or failed Verification Request; one restricted Verification Evidence and observed event per started attempt; unchanged proposed Source except on atomic success.
- Success Condition: Exact method predicate succeeds once, Source atomically transitions proposed to verified, and replay returns the same result.
- Failure Condition: Unsupported/invalid request, unauthorized redelivery, on-demand concurrency/rate/count denial, mismatch, or dependency timeout never verifies or disables the Source; unresolved request expires after exactly 24 hours and terminal challenge material cannot be recovered.
- Business Rules: PRULE-005, PRULE-020
- Security Implications: Prevents unauthorized domain scanning.
- Data Implications: Verification evidence and audit trail retained.
- AI Implications: None.
- Observability Requirements: SourceVerificationRequested, observation attempt, SourceVerified, expiry, cancellation, integrity failure, reason-code, latency, and redacted evidence telemetry.
- Acceptance Criteria: AC-CAP-005
- Dependencies: WF-003, WF-004, [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md)
- Non-goals: Selection of unapproved verification channels without owner decision.
- Release Classification: Baseline Core With Owner Decision Dependency

### CAP-006 Source Discovery And Scope Control

- Identifier: CAP-006
- Name: Source Discovery and Scope Control
- Purpose: Define and maintain crawlable source scope for each project.
- Actor: Organization Administrator, Marketing Operator, or Technical Implementer
- Preconditions: CAP-005 complete.
- Inputs: Versioned Source Scope Policy; normalized, timestamped and versioned boundary-change request with reason/idempotency; expected policy and Source state versions; discovered canonical URLs.
- Product Behavior: Resolve scope as the intersection of verified Source, Organization, and Project policy; apply contractions, adjudicate allowed same-host expansions, and require a new verified Source for a new host.
- Outputs: Immutable pending or terminal Source Scope Change Request, active policy version when approved, valid Source state, and affected-run decision record.
- Success Condition: Active source set supports audit execution.
- Failure Condition: Source remains disabled or removed.
- Business Rules: PRULE-006, PRULE-021
- Security Implications: Scope constraints prevent boundary leakage.
- Data Implications: Source lineage and state transitions are persisted.
- AI Implications: Source quality influences retrieval fidelity.
- Observability Requirements: SourceActivated, SourceDisabled, SourceRemoved events.
- Acceptance Criteria: AC-CAP-006
- Dependencies: WF-003, WF-004, WF-005
- Non-goals: Unlimited autonomous source expansion.
- Release Classification: Baseline Core

### CAP-007 Crawl Initiation

- Identifier: CAP-007
- Name: Crawl Initiation
- Purpose: Start initial or re-audit crawl execution.
- Actor: Organization Administrator, Marketing Operator, or scheduler service identity
- Preconditions: CAP-006 complete and project active.
- Inputs: Authorized Crawl command, active Sources, request-time Source Scope/Crawl Policy Snapshots, and Entitlement policy/counter context; the allowed root `crawl.start` Decision/reservation or parent `reassessment.start` reservation is resolved immediately before execution.
- Product Behavior: Queue and start a Crawl under WF-005's exact numeric bounds, per-attempt/run byte formula and sentinel boundary, reservation-safe concurrent accounting, canonical breadth/sitemap/queue retention order, fetch retry policy, and terminal race/reason precedence independent of concurrent completion order.
- Outputs: Crawl attempt, source-level outcomes, IngestionJobs, coverage status, completion reason, limit records, and entitlement reservation outcome.
- Success Condition: Crawl reaches completed with full or explicitly partial coverage and at least one valid Document, or reaches an auditable canceled state by authorized request.
- Failure Condition: Zero valid Documents, all Source roots fail, or a nonrecoverable pre-output policy/integrity failure produces failed; no terminal Crawl is moved back to running.
- Business Rules: PRULE-007, PRULE-008
- Security Implications: Trigger authorization enforced.
- Data Implications: Crawl attempts and execution metadata persisted.
- AI Implications: Crawl completeness influences downstream AI recommendations.
- Observability Requirements: CrawlQueued, CrawlStarted, soft/hard limit, retry, per-Source coverage, CrawlCompleted, CrawlFailed, and CrawlCanceled events with exact policy versions and counts.
- Acceptance Criteria: AC-CAP-007
- Dependencies: WF-004, WF-005, WF-006, WF-011
- Non-goals: Crawling beyond the exact active Crawl Policy limits.
- Release Classification: Baseline Core

### CAP-008 Crawl Progress And Recovery

- Identifier: CAP-008
- Name: Crawl Progress and Recovery
- Purpose: Provide operational visibility and recovery controls for partial failures.
- Actor: Organization Administrator, Marketing Operator, or approved time-bounded SecurityOperator support session for recovery
- Preconditions: CAP-007 started.
- Inputs: Crawl, IngestionJob, and ParsingJob telemetry; complete parse manifest; exact failed subset, reason codes, attempt/replay counts, recovery command, and expected state version.
- Product Behavior: Surface accepted pages/bytes, Source-root, coverage, limit, fetch, parsing, and readiness state; apply only WF-005 bounded fetch recovery or `parsing-interim-v1` internal retry and authorized dead-letter replay.
- Outputs: Immutable Crawl/parse attempt history, Parsed Artifacts, exact Evaluation Input Snapshot, terminal/coverage/readiness result, and linked recovery outcome.
- Success Condition: Every admitted Crawl and parse member has an exact terminal outcome, ready-full/ready-partial/blocked derives solely from the complete manifest, and concurrent completion or replay cannot change an earlier snapshot.
- Failure Condition: Exhausted/nonretryable parse, blocked readiness, or denied recovery creates the enumerated state/reason/subset/events without hidden retry, dropped manifest member, stale Evaluation mutation, or unclassified persistence.
- Business Rules: PRULE-009, PRULE-022
- Security Implications: Recovery actions require authorized roles.
- Data Implications: Failure lineage and recovery attempts retained.
- AI Implications: None directly.
- Observability Requirements: Crawl, ingestion, parsing attempt/replay, failed-subset, readiness, Evaluation-transition, and correlation telemetry.
- Acceptance Criteria: AC-CAP-008
- Dependencies: WF-005, WF-006, WF-017
- Non-goals: Automatic hidden retries without audit trace.
- Release Classification: Baseline Core

### CAP-009 Technical Inspection

- Identifier: CAP-009
- Name: Technical Inspection
- Purpose: Evaluate technical discoverability checks on ingested material.
- Actor: System automation
- Preconditions: Immutable Evaluation input snapshot exists with exact full/partial coverage and failed-subset metadata.
- Inputs: Parsed documents and technical evidence.
- Product Behavior: Execute deterministic technical checks and produce check results.
- Outputs: Technical check results linked to evidence.
- Success Condition: Technical checks produce evaluable outputs.
- Failure Condition: Check execution fails or evidence insufficient.
- Business Rules: PRULE-010, PRULE-011
- Security Implications: Internal-only processing under tenant isolation.
- Data Implications: Check outputs and evidence references persisted.
- AI Implications: Technical check outputs may inform recommendation context.
- Observability Requirements: Evaluation and check-result telemetry.
- Acceptance Criteria: AC-CAP-009
- Dependencies: WF-006, WF-007, [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md)
- Non-goals: Framework-specific lint implementation details.
- Release Classification: Baseline Core

### CAP-010 Content Inspection

- Identifier: CAP-010
- Name: Content Inspection
- Purpose: Evaluate content quality and discoverability relevance signals.
- Actor: System automation
- Preconditions: CAP-009 and parsed content availability.
- Inputs: Content evidence and check definitions.
- Product Behavior: Execute content checks and confidence attribution.
- Outputs: Content Check Results and candidate Issues.
- Success Condition: Content issues are evidence-linked and reviewable.
- Failure Condition: Checks fail due to missing or invalid content signals.
- Business Rules: PRULE-010, PRULE-012
- Security Implications: Tenant-scoped evidence access.
- Data Implications: Content-derived Issues and confidence metadata persisted.
- AI Implications: Content signals can influence AI recommendation context.
- Observability Requirements: EvaluationCompleted plus content-check metrics.
- Acceptance Criteria: AC-CAP-010
- Dependencies: WF-006, WF-007
- Non-goals: Human editorial workflow automation.
- Release Classification: Baseline Core

### CAP-011 Structured-Data Inspection

- Identifier: CAP-011
- Name: Structured-Data Inspection
- Purpose: Evaluate structured-data and schema quality for discoverability surfaces.
- Actor: System automation
- Preconditions: Parsed structured-data artifacts are available.
- Inputs: Structured-data evidence and check rules.
- Product Behavior: Validate schema presence and quality constraints.
- Outputs: Structured-data Check Results and related Issues.
- Success Condition: Structured-data outcomes are attributable and measurable.
- Failure Condition: Parsing or validation failure blocks decision-grade output.
- Business Rules: PRULE-010, PRULE-013
- Security Implications: None beyond standard tenant isolation.
- Data Implications: Schema validation outcomes and evidence pointers persisted.
- AI Implications: Structured-data quality may influence AI discoverability guidance.
- Observability Requirements: Parsing and validation success or failure metrics.
- Acceptance Criteria: AC-CAP-011
- Dependencies: WF-006, WF-007
- Non-goals: Direct website schema mutation.
- Release Classification: Baseline Core

### CAP-012 AI Discoverability Analysis

- Identifier: CAP-012
- Name: AI Discoverability Analysis
- Purpose: Produce AI-assisted explanations and recommendation support under deterministic guardrails.
- Actor: AI orchestration service; Organization Administrator or Marketing Operator for publication control
- Preconditions: One target Recommendation version, exactly one origin Issue/state version, valid Evidence in that Issue/Check lineage, and AI/citation policy gates.
- Inputs: Origin Issue, ordered Evidence tuples, target Artifact version, prompt/model/policy versions, locale, and idempotency key.
- Product Behavior: Apply `citation-interim-v1`: fingerprint/replay one AIResponse attempt, manifest every generated claim, create one-AIResponse/one-Evidence Citations with no direct Evaluation write link, decide every Citation, and validate/reject/expire the response under exact boundaries.
- Outputs: Requested/generated/validated/rejected/expired AIResponse attempts and proposed/verified/invalid/superseded Citations with immutable claim/Evidence lineage.
- Success Condition: One validation transaction persists every Citation decision, validates the response only with complete verified coverage, and binds draft content only on full pass; exact replay repeats no provider or decision side effect.
- Failure Condition: Timeout, schema/policy/advisory failure, stale origin, incomplete claim coverage, invalid Evidence/locator, tenant mismatch, or altered replay produces the exact terminal reason and no AI-assisted publication.
- Business Rules: PRULE-014, PRULE-015
- Security Implications: Prompt injection and retrieval poisoning controls apply.
- Data Implications: Prompt/model/policy versions, response and Citation fingerprint preimages, claims, one-directional lineage, decisions, and timestamps are persisted.
- AI Implications: Must comply with foundation AI principles and quality gates.
- Observability Requirements: Every AIResponse/Citation transition, collision, replay, timeout, coverage result, and binding event.
- Acceptance Criteria: AC-CAP-012
- Dependencies: WF-008, WF-009, [../008 AI_PRINCIPLES.md](../008%20AI_PRINCIPLES.md)
- Non-goals: Autonomous production writes.
- Release Classification: Baseline Core

### CAP-013 Evidence Capture And Provenance

- Identifier: CAP-013
- Name: Evidence Capture and Provenance
- Purpose: Ensure all Issues, scores, and Recommendation Artifacts are backed by valid auditable Evidence.
- Actor: Tenant-scoped integrity-validation service; SecurityOperator holding protected `evidence.validation.manage` in authorized security/legal scope
- Preconditions: Inspection workflows produce check outputs.
- Inputs: Raw observations or immutable references, digest, same-Organization lineage, schema and collector versions, classification, validation result, and retention class.
- Product Behavior: Enforce exact Evidence fields/digest/tenant/immutability, operator/service Validation Decision permissions/transitions, and atomic propagation across current Issue support, passed/failed score-coverage Checks, and independent Recommendation rationale/citations, plus redaction.
- Outputs: Valid, invalid, or quarantined Evidence with immutable provenance/access history; atomic unavailable score and suppressed-Recommendation projection when current support ceases to be valid.
- Success Condition: Valid Evidence bytes match digest and every referenced entity belongs to one Organization; permitted users receive exact allowed/redacted fields.
- Failure Condition: Missing bytes or fields, digest mismatch, unknown schema, invalid state, or cross-Organization reference rejects every downstream Issue, score, recommendation, and citation write.
- Business Rules: PRULE-011, PRULE-016
- Security Implications: Evidence access controls must follow data classification.
- Data Implications: Provenance and lineage metadata mandatory.
- AI Implications: Citation-backed responses depend on evidence availability.
- Observability Requirements: Evidence capture success, citation validity rates.
- Acceptance Criteria: AC-CAP-013
- Dependencies: WF-007, WF-008, WF-017
- Non-goals: Unattributed recommendation publication.
- Release Classification: Baseline Core

### CAP-014 Issue Creation, Adjudication, Deduplication, And Supersession

- Identifier: CAP-014
- Name: Issue Creation, Adjudication, Deduplication, and Supersession
- Purpose: Create the canonical Issue entity from evaluated Evidence, resolve review and dispute states, prevent duplicates, and preserve immutable reassessment lineage.
- Actor: Tenant-scoped evaluation service; Organization Administrator, Marketing Operator, or Technical Implementer for dispute; SecurityOperator or approved support session for adjudication
- Preconditions: Evaluation is running with frozen definitions and policies; Check Result and valid Evidence exist. Evaluation completion is not a creation prerequisite.
- Inputs: Canonical Check Result, confidence, impact, Evidence, full fingerprint preimage and version, command idempotency key, and current predecessor set for reassessment.
- Product Behavior: Apply the exact fingerprint replay/collision algorithm, Case request/terminal fields, dual-version commands, reminder/critical/race cursor, ordered two-pass predecessor/new reconciliation, linked terminal recurrence, exhaustive unverified reasons, declared absence-proof rules, exact closure Check/Evidence, score-unavailable handoff, and atomic supersession.
- Outputs: One same-run Issue per full fingerprint tuple, immutable linked Adjudication Cases when needed, an exact sealed Issue Set with one current leaf per identity, and immutable audit events.
- Success Condition: Exact replay or concurrency creates one Issue; every state transition is authorized and version-checked; supersession is same-Project, acyclic, single-successor, and atomic.
- Failure Condition: Invalid Evidence, unauthorized or stale transition, hash-only merge, lineage cycle, cross-Project link, or partial publish is rejected without changing current pointers.
- Business Rules: PRULE-011, PRULE-017, PRULE-023, PRULE-033, PRULE-043
- Security Implications: Organization scope, explicit dispute/adjudication permissions, requester/adjudicator separation, Evidence classification, and score visibility rules apply.
- Data Implications: Issue fingerprint preimage/hash/version, state versions, Case SLA/decision metadata, closure Evaluation/Check/Evidence, Issue-set membership/order, and supersession chain are retained.
- AI Implications: Each published AI-assisted Recommendation Artifact has exactly one eligible current origin Issue.
- Observability Requirements: Issue creation/replay/collision, dispute, adjudication, overdue/critical, resolution, supersession, and recalculation events.
- Acceptance Criteria: AC-CAP-014
- Dependencies: WF-007, WF-012
- Non-goals: A second deficiency entity, silent deletion, terminal-record reopening, or automatic adjudication.
- Release Classification: Baseline Core

### CAP-015 Scoring And Recalculation

- Identifier: CAP-015
- Name: Scoring and Recalculation
- Purpose: Compute and recalculate Discoverability Score from governed inputs.
- Actor: System automation
- Preconditions: One exact sealed staged prospective or atomic current Issue Set with ordered membership/current-leaf lists, frozen state-at-snapshot Evidence/Check/scope/coverage/policy inputs, pillar applicability, and deterministic eligibility for every member.
- Inputs: Selected Issue-set ID and Issues, Check Results, latest effective Evidence Validation Decisions, exact scope/coverage identities, and score/confidence/eligibility/fingerprint/catalog versions and hashes.
- Product Behavior: Apply `score-interim-v1` exactly, including membership validation, state-at-snapshot Contributions, fixed exclusion precedence, retained penalties, exact semantic hash tuples, rational equal weights, decimal/rounding rules, per-pillar status/reasons, serialized prior-snapshot linkage, Current Score Projection, and staging-specific no-pointer behavior.
- Outputs: Complete, partial, or unavailable immutable ScoreSnapshot; one exact Contribution per Issue-set member; exact nullable current/last-promoted and latest-calculation projection pointers; exhaustive ordered pillar/unavailable reasons.
- Success Condition: Normative fixtures reproduce exact values/hashes, every contribution reconciles, exact replay returns one snapshot, and permitted projection promotion never mutates history.
- Failure Condition: Any missing/inconsistent policy, invalid Evidence, uncovered pillar, input mismatch, or invariant failure returns unavailable, exposes no old current numeric score, and leaves last-promoted history unchanged.
- Business Rules: PRULE-024, PRULE-025, PRULE-043
- Security Implications: Score visibility follows role permissions.
- Data Implications: Score snapshots and model version markers persisted.
- AI Implications: AI may explain scores but must not redefine score values.
- Observability Requirements: EvaluationCompleted and score movement telemetry.
- Acceptance Criteria: AC-CAP-015
- Dependencies: WF-008, WF-012, WF-011
- Non-goals: Unjustified numerical weight invention.
- Release Classification: Baseline Core With Owner Decision Dependency

### CAP-016 Recommendation Creation

- Identifier: CAP-016
- Name: Recommendation Creation
- Purpose: Generate implementation-ready Recommendation Artifacts from Issues.
- Actor: Recommendation service; Organization Administrator or Marketing Operator for publication; Technical Implementer as consumer
- Preconditions: CAP-014 and CAP-015 complete.
- Inputs: Exactly one origin Issue, optional informational related Issue references, origin-lineage Evidence, Score Contribution context, and artifact templates or validated AIResponse.
- Product Behavior: Generate and validate the exact versioned Recommendation Artifact fields, sole-origin eligibility, Evidence/AIResponse/Citation lineage, publication, suppression, and deterministic fallback contract.
- Outputs: Draft, published, suppressed, or retired Recommendation Artifact versions linked to one origin Issue, optional non-governing related Issues, and valid Evidence.
- Success Condition: Every required field passes; impact/confidence equal the origin; an AI-assisted version has complete verified Citation coverage; only the origin controls eligibility, suppression, and priority.
- Failure Condition: Missing/blank field, non-discoverability advisory scope, personalized legal/tax conclusion or instruction, empty step list, invalid Evidence/AIResponse/Citation, ineligible origin Issue, stale version, or policy-invalid output prevents publication with the exact reason.
- Business Rules: PRULE-026, PRULE-027
- Security Implications: Artifact access scoped by organization and role.
- Data Implications: Artifact versions and lineage persisted.
- AI Implications: AI outputs used only when policy-validated.
- Observability Requirements: RecommendationArtifactGenerated telemetry.
- Acceptance Criteria: AC-CAP-016
- Dependencies: WF-009, WF-010
- Non-goals: Direct artifact deployment into customer systems.
- Release Classification: Baseline Core

### CAP-017 Recommendation Prioritization

- Identifier: CAP-017
- Name: Recommendation Prioritization
- Purpose: Rank recommendations by impact, confidence, and effort.
- Actor: Organization Administrator or Marketing Operator; read-only consumers cannot override
- Preconditions: CAP-016 complete.
- Inputs: Published Recommendation Artifacts with one eligible origin Issue each, persisted origin impact/confidence plus Artifact effort, creation time, identifier, policy version, and input hash.
- Product Behavior: Apply the exact lexicographic `priority-interim-v1` order and retain base order separately from authorized display overrides.
- Outputs: Immutable Priority Decisions, deterministic base queue, optional reasoned display override, and suppressed ineligible recommendations.
- Success Condition: Stable inputs produce byte-for-byte equal semantic ordering including ties; every override records actor, reason, prior and resulting order without changing factors or score.
- Failure Condition: Missing factor, ineligible origin Issue, stale input hash, unauthorized override, or unexplained order prevents publication.
- Business Rules: PRULE-028, PRULE-029
- Security Implications: None beyond role-scoped access.
- Data Implications: Priority snapshots and change history retained.
- AI Implications: AI-generated suggestions cannot override deterministic policy rules.
- Observability Requirements: priority calculation telemetry and review events.
- Acceptance Criteria: AC-CAP-017
- Dependencies: WF-009, WF-010
- Non-goals: Opaque ranking based on undocumented factors.
- Release Classification: Baseline Core

### CAP-018 Reporting And Dashboarding

- Identifier: CAP-018
- Name: Reporting and Dashboarding
- Purpose: Present score, Issues, Recommendation Artifacts, and trend context.
- Actor: Organization Administrator, Marketing Operator, Technical Implementer, read-only Executive Buyer, or authorized SecurityOperator scope
- Preconditions: CAP-015 through CAP-017 complete.
- Inputs: ScoreSnapshots, Issue inventory, Recommendation status, historical runs.
- Product Behavior: Render current immutable snapshot and state-at-snapshot history using the exact role/classification allow, omit, restricted-reference, and deny rules across every delivery surface.
- Outputs: Role-scoped summary and drill-down read models, stable redacted-field codes, and generated report artifacts.
- Success Condition: Every role/classification fixture exposes exactly the allowed fields, denies inaccessible objects, and produces identical redaction semantics in UI, logical API responses, exports, notifications, and support views.
- Failure Condition: Cross-Organization data, unauthorized field value, restricted Evidence detail, inconsistent surface redaction, or stale current pointer is returned.
- Business Rules: PRULE-030, PRULE-031
- Security Implications: Role-specific data visibility and redaction controls.
- Data Implications: Report generation metadata and access logs persisted.
- AI Implications: AI explanation is optional and must remain policy bounded.
- Observability Requirements: report generation and view telemetry.
- Acceptance Criteria: AC-CAP-018
- Dependencies: WF-008, WF-010
- Non-goals: Generic BI replacement features.
- Release Classification: Baseline Core

### CAP-019 Historical Comparison

- Identifier: CAP-019
- Name: Historical Comparison
- Purpose: Compare current and prior assessment outcomes.
- Actor: Organization Administrator, Marketing Operator, Technical Implementer, read-only Executive Buyer, or authorized SecurityOperator scope
- Preconditions: Project exists and actor holds `history.read`; zero or one completed Evaluation is a valid insufficient-history query. Numeric comparison requires two completed promoted snapshots.
- Inputs: ScoreSnapshot history, Issue supersession state, Recommendation outcomes.
- Product Behavior: Compare state-at-snapshot data only when every required dimension matches; return every applicable fixed-order mismatch code otherwise. An OrganizationAdmin with `score.rebase` may request every exact target version for immutable noncurrent snapshots, but rebase never overcomes different normalized scope hashes.
- Outputs: `comparable`, `not_comparable`, `insufficient_history`, or `comparison_unavailable` result with exact reason codes and permitted next action.
- Success Condition: Compatible pairs return reproducible attributable deltas; incompatible pairs return no numeric score delta; fewer than two completed evaluations returns the exact available count.
- Failure Condition: Silent cross-version comparison, synthetic missing data, later-state rewrite of history, or unbounded projection rebuild occurs.
- Business Rules: PRULE-032
- Security Implications: Historical data access scoped by tenant and role.
- Data Implications: Historical snapshots retained according to lifecycle policy.
- AI Implications: AI-generated summaries must not alter underlying historical values.
- Observability Requirements: comparison query latency and usage telemetry.
- Acceptance Criteria: AC-CAP-019
- Dependencies: WF-012, WF-011
- Non-goals: Predictive forecasting commitments in baseline scope.
- Release Classification: Baseline Core

### CAP-020 Reassessment

- Identifier: CAP-020
- Name: Reassessment
- Purpose: Re-run assessment workflows on schedule or manual trigger.
- Actor: Organization Administrator, Marketing Operator, or scheduler service identity
- Preconditions: Project active with at least one active Source, request covers the full active-Source set, and one prior completed Evaluation has the current promoted Issue Set/ScoreSnapshot pair.
- Inputs: Authorized trigger or cancellation, full-Project active Source-set version/scope hash, current policy versions, expected Evaluation version when canceling, reason, and idempotency key.
- Product Behavior: Reject no-prior and scope-limited requests before entitlement/Evaluation/Result creation; otherwise create/start a canonical Evaluation before its nested Crawl, let WF-006/007 reuse that Running state, stage the pipeline without pointer changes, recheck scope, and atomically publish all outputs only after invariants pass.
- Outputs: Immutable Reassessment Result, Evaluation attempt lineage, Issue/Case supersession-resolution-unverified sets, Contributions, ScoreSnapshot, projection, and exact usage outcome.
- Success Condition: Same/new/absent/unverified cases follow exact two-pass rules, frozen and publication Source/scope match, prior current results remain until atomic success, and retry cannot duplicate stages/outputs.
- Failure Condition: Entitlement Block, Source/scope race, pipeline/scoring/publication failure, or running/post-completion cancellation produces the exact Evaluation/Result/reservation outcome, changes no prior Current Score Projection field, and emits one terminal event; unavailable staged diagnostics never become latest/current.
- Business Rules: PRULE-033
- Security Implications: Trigger authorization and audit requirements.
- Data Implications: New evaluation history and lineage preserved.
- AI Implications: AI recommendation refresh uses current evidence and versions.
- Observability Requirements: reassessment trigger and completion telemetry.
- Acceptance Criteria: AC-CAP-020
- Dependencies: WF-011, WF-012
- Non-goals: Automatic policy override of previous operator decisions.
- Release Classification: Baseline Core

### CAP-021 Notifications

- Identifier: CAP-021
- Name: Notifications
- Purpose: Inform users about significant lifecycle outcomes and required actions.
- Actor: Notification service identity; Organization Administrator or SecurityOperator for allowed policy changes; approved SecurityOperator support session for terminal recovery
- Preconditions: Event-generating workflows execute.
- Inputs: Versioned logical event, active route/template policy, exact authorized recipients, redacted payload fields, and provider adapter context.
- Product Behavior: Validate/activate immediate authorized immutable Notification Policy versions; union route selectors by required permission; create one logical Notification and in-app/Mailgun Delivery per recipient; classify missing verified addresses without a provider call; apply exact delta-seconds retry, provider mapping, aggregate transitions, and precedence; reauthorize each attempt; and re-resolve current policy/recipients for a linked replay generation.
- Outputs: Immutable per-channel attempts and provider results, aggregate status, suppressed/terminal address reasons, and exactly one escalation for each terminally failed required Delivery or mandatory empty selector union.
- Success Condition: Each Delivery durably succeeds, reaches an authorized governed suppression, or reaches a classified terminal failure escalated within 5 minutes; a mandatory empty selector union is likewise escalated, and replay causes no duplicate send.
- Failure Condition: Unauthorized send, secret or raw Evidence leakage, duplicate provider side effect, retry beyond bound, unclassified terminal status, or missing escalation occurs.
- Business Rules: PRULE-034
- Security Implications: No sensitive payload leakage; recipient authorization enforced.
- Data Implications: Delivery status and notification history retained.
- AI Implications: None required for baseline dispatch.
- Observability Requirements: notification send success and failure telemetry.
- Acceptance Criteria: AC-CAP-021
- Dependencies: WF-006, WF-014, WF-017
- Non-goals: Marketing campaign automation.
- Release Classification: Baseline Core

### CAP-022 Export And Sharing

- Identifier: CAP-022
- Name: Export and Sharing
- Purpose: Provide governed outbound report or data package delivery.
- Actor: Organization Administrator, Marketing Operator, Technical Implementer, read-only Executive Buyer for summary scope, or authorized SecurityOperator investigation scope
- Preconditions: Every selected immutable report/evaluation object exists in one Organization and is readable by the requester under the requested field scope.
- Inputs: Logical format, one-Organization immutable object/field selection, requester-as-recipient, authorization/redaction and distinct approval when high-risk, Export Policy version, and idempotency key.
- Product Behavior: Apply `export-interim-v1`, freeze one-Organization logical scope, enforce the exact one-hour single-use distinct approval for each high-risk create/retry generation attempt, generate/validate a bounded package/manifest without prescribing physical serialization, re-resolve current Export Policy and expiry before every retrieval, and enforce named human/service transitions; cross-Organization investigations produce separate Exports.
- Outputs: Manifested ExportAvailable artifact, retrieval audit, or exact failed/expired/revoked state.
- Success Condition: Package contains exactly the authorized manifest scope and digests, retrieval reauthorizes, and replay cannot create a duplicate package or usage commitment.
- Failure Condition: Unsupported format, over-size or manifest mismatch, unauthorized field/retrieval, or invalid transition publishes no bytes.
- Business Rules: PRULE-035, PRULE-036
- Security Implications: Export scope and recipient authorization checks mandatory.
- Data Implications: Export metadata and access logs retained.
- AI Implications: AI-generated text included only when policy compliant.
- Observability Requirements: ExportRequested, ExportAvailable, ExportFailed events.
- Acceptance Criteria: AC-CAP-022
- Dependencies: WF-010, WF-016
- Non-goals: Unrestricted public sharing.
- Release Classification: Baseline Core

### CAP-023 Administration And Support Investigation

- Identifier: CAP-023
- Name: Administration and Support Investigation
- Purpose: Support operational investigation and controlled remediation paths.
- Actor: Security Operator; time-bounded approved SecurityOperator support session
- Preconditions: Incident, failure, or customer support trigger exists.
- Inputs: Versioned Incident or Investigation request, exact scope/permissions, telemetry/Evidence source set, state version, reason, and correlation identifiers.
- Product Behavior: Apply WF-017's severity/playbook/checkpoint/restoration and exact single-use high-risk step-approval contract, plus WF-018's one-Organization authority or complete per-Organization Support Session set, frozen query, custody, gap, completeness, report-version, and distinct-approval contract.
- Outputs: Versioned Incident timeline and recovery records or complete/partial/insufficient Investigation report with immutable Evidence custody and gap records.
- Success Condition: Every privileged action is named and approved, restoration passes twice, and every investigation source is either validated and custody-linked or represented by an explicit gap.
- Failure Condition: Unauthorized/unnamed remediation, synthetic reconstruction, missing custody, unapproved closure/export, or hidden evidence gap occurs.
- Business Rules: PRULE-037, PRULE-038
- Security Implications: Break-glass and dual-control requirements apply.
- Data Implications: Investigation artifacts and operator actions are immutable in audit logs.
- AI Implications: AI may summarize evidence but cannot execute remediation.
- Observability Requirements: incident investigation traceability and gap reports.
- Acceptance Criteria: AC-CAP-023
- Dependencies: WF-017, WF-018
- Non-goals: Hidden administrative bypass of authorization controls.
- Release Classification: Baseline Core

### CAP-024 Usage And Entitlement Enforcement

- Identifier: CAP-024
- Name: Usage and Entitlement Enforcement
- Purpose: Enforce package limits and entitlement policy consistently.
- Actor: System automation and Billing Operator
- Preconditions: Organization and billing entity context exists.
- Inputs: Versioned Entitlement and plan policy, operation class and units, UTC counter window, atomic counter snapshot, idempotency key, and actor/resource scope.
- Product Behavior: Validate/activate immediate authorized Entitlement Policy versions; apply exact negative short-circuit/nullability and atomic whole-tuple cached-fallback behavior; create no queue-time high-cost Decision/reservation; atomically reserve/commit/release high-cost usage at execution; append exactly one low-cost usage record at durable response; recheck queued/nested work; never reopen terminal replay; and require linked new identity for retry.
- Outputs: Immutable Allow, AllowWithWarning, or Block Decision; reservation lifecycle; exact low-cost usage record; exact actor/unit/window/counters/cache/retry/reason/recovery fields; usage and policy snapshot.
- Success Condition: Concurrent and replayed high-cost requests never reserve or commit above hard limits; warning-only low-cost records may pass and increment beyond their hard threshold under the interim policy but never double-count; failed pre-output work releases once; queued work uses current policy; every denial or warning is auditable.
- Failure Condition: Client-side decision, stale or missing high-cost policy/counter fail-open, high-cost side effect above the hard limit, duplicate high- or low-cost consumption, or unexplained legitimate block occurs.
- Business Rules: PRULE-039, PRULE-040
- Security Implications: Entitlement checks are server-side and auditable.
- Data Implications: Usage counters and entitlement states retained.
- AI Implications: None directly.
- Observability Requirements: entitlement enforcement metrics and failure telemetry.
- Acceptance Criteria: AC-CAP-024
- Dependencies: WF-015, WF-013
- Non-goals: Dynamic commercial experimentation outside approved pricing models.
- Release Classification: Baseline Core With Owner Decision Dependency

### CAP-025 Account Suspension And Deletion

- Identifier: CAP-025
- Name: Account Suspension and Deletion
- Purpose: Apply account lifecycle controls and aligned data lifecycle consequences.
- Actor: Organization Administrator or Security Operator
- Preconditions: Valid suspension or deletion request and authorization.
- Inputs: Account or organization lifecycle action request.
- Product Behavior: Transition states, revoke access, and enforce lifecycle retention or deletion policy.
- Outputs: Suspended, revoked, archived, or deletion-complete status with audit records.
- Success Condition: The next protected request is denied after suspension and every authorization cache and active session converges within 60 seconds; lifecycle obligations then reach their exact terminal state.
- Failure Condition: Access remains active after suspension or deletion obligations are incomplete.
- Business Rules: PRULE-041, PRULE-042
- Security Implications: Immediate access revocation and audit evidence required.
- Data Implications: Data retention and deletion controls follow 015 DATA_LIFECYCLE.
- AI Implications: None directly.
- Observability Requirements: AccountSuspended, AccountRevoked, lifecycle completion telemetry.
- Acceptance Criteria: AC-CAP-025
- Dependencies: WF-013, [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md)
- Non-goals: Silent account deactivation without user-visible status.
- Release Classification: Baseline Core

## Dependencies

- [PRODUCT_DEFINITION.md](PRODUCT_DEFINITION.md)
- [WORKFLOW_SPECIFICATIONS.md](WORKFLOW_SPECIFICATIONS.md)
- [PRODUCT_RULES.md](PRODUCT_RULES.md)
- [ACCEPTANCE_AND_TEST_MAPPING.md](ACCEPTANCE_AND_TEST_MAPPING.md)
- [SCORE_EVIDENCE_MODEL.md](SCORE_EVIDENCE_MODEL.md)
- [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md)

## Change Control

Any normative change to capability definitions MUST:

1. update related workflow and rule references
2. update acceptance criteria mappings
3. update traceability rows for affected capabilities
4. update owner decision dependencies where unresolved choices are involved
