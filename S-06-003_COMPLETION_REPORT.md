# S-06-003 source_scope_change_requests + ProposeSourceScopeChange (pending) — Completion Report

Status: **ACCEPTED AND MERGED** (under owner standing authority, 2026-07-27, DECISIONS ADR-061) —
fast-forward merged from `tranche/S-06/S-06-003` into `implementation/s01-registration-access` at `b76e16b`
(no merge commit, no history rewrite); added to `BUILD_STATE.completed_blocks` (BUILD_PLAN S-06-003 →
completed); the integration branch pushed. The protected branch (`main`) is untouched. Implemented and
independently reviewed on that branch (implementation commit `b94b0f0`). The second sub-tranche of the
owner's Option-1 decomposition of S-06.

All five independent ADR-026 lenses returned **PASS** with **zero confirmed-blocking findings** (ADR-060).

## What was built

The Source Scope Change Request aggregate and the WF-004 propose command, **pending path only**
(WORKFLOW_SPECIFICATIONS.md § Source Scope Change Contract :414, :705; contracts/S-06.json MTX-029;
APPLICATION_LAYER.md § WF-004; owner ADR-059).

- **`source_scope_change_requests` migration** — the canonical aggregate table: FORCE row-level security
  (`organization_id = f1_current_context_org()`), terminal-row immutability + frozen-facts /
  refused-transition guard (every transition `FALSE` this tranche, DELETE refused), the state CHECK
  (`pending/approved/rejected/canceled/expired`), the 20-2,000 char reason CHECK, 32-byte digest CHECKs,
  array cardinality CHECKs, the composite Source FK `(organization_id, project_id, source_id)`, and two
  indexes (source+state; due-where-pending). Runtime grant **SELECT, INSERT only**. It **was verified by STRUCTURE LOAD, not migration replay (ADR-129)**
  and produces **no `structure.sql` drift** beyond itself.
- **`source.scope.propose` permission** — the ratified Permission Baseline row (WORKFLOW_SPECIFICATIONS.md
  :144: allow OrganizationAdmin/MarketingOperator/TechnicalImplementer) materialized into
  `permission-baseline-v1` as a pure data addition (the S-05-001 `source.verify` pattern; VERSION unchanged,
  not a protected permission).
- **`Workflows::Wf004::ProposeSourceScopeChange`** — authenticate → tenant check (cross-org/project/
  nonexistent Source → `tenant_mismatch`, no write) → authorize `source.scope.propose` → validate the reason
  (20-2,000) and proposal shape → read the current active Source Scope Policy and check the
  `expected_active_policy_version` (`source_not_verified` / `stale_active_policy_version`) → classify via the
  merged **S-06-002 classifier** (a boundary violation → `unsupported_source_scheme` /
  `source_scope_boundary_violation`, no write) → create exactly one **PENDING** request with the normalized
  proposed rules + content hash, the **24-hour F-04 expiry** (`source_scope_request_expire`; execution is
  S-06-005), the full ledger, and one **`SourceScopeChangeRequested`** event — all in one transaction,
  idempotently (`idempotency_conflict` on changed content). The Source's verified `canonical_host` is
  authoritative (never a command input), so a scope change can never change the host.
- **Interim (owner-accepted):** a contraction remains **pending** here — the fail-closed interim; atomic
  contraction activation, Decide/Cancel and expiry execution are S-06-004/005. No provisional alternative
  activation path exists.
- **`SourceScopeChangeExpirySchedule`**, **`SourceScopeChangeStore`**, and the S-06-003 **ErrorCatalog**
  reason codes.

## Commit tranche (branch `tranche/S-06/S-06-003`, base `4d3773f`)

| Commit | Purpose |
| --- | --- |
| `82b67f1` | S-06-003 authorisation (ADR-059); HD-S06-003-AUTHORISE resolved (planning) |
| `b94b0f0` | S-06-003 (1/n): migration + guard + RLS + grant + permission row + expiry schedule + store + command + handler + ErrorCatalog reasons + specs; two S-04 characterization specs updated |
| _(records)_ | ADR-060 (review outcome), a comment-only migration clarification, BUILD_STATE/BUILD_PLAN, this report |

