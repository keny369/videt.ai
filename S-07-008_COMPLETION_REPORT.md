# S-07-008 — Crawl Limits, Soft/Hard Decision Events, The Wall Clock, Ordered Admission

**Status: reviewed and repaired. NOT ACCEPTED.** No acceptance ADR is allocated.

The five ADR-026 lenses returned **four BLOCK and one PASS_WITH_OBSERVATIONS**, with eight
confirmed-blocking findings after deduplication — two of them reached independently by more than
one lens. Every confirmed-blocking finding is repaired below, each with a test that fails when the
repair is reverted. The gate was not ceremony: it stopped a materially incorrect tranche.

**FU-9 is `mitigated`, not delivered.** A hand-back method is not scheduler re-entry, and nothing in
production calls `DiscoverSitemaps#call` at all. The driver is now owned by **BUILD_PLAN S-07-012**,
and FU-9 closes when that lands.

Built under standing delegation ADR-061. The tranche is reviewed BY PATH over a commit range, not by commit — see "The acceptance diff" below.

## The shape that matters

Every customer-visible limit event is a **consequence of a durable record**, never of runtime state:

```text
decision inserted (UNIQUE adjudicates)  ->  audit + event, on the same transaction
```

rather than the shape that was tempting at every one of the ten observation points:

```text
runtime detects a threshold  ->  emit  ->  hope nothing else emitted too
```

`UNIQUE (crawl_id, limit_dimension, threshold_kind)` **is** `:442`'s "exactly once per dimension and
run". It is the only participant that can adjudicate *first* across processes, so making it the
thing that decides means a retry, a replay, a crash between the two writes, or eight workers
crossing in the same millisecond all converge on one event without any of them coordinating. Every
other ordering — emit then record, count then emit, check then insert — has a window. This one has
none, because the barrier and the record are the same statement.

Two consequences that were designed for rather than discovered:

- **The event is built from the `RETURNING` columns**, not from the caller's arguments. A CHECK that
  rejects a value stops the event as well as the row, and the stream cannot describe a decision the
  database does not hold.
- **There is no pre-filter.** The insert *is* the check, so no second mechanism can disagree with
  it. The counter-bit claim written alongside this table in 1/n was superseded in 3/n and deleted;
  `crawl_budget_counters.soft_limit_events` / `hard_limit_events` are written and read by nothing.

## What the review found, and what it changed

| # | Finding | Lenses | Repair |
| --- | --- | --- | --- |
| 1 | FU-9 leaked the run-wide sitemap-document budget; re-entry converged on the very `sitemap_unavailable` it exists to prevent | concurrency, security, architecture | The charge moved inside `fetch_document`, after the gate grants and once per DISTINCT URL |
| 2 | `DiscoverSitemaps#terminalize` committed decisions when its UPDATE matched zero rows — the guard was outside the unit of work | concurrency | Guard moved inside, before the observation, matching `FetchContent#settle` |
| 3 | `Admission#reserve` called a lost compare-and-update "exhaustion" and recorded the STALE figure | concurrency | Re-read and retry; a lost race is `run_byte_budget_contended`, not a limit |
| 4 | A single retryable timeout emitted `CrawlLimitReached` | contract | Fires only once `:444`'s retries are exhausted |
| 5 | Queue hard event recorded `observed_value = configured − 1` on the eviction path | contract, architecture | Observed from the count read BEFORE the eviction |
| 6 | `crawl_depth_from_source_root` had no soft limb at all | contract | Added |
| 7 | No persistence-invariants spec, while the report implied `verify_runtime` covered the table | security | `spec/persistence/crawl_limit_decision_invariants_spec.rb` |
| 8 | FU-9 had no driver and no build-plan block owned one | architecture | S-07-012 added; FU-9 downgraded to `mitigated` |

### The third pass: the accounting semantics, the proof quality and the repository truth

Owner-directed. All five lenses ran again over the complete tranche and every repair. **Three BLOCK,
two PASS_WITH_OBSERVATIONS** — and concurrency, which had blocked hardest, passed: the ledger held
under every interleaving it could construct.

