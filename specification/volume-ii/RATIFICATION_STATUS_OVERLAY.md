# Volume II Ratification-Status Overlay

## Status

- Status: Pass B execution control. Not product authority.
- Last Updated: 2026-07-17
- Owner: Chief Architect
- Product-behaviour baseline: `v1.5-volume-i-frozen` (frozen; NOT modified by this overlay)
- Engineering-practice baseline: `v1.7-engineering-manual-accepted`

## Why this exists

Frozen Volume I contains requirement prose written **before** the 2026-07-17 owner ratification
session and never updated. Several rules still describe decisions as "interim" or "pending" that
the Owner Decision Register records as ratified. The register was updated; the prose citing it was
not.

The failure mode has a direction. A reader who trusts the wording **withholds behaviour the owner
has approved** — the mirror image of pre-empting an open decision, and just as wrong. Pass B
Continuation 003 was briefed on exactly that premise for OD-001 and would have withheld a ratified
method set.

This overlay exists so that no worker rediscovers this. Volume I is frozen and is **not** edited
here: a controlled correction, if authorized, belongs in a separate governed pass with its own ADR
and impact mapping.

## The rule

**Owner Decision status comes only from that decision's `Current Status` field in
`specification/volume-i/OWNER_DECISION_REGISTER.md`.**

Requirement prose is not a status source. A rule that says "interim" does not make its decision
pending. A rule that omits the word does not make it ratified. This rule is executable:
`scripts/validate_volume_ii.py` resolves status from `Current Status` alone and fails a contract
that treats a ratified decision as pending (`ratified_decision_treated_as_pending`) or a pending
decision as ratified (`pending_decision_treated_as_ratified`), with mutation-killed controls.

## Canonical status

### Pending — withhold the named limb only

| OD | Withheld limb | Blocker |
| --- | --- | --- |
| OD-014 | Project pause/resume/archive transition. State may be **represented and read as a guard**, never effected. | `UPSTREAM-V1-PROJECT-LIFECYCLE-003` |
| OD-023 | Credential rotation **begin** and **complete**. Delivery against an already-active Credential is settled. `credential.rotate` is canonical but unreachable. | `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` |
| OD-027 | Exactly three artifacts: a `has_one` narrowing, a `unique (parsing_job_id)` constraint, any second IndexingJob per ParsingJob. `indexing-interim-v1` pins both keys. | none |
| OD-031 | Routine retention-expiry destruction, under `retention-destruction-trigger-interim-v1`. | none |
| OD-032 | Canonical namespace for an unassigned record. Behaviour permitted under the interim. | none |

No other decision is pending. None of the five blocks a whole slice; each withholds a limb.

### Ratified but still described as pending or interim by frozen prose

These are **settled authority**. Do not withhold them. Do not reopen them.

#### OD-001 — Verification Method Set (OBS-001)

- `Current Status`: Ratified 2026-07-17, ratified as specified. `Blocking Impact: None.`
- Approved: **Option 2 — DNS TXT and HTTPS file.** Other methods are **out of baseline scope**,
  not blocked pending approval.
- Stale prose: PRULE-005, PRULE-020, and the Ownership-Verification Evidence Contract preamble
  ("operationalizes the OD-001 **interim** method set without resolving the owner approval").
- Position: the content those documents carry **is** the ratified baseline. ADR-019 integrated
  OD-001 "as specified". Implement it exactly.

#### OD-010 — Baseline Check Catalog And Measurement Scope (OBS-002)

- `Current Status`: Ratified 2026-07-17. `Blocking Impact: None.`
- Approved: **Option 1** — `check-catalog-v1` with exactly `CHK-TI-001`, `CHK-CQ-001`,
  `CHK-TR-001`, `CHK-SP-001`, `CHK-AIP-001`, `CHK-AS-001`, `CHK-LP-001`.
- Stale prose: `parsing-interim-v1` says the set bundles nothing "**while OD-010 remains
  pending**"; the catalogue carries `status: active_interim` and is called "the mandatory
  deterministic interim Catalog **pending OD-010 approval**".
