# F-04 Background Execution — Frozen Transport Semantics

Status: **Implementation blueprint for the ratified F-04 completion** (see `F-04_COMPLETION_MATRIX.md`).
Documents the exact semantics the freeze locks, as required by the owner directive (2026-07-25).
Grounded in `specification/volume-ii/BACKGROUND_PROCESSING.md` (line refs `:NN`) and
FOUNDATION-004. This note is consolidated into the F-04 freeze report at freeze time.

## The identities (frozen meanings)

| Identity | What it is | Lifetime / mutability | Authority |
| --- | --- | --- | --- |
| **Action identity** | SHA-256 over the canonical preimage `(action_kind, action_schema_version, organization_id, project_id, target_type, target_id, product_generation, schedule_generation, due_at)` (:100, :106). Unchanged by F-04. | One row per identity; exact creation replay returns it; immutable at the DB (guard trigger). | The product idempotency key — re-delivery never doubles a product effect. |
| **Binding identity** | `work_dispatch_bindings.id`, a fresh UUID minted **in the claim transaction** for one `(source_action_id, source_claim_generation)` (:115, :243). | Exactly one per claim generation (`UNIQUE(source_action_id, source_claim_generation)`, exact-replay returns it); **insert-only, immutable** (trigger refuses UPDATE/DELETE from every role). | The **dispatch authority**: the worker resolves the authorised target *through* the binding, never from an envelope string. |
| **Envelope `work_id`** | Equals the binding UUID (:78, :116). A transport **locator**, never a product/attempt/event identity. | Per enqueue. | Names the binding the receiver must resolve. |
| **`claim_generation`** | Monotonic per action; incremented on each claim (:80, :301). The envelope carries the exact value. | Never regresses (guard trigger); a stale value cannot claim or dispatch. | The claim CAS discriminant. |
| **`target_generation`** | The direct target's independent claim generation (:243). For a generic `scheduled_action_dispatch` the target **is** the ScheduledAction, so `target_generation = source_claim_generation`. For a specialised target (Verification Attempt, `work_executions`, …) it is that row's own claim generation. | Per claim. | Independent target claim for specialised jobs. |

**F-04 scope on `target_generation`:** the column and the generic case (`target = the action`) are built and
frozen now. The specialised-target population (an independent target row + its own generation increment)
is **deferred to the slice that introduces the target table** — no S-05 Verification Request aggregate
or verification handler is invented here (owner constraint). The binding *shape* is frozen so `work_id`'s
meaning never changes later.

## The ratified Sidekiq envelope (frozen)

Exactly eight fields (:71–83) — replacing the interim 6-field skeleton, which carried `action_id`/`claim_owner`
and is not conformant:

`schema_version` (`"1.0"`), `organization_id`, `work_type`, `work_id` (=binding UUID), `product_generation`,
`claim_generation`, `correlation_id`, `causation_id`.

Identifiers only; the handler reloads everything else from PostgreSQL (:84). Any unknown/missing/mistyped
field ⇒ record transport-contract telemetry and **exit without claiming work** (fail-closed).

**G7 resolution (frozen):** `correlation_id` and `causation_id` are carried **physically in the envelope**
per :81–82 — the specification is unambiguous, so the literal requirement is implemented rather than a
DB-reload substitute. An acceptance test proves both reach the executing handler through the real Sidekiq
path. (ADR recorded at freeze.)

## How a worker resolves the authorised target (frozen)

1. `ExecutionJob#perform(args)` parses the envelope; malformed ⇒ no-op, no raise.
2. It calls `f1_dispatch_scheduled_action(p_work_id, p_expected_generation := claim_generation, p_worker_owner, p_lease_seconds)`.
3. The SECURITY DEFINER function **resolves the binding by `work_id`** (a keyed lookup — no constantisation,
   no method dispatch), requires `binding.source_claim_generation = p_expected_generation`, then CAS-transfers
   the **source action** to the worker: `status ∈ (claimed, dispatched)` at that generation and
   (`claim_phase = 'scheduler'` ⇒ first transfer, or `claim_phase = 'worker' AND claim_owner = p_worker_owner`
   ⇒ idempotent resume). Any other owner/generation/terminal/reclaimed state ⇒ **no row ⇒ no product work**.
   Returns the full action row (the handler runs against it).
4. Successful transfer resets `dispatch_attempt_count = 0`.

No worker scans a domain/attempt table (:243); the binding is the only resolution path.

## Two-phase enqueue + infrastructure dispatch retry (G1/G2, frozen)

- **Claim** (`f1_claim_due_scheduled_actions`): sets `claimed`, `claim_generation += 1`, a **derived
  lease** (see below), **creates/exact-replays the binding**, returns the action fields **plus**
  `work_id`, `work_type`, `product_generation`, `correlation_id`, `causation_id`. The scan admits a row
  only when `due_at ≤ now`, `not_before_at` clear, **and `next_dispatch_at` clear** (the backoff gate).

