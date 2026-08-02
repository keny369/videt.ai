# S-07-009 — Crawl Execution: Terminal Checkpoint, Coverage/Completion, CancelCrawl

**Acceptance status: NOT ACCEPTED. Implementation complete, INDEPENDENT REVIEW OWED.**

This record exists because the implementation is finished and reviewable, not because it has been
accepted. Nothing here may be read as acceptance. Three full ADR-026 five-lens rounds have run against
this tranche and **all three returned FAIL**; the eleven round-3 blockers are repaired and a fourth
round is owed.

This record describes the candidate. It does not narrate how the candidate was reached — git holds
that — and every claim below is either mechanically checked by
`spec/architecture/repository_truth_spec.rb` or reproducible by the commands in **Verification**.

## Identity

| | |
| --- | --- |
| Block | S-07-009, BUILD_PLAN `Crawl Execution — terminal checkpoint + coverage/completion + CancelCrawl` |
| **Round-4 candidate** | **`7f043a2..332c52b`, PINNED** — never `..HEAD` |
| Round-3 candidate | `7f043a2..467f1d1` (superseded; its findings are in `S-07-009_ACCEPTANCE_REVIEW.md`) |
| Authority | standing delegation ADR-061; review discipline ADR-080; five-lens form ADR-026 |
| Depends on | S-07-007, S-07-008, S-07-012 — all accepted |
| Blocks | S-07-010 and S-07-011, which `depends_on` this tranche and may not proceed on it unaccepted |

The candidate range deliberately **excludes the governance commit that records it**. Writing a SHA
into `BUILD_STATE.json` changes that file's own commit, so the endpoint is the last implementation
commit and the record naming it sits above the range. This is the convention `BUILD_STATE`'s
`note_on_range` already documents.

## Delivered behaviour

**Terminal selection happens once, at a serialized checkpoint.** `Workflows::Wf005::Handlers::CompleteCrawl`
takes the `crawl-frontier:<crawl>` advisory lock and then the `crawls` row lock — frontier THEN crawls,
the order `Admission#claim` and `CrawlDriver#retire` already use — and derives the run's terminal state
from counted facts rather than from anything a caller supplies. `Workflows::Wf005::TerminalSelection` is
the pure function that turns those facts into `(state, completion_reason, coverage_status)` in :458's
precedence `canceled`, `failed`, `limit_reached`, `partial_source_failure`, `completed`.

**Every counted fact decides something a run can be wrong about.** `crawl_terminal_outcomes` is the
per-candidate coverage record :452 defines, and `CrawlStartStore#terminal_facts` reads documents, Source
roots, fetch failures, uncovered and unevaluated candidates, unresolved discovery and hard-limit
decisions from committed rows. `coverage_status = 'full'` requires every in-scope candidate to have
reached a terminal covered outcome with no unresolved failure.

**The run's own sixty minutes are recorded where they actually ended the run.** `observe_wall_clock`
records a crossing only when the deadline PREVENTED an evaluation: it reads the affected count first and
writes nothing when it is zero, because :458 conditions the rule on "any in-scope candidate NOT
EVALUATED because of … wall-clock bound". The affected population is the candidates the run never
reached, unioned with the candidates whose REQUEST the clock cancelled — and, since R3-1, **not** the
candidates a different bound discarded.

**Cancellation.** `Workflows::Wf005::Handlers::CancelCrawl` authorizes `crawl.cancel` (:738, a permission
separate from `crawl.trigger`), takes the same two locks in the same order, moves a `queued` or
`running` Crawl to `canceled`, releases its entitlement reservation per :551, and emits `CrawlCanceled`
carrying all three `crawl_terminal` members. :458's boundary is the CHECKPOINT'S COMMIT; the wall-clock
handler wins only the tie at exactly the deadline instant.

**The reservation is committed or released exactly once**, at the durable commit point MTX-030 names.

## Schema changes

