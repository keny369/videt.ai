# S-07-012 — Crawl Execution: The Run Driver

**Acceptance status: ACCEPTED 2026-07-30, DECISIONS ADR-096.**

This record describes HEAD. It does not narrate how HEAD was reached — git holds that, and a narrative
acceptance record accumulates stale counts and superseded mechanisms faster than it can be corrected.
Every claim below is either mechanically checked by `spec/architecture/repository_truth_spec.rb` or
reproducible by the commands in **Verification**.

**THE MECHANICAL CHECK NOW READS THIS RECORD.** Until the acceptance transition,
`spec/architecture/repository_truth_spec.rb` named `S-07-008_COMPLETION_REPORT.md` by hand, so it went on
validating a superseded tranche while the record actually being accepted was checked by nothing. It now
derives the report from `acceptance_evidence.block`. This document's path partition, path citations,
identifier citations, migration citations and suite figure are therefore asserted for THIS tranche.

## Identity

| | |
| --- | --- |
| Block | S-07-012, BUILD_PLAN `Crawl Execution — the run driver (scheduler re-entry for dequeue, fetch and discovery)` |
| Range | `b48bf6e..f2b576e`, bounded at both ends |
| Authority | standing delegation ADR-061; cadence ADR-086; review discipline ADR-080 |
| Owner rulings implemented | ADR-085 (FU-16), ADR-087 (FU-18), ADR-089 (FU-19), ADR-091 (FU-24), ADR-094 and ADR-095 (FU-25) |
| Excluded | 15 files from four unrelated authorized commits inside the range, each attributed in `specification/automation/BUILD_STATE.json` |

**Accepted paths**, named file by file rather than as `app/` and `spec/`: `DECISIONS.md`,
`F-04_TRANSPORT_DESIGN.md`, `S-07-012_COMPLETION_REPORT.md`,
`app/contexts/identity_access/infrastructure/crawl_budget_store.rb`,
`app/contexts/identity_access/infrastructure/crawl_frontier_store.rb`,
`app/contexts/identity_access/infrastructure/crawl_host_gate_store.rb`,
`app/contexts/identity_access/infrastructure/crawl_start_store.rb`,
`app/contexts/identity_access/infrastructure/fetch_attempt_store.rb`, `app/platform/pg_bool.rb`,
`app/platform/scheduled_actions/lease.rb`, `app/platform/scheduled_actions/lease_keeper.rb`,
`app/platform/scheduled_actions/scheduler.rb`, `app/platform/scheduled_actions/store.rb`,
`app/platform/scheduled_actions/worker.rb`, `app/workflows/wf005/`,
`config/initializers/scheduled_actions.rb`,
`db/migrate/20260727120300_crawl_frontier_seal_release.rb`,
`db/migrate/20260727120310_scheduled_action_lease_heartbeat.rb`,
`db/migrate/20260727120320_scheduled_action_derived_lease.rb`,
`db/migrate/20260727120330_scheduled_action_coherent_lease_rule.rb`, `db/structure.sql`,
`lib/f1/runtime_grants.rb`, `schemas/POSTGRESQL_SCHEMA.md`,
`spec/acceptance/support/wf005_crawl_chain.rb`, `spec/acceptance/wf005_admission_spec.rb`,
`spec/acceptance/wf005_content_fetch_spec.rb`, `spec/acceptance/wf005_crawl_frontier_spec.rb`,
`spec/acceptance/wf005_limit_observation_points_spec.rb`,
`spec/acceptance/wf005_record_fetch_attempt_spec.rb`, `spec/acceptance/wf005_sitemap_discovery_spec.rb`,
`spec/acceptance/wf005_start_crawl_spec.rb`, `spec/architecture/repository_truth_spec.rb`,
`spec/architecture/scheduled_action_lease_rule_spec.rb`,
`spec/persistence/crawl_frontier_invariants_spec.rb`,
`spec/platform/scheduled_actions/lease_keeper_spec.rb`,
`spec/platform/scheduled_actions/store_spec.rb`, `specification/automation/AUTONOMY_POLICY.md`,
`specification/automation/BUILD_PLAN.yml`, `specification/automation/BUILD_STATE.json`,
`specification/volume-ii/BACKGROUND_PROCESSING.md`.

