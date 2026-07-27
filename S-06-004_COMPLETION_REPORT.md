# S-06-004 Atomic Contraction Activation + Decide + Cancel — Completion Report

Status: **ACCEPTED AND MERGED** (under owner standing authority, 2026-07-27, DECISIONS ADR-061/ADR-063) —
fast-forward merged from `tranche/S-06/S-06-004` into `implementation/s01-registration-access` (no merge
commit, no history rewrite); added to `BUILD_STATE.completed_blocks` (BUILD_PLAN S-06-004 → completed); the
integration branch pushed. The protected branch (`main`) is untouched. The third sub-tranche of the owner's
Option-1 decomposition of S-06.

All five independent ADR-026 lenses returned **PASS** with **zero confirmed-blocking findings** (ADR-063),
each under live-DB exercise (seven security exploit probes, a two-connection concurrency race probe, and a
build-from-empty migration provision). Every non-blocking refinement they surfaced was applied.

## What was built

The decision and activation layer for WF-004 Source Scope Changes (WORKFLOW_SPECIFICATIONS.md § Source Scope
Change Contract :420-421; contracts/S-06.json MTX-029; APPLICATION_LAYER.md § WF-004).

- **`Workflows::Wf004::SourceScopePolicyActivation`** — the shared, none-without-the-others activation used by
  both the Propose fast-path and Decide approval: in the caller's single transaction it inserts one new
  immutable `source_scope_policies` version (`source-scope-v{N}`, a monotonic per-Source ordinal read under
  the per-Source lock; DECISIONS ADR-062) and repoints the Source's `current_scope_policy_id`, guarded on the
  expected current pointer so a concurrent activation cannot apply twice (`LostRace` → rollback).
- **`Workflows::Wf004::DecideSourceScopeChange`** — approve/reject a PENDING request guarded by **both** the
  expected request state version AND the expected active-policy version; re-classify the stored proposal
  against the current active policy via the S-06-002 classifier; **dual control** — a contraction needs no
  second party, an expansion may be approved/rejected only by an OrganizationAdmin who is a different Account
  from the non-admin requester; approval activates exactly one new version, rejection requires a 20-2,000 char
  reason and changes no scope; idempotent by key. Emits `SourceScopeChangeApproved` / `SourceScopeChangeRejected`.
- **`Workflows::Wf004::CancelSourceScopeChange`** — cancel from **pending only**, identity-authorized (the
  requester, or an OrganizationAdmin via effective role assignments — not capability-based), 20-2,000 char
  reason, no policy or Source change. Emits `SourceScopeChangeCanceled`.
- **`ProposeSourceScopeChange` atomic fast-path** — a contraction by any `policy.source_scope.manage` holder
  (OrganizationAdmin or MarketingOperator), or an expansion by an OrganizationAdmin, is created,
  self-approved and activated in the **one** transaction (`SourceScopeChangeRequested` at aggregate_version 0
  then `SourceScopeChangeApproved` at 1, one new immutable policy version, no 24-hour expiry timer). Every
  other authorized proposal (a non-manage holder's contraction, a non-admin's expansion) stays **pending**
  with its expiry timer, awaiting Decide. The idempotency check precedes the active-version check so an exact
  replay of an auto-activating proposal returns the stored result; the Source is re-read under the per-Source
  lock so the repoint guard is taken against the live pointer.
- **Decision guard relaxation + UPDATE grant** (`db/migrate/20260727120050`) — `pending -> {approved,
  rejected,canceled}` permitted; `pending -> expired` still refused (S-06-005); terminal rows fully immutable.
- **Pending-immutability hardening** (`db/migrate/20260727120051`, ADR-063) — the decision-edge requirement is
  unconditional for a pending row (only a transition to a terminal decision state is permitted, so
  `pending -> pending` is refused and decision facts are write-once), and `created_at`/`correlation_id` are
  frozen. Completes the ADR-060 forward-compat flag.
