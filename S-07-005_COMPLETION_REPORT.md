# S-07-005 Host Gate, Robots (Fail-Closed), Per-Host Rate, Execution-Time Authorization — Completion Report

Status: **ACCEPTED** on the COMPLETE five-lens outcome (standing delegation ADR-061; DECISIONS
ADR-079, **corrected by ADR-080**)

> **Correction.** Acceptance was first recorded (ADR-079) on FOUR of the five lenses, while the
> concurrency lens was still running. That was a mandatory-gate failure. That lens then returned two
> confirmed-blocking defects live at HEAD — an unguarded `release_slot` that let one worker drop
> another's slot and silently widen the nonexceedable concurrency ceiling, and no reclamation of a
> slot lost with its worker, which closed the host for the rest of the run. Both are fixed
> (a claim is now an identified, self-expiring lease), every gate was re-run green, and the tranche
> is re-accepted. A tranche is not accepted until every lens has reported.

The integration branch `implementation/s01-registration-access` is pushed; protected branch `main` is
untouched. The FIFTH tranche of the S-07 slice.

The ADR-026 five-lens review was run by **five independent reviewers**, restoring the per-lens
independence ADR-078 recorded as reduced. Confirmed-blocking findings were returned and **all fixed
before acceptance**; two further defects were found by **self-review before the lenses reported**.

## What was built

- **`crawl_host_gates`** (T-MUT, migration `20260727120190`) — one row per `(crawl, canonical host)`,
  carrying both host concerns because both are decided under the same row lock: the **robots record**
  (attempts, normalized rules and schema, agent group, crawl delay, ordered sitemap candidates,
  source digest, terminal reason/time) and the **rate/concurrency gate** (next allowed start, rolling
  start instants, active connection count, lease version). The robots **terminal decision is
  write-once at the database**, so a host that failed closed can never become fetchable within the run.
- **`RobotsPolicy`** — the pure `:448` algorithm: the exact `F1DiscoverabilityBot` token matched
  ASCII-case-insensitively with `*` only as fallback, **longest matching rule wins**, **allow wins an
  equal-length tie**, malformed lines ignored, invalid bytes replaced, crawl-delay only ever more
  restrictive, plus RFC 9309 `*`/`$` matching. Covered by a **golden corpus**, as
  SEARCH_CRAWL_RETRIEVAL requires. The contract lens differentially fuzzed the selection logic
  against a reference implementation over 200,000 rule sets with **0 mismatches**.