- **Position — read this precisely.** OD-010's Ratified Behavior *approves* the bundle-nothing
  state and its consequence: "`external-measurement-v1` bundles no query, intent, listing,
  provider, or adapter set before approval, so implementations do not invent one ... The numeric
  score therefore remains unavailable."
  - The three always-applicable external entries (`CHK-SP-001`, `CHK-AIP-001`, `CHK-AS-001`)
    persist handled `input_evidence_missing` errors.
  - `CHK-LP-001` does the same **only** when its frozen applicability decision is true, and
    otherwise persists its canonical `not_applicable` Result.
  - **An unavailable numeric score is approved baseline behaviour, not a withheld limb.**
  - A Measurement Set may later activate as exact signed configuration; Check execution still
    makes no provider call.
  - No Recommendation or Priority Decision publishes from an unavailable calculation.
- The catalogue is **not broadened** by this ratification.

#### OD-012 — Emergency Cross-Organization Support Access (OBS-003)

- `Current Status`: Ratified 2026-07-17, resolved by replacement.
- Approved: **Option 3** — emergency access is authorized outside the Incident record by a
  dedicated break-glass artifact and workflow. `emergency_customer_access` does not exist; the
  fail-closed outcome is **permanent baseline**, not an interim.
- `Blocking Impact`: **Partially outstanding** — this one is not a clean "None". The
  emergency-access architecture is ratified and integrated; **customer notification on emergency
  access remains blocked pending qualified legal review**. Treat the architecture as settled and
  the customer-notification limb as withheld under its recorded gate.
- Stale prose: WF-017's "until OD-012 is approved".

#### OD-017 — Issue Fingerprint Collision (OBS-004)

- `Current Status`: Ratified 2026-07-17, resolved by owner decision. `Blocking Impact: None.`
- Approved: `issue-collision-v1`. On a collision — `fingerprint_sha256` equal AND retained
  preimage unequal within the same `(evaluation_id, fingerprint_version)` — **the second Issue
  MUST NOT be created and the affected Evaluation fails closed** as
  `F1-DATA-409 / issue_fingerprint_key_collision`, `retryable=false`.
- **Stale prose, and note the direction.** `SCORE_EVIDENCE_MODEL.md` "Replay And Collision
  Behavior" still reads: "The second full tuple **may create** its own Issue in the hash bucket."
  Unlike OBS-001 to OBS-003, this does not withhold approved behaviour — it *permits behaviour
  the owner forbade*. A reader who trusts it persists a customer-visible finding from a
  fingerprint scheme that has demonstrably failed.
- Position: OD-017's own `Why The Decision Exists` names that exact permissive keyword as the
  defect it was raised to fix, and WF-007 Primary Path step 4 carries the ratified branch.
  WF-007/OD-017 prevail. PRULE-023's only MUST (never merge) is satisfied either way, so
  implementing the ratified branch breaches nothing.

### Retired blocker tags cited as live (OBS-005)

`INDEX.md`'s registry is the status authority for `UPSTREAM-V1-*` blocker tags, exactly as each
decision's `Current Status` is for Owner Decisions. **Only two tags are LIVE:**
`UPSTREAM-V1-PROJECT-LIFECYCLE-003` (OD-014) and `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009`
(OD-023).

Every other tag is retired under ADR-019 or ADR-020, and each of their decisions records
`Blocking Impact: None`. Volume II nonetheless still cites eight retired tags as live reasons to
defer, disable or refuse to route — 69 sites across `API_CONTRACTS.md`, `APPLICATION_LAYER.md`,
`FRONTEND_ARCHITECTURE.md`, `BACKGROUND_PROCESSING.md`, `INDEX.md` and
`schemas/POSTGRESQL_SCHEMA.md`. This is the OBS-001 trap at scale: a worker who trusts the
citation withholds behaviour the owner ratified.

`scripts/validate_volume_ii.py` now detects this (`retired_blocker_cited_as_live`,
mutation-killed control). It is **reported, not suppressed** — the findings are real and the
correct replacement text is a product-visible question, not a mechanical substitution.

#### Why a bulk replacement is unsound

Each citation asserts *"this capability is disabled because OD-XXX is not complete."* Where
OD-XXX has since landed, that sentence has silently become a **product decision**. Removing it
may enable behaviour, change security posture, change an API guarantee or change an operational
expectation. One validator signal covers at least three different defects, and only a governed
review can tell which one each occurrence is:

