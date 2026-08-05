# S-07-009 Blocker Ledger — established 2026-08-05 on `repair/s07-009-r12`

## What this is, and why it exists rather than a twelfth repair pass

S-07-009 has failed ten reviews. Rounds 10 and 11 produced findings and an architectural disposition
that were never integrated: `repair/s07-009-r10@68c1d52` is PRESERVED AS EVIDENCE ONLY and is not
merged, so this branch — cut from the authoritative state at `dc7a03c` — carries the ROUND-10 CODE
and an authoritative record that stops at ROUND 9.

**THAT GAP IS THE FIRST THING THIS LEDGER FIXES.** Every blocker below was re-verified against THIS
tree rather than carried across on the strength of a record written elsewhere. Where a round-11
repair was proved to work, that is stated as evidence and the code still has to be re-applied here.
Where a round-11 repair was proved NOT to work, that is stated too, because re-applying it would
reintroduce a false closure.

## Provenance

| Evidence | Where it lives | Status |
| --- | --- | --- |
| ROUND 10 findings R10-1..R10-21 | `repair/s07-009-r10@7820f8c`, `2343276` | preserved, unmerged |
| ADR-127 architectural disposition, ADR-128 R10-10 negative result | same branch | preserved, unmerged |
| Round-11 implementation and its mutation ledger | same branch, `8aa776b`..`68c1d52` | preserved, unmerged |
| WF-013 stability resolution | ADR-131, integrated | CLOSED |
| Database bootstrap provenance | ADR-129/130, integrated | CLOSED |

## Deterministic blockers, in the order the owner set

### D1 — dead production code. VERIFIED OPEN ON THIS TREE.

`Platform::RunDeadline#iso8601` is called by no production path. Verified here by scanning
`app/workflows/wf005/` and `app/platform/` for callers: none. A method nothing asks cannot be
defended by any behavioural proof, because no behaviour depends on it — its body could be replaced by
a constant and every example would still pass. Closing it means removing the method or driving it
from production, and then proving the choice.

### D2 — reproducible failing examples. VERIFIED OPEN ON THIS TREE.

- **R10-3.** `RunDeadline#beyond?` and `#not_after` have no proof at all. Round 11 showed each body
  could be replaced by a constant and survive the whole suite; PROOF 201/202 killed both mutations
  once written.
- **R10-4.** `RunDeadline::NONE` answers `expired?`, `remaining_seconds`, `not_after`, `present?`,
  `iso8601` and `inspect` — and NOT `beyond?` or `at?`, both of which its declared callers in
  `crawl_fetch_due_schedule.rb` invoke. Verified by reading the singleton definitions on this tree.
  Both declared no-deadline branches raise `NoMethodError`.

### D3 — R10-10. **CLOSED 2026-08-05**, and not by the rejected xid floor.

**HOW IT WAS ACTUALLY CLOSED.** `CommandAuthorizer.authority_current?` is, in full,
"`organizations.authorization_epoch` equals the epoch the actor authenticated with". That is
ordinary row state, so it is now a CONJUNCT OF THE CANCELLATION WRITE. There is no separate
check left to hoist, reorder, extract into a helper or arrange a Boolean around: PostgreSQL
evaluates authority and the state transition in one statement, at the instant of the write,
which is necessarily after every lock the handler took. No transaction-header interpretation is
involved and the multixact question below is moot — the design does not read `xmax` at all.
The two zero-row cases are computed in the same statement and reported separately, because a
revocation is a domain denial and a lost serialized transition is corruption. PROOF 216-220;
9 of 9 mutations killed by their proof targets, including the handler-branch gaps the battery
itself uncovered.

The original analysis is retained below as the record of what was ruled out.

#### The rejected approaches, retained

Hoisting the recheck above `lock_frontier`/`lock_crawl` in `CancelCrawl` passes `require!`, passes the
sentinel, and commits an irreversible cancellation on revoked authority.

**DO NOT RE-APPLY ROUND 11's REPAIR.** It added a floor — refuse to mint when
`pg_current_xact_id_if_assigned()` is NULL — and the exploit SURVIVED it at 17 examples, 0 failures,
because `auth.authorize` assigns the transaction an xid before the locks are taken. The floor proves
"this transaction wrote something", not "this transaction took THE lock". ADR-128 records this as a
measured negative result.

The identified closure is a row-bound invariant: after `SELECT ... FOR UPDATE`, that tuple's `xmax`
equals `pg_current_xact_id()`, verified in this repository as
`before=13162960 after=13162961 xid=13162961 MATCH=true`. **It was not adopted because it is not
validated**: a concurrent `FOR KEY SHARE` holder — which foreign-key checks take — turns `xmax` into
a multixact id, and an invariant that can raise spuriously in production is worse than a recorded
gap. Closing D3 requires that multixact proof first, or an owner-authorised narrowing of what the
post-wait mechanism claims.

