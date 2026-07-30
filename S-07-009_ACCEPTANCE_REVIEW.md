# S-07-009 — ADR-080 Acceptance Review: NOT ACCEPTED

Candidate: `7f043a2..a414f5c` (nine commits, "S-07-009 (1/n)".."(9/n)") on `implementation/s01-registration-access`.
Round run: 2026-07-31, on owner instruction, full ADR-026 five-lens form, deliberately NOT narrowed.
Gates at the candidate: rspec 2040/0, brakeman 0, packwerk clean, zeitwerk ok, verify_runtime 15/15, no structure drift.

**VERDICT: FAIL-WITH-FINDINGS. Eleven confirmed-blocking findings. S-07-009 IS NOT ACCEPTED.**

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
