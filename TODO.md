# TODO

This file is intended to be maintained automatically.

## Current Milestone

Could an experienced engineering team build F1 without asking the product owner a single functional question?

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