**FIRST MEASUREMENT OF THE MULTIXACT HAZARD, 2026-08-05. IT LOOKS SMALLER THAN FEARED, AND ONE PROBE
IS NOT A PROOF.** A transaction took `SELECT ... FOR UPDATE` on a parent row and held it while a
second transaction inserted a child row, which is the FK-induced `FOR KEY SHARE` case the hazard was
about. The locking transaction's `xmax` on that row REMAINED EQUAL TO ITS OWN XID
(`A_xid=13739220`, `xmax_after_other=13739220`, `MATCH_AFTER=true`).

The mechanism is that `FOR UPDATE` CONFLICTS with `FOR KEY SHARE`, so the second transaction waited
rather than joining a multixact, and the holder stayed the sole locker. If that generalises, the
row-bound invariant is safe for rows locked with an explicit `FOR UPDATE`, which is what WF-005 takes.

**WHAT THIS DOES NOT ESTABLISH, and why D3 stays open.** The probe demonstrated BLOCKING; it did not
construct a multixact and then observe the predicate. It does not cover `FOR NO KEY UPDATE`, which a
plain non-key `UPDATE` takes and which does NOT conflict with `FOR KEY SHARE`, nor a row that already
carries a live multixact when the handler arrives. A designed concurrency proof over those cases is
what D3 needs before the invariant is adopted, and adopting it on one favourable probe is precisely
the shape of reasoning that produced ten failed rounds.

### D4 — R10-15. **CLOSED 2026-08-05.**

PROOF 157 is replaced by BEHAVIOURAL proofs that observe the trigger's decision: each governed
column or coherent group is written post-terminal against a gate whose OWN guards still permit
the write, and must be refused by the closure; pacing must still succeed; every write must
commit on a live run so a malformed write cannot masquerade as a refusal; and a census derived
from the WHEN clause requires every governed column to be exercised. 4 of 4 trigger mutations
killed, including the `OR`->`AND` mutant R10-15 named, which the old text proof could not see.

The original finding is retained below.

#### The finding, retained

Replacing `OR` with `AND` in the trigger's WHEN clause keeps all seven column names present, so the
proof passes while the limb becomes unfireable — a post-terminal `sitemap_state` write is ACCEPTED
under the mutant and REFUSED at HEAD, with 248 examples green. The proof asserts the presence of
names in text; the contract is about when the trigger fires.

### D5 — the proof-system blockers round 11 proved repairable. OPEN HERE; the repairs are known-good.

Each was closed on the preserved branch with an adversarial mutation that is killed. The code is not
on this branch and must be re-applied and re-proved here, not assumed.

| Blocker | What is wrong | Round-11 outcome |
| --- | --- | --- |
| R10-17, R10-18 | an inverted `:442` boundary survives the full suite through `instant_for_transport`; PROOF 185/186 are a text scan and an eight-name denylist | KILLED by caller-bound invocation proofs |
| R10-7, R10-8 | `WireTap` cannot read prepared-statement doors and killed the headline gate with a SIGSEGV | removed; census re-based on the one door the corpus uses |
| R10-12, R10-13, R10-14, R10-16 | `RowInstantGuard` keys taint to SQL text, excludes a crawl table, is defeated by an alias, hooks 1 of 10 accessors | removed; `ftable` is 0 for any computed value, so no extension could work |
| R10-9, R10-11 | `AuthoritySentinel` discovers handlers by one regex over source text and accounts in process-global state across threads | runtime discovery; thread-local accounting |
| R10-5, R10-19 | the mutation-ledger gate validates applicability and trusts the recorded verdict | verdicts bound by SHA-256 to the bytes measured; `broken` is a distinct outcome |
| R10-21 | `ExecutionProbe` is silently blind to C-defined methods, so every negative assertion on one passes | refused at construction |

**THE ONE LESSON THAT MUST SURVIVE RE-APPLICATION.** The first version of the round-11 invocation
proofs asserted only that the owner ran *somewhere in the block*, and the inverted-gate mutation
SURVIVED that form, because a pass consults the deadline again through `RunBoundedOutbound` on every
request. Binding each assertion to the CALLER is what made all six mutations kill. A proof that a
control ran somewhere is not a proof that a given gate consulted it.

## Process blockers

- **R10-1, R10-2.** The pinned candidate must contain the implementation and its proofs, and evidence
  must be measured from a clean worktree of that candidate rather than from the working tree.

## Not S-07-009 blockers

