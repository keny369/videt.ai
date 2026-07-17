# TODO

This file is intended to be maintained automatically.

## Current Milestone

Could an experienced engineering team build F1 without asking the product owner a single functional question?

## Engineering Manual Governance Backlog (Pass 001, ADR-021)

Registered by Governance Pass 001. Items 1 and 2 are prerequisites for Volume II.

1. Correct Engineering Manual Volume III product-behaviour ownership conflicts by controlled change. EM-III-010 `Project#archive!`, `project.archive!` and the "archived Projects cannot accept new Assessments" invariant pre-empt pending OD-014 and its live blocker `UPSTREAM-V1-PROJECT-LIFECYCLE-003`; replace with an explicit deferral naming the canonical owner.
2. Purge the invented `Assessment` entity from Volume III. DM-REQ-001 does not define it. It propagates to `AssessmentCompleted`, `IssueDetected`, `POST /assessments`, `AssessmentRecalculationJob` and an `assessments` table, and EM-III-003 presents it as canonical terminology while claiming to quote the Product Specification. Correct the non-canonical `Organisation` spelling, including `organisation_id`, at the same time.
3. Correct or remove the invented event names in EM-III-003 and EM-III-017 and the routes in EM-III-019, none of which have Specification authority.
4. Retire `scripts/front_matter_baseline.txt`. 247 files still carry a structural defect preventing authority metadata from being parsed. Volumes II through XII are not frozen and may be corrected directly; frozen Volume I requires its own controlled change. The baseline may only shrink.
5. Correct the body indentation of the 177 files with indented front matter. The front matter is the parsing defect and is baselined; the indented body additionally renders as a code block. Fix `scripts/generate_engineering_manual.py` so regeneration stops reintroducing both.
6. Add citation anchors to the manual. `PM-REQ`, `SEC-REQ` and `UPSTREAM-` are cited zero times across the manual, so its deferral boilerplate names no canonical owner. This is the structural reason Volume III filled the vacuum with invented specifics.
7. Restate the two surviving count-based gates, both left untouched because this pass must not begin Volume II: `specification/volume-ii/INDEX.md` line 131 gates the Volume II architecture baseline on "all thirteen upstream Volume I blockers", and `specification/INDEX.md` line 96 reports Volume II as blocked by "the thirteen upstream ambiguities". Both carry the count defect corrected in Gate C.
8. Reconcile the stale `PROJECT_STATE.md` snapshot header, which is dated 2026-07-16 and still describes Volume I as accepted but NOT frozen while the same document records the `v1.5-volume-i-frozen` baseline.

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
