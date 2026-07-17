# Volume II Specification Freeze Candidate

## Status

- Status: Freeze candidate. Release control, not product authority. Not frozen.
- Last Updated: 2026-07-17
- Owner: Chief Architect
- Source commit at candidate creation: `8dee0355b59f232424c4136f5891d54417f2eda6`
- Source branch: `specification/volume-ii-pass-b`
- Product-behaviour baseline: `v1.5-volume-i-frozen` (commit `c6b3853`, ADR-020)
- Engineering-practice baseline: `v1.7-engineering-manual-accepted` (commit `b049a41`, ADR-022)

## Authority

This document is a **release-control artefact**. It carries no product authority of its own
and creates no product behaviour. Under PM-REQ-003 authority is resolved by scope before
rank: Volume I owns product behaviour, the Engineering Manual owns engineering practice, and
this document owns nothing but the record of whether Volume II is fit to freeze.

Where this document and any canonical owner disagree, the canonical owner prevails and this
document is defective. It MUST NOT be cited to settle a product question, and it MUST NOT be
used to invent a product decision.

## Purpose

State exactly what the Volume II baseline is at the candidate commit, what it ships, what it
withholds, what blocks its freeze, and the exit criteria that must be met before an
implementation-ready tag may be created.

The failure this guards against is a freeze that reads as complete because its wording was
cleaned up rather than because its behaviour was settled. **No unresolved behaviour may be
concealed by wording-only cleanup.** A citation removed without resolving what it was
withholding is a product decision made silently, which is the exact defect
`retired_blocker_cited_as_live` exists to surface.

## Evidence Basis

Every figure below was observed on the same integrated repository state — the working tree at
commit `8dee035`, clean, with no staged or unstaged modification and no untracked file. No
figure is carried over from an earlier pass, a pre-merge run, or a subset of the tree.

Commands run to establish this baseline:

```
git rev-parse HEAD                                   # 8dee0355b59f232424c4136f5891d54417f2eda6
git status --porcelain                               # empty
python3 scripts/build_volume_ii_matrix.py --check    # exit 0
python3 scripts/validate_volume_ii.py                # exit 1, 72 findings
python3 scripts/validate_volume_ii.py --negative-controls  # exit 0, 18 controls
python3 scripts/test_volume_ii_matrix.py             # exit 0
python3 scripts/validate_engineering_manual.py       # exit 0
python3 scripts/test_generate_engineering_manual.py  # exit 0
```

## Matrix Totals At Candidate Creation

| Measure | Value |
| --- | --- |
| Volume I acceptance criteria | 97 |
| Matrix rows | 97 |
| Unique acceptance criteria mapped | 97 |
| Rows `Complete` | 79 |
| Rows `Complete; limb withheld` | 18 |
| Rows complete in total | 97 |
| Rows outstanding (`Pass B required`) | 0 |
| Cross-cutting rows (`ALL`) | 4 |
| Contract sources integrated | 25 (24 product slices plus `S-XC` cross-cutting) |
| Rows carrying a structured contract | 97 |

`build_volume_ii_matrix.py --check` exits 0: the generated matrix matches its canonical
sources byte for byte.

### `Complete` versus `Complete; limb withheld`

These are **not** two grades of the same thing and MUST NOT be conflated.

- **`Complete`** — the row's contract is supplied in full and nothing about the row is
  reserved by a pending owner decision. It is implementable end to end.
- **`Complete; limb withheld`** — the row's contract is supplied in full **and is equally
  implementable**, but one named limb of its behaviour is reserved by a pending owner
  decision and MUST NOT be effected. The limb is named exactly, never gestured at.

A withheld limb is a limb, never a capability. The surrounding behaviour is permitted,
specified and testable. Volume I permits the withheld state to be *represented* and *read as
a guard*; it never permits it to be *effected*. A row marked `Complete; limb withheld` does
not block implementation of that row — it bounds it.

The generator derives withholding mechanically from each decision's `Current Status` field in
`OWNER_DECISION_REGISTER.md`, never from prose. `validate_volume_ii.py` re-derives the same
classification independently and fails on disagreement
(`pending_decision_treated_as_ratified`, `ratified_decision_treated_as_pending`), so a defect
in either one is caught by the other rather than by both being wrong together.

