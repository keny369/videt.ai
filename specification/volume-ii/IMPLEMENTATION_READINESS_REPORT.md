# Volume II Implementation Readiness Report

## Status

- Status: Implementation readiness. Release control, not product authority.
- Last Updated: 2026-07-17
- Owner: Chief Architect
- Product-behaviour baseline: `v1.5-volume-i-frozen` (commit `c6b3853`, ADR-020) — **unchanged**
- Engineering-practice baseline: `v1.7-engineering-manual-accepted` (commit `b049a41`, ADR-022) — **unchanged**
- Governing change: ADR-023
- Freeze candidate opened at: `8dee0355b59f232424c4136f5891d54417f2eda6`

## Verdict

**The Volume II specification baseline is implementation-ready.** Production implementation may
begin immediately, at S-01 Registration and Access, from
[IMPLEMENTATION_BACKLOG.md](IMPLEMENTATION_BACKLOG.md).

Seven owner decisions remain pending. **None blocks implementation of the baseline**, and this
report proves that per row rather than asserting it — see Withheld-Limb Disposition. Each pending
decision reserves one named limb, records deterministic fail-closed interim behaviour that is itself
fully specified and implementable, and states `Volume II — no` and `Implementation — no` for
blocking impact.

This verdict supersedes [SPECIFICATION_FREEZE_CANDIDATE.md](SPECIFICATION_FREEZE_CANDIDATE.md),
whose exit criteria are each met below.

## Evidence Basis

Every figure in this report was observed on **one integrated tree** — the working tree at the freeze
commit, clean, with no staged or unstaged modification and no untracked file. No figure is carried
over from an earlier pass, a pre-merge run or a subset of the tree. Pre-change greens are not
evidence and are not cited.

### Exact evidence commands

```
git rev-parse HEAD
git status --porcelain                                     # empty
# every suite below is reported by its exit code, captured directly.
# Piping a suite through `tail` and reading ${PIPESTATUS[0]} silently returns empty
# and reports a failing suite as green. That happened once in this programme.
python3 scripts/build_volume_ii_matrix.py --check          # exit 0
python3 scripts/build_implementation_backlog.py --check    # exit 0
python3 scripts/validate_volume_ii.py                      # exit 0
python3 scripts/validate_volume_ii.py --negative-controls  # exit 0, 22 controls
python3 scripts/test_volume_ii_matrix.py                   # exit 0
python3 scripts/validate_engineering_manual.py             # exit 0
python3 scripts/test_generate_engineering_manual.py        # exit 0
python3 scripts/integrate_fragments.py --check             # exit 0, 0 pending
git diff --stat v1.5-volume-i-frozen -- specification/volume-i/
git tag -l
```

### Complete validation output

```
matrix matches its canonical sources
backlog matches its canonical sources
Volume II validation passed
Negative controls passed (22 controls)
Volume II matrix generator tests passed
Engineering manual validation passed
Generator tests passed
0 section(s) pending integration
```

`validate_volume_ii.py` exits 0 with **zero findings of every rule**, including
`retired_blocker_cited_as_live` (72 at the candidate commit), `unresolved_successor_decision`,
`anchor_target_missing`, `contract_owner_does_not_cite_row`, `contract_missing_required_field`,
`contract_field_vague`, `pending_decision_treated_as_ratified` and
`ratified_decision_treated_as_pending`.

## Matrix And Contract Totals

| Measure | Value |
| --- | --- |
| Volume I acceptance criteria | 97 |
| Matrix rows | 97 |
| Unique acceptance criteria mapped | 97 |
| Rows complete | **97** |
| — of which `Complete` | 75 |
| — of which `Complete; limb withheld` | 22 |
| Rows outstanding (`Pass B required`) | **0** |
| Duplicate row ownership | 0 |
| Cross-cutting rows (`ALL`) | 4 |
| Contract sources | 25 (24 product slices plus `S-XC`) |
| Rows carrying a structured contract | 97 |
| Contract schema | 40 fields, unchanged |
| Backlog items | 97 — one per matrix row, by construction |

