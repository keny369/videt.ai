# PREREQ-DB-BOOTSTRAP — Database Bootstrap Provenance

Repository-wide prerequisite. Not a tranche. Disposition recorded in `DECISIONS.md` ADR-129.

## What was wrong

`bin/f1db db:migrate` against an empty database loads `db/structure.sql` and executes **zero**
historical migrations. Every "from empty" claim in this repository therefore described a **structure
load**, and the gate that was supposed to catch this compared a file with a dump of itself.

The mechanism is exact. `db:migrate` calls `DatabaseTasks.migrate_all`, which calls
`initialize_database` for each config (activerecord-8.1.3.1 `database_tasks.rb:243`). That method
(`:651-669`) finds no `schema_migrations` table on an empty database and, because a schema dump path
exists, calls `load_schema`. `db/structure.sql` carries recorded versions for all 70 migrations, so
the migration run that follows finds nothing pending.

## Reproduced with a controlled marker, not inferred from schema correctness

A sentinel migration dated after every real one was added to `db/migrate`. `structure.sql` cannot
contain it and its recorded versions cannot name it, so its fate separates the two operations.

| Observation | Value |
| --- | --- |
| initial state | 0 tables, 0 functions, 0 extensions, no `schema_migrations` |
| exit status of `bin/f1db db:migrate` | 0 |
| migrations reporting `migrating` | **1 — the sentinel, and only the sentinel** |
| of the 70 retained migrations, executed | **0** |
| tables afterwards | 56 |
| `schema_migrations` rows afterwards | 71 (70 imported by the structure load, 1 from the sentinel) |
| `f1_find_invitation_acceptance_replay` present | yes — a function **no migration creates** |

## Two independent reasons the migration chain cannot be the bootstrap

**It does not replay.** With the schema dump moved aside so the chain is the only thing that can
build the database, it dies at **14 of 71**: `20260721120004_create_tenant_accounts_sessions.rb:68`
CREATES `organizations` with a `lifecycle_reason` column and
`20260722120014_create_organization_lifecycle.rb:25` ADDS it — `PG::DuplicateColumn`. An earlier
migration was amended to contain a column a later one introduces, so the chain is not a faithful
history of how any database was built.

**It cannot produce the canonical schema.** Of 63 functions in `db/structure.sql`, one is created by
no migration at all. Even a fully repaired chain would end somewhere else.

## The model selected — C, baseline plus forward migrations

Model B was rejected on evidence: replaying a retroactively edited history proves nothing about any
upgrade any installation performed. Model A was rejected because it permanently forfeits upgrade-path
proof, and this repository has no deployed installation today — which is exactly why a baseline can
be cut cleanly now and never again this cheaply.

| Artifact | What it is |
| --- | --- |
| `db/baseline/BASELINE.sql` | the immutable baseline schema, cut from `52818fc` |
| `db/baseline/BASELINE.json` | its manifest: sha256, 70 pre-baseline versions, the single supported upgrade origin, and why the pre-baseline migrations are historical records |
| `bin/f1-db-bootstrap` | loads the baseline, then executes **every post-baseline migration**, verifying the baseline digest, the declared empty initial state, and the recorded version set |
| `bin/f1-db-bootstrap-gate` | the clean-database gate, adversarially defended |
| `lib/tasks/f1_db_fingerprint.rake` | a schema fingerprint deep enough to be worth comparing |
| `bin/f1-provision-db` | **deprecated**, delegates, and records what it used to claim falsely |

## The gate, and what each check exists to catch

| Check | Adversarial case it refuses |
| --- | --- |
| refuses a dirty tree | measuring the working tree instead of the candidate |
| declared initial state verified | starting from an already-current database |
| baseline load recorded all 70 versions | a partial import reading as success |
| expected post-baseline count, **derived from the artifacts** | skipping a migration, or restating a number |
| recorded version set == baseline ∪ migration files | a wrong migration-version state |
| deep fingerprint vs `db/structure.sql` | comparing table names while missing constraints or policies |
| fingerprint dimensions must be non-empty | two nulls comparing equal |
| a pending migration executes **exactly once** with its effect present | running zero migrations while claiming a migration build |
| bootstrap onto a populated database refused **for the stated reason** | the empty-state guard silently deleted |
| one-byte baseline tamper detected and restored | a stale or edited baseline |

The gate was itself mutation-tested. Removing the empty-state guard, removing the baseline
immutability check, and truncating the baseline load to a bare `schema_migrations` table each make it
FAIL, and each control was restored and confirmed.

## Evidence language corrected

24 evidence claims across 17 files asserted that migrations "build from empty". Each now states the
operation actually performed and cites ADR-129. The claim that the last **accepted** tranche was
"verified from empty" was one of them; the figure `rspec 1977/0` is unchanged and still true, and what
is corrected is the operation its evidence described.

Two specification documents stated "from empty" as a **requirement** rather than as evidence, and are
reconciled to Model C rather than deleted. Matches in `spec/acceptance/wf005_admission_spec.rb` (byte
budgets) and `OWNER_DECISION_REGISTER.md` (a reason vocabulary authored from scratch) are not database
claims and are untouched.

## Effect on S-07-009

S-07-009's schema/migration-safety evidence depended on the false claim and is **invalidated**. No
S-07-009 blocker was caused by it and none is cleared by repairing it. S-07-009 remains **NOT
ACCEPTED**, blocked independently by R10-10 (reproduced and exploitable), the WF-013 stability
failure, the red full suite at 2251/9, the dead production code the tranche introduced, and R10-15.
S-07-010 and S-07-011 remain blocked. The repair branch `repair/s07-009-r10` is preserved unmerged.

## Gate results

| Gate | Result |
| --- | --- |
| `bin/f1-db-bootstrap-gate` | 9 checks passed, run 3 times |
| `bundle exec rspec` | 2248 examples, 0 failures, 8 pending |
| gate mutation testing | 3 controls removed, 3 killed, 3 restored |

## An unrelated finding this item's runs settled

**THE WF-013 CONCURRENCY HANG IS PRE-EXISTING AND REPOSITORY-LEVEL, NOT CAUSED BY S-07-009's ROUND-11
INSTRUMENTATION.** The round-11 record hypothesised that `AuthoritySentinel::WriteObserver` — newly
prepended to `PG::Connection#exec_params` on every statement in every thread — was a plausible
mechanism for `wf013_organization_lifecycle_concurrency_spec.rb:188` timing out at its 15-second
bound. **That hypothesis is refuted.** This branch is based on `52818fc` and carries none of that
instrumentation (`grep -c WriteObserver spec/support/authority_sentinel.rb` → 0), and the same example
hung here in a full-suite run. Run in isolation on the same tree it passes, 9 examples, 0 failures.

So the defect is intermittent, dependent on full-suite context, and older than the tranche that was
blamed for it. It remains a blocker for S-07-009 acceptance under the standing stability requirement,
but it is not an S-07-009 defect and repairing S-07-009 will not fix it. It needs a follow-up of its
own.
