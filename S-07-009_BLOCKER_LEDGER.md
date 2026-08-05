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

---

## D7 — CLOSED 2026-08-05, on `repair/s07-009-d7`. The antecedent is now :335's own concept.

**THE RECORDED DIAGNOSIS WAS HALF RIGHT AND ITS EXAMPLE WAS WRONG, WHICH MATTERS BECAUSE THE WRONG
EXAMPLE WOULD HAVE PRODUCED THE WRONG REPAIR.** The record said the rule "now fires on an idempotent
replay, which correctly writes its execution record without re-reading authority". A replay writes NO
execution record. `CancelCrawl#replay` loads the stored result and returns it; it executes no
data-modifying statement of any kind. Measured on this tree: the sentinel reported
`CancelCrawl SUCCEEDED and issued 1 write(s)` for a replay, and the ONE "write" was
`CrawlStartStore#lock_crawl` — a `SELECT ... FOR UPDATE`. `WRITE_VERB` matched `\bUPDATE\b` inside
`FOR UPDATE`.

So the sentinel's own header was TRUE where it said "a replay WRITES NOTHING, so it never satisfies
the antecedent". The DOOR was false. That is the third wrong verb pattern in this tranche, each
greener than the last:

| Form | What it missed | How it was found |
| --- | --- | --- |
| anchored to statement start | every CTE-shaped write, which all three protected writes are | round-two review |
| `UPDATE\s+\w` + `\b` | every UPDATE whose table name is longer than one character | round-two review |
| `\b(?:INSERT\s+INTO\|UPDATE\|DELETE\s+FROM)\b` | nothing — it matched TOO MUCH, counting `FOR UPDATE` and `FOR NO KEY UPDATE` row locks as writes | D7, by measurement |

**PROOF 232 PASSED THROUGHOUT.** It asked only whether the real writes MATCHED and never what else
did, so it certified all three.

### What replaced it: PostgreSQL answers, and nothing parses SQL

`ProtectedEffectDoor` asks the planner about the real statement:

```
EXPLAIN (GENERIC_PLAN, FORMAT JSON) <the statement, parameter placeholders and all>
```

Every `ModifyTable` node names a relation the statement modifies. `GENERIC_PLAN` (PG 16+) is what
makes this possible on the production statement — it plans `$1` placeholders with no values — so the
statement OBSERVED is the statement EXECUTED. `SELECT ... FOR UPDATE` plans to `LockRows` and yields
none, which closes the D7 symptom by construction rather than by one more character class. There is
no pattern left to certify, and `AuthoritySentinel::WRITE_VERB` no longer exists.

### The antecedent, and why "governed write" now means what :335 already said

`WORKFLOW_SPECIFICATIONS.md :335` — the rule the invariant cites — reads:

> A running privileged operation rechecks at each durable checkpoint and **stops before the next
> PROTECTED SIDE EFFECT** after revocation.

The antecedent is now that, and the term is the specification's rather than an invented one:

> a human-authorized WF-005 command that SUCCEEDS and **commits a protected side effect** must have
> evaluated `CommandAuthorizer.authority_current?` and presented an `AuthorityAttestation`.

A **governed write** is a data-modifying statement, in any shape, whose target relation carries
product facts — and the governed set is read from `pg_trigger` at run time, never listed. The
command-evidence ledgers carry no guard, because nothing about them is a product fact: every command
writes them, a denial included. **THE REPLAY EXEMPTION IS DELETED AND NOTHING REPLACES IT.** A replay
executes no statement whose plan modifies a guarded relation, so it falls outside the antecedent by
what it does (PROOF 234, PROOF 235).

**THE LEDGER'S OWN CANDIDATE REPAIR WOULD HAVE BEEN SILENTLY CATASTROPHIC AND IS RECORDED AS
REJECTED.** It proposed reusing `GovernedWriteSentinel`'s governed set, "which it already derives
from the trigger catalogue". That set is `f1_crawl_child_fact_closed` — owner ruling 2's CHILD-fact
closure — and it contains neither `crawls` nor `crawl_policies`. Adopting it would have made the
antecedent unsatisfiable and the headline invariant would have gone quiet while reporting success.
Both files now carry the disambiguation.

### The classification is checked against a property it does not use

Governed is derived from `pg_trigger`; the check reads `pg_attribute`. The dangerous
misclassification is a product aggregate called command evidence, because that direction is SILENT —
the antecedent stops being satisfied and the run goes GREENER. So every relation the run observed a
WF-005 command write and classify INCIDENTAL must carry no `state` lifecycle either (PROOF 238), and
the shape it looks for is shown to exist in this schema so the check is not vacuous (PROOF 238b).