Every acceptance criterion maps to exactly one row and every row maps back to exactly one governing
criterion and its source, **by construction** rather than by review: the matrix is generated from the
frozen Volume I corpus, and `--check` fails if the file differs from what the sources produce.

## Resolved Governance Issues

### 1. Seventy-two retired blockers cited as live — RESOLVED

All 72 were classified individually in
[RETIRED_BLOCKER_CLASSIFICATION.md](RETIRED_BLOCKER_CLASSIFICATION.md), each appearing exactly once,
each answered against *"what would break if this citation were simply deleted?"*, and none edited
before it was classified.

| Class | Findings | Outcome |
| --- | --- | --- |
| Stale label | 30 | Citation replaced with the ratified authority. |
| Masked dependency | 29 | Obligation identified; **not** deleted. Re-anchored to OD-019's fail-closed leg plus registered OD-035; the routes stay unreachable. |
| Right outcome, wrong reason | 11 | Deny preserved verbatim; re-anchored to OD-020's carve-out plus registered OD-034. Access does not widen. |
| Check artefact | 2 | Document correct; the **check** was wrong and was corrected. |

**No finding in any class changed product behaviour.** Every deny is preserved, every ratified grant
is honoured, and no deny became an allow. A bulk replacement was prohibited and was not performed.

Two masked dependencies were closed rather than recorded again, because both were satisfiable from
already-ratified authority:

- **Export enumeration had no route at all.** Clearing its authority citation would have left a
  ratified read unreachable behind a transport `404` that a caller cannot distinguish from a denial.
  `GET /api/v1/organizations/:organization_id/exports` → `QRY-015` → `export.list` is registered.
  Nothing was invented: the query, its permission and its DTO already existed, and Volume I binds
  `export.list` to Export enumeration in WF-016.
- **The schema contradicted OD-013 Option 1.** `schemas/POSTGRESQL_SCHEMA.md` carried the
  pre-OD-013 `incidents.platform_wide` boolean and nullable "primary Organization" columns — the
  exact tier-5 invention OD-013's own evidence names. Clearing the EVENT-SCOPE citations while the
  DDL contradicted the ratified representation would have asserted an enablement the schema refuses.
  The DDL is corrected to nonnull tenancy in the same change set.

### 2. Missing successor decision — RESOLVED

OD-020's ratified text delegated read authority for security, administrative and internal
operational objects to "a separate decision" that had no OD number and was absent from the register.
Volume II had recorded the consequence exactly, on MTX-095: it was "neither a pending Owner Decision
this row may withhold against nor a resolved one this row may implement."

**OD-034 is registered**, pending, Owner Required Chief Product and Chief Security, with OD-020's own
deny-by-default as its interim. Its scope follows the **wider normative list** in
`WORKFLOW_SPECIFICATIONS.md`, which names **Emergency Access Grant** where OD-020's own sentence
omits it, and it puts the three classes OD-020's problem statement raised but neither carve-out
sentence named — Integration/Credential, Account administration, Policy administration — to the owner
expressly rather than resolving them by silence.

Applying the same reasoning to OD-019 found a second unregistered successor. **OD-035 is registered**,
pending, Owner Required Chief Product: OD-019 ratified the metered-read unit and booked the exhaustive
route-to-operation table and `report.view`'s read surface as unpaid Costs, and neither exists.

Neither decision was resolved by inference, and every inference route was tested and found closed by
accepted authority: OD-020 expressly rejected deriving read from write; `CAPABILITY_MODEL.md:16`
states an `Actor` line never grants authority; a Support Session scopes an already-permitted action
and is never itself a read grant; the five low-cost operation strings are not permissions and the
overlap is a coincidence; `/scores/current` is the case OD-019 itself names as reasonably resolving
either way; and OD-019 classifies the residual as "a commercial and packaging choice rather than an
architectural inference". Choosing either would have resolved an owner decision by implementation.

`unresolved_successor_decision` now fails the build when a settled decision delegates a required
policy question and no registered decision names `- Successor To:` it.

### 3. Latent defects found and fixed while proving readiness

