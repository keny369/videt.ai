# Volume II Retired-Blocker Classification

## Status

- Status: Freeze-candidate classification record. Not product authority. Not frozen.
- Last Updated: 2026-07-17
- Owner: Chief Architect
- Source commit at classification: `8dee0355b59f232424c4136f5891d54417f2eda6`
- Product-behaviour baseline: `v1.5-volume-i-frozen` (commit `c6b3853`, ADR-020)
- Governing change: ADR-023

## Authority

This record classifies findings. It creates no product behaviour and resolves no owner decision.
Where it and a canonical owner disagree, the canonical owner prevails and this record is
defective. It exists so that a reader can tell, per finding, which of four different defects
was found and what was done about it.

## Purpose

`scripts/validate_volume_ii.py` reports 72 `retired_blocker_cited_as_live` findings at commit
`8dee035`. One validator signal covers at least three different defects, and this pass found a
fourth. A bulk replacement is therefore unsound and is prohibited: each citation asserts *"this
capability is disabled because OD-XXX is not complete"*, and where OD-XXX has since landed that
sentence has silently become a product decision. Removing it may enable behaviour, change
security posture, change an API guarantee or change an operational expectation.

Every finding below was classified by reading **outward** — into the cited decision's own
`Ratified Behavior` and `Blocking Impact`, the affected acceptance criterion, the slice
contract, the product rule, the route or object behaviour, and any successor decision — never
from the citation cell alone. The governing question for each is:

> **What would break if this citation were simply deleted?**

Classification is exhaustive. Every one of the 72 current findings appears exactly once.

## Method

The finding set was extracted mechanically from the validator rather than transcribed, so the
population is a property of the checker rather than of anyone's diligence:

```
python3 - <<'EOF'
import sys, pathlib; sys.path.insert(0, "scripts")
import validate_volume_ii as V
root = pathlib.Path(".").resolve()
findings = [f for f in V.validate(root) if f.code == "retired_blocker_cited_as_live"]
EOF
```

72 findings, across 5 documents and 8 retired tags. No finding was edited before it was
classified.

## Classes

| Class | Count | What is true | Corrective action |
| --- | --- | --- | --- |
| Stale label | 30 | Behaviour is already correct; only the retired reference is obsolete. | Replace the citation with the ratified authority. Change no behaviour. |
| Masked dependency | 29 | The retired citation conceals a genuine unmet obligation. Deleting it asserts an enablement nothing can honour. | Satisfy the obligation, or register it and withhold the limb explicitly. Never delete alone. |
| Right outcome, wrong reason | 11 | The deny is correct and must stay, but under a different ratified authority. | Re-anchor the rationale. Do not widen access. |
| Check artefact | 2 | The document is correct; the **check** misreports it. | Correct the check, not the document. |

### On the fourth class

"Check artefact" is a newly discovered class and is recorded only because it is genuinely
required — the other three each presuppose a document defect, and these two findings are not
document defects.

Both sit on `IMPLEMENTATION_MATRIX.md` line 2000. That file is **generated**, and it renders an
entire contract field as a single physical line of roughly 3,000 characters. The retired-blocker
rule is scoped to a line, on the recorded premise that "a table row and a prose sentence each
occupy one line in this repository". That premise held when the rule was written and no longer
holds for generated contract fields. The result is that a `deferred under` belonging to one
sentence collides with a tag named in a different sentence — a sentence which, in this instance,
says the exact opposite:

> "Enumeration is therefore unreachable because no path was written, NOT because a decision
> withholds it: OD-020 ratifies the authority, `UPSTREAM-V1-READ-AUTHORIZATION-004` is retired,
> and `export.list` governs Export enumeration in WF-016."

That is a correct status statement being reported as a live citation. The remedy is to the rule:
scope it to the **sentence** containing the tag. That is a structural unit — a sentence binds a
subject to its predicate — and is not a character-proximity window. Proximity windows are
prohibited here for good reason: an unrelated "blocked" 218 characters away once exempted a real
violation, and a rejection of an unrelated subject once disabled a check for a whole document
tail. Sentence scoping is narrower than line scoping and is justified structurally, and the
mutation control still kills the rule.

Classifying these as "stale label" and deleting the sentences would have destroyed two correct
status statements to satisfy a defective check. That is the inverse of the failure this record
exists to prevent, and it is why the class exists.

