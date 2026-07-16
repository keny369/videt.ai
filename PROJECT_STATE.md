# Project State

## Snapshot

- Date: 2026-07-16
- Status: Corrected Volume I frozen; Volume II Implementation Architecture Pass 001 complete for unblocked behavior and acceptance-blocked by demonstrated upstream ambiguities
- Foundation Baseline: 1.0
- Frozen Volume I Tag: `v1.3-volume-i-corrected` at `5d725fa`; historical `v1.2-volume-i-frozen` remains immutable
- Initial Volume II Draft Commit: `7213e9a`
- Current Gate: Volume II cannot be frozen or broad implementation begun until the thirteen demonstrated frozen-Volume-I blockers in [specification/volume-ii/INDEX.md](specification/volume-ii/INDEX.md) receive controlled deterministic corrections

## Current Objective

Preserve `v1.3-volume-i-corrected` as the authoritative behavior, complete Volume II for every unblocked behavior, and report rather than invent the missing event scope, lifecycle, read, metering, reactivation-proof, comparison-event, Credential-rotation-token, reassessment-trigger-event, Role-expiry-blocked-event/notification, Document-lifecycle and Issue-fingerprint-collision semantics.

## Operating Constraints

- No new governance documents, review packs, matrices, standards, frameworks, indexes, registers, or process documents may be created unless required to remove a demonstrated ambiguity in the product specification itself.
- Treat `v1.3-volume-i-corrected` as the authoritative frozen behavioral baseline; do not move or replace historical tags.
- Do not edit frozen Volume I behavior for preference, speculative refinement, scope expansion, or governance expansion.
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
- Volume I Product Foundations: frozen at `v1.3-volume-i-corrected`
- Experience and Interaction: Volume II Pass 001 complete for authorized/unblocked screens; blocked screens are absent
- Domain and State downstream detail: aggregate, workflow, dependency, transaction and lock architecture complete for unblocked behavior
- Data and Persistence downstream detail: PostgreSQL design complete except blocked pretenant/platform/cross-Organization event/audit scope
- Search and Retrieval downstream detail: Pass 001 complete
- AI and Evaluation downstream detail: Pass 001 complete with dormant-provider gates and structured-only dashboard/history behavior
- API and Integration downstream detail: Pass 001 complete for unblocked routes/providers; blocked routes remain absent
- Implementation planning: TDD slices and CI gates specified; broad implementation remains paused

## Active Workstream

1. Preserve the local `v1.3-volume-i-corrected` tag and initial Volume II draft commit.
2. Obtain narrow controlled Volume I corrections for the thirteen blockers recorded in the Volume II index.
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

- Resolve only the thirteen recorded Volume I blockers through controlled change; do not reopen unrelated product behavior.
- Obtain OD-010 owner approval and exact Measurement Set bytes before complete customer-facing numeric score release.
- Complete OD-011 qualified legal/product approval before production customer-data use.
- Revalidate and freeze Volume II only after the blocked contracts are deterministic; accept later Volume I changes only for demonstrated defects or approved owner decisions.