| # | Finding | Repair |
| --- | --- | --- |
| 15 | `discovered_url_queue` counted `state <> 'discarded'`, excluding depth-rejected candidates that `:440` says DO consume the queue — a run could pass its inclusive maximum in silence | the count now includes them; a queue-limit discard stays excluded, or the bound would be self-defeating |
| 16 | The queue bound was an `elsif` on the depth limb, so an over-depth candidate arriving at the retention bound produced no queue decision | the bound is evaluated for every candidate; only the EVICTION is skipped for one that is not retained |
| 17 | The soft limb was gated behind the hard limb at four remaining sites, losing the soft event permanently for any run whose only crossing was the hard one | all four hoisted; the rule the frontier learned, applied everywhere |
| 18 | `affected_*` counts named the whole unselected frontier for dimensions that do not stop scheduling — ~20,000 reported for a queue discard costing one URL | explicit counts per dimension; the default is restricted to the two run-stopping bounds |
| 19 | `canonical_url` had an 8,192 CHECK over remote input with no application bound, so an over-long sitemap URL raised an uncaught violation that wedged the gate `in_progress` for the run | bounded at `normalize`, where a refusal is an ordinary recorded skip |
| 20 | `charge_for` was keyed on `crawl_id` alone — the shape the sibling repair condemned by name ten lines away | all three of (organization, project, crawl), plus a guard for a missing counter row |

**The ledger authority question is resolved rather than documented.** The ledger is now the SOLE
authority: the bound is `COUNT(*) < ceiling` over its rows under the per-Crawl row lock, and
`crawl_budget_counters.sitemap_documents` is a declared projection *recomputed* from it in the same
transaction — never incremented, so the two cannot disagree. Two apparently authoritative
representations connected only by convention is what S-07-005 already rejected in this subsystem.

**The `pacer` seam is deleted.** The byte race is now forced by an uncommitted rival holding the
counter row, with PostgreSQL's re-evaluation ordering it — the same EPQ mechanism the store already
documents, no production API change. The seam was a new category justified by a claim that no
alternative existed; there was one.

**Four claim-honesty failures**, all mine: the `FOR UPDATE` explanation in the spec contradicted the
store's own correct comment; `charging_threads` documented a `gate` mechanism that did not exist;
`ActiveCrawlPolicies` said three copies when there were two; and the Project authorization limb was
called mutation-proved when it is UNREACHABLE at HEAD — `f1_projects_guard` admits only
`draft -> active`. Its spec now asserts that unreachability and fails when the Project lifecycle
lands, which is the signal to write the real denial test.

**Three governance contradictions**: `BUILD_STATE.next_action` was byte-identical to `09277e7`,
still assigning FU-9 re-entry to this tranche and still directing the deleted counter-bit mechanism;
the machine fields said `pending`/`ready` while the prose said complete-and-reviewed, with
`updated_at` moving backwards; and the ledger table was absent from `schemas/POSTGRESQL_SCHEMA.md`
— structurally invisible because `schemas/` was missing from the declared acceptance paths. All
three repaired, including the paths.

### The second pass found the repairs had their own defects

Owner-directed scope: the five lenses ran again over the repair delta, in the context of their own
original findings. **All five returned BLOCK.**

| # | Finding | Lenses | Repair |
| --- | --- | --- | --- |
| 10 | The depth-soft observation was written as an `elsif` in the disposition chain, so a candidate in `[soft, hard]` skipped the 20,000 retention bound entirely — no eviction, no discard, no decision | **all five** | Observation hoisted out of the chain; regression test combining depth ≥ soft with the retention bound |
| 11 | The sitemap charge was memoized in memory, so re-entry re-charged any URL that had reached the network and failed — converging on the same false `CrawlLimitReached` | 4 of 5 | `crawl_sitemap_document_charges`, `UNIQUE (crawl_id, canonical_url_sha256)` — :437's distinct-URL unit made durable |
| 12 | The replacement run-wide-maximum test was still not a bound test: the frontier lock serialised every thread, so the counter predicate was never exercised | concurrency | The rival now reserves through the production store on its own connection — the real `FetchContent` relationship |
| 13 | `crawl_not_running` had no test at all, and the residual gap was wider than the fix | security | The admission-safe subset of `FetchAuthorization` (Organization, Crawl, Project, entitlement), every limb denying before any effect |
| 14 | Governance contradicted itself: BUILD_PLAN still claimed FU-9 delivered, nothing depended on S-07-012, and the report carried stale figures and a claim it disowned elsewhere | architecture | One truth across all three; S-07-012 added to S-07-009's `depends_on` |

