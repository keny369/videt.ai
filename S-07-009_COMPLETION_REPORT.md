# S-07-009 — Crawl Execution: Terminal Checkpoint, Coverage/Completion, CancelCrawl

**Acceptance status: NOT ACCEPTED. The round-6 repair candidate is complete under ADR-120.**

Six full ADR-026 five-lens rounds have reviewed this tranche and all six returned FAIL. Round 6 returned
nine confirmed blockers (ADR-118). The owner then directed a classification of those nine BEFORE any
repair, which found five root concepts rather than nine independent defects, and issued four rulings and
an ordered implementation programme (ADR-120). This report records the completed repair candidate and the
stop boundary. It is not an acceptance record.

## Identity

| | |
| --- | --- |
| Block | S-07-009, BUILD_PLAN `Crawl Execution — terminal checkpoint + coverage/completion + CancelCrawl` |
| **Repair candidate** | **`7f043a2..4e2d8cf`, PINNED** — never `..HEAD` |
| Round-6 reviewed candidate | `7f043a2..5860bb4`, reviewed as the complete state through `cf2059e` (failed; findings remain in `S-07-009_ACCEPTANCE_REVIEW.md`) |
| Repair authority | ADR-120, the explicit 2026-08-04 owner rulings; ADR-117's semantic rulings remain in force |
| Depends on | S-07-007, S-07-008, S-07-012 — all accepted |
| Blocks | S-07-010 and S-07-011 while S-07-009 remains unaccepted |

## The round-6 repair: nine blockers, five concepts

The owner's classification instruction is the reason this round's diff is small relative to its finding
count. Every prior round repaired findings one at a time and the next round found the same class one
producer along: B7 fenced `retire` and R5-3 fenced Admission's fall-through, and round 6 then found the
two producers neither had reached. Each concept below is repaired ONCE, at the location that owns it.

| Root concept | Blockers | Owner of the repair | Code? |
| --- | --- | --- | --- |
| The pre-wait snapshot used as post-wait authority | R6-1, R6-5, R6-6 | `Platform::PgInstant.after_wait`, `Workflows::Wf005::PostWaitDecision` | yes |
| The Crawl's child fact set is never closed on terminalization | R6-2, R6-3 | `f1_crawl_child_fact_closed` (migration `20260727120390`) | yes, schema and application |
| :450's antecedents versus the FU-9 transfer | R6-4 | Volume I :450, by owner ruling; FU-9's transfer withdrawn | yes, plus governance |
| The single-decoder check enumerates violations instead of deriving them | R6-7 | `spec/architecture/wf005_time_single_surface_spec.rb` | tests only |
| No truth check binds the record of the tranche under review | R6-8, R6-9 | `spec/architecture/repository_truth_spec.rb` | tests and records |

### Post-wait truth (R6-1, R6-5, R6-6)

`Platform::PgInstant.after_wait` computes the decision instant IN PostgreSQL as the caller's instant plus
`clock_timestamp() - transaction_timestamp()`. It is an advance rather than a raw `clock_timestamp()`
reading because every instant it is compared against — `crawls.deadline_at`, `crawls.started_at`,
`entitlement_reservations.lease_due` — is written by an application clock, and
`CrawlHostGateStore#reservation_executing?` already records that two surfaces judging one reservation
against two clocks is the defect to avoid. `Workflows::Wf005::PostWaitDecision` states the rule the three
waiting handlers share and owns :458's terminal vocabulary and the `authority_current?` call site.

Admission re-reads the instant before re-authorizing, so the wall clock and the entitlement lease are both
judged at the instant the decision is actually made. `CancelCrawl` re-checks `CommandAuthorizer.
authority_current?` immediately before its irreversible transition. `CompleteCrawl` settles entitlement on
the post-wait instant, so :551's strict-before rule is applied to the durable terminal point rather than to
the delivery.

:458's exact-boundary tie is the one test deliberately left on the ARRIVAL instant. Sentence 3 names the
instant the cancellation is ABOUT, and measuring it post-wait would not tighten it but delete it: the
post-wait instant can never equal a stored microsecond, so `==` would be dead code and round 1's B1 would
return through an unrelated repair.

### The closed fact set (R6-2, R6-3)