- **`policy.source_scope.manage` permission** (OrganizationAdmin + MarketingOperator; WORKFLOW_SPECIFICATIONS
  :172), materialized as a ratified `permission-baseline-v1` data row (VERSION unchanged). **S-06-004
  ErrorCatalog** reasons. Store reads/writes: `read_request`, `policy_count`, `insert_source_scope_policy`,
  `repoint_source`, `transition_request`.

## Commit tranche (branch `tranche/S-06/S-06-004`, base `d187410`)

| Commit | Purpose |
| --- | --- |
| `1c93b75` | S-06-004 (1/n): guard relax (decision edges) + UPDATE grant + `policy.source_scope.manage` |
| `67e6a2d` | S-06-004 (2/n): SourceScopePolicyActivation + Decide + Cancel + Propose fast-path + ErrorCatalog + ADR-062 + 28 acceptance tests |
| `4bf4487` | S-06-004 (3/n): ADR-026 review refinements (guard hardening migration; fast-path lock re-read; audit terminal state; baseline comment; TYP-SEC test) |
| _(records)_ | ADR-063 (review outcome + acceptance + FU-1/FU-2), BUILD_STATE/BUILD_PLAN, this report |

## Verification (exact results)

- Whole repository: **1309 examples, 0 failures**. Zeitwerk clean; Packwerk no offenses; Brakeman 0 warnings;
  bundler-audit no vulnerabilities. Architecture fitness (`spec/architecture`) **31/0**.
- Both migrations **build from empty** (provision probe by the schema lens) and `db:schema:dump` shows no
  drift beyond them. `verify_runtime` OK — 15 checks, RLS intact.
- 44 WF-004 scope-change examples (propose fast-path + pending + boundary + idempotency + Decide dual control
  + reject + stale guards + terminal immutability + cancel authority + tenant + persistence invariants).

## Independent review (ADR-026 — ADR-063)

Five separately-invoked adversarial lenses, all **PASS**, zero confirmed-blocking:
- **Contract-correctness** — the six actor×direction fast-path cells, both-version guarding, event versions,
  idempotency ordering and the error contract all match MTX-029.
- **Security/tenant** — seven live exploit probes (dual-control bypass, self-approval, cancel authority,
  tenant isolation, guard, confused-deputy, content integrity) all held.
- **Concurrency/atomicity/idempotency** — a two-connection race probe confirmed no double activation (the
  loser's guarded UPDATE returns 0 rows → rollback); single-transaction, lock-ordering and success-only replay
  verified.
- **Schema/migration-safety** — builds from empty, 122 grants, verify_runtime green; guard edges live-tested.
- **Architecture/scope** — no S-06-005/006 behaviour pulled forward, no frozen surface touched, baseline
  VERSION unchanged, pattern-faithful.

### Recommended owner follow-ups (systemic; NOT S-06-004 defects — ADR-063 FU-1/FU-2)

1. **FU-1 — `permission_mode: read_only` is ignored for write capabilities** in the platform
   `CommandAuthorizer#confers?` (pre-existing; already affects `source.register`, `project.create`).
   S-06-004 widens the blast radius to scope-policy activation but adds no new gap. Recommend a dedicated
   platform-authorization tranche.
2. **FU-2 — assignment-scope (GrantScope) containment is not enforced** for the resource capabilities
   (deferred platform-wide; wired only to `role.manage`). The only in-scope action taken was to correct the
   inaccurate permission-baseline comment that had claimed the limb was enforced.

## What this tranche did NOT do (deliberate)

No Expire execution (S-06-005 — the `pending -> expired` edge stays refused, no `ExpireSourceScopeChange`
handler, no expiry job) and no Source lifecycle (S-06-006 — Activate/Disable/Reactivate/Remove). No crawl.
S-07 is not authorised. The allowlist `query_handling` serialization gap (pre-existing S-06-003, unexercised)
is recorded for the tranche that first exercises a non-`retain_all` allowlist.
