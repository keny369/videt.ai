# S-06-006 Source Lifecycle (PRULE-006) — Completion Report

Status: **ACCEPTED** (under owner standing authority, 2026-07-27, DECISIONS ADR-061/ADR-065) — the
integration branch `implementation/s01-registration-access` pushed. The protected branch (`main`) is
untouched. The fifth and final sub-tranche of the owner's Option-1 decomposition of S-06. **Its acceptance
closes and exhausts the S-06 block.**

All five independent ADR-026 lenses returned **PASS** with **zero confirmed-blocking findings** (ADR-065),
under heavy live exercise: all five legal edges succeed and all fifteen illegal edges raise; a forged-org
cross-tenant raw UPDATE affects zero rows under RLS; 5/5 two-connection concurrent-activation races yield
exactly one success; and there is no source-aggregate event-version collision.

## What was built

The Source lifecycle transitions for WF-004 (contracts/S-06.json MTX-057 / PRULE-006; MTX-029 lifecycle limb;
WORKFLOW_SPECIFICATIONS.md § Source lifecycle).

- **`Workflows::Wf004::{ActivateSource, DisableSource, ReactivateSource, RemoveSource}`** — four thin edge
  specs over a shared `SourceLifecycleTransition` handler: authenticate → refuse cross-tenant/missing Source
  → authorize `source.lifecycle.manage` (OrganizationAdmin or MarketingOperator only; a TechnicalImplementer
  is refused) → lock → idempotency → re-read → require the current state to be exactly the FROM state (an
  unlisted transition — including a repeat from the new state — is denied AND audited) and the expected state
  version (a stale version rejects with no side effect) → transition in one transaction, pinning the active
  policy version and emitting the lifecycle event once. The four edges: verified→active (SourceActivated),
  active→disabled (SourceDisabled), disabled→active (SourceActivated), disabled→removed (SourceRemoved).
- **Sources guard widened** (`db/migrate/20260727120070`) to permit exactly those four edges plus the
  S-05-006 proposed→verified edge; every other transition raises `source_lifecycle_transition_unavailable`,
  and the tenant-identity + registration-provenance freezes are preserved verbatim.
- **`source.lifecycle.manage`** materialized into `permission-baseline-v1` (OrganizationAdmin or
  MarketingOperator; VERSION unchanged; WORKFLOW_SPECIFICATIONS.md :145).
- **`SourceLifecycleStore`** (SourceStore shape) — the guarded transition, the Source read with the pinned
  policy version, the shared per-Source advisory lock (so lifecycle serializes with scope activation), and
  the WF-004 actor-attributed ledger.
- **Degenerate affected-run decision record** — disable/remove record an empty `affected_running_crawls`
  list; no crawl machinery (the running-Crawl restriction is applied by S-07 at its checkpoint).
- **ErrorCatalog**: `source_lifecycle_transition_invalid` (409), `source_lifecycle_unauthorized` (403),
  `source_lifecycle_reason_invalid` (400).

## Commit tranche (on `implementation/s01-registration-access`, base `13002aa`)

| Commit | Purpose |
| --- | --- |
| `cfe1b2f` | S-06-006 (1/n): migration + SourceLifecycleStore + SourceLifecycleTransition + 4 commands + 4 handlers + baseline + ErrorCatalog + 9 acceptance tests |
| `4484a1f` | S-06-006 (2/n): ADR-026 review coverage — MarketingOperator allow-side test |
| _(records)_ | ADR-065 (review outcome + acceptance + S-06 completion), BUILD_STATE/BUILD_PLAN, this report |

## Verification (exact results)

- Whole repository: **1330 examples, 0 failures**. Zeitwerk clean; Packwerk no offenses; Brakeman 0
  warnings; bundler-audit no vulnerabilities. Architecture fitness (`spec/architecture`) **31/0**.
- The migration **was verified by STRUCTURE LOAD, not migration replay (ADR-129)** (scratch-DB provision by the schema lens) and `db:schema:dump` shows no
  drift beyond the guard widening + the migration row. `verify_runtime` OK — 15 checks, RLS intact.
- 10 lifecycle acceptance examples (the four-edge walk; unlisted/stale denials audited; TI refused; Marketing
  allowed; tenant isolation; idempotent replay + distinct-repeat invalid; removal only from disabled; host
  freed for a fresh lineage on removal).

## Independent review (ADR-026 — ADR-065)

Five separately-invoked adversarial lenses, all **PASS**, zero confirmed-blocking. Non-blocking observations
recorded (none a regression or application-reachable defect): the pinned policy version is a live reference
(correct S-06 design; S-07 note); three pre-existing platform deferrals (ADR-063 FU-1 `permission_mode`
read_only ignored; FU-2 assignment-scope containment deferred; no `authority_current?` epoch recheck) — all
confirmed NOT newly widened by this tranche; and four cosmetic notes.

---

## S-06 completion summary

With S-06-006 accepted, the **S-06 Source Discovery and Scope block is COMPLETE and EXHAUSTED**:

| Sub-tranche | Delivered | ADR |
| --- | --- | --- |
| S-06-001 | Source Scope Predicate (PRULE-021) + fail-closed separator hardening | ADR-050/051/052 |
| S-06-002 | Scope Change Classifier (Option-B subset + query-multiplicity) | ADR-054/057/058 |
| S-06-003 | `source_scope_change_requests` + ProposeSourceScopeChange (pending path) | ADR-059/060/061 |
| S-06-004 | Atomic contraction activation + Decide + Cancel + Propose fast-path | ADR-062/063 |
| S-06-005 | ExpireSourceScopeChange + expiry-wins-at-due_at | ADR-064 |
| S-06-006 | Source lifecycle PRULE-006 (Activate/Disable/Reactivate/Remove) | ADR-065 |

Every sub-tranche passed all mandatory gates and a five-lens ADR-026 review with zero confirmed-blocking
findings. The owner's S-06 authorisation was limited to S-06.

**Next: STOP for owner authorisation.** S-07 (crawl / scheduler / checkpoint / scoring — CAP-007/WF-005) is
NOT authorised; per ADR-061's stop condition the controller returns to the owner for **HD-S07-AUTHORISE**
before any S-07 work. No S-07 scope is inferred or begun.

**Open owner follow-ups (recommended, not blocking):** ADR-063 FU-1 (platform `permission_mode: read_only`
is not enforced for write capabilities) and FU-2 (assignment-scope GrantScope containment is not enforced for
the resource capabilities) — both pre-existing platform-authorization items surfaced during the S-06-004/006
reviews, suitable for a dedicated platform-authorization tranche.