**WHY FILE BY FILE.** The range interleaves this tranche with four unrelated authorized commits. One is
the ADR-084 blocking-defect repair that bounded the shared test-harness PG connections, and it touches
`spec/`; another is a dependency-security patch to Rails 8.1.3.1. A wholesale `spec/` claim would have
absorbed a repair this tranche did not make into its acceptance, which is exactly the class of false
record the repository-truth spec exists to prevent. The accepted paths and the excluded list partition
the range EXACTLY, and that is asserted, not asserted-about.

## What this tranche is

**S-07-004 through S-07-008 built the execution surfaces and NOTHING IN PRODUCTION CALLED ANY OF THEM.**
The only registered entry point was `crawl_dispatch -> StartCrawl`, which seeded the root frontier and
scheduled nothing further. Every claim about a run making progress — including S-07-008's FU-9
"re-entry" — presupposed a driver that did not exist. This tranche is that driver, the frontier seal
release without which its own loop could not cross a depth boundary, and the F-04 lease work the driver
turned out to need.

## Delivered behaviour

**One `crawl_fetch_due` action is one pass of the run.** BACKGROUND_PROCESSING.md :377 fixes
`crawl_orchestrate` to `StartCrawl` / `CompleteCrawl` / `FailCrawl` / `CancelCrawl` "selected solely from
persisted Crawl/deadline state", so the orchestrator cannot drive the frontier. :378 gives
`crawl_fetch -> RecordFetchAttempt` and "its terminal transaction creates the exact ingestion or
next-frontier action". The run is therefore a CHAIN, not a loop, and the run's own 60-minute wall clock
bounds it: past the deadline no pass links, so a chain cannot outlive its Crawl.