Two claims of mine were withdrawn rather than defended: the `pacer` is **not** the seam the sibling
services carry, and `EffectiveLimits` unified **three** copies, not four. Both were caught by lenses
reading the code against the prose.

**A ninth defect was found by writing repair 7.** The threshold biconditional read
`decision_reason_code = 'limit_reached'`, so a hard decision with a NULL reason evaluated to
`FALSE OR NULL` = NULL — and SQL admits a CHECK whose result is unknown. The row `:300` exists to
forbid was accepted. Repaired NULL-safely in its own migration
(`20260727120280`) rather than by amending the original, so the hole and its repair both stay
visible. No lens found this one; the spec written to close a lens's finding did.

A tenth was found by mutation-checking repair 11: my own comment claimed the counter-row `FOR UPDATE`
was what made the sitemap bound exact. It is not — the UPDATE's own `sitemap_documents < ceiling`
predicate is, under EPQ re-evaluation. Removing the lock changed nothing; removing the predicate let
six workers charge past a ceiling of one. The comment now states what each mechanism actually
protects, and marks the one property that is asserted rather than proved.

Also removed: `claim_limit_event` and the three comments describing it as a live pre-filter (it had
no caller); the `EffectiveLimits` rationale claiming it replaced four copies including `Admission`
(which this tranche created) and `StartCrawl` (which still resolves its own, for reasons now
written down); and `DerivedUuid`'s claim to be "pinned by spec" — the pin now exists, comparing the
Ruby against the live PL/pgSQL over fixed digests.

## The twelve dimensions

| Dimension | Observation point | Notes |
| --- | --- | --- |
| `accounted_response_body_bytes_per_run` | `Admission#admit` | soft on the **reserved peak** the statement returns; hard before the budget is exceeded |
| `wall_clock_run_duration` | `Admission` | soft from `started_at`; hard from `crawls.deadline_at`; only while `state='running'` |
| `discovered_url_queue` | `Frontier#offer` | soft on the retained count; hard when a candidate is discarded at the retention bound |
| `crawl_depth_from_source_root` | `Frontier#offer` | decided **before** the queue bound; soft and hard |
| `response_body_per_url` | `FetchContent#settle` | observed value is the bound plus the probes — the exact size is unknowable |
| `connection_plus_response_time_per_request` | `FetchContent#settle` | hard on timeout **exhaustion** (`:444`), not per attempt; soft from measured latency |
| `redirects_per_url` | `FetchContent#settle` | hard on `redirect_limit_exhausted` |
| `sitemap_documents_per_run` | `DiscoverSitemaps` | soft at the reservation; hard from the traversal's limit reasons |
| `sitemap_index_nesting_depth` | `DiscoverSitemaps` | at terminalization, with the outcome it explains |
| `accepted_pages_per_run` | **none — S-07-010** | the bound counts Documents, which this tranche cannot create |
| `request_rate_per_canonical_host` | **none — by contract** | see the assumption below |
| `concurrent_requests_per_canonical_host` | **none — by contract** | see the assumption below |

Every decision is written **on the transaction that caused it**: the frontier's two with the
candidate row, the fetch's three with the attempt record, the sitemap document soft with its
reservation, the sitemap hard limits with the terminal outcome. A decision in a separate transaction
would leave a window in which the effect is durable and the reason for it is not — and since
S-07-009's terminal checkpoint reads the decision table rather than the counters, that window is
exactly where a run would forget it had hit a limit.

## FU-10 — ordered admission (`:456`)

`Wf005::Admission` claims the frontier entry **and** its byte reservation in one transaction, under
the frontier's own advisory lock. That is the whole of it, and it is smaller than the follow-up
implied: the lock already serialises the dequeue, so a reservation taken inside it is taken in
dequeue order *by construction*. No coordinator to fall behind, no pending queue to drain.