## Analysis By Class

### Stale label — 30 findings

Seven distinct decisions, each ratified or resolved and each recording `Blocking Impact: None`.

- **`UPSTREAM-V1-EVENT-SCOPE-001` (9) — OD-013, resolved, ADR-020, Option 1.** *What breaks if
  deleted: nothing.* Every workflow event and audit record carries a nonnull `organization_id`;
  `BootstrapGrantIssued` and `BootstrapGrantExpired` are emittable under the DM-REQ-013 gate that
  WF-001 now expressly names; a platform-wide Incident and a cross-Organization Investigation are
  each N Organization-owned records linked by `correlation_id`. OD-013's Blocking Impact states
  the DDL and the WF-017/WF-018 scope columns "are unblocked, and `UPSTREAM-V1-EVENT-SCOPE-001`
  is retired." Leaving the citation withholds emission the owner unblocked. **Note the
  dependency:** the citation cannot be cleared alone — `schemas/POSTGRESQL_SCHEMA.md` still
  carries the pre-OD-013 `incidents.platform_wide` boolean and nullable Organization columns, so
  clearing the marker while the DDL contradicts Option 1 would assert an enablement the schema
  refuses. The schema is corrected in the same change set.
- **`UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010` (4) — OD-025, ratified.** *Nothing breaks.* The
  event is removed, not deferred; the question of whether an Entitlement-blocked trigger emits it
  no longer arises because no trigger event exists. Provenance lives on the Reassessment Result
  record and its Audit Evidence.
- **`UPSTREAM-V1-COMPARISON-EVENT-007` (3) — OD-024, ratified.** *Nothing breaks.* "QRY-008 and
  WF-012 are unblocked read-only." The comparison read is audit-only and side-effect-free.
- **`UPSTREAM-V1-ROLE-EXPIRY-BLOCKED-EVENT-011` (3) — OD-026, resolved.** *Nothing breaks* — and
  this one was checked specifically, because the historical prose claims the WF-014 trigger table
  "defines no route predicate, selectors, permission, severity or context for this event", which
  would be a masked dependency. It is not: OD-026's Ratified Behavior states "The mandatory
  `RoleExpiryBlocked` notification route row exists with its recipients, required permission and
  severity." The obligation the citation appeared to conceal is supplied by the decision itself.
- **`UPSTREAM-V1-ISSUE-COLLISION-013` (1) — OD-017, ratified.** *Nothing breaks.* The full
  contract exists: detection predicate, preallocated conflicting identity, the collision decision
  row, restricted `IssueFingerprintCollision` emitted once per attempted conflicting create in
  the same transaction, and `F1-DATA-409 / issue_fingerprint_key_collision` with
  `retryable=false`. The row's four `unavailable` placeholders are fillable from ratified text.
- **`UPSTREAM-V1-SESSION-REVOCATION-002` (1) — OD-016, ratified.** *Nothing breaks.*
  Current-Session sign-out and single-Session SecurityOperator revocation are approved baseline;
  the schema already reaches `revoked` with `self_sign_out` and `security_revocation` reasons.
  Sign-out-everywhere is out of baseline scope, not blocked.
- **`UPSTREAM-V1-READ-AUTHORIZATION-004`, customer-facing (9) — OD-020, ratified, Option 1.**
  *Nothing breaks.* `WORKFLOW_SPECIFICATIONS.md` binds each token to its workflow: `project.read`
  governs Project reads in WF-002; `source.read` WF-003/WF-004; `crawl.read` WF-005;
  `evaluation.read` WF-005/WF-008/WF-011; `notification.inbox.read` the WF-014 inbox scoped to
  the acting principal; `export.list` Export enumeration in WF-016. "Deny-by-default is no longer
  the answer for customer-facing objects." Leaving these citations withholds reads the owner
  ratified on 2026-07-17.

**One masked dependency was found inside this class and is repaired rather than waved through.**
`QRY-015 ExportCollection`'s authority is settled (`export.list`), but S-20 reports that Export
enumeration has **no route at all** — "unreachable because no path was written, NOT because a
decision withholds it". Clearing the authority citation without registering the route would leave
a ratified read unreachable for an undocumented reason. The route is added under the existing
convention; the query, permission and DTO all already exist, so nothing is invented.

### Masked dependency — 29 findings

