# Project State

## Snapshot

- Date: 2026-07-16
- Status: Frozen Volume I controlled defect correction validated; commit and successor frozen tag pending
- Foundation Baseline: 1.0
- Frozen Volume I Tag: `v1.2-volume-i-frozen`
- Current Gate: Validated ADR-017 corrections for DEF-V1-001 through DEF-V1-006 must be committed and receive a successor frozen tag before Volume II resumes

## Current Objective

Commit and tag the validated six-defect ADR-017 correction set, then resume Volume II from the corrected behavior. Preserve the two existing Volume II drafts without further architecture expansion during this correction pass.

## Operating Constraints

- No new governance documents, review packs, matrices, standards, frameworks, indexes, registers, or process documents may be created unless required to remove a demonstrated ambiguity in the product specification itself.
- Treat `v1.2-volume-i-frozen` as the currently tagged frozen baseline until the ADR-017 correction set receives its successor frozen tag.
- Do not edit frozen Volume I behavior for preference, speculative refinement, scope expansion, or governance expansion.
- Permit a Volume I correction after acceptance only for a demonstrated contradiction, non-executable contract, unsafe behavior, invalid acceptance oracle, or an approved owner decision incorporated through controlled change.
- Keep further Volume II expansion paused until the corrected baseline is committed and tagged; only alignment references in the two retained drafts are permitted during this correction pass.
- Do not infer permission to begin implementation or downstream specification work from the freeze alone.

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
- Volume I Product Foundations: frozen at `v1.2-volume-i-frozen`; controlled correction set validated and successor baseline commit/tag pending
- Experience and Interaction: Volume II expansion paused; retained Rails architecture draft only
- Domain and State downstream detail: Volume II expansion paused; retained Rails architecture draft only
- Data and Persistence downstream detail: Volume II expansion paused; retained PostgreSQL schema draft only
- Search and Retrieval downstream detail: paused
- AI and Evaluation downstream detail: paused
- API and Integration downstream detail: paused
- Implementation planning: paused

## Active Workstream

1. Commit and apply a successor frozen-baseline tag to the validated ADR-017 change set.
2. Resume Volume II from the corrected behavior; do not silently preserve a contradicted draft assumption.
3. Record explicit owner approvals without silently changing accepted behaviour.

## Risks

- Risk: downstream work starts before Volume I acceptance.
  Mitigation: further Volume II expansion remains paused until the corrected frozen baseline is committed and tagged.

- Risk: retained Volume II drafts continue to encode pre-correction behavior.
  Mitigation: the two drafts may contain only reference-level alignment to ADR-017 until Volume II resumes.

- Risk: governance artifacts proliferate faster than product specification quality.
  Mitigation: reject new process artifacts unless they remove demonstrated product ambiguity.

- Risk: foundation drift through uncontrolled edits.
  Mitigation: ADR-backed controlled change policy MUST be enforced.

- Risk: quality thresholds remain unresolved at gate deadlines.
  Mitigation: quality attribute owners MUST resolve provisional ranges before gate closure.

## Next Checkpoints

- Commit and apply a successor frozen tag to the validated ADR-017 Volume I correction set.
- Obtain OD-010 owner approval and exact Measurement Set bytes before complete customer-facing numeric score release.
- Complete OD-011 qualified legal/product approval before production customer-data use.
- Resume Volume II only after the corrected frozen-baseline tag exists; accept later Volume I changes only for demonstrated defects or approved owner decisions.
