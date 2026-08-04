# F-04 Background Execution — Completion and Freeze Report

Status: **COMPLETE and FROZEN** (2026-07-25). The last foundation before S-05. Implements the
ratified completion scope in `F-04_COMPLETION_MATRIX.md` (owner-amended 2026-07-25) against
`specification/foundations/FOUNDATION-004_BACKGROUND_EXECUTION.md` (ADR-024) and
`specification/volume-ii/BACKGROUND_PROCESSING.md`. Frozen semantics: `F-04_TRANSPORT_DESIGN.md`.

## What F-04 delivers

Production-reachable, durable, idempotent asynchronous execution: **PostgreSQL is the sole
timer/lease/idempotency authority; Sidekiq is transport only.** F-04 makes the pre-existing
ScheduledAction substrate (store/scheduler/worker/registry/catalogue) runnable end-to-end and
adds the reliability substrate the Jul-22 create migration explicitly deferred to this slice:
the Work Dispatch Binding, the infrastructure dispatch-retry ceiling, the two-phase
enqueue-failure handling, the ratified 8-field envelope, the committed operational config, and
the single-scheduler control.

**The guarantee proven end-to-end (real PostgreSQL + Redis + Sidekiq): transport delivery is
at-least-once; the authorised domain effect is at-most-once.**

## The FROZEN contract

- **Façade** — `Platform::BackgroundExecution.scheduler_pass` — the single named front door for
  the deployment's singleton `scheduler` process (recover expired leases, then dispatch due
  actions, as the elected leader). Scheduling and handler registration remain the ScheduledAction
  core's own established surface (`ScheduledActions::Store#create` inside a product transaction;
  `ScheduledActions::Registry` at boot), unchanged.
- **Envelope** — `ScheduledActions::Envelope`, exactly the eight ratified identifier fields
  (`schema_version, organization_id, work_type, work_id, product_generation, claim_generation,
  correlation_id, causation_id`), identifiers only, fail-closed parse. `work_id` **is** the Work
  Dispatch Binding UUID.
- **Single Sidekiq job** — `ScheduledActions::ExecutionJob` (`retry: false, dead: false`); it
  resolves the action THROUGH the binding and runs the registered handler under the envelope's
  lineage. **Single enqueue surface** — `ScheduledActions::Dispatcher`.
- **Fitness** — `spec/architecture/background_execution_single_surface_spec.rb` fails CI if any
  code outside the adapter defines a second Sidekiq job, pushes to Redis directly, disables the
  retry/dead guard, or changes the envelope's field set.

Frozen semantics of action identity, binding identity, envelope `work_id`, claim generation,
target generation, and worker target resolution are documented in `F-04_TRANSPORT_DESIGN.md`.

## Acceptance evidence (FOUNDATION-004)

| Criterion / property | Where proven |
| --- | --- |
| AC-1 Sidekiq runs against control/lifecycle via committed config; dispatch+execute end-to-end | `spec/acceptance/f04_background_execution_acceptance_spec.rb` (real Redis); `config/sidekiq.yml` + `config/sidekiq_lifecycle.yml` |
| AC-2 exactly-once under concurrency; re-delivered envelope writes nothing | acceptance spec (duplicate delivery; two workers racing one generation) |
| AC-3 lease expiry re-enqueues the SAME identity, no second count | acceptance spec (stale re-enqueue); `claiming_spec` |
| AC-4 enqueue is transaction-safe (rollback → no enqueue) | acceptance spec (rollback); `dispatcher_spec` |
| AC-5 deterministic harness, no sleeps, no fake/inline pathway | all transport specs (PostgreSQL time + injected failures); acceptance runs real Redis (`Sidekiq::Testing.disable!`) |
| AC-6 infra retry schedule + quarantine are exact | `spec/platform/scheduled_actions/dispatch_retry_spec.rb` (1/5/30/120/600 → 6th `redis_dispatch_exhausted` + high alert) |
| P3 Sidekiq auto-retry/dead disabled | `execution_job_spec`; fitness spec |
| P6 correlation+causation reach every execution (through the envelope) | acceptance spec (real Sidekiq path asserts both at the handler) |
| P9 no fake inline production pathway | acceptance spec drives real Redis + real ExecutionJob |
| P10 operational wiring (initializer, control/lifecycle configs) | `config/initializers/sidekiq.rb`, `config/sidekiq.yml`, `config/sidekiq_lifecycle.yml` |
| Crash after committed effect, replay is a no-op | `worker_spec` + `wf001_expire_invitation_lifecycle_spec` (real transition) |

## Deferred, with ENFORCEABLE triggers

Both are recorded here, in DECISIONS.md (ADR-025), and enforced by a mechanism — not prose alone.