## Validator State At Candidate Creation

`python3 scripts/validate_volume_ii.py` exits 1 with **72 findings, all of one code**:

| Code | Count |
| --- | --- |
| `retired_blocker_cited_as_live` | 72 |
| *(every other rule)* | 0 |

Notably `contract_owner_does_not_cite_row` is **0**: every contract names a canonical owner
document that exists and cites the row back.

The 72 findings distribute across five documents and eight retired blocker tags:

| Document | Findings | | Retired tag cited | Findings |
| --- | --- | --- | --- | --- |
| `APPLICATION_LAYER.md` | 37 | | `UPSTREAM-V1-LOW-COST-METERING-005` | 30 |
| `API_CONTRACTS.md` | 27 | | `UPSTREAM-V1-READ-AUTHORIZATION-004` | 21 |
| `FRONTEND_ARCHITECTURE.md` | 3 | | `UPSTREAM-V1-EVENT-SCOPE-001` | 9 |
| `IMPLEMENTATION_MATRIX.md` | 3 | | `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010` | 4 |
| `BACKGROUND_PROCESSING.md` | 2 | | `UPSTREAM-V1-COMPARISON-EVENT-007` | 3 |
| | | | `UPSTREAM-V1-ROLE-EXPIRY-BLOCKED-EVENT-011` | 3 |
| | | | `UPSTREAM-V1-ISSUE-COLLISION-013` | 1 |
| | | | `UPSTREAM-V1-SESSION-REVOCATION-002` | 1 |

`IMPLEMENTATION_MATRIX.md` is generated. Its three findings are not editable in place: they
originate in `contracts/S-20.json` and `contracts/S-24.json` and must be corrected there.

All 18 negative mutation controls pass. Every local anchor and every cross-document Markdown
anchor resolves.

## Pending Owner Decision Set At Candidate Creation

Exactly five, unchanged from Pass B completion. Status is read from each decision's
`Current Status` field and from nowhere else.

| OD | Withheld limb | Blocker tag | Blocks baseline? |
| --- | --- | --- | --- |
| OD-014 | Project pause/resume/archive transition. State may be represented and read as a guard, never effected. | `UPSTREAM-V1-PROJECT-LIFECYCLE-003` (LIVE) | No |
| OD-023 | Credential rotation begin and complete. Delivery against an already-active Credential is settled; `credential.rotate` is canonical but unreachable. | `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` (LIVE) | No |
| OD-027 | Exactly three artifacts: a `has_one` narrowing, a `unique (parsing_job_id)` constraint, any second IndexingJob per ParsingJob. `indexing-interim-v1` pins both keys. | none | No |
| OD-031 | Routine retention-expiry destruction, under `retention-destruction-trigger-interim-v1`. | none | No |
| OD-032 | Canonical namespace for an unassigned record. Behaviour permitted under the interim. | none | No |

Each records `Volume II — no` for blocking impact under its interim. None blocks this
baseline; each withholds a named limb.

## Meaning Of Withheld Limbs

A withheld limb is a **deliberate, registered, bounded reservation of one behaviour by an
owner decision that has not yet been approved**. It is not a gap, not a defect, and not an
omission.

The rules that make it safe:

1. The limb is named exactly. "Pause/resume/archive transition" is a limb; "project
   lifecycle" is not.
2. The surrounding behaviour is fully specified and implementable. The row is complete.
3. The withheld state may be **represented** in schema and **read as a guard**. It may never
   be **effected**.
4. Implementation MUST NOT resolve the limb by inference, analogy or convenience. Doing so
   resolves a pending owner decision by implementation, which is the failure the register
   exists to prevent.
5. The limb becomes available only when its decision's `Current Status` changes through the
   established governance process — never by a Volume II edit.

## Known Product-Visible Baseline Consequences

These are **settled, ratified behaviours**, not defects and not withheld limbs. They are
recorded here so that no reader mistakes an approved consequence for an outstanding gap, and
so that no implementer "fixes" them.

### The action queue ships empty (OD-010)

OD-010 is ratified. `check-catalog-v1` carries exactly `CHK-TI-001`, `CHK-CQ-001`,
`CHK-TR-001`, `CHK-SP-001`, `CHK-AIP-001`, `CHK-AS-001` and `CHK-LP-001`.