- **`HostGate`** — claims a slot only when the rolling-start and concurrency predicates pass,
  evaluated **in PostgreSQL against `clock_timestamp()` under `FOR UPDATE`** ("a worker cannot start
  merely because Redis granted a token"). Limits are the run's **effective** bounds — the most
  restrictive of the global ceiling and every active Organization/Project policy (`:390`) — with the
  nonexceedable ceilings asserted **before** the scheduling targets.
- **`EnsureRobots`** — the `:448` decision table, fail-closed, in **three phases** so no external
  call sits inside a transaction: claim the attempt and commit; fetch holding no transaction and no
  lock; record the outcome under the row lock. `:444`'s 30s/120s schedule and the `Retry-After`
  1–120s override are honoured; exhaustion **is** the fail-closed outcome.
- **`FetchAuthorization`** — execution-time authorization immediately before every URL, first-match
  from the widest authority: Organization active → Crawl running → Project active → **Source active**
  → entitlement reservation still executing **and within its deadline** → current scope policy admits
  the URL → robots permits it. Every unknown denies.

## Independent review (ADR-026 — ADR-079, corrected by ADR-080)

Found by **self-review** first: the robots fetch sat inside the caller's transaction holding the gate
row lock (MTX-030: "No external call sits inside a database transaction" — a slow host would have
stalled every other worker on it); and `:444`'s retry delays and `Retry-After` override were
unimplemented, with only the attempt count honoured.

Confirmed-blocking from the lenses, all fixed. **Three were fail-open at the last gate before bytes
leave the platform**, and **two more came from the concurrency lens after acceptance had been
prematurely recorded** (see the correction above): an unguarded `release_slot` that let one worker
drop another's slot and silently widen the nonexceedable concurrency ceiling, and no reclamation of a
slot lost with its worker, which closed the host for the rest of the run. A claim is now an
identified, self-expiring lease: the counter is derived from the lease set with a CHECK making
disagreement impossible, release removes a token (idempotent, and only ever its own claim), and every
claim sweeps stale leases so reclamation cannot itself be lost.

- **Robots bypass via the raw URL** — `path_of` used the caller's string while scope used the
  predicate's canonical form, so `/%70rivate/secret` and `/a/../private/secret` walked past
  `Disallow: /private`. No caller mistake required.
- **`pg_array` mangled array literals** — splitting on every comma turned `{"/a,b"}` into two
  elements, admitting a URL the current scope policy denies and diverging from S-07-004's correct
  parse of the same columns. Extracted once as `Platform::PgArray`; all three call sites delegate.
- **Robots wildcards were literal** — `Disallow: *` crawled everything. `:448` is silent, so this was
  a real ambiguity resolved permissively, inverting the owner's standing "fail closed when uncertain".

Also fixed: `kind: "robots"` exempted *any* URL from robots (and the spec asserted the bypass); the
gate was never bound to the URL's host, Crawl or Organization; **same-Organization cross-Project
authorization** in the read path; a **3xx on `robots.txt` permanently denied an entirely crawlable
host** (`:452` makes that a failed Source root and partial coverage); the gate enforced the **global
ceiling rather than the run's effective limits** (`:390`); and `robots_rules_schema` was not
write-once, with the rules CHECK one-directional so `rules_applied` with NULL rules read as "nothing
disallowed".

Further hardening: the entitlement limb checks the reservation's effective **deadline**, not merely
its state (F-05 has no `executing -> expired` edge, so a dead worker's reservation would keep
authorizing an unmetered run) — compared against the caller's `now`, agreeing with F-05, while the
rate window keeps `clock_timestamp()` because it measures real elapsed time; a robots attempt lost
with its worker is **reclaimed** rather than wedging the host; a corrupt rule set **denies**; and
"robots not yet resolved" is split from "robots failed closed", since only the latter is terminal and
carries `:452`'s coverage penalty.

## Verification (exact results)

- Whole repository: **1603 examples, 0 failures** (re-run after the ADR-080 correction). Zeitwerk clean; Packwerk no offenses; Brakeman 0
  warnings; bundler-audit no vulnerabilities. Architecture fitness **31/0**.
- All migrations **build from empty**; the schema dump is **idempotent** with no drift.
  `verify_runtime` OK — 15 checks, RLS intact.
- Acceptance over the production-real chain with only the **frozen F-01 façade** stubbed; the robots
  golden corpus; and host-gate persistence invariants at the database.

## Recorded boundaries

- **FU-7 (owner attention)** — the same-Organization cross-Project defect class has now appeared in
  **three consecutive tranches** (S-07-003 CB5, S-07-004 CB5, S-07-005 in the read path). Each was
  caught by review, but the recurrence is itself the finding: the rule is easy to violate silently
  and nothing detects it mechanically. Recommended: an architecture fitness spec failing any FK to a
  Project-owned parent with arity < 3, plus a convention for Project-scoped reads.
- **Named requirements S-07-006 inherits**: sort the stored robots sitemap candidates into `:454`
  order (they are stored in *file* order, as `:450` describes); treat the stored list as
  **unfiltered** (in-scope checking is S-07-006's); and pass the discovering *sitemap* URL to the
  frontier occurrence record, since the entry's ordering tuple is forced to `('', 0)` for a sitemap
  candidate by `:454`.
- `:452`'s "robots-disallowed URLs are recorded as skipped, excluded from the coverage denominator
  and Evidence, and are not fetch failures" needs an owner when coverage classification lands
  (S-07-009). The host-level half is already preserved: `robots_terminal_reason` persists per host.
- `fetch_crawl_not_running` and `fetch_project_not_active` are defence in depth and currently
  unreachable, because the guards still refuse the running-terminal and active-Project-exit edges
  (S-07-009 and OD-014 respectively).

## Next

S-07-006 (sitemap discovery + XXE-hardened XML), then S-07-007..011, under the standing delegation.
