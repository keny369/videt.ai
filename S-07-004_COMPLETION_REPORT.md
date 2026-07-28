# S-07-004 Deterministic Crawl Frontier + Dequeue (WF-005) — Completion Report

Status: **ACCEPTED** (standing delegation ADR-061; DECISIONS ADR-078) — the integration branch
`implementation/s01-registration-access` pushed; protected branch `main` untouched. The FOURTH
tranche of the S-07 "Crawl Execution and Recovery" slice, and the one that discharges the frontier
limb of owner decision **HD-S07-FU4-FU5** (ADR-077).

The ADR-026 five-lens review was run by **three independent reviewers** (contract; security+schema;
concurrency+architecture). The concurrency lens returned **PASS**; the other lenses returned **five
confirmed-blocking findings, all fixed before acceptance**.

## What was built

- **`Workflows::Wf005::FrontierOrder`** — the pure ordering function. Volume I (:454) fixes the tuple
  `(depth, origin_rank, canonical_url, discovering_document_url, link_position)` with
  `root < sitemap < link`; SEARCH_CRAWL_RETRIEVAL requires it materialized into `dequeue_key bytea`
  and "tested against a reference tuple comparator". `bytea` compares bytewise, so the encoding must
  be **order-preserving**: fixed-width big-endian numerics, and string fields **escaped and
  terminated** (`0x00 -> 0x00 0xFF`, closed with `0x00 0x00`). The document's "length-prefixed"
  phrasing cannot apply to the variable-length fields — a length prefix inverts `"ab" < "b"` — and
  the testable obligation is what governs. A trailing entry UUID makes the key total.
- **Migration `20260727120170`** — `crawl_frontier_entries` (T-MUT) and `crawl_frontier_occurrences`
  (T-IMM): FORCE RLS, composite same-Project FKs, the identity unique
  `(crawl_id, canonical_url_sha256, collision_ordinal)` with the **full preimage retained beside the
  digest** (a collision allocates an ordinal and never merges candidates), the dequeue unique, the
  origin/depth/discard shape CHECKs, and a lifecycle guard.
- **`Workflows::Wf005::Frontier` + `CrawlFrontierStore`** — root seeding inside the accepted-start
  commit (SEARCH_CRAWL_RETRIEVAL step 6), `offer` with deduplication and the discovered-queue bound,
  and the dequeue claim, which orders by `dequeue_key` **in PostgreSQL** under `FOR UPDATE SKIP
  LOCKED`. Admission is serialized on a per-Crawl advisory lock because both deduplication and the
  retention bound are order-dependent read-then-write decisions.
- **Migration `20260727120180`** — the review hardening.

## The owner's requirement, enforced at three layers

`crawl_sources` is T-IMM and records **queue-time** membership, so seeding from it alone would crawl
a Source the customer has since disabled or removed:

1. **Seeding** intersects the pinned set with Sources still `active`.
2. **StartCrawl's `crawl_no_active_source` precondition** is evaluated over that same intersection,
   so a run that can crawl nothing **fails** rather than reaching `running` with an empty frontier.
   (A Source activated after queueing cannot rescue the run — only pinned Sources are crawlable.)
3. **The dequeue** re-checks Source state on every claim, so a Source disabled *after* the start is
   never handed to a worker. Added on a review finding: the owner's words are "at execution time",
   and the dequeue is execution time.

An independent reviewer attacked all of this — disable one, remove one, disable all, activate a
different Source after queueing, and a real race committing a `DisableSource` underneath an in-flight
`StartCrawl` — and could not defeat it.

## Independent review (ADR-026 — ADR-078)

**Concurrency — PASS.** 3/3 concurrent claim races took distinct entries; 5/5 concurrent identical
offers produced exactly one admission plus one occurrence; three concurrent offers at a pre-loaded
bound left the counter exactly at the bound; no ABBA cycle across the three advisory locks StartCrawl
holds (`crawl-queue` → entitlement window → `crawl-frontier`, always that order).

