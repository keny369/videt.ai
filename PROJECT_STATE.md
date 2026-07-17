# Project State

## Snapshot

- Date: 2026-07-17
- Status: Volume I is FROZEN at `v1.5-volume-i-frozen` and is the authoritative implementation baseline; the PM-REQ-010 gate for Volume I is satisfied. The RC1 correction programme under ADR-018 is closed and its decisions are integrated under ADR-019 and ADR-020. The Engineering Manual is ACCEPTED at `v1.7-engineering-manual-accepted` as the normative authority for engineering practice only, with no independent product-behaviour authority. Volume II is COMPLETE and IMPLEMENTATION-READY: 97/97 implementation-matrix rows contracted, all 25 contract sources integrated, and the governance repair completed under ADR-023. Seven owner decisions are pending; each withholds one named limb under a deterministic fail-closed interim and none blocks implementation. See [specification/volume-ii/IMPLEMENTATION_READINESS_REPORT.md](specification/volume-ii/IMPLEMENTATION_READINESS_REPORT.md)
- Foundation Baseline: 1.0
- Current Volume I Baseline Tag: `v1.5-volume-i-frozen` (authoritative Volume I implementation baseline, ADR-020); predecessors `v1.4-volume-i-ratified-prelegal` at `b2cb4ca` and `v1.3-volume-i-corrected` at `5d725fa` are retained as history; historical `v1.2-volume-i-frozen` and `v1.1-implementation-ready` are superseded and are not implementation baselines
- Initial Volume II Draft Commit: `7213e9a`
- Current Gate: CLEARED for the Volume II baseline. Under ADR-021 the gate is measured by blocking status rather than by a count. `UPSTREAM-V1-PROJECT-LIFECYCLE-003` (OD-014) and `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` (OD-023) remain live and pending under their deterministic neutral interims, and each records `Volume II — no`; every other Pass 001 blocker is retired by ratified Owner Decisions integrated under ADR-019 and ADR-020, and ADR-023 re-anchored all 72 sites that still cited one as a live reason. Production implementation may begin at S-01 from [specification/volume-ii/IMPLEMENTATION_BACKLOG.md](specification/volume-ii/IMPLEMENTATION_BACKLOG.md)

## Current Objective

Begin production implementation at S-01 Registration and Access, working [specification/volume-ii/IMPLEMENTATION_BACKLOG.md](specification/volume-ii/IMPLEMENTATION_BACKLOG.md) in order. The acceptance criterion is the oracle. Report rather than invent every limb the seven pending decisions reserve, and never resolve one by inference.

## Operating Constraints

- No new governance documents, review packs, matrices, standards, frameworks, indexes, registers, or process documents may be created unless required to remove a demonstrated ambiguity in the product specification itself.
- Treat `v1.5-volume-i-frozen` as the authoritative Volume I implementation baseline; the PM-REQ-010 gate for Volume I is satisfied. Reopening any frozen contract requires a new ADR and, where foundation content is affected, the PM-REQ-009 process. Do not move or replace historical tags.
- Do not edit accepted Volume I behavior for preference, speculative refinement, scope expansion, or governance expansion; only ADR-018 correction-programme changes and controlled defect/owner-decision changes are permitted.
- Permit a Volume I correction after acceptance only for a demonstrated contradiction, non-executable contract, unsafe behavior, invalid acceptance oracle, or an approved owner decision incorporated through controlled change.
- Permit Volume II implementation architecture, but withhold every route, query, control, event shape or job that intersects a recorded upstream blocker.
- Do not infer permission to begin broad implementation from the Volume I freeze or an incomplete Volume II pass.

## Baseline Summary