Four further whole-suite emptiness checks were added, each of which fails a blind run rather than
quietening it: zero protected side effects observed; a human-authorized handler never observed
committing one; a statement that executed successfully and could not be planned; a relation with a
lifecycle and no guard.

---

## D8 — the round-two lock repair was measured and it does not hold. CLOSED 2026-08-05.

**FOUND WHILE PROVING D7, NOT REPORTED BY A REVIEW.** `b2e8cfb` made all three authority reads
`FOR KEY SHARE` and recorded that this "makes an epoch advance conflict with them, so the claim is
unconditional rather than conditional on an enumeration nobody wrote down".

**THE CLAIM IS FALSE.** `authorization_epoch` belongs to no key, so advancing it is a NON-KEY update
and takes `FOR NO KEY UPDATE`, which DOES NOT CONFLICT with `FOR KEY SHARE`. Measured on the real
`organizations` row with the real revocation statement (PROOF 239):

| Reader holds | Concurrent epoch advance |
| --- | --- |
| `FOR KEY SHARE` | **COMMITTED straight through** |
| `FOR SHARE` | BLOCKED |
| `FOR UPDATE` | BLOCKED |

The repair had restated the very premise it was written to remove, and nothing in the suite could
tell, because nothing measured the conflict. All three authority reads are now `FOR SHARE`, which
conflicts with the advance and NOT with a second `FOR SHARE` reader — so two authorized commands for
one Organization still run side by side rather than queueing.

**AND IT IS PROVED ON THE GUARDED STATEMENTS, NOT ONLY ON THE LOCK MATRIX.** PROOF 240/241/242 drive
each of the three protected writes into a genuine mid-flight block — the cancellation on the `crawls`
row, the queue insert on its `projects` foreign-key check, the activation on the row it supersedes —
observe the block through `pg_blocking_pids`, and show the revocation CANNOT land inside the window.
Nothing enumerates who else might hold a lock: the causal edge is read out of the catalogue.

---

## FU-48 — IMPLEMENTED 2026-08-05 under the owner decision. The capability axis has a write-level counterpart.

**WHAT WAS OPEN, IN THE CODE'S OWN WORDS.** `QueueCrawl` recorded it exactly: the epoch conjunct
"detects a CHANGE in authority since authentication. It does not detect the ABSENCE of a capability:
`decision.allowed?` above is the only thing that refuses an actor who never held `crawl.trigger`, and
deleting it lets such an actor queue a Crawl that this write will happily insert."

**THE COUNTERPART, AND WHY IT IS NOT A SECOND IMPLEMENTATION OF THE ALGORITHM.** The six-step
effective-permission algorithm reads two kinds of input. One is IMMUTABLE FOR THE LIFE OF A DEPLOY —
the `permission-baseline-v1` cells, the protected-grant enumeration — and cannot change under a
running command. The other is ORDINARY ROW STATE another transaction can move while this one waits:
whether the Assignment that conferred the capability is still active, effective, unexpired, at the
version and scope the decision saw. Only the second kind can go stale, and only the second kind
belongs in the statement. Re-deriving the baseline in SQL would put a second copy of the authority in
the database.

So each protected write now carries `IdentityAccess::Authorization::WriteAuthority` — the grants
`Decision#granting_assignments` actually relied on — and PostgreSQL re-reads them in the same
statement as the transition, under `FOR SHARE`. An actor who never held the capability carries no
grant, the array is empty, and the predicate is false. `AuthorityAttestation` carries the same
object, so an attestation minted for one capability or grant set cannot be presented at a write
carrying another.

**THE SCOPE AXIS HAS TWO LIMBS AND FU-48 NAMED BOTH. BOTH ARE NOW AT THE WRITE.**

*The grant's own scope* is bound: `scope_hex` is carried and compared, so a write refuses when the
grant's scope is not the one the decision evaluated (PROOF 246).

*The RATIFIED SCOPE RULE* — `:732`/`:738`, "OrganizationAdmin … may activate a more restrictive
immutable Organization version; MarketingOperator with that permission may do so only for a Project"
— is the limb FU-48's own record demonstrated: "removing the single `authorized_for_scope?` operand
lets a MarketingOperator commit an ORGANIZATION-scope crawl policy — the latter surviving 2364
examples but for two hand-written ones." That rule was transcribed in exactly one Ruby predicate and
nothing below it. It is now transcribed ONCE, in `ActivateCrawlPolicy::SCOPE_ROLE`, read by BOTH the
Ruby guard and the write: the role the SCOPE demands is derived from the scope and handed to the
statement as `WriteAuthority#required_role`, and the capability CTE requires the granting Assignment
to hold it. Removing the Ruby operand no longer commits anything (PROOF 258), the predicate is not a
blanket refusal (PROOF 258b), and the rule cannot drift because there is one copy (PROOF 258c).