S-07-007 enforced the sum and not the order — it claimed in one transaction and reserved in another,
so which URL received the last of the run's budget depended on thread scheduling.

**The lock is proved load-bearing, not asserted.** The same advisory key is held from another
connection and admission must BLOCK. The earlier version of that test raced four threads and passed
with the lock removed.

`fetched_pending_commit` — `:456`'s other clause, about committing a fetched document's outgoing
links in dequeue order — belongs with link extraction in S-07-010 and is deliberately not pre-empted.

> **None of these observation points runs in production yet.** `Admission`, `FetchContent`,
> `DiscoverSitemaps` and `EnsureRobots` have no caller: the only registered entry point is
> `crawl_dispatch -> StartCrawl`, which seeds the root frontier and schedules nothing further. That
> boundary is pre-existing and was accepted for S-07-005/006/007, but this report stated the
> dimensions as "observed" without it, which was misleading. The driver is **S-07-012**.

## FU-9 — sustained contention is not an outcome

A host under sustained gate contention could exhaust the traversal's deferral budget and then be
terminalized `sitemap_unavailable` — write-once, coverage permanently partial — having made **zero
network attempts**.

`:450` conditions `sitemap_unavailable` on "no sitemap candidate succeeds **after retries/
validation**". A candidate the rate limiter never released has had neither, so the premise is unmet
and there is nothing to record. The claim is handed back, the gate returns to `pending`, and the
host is exactly as discoverable as it was before.

**No new scheduled-action kind.** The ratified catalogue is closed and none of its crawl kinds means
"re-run sitemap discovery for a host" — `crawl_fetch_due` is bound to a Fetch Attempt identity,
`crawl_dispatch` to `StartCrawl`/`CompleteCrawl`/`FailCrawl`/`CancelCrawl` "selected solely from
persisted Crawl/deadline state". A `pending` gate **is** the re-entry: the next pass claims it
exactly as the first did.

**What bounds it** is the run's wall clock. Past the deadline no candidate can ever be attempted, so
discovery terminalizes `unavailable` once, honestly.

**What it does NOT do is re-enter.** Nothing calls `DiscoverSitemaps`, so "the next pass claims it
exactly as the first did" describes a pass that does not exist. What is genuinely delivered is the
removal of a write-once FALSE outcome and of the budget leak that made it inevitable; the driver is
S-07-012's, and FU-9 stays open until then.

## Two defects found by making the number customer-visible

Both are the class `:390` keeps producing: a ratified bound expressed as a class constant, so a
Project that narrowed it was silently ignored.

1. **Sitemap discovery passed constants as its ceilings** — `SitemapCandidates::DOCUMENT_LIMIT` to
   the run-wide reservation and `MAX_INDEX_DEPTH` to the child check. This is the defect S-07-007
   fixed on the per-fetch bounds, still present here. Writing a decision that records its
   `configured_value` is what surfaced it: the moment the recorded number must be the enforced
   number, a constant cannot pretend.
2. **The sitemap document hard limb watched only the reservation refusal**, missing the ordered
   retention path (`:450` — "only the first 50 distinct candidates in that order are retained")
   entirely. A run that discovered sixty sitemaps and kept fifty recorded no limit at all.

## Boundaries stated rather than implied

- **`coverage_status` / `completion_reason` are not written here.** `crawls_terminal_shape` forbids
  them while running, and `:456`'s precedence (`canceled`, `failed`, `limit_reached`,
  `partial_source_failure`, `completed`) is the terminal checkpoint's. S-07-009 derives them from
  the decision table — the same single-source discipline seen from the other end.
- **`sitemap_xml_limit` gets no decision row.** The closed `limit_dimension` enum has no member for
  an XML structural limit. It still forces `limit_reached` through the sitemap outcome, so nothing
  is lost; inventing a dimension would put a value in a customer event the contract does not admit.
- **`accepted_pages_per_run` stays unobserved** until the artifact it counts exists.

## Owner-decided: what a limit event is for

**Principle (owner, 2026-07-29): do not emit events for normal pacing decisions. An event must
represent an exceptional operational condition, not expected scheduler behaviour — otherwise the
signal loses its diagnostic value.** This is a general rule for the system, not a WF-005 detail: it
applies wherever a ratified dimension has a "soft" value that is really an operating target rather
than an approach to a wall.

