# S-07-002 Crawl Aggregate + QueueCrawl (WF-005) — Completion Report

Status: **ACCEPTED** (under owner standing delegation ADR-061, 2026-07-27, DECISIONS ADR-074) — the
integration branch `implementation/s01-registration-access` pushed; protected branch `main` untouched. The
SECOND tranche of the S-07 "Crawl Execution and Recovery" slice, resumed on owner decision **D5** using **real**
end-to-end Project activation (no fabricated active-Project fixtures).

The ADR-026 five-lens review returned **security / schema / concurrency / architecture PASS**. One
confirmed-blocking finding (**B1**, wrong OD-018 `recovery_action`) was **fixed before acceptance**, and the
strongest non-blocking items (idempotency-before-preconditions, precondition order, event payload, the OD-018
NULL-`crawl_id` backstop hole) were hardened. See "Independent review" below.

## What was built

QueueCrawl for WF-005 (contracts/S-07.json MTX-030 queue limb, MTX-058 PRULE-007;
WORKFLOW_SPECIFICATIONS.md § WF-005 :725-728, :734). Creates a single **root** queued Crawl and nothing more —
it **reserves no usage and creates no Evaluation** (those are StartCrawl + F-05, S-07-003).

- **`crawls` / `crawl_sources` / `evaluations` migration** (`20260727120090`) — three FORCE-RLS tenant tables.
  `crawls` (root/reassessment_child; request-pinned crawl-policy + entitlement-policy versions as dedicated
  columns per D1; state queued/running/completed/failed/canceled; kind↔parent and terminal-shape CHECKs; a
  guard freezing identity + request-pinned facts, refusing DELETE, and refusing every state change — later
  tranches relax Queued→Running/terminal). `crawl_sources` — **T-IMM**, the pinned request-time Source set
  (each Source's state version + active scope-policy id/version + canonical root, ordered). `evaluations` — the
  OD-018 DB backstops (`evaluations_orchestration_slot_unique`: one active orchestration slot per Project;
  `evaluations_initial_per_crawl_unique`: one initial Evaluation per Crawl) plus an immutability/lifecycle guard.
- **`Workflows::Wf005::QueueCrawl`** (command + handler) — authenticate → refuse cross-tenant/missing Project
  (`tenant_mismatch`) → authorize **`crawl.trigger`** → require active Project (`crawl_project_not_active`),
  a resolvable active Entitlement Policy (`crawl_entitlement_unavailable`), and ≥1 active Source
  (`crawl_no_active_source`) → per-Project lock + idempotency (project-scoped) → the OD-018 queue-time guard
  (`initial_evaluation_already_running`, re-checked at Queued→Running in S-07-003) → insert one root queued
  Crawl pinning the request-time crawl-policy (Project else Organization active version, else the frozen global
  ceiling) + entitlement-policy versions and the active Source set → emit **`CrawlQueued`**. All writes are in
  the single `Platform::UnitOfWork` transaction; idempotent by key.
- **`CrawlStore`** (reads the queue preconditions + writes the queued Crawl and its pinned Sources), the
  `crawl.trigger` permission (OrganizationAdmin/MarketingOperator), the QueueCrawl ErrorCatalog reasons, and
  the runtime grants (crawls S/I/U, crawl_sources S/I, evaluations S/I/U — never DELETE).

Documented interims (ADR-067/071, not owner decisions): `reassessment_required` is vacuously satisfied because
promotion (`current_score_projections`) is an S-09 table not yet built, so every request is a root
initial-assessment Crawl; the reassessment-child branch is deferred to WF-011.

## Verification (exact results)

- Whole repository: **1397 examples, 0 failures** on the deterministic green baseline. Zeitwerk clean; Packwerk
  no offenses; Brakeman 0 warnings; bundler-audit no vulnerabilities. Architecture fitness **31/0**.
- The migrations (`20260727120090` + the review-hardening `20260727120110`) **were verified by STRUCTURE LOAD, not migration replay (ADR-129)**; the schema
  dump is **idempotent** with no drift. `verify_runtime` OK — 15 checks, RLS intact.
- 26 new examples: 16 acceptance over a **production-real** chain (bootstrap → register → verify →
  ActivateSource → **ActivateProject** → QueueCrawl) — happy path pinning the global ceiling; pinning an active
  Organization-scope crawl policy; multi-Source ordering; all four precondition denials incl.
  `crawl_entitlement_unavailable`; the Project→Source→Entitlement first-match order; the OD-018 guard with its
  `recovery_action`; exact replay, replay-after-precondition-change, and idempotency_conflict; and the
  crawls/crawl_sources guards on real rows — plus 10 persistence invariants (RLS/grants on all three tables; the
  two OD-018 partial-uniques and the new NULL-`crawl_id` CHECK; the evaluations guard).

## Independent review (ADR-026 — ADR-074)

Five lenses ran independently with live DB probes.

- **Security / schema / concurrency / architecture — PASS.** Live cross-tenant INSERT/SELECT probes on all three
  tables were blocked (FORCE RLS + proof-gated context; composite tenant FKs reject cross-tenant Source pinning);
  the guards/constraints were edge-probed (crawls facts frozen + DELETE/state refused; crawl_sources T-IMM;
  evaluations guard; kind↔parent and terminal-shape CHECKs; the two OD-018 partial-uniques); the transition is
  race-tight (per-Project advisory lock, single-transaction idempotency with a DB unique backstop); and scope,
  packwerk seams, ledger arity and interim honesty conform (`current_score_projections` confirmed absent).
- **B1 (CONFIRMED-BLOCKING) — FIXED.** `initial_evaluation_already_running` returned the F1-DOMAIN-409 class
  default `recovery_action`, but MTX-030 / WORKFLOW_SPECIFICATIONS.md :734 mandate
  `await_running_initial_evaluation_or_submit_new_command`. Added a per-reason `REASON_RECOVERY` override in
  `Platform::ErrorCatalog` and asserted `recovery_action` (and `retryable=false`) in the OD-018 test.
- **N1 / N2 (hardened).** Reordered the handler so idempotency/replay is resolved **before** the domain
  preconditions (a replay now faithfully returns its stored result even after a precondition ceases to hold —
  new test) and the preconditions are re-read **under the lock** in the WORKFLOW_SPECIFICATIONS :725 order
  (Project → Source → Entitlement — new order + entitlement tests). This also closes the concurrency lens's
  pre-lock staleness window.
- **N3 (hardened).** `CrawlQueued` now carries `requested_crawl_policy_version` + `requested_entitlement_policy_version`.
- **Schema backstop (hardened).** New migration `20260727120110` adds
  `CHECK (kind <> 'initial' OR crawl_id IS NOT NULL)` so the OD-018 "one initial Evaluation per Crawl" index no
  longer relies on the app always supplying `crawl_id` (btree NULLs are distinct); persistence test added.
- Non-blocking, recorded (no change): multiple *queued* root Crawls per Project is intended (single-flight is
  authoritatively enforced at Queued→Running via the evaluations partial-unique, S-07-003); front-loaded crawl
  lifecycle columns/grants are inert now and consumed by later tranches; `active_sources` uses an INNER JOIN
  (safe under the verified→active invariant that an active Source always carries a scope policy); the pre-existing
  F-01 org-context trust boundary is unchanged.

## What this tranche did NOT do (deliberate)

No StartCrawl, entitlement reservation (F-05), fetch, frontier, robots/sitemap, coverage, documents/ingestion,
or recovery. Creates no Evaluation and reserves no usage (PRULE-007). No reassessment-child branch (WF-011). No
source-set sealing (S-03 FU-3). Next: foundation **F-05** (entitlement reservation, before StartCrawl S-07-003),
then S-07-003, continuing under the standing delegation.
