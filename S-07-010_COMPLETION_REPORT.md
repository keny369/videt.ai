# S-07-010 — Crawl Execution: Documents, Ingestion, Evidence And The Durable Handoff

**Status: IMPLEMENTED AND VERIFIED. NOT ACCEPTED.** ADR-061 makes the objective verification suite
*plus* the independent ADR-026 five-lens review the acceptance mechanism. Only the first half has
run. `completed_blocks` does not gain S-07-010, `review_commit` in `BUILD_STATE` is deliberately
empty, and this record says so at the top rather than in a footnote.

Governing text: `specification/volume-i/WORKFLOW_SPECIFICATIONS.md` § Interim Ingestion Contract
`ingestion-interim-v1` (:460-466) and :452's coverage classification;
`specification/volume-ii/contracts/S-07.json` MTX-008 and MTX-030;
`specification/volume-ii/APPLICATION_LAYER.md` § CAP-008; `schemas/POSTGRESQL_SCHEMA.md` :302, :303,
:304; `specification/volume-ii/BACKGROUND_PROCESSING.md` :140, :200, :378.

```f1-evidence
candidate_range: 780b1a4..8f55c9e
frozen_path_changes: 1
frozen_paths:
  - lib/f1/runtime_grants.rb
suite_examples: 2882
review_rounds: 0
```

## Identity

| | |
| --- | --- |
| Block | S-07-010 |
| Branch | `implementation/s07-010-documents` |
| Base | `780b1a4` (ADR-142, S-07-009 accepted) |
| Candidate | `780b1a4..8f55c9e` |
| Files in range | 30, every one under a declared path; excluded set EMPTY |
| Frozen-path changes | 1 — `lib/f1/runtime_grants.rb`, additive new-table grants under the Foundation Consumption Rule (ADR-029) |
| Independent review | NOT RUN by a reviewer ADR-026 recognises. One adversarial round was conducted in-session by the implementer and is recorded as ADR-144; it is not a substitute |

## What the tranche owns, and what it deliberately does not

`BUILD_PLAN.yml` scopes S-07-010 to "documents + ingestion_jobs + ingestion_attempts; IngestionJob
lifecycle; F-03 source_document / content_absent Evidence (D3 interim, ADR-067); durable handoff",
and it **ENDS BEFORE the OD-027 withheld limb**. MTX-008 names that limb exactly: "The
`unique (parsing_job_id)` constraint that would narrow ParsingJob-to-IndexingJob is WITHHELD under
OD-027 and MUST NOT be added." No `parsing_jobs`, no `indexing_jobs`, no `has_one` and no such
constraint appears anywhere in the range.

`ReplayIngestionJob` is **not** here either, and that is BUILD_PLAN's decision rather than an
omission: S-07-011 owns recovery and replay, the `ingestion.recover` permission, the Support Session
limb and the 24-hour staging bound *at replay*. What this tranche owes that block is the state it can
act on, and it is present: the `dead_letter -> queued` edge with its atomic seven-column capsule and
its exactly-once generation increment (built and proved at `e0d48bb`), and an immutable
`staging_expires_at` the replay path can test. No store method was written for an operation whose
caller does not exist yet — FU-31 is this repository's own record of what that costs.

## The durable handoff is a constraint, not a convention

MTX-008: "the durable handoff record IS the succeeded IngestionJob with its valid `source_document`
Evidence". :464: "No Document may become ingested or enter the parse manifest WITHOUT that valid
Evidence."

`ingestion_jobs_succeeded_carries_evidence` and `ingestion_jobs_evidence_only_on_success` are those
two sentences as CHECKs. A succeeded job with no Evidence is *unrepresentable*, not merely unwritten,
which is what lets S-08 read `state = 'succeeded'` to build :472's parse manifest without
re-validating every row it selects. The mutation `s10-job-guard-disarmed` removes the guard that
carries the surrounding lifecycle and kills eight examples.

## :452's two covered outcomes, each with its artifact

:452 gives an admitted content URL a covered outcome "only when it creates a valid Document, or
returns terminal 404/410 and creates a valid body-free `crawl_observation` with reason
`content_absent`". Both artifacts are now produced in the **same transaction that retires the
frontier entry** — the one that releases :454's depth seal and writes `crawl_terminal_outcomes`.

That is not a convenience. A Document committing while the retirement rolled back would be a
coverage-bearing artifact for an entry nothing classified; a retirement committing while the Document
rolled back would be `document_created / covered` naming a Document that does not exist. `s10-
document-not-created` and `s10-absence-not-recorded` each remove one limb; the first kills 19
examples.

