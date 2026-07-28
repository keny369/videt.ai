# S-03 Project Activation — WF-002 ActivateProject (Draft → Active) — Completion Report

Status: **ACCEPTED** (under owner standing delegation ADR-061, 2026-07-27, DECISIONS ADR-072/ADR-073) — the
integration branch `implementation/s01-registration-access` pushed. The protected branch (`main`) is
untouched. Built now on owner decision **D3** (HD-S07-D3-PROJECT-ACTIVATION) as the ratified-sequence
prerequisite (`S-06 → S-03 → S-07`) so S-07 QueueCrawl consumes a REAL active Project, never a fabricated
fixture.

The ADR-026 five-lens review returned **security / schema / concurrency PASS**. **One** confirmed-blocking
finding — **B1**, the MTX-027 first-match order inverting `active_source_required` and
`source_membership_changed` — was **fixed before acceptance** (reordered to the normative order; docstring
corrected; adversarial test added). **B2** (the `source_membership_changed` guard is inert) and **N1**
(recording the sealed selected-Source set) depend on the unbuilt source-set sealing subsystem and are
**deferred as tracked follow-up FU-3** per owner decision **D5** (ADR-073). **No immutable source-set sealing
is implemented in this tranche** — see the Known Limitation section below.

## What was built

The canonical WF-002 Project state transition **Draft → Active**, gated on **≥1 active same-Project Source**
(contracts/S-03.json MTX-027 activation limb; WORKFLOW_SPECIFICATIONS.md § WF-002 :651-666; CAP-003,
PRULE-004). Project pause / resume / archive remain withheld (OD-014).

- **`db/migrate/20260727120100_allow_project_activation.rb`** — a `CREATE OR REPLACE` of the
  `f1_projects_lifecycle_guard` trigger function that relaxes it to permit **exactly** `draft → active`
  (`IF NEW.state IS DISTINCT FROM OLD.state THEN IF NOT (OLD.state='draft' AND NEW.state='active') THEN RAISE …`).
  Every other state edge is still refused (`project_lifecycle_transition_unavailable`); the Organization-identity
  freeze (`project_organization_immutable`) and the creation-profile freeze (`project_profile_immutable`) are
  preserved verbatim. No table added; RLS/FORCE and the SELECT/INSERT/UPDATE-never-DELETE grant unchanged.
- **`Workflows::Wf002::ActivateProject`** (command + handler) — authenticate → refuse cross-tenant/missing
  Project (`tenant_mismatch`) → authorize **`project.activate`** (distinct from `project.create`) → per-Project
  lock → idempotency (target = the Project) → re-read under lock and apply the first-match order
  `project_not_draft` → `stale_state_version` → `source_membership_changed` → `active_source_required` → a
  compare-and-swap `draft → active` UPDATE (raises `LostRace` on 0 rows) → emit **`ProjectActivated`**. All
  writes (execution, authorization_decision, audit, event, result, idempotency) occur in the single
  `Platform::UnitOfWork` transaction. Naturally idempotent by the state guard; exact replay returns the stored
  result.
- **`ProjectStore`** — `lock_project`, `project` (id/state/state_version/source_set_version),
  `active_source_count` (sources in `state='active'` scoped to org+project), and the guarded `activate_project`
  UPDATE. The `project.activate` permission (OrganizationAdmin, MarketingOperator). ErrorCatalog:
  `project_activate_unauthorized` (403), `project_not_draft` / `active_source_required` /
  `source_membership_changed` (409), `activation_transaction_unavailable` (F1-DEPENDENCY-503).

## Verification (exact results)

- Whole repository: **1371 examples, 0 failures** on a **deterministic** green baseline (see the WF-013
  repo-health note below), including the B1 adversarial order test. Zeitwerk clean; Packwerk no offenses;
  Brakeman 0 warnings; bundler-audit no vulnerabilities. Architecture fitness **31/0**.
- The migration **builds from empty**; the schema dump is **idempotent** with the only structure.sql delta being
  the guard relaxation. `verify_runtime` OK — 15 checks, RLS intact.
- 9 acceptance examples over a production-real chain (bootstrap → register → verify → ActivateSource →
  ActivateProject): activation + `ProjectActivated`; `active_source_required` (no active Source, and a
  verified-but-not-activated Source does not satisfy it); a Technical Implementer denied; `project_not_draft`;
  `stale_state_version`; `source_membership_changed`; exact idempotent replay; cross-tenant refused. Plus the
  updated `project_setup_invariants` guard test (draft→active permitted; pause/archive/reverse refused) and the
  updated `wf002_create_project` state-transition test.

