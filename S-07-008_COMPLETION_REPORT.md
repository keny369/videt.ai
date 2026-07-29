# S-07-008 — Crawl Limits, Soft/Hard Decision Events, The Wall Clock, Ordered Admission

**Acceptance status: ACCEPTED (DECISIONS.md ADR-083, 2026-07-29), under standing delegation
ADR-061 and review discipline ADR-080.**

This record describes HEAD. It does not narrate how HEAD was reached — git holds that, and a
narrative acceptance record accumulates stale counts and superseded mechanisms faster than it can be
corrected. Every claim below is either mechanically checked by
`spec/architecture/repository_truth_spec.rb` or reproducible by the commands in **Verification**.

## Identity

| | |
| --- | --- |
| Block | S-07-008, BUILD_PLAN `Crawl Execution — limits, soft/hard events, wall clock` |
| Range | from `09277e7` (S-07-007 acceptance) to the branch head |
| Authority | standing delegation ADR-061; review discipline ADR-080 |
| Accepted paths | `app/`, `db/`, `schemas/`, `spec/`, `lib/`, `specification/`, `S-07-008_COMPLETION_REPORT.md`, `DECISIONS.md` |
| Excluded | 12 `branding/`, `investor/` and `operations/` files listed in `BUILD_STATE.acceptance_evidence` |

The excluded files are unrelated work swept in by two early commits made with `git add -A`. Owner
ruling: published history is not rewritten for cosmetic cleanliness. The consequence is procedural —
**this tranche is reviewed by PATH over a commit range, never by treating any single commit as a
slice.** The accepted paths and the excluded list partition the range exactly; the repository-truth
spec asserts that partition.

## Delivered behaviour

**Every limit event is a consequence of a durable record.** `Workflows::Wf005::LimitDecisions#observe` inserts
into `crawl_limit_decisions` with `ON CONFLICT DO NOTHING RETURNING` and emits only when that
statement created the row, so `UNIQUE (crawl_id, limit_dimension, threshold_kind)` is what
adjudicates `:442`'s "exactly once per dimension and run" across processes. The event envelope is
built from the returned columns, so a CHECK that rejects a value stops the event with the row.

**Nine of the twelve ratified dimensions are observed**, each on the transaction that caused the
effect it describes.

| Dimension | Observation point |
| --- | --- |
| `accounted_response_body_bytes_per_run` | `Wf005::Admission` |
| `wall_clock_run_duration` | `Wf005::Admission` |
| `discovered_url_queue` | `Wf005::Frontier` |
| `crawl_depth_from_source_root` | `Wf005::Frontier` |
| `response_body_per_url` | `Wf005::FetchContent` |
| `connection_plus_response_time_per_request` | `Wf005::FetchContent` |
| `redirects_per_url` | `Wf005::FetchContent` |
| `sitemap_documents_per_run` | `Wf005::DiscoverSitemaps` |
| `sitemap_index_nesting_depth` | `Wf005::DiscoverSitemaps` |
| `accepted_pages_per_run` | none — counts Documents, which S-07-010 creates |
| `request_rate_per_canonical_host` | none — see *Owner rulings* |
| `concurrent_requests_per_canonical_host` | none — see *Owner rulings* |

Soft and hard observations are independent at every site: a run that crosses a hard bound reached
the soft value on the way, and the decision is once-per-run, so gating soft behind hard loses it
permanently.

**The discovered queue is one population.** Membership is every candidate discovered except those
the queue bound itself refused — `:440` counts a URL "even when it is later rejected for depth". The
bound is enforced at ENTRY, so the population can never exceed it: a joiner at the ceiling either
displaces a member or is refused. Depth then describes what kind of member a candidate is.

**Ordered admission (FU-10).** `Admission` claims the frontier entry and its byte reservation in one
transaction under the frontier's own advisory lock, so admission order equals dequeue order by
construction. It peeks before claiming, because the frontier guard has no `in_progress -> queued`
edge and a stranded claim would pin `sealed_depth` for the run. It applies the admission-safe subset
of `FetchAuthorization` — Organization, Crawl, Project, entitlement reservation — before the peek,
the reservation, the claim and any observation.