**The action targets the SELECTED FRONTIER ENTRY and admission happens at execution** (ADR-085, the
owner's ruling on FU-16). `Workflows::Wf005::CrawlFetchDueSchedule#link_next` names the entry the frontier
peek selects under the frontier's own advisory lock; it mints no attempt identity, holds no byte
reservation, and does not touch the frontier. The FETCH PATH IS THE SOLE PRODUCER of `fetch_attempts`
rows, and no ScheduledAction anywhere targets a `fetch_attempt`.

**THE SCHEDULER OWNS WAITING; THE WORKER OWNS ONE BOUNDED ATTEMPT** (ADR-089, the owner's ruling on
FU-19, superseding ADR-085's in-process-retry clause). One execution performs at most one attempt. A
retryable outcome with attempts remaining schedules a new `crawl_fetch_due` for the same entry at
`fetch_attempts.completed_at` plus :444's delay and returns; nothing sleeps. :444's three-attempt bound
and its exact 30,000 / 120,000 ms delays are unchanged, the attempt number still comes from committed
state, and the claim, the reservation and the depth seal are held across the retry because they belong to
one admission of one URL. The instant is DERIVED from the committed row rather than taken from the
worker's clock, so any party deriving it lands on the same ScheduledAction identity and a second link
replays. A retry that would fall past `crawls.deadline_at` is treated as exhaustion, which releases the
reservation and the seal immediately.

**The order of operations is the specification, and two steps of it are not obvious.**

1. **The wall clock, before anything.** :442's "At 60 elapsed minutes, NO NEW REQUEST STARTS" binds robots
   and sitemap documents too, so `Workflows::Wf005::CrawlDriver#within_wall_clock?` is consulted before
   the first of the three rather than only at admission. An expired run makes ZERO requests.
2. **Robots.** `Workflows::Wf005::EnsureRobots#call` performs at most one network attempt per call and
   hands its :444 retry schedule back to the caller. Nothing was that caller until now, so a host whose
   robots failed transiently was never resolved. A terminal-but-not-fetchable record halts the pass
   without discarding the candidate: it is retired unfetched so the run carries on to other Sources
   (:448 scopes fail-closed to one host), and it stays inside :452's coverage denominator.
3. **Sitemap discovery**, which is FU-9's re-entry. A gate the release handed back is `pending` with a
   `retry_after`, and re-entering at exactly that instant is what stops sustained contention from
   terminalizing `sitemap_unavailable` with zero network attempts.
4. **ONE PASS MAKES AT MOST ONE PACED HOST START.** Without `Workflows::Wf005::CrawlDriver#host_ready_at`
   a pass would fetch a sitemap and then have its content claim refused in the same second, and
   `Workflows::Wf005::FetchContent#call` classifies a refused claim as `host_gate_deferred` with
   `retryable: false`, so the root URL would be recorded `limit_discarded` because the run's own
   discovery had just been polite.
5. **Admission of the named entry.** `Workflows::Wf005::Admission#claim_entry` claims the NAMED entry or
   nothing, under the same advisory lock and the same peek-pay-claim sequence
   `IdentityAccess::Infrastructure::CrawlFrontierStore#claim_next` uses, so :456's dequeue-order admission
   is unchanged.
6. **The fetch**, through the accepted `Workflows::Wf005::FetchContent#call`, consuming the reservation
   admission paid for.
7. **The seal release.** `IdentityAccess::Infrastructure::CrawlFrontierStore#terminalize` retires the
   claimed entry, `in_progress -> terminal`.

**A pass that decides nothing re-enters against the same entry and leaves the frontier exactly as it found
it.** Robots still resolving under :444, sitemap discovery handed back by FU-9's release, and a refused
host-gate claim are all "come back": none is an outcome and none costs the entry an attempt or the run a
byte.

## The frontier seal release

Before `20260727120300_crawl_frontier_seal_release` the guard permitted no edge out of `in_progress`, so
a claimed entry pinned `sealed_depth` at its own depth for the rest of the run. Sitemap discovery admits
content URLs at depth 1 (:440), so a Crawl with any usable sitemap fetched its roots and then stalled
with admitted work queued. Exactly one edge was added, and the boundaries ADR-087 fixed are each
asserted: `terminal` is reachable from `in_progress` ONLY; the transition is a COMPARE-AND-SET on
`(state = 'in_progress', state_version)` bound to the claim that authorised it; `fetched_pending_commit`
remains refused as a source, because it is :456's coordinator limb; NO edge leaves `terminal`;
`commit_order` stays NULL and `crawl_terminal_outcomes` stays unbuilt, both remaining S-07-009's and
S-07-010's.

**The release is taken in the driver's own transaction, before the ledger and the next link.** Retiring
the entry inside the handler's terminal transaction has the worse failure mode: a process lost between
the fetch and the ledger write would leave the entry `in_progress` forever and PERMANENTLY PIN THE DEPTH,
needing a resumption policy this tranche has no authority to invent.

## The F-04 lease work, and the two records that were wrong before they were right

The driver made a latent F-04 defect reachable: a delivery could outlive its transport lease, so the
sweep returned the action to `pending` and the ordinary path executed twice. Three mechanisms were built
across four commits, and **two of the three were recorded as complete while still defective**. That is
recorded here because it is the tranche's most transferable lesson.

- `20260727120310_scheduled_action_lease_heartbeat` — the FENCED heartbeat (ADR-091). Three claims in its
  first record were false and were demonstrated false by review: a relinquished delivery was SETTLED
  rather than released; renewal-per-hop was true of the content path only; and "no request, attempt,
  byte, terminal state, link or ledger row" was an intent rather than a property. All three repaired
  (ADR-092), with `Platform::ScheduledActions::Lease#redirect_guard` as the single per-hop boundary.
- `20260727120320_scheduled_action_derived_lease` — :288's derived lease (ADR-094). The producer stamps
  `scheduled_actions.product_attempt_deadline`, immutable under the row guard, and transport does the
  arithmetic.
- `20260727120330_scheduled_action_coherent_lease_rule` — the repair ADR-094 needed (ADR-095). **The
  derivation had reached two of the three functions that assign a lease.**
  `f1_heartbeat_scheduled_action` still wrote the caller's flat value, which
  `Platform::ScheduledActions::Worker#lease_keeper_for` supplies as 30, so a pass dispatched with a
  900-second lease had it rewritten to 30 within ten seconds and the original defect was live again.
  Found by a focused review; not by the suite, which was green. Two adjacent false invariants were
  repaired with it: the cap was `greatest(15 minutes, caller_request)` and therefore not a cap, and
  :288's own 30-second floor could not satisfy the invariant `lease > interval + max_hop` that the rule
  exists to guarantee. `specification/volume-ii/BACKGROUND_PROCESSING.md` :288 was amended under the
  owner's express instruction: floor 60, cap explicitly absolute.

**WHY THE SUITE DID NOT CATCH IT, WHICH IS THE POINT.** Every example asserted the implementation's own
arithmetic back to itself. The checks that would have caught it — and that now exist — read the DOCUMENT
and the CATALOGUE instead: `spec/architecture/scheduled_action_lease_rule_spec.rb` parses :288's own
sentence, discovers the lease writers from `pg_proc` rather than a hardcoded list, and fails if any of
them drifts from the document's numbers or expresses the cap as anything but the outer bound.
`Platform::ScheduledActions::LeaseKeeper#interval` is still divided from the REQUESTED lease rather than
the granted one; that residue is FU-29, conservative in a named direction and never late.

## Verification

Run from the repository root, from a database built FROM EMPTY. The commands are
`specification/automation/VERIFICATION_MANIFEST.yml`'s, not a hand-picked subset.

| Command | Output |
| --- | --- |
| `bundle exec rspec` | `1977 examples, 0 failures` |
| `bundle exec brakeman -q --no-pager -z` | `No warnings found` |
| `bin/packwerk check` | `No offenses detected` |
| `bundle exec bundle-audit check --update` | `No vulnerabilities found` |
| `bin/rails zeitwerk:check` | `All is good!` |
| `bin/f1db db:schema:dump && git diff --exit-code db/structure.sql` | no drift |
| `bin/f1db f1:db:verify_runtime` | `OK as f1_web — 15 checks passed (RLS intact)` |
| `bundle exec rspec spec/architecture` | `58 examples, 0 failures` |
| `bundle exec rspec spec/platform/scheduled_actions` | `116 examples, 0 failures` |
| `bin/f1-provision-db f1_test test` | provisioned by structure load (ADR-129); suite green from the rebuilt database |

Two manifest checks could not run: `controller_locking` and `controller_crash_recovery` name spec
directories that have never existed in this repository, so under `fail_on_missing_required_check: true`
they have never run, for any tranche. Pre-existing and unrelated, registered as FU-14. They are named
here without the path-citation form deliberately, because this record's citations are checked for
existence and those paths do not exist.

## Proof standard

A green suite proves nothing about a control the suite never reaches. Every material predicate and state
transition this tranche introduced was reverted or loosened one at a time, and each mutation fails a named
example.

| Mutation | Caught by |
| --- | --- |
| `Workflows::Wf005::Admission#claim_entry` stops verifying that the named entry is the next one | the redelivery example: a superseded pass fetches a second URL under the first's identity |
| the one-paced-host-start-per-pass check is removed | the chain example: the root is recorded `limit_discarded` because discovery had just been polite |
| a halted pass links forward anyway | the wall-clock and fail-closed-robots examples |
| the wall clock no longer gates robots and sitemaps | the expired-run example, which permits NO outbound request |
| a re-entry ignores the instant its result named | the :444 robots-schedule example |
| the terminal transaction stops creating the next-frontier link | four examples across the chain |
| StartCrawl's first handoff is not created | 11 examples across the accepted-start surface |
| the seal-release store drops its `in_progress` source predicate | the unclaimed-entry refusal |
| the compare-and-set is loosened to `>=` | the stale-version refusal |
| the frontier claim no longer returns the post-claim version | the seal-release and depth-advance examples |
| the driver never releases the seal | the depth-advance examples |
| the driver releases on the entry the ACTION named rather than the one admission claimed | the depth-advance examples |
| the driver releases on a superseded pass, stealing another pass's claim | the redelivery example |
| the guard admits `fetched_pending_commit -> terminal`, `queued -> terminal`, or any edge OUT of `terminal` | the edge-matrix example |
| the heartbeat is unfenced on owner, generation, state or an already-lapsed lease | PROOFs 4, 5 and the refusal examples |
| a relinquished delivery settles `completed` instead of releasing its claim | PROOFs 10 and 11 |
| the heartbeat writes the flat caller value | PROOF 23, at 30 seconds — the measured production defect |
| the heartbeat ignores the stored product deadline | PROOF 23, at 60 seconds |
| the outer `least` cap becomes a `greatest` | PROOFs 19 and 23 and the outer-bound check, at 3630 seconds |
| the lease floor returns to 30 seconds | PROOFs 19 and 22 and the document-conformance check |
| the heartbeat may shorten a derived lease to the worker constant | PROOF 23 and the writer-drift check |

Two driver mutations SURVIVED their first round and the examples were strengthened rather than the
mutation waved off. The wall-clock gate survived because the expired-run example started from a host
whose robots and sitemap records were already terminal; an example with robots unresolved and the
outbound facade permitting nothing was added. StartCrawl's empty-selection guard survived and is recorded
as an UNCOVERED guard: the window is a READ COMMITTED visibility race inside one transaction, and
reaching it needs a second connection committing between two statements of one transaction. A comment
claiming it was "asserted rather than assumed" was wrong and was corrected rather than left standing.

**The depth advance is proven end to end**, over the production-real chain, in one example: pass 1
resolves robots and discovers a sitemap naming a content URL and defers; pass 2 fetches the root,
releases the seal, and links to the depth-1 entry the sitemap contributed; pass 3 fetches that URL and
the run drains. Before the seal-release edge existed, pass 3 had nothing it could ever be scheduled for.

## Ownership and follow-ups

**FU-9 is CLOSED BY EXPLICIT TRANSFER, not by completion.** The re-entry it asked for is delivered and
proven: the driver honours the `retry_after` instant the release reports and re-enters the
`run_byte_budget_contended` outcome, and both were unreachable while nothing in production drove crawl
execution. What is NOT delivered is deriving :450's `sitemap_unavailable` for a gate no production path
can terminalize — `Workflows::Wf005::DiscoverSitemaps#defer_to_scheduler?` writes it only once the run has
expired, while `Workflows::Wf005::CrawlDriver#advance` halts on the same wall clock first, with the same
`now`. That obligation is transferred whole to S-07-009 and written into its BUILD_PLAN preconditions, so
the successor reads it where it works rather than in a closed item.

**Resolved by owner ruling:** FU-16 (ADR-085), FU-18 (ADR-087), FU-19 (ADR-089), FU-24 (ADR-091 as
corrected by ADR-092), FU-25 (ADR-094 as completed by ADR-095). FU-10 was delivered at S-07-008.

**NOT DELIVERED, each recorded with its evidence.** FU-11, a terminal Crawl carrying NULL in both
`coverage_status` and `completion_reason`, BLOCKING for S-07-009. FU-21, a terminal frontier entry with no
attempt row, also blocking for S-07-009. FU-22, a stranded frontier claim, whose recovery needs the
`in_progress` analogue of ADR-082's lease sweeper and belongs to S-07-011. FU-20 and FU-23, latent until
:456's concurrent fetching lands. FU-26, :290's authorization/policy checkpoint, an owner decision. FU-27,
an unfenced `defer_robots` compare-and-set in pre-existing S-07-005 code.

**FU-28 IS THE OBLIGATION THIS ACCEPTANCE MOST DELIBERATELY DOES NOT DISCHARGE.** :288 ends "a handler
whose work can legitimately exceed 15 minutes divides it into checkpointed members; no individual claim
exceeds the cap." One `crawl_fetch_due` pass can run 75 minutes: 50 sitemap documents, three attempts
each, ~30 seconds of hop time, before :444's paces. The derived lease does not fix that and was never
claimed to — **the heartbeat is transitional infrastructure and this record does not present ownership
for `crawl_fetch_due` as established by construction.** It is maintained by renewal today. Divided so one
execution performs at most one bounded outbound unit, the derived lease covers a claim by construction
and `Platform::ScheduledActions::LeaseKeeper` and the heartbeat function are deleted rather than
maintained. That is its own tranche because it changes the unit of execution and invalidates accepted
S-07-005 and S-07-006 proofs that assert a full traversal in one call.

**FU-15 remains open**, and not as a formality: the harness contention is BOUNDED, never disproved, and
it recurred under concurrent reviewers with the holder named. **FU-29 remains open** as ADR-095's named
residue.

Still owned elsewhere and deliberately untouched: `commit_order` and `crawl_terminal_outcomes` (S-07-009
and S-07-010), the `fetched_pending_commit` coordinator limb and link extraction (S-07-010), ingestion
(S-07-010), and recovery and replay (S-07-011). FU-17 remains open and is prose, not behaviour: editing a
ratified dispatch registry is not an implementation tranche's to take.
