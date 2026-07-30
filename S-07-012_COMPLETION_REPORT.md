# S-07-012 — Crawl Execution: The Run Driver

**Acceptance status: NOT ACCEPTED.** The ADR-026 five-lens independent review returned four BLOCK
verdicts. Every finding resolvable under existing authority is repaired and committed; ONE
confirmed-blocking finding, FU-19, needs an owner ruling, so no acceptance is recorded (ADR-080: no
acceptance until every lens has reported with zero confirmed-blocking findings).

This record describes HEAD. It does not narrate how HEAD was reached — git holds that, and a
narrative acceptance record accumulates stale counts and superseded mechanisms faster than it can be
corrected. Every claim below is either mechanically checked by
`spec/architecture/repository_truth_spec.rb` or reproducible by the commands in **Verification**.

## Identity

| | |
| --- | --- |
| Block | S-07-012, BUILD_PLAN `Crawl Execution — the run driver (scheduler re-entry for dequeue, fetch and discovery)` |
| Range | from `b48bf6e` (S-07-008 acceptance) to the branch head |
| Authority | standing delegation ADR-061; cadence ADR-086; review discipline ADR-080 |
| Owner rulings implemented | ADR-085 (FU-16), ADR-087 (FU-18), ADR-089 (FU-19) |
| Accepted paths | `app/contexts/identity_access/infrastructure/crawl_budget_store.rb`, `app/contexts/identity_access/infrastructure/crawl_frontier_store.rb`, `app/contexts/identity_access/infrastructure/crawl_host_gate_store.rb`, `app/contexts/identity_access/infrastructure/fetch_attempt_store.rb`, `app/workflows/wf005/`, `config/initializers/scheduled_actions.rb`, `db/migrate/20260727120300_crawl_frontier_seal_release.rb`, `db/structure.sql`, `spec/acceptance/support/wf005_crawl_chain.rb`, `spec/acceptance/wf005_admission_spec.rb`, `spec/acceptance/wf005_content_fetch_spec.rb`, `spec/acceptance/wf005_crawl_frontier_spec.rb`, `spec/acceptance/wf005_limit_observation_points_spec.rb`, `spec/acceptance/wf005_record_fetch_attempt_spec.rb`, `spec/acceptance/wf005_start_crawl_spec.rb`, `spec/persistence/crawl_frontier_invariants_spec.rb`, `specification/automation/AUTONOMY_POLICY.md`, `specification/automation/BUILD_PLAN.yml`, `specification/automation/BUILD_STATE.json`, `DECISIONS.md`, `S-07-012_COMPLETION_REPORT.md` |
| Excluded | 16 files from four unrelated AUTHORIZED commits inside the range, each attributed in `BUILD_STATE.acceptance_evidence` |

**THE PATHS ARE NAMED FILE BY FILE, NOT AS `app/` AND `spec/`.** The range interleaves this tranche
with four unrelated authorized commits, and one of them — the ADR-084 blocking-defect repair that
bounded the shared test-harness PG connections — touches `spec/`. A wholesale `spec/` claim would
have absorbed that repair into this tranche's acceptance, which is exactly the class of false record
the repository-truth spec exists to prevent. The accepted paths and the excluded list partition the
range exactly, and that partition is asserted, not asserted-in-prose.

## What this tranche is

**S-07-004 through S-07-008 built the execution surfaces and NOTHING IN PRODUCTION CALLED ANY OF
THEM.** The only registered entry point was `crawl_dispatch -> StartCrawl`, which seeded the root
frontier and scheduled nothing further. Every claim about a run making progress — including
S-07-008's FU-9 "re-entry" — presupposed a driver that did not exist. This tranche is that driver, and
the frontier seal release without which its own loop could not cross a depth boundary.

## Delivered behaviour