**D3 is resolved inline, and the reading is the narrow one.** ADR-067 left open whether the
`content_absent` observation is produced at fetch-commit or through the ingestion pipeline. The
pipeline reading cannot be built without inventing product state: an IngestionJob is keyed on
`fetched_body_sha256` and a 404 has no body; its Document would have no fetched object, byte size or
content digest; and :464's success path — the only path that produces Evidence — is defined as
creating a `source_document` and moving a Document `discovered -> ingested`. :452 says this outcome
has none of them. Inline needs no inventions; the pipeline reading needs five.

## Body staging is F-02, and that is an interim with its reason stated

:462 requires staged bytes "immutable and inaccessible to product reads"; :464 destroys the "separate
staging reference" at success; :466 destroys them at 24 hours. The canonical home is `stored_objects`
(`schemas/POSTGRESQL_SCHEMA.md` :231) — a shared platform table with `storage_provider CHECK
('aws_s3')` that **has never been built**, that no S-07 tranche owns, and whose construction needs an
external paid provider, which `specification/automation/AUTONOMY_POLICY.md` makes an owner decision.
Building it inside this tranche would repeat precisely what D1 and D2 were escalated for.

F-02 supplies all three ratified properties through a frozen public contract this repository already
uses for the same purpose — S-05 stores its redacted verification payload behind an F-02 reference.
The staged record's AAD purpose is `temporary_processing`, which is the retention class
`SCORE_EVIDENCE_MODEL.md` names for "staging bytes before Evidence creation". The Evidence payload is
a **separate retained record**, which is why :464 calls the destroyed one "the separate staging
reference": destroying the staging copy cannot dangle the Evidence. FU-65 carries the migration and
states plainly what differs from the canonical design — *where* the bytes live and the absence of the
staged/sealed/published state machine, not whether the contract's properties hold.

## Defects found by this tranche's own chain, and repaired

**(a) The Ingestion Job lifecycle guard evaluated the edge set on every update.** `succeeded ->
succeeded` was therefore an illegal transition — and :464's own next sentence, "deletes the separate
staging reference", is an UPDATE of a succeeded row that changes no state. The ratified success path
could not execute. **The repair is not a self-edge**: admitting one in the edge set would let a
writer consume a `state_version` for a transition that did not happen and break another worker's
compare-and-set for no reason. A state-preserving update is admitted, and separately forbidden from
advancing the version. Demonstrated twice by the acceptance chain, on `succeeded` and on `queued`.

**(b) A contended delivery stranded its job for ever.** `Platform::ScheduledActions::Worker`
SETTLES every result that is not a confirmed lease loss, so a delivery that found a live attempt
lease ended its own action. If the incumbent then died, the job sat `running` behind a lease that
would lapse with **nothing pending to notice it** — permanently, because :466's retry is only ever
minted by a settle that never happens and `running_work_sweep_due` has no registered handler. The
path is ordinary rather than exotic: any worker crash whose action is re-dispatched inside the
attempt lease reaches it. A contended delivery now mints its successor at the incumbent's own lease
boundary, read from the committed attempt row so two contended deliveries compute one action
identity. It cannot spin: by that instant the job is either settled — `ingestion_job_not_runnable`,
which mints nothing — or reclaimable. `s10-contended-strands-the-job` removes the successor and
PROOF 184 fails.

**(c) `spec/architecture/repository_truth_spec.rb` hardcoded two S-07-009 artefacts** — the mutation
ledger and the acceptance-review record — inside a block titled "the record of the tranche currently
under review", while every sibling check in it derives its subject from `current_tranche`. That is
the exact defect the same file's :191 already corrected for the completion-report path. It was not
cosmetic: the ledger binds each verdict to the *bytes* of the file it was measured against, so the
first tranche to touch one of those files makes the accepted ledger stale and the gate reports a
defect in a record nobody is reviewing. Both are derived now, both skip when the tranche has no such
record, and `lib/tasks/f1_mutations.rake` takes its set from a closed registry so a second tranche
can regenerate a ledger at all.

## The scheduled action targets the job, and the reason is stronger than ADR-085's

`specification/volume-ii/BACKGROUND_PROCESSING.md` :200 records `ingestion_attempt_due`'s direct
claim owner as "Ingestion Attempt". An attempt row created at *scheduling* time would consume one of
:466's three attempts without ever running, because the attempt number is `COUNT(*)` over
`ingestion_attempts` — and the retry action is minted by the transaction that records the failure, so
the failing execution would be creating its successor's attempt, which is the second producer ADR-085
refused. The job is a genuine claim owner (`queued -> running` under a compare-and-set *is* the
claim) and the durable idempotency authority is unchanged. Unlike `crawl_frontier_entry`,
`ingestion_job` is a member of the entity-type vocabulary `API_CONTRACTS.md` declares closed, so
FU-17's divergence does not extend to this kind.