`f1_crawl_child_fact_closed` refuses any governed child fact for a terminal Crawl. It runs on INSERT for
`crawl_limit_decisions`, `crawl_terminal_outcomes`, `crawl_frontier_entries`, `crawl_frontier_occurrences`
and `crawl_host_gates`, and on UPDATE of the sitemap and robots outcome columns, which is where R6-3's
second variant lives. It reads the parent `FOR KEY SHARE` — the same lock the composite foreign key
already takes in the same statement — so the subsystem's one lock order is unchanged and no new cycle is
reachable, and it BLOCKS on an uncommitted terminal transition rather than passing on its preimage. It is
an AFTER trigger, because a BEFORE trigger runs ahead of a policy's WITH CHECK limb and would answer a
cross-tenant write with a state message instead of a tenant refusal.

`fetch_attempts`, `crawl_budget_counters`, `crawl_sitemap_document_charges`, `crawl_sources`, `evaluations`
and `evaluation_orchestration_contexts` are deliberately ungoverned, each for a reason recorded in the
migration header and re-asserted by PROOF 156, which derives the child-table set from `pg_constraint` so a
future child table must be classified rather than defaulted. `fetch_attempts` in particular is left alone
because closing it would silently decide FU-32.

Admission's unlocked hard-expired shortcut is removed; both wall-clock thresholds are recorded by the
single post-lock call, after revalidation. `DiscoverSitemaps` translates the database's refusal into a
controlled, idempotent `pending` / `crawl_terminal` result. A refused late claim leaves its gate
`in_progress` on a run that is over; that residue is inert and belongs to FU-22 under S-07-011.

### :450's antecedents (R6-4)

`CompleteCrawl#resolve_pending_sitemaps` is removed. It satisfied only the consequent of :450's sentence
and wrote `sitemap_unavailable` for gates the run never attempted, and the proof that pinned it used
allow-all robots with no declared sitemap and no default fetch. The COVERAGE answer it reached was correct
and is kept, stated directly as :458's not-evaluated limb: `TerminalSelection::Facts` gains
`unattempted_discovery`, which makes coverage `partial` and deliberately does not touch :452's completion
reason, because :452 lists three causes of `partial_source_failure` and a host nobody contacted is none of
them. The FU-9 transfer is withdrawn in `BUILD_PLAN.yml` and `BUILD_STATE.json`; no contradictory
governance text is retained.

The pinned range ends at the implementation commit. The governance commit that writes this SHA sits
above the range because a commit cannot truthfully contain its own identifier. This is the bounded-range
convention already used by the repository; the endpoint is not inferred from HEAD.

## Delivered behaviour

### Admission and terminal locking

`Workflows::Wf005::Admission` now takes `crawl-frontier:<crawl>` before any fall-through operation can
acquire a `crawls` tuple lock, including the implicit `FOR KEY SHARE` from a limit-decision foreign key.
After any wait it re-reads and re-authorizes Organization, Project, Crawl and entitlement state and
re-resolves active policy before its first durable effect. A hard-expired Admission may record and return
without entering the frontier critical section; it cannot fall through and form the old cycle.

`CancelCrawl` and `CompleteCrawl` retain the authorized order: frontier advisory lock, then `crawls FOR
UPDATE`. PROOF 132 checks the actual soft `crawl_limit_decisions` insert and raises unless that backend
already holds the advisory lock derived from `NEW.crawl_id`. PROOFs 133-135 exercise Admission-first,
CancelCrawl-first and CompleteCrawl-first orientations on PostgreSQL and verify post-wait revalidation and
the absence of limit decisions, reservations and claims after a terminal winner.

### Canonical limit semantics

`Workflows::Wf005::LimitSemantics` is the authoritative twelve-row classifier. It separately records
local disposition, delay, scheduling stop, hard-decision production, decision reason, terminal reason,
coverage effect, affected-count ownership and sitemap override. Its derived run-stopping set is exactly:

- `accepted_pages_per_run`;
- `discovered_url_queue`;
- `accounted_response_body_bytes_per_run`;
- `wall_clock_run_duration`.

Rate and concurrency ceilings are pacing-only and `LimitDecisions` refuses to persist a decision for
them. A general hard decision with `decision_reason_code = limit_reached` no longer promotes a local URL
failure into `crawls.completion_reason = limit_reached`. Terminal selection uses only classified
terminal-forcing decisions plus persisted sitemap-specific limit facts. Affected counts remain owned by
the causal population at the immutable first decision.

The wall clock is suppressed only when an earlier accepted-page or run-byte decision already abandoned
the same unselected frontier. Depth, queue-admission and per-URL decisions do not own unrelated queued
rows. PROOF 99 now pins the local-decision outcome; PROOF 131 pins independent wall-clock ownership;
PROOFs 136-142 pin the classifier and terminal-fact split; PROOFs 143-144 pin exhausted sitemap request
time as a persisted §450 terminal fact.

