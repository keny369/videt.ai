# S-07-009 — Crawl Execution: Terminal Checkpoint, Coverage/Completion, CancelCrawl

**Acceptance status: NOT ACCEPTED. The round-10 repair is complete under ADR-126; this report is not an acceptance record.**

Nine full ADR-026 five-lens rounds have reviewed this tranche and all nine returned FAIL. Round 9
(ADR-125) closed six of round 8's nine blockers and then reproduced its own failure mode one step
later in the other three: **it replaced three enumerations with three narrower enumerations.**

```f1-evidence
candidate_range: 7f043a2..6d00aa1
frozen_path_changes: 2
frozen_paths:
  - lib/f1/runtime_grants.rb
  - spec/architecture/wf005_time_single_surface_spec.rb
suite_examples: 2311
review_rounds: 9
```

The block above exists because round 9's frozen-path gate NEVER EXECUTED: it read prose with a regex
expecting a literal space, the record's only claim wrapped across a line, and the example skipped in
every run. A fact a gate depends on does not live in a sentence any more.

### The pattern this round was authorised to remove, and how

| Round 9 blocker | What it enumerated | What replaced it |
| --- | --- | --- |
| R9-1 | a list of two classified translation EXCEPTIONS, missing a third producer | **no exceptions at all.** Both command handlers now translate, so `CLASSIFIED_UNTRANSLATED` is empty; completeness is a runtime census over every execution API `PG::Connection` exposes |
| R9-3 | a matrix of two authority AXES, missing a third that was exploitable | **the write refuses.** `Wf005::AuthorityAttestation` is minted only by a passing recheck and demanded by every protected commit, so no Boolean arrangement reaches a commit without one |
| R9-4 | a source LINE standing in for a control | **method invocation.** `ExecutionProbe.watch` observes `:call`, which no short-circuit can fake; `line_of` now refuses to resolve a control to a continuation line Ruby never reports |
| R9-5 | a list of receiver and BINDING FORMS, missing four classes | **the taint is the value.** A `timestamptz` read by WF-005 arrives wrapped; assignment, `&:symbol`, containers, aliases and helpers all carry it, because it is the object rather than the spelling |
| R9-7 | a per-line text scan defeated by one method indirection | **there is nothing to reimplement.** `Platform::RunDeadline` answers :442's questions and exposes no comparison and no raw instant |
| R9-2 | a regex over prose | the `f1-evidence` block above, and an absent block is a FAILURE rather than a skip |
| R9-6 | a ledger that reported on itself | `AutonomousBuild::MutationHarness`, IN the repository, with each entry carrying its exact substitution so the gate can prove it is replayable |

### The :442 cross-deadline defect, repaired

Round 9 reproduced a real product defect and correctly left it for an owner decision: a pass consults
the wall clock once, at entry, then makes network requests. A pass entering one second inside its
deadline and spending 1.6 seconds on robots STARTED A SITEMAP REQUEST 0.659 SECONDS AFTER THE RUN WAS
OVER, and could mint a forward action from work performed after expiry.

**The rule is now enforced where requests actually leave.** `Wf005::RunBoundedOutbound` wraps the
façade the pass hands to every producer and checks the run's deadline AT THE MOMENT OF EACH REQUEST,
against the pass's own anchored instant rather than a raw database clock. A check before each fetch
would have been a list of request sites, and this tranche's history is lists being one entry short.
`DeadlinePassed` descends from `Exception`, not `StandardError`, because every producer wraps its
network call in a rescue that turns a fault into a RETRYABLE outcome — scheduling another attempt for
a run whose clock has stopped is precisely what ":442 stop scheduling affected work" forbids. PROOF
194-197 drive real request ordering and do not pre-resolve the window they test.


### Mutation evidence

Every entry is verified replayable from the repository by `AutonomousBuild::MutationHarness`: it carries the exact substitution, its `from` text must occur EXACTLY ONCE in the named file, and `landed` is computed from the file's own bytes rather than accepted as input.

