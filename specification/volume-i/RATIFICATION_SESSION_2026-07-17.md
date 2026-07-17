# Volume I Owner Ratification Session — 2026-07-17

## Status

- Status: Owner decisions recorded; NOT yet applied to the specification
- Session Date: 2026-07-17
- Decision Owner: Product Owner (Lee Powell), exercising Chief Product, Chief Architect and Chief Security authority
- Authorizing ADR: ADR-018 (RC1 correction programme)
- Purpose: durable record of owner decisions taken in the five-cluster ratification session, plus the two decisions the cluster agenda initially omitted

## Why This Record Exists

The RC1 neutrality review found that 25 of 33 owner-decision interims already implemented one of their own stated options while the register described them as pending. Volume I was therefore decided-but-unratified rather than under-designed.

This document records the owner's disposition of every release-blocking decision. It is an audit record only. It changes no normative behaviour and confers no authority by itself. The integration pass applies these decisions to the affected artifacts; until then, the Owner Decision Register remains the operative text and continues to show these decisions as pending.

## Decisions Recorded

### Ratified as specified

The following are approved exactly as the specification already implements them. Their status becomes ratified, and pending/interim/owner-approval-required language is removed for each.

| OD | Approved behaviour | Option |
| --- | --- | --- |
| OD-001 | DNS TXT and HTTPS file source-ownership verification | Option 2 |
| OD-002 | Equal weighting of applicable score pillars as the Version 1 baseline scoring policy | Option 1 |
| OD-003 | Numeric confidence `0.0000`–`1.0000` with displayed Low/Medium/High bands | Option 3 |
| OD-005 | Provisional QA and operational thresholds, subject to the commercial clarification below | — |
| OD-006 | Entitlement enforcement semantics, subject to the commercial clarification below | Option 3 as implemented |
| OD-007 | One-directional Citation: exactly one AIResponse, exactly one Evidence, no direct Evaluation write link | Option 1 |
| OD-008 | BillingEntity core with invoice and payment detail adapter-level | Option 2 |
| OD-009 | Disputed and review-required Issues excluded from published scoring and prioritisation until eligible | Option 2 |
| OD-010 | The seven-check baseline catalogue, thresholds, impact mappings and measurement contracts | Option 1 |
| OD-019 | The metered-read unit, subject to the commercial clarification below | Option 1 |
| OD-021 | Account reactivation proves only the acting administrator's current MFA-satisfied Session; restores state, creates no Session, consults no target identity | Option 1 |
| OD-022 | Organization reactivation assurance as specified | — |
| OD-026 | Last-administrator expiry protection as specified | — |

OD-002 note recorded verbatim by the owner: this approval supersedes the earlier recommendation for a weighted distribution. Any later weighting change MUST use a new scoring-policy version and MUST NOT reinterpret historical ScoreSnapshots.

OD-021 note: the owner ratified this as Option 1 knowingly. It is not a neutral interim and MUST NOT be described as one.

### Resolved by decision

| OD | Owner decision |
| --- | --- |
| OD-017 | On an Issue fingerprint collision the second Issue MUST NOT be created, and the affected Evaluation MUST fail closed using the existing canonical collision outcome and telemetry. No alternative duplicate Issue may be silently persisted. |
| OD-018 | Only one initial Evaluation orchestration may exist per Project. A second root Crawl request that would initiate another initial Evaluation MUST be rejected. Reuse the existing reassessment single-orchestration pattern where practical. |
| OD-024 | `ComparisonGenerated` is removed as a Volume I domain event. Comparison behaviour remains; no domain event is emitted. It may be introduced in a later specification revision. |
| OD-025 | `ReassessmentTriggered` is removed as a Volume I domain event. Reassessment continues to execute deterministically through existing workflows; no domain event is emitted. It may be introduced in a later specification revision. |
| OD-015 | The `quarantined` and `retired` Document states, and the `DocumentQuarantined` and `DocumentRetired` events, are removed from [../016 STATE_MODEL.md](../016%20STATE_MODEL.md) through the PM-REQ-009 controlled-change process. The Document lifecycle is `discovered -> ingested -> parsed -> indexed` only. Evidence quarantine remains a separate, unaffected state machine. Retention concerns are governed by the Cluster 2 legal package. |

### Resolved by replacement