All 29 cite `UPSTREAM-V1-LOW-COST-METERING-005`. OD-019 is ratified and records `Blocking
Impact: None`, so the tag is correctly retired — and the citation is nonetheless **accidentally
load-bearing**.

*What breaks if deleted: a false enablement.* OD-019's Ratified Behavior requires that "Every
metered read route carries a static declaration of exactly one of the five low-cost operations; a
read route with no declaration resolves `operation_unknown` and returns Block with
`contact_support`, so an undeclared metered route is unreachable rather than silently unmetered."

No route in Volume II carries such a declaration, and the route table has no column for one.
Deleting the marker asserts a reachable metered read that nothing can meter, charge or
deduplicate.

**The declaration is not derivable, and this was tested rather than assumed:**

1. OD-019's Costs book it as unpaid: "Requires a new normative exhaustive route-to-operation
   declaration table, and `report.view` must be given a defined read surface."
2. Volume I defines none of the five operations beyond membership in WF-015's list and a limits
   row. `report.view`, `history.view` and `score.read` appear nowhere else. **`report.view` has
   no read surface at all.**
3. The operation strings are **not** permissions. Three do not exist in `permission-baseline-v1`,
   and Volume II already ruled the overlap inadmissible as authority: "That `issue.read` and
   `recommendation.read` appear in both maps is a coincidence, and inferring a permission from an
   operation name would grant authority Volume I never wrote." The declaration cannot be read off
   the permission cell.
4. `/scores/current` is the case **OD-019 itself names as ambiguous** — "the same navigation can
   reasonably resolve to `report.view` or `score.read`" — and its permission cells
   (`score.summary.read`, `score.detail.read`) match neither candidate.
5. OD-019 classifies the consequence as "a commercial and packaging choice rather than an
   architectural inference", owned by Chief Product. Volume II must not make a commercial choice,
   and `FRONTEND_ARCHITECTURE.md` already forbids making a screen reachable "by selecting a
   convenient operation".

*Action:* do not delete. **OD-035 is registered pending** under ADR-023, carrying OD-019's own
fail-closed leg as its interim. Every citation is re-anchored to OD-019 plus OD-035. The routes
stay unreachable — exactly as today — and the limb is now named and withheld against a registered
node instead of a retired tag. Behaviour does not change; authority does.

### Right outcome, wrong reason — 11 findings

All 11 cite `UPSTREAM-V1-READ-AUTHORIZATION-004` against a security, administrative or internal
operational object: `QRY-017` AccessAdministration, `QRY-019` LifecycleAdministration, `QRY-020`
SecurityOperations, `QRY-028` IntegrationStatus, `QRY-029`–`QRY-034`, and the
`FRONTEND_ARCHITECTURE.md` rendering prohibition.

*What breaks if deleted: access widens.* OD-020's Ratified Behavior is explicit that security,
administrative and internal operational objects "remain deny-by-default pending a separate
decision", and its Blocking Impact records that scope as "out of scope for this decision rather
than resolved by it". The normative binding text in `WORKFLOW_SPECIFICATIONS.md` says the same
and names one further class — **Emergency Access Grant** — that OD-020's own sentence omits.
Deleting the citation invites a reader to "unblock" objects the ratified decision says stay
denied.

**This class could not be reconciled before the governance graph was repaired.** The correct
authority had no OD number and was absent from the register. Volume II recorded the consequence
exactly, on MTX-095: the decision "has no OD number and is absent from the register's pending
set, so it is neither a pending Owner Decision this row may withhold against nor a resolved one
this row may implement." There was nothing correct to cite. **OD-034 is registered pending** under
ADR-023; every citation is re-anchored to OD-020's carve-out plus OD-034, and every deny is
preserved verbatim.

`FRONTEND_ARCHITECTURE.md` line 123 is compound and is classified here because the security half
is the load-bearing one: the same sentence names customer-facing classes that OD-020 has since
granted **and** administrative classes that stay denied. Splitting it is required; collapsing it
either way would be wrong in one direction.

**Scope was derived, not assumed.** OD-034 gates exactly one acceptance criterion —
`AC-PRULE-044` — because its "complete permission-matrix allow/deny fixtures" clause cannot be
satisfied for an object class with no row. `AC-CAP-021`, `AC-CAP-023`, `AC-CAP-025`, `AC-WF-013`,
`AC-WF-017`, `AC-WF-018` and `AC-PRULE-034` each name one of these classes and were each examined
and expressly **not** gated: every dual-control step is satisfied by its own approval contract,
which carries the canonical command request hash and expected target state version as asserted
command inputs rather than by a general read; every exact command result remains available to its
acting actor; and PRULE-034's uncertain aggregate, escalation and user status is served by the
ratified `notification.inbox.read` row. Their contracts are complete and were verified so.