| Mutation | Blocker | Result |
| --- | --- | --- |
| `r10-authority-supersede-axis` | R9-3 | killed, 15 examples, 15 failures |
| `r10-authority-queue-policy-axis` | R9-3 | killed, 43 examples, 43 failures |
| `r10-authority-cancel-state-axis` | R9-3 | killed, 17 examples, 16 failures |
| `r10-attestation-not-required` | R9-3 | killed, 9 examples, 8 failures |
| `r10-handler-translate-removed` | R9-1 | killed, 7 examples, 7 failures |
| `r10-checkpoint-translate-removed` | R9-1 | killed, 33 examples, 32 failures |
| `r10-pass-translate-removed` | R9-1 | killed, 7 examples, 7 failures |
| `r10-deadline-boundary-weakened` | R9-7 | killed, 10 examples, 3 failures |
| `r10-deadline-indirection` | R9-7 | killed, 9 examples, 8 failures |
| `r10-outbound-unbounded` | :442 | killed, 9 examples, 6 failures |
| `r10-request-bound-not-equality` | :442 | killed, 9 examples, 1 failure |
| `r10-refusal-swallowable` | :442 | killed, 9 examples, 2 failures |
| `r10-entitlement-commit-boundary` | FU-44 | killed, 11 examples, 1 failure |
| `r10-entitlement-prestart-boundary` | FU-44 | killed, 19 examples, 1 failure |


### The proof-system audit

Every defect class the owner named was checked against this repair's own work, and four were found in
it. They are listed because finding them is the point of running the audit on yourself.

| Class | Found in this repair? | Disposition |
| --- | --- | --- |
| claims based on source lines rather than evaluated controls | yes — the old probe | replaced by invocation observation; `line_of` now REFUSES a continuation line, so the vacuous negative assertion is impossible |
| completeness claims based on manually maintained counts | yes — the record's counts | derived by the gate from the files, and the suite size compared to `rspec --dry-run` |
| regexes over prose or formatting | yes — the frozen-path and round-count limbs | both moved into the `f1-evidence` block; an absent block FAILS |
| syntactic scans presented as semantic guarantees | yes — the time-surface rule | it remains as a SECONDARY net and is no longer the completeness mechanism; the value guard is |
| tests satisfiable by a different mechanism | checked | PROOF 195 asserts the request COUNT and the halt reason; PROOF 172 asserts the write was attempted AND refused |
| fixtures that pre-remove the behaviour under test | checked | PROOF 194-197 deliberately do not pre-resolve robots or sitemaps, which is what made round 9's :442 proofs unable to fail |
| mutations landing at the wrong identical site | closed | the harness requires the `from` text to occur EXACTLY ONCE — the FU-44 class |
| negative assertions that can pass vacuously | closed | `expect_did_not_write` asserts on `require!` invocation, which is observable in both directions |
| sentinels observing one database execution API | yes — the governed-write sentinel | routed through `WireTap`, which covers every door `PG::Connection` defines and proves the set against the live class |
| defaults preserving a known unsafe affordance | yes — `Admission#claim_next(anchored_at: nil)` | the keyword is now REQUIRED; it had no production caller, so the default was the `m1c` mutation left in place for the next caller to inherit |
| gates that can hang rather than fail | closed | `wf013`'s join is bounded and reports thread states and backtraces |

**One process fault is recorded rather than glossed.** A full-suite run and a mutation-ledger replay
were allowed to run concurrently against the same database. The resulting failures were DISCARDED, the
database was re-provisioned from empty, and everything was re-run serially. No result in this report
comes from that window.

## Identity

