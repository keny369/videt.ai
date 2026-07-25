# S-05-002 ExpireVerificationRequest — Completion Report

Status: **ready_for_review** — implemented, verified and independently reviewed on branch
`tranche/S-05/S-05-002` (off base `58383dd`), **not merged**; the protected branch (`main`) is
untouched and nothing is pushed. Owner-designated as the next tranche (DECISIONS.md ADR-029). Consumes
F-01..F-04 only through their frozen façades.

## What was built

The expiry limb of WF-003 Ownership Verification: the service-only handler that runs when the
24-hour `verification_request_expire` ScheduledAction (scheduled by S-05-001) is due.

- A still-pending `verification_requests` row transitions `pending -> expired` with reason
  `challenge_expired`, guarded on its state version under an advisory lock.
- The challenge material is **cryptographically destroyed** in the same transaction
  (`Platform::Encryption.erase` + nulling the ciphertext/key references), so redelivery is
  immediately unavailable; the immutable challenge digest and the audit survive.
- `SourceVerificationExpired` is emitted exactly once; the Source is left `proposed`.
- Everything is **service-attributed** (the ScheduledAction executor identity, null human actor).
- It **closes the dangling `verification_request_expire` action** S-05-001 left (its handler now exists).

Guards, all tested: schema, target_type, target/due mismatch (`scheduled_action_target_mismatch`),
not-due (`scheduled_action_not_due`; equality at `expires_at` is due — expiry wins), already-terminal
(`verification_request_not_pending`), a not-visible target, and exact-action idempotent replay.

Out of scope (and untouched): DNS/HTTP observation (Reserve/Complete), the `proposed -> verified`
transition, cancellation and integrity-failure limbs, scoring.

## Commit tranche (branch `tranche/S-05/S-05-002`)

| Commit | Purpose |
| --- | --- |
| S-05-002 (1/n) | Migration: relax the lifecycle guard for exactly `pending -> expired` (every other edge still refused, identity/issuance still frozen) + `verification_request_not_pending` error + structure.sql |
| S-05-002 (2/n) | `Workflows::Wf003::ExpireVerificationRequest` command + service-attributed `VerificationExpiryStore` + handler; F-02 challenge erase; `SourceVerificationExpired`; registry wiring; specs |
| S-05-002 (3/n) | Independent-review repairs: end-to-end redelivery-unavailable test + not-found-target test |

## Verification (exact results)

- Whole repository: **1103 examples, 0 failures**. Zeitwerk clean; Packwerk no offenses; Brakeman 0
  warnings; bundler-audit no vulnerabilities.
- DB permissions/RLS: `verify_runtime` OK as `f1_web` — 15 checks passed (RLS intact).
- `migration_safety_no_drift`: `db:schema:dump` produces no `db/structure.sql` diff post-commit.
- Architecture fitness (`spec/architecture`) green — F-02 and F-04 single-surface fences pass; the
  runtime-grants least-privilege backstop passes.

## Independent review (ADR-026)

A separately invoked model with no shared conversational state reviewed the committed diff:
**pass_with_observations, zero blocking findings**. It confirmed atomic challenge destruction, the
minimal guard relaxation, the due/target guards, idempotent + state-version-guarded concurrency,
service attribution, and frozen-façade compliance. Two test-only repairs applied (its own
recommendations): the end-to-end redelivery-unavailable proof through the issuance path, and a
not-found-target test.

## Flagged for owner reconciliation (non-blocking)

The challenge material is destroyed **inline** at expiry (immediate, atomic) rather than via the
scheduled 60-second deletion job the canonical Volume I prose describes (`ChallengeCryptographicDeletionJob`
/ the reserved `verification_material_destroy` action kind). This is a strict strengthening authorized by
the BUILD_PLAN S-05-002 scope, but it leaves `verification_material_destroy` an orphaned catalogue kind
and the Volume I prose out of date. Per the constitution's single-source-of-truth standard, reconcile the
model/contract text and/or retire the reserved kind. Recorded as a flagged Volume I item (the
`organization_inactive` precedent), not silently changed. See DECISIONS.md ADR-030.

## What happens next

- **Owner review gate (human_gate_after):** review branch `tranche/S-05/S-05-002` and, if accepted,
  merge it and add `S-05-002` to `BUILD_STATE.completed_blocks`.
- **The tranche after S-05-002 was NOT begun** (owner instruction); the next WF-003 limb is designated
  from authoritative sources + owner decision after this review.
- Nothing is pushed; no tag moved; no production path exercised.