**Sustained host-gate contention is not an outcome (FU-9, mitigated).** `:450` conditions
`sitemap_unavailable` on "no candidate succeeds after retries/validation"; a candidate the rate
limiter never released has had neither, so the claim is handed back and the gate returns to
`pending`. **This is not scheduler re-entry** — nothing in production drives crawl execution. The
driver is S-07-012 and FU-9 closes when it lands.

**Run-wide sitemap-document accounting.** `crawl_sitemap_document_charges` is the durable identity
behind `:437`'s "distinct canonical sitemap URLs": `UNIQUE (crawl_id, canonical_url_sha256)`. It is
the sole authority for the bound, which is `COUNT(*) < ceiling` over its rows under the per-Crawl
`crawl_budget_counters` row lock. `crawl_budget_counters.sitemap_documents` is a projection
recomputed from it in the same transaction, never incremented. Charges are taken once per distinct
URL at the moment an attempt begins, so a paced candidate costs nothing and re-entry re-charges
nothing. The stored URL is the NFC form that was hashed, so a row reproduces its own identity.

**Not written here:** `coverage_status` and `completion_reason`. `crawls_terminal_shape` forbids them
while running, and `:456`'s precedence belongs to the terminal checkpoint. S-07-009 derives both by
reading `IdentityAccess::Infrastructure::CrawlLimitDecisionStore#decisions`.

## Schema changes

| Migration | Effect |
| --- | --- |
| `20260727120270_create_crawl_limit_decisions` | the decision record; `UNIQUE (crawl_id, limit_dimension, threshold_kind)`; T-IMM; forced RLS |
| `20260727120280_crawl_limit_decision_reason_null_safe` | the threshold biconditional made NULL-safe with `IS NOT DISTINCT FROM`; a CHECK evaluating to UNKNOWN is satisfied, so the hard limb admitted a NULL reason |
| `20260727120290_create_crawl_sitemap_document_charges` | the sitemap charge ledger; `UNIQUE (crawl_id, canonical_url_sha256)`; T-IMM; forced RLS |

Both new tables are `SELECT, INSERT` only for `f1_runtime` and are catalogued in
`schemas/POSTGRESQL_SCHEMA.md`.

## Owner rulings carried by this tranche

**Events represent exceptional operational conditions, not expected scheduler behaviour** — or the
signal loses diagnostic value. Applied to per-host rate and concurrency, whose soft values are
normal scheduling targets and whose hard limbs `:442` resolves by delaying rather than by stopping
work. `:456`'s list of bounds that leave a candidate unevaluated excludes both. To change this, add
the two dimensions to `Workflows::Wf005::HostGate#claim`, which would need a crawl, a project and a resolution it does
not currently receive.

**Published history is not rewritten** to make a tranche cosmetically clean. See *Identity*.

## Verification

Run from the repository root. Outputs are those observed at this commit.

The commands are `specification/automation/VERIFICATION_MANIFEST.yml`'s, not a hand-picked subset.

| Command | Output |
| --- | --- |
| `bundle exec rspec` | `1882 examples, 0 failures` |
| `bundle exec brakeman -q --no-pager -z` | `No warnings found` |
| `bin/packwerk check` | `No offenses detected` |
| `bundle exec bundle-audit check --update` | `No vulnerabilities found` |
| `bin/rails zeitwerk:check` | `All is good!` |
| `bin/f1db db:schema:dump && git diff --exit-code db/structure.sql` | no drift |
| `bin/f1db f1:db:verify_runtime` | `OK as f1_web — 15 checks passed (RLS intact)` |
| `bundle exec rspec spec/architecture` | `45 examples, 0 failures` |
| `bundle exec rspec spec/automation/{unit,integration,policy,end_to_end}` | `33/0, 20/0, 21/0, 10/0` |
| `git status --porcelain` | NOT empty — see below |

Two manifest checks could not run. `controller_locking` and `controller_crash_recovery` name spec
directories that have never existed in this repository — `git log --all` over both paths is empty —
so under `fail_on_missing_required_check: true` they have never run, for any tranche. Pre-existing,
unrelated to this work, registered as FU-14. They are named here without the path-citation form
deliberately: this record's citations are checked for existence, and these paths do not exist.

`git status --porcelain` is not empty. Nine `branding/` and `operations/` files carry the owner's own
in-flight parallel work. They lie outside the acceptance path partition and were deliberately left
untouched; no commit in this tranche contains them.

