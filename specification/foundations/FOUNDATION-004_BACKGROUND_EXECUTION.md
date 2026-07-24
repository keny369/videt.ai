# FOUNDATION-004 — Background Execution Foundation

Status: **Ratified contract (ADR-024).** Supporting architecture contract, not a canonical ADR (decision of record: `DECISIONS.md` ADR-024). Implemented by the **F-04** tranche step, after F-03, before S-05.

- Ratified: 2026-07-24 (ADR-024)
- Owner context: Platform kernel (Background Processing baseline)
- First consumer: **S-05** — the automated observation slots (`verification_observation_slot`), the 24-hour expiry (`verification_request_expire`) and the 60-second challenge destruction (`verification_material_destroy`).
- Substrate that already exists and is consumed as-is: the `scheduled_actions` durable-timer table, the ScheduledAction catalogue/registry/scheduler/worker/store, and Sidekiq as declared transport. The catalogue already reserves all S-05 action-kinds. **F-04 makes this substrate production-reachable** (operational wiring + the executors/handlers), it does not redesign it.

## Purpose

Production-reachable, durable, idempotent asynchronous command execution, so scheduled and deferred work (observation slots, expiries, timed deletions, and later crawl/parse/AI work) runs exactly as ratified — PostgreSQL as timer/lease/idempotency authority, Sidekiq as transport only — with no fake inline production pathway.

## Mandatory properties

1. **Durable job dispatch.** `scheduled_actions` is the sole physical timer authority; the scheduler claims due actions (`ORDER BY due_at, id FOR UPDATE SKIP LOCKED`), creates a Work Dispatch Binding, enqueues a scalar envelope, and marks dispatched. No direct Redis push; the action registry is **closed**.
2. **Idempotent workers.** A worker establishes Organization context, transfers the claim by compare-and-swap on `claim_generation`, and a worker that cannot claim **exits successfully with no product write**. Re-delivery never double-applies.
3. **Retry policy** — product retries are Volume I's only; infrastructure dispatch retries at the ratified `1, 5, 30, 120, 600` s then quarantines (`redis_dispatch_exhausted`). Sidekiq auto-retry/dead disabled (`retry: false`, `dead: false`).
4. **Terminal failure** — quarantine rather than silent loss; no unbounded retry.
5. **Execution leases** — `claim_owner`, positive `claim_generation`, `claimed_at`/`lease_expires_at`, heartbeat; an expiry sweeper releases pre-external-checkpoint work and re-enqueues the **same product-attempt identity**, incrementing only `claim_generation`.
6. **Correlation and causation** propagate through the envelope into every execution.
7. **Transaction-safe enqueueing** — the enqueue is committed with the scheduling transaction (outbox/transactional-enqueue), never a fire-and-forget after commit; the external call happens **only after the durable checkpoint**, never inside an open DB transaction.
8. **Auditability** — every claim/dispatch/execution/terminal outcome is recorded.
9. **Deterministic test harness** — the existing ScheduledAction race/lease harness pattern; time and claim ordering are controllable; **no fake inline production pathway** (jobs run through the real dispatch/claim path in tests, not a synchronous shortcut).
10. **Operational wiring** — Sidekiq initializer, `sidekiq.yml` (the `control` and `lifecycle` queues at their ratified concurrencies), and the queue Redis/valkey connection, so the worker actually runs.

## Abstraction

F-04 owns the **runtime + executors** for the reserved action-kinds/work-types, mapping each to its ratified application operation:

```
verification_observation_slot → verification_observe  → reserve+complete a Verification Attempt (F-01 outbound)
verification_request_expire   → scheduled_action_dispatch → ExpireVerificationRequest
verification_material_destroy → object_destroy         → cryptographic deletion (F-02 erasure)
```

Consumers (S-05, later S-06/S-07/S-08) register their handler/command classes; the dispatch, claim, lease and retry mechanics are the shared foundation.

## Acceptance criteria (for the F-04 implementation)

- Sidekiq runs against the `control`/`lifecycle` queues via committed operational config; a scheduled action dispatches and executes end-to-end.
- A due action executes exactly once under concurrency (claim CAS); a re-delivered envelope writes nothing.
- A lease expiry re-enqueues the same product-attempt identity and consumes no second count.
- Enqueue is transaction-safe: a rolled-back scheduling transaction enqueues nothing.
- The deterministic harness proves ordering/lease behaviour with no timing sleeps and no inline shortcut.
- Infrastructure retry schedule and quarantine are exact; product retries are Volume I's only.

## Non-goals / boundaries

- **Not** a redesign of the ScheduledAction substrate (already ratified/built) — F-04 wires it to run and adds the verification executors.
- **Not** the verification predicate, the encryption erasure primitive, or the outbound safety — those are S-05, F-02, F-01 respectively; F-04 orchestrates them under a durable claim.
- **Not** an `event_consume` route for verification; the registry stays closed.

## Genesis + Videt

Genesis contracts unchanged. This is the "durable background execution" foundation; every future Videt observation/reassessment/notification loop runs on it. Getting the claim/lease/idempotency exactly right here pays off across the entire evaluation pipeline (S-07..S-18) and the future intervention-learning lifecycle.