- **G5 — queue-health gate + automatic recovery of `redis_dispatch_exhausted` records +
  `transport_recovery_generation`** (BACKGROUND_PROCESSING.md :315). Not required for at-most-once
  or retry-exactness (G1 delivers those). **Trigger:** mandatory before production is expected to
  auto-recover from a sustained Redis/Valkey outage. Until then a `redis_dispatch_exhausted`
  record stays quarantined pending reviewed reconciliation (proven by `dispatch_retry_spec`: the
  ordinary lease sweep never recovers it).
- **G6 — full renewable leader-election lease (`scheduler_leases`, 15-second term, heartbeat)**
  (BACKGROUND_PROCESSING.md :67, :112). **Trigger:** mandatory before more than one scheduler
  process may be configured or deployed. **Enforced now:** the scheduler is a LONG-LIVED singleton
  process — `rake f1:scheduled_actions:run` → `BackgroundExecution.run_scheduler` acquires
  `ScheduledActions::SchedulerLease` (a two-int session advisory lock) ONCE and HOLDS it for the
  process lifetime while it loops, so a second scheduler process cannot acquire it and exits
  without dispatching. `scheduler_lease_spec` proves exclusivity, failover, that the run holds the
  lease across the loop, and that the front door refuses a second leader. **The committed
  operational configuration must not run more than one scheduler process while G6 is deferred.**
  (The lease is deliberately held for the whole run on a dedicated PINNED connection, not per pass: a
  per-pass acquire/release would only serialise concurrent passes; and a lost lease-holding connection
  fails closed — `run_scheduler` returns `:lease_lost` rather than reconnecting and dispatching lease-less.)

No S-05 domain behaviour, and no G5/G6 machinery beyond the single-scheduler control, was built.

## Decision Ledger

| Decision | Authority | Reason |
| --- | --- | --- |
| Pull G4 (Work Dispatch Binding) into F-04 rather than defer | Owner | P1 is a mandatory property; freezing `work_id` as a locator then re-meaning it as a binding id later is not backwards-compatible (semantics, not UUID shape). |
| Envelope = the ratified 8 fields; `work_id` = binding UUID; drop the interim 6-field shape | Owner (G4) + Assumption (spec :71-83) | The envelope is being frozen; a non-conformant shape would be the movable contract the owner rejected. |
| G7: carry correlation+causation PHYSICALLY in the envelope | Owner (G7) + Autonomous | Spec :81-82 lists them as envelope fields — the literal requirement, implemented rather than a DB-reload substitute; proven at the handler on the real Sidekiq path. |
| Dispatched set at the worker CAS (happy path), not a separate scheduler post-ack step | Assumption | :119 blesses transfer before/after ack; the ratified matrix kept this. Only the enqueue-FAILURE path was added (G1/G2). |
| Generic-only bindings in F-04 (target = the action); specialised targets deferred | Owner (scope) | No S-05 Verification aggregate invented; the binding shape is frozen, its specialised population is a later backwards-compatible extension. |
| Restore the executor-active JOIN in the rewritten claim function | Autonomous (defect) | The live claim function filtered on `service_identities.status='active'`; the rewrite must preserve it (caught by `store_spec`). |
| Tighten the F-02 fitness regex from bare `Envelope` to `Encryption::Envelope` | Autonomous (Foundation Evolution defect-fix) | The bare short name false-positived on the unrelated `ScheduledActions::Envelope`; scoping keeps F-02's boundary precise without weakening it. |
| SchedulerLease (advisory lock) as the G6 stopgap control; held for the whole scheduler run | Owner (G6-control) + Autonomous (review fix) | Prevents two effective schedulers now, short of the full renewable lease; committed config cannot run >1 scheduler. A process-lifetime held lease (not per-pass) is what actually enforces this (architectural review Finding A). |
| Defer G5 and G6 with enforceable triggers | Owner | Neither is required for at-most-once/retry-exactness; each has a recorded, enforced gating condition. |
| Envelope.parse validates UUID format on the id fields | Autonomous (security-review robustness) | A shape-valid non-UUID id now fails closed cleanly rather than raising at a `::uuid` cast — makes the "malformed → clean exit" guarantee exact. |
| Dispatcher fails closed on a nil catalogue work_type (quarantine, no enqueue) | Autonomous (architectural-review Finding B) | Prevents a future nil-work_type action (evaluation_stage_advance) from churning forever as an unparseable envelope. |

## Verification

- **973 examples, 0 failures** (full suite, post-review + post-confirmation hardening). Zeitwerk clean;
  Packwerk no offenses; Brakeman 0 warnings; bundler-audit no vulnerabilities; `structure.sql` re-dumps
  with no drift; both databases was verified by structure load, not migration replay (ADR-129).
- New/changed transport specs: `dispatch_retry_spec`, `scheduler_lease_spec`, `dispatcher_spec`,
  `envelope_spec`, `execution_job_spec`, `claiming_spec`, `store_spec`, `worker_spec`,
  `f04_background_execution_acceptance_spec`, `background_execution_single_surface_spec`.

## Independent review

Two independent adversarial reviews ran against the full change surface (2026-07-25).

