# S-07-001 Crawl Policy (dedicated crawl_policies table) + ActivateCrawlPolicy — Completion Report

Status: **ACCEPTED** (under owner standing delegation ADR-061, 2026-07-27, DECISIONS ADR-070) — the
integration branch `implementation/s01-registration-access` pushed. The protected branch (`main`) is
untouched. The FIRST tranche of the S-07 "Crawl Execution and Recovery" slice.

All five independent ADR-026 lenses returned **PASS** with **zero confirmed-blocking findings** (ADR-070),
under heavy live exercise (guard-mutation exploits, cross-tenant probes under a proof-gated context,
build-from-empty, and a two-connection race).

## What was built

Crawl policy for WF-005 (contracts/S-07.json MTX-030 policy limb, MTX-059 PRULE-008;
WORKFLOW_SPECIFICATIONS.md § Interim Crawl Policy crawl-policy-v1 :423-458 / policy subflow :732). Realized
per owner decision **D1 (ADR-068)** as a dedicated table, with the owner-approved interim global ceiling.

- **`Workflows::Wf005::CrawlPolicy`** — the frozen `crawl-policy-v1` global safety ceiling (the twelve
  ratified soft/hard dimensions), the completeness / soft≤hard / narrowing predicates, and the pure
  `most_restrictive` effective-resolution function. Owner-approved migration path (ADR-068): a
  `release_artifacts` global row later supersedes the constant with NO behavioural change.
- **`crawl_policies` migration** — a dedicated immutable-content table: FORCE RLS, one active version per
  (Organization, scope, Project) via a partial-unique index, an `active -> superseded` lifecycle guard that
  freezes all content columns (including the primary key) and refuses DELETE, and a SELECT/INSERT/UPDATE
  runtime grant.
- **`Workflows::Wf005::ActivateCrawlPolicy`** — narrowing-only activation at Organization scope (an
  OrganizationAdmin) or Project scope (a MarketingOperator); validates completeness, soft≤hard, and
  at-or-below the resolved parent (Organization narrows the global ceiling; Project narrows the active
  Organization policy or the global ceiling) AND the global ceiling; guarded by the expected current,
  parent, and global versions; supersedes the prior active version (before insert, so one-active-per-scope
  holds); emits `CrawlPolicyActivated`; idempotent by key. Serialized by a per-Organization advisory lock.
  Permission `policy.crawl.manage` (Admin/Marketing only, scope limb enforced in-handler; implies no
  crawl-execution permission).
- **`Wf005::CrawlLedger`** (WF-005 ledger mixin) + **`CrawlPolicyStore`**. ErrorCatalog:
  `crawl_policy_unauthorized/scope_invalid/incomplete/soft_exceeds_hard/not_narrowing/stale_version/unavailable`.

## Commit tranche (base `e5b1f32`)

| Commit | Purpose |
| --- | --- |
| `c781647` | S-07-001 (1/n): CrawlPolicy constant/resolver + crawl_policies migration + ActivateCrawlPolicy + store + ledger + baseline + ErrorCatalog + 24 specs |
| `c5b32f1` | S-07-001 (2/n): ADR-026 review refinements (per-Org activation lock; id-frozen guard; audited crawl_policy_scope_invalid; most_restrictive unit spec; drop dead well_formed?) |
| _(records)_ | ADR-070 (review outcome + acceptance), BUILD_STATE/BUILD_PLAN, this report |

## Verification (exact results)

- Whole repository: **1361 examples, 0 failures**. Zeitwerk clean; Packwerk no offenses; Brakeman 0
  warnings; bundler-audit no vulnerabilities. Architecture fitness **31/0**.
- The migration **builds from empty** (scratch-DB provision by the schema lens) with **zero structure.sql
  drift**. `verify_runtime` OK — 15 checks, RLS intact.
- 31 crawl-policy examples (7 resolver unit; 15 acceptance: org/project narrowing, supersession, all
  rejections, strict scope enforcement, scope-invalid audit, idempotency, tenant; 10 persistence invariants
  incl. the id-freeze).

## Independent review (ADR-026 — ADR-070)

Five lenses, all **PASS**, zero confirmed-blocking. The contract lens confirmed the twelve bounds match
WORKFLOW:425-438 exactly and that the strict scope reading (Admin→Org, Marketing→Project) is faithful (a
qualified Admin cell, unlike source_scope's superset). Refinements applied: per-Organization activation lock
(NB-1), id-frozen guard (NB-2, defense-in-depth), audited `crawl_policy_scope_invalid`, `most_restrictive`
unit spec. Non-blocking observations recorded: inter-version broadening within a scope never weakens the
effective MIN envelope; the pre-existing FU-1/FU-2 platform gaps are inherited with no new instance
(backlogged, ADR-066).

## What this tranche did NOT do (deliberate)

No Crawl aggregate, QueueCrawl, StartCrawl, fetch, frontier, robots/sitemap, coverage, documents/ingestion,
or recovery. No entitlement reservation (foundation F-05). No generic `policy_artifacts` framework (D1
deferred it). Next: **S-07-002** (Crawl aggregate + QueueCrawl), then foundation **F-05** (entitlement
reservation, before StartCrawl S-07-003), continuing under the standing delegation.