| OD | Owner decision |
| --- | --- |
| OD-016 | The current no-sign-out behaviour is NOT ratified. Every authenticated user MUST be able to terminate their own authenticated session. The baseline supports current-session sign-out and security-initiated revocation of an individual compromised Session. Sign-out-everywhere remains deferred. Deterministic Session state transitions and existing audit requirements are preserved. |
| OD-012 | The current no-break-glass behaviour is NOT ratified. There is no standing cross-tenant support access. Emergency access is permitted only when all are true: explicit authorized invocation; fully audited; time-limited; least-privilege; reason recorded; immutable audit trail retained; customer notification where contractually or legally required. Normal support operations retain no tenant access. |
| OD-020 | Deny-by-default is NOT accepted as the answer for customer-facing objects. Explicit read rows are added to the Permission Baseline for Organization home data, Project, Source, Crawl, Evaluation, Notification inbox and Export enumeration, mirroring their existing mutation permissions. Security and administrative objects — Support Session, Incident, Investigation, Legal Hold, deletion jobs and Billing summary — remain deny-by-default pending a separate decision. |

### Commercial clarification (OD-005, OD-006, OD-008, OD-019)

The commercial enforcement model, billing architecture and metering unit are approved as the Volume I baseline.

Specific commercial thresholds — including daily read limits, crawl limits, entitlement quotas, grace thresholds and similar numeric values — are versioned policy configuration rather than immutable Volume I product constants.

Volume I specifies what is measured, when enforcement occurs, how enforcement behaves, and how metering is performed. It does not fix commercial numerals unless a value is intrinsic to the product itself. Policy values are externally configurable and versioned so they may evolve without a Volume I revision.

Affected requirements, workflows, acceptance criteria and traceability must distinguish commercial policy from product architecture.

## Remaining Blockers

Volume I remains BLOCKED. Two inputs are outstanding, and neither is resolvable by specification work.

### Blocker 1 — Retention and deletion legal package

Affects OD-011, OD-029, OD-030, OD-033, and the notification limb of OD-012.

OD-011 requires qualified legal review by its own terms and no reviewer has signed. `AC-CAP-013`'s 30-day expiry-warning criterion is currently unsatisfiable and must be reconciled or changed.

Prerequisite owner input, required before legal review can begin: OD-011's approval package requires approved jurisdictions, markets, and customer/contract scope. The repository contains no jurisdiction, customer-type, contract-template or data-category information. The product owner MUST supply these; they are an owner input, not a legal one.

OD-012's replacement inherits this dependency, because "notification where contractually or legally required" is a determination inside the same package. OD-011 and OD-012's notification question go to legal together.

### Blocker 2 — OD-013 event tenant identity

The canonical event envelope requires `organization_id`, which cannot truthfully represent pre-Organization bootstrap events, platform-scope Incidents, or cross-Organization Investigations. The owner declined to infer an answer; a Chief Architect decision is required.

The architectural recommendation on record is Option A: an explicit `event_scope` discriminator with conditional tenant identity, avoiding synthetic platform tenants.

Any option that narrows the universal `organization_id` requirement is a foundation change to DM-REQ-013 in [../011 DOMAIN_MODEL.md](../011%20DOMAIN_MODEL.md) and requires the PM-REQ-009 controlled-change process plus an ADR. It additionally requires removing two frozen sentences that would otherwise forbid it: the event-envelope rule that "no separate tenant value may be supplied", and the statement that "Volume I defines no independent tenant identifier that can disagree with it".

## Decisions Not Blocking Volume I Freeze

| OD | Class | Reason |
| --- | --- | --- |
| OD-014 | Implementation-blocking | Project pause/resume/archive; interim is genuinely neutral |
| OD-023 | Implementation-blocking | Credential rotation token; interim is genuinely neutral |
| OD-027 | Volume II-blocking | ParsingJob-to-IndexingJob persistence key |
| OD-031 | Implementation-blocking | Routine retention destruction path |
| OD-032 | Volume II-blocking | Auxiliary domain namespaces |
| OD-004 | Resolved | Notification channel baseline |
| OD-028 | Withdrawn | Superseded by OD-029 |

## Integration Requirements

When both blockers clear, one controlled integration pass applies every decision above, in a single coherent change set, across each affected foundation requirement, Owner Decision record, ADR, capability, workflow, product rule, state transition, event contract, permission, error and reason code, acceptance criterion, traceability row, glossary entry, diagram, and retained Volume II draft.

No cluster may be left partially ratified. For every ratified decision: status becomes ratified, the approved option is named, pending/interim/owner-approval language is removed, the historical decision record is preserved, and normative fixtures identify the approved policy version accurately.

## Change Control

This record is append-only. A correction to a recorded decision requires a new dated session record; this file MUST NOT be edited to change a decision after the fact.