Its first application is here. **Per-host RATE and CONCURRENCY emit no limit decision.** `:442` resolves an over-rate start by
**delaying** it ("a start that would make the count exceed 2 is delayed"), and carves that limb out
before "At any **other** hard limit…". `:456`'s list of bounds that leave a candidate unevaluated is
"depth, sitemap, queue, page, byte, response, request, or wall-clock" — rate and concurrency are
absent from both. They are pacing parameters the scheduler holds the observation *below*, not
thresholds a run reaches; the soft values are described as "normal scheduling targets", so emitting
on them would fire on essentially every run and make the saturation signal worthless.

This is the one reading here a careful reader could differ on. **To change it**, add the two
dimensions to the observation in `HostGate#claim` — the surface takes them without modification.

## The acceptance diff, and what is excluded from it

Owner ruling, 2026-07-29: **published history is not rewritten to make a tranche cosmetically
clean.** Commits `827c39a` and `508edde` were made with `git add -A` and swept in twelve unrelated
`branding/`, `investor/` and `operations/` files, including ~2 MB of binaries. `827c39a` is
therefore **not an atomic implementation unit**.

The consequence for review is procedural, not cosmetic: **S-07-008 is reviewed BY PATH over a
commit range, never by treating any single commit as a tranche slice.**

| | |
| --- | --- |
| Range | `09277e7..HEAD` of this branch |
| Acceptance paths | `app/`, `db/`, `spec/`, `lib/`, `specification/`, `S-07-008_COMPLETION_REPORT.md` |
| Excluded | the twelve files listed in `BUILD_STATE.acceptance_evidence.excluded_contamination` |

Verified complete: the acceptance paths plus the excluded set account for every file changed in the
range — nothing falls outside both. History surgery was considered and rejected; it would only be
justified if the branch were private, nothing were based on it, governance permitted rewriting, and
separation materially improved release, audit or cherry-pick integrity. None of that is established,
and rewriting would create more risk than it removes.

## Verification

| Gate | Result |
| --- | --- |
| RSpec | see `BUILD_STATE.reconciliation_note` for the figure at the last gate run (1741 at tranche start) |
| Zeitwerk | clean |
| Packwerk | clean, no stale violations |
| Brakeman | 0 security warnings |
| `verify_runtime` | OK as `f1_web`, 15 checks — a FIXED list over `sessions`/`accounts`/`scheduled_actions`/transport, which says **nothing** about this tranche's table |
| Persistence invariants (`crawl_limit_decisions` + `crawl_sitemap_document_charges`) | 21 examples, asserted against a live database |
| `db/structure.sql` | no drift |

### What is proved rather than asserted

- **The once-ness blocks.** An uncommitted decision makes a concurrent observer wait on the index,
  observed in `pg_stat_activity` rather than timed. Eight observers then race on eight **independent
  logins** — the AR pool is five, so pooled threads would have queued and proved nothing.
- **The frontier lock is load-bearing.** Held from another connection, admission must block.
- **Every bound in the observation spec is narrowed by an active Project policy**, because a test
  that only ever sees the global ceiling cannot tell the resolved bound from the constant.
- **Contention is produced by the gate's own predicates** — every concurrency slot held by live
  leases, no simulated time passing — not by a stub that reports refusal.
- **Mutation-checked**: dropping `crawl_limit_decisions_once`, removing the `unless replayed` guard
  (one event becomes eight), removing the depth branch, removing the queue observation, and removing
  the FU-9 deferral branch each fail their tests.

## Decision Ledger

