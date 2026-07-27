# S-06-005 ExpireSourceScopeChange + Expiry-Wins-at-due_at — Completion Report

Status: **ACCEPTED** (under owner standing authority, 2026-07-27, DECISIONS ADR-061/ADR-064) — the
integration branch `implementation/s01-registration-access` (which already carried the reviewed S-06-005
commits) pushed. The protected branch (`main`) is untouched. The fourth sub-tranche of the owner's Option-1
decomposition of S-06.

All five independent ADR-026 lenses returned **PASS** with **zero confirmed-blocking findings** (ADR-064),
under heavy live exercise: a two-tenant forged-organization_id cross-tenant expiry attack (rejected —
`scheduled_action_target_mismatch`, victim row byte-identical, no leak, RLS held), an 8/8 two-connection
`expire`-vs-`approve` thread race at exactly `due_at` (exactly one outcome, always the expiry), an empirical
disproof of the before-due idempotency-poisoning hazard, and a build-from-empty provision with live trigger
probes.

## What was built

The service-only timed expiry for WF-004 Source Scope Change Requests (WORKFLOW_SPECIFICATIONS.md § Source
Scope Change Contract :419; contracts/S-06.json MTX-029 domain_events/transaction_boundary/concurrency).

- **`Workflows::Wf004::ExpireSourceScopeChange`** (command + handler) — the executor behind the ratified
  `source_scope_request_expire` ScheduledAction that ProposeSourceScopeChange schedules on a PENDING request
  (the timer was created in S-06-003; this tranche runs it). Service-attributed (null actor); takes the SAME
  per-Source advisory lock as propose/decide/cancel; at `due_at_utc` transitions a still-pending request to
  `expired`, emits **`SourceScopeChangeExpired`** exactly once, and changes **no policy and no Source state**
  (the decision facts stay null; only `terminal_at_utc` is stamped). Idempotent by the action identity; a
  before-due timer is `scheduled_action_not_due` (non-replayable, so it cannot poison the at-due fire); an
  already-terminal request is a harmless no-op; a `due_at` mismatch is `scheduled_action_target_mismatch`.
  Registered in the closed F-04 dispatch table (`config/initializers/scheduled_actions.rb`) against the
  pre-ratified catalogue mapping.
- **`SourceScopeChangeExpiryStore`** — the VerificationExpiryStore shape specialized to
  `source_scope_change_requests` and stamped `WF-004`; service-attributed ledger, RLS-scoped reads, the
  guarded `expire` UPDATE, the shared per-Source lock.
- **Guard widening** (`db/migrate/20260727120060`) — `pending -> expired` added to the permitted terminal
  set, preserving every other invariant (DELETE refused, terminal rows immutable, tenant/proposed facts +
  created_at/correlation_id frozen, `pending -> pending` refused).
- **Expiry wins at `due_at`** — DecideSourceScopeChange and CancelSourceScopeChange now refuse a
  still-pending-but-due request (`now >= due_at_utc`) with **`source_scope_request_expired`**, so at exact
  equality the expiry transition wins over a decision or cancellation. `read_request` gained `due_at_utc`;
  the new reason maps to `F1-DOMAIN-409`.

## Commit tranche (on `implementation/s01-registration-access`, base `31bc6fb`)

| Commit | Purpose |
| --- | --- |
| `d435916` | S-06-005 (1/n): migration + expiry store + command + handler + registry + Decide/Cancel precedence + ErrorCatalog + 10 acceptance tests |
| `40b9489` | S-06-005 (2/n): ADR-026 review coverage — rejection-at-due_at + second-decision-on-expired tests |
| _(records)_ | ADR-064 (review outcome + acceptance), BUILD_STATE/BUILD_PLAN, this report |

## Verification (exact results)

- Whole repository: **1320 examples, 0 failures**. Zeitwerk clean; Packwerk no offenses; Brakeman 0
  warnings; bundler-audit no vulnerabilities. Architecture fitness (`spec/architecture`) **31/0**.
- The migration **builds from empty** (scratch-DB provision by the schema lens) and `db:schema:dump` shows no
  drift beyond the guard widening + the migration row. `verify_runtime` OK — 15 checks, RLS intact.
- 12 expiry acceptance examples (before/at/after `due_at`; emits once; no policy/Source change; idempotent
  replay; harmless late arrival; `due_at` mismatch; expiry precedence over approval/rejection/cancellation;
  a decision on an already-expired request changes nothing; dispatch registration) + the persistence
  invariants (the `pending -> expired` edge flipped from refused to permitted).

## Independent review (ADR-026 — ADR-064)

Five separately-invoked adversarial lenses, all **PASS**, zero confirmed-blocking. Non-blocking observations
recorded (none a regression or application-reachable defect): the expired-edge decision-fact latitude (the
DB does not independently force the decision columns null on `pending -> expired`; the sole writer already
leaves them null; identical to the pre-existing decision edges — recorded for a future backstop-hardening
pass, not fixed here); the absence of a `(aggregate_type, aggregate_id, aggregate_version)` unique index on
`event_registry` (pre-existing shared platform design); and two cosmetic notes.

## What this tranche did NOT do (deliberate)

No Source lifecycle (S-06-006 — Activate/Disable/Reactivate/Remove). No crawl. S-07 is not authorised. The
prior owner follow-ups (ADR-063 FU-1 read_only ignored; FU-2 assignment-scope containment deferred) remain
open platform-authorization items. S-06-006 is the last authorised S-06 sub-tranche; after it, S-06 is
exhausted and S-07 requires fresh owner authorisation.
