# TODO

This file is intended to be maintained automatically.

## Current Milestone

Could an experienced engineering team build F1 without asking the product owner a single functional question?

## Volume II Freeze And Implementation Readiness (ADR-023)

CLEARED. Volume II is implementation-ready. Every blocker is closed and enforced by an executable check with a load-bearing negative control:

- 72 retired blockers cited as live: classified individually in `specification/volume-ii/RETIRED_BLOCKER_CLASSIFICATION.md` (30 stale label, 29 masked dependency, 11 right outcome/wrong reason, 2 check artefact) and reconciled. No finding changed product behaviour - enforced by `retired_blocker_cited_as_live`, now scoped to the sentence and widened to the whole in-scope tree.
- Missing successor decision: OD-034 registered as the successor OD-020's ratified text delegates; OD-035 registered for the same reason against OD-019 - enforced by `unresolved_successor_decision`.
- Seven broken Markdown anchors that Pass B recorded as resolving: asserted, never executed. Fixed - enforced by `anchor_target_missing`.
- The prior `unauthorized_verification_method` vacuity: line scoping left it reachable. Closed by segment scoping - enforced by a regression control proven to kill the superseded rule.

## Owner Decisions Awaiting Approval

Seven, none blocking implementation. Each withholds one named limb under a deterministic fail-closed interim:

- OD-014 (Chief Product) - Project pause/resume/archive transition.
- OD-023 (Chief Security) - Credential rotation begin and complete.
- OD-027 (Chief Architect) - ParsingJob/IndexingJob cardinality: three named artifacts.
- OD-031 (Chief Architect) - Routine retention-expiry destruction trigger.
- OD-032 (Chief Architect) - Canonical namespace for an unassigned record.
- OD-034 (Chief Product and Chief Security) - Read authority for security, administrative and internal operational objects. Until approved, no operator or administrator can read Support Session, Incident, Investigation, Legal Hold, Emergency Access Grant, deletion-job or privileged Billing state through a defined permission.
- OD-035 (Chief Product) - Low-cost read route-to-operation declaration and `report.view`'s read surface. Until approved, every metered read route Blocks with `operation_unknown`.

## Known Completeness Gap

The Emergency Access Grant has no `emergency_access_grants` table, no `emergency_access_grant` `EventEntityType` member and no `EmergencyAccess*` `EventType` rows, and Volume I's Versioned Policy Resolution enumeration names no artifact type to back `emergency-access-v1`. Not an authority gap and not a withheld limb: OD-012's architecture is ratified and nothing about it awaits an owner. Bounds S-21 only; blocks no earlier slice. Outside ADR-023's authorised scope.

## Engineering Manual Governance Backlog (Passes 001-002, ADR-021 and ADR-022)

CLEARED. Every blocker recorded by Governance Pass 001 is closed and enforced by an executable check with a load-bearing negative control:

- OD-014 pre-emption removed (5 sites; 4 were not in the original audit) - enforced by `pending_od_preemption`.
- Invented `Assessment` entity purged (65 references, 21 chapters) - enforced by `invented_canonical_entity`.
- Invented routes, events and tables removed - enforced by `undefined_product_route`.
- Canonical `Organization` spelling enforced (204 corrections, 190 files) - enforced by `noncanonical_product_spelling`.
- Front matter debt retired at source; baseline deleted; generator fixed with regression tests.
- Count-based gates restated on blocking status in ROADMAP, PROJECT_STATE, specification/INDEX.md and specification/volume-ii/INDEX.md.
- Stale PROJECT_STATE header reconciled to the Volume I freeze.

Remaining, not blocking Specification Volume II:

1. Broaden citation coverage. Governance Pass 002 added governing citations where product authority was being implied (DM-REQ-001, 016 STATE_MODEL.md, OD-014, UPSTREAM-V1-PROJECT-LIFECYCLE-003, PM-REQ-003, POSTGRESQL_SCHEMA.md). Chapters that make no product-specific claim remain uncited by design; extend only where a claim needs an owner.
2. Consider narrowing the Volume I publication-placeholder exemption to the four files with legitimate template tokens, so a new placeholder in Volume I is caught rather than exempted by volume.
3. Consider whether Volume I chapter titles should adopt the `CHAPTER-0NN` three-digit form used by Volumes II-XII; the two-digit form is currently special-cased in the validator.

## Adversarial Spec Defect Backlog (Volume I)

1. Define finding lifecycle states and transitions used by scoring and adjudication.
2. Define adjudication workflow, authority, and SLA for review_required and disputed findings.
3. Define interim scoring algorithm semantics (pillar definitions, contribution fields, determinism rules) until OD-002 and OD-003 approvals finalize policy.
4. Obtain OD-001 owner approval or retain the already-defined `verification_observation` Verification Evidence payload, method-validation, and timeout interim contract.
5. Define role-permission matrix for all workflow actors and gated actions.
6. Define policy entity semantics and versioning for scope-change approvals and entitlement enforcement.
7. Define deduplication fingerprint algorithm and collision/idempotency behavior.
8. Define supersession mechanism and audit semantics for reassessment.
9. Define crawl bounded-limit constants and enforcement behavior when limits are hit.
10. Define notification retry, backoff, escalation target, and terminal failure behavior.
11. Define score visibility and redaction matrix by role.
12. Rewrite non-testable acceptance statements into measurable pass/fail assertions.