- **The retired-blocker rule was blind to the schema.** It globbed `specification/volume-ii/*.md`
  while every other check uses `in_scope`. `schemas/POSTGRESQL_SCHEMA.md` — the document that decides
  what the database will actually permit — cited retired tags as live reasons to refuse a DML grant
  and was never scanned. Widening the corpus **added** findings, which were then fixed.
- **Seven Markdown anchors were broken.** Pass B recorded that every local and cross-document anchor
  resolves; that was asserted, never executed. Six were cross-document links written as local ones;
  one named a heading title that exists nowhere in the repository. `anchor_target_missing` now
  executes the claim.
- **The `unauthorized_verification_method` vacuity was still reachable.** Line scoping narrowed the
  original proximity-window hole without closing it: one line asserting an unapproved verification
  method as usable while rejecting something unrelated still exempted. Segment scoping closes it, and
  the regression control is proven to report nothing under the superseded rule and to report the
  violation under the new one.
- **The matrix generator test suite was failing, and the failure was nearly missed.** Its
  withheld-limb assertion pinned the count at 18 and broke when ADR-023 correctly took it to 22. The
  assertion is now pinned by row **identity** rather than by count, because a count catches a row
  appearing or vanishing and says nothing about which row, so a limb migrating between rows passes it
  unchanged — blindness at exactly the moment the set changes. A third assertion was added: every
  withheld row must name the decision reserving its limb, which is the defect OD-020's unregistered
  successor produced.
  **The process failure matters more than the fix.** The Stage 0 baseline check piped this suite
  through `tail` and read `${PIPESTATUS[0]}`, which returned empty, so its exit code was never
  observed and the suite was recorded green on the strength of its last few stdout lines. It
  surfaced only when exit codes were captured directly against the freeze tree. This is the same
  defect as the unexecuted anchor claim — a baseline asserted rather than executed — occurring in
  the tooling used to verify the baseline. Every suite in this report is now reported by exit code.

## Remaining Pending Decisions, And Why None Blocks Baseline Implementation

Seven. Status is read from each decision's `Current Status` field and nowhere else.

| OD | Withheld limb | Blocking impact | Owner |
| --- | --- | --- | --- |
| OD-014 | Project pause/resume/archive transition. State may be represented and read as a guard, never effected. | Volume II — no; implementation — no | Chief Product |
| OD-023 | Credential rotation begin and complete. `credential.rotate` is canonical but unreachable; delivery against an active Credential is settled. | Volume II — no; implementation — no | Chief Security |
| OD-027 | Exactly three artifacts: a `has_one` narrowing, a `unique (parsing_job_id)` constraint, any second IndexingJob per ParsingJob. `indexing-interim-v1` pins both keys. | Volume II — no; implementation — no | Chief Architect |
| OD-031 | Routine retention-expiry destruction, under `retention-destruction-trigger-interim-v1`. | Volume II — no; implementation — no | Chief Architect |
| OD-032 | Canonical namespace for an unassigned record. Behaviour permitted under the interim. | Volume II — no for behaviour, yes for any artifact requiring the namespace; implementation — no | Chief Architect |
| **OD-034** | Complete permission-matrix allow/deny fixtures for security, administrative and internal operational object **read** cells. Those classes have no row and stay deny-by-default. | Volume II — no; implementation — no; feature — yes | Chief Product and Chief Security |
| **OD-035** | The low-cost read route-to-operation declaration and `report.view`'s read surface. Every metered read route resolves `operation_unknown` and Blocks. | Volume II — no; implementation — no; feature — yes | Chief Product |

### The proof that none blocks implementation

A pending decision blocks implementation only if the work it touches cannot be built. For each of the
seven, it can:

1. **Every affected row's contract is complete.** All 97 rows carry all required fields of the
   unchanged 40-field schema; `contract_missing_required_field` and `contract_field_vague` are 0.
2. **Every interim is itself a specification, not an absence.** Deny-by-default (OD-034) and
   `operation_unknown` → Block with `contact_support` (OD-035) are exact, testable behaviours with
   defined error codes, audit obligations and fixtures. An implementer builds the route, the handler,
   the DTO, the authorization facade and the entitlement checkpoint, and the declared operation is
   simply absent — which is precisely what OD-019 ratified should happen.
