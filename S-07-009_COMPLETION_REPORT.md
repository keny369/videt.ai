# S-07-009 — Crawl Execution: Terminal Checkpoint, Coverage/Completion, CancelCrawl

**Acceptance status: NOT ACCEPTED. The round-5 repair candidate is complete under ADR-117.**

Five full ADR-026 five-lens rounds have reviewed this tranche and all five returned FAIL. The owner
authorized the R5-1 through R5-5 repair programme, including one exact frozen architecture check; that
authorization did not accept S-07-009 and explicitly did not commission Round 6. This report records the
completed repair candidate and the stop boundary. It is not an acceptance record.

## Identity

| | |
| --- | --- |
| Block | S-07-009, BUILD_PLAN `Crawl Execution — terminal checkpoint + coverage/completion + CancelCrawl` |
| **Repair candidate** | **`7f043a2..5860bb4`, PINNED** — never `..HEAD` |
| Round-5 reviewed candidate | `7f043a2..ac962bb` (failed; findings remain in `S-07-009_ACCEPTANCE_REVIEW.md`) |
| Repair authority | ADR-117, the explicit 2026-08-03 owner rulings |
| Depends on | S-07-007, S-07-008, S-07-012 — all accepted |
| Blocks | S-07-010 and S-07-011 while S-07-009 remains unaccepted |

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

### One PostgreSQL instant surface

Every WF-005 PostgreSQL timestamp decoder uses `Platform::PgInstant`. PROOF 145 drives the real checkpoint
one microsecond before a subsecond deadline and proves that it does not write an early wall-clock decision.
The one owner-authorized file, `spec/architecture/wf005_time_single_surface_spec.rb`, derives all tracked
Ruby under `app/workflows/wf005/` recursively, parses Ruby syntax, self-tests its decoder detector, proves
canonical use, and directly checks typed `Time`, text, nil, exact microseconds, non-mutating UTC conversion
and the 59.99/60-minute boundary. No existing frozen check, `FrozenContracts`, or F-01 through F-04 changed.

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

The migration-350 defect was absence, not arity two. PROOF 39's original enumeration could validate the
arity of foreign keys it found but could not discover a missing link; migration 380 and the strengthened
proof repair that exact gap. The separate `IS NOT DISTINCT FROM` refutation remains unchanged and is
covered by `spec/architecture/repository_truth_spec.rb`'s tracked-record corpus.

## Review history — five rounds, five FAILs

| Round | Candidate | Outcome |
| --- | --- | --- |
| 1 | `7f043a2..a414f5c` | FAIL — 11 confirmed blockers on 2040/0 |
| 2 | `7f043a2..95d37f4` | FAIL — 3 blockers on 2055/0; two were defects in round-1 repairs |
| 3 | `7f043a2..467f1d1` | FAIL — 11 in-candidate blockers on 2068/0; all three round-2 repairs were refuted |
| 4 | `7f043a2..7034e25` | FAIL — 8 blockers on 2085/0; five were defects in round-3 repairs |
| 5 | `7f043a2..ac962bb` | FAIL — 5 blockers; four were defects in round-4 repairs |

Round 5 returned contract FAIL (R5-1, R5-2), concurrency FAIL (R5-3), schema FAIL (R5-4), architecture
FAIL (R5-1, R5-2, R5-5), and security PASS_WITH_OBSERVATIONS. The complete findings and lens provenance
remain in `S-07-009_ACCEPTANCE_REVIEW.md`; this repair report does not rewrite that independent verdict.

## Verification

Run from the repair tip on PostgreSQL 17 at `127.0.0.1:5433`:

| Gate | Result |
| --- | --- |
| `bundle exec rspec` | `2110 examples, 0 failures` |
| `bin/rspec spec/architecture` | `70 examples, 0 failures` |
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

All temporary mutations were restored before the clean gate run.

## The tranche's proof surfaces

Counts below are distinct `PROOF n` identifiers, not RSpec example counts; the architecture row is
labelled separately because its five examples intentionally do not consume workflow proof numbers.

| Spec | Proofs |
| --- | --- |
| `spec/acceptance/wf005_terminal_checkpoint_spec.rb` | 31 |
| `spec/acceptance/wf005_cancel_crawl_spec.rb` | 17 |
| `spec/persistence/crawl_terminal_outcome_invariants_spec.rb` | 13 |
| `spec/acceptance/wf005_checkpoint_pass_concurrency_spec.rb` | 10 |
| `spec/workflows/wf005/terminal_selection_spec.rb` | 11 |
| `spec/acceptance/wf005_start_cancel_concurrency_spec.rb` | 3 |
| `spec/acceptance/wf005_admission_terminal_concurrency_spec.rb` | 4 |
| `spec/acceptance/wf005_sitemap_discovery_spec.rb` | 5 |
| `spec/workflows/wf005/limit_semantics_spec.rb` | 6 |
| `spec/architecture/wf005_time_single_surface_spec.rb` | 5 direct detector/corpus/decoder examples |

## Ownership and stop boundary

FU-38 and FU-41 are `resolved` in `BUILD_STATE.json`; this report no longer lists either as open and no
longer repeats FU-41's superseded “FOR UPDATE is redundant” explanation. FU-42 remains open. FU-7,
FU-22, FU-37, FU-39 and FU-40 also remain open and unchanged by this bounded repair. The round-5
non-blocking observations remain recorded in the independent review and are not silently promoted or
repaired here.

The remaining genuine owner decisions are FU-32 (CancelCrawl pass-boundary semantics), FU-33 (pre-terminal
event members), FU-43 (the frozen F-01 total request-deadline question), and R3-P1 through R3-P3 (the
pre-existing migration-chain/governance scope questions).

**Stop here. Do not commission Round 6. Do not accept S-07-009. Do not proceed to S-07-010 or S-07-011
on this unaccepted dependency without a new owner instruction.**