### One PostgreSQL instant surface, and a check that cannot be respelled around (R6-7)

Every WF-005 PostgreSQL timestamp decoder uses `Platform::PgInstant`. PROOF 145 drives the real checkpoint
400ms before a subsecond deadline and proves that it does not write an early wall-clock decision; the
margin is 400ms rather than one microsecond because the checkpoint now reads its decision instant from the
database after taking its locks, so the transaction's own elapsed time is part of the answer. The margin
sits between the handler's transaction time and the 987,654µs error its target mutation introduces.

`spec/architecture/wf005_time_single_surface_spec.rb` is a FROZEN PATH under `AutonomousBuild::
FrozenContracts`, and the owner's round-6 programme names it explicitly for repair. That instruction is the
authority for this change; it is the only frozen-path change in the tranche, and ADR-120 records it by name
rather than leaving it to be inferred from the diff. The check keeps ADR-117 R5-2's narrow scope and creates
no new family of checks.

Its detector is inverted from a denylist into a structural rule. The old form enumerated four AST shapes and
self-tested against those same four, and round 6 walked four ordinary spellings through it. WF-005 names
`Time` and `DateTime` NOWHERE in the tracked corpus, so the rule is now that it may not — which no
respelling evades, because every parser, type test, `case/when`, `===` and `.class ==` has to name the
constant to work — plus a ban on naming the UTC protocol as data, which closes the parenless
`respond_to? :getutc` route. Both `.getutc` METHOD CALLS in the corpus are untouched and correct: formatting
an instant the application already holds is a different act from deciding how to decode one.

### Terminal checkpoint and cancellation

`Workflows::Wf005::Handlers::CompleteCrawl` still serializes terminal selection by taking the frontier
lock and then the Crawl row lock. `Workflows::Wf005::TerminalSelection` derives `(state,
completion_reason, coverage_status)` from one committed fact snapshot. `CancelCrawl` authorizes the
separate `crawl.cancel` capability, terminalizes a queued or running Crawl, releases its reservation and
emits the complete `crawl_terminal` event members. Reservation commit/release remains exactly once at the
durable terminal commit.

## Schema changes

| Migration | Effect |
| --- | --- |
| `20260727120340_crawls_terminal_completeness` | strengthens `crawls_terminal_shape`: every terminal state requires `completion_reason`; `completed` also requires `coverage_status` |
| `20260727120350_create_crawl_terminal_outcomes` | creates the immutable per-candidate coverage record with forced RLS; it constrained the Crawl and frontier-entry links, but **shipped `source_id` with no foreign key at all** |
| `20260727120360_crawls_terminal_transitions` | enforces the ratified edge set, terminal-row immutability and run-identity immutability |
| `20260727120370_crawls_run_clock_immutable` | freezes `started_at` and `deadline_at` with the run identity |
| `20260727120380_crawl_terminal_outcomes_source_link` | adds the previously absent arity-3 `(organization_id, project_id, source_id)` Source foreign key |
| `20260727120390_crawl_child_fact_closed_on_terminal` | closes the governed child-fact set on parent terminalization: AFTER INSERT on five tables, AFTER UPDATE of the sitemap/robots outcome columns, reading the parent `FOR KEY SHARE` so no lock edge is added |

The migration-350 defect was absence, not arity two. PROOF 39's original enumeration could validate the
arity of foreign keys it found but could not discover a missing link; migration 380 and the strengthened
proof repair that exact gap. The separate `IS NOT DISTINCT FROM` refutation remains unchanged and is
covered by `spec/architecture/repository_truth_spec.rb`'s tracked-record corpus.

## Review history — six rounds, six FAILs

| Round | Candidate | Outcome |
| --- | --- | --- |
| 1 | `7f043a2..a414f5c` | FAIL — 11 confirmed blockers on 2040/0 |
| 2 | `7f043a2..95d37f4` | FAIL — 3 blockers on 2055/0; two were defects in round-1 repairs |
| 3 | `7f043a2..467f1d1` | FAIL — 11 in-candidate blockers on 2068/0; all three round-2 repairs were refuted |
| 4 | `7f043a2..7034e25` | FAIL — 8 blockers on 2085/0; five were defects in round-3 repairs |
| 5 | `7f043a2..ac962bb` | FAIL — 5 blockers; four were defects in round-4 repairs |
| 6 | `7f043a2..5860bb4`, reviewed through `cf2059e` | FAIL — all five lenses, 9 blockers; three reproduced as deterministic real-PostgreSQL interleavings |

