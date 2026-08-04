# S-07-009 — ADR-080 Acceptance Review: NOT ACCEPTED

> **ROUND 2 HAS NOW RUN AND ALSO FAILS. See [ROUND 2](#round-2--the-repaired-candidate-7f043a295d37f4)
> at the foot of this file.** Three confirmed-blocking findings, two of them defects in the round-1
> repairs themselves: **B7 is not closed** (the same corrupt terminal state reproduced 3/3 against the
> repaired candidate), the B2 repair **introduced** a new wrong coverage verdict, and B6's correction
> missed a fifth place. **S-07-009 REMAINS NOT ACCEPTED.**

> **ROUND 3 HAS NOW RUN AND ALSO FAILS — ALL FIVE LENSES, ELEVEN IN-CANDIDATE BLOCKERS, AND ALL THREE
> ROUND-2 REPAIRS REFUTED.** See [ROUND 3](#round-3--the-round-2-repaired-candidate-7f043a2467f1d1).
> FU-34, FU-35 and FU-36 are each independently **NOT CLOSED**, by three different routes. Round 3 also
> establishes that the mandatory gate "the schema builds from empty" **has never been executed** in this
> repository's history, and that three of the concurrency proofs the round-1 repairs rest on **pass
> vacuously whenever any unrelated transaction anywhere on the cluster is waiting on a row lock**.
> The suite was **2068/0 on a quiet cluster at the moment of the verdict**. **S-07-009 REMAINS NOT ACCEPTED.**

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

> **REPAIRED 2026-07-31 — FU-34, ADR-113, on the owner's ruling that the RATIFIED cancellation rule is
> the repository-consistent choice and the interim guard alone would "make the contradiction less
> visible without completing the promised behaviour". :442's second sentence is now implemented at the
> request's own budget through F-01's frozen `timeout_s`, and `retire` decides against the run's
> authoritative state under the frontier lock. PROOFs 105-111; SEVEN adversarial mutations, each
> plausible incomplete repair failing a named proof. Verified by the repair phase, NOT by round 2 —
> round 3 must review it as candidate material.**

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

> **REPAIRED 2026-07-31 — FU-35, ADR-114.** The observation is gated on whether the deadline prevented
> an evaluation, not on when the handler arrived; both limbs are gated; and the affected measure now
> unions the candidates whose request ADR-113's cancellation ended, which is the seam between the two
> repairs. PROOFs 112-116; four mutations, including one that drops the cancelled population without
> raising. Verified by the repair phase, NOT by round 2.

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

> **REPAIRED 2026-07-31 — FU-36, ADR-115. The repository-wide sweep found a SEVENTH copy this round
> did not name — `specification/automation/BUILD_PLAN.yml` — so the finding was larger than reported.**
> Both corrected in place, and the durable half is a mechanical check over the records themselves,
> because correcting copies someone listed is the defect rather than the repair. Verified by
> reintroducing the claim three ways. Verified by the repair phase, NOT by round 2.

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

> **DISPOSITIONED 2026-07-31 — FU-37, ADR-116.** Four repaired because each is a false or misleading
> record this block itself wrote, which is the B6 defect class: **1** (ADR-105's lock-order premise,
> corrected in place; the hazard tracked as FU-38), **2** (PROOF 91's scope stated in the example),
> **3** (ADR-110's "derived" overstatement corrected; the deriving check folded into FU-7), **7** (the
> catalogue de-split; the identical PRE-EXISTING split at :272-274 deliberately untouched). **5** is
> closed by ADR-113. **4**, **6** and **8** are carried with reasons — 4 turns out not to be a
> contradiction at all but a naming ambiguity the truth spec's own invariant depends on. The
> twenty-four round-1 observations remain open and unpromoted, attribution intact.

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

---

# ROUND 3 — the round-2 repaired candidate `7f043a2..467f1d1`

Candidate: `7f043a2..467f1d1`, pinned (not `..HEAD`; two governance commits sit above it).
Round run: 2026-08-02, full ADR-026 five-lens form, five reviewers in five independent contexts with no
shared conversational state and no knowledge of who authored which repair.
Gates at the candidate, re-measured on a quiet cluster after the reviewers finished:
**rspec 2068/0**, architecture fitness 59/0, brakeman 0, packwerk clean, zeitwerk ok, bundler-audit clean,
verify_runtime 15/15 RLS intact, no structure.sql drift.

**VERDICT: FAIL. All five lenses. Eleven in-candidate blockers, three pre-existing/governance blockers.
All three round-2 repairs (FU-34, FU-35, FU-36) are independently REFUTED. S-07-009 IS NOT ACCEPTED.**

| Lens | Verdict | In-candidate blocking |
| --- | --- | --- |
| Contract-correctness | FAIL | 3 (R3-1, R3-2, R3-3) |
| Concurrency / atomicity / idempotency | FAIL | 2 (R3-4, R3-5) + R3-6 as observation |
| Schema / migration-safety | FAIL | 1 (R3-7 converged) + 3 pre-existing (R3-P1..P3) |
| Architecture / scope / test-quality | FAIL | 4 (R3-6 converged, R3-8, R3-7 converged, R3-9) |
| Security / tenant-isolation | FAIL | 2 (R3-10, R3-11) |

## The three round-2 repairs, each refuted by a different route

**FU-34 is NOT closed.** Its in-transaction half is genuine and mutation-verified, but it is bounded by
two failures the round-2 session did not test. (a) The out-of-transaction half does not hold at all:
`RequestPolicy#timeout_s` is a **per-connection-attempt** bound, re-armed once per redirect hop, so one
`Outbound.fetch` bounded at `remaining` runs up to `(10+1) x (dns + response)`; measured overrun **11.1x
at 10/10**, and up to 22x with DNS timing. Separately `context[:now]` is the pass's *delivery* instant,
not the request's start, so the bound is computed from a clock that has already advanced past the robots
fetch and sitemap discovery. (b) The in-transaction half is authoritative against `CompleteCrawl` only.

**FU-35 is NOT closed.** The repair removed *delivery latency* as a determinant, which was the round-2
finding, and stopped there. `unevaluated_reach` still admits `state = 'discarded' AND reason IS NOT NULL`
— every candidate a **different** bound affirmatively disposed of. A run whose only unfetched URL was
discarded by the **depth** limit at minute zero emits a `wall_clock_run_duration` **hard** decision with
`affected_urls = 1` and spends its once-per-run `CrawlLimitReached`. Both records are immutable and
`f1_crawls_guard` refuses correction of the terminal row. The customer is told their crawl ran out of time.

**FU-36 is NOT closed.** The predicate claims themselves are substantively correct and PROOF 104 is potent
— verified by execution against PG17 (pairwise form FALSE; `ANY(...)` form raises `PG::SyntaxError`; NULL
admitted under UNKNOWN and refused under FALSE; a live `queued` crawl refused). But ADR-115's claim that
"an eighth copy fails CI" is false, by two independent escapes found by two lenses separately.

## Consolidated blockers, with per-lens provenance

Provenance is preserved: **U** = discovered by that lens alone; **J** = joint.

| id | finding | lens(es) | file |
| --- | --- | --- | --- |
| R3-1 | FU-35 refuted: `unevaluated_reach` counts other dimensions' discarded candidates as wall-clock-affected | contract **U** | `crawl_start_store.rb:264` |
| R3-2 | `CancelCrawl` bars **every** post-deadline cancellation; :458 s.3 scopes the win to the instant, s.1 governs the rest by commit order. Refusal code contradicts the authoritative state (`running`, `terminal_at` NULL) | contract **U** | `cancel_crawl.rb:131-134` |
| R3-3 | `CrawlCanceled` omits `coverage_status`, a declared `crawl_terminal` member; the command-result payload already sets it | contract **U** | `cancel_crawl.rb:182-187` |
| R3-4 | FU-34 out-of-transaction half not implemented: per-hop timeout re-arming (11.1x overrun, 10/10) + `now` is the pass's delivery instant | concurrency **U** | `fetch_content.rb:345-353`, `guarded_http_client.rb:109-112` |
| R3-5 | The three lock proofs gate on a **cluster-wide** `pg_locks` predicate with no database filter. With one unrelated waiter in a *different database*: deleting `FOR UPDATE` → PROOF 101 passes 10/10; deleting `lock_reservation` → PROOF 92 passes 10/10 | concurrency **U** | `wf005_checkpoint_pass_concurrency_spec.rb:197-201`, `wf005_heartbeat_concurrency_spec.rb:132-137` |
| R3-6 | `CancelCrawl` takes no frontier lock, so `retire` can commit `document_created / covered` onto a cancelled, entitlement-released Crawl. Irreversible. R2-B1's shape with `canceled` for `failed` | architecture **J** (BLOCKER, 3/3) + concurrency **J** (OBSERVATION, 10/10) | `cancel_crawl.rb:102` vs `crawl_driver.rb:402` |
| R3-7 | FU-36's durable check has two escapes: `CORRECT_USE` whitelists any window containing `limit_reached` (this tranche's own completion reason), and `PREDICATE_RECORDS` is a hardcoded six-file list that misses `S-07-009_COMPLETION_REPORT.md` — the file acceptance will create | schema **J** + architecture **J** | `repository_truth_spec.rb:291-299,309` |
| R3-8 | PROOF 108's central assertion cannot fail: `requests` is appended to only by `content_outbound`, and PROOF 108's bespoke stub never touches it. The "stub raises" backup is also false — `fetch_content.rb:320` rescues `StandardError` | architecture **U** | `wf005_content_fetch_spec.rb:885` |
| R3-9 | `gate_row` selects one row with no `ORDER BY` from a two-gate crawl. `ORDER BY canonical_host ASC` → PROOFs 98, 99, 114 **fail**. The suite is green on heap order | architecture **U** | `wf005_crawl_chain.rb:181` |
| R3-10 | A **Read-Only Executive Buyer** can irreversibly cancel a running Crawl. :147 is a seven-cell row and only its two allows were transcribed; `confers?` reads `canonical_role` and never `permission_mode` | security **U** | `command_authorizer.rb:122`, `permission_baseline.rb:130` |
| R3-11 | The RLS **policy predicate** on `crawl_terminal_outcomes` is asserted by nothing. `USING (true) WITH CHECK (true)` → every S-07-009 spec stays green. The preceding tranche established the rule and named this exact mutation | security **U** | `crawl_terminal_outcome_invariants_spec.rb:310` |

## Pre-existing / governance blockers (outside the candidate range)

| id | finding | evidence |
| --- | --- | --- |
| R3-P1 | **The migration chain cannot build an empty database.** `20260721120004:68` puts `lifecycle_reason` in the `CREATE TABLE`; `20260722120014:22` adds it again with no `IF NOT EXISTS`. 13 of 69 migrations apply, then `PG::DuplicateColumn`. Present since `54b4abd`, 2026-07-21 | reproduced with `SCHEMA` pointed away from `structure.sql`; deleting the duplicate line applies all 69 and dumps byte-identical |
| R3-P2 | **The gate "the schema builds from empty" has never been executed.** Rails' `db:migrate` loads `structure.sql` first on an uninitialised database (`database_tasks.rb:651-669`), so `bin/f1-provision-db:46` prints "provisioned from empty" having run **zero** migrations. `VERIFICATION_MANIFEST.yml:83` is only dump-and-diff. **22 assertions in DECISIONS.md** plus `BUILD_STATE.reconciliation_note` describe an operation never performed | `[3/5] run migrations` emitted no `migrating` lines while taking the DB 0 → 55 tables |
| R3-P3 | `db/structure.sql:1292-1309` defines `f1_find_invitation_acceptance_replay`, which **no migration creates**. Invisible to the gate because dump-and-diff against a structure-loaded database is a closed loop | absent from `db/migrate`, `app`, `lib`, `spec` |

R3-P1..P3 are **outside `7f043a2..467f1d1`** and are not S-07-009 defects. They are recorded here because
R3-P2 means no acceptance in this repository has met its own stated migration-safety criterion, which is a
scope question for the owner rather than a repair this tranche may absorb.

## Marginal contribution per lens

| Lens | Blockers unique | Blockers joint | Observations unique |
| --- | --- | --- | --- |
| Contract-correctness | 3 | 0 | 4 |
| Concurrency / atomicity | 2 | 1 (R3-6) | 3 |
| Schema / migration-safety | 3 (all pre-existing) | 1 (R3-7) | 0 |
| Architecture / scope / test-quality | 3 | 2 (R3-6, R3-7) | 8 |
| Security / tenant-isolation | 2 | 0 | 4 |

Two joint discoveries. **R3-6** was reached from opposite mandates — architecture by auditing what the
cancellation specs never race, concurrency by auditing the lock graph — and the two lenses **disagreed on
severity**, architecture calling it a blocker and concurrency an observation on the strength of FU-32's
ratified disclosure. That disagreement is preserved rather than averaged. **R3-7** was reached by schema
and architecture with overlapping but separately constructed escapes.

**Consequence-establishment, recorded separately from discovery.** Three findings were established as
consequential by evidence that no reading could have produced: R3-5 by running a noise generator in a
*different database* and watching two mutation-killed proofs return to green (10/10); R3-9 by forcing the
unordered `SELECT` both ways and watching three proofs flip; R3-11 by rewriting a live policy to
`USING (true)` and watching 112 examples stay green.

## Round 3 against rounds 1 and 2

Round 1: 11 blockers on a 2040/0 candidate. Round 2: 3 on a 2055/0 candidate, two of them defects in
round 1's repairs. Round 3: 11 in-candidate on a **2068/0** candidate, **all three round-2 repairs refuted**,
plus a pre-existing gate that has never run.

The count did not fall, and the depth increased. Rounds 1 and 2 found defects in code; round 3's most
serious findings are that **the evidence itself does not hold** — three lock proofs that pass whenever the
cluster is busy, an assertion that cannot fail, three proofs green on physical row order, and a policy
predicate no test exercises. A fourth round is not made unnecessary by a smaller number; on this record it
is made necessary by the kind.

## Dependency-ordered repair programme

1. **R3-5 first, before anything else is measured.** While the lock proofs can false-pass, no concurrency
   evidence in this repository is trustworthy, including the evidence for repairs 2-4 below. Scope the
   waiter predicate to `current_database()` and to the blocking pids, then re-run every mutation round 1
   and round 2 relied on.
2. **R3-8, R3-9, R3-11** — the other three evidence defects. Repair the instruments before the code they
   are supposed to measure.
3. **R3-6** — resolve the severity disagreement first (it is an owner question: does FU-32's disclosure
   cover a cancelled run, or does `crawl_driver.rb:378-390`'s authoritativeness claim govern?), then either
   take the frontier lock in `CancelCrawl` or correct the claim, and add PROOF 111's cancellation counterpart.
4. **R3-10** — the only irreversible customer-facing hole. Independent of the rest.
5. **R3-4**, then **R3-1**, then **R3-2**, then **R3-3** — the contract and bounding repairs, in that order,
   because R3-4 changes what "still in flight at the deadline" means and R3-1 changes what the deadline is
   recorded as having bounded.
6. **R3-7** — widen the durable check last, so it is written against the final vocabulary.
7. **R3-P1..P3** — owner scope decision. Not absorbed into this tranche.

**Round 4 must be run by five fresh contexts.** Round 3's own method is the reason it found what it did.

# ROUND 4 — the round-3 repaired candidate `7f043a2..7034e25`

Candidate: `7f043a2..7034e25`, pinned (not `..HEAD`; two governance commits sit above it).
Round run: 2026-08-03, full ADR-026 five-lens form, five reviewers in five independent contexts with no
shared conversational state and no knowledge of who authored which repair.
Gates at the candidate, re-measured on a quiet cluster: **rspec 2085/0**, architecture fitness 65/0,
brakeman 0, packwerk clean, zeitwerk ok, bundler-audit clean, verify_runtime 15/15 RLS intact, no
structure.sql drift.

**VERDICT: FAIL. Three of five lenses. EIGHT confirmed-blocking findings. S-07-009 IS NOT ACCEPTED.**

| Lens | Verdict | In-candidate blocking |
| --- | --- | --- |
| Contract-correctness | FAIL | 4 (R4-1, R4-5, R4-6, R4-7) |
| Concurrency / atomicity / idempotency | FAIL | 2 (R4-2, R4-4) |
| Architecture / scope / test-quality | FAIL | 2 (R4-3, R4-8) |
| Schema / migration-safety | PASS_WITH_OBSERVATIONS | 0 |
| Security / tenant-isolation | PASS_WITH_OBSERVATIONS | 0 |

**FOUR OF THE EIGHT BLOCKERS ARE DEFECTS IN ROUND 3's OWN REPAIRS** (R4-1 in R3-2, R4-2 in R3-6, R4-4 in
R3-5-as-amended-by-R3-6, R4-5 in R3-4(b), R4-6 in R3-1 — five, counting R4-6). That is now the pattern in
every round: round 2 found two defects in round 1's repairs, round 3 refuted all three of round 2's, and
round 4 finds five in round 3's. **A repair being present, gated green and mutation-proved against ONE
named mutation is not evidence that it is correct.**

## Consolidated blockers

Provenance preserved. **U** = discovered by that lens alone; **J** = joint.

| id | finding | lens(es) | file |
| --- | --- | --- | --- |
| R4-1 | R3-2's boundary compares against a deadline TRUNCATED TO THE WHOLE SECOND. `Time.parse(t.to_s)` drops subseconds, so :458 s.3 never fires at the true boundary and s.2's "strictly before" cancellations are refused for up to 999,999µs | contract **U** | `cancel_crawl.rb:161-163` |
| R4-2 | R3-6 created a LOCK-ORDER INVERSION with `StartCrawl`, which takes the `crawls` ROW lock (`store.start`) before the frontier advisory lock (`seed_roots`). `CancelCrawl` now takes them in the opposite order. Reachable by cancelling a `queued` Crawl; `CancelCrawl` has no rescue, so `PG::TRDeadlockDetected` escapes a customer command raw | concurrency **U** | `cancel_crawl.rb:117-118` vs `start_crawl.rb:275,298` |
| R4-3 | PROOF 78's assertion cannot fail, and :452's "policy_excluded is OUTSIDE the denominator" is asserted by NOTHING. The whole suite passes with the rule inverted | architecture **U** | `terminal_selection_spec.rb:101-108`, `crawl_start_store.rb:206` |
| R4-4 | R3-6 deleted `locktype IN ('transactionid','tuple')` from `blocked_behind`, so the predicate counts ANY ungranted lock behind the gated backend. R3-5's defect class narrowed, not removed | concurrency **U** | `race_harness.rb:130-146` |
| R4-5 | R3-4(b) anchors `entered_monotonic` at `FetchContent#call`, but robots and sitemap discovery run in `CrawlDriver#advance` BEFORE that — so the elapsed time the repair exists to measure is still invisible | contract **U** | `fetch_content.rb:164` vs `crawl_driver.rb:149,153` |
| R4-6 | R3-1 removed only the `discarded` leg. Candidates a DIFFERENT run-wide bound left `queued` are still counted as wall-clock-affected — byte-for-byte the harm R3-1 was written to remove | contract **U** | `crawl_start_store.rb:277-291` |
| R4-7 | `CrawlCompleted` omits `transition_reason_code`, a required :938 `state_transition` BASE member, while both siblings carry it. The inconsistency is created inside this range | contract **U** | `complete_crawl.rb:225-234` |
| R4-8 | The completion report names TWO different candidate ranges, and the one under "What a round-4 reviewer must know" is the SUPERSEDED pin | architecture **J** + security **J** + schema **J** | `S-07-009_COMPLETION_REPORT.md:19` vs `:133`, `:182` |

## Evidence established by execution, recorded separately from discovery

Three blockers were settled mechanically rather than by reading:

- **R4-1** — evaluated in the real runtime: a `deadline_at` of `12:01:30.123456Z` truncates to
  `12:01:30.000000Z`. At the true boundary the branch does NOT fire; 123ms strictly before it, it DOES.
  Both halves of :458's rule are inverted. Invisible to the suite because every fixture instant is a
  whole second (`wf005_crawl_chain.rb:16`) and the proofs read the deadline back through a raw PG
  connection with no type map — a different decoding path from production.
- **R4-3** — `AND o.coverage_effect = 'not_covered'` mutated to `<> 'covered'`, which counts
  `policy_excluded` rows in the denominator, exactly what :452 forbids. **FULL SUITE 2085 examples,
  0 failures.** The rule is asserted by no executable proof anywhere in the repository.
- **R4-2** — the two lock statements are explicit and unconditional and were read directly:
  `StartCrawl` = crawls-row then frontier-advisory; `CancelCrawl` = frontier-advisory then crawls-row.
  A `queued` Crawl is cancellable (`state = ANY (ARRAY['queued','running'])`), so the race is ordinary
  rather than exotic. `CancelCrawl` contains zero `rescue` clauses.

## Records that state something untrue

The code held up better than the record did. Every item below is a claim the repository makes about
itself that a reviewer disproved:

- **The candidate range** (R4-8): three lenses independently. `dfb6437` asserted it re-pinned the range
  "forward and in the open" and updated ONE of THREE occurrences.
- **"all fourteen" capabilities** (`permission_baseline.rb`, `BUILD_STATE` FU-1, the R3-10 commit
  message): there are **SIXTEEN**, and the cited range `:137-:151` excludes three of them at `:170`,
  `:172`, `:173`. The SUBSTANCE is correct — all sixteen sixth cells read `deny`, verified — and the
  transcription spec derives from `CAPABILITIES.keys`, so the MECHANISM was right where the prose was
  wrong.
- **"Every repair was mutation-proved: the fix was reverted and a NAMED proof required to fail"**
  (report `:114`): FALSE for R3-9, whose recorded evidence is "forcing the order both ways, 24/24" —
  no named proof fails on reversion. STALE for R3-5, whose named mutation leaves the suite green after
  `bc965dd`, as FU-41 itself records.
- **"every claim below is mechanically checked by `repository_truth_spec`"** (report `:12`): FALSE.
  That spec derives its report path from `acceptance_evidence.block`, which is S-07-012, so it checks a
  different tranche's report.
- **"an eighth cannot be written silently"** (report `:84`): OVERSTATED. `HARMLESS` is a precondition
  for being examined, so a false claim phrased without "no-op", "admitted" or "yields true" is never
  looked at. Three constructed paraphrases pass.
- **The Schema-changes table** (report `:72`, `:73`, `:75`): `20260727120360` also adds
  `crawl_terminal_immutable` (a blanket freeze on any UPDATE of a terminal row) and
  `crawl_run_identity_immutable` — two NEW irreversible restrictions on a production table, unmentioned.
  `:75` reads as though the missing Source link were pre-existing; it was introduced by
  `20260727120350` inside this same range and repaired by `20260727120380`.
- **The proof-count table** (report `:156`, `:157`): 13 should be 16, 10 should be 7. The errors cancel
  in the total, and the inflated row is the file carrying the R3-6 proofs.
- **FU-41's reasoning is wrong.** `lock_crawl` has two callers, but the ROW has a THIRD writer that
  takes no frontier lock — `CrawlStartStore#start`/`#fail` from `StartCrawl`. `FOR UPDATE` is therefore
  NOT superseded, and the record as written would license removing a load-bearing control.
- **"Open and unchanged: FU-38"**: FALSE. R3-6 added a customer-reachable second party to the inverted
  side, which is precisely what makes FU-38 reachable (R4-2). FU-38's own note still carries the
  now-invalidated "no reachable interleaving" justification.

## What the round confirmed sound

Recorded so the next round need not re-derive it. **R3-10 is correct AND complete** — the ratified table
was parsed mechanically and all sixteen materialized capabilities deny the Read-Only Executive Buyer, so
`READ_ONLY_CAPABILITIES = []` is right by transcription; no other route to an irreversible cancellation
exists; a `standard` actor is provably unaffected. **R3-11 is genuinely repaired** — PROOF 40a/40b
exercise the policy predicate as a real `f1_web` connection on both limbs, and test the policy rather
than a foreign-key refusal. **PROOF 117 is sound and falsifiable**, object-scoped on the frontier key;
**PROOF 118 is honestly scoped** to `retire`'s re-read rather than to the lock. **Zero structure drift**,
independently reproduced. `crawls_terminal_shape` is fully two-valued across all 16 shapes, refusing
FU-11's bad shape and preserving `CrawlStartStore#fail`'s. All three `crawl_terminal_outcomes` FKs are
arity-3. The run-clock freeze does not over-freeze. **R3-P1/P2/P3 are genuinely pre-existing and outside
the range**, and the candidate neither introduces nor worsens them. **Scope is clean** — nothing in the
49-file range lies outside S-07-009's remit, and the only frozen-path touch is `runtime_grants.rb` under
the ADR-027/029 additive exception. R3-2's removal of the `>=` guard opens no metering path :551 does not
already ratify.

## Notable non-blocking observations

- **Cross-tenant advisory lock** (security OBS-2 / concurrency O6): `cancel_crawl.rb:117` takes an
  org-agnostic `pg_advisory_xact_lock` on a caller-supplied crawl id BEFORE the tenancy check, so an
  actor in org A can hold org B's frontier lock for the duration of a denial. Introduced by R3-6.
  Bounded by uuid_v7 unguessability. The fix composes with R4-2's: tenancy check, then frontier, then row.
- **PROOF 39 does not derive** (schema O-1): its expected link set is a hardcoded three-element literal,
  so `20260727120380`'s header claim is false. FU-7's detector remains unbuilt; next recurrence path
  is dated S-07-010.
- **A `POP_TIMEOUT_S` timeout reports the wrong cause** (concurrency O3): `FetchContent#fetch` rescues
  `StandardError`, so the await's message never surfaces; the example fails on `expected "halted", got
  "retrying"`.
- PROOF 119 is reason-blind (only PROOF 120 pins `missing_authority`); the transcription guard cannot
  fail if `materialized` shrinks; `repository_truth_spec`'s new `predicate_records` uses backticks with
  interpolation in the one file whose header condemns exactly that.

## Repair programme, in dependency order

1. **R4-2 first.** A deadlock in a customer command is the most serious finding and it is in the lock
   graph everything else races on. Take the tenancy check first, then frontier, then row — the shape
   `start_crawl.rb` already uses — or make `StartCrawl` conform.
2. **R4-4**, before any concurrency evidence is trusted again: restore an object-scoped predicate.
   `blocked_on(frontier_key)` expresses PROOF 100/101 exactly and PROOF 92 never needed the change.
3. **R4-3** — the denominator rule needs a real proof, and PROOF 78 needs to be able to fail.
4. **R4-1** — compare against the untruncated instant.
5. **R4-5**, **R4-6**, **R4-7** — the contract repairs.
6. **R4-8 and the record defects** — last, so they are written against the final vocabulary.

**Round 5 must be run by five fresh contexts.** No repair in this programme may be authored by a
reviewer of it.

# ROUND 5 — the round-4 repaired candidate `7f043a2..ac962bb`

Candidate: `7f043a2..ac962bb`, pinned (HEAD was `46dc6da`; one governance commit sits above the range).
Round run: 2026-08-03, full ADR-026 five-lens form, five reviewers in five independent contexts with no
shared conversational state.

**VERDICT: FAIL. Four of five lenses. FIVE confirmed-blocking findings. S-07-009 IS NOT ACCEPTED.**

| Lens | Verdict | In-candidate blocking |
| --- | --- | --- |
| Contract-correctness | FAIL | R5-1, R5-2 |
| Concurrency / atomicity / idempotency | FAIL | R5-3 |
| Schema / migration-safety | FAIL | R5-4 |
| Architecture / scope / test-quality | FAIL | R5-1, R5-2, R5-5 |
| Security / tenant-isolation | PASS_WITH_OBSERVATIONS | 0 |

**FOUR OF THE FIVE BLOCKERS ARE DEFECTS IN ROUND 4'S OWN REPAIRS.** The pattern is now five rounds old
and has not weakened once: round 2 found two defects in round 1's repairs, round 3 refuted all three of
round 2's, round 4 found five in round 3's, and round 5 finds four in round 4's. **A repair that is
present, gated green and mutation-proved against one named mutation is still not evidence that it is
correct.**

## Confirmed blockers

**R5-1 — R4-6's `other_hard_limit?` suppresses the wall-clock record for bounds that stop nothing.**
`crawl_start_store.rb:282-288`, consumed at `complete_crawl.rb:347`. Reached independently by the
contract and architecture lenses.

:442 defines TWO classes of hard limit. Six named bounds — "A URL deeper than 10, response with a
sentinel beyond 10 MiB on either byte path, request exceeding 15 seconds, fourth-level sitemap index,
fifty-first sitemap, or eleventh redirect" — **fail that URL** and the run continues. Only "at ANY OTHER
hard limit" is it "stop scheduling affected work". :442 further requires `CrawlLimitReached` **exactly
once PER DIMENSION and run**, so the wall clock is entitled to its own record.

The guard matches `limit_dimension <> 'wall_clock_run_duration'` — any dimension. One oversized page at
minute two therefore suppresses BOTH wall-clock limbs, hard and soft, for a run that abandoned thousands
of candidates at minute sixty. Immutable and uncorrectable.

**THE REPOSITORY ALREADY CARRIED THE CORRECT CLASSIFICATION AND THE REPAIR DID NOT USE IT.**
`limit_decisions.rb:139`: `RUN_STOPPING = ["accounted_response_body_bytes_per_run",
"wall_clock_run_duration"]`, commented "exactly the two bounds that DO stop scheduling — every other
dimension abandons something NARROWER".

*Why the proofs missed it:* PROOF 131 **pins the defect**. It uses `response_body_per_url` — one of the
six :442 says merely fails a URL — as its "other hard bound that halted the run", and asserts the
suppression is correct. **VERIFIED BY EXECUTION:** restricting the guard to a genuinely run-stopping
dimension makes PROOF 131 FAIL (`the wall clock claimed ["1", "0"] URLs`). The correct fix breaks the
proof written to defend the repair.

**R5-2 — R4-1 repaired one call site of a defect class with several live sites, and locked the fix away.**
`fetch_content.rb:167`, `complete_crawl.rb:327` and `:365`, all in range. Contract and architecture lenses.

`Time#to_s` formats to whole seconds and the raw connection decodes `timestamptz` to a microsecond
`Time`, so `Time.parse(x.to_s)` truncates. R4-1 fixed `cancel_crawl.rb` and made `utc_instant` a PRIVATE
method of that class, so no other reader can use it. `complete_crawl.rb:327` therefore lets a checkpoint
delivered in `[floor(deadline), deadline)` terminalize a **still-running** Crawl up to a second early and
write an immutable hard `wall_clock_run_duration` decision; `:365`'s `elapsed_minutes` can report 60 for
a 59.99-minute run. **After R4-1 the two handlers disagree about where :458's boundary is.**

*Why the proofs missed it:* exactly R4-1's own stated reason — every checkpoint fixture ages the run
through `DbInspector`'s untyped connection, i.e. whole-second instants on a different decoding path.
PROOF 128/129 cover `CancelCrawl` alone.

**R5-3 — a SECOND frontier/crawls lock inversion survives R4-2, and this range is what makes it a
deadlock.** `admission.rb:147 -> :152` against `cancel_crawl.rb:117-118` and `complete_crawl.rb:117-118`.
Concurrency lens.

`Admission#claim` writes a `crawl_limit_decisions` row — which carries an FK to `crawls` and therefore
takes `FOR KEY SHARE` — on the SOFT wall-clock limb, which **falls through** rather than returning, and
only then takes `crawl-frontier:<crawl>` at `:152`. So:

    T1 Admission    holds crawls FOR KEY SHARE  ->  waits crawl-frontier
    T2 CancelCrawl  holds crawl-frontier        ->  waits crawls FOR UPDATE

`FOR UPDATE` conflicts with `FOR KEY SHARE`. **This was inert before the candidate**: nothing took
`FOR UPDATE` on `crawls`, and `start`/`fail`/`cancel` are bare UPDATEs taking `FOR NO KEY UPDATE`, which
does not conflict. `lock_crawl` was introduced by `ee8dbe0` INSIDE this range and is used only by the two
handlers this range adds. **The candidate creates the cycle.** `Handlers::CancelCrawl` contains no
rescue, so a customer command surfaces a raw `PG::TRDeadlockDetected` where ADR-103 and :458 require a
`Platform::CommandResult`.

**VERIFIED BY EXECUTION:** the lock pairing was reproduced directly on PG 17 — `T1:
PG::TRDeadlockDetected ERROR: deadlock detected`, SQLSTATE 40P01. The FK, the fall-through soft limb and
the in-range introduction of `lock_crawl` were each verified from the catalogue and the source.

`ac962bb`'s claim that `StartCrawl` was "the subsystem's ONLY lock-order inversion" is false.

*Why the proofs missed it:* every lock proof in the candidate races a transaction that ALREADY holds the
frontier lock (PROOF 91/100/101/117 gate after it) or one holding nothing (110/118). No proof gates a
transaction holding a `crawls` FK lock that has not yet reached the frontier lock. PROOF 126 was written
for exactly this class and covers only the StartCrawl pair.

**R5-4 — the R4-8 record repair introduced a NEW false statement, inverting the lesson it records.**
`S-07-009_COMPLETION_REPORT.md:79` and `:82`. Schema lens.

The rewritten table says migration 350 "Shipped the Source link with **FK arity 2**, which `…380`
repairs". **No foreign key on `source_id` ever existed.** VERIFIED three ways: migration 350's only
commit contains zero `source_fk` matches; migration 380's own header says the link "carried **NO** foreign
key at all"; the live catalogue shows three FKs, all arity 3. The statement REPLACED a true one ("the
composite Source link the review found missing").

It matters because PROOF 39 enumerated `pg_constraint` and asserted arity on **every row returned** — an
arity-2 FK is precisely what it WOULD have caught. It was blind to ABSENCE. The false correction destroys
the one lesson ADR-110 calls "the more important half".

**R5-5 — the acceptance record still describes a superseded candidate and contradicts itself.**
Contract, schema and architecture lenses independently. At `ac962bb`: `:6` "Three full ADR-026 five-lens
rounds have run … a fourth round is owed" (four have run; round 4's review `686bf5e` is INSIDE the
range); `:26` pins `7f043a2..7034e25`, which excludes every round-4 repair, while `:204` instructs the
reviewer to take the range from §Identity and nowhere else; `:98` "Review history — three rounds, three
FAILs" omits round 4; `:195` lists FU-38 "Open and unchanged" and `:186` still states FU-41's superseded
reasoning, while `BUILD_STATE` marks both `resolved` in the SAME commit; the proofs table is split by an
interposed paragraph so four rows render as literal pipe text. R4-8 made the report internally consistent
about round 4 and did not advance it for the round it was itself creating.

## What round 5 confirmed sound

**The security lens returned PASS_WITH_OBSERVATIONS with zero blocking, having re-derived R3-10 from the
ratified table rather than trusting it.** It enumerated all sixteen materialized capabilities and read
each one's sixth cell directly: every one is `deny`, so `READ_ONLY_CAPABILITIES = []` is correct and the
corrected count is true. `permission_mode` is `NOT NULL` with a two-value CHECK, so `mode_permits?` is
total and `standard` actors are provably unaffected on every path including `bootstrap_admin_exception`.
Exactly four `UPDATE crawls` statements exist application-wide and every terminal-producing one is
authorized; `CancelCrawl` is correctly absent from the ScheduledAction registry. PROOF 40a/40b genuinely
exercise the RLS policy rather than a foreign-key refusal. No `f1` role holds `SUPERUSER` or `BYPASSRLS`;
every table the candidate touches has FORCE RLS with the correct tenant predicate.

Also confirmed: R4-2 genuinely closes the StartCrawl↔CancelCrawl cycle **for its named pair**, and the
frontier lock is released correctly on both rollback paths; R3-1's "one caller, one reason" claim is true;
R3-3's `CrawlCanceled` envelope is correct; R4-3's contract half is correct — :452's exclusion list is
exactly four conditions and only `policy_excluded` maps to `excluded`; the `IS NOT DISTINCT FROM`
refutation is true, re-evaluated live on PG 17.10; R3-P1/P2/P3 remain genuinely pre-existing and outside
the range; the only frozen-path touch is the ADR-027/029 additive grant, so no escalation is owed.

## Notable non-blocking observations

- `cancel_crawl.rb:117` takes an org-agnostic advisory lock on a caller-supplied `crawl_id` BEFORE any
  tenancy check (R3-6). Both the security and concurrency lenses judged it non-blocking — every holder
  works inside a short DB-only transaction and no cycle is constructible — but it is a real cross-tenant
  timing channel, and `StartCrawl` shows the shape that avoids it.
- PROOF 126's `ROW_WAIT_SQL` has no "behind our winner" filter, so it counts ANY ungranted row waiter in
  the database. It is only a disjunct of the wait, but on a busy shared database it can short-circuit the
  wait before the cancellation reaches `lock_frontier` and fail the assertion spuriously — the R4-4 defect
  class reintroduced as a disjunct in the proof that repairs R4-2.
- `blocked_on(gate_key)` uses FIXED gate names in PROOF 91/92/117/126, so two concurrent runs of one file
  satisfy each other's predicate. `race_harness.rb`'s "no unrelated transaction can satisfy this" claim is
  true only of the per-crawl frontier keys.
- `FetchContent#fetch`'s `rescue StandardError` swallows the bounded-wait raise, so a `POP_TIMEOUT_S`
  timeout reaches the reader as an unrelated assertion mismatch rather than as its own message.
- FU-41's and FU-38's closing claims are false: `CrawlStartStore#fail` writes the `crawls` row from the
  gate path, which never reaches `lock_frontier`. FU-41's CONCLUSION (retain `FOR UPDATE`) survives, but
  through `#fail` rather than the `#start` argument the record gives.
- PROOF 78's `not_to include(:excluded)` cannot fail given the `contain_exactly` on the next line; PROOF
  131's closing `expect(hard).not_to be_empty` cannot fail given its own precondition.
- `permission_baseline.rb`'s description of the Read-Only column's non-deny cells as "READ capabilities"
  is inaccurate for `session.terminate` and `export.create`; the operative claim (none are materialized)
  is true.

## Repair programme, in dependency order

1. **R5-3 first.** A deadlock in a customer command, in the lock graph everything else races on, and the
   second one this tranche has produced.
2. **R5-1** — the run-stopping classification already exists; the wall clock's own per-dimension record
   is a contract obligation.
3. **R5-2** — the truncation must be repaired as a CLASS, not one call site at a time.
4. **R5-4 and R5-5** — the record, written against the final vocabulary and the round it is creating.

**Round 6 must be run by five fresh contexts, and no repair may be authored by a reviewer of it.**

# ROUND 6 — the complete resulting state through `cf2059e`

Implementation candidate: `7f043a2..5860bb4`, pinned (not `..HEAD`). Governance-record commit:
`cf2059e`. Review scope: the complete resulting state through `cf2059e`, so the reviewers inspected both
the implementation candidate and the record-only commit while keeping their roles distinct.

Round run: 2026-08-03, full ADR-026 five-lens form, on the owner's explicit instruction after the
round-5 repair stop. Five reviewers ran in five fresh independent contexts with no shared conclusions
and no repair authorship. Every reviewer was read-only. The owner's instruction superseded ADR-117's
earlier “do not commission Round 6” terminus for this one review; it did not authorize a repair cycle.

**VERDICT: FAIL. All five lenses. NINE confirmed-blocking findings. S-07-009 IS NOT ACCEPTED.**

| Lens | Verdict | Confirmed blocking |
| --- | --- | --- |
| Contract-correctness | FAIL | R6-2, R6-3, R6-4 |
| Concurrency / atomicity / idempotency | FAIL | R6-1, R6-2, R6-3 |
| Security / tenant-isolation | FAIL | R6-1, R6-5, R6-6 |
| Schema / migration-safety | FAIL | R6-2 |
| Architecture / scope / test-quality | FAIL | R6-7, R6-8, R6-9 |

## Confirmed blockers

**R6-1 — Admission revalidates state after the frontier wait, but reuses the pre-wait instant.**
Security and concurrency independently. `Admission#claim` takes `lock_frontier`, re-reads the Crawl and
policy, then calls `authorize(..., now)` and `wall_clock(..., now)` with the caller's original instant.
That value was captured before the wait. A real-PG interleaving held the actual Crawl frontier lock until
`clock_timestamp()` was after `deadline_at`; Admission then returned admitted, claimed one frontier row
and reserved 10,485,760 bytes. The observed release was after the deadline. The same stale instant lets
an entitlement whose lease expires during the wait pass `reservation_executing?`. This violates :442's
“no new request starts” boundary, :551's strict-before lease rule and ADR-117's post-wait reauthorization.

**R6-2 — the terminal fact set remains appendable after the once-only terminal commit.** Contract,
concurrency and schema independently. The hard-expired Admission branch records soft/hard wall-clock
decisions without taking frontier and without a terminal-state re-read. In a deterministic PG race,
CancelCrawl held frontier and `crawls FOR UPDATE`, transitioned to `canceled`, and held the transaction;
Admission read the committed `running` preimage and blocked on the child FK's implicit tuple lock. After
CancelCrawl committed, Admission committed both immutable decisions onto the canceled Crawl. Catalog
inspection proves the general backstop gap: `f1_runtime` retains INSERT on both
`crawl_limit_decisions` and `crawl_terminal_outcomes`; their guards cover UPDATE/DELETE only; their Crawl
FKs and RLS predicates validate identity/tenant, not parent state. A valid child fact can therefore be
inserted after any terminal state and permanently disagree with the frozen Crawl outcome. :458's
serialized-once selection and the immutable-first-decision rule fail.

**R6-3 — CompleteCrawl does not serialize with in-progress sitemap discovery.** Contract and concurrency
independently. Discovery commits `sitemap_state='in_progress'`, performs traversal outside that
transaction, and neither holds the Crawl frontier lock throughout nor re-reads terminal Crawl state
before offering URLs and committing the gate outcome. CompleteCrawl reconciles only `pending` gates and
its fact query excludes `in_progress`. A deterministic application/PG race held discovery in its real
outbound request, ran the real deadline checkpoint to a committed `failed` Crawl, then released a valid
sitemap. Discovery returned `succeeded` and inserted `/late` as a queued sitemap frontier entry after the
Crawl was terminal. A second variant committed `sitemap_unavailable` after the checkpoint had recorded
`unresolved_discovery=0`. The supposedly frozen :450/:458 fact snapshot is not frozen.

**R6-4 — the checkpoint invents `sitemap_unavailable` for a merely pending, unattempted gate.** Contract
alone. `resolve_pending_sitemaps` turns every pending non-robots-failed gate into unavailable. Pending does
not establish either :450 antecedent — a declared sitemap exists, or the default returned non-404/410 —
and does not prove retries/validation completed. PROOF 67 itself uses allow-all robots with neither a
declared sitemap nor a default fetch, then requires `sitemap_unavailable`. Volume I :450 wins over the
BUILD_PLAN transfer prose and does not admit that invented observation.

**R6-5 — CancelCrawl can commit after the human authority it used has been revoked.** Security alone.
CancelCrawl authenticates and authorizes, can then wait at `lock_frontier`, and performs the irreversible
cancel/release/event sequence without checking the Organization authorization epoch again. The repository
already provides `CommandAuthorizer.authority_current?` for exactly “authorize, wait, protected side
effect”; this handler does not call it. A revocation, suspension or policy change can commit while the
command waits, after which the stale allowed decision still cancels the Crawl. This violates :335 and
SEC-REQ-004/005.

**R6-6 — CompleteCrawl settles entitlement using an instant captured before its frontier wait.** Security
alone. The handler captures `now`, later waits on frontier/Crawl, terminalizes, and calls entitlement
commit with the old value. `Entitlement::Service#commit` chooses commit versus release from the supplied
timestamp, so a reservation can be committed even though the durable terminal point occurred at or after
its effective deadline. :551 makes expiry win at equality and requires the commit point to be strictly
before expiry.

**R6-7 — the authorized timestamp detector has trivial syntax escapes.** Architecture alone. Directly
calling the committed `violations` helper returned an empty finding set for all four obvious local
decoder/type-dispatch forms:

```ruby
Time.zone.parse(value.to_s)
Time.rfc3339(value.to_s)
value.respond_to? :getutc
Time === value ? value.getutc : value
```

The detector's synthetic tests restate only the AST forms it recognizes. A second local decoder can enter
the derived tracked corpus while the check remains green, contrary to ADR-117's explicit detection and
self-test criterion.

**R6-8 — ADR-117 falsely says it recorded authority before implementation.** Architecture alone. History
is `fc069c9` (round-5 review), `f7472aa` (PgInstant implementation), `5860bb4` (ADR-117 plus repairs), then
`cf2059e` (records). ADR-117 is absent from the parent of `f7472aa`, yet says both that it records the
authority “before implementation” and that “Record this ruling” is the first binding step. This conflicts
with the repository-as-authority rule in AUTONOMOUS_BUILD_CONTROLLER §2.1.

**R6-9 — the completion report's mechanically stated proof count is false.** Architecture blocker,
independently corroborated as a contract observation. The report defines its numbers as distinct
`PROOF n` identifiers and reports 13 for `crawl_terminal_outcome_invariants_spec.rb`. The file contains
16: PROOF 30 through 39, 39b, 40, 40a, 40b, 41 and 42. The prior round-4 review had already recorded the
13-versus-16 discrepancy; the R5-5 rewrite retained it. This fails the owner-required accuracy and
internal-consistency review and repeats the false-evidence-record blocker class.

## Evidence established by execution

The concurrency reviewer ran 91 committed focused PostgreSQL examples with zero failures, then three
additional deterministic real-PG interleavings. Those interleavings, not the green examples, established
R6-1, R6-2 and R6-3. The committed proofs remain genuinely useful but incomplete: PROOF 132 detects the
original decision-before-frontier inversion; PROOFs 133-135 keep their races inside the soft fall-through
branch and do not cross the deadline or enter hard-expired Admission; checkpoint/pass races fence
retirement, not sitemap traversal.

The schema reviewer used read-only PG17 catalog queries. It confirmed ENABLE+FORCE RLS, exact-org policies,
validated arity-3 outcome links, SELECT/INSERT-only runtime grants, migration/structure parity, and the
truth of the repaired migration-350/380 record. The same catalog showed no INSERT guard closing the child
fact set after parent terminalization.

The architecture and contract reviewers each ran 21 focused non-truncating examples with zero failures;
security ran 11 plus Brakeman with zero warnings. All five checked the exact committed range and left the
worktree unchanged. No full suite was rerun because the first confirmed blocker made acceptance
impossible and the user required reviewers to stop without repairing.

## Confirmed sound and carried observations

The original R5-3 Admission soft-path deadlock is repaired: the real insert probe is non-vacuous, both
named terminal orientations avoid 40P01, and losing fall-through Admission produces no durable effect.
The twelve-row classifier's live projections correctly separate decision production, terminal forcing,
default affected counts and unselected-frontier ownership; rate/concurrency remain pacing-only. PgInstant
itself preserves typed/text/nil/subsecond/UTC/nonmutation semantics and PROOF 145 independently drives the
real checkpoint boundary. RLS, tenant predicates, fixed SQL parameters and the migration-380 Source link
are sound.

Carried non-blocking observations remain carried, including the bounded cross-tenant advisory-lock timing
channel, FU-2 GrantScope containment, the outcome links not tying Crawl/Source to the chosen frontier
entry, FU-12's service-identity link, FU-40's empty `failed_attempts`, and the pre-existing BUILD_PLAN YAML
parse failure. None is silently repaired or promoted by this record.

## Stop

This review authorizes no repair. S-07-009 remains NOT ACCEPTED. Do not merge, push, begin S-07-010, or
start another repair cycle from any of the reviewer contexts. FU-32, FU-33, FU-43 and R3-P1..R3-P3 are
unchanged.

# ROUND 7 — the round-6 repair candidate `7f043a2..4e2d8cf`

Implementation candidate: `7f043a2..4e2d8cf`, pinned (never `..HEAD`). Governance commit: `72724f1`.
Review HEAD: `9720d25`. Round run: 2026-08-04, full ADR-026 five-lens form, on the owner's explicit
final-acceptance instruction.

**EXCLUDED FROM THE ACCEPTANCE DIFF: `9720d25`.** That commit contains five owner-authored markdown
files under `branding/`, `investor/`, `operations/` and `research/` and nothing else. Verified by the
architecture lens: it touches zero files under `app/ db/ spec/ specification/ schemas/ lib/ config/
governance/ DECISIONS.md`, and neither `4e2d8cf` nor `72724f1` touches any owner-material path. It is
present in the reviewed state as unrelated content and is not product implementation evidence.

**VERDICT: FAIL. Three of five lenses. FIVE confirmed-blocking findings. S-07-009 IS NOT ACCEPTED.**

| Lens | Verdict | Confirmed blocking |
| --- | --- | --- |
| Contract-correctness | PASS_WITH_OBSERVATIONS | none |
| Concurrency / atomicity / idempotency | FAIL | C-1, C-2 |
| Security / tenant-isolation | FAIL | SEC-B1 |
| Schema / migration-safety | PASS_WITH_OBSERVATIONS | none |
| Architecture / scope / test-quality | FAIL | A-1, A-2 |

## Review conditions, and a methodology fault in this round's own setup

Five fresh contexts, none of which authored the round-6 repairs, reviewed the complete resulting state
in a detached worktree at `9720d25`. Each had its own database, provisioned FROM EMPTY by the migration
chain under review, so "the schema builds from empty" is established five times independently.

**THE FIVE LENSES SHARED ONE WORKTREE, AND THAT WAS AN ERROR BY THE REVIEW COORDINATOR.** Databases
were isolated; the working tree was not. Three lenses independently observed foreign live mutations to
tracked files mid-run (`app/platform/pg_instant.rb` twice, `handlers/complete_crawl.rb`,
`crawl_start_store.rb`). This is the repository's own one-session-per-worktree rule, broken by the
setup rather than by the candidate. Its cost was measured and contained rather than assumed:

* the contract lens detected a contaminated run, discarded it (50 examples / 1 failure), waited, and
  re-ran clean (50 / 0);
* the architecture lens found its own backup had captured a foreign mutation, discarded that round and
  redid every mutation in an isolated copy of HEAD;
* the concurrency lens never edited a tracked file at all, worked in an isolated copy throughout, and
  re-ran every finding end to end after the coordinator's stop-order, reproducing each identically;
* the schema lens refused to revert another lens's in-flight mutation on the grounds that doing so
  could hand that lens a false PASS, and reported it instead.

No mutation was banked. The review worktree ended pristine against `9720d25` and no commit was made in
it. Every finding below was re-verified in clean conditions by the lens that raised it. The fault
cost time and required re-runs; it did not produce any finding recorded here.

## Confirmed blockers

**C-1 — `after_wait` is blind to elapsed time before `BEGIN`, which is exactly where the driver spends
its outbound work.** Concurrency. `Platform::PgInstant.after_wait` returns
`entered_with + (clock_timestamp() - transaction_timestamp())`, and that delta measures elapsed time
since BEGIN only. `CrawlDriver#advance` captures `now` once at the top, then performs the robots fetch
and sitemap discovery OUTSIDE every transaction — up to eleven bounded requests and roughly 165 seconds
for robots alone by `EnsureRobots`' own accounting — and hands that same instant to `claim_entry`. The
elapsed time in that window is invisible to the repair. Reproduced: with 1.5s burned AFTER BEGIN the
admission correctly refuses `wall_clock_exhausted` and claims nothing; with the identical 1.5s burned
BEFORE BEGIN it admits, reserves 10,485,760 bytes and claims a frontier entry — the same figure ADR-118
recorded for the original R6-1. `reservation_executing?` takes the same value, so :551's lease limb has
the identical hole. `crawl_driver.rb:133` already carries `entered_monotonic` for precisely this
problem on the request budget and does not pass it to Admission. :442's "no new request starts" and
ADR-120 Ruling 1's "current database time". The lock-wait limb IS genuinely repaired; the fix is right
in kind and incomplete in reach. Owner: `Wf005::Admission` / `CrawlDriver#advance`.

**C-2 — Ruling 2's controlled-outcome half is implemented for one producer only.** Concurrency.
ADR-120 Ruling 2 requires that "a stale or late worker must receive a controlled domain outcome and
must not append facts after terminalization." The database half is sound and proved. The translation
half exists at exactly one site, `discover_sitemaps.rb:717`. `EnsureRobots#record`/`#decide` write
`robots_state`, `robots_terminal_reason` and `robots_terminal_at` — all governed by
`crawl_host_gates_terminal_outcome_closure` — with no translation, and `CrawlHostGateStore` line 39's
gate INSERT is likewise governed and untranslated. Reproduced with the tranche's own PROOF-159 device:
a cancellation committing during the robots fetch makes `PG::RaiseException:
crawl_child_fact_after_terminal` escape `EnsureRobots#call`, leaving the gate `robots_state`
`in_progress`; `ScheduledActions::Worker#run_handler:142` then classifies it
`scheduled_action_execution_failed`, the token meaning DEFECT — which is exactly what
`discover_sitemaps.rb`'s own comment says must not happen. `EnsureRobots` holds no advisory lock across
its fetch, so nothing serializes it against the terminal handlers. THE CONVERSE WAS RUN SERIALLY AND
CONFIRMS THE TRANSLATION IS LOAD-BEARING: commenting out the `CrawlWentTerminal` raise fails PROOF 159
and PROOF 160 with an uncaught `PG::RaiseException` at `discover_sitemaps.rb:183`, so its absence next
door is a gap and not redundancy. Bounded: no corruption, the fact is correctly refused, the residue is
one defect-classified transport failure plus a stranded `in_progress` robots claim. Owner:
`Wf005::EnsureRobots` and the driver's `ensure_gate`.

**SEC-B1 — `CancelCrawl` is not the only WF-005 handler that authorizes a human capability and then
waits.** Security. ADR-120 Ruling 1 draws its line at "can wait", and states that the ADR-063/S-06-006
deferral "does not apply once a command can wait before an irreversible effect; that deferral continues
to cover handlers that authorize and act with no wait between the two." Two handlers meet the
antecedent and were not repaired: `handlers/queue_crawl.rb` authorizes `crawl.trigger` at :68, takes
`pg_advisory_xact_lock('crawl-queue:<org>:<project>')` at :75 and commits at :98; and
`handlers/activate_crawl_policy.rb` authorizes `policy.crawl.manage` at :60, takes
`pg_advisory_xact_lock('crawl-policy:<org>')` at :71 and commits at :91. Neither calls
`authority_current?` and neither constructs `PostWaitDecision`. Both reproduced on real PostgreSQL by
advancing `organizations.authorization_epoch` under an OBSERVED ungranted waiter: QueueCrawl committed
a Crawl (0 -> 1) and ActivateCrawlPolicy committed a policy (0 -> 1), each on an authority that no
longer existed at the moment of the effect. QueueCrawl additionally creates the `crawl_dispatch`
action, so the revoked authority goes on to start a metered run that makes outbound requests.
:333/:335, SEC-REQ-004/005. The window is narrower than CancelCrawl's — these two keys are only ever
held by database-only critical sections, never across an outbound fetch — but the ruling's own line is
"can wait", and R6-5 was confirmed blocking on exactly that reasoning. Owner: the two handlers, through
the existing `Wf005::PostWaitDecision`.

**A-1 — R6-7 is not closed: the "structural ban" is still an enumeration.** Architecture. The detector
inverted from four forbidden SPELLINGS to two forbidden NAMES, and a name can be renamed around exactly
as a spelling can be respelled. NINE decoder and type-dispatch forms were injected into the real tracked
corpus and the committed frozen check stayed green at 7 examples / 0 failures: `row["x"].to_time`,
`.to_datetime`, `.in_time_zone`, `respond_to?(:strftime)`, `acts_like?(:time)`,
`Object.const_get("Time").parse`, `ActiveSupport::TimeZone["UTC"].parse`, `class.name == "Time"`, and
`send(:strftime, ...)`. Twenty-odd further forms evade the helper directly. The sharpest instance is
`to_time`, which the check bans as a SYMBOL and permits as a CALL: the file's own justification for
permitting calls is about `getutc`, where formatting an instant you already hold is genuinely different
from decoding one, and that reasoning does not transfer to `to_time`, which decodes. Confirmed
independently at the AST level: `row["x"].to_time` yields no `@const` token and `to_time` as an
`@ident` in call position, so neither rule fires. R6-7's original wording — "a second local decoder can
enter the derived tracked corpus while the check remains green" — remains literally true. ADR-117 R5-2
requires the check to "detect local parsing and type-dispatch decoders"; ADR-120 :3266-3268 and
`S-07-009_COMPLETION_REPORT.md:148-154` assert a completeness the check does not have. Owner:
`spec/architecture/wf005_time_single_surface_spec.rb`, a FROZEN PATH, so the repair needs the same
explicit recorded owner authority ADR-120 supplied for the round-6 change.

**A-2 — the record states false, mechanically countable facts about itself.** Architecture, and it is
the R6-9 class recurring inside the repair that closes R6-9. Two instances. (1) `COMPLETION_REPORT
:153` says "Both `.getutc` METHOD CALLS in the corpus are untouched and correct" and the frozen check
at `:36-37` and `:230-235` says "the two `.getutc` method CALLS", enumerating them as `CrawlLedger#iso`
and `CrawlDriver`'s due-instant comparison. There are NINE, in five files: `crawl_driver.rb:241`,
`crawl_ledger.rb:145`, `handlers/start_crawl.rb:407,686,691`,
`handlers/record_fetch_attempt.rb:206,344`, `handlers/complete_crawl.rb:557,562`. Seven were missed, in
a file whose own header calls hand enumeration "PROOF 39's mistake in a third costume". (2) PROOF 145's
margin is stated three ways: `COMPLETION_REPORT:136-140` says 400ms, its own mutation table at `:229`
still says "one microsecond", and `wf005_terminal_checkpoint_spec.rb:910-911` says "one-microsecond-
before" eleven lines below the comment at `:867` that says "THE MARGIN IS 400ms, NOT ONE MICROSECOND".
The new in-flight truth check catches neither: it re-derives proof COUNTS and resolves CITATIONS, and
nothing else in the record is mechanically bound. Owner: `S-07-009_COMPLETION_REPORT.md`, the frozen
check, and `wf005_terminal_checkpoint_spec.rb`.

## What the round confirmed genuinely repaired

R6-5 is closed: epoch advanced during the frontier wait produces a refusal, the Crawl stays `running`,
no `CrawlCanceled` is emitted and the reservation stays `executing` at an unchanged `state_version`;
the control case commits. R6-6 is closed and discriminating: a committing run whose lease lapses during
the wait is `completed` / `released` with zero commit intents, while the identical run with a live lease
and the same wait commits. R6-2 and R6-3's DATABASE enforcement is real: the late insert observably
blocks on the parent row with the causal edge verified through `pg_blocking_pids`, is rejected after the
terminal commit, writes zero rows, and the terminal transition survives intact. Dropping only
`crawl_frontier_entries_terminal_closure` reproduces R6-3 exactly, which establishes that the rule is
database-owned rather than application-owned. R6-8 is closed: ADR-117 has zero occurrences in
`fc069c9`, `f7472aa` and `f7472aa^` and one in `5860bb4`, and the replacement paragraph is true of git.
:450's three states are genuinely distinguished and the two SQL predicates are provably disjoint
against the live CHECK domain. `unattempted_discovery` enters at exactly one site and is a pure monotone
move toward `partial`, so it cannot make a run report better than it was. Lock order is one order
throughout, `crawl-frontier:<crawl>` then `crawls`, with no reverse edge and zero deadlocks in 48
contended operations. The migration is exactly reversible with the catalog byte-identical after redo,
purely additive against `db/structure.sql`, and no pre-existing guard is weakened. Cross-tenant writes
are refused BY RLS with byte-identical messages and no timing channel. All four round-6 escapes are
genuinely closed. Every claimed round-6 mutation was independently re-run and each killed its named
proofs; no proof survived its mutation.

## Carried non-blocking observations

Recorded in full so none is lost and none is silently repaired: the `:458` citation for
`unattempted_discovery` names the wrong sentence (the final `full`-is-only-when sentence carries it, not
the not-evaluated one); the withdrawn FU-9 rationale block survives in `crawl_start_store.rb:337-351`
and now reads as documentation for `insert_evaluation`; `Entitlement::Service#commit`'s `>=` equality
rule is pinned by no proof and `>=` -> `>` survives 50 examples (F-05's, outside this range); PROOF 69
is used twice; PROOF 67's completion-reason assertion is vacuous on a `failed` run; PROOF 157 does not
pin `sitemap_limit_reasons` and narrowing the WHEN clause survives the whole 241-example persistence
suite; `CrawlStartStore#fail` takes `FOR NO KEY UPDATE`, which does not conflict with the closure's
`FOR KEY SHARE`, so the migration header and ADR-120 overstate the guarantee (latent, not live); two
exclusion reasons in `UNGOVERNED_WITH_REASON` are factually wrong though both exclusions are correct;
post-terminal `crawl_frontier_entries.state` UPDATE is ungoverned; the ADR-117 provenance guard is a
literal-string regex any reword walks through; the proof table's measure counts cross-references,
overstating by 8; `BUILD_PLAN.yml:966` still reads "FU-9 closed by transfer to S-07-009"; the
pre-existing BUILD_PLAN YAML parse failure and the bounded cross-tenant advisory-lock timing channel
remain carried.

## Stop

This review authorizes no repair. S-07-009 remains NOT ACCEPTED. Do not merge, push, begin S-07-010, or
start a repair cycle from any reviewer context or from the round-6 repair-author context. FU-32, FU-33,
FU-43 and R3-P1..R3-P3 are unchanged.

# ROUND 8 — the round-7 repair candidate `7f043a2..e1f5bab`

Implementation candidate: `7f043a2..e1f5bab`, pinned. Governance commit: `5dadf7f`. Review HEAD:
`5dadf7f`. Round run: 2026-08-04, full ADR-026 five-lens form, on the owner's explicit instruction.

**EXCLUDED FROM THE ACCEPTANCE DIFF:** `9720d25` (owner branding/investor/operations/research markdown),
`5261cee` and `d52e66a` (the round-7 findings records). Two lenses independently confirmed the exclusion
is substantively sound — `9720d25` touches zero paths under `app/ db/ spec/ specification/ governance/
lib/ config/` — and both also recorded that all three are ANCESTORS of `e1f5bab`, so the two-dot range
literally contains them and the exclusion list is what makes it an implementation diff. The round-7
repair commit `e1f5bab` is itself clean: 17 files, all `app/` and `spec/`.

**ISOLATION.** Six separate worktrees at review HEAD and six databases provisioned FROM EMPTY by the
candidate's own chain, one per lens plus an unused acceptance environment. No worktree or database was
shared. Every lens ended with no modified tracked file. **ONE ISOLATION GAP REMAINED AND IS RECORDED
RATHER THAN GLOSSED:** Redis at `127.0.0.1:6379/0` is shared across lenses, which produced one spurious
`f04_background_execution_acceptance_spec.rb` failure in the concurrency lens's full-suite sweep (8/8 in
isolation). Databases were isolated; Redis was not. A future review must isolate it too.

**VERDICT: FAIL. Four of five lenses. NINE confirmed-blocking findings. S-07-009 IS NOT ACCEPTED.**

| Lens | Verdict | Confirmed blocking |
| --- | --- | --- |
| Contract-correctness | FAIL | R8-2, R8-3, R8-4, R8-7, R8-8 |
| Concurrency / atomicity / idempotency | FAIL | R8-1, R8-3, R8-9 |
| Security / tenant-isolation | FAIL | R8-4, R8-5 |
| Schema / migration-safety | PASS_WITH_OBSERVATIONS | none |
| Architecture / scope / test-quality | FAIL | R8-6, R8-7, R8-8 |

## The shape of this round

EVERY BLOCKER BUT ONE IS A PROOF DEFECT, NOT A BEHAVIOUR DEFECT. Three lenses independently verified
that the shipped code is CORRECT on every path they exercised: C-1's anchor makes elapsed time before
and after `BEGIN` equivalent, C-2's three producers all return controlled outcomes, and SEC-B1's two
handlers both refuse under an observed ungranted waiter with the epoch advanced underneath. What fails
is what DEFENDS those repairs. A control no proof pins is a control the next tranche deletes silently,
and this tranche's own history is the argument: R5-2, R6-7 and A-1 were each that failure one round
earlier.

## Confirmed blockers

**R8-1 — the C-1 anchor is unproved at the only production call site that motivates it.** Concurrency.
`CrawlDriver#advance` captures the anchor at `crawl_driver.rb:144` and admits at `:190`. Replacing
`anchored_at` with `nil` at `:190` restores the exact C-1 defect and **survives 2148 examples, 0
failures**. A second variant, recomputing the anchor after the pre-transaction work, survives 1818.
Reproduced on real PostgreSQL: a run one second inside its deadline that spends 1.6s in its robots fetch
is ADMITTED — frontier entry `in_progress`, bytes reserved, a `crawl_terminal_outcomes` row written
`limit_discarded / not_covered` — where :442 requires refusal with zero effects. PROOF 164 and 165 call
`Admission#claim_next` DIRECTLY with an explicit anchor and never exercise the driver, so the
propagation that is the whole repair is untested. Inside range. Owner: the C-1 proof surface.

**R8-2 — C-2 is not closed: `FetchContent#settle` is a third untranslated producer.** Contract.
`fetch_content.rb:702` opens a bare `Platform::UnitOfWork.run` with no `ClosedFactSet.translate` and
reaches `INSERT INTO crawl_limit_decisions` through `observe_fetch_limits` at `:744`. This is on the one
path in the workflow that spends unbounded real time outside every lock — the content request. Round 7
enumerated two producers and the repair fixed those two; this third was named by neither. Reproduced end
to end, directly and through the driver: `PG::RaiseException: crawl_child_fact_after_terminal` escapes
`CrawlDriver#advance`'s rescue and reaches `ScheduledActions::Worker`, which classifies it
`scheduled_action_execution_failed` — the token meaning DEFECT. The contract lens enumerated every
governed writer and confirmed the remainder are covered. Inside range: the closure trigger and the
completeness claim are both in-range, so the failure mode exists only because of in-range changes.
Violates owner ruling 2 and `closed_fact_set.rb:18`'s own assertion that "every producer wraps its unit
of work in it". Owner: `Wf005::FetchContent`.

**R8-3 — PROOF 168 is vacuous: it never reaches the code it names.** Contract and concurrency
independently. `wf005_host_gate_robots_spec.rb:715` terminalizes the Crawl BEFORE calling `advance`, so
`Admission#authorize_run` denies on `crawl["state"] != "running"` at `crawl_driver.rb:152` and returns
HALTED before `ensure_gate` at `:566` is reached. Both of the proof's assertions are satisfied by the
authorization denial. Removing `ClosedFactSet.translate` from `ensure_gate` survives 44 examples in that
file and 2158 examples across the suite. The real window — RUNNING at authorization, terminal before the
first effect — is untested, and the concurrency lens's own gated interleaving kills the mutation
immediately. Inside range: both the code and the proof are in `e1f5bab`. Owner: the C-2 proof surface.

**R8-4 — `ActivateCrawlPolicy`'s SEC-B1 recheck has no proof of any kind.** Security and contract
independently. Deleting the entire guard at `activate_crawl_policy.rb:103-107` leaves **388 examples, 0
failures** across every spec in the tree that names the handler, and 15/17/26 across its own,
`queue_crawl` and `start_crawl` specs. The mutation is not vacuous: it kills three of the security lens's
own independent proofs, so the control is real and only the evidence is absent. The mechanical signature
is exact — the handler gained twenty lines in `e1f5bab` and
`git diff 7f043a2..e1f5bab -- spec/acceptance/wf005_activate_crawl_policy_spec.rb` is EMPTY, and
`advance_authorization_epoch` has exactly one caller in the whole tree. PROOF 169 and 170 are both about
`QueueCrawl`. ADR-122 nevertheless states both handlers are covered "PROOF 169/170". :331/:333/:335,
SEC-REQ-004/005. Inside range. Owner: the SEC-B1 proof surface.

**R8-5 — both SEC-B1 proofs are branch-depth-one and a single-branch bypass survives.** Security. Two
one-line bypasses — `unless sources.size > 1 || ...` in `queue_crawl.rb:110` and
`unless command.scope == "project" || ...` in `activate_crawl_policy.rb:103` — survive 174 examples.
Demonstrated exploitable under an observed ungranted waiter with the epoch advanced underneath: a
two-Source root Crawl commits AND mints its `crawl_dispatch` action on revoked authority, and a
project-scope policy activates. PROOF 169 uses a single-Source project and organization scope only, so
neither branch is covered. At restored HEAD the identical probes refuse. Inside range. Owner: the SEC-B1
proof surface.

**R8-6 — A-1 is not closed: rule 3's receiver predicate is a new enumeration, and round 6's
`command_call` escape recurs inside it.** Architecture. Thirty of forty-one bypass forms enter the REAL
tracked corpus with the frozen check green. The sharpest is `row["x"].strftime "%s"` — a parenless call
with arguments is Ripper `:command_call`, and rule 3 fires only on `next unless node.first == :call`.
That is round-6 escape #3, which the file's own header documents at `:20`, recurring one rule later; the
same shape also lets through `row["x"].acts_like? :time` and `row["x"].send :strftime, "%s"`. Also
escaping: one intermediate binding (`d = row["x"]; d.to_time`) severs `row_rooted?` entirely, and every
hop form with it; `row.dig("x")` because the receiver allowlist names only `fetch`; `(row["x"]).to_time`
because a `:paren` node terminates the recursion; and `Date.parse(row["x"])` because `Date` supplies the
derived vocabulary but is absent from `banned_constants` — the file treats `Date` as a timestamp class
for one purpose and not the other. The VOCABULARY half is genuinely runtime-derived and closes the
method-name axis, confirmed by catching `strptime`, `xmlschema` and `httpdate`, none of which appears in
the detector source. The RECEIVER half hand-enumerates three receiver shapes and four AST node kinds, so
the header's own argument — "adding four more shapes would have reproduced the defect one round later" —
applies verbatim to it. R6-7's original wording remains literally true. The check is confirmed
NON-VACUOUS and produced no false positives on twelve legitimate forms. Inside range. Owner:
`spec/architecture/wf005_time_single_surface_spec.rb`, a frozen path.

**R8-7 — A-2 is not closed: the record states mechanically checkable falsehoods about itself.**
Architecture and contract independently. The candidate endpoint `e1f5bab` appears in NO record in the
repository. `S-07-009_COMPLETION_REPORT.md:34` still pins the repair candidate at `7f043a2..4e2d8cf` and
`:36` still names ADR-120 as the authority — both round-6 values — while `:3` and `:14` describe round 7,
so a reviewer following the Identity table reviews the wrong range. `:204` says "six rounds, six FAILs"
against `:5`'s "Seven full ADR-026 five-lens rounds … all seven returned FAIL". `:235` states
`bundle exec rspec` = 2134/0 where the measured figure at HEAD is 2142/0 and `BUILD_STATE.next_action`
says 2141/0 — three records, three numbers, one correct; 2134 is traceably the round-6 figure carried
forward under a round-7 heading. `:162` claims the detector spec is "the only frozen-path change in the
tranche" where `FrozenContracts.frozen_changes` on the candidate diff returns TWO, the second being
`lib/f1/runtime_grants.rb`. `BUILD_STATE.reconciliation_note` still says SIX rounds and still pins
`7f043a2..4e2d8cf`, contradicting `next_action` in the same file. The truth check sees none of it: its
suite-size limb binds the ACCEPTED block and compares two records to each other rather than to a
measurement, which is the "restating a maintained number" failure R6-9 named. Inside range. Owner: the
completion report and BUILD_STATE.

**R8-8 — FU-44's stated failure model is refuted by the repository.** Architecture and contract
independently, the contract lens deterministically three times out of three. `BUILD_STATE` FU-44 states
the round-7 boundary example "DOES NOT kill the `>=`->`>` mutation and is therefore not yet a valid
proof … The reason it does not is undiagnosed." Applying exactly that mutation to
`app/platform/entitlement/service.rb:150` fails `spec/platform/entitlement/service_spec.rb:155` with
`expected :released, got :committed` — 18 examples, 1 failure; isolated file 10/1 three times running;
restored 10/0. The example IS a valid proof and DOES kill its mutation. FU-44's other assertions are
verified TRUE: the file is genuinely outside `7f043a2..e1f5bab`, F-05 ownership is correct, and all four
`effective_deadline` comparisons use the contract's direction. The gap is CLOSED, not open, and the open
decision is built on a false premise. It does not block on its own merits — the error runs in the
conservative direction — but it is the same false-record class as R8-7. Inside range. Owner: FU-44's
record.

**R8-9 — :442's exact 60-minute equality is unpinned, and undisclosed.** Concurrency.
`Admission#wall_clock_expired?` at `admission.rb:315` is `deadline <= now`. Weakening it to `<` survives
the ENTIRE repository suite. :442 says "AT 60 elapsed minutes", so equality is refusal, and round 4's
R4-1 found this exact boundary broken once already. This is the same defect class the repository records
as FU-44 for `Entitlement::Service#commit`, except that this survivor is in S-07-009's OWN file, was
introduced by `5860bb4` inside the candidate range, and is recorded nowhere. Inside range. Owner:
`Wf005::Admission`.

## What the round confirmed genuinely repaired

C-1's behaviour is correct and independently reproduced: before, after and split placements of 1.6s
against a 1s margin all refuse identically, and all three admit identically inside a 600s margin, with
the boundary correct at minus one microsecond, exact, and plus one microsecond. C-2's behaviour is
correct at all three enumerated producers, with controlled outcomes, no rollback of the terminal parent
transition and nothing governed written. SEC-B1's behaviour is correct at both handlers, and the
security lens proved the recheck and the protected write share one transaction id, one backend and one
held advisory lock — instrumented on the handler's own connection, not asserted. There is no fourth
WF-005 handler that authorizes a human capability and then waits; `ActivateProject` does NOT share the
`crawl-queue:` key, correcting a claim carried from round 7. The schema is clean: 76 insertions and zero
deletions in the structure delta, five down/up cycles byte-identical across a 9,739-line catalogue
snapshot, a from-empty rebuild dumping identically, all seven outcome columns pinned and every narrowing
killing PROOF 157, RLS FORCE intact on all 43 tenant tables, `f1_web` gaining no privilege, brakeman
clean. All thirteen proof-table counts recount exactly and the nine `.getutc` sites are correct and
correctly located. Every C-1, C-2 and SEC-B1 mutation the record claims kills its named proof does so.

## Carried non-blocking observations

`spec/platform/pg_instant_spec.rb` never passes `anchored_at`, so the C-1 parameter has no unit-level
owner. PROOF 157 pins its seven columns structurally rather than behaviourally, and a neutered predicate
that still names a column survives it. The migration header's "lock graph unchanged" reason is wrong for
the UPDATE limb, which does add an edge, though the graph stays acyclic and no 40P01 is reachable. The
durable authorization decision records `allow` for a command refused on authority grounds, a
platform-wide pre-existing shape now propagated to three more handlers. The WF-005 rechecks discard
WF-013's `stale_authorization_epoch` internal token, so an operator cannot distinguish a never-authorized
request from a mid-flight revocation. `ActivateProject` has the same structural shape and is out of scope
but should be a decision rather than an oversight. The "16 forms injected into the real corpus" claim is
inaccurate twice: the spec evaluates 26 synthetic programs as strings and injects nothing. The
`CrawlStartStore#fail` `FOR NO KEY UPDATE` gap is reproduced again and remains latent. `attempt_number`
is 6 during round 7.

## Stop

This review authorizes no repair. S-07-009 remains NOT ACCEPTED. Do not merge, push, begin S-07-010, or
start a repair cycle from any reviewer context or from the round-7 repair-author context. FU-32, FU-33,
FU-43, FU-44 and R3-P1..R3-P3 are unchanged.

# ROUND 9 — the round-8 repair candidate `7f043a2..6fda00d`

Implementation candidate: `7f043a2..6fda00d`, pinned. Governance commit: `ca655b0`. Review HEAD:
`ca655b0`. Round run: 2026-08-04, full ADR-026 five-lens form, under ADR-124.

**EXCLUDED FROM THE ACCEPTANCE DIFF:** `9720d25` (owner branding/investor/operations/research
markdown), `5261cee`, `d52e66a`, `555c4e9` and `fcd161b` (the round-7 and round-8 findings and
reconciliation records).

**ISOLATION, WITH THE ROUND-8 GAP CLOSED.** Six worktrees at review HEAD, six databases provisioned
FROM EMPTY by the candidate's own migration chain, and — for the first time — **six separate Redis
servers**, one per lens on its own port (6401-6406) with its own directory, run ids recorded at
provision time. Round 8 recorded that it had isolated worktrees and databases but not Redis, and that
the sharing produced one spurious F-04 failure. That gap is closed. No worktree, database, Redis
instance, port or temporary directory was shared. Every lens ended with no modified tracked file.
One lens recorded a >20-minute hang under concurrent load from the other lenses on the same machine,
could not reproduce it in isolation, and correctly declined to assert it as a defect.

**VERDICT: FAIL. Four of five lenses. SEVEN confirmed-blocking findings. S-07-009 IS NOT ACCEPTED.**

**A NOTE ON THE CONCURRENCY VERDICT, RECONCILED RATHER THAN GLOSSED.** That lens wrote
`VERDICT: PASS_WITH_OBSERVATIONS` on its verdict line and then raised one finding under CONFIRMED
BLOCKING, stating it is inside the candidate range, naming its owner, and closing with "I raise one
blocking finding". The two are inconsistent. Reconciliation takes the FINDING at its word rather than
the label: a confirmed-blocking finding inside the range is a FAIL, and a lens's summary line cannot
outrank its own reproduction. R9-7 is counted.

| Lens | Verdict | Confirmed blocking |
| --- | --- | --- |
| Contract-correctness | FAIL | R9-1, R9-2 |
| Concurrency / atomicity / idempotency | FAIL (see note) | R9-7 |
| Security / tenant-isolation | FAIL | R9-3, R9-4 |
| Schema / migration-safety | PASS_WITH_OBSERVATIONS | none |
| Architecture / scope / test-quality | FAIL | R9-1(A), R9-2, R9-5, R9-6 |

## The shape of this round

**THE REPAIR CLOSED SIX OF THE NINE BLOCKERS AND REPRODUCED THE FAILURE MODE OF THE OTHER THREE ONE
STEP LATER.** R8-1, R8-3, R8-4, R8-8 and R8-9 are independently confirmed closed by execution, and
the two production repairs are sound: three lenses drove the pass translation, the boundary owner and
the entitlement boundary and could not refute any of them. What round 9 got wrong is what round 8 got
wrong, in the same three places:

* **R8-2 was an enumeration of producers. Round 9 replaced it with an enumeration of EXCEPTIONS**, and
  the contract lens found a third producer outside it (R9-1).
* **R8-5 was an enumeration of branches. Round 9 replaced it with an enumeration of AXES**, and the
  security lens found a third axis outside it, exploitable (R9-3).
* **R8-6 was an enumeration of receiver shapes. Round 9 replaced it with an enumeration of BINDING
  FORMS**, and the architecture lens found four classes outside it (R9-1(A) is separate; this is R9-5).

The repair's own instruments are the strongest thing in the tranche and the reason this round could
be this precise: `GovernedWriteSentinel`'s `after(:suite)` rule FIRED on the producer the corpus does
not drive, the moment a lens drove it. Both instruments were proved non-vacuous by blinding them.
But one of them does not observe what three ratified records say it observes (R9-4), and the gate
written to catch a false frozen-path claim never executes at all (R9-2).

## Confirmed blockers

**R9-1 — R8-2 IS NOT CLOSED: a third governed producer is neither translated nor classified, and the
corpus cannot see it.** Contract. `Frontier#seed_roots` at `frontier.rb:93` calls
`observer&.hard(QUEUE_DIMENSION, ...)`, reaching `limit_decisions.rb:123`, which INSERTs
`crawl_limit_decisions` — a table `f1_crawl_child_fact_closed` governs. `Handlers::StartCrawl` passes
a REAL observer at `start_crawl.rb:338-345` and has no translation anywhere. The triple
`["workflows/wf005/limit_decisions.rb", "workflows/wf005/handlers/start_crawl.rb",
"crawl_limit_decisions"]` is absent from `CLASSIFIED_UNTRANSLATED`, which lists the frontier-entry
write from THE SAME METHOD, THE SAME HANDLER and THE SAME TRANSACTION but not this one. Reproduced end
to end through the real handlers, whereupon the sentinel's own `after(:suite)` rule fires:
`OWNER RULING 2: 1 governed write(s) reachable from a WF-005 entry point executed with no
Wf005::ClosedFactSet.translate frame and no recorded reason`. No example in the repository drives a
run whose pinned Source count reaches the queue ceiling, so the census never observes it and PROOF 173
passes. THE BEHAVIOUR IS SAFE — the write sits in the same transaction as `store.start`'s
compare-and-set under the `crawls` row lock, exactly like its classified sibling — so this is a proof
and record defect, not a behaviour defect. But three records assert the opposite of what was
reproduced: `governed_write_sentinel.rb:56-58` ("A producer that appears in neither this list nor a
translation FAILS"), `S-07-009_COMPLETION_REPORT.md:45-48` ("what makes the producer set an
OBSERVATION rather than a list"), and ADR-124 ("existing, added later, or never enumerated — is
covered"). Inside range: the rule, the classification, PROOF 173/175 and the completeness claim are
all added by `6fda00d`. Owner: `CLASSIFIED_UNTRANSLATED` or `Handlers::StartCrawl`. One line either
way.

**R9-2 — R8-7 IS NOT CLOSED: the frozen-path limb of the truth gate never executes.** Contract and
architecture independently. `repository_truth_spec.rb:404` extracts claims with
`/(\w+) frozen-path changes?/i`, a literal space. The report's only numeric claim wraps across a line
(`CONTAINS TWO FROZEN-PATH\nCHANGES`), so the regex matches only the QUOTED round-8 finding ("the
only frozen-path change"), `"only"` is not numeric, the claim list empties and the example SKIPS —
in every run, at HEAD. The check's own comment says it reads "EVERY numeric claim, not the first
phrase that happens to match ... a rule that read the first match would judge the quotation rather
than the claim." It does precisely that, then skips. Both lenses changed `TWO` to `NINE`, confirmed
the edit landed, and the suite stayed green. The true count is 2. The suite's single reported
`pending` IS this example. Inside range (`6fda00d`). Owner: the R8-7 truth-gate surface — and an
empty claim set must FAIL rather than skip, because "no claim" is indistinguishable from "the claim
moved", which is the R8-7 failure mode itself.

**R9-3 — R8-5 IS NOT CLOSED: a one-line bypass keyed to a third axis survives the entire suite and is
exploitable.** Security. The branch matrix at `wf005_post_wait_authority_spec.rb:27-30` claims "Every
branch that can reach a protected write is driven ... A bypass keyed to any single one of them fails
a named example rather than hiding in the case nobody drove." `ActivateCrawlPolicy` has a SUPERSEDE
axis the matrix never drives: PROOF 189/190 both bootstrap a fresh Organization and pass
`expected_current_policy_version: nil`, so `current` is always nil. `unless current || ...` at
`activate_crawl_policy.rb:103` survives **2232 examples, 0 failures** — byte-identical to the
baseline — and was exploited on real PostgreSQL with the epoch advanced under an observed ungranted
waiter: the command committed, superseded v1, activated v2 and emitted two `CrawlPolicyActivated`
events on revoked authority. The same shape survives at `queue_crawl.rb:110` (a crawl-policy axis the
`queueable` fixture never activates; 87 examples, 0 failures) and at `cancel_crawl.rb:219` (a
queued-state axis PROOF 151 never drives, since it only cancels a RUNNING Crawl; 39 examples, 0
failures). Inside range. Owner: the SEC-B1 proof surface and the completion report's coverage claim.
**A non-enumerative repair was demonstrated by the lens**: assert suite-wide that a protected write
implies the recheck OWNER's body executed — the model `GovernedWriteSentinel` already establishes —
which the bypass violates on an ordinary path with no revocation at all, on a branch the existing
`wf005_activate_crawl_policy_spec.rb:93` already drives.

**R9-4 — `ExecutionProbe` does not observe the control, and three records say it does.** Security.
`expect_reached_recheck` resolves the control by `/Wf005::PostWaitDecision\.new/`, which matches the
`unless` line itself, and then asserts only that that line ran. A leading-dot continuation line never
fires its own `:line` event, proved in isolation: `line 4 (unless): true, line 5
(.authority_current?): false`, identically whether the guard ran or was short-circuited past. Under
`unless true || Wf005::PostWaitDecision.new(...)` — where the recheck never runs anywhere — PROOF 189
fails at its OUTCOME assertion and never at `expect_reached_recheck`. The probe is not worthless: it
catches deletion, renaming and never-reaching-the-statement, which is why R8-4's deletion fails
loudly. It does not catch a short-circuit INSIDE the statement, which is exactly R8-5's bypass form.
`S-07-009_COMPLETION_REPORT.md:51`, `BUILD_STATE.next_action` and ADR-124 all say a proof "asserts it
REACHED its control"; it asserts it reached the statement containing it. Inside range
(`spec/support/execution_probe.rb` is new in `6fda00d`). Owner: `ExecutionProbe` and every proof
calling `expect_reached_recheck`. The fix is available today: probe the OWNER file —
`command_authorizer.rb:54` and `post_wait_decision.rb:76` are both reported at HEAD.

**R9-5 — R8-6 IS NOT CLOSED: the receiver analysis is a new enumeration and four escape classes reach
the real corpus with the frozen check green.** Architecture. Four forms injected into the real tracked
`crawl_driver.rb` leave the check at **63 examples, 0 failures**: (a) MULTIPLE ASSIGNMENT severs the
taint, because `row_locals` closes over exactly `%i[assign opassign]` and `massign`, `for` and
pattern-match bindings are none of them — and `crawl, anchored_at = load_crawl_with_anchor(...)` is
the corpus's own idiom three lines from the injection anchor; (b) BLOCK-PASS SYMBOL PROC
(`crawl["x"].then(&:to_datetime)`) produces no explicit-receiver call carrying a vocabulary method, and
rule 2 bans only the two-name hand list `%w[getutc to_time]`, so `&:iso8601`, `&:xmlschema`,
`&:in_time_zone` and `&:getlocal` all pass — symbol-proc is live at 8 corpus sites; (c) CONTAINER
LAUNDERING, because `:array` and `:hash` literals are "in memory" regardless of contents, so
`[row["x"]].first.to_time` and `{ k: row["x"] }[:k].getutc` both pass, the latter defeating the rule's
own stated premise; (d) receiver shapes with no case at all that fall through to safe. Calling
`violations` directly on 20 constructed forms through the file's own `findings_for` gave 14 ESCAPED /
6 caught. Inside range; frozen path. Owner: `spec/architecture/wf005_time_single_surface_spec.rb`.

**R9-6 — the mutation-ledger gate validates a self-report, and the harness it names is not in the
repository.** Architecture. `repository_truth_spec.rb:435` asserts `entry["landed"] == true` — a
boolean the ledger's author writes. `BUILD_STATE.next_action` states the ledger was "written by the
harness ... EVERY ONE CONFIRMED LANDED against git rather than intended", and the spec's own comment
says "the harness aborts rather than record a verdict for an edit git cannot see". `git ls-files`
contains no such harness; the ledger's `worktree` field points outside the repository; no entry
records a file, a line or a diff, so no entry is independently reproducible from the repository
alone. A fabricated entry that never ran (`zz-fabricated-never-ran`, `landed: true`, `result: "9999
examples, 7 failures"`) passes the gate. MITIGATING AND RECORDED: every ledger entry re-run
independently by a lens — nine across three lenses — landed where the ledger says and killed the
example it names, so the ledger is not fabricated in fact. The defect is that nothing in the
repository can establish that, while a gate written to say it does. Inside range. Owner: the ledger
and `repository_truth_spec.rb`.

**R9-7 — PROOF 185's single-owner rule is defeated by one method indirection, and an INVERTED :442
boundary survives the suite at a line this candidate wrote.** Concurrency. `within_wall_clock?` at
`crawl_driver.rb:492-494` was rewritten in range to ask `Platform::PgInstant.expired?`, with the
in-range comment "which is why all three now ask it in one place rather than each spelling out a
comparison whose direction a later edit can invert unnoticed". The lens made exactly that edit and it
went unnoticed. PROOF 185 is a per-line text scan whose taint propagation is severed by an endpoint
method: `def run_ceiling(crawl) = crawl["deadline_at"]` mentions `deadline` but carries no ordering
operator, so it is not an offender and taints nothing; `ceiling = run_ceiling(crawl)` mentions nothing
tainted; and the comparison line then mentions neither `deadline` nor a tainted name. With that
indirection in place, an INVERTED boundary — `PgInstant.utc(now) <= PgInstant.utc(ceiling)` — passes
**2223 examples, 0 failures** (the full suite less nine unrelated excluded examples). The same escape
at `Admission#wall_clock_expired?` likewise survives. It is not cosmetic: at exact equality the mutant
lets the pass proceed past the only gate that decides whether a request starts at all, and PROOF 187 —
whose stated purpose is ":442's boundary, through the real handler ... AT 60 elapsed minutes, NO NEW
REQUEST STARTS. At, not after" — passes under it, because its `ready_to_fetch` fixture pre-resolves
robots and sitemaps so `expect(requests).to be_empty` cannot fail for a boundary defect. That is R8-3's
shape exactly: an assertion satisfied by a mechanism other than the one it names. Inside range — the
predicate body, `expired?` and PROOF 185 are all `+` lines in `7f043a2..6fda00d`. Owner: the R8-9
repair surface, `spec/platform/pg_instant_spec.rb` and `Wf005::CrawlDriver`.

## A REAL :442 VIOLATION, REPRODUCED, PRE-EXISTING AND OUTSIDE THE RANGE

Recorded here because it is the most consequential thing this round found about the PRODUCT, and
because no round has recorded it. The C-1 anchor has exactly ONE consumer, `Admission`. Every other
:442-sensitive decision in the same pass still uses the un-anchored `now` — `within_wall_clock?` at
`crawl_driver.rb:186` and `DiscoverSitemaps#run_expired?` at `discover_sitemaps.rb:256`. So a pass that
enters INSIDE its deadline and crosses it during the pre-transaction window starts requests after the
run's sixty minutes are up. Reproduced with no trigger and no harness time machine, the window being
the robots fetch at 1.6s:

    run entered at deadline - 1.0s
    robots request  started +0.014s  (legal)
    sitemap request started +1.659s  (0.659s AFTER the run's deadline)
    pass outcome: deferred / host_gate_paced -> it mints a forward action

The repository asserts the exact property this refutes, by name, at
`spec/acceptance/wf005_record_fetch_attempt_spec.rb:729` — "starts NO request past the deadline, not
even robots or a sitemap", whose own comment says "a pass that consulted the wall clock only at
admission would still have fetched robots and a sitemap first". That example only ever enters ALREADY
expired, never crossing during the pass. NOT introduced by this candidate: `7f043a2`'s driver has the
same ordering, and the example is untouched by the range. It is a distinct half from `open_decisions`
R3-4(a), which is about F-01 re-arming `timeout_s` per redirect hop. **It needs a follow-up of its own
and an owner decision; this review opens neither.**

## Records that state something the repository refutes

Three, all in-range, all of the R8-7 class and all introduced by this repair:

1. **"forty-one bypass forms"** (`S-07-009_COMPLETION_REPORT.md` twice, ADR-124 once). The file
   declares **40**. `rspec --dry-run --format doc | grep -c "catches a decoder injected"` → 40, and
   63 = 8 + 40 + 15 corroborates. No gate checks it.
2. **"EIGHT WF-005 source lines"** (report R8-2 row, ADR-124, commit message). Not reproducible: a
   census over 319 WF-005 acceptance examples records governed writes from **17** distinct WF-005
   source lines, 15 of them production-reachable, across 7 files. The figure is historical, from an
   earlier and narrower census, and no gate checks it.
3. **"a proof asserts it REACHED its control"** (report, BUILD_STATE, ADR-124) — refuted by R9-4.

## What the round confirmed genuinely repaired

R8-1, R8-3, R8-4, R8-8 and R8-9 are closed, each verified by a lens applying the mutation itself and
confirming by `git diff` that it landed. R8-3's replacement opens the real window: removing the pass
translation makes a raw `PG::RaiseException` escape `ensure_gate` and reach the scheduled-action
worker, killing PROOF 172 and 173. R8-4's deletion now fails 5 examples where round 8 measured 388/0.
R8-8's disposition is correct in both directions: the mutation at `:150` is killed, and the real
survivor at `:113` — the one an unscoped substitution actually lands on — is killed by the new
boundary example. R8-9's owner has exactly four call sites and no SQL-level deadline comparison exists
outside the workflow. Both `CLASSIFIED_UNTRANSLATED` entries were verified TRUE rather than
convenient, by reading the lock order in both handlers. The handler set is complete by directory
enumeration: three human-authorized waiting handlers, all three calling `authority_current?`, and no
fourth. `ActivateProject` genuinely does not share the key. Both instruments were proved non-vacuous
by blinding them — the sentinel's catalogue read and the probe's path roots — and the sentinel's
`after(:suite)` really does fail a run. The schema is untouched by round 9 (four subtree hashes
byte-identical), reversible over nine cycles, RLS FORCE intact on 43 tables, `f1_web` gaining no
privilege and holding no DELETE/TRUNCATE/REFERENCES/TRIGGER anywhere. Gates reproduce exactly in
every lens environment: rspec 2232/0/1 pending, architecture 137/0, brakeman clean, packwerk clean.

## Carried non-blocking observations

PROOF 156's INSERT limb is structural only: a closure trigger recreated with an unfireable `WHEN`
clause survives 304 examples, though removal is genuinely defended. PROOF 157's three round-7 columns
admit an equivalent mutant, bounded by the store's write shape. Round 8's own "76 insertions, zero
deletions" structure delta is wrong — measured 234/2 — and round 10 must not inherit it. The report's
13-row prose mutation table carries no ledger ids, so both ledger limbs skip it. The durable
authorization decision still records `allow` for a command the recheck refused. `replay` returns
before the recheck in both command handlers. `GovernedWriteSentinel` fails OPEN on two axes: an entry
point outside `handlers/` and a stack deeper than 160 both drop a write from the failure set rather
than flagging it. PROOF 193 enforces a SUBSTRING (`include?("PostWaitDecision")`), which
`complete_crawl.rb` satisfies while calling only `#now`. PROOF 187 does not kill the `m9` mutation —
PROOF 188's comment discloses this, but the report's "PROOF 180-188" row invites the opposite reading.
Ledger `result` counts are RSpec-seed dependent; `failing_examples` is the load-bearing field.
`CrawlDriver` holds a SECOND `admission.claim_entry` call at `:503` (`admission_reason`) that passes no
anchor — benign, reached only when the raw instant is already expired and fenced by an explicit
`Platform::InvariantViolation` at `:507`, but every recorded anchor mutation only ever hit the other
site, and per the FU-44 lesson a ledger entry must say which. `Admission#claim_next` has an
`anchored_at: nil` default and no production caller at all — the `m1c` shape as a permanent API
affordance. **THE HEADLINE GATE CAN HANG RATHER THAN FAIL**: one full-suite run wedged indefinitely
with a live thread from `wf013_organization_lifecycle_concurrency_spec.rb:84` blocked in `PQgetResult`
while every connection sat idle and no lock was ungranted; that spec joins two bare `Thread.new` with
no timeout, unlike `RaceHarness.wait_until` which is bounded at 15s. Five other full runs completed in
159-227s and the file passes 6/6 in isolation, so it is intermittent and suite-context-dependent.
Outside the range, and not a defect this round can assert — but a gate that can hang forever instead of
failing is worth an owner's attention.

## Stop

This review authorizes no repair. S-07-009 remains NOT ACCEPTED. Do not merge, push, begin S-07-010 or
S-07-011, or start a repair cycle from any reviewer context or from the round-9 repair-author context.
FU-32, FU-33, FU-43 and R3-P1..R3-P3 are unchanged. FU-44 remains correctly SUPERSEDED.