## Isolated repo-health correction — WF-013 deterministic test-clock (owner D4, commit `aca3065`)

Bringing the suite to a strictly-green baseline required fixing a **pre-existing wall-clock time-bomb** in four
WF-013 invitation-reference specs (present identically at the last accepted commit `c062b60`; **not** introduced
by S-03). Those specs anchored `fixed_now = 2026-07-20`, so their 7-day invitation references expired at
`2026-07-27 10:00`; the resolver `f1_resolve_invitation_reference` deliberately uses real database time
(`transaction_timestamp()`), so once the wall clock passed that instant the references correctly read as expired
and the specs failed. Per owner decision **D4** (repository policy requires an objectively green gate; do not
weaken to "no new failures"), the fix re-anchors those specs' `fixed_now` to the **database clock minus three
days** — `(@fixed_now ||= (TenantSeeder.db_now - (3*24*3600)).floor(6))` — aligning the fixed-clock handlers,
the `db_now`-anchored fixtures, and the real-time resolver so the outcome is deterministic regardless of wall
clock. **Tests only; no production behaviour changed.** The resolver's real-time property (a security invariant)
is untouched.

## Independent review (ADR-026 — ADR-073)

Five lenses ran independently with live DB probes.

- **Security / schema / concurrency — PASS.** Live cross-tenant read/UPDATE probes as the runtime role all
  returned 0 rows / `UPDATE 0` (RLS forced; `f1_current_context_org` proof-gated); the guard edge-table was
  verified (draft→active is the only permitted cross-state edge; org/profile freezes byte-identical; DELETE
  never granted); and the transition is race-tight (per-Project advisory lock before the re-read, CAS on
  state+version with `LostRace`, single-transaction idempotency with a DB unique-index backstop, exactly-once
  event).
- **B1 (CONFIRMED-BLOCKING) — FIXED.** The MTX-027 first-match order (normative) requires
  `active_source_required` before `source_membership_changed`; the handler had them reversed. Reordered to
  `project_not_draft → active_source_required → source_membership_changed → stale_state_version`, docstring
  corrected, and an adversarial test added (zero active Sources + wrong membership version → `active_source_required`).
- **B2 / N1 — DEFERRED as FU-3 (owner D5).** See Known Limitation.
- **N2 / N3 — non-blocking.** `activation_transaction_unavailable` retry(1s/5s)/10s-deadline is unimplemented,
  consistent with the accepted `onboarding_transaction_unavailable` precedent (N2); `policy_unavailable` has no
  path because the core transition resolves no policy (N3). Both are platform-layer limbs, noted for their
  eventual platform-wide implementation.

## Known limitation — source-set sealing deferred (FU-3, owner D5 / ADR-073)

**Immutable source-set sealing is NOT implemented in this tranche.** The active-Source precondition is enforced
by count, and `source_membership_changed` compares `expected_source_membership_version` against
`projects.source_set_version` — a column no code increments. The canonical immutable sealing subsystem
(`source_set_versions` / `source_set_memberships`, POSTGRESQL_SCHEMA.md :287-288) that would make a concurrent
Source-membership/scope change detectable and record the sealed selected-Source set (MTX-055, PRULE-004) was
**specified but never built** by any tranche, and is also required by WF-011 reassessment. Per owner decision
**D5**, S-03 is accepted with the current correct activation behaviour preserved — **no in-tranche digest and no
partial substitute** — and the dependency is tracked as follow-up **FU-3** (BUILD_STATE `open_decisions`;
BUILD_PLAN S-03 `out_of_scope`; ADR-073) with its downstream consumers named. No repository contract makes
source-set sealing a hard prerequisite for Project activation, so it is a separately sequenced subsystem.

## What this tranche did NOT do (deliberate)

No Project pause / resume / archive (withheld, OD-014). No Source or Crawl behaviour. No source-set sealing
subsystem (FU-3). No change to the resolver or any production code in the WF-013 repo-health correction. Next:
resume **S-07-002** (Crawl aggregate + QueueCrawl) using real end-to-end Project activation, then foundation
**F-05** (entitlement reservation, before StartCrawl S-07-003), continuing under the standing delegation.