Round 6 returned contract FAIL (R6-2, R6-3, R6-4), concurrency FAIL (R6-1, R6-2, R6-3), security FAIL
(R6-1, R6-5, R6-6), schema FAIL (R6-2) and architecture FAIL (R6-7, R6-8, R6-9). The complete findings and
lens provenance remain in `S-07-009_ACCEPTANCE_REVIEW.md`; this repair report does not rewrite that
independent verdict.

**The recurrence is what the round-6 rulings addressed.** Five of the nine were recurrences of classes
already identified: R6-2 and R6-3 are B7/R2-B1's fencing class at the producers that repair never reached;
R6-4 was round 1's non-blocking observation 1, examined and not promoted by round 2; R6-7 succeeds R5-2's
"repaired one call site of a defect class with several live sites"; R6-8 is B6/R4-8/R5-4's false-record
class; and R6-9 was recorded verbatim by the round-4 review and retained through the R5-5 rewrite. Each is
now repaired at a canonical owner, and the two classes that kept recurring — per-producer fencing and
unchecked records — are closed by a database rule and a truth check respectively rather than by another
careful edit.

## Verification

Run from the repair tip on PostgreSQL 17 at `127.0.0.1:5433`:

| Gate | Result |
| --- | --- |
| `bundle exec rspec` | `2134 examples, 0 failures` |
| `bundle exec rspec spec/architecture` | `75 examples, 0 failures` |
| `bundle exec brakeman -q --no-pager -z` | zero warnings |
| `bin/packwerk check` | no offenses; no stale violations |
| `bin/rails zeitwerk:check` | all is good |
| `bundle exec bundle-audit check --update` | no vulnerabilities |
| `bin/f1db f1:db:verify_runtime` | 15 checks passed; RLS intact |
| `bin/f1db db:schema:dump` then `git diff --exit-code -- db/structure.sql` | no structure drift |

Every gate passing remains verification, not acceptance.

## Mutation and structural evidence

| Mutation or probe | Required result |
| --- | --- |
| move the fall-through soft wall-clock decision before `lock_frontier` | PROOF 132 fails at the real insert with `soft Admission decision preceded crawl frontier lock`; the concurrency examples cannot observe the required frontier waits |
| derive terminal reason from every hard decision again | PROOF 99 fails: a local per-URL decision incorrectly changes `partial_source_failure` to `limit_reached` |
| decode the checkpoint deadline with `Time.parse(deadline.to_s)` again | PROOF 145 fails one microsecond before the real deadline by writing an early wall-clock decision |
| unmutated runtime structural probe | PROOF 132 derives the advisory key from `NEW.crawl_id` and observes the granted transaction lock in `pg_locks` at the actual insert |
| real two-orientation terminal races | PROOFs 133-135 show Admission-first waiting, terminal-first re-read, no SQLSTATE 40P01 and no losing durable effect |

### Round-6 mutations, each run and each observed

Every mutation below was applied to the working tree, the named proofs were run, and the mutation was
reverted and the proofs re-run green before the clean gate run. A proof that passes under its target
mutation is not counted.

| Mutation | Observed result |
| --- | --- |
| `PgInstant.after_wait` returns the caller's instant unchanged (restore pre-wait time everywhere) | 4 failures — PROOF 146, PROOF 149, PROOF 150, PROOF 152 |
| `PgInstant.after_wait` returns a raw `clock_timestamp()` instead of an advance | 3 failures — PROOF 146, PROOF 147, PROOF 148 |
| omit `CancelCrawl`'s post-wait `authority_current?` recheck | 1 failure — PROOF 151 |
| drop the five INSERT-side closure triggers | 6 failures — PROOF 154, 155, 156, 158, 159, 160 |
| count a merely pending gate as :450 `sitemap_unavailable` again | 1 failure — PROOF 67 |
| remove the `unattempted_discovery` limb from coverage (lose the answer with the route) | 1 failure — PROOF 162 |
| inject `Time.zone.parse(value.to_s)` into the real WF-005 corpus | corpus scan fails |
| inject `Time.rfc3339(value.to_s)` into the real WF-005 corpus | corpus scan fails |
| inject `value.respond_to? :getutc` into the real WF-005 corpus | corpus scan fails |
| inject `Time === value ? value.getutc : value` into the real WF-005 corpus | corpus scan fails |
| restate a wrong mechanically countable proof total (16 → 13) | `repository_truth_spec` fails |
| cite a spec path that does not resolve (stale candidate information) | `repository_truth_spec` fails, 2 examples |
| reintroduce ADR-117's false "before implementation" provenance claim | `repository_truth_spec` fails |

