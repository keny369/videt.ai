# S-07-003 StartCrawl + Initial Evaluation (WF-005) — Completion Report

Status: **ACCEPTED** (under owner standing delegation ADR-061, 2026-07-29, DECISIONS ADR-076) — the
integration branch `implementation/s01-registration-access` pushed; protected branch `main` untouched.
The THIRD tranche of the S-07 "Crawl Execution and Recovery" slice, and the first consumer of the
F-05 entitlement reservation foundation.

The ADR-026 five-lens review returned **concurrency PASS**; the security, contract, schema and
architecture lenses each returned confirmed-blocking findings. **All five were fixed before
acceptance**, together with the strongest non-blocking items. See "Independent review" below.

## What was built

StartCrawl for WF-005 (contracts/S-07.json MTX-030 start limb, MTX-058 PRULE-007;
WORKFLOW_SPECIFICATIONS.md § WF-005 :725-728/:734/:736; SEARCH_CRAWL_RETRIEVAL.md § Crawl Admission
And Snapshot; DECISIONS OD-018). The service-only `Crawl.Queued -> Crawl.Running` commit — the gate
WF-005 places at the running transition rather than at queueing.

### The dispatch path (making the start reachable)

`crawl_dispatch` is the ratified action kind for "admitted queued Crawl start"
(BACKGROUND_PROCESSING.md :137), enqueued as `crawl_orchestrate` (:197), whose permitted operations
are exactly `StartCrawl` / `CompleteCrawl` / `FailCrawl` / `CancelCrawl` "selected solely from
persisted Crawl/deadline state" (:377). S-07-002 built QueueCrawl without that limb because its
handler did not yet exist; S-07-003 completes it.

- **`Workflows::Wf005::CrawlDispatchSchedule`** creates the action **on the queueing transaction's own
  connection**, so the queued Crawl and its dispatch commit or roll back together — no
  fire-and-forget after commit, and a refused queue leaves no action to claim (tested).
- **`config/initializers/scheduled_actions.rb`** registers `crawl_dispatch` @ `1.0` -> `StartCrawl`.
  `crawl_dispatch` is a *specialized* work type, so it is absent from the generic
  `scheduled_action_dispatch` operation table and `Registry#register`'s cross-check is inert for it
  by design; the catalogue mapping is asserted in the acceptance spec instead. Precedent:
  `verification_observation_slot`.

### The start commit

**`Workflows::Wf005::StartCrawl`** (command + handler) runs under the **same** per-Project advisory
lock QueueCrawl takes (`crawl-queue:<org>:<project>` — verified byte-identical), is idempotent by the
ScheduledAction identity — resolved **before** the domain preconditions, as the accepted
QueueCrawl/ActivateProject order — and then applies the pre-execution gate in first-match order:

1. the Crawl is still `queued` (else the harmless terminal execution, `crawl_not_queued`);
2. the **Organization** is still active (added by the security lens — see CB1);
3. the Project is still active;
4. at least one Source is still active;
5. **OD-018** — no pending/running initial Evaluation for the Project on another Crawl;
6. the MTX-030 Evaluation key `(crawl_id, kind=initial)` is free (`evaluation_creation_conflict`);
7. the **current** crawl policy resolves (frozen global ceiling ∧ Organization ∧ Project — a new
   restriction governs queued work immediately, so it is re-resolved, never the pinned version);
8. the root `crawl.start` Entitlement Decision + reservation is obtained atomically (F-05).

2-5, 7 and 8 transition the queued Crawl to `failed` and reserve nothing. 6 is a **request
rejection** and changes no state. An accepted start, in **one transaction**:

- moves the reservation `reserved -> executing` (the start commit *is* its first side effect, so the
  executing lease and the 65-minute maximum-execution ceiling begin here);
- transitions the Crawl `queued -> running` under a `(state, state_version)` CAS, stamping
  `started_at` (the wall-clock origin, :736), the resolved wall-clock `deadline_at`, and the
  Decision/reservation ids;
- creates **exactly one** pending Evaluation keyed by `(crawl_id, kind=initial)`, `started_at` NULL
  (":736 materializes Evaluation.Pending without starting it"), `orchestration_slot_active` FALSE
  (POSTGRESQL_SCHEMA.md :340 reserves the slot for reassessment/retry);