## Complete Finding Register

Every current `retired_blocker_cited_as_live` finding, exactly once. Line numbers are as observed
at commit `8dee035`.

| # | Document | Line | Retired tag cited | Class | Governing authority after reconciliation | Behaviour changes? | Limb changes? |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `API_CONTRACTS.md` | 294 | `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010` | Stale label | OD-025 (ratified, ADR-019) | No | No |
| 2 | `API_CONTRACTS.md` | 296 | `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010` | Stale label | OD-025 (ratified, ADR-019) | No | No |
| 3 | `API_CONTRACTS.md` | 335 | `UPSTREAM-V1-EVENT-SCOPE-001` | Stale label | OD-013 (resolved, ADR-020, Option 1) | No | No |
| 4 | `API_CONTRACTS.md` | 336 | `UPSTREAM-V1-EVENT-SCOPE-001` | Stale label | OD-013 (resolved, ADR-020, Option 1) | No | No |
| 5 | `API_CONTRACTS.md` | 337 | `UPSTREAM-V1-EVENT-SCOPE-001` | Stale label | OD-013 (resolved, ADR-020, Option 1) | No | No |
| 6 | `API_CONTRACTS.md` | 593 | `UPSTREAM-V1-COMPARISON-EVENT-007` | Stale label | OD-024 (ratified, ADR-019, Option 2) | No | No |
| 7 | `API_CONTRACTS.md` | 776 | `UPSTREAM-V1-EVENT-SCOPE-001` | Stale label | OD-013 (resolved, ADR-020, Option 1) | No | No |
| 8 | `API_CONTRACTS.md` | 839 | `UPSTREAM-V1-ISSUE-COLLISION-013` | Stale label | OD-017 (ratified, `issue-collision-v1`) | No | No |
| 9 | `API_CONTRACTS.md` | 869 | `UPSTREAM-V1-ROLE-EXPIRY-BLOCKED-EVENT-011` | Stale label | OD-026 (resolved, supplement, Option 1) | No | No |
| 10 | `API_CONTRACTS.md` | 876 | `UPSTREAM-V1-SESSION-REVOCATION-002` | Stale label | OD-016 (ratified, ADR-019, Option 3) | No | No |
| 11 | `API_CONTRACTS.md` | 916 | `UPSTREAM-V1-EVENT-SCOPE-001` | Stale label | OD-013 (resolved, ADR-020, Option 1) | No | No |
| 12 | `API_CONTRACTS.md` | 924 | `UPSTREAM-V1-EVENT-SCOPE-001` | Stale label | OD-013 (resolved, ADR-020, Option 1) | No | No |
| 13 | `API_CONTRACTS.md` | 925 | `UPSTREAM-V1-EVENT-SCOPE-001` | Stale label | OD-013 (resolved, ADR-020, Option 1) | No | No |
| 14 | `API_CONTRACTS.md` | 926 | `UPSTREAM-V1-EVENT-SCOPE-001` | Stale label | OD-013 (resolved, ADR-020, Option 1) | No | No |
| 15 | `APPLICATION_LAYER.md` | 116 | `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010` | Stale label | OD-025 (ratified, ADR-019) | No | No |
| 16 | `APPLICATION_LAYER.md` | 118 | `UPSTREAM-V1-ROLE-EXPIRY-BLOCKED-EVENT-011` | Stale label | OD-026 (resolved, supplement, Option 1) | No | No |
| 17 | `APPLICATION_LAYER.md` | 153 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Stale label | OD-020 (ratified, ADR-019, Option 1) — explicit read row | No | No |
| 18 | `APPLICATION_LAYER.md` | 155 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Stale label | OD-020 (ratified, ADR-019, Option 1) — explicit read row | No | No |
| 19 | `APPLICATION_LAYER.md` | 156 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Stale label | OD-020 (ratified, ADR-019, Option 1) — explicit read row | No | No |
| 20 | `APPLICATION_LAYER.md` | 157 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Stale label | OD-020 (ratified, ADR-019, Option 1) — explicit read row | No | No |
| 21 | `APPLICATION_LAYER.md` | 159 | `UPSTREAM-V1-COMPARISON-EVENT-007` | Stale label | OD-024 (ratified, ADR-019, Option 2) | No | No |
| 22 | `APPLICATION_LAYER.md` | 165 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Stale label | OD-020 (ratified, ADR-019, Option 1) — explicit read row | No | No |
| 23 | `APPLICATION_LAYER.md` | 166 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Stale label | OD-020 (ratified, ADR-019, Option 1) — explicit read row | No | No |
| 24 | `APPLICATION_LAYER.md` | 167 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Stale label | OD-020 (ratified, ADR-019, Option 1) — explicit read row | No | No |
| 25 | `APPLICATION_LAYER.md` | 173 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Stale label | OD-020 (ratified, ADR-019, Option 1) — explicit read row | No | No |
| 26 | `APPLICATION_LAYER.md` | 174 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Stale label | OD-020 (ratified, ADR-019, Option 1) — explicit read row | No | No |
| 27 | `BACKGROUND_PROCESSING.md` | 406 | `UPSTREAM-V1-ROLE-EXPIRY-BLOCKED-EVENT-011` | Stale label | OD-026 (resolved, supplement, Option 1) | No | No |
| 28 | `BACKGROUND_PROCESSING.md` | 411 | `UPSTREAM-V1-REASSESSMENT-TRIGGER-EVENT-010` | Stale label | OD-025 (ratified, ADR-019) | No | No |
| 29 | `FRONTEND_ARCHITECTURE.md` | 125 | `UPSTREAM-V1-COMPARISON-EVENT-007` | Stale label | OD-024 (ratified, ADR-019, Option 2) | No | No |
| 30 | `IMPLEMENTATION_MATRIX.md` | 2109 | `UPSTREAM-V1-EVENT-SCOPE-001` | Stale label | OD-013 (resolved, ADR-020, Option 1) | No | No |
| 31 | `API_CONTRACTS.md` | 541 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 32 | `API_CONTRACTS.md` | 586 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 33 | `API_CONTRACTS.md` | 587 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 34 | `API_CONTRACTS.md` | 588 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 35 | `API_CONTRACTS.md` | 589 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 36 | `API_CONTRACTS.md` | 590 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 37 | `API_CONTRACTS.md` | 591 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 38 | `API_CONTRACTS.md` | 592 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 39 | `API_CONTRACTS.md` | 593 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 40 | `API_CONTRACTS.md` | 594 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 41 | `API_CONTRACTS.md` | 595 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 42 | `API_CONTRACTS.md` | 596 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 43 | `API_CONTRACTS.md` | 597 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 44 | `APPLICATION_LAYER.md` | 154 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 45 | `APPLICATION_LAYER.md` | 157 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 46 | `APPLICATION_LAYER.md` | 158 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 47 | `APPLICATION_LAYER.md` | 159 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 48 | `APPLICATION_LAYER.md` | 160 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 49 | `APPLICATION_LAYER.md` | 161 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 50 | `APPLICATION_LAYER.md` | 162 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 51 | `APPLICATION_LAYER.md` | 163 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 52 | `APPLICATION_LAYER.md` | 164 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 53 | `APPLICATION_LAYER.md` | 175 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 54 | `APPLICATION_LAYER.md` | 176 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 55 | `APPLICATION_LAYER.md` | 187 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 56 | `APPLICATION_LAYER.md` | 189 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 57 | `APPLICATION_LAYER.md` | 190 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 58 | `APPLICATION_LAYER.md` | 2897 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 59 | `FRONTEND_ARCHITECTURE.md` | 125 | `UPSTREAM-V1-LOW-COST-METERING-005` | Masked dependency | OD-019 ratified fail-closed leg + **OD-035** (pending, registered this pass) | No | Yes |
| 60 | `APPLICATION_LAYER.md` | 168 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Right outcome, wrong reason | OD-020 ratified carve-out + **OD-034** (pending, registered this pass) | No | Yes |
| 61 | `APPLICATION_LAYER.md` | 170 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Right outcome, wrong reason | OD-020 ratified carve-out + **OD-034** (pending, registered this pass) | No | Yes |
| 62 | `APPLICATION_LAYER.md` | 171 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Right outcome, wrong reason | OD-020 ratified carve-out + **OD-034** (pending, registered this pass) | No | Yes |
| 63 | `APPLICATION_LAYER.md` | 179 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Right outcome, wrong reason | OD-020 ratified carve-out + **OD-034** (pending, registered this pass) | No | Yes |
| 64 | `APPLICATION_LAYER.md` | 180 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Right outcome, wrong reason | OD-020 ratified carve-out + **OD-034** (pending, registered this pass) | No | Yes |
| 65 | `APPLICATION_LAYER.md` | 181 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Right outcome, wrong reason | OD-020 ratified carve-out + **OD-034** (pending, registered this pass) | No | Yes |
| 66 | `APPLICATION_LAYER.md` | 182 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Right outcome, wrong reason | OD-020 ratified carve-out + **OD-034** (pending, registered this pass) | No | Yes |
| 67 | `APPLICATION_LAYER.md` | 183 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Right outcome, wrong reason | OD-020 ratified carve-out + **OD-034** (pending, registered this pass) | No | Yes |
| 68 | `APPLICATION_LAYER.md` | 184 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Right outcome, wrong reason | OD-020 ratified carve-out + **OD-034** (pending, registered this pass) | No | Yes |
| 69 | `APPLICATION_LAYER.md` | 185 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Right outcome, wrong reason | OD-020 ratified carve-out + **OD-034** (pending, registered this pass) | No | Yes |
| 70 | `FRONTEND_ARCHITECTURE.md` | 123 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Right outcome, wrong reason | OD-020 ratified carve-out + **OD-034** (pending, registered this pass) | No | Yes |
| 71 | `IMPLEMENTATION_MATRIX.md` | 2000 | `UPSTREAM-V1-LOW-COST-METERING-005` | Check artefact | OD-019 (ratified) — sentence quotes another document's marker | No | No |
| 72 | `IMPLEMENTATION_MATRIX.md` | 2000 | `UPSTREAM-V1-READ-AUTHORIZATION-004` | Check artefact | OD-020 (ratified) — sentence already states the tag is retired | No | No |