| Migration | Effect |
| --- | --- |
| `20260727120340_crawls_terminal_completeness` | `crawls_terminal_shape` gains a terminal-completeness conjunct: every terminal state requires `completion_reason`, and `completed` additionally requires `coverage_status` |
| `20260727120350_create_crawl_terminal_outcomes` | the per-candidate coverage record; T-IMM; forced RLS |
| `20260727120360_crawls_terminal_transitions` | :736's edge set, with terminal states only on the right |
| `20260727120370_crawls_run_clock_immutable` | the run's clock frozen alongside the metering identity (FU-30) |
| `20260727120380_crawl_terminal_outcomes_source_link` | the composite Source link the review found missing |

**A note the record has now been wrong about twice, stated correctly here.** The constraint at fault for
the original FU-11 hole was `crawls_terminal_shape`, not `crawls_coverage_status_check`. The
`IS NOT DISTINCT FROM` rewrite once prescribed for it **is not a no-op and is not admitted**: its
`ANY(...)` form is a PostgreSQL syntax error, and its only valid spelling — pairwise
`NULL IS NOT DISTINCT FROM 'full' OR …` — evaluates to FALSE, which a CHECK REFUSES, so it would reject
every `queued` and `running` Crawl. PROOF 104 pins this against a live PG17 cluster. Seven ratified
records stated the opposite; `spec/architecture/repository_truth_spec.rb` now derives its corpus from
`git ls-files` so an eighth cannot be written silently (R3-7).

## Review history — three rounds, three FAILs

| Round | Candidate | Outcome |
| --- | --- | --- |
| 1 | `7f043a2..a414f5c` | FAIL — 11 confirmed-blocking findings on a 2040/0 suite |
| 2 | `7f043a2..95d37f4` | FAIL — 3 blocking, **two of them defects in round 1's repairs** |
| 3 | `7f043a2..467f1d1` | FAIL — 11 in-candidate blockers on a 2068/0 suite, **all three round-2 repairs refuted**, plus 3 pre-existing governance blockers |

Round 3's most serious class was **evidence failure, not code failure**: three lock proofs passed 10/10
with their control deleted whenever any unrelated transaction anywhere on the cluster waited on a row
lock; one proof's central assertion could not fail; three were green only on physical heap order; and a
live RLS policy predicate was asserted by nothing.

## Round-3 repairs, in the recorded dependency order

| Item | Repair | Commit |
| --- | --- | --- |
| R3-5 | lock proofs assert the causal edge in this database, not a cluster-wide `pg_locks` count | `ad0cec0` |
| R3-11, R3-9 | the RLS policy predicate exercised as `f1_web` across the tenant boundary; `gate_row` raises on ambiguity instead of answering by heap order | `0dab415` |
| R3-8 | PROOF 108 records through the sink every other example uses | `00cc247` |
| R3-6 | `CancelCrawl` takes the frontier lock | `bc965dd` |
| R3-6 | **completed**: PROOF 117 and PROOF 118, because the lock was asserted by nothing | `f4f9687` |
| R3-10 | :147's sixth cell implemented — a Read-Only Executive Buyer could irreversibly cancel a running Crawl | `6fd5c63` |
| R3-4 (half b) | the request budget measured from the request's start, not the pass's delivery instant | `fa03590` |
| R3-1 | the wall clock counts what the wall clock prevented | `74e723d` |
| R3-2, R3-3 | :458's boundary is the checkpoint's commit; `CrawlCanceled` carries `coverage_status` | `a2a990d` |
| R3-7 | the durable check derives its corpus from `git ls-files` | `332c52b` |

**Every repair was mutation-proved**: the fix was reverted and a NAMED proof required to fail. Both
production mutations and two temporary record mutations were restored and verified by diff.

## One in-candidate item is NOT closed

**R3-4 half (a), recorded as FU-43.** `RequestPolicy#timeout_s` is a per-connection-attempt bound and
`GuardedHttpClient#attempt` re-arms it on every redirect hop, so one wall-clock-bounded fetch can run
`(max_redirects + 1) × (dns + response)` — 11.1× measured by the review. A request the run's clock was
supposed to end can still be reading a customer's site after `deadline_at`.

