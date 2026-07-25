# F-04 Background Execution — Completion Matrix

Status: **RATIFIED WITH AMENDMENTS (owner, 2026-07-25) — implementation authorised.** Classifies
every remaining F-04 gap against the ratified contract so scope is unambiguous before code resumes.

## Ratified decision (owner, 2026-07-25)

Approved **with amendments** to the recommendation below:

- **G4 is pulled INTO the F-04 freeze** (not deferred). Rationale: FOUNDATION-004 marks **P1 mandatory**;
  absence from the enumerated acceptance criteria does not make a mandatory property optional (ACs are
  proof conditions, they do not narrow properties). Freezing `Envelope#work_id` with a
  scheduled-action-locator meaning and later changing it to a binding identifier is **not**
  backwards-compatible — a UUID staying a UUID does not make the *semantic* change safe once consumers,
  logs, replay, debugging and idempotency assumptions depend on it. Close the identity model now.
- **G7 must be explicitly locked**, not silently frozen as "immaterial wording." Choose the smallest
  repository-consistent resolution — (1) put correlation+causation physically in the scalar envelope,
  or (2) formally ratify that the envelope is a scalar dispatch *locator* and PostgreSQL reload is the
  authoritative transport of correlation/causation into the execution context — record it in an ADR
  and the freeze report, and prove it with a real-Sidekiq-path acceptance test. If the specification
  unambiguously requires the fields physically in the envelope, implement that literally.
- **G3's real-Redis/Sidekiq proof must cover the full failure-boundary matrix** (see the expanded G3
  bar recorded below), establishing the actual guarantee: **transport delivery is at-least-once; the
  authorised domain effect is at-most-once.** Deterministic clocks + injected failure points, not sleeps.
- **G5 and G6 remain deferred, but their triggers must be ENFORCEABLE**, not merely mentioned: recorded
  in the Decision Ledger, the freeze report, AND an architecture-fitness / release-readiness mechanism.
  The committed operational configuration **must not permit multiple scheduler processes** while G6 is
  deferred (single-scheduler assumption enforced at the config/mechanism level).
- **Boundaries:** do not implement S-05 domain behaviour; do not build G5/G6 beyond the controls that
  prevent their unapproved operational use; **stop after F-04 is completely verified and frozen and
  report back before any autonomous-controller design or implementation begins.**

**Ratified freeze boundary:** F-04 = G1 + G2 + G3 + **G4** + G7-decision + G8. Deferred = G5 (until
automatic outage recovery is required) + G6 (until multiple schedulers are permitted).

### Expanded G3 proof bar (ratified)

The real PostgreSQL + Redis + Sidekiq acceptance proof must cover at least: duplicate delivery of the
same envelope; concurrent workers racing for the same action generation; stale-lease expiry and
re-enqueue; enqueue failure before successful Redis acceptance; exact dispatch retry intervals
1/5/30/120/600 s; sixth failed dispatch → terminal `redis_dispatch_exhausted` quarantine; crash or
interruption after the authorised domain effect but before execution acknowledgement; replay/redelivery
after that ambiguous completion boundary; transaction rollback → no enqueue; unknown work type or target
→ no arbitrary dispatch; and the absence of any fake/inline production execution pathway.

### G4 substrate scope (ratified, smallest complete)

Durable `work_dispatch_bindings`; binding UUID as the envelope `work_id`; binding between the scheduled
action and the authorised execution target; target type + target identity constrained without arbitrary
constantisation or method dispatch; target-generation (or equivalent claim info) where the ratified spec
requires it; ownership+generation checks that preserve the existing PostgreSQL-authoritative claim model;
generic bindings may bind source and target to the scheduled action where no specialised target exists;
closed-registry dispatch stays mandatory; **no S-05 Verification Request aggregate or verification-specific
domain handler may be invented in F-04.** Document the exact frozen semantics of: action identity;
binding identity; envelope `work_id`; claim generation; target generation; and how a worker resolves the
authorised target.

The original recommendation (defer G4) and its reasoning are retained below for the record, superseded by
the ratified decision above.

- Author context: pre-implementation review, 2026-07-25
- Authoritative sources cited verbatim:
  - `specification/foundations/FOUNDATION-004_BACKGROUND_EXECUTION.md` — the ratified contract
    (ADR-024). **Mandatory properties P1–P10** (lines 16–25) and **Acceptance criteria AC-1–AC-6**
    (lines 41–46; numbering AC-1..6 assigned here in reading order for reference).
  - `specification/volume-ii/BACKGROUND_PROCESSING.md` — the substrate specification
    (line refs `:NN`).
  - `db/migrate/20260722120007_create_scheduled_actions.rb:29–34` — the explicit deferral note
    that punted the reliability substrate to "the Redis/Sidekiq transport" slice (i.e. F-04).
