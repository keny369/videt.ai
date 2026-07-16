# TODO

This file is intended to be maintained automatically.

## Current Milestone

Could an experienced engineering team build F1 without asking the product owner a single functional question?

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