Diff `4d3773f..b94b0f0`: 13 files, ~1,239 insertions / 16 deletions — well within the reviewability limits.

## Verification (exact results)

- Whole repository: **1286 examples, 0 failures**. Zeitwerk clean; Packwerk no offenses; Brakeman 0
  warnings; bundler-audit no vulnerabilities. Architecture fitness (`spec/architecture`) **31/0**.
- `migration_safety_no_drift`: the migration **was verified by STRUCTURE LOAD, not migration replay (ADR-129)** (`f1_test` reprovisioned by structure load (ADR-129) this
  run) and `db:schema:dump` shows no drift beyond the migration.
- `runtime_role_and_rls`: `f1:db:verify_runtime` OK as `f1_web` — **15 checks passed (RLS intact)**;
  `f1_runtime` holds **SELECT, INSERT only** on the new table (no UPDATE/DELETE).
- Rubocop: only `Layout/SpaceInsideArrayLiteralBrackets` — the accepted S-05 baseline idiom.
- New specs: persistence invariants (11) + acceptance (10) — routing, boundary rejects, idempotency
  (replay + conflict), reason length, stale version, unverified Source, tenant mismatch, RLS, guard.

Environment note: an IDE `db:test:prepare` on the new migration dropped `f1_test` (the runtime role cannot
`CREATE DATABASE`); it was reprovisioned by structure load (ADR-129) via `bin/f1-provision-db`. Two S-04 characterization
specs that asserted the scope-change table's absence were updated faithfully (registration still creates no
scope-change rows; the table now exists).

## Independent review (ADR-026) — five separately-invoked adversarial lenses

| Lens | Verdict |
| --- | --- |
| Contract correctness | **PASS** — MTX-029 propose path exactly; +24h due_at; pending-only; boundary via failure path; idempotency |
| Security / tenant-isolation | **PASS** — proved RLS context, tenant checks pre-write, composite FK, ratified permission, least privilege, no leakage |
| Concurrency / atomicity / idempotency | **PASS** — one-transaction atomicity; lock before check+insert; replay vs conflict; no double-create |
| Schema / migration-safety | **PASS** — additive, was verified by structure load, not migration replay (ADR-129), no drift, FORCE RLS, SELECT/INSERT grant, fail-closed guard, constraints complete |
| Architecture / scope / frozen | **PASS** — pending-only, no pull-forward, frozen contracts untouched, Zeitwerk+Packwerk clean, faithful S-04 spec updates |

**Zero confirmed-blocking findings.**

## Non-blocking observations recorded (not actioned — repair-only-confirmed-blocking)

- The 24h `due_at` delta is enforced application-side (no DB CHECK), then frozen by the guard with the
  SELECT/INSERT-only grant leaving the handler the sole writer; the migration comment was clarified
  (comment-only). A DB CHECK is an optional future hardening.
- The current-side rules are stored by reference (`expected_active_policy_version` + `current_content_sha256`)
  rather than inline — the current active policy is immutable and fully recoverable by version, so this is a
  faithful normalization (an inline snapshot would be write-only in this design).
- **Forward-compat flags for S-06-004** (vacuous here — this tranche grants no UPDATE and permits no
  transition): (1) when S-06-004 grants UPDATE and relaxes `pending -> approved`, its guard must freeze the
  already-terminal decision facts; (2) the active-policy read + expected-version check should be taken or
  re-validated under the per-Source advisory lock at activation, since S-06-004 introduces a concurrent
  policy writer.

## What happens next

- **Owner acceptance-and-merge (human_gate_after):** review `tranche/S-06/S-06-003` and, if accepted,
  fast-forward merge it into `implementation/s01-registration-access` and add `S-06-003` to `completed_blocks`.
- **Do not begin S-06-004** (atomic contraction activation + Decide + Cancel) until S-06-003 is accepted
  (owner instruction). **No merge, no push, `main` untouched.** S-06-004..006 remain `human_gate_before`.