**One `crawl_fetch_due` action is one pass of the run.** BACKGROUND_PROCESSING.md :377 fixes
`crawl_orchestrate` to `StartCrawl` / `CompleteCrawl` / `FailCrawl` / `CancelCrawl` "selected solely
from persisted Crawl/deadline state", so the orchestrator cannot drive the frontier. :378 gives
`crawl_fetch -> RecordFetchAttempt` and "its terminal transaction creates the exact ingestion or
next-frontier action". The run is therefore a CHAIN, not a loop, and the run's own 60-minute wall
clock bounds it: past the deadline no pass links, so a chain cannot outlive its Crawl.

**The action targets the SELECTED FRONTIER ENTRY and admission happens at execution** (ADR-085, the
owner's ruling on FU-16). `Workflows::Wf005::CrawlFetchDueSchedule#link_next` names the entry
`peek_next` selects under the frontier's own advisory lock; it mints no attempt identity, holds no
byte reservation, and does not touch the frontier. The FETCH PATH IS THE SOLE PRODUCER of
`fetch_attempts` rows, and no ScheduledAction anywhere targets a `fetch_attempt`.

**THE SCHEDULER OWNS WAITING; THE WORKER OWNS ONE BOUNDED ATTEMPT** (ADR-089, the owner's ruling on
FU-19, superseding ADR-085's in-process-retry clause). One execution performs at most one attempt. A
retryable outcome with attempts remaining schedules a new `crawl_fetch_due` for the same entry at
`fetch_attempts.completed_at` plus :444's delay and returns; nothing sleeps. :444's three-attempt bound
and its exact 30,000 / 120,000 ms delays are unchanged, the attempt number still comes from committed
state, and the claim, the reservation and the depth seal are held across the retry because they belong
to one admission of one URL. The instant is DERIVED from the committed row rather than taken from the
worker's clock, so two deliveries of one action compute the same ScheduledAction identity and the second
replays instead of forking the run. A retry that would fall past `crawls.deadline_at` is treated as
exhaustion, which releases the reservation and the seal immediately.

**The order of operations is the specification, and two steps of it are not obvious.**

1. **The wall clock, before anything.** :442's "At 60 elapsed minutes, NO NEW REQUEST STARTS" binds
   robots and sitemap documents too, so `Workflows::Wf005::CrawlDriver#within_wall_clock?` is consulted before
   the first of the three rather than only at admission. An expired run makes ZERO requests. The
   decision stays `Workflows::Wf005::Admission`'s, which is the ratified observation point for
   `wall_clock_run_duration` and refuses before it peeks, so nothing is claimed.
2. **Robots.** `Workflows::Wf005::EnsureRobots#call` performs at most one network attempt per call and
   hands its :444 retry schedule back to the caller. Nothing was that caller until now, so a host
   whose robots failed transiently was never resolved. A retryable outcome re-enters at the instant
   the result names; a terminal-but-not-fetchable record halts the pass without discarding the
   candidate, which keeps a genuinely unfetched in-scope URL inside :452's coverage denominator.
3. **Sitemap discovery**, which is FU-9's re-entry. A gate the release handed back is `pending` with a
   `retry_after`, and re-entering at exactly that instant is what stops sustained contention from
   terminalizing `sitemap_unavailable` with zero network attempts.
4. **ONE PASS MAKES AT MOST ONE PACED HOST START.** :442 paces starts over a rolling one-second window
   per canonical host, and discovery claims the same gate a content fetch does. Without
   `Workflows::Wf005::CrawlDriver#host_ready_at` a pass would fetch a sitemap and then have its content
   claim refused in the same second — and `Workflows::Wf005::FetchContent` classifies a refused claim
   as `host_gate_deferred` with `retryable: false`, so the root URL would be recorded
   `limit_discarded` because the run's own discovery had just been polite. The gate publishes the
   exact remaining wait; the pass comes back then.
5. **Admission of the named entry.** `Workflows::Wf005::Admission#claim_entry` claims the NAMED entry
   or nothing, under the same advisory lock and the same peek-pay-claim sequence `claim_next` uses, so
   :456's dequeue-order admission is unchanged. Claiming whatever happened to be next would attribute
   an execution, audit record and result to an entry the pass did not act on, and a redelivery whose
   original claim outlived a lost worker would fetch a second, unrelated URL under the first one's
   identity.
6. **The fetch**, through the accepted `Workflows::Wf005::FetchContent#call`, consuming the reservation
   admission paid for.
7. **The seal release.** `IdentityAccess::Infrastructure::CrawlFrontierStore#terminalize` retires the
   claimed entry, `in_progress -> terminal`.

**A pass that decides nothing re-enters against the same entry and leaves the frontier exactly as it
found it.** Robots still resolving under :444, sitemap discovery handed back by FU-9's release, and
`Admission`'s `run_byte_budget_contended` are all "come back": none is an outcome, none costs the
entry an attempt or the run a byte, and the entry is still `queued` for the next pass to claim.

**A pass that may not start a request creates no link**, which is :442's "stop scheduling affected
work" — a hard byte limit, the wall clock, an authorization denial, or fail-closed robots ends the
chain and the Crawl's terminal checkpoint reports what happened.

**StartCrawl's first handoff** is selection only, in the same transaction as the
`Crawl.Queued -> Crawl.Running` transition. The accepted-start proof is unchanged byte for byte: the
root entry is still `queued`, no `fetch_attempts` row exists, and no budget counter does.

## The frontier seal release

`peek_next` and `claim_next` select at `sealed_depth = MIN(depth)` over
`('queued','in_progress','fetched_pending_commit')`, which is WORKFLOW_SPECIFICATIONS.md :454's "all
depth d discoveries are SEALED before any depth d+1 candidate is SELECTED". Before
`20260727120300_crawl_frontier_seal_release` the guard permitted no edge out of `in_progress`, so a
claimed entry pinned `sealed_depth` at its own depth for the rest of the run. Sitemap discovery admits
content URLs at depth 1 (:440), so a Crawl with any usable sitemap fetched its roots and then stalled
with admitted work queued.

Exactly one edge was added, and the boundaries ADR-087 fixed are each asserted:

- `terminal` is reachable from `in_progress` ONLY.
- The transition is a COMPARE-AND-SET on `(state = 'in_progress', state_version)`, and the version
  comes from Admission's claim rather than a re-read, so the release binds to the claim that
  authorised it. `claim_next` therefore also returns the post-claim version. Zero rows is reported,
  not raised, because the redelivery path is where it happens legitimately.
- `fetched_pending_commit` remains refused as a source, because it is :456's coordinator limb — "a
  completion with a later key waits in `fetched_pending_commit`; it cannot change selection" — and
  arrives with concurrent fetching and link extraction.
- NO edge leaves `terminal`, so a coverage-bearing decision cannot be rewritten.
- `commit_order` stays NULL and `crawl_terminal_outcomes` stays unbuilt: both are the
  coverage/coordinator record and remain S-07-009's and S-07-010's.

**The release is taken in the driver's own transaction, before the ledger and the next link.** The
tidier alternative — retiring the entry inside the handler's terminal transaction, atomically with the
ledger and the link — has the worse failure mode: a process lost between the fetch and the ledger
write would leave the entry `in_progress` forever and PERMANENTLY PIN THE DEPTH, needing a resumption
policy this tranche has no authority to invent. Retiring it first leaves the seal released and no
link, and the redelivery then finds the entry terminal, records `superseded`, and links the run on.
The chain repairs itself; ledger completeness is identical either way, because in both cases the lost
transaction is the one carrying the ledger rows.

## What was REMOVED

ADR-085's ruling required it rather than permitted it. `FetchAttemptDueSchedule`,
`IdentityAccess::Infrastructure::FetchAttemptStore`'s `prepare` / `claim_prepared` /
`submission_started` / `find_by_identity`, and `Workflows::Wf005::FetchContent`'s
`record_persisted_attempt` limb existed only to make a PRE-CREATED attempt executable. Retaining them
beside the delivered shape would have been the second producer of `fetch_attempts` the ruling forbids.
Four dead private methods in `FetchContent` went with them, one of which referenced a column
`fetch_attempts` does not carry and would have raised if it had ever been called.

## Schema changes

One migration, `20260727120300_crawl_frontier_seal_release`, which redefines
`f1_crawl_frontier_entries_guard` to add `in_progress -> terminal` and re-emits every other limb
byte-identically: the identity and provenance freeze, the single-step `state_version` rule, the
write-once discard reason, and the position freeze. Additive; no column, index, constraint or grant
changed; forced RLS untouched. `db/structure.sql`'s diff is the one edge, its comment, and the
migration row. The schema builds FROM EMPTY through `bin/f1-provision-db`, and reversibility was
exercised down and up.

`schemas/POSTGRESQL_SCHEMA.md` needs no change: its `crawl_frontier_entries` row documents the state
CHECK, which already declared `terminal`, and it does not enumerate guard edges.

## Verification

Run from the repository root. Outputs are those observed at this commit. The commands are
`specification/automation/VERIFICATION_MANIFEST.yml`'s, not a hand-picked subset.

| Command | Output |
| --- | --- |
| `bundle exec rspec` | `1926 examples, 0 failures` |
| `bundle exec brakeman -q --no-pager -z` | `No warnings found` |
| `bin/packwerk check` | `No offenses detected` |
| `bundle exec bundle-audit check --update` | `No vulnerabilities found` |
| `bin/rails zeitwerk:check` | `All is good!` |
| `bin/f1db db:schema:dump && git diff --exit-code db/structure.sql` | no drift |
| `bin/f1db f1:db:verify_runtime` | `OK as f1_web — 15 checks passed (RLS intact)` |
| `bundle exec rspec spec/architecture` | `52 examples, 0 failures` |
| `bundle exec rspec spec/automation/{unit,integration,policy,end_to_end}` | `33/0, 20/0, 21/0, 10/0` |
| `bundle exec rspec spec/platform/scheduled_actions` | `85 examples, 0 failures` |
| `bin/f1-provision-db f1_test test` | provisioned from empty; suite green from the rebuilt database |

Two manifest checks could not run: `controller_locking` and `controller_crash_recovery` name spec
directories that have never existed in this repository, so under `fail_on_missing_required_check: true`
they have never run, for any tranche. Pre-existing and unrelated, registered as FU-14. They are named
here without the path-citation form deliberately, because this record's citations are checked for
existence and these paths do not exist.

## Proof standard

A green suite proves nothing about a control the suite never reaches. Every material predicate and
state transition this tranche introduced was reverted or loosened one at a time, and each mutation
fails a named example:

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
| `claim_next` no longer returns the post-claim version | the seal-release and depth-advance examples |
| the driver never releases the seal | the depth-advance examples |
| the driver releases on the entry the ACTION named rather than the one admission claimed | the depth-advance examples |
| the driver releases on a superseded pass, stealing another pass's claim | the redelivery example |
| the guard admits `fetched_pending_commit -> terminal` | the edge-matrix example |
| the guard admits `queued -> terminal` | the edge-matrix example |
| the guard permits any edge OUT of `terminal` | the edge-matrix example |

Two of those mutations SURVIVED their first round and the examples were strengthened rather than the
mutation waved off. The wall-clock gate survived because the expired-run example started from a host
whose robots and sitemap records were already terminal, so it proved the limit decision and not the
absence of requests; an example with robots unresolved and the outbound facade permitting nothing was
added. StartCrawl's empty-selection guard survived, and it is now recorded as an UNCOVERED guard —
the window is a READ COMMITTED visibility race inside one transaction, between the gate's
`active_pinned_sources` read and `peek_next`'s own re-read of `sources.state`, and reaching it needs a
second connection committing between two statements of one transaction. A comment that claimed it was
"asserted rather than assumed" was wrong and was corrected rather than left standing.

**The depth advance is proven end to end**, over the production-real chain, in one example: pass 1
resolves robots and discovers a sitemap naming a content URL and defers; pass 2 fetches the root,
releases the seal, and links to the depth-1 entry the sitemap contributed; pass 3 fetches that URL and
the run drains. Before the seal-release edge existed, pass 3 had nothing it could ever be scheduled
for.

## What the five-lens review found, and what it changed

Four of five lenses returned BLOCK. The two most serious findings were not polish.

**The pass egressed before it was authorized.** The driver's first effects — a `crawl_host_gates` row,
a robots request, and the write-once sitemap outcome — all preceded the run-scoped authorization gate,
which lived inside `claim_entry`. Proven twice: with the Organization suspended and again with the
entitlement lease lapsed, a pass sent `/robots.txt` to the customer's host and then wrote
`sitemap_unavailable`, which is write-once, so :450/:452 made that Source root's coverage permanently
partial on the strength of our own authorization failure. `Workflows::Wf005::Admission#authorize_run`
is now step zero, before any effect.

**The byte reservation leaked on exhausted retries**, found independently by three lenses.
`attempt_loop` exited via `break if number >= MAX_ATTEMPTS` still holding the whole reservation, and
nothing reclaimed it — so ~125 exhausted URLs falsely exhausted a run and fired an immutable
customer-visible hard limit for a Crawl that received no body bytes. It now releases what it abandons.

**Robots fail-closed halted the whole run**, against :448's "for that host" and :452's "that Source
root". It now retires its own entry through the edge this tranche built and the run reaches the healthy
Source.

**`frontier_drained` could be false**, because `peek_next` returns nil both for a drained frontier and
for one pinned by a stranded claim. The payload now distinguishes them.

Eight further findings were repaired: an unreachable `host.nil?` guard that would have passed `""` to
`https:///robots.txt`; `terminalize` now names the Organization so isolation is local to the statement;
the sitemap deferral uses the relative pacing remainder rather than the gate's absolute instant, which
under clock skew made the re-entry a fixed point whose identity replayed the action that just ran;
`link_next` peeks under the frontier lock; links are clamped to the run deadline; `admission_reason`
fails closed rather than discarding an admitted claim; the duplicated pacing SQL has one definition;
`retain_until` matches the rest of the platform.

**A defect the mutation round caught in the repair itself.** `unfinished?` first read its boolean with
`== "t"`, which is always false on a type-mapped connection — so the pinned check silently did nothing,
which is exactly the failure it had been added to stop. `Platform::PgBool` now owns both encodings.

## Ownership and follow-ups

FU-9 (sitemap scheduler re-entry) is DELIVERED here: the driver honours the `retry_after` instant the
release reports and re-enters `Admission`'s `run_byte_budget_contended` outcome, and both were
unreachable while nothing in production drove crawl execution. FU-10 was delivered at S-07-008 and is
unchanged. FU-16 and FU-18 are resolved by ADR-085 and ADR-087.

NOT DELIVERED, and each recorded with its evidence: FU-19, a fetch pass outliving its 30-second
transport lease so the ordinary retry path executes twice — the one finding that needs an owner ruling,
because both repairs lie outside this tranche's authority. FU-21, a terminal frontier entry with no
attempt row, blocking for S-07-009 alongside FU-11. FU-22, a stranded frontier claim, whose recovery
needs the `in_progress` analogue of ADR-082's lease sweeper and belongs to S-07-011. FU-20 and FU-23,
latent until :456's concurrent fetching lands. ADR-088 corrects two justifications this tranche's own
ADRs recorded wrongly.

FU-17 remains open and is prose, not behaviour: BACKGROUND_PROCESSING.md's dispatch registry still
names a Fetch Attempt as `crawl_fetch_due`'s claim owner, while ADR-085 makes it the frontier entry.
Editing a ratified document is not an implementation tranche's to take.

Still owned elsewhere and deliberately untouched: `commit_order` and `crawl_terminal_outcomes`
(S-07-009 and S-07-010), the `fetched_pending_commit` coordinator limb and link extraction (S-07-010),
ingestion (S-07-010), and recovery and replay (S-07-011). FU-11 remains BLOCKING for S-07-009. FU-15
remains open: the harness hang is bounded, not disproved.