- The two frozen contracts F-04 must not violate: **F-01** `Platform::Outbound` and **F-02**
  `Platform::Encryption` façades. **The Envelope is not yet frozen** (F-04 is the freeze in
  question), so changing its *source of values* is not a frozen-contract break.

## What is already built and green (the happy path)

`Dispatcher` (poll → `perform_async` one scalar `Envelope` per due action to its fixed queue),
`Envelope` (six-field identifiers-only Sidekiq arg, fail-closed `parse`), `ExecutionJob`
(`retry: false, dead: false`; malformed/gone-row no-ops; `Worker#execute` via claim CAS),
`config/sidekiq.yml` + `config/initializers/sidekiq.rb`. Specs: `spec/platform/scheduled_actions/`
= 67 examples, 0 failures — **but the new transport path is proven only in `Sidekiq::Testing.fake!`
(enqueue asserted) and unit guards; it is not proven end-to-end through real Redis.**

## Completion matrix

| # | Item | Class | Source | Foundation vs downstream | Smallest implementation | Proving test | If deferred: consequence + frozen-contract check |
|---|------|-------|--------|--------------------------|-------------------------|--------------|--------------------------------------------------|
| G1 | Infra dispatch-retry ceiling: `dispatch_attempt_count`, schedule **1,5,30,120,600 s**, attempt-6 quarantine `redis_dispatch_exhausted` + high alert | **Required now** | FOUNDATION-004 **AC-6** ("Infrastructure retry schedule and quarantine are exact") + **P3**; BACKGROUND_PROCESSING.md **:313** | Foundation (shared transport reliability) | Add `dispatch_attempt_count` + `next_dispatch_at` columns (migration); on enqueue failure increment count and reschedule per the schedule; at attempt 6 quarantine via the existing settle path (quarantine-from-`claimed` is already permitted, see restrict migration line 169) with reason `redis_dispatch_exhausted`; emit high alert | New transport-fn spec: failures at 1/5/30/120/600 → 6th quarantines `redis_dispatch_exhausted`; earlier attempts stay retryable; deterministic (no sleeps, injected attempt clock) | Would leave AC-6 unmet — **cannot defer**; AC-6 is an explicit F-04 acceptance criterion |
| G2 | Two-phase / enqueue-failure handling: detect a failed enqueue and return the still-scheduler-owned row for the G1 schedule (`dispatched` stays set at the worker CAS on the happy path) | **Required now** | BACKGROUND_PROCESSING.md **:117**; FOUNDATION-004 **P7** + **AC-4**; substrate G1 needs | Foundation | Wrap `Dispatcher#enqueue` so a raised `perform_async` triggers the G1 counter/reschedule (owner+generation guard, `dispatched_at IS NULL`); happy path unchanged | Dispatcher spec: simulated enqueue raise leaves the row claimable/rescheduled, not lost, and enqueues nothing on rollback (AC-4 already covered) | Without it G1 has nothing to re-attempt → AC-6 unmet. **Cannot defer** (coupled to G1) |
| G3 | End-to-end proof through **real Redis**: due action → `Dispatcher` → Redis → `ExecutionJob` → `Worker` → handler, no inline shortcut; plus duplicate-delivery-writes-nothing and lease-expiry-re-enqueue at the transport level | **Required now** | FOUNDATION-004 **AC-1**, **AC-2**, **AC-3**, **AC-5**; **P9**. `dispatcher_spec` itself defers this to "the acceptance spec" (which does not exist) | Foundation (proof) | One acceptance spec running `Sidekiq::Testing.disable!` (or a real inline drain) end-to-end; assert exactly-once under a duplicate delivery, and lease-expiry re-enqueue consumes no second count | The spec is itself the proof | Leaves AC-1/AC-5/P9 unmet ("no fake inline production pathway"). **Cannot defer** |
| G8 | Committed operational config for the **`lifecycle`** queue (today only `control` + a `maintenance` capsule are committed; `lifecycle` lives in a comment) | **Required now (small)** | FOUNDATION-004 **AC-1** ("control/lifecycle queues via committed operational config") + **P10** | Foundation (ops) | Commit the lifecycle worker config (capsule or a second committed config file) at its ratified concurrency (2) | Assert the committed config declares `control` and `lifecycle` | Leaves AC-1's "committed operational config" literally unmet for `lifecycle`. **Cannot defer** |
| G7 | Correlation/causation reaching every execution | **Not required as new work — already satisfied** | FOUNDATION-004 **P6** | Foundation | None needed: the dispatch CAS reloads the full row, so `Worker#invoke` builds the service `RequestContext` from `action.correlation_id`/`causation_id` (DB), not the envelope. Optionally add a test locking this on the Sidekiq path | Optional: handler on the real-Redis path observes the scheduled action's correlation_id | P6 says "through the envelope"; we satisfy it "via DB reload." Deviation is wording, not behaviour — **no contract/AC violation**. Owner may ratify DB-reload as canonical, or ask for the two fields on the Envelope (backwards-compatible add) |
| G4 | **Work Dispatch Binding** table (`work_dispatch_bindings`); make `work_id` the binding UUID; specialized-type independent target-generation claim | **Required later (defer)** | BACKGROUND_PROCESSING.md **:78, :115, :243**; FOUNDATION-004 **P1**. **Absent from the AC-1–AC-6 list** | Foundation substrate whose *value* is downstream (specialized targets) | Deferred | Deferred | For a generic kind the binding "binds the action as both source and target" (:243) — degenerate; the action identity + `claim_generation` already are the binding, and AC-1–AC-6 never require the table. Its real value is the **independent target-generation claim for specialized work-types**, whose need is an **S-05 design question that does not yet exist** — building it now is speculative (YAGNI per delegation-authority). Deferral violates no frozen contract (F-01/F-02 unaffected) and no AC. `work_id` stays a locator; later pointing it at a binding UUID is a **backwards-compatible** change to the not-yet-frozen Envelope. **Trigger to un-defer:** the first specialized work-type that needs an independent target-generation claim (in S-05's design) |
| G5 | Queue-health 3-sample PING gate + `invariant_sweep` recovery of `redis_dispatch_exhausted` records + `transport_recovery_generation` | **Required later (defer)** | BACKGROUND_PROCESSING.md **:315**. **Absent from the AC list** | Operational recovery | Deferred | Deferred | This is *recovery from* quarantine, not the exactly-once/idempotency or the retry-exactness that AC-6 requires (G1 delivers those). It depends on the `invariant_sweep` maintenance path and the elected scheduler. Deferral leaves a `redis_dispatch_exhausted` row quarantined-but-recoverable-later; violates no AC and no frozen contract. **Trigger:** before production must auto-recover from a sustained Redis outage |
| G6 | Singleton scheduler lease / leader election (`scheduler_leases`) | **Required later (defer)** | BACKGROUND_PROCESSING.md **:67**. **Absent from the AC list** | Operational (efficiency) | Deferred | Deferred | Correctness does **not** depend on it: `claim_due` is `FOR UPDATE SKIP LOCKED`, so concurrent schedulers take disjoint batches (never double-claim a generation), and any duplicate *enqueue* is a no-op the worker CAS drops — **exactly what AC-2 already proves**. The lease only *reduces redundant enqueues*. Deferral yields at most redundant no-op deliveries; violates no AC and no frozen contract. **Trigger:** before running more than one scheduler process in production |

## Scope conclusion

**Required now (the F-04 freeze bar):** G1, G2, G3 (incl. AC-2/AC-3 transport-level coverage), G8.
G7 is already satisfied (optionally locked with one test). Every "Required now" item maps to an
explicit FOUNDATION-004 **acceptance criterion** (AC-1..AC-6), not merely to the broader vision.

**Deferred with justification:** G4 (Work Dispatch Binding), G5 (queue-health recovery),
G6 (scheduler leader election). **None appears in the FOUNDATION-004 AC-1–AC-6 list**; each is
either degenerate for the kinds F-04/S-05 first exercise (G4), or operational resilience beyond
exactly-once/retry-exactness (G5, G6). **No deferral changes a frozen contract (F-01 `Platform::Outbound`,
F-02 `Platform::Encryption`), and none weakens an F-04 acceptance criterion**; each carries an explicit
un-defer trigger. `work_id` remaining a locator keeps a later binding a backwards-compatible change.

**The one call worth an explicit owner nod:** G4. FOUNDATION-004 **P1** names the binding, though the
**AC list does not require it**. Recommended: defer per the trigger above. If you'd rather it be in the
F-04 freeze, it moves to "Required now."

## Proposed build order (only if this classification is approved)

1. Migration: `dispatch_attempt_count` + `next_dispatch_at` (+ any needed transport-fn changes) — G1/G2 substrate.
2. `Dispatcher` enqueue-failure handling + the 1,5,30,120,600 schedule + attempt-6 `redis_dispatch_exhausted` quarantine + alert — G1/G2, with a deterministic transport-fn spec.
3. Committed `lifecycle` operational config — G8.
4. End-to-end real-Redis acceptance spec (exactly-once under duplicate delivery; lease-expiry re-enqueue; no inline shortcut) — G3, incl. AC-2/AC-3.
5. (Optional) correlation-on-the-Sidekiq-path test — G7 lock.
6. Freeze: `Platform::BackgroundExecution` façade + `spec/architecture/background_execution_single_surface_spec.rb` (single Sidekiq job, single enqueue surface, retry/dead disabled, scalar envelope) + record the deferrals (G4/G5/G6) with triggers.

**No code will be written until this classification is approved.**