It is **not repairable by an implementer**. `app/platform/outbound/` is a frozen foundation with no
additive Evolution Rule, and the repository's own classifier
`AutonomousBuild::FrozenContracts.frozen_path?` returns true for both files, which makes any edit a
MANDATORY HUMAN ESCALATION. No caller-side fix exists: the façade exposes only a per-attempt timeout,
and the single available lever (`max_redirects: 0`) does not bound the remaining hop and would silently
change crawl semantics. **FU-34 is therefore also not closed** — two of its three halves hold.

## Verification

Run from the candidate `332c52b` on a quiet cluster (PostgreSQL 17 on `127.0.0.1:5433`):

```
bin/rspec                                     # 2085 examples, 0 failures
bin/rspec spec/architecture                   # 65 examples, 0 failures
bundle exec brakeman -q --no-pager -z         # no warnings
bin/packwerk check                            # no offenses, no stale violations
bin/rails zeitwerk:check                      # all is good
bundle exec bundle-audit check --update       # no vulnerabilities
bin/f1db f1:db:verify_runtime                 # 15 checks passed, RLS intact
bin/f1db db:schema:dump && git diff --exit-code db/structure.sql   # no drift
```

**Every mandatory gate passing is not acceptance.** That sentence is three rounds old and is the reason
a fourth is required: round 3 refuted all three of round 2's repairs against a suite that was 2068/0 at
the moment of the verdict.

## The tranche's own proofs

| Spec | Proofs |
| --- | --- |
| `spec/acceptance/wf005_terminal_checkpoint_spec.rb` | 25 |
| `spec/acceptance/wf005_cancel_crawl_spec.rb` | 15 |
| `spec/persistence/crawl_terminal_outcome_invariants_spec.rb` | 13 |
| `spec/acceptance/wf005_checkpoint_pass_concurrency_spec.rb` | 10 |
| `spec/workflows/wf005/terminal_selection_spec.rb` | 9 |
| `spec/acceptance/wf005_start_cancel_concurrency_spec.rb` | 2 |
| `spec/acceptance/wf005_heartbeat_concurrency_spec.rb` | 1 |
| `spec/architecture/permission_baseline_transcription_spec.rb` | the :135 transcription, derived from the ratified table (R3-10) |

## Ownership and follow-ups

**Opened by this repair programme:** FU-41 (after R3-6, `lock_crawl`'s `FOR UPDATE` is superseded by the
frontier lock and is asserted by nothing — deliberately RETAINED, not removed); FU-42 (a constant
assigned inside an `RSpec.describe` block lands on `Object`, so two spec files can silently read each
other's document); **FU-43** (the frozen-foundation escalation above).

**Resolved by this programme:** FU-1, under its own "unless a contract makes it one" clause — :147's
sixth cell plus :738 plus the irreversibility of a cancellation is a contract making it one. FU-2, the
GrantScope containment limb of the same rows, is a **different dimension and remains open**.

**Open and unchanged:** FU-7, FU-22, FU-37, FU-38, FU-39, FU-40. **Owner decisions outstanding:** FU-32,
FU-33, FU-43, and R3-P1..R3-P3.

R3-6's severity disagreement — architecture called it blocking, concurrency an observation — is **moot**:
both lenses proposed the same repair and it is implemented, so the disagreement never needed resolving.

## What a round-4 reviewer must know

1. The candidate is the **fixed range `7f043a2..332c52b`**. Do not review `..HEAD`.
2. Review by **PATH over the range**, never by treating a single commit as a slice.
3. The **round-3 repairs are candidate material** and must be reviewed as such. Rounds 1 and 2 both had
   repairs that were themselves defective, and round 3 found all three of round 2's refuted.
4. Round 4 must be run by **five fresh contexts with no shared conversational state**. The author of
   the round-3 repairs cannot review them.
5. **R3-P1..R3-P3 are outside this candidate.** The mandatory gate "the schema builds from empty" has
   never been executed in this repository's history, and the raw migration chain in fact fails at
   `PG::DuplicateColumn`. That is a question about every accepted block and this tranche must not
   absorb it.