OD-010's Ratified Behavior *approves* the bundle-nothing state and its consequence:
`external-measurement-v1` bundles no query, intent, listing, provider or adapter set before
approval, so implementations do not invent one. Therefore:

- The numeric Discoverability Score is **unavailable** at baseline.
- The three always-applicable external entries (`CHK-SP-001`, `CHK-AIP-001`, `CHK-AS-001`)
  persist handled `input_evidence_missing` errors. `CHK-LP-001` does the same only when its
  frozen applicability decision is true, and otherwise persists its canonical
  `not_applicable` Result.
- **No Recommendation or Priority Decision publishes from an unavailable calculation.**
- Consequently the ratified baseline **ships with an empty action queue**.

This is approved baseline behaviour, not a withheld limb. An implementation that invents a
Measurement Set, a provider call or a placeholder score to populate the queue is
non-conformant. A Measurement Set may later activate as exact signed configuration; Check
execution still makes no provider call. The catalogue is not broadened by this ratification.

### Security and administrative objects are unreadable (OD-020)

OD-020 is ratified. It adds explicit read rows for customer-facing objects and states that
"Deny-by-default is no longer the answer for customer-facing objects." It also carves out:
security, administrative and internal operational objects "remain deny-by-default pending a
separate decision."

At baseline, therefore, no actor can read Support Session, Incident, Investigation, Legal
Hold, LifecycleDeletionJob or privileged Billing collections through a defined permission.
This is ratified, deliberate and fail-closed. See blocker 2 below: the separate decision is
missing from the register, which is a governance defect even though the *behaviour* is
correct.

### Other settled consequences

- Emergency cross-Organization support access is authorized outside the Incident record by a
  dedicated break-glass artifact (OD-012, Option 3). `emergency_customer_access` does not
  exist and the fail-closed outcome is **permanent baseline**, not an interim. The
  customer-notification limb remains withheld pending qualified legal review.
- Sign-out-everywhere is **out of baseline scope**, not blocked (OD-016).
- Verification methods outside DNS TXT and HTTPS file are **out of baseline scope**, not
  blocked pending approval (OD-001).
- The comparison read emits no domain event (OD-024). `ReassessmentTriggered` does not exist
  (OD-025). Document `quarantined` and `retired` states are removed, not reserved (OD-015).

## Release-Readiness Blockers

Two blockers stand between this candidate and an implementation-ready freeze. They are
**governance defects, not implementation gaps**. Pass B's implementation content is complete.

### Blocker 1 — 72 retired blockers cited as live

Volume II cites eight retired blocker tags as live reasons to defer, disable or refuse to
route. `INDEX.md`'s registry is the status authority: only `UPSTREAM-V1-PROJECT-LIFECYCLE-003`
(OD-014) and `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` (OD-023) are LIVE. Every other tag
is retired under ADR-019 or ADR-020 and each of their decisions records `Blocking Impact:
None`.

The failure runs in **both** directions. The same wrong label withholds behaviour the owner
approved *and* risks exposing objects the owner denied. A worker who trusts the citation
withholds ratified behaviour; a worker who bulk-deletes it may enable behaviour whose
obligations are unmet.

**A bulk replacement is therefore unsound and is prohibited.** Each citation asserts "this
capability is disabled because OD-XXX is not complete." Where OD-XXX has since landed, that
sentence has silently become a product decision. One validator signal covers at least three
different defects:

| Class | What is true | Corrective action |
| --- | --- | --- |
| Stale label | Behaviour is already correct; only the retired reference is obsolete. | Replace or remove the citation; change no behaviour. |
| Masked dependency | The retired blocker conceals a genuine unmet obligation. | Satisfy the obligation **before** removing the citation, or register it and withhold the limb explicitly. |
| Right outcome, wrong reason | Behaviour must stay exactly as it is, but under a different ratified authority. | Re-anchor the rationale; change no behaviour; do not widen access. |

Every finding MUST be classified individually, by reading outward into the cited decision's
obligations, the affected acceptance criterion, the contract, the product rules, the route or
object behaviour and any successor decision — never from the citation cell alone. The
governing question for each is: **what would break if this citation were simply deleted?**

