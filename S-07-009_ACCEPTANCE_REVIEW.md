# S-07-009 — ADR-080 Acceptance Review: NOT ACCEPTED

> **ROUND 2 HAS NOW RUN AND ALSO FAILS. See [ROUND 2](#round-2--the-repaired-candidate-7f043a295d37f4)
> at the foot of this file.** Three confirmed-blocking findings, two of them defects in the round-1
> repairs themselves: **B7 is not closed** (the same corrupt terminal state reproduced 3/3 against the
> repaired candidate), the B2 repair **introduced** a new wrong coverage verdict, and B6's correction
> missed a fifth place. **S-07-009 REMAINS NOT ACCEPTED.**

---

## ROUND 1 — the original candidate `7f043a2..a414f5c`

Candidate: `7f043a2..a414f5c` (nine commits, "S-07-009 (1/n)".."(9/n)") on `implementation/s01-registration-access`.
Round run: 2026-07-31, on owner instruction, full ADR-026 five-lens form, deliberately NOT narrowed.
Gates at the candidate: rspec 2040/0, brakeman 0, packwerk clean, zeitwerk ok, verify_runtime 15/15, no structure drift.

**VERDICT: FAIL-WITH-FINDINGS. Eleven confirmed-blocking findings. S-07-009 IS NOT ACCEPTED.**

> **REPAIR STATUS (2026-07-31): ALL ELEVEN REPAIRED; ROUND 2 THEN RAN AND CLOSED NINE OF THEM.**
> B7 → ADR-105; B8 → ADR-106; B1, B2 → ADR-107; B9 → ADR-108; B10 → ADR-109; B3, B4, B5 → ADR-110;
> B6, B11 → ADR-111. Each carries a proof that fails under a mutation of its own repair, and round 2
> independently re-ran all fourteen of those mutations: every one kills its named proof. **Round 2
> nevertheless closes only nine of the eleven** — B7 and B6 are re-opened below, and the B2 repair is
> itself defective. The 24 non-blocking observations are NOT repaired and remain open.

All five lenses returned FAIL. Three findings were reached independently by two or three lenses from
different mandates, which is the strongest signal this round produced.

| Lens | Verdict | Blocking |
| --- | --- | --- |
| Contract-correctness | FAIL | 4 (B1, B2, B3, B4) |
| Concurrency / atomicity / idempotency | FAIL | 2 (B7, B8) |
| Security / tenant-isolation | FAIL | 1 (B1, converged) |
| Schema / migration-safety | FAIL | 2 (B5 converged, B6) |
| Architecture / scope / test-quality | FAIL | 4 (B5 converged, B9, B10, B11) |

**The owner's ruling is vindicated by the result.** Every one of the eleven lives at a boundary between
components or between the code and its record. A review narrowed to the three areas named before the
round would have found at most two of them, and would have missed B7 entirely.

---

## CONFIRMED-BLOCKING

### B1 — :458's third sentence is unimplemented: a cancellation after the wall clock still wins
*Found independently by the SECURITY and CONTRACT lenses.*

:458 has three sentences about the boundary; the implementation carries two. The third reads: "**At
exactly the 60-minute boundary the wall-clock terminal handler wins over a simultaneous cancellation.**"
`Handlers::CancelCrawl` never reads `crawl["deadline_at"]`, which `lock_crawl` returns to it
(`app/workflows/wf005/handlers/cancel_crawl.rb:98-115`), so the boundary is decided purely by which
transaction takes the row lock first.

Probed live: a run aged past its deadline, then the real `CancelCrawl` at `deadline_at + 60s` →
`success=true state=canceled entitlement=released`.

**Consequence.** A `crawl.cancel` holder can let a run consume its full sixty minutes of work and then
cancel before the checkpoint action is delivered, taking :551's *release* limb instead of
`crawl_completed_with_valid_document`. A repeatable metering escape available to an ordinary
MarketingOperator. :551 ratifies release for a cancellation *before* the commit point; :458 is what stops
the principal choosing that after the clock has decided.

**Repair.** In `CancelCrawl#process`, after the terminal-state limb, refuse when `deadline_at` is present
and `now >= deadline_at`, with :458's own `crawl_already_terminal`. `>=`, not `>`. Correct ADR-102 and the
handler header, both of which quote :458 and stop at the second full stop.

### B2 — a run terminalized BY its own wall clock records no wall-clock limit at all
*CONTRACT lens.*

The deadline delivery arrives with `now == due_at == crawls.deadline_at` by construction, but
`CompleteCrawl#checkpoint` never compares them, and `terminal_facts` counts only `crawl_limit_decisions`
rows some *pass* already wrote. In the exact case the deadline action exists for — FU-22's pinned run,
where no pass ever arrives after the deadline — nothing records the crossing.

Demonstrated on the real chain: `completion_reason="partial_source_failure" hard_limits=0`, zero limit
decisions, zero `CrawlLimitReached`, and the unevaluated entry carrying `reason = nil`. :458 requires
"any in-scope candidate not evaluated because of … wall-clock bound makes coverage partial **and records
its exact limit reason**".

**Repair.** Before `count_facts`, when the locked Crawl is `running` and `now >= deadline_at`, record the
`wall_clock_run_duration` hard crossing through the existing `Wf005::LimitDecisions` observer, whose
`UNIQUE (crawl_id, limit_dimension, threshold_kind)` makes it idempotent against a pass that already did.

### B3 — `CrawlFailed` / `CrawlCanceled` omit the reason the catalogue requires, and two producers disagree
*CONTRACT lens.*

API_CONTRACTS :808 gives both events reason source `transition`; :938 requires root `reason_code` to equal
the retained `transition_reason_code` exactly when the source is `transition`. Both terminal envelopes
hard-code `reason_code: nil` and supply no `transition_reason_code`
(`complete_crawl.rb:350` + `:181-183`; `crawl_ledger.rb:65` + `cancel_crawl.rb:152-156`).

Decisively, WF-005's **own** pre-execution `CrawlFailed` at `start_crawl.rb:435` **does** set it. Two
producers of one event type now disagree, and `crawl_start_store.rb:112-114` asserts the machine reason
"is retained where the contract puts it — the `CrawlFailed` envelope". It is not.

**Repair.** Merge `reason_code` and `transition_reason_code` (the completion reason) into both terminal
envelopes; `CrawlCompleted` correctly stays null, its source being `none`.

### B4 — `accepted_document_count` is absent from every `crawl_terminal` envelope
*CONTRACT lens.*

API_CONTRACTS :956 defines the `crawl_terminal` extra schema as three members: `coverage_status`,
`completion_reason`, **and `accepted_document_count: uint53`**. `grep` over the repository returns nothing.
The value is computed two lines before the envelope is built (`facts.documents`) and discarded.

Scope, stated honestly: `CrawlQueued` and `CrawlStarted` carry the same profile and also omit it, and both
predate this range. This block owns the two events for which the member is non-zero.

**Repair.** Add it to the two terminal envelopes. Record the two pre-existing omissions as a follow-up
rather than editing accepted blocks inside an acceptance round.

### B5 — `crawl_terminal_outcomes.source_id` has no foreign key, and PROOF 39 is structurally blind to it
*Found independently by the SCHEMA, SECURITY and ARCHITECTURE lenses.*

The migration declares `source_id uuid NOT NULL`, constrains `crawl_id` and `crawl_frontier_entry_id`, and
omits the third link — under a comment invoking :128 and FU-7 by name ("violated silently three times; it
is easier to satisfy than to detect"). It is the only table in the schema carrying `source_id` without an
FK; nine siblings have one. Probed as `f1_web`: a cross-Project `source_id` and a wholly fabricated UUID
were both admitted.

**The proof written to catch this cannot see it.** PROOF 39 enumerates `pg_constraint … contype='f'` and
asserts arity 3 on each row returned. An absent FK has no arity. It passes on two 3-column FKs, and its
own title — "so coverage cannot cross a Project" — is false.

**Repair.** Add the composite FK. Rewrite PROOF 39 to assert the expected link **set** (each Project-owned
parent column is covered by an arity-3 FK), not the shape of whichever links happen to exist.

### B6 — the "proven no-op" refutation ratified in four places is itself false
*SCHEMA lens.*

ADR-097, the migration header, `POSTGRESQL_SCHEMA.md:294`, the FU-11 note and the PROOF 29 comment all
state that the `IS NOT DISTINCT FROM` rewrite of `crawls_coverage_status_check` "yields TRUE" and is a
"proven no-op, evaluated against the live cluster". Evaluated live:

```
NULL = ANY(ARRAY['full','partial'])                 -> UNKNOWN   (a CHECK admits)      as claimed
NULL IS NOT DISTINCT FROM 'full' OR ... 'partial'   -> false     (a CHECK REFUSES)     NOT as claimed
NULL IS NULL OR NULL = ANY(ARRAY[...])              -> true      (what PROOF 29 tests)
NULL IS NOT DISTINCT FROM ANY(ARRAY[...])           -> syntax error
```

The form as named does not parse; its only valid spelling would **refuse every `queued` and `running`
Crawl** — a breaking change, the opposite of a no-op. That record exists precisely to stop a future
implementer applying the wrong fix, and it tells them the wrong fix is harmless. The substantive
conclusion (the fault was `crawls_terminal_shape`) is unaffected and was re-verified.

**Repair.** Correct all four places to name the form PROOF 29 actually evaluates, or state the
`IS NOT DISTINCT FROM` result correctly.

### B7 — the checkpoint and the driver's retirement are not ordered: a covered run is recorded `failed`, unrecoverably
*CONCURRENCY lens. The most serious finding of the round.*

`CompleteCrawl` serializes on `crawls FOR UPDATE`; `CrawlDriver#retire` serializes on the
`crawl-frontier:<crawl>` advisory lock. Nothing orders the two, so `terminal_facts` counts a snapshot an
in-flight pass invalidates a moment later.

Observed state, identically in three reproductions:

```
crawls                  : state=failed  completion_reason=failed  coverage_status=NULL
checkpoint payload      : documents:0  source_roots_succeeded:0  entitlement_outcome:"released"
crawl_terminal_outcomes : [document_created, covered, commit_order 1]
fetch_attempts          : [document_created, 200]
entitlement_reservations: released / crawl_terminal_without_durable_output
```

Reproduced (a) forced with a trigger gate, (b) driven by the **production** `crawl_terminal_deadline`
action at its own due instant, and (c) **at natural timing with no gate at all — a 150 ms fetch with the
checkpoint fired 50 ms in, 10/10.**

**It is unrecoverable.** The terminal freeze added in (4/n) raises `crawl_terminal_immutable` on any UPDATE
of a terminal row, so nothing can ever correct it. Two things introduced in this block combine into a
permanent wrong answer about a customer's run and their billing. ADR-101's drained-run checkpoint makes
checkpoint-concurrent-with-pass the ordinary case rather than an exotic one.

**Repair — and NOT the one the lens proposed.** The lens suggests `retire` take the `crawls` row lock
before `lock_frontier`. That inverts the order this subsystem established: `Admission#claim` takes the
frontier advisory lock and then writes `crawl_budget_counters`, which carries an FK to `crawls` and so
takes `FOR KEY SHARE` on that row; `retire` does the same via the outcome row's FK. The correct repair is
the mirror: **the checkpoint takes `lock_frontier` first, then `crawls FOR UPDATE`** — the same order as
every other party, no inversion, and it fences every in-flight retirement because `retire` holds that
advisory lock for its whole transaction. The lens's own RACE 8 is the supporting evidence: once the
outcome INSERT has run, the FK's key-share lock already blocks the checkpoint, which then counts
correctly. The gap is only the window before that INSERT, and the frontier lock closes it.

### B8 — the heartbeat's cadence read is unlocked: an exception out of the workflow, or a triple renewal
*CONCURRENCY lens.*

`CrawlDriver#renew_entitlement_lease` reads the reservation with a plain SELECT, decides `heartbeat_due?`,
then calls `Service#heartbeat`, which locks and re-reads but never re-checks the cadence. Reproduced
through the real handler with two deliveries of one `crawl_fetch_due` — which `crawl_start_store.rb:413`
itself calls ordinary:

- loser's clock earlier → `PG::CheckViolation … entitlement_lease_heartbeats_advances`, unhandled, out of
  the workflow;
- loser's clock later → **three heartbeat rows inside one five-minute window**, refuting the comment
  claiming "two deliveries of one action compute the same answer".

**Repair.** Take `Entitlement::Store#lock_reservation` before reading `last_heartbeat_at`, so the cadence
decision and the heartbeat are made under one lock. No change to frozen F-05.

### B9 — the three counted facts that decide the coverage number are load-bearing in no example
*ARCHITECTURE / TEST-QUALITY lens.*

Mutations applied to `count_facts`, each run against all 11 WF-005 spec files (218 examples):

| mutation | result |
| --- | --- |
| `uncovered → 0` | **218 / 0** |
| `fetch_failures → 0` | **218 / 0** |
| `hard_limits → 0` | **218 / 0** |

`uncovered` is :458's coverage denominator; zeroing it turns `partial` into `full`, the single error
direction `CoverageClassification`'s own header says it exists to prevent. No example in the range ever
produces a `content_fetch_failed` outcome that reaches the checkpoint, and **`completion_reason =
'limit_reached'` is never written to a real `crawls` row anywhere in the suite** — it exists only inside
the pure-function spec, which hands the fact in by hand.

This is the repository's institutionalised failure mode restated: the derivation is proved exhaustively as
a pure function, and the SQL supplying its inputs — the part that can be wrong — has no behavioural anchor.

**Repair.** Three acceptance examples on the real chain: a run with a `content_fetch_failed` outcome; a run
that trips a hard limit before its checkpoint (`limit_reached` + `partial`); a run whose only defect is a
`not_covered` outcome. Each must fail under the corresponding zeroing.

### B10 — the `FOR UPDATE` that two ADRs make load-bearing has no proof of any kind
*ARCHITECTURE / TEST-QUALITY lens.*

Deleting `FOR UPDATE` from `CrawlStartStore#lock_crawl` → **218 examples, 0 failures.** ADR-101 and ADR-102
both rest their central claim on it. PROOF 64 and PROOF 82 are sequential; PROOF 65 mutates the row first.

The failure mode if it is ever lost is the exact defect class ADR-103 was written one commit earlier to
repair: both terminal handlers raise `Platform::InvariantViolation` on a lost compare-and-set, so a
cancellation losing to a concurrent checkpoint would surface as an invariant failure instead of :458's
`crawl_already_terminal`.

**Repair.** One `RaceHarness.interleave` example gating `CompleteCrawl`'s first `command_executions` INSERT
with a `CancelCrawl` committing underneath, and its mirror. Must assert the loser reports
`crawl_already_terminal`, and must fail when `FOR UPDATE` is removed.

### B11 — `BUILD_STATE.next_action` contradicts the same file's `open_decisions`
*ARCHITECTURE / TEST-QUALITY lens.*

`open_decisions[FU-30].status == "resolved"`; `next_action` says twice that FU-30 is "deliberately
deferred" and "STAYING OPEN". It also says "seven commits" against nine, and omits ADR-103, ADR-104 and
FU-32. `next_action` is what the controller reads, and it currently describes the block as it stood at
commit 7/n.

**Repair.** Rewrite `next_action` for the nine-commit state. (Corrected in this commit.)

---

## NON-BLOCKING OBSERVATIONS CARRIED FORWARD

Recorded here so none is lost; several are corrections to this block's own record.

1. **The FU-9 comment's reasoning is unsound in one limb** (CONTRACT). `complete_crawl.rb:201-215` argues
   :450's `unavailable` premise "is satisfied for the run as a whole"; that establishes only the second
   conjunct. For a gate where robots declared no `Sitemap:` location, :450 authorises neither outcome on
   the facts the checkpoint holds. Error direction is coverage-conservative, hence non-blocking, but the
   reasoning must not stand as recorded. `pending_sitemap_gates` even selects `sitemap_candidates` and
   never reads it.
2. **FU-9's obligation is silently abandoned on a lost compare-and-set** (CONCURRENCY). `next false`
   swallows a `begin_sitemaps` refusal — no retry, no escalation — leaving a gate `pending` for ever on a
   frozen terminal Crawl and under-reporting `unresolved_discovery`, which pushes coverage in the one
   direction `terminal_selection.rb:105` says must never happen.
3. **The checkpoint's claim erases the candidate list it exists to record** (CONCURRENCY).
   `begin_sitemaps(..., [], [], token)` blanks `sitemap_candidates` and `sitemap_discarded`, so :450's
   "every skipped or failed candidate is RECORDED" is unmet.
4. **ADR-101's second checkpoint instant is a genuine widening of two catalogue sentences** (CONTRACT).
   Defensible — there is no ratified action kind for "the run drained early, terminalize now", and the
   block chose the kind whose work type and operation set are correct — but it should be closed by a
   ratified `BACKGROUND_PROCESSING` amendment, not by code.
5. **ADR-102 overclaims its permission mutation** (ARCHITECTURE). Widening `crawl.cancel` to
   `SecurityOperator` + `ContentEditor` → 218/0. Only `TechnicalImplementer` fails PROOF 84, because that
   is the role PROOF 84 seeds. One of :147's four deny cells is proven.
6. **ADR-101's PINNED-frontier exclusion is unenforced** (ARCHITECTURE). Relaxing the guard so a pinned
   frontier also mints a drained checkpoint → 218/0. This is the boundary the ADR says exists so S-07-011's
   recovery is not foreclosed; a future edit can cross it silently.
7. **Three assertions are true by construction** (ARCHITECTURE). PROOF 64's `state_version` comparison is
   `x == x`; PROOF 78 duplicates PROOF 76 and asserts nothing about exclusion (`Facts` has no `excluded`
   field); PROOF 73's condition is already decided by the `roots_succeeded.zero?` limb.
8. **`CrawlTerminalOutcomeStore#outcomes` is dead code with a false comment** (ARCHITECTURE).
9. **`POSTGRESQL_SCHEMA.md` :294-295 splits the canonical table** (SCHEMA + ARCHITECTURE). The two
   blockquotes sit between the `crawls` row and `crawl_sources`, so ~25 rows render as literal pipe text.
10. **`crawls_terminal_shape` is one-directional on coverage** (SCHEMA): a `failed` or `canceled` Crawl may
    carry `coverage_status`. Nothing writes it; the same shape FU-11 was about, left open the other way.
11. **The run-clock freeze is conditional on a column nothing requires** (SCHEMA). Scoped on
    `OLD.started_at IS NOT NULL`, and no constraint requires `started_at` when `state='running'`. ADR-104's
    "neither column may move again by any route" is stronger than the schema. Repair:
    `CHECK (state = 'queued' OR started_at IS NOT NULL)`.
12. **Nothing ties `crawl_terminal_outcomes.crawl_id` to its frontier entry's `crawl_id`** (SCHEMA).
13. **`reason_presence` is satisfied by the empty string** (SCHEMA); closed app-side only.
14. **`unevaluated`'s `AND e.reason IS NOT NULL` conjunct is a proven no-op** (SCHEMA) — the discard-reason
    biconditional already guarantees it.
15. **`commit_order`'s per-Crawl scoping is unpinned** (ARCHITECTURE): scoping it per-Organization → 218/0.
16. **`Entitlement::Service#expire` still has no caller anywhere** (CONCURRENCY). Pre-existing F-05 gap,
    now load-bearing because this block makes the checkpoint the sole settler of a `crawl.start`
    reservation.
17. **FU-2 / FU-1 disclosure missing on the new baseline row** (SECURITY). Both neighbouring entries carry
    the ADR-063 deferral sentence; `crawl.cancel` does not. Probes confirmed both deferrals apply to it.
18. **`:527`'s durable commit point is met by a proxy that charges the customer** (CONTRACT). No FU
    currently carries S-07-010's obligation to re-derive `documents` from the artifact by name. One is
    needed.
19. **`:551`'s "at least every 5 minutes" can be exceeded** (CONTRACT): the cadence is 300 s evaluated only
    when a pass runs, so the worst case is 300 s plus the inter-pass gap.
20. **`TerminalSelection::Facts#failed?` treats `roots_total.zero?` as failure** (CONTRACT) — reachable if
    every Source is disabled mid-run, and it releases the reservation on a run that produced Documents.
21. **Two accepted examples changed; one is stronger, one is a trade** (ARCHITECTURE). The queue-crawl
    replacement was verified stronger under two mutations. The limit-decisions replacement dropped `.sole`,
    which was also asserting "exactly one decision row of any dimension"; disclosed in ADR-104, but a trade.
22. **Uncovered paths**: 15 enumerated by the architecture lens, including every fail-closed branch of both
    new handlers (`schema_failure`, `target_type` mismatch, unknown Organization, absent Crawl,
    `idempotency_conflict`, `crawl_not_running`) — all of which the accepted precedent in the same workflow
    does cover — plus both refusal limbs of `resolve_pending_sitemaps`.
23. **FU-15 is live and cost this round real time** (all lenses). Concurrent suites against the shared
    `f1_test` produced 614, 895 and 1175 spurious failures; two lenses had to provision isolated databases.
    `race_harness` leaving connections `idle in transaction` compounds it.
24. **`bin/rubocop` is red repo-wide (4008 of 4034 offences are one layout cop)** (ARCHITECTURE);
    this block contributes 6, all in specs.

---

## WHAT THE ROUND CONFIRMED SOUND

Recorded so the review's coverage is visible, not only its output.

- `f1_crawls_guard`'s full 5×5 state cross-product against the live trigger is exactly :736's edge set and
  nothing else; every freeze-evasion probe refused with the correct reason code; `f1_runtime` holds no
  TRUNCATE, no DELETE and no ownership.
- `crawl_terminal_outcomes`' full 6×3 outcome × effect cross-product: exactly the six legal pairs admitted,
  all twelve illegal pairs refused. T-IMM, forced RLS and the `SELECT, INSERT`-only grant matrix all hold
  as `f1_web`.
- Reversibility: all four migrations down and up one at a time, catalogue byte-identical to baseline
  afterwards; `structure.sql` shows no drift; the structure loaded into a fresh database matches live.
- `terminal_facts`' seven subqueries verified against hand-inserted rows including a full mirror population
  under a second Organization: every count matches its comment, `roots_succeeded` cannot exceed
  `roots_total`, `unevaluated` does not double-count, and no subquery ignores tenancy.
- Two concurrent checkpoints resolve to one `CrawlCompleted` and one commit intent; checkpoint versus
  cancel resolves correctly in **both** orders; `commit_order` genuinely blocks and can neither collide nor
  skip; two StartCrawl deliveries produce exactly one of everything.
- ADR-103's repair holds under independent race: the losing attempt's reservation, Decision and execution
  row genuinely roll back, and the denial is written against the winner's committed state. The PROOF 88/89
  gate was verified genuine — neutralising it makes both proofs fail loudly rather than degrade.
- Cross-tenant probes at the command: three parameter combinations from a foreign session all
  `tenant_mismatch`, zero ledger rows written into the other tenant.
- Scope is clean: no S-07-010 or S-07-011 pull-forward, no package boundary crossed, and 34 of 51 mutations
  applied by the test-quality lens failed their named examples as claimed.
- `age_run_to` is faithful and fails loudly: forcing the heartbeat to report `:lease_expired` produces six
  failures rather than silent passage.

---

## LENS MARGINAL CONTRIBUTION — round 1 of the measure

Recorded on owner instruction. The question worth tracking is not how many blockers a round finds, but
**how much each lens contributes that no other lens would have**. Over five or ten rounds this says whether
a lens is paying for itself; on one round it says almost nothing, and is recorded to start the series.

| Lens | Blockers unique | Blockers joint | Blocker total | Observations unique |
| --- | --- | --- | --- | --- |
| Contract-correctness | 3 (B2, B3, B4) | 1 (B1) | 4 | 6 |
| Architecture / test-quality | 3 (B9, B10, B11) | 1 (B5) | 4 | 9 |
| Concurrency | 2 (B7, B8) | 0 | 2 | 5 |
| Schema / migration | 1 (B6) | 1 (B5) | 2 | 11 |
| Security / tenancy | 0 | 2 (B1, B5) | 2 | 6 |

Round totals: 11 blockers — **9 found by exactly one lens (81.8%), 1 by two, 1 by three, none by four or
five.** 24 de-duplicated observations, 1 of them joint.

**Low convergence is the good reading, and it inverts the naive one.** 18% blocker convergence means the
lenses are largely orthogonal and all five are earning their place. Sustained 60-80% convergence across
rounds would be the signal that two lenses express one underlying concern and the round is buying less
than it costs.

**THE SECURITY LENS SCORED ZERO UNIQUE BLOCKERS AND MUST NOT BE READ AS THE WEAKEST.** It found B1
independently of the contract lens, and it was the ONLY lens to establish B1's *consequence* — that the
missing sentence is a repeatable metering escape available to an ordinary MarketingOperator, who can let a
run consume its full sixty minutes and then cancel before the checkpoint fires to take :551's release limb.
The contract lens found the same omission and correctly classified it as a contract gap. What made it a
release blocker was the security characterisation. **Marginal contribution is therefore not only "who found
it first" but "who established why it matters", and a metric that counts only discovery will eventually
retire a lens that is doing the second job.** Record both.

**Method note for future rounds.** This table was computable only because the non-blocking list below
carries a lens tag per item. Preserve that attribution when consolidating; a round that merges findings
without provenance destroys the measure it is supposed to feed.

## REPAIR PROGRAMME, IN DEPENDENCY ORDER

1. **B7** (checkpoint/retire lock order) — highest severity, unrecoverable, ordinary timing.
2. **B8** (heartbeat cadence under lock) — exception on an anticipated path.
3. **B1** (:458's third sentence) + **B2** (wall-clock limit at the checkpoint) — both touch the same
   `deadline_at` comparison the checkpoint and the cancel path each need.
4. **B9** + **B10** — the missing behavioural anchors. Taking these before 5 and 6 means the remaining
   repairs land against tests that can actually fail.
5. **B3**, **B4** (envelope contract), **B5** (the FK and PROOF 39's rewrite).
6. **B6**, **B11** (record corrections), then the non-blocking set.

Re-run the full five-lens round against the repaired candidate. ADR-080 exists because a block was once
accepted on four lenses while the fifth was still working; this round found eleven blockers on a candidate
whose suite was 2040/0, which is the same lesson again.

---

# ROUND 2 — the repaired candidate `7f043a2..95d37f4`

Candidate: `7f043a2..95d37f4` (nine implementation commits plus six repair commits `5672fc5..95d37f4`)
on `implementation/s01-registration-access`.
Round run: 2026-07-31, full ADR-026 five-lens form against the complete range, by a reviewer with no
share in the repairs and no prior conversational state. Not narrowed to the repairs: the whole block
was re-reviewed, because a repair is a change and a change is candidate material.

Gates at the candidate (all re-run from this reviewed state, results in full below): rspec **2055/0**,
brakeman 0, packwerk clean, zeitwerk ok, bundler-audit clean, verify_runtime OK 15 checks (RLS intact),
architecture fitness 58/0, no `structure.sql` drift, **schema builds from empty byte-identical**, all
five migrations reverse and re-apply byte-identical.

**VERDICT: FAIL-WITH-FINDINGS. Three confirmed-blocking findings. S-07-009 IS NOT ACCEPTED.**

| Lens | Verdict | Blocking |
| --- | --- | --- |
| Contract-correctness | FAIL | 2 (R2-B2 unique, R2-B1 converged) |
| Concurrency / atomicity / idempotency | FAIL | 1 (R2-B1 unique discovery) |
| Schema / migration-safety | FAIL | 1 (R2-B3 unique) |
| Architecture / scope / test-quality | FAIL | 2 (R2-B2, R2-B3 both converged) |
| Security / tenant-isolation | FAIL | 1 (R2-B1 converged; established the metering-integrity half) |

**A GREEN SUITE IS AGAIN NOT EVIDENCE.** The candidate is 2055/0 and every one of the fourteen
mutations the repair ADRs name kills its named proof — and two of the eleven round-1 blockers are
still live at HEAD, one of them reproduced three times out of three. The lesson ADR-080 records and
round 1 demonstrated is demonstrated a third time, now from inside the repair programme itself.

---

## ROUND 2 CONFIRMED-BLOCKING

### R2-B1 — B7 IS NOT CLOSED. The checkpoint still counts a snapshot an in-flight pass invalidates, and the run is still recorded `failed` with a Document in the record
*Found by the CONCURRENCY lens. Converged with CONTRACT (the ratified sentence whose absence makes it reachable) and SECURITY (the metering half).*

ADR-105 repaired B7 by taking the frontier advisory lock before the Crawl row lock
(`app/workflows/wf005/handlers/complete_crawl.rb:117-118`). `CrawlDriver#retire` holds
`crawl-frontier:<crawl>` across its frontier terminalize and its `crawl_terminal_outcomes` INSERT
(`app/workflows/wf005/crawl_driver.rb:362-373`), so a retirement **already in flight** is now fenced.

**A pass in its FETCH holds no lock at all.** `fetch_and_settle`
(`app/workflows/wf005/crawl_driver.rb:262-300`) performs the network request outside every
transaction — correctly, per MTX-030's "no external call sits inside a database transaction" — and
only afterwards opens `retire`'s transaction. Between admission's commit and `retire`'s first
statement the checkpoint takes an uncontended frontier lock, counts, and terminalizes.

That is **the exact window round 1's own reproduction (c) used**: "at natural timing with no gate at
all — a 150 ms fetch with the checkpoint fired 50 ms in, 10/10." ADR-105 states "the only gap was the
window before that INSERT, and the frontier lock closes exactly it." The frontier lock closes the part
of that window inside `retire`. It does not close the part inside the fetch, which is the larger part
and the one the reproduction used.

**Reproduced against HEAD `95d37f4`, 3 runs of 3**, through the real registered handlers, the real
`crawl_terminal_deadline` action and the real chain, with the F-01 façade stub suspended mid-request
(no production hook, no sleep ordering anything):

```
checkpoint payload      : documents:0  source_roots_succeeded:0  unevaluated_candidates:1
                          entitlement_outcome:"released"
crawls                  : state=failed  completion_reason=failed  coverage_status=NULL
crawl_terminal_outcomes : [document_created, covered, commit_order 1]
pass payload            : pass_outcome:"fetched"  outcome:"document_created"  http_status:200
entitlement_reservations: released
```

Byte-for-byte the state round 1 recorded for B7.

**Consequence, unchanged from B7 and still unrecoverable.** `f1_crawls_guard` refuses every UPDATE of
a terminal row (ADR-099), so a run that fetched a valid Document is permanently recorded `failed` and
its coverage permanently NULL, while the run's own committed record says `document_created / covered`.
The customer's run is wrong in the product and wrong in the ledger. ADR-101's drained-run checkpoint
is what makes checkpoint-concurrent-with-pass ordinary rather than exotic, and the deadline checkpoint
— which the accepted start now always schedules — fires at a fixed instant with no regard to whether a
pass is mid-request.

**THE CONTRACT LENS REACHED THE SAME PLACE FROM THE OTHER END, AND NAMES THE MISSING RULE.**
WORKFLOW_SPECIFICATIONS.md :442: "At 60 elapsed minutes, no new request starts **and incomplete
requests are canceled**." Only the first half is implemented, and `Workflows::Wf005::Admission`
says so in its own comment (`app/workflows/wf005/admission.rb:29-31`: "The first half is a decision
about whether to hand a worker any work at all"). The second half is what would make a post-deadline
retirement impossible. No follow-up owns it: FU-32 covers `CancelCrawl` only and states in terms that
":442 requires in-flight cancellation at the WALL CLOCK and says nothing about `CancelCrawl`".

**THE SECURITY LENS ESTABLISHES THE METERING HALF.** The reservation is RELEASED on a run that reached
`crawl_completed_with_valid_document` in fact, so `entitlement-interim-v1`'s durable commit point is
bypassed by timing. Round 1's B7 recorded the same direction; it is restated here because it is the
half that survives even if the coverage record were later reconciled.

**Repair.** Two candidates, and the choice is an owner-visible one:
1. **The ratified one** — implement :442's second half, so a request in flight at the wall clock is
   cancelled and no retirement can commit after the checkpoint. This is the sentence the contract
   already carries and it removes the class, not the instance.
2. **The minimal interim** — under the frontier advisory lock `retire` already takes, re-read
   `crawls.state` and abandon the retirement when the run is terminal (record no outcome, report the
   pass as superseded). The contradiction becomes unrepresentable; the terminal verdict is still
   decided without the in-flight fetch, which is why (1) is the real answer.

**PROOF 91 is not wrong, it is narrow.** It gates the outcome INSERT, so the pass it races is already
inside `retire`. Its title — "a checkpoint cannot count a run whose pass is mid-retirement" — is true.
ADR-105's general claim is not, and no example in the repository races the checkpoint against a pass
that is mid-REQUEST.

### R2-B2 — the B2 repair records a wall-clock hard limit for a run that abandoned nothing, turning a `completed` / `full` run into `limit_reached` / `partial`
*Found by the CONTRACT lens. Converged with ARCHITECTURE / TEST-QUALITY, which established that all three of the repair's own proofs avoid the case.*

`CompleteCrawl#observe_wall_clock` (`app/workflows/wf005/handlers/complete_crawl.rb:296-314`) records
the soft and hard `wall_clock_run_duration` crossings whenever `now >= deadline_at`, with no reference
to whether the clock actually abandoned anything. The predicate is **the checkpoint's delivery
instant**, not :458's "any in-scope candidate not evaluated".

Reproduced deterministically on the real chain: a run whose single candidate was fetched, whose
frontier is entirely `terminal`, and which is terminalized by its own deadline action —

```
frontier_states  : ["terminal"]
payload          : documents:1  source_roots_succeeded:1  uncovered_candidates:0
                   unevaluated_candidates:0  hard_limit_decisions:1
crawls           : state=completed  completion_reason=limit_reached  coverage_status=partial
crawl_limit_decisions:
  wall_clock_run_duration / hard / observed 60 / affected_url_count 0 / affected_source_count 0
  wall_clock_run_duration / soft / observed 60 / affected_url_count 0 / affected_source_count 0
```

**Four ratified sentences are broken at once.**
- :458 — "**Any in-scope candidate not evaluated** because of … wall-clock bound makes coverage
  partial." There is none. By :458's own `full` test — every in-scope candidate reached a terminal
  covered outcome and no Source or discovery path has an unresolved failure — this run is `full`.
- :442 — a hard limit is recorded with "dimension, configured value, observed value, **affected Source
  and URL counts**", and it means "stop scheduling affected work". Zero affected URLs and zero
  affected Sources is a record that no work was stopped.
- :458's precedence — `limit_reached` outranks `completed`, so the false reason wins the run.
- :442 — `CrawlLimitReached` is emitted "exactly once per dimension and run", here for a dimension
  that bounded nothing. The event is real, durable and outward-facing.

**Reachability is ordinary, not exotic.** The deadline checkpoint is scheduled by every accepted start
and is the only checkpoint for: a run whose last pass HALTED (a halted pass creates no link and no
drained checkpoint); a run whose drained pass reported `beyond_deadline` (`terminal_checkpoint`
refuses to mint one, `record_fetch_attempt.rb:178`); and any run whose drained-checkpoint delivery is
lost. It is also reached whenever the drained checkpoint's own delivery merely arrives at or after
`deadline_at` — **transport latency alone changes a customer's coverage verdict**, and the terminal
freeze makes it permanent.

**This is a regression the repair introduced.** Before ADR-107 the run above read `completed` / `full`.

**The suite cannot see it, and that is the test-quality half.** PROOF 95 seeds an unevaluated depth-1
candidate; PROOF 96 runs the checkpoint INSIDE the deadline; PROOF 97's run halted with zero
Documents. The one shape that matters — drained, fully covered, terminalized at or after the deadline
— is exercised by no example.

**Repair.** Gate the observation on what the method already computes: record only when
`affected_by_wall_clock(...)` reports a positive URL count, which is exactly :458's "any in-scope
candidate not evaluated" and exactly :442's "affected … counts". Add the missing example, and require
it to fail when the gate is removed.

### R2-B3 — B6's correction missed a fifth ratified place, and it is the one that states the refuted claim most plainly
*Found by the SCHEMA lens. Converged with ARCHITECTURE on record consistency.*

ADR-111 corrected the false `IS NOT DISTINCT FROM` refutation in ADR-097, the `20260727120340`
migration header, `POSTGRESQL_SCHEMA.md`, the FU-11 note in `BUILD_STATE.json` and PROOF 29's comment,
and pinned the truth with PROOF 104. **`DECISIONS.md:2236` (ADR-083) was not corrected** and still
reads:

> "that prescription is a proven no-op, since `NULL = ANY(...)` is UNKNOWN and therefore admitted and
> `IS NOT DISTINCT FROM` is admitted too."

Re-evaluated live against the PostgreSQL 17 cluster during this round, confirming ADR-111's corrected
statements and refuting ADR-083's:

```
(NULL = ANY(ARRAY['full','partial'])) IS NULL                        -> t   (UNKNOWN; a CHECK ADMITS)
NULL IS NULL OR NULL = ANY(ARRAY['full','partial'])                  -> t   (a CHECK ADMITS)
NULL IS NOT DISTINCT FROM 'full' OR ... 'partial'                    -> f   (a CHECK REFUSES)
NULL IS NOT DISTINCT FROM ANY(ARRAY['full','partial'])               -> ERROR: syntax error at or near "ANY"
```

**Consequence is B6's, unchanged.** ADR-083 is an ACCEPTED decision record, and it is the one a reader
tracing FU-11's history reaches first. It tells a future implementer that applying the
`IS NOT DISTINCT FROM` rewrite is harmless; the only spelling that parses would refuse every `queued`
and `running` Crawl, which carry NULL in that column by design. A blocker whose whole content is "a
ratified record states the opposite of the truth" is not closed while a ratified record still states
the opposite of the truth.

**Repair.** Correct ADR-083 in place, using the convention ADR-097 set for its own refutations and
ADR-111 followed.

---

## ROUND 2 OBSERVATIONS

Lens tag preserved per item, so the marginal-contribution measure stays computable (round 1's method
note).

1. **ADR-105's central premise is factually false** (CONCURRENCY + ARCHITECTURE). It argues the repair
   "conforms to an order that already existed": "`Admission#claim` takes the frontier advisory lock and
   then writes `crawl_budget_counters` … Frontier THEN crawls is therefore the subsystem's established
   order." `Handlers::StartCrawl` does the opposite — `store.start` takes the `crawls` row lock
   (`start_crawl.rb:275`) and `Frontier#seed_roots` then takes the frontier advisory lock
   (`start_crawl.rb:298`, `frontier.rb:78`). No reachable interleaving was demonstrated: a
   `crawl_terminal_deadline` action for a Crawl cannot exist until that same StartCrawl transaction
   commits. But the invariant the ADR rests on is not true of all four writers and nothing enforces it.
2. **PROOF 91 proves the sub-window, not the property** (TEST-QUALITY). See R2-B1.
3. **PROOF 39's expected link set is a hard-coded literal** (TEST-QUALITY), not "derived from the
   columns that name a Project-owned parent" as its own comment and ADR-110 both say. It does catch a
   removed FK on the three columns named — verified this round by dropping
   `crawl_terminal_outcomes_source_fk` live, which fails PROOF 39 and PROOF 39b — but it would also
   fail on a legitimately added fourth link, and it cannot generalise to FU-7's recommendation of a
   fitness check over every Project-owned FK in the schema.
4. **`BUILD_STATE` is still internally inconsistent, one field over from B11** (ARCHITECTURE).
   `implementation_commit` and `last_verified_commit` both read `f2b576e` — S-07-012's head — while
   `current_tranche` is `S-07-009` and `next_action` asserts "Gates at the repaired candidate: rspec
   2055/0 … structure.sql rebuilt". `review_commit` reads `a414f5c`, the superseded round-1 candidate.
   B11's repair rewrote `next_action` only.
5. **:442's second half is unimplemented and unowned** (CONTRACT). Recorded separately from R2-B1
   because it outlives whichever repair is taken for it. See R2-B1.
6. **`CancelCrawl`'s new deadline limb reports `crawl_already_terminal` for a Crawl that is still
   `running`** (SECURITY + CONTRACT). Faithful to the prescribed repair and to :458's own token, and
   correct as a refusal — but a run past its deadline whose checkpoint delivery is delayed or lost is
   cancellable by no principal, and the reason code tells the caller something untrue about the state.
7. **Round-1 observation 9 stands and was re-verified** (SCHEMA). `schemas/POSTGRESQL_SCHEMA.md`
   293-296 still interrupts the canonical catalogue with two blockquotes; the ~25 rows from
   `crawl_sources` (297) onward now form a table with no header row and render as literal pipe text.
8. **The harness now carries three outbound stubs across two spec files** (TEST-QUALITY).
   `outbound_by_path` is duplicated at `wf005_record_fetch_attempt_spec.rb:31` and
   `wf005_terminal_checkpoint_spec.rb:27`, and `outbound_by_host_path` sits beside the second at :51.
   `spec/acceptance/support/wf005_crawl_chain.rb` exists because this exact drift was found before.
9. **The 24 round-1 non-blocking observations remain open.** Round 2 re-confirms 9 (above) and
   promotes none of the others; the two it does promote are covered by R2-B1 and R2-B3.

---

## THE TWO HARNESS CORRECTIONS, REVIEWED AS PRODUCTION TEST INFRASTRUCTURE

Both were introduced by ADR-108 while repairing B9, and both are changes to the instrument every other
finding is measured with, so they are reviewed on their own terms.

**Drain timing across retry passes — CORRECT, AND STRICTLY STRONGER.**
`drain` (`wf005_terminal_checkpoint_spec.rb:120-131`) now executes each pass at
`Time.parse(action["due_at"])` instead of at `start_now`. :444's retries are due at
`completed_at + 30s`, so the previous form had the handler refuse every retry `scheduled_action_not_due`
and every chain stopped one pass in — silently, because the loop simply ended. No example that needed a
retry had been getting one. Verified this round: the corrected form reproduces what the transport does
(one delivery per due instant), the chain runs to genuine exhaustion, and PROOF 98 — which needs three
5xx responses to exhaust :444 — is unreachable without it. No weakening found: the loop still bounds
itself, still breaks on an absent link, and the clock it advances is the same injected clock every
other assertion reads.

**Host-specific `outbound_by_path` for multiple Sources — CORRECT.**
`outbound_by_host_path` (`:51-67`) keys on `"<host><path>"` and builds each response with the REQUESTED
host in `canonical_host` and `final_url`. The single-host stub answered as one canonical host whatever
it was asked, which is invisible with one Source and silently fails a second Source's fetch on :436's
final-URL scope check — producing `policy_excluded / redirect_policy_denied` for a URL nothing had
refused. Verified: the two-Source examples that carry B9's repair depend on it, and the correction is
faithful rather than permissive (an unmapped host/path still raises). Placement is observation 8.

---

## WHAT ROUND 2 INDEPENDENTLY CONFIRMED SOUND

- **Every mutation the repair ADRs name kills its named proof.** Fourteen applied and reverted
  independently, each against the 721-example WF-005 acceptance surface (`spec/acceptance/wf005_*`,
  `spec/persistence`, `spec/workflows/wf005`), baseline 721/0:

  | mutation | result |
  | --- | --- |
  | remove `lock_frontier` from the checkpoint | PROOF 91 fails |
  | remove `lock_reservation` from `renew_entitlement_lease` | PROOF 92 fails |
  | remove the cancel deadline limb | PROOF 93 fails |
  | weaken `>=` to `>` in the cancel deadline limb | PROOF 93 fails |
  | remove `observe_wall_clock` | PROOF 95 fails |
  | `uncovered → 0` | PROOF 98 fails |
  | `fetch_failures → 0` | PROOF 98 fails |
  | `hard_limits → 0` | PROOF 99 **and** PROOF 95 fail |
  | remove `FOR UPDATE` from `lock_crawl` | PROOFs 100 **and** 101 fail |
  | remove `accepted_document_count` (checkpoint) | PROOFs 102 **and** 103 fail |
  | remove `transition_reason_code` (checkpoint) | PROOF 103 fails |
  | remove `accepted_document_count` (`CrawlCanceled`) | cancel spec :122 fails |
  | remove `transition_reason_code` (`CrawlCanceled`) | cancel spec :122 fails |
  | DROP `crawl_terminal_outcomes_source_fk` (live DDL) | PROOFs 39 **and** 39b fail |

  Round 1's three signature survivals — `uncovered → 0`, `fetch_failures → 0`, `hard_limits → 0` at
  218/0, and `FOR UPDATE` deleted at 218/0 — are genuinely gone.
- **B3, B4, B5, B8, B9, B10 are independently closed**, by the mutations above plus direct reading of
  the envelopes against API_CONTRACTS.md :807-808, :938 and :956 (whose text was re-read this round and
  matches the repair exactly), and of `crawl.cancel` against WORKFLOW_SPECIFICATIONS.md :147 and :738.
- **B1 is independently closed.** :458's three sentences were re-read; the third is implemented at
  `cancel_crawl.rb:131-134` with `>=`, and PROOFs 93/94 bracket the instant from both sides.
- **B11 is closed for the field it names.** `next_action` describes the fifteen-commit state; the
  FU-30 contradiction is gone. Observation 4 is the adjacent field it did not reach.
- **B6's four named places are corrected and PROOF 104 pins the truth**; the fifth is R2-B3.
- **Schema and migration safety, verified from this state, not taken on report**: `structure.sql`
  re-dumps with no drift; the schema **built from empty on a scratch database dumps byte-identical to
  the committed `structure.sql`**; all five S-07-009 migrations reverse and re-apply one at a time with
  the catalogue byte-identical afterwards; `crawl_terminal_outcomes_source_fk` is present in
  `structure.sql` and live; grants are `SELECT, INSERT` only; `verify_runtime` OK, 15 checks, RLS
  intact.
- **Tenancy**: `CompleteCrawl` proves the Organization before any ledger row and reads the Crawl
  org-scoped under the row lock; `CancelCrawl` refuses a cross-tenant or mismatched Project before
  authorization; every `terminal_facts` subquery is organization-scoped; `crawl.cancel`'s baseline row
  transcribes :147's two allow cells and no others, with `PermissionBaseline::VERSION` unchanged.
- **Scope**: no S-07-010 or S-07-011 work pulled forward; no frozen foundation contract changed; the
  only frozen-path touch is the additive `crawl_terminal_outcomes` grant.

---

## GATES, RUN FROM THE FINAL REVIEWED STATE (`95d37f4`)

| Gate | Command | Result |
| --- | --- | --- |
| complete_test_suite | `bundle exec rspec` | **2055 examples, 0 failures** |
| brakeman | `bundle exec brakeman -q --no-pager -z` | 0 warnings |
| packwerk | `bin/packwerk check` | no offenses, no stale violations |
| zeitwerk | `bin/rails zeitwerk:check` | All is good |
| bundler_audit | `bundle exec bundle-audit check --update` | no vulnerabilities |
| runtime_role_and_rls | `bin/f1db f1:db:verify_runtime` | OK as `f1_web`, 15 checks, RLS intact |
| migration_safety_no_drift | `bin/f1db db:schema:dump && git diff --exit-code db/structure.sql` | no drift |
| build from empty | scratch database, `db:migrate` then dump | **byte-identical** |
| migration reversibility | five down, five up, then dump | **byte-identical** |
| architecture_fitness | `bundle exec rspec spec/architecture` | 58 examples, 0 failures |
| repository_cleanliness | `git status --porcelain` | **not empty** — pre-existing untracked/modified `branding/`, `investor/`, `operations/` files, unrelated to this block and outside its acceptance diff |
| rubocop (not in the manifest) | `bin/rubocop` | red repo-wide, 4102 offences, pre-existing (round-1 observation 24) |

**Every mandatory gate passes and the block still fails acceptance.** That is the point of the review.

---

## LENS MARGINAL CONTRIBUTION — round 2 of the measure

| Lens | Blockers unique | Blockers joint | Blocker total | Observations unique |
| --- | --- | --- | --- | --- |
| Contract-correctness | 1 (R2-B2) | 1 (R2-B1) | 2 | 2 (5, 6-joint) |
| Concurrency | 1 (R2-B1) | 0 | 1 | 1 (1-joint) |
| Schema / migration | 1 (R2-B3) | 0 | 1 | 1 (7) |
| Architecture / test-quality | 0 | 2 (R2-B2, R2-B3) | 2 | 4 (1-joint, 2, 3, 4, 8) |
| Security / tenancy | 0 | 1 (R2-B1) | 1 | 1 (6-joint) |

Round totals: **3 blockers — 3 found by exactly one lens (100% unique discovery), 2 of them then
independently corroborated by a second and third lens.** 9 observations, 2 of them joint.

**WHO ESTABLISHED CONSEQUENCE, RECORDED SEPARATELY FROM WHO FOUND IT** — round 1's method note, which
is what makes this measure worth keeping:

- **R2-B1** — discovered by CONCURRENCY, which also reproduced it. CONTRACT established *why it is
  reachable at all* by naming the unimplemented ratified sentence (:442's "incomplete requests are
  canceled"), which turns "a race exists" into "a rule is missing". SECURITY established the
  metering-integrity half. A metric counting only discovery would credit one lens with a finding three
  mandates built.
- **R2-B2** — discovered by CONTRACT against :458 and :442. ARCHITECTURE / TEST-QUALITY established
  the consequence that matters for governance: all three of the repair's own proofs avoid the shape,
  so the defect is not merely present but structurally invisible to the suite that certifies it.
- **R2-B3** — discovered and consequence-established by SCHEMA alone, with ARCHITECTURE corroborating
  it as a record-consistency defect.

**COMPARING ROUND 1 AND ROUND 2 — AND ELEVEN TO THREE IS NOT PROGRESS UNTIL IT IS READ PROPERLY.**

| | round 1 | round 2 |
| --- | --- | --- |
| candidate | `7f043a2..a414f5c` | `7f043a2..95d37f4` |
| suite at candidate | 2040 / 0 | 2055 / 0 |
| blockers | 11 | 3 |
| of which are defects in the previous round's REPAIRS | n/a | **2 of 3** |
| unique-discovery rate | 81.8% | 100% |
| lenses returning FAIL | 5 of 5 | 5 of 5 |

- **The count fell; the failure did not.** Nine of eleven are genuinely closed and independently
  verified. Two are not, and one of the two is the round's most serious finding on both rounds.
- **Two of round 2's three blockers are IN THE REPAIRS.** R2-B1 is a repair that closed the smaller
  half of its window; R2-B2 is a repair that introduced a new wrong answer; R2-B3 is a repair that
  stopped one place short. That is the round's real finding, and it is a statement about the repair
  phase rather than about the original implementation: **a repair is candidate material and must be
  reviewed as such, not credited because it carries a passing mutation proof.** Every one of the
  fourteen mutations passes, and two of the repairs are still defective — a mutation proof shows a
  repair is load-bearing, never that it is complete or that it is right.
- **Unique discovery rose to 100%**, which continues round 1's reading: the five lenses remain
  orthogonal and all five are earning their place. Corroboration after discovery rose too, which is
  the healthy direction — the same defect reached from three mandates is the strongest evidence a
  round can produce.
- **A lower blocker count on a repaired candidate is exactly what a successful repair phase and a
  failing one both look like from the outside.** Only re-running the round distinguishes them, and
  this one distinguishes them: it found that the most serious blocker of round 1 was reported closed
  and is not.

---

## REPAIR PROGRAMME, IN DEPENDENCY ORDER

1. **R2-B1** — highest severity, unrecoverable, ordinary timing, and open on a second round. The
   owner-visible choice between :442's ratified in-flight cancellation and the minimal interim guard
   must be taken explicitly. Whichever is chosen, the example that closes it must race the checkpoint
   against a pass that is mid-REQUEST, and must fail without the repair.
2. **R2-B2** — a live regression introduced by ADR-107; gate the observation on the affected-URL count
   and add the drained-at-deadline example.
3. **R2-B3** — correct ADR-083 in place.
4. Then observations 1-8, and the 24 carried from round 1.

Re-run the full five-lens round against the next repaired candidate. **Round 2 exists because round 1's
repairs were not themselves reviewed; round 3 must review round 2's the same way.**