**WHAT IS STILL NOT DECIDED HERE, AND IS NOT D7'S TO DECIDE.** Whether an Assignment's scope must
CONTAIN the target is **FU-2** — a pre-existing, platform-wide deferral recorded in `DECISIONS.md`
for every resource capability (`policy.source_scope.manage`, `source.scope.propose`,
`source.register`, `project.create`), demonstrated live as a within-tenant cross-project escalation,
and backlogged under ADR-066. Inventing containment under a repair would be new authorization
semantics. What D7 does is give that axis a place at the write, so the containment predicate has one
obvious home the day FU-2 is taken.

**A HANDLER'S OWN CHECK STILL HAS A PROPERTY OF ITS OWN.** With the write as the backstop, deleting
`decision.allowed?` no longer produces an unauthorised transition — so the OUTCOME alone can no
longer tell the two apart, and a proof that only checked the outcome would let the check be deleted
silently. `PRULE-039`/SEC-REQ-005 supplies the property: a check performed after a side effect is a
bypass regardless of its arithmetic. PROOF 255/256/257 observe, by INVOCATION, that each handler
refuses an actor holding no authority BEFORE taking the lock other tenants queue behind.

**FU-48 IS RESOLVED. FU-2 REMAINS OPEN, PLATFORM-WIDE, AND IS NOT AN S-07-009 BLOCKER.**

---

## D9 — the round-two harness repair reached one of its two replay paths. CLOSED 2026-08-05.

**FOUND BY THE D7 MUTATIONS, NOT BY A REVIEW.** `b2e8cfb` recorded that "`broken` now means what it
says, since treating any after(:suite) error as 'no example ran' misclassified two real kills" — and
applied that correction to ONE of the harness's two replay paths.

**AND THIS RECORD HAD THE DIRECTION BACKWARDS UNTIL ROUND 16 MEASURED IT (R16-CTR-2).** The bytes at
both `b2e8cfb` and `ea8ef8d` read the same way: `replay` - the file path, which carries all 82 of the
92 definitions that are file mutations - CARRIED the correction, and `replay_trigger`, which carries
the other 10, still ended `else "broken"`. The path left classifying a suite-level error as "proving
nothing" was the TRIGGER path, not the file path. The defect D9 names is real and was real; the
sentence describing which half had it was wrong, twice, and is corrected here rather than left
standing.

Measured on the first D7 regeneration: `d7-door-regex-restored` (13 examples, **7 failures**) and
`d7-antecedent-dropped` (13 examples, **1 failure**) both trip `AuthoritySentinel`'s suite-wide rule
IN ADDITION to failing their proof — the strongest possible kill — and both were recorded as proving
nothing, which `verify_bindings!` then reports as a ledger error. A repair applied to one of two
paths is this tranche's own defect class one level up, inside the machinery that measures it.

Both paths now carry the same classification: `broken` means no example ran; a run with failures, or
a run whose examples passed but which tripped a suite-wide invariant, is a KILL.

**AND THAT CLOSURE WAS FALSE WHEN IT WAS WRITTEN. ROUND 15 MEASURED IT (R15-CONC-2).** The correction
reached `replay` and NOT `replay_trigger`, which still ended `else "broken"` — the same one-of-two
shape, one round later, in the same file. Neither copy had a test, which is why it survived a repair
written to remove exactly this. **THE TWO COPIES ARE NOW ONE**: `MutationHarness.classify` is the
single implementation both paths call, and `spec/automation/unit/mutation_harness_classification_spec.rb`
proves all four outcomes including the case the copies disagreed on. No ledger verdict was wrong —
all ten trigger definitions kill with failing examples, so the divergent branch was never reached —
so this was a false RECORD and a latent asymmetry rather than a live proof-system defect.

---

## D10 — a proof whose verdict was the scheduler's choice. CLOSED 2026-08-05.

**FOUND BY REPLAYING THE BATTERY TWICE, WHICH IS THE ONLY WAY IT COULD BE FOUND.**
`f4-accounting-global` — the D5 family-4 mutation that returns the sentinel's per-thread accounting to
process-global state — was **killed on one regeneration and SURVIVED the next, from the same bytes.**

The proof incremented the frame counter and THEN synchronised, so whether the mutation showed depended
on the interleaving: if each thread opened its frame AFTER the other had incremented, the shared frame
was reset to zero between them and both threads still read 1. Only one of the possible orderings can
distinguish per-thread accounting from shared accounting, and nothing made that ordering happen.

Both frames are now opened BEFORE either increments — the only interleaving that can tell the two
apart is now the only one that runs. Replayed three times: killed, killed, killed.

