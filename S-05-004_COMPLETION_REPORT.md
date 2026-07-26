# S-05-004 verification_attempts + ReserveVerificationAttempt — Completion Report

Status: **ACCEPTED AND MERGED** (owner approval, 2026-07-26) — fast-forward merged from
`tranche/S-05/S-05-004` into the integration branch `implementation/s01-registration-access` at
`dd802a0`; added to `BUILD_STATE.completed_blocks` (BUILD_PLAN S-05-004 → completed, DECISIONS
ADR-038). The protected branch (`main`) is untouched and nothing is pushed. It was implemented,
verified and independently reviewed on that branch off base `891e295` (the owner-authorisation commit
ADR-036). Second sub-tranche of the owner-accepted Observation split (ADR-033). Consumes F-01..F-04
only through their frozen façades.

## What was built

The on-demand reservation limb of WF-003 Ownership Verification: the `verification_attempts` child
table of the `verification_requests` aggregate, and `Workflows::Wf003::ReserveVerificationAttempt`.

- **`verification_attempts` table** (schemas/POSTGRESQL_SCHEMA.md :288): the reserved lineage
  (tenant / Project / parent Request / Source, `attempt_number`, `origin` automated/on_demand, the
  nullable automated slot offset, `reserved_at_utc`), the observation-outcome columns (present but
  NULL until the completion limb), `state CHECK ('reserved','running','completed','quarantined')`,
  `unique (verification_request_id, attempt_number)`, `unique (organization_id, id)`, composite FKs
  to `verification_requests (organization_id, id)` and `sources (organization_id, project_id, id)`,
  forced tenant RLS, and a lifecycle guard that freezes the reservation and **withholds every state
  transition** until the completion limb relaxes its edge. Two load-bearing CHECKs: `reserved` carries
  no outcome, and the slot offset is present exactly for an automated attempt.
- **`ReserveVerificationAttempt`** — an authorized (`source.verify`) on-demand reservation. It
  serializes on the Request under the same advisory-lock key the expiry service uses, and in one
  transaction inserts a `reserved` on_demand attempt (`attempt_number = attempt_count + 1`),
  increments both the total and on-demand counts, and stores `on_demand_in_progress_attempt_id` — the
  count/marker `UPDATE` guarded on `request_status = 'pending' AND state_version = <read>`, so a lost
  race rolls the whole reservation back. No provider call, no Evidence, no domain event, no Request or
  Source transition (all later limbs).
- **The four denials, at their exact boundaries, writing nothing** (so `attempt_count` never moves):
  `verification_request_not_pending` (terminal), `on_demand_limit_reached` (count = 10 — the 10th
  succeeds, the 11th rejects), `on_demand_observation_in_progress` (marker set), `on_demand_rate_limited`
  (`now < last_completion + 5 min`; equality at 5 min allowed). Idempotency is checked **before** the
  state-version check, so an exact replay returns the same reserved attempt even though a successful
  reserve advanced the version.
- **ErrorCatalog** gains the three on-demand reason codes (F1-DOMAIN-409). **runtime_grants** gains an
  additive `verification_attempts` grant (SELECT/INSERT/UPDATE, **no DELETE**) under the ratified
  additive-new-table rule (ADR-029). Authorization uses the canonical `source.verify` permission — no
  new Permission Baseline row (MTX-028: "no other is introduced").

Out of scope (later sub-tranches, untouched): running the observation (the S-05-003 engine is consumed
by S-05-005), Evidence (F-03), `SourceVerificationObserved`, the attempt `reserved -> running ->
completed/quarantined` transitions, the matched success commit, and the automated slot schedule.

## Commit tranche (branch `tranche/S-05/S-05-004`)

| Commit | Purpose |
| --- | --- |
| S-05-004 (1/n) | `verification_attempts` migration (RLS + guard + composite FKs + CHECKs) + structure.sql + additive runtime grant + on-demand error reasons + table-invariants spec + S-04 forward-guard maintenance |
| S-05-004 (2/n) | `ReserveVerificationAttempt` command + handler (VerificationLedger; a reserve-specific `deny` keyed on the Request) + the store reservation methods + acceptance spec |
| S-05-004 (3/n) | Independent-review repairs (no behaviour change): correct the outcome-order docstring (replay precedes the version check; add `idempotency_conflict`) and remove three dead migration constants |

## Verification (exact results)

- Whole repository: **1149 examples, 0 failures**. Zeitwerk clean; Packwerk no offenses; Brakeman 0
  warnings; bundler-audit no vulnerabilities.
- DB permissions/RLS: `f1:db:verify_runtime` OK as `f1_web` — 15 checks passed (RLS intact).
- `migration_safety_no_drift`: `db:schema:dump` is idempotent; no `db/structure.sql` drift.
- Architecture fitness (`spec/architecture`): **31/0** — the slice consumes F-01..F-04 only through
  their public façades; the single-surface fences pass.

## Independent review (ADR-026)

Reviewed by separately-invoked models with no shared conversational state, across five adversarial
lenses (contract-correctness, security/tenant-isolation, migration/schema, test-adequacy,
architecture/frozen-contract): **PASS_NO_BLOCKING — zero blocking findings, zero confirmed-blocking
after the verify pass.** The reviewers byte-checked the reservation atomicity, the four denials at
their exact boundaries, `attempt_count`-unchanged-on-rejection, the state-version guard, the
idempotency-before-version ordering, the migration against the canonical schema (no drift), the RLS /
composite-FK / CHECK / guard invariants, and frozen-façade compliance.

Review-driven repairs applied (comment/dead-code accuracy only, no behaviour change; the prior
tranches' "comment accuracy" precedent): the outcome-order docstring corrected, and three unused
migration constants removed.

## Non-blocking findings recorded (not actioned per the "confirmed blocking only" instruction)

- **(medium) concurrency coverage:** "concurrent reserves cannot share a slot" is enforced by
  construction (per-Request advisory lock + the `state_version`-guarded `UPDATE` + the
  `unique (verification_request_id, attempt_number)` index, the last proven in the invariants spec) but
  is not exercised by a direct two-racer test. A follow-up could add one (deterministically: two
  reserves at the same expected version — the second is `stale_state_version`).
- **(low) rate-limit boundary:** tests reject at 4 min and allow at exactly 5 min; a tighter reject
  just below 5 min would pin the window exactly.
- **(observation) denial-not-recorded:** no test directly proves a denied reserve writes no idempotency
  record (so a retry re-evaluates); the counts-unchanged assertions cover the observable effect.
- **(considered, dismissed) WORK-CLAIM columns:** the canonical schema tags `verification_attempts`
  WORK-CLAIM, but the claim/lease state lives in `work_dispatch_bindings` (POSTGRESQL_SCHEMA.md :226),
  which references the attempt as a target — the attempt's own column list (:288) is implemented
  exactly. Not a gap.
- **(observation) idempotency_conflict ordering:** evaluated after the on-demand denials, matching
  IssueVerificationChallenge's guards-before-conflict order; the contract mandates no strict order and
  all are non-mutating F1-DOMAIN-409 conflicts.

## What happens next

- **Owner review gate (human_gate_after):** review `tranche/S-05/S-05-004` and, if accepted, merge it
  into `implementation/s01-registration-access` and add `S-05-004` to `completed_blocks`.
- **S-05-005 is NOT begun** (owner instruction). It is next in the authoritative sequence
  (CompleteVerificationAttempt — observation recording + Evidence) and remains `human_gate_before`.
- Nothing is pushed; no tag moved; no production path exercised.