| Class | What is true | Corrective action |
| --- | --- | --- |
| **Stale label** | Behaviour is already correct; only the retired reference is obsolete. | Replace or remove the citation. |
| **Masked dependency** | The retired blocker was hiding a capability that still lacks a required dependency. | Implement the dependency **before** removing the citation. |
| **Right outcome, wrong reason** | Behaviour must stay exactly as it is, but under a different ratified decision. | Re-anchor the rationale; change no behaviour. |

Worked examples of each, found by slice workers rather than by the check:

- **Stale label** — `QRY-008` is disabled under COMPARISON-EVENT-007 while OD-024 records
  "comparison reads are unblocked". `API_CONTRACTS.md` asserts "no `project.read` action exists";
  it exists, in the Permission Baseline, under ratified OD-020.
- **Masked dependency** — OD-019 requires every metered read route to statically declare one of
  five low-cost operations or fail `operation_unknown`. **No route in Volume II carries such a
  declaration and the route table has no column for one.** Clearing the metering marker would
  assert an enablement nothing can honour. The citation is accidentally load-bearing.
- **Right outcome, wrong reason** — `QRY-017`, `QRY-019`, `QRY-020`, `QRY-029`–`QRY-035` must
  stay deny-by-default, but on OD-020's own ratified carve-out, not on a retired tag. Citing the
  retired tag here invites someone to "unblock" objects the ratified decision says stay denied.

Note the failure runs in **both** directions. The same wrong label withholds behaviour the owner
approved *and* risks exposing objects the owner denied.

Distinguish two things the prose conflates:

- **The upstream ambiguity** each tag named — resolved. The semantic contract is canonical in
  Volume I.
- **The Volume II transport/application exposure** — the correction packages say this "remains
  intentionally deferred until the Volume II baseline". Pass B **is** that baseline, so this
  resolves *to this pass*, and a slice contracting the surface supersedes the deferral.

**One residual is genuinely open and is not a labelling error.** OD-020 ratified explicit read
rows for customer-facing objects (Organization home data, Project, Source, Crawl, Evaluation,
Notification inbox, Export enumeration) — "Deny-by-default is no longer the answer for
customer-facing objects." But read authority for **security, administrative and internal
operational objects** (Support Session, Incident, Investigation, Legal Hold, LifecycleDeletionJob,
privileged Billing) "remains deny-by-default **pending a separate owner decision**, and is out of
scope for this decision rather than resolved by it." That separate decision **has no OD number and
is absent from the register's pending set**. Deferring a customer-facing read under
`UPSTREAM-V1-READ-AUTHORIZATION-004` is a defect; deferring a security or administrative read is
substantively correct but mis-attributed — its authority is an unregistered pending decision, not
a retired tag.

### Other ratified decisions referenced by remaining slices

Settled authority; implement as ratified. `OD-003` (numeric confidence `0.0000`-`1.0000` with
displayed Low/Medium/High bands), `OD-005`, `OD-006`, `OD-007` (one-directional Citation),
`OD-008`, `OD-009` (disputed and review-required Issues excluded from published scoring and
prioritisation until eligible), `OD-011`, `OD-013` (Option 1, Organization-owned; no platform-owned
record), `OD-015`, `OD-016`, `OD-017`, `OD-018` (one initial Evaluation orchestration per Project),
`OD-019`, `OD-020`, `OD-021` (ratified knowingly; MUST NOT be described as a neutral interim),
`OD-022`, `OD-024` (comparison emits no domain event), `OD-025`, `OD-026`, `OD-029`, `OD-030`,
`OD-033`. `OD-028` is withdrawn.

Note: the register's own Status header (line 5) still lists ten decisions as pending and says
OD-013 "awaits an explicit Chief Architect decision". That header is stale; each decision's
`Current Status` field prevails, and OD-013's says resolved and closed.

## Scope of this overlay

This overlay is **execution control for Pass B workers**, not product authority. It restates the
register; it does not amend it. Where this overlay and the register disagree, the register
prevails and this overlay is defective.

It creates no pending-decision blocker for OD-001, OD-010 or OD-012, and reclassifies no
completed slice as provisional.