## Totals

| Class | Findings | Behaviour changes | New withheld limb |
| --- | --- | --- | --- |
| Stale label | 30 | none | none |
| Masked dependency | 29 | none | MTX-024, MTX-040, MTX-091 under OD-035 |
| Right outcome, wrong reason | 11 | none | MTX-095 under OD-034 |
| Check artefact | 2 | none | none |
| **Total** | **72** | **none** | **4 rows** |

**No finding in any class changes product behaviour.** Every deny is preserved; every ratified
grant is honoured; no deny becomes an allow. The matrix stays 97 rows, 97 acceptance criteria,
97 complete and 0 outstanding. The withheld-limb count rises from 18 rows to 22 — not because
anything was withdrawn, but because two limbs that were previously withheld against a *retired
tag* or against *nothing at all* are now withheld against registered decisions that can actually
be approved.

## Validator Effect

Reconciling all 72 takes `retired_blocker_cited_as_live` to 0. That is a consequence of the
repair, not its objective. The objective is that every withholding in Volume II cites an
authority that exists and is live. Two rule changes are made in the same change set and each
carries a negative mutation control:

- the retired-blocker rule is scoped to the sentence containing the tag rather than the whole
  line, which removes the two check artefacts without weakening the rule;
- the rule's corpus is widened from `specification/volume-ii/*.md` to the full in-scope tree,
  because `schemas/POSTGRESQL_SCHEMA.md` cites retired tags as live and was never scanned.

The second change **adds** findings. It is made in this pass precisely because it would otherwise
have let a real defect class survive a freeze that claimed to have eliminated it.

## Related Documents

- [SPECIFICATION_FREEZE_CANDIDATE.md](SPECIFICATION_FREEZE_CANDIDATE.md)
- [RATIFICATION_STATUS_OVERLAY.md](RATIFICATION_STATUS_OVERLAY.md) — OBS-005 records this defect class
- [../volume-i/OWNER_DECISION_REGISTER.md](../volume-i/OWNER_DECISION_REGISTER.md) — OD-034, OD-035
- [../../DECISIONS.md](../../DECISIONS.md) — ADR-023

## Change Control

A new `retired_blocker_cited_as_live` finding MUST be classified here before it is edited. This
record is append-only for its finding register: a classification is superseded by a dated entry,
never rewritten.