`f1:db:verify_runtime` is a fixed 15-check list over `sessions`, `accounts`, `scheduled_actions` and
the transport functions. **It says nothing about this tranche's tables.** Their invariants are
asserted against a live database in `spec/persistence/crawl_limit_decision_invariants_spec.rb`.

Repository-truth facts — the state file's status vocabulary, its commit fields and timestamp, the
acceptance-path partition, cited paths and identifiers, cited migrations, and canonical-catalogue
completeness — are asserted by `spec/architecture/repository_truth_spec.rb` on every run.

## Proof standard

A green suite proves nothing about a control the suite never reaches. Every control below was
verified by REVERTING it and requiring a named test to fail; each was a survivor before the test
named beside it existed.

| Control | Mutation it now fails under | Test |
| --- | --- | --- |
| run-wide sitemap-document ceiling | `ceiling: documents_hard` → `10_000` | holds the RUN-WIDE document bound across hosts |
| charge + projection atomicity | the two statements split across transactions | rolls the charge and its projection back together |
| charge + decision atomicity | `observe_documents` moved to its own transaction | writes the limit decision on the SAME transaction |
| missing-counter-row guard | `raise` → `return :exhausted` | refuses to charge without a budget counter row |
| derived projection | `COUNT(*)` → `sitemap_documents + 1` | ANCHORS the projection to the ledger |
| byte-budget predicate | `<= $4` → `<= $4 + 1` | grants exactly the ceiling and refuses one byte more |
| ledger and decision RLS | `USING`/`WITH CHECK` → `true` | BLOCKS a cross-tenant read / write as the runtime role |

The bound is only reachable across HOSTS. Within one pass `SitemapCandidates.retain` already caps
the attempted set at `documents_hard`, and `crawl_host_gate_robots_decision_frozen` means a gate can
never offer a second, different declared set — so the ceiling argument was unreachable by every
single-host fixture in the suite. `:437`'s unit is the RUN, and a Crawl covers every active Source in
its Project.

Two behaviours are deliberately asserted through a database guard rather than a return value. A
counter ahead of its ledger is rejected by `crawl_budget_counters_not_monotonic` when the projection
recomputes, because the projection is anchored to the ledger rather than free-running; an incremented
counter would carry the disagreement forward silently as spent budget nobody charged for.

## Ownership and follow-ups

| Id | Status | Owner |
| --- | --- | --- |
| FU-9 | mitigated | S-07-012 (the run driver) |
| FU-10 | delivered and accepted | this tranche |
| FU-11 | open, **blocking S-07-009** | `crawls_terminal_shape` lacks a terminal-completeness conjunct |
| FU-12 | open backlog | recorded, not scheduled |
| FU-13 | open backlog | two pre-existing catalogue gaps |
| FU-14 | open backlog | `VERIFICATION_MANIFEST.yml` names two check paths that have never existed |

## Unresolved observations

- **No production caller exists** for `Admission`, `FetchContent`, `DiscoverSitemaps` or
  `EnsureRobots`. The only registered entry point is `crawl_dispatch -> StartCrawl`, which seeds the
  root frontier and schedules nothing further. Every observation point above is exercised by
  acceptance specs driving these services directly. S-07-012 owns the driver.
- **`Admission`'s byte reservation has no owner or reclaimer**, and `FetchContent` reserves again for
  itself. S-07-012 must reconcile them; calling both on one entry double-reserves.
- **`Admission`'s Project-state limb is unreachable at HEAD** — `f1_projects_lifecycle_guard` admits
  only `draft -> active`, so a Project that has started a Crawl cannot become inactive. The limb is
  defence in depth; its spec asserts the unreachability and will fail when the Project lifecycle
  gains its remaining edges, which is the signal to write the real denial test.
- **`sitemap_xml_limit` produces no decision row** — the ratified `limit_dimension` enum has no
  member for an XML structural limit. It still forces `limit_reached` through the sitemap outcome.
- **`BUILD_PLAN.yml` does not parse as YAML** (pre-existing). S-07-009's dependency on S-07-012 is
  encoded there; the guarantee is only as strong as the consumer that reads it. FU-12(b).