> **AMENDED 2026-07-30 BY DECISIONS ADR-094 AND ADR-095.** This line read "30-second lease", which was
> true when F-04 was frozen and is no longer true of any of the three functions that assign one. Lease
> duration is now BACKGROUND_PROCESSING.md :288's rule, evaluated inside the transport function from
> `transaction_timestamp()` and the row's immutable `product_attempt_deadline`:
> `least(greatest(caller_request, 60 seconds, deadline - claim_time + 30 seconds), 15 minutes)`.
> The `p_lease_seconds` argument is a FLOOR the caller requests, never a ceiling it can raise. The same
> expression is carried byte-for-byte by `f1_claim_due_scheduled_actions`,
> `f1_dispatch_scheduled_action` and `f1_heartbeat_scheduled_action`, and
> `spec/architecture/scheduled_action_lease_rule_spec.rb` fails if the three ever diverge or if any of
> them drifts from :288's own numbers. This is an extension of a frozen foundation under the defect limb
> of the Foundation Freeze rule, not a redesign: no signature, grant, RLS policy or return shape changed.

- **Enqueue** (`Dispatcher`): builds the 8-field envelope (`work_id` = binding), `perform_async` to the
  action's fixed queue. `dispatched`/`dispatched_at` are set at the **worker CAS** on the happy path
  (:119 blesses transfer before or after ack — no separate scheduler ack step).
- **Enqueue failure** (`perform_async` raises) ⇒ `f1_fail_scheduled_action_dispatch(action_id, owner, generation)`,
  guarded by owner+generation and `dispatched_at IS NULL`:
  - `dispatch_attempt_count += 1`;
  - if it reaches **6** ⇒ `status = quarantined`, `reason = redis_dispatch_exhausted`, and the Dispatcher
    raises a **high alert** (:313). No human/console/Rake/Sidekiq-Web/product replay exists for transport quarantine.
  - else ⇒ return the row to `pending` (release the claim) and set
    `next_dispatch_at = now + [1,5,30,120,600][count-1] s` (:313). The identity is unchanged; the next claim
    increments only `claim_generation`; `dispatch_attempt_count` persists across claims until a successful
    transfer resets it (or, later, G5 recovery).
- **Transaction-safe:** a rolled-back scheduling transaction wrote no action row, so nothing is enqueued
  (:117, AC-4). No producer pushes to Redis directly (:243).

## The guarantee this proves

**Transport delivery is at-least-once; the authorised domain effect is at-most-once.** Duplicate delivery,
stale-lease re-enqueue, concurrent workers racing one generation, and replay across the
crash-after-effect-before-ack boundary all fail the binding-mediated claim CAS and perform no second product
write. The real PostgreSQL+Redis+Sidekiq acceptance proof (G3) exercises exactly these boundaries with
deterministic clocks and injected failures (no sleeps).

## Deferred, with enforceable triggers (G5, G6)

- **G5** queue-health gate + `invariant_sweep` recovery of `redis_dispatch_exhausted` + `transport_recovery_generation`
  (:315) — recovery *from* quarantine; not required for at-most-once or retry-exactness. Trigger: before
  production must auto-recover from a sustained Redis outage.
- **G6** full renewable leader-election lease with heartbeat/failover (:112) — correctness holds via
  `FOR UPDATE SKIP LOCKED` + the binding-mediated worker CAS (duplicate enqueue is a no-op, AC-2). Enforced
  now by a long-lived singleton scheduler: `BackgroundExecution.run_scheduler` holds `SchedulerLease` for the
  process lifetime on a dedicated PINNED transport connection, so a second scheduler cannot acquire it and does
  not dispatch; and a lost lease-holding connection FAILS CLOSED (`:lease_lost`, no silent reconnect), with the
  next start required to re-acquire the lease before any dispatch. Trigger: before more than one scheduler
  process is configured/deployed. **The committed operational config must forbid multiple scheduler processes
  while G6 is deferred.**

Notes carried from the independent architecture review (informational, not gaps): the binding is a plain
`INSERT` — safe because each claim mints a fresh `claim_generation` (a specialised-target slice that re-mints
inside a retried transaction adds `ON CONFLICT` for exact-replay). The `claim_phase='worker' AND
claim_owner=p_worker_owner` "same-owner resume" branch is exercised only on the in-process path; across Sidekiq
deliveries a redelivery gets a fresh worker owner and correctly no-ops (still at-most-once) — the contract does
not rely on same-owner resume.

Triggers are recorded in the Decision Ledger, the freeze report, and an architecture-fitness/release-readiness
check (not prose alone).