- Constitution and governance documents are accepted.
- Foundation layer 000 through 020 is authored and integrated.
- Canonical dependency graph is established in manual control documents.
- Canonical diagrams are created and source-controlled.
- TDD, documentation-as-code, and fitness-function policy are established.
- Volume I has been decomposed into a canonical implementation-ready specification set under specification/volume-i.
- Accepted dashboard and history behaviour is deterministic structured data only; AI-generated narrative and its provider calls/placeholders are excluded unless a controlled future Volume I change accepts a separate capability and complete AI contract.
- ADR-017 corrects six demonstrated defects without adding a capability: Mailgun uncertainty, existing-Account sign-in, policy-scheduled reassessment, BillingEntity creation, canonical Evidence vocabulary, and stale CAP-019 wording.

## Domain Progress

- Foundation governance: complete and active
- Volume I Product Foundations: FROZEN at `v1.5-volume-i-frozen`; 27 owner decisions resolved across ADR-019 and ADR-020; the retention/deletion legal package and OD-013 event tenant identity are closed; five non-blocking decisions remain pending (OD-014, OD-023, OD-027, OD-031, OD-032)
- Experience and Interaction: Volume II Pass 001 complete for authorized/unblocked screens; blocked screens are absent
- Domain and State downstream detail: aggregate, workflow, dependency, transaction and lock architecture complete for unblocked behavior
- Data and Persistence downstream detail: PostgreSQL design complete except blocked pretenant/platform/cross-Organization event/audit scope
- Search and Retrieval downstream detail: Pass 001 complete
- AI and Evaluation downstream detail: Pass 001 complete with dormant-provider gates and structured-only dashboard/history behavior
- API and Integration downstream detail: Pass 001 complete for unblocked routes/providers; blocked routes remain absent
- Implementation planning: TDD slices and CI gates specified; broad implementation remains paused

## Active Workstream

1. Preserve every established tag and commit; do not move or delete a baseline.
2. Obtain narrow controlled Volume I corrections for the blockers recorded in the Volume II index that remain live: `UPSTREAM-V1-PROJECT-LIFECYCLE-003` (OD-014) and `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` (OD-023).
3. Reconcile only the affected Volume II contracts, rerun validation, then freeze the Volume II architecture baseline before broad implementation.
4. Push the two existing commits and corrected tag only after the configured remote is explicitly confirmed as trusted.

## Risks

- Risk: implementation begins from guessed behavior at a frozen-Volume-I gap.
  Mitigation: blocked operations are unreachable and listed centrally in the Volume II index.

- Risk: architecture documents disagree on physical contracts.
  Mitigation: cross-document API/schema/job/security/deployment validation and adversarial role review run before Volume II acceptance.

- Risk: governance artifacts proliferate faster than product specification quality.
  Mitigation: reject new process artifacts unless they remove demonstrated product ambiguity.

- Risk: foundation drift through uncontrolled edits.
  Mitigation: ADR-backed controlled change policy MUST be enforced.

- Risk: quality thresholds remain unresolved at gate deadlines.
  Mitigation: quality attribute owners MUST resolve provisional ranges before gate closure.

## Next Checkpoints

- Resolve only the recorded Volume I blockers that remain live through controlled change — `UPSTREAM-V1-PROJECT-LIFECYCLE-003` (OD-014) and `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` (OD-023); do not reopen unrelated product behavior or a retired blocker.
- Obtain OD-010 owner approval and exact Measurement Set bytes before complete customer-facing numeric score release.
- OD-011 is closed on 2026-07-17 under ADR-020: `retention-interim-v1` is the approved fixed retention baseline for worldwide availability with principal markets United States, United Kingdom, Australia, New Zealand, Canada and South Africa; qualified external counsel reviewed the position and raised no objection. Its Qualified Legal Approval element was narrowly amended to accept an append-only owner approval record plus a factual counsel-review record, excluding privileged material from this repository by design. See `specification/volume-i/OWNER_DECISION_RECORD_2026-07-17_LEGAL_AND_CLOSURE.md`.
- Revalidate and freeze Volume II only after the blocked contracts are deterministic; accept later Volume I changes only for demonstrated defects or approved owner decisions.