- **CB1 — FIXED.** Deduplication retained the first *offered*, but :454 says "retains the first
  candidate **in this order**". Reachable because :440 puts sitemap URLs and root-followed links both
  at depth 1, where origin rank rather than the URL decides parent order. A lower-ordered later
  discovery now **repositions** the retained entry; the superseded position becomes the occurrence.
  This required the guard to make **position** mutable while unclaimed and frozen from the claim
  onward — **identity** stays frozen for life.
- **CB2 — FIXED.** The 20,000 bound discarded by arrival, but :454 says "retain the **lowest** 20,000
  by this order". At the bound a lower-ordered newcomer now **evicts** the highest-ordered unclaimed
  entry. Both losers are retained as `discarded` rows for the coverage denominator (:452). The bound
  had **no behavioural test at all**; it now has two.
- **CB3 — FIXED.** Breadth-first **sealing** was asserted as "falls out of the tuple" and was not
  implemented. Ordering by depth is necessary but not sufficient: once every depth-`d` row is claimed,
  `SKIP LOCKED` would hand out depth `d+1` while depth `d` is still in flight. :454 binds sealing to
  **selection**, which is `claim_next`. Selection is now confined to the lowest depth still holding a
  non-terminal entry, and the false claim is corrected everywhere it appeared.
- **CB4 — FIXED.** Two **whole-table sequential scans per offer**, inside the exclusive admission lock,
  on a workflow with a hard 60-minute ceiling (measured 8.8× degradation, 0.62 → 5.43 ms/offer at
  ~19k rows). Two indexes added.
- **CB5 — FIXED.** A **two-column FK to Project-owned `source_scope_policies`** — the same defect class
  as S-07-003's CB5, with a demonstrated persisted cross-project link. `source_scope_policies` gains
  the mandated three-column unique and the FK is rebuilt on it.

**Further hardening:** `state_version` may only advance by one (the sole defence the CAS guards have);
`correlation_id` and a written `reason` frozen; idempotent occurrence insertion (a fetch-retry
re-offer can no longer abort the caller's transaction); NFC-normalized `canonical_url`; `uint32`
refuses overflow rather than silently wrapping the order; domain reason codes moved off the
persistence adapter.

**Claims corrected rather than left standing:** collision telemetry is **not** emitted (three of
SEARCH_CRAWL_RETRIEVAL's four clauses are implemented) — recorded as **FU-6**; the `discovered`
staging edges are not on a live path in this tranche; and the ordering proof's "0xFF" alphabet claim
was *unreachable* (NFC normalization raises on invalid UTF-8) rather than merely untested.

## Verification (exact results)

- Whole repository: **1522 examples, 0 failures**. Zeitwerk clean; Packwerk no offenses; Brakeman 0
  warnings; bundler-audit no vulnerabilities. Architecture fitness **31/0**.
- All migrations **build from empty**; the schema dump is **idempotent** with no drift.
  `verify_runtime` OK — 15 checks, RLS intact.
- **16 acceptance examples** over the production-real chain, **19 persistence invariants** on the
  database itself, and **16 ordering examples** including the exhaustive cross-product proof.

## Recorded boundaries

- **No robots gate** (S-07-005) — the two nullable `robots_*` columns are reserved for it. **Named
  requirement it inherits:** per-URL Source and scope re-validation must continue at fetch time; the
  frontier's dequeue-time check is necessary but is not a substitute for the per-URL obligation.
- **No sitemap or link discovery** (S-07-006 / S-07-007) — both enter through the same `offer`
  surface. S-07-006 must pass the discovering *sitemap* URL to the occurrence record: the entry's
  ordering tuple is forced to `('', 0)` for a sitemap candidate by :454, so the occurrence is the only
  place that provenance can live.
- **No commit coordinator** (S-07-007) — SEARCH_CRAWL_RETRIEVAL's "one coordinator commits discoveries
  in increasing dequeue key, a later key waits in `fetched_pending_commit`". The state exists in the
  CHECK; nothing writes it yet.
- **No limit events** (S-07-008) — the soft 16,000 threshold and `CrawlSoftLimitApproaching` are its.
- **FU-6** — restricted collision telemetry.

## Next

S-07-005 (host gate + robots fail-closed + per-host rate), then S-07-006..011, under the standing
delegation.