| | |
| --- | --- |
| Block | S-07-009, BUILD_PLAN `Crawl Execution — terminal checkpoint + coverage/completion + CancelCrawl` |
| **Repair candidate** | **`7f043a2..6fda00d`, PINNED** — never `..HEAD` |
| Round-8 reviewed candidate | `7f043a2..e1f5bab`, governance `5dadf7f` (FAIL, nine blockers; findings in `S-07-009_ACCEPTANCE_REVIEW.md` § ROUND 8) |
| Repair authority | ADR-124; ADR-122's isolation invariant remains in force and is extended to Redis |
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
FrozenContracts`, and ADR-124 names it explicitly for repair. **THE TRANCHE CONTAINS TWO FROZEN-PATH
CHANGES, NOT ONE** — this detector and `lib/f1/runtime_grants.rb`, which is the ratified additive-grant
exception. Round 8's R8-7 found the record claiming "the only frozen-path change" where
`FrozenContracts.frozen_changes` returns two, and `repository_truth_spec.rb` now derives that number from
the candidate diff rather than accepting a sentence about it. The check keeps ADR-117 R5-2's narrow scope and creates
no new family of checks.

Its detector carries three structural rules, and round 9 rebuilt the third of them. Round 6 replaced an
enumeration of four AST SPELLINGS with a ban on two NAMES; round 7's A-1 showed that is still an
enumeration and added rule 3, about the RECEIVER; round 8's R8-6 then showed that rule 3 was itself a new
enumeration, and walked THIRTY OF FORTY-ONE bypass forms past it. Its two axes each listed things: the
CALL axis fired only on Ripper's `:call`, so `crawl["x"].strftime "%s"` — a parenless call, which is
`:command_call` — escaped, which is round 6's own escape #3 recurring one rule later inside the rule
written to close it; and the RECEIVER axis named three shapes and four node kinds, so `crawl.dig("x")`,
`(crawl["x"])` and `d = crawl["x"]; d.to_time` all escaped.

**BOTH AXES ARE NOW INVERTED, WHICH IS THE DIFFERENCE BETWEEN A RULE AND A LONGER LIST.**

* A CALL IS RECOGNISED BY ITS OPERATOR. Every explicit-receiver call in Ruby is `receiver <op> name`
  where `<op>` is `.`, `&.` or `::` — a closed set the LANGUAGE defines — so any node of that shape is a
  call whatever Ripper labels it, including labels that do not exist yet. The detector names no node
  kind, and an example asserts that it does not.
* A RECEIVER MUST BE PROVED IN MEMORY. Locals, parameters, instance variables, symbol-keyed subscripts of
  those, literals, and chains over them. ANYTHING ELSE IS A FINDING, including shapes the rule has never
  been shown, so a new escape is caught by default and a new false positive is a visible failure someone
  fixes. The one structural fact it rests on is that a `PG::Result` tuple is STRING-KEYED while every
  in-memory structure in this workflow is symbol-keyed, so a name that is string-subscripted anywhere in
  a file holds a row in that file — and everything reached through it is row data, by subscript, by
  `fetch`, by `dig`, by a method nobody anticipated, through a local it was bound to, or through a block
  parameter it was handed.

Rule 1's banned constants and rule 3's vocabulary are now DERIVED FROM ONE LIST OF CLASSES rather than two
lists of spellings, which is what lets `Date.parse(crawl["x"])` be a finding while the four legitimate
`Date.new(now.year, now.month, 1)` sites are not. The NINE `.getutc` METHOD CALLS in the corpus are
untouched and correct: formatting an instant the application already holds is a different act from
deciding how to decode one.

**AND THE FORMS ARE INJECTED INTO THE REAL CORPUS, WHICH THE PREVIOUS RECORD CLAIMED AND DID NOT DO.**
Round 8 recorded that "16 forms injected into the real corpus" was inaccurate twice: the examples
evaluated synthetic programs as strings and injected nothing. Each form is now inserted into the REAL
source of `app/workflows/wf005/crawl_driver.rb`, inside a real method, at an anchor located by CONTENT,
and scanned by the same `violations` the corpus proof runs, under the same file name. That is not a
detail: rule 3 decides by PROVENANCE, so a one-line synthetic program in which nothing establishes what
`crawl` holds cannot test it. FORTY-ONE bypass forms are injected and all forty-one are caught; FIFTEEN
legitimate forms are injected the same way and none is. Six mutations of the rule itself — reverting the
call axis to `:call`, making the receiver fail open, removing the binding taint, the block-parameter
taint, the parenthesis recursion and the decoder-class limb — are each killed by a named form.

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

## Review history — nine rounds, nine FAILs

| Round | Candidate | Outcome |
| --- | --- | --- |
| 1 | `7f043a2..a414f5c` | FAIL — 11 confirmed blockers on 2040/0 |
| 2 | `7f043a2..95d37f4` | FAIL — 3 blockers on 2055/0; two were defects in round-1 repairs |
| 3 | `7f043a2..467f1d1` | FAIL — 11 in-candidate blockers on 2068/0; all three round-2 repairs were refuted |
| 4 | `7f043a2..7034e25` | FAIL — 8 blockers on 2085/0; five were defects in round-3 repairs |
| 5 | `7f043a2..ac962bb` | FAIL — 5 blockers; four were defects in round-4 repairs |
| 6 | `7f043a2..5860bb4`, reviewed through `cf2059e` | FAIL — all five lenses, 9 blockers; three reproduced as deterministic real-PostgreSQL interleavings |
| 7 | `7f043a2..4e2d8cf` | FAIL — three of five lenses, 5 blockers: C-1, C-2, SEC-B1, A-1, A-2 |
| 8 | `7f043a2..e1f5bab` | FAIL — four of five lenses, 9 blockers, EIGHT of them proof defects rather than behaviour defects |
| 9 | `7f043a2..6fda00d` | FAIL — four of five lenses, 7 blockers; six of round 8's nine closed, and three enumerations replaced by narrower ones |

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
| `bundle exec rspec` | `2248 examples, 0 failures` |
| `bundle exec rspec spec/architecture` | `137 examples, 0 failures, 1 pending` |
| `bundle exec brakeman -q --no-pager -z` | zero warnings |
| `bin/packwerk check` | no offenses; no stale violations |
| `bin/rails zeitwerk:check` | all is good |
| `bundle exec bundle-audit check --update` | no vulnerabilities |
| `bin/f1db f1:db:verify_runtime` | 15 checks passed; RLS intact |
| `bin/f1db db:schema:dump` then `git diff --exit-code -- db/structure.sql` | no structure drift |
| mutation ledger | 38 mutations, all confirmed LANDED; 37 killed, 1 recorded equivalent with its reason |

Every gate passing remains verification, not acceptance.

## Mutation and structural evidence

| Mutation or probe | Required result |
| --- | --- |
| move the fall-through soft wall-clock decision before `lock_frontier` | PROOF 132 fails at the real insert with `soft Admission decision preceded crawl frontier lock`; the concurrency examples cannot observe the required frontier waits |
| derive terminal reason from every hard decision again | PROOF 99 fails: a local per-URL decision incorrectly changes `partial_source_failure` to `limit_reached` |
| decode the checkpoint deadline with `Time.parse(deadline.to_s)` again | PROOF 145 fails 400ms before the real deadline by writing an early wall-clock decision |
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
| `spec/workflows/wf005/terminal_selection_spec.rb` | 12 |
| `spec/acceptance/wf005_admission_terminal_concurrency_spec.rb` | 11 |
| `spec/acceptance/wf005_checkpoint_pass_concurrency_spec.rb` | 10 |
| `spec/platform/pg_instant_spec.rb` | 9 |
| `spec/acceptance/wf005_closed_fact_set_spec.rb` | 8 |
| `spec/acceptance/wf005_pass_anchor_spec.rb` | 11 |
| `spec/acceptance/wf005_post_wait_authority_spec.rb` | 6 |
| `spec/acceptance/wf005_sitemap_discovery_spec.rb` | 7 |
| `spec/workflows/wf005/limit_semantics_spec.rb` | 6 |
| `spec/persistence/crawl_terminal_fact_closure_spec.rb` | 7 |
| `spec/acceptance/wf005_host_gate_robots_spec.rb` | 4 |
| `spec/acceptance/wf005_start_cancel_concurrency_spec.rb` | 3 |
| `spec/acceptance/wf005_queue_crawl_spec.rb` | 3 |
| `spec/acceptance/wf005_deadline_gates_spec.rb` | 7 |
| `spec/architecture/run_deadline_query_surface_spec.rb` | 1 |
| `spec/acceptance/wf005_cancel_authority_write_spec.rb` | 5 |
| `spec/platform/run_deadline_spec.rb` | 5 |

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

**FU-44 IS SUPERSEDED (ADR-124), not carried.** Its stated failure model was false, and the reason is
exact: `app/platform/entitlement/service.rb` holds THREE identical `if now >= effective_deadline(r)`
comparisons, so an unscoped substitution lands on the FIRST — `start_execution` at :113 — and not on
`commit` at :150, the site the follow-up names. With the mutation verified applied at :150 by diff, the
named example fails deterministically, four times out of four. The re-derivation found a DIFFERENT and
real survivor in its place: `start_execution`'s prestart boundary genuinely survived the whole entitlement
suite, and it is now closed by a named boundary proof that kills it three times out of three. No F-05
implementation was changed to preserve FU-44's existence.

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

**Stop here. Do not commission the round-9 review from this repair-author context. Do not accept
S-07-009. Do not proceed to S-07-010 or S-07-011 on this unaccepted dependency without a new owner
instruction.**