- writes its immutable `evaluation_orchestration_contexts` row (the root Decision/reservation, the
  re-resolved crawl-policy version and the Decision's own entitlement-policy version, null prior
  pointers for an initial); and
- emits **`CrawlStarted`** + **`EvaluationPending`**, service-attributed with a null human actor.

### Supporting changes

- **`IdentityAccess::Infrastructure::CrawlStartStore`** — the service-attributed WF-005 ledger writers
  (the `SourceScopeChangeExpiryStore` shape), the gate reads, and the `start`/`fail` CAS transitions.
- **`Platform::ErrorCatalog`** — `crawl_not_queued`, `crawl_organization_not_active`,
  `evaluation_creation_conflict`, plus the three `entitlement-interim-v1` Block reasons with the
  recovery actions WORKFLOW :541 **fixes** (`wait_for_window` / `upgrade_plan` / `contact_support`).
- **Migration `20260727120150`** — the **OD-018 database backstop**: partial unique
  `(organization_id, project_id) WHERE kind='initial' AND state IN ('pending','running')`, plus the
  canonical :340 restriction that only a reassessment/retry may hold `orchestration_slot_active`.
  The S-07-002 slot index is therefore the WF-011 reassessment single-flight, and OD-018 has its own
  backstop; keying on the in-flight states only keeps "a root `crawl.recover` after a FAILED initial
  Evaluation remains admissible" (:725) true — probed both ways.
- **Migration `20260727120160`** — the review hardening (CB2, CB5 and the missing tenant FKs).

## Verification (exact results)

- Whole repository: **1471 examples, 0 failures**. Zeitwerk clean; Packwerk no offenses (408 files);
  Brakeman 0 warnings; bundler-audit no vulnerabilities. Architecture fitness **31/0**.
- All four S-07-003 migrations **were verified by STRUCTURE LOAD, not migration replay (ADR-129)**; the schema dump is **idempotent** with no drift.
  `verify_runtime` OK — 15 checks, RLS intact.
- **24 acceptance examples** over a **production-real** chain (bootstrap → register → verify →
  ActivateSource → ActivateProject → QueueCrawl → StartCrawl), with the command built from the
  **real persisted `crawl_dispatch` row's own identity** — including entitlement exhaustion driven
  through the real F-05 `reserve` surface and Organization suspension through the real WF-013
  command. **13 persistence invariants** on the database itself.

## Independent review (ADR-026 — ADR-076)

Five lenses ran independently with live DB probes.

- **Concurrency — PASS.** 5/5 two-connection OD-018 races yielded exactly one winner (the loser's
  Crawl failed, holding no reservation); 5 concurrent starts across 5 Projects of one Organization
  gave 4 allow + 1 `hard_limit_exceeded` with `reserved_units=4` and no over-reservation; injected
  lost-CAS and mid-commit failures rolled back completely (no "reservation without Crawl" or its
  converse); exact-duplicate delivery replayed 5/5 with one Evaluation, one reservation, one event.
- **CB1 (security) — FIXED.** StartCrawl never re-authorized current **Organization** state. A
  suspended tenant — every Session revoked, authorization epoch advanced — still started its queued
  Crawl, consumed a metered `crawl.start` unit and created an immutable Evaluation, purely on
  queue-time authority, which MTX-030 `authorization_entry_point` forbids in terms and
  SEARCH_CRAWL_RETRIEVAL step 1 names first. Added as the first gate limb, before entitlement.
- **CB2 (contract) — FIXED.** `crawls.completion_reason` was written from an invented vocabulary;
  WORKFLOW :456 closes it to five values. It now records `failed`, with the exact machine reason in
  the audit record and the `CrawlFailed` envelope, and a DB CHECK prevents recurrence.
- **CB3 (contract) — FIXED.** `entitlement_inactive` was bound to `restore_policy`; :541 fixes
  "inactive entitlement -> `upgrade_plan`". Corrected in `ErrorCatalog` **and** in F-05's `Service`,
  which writes it into the immutable Decision row, so the durable record and the outward failure agree.
- **CB4 (architecture) — FIXED.** `CrawlStarted` carried the queue-time pinned entitlement policy
  version beside an execution-time crawl policy version. F-05's `Decision` now returns the version it
  resolved; the event, the orchestration context and the Decision row all name that one value.