**THIS IS THE DEFECT CLASS THE TRANCHE EXISTS TO REMOVE, INSIDE ITS OWN INSTRUMENT.** A proof that
reports the scheduler's choice is a proof whose green result means nothing, and a mutation ledger
generated once cannot see it. The regeneration was run repeatedly for exactly that reason.

---

## The rule, restated after D7

The rule at `:150` stands unchanged and is not superseded by anything below it. S-07-009 is NOT
ACCEPTED by this branch. D7, D8, D9 and D10 are closed with production fixes and direct proofs, and
FU-48 is implemented under its owner decision; acceptance remains an independent five-lens review's
decision, and no acceptance transition, merge, push or progression is authorised until one returns
PASS.

---

## ROUND 15 — the D7 candidate was reviewed, and it carried two live authority defects

Recorded 2026-08-05 on `repair/s07-009-r15`. Full findings in `S-07-009_ACCEPTANCE_REVIEW.md` § ROUND 10;
disposition in `DECISIONS.md` ADR-133.

**THE CANDIDATE PASSED EVERY MANDATORY GATE AND WAS STILL WRONG IN TWO PLACES THAT MATTER.** rspec
2407/0 three times consecutively, zeitwerk, packwerk, brakeman, bundler-audit, `verify_runtime`, no
structure drift, the bootstrap gate's nine checks, and a 92-row mutation ledger regenerated twice
independently with no verdict difference. Four of five lenses returned FAIL anyway.

| Finding | What was actually wrong | Status |
| --- | --- | --- |
| **R15-SEC-1** | `QueueCrawl` and `ActivateCrawlPolicy` handed the write the instant they ENTERED with, so the grant-lifetime conjunct was judged before an unbounded lock wait. An expired Role Assignment queued a Crawl and activated an immutable Organization-scope policy, live. `CancelCrawl` was correct, and that asymmetry was the finding. | CLOSED — both handlers adopt the post-wait instant they were already computing; PROOF 259/260 fail before the fix, PROOF 261 locks the handler that was right, each paired with a must-succeed control |
| **R15-CONC-1** | FU-48's second row lock closed a deadlock cycle: the protected writes take `organizations` then `role_assignments`, the WF-013 authority handlers took them the other way round, nothing serialized the two sides, and nothing rescues 40P01. 20 customer-command deaths and 8 revocation deaths over 80 rounds. | CLOSED — one global order, `organizations` first, in all three WF-013 handlers; PROOF 262 MEASURES the order inside the handler's own transaction, PROOF 263 replays it, PROOF 263b requires the reverse to deadlock, PROOF 264 measures the WF-005 half |
| **R15-CTR-1** | `ActivateCrawlPolicy#authorized_for_scope?` — the single transcription of the ratified `:732`/`:738` scope rule — could be deleted with 1136 acceptance examples green, because the write refuses either way and the OUTCOME cannot tell them apart. Deletion changes the reason code and takes the tenant-shared lock before refusing. | CLOSED — PROOF 257b refuses a MIS-SCOPED actor by invocation, before the lock; verified to fail when the operand is deleted |
| **A15-1** | Ten conjuncts of the capability predicate could be deleted with the whole suite green: the proofs enumerated which (write, conjunct) pairs were exercised. | CLOSED — one battery, seven cases, all three writes, plus PROOF 252b/252c for the two unproved locks; all ten deletions verified killed |
| **A15-2** | Handler discovery was a NON-RECURSIVE directory glob and the observer was prepended into one ancestry, so a handler one directory deeper, or one exposing `def self.call`, was invisible — and invisible is greener. | CLOSED — discovery is the `Workflows::Wf005::Handlers` namespace walked; both ancestries observed; both escapes have proofs |
| **A15-3** | Four public members added by D7 have no caller anywhere — D1's rule inside D1's own tranche. | CLOSED — deleted |
| **R15-CONC-2 / R15-CTR-2 / R15-CTR-3** | D9's closure was itself false (`replay_trigger` still ended `else "broken"`); three records gave three inconsistent definition counts; the door described a whole-suite cross-check that does not exist and could not. | CLOSED — one classifier with the first spec that decision has ever had; counts measured; the door's comment now states what is actually checked and names its limit |

**THE RULE AT `:150` STANDS AND IS NOT SATISFIED BY THIS ROUND.** S-07-009 is NOT ACCEPTED. The
repaired state is a NEW candidate and needs its own independent review: in fourteen rounds, no repair
has ever been accepted on the strength of its own author's verification, and this round is the reason
why — every gate was green on a candidate carrying two live authority defects. S-07-010 and S-07-011
remain blocked.