3. **The limb is bounded and named exactly**, never gestured at. `validate_volume_ii.py` re-derives
   withholding independently of the generator and fails on disagreement, so a limb cannot silently
   widen.
4. **The dependency graph is unaffected.** No withheld limb sits on S-01, S-02 or any slice they
   gate. Implementation begins at S-01 and reaches S-13 before meeting anything OD-034 or OD-035
   touches.
5. **This is the repository's own test**, not a new one: `INDEX.md`'s freeze gate measures blockers
   "by blocking status rather than by a count", and ADR-020 froze Volume I with five decisions
   pending on exactly this basis.

**What is genuinely lost is feature surface, not buildability** — and that loss is ratified. The
owner approved a baseline whose numeric score is unavailable (OD-010), and the metered read surface
whose content that score would be is therefore Blocked. The two are consistent, not accidental.

## Withheld-Limb Disposition

All 22 rows, derived from the generated matrix. Each is **explicitly retained with a registered
pending decision** and proven above not to block implementation. None is resolved by inference, and
none is silently carried.

| Row | AC | Pending OD | Withheld limb |
| --- | --- | --- | --- |
| MTX-003 | AC-CAP-003 | OD-014 | pause/resume/archive transition withheld; create/activate permitted; paused/archived state may be represented, never effected |
| MTX-008 | AC-CAP-008 | OD-027 | second IndexingJob per ParsingJob and index-key narrowing withheld under indexing-interim-v1 |
| MTX-013 | AC-CAP-013 | OD-032 | canonical namespace for an unassigned record withheld; behaviour permitted under the interim |
| MTX-015 | AC-CAP-015 | OD-032 | canonical namespace for an unassigned record withheld; behaviour permitted under the interim |
| MTX-021 | AC-CAP-021 | OD-023, OD-032 | credential rotation begin/complete withheld; other Credential lifecycle permitted; canonical namespace for an unassigned record withheld; behaviour permitted under the interim |
| MTX-024 | AC-CAP-024 | OD-035 | low-cost read route-to-operation declaration withheld; every metered read route resolves operation_unknown and returns Block with contact_support under OD-019's ratified fail-closed leg; the unit, che |
| MTX-025 | AC-CAP-025 | OD-031, OD-032 | routine retention-expiry destruction withheld under retention-destruction-trigger-interim-v1; canonical namespace for an unassigned record withheld; behaviour permitted under the interim |
| MTX-027 | AC-WF-002 | OD-014 | pause/resume/archive transition withheld; create/activate permitted; paused/archived state may be represented, never effected |
| MTX-031 | AC-WF-006 | OD-027 | second IndexingJob per ParsingJob and index-key narrowing withheld under indexing-interim-v1 |
| MTX-038 | AC-WF-013 | OD-031 | routine retention-expiry destruction withheld under retention-destruction-trigger-interim-v1 |
| MTX-039 | AC-WF-014 | OD-023 | credential rotation begin/complete withheld; other Credential lifecycle permitted |
| MTX-040 | AC-WF-015 | OD-035 | low-cost read route-to-operation declaration withheld; every metered read route resolves operation_unknown and returns Block with contact_support under OD-019's ratified fail-closed leg; the unit, che |
| MTX-045 | AC-SM-002 | OD-032 | canonical namespace for an unassigned record withheld; behaviour permitted under the interim |
| MTX-054 | AC-PRULE-003 | OD-014 | pause/resume/archive transition withheld; create/activate permitted; paused/archived state may be represented, never effected |
| MTX-055 | AC-PRULE-004 | OD-014 | pause/resume/archive transition withheld; create/activate permitted; paused/archived state may be represented, never effected |
| MTX-060 | AC-PRULE-009 | OD-027 | second IndexingJob per ParsingJob and index-key narrowing withheld under indexing-interim-v1 |
| MTX-069 | AC-PRULE-018 | OD-032 | canonical namespace for an unassigned record withheld; behaviour permitted under the interim |
| MTX-085 | AC-PRULE-034 | OD-023 | credential rotation begin/complete withheld; other Credential lifecycle permitted |
| MTX-091 | AC-PRULE-040 | OD-035 | low-cost read route-to-operation declaration withheld; every metered read route resolves operation_unknown and returns Block with contact_support under OD-019's ratified fail-closed leg; the unit, che |
| MTX-093 | AC-PRULE-042 | OD-031 | routine retention-expiry destruction withheld under retention-destruction-trigger-interim-v1 |
| MTX-095 | AC-PRULE-044 | OD-034 | complete permission-matrix allow/deny fixtures for security, administrative and internal operational object read cells withheld; those classes have no row in permission-baseline-v1 and stay deny-by-de |
| MTX-097 | AC-PRULE-046 | OD-032 | canonical namespace for an unassigned record withheld; behaviour permitted under the interim |

