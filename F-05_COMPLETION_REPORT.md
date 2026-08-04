# F-05 Entitlement Reservation Subsystem (entitlement-interim-v1) — Completion Report

Status: **ACCEPTED** (owner D2 / DECISIONS ADR-069 authorised; standing delegation ADR-061, 2026-07-29,
DECISIONS ADR-075) — the integration branch `implementation/s01-registration-access` pushed; protected
branch `main` untouched. A shared **foundation** built before S-07-003 StartCrawl consumes it.

The ADR-026 five-lens review returned **security / concurrency / schema PASS**. One confirmed-blocking
finding (the max-execution ceiling was unenforced) — raised independently by the contract AND architecture
lenses — was **fixed before acceptance**, with review-driven hardening. See "Independent review" below.

## What was built

The shared reserve/commit/release/heartbeat surface for high-cost operations (crawl.start,
reassessment.start, ai.generate, export.generate), consumed **in the caller's transaction** with **no actor
entry point** (S-22 WF-015: entitlement checkpoints are "internal to the operation being gated").

- **Migration `20260727120120`** — five FORCE-RLS tenant tables: `entitlement_counter_windows` (T-MUT, the
  per-(org, counter_group, UTC-day) accumulator, unique slot), `entitlement_decisions` (T-IMM, the immutable
  Allow/AllowWithWarning/Block record with the closed reason/recovery enums + subject XOR), `entitlement_reservations`
  (T-MUT; **F-05 owns** reserved→executing→committed/released/expired), `entitlement_lease_heartbeats` (T-IMM,
  one row per accepted renewal), `entitlement_commit_intents` (T-MUT, pending→committed/released). Guards freeze
  identity/limits, refuse DELETE, and enforce the state machine; composite tenant FKs; grants immutable =
  SELECT/INSERT, mutable = SELECT/INSERT/UPDATE, **no DELETE anywhere**.
- **`Platform::Entitlement::InterimPolicy`** — the frozen `entitlement-interim-v1` rules (WORKFLOW :527:
  crawl.start counter-group `crawl.start`, unit `crawl_run`, soft 3 / hard 4, 15-min prestart lease, 65-min
  max execution, durable commit = "Crawl completed with ≥1 valid Document"; plus reassessment/ai/export), the
  half-open UTC-day counter window, and the allow/warn/block formula (`committed + active_reserved + requested
  <= hard`, equality allowed; result `>= soft` warns). **Operative limits are this fixed constant, NOT the
  non-operative genesis policy bytes** (ADR-069; genesis untouched).
- **`Platform::Entitlement::Store` + `Service`** — `reserve` (serialized on the counter window per WORKFLOW
  :549: get-or-create the window, classify, write the immutable Decision, and on allow create a reserved
  reservation accruing its units), `start_execution`, `heartbeat` (the parent-row-lock renewal, schema :421),
  `commit` (move units reserved→committed + bind the durable output), `release`, and `expire` (the
  prestart/lease reclaim). `Platform::Entitlement::InvariantViolation`-guarded CAS on every transition.
  ErrorCatalog: `reservation_expired`.

## Verification (exact results)

- Whole repository: **1431 examples, 0 failures**. Zeitwerk clean; Packwerk no offenses; Brakeman 0 warnings;
  bundler-audit no vulnerabilities. Architecture fitness **31/0**.
- Both migrations (`20260727120120` + the review-hardening `20260727120130`) **were verified by STRUCTURE LOAD, not migration replay (ADR-129)**; the schema
  dump is **idempotent**. `verify_runtime` OK — 15 checks, RLS intact.
- 34 F-05 examples: unit (the formula boundaries incl. equality-at-hard, UTC windows, frozen rules); the
  service lifecycle over the **real** f1_web + proved-org-context path (allow/warn/block via accumulated
  reservations, short-circuits, reserve→execute→heartbeat→commit, release, prestart + lease expiry, the 65-min
  max-execution cap on a heartbeating lease, and commit-releases-past-deadline); and persistence invariants
  (RLS/grants/guards/state-machine/uniques on all five tables).

## Independent review (ADR-026 — ADR-075)

Five lenses ran independently with live DB probes.

- **Security / concurrency / schema — PASS.** Cross-tenant reads/writes blocked on all five FORCE-RLS tables
  (proof-gated context; composite tenant FKs reject cross-tenant lineage); the WORKFLOW :549 atomic-reserve
  serialization holds under five two-connection race probes (no over-reservation past hard, no lost update, no
  double-count, no torn transition, no lease/heartbeat race); every guard edge, CHECK, and partial-unique
  verified with **no NULL hole**; migration hygiene clean (was verified by structure load, not migration replay (ADR-129), idempotent dump, FK-safe down).
- **CB (CONFIRMED-BLOCKING, contract + architecture) — FIXED.** The 65-min maximum-execution ceiling was a
  dead constant and `commit()` lacked the lease-expiry guard its siblings had, so a faithfully-heartbeating
  operation ran and committed unbounded past its metered ceiling (violating WORKFLOW :551 / S-22 / PRULE-039).
  Fixed via `Service#effective_deadline = min(lease_due, started_at + max_exec)`, gating
  `start_execution`/`heartbeat`/`commit`/`expire`; a past-deadline commit **releases** (`lease_expired_at_commit`).
  Tests added.
- **Hardening (migration `20260727120130`)** — DB hard-cap CHECK `reserved + committed <= hard`
  (concurrency defence-in-depth); `idempotency_key_digest` NOT NULL (WORKFLOW :543); dropped the redundant
  heartbeat index; reason precedence reordered (`entitlement_inactive` before `operation_unknown`, :541);
  CAS-return checks on every transition; `require "securerandom"`; deferrals documented in-code.
- **Non-blocking, recorded (no change).** Subject uuids without FK are inert within-tenant; two org-implicit
  writes are FORCE-RLS-backstopped; `HEARTBEAT_CADENCE_SECONDS`/`high_cost?` are the consumer's API.

## Known deferrals (honestly recorded)

**F-05 emits no `event_registry` envelopes** — the entitlement domain events are emitted by the CONSUMING
workflow (workflow_id is WF-NNN only; F-05 returns the data to emit from). **The S-07-003 review must verify
StartCrawl emits `EntitlementReserved`/`EntitlementLeaseRenewed` with the mandated fields.** Low-cost
`baseline_reads` accounting (`low_cost_*` tables) is deferred to S-22. Replay/`retry_of` dedup is the
consumer's command-level idempotency. Per-org prestart-lifetime shortening (1-15 min) is OD-006-era.

## What this tranche did NOT do (deliberate)

No actor-facing command/route. No crawl execution (S-07 consumes this surface). No low-cost accounting (S-22).
No change to the genesis `entitlement_policies` bytes or `baseline_content.rb`. Next: **S-07-003 StartCrawl** —
reserve `crawl.start` via F-05 at Queued→Running, create the initial Evaluation (OD-018), emit the entitlement
events — then S-07-004..011 under the standing delegation.