The four corpus injections are the exact spellings round 6 demonstrated against the committed detector,
which returned an empty finding set for all four. The three record mutations are the three the programme
named: stale candidate information, a false provenance claim, and a wrong mechanically countable total.

All temporary mutations were restored before the clean gate run.

## The tranche's proof surfaces

Counts below are distinct `PROOF n` identifiers, not RSpec example counts.

**THESE NUMBERS ARE DERIVED, NOT MAINTAINED (round-6 blocker R6-9).** The previous table said 13 for a
file containing 16. The round-4 review recorded that discrepancy, the R5-5 rewrite retained it, and
round 6 promoted it to a blocker — three rounds for a number the repository could count. Every row is
now re-counted from the file it names by
`spec/architecture/repository_truth_spec.rb`, which binds `BUILD_STATE.current_tranche` and therefore
checks this report WHILE IT IS UNACCEPTED. That was the structural gap: every prior truth check bound
`acceptance_evidence.block`, the last accepted tranche, so this report was validated by nothing during
the five rounds that were reading it.

| Spec | Proofs |
| --- | --- |
| `spec/acceptance/wf005_terminal_checkpoint_spec.rb` | 34 |
| `spec/acceptance/wf005_cancel_crawl_spec.rb` | 17 |
| `spec/persistence/crawl_terminal_outcome_invariants_spec.rb` | 16 |
| `spec/acceptance/wf005_checkpoint_pass_concurrency_spec.rb` | 10 |
| `spec/workflows/wf005/terminal_selection_spec.rb` | 12 |
| `spec/acceptance/wf005_admission_terminal_concurrency_spec.rb` | 9 |
| `spec/acceptance/wf005_sitemap_discovery_spec.rb` | 7 |
| `spec/workflows/wf005/limit_semantics_spec.rb` | 6 |
| `spec/persistence/crawl_terminal_fact_closure_spec.rb` | 6 |
| `spec/acceptance/wf005_start_cancel_concurrency_spec.rb` | 3 |
| `spec/platform/pg_instant_spec.rb` | 3 |

`spec/architecture/wf005_time_single_surface_spec.rb` is deliberately absent from the table: its seven
examples consume no workflow proof numbers, so a count for it would be a different measure sharing a
column with these.

## Ownership and stop boundary

FU-38 and FU-41 are `resolved` in `BUILD_STATE.json`; this report no longer lists either as open and no
longer repeats FU-41's superseded “FOR UPDATE is redundant” explanation. FU-42 remains open. FU-7,
FU-22, FU-37, FU-39 and FU-40 also remain open and unchanged by this bounded repair. The round-5
non-blocking observations remain recorded in the independent review and are not silently promoted or
repaired here.

FU-9's transferred obligation is WITHDRAWN by owner ruling 3 and reconciled in `BUILD_PLAN.yml` and
`BUILD_STATE.json`. Nothing is owed to another block by that withdrawal.

The remaining genuine owner decisions are FU-32 (CancelCrawl pass-boundary semantics), FU-33 (pre-terminal
event members), FU-43 (the frozen F-01 total request-deadline question), and R3-P1 through R3-P3 (the
pre-existing migration-chain/governance scope questions). The round-6 repairs deliberately decide none of
them: in particular `fetch_attempts` is left outside the terminal fact closure precisely because closing
it would settle FU-32 silently.

### Recovery work that remains S-07-011's

Owner ruling 4 requires every nonterminal state to have a deterministic path to a terminal one, and bounds
this tranche to four obligations, all of which are met. Two residues are created by the repairs and both
belong to S-07-011's existing stranded-claim recovery (FU-22), recorded here rather than given an ad hoc
substitute:

1. **A sitemap gate left `in_progress` on a terminal Crawl.** A discovery worker whose run ends mid
   traversal cannot hand its claim back, because `release_sitemaps` writes `sitemap_state`, which is
   itself closed on a terminal Crawl. The gate is inert — the coverage record is frozen, nothing reads it
   again, and it is counted as `unattempted_discovery` — but it is a claim nobody will release.
2. **A frontier entry left `in_progress` on a terminal Crawl.** Unchanged by this tranche and pre-existing:
   the closure governs INSERTs, so `retire` may still terminalize an entry it legitimately claimed.

Neither blocks acceptance of this tranche and neither is a new obligation; both are the same sweep FU-22
already names.

**Stop here. Do not commission Round 7 from this repair-author context. Do not accept S-07-009. Do not
proceed to S-07-010 or S-07-011 on this unaccepted dependency without a new owner instruction.**