## Migrations

| | |
| --- | --- |
| `20260806100000_create_documents_and_ingestion` | the three product tables, their guards and the OD-015 vocabulary (accepted at `e0d48bb`) |
| `20260806110000_ingestion_job_capture_contract` | the nine :462 job members, the two durable-handoff CHECKs, the staging biconditional, and the guard repair described above |

## Proofs

| Proof file | Distinct `PROOF n` |
| --- | --- |
| `spec/acceptance/wf005_document_ingestion_spec.rb` | 28 |

`spec/persistence/documents_and_ingestion_schema_spec.rb` carries the schema and guard battery — 31
examples over the Document lifecycle, OD-015's omitted vocabulary, the replay capsule, the durable
handoff CHECKs, the staged-reference lifecycle, post-terminal closure as *behaviour* rather than as a
catalogue entry, and Document version allocation through the production writer. Its examples predate
the `PROOF n` convention in that file and are not numbered; they are counted here rather than
tabulated, so no maintained number can drift from the file.

## Mutation evidence

`specification/automation/S-07-010_MUTATION_LEDGER.json`, regenerated by
`rake f1:mutations:regenerate SET=s07_010` from
`automation/lib/autonomous_build/s07_010_mutation_set.rb`. **28 mutations, 28 killed**, 0 survived, 0
broken. Every row was replayed: the substitution applied, confirmed landed from the file's own bytes
(or from the catalogue, for the three trigger rows), the bound proof run, the failing example
identities captured, the change restored and the restoration verified.

Three rows survived the first regeneration and **each survivor was a real coverage gap, closed by a
new proof rather than by a weaker expectation**:

- `s10-replay-forks-the-job` — nothing exercised :462's "exact fetch replay returns the same job",
  because the frontier compare-and-set makes a second `produce` unreachable on today's chain. PROOF
  168a asks the production object directly, in the state the sentence is about.
- `s10-document-advance-unguarded` — PRULE-009's same-version guard on the Document advance was
  asserted nowhere. A store-level example now requires a stale version to advance nothing.
- `s10-document-closure-removed` — `spec/persistence/crawl_terminal_fact_closure_spec.rb`'s PROOF 156
  derives every Crawl child table and requires the closure *trigger* to exist on each. A mutant that
  leaves the trigger in place with a `WHEN` clause that never holds passes it untouched. The refusal
  is now measured behaviourally, on both `documents` and `ingestion_jobs`.

## Verification

| Gate | Result |
| --- | --- |
| `bundle exec rspec` | `2882 examples, 0 failures` (2584 at this tranche; +29 from the registration-access transport work, then +61 from the WF-003 verification surface, the crawl-detail screen and the two outbound-transport defects, +73 from the WF-006 evaluation input gate and the S-08 parsing pipeline, and +135 from the S-09/S-12 WF-007 check-catalogue slice, all of which followed it) |
| `bundle exec rspec spec/architecture` | 245 examples, 0 failures |
| `bundle exec brakeman -q --no-pager -z` | 0 warnings, 0 errors |
| `bin/packwerk check` | no offenses, no stale violations |
| `bin/rails zeitwerk:check` | clean |
| `bundle exec bundle-audit check --update` | no vulnerabilities |
| `bin/f1db f1:db:verify_runtime` | 15 checks passed, RLS intact |
| `bin/f1db db:schema:dump` + `git diff --exit-code db/structure.sql` | no drift |
| Mutation ledger | 28 definitions, 28 killed, 0 survived, 0 broken |

## Follow-ups opened

| | |
| --- | --- |
| FU-65 | Staged bodies are on F-02 rather than in `stored_objects`; the migration is owed, and what differs is stated |
| FU-66 | :464's `malware_or_active_content_detected` is **not performed** — no scanning provider exists and adding one is an owner decision. The omission is carried in the code where the check would be, not passed silently |
| FU-67 | Accepted WF-005 events omit `prior_aggregate_version` / `committed_aggregate_version`, which `API_CONTRACTS.md` makes base members of every `created` and `state_transition` payload. The S-07-010 events carry them; the earlier ones do not. Same class as FU-33 |

## What is owed before acceptance

The independent ADR-026 five-lens review over `780b1a4..8f55c9e` — contract, security and tenancy,
concurrency and atomicity and idempotency, schema and migration, architecture and scope. This record
is the implementation's own account of itself and an adversarial self-review against the governing
text; it is not a substitute for that review, and ADR-061 says so.
