# S-07-007 — Content Fetch, Scope And Redirect Validation, Byte Accounting, Retry

Accepted 2026-07-29 under standing delegation ADR-061. Governance record: **ADR-082**.
Review discipline: **ADR-080** — no acceptance until every ADR-026 lens has reported.

## What this tranche owns

One content fetch, in the order the specification states it:

1. **Claim** the host slot (`:442`'s rolling-rate and concurrency predicates, under a row lock).
2. **Authorize at execution time** — Organization, Crawl, Project, Source, entitlement reservation,
   current Source Scope, robots. Never queue-time authority.
3. **Reserve** bytes from the run-wide budget *before* the body is read (`:442`).
4. **Claim the attempt**, with a lease, so a lost worker leaves a record rather than a hole.
5. **Fetch**, with the caller's guard rechecking robots and Source Scope on **every hop before it is
   followed** (`:448`).
6. **Measure** against `:436`'s max-of-two-paths formula and the sentinel rule.
7. **Commit and terminalise in one transaction**, releasing the unused reservation.
8. **Release** the host slot however it ended.

No transaction spans the network call. The redirect guard opens one per hop from inside it — the
price of `:448`'s per-hop recheck, since the policies live in the database — and holds nothing while
it waits, so it can only ever be a victim of contention, never a cause.

## The F-01 change

`:448` requires redirects rechecked "before following", and Volume II makes that **step 1** of the
connector's indivisible per-redirect sequence. F-01 implemented steps 2–8. `max_redirects: 0`
discards the `Location`, so no workflow-side alternative exists that does not duplicate pinning, TLS
validation, loop detection and destination safety.

`RequestPolicy#redirect_guard` is additive and defaulted: consulted after every platform check, able
only to **refuse** a hop the platform would have allowed, `nil` meaning "no caller policy". The
architecture lens verified the justification against the specification and the `max_redirects: 0`
claim against the code, and judged it a defect repair rather than scope creep.

## Byte accounting (`:442`)

- **Reserve before reading**, sized from what the run has left. The bound is in the statement's own
  predicate, so the row lock is the serialisation point — verified under eight genuinely
  simultaneous workers: three granted, sum under the ceiling.
- **`accounted = max(received, expanded)`.** All three counters are persisted so the formula is
  auditable rather than asserted.
- **The sentinel is a three-way distinction.** A body at exactly the maximum is allowed; one byte
  past it fails the URL; the probe byte is counted apart, because `:442` calls probes "detection
  telemetry, not accepted/accounted capacity".
- **Measured against the RESERVATION**, and the two bounds are distinguished on the way out: over the
  per-URL maximum is the site's response (`content_fetch_failed`, in the denominator); a smaller
  reservation exceeded because the run is nearly spent is a limit discard.

## Reclamation (`:82` — "completed **or timed out**")

Every claim sweeps the run's expired attempt leases and hands their reservations back. Without it a
lost worker retired 10 MiB — 0.8% of the run budget — permanently, and three losses retired the
frontier entry. A timed-out attempt still **counts** against `:444`'s bound: the worker may already
have issued its request, and refunding it would let a host that kills workers be retried without
bound.

## Verification

| Gate | Result |
| --- | --- |
| Complete suite | **1741 examples, 0 failures** |
| Brakeman (`-z`) | clean |
| Packwerk | no offenses, no stale violations |
| Zeitwerk | all is good |
| bundler-audit | no vulnerabilities |
| Architecture fitness | **31 examples, 0 failures** |
| `verify_runtime` | OK as `f1_web`, 15 checks, RLS intact |
| Schema from empty | dump **byte-identical** to committed `structure.sql` |
| Migration round-trip | both migrations down and up, schema reproduced exactly |

**All 24 fixes were mutation-checked** — reverted individually, each required to fail its test. Four
did not discriminate on the first pass and their tests were rewritten. The previous commit's claim
that "every property is mutation-checked" was overstated and is corrected in ADR-082.

## Carried forward

- **FU-10** — `:456`'s ordered admission is a coordinator function and belongs to **S-07-008**. This
  tranche enforces the sum and materializes `dequeue_key` on every attempt so the order can be
  applied without re-deriving it. If S-07-008 does not enforce it, byte and page admission remain
  nondeterministic at the boundary, which `:456` forbids.
- **FU-9** (from ADR-081) — scheduler re-entry after sustained host-gate contention, still owed by
  S-07-008.
- **Page admission** is deliberately absent: `:436` retains "the first 10,000 successful Documents in
  dequeue order", so it belongs with Document creation in **S-07-010**.
- **The content-decoded accounting path** has no live producer: F-01 sends `Accept-Encoding:
  identity` and exposes one byte counter. Volume II step 8 requires "separate transfer-decoded and
  content-decoded bounded counters" in the connector. Harmless today because nothing inflates a
  body; the trigger is **S-07-010** — if ingestion ever decodes, `:436` is bypassed. The columns
  exist and are ready.
- **The hardening in this tranche was not itself lens-reviewed.** S-07-008's review inherits
  `crawl_budget_counters`, `fetch_attempts` and the lease sweeper as new surface.
