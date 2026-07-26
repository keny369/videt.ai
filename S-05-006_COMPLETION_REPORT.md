# S-05-006 matched success commit + source-scope-interim-v1 — Completion Report

Status: **ready_for_review** — implemented, verified and independently reviewed on branch
`tranche/S-05/S-05-006` (off base `af25168`, the owner-authorisation commit ADR-042), **not merged**;
the protected branch (`main`) is untouched and nothing is pushed. Fourth sub-tranche of the
owner-accepted Observation split (ADR-033); owner-authorised with Option A (ADR-042). Consumes
F-01..F-04 only through their frozen façades.

## What was built

The matched-verification success commit of WF-003 Ownership Verification, extending
`Workflows::Wf003::CompleteVerificationAttempt`. On a **matched observation committing before expiry**,
the completion transaction commits the atomic multi-root success — none may appear without the others:

- **materialize `source-scope-interim-v1`** — the fixed interim Source Scope Policy
  (WORKFLOW_SPECIFICATIONS.md :412: HTTPS, default port 443, the verified canonical host, include `/`,
  no exclude, `retain_all`) into the new minimal, canonical-shaped `source_scope_policies` table;
- **Request `pending → verified`/`matched`** with the F-02 challenge material erased (redelivery
  disablement); the immutable challenge digest survives;
- **Source `proposed → verified`** with the interim policy pinned (`current_scope_policy_id`);
- **`SourceVerified`** on the Source aggregate.

**Expiry wins at the boundary:** a matched observation completing **at or after** `expires_at_utc` is
recorded like any observation (Evidence + attempt completed) but does **not** verify — the Source stays
`proposed` and the Request `pending` for a later expiry (contract: "at exact equality expiry wins").
A non-matching outcome is unchanged from S-05-005 (records only).

**Atomicity & exactly-once:** every success write is guarded on the expected Request and Source state
versions; a lost race raises `LostRace → InvariantViolation` and the whole completion rolls back
(Evidence, policy, both transitions, the F-02 erase — together). Concurrent matched completions
serialize on the per-Request advisory lock; the loser re-reads a non-pending Request and rejects with
no side effect. An idempotent replay re-transitions, re-emits and re-materializes nothing.

**Option A (minimal, canonical, S-06-extensible):** the `source_scope_policies` table carries exactly
the canonical Source Scope Policy fields (S-06.json MTX-029) — host, allowed schemes/ports,
include/exclude prefixes, query handling, policy version, scope, content hash — is immutable (T-IMM
trigger + SELECT/INSERT-only grant), source-scoped for the interim (nullable `source_id` for later
Organization/Project scope), with the composite Source FK and the scope/source CHECK. No S-06
change-request/source-set machinery is built. The two guard edges relaxed are exactly
`sources proposed → verified` and `verification_requests pending → verified`.

## Commit tranche (branch `tranche/S-05/S-05-006`)

| Commit | Purpose |
| --- | --- |
| S-05-006 (1/n) | `source_scope_policies` table (RLS + immutability + composite FK + CHECKs) + the two guard-edge relaxations + structure.sql + additive grant + invariants spec + forward-guard maintenance |
| S-05-006 (2/n) | The matched success commit + interim-policy materialization + `SourceVerified` in `CompleteVerificationAttempt` + store methods + the success spec (atomicity, exact policy, exactly-once) |
| S-05-006 (3/n) | Independent-review repair (confirmed-blocking): enforce the `expires_at_utc` boundary on verify (app gate + DB backstop + boundary specs) |

## Verification (exact results)

- Whole repository: **1173 examples, 0 failures**. Zeitwerk clean; Packwerk no offenses; Brakeman 0
  warnings; bundler-audit no vulnerabilities.
- DB permissions/RLS: `f1:db:verify_runtime` OK as `f1_web` — 15 checks passed (RLS intact).
- `migration_safety_no_drift`: `db:schema:dump` is idempotent; no `db/structure.sql` drift.
- Architecture fitness (`spec/architecture`): **31/0** — foundations consumed only through their
  façades; the F-03 evidence single-surface fence passes.

## Independent review (ADR-026)

Five adversarial lenses by separately-invoked models with no shared conversational state
(contract-correctness, security/tenant-isolation, schema/canonical-shape, concurrency/atomicity,
architecture/scope): the first pass returned **BLOCK — two confirmed-blocking findings (the same
defect)**: the matched success commit did not enforce the `expires_at_utc` boundary, so a matched
observation committing at/after expiry could wrongly verify.

**Repair applied (confirmed-blocking only):** verification now gates on `now < expires_at_utc` (strict —
equality means expiry wins), with a defence-in-depth guard in `verify_request_on_match` and two boundary
specs. A focused independent re-review of the repair delta confirmed **RESOLVED, no new blocking issue**.
The tranche now has **zero confirmed-blocking findings**.

## Non-blocking findings recorded (not actioned per the "confirmed blocking only" instruction)

- **(low) SourceVerified event envelope** omits `idempotency_identity_hash` / `input_hash` that the
  sibling `SourceVerificationObserved` carries — a minor consistency gap; the event validates and
  persists correctly.
- **(low) F-02 erase ordering** — `Platform::Encryption.erase` runs between the two guarded UPDATEs; it
  is transactional (same connection) and rolls back with a lost race, so it is safe.
- **(low) test coverage** — only the exact-equality "at expiry" boundary is tested (a strictly-after
  case is a-fortiori handled by the same gate); and a true concurrent two-racer verification test could
  join the sequential exactly-once coverage.
- **(observation) app-clock boundary** — the expiry boundary is decided on the application `now` (the
  canonical pre-commit instant), consistent with how `expires_at_utc` is derived at issuance, and
  serialized against the expiry job via the advisory lock; a deliberate platform choice, not a defect.
- Various minor observations (recorded in DECISIONS ADR-043).

## What happens next

- **Owner review gate (human_gate_after):** review `tranche/S-05/S-05-006` and, if accepted, merge it
  into `implementation/s01-registration-access` and add `S-05-006` to `completed_blocks`.
- **S-05-007 is NOT begun** (owner instruction). It is the final Observation sub-tranche (the automated
  observation slot schedule) and remains `human_gate_before`.
- Nothing is pushed; no tag moved; no production path exercised.