| Item | Disposition |
| --- | --- |
| WF-013 concurrency hang | CLOSED by ADR-131. It was the harness contending with itself and was never an S-07-009 defect. S-07-009 still may not claim acceptance while any stability violation is live. |
| Database "from empty" evidence | CLOSED by ADR-129/130. S-07-009's schema evidence is invalidated by it; none of its blockers was caused by it. |
| FU-45 | **RESOLVED 2026-08-05.** Both mandatory gates now have real, owned targets and both execute (5 examples each). `spec/architecture/mandatory_gate_targets_spec.rb` makes a gate that names nothing, or a target that defines zero examples, fail loudly. No declaration was deleted or weakened. |
| FU-46, FU-47 | repository-level; recorded by ADR-130. |

## Rule carried forward

S-07-009 is NOT ACCEPTED. No acceptance transition, merge, push or progression is authorised, and
S-07-010 and S-07-011 remain blocked, until every deterministic blocker above is closed with a
production fix and a direct proof, an explicit contract amendment, or an owner-authorised
unreachability finding — and no stability violation is live.

---

## D5 — CLOSED 2026-08-05. All six families ported, reproduced and independently verified.

Each family was reproduced on this branch before porting, and each ported patch was adapted where
the current tree invalidated it rather than applied as-is.

| Family | Blockers | Reproduced here | Mutations |
| --- | --- | --- | --- |
| 6 ExecutionProbe refuses unobservable targets | R10-21 | a Struct accessor was accepted, called 5 times, `evaluated?` false, every negative assertion vacuous | 6 killed |
| 1 Caller-bound invocation proofs | R10-17, R10-18 | the boundary inverted through `instant_for_transport` left 82 examples green including PROOF 185/186 | 6 killed |
| 3 RowInstantGuard removed | R10-12/13/14/16 | `SELECT now()::timestamptz` returns `ftable = 0`; a computed value has no table identity to key on | 4 killed |
| 2 WireTap removed | R10-7, R10-8 | `exec_prepared` published the statement NAME `"wt_repro"` as if it were SQL, across 14 redefined doors | 3 killed |
| 4 AuthoritySentinel runtime discovery | R10-9, R10-11 | the regex covered 3 OF 6 handlers and a wrapped argument list defeats it; accounting on module ivars | 6 killed |
| 5 Ledger verdict byte-binding | R10-5, R10-19 | a non-zero exit read as a kill; the gate compared a self-report against itself | 12 verifier examples |

**TWO PORTED PATCHES WERE WRONG ON THIS TREE AND WERE CORRECTED, NOT APPLIED.** Family 6's
discriminator used `source_location`, which `attr_reader` HAS while `TracePoint(:call)` still never
fires for it — the most common accessor form in the language would have remained silently
unobservable. It now uses `RubyVM::InstructionSequence.of`. Family 6's staleness check could not tell
a redefinition from ordinary instrumentation and broke eight existing post-wait authority proofs; it
is dropped, because `traced_class` is re-derived on every watch and stale metadata cannot arise.

**THE MUTATION LEDGER IS REGENERATED, NOT EDITED.** `rake f1:mutations:regenerate` replays 33
definitions held in `automation/lib/autonomous_build/s07_009_mutation_set.rb`: **33 killed, 0
survived, 0 broken**, `app/` byte-clean after every apply and restore. One row was false on its first
generation and the fix was the proof, not the expectation.

## Proof-system audit, 2026-08-05

Clean against: global state leakage (the probe holds none; the sentinels are thread-scoped where they
account and process-scoped only where the question is about the run), cross-thread attribution,
source-line proxies, C-defined vacuity, stale method metadata, self-reported mutation outcomes,
identical-site misapplication, unbounded waits, forked test processes inheriting live resources,
zero-example gate targets, and staged secrets or artifacts.

**ONE RESIDUAL ENUMERATION IS OPEN AND IT BLOCKS ACCEPTANCE.**

`spec/acceptance/wf005_post_wait_authority_spec.rb` PROOF 193 selects the handlers that must consult
the post-wait owner by matching each file's source against
`/lock_(organization|project|frontier|crawl)\b|pg_advisory_xact_lock/`, and excuses the rest through
a maintained `CLASSIFIED_WITHOUT_POST_WAIT` list. That is a lock-name enumeration plus a manually
maintained completeness list — two of the defect classes this tranche exists to remove, and the same
shape as the handler regex family 4 has just replaced.

D3 supersedes it FOR CANCELLATION ONLY: authority there is a conjunct of the write, so no Ruby
arrangement can bypass it and no source scan is load-bearing. `QueueCrawl` and `ActivateCrawlPolicy`
are NOT covered by that repair, and for those two the post-wait defence still rests on the regex and
the list.

**The remedy is the one D3 already demonstrated**: make current authority a conjunct of each
protected write, which removes the need to identify which handlers must consult anything. Until that
is done for both handlers, S-07-009 is not acceptable — the tranche would be accepted on a mechanism
whose failure mode is the one it has failed on six times.