**Security review — verdict: no security must-fix.** Live-verified against `f1_test`/`f1_development`:
the request-serving role (`f1_web`) is provably barred from claiming, dispatching, settling and
quarantining scheduled work (all functions `SECURITY DEFINER`, fixed `search_path`, `REVOKE PUBLIC`,
granted only to `f1_platform_worker`; `f1_web` execution → permission denied); `work_dispatch_bindings`
carries no runtime grant and is reached only through the owner path; the binding is unforgeable
(`gen_random_uuid`) and immutable (UPDATE/DELETE → `work_dispatch_binding_is_immutable`); no secret,
payload or exception message/backtrace leaks into the envelope, binding, reason codes or the
redacted `DispatchAlert`. All Store SQL is parameterized.

- **Applied (robustness):** `Envelope.parse` now validates the four UUID fields against a UUID format,
  so a shape-valid but non-UUID identifier fails closed cleanly instead of raising at a `::uuid` cast.
- **Noted:** Redis transport defaults to plaintext `redis://` — production MUST set an authenticated
  `rediss://` URL (the TLS-authenticated queue-health sample is part of deferred G5). Recorded as a
  deployment requirement.

**Architectural review — verdict: sound to freeze on correctness.** No defect permits a double-applied
domain effect or a wrong retry count. The binding-mediated CAS is airtight across every hostile
interleaving (duplicate delivery, concurrent workers on one generation, stale delivery after re-claim);
the retry schedule is exactly 1/5/30/120/600 → 6th-failure quarantine with no off-by-one; enqueue is
transaction-safe; the envelope is fail-closed.

- **Applied (Finding A — truth-in-freeze, Medium):** the single-scheduler control was strengthened from
  a per-pass advisory lock (which only serialises simultaneous passes) to a **process-lifetime held
  lease** (`BackgroundExecution.run_scheduler` holds `SchedulerLease` across its whole loop; the
  committed entrypoint is the long-lived `rake f1:scheduled_actions:run`). This makes the ratified
  "committed config must not run more than one scheduler" true at the mechanism level, and is a natural
  stepping stone to G6. Proven by `scheduler_lease_spec` (front-door refusal + held-across-loop).
- **Applied (Finding B — latent, Low):** the Dispatcher now fails closed on a nil catalogue `work_type`
  (e.g. `evaluation_stage_advance`), quarantining as `scheduled_work_mapping_mismatch` rather than
  emitting an unparseable envelope that would churn forever. Proven by `dispatcher_spec`.
- **Noted, no change (Low/informational):** the binding is a plain `INSERT` (safe today — each claim
  mints a fresh generation; a specialised-target slice that re-mints inside a retried transaction adds
  `ON CONFLICT` for exact-replay). The "same-owner resume" CAS branch is exercised only on the in-process
  path; across Sidekiq deliveries a redelivery gets a fresh owner and correctly no-ops (still
  at-most-once) — the frozen contract does not lean on same-owner resume as an operative guarantee.
- **Out of F-04 scope:** the suspended-executor claim gate strands such actions without a quarantine/alert
  — this predates F-04 (`20260722120010`) and is operationally guarded by `f1:db:ensure_service_identities`.

Post-review, the full suite is **970 examples, 0 failures**, all gates green.

### Post-freeze owner confirmation and hardening (2026-07-25)

A read-only owner confirmation of nine freeze details found the single-scheduler control did not
fully deliver two of them: a mid-run loss of the lease-holding transport connection was **silently
reconnected**, so dispatch could continue on a connection that held no lease (neither stopping/failing
closed nor re-acquiring). Correctness (at-most-once) was unaffected, but the enforcement guarantee
was not met. The owner authorised the bounded fixes; **F-04 was not otherwise re-opened**:

- **Connection-lifecycle fail-closed (points 2/3).** `TransportConnection.pinned` runs the scheduler on
  a dedicated connection that is never silently reconnected — a lost connection raises `ConnectionLost`;
  `run_scheduler` fails closed (`:lease_lost`) and the next start must re-acquire the lease before any
  dispatch. Proven by `scheduler_lease_spec` (pinned-raises + run-fails-closed).
- **Real-Redis crash-before-ack proof (point 6).** The acceptance spec now proves that a committed
  effect whose ack is lost, then redelivered by Sidekiq, applies the domain effect exactly once.
- **Production TLS enforcement (point 7).** `config/initializers/sidekiq.rb` now refuses to start in
  production unless `REDIS_URL` is `rediss://` (authenticated TLS); plaintext stays dev/test only.
- **Directory rename (point 8).** `specification/automatation/` → `specification/automation/`.

Confirmed as already satisfied: dedicated pinned lease session (now fully, after the fix); specialised
binding targets addable without changing `work_id`/envelope meaning; atomic increment/schedule/quarantine
under concurrent failure (`FOR UPDATE`); the three F-04 commits are cleanly attributable/reviewable
despite the historically broad branch name. Post-fix suite: **973 examples, 0 failures**, all gates green.