At least one known masked dependency exists: OD-019 requires every metered read route to
statically declare exactly one of five low-cost operations or resolve `operation_unknown`. No
route in Volume II carries such a declaration and the route table has no column for one.
Clearing the metering marker without supplying the declaration would assert an enablement
nothing can honour. The citation is accidentally load-bearing.

### Blocker 2 — a required successor decision has no node in the governance graph

OD-020 leaves read authority for security, administrative and internal objects deny-by-default
"pending a separate owner decision", and states that scope "is out of scope for this decision
rather than resolved by it."

That successor decision:

- has no OD number;
- is absent from the register's pending set;
- is required for the affected permission-matrix classes;
- governs at least the `QRY-017`, `QRY-019`, `QRY-020` and `QRY-029`–`QRY-035` group;
- must exist before those right-outcome-wrong-reason citations can be correctly re-anchored.

Deferring a security or administrative read is **substantively correct but mis-attributed**:
its authority is an unregistered pending decision, not a retired tag. Until the node exists
there is nothing correct to re-anchor those citations *to*.

**Workstream B (repair the governance graph) must therefore precede Workstream A (reconcile
the citations).** Reconciling first would force either a false enablement or a citation of a
decision that does not exist.

## Freeze Exit Criteria

The baseline may be frozen and tagged implementation-ready only when **every** criterion
below is met, observed on **one** integrated tree.

1. `build_volume_ii_matrix.py` succeeds and `--check` exits 0.
2. 97 matrix rows; 97 unique acceptance criteria; 97 complete; 0 outstanding.
3. All contract-owner references resolve and every owner cites its row back.
4. Every local and cross-document Markdown anchor resolves against real generated heading
   slugs.
5. `validate_volume_ii.py` exits 0 — in particular **no retired blocker is cited as live**.
6. All negative mutation controls pass, including a control for every newly added rule.
7. The pending-decision register is accurate and complete.
8. **No missing successor-decision node exists.** Every ratified decision that delegates a
   required policy question to a successor names a registered successor.
9. No unresolved implementation-critical authority gap remains.
10. Every withheld limb is either resolved by valid authority, or explicitly retained with a
    registered pending decision **and proven not to block implementation of the baseline**.
11. Volume I and the existing frozen tags remain intact unless an authorised governance change
    explicitly requires otherwise.
12. Generated files match their canonical sources.
13. The repository tree is clean after commits; no untracked files; no unstaged changes.

### Criteria that MUST NOT be met by weakening the test

- An exemption MUST be scoped structurally or line-wise, never by a character-proximity
  window. A proximity window silently exempts real violations: an unrelated "blocked" 218
  characters away in neighbouring prose already defeated one rule, and a rejection of an
  unrelated subject already disabled another for a whole document tail.
- Deny-by-default MUST NOT become allow in order to clear a validator.
- A pending decision MUST NOT be recorded as ratified, and owner approval MUST NOT be
  fabricated, in order to clear a gate.
- If a genuine non-derivable owner decision remains and blocks implementation, the repository
  MUST NOT be tagged implementation-ready. A blocked freeze-candidate commit with exact
  evidence is the correct terminal state.

**Readiness is not manufactured. An artificially green validator is a worse outcome than an
honestly red one.**

## Related Documents

- [RATIFICATION_STATUS_OVERLAY.md](RATIFICATION_STATUS_OVERLAY.md) — Pass B execution control; OBS-001..OBS-005
- [RETIRED_BLOCKER_CLASSIFICATION.md](RETIRED_BLOCKER_CLASSIFICATION.md) — per-finding classification record
- [IMPLEMENTATION_MATRIX.md](IMPLEMENTATION_MATRIX.md) — generated canonical matrix
- [INDEX.md](INDEX.md) — blocker registry and implementation gate
- [../volume-i/OWNER_DECISION_REGISTER.md](../volume-i/OWNER_DECISION_REGISTER.md) — decision status authority
- [../../DECISIONS.md](../../DECISIONS.md) — ADR registry

## Change Control

This document is superseded by the Implementation Readiness Report once every exit criterion
is met. It is not amended to make a criterion look satisfied; a criterion is either observed
green on the integrated tree or it is recorded as blocked.