- **CB5 (schema) — FIXED.** `evaluation_orchestration_contexts_evaluation_fk` was the only
  two-column Project-owned child-to-parent FK in the schema, admitting a same-Organization
  **cross-Project** link (POSTGRESQL_SCHEMA.md :128 requires all three values). `evaluations` gained
  the mandated three-column unique and the FK was rebuilt on it.
- **Hardening.** The missing tenant FKs (`crawls.entitlement_decision_id` /
  `entitlement_reservation_id`, `evaluations.crawl_id`, the context's `prior_evaluation_id` /
  `root_entitlement_reservation_id`); `evaluation_creation_conflict` implemented; a ghost
  `organization_id` fails closed before any ledger row is written; `entitlement_decision_id` stays
  NULL on a Crawl that never started (:338); the binding F-05 lock order, the pre-lock read's
  staleness argument and the non-replayable denials documented; the effective crawl-policy bounds
  and contributing versions recorded in the audit record (WF-005 "all policy versions **and
  effective limits**").
- **Lens-flagged, verified sound (no change):** the human `crawl.trigger` authorization is
  deliberately *not* re-checked here — :738 binds that permission to the request, which was
  authorized and audited at queue time; failing the queued Crawl for the non-entitlement gate reasons
  is correct under MTX-030 `terminal_failure` / CAP-007 (the docstring's citation was corrected from
  :734); the `crawl_queue_invariants` edits are a tightening, not a weakening (2 tests → 5, every
  prior guarantee retained).

## Recorded boundaries (deferrals, not silent omissions)

- **Root only.** The reassessment-child limb is WF-011's and is deferred (ADR-067/071). A non-root
  target quarantines rather than being guessed at.
- **No frontier.** SEARCH_CRAWL_RETRIEVAL step 6 ("creates ordered root frontier entries") and the
  post-commit dispatch of the first fetch belong to S-07-004. No network call exists on this path.
  **Gate requirement for S-07-004** (security lens N3): the pinned `crawl_sources` set is T-IMM and
  is *not* re-resolved at start, so the frontier MUST exclude Sources that have left `active`, or a
  customer-disabled Source would be crawled on queue-time authority.
- **No WF-015 entitlement events.** `EntitlementReserved` / `EntitlementExecutionStarted` /
  `EntitlementLeaseRenewed` are WF-015 events on the `entitlement_reservation` aggregate
  (API_CONTRACTS.md :907-910), owned by S-22 — not among the seventeen events MTX-030 makes
  `Workflows::Wf005` "the sole producer of". This **corrects** the ADR-075 note that anticipated the
  consumer emitting them; `HeartbeatEntitlement`/`CommitEntitlement`/`ReleaseEntitlement` are the
  `entitlement_reconcile` work type's operations (BACKGROUND_PROCESSING.md :217/:390), not the start
  commit's. Registered as follow-up **FU-4** for owner attention.
- **F-05's :541 identity precedence is incomplete** — `Service#reserve` implements
  `entitlement_inactive` and `operation_unknown` but not `organization_inactive` / `actor_inactive` /
  `service_unauthorized`. S-07-003 closes the observable hole at the consumer (CB1); the
  foundation-level completeness is registered as follow-up **FU-5**, since it spans every future
  high-cost consumer and S-22 owns that surface.
- **FU-3.** `source_set_hash` / `normalized_scope_hash` stay NULL pending the source-set sealing
  subsystem (ADR-073). No locally invented digest is substituted for the sealed identity. FU-3's
  consumer list is amended to name this third consumer.
- **`crawl_project_not_active` is currently unreachable.** OD-014 is pending and
  `f1_projects_lifecycle_guard` permits exactly `draft -> active`. The limb is kept because WF-005
  and SEARCH_CRAWL_RETRIEVAL both require StartCrawl to reauthorize current Project state, and it is
  checked before any Entitlement is consumed; the spec asserts the unreachability rather than
  pretending to exercise a path the database forbids.
- **The 60-minute deadline is stamped but not yet enforced.** `crawl_terminal_deadline`
  (BACKGROUND_PROCESSING.md :139) is created by S-07-008/S-07-009; `deadline_at` is inert until then.
- **At HEAD a completed initial Evaluation permanently blocks new root starts for its Project**,
  because `f1_evaluations_guard` still refuses every Evaluation state change. Correct for OD-018
  today; the guard relaxation belongs to S-08/WF-006.

## Next

S-07-004 (crawl frontier), then S-07-005..011, under the standing delegation. S-07 remains authorized.