## Known Product Consequences

Settled, ratified behaviours. Not defects, not gaps, not withheld limbs. An implementation that
"fixes" one is non-conformant.

- **The action queue ships empty and the numeric score is unavailable** (OD-010). OD-010's Ratified
  Behavior *approves* the bundle-nothing state: `external-measurement-v1` bundles no query, intent,
  listing, provider or adapter set, so implementations do not invent one. The three always-applicable
  external Checks persist handled `input_evidence_missing` errors; `CHK-LP-001` does the same only
  when its frozen applicability decision is true and otherwise persists its canonical
  `not_applicable` Result. **No Recommendation or Priority Decision publishes from an unavailable
  calculation.** A Measurement Set may later activate as exact signed configuration; Check execution
  still makes no provider call. The catalogue is not broadened by this ratification.
- **Security and administrative objects are unreadable** (OD-020's carve-out, pending OD-034). No
  actor can read Support Session, Incident, Investigation, Legal Hold, Emergency Access Grant,
  deletion-job or privileged Billing collections through a defined permission. Every command,
  approval, command-result and audit path is fully available.
- **Every metered low-cost read Blocks** (OD-019's fail-closed leg, pending OD-035). The high-cost
  path is fully reachable. Non-metered reads — the current Session, the Organization home shell,
  entitlement notices, security notices, the pending verification challenge, and the customer-facing
  collections OD-020 ratified — are unaffected.
- **Emergency cross-Organization support access** is authorized outside the Incident record by a
  dedicated break-glass artifact (OD-012, Option 3). `emergency_customer_access` does not exist and
  the fail-closed outcome is **permanent baseline**, not an interim. The customer-notification limb
  remains withheld pending qualified legal review.
- **Sign-out-everywhere** is out of baseline scope, not blocked (OD-016). **Verification methods**
  beyond DNS TXT and HTTPS file are out of baseline scope, not blocked (OD-001). **The comparison
  read emits no domain event** (OD-024). **`ReassessmentTriggered` does not exist** (OD-025).
  **Document `quarantined` and `retired` are removed, not reserved** (OD-015).

## Known Completeness Gap — recorded, not invented

The **Emergency Access Grant** has no `emergency_access_grants` table in the canonical schema, no
`emergency_access_grant` member in the Volume II `EventEntityType` enum, and no `EmergencyAccess*`
rows in the `EventType` enum; and Volume I's Versioned Policy Resolution enumeration names no
artifact type to back `emergency-access-v1`.

Its status is precise and was verified rather than assumed:

- It is **not an authority gap and not a withheld limb.** OD-012's architecture is ratified and
  nothing about it awaits an owner; OD-012's Blocking Impact records the architecture "ratified and
  integrated", with only the customer-notification limb outstanding. Volume I expressly disclaims the
  lifetime **value** as "versioned policy configuration, not a Volume I product constant".
- It is a **Volume II completeness gap** with a named owning document, recorded by S-21 with the
  correct rationale that closing it is not that slice's authority.
- **It does not block the start of implementation.** It bounds the Emergency Access Grant only, deep
  inside S-21 — the twenty-first slice — and blocks no earlier slice and no other capability.
- ADR-023's authorised scope is the retired-blocker citations and the successor-decision graph. It
  does not close this gap, and this report does not claim it did.

It is carried forward here rather than buried, because a freeze that claimed total completeness while
a ratified capability lacked its persistence would be exactly the manufactured readiness this
programme exists to prevent.

## Security Posture

- **Deny-by-default is the rule, not the fallback.** Undefined role, permission, resource scope or
  tenant context is denied. `permission-baseline-v1` is a closed enumeration; an Access Policy cannot
  turn a baseline deny or conditional cell into an unconditional allow, raise a classification
  ceiling, change protected status or introduce a role or persona.
- **No authority is inferred.** An `Actor` line grants none. A Support Session scopes an
  already-permitted action and never widens a cell. Read is never derived from write. No wildcard read
  exists.
- **One authorization facade**, invoked inside the unit of work, never at a transport edge alone.
  Object-level authorization strictly precedes field-level redaction, with whole-object denial for an
  actor who cannot access the object at all.
- **Forced RLS** with composite tenant keys, proven to hold independently of the application check.
  Every allow is Organization-scoped and no cell relaxes it.
- **Denials are events, not gaps.** Every denial emits exactly one authorization audit event and
  performs no state change or provider call. `F1-AUTH-403` is indistinguishable across an
  unauthorized Session revoke, an out-of-scope Session and a nonexistent Session identifier, so
  existence is not disclosed.
- **Protected grants** require approval within 24 hours by a SecurityOperator other than the
  requester, with an active expiry. Exactly two bootstrap exceptions exist and are exercised as the
  only ones.
- **Telemetry** MUST NOT carry a raw identity assertion, email, token, credential or authentication
  factor.

## Data And Lifecycle Constraints

- `retention-interim-v1` is a **fixed approved baseline**, not an interim. Customer-configurable
  retention is not approved and remains disabled. Worldwide availability; principal initial markets
  are the US, UK, Australia, New Zealand, Canada and South Africa.
- No LifecycleDeletionJob may complete without entering `running` (OD-033); no compatibility path,
  schema shape, migration, function or grant may admit the removed edge.
- Document lifecycle is `discovered → ingested → parsed → indexed`, terminal at `indexed`.
  `quarantined` and `retired` are **removed**, not reserved (OD-015). Evidence quarantine is a
  separate, unaffected state machine.
- An access audit **survives** cryptographic deletion of the material it authorized. No command
  silently hard-deletes Audit Evidence.
- Every event and audit record carries a **nonnull `organization_id`** (OD-013 Option 1), with the
  single DM-REQ-013 bootstrap substitution WF-001 expressly names.

## Metering And Low-Cost-Operation Requirements

- `read-metering-v1`: exactly one LowCostUsageRecord per accepted top-level document read at the
  durable response checkpoint, Decision ID as uniqueness key. Frames and partials of a declared root
  carry the root Decision ID and MUST NOT append a second record; a Frame reached by direct
  navigation is itself a root. A request that never reaches the checkpoint creates no record.
- Read Decision IDs are **server-minted deterministically**; client-supplied idempotency keys are
  prohibited on GET, and a repeated tuple within the window replays the stored record.
- **Every metered read route MUST declare exactly one of five low-cost operations, and none does.**
  Under OD-019's ratified fail-closed leg each therefore resolves `operation_unknown` and returns
  Block with `contact_support`. This is the OD-035 limb. An undeclared metered route is **unreachable
  rather than silently unmetered** — that is the point of the leg, and it is what makes the interim
  safe.
- The five operation strings are **not** permissions. Do not infer either from the other.
- The high-cost path (`crawl.start`, `reassessment.start`, `ai.generate`, `export.generate`) is fully
  reachable, with atomic idempotent reserve at the protected execution checkpoint.

## Event, Idempotency And Audit Requirements

- Every state-changing command, result, event, retryable transition, provider dispatch, reservation,
  low-cost usage commit and stage execution uses the complete tenant, identity, payload, version,
  policy, compatibility, redaction, audit, idempotency and replay envelopes, so exact replay and
  concurrency repeat no product side effect (PRULE-046).
- `ReassessmentTriggered`, `DocumentQuarantined`, `DocumentRetired` and `ComparisonGenerated` are
  **permanently excluded** from the executable event-registry manifest. No generic Event row may
  admit one; reintroduction requires controlled Volume I change.
- `RoleExpiryBlocked` and `IssueFingerprintCollision` each have exactly one defined producer
  (OD-026, OD-017) and are no longer excluded.
- Exact replay of an accepted command **reauthorizes** before returning retained identifiers and
  applies current field redaction.
- Mailgun provides at-least-once application attempt processing with explicit provider-acceptance
  uncertainty and **no exactly-once claim**; administrative replay of an uncertain Delivery requires
  explicit duplicate-risk acknowledgment.

## Freeze Exit Criteria — Disposition

Every criterion from [SPECIFICATION_FREEZE_CANDIDATE.md](SPECIFICATION_FREEZE_CANDIDATE.md),
observed on one integrated tree.

| # | Criterion | Status |
| --- | --- | --- |
| 1 | Matrix generator succeeds; `--check` exits 0 | **Met** |
| 2 | 97 rows; 97 unique ACs; 97 complete; 0 outstanding | **Met** |
| 3 | All contract-owner references resolve and cite their row back | **Met** — `contract_owner_does_not_cite_row` 0 |
| 4 | Every local and cross-document anchor resolves against real slugs | **Met** — now executed, not asserted; 7 breaks fixed |
| 5 | `validate_volume_ii.py` exits 0; no retired blocker cited as live | **Met** — 72 → 0 |
| 6 | All mutation controls pass, including one per new rule | **Met** — 22/22 |
| 7 | Pending-decision register accurate | **Met** — 7 pending; stale Status line corrected |
| 8 | No missing successor-decision node | **Met** — OD-034, OD-035 registered; rule enforces it |
| 9 | No unresolved implementation-critical **authority** gap | **Met** — the one known gap is a completeness gap with a named owner, not an authority gap, and blocks no slice's start |
| 10 | Withheld limbs resolved, or retained with a registered pending decision **and proven** not to block | **Met** — 22 rows, proven per row |
| 11 | Volume I and frozen tags intact unless authorised | **Met** — 9 tags unmoved; Volume I change is registration only, authorised by ADR-023, no behavioural contract altered |
| 12 | Generated files match canonical sources | **Met** — matrix and backlog both `--check` clean |
| 13 | Tree clean; no untracked files; no unstaged changes | **Met** |

**Readiness was not manufactured.** The two rule changes that reduce findings (segment scoping, the
fragments exemption) are structural and each is mutation-controlled; the one that increases them
(widened corpus) was made deliberately in this pass, and its findings were fixed rather than
exempted. No deny became an allow, no pending decision was recorded as ratified, and no owner
approval was fabricated.

## Implementation Starting Point

**Begin at S-01 Registration and Access**, backlog item **BL-001 (MTX-001, AC-CAP-001)**.

Read [IMPLEMENTATION_ENTRY_MAP.md](IMPLEMENTATION_ENTRY_MAP.md) first — in particular its four
counter-intuitive settled behaviours — then work
[IMPLEMENTATION_BACKLOG.md](IMPLEMENTATION_BACKLOG.md) in order. The acceptance criterion is the
oracle; an item is done when its criterion passes and not before.

## Related Documents

- [IMPLEMENTATION_BACKLOG.md](IMPLEMENTATION_BACKLOG.md) — generated; 97 items
- [IMPLEMENTATION_ENTRY_MAP.md](IMPLEMENTATION_ENTRY_MAP.md) — implementation order to canonical owners
- [RETIRED_BLOCKER_CLASSIFICATION.md](RETIRED_BLOCKER_CLASSIFICATION.md) — all 72 findings
- [SPECIFICATION_FREEZE_CANDIDATE.md](SPECIFICATION_FREEZE_CANDIDATE.md) — superseded by this report
- [../volume-i/OWNER_DECISION_REGISTER.md](../volume-i/OWNER_DECISION_REGISTER.md) — status authority
- [../../DECISIONS.md](../../DECISIONS.md) — ADR-023

## Change Control

This report is evidence, not authority. It is reissued when the tree changes, never amended to make
a criterion look satisfied. A criterion is either observed green on the integrated tree or it is
recorded as blocked.