| Decision | Authority | Reason |
| --- | --- | --- |
| Sitemap documents charged after the gate grants, once per distinct URL | Autonomous (defect repair) | The unit is URLs ATTEMPTED; charging before the gate leaked a budget with no release path |
| A lost byte-reservation race is `run_byte_budget_contended`, not a limit | Autonomous (defect repair) | The frontier lock does not cover the fetch path's writers; a lost compare-and-update is not exhaustion |
| Admission PEEKS before it claims | Autonomous (defect repair) | `in_progress` has no way back under the frontier guard, and a stranded entry pins `sealed_depth` for the run |
| Admission refuses a Crawl that is not `running` | Autonomous (security default) | A terminal run's `deadline_at` is past, so the wall-clock limb would emit `CrawlLimitReached` for a run that finished normally |
| The request-time hard limb fires on exhaustion, not per attempt | Autonomous (defect repair) | `:444` allows two retries; `:452` fails the URL only when they are exhausted |
| `Admission` gains a no-op `pacer` probe point | Autonomous | A NEW kind of seam here, not the millisecond-sleep collaborator the sibling services carry — an earlier claim that it was the same pattern is withdrawn. It earns its place because the repaired window cannot be opened reliably by racing threads, and the alternative was to leave the repair unproved |
| The NULL-reason CHECK hole repaired in its own migration | Autonomous (defect repair) | The hole and its repair both stay visible; amending the original would erase the lesson |
| FU-9 downgraded to `mitigated`; S-07-012 added | **Owner-directed** | A hand-back method is not scheduler re-entry, and no block owned the driver |
| The decision row is the outbox trigger; events derive from `RETURNING` columns | Autonomous | The unique key is the only cross-process adjudicator of "first"; deriving the event from the row removes the drift window |
| `EffectiveLimits` unifies the THREE execution-time copies of the `:390` resolution; `StartCrawl` keeps its own | Platform Authority | The configured value in an event and the bound the scheduler enforced must come from one resolution — but a start GATE and a running scheduler are entitled to different answers about an unreadable policy, so collapsing them would have loosened the gate |
| `KeyError` deliberately not carried into the new rescue | Autonomous (defect avoidance) | It would silently discard every Organization/Project policy whenever a reader forgot `content_sha256` |
| `Platform::DerivedUuid` for the global ceiling's `artifact_id` | Assumption (OD-013 precedent) | `EventGoverningVersion` needs a uuid; a constant artifact has none; a derived one is stable and adoptable by the deferred release artifact |
| `global_crawl_safety` as the ceiling's artifact type | Autonomous | The ratified enum already distinguishes it from `crawl_policy` |
| Crawler service identity = `SCHEDULED_ACTION_EXECUTOR` | Assumption | The existing convention for all crawl execution; no separate crawler identity row exists |
| Depth decided before the queue bound | Autonomous | Depth is intrinsic; a queue discard is positional and would name the wrong limit |
| Affected counts = unselected frontier entries for run-wide bounds, 1/1 for per-URL bounds | Autonomous | `:456` — the candidates a limit abandons are the ones still awaiting selection |
| Rate/concurrency emit nothing | **Assumption — owner-visible** | `:442` resolves them by delaying; `:456`'s bound list excludes them |
| `sitemap_xml_limit` gets no row | Autonomous | The closed enum has no member for it |
| FU-9 re-entry uses the existing `pending` gate state, no new action kind | Autonomous | The catalogue is closed and the existing state already expresses re-entry |
| Sitemap ceilings resolved from policy | Autonomous (defect fix) | `:390`; the same defect class S-07-007 repaired |
| `wf005_sitemap_discovery_spec` migrated onto the shared chain harness | Autonomous | It still held a verbatim 184-line copy — the drift the 2/n extraction set out to end |

## Handoff

**To S-07-012 (the driver)** — it owns re-entry for two states this tranche newly produces:
a host gate left `sitemap_state='pending'` (honour the `retry_after` the release reports), and
`Admission`'s `run_byte_budget_contended`. Neither is a limit; both mean "come back". Do **not**
call `Admission#claim_next` and `FetchContent#call` on the same entry — admission already reserves
its bytes, and the fetch path reserves again.

## Handoff to S-07-009

- **Read `crawl_limit_decisions`, not the counters**, to decide `coverage_status` and
  `completion_reason`. `CrawlLimitDecisionStore#decisions` exists for exactly that.
- Any **hard** row makes coverage partial and puts `limit_reached` into the `:456` precedence.
- `crawl_terminal_deadline` enforcement of the stamped `deadline_at` is still S-07-009's; admission
  refuses new work past it, but nothing yet closes the run.
