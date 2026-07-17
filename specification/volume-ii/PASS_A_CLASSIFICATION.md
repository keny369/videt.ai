# Volume II Pass A Classification

## Status

- Status: Pass A record. Not frozen.
- Last Updated: 2026-07-17
- Owner: Chief Architect
- Product-behaviour baseline: `v1.5-volume-i-frozen` (commit `c6b3853`, ADR-020)
- Engineering-practice baseline: `v1.7-engineering-manual-accepted` (commit `b049a41`, ADR-022)

## Purpose

Record how every existing Volume II statement was classified against the two accepted
baselines, and by what method. The corpus is 11 documents and roughly 4,000 lines. This
record states what was checked mechanically and what was not, so that a reader can tell the
difference between a verified claim and an unverified one.

## Method

Classification was mechanical wherever a check could be written, and explicit about its
limits everywhere else. `scripts/validate_volume_ii.py` decides seven of the categories by
executing nine checks over the corpus; the remaining judgements are recorded below with
their evidence.

Mechanical classification is not a convenience here. The Engineering Manual carried an
invented entity and five pre-empted owner decisions through months of human review, and a
whole-corpus read by one author is exactly the control that already failed. Where a claim
is asserted rather than executed, it is marked as such.

## Categories

### Still valid against both accepted baselines

The substantive body of all 11 documents. Volume II Pass 001 was authored against
the historical predecessor `v1.3-volume-i-corrected`. ADR-019 and ADR-020 changed Volume I
by resolving owner decisions rather than by re-writing accepted behaviour. The behavioural contracts Volume II
records therefore survive the re-baseline.

Evidence: after correcting the stale headers below, `scripts/validate_volume_ii.py` reports
zero findings across 385 in-scope files, including zero invented entities, zero invented
events, zero invented permissions, zero pre-empted owner decisions and zero non-canonical
terminology. Each check is proved load-bearing by mutation.

Limitation, stated plainly: these checks decide vocabulary and authority, not semantics.
They confirm that Volume II names no artefact Volume I does not define. They do not confirm
that every behavioural clause matches its Volume I clause word for word. That comparison is
per-contract work and belongs to Pass B, where each matrix row is filled against its own
acceptance criterion.

### Stale but mechanically correctable — 12 statements, all corrected

| Statement | Documents | Correction |
| --- | --- | --- |
| Behavioural baseline declared as `v1.3-volume-i-corrected` | all 11 Volume II documents | Re-baselined onto `v1.5-volume-i-frozen`, with the engineering-practice baseline added and the historical tag retained as predecessor history |
| Volume II architecture baseline gated on "all thirteen upstream Volume I blockers" | INDEX.md | Restated on implementation-blocking status; eleven blockers are retired and cannot be "corrected" |

The whole corpus declared a superseded product-behaviour baseline. This was invisible to
review for the same reason it was invisible to the first version of the Volume II validator:
a string-prefix bug excluded `specification/volume-ii` from every check, because that path
starts with `specification/volume-i`. The negative controls caught it.

### Contradicted by Volume I — 11 statements, all corrected

The per-blocker prose in INDEX.md described eleven retired blockers as live constraints.
Each blocker's governing owner decision was ratified and integrated under ADR-019 or
ADR-020, so the prose contradicted the frozen baseline it claimed to defer to.

Correction: a status table now records each blocker's governing decision and whether it is
retired or live. The original prose is retained beneath it as the historical record of why
each blocker existed, explicitly marked as describing a resolved question.

| Retired | Governing OD | | Live | Governing OD |
| --- | --- | --- | --- | --- |
| EVENT-SCOPE-001 | OD-013 | | PROJECT-LIFECYCLE-003 | OD-014 |
| SESSION-REVOCATION-002 | OD-016 | | CREDENTIAL-ROTATION-TOKEN-009 | OD-023 |
| READ-AUTHORIZATION-004 | OD-020 | | | |
| LOW-COST-METERING-005 | OD-019 | | | |
| REACTIVATION-PROOF-006 | OD-021 | | | |
| COMPARISON-EVENT-007 | OD-024 | | | |
| ORGANIZATION-REACTIVATION-PROOF-008 | OD-022 | | | |
| REASSESSMENT-TRIGGER-EVENT-010 | OD-025 | | | |
| ROLE-EXPIRY-BLOCKED-EVENT-011 | OD-026 | | | |
| DOCUMENT-LIFECYCLE-012 | OD-015 | | | |
| ISSUE-COLLISION-013 | OD-017 | | | |

### Contradicted by the Engineering Manual — none found

Volume II specialises manual defaults in several places, which the authority model permits
where the specialisation is explicit and traceable. No statement was found that contradicts
an accepted manual standard rather than specialising it.

Evidence: asserted, not executed. No check distinguishes a permitted specialisation from a
contradiction, because doing so requires reading each manual default against each Volume II
clause. Recorded as a Pass B obligation per row rather than claimed as verified here.

### Blocked by a pending decision — 18 matrix rows, limb-withheld

Five owner decisions remain pending. Each withholds a limb rather than a capability, and the
Owner Decision Register records every one as `Volume II — no` for blocking impact under its
interim. Volume II is therefore not blocked; eighteen matrix rows carry a withheld limb.

Withheld limbs and their slices are recorded in [SLICE_REGISTER.md](SLICE_REGISTER.md).
No statement was found that implements a withheld limb.

### Unsupported invention — none found

Evidence: executed. Zero findings for `entity_absent_from_volume_i`,
`event_absent_from_canonical_model`, `permission_absent_from_model`,
`route_without_governing_obligation` and `pending_od_preemption` across the corpus, with
Volume II genuinely in scope after the prefix bug was fixed.

This is a stronger result than it first appears, and it is worth being precise about why.
An earlier run reported 104 findings, of which 98 were false positives: the event check read
only `016 STATE_MODEL.md` and so missed 73 of the 157 canonical event names, and the
permission check treated every dotted token — `issues.csv`, `meta.page_size`, the Postgres
GUC `app.organization_id` — as a permission. Both checks were corrected to read the full
canonical vocabulary and to judge only tokens in a real permission namespace. The surviving
zero is therefore a zero from a check that works, not from a check that sees nothing.

### Duplicate of another canonical contract — 1 accepted overlap

`APPLICATION_LAYER.md` and `API_CONTRACTS.md` both enumerate operations, at different
altitudes: the application layer names the command and its aggregate root, the API contract
names the transport exposure. This is a deliberate separation rather than duplication, and
both are needed. It is recorded here so that Pass B does not "resolve" it by deleting one.

No other duplicate canonical contract was found.

## Counts

| Classification | Count | Decided by |
| --- | --- | --- |
| Still valid against both baselines | 11 documents (substantive body) | Executed checks for vocabulary and authority; semantics deferred to Pass B |
| Stale but mechanically correctable | 12 statements | Executed; all corrected |
| Contradicted by Volume I | 11 statements | Executed; all corrected |
| Contradicted by the Engineering Manual | 0 | Asserted, not executed |
| Blocked by a pending decision | 18 matrix rows | Executed against the Owner Decision Register |
| Unsupported invention | 0 | Executed |
| Duplicate of another canonical contract | 1 accepted overlap | Asserted, not executed |

## What Pass A Did Not Verify

Stated so that Pass B does not inherit a false sense of completeness:

1. Clause-level semantic agreement between each Volume II contract and its Volume I source.
   The checks confirm vocabulary and authority, not meaning.
2. Whether each Volume II specialisation of a manual default is justified. No check
   distinguishes a permitted specialisation from a contradiction.
3. Whether the existing 150 command operations and 40 query operations in
   `APPLICATION_LAYER.md` are individually correct. They are reconciled as a set, not audited
   one by one.

Each is a per-row Pass B obligation, and each matrix row carries its own acceptance criterion
against which it will be decided.

## Upstream Authority-Status Observations (Pass B)

Recorded here rather than corrected. Volume I is frozen at `v1.5-volume-i-frozen`, and changing
an immutable behavioural baseline inside Volume II Pass B would weaken the governance model. Each
observation is status-only: none contradicts any behaviour, and none blocks a contract.

### OBS-001 — Stale "interim" wording for the ratified OD-001 method set

- **Status:** open, upstream, non-blocking.
- **Where:** PRULE-005 and PRULE-020 in `PRODUCT_RULES.md`; the preamble of the
  Ownership-Verification Evidence Contract in `SCORE_EVIDENCE_MODEL.md`
  ("This logical contract operationalizes the OD-001 interim method set without resolving the
  owner approval").
- **Canonical position:** the Owner Decision Register records OD-001 as
  `Current Status: Ratified on 2026-07-17 ... ratified as specified`, Approved Option 2 (DNS TXT
  and HTTPS file), `Blocking Impact: None`, integrated by ADR-019. OD-001 is not one of the five
  pending decisions.
- **Why it matters:** the wording predates ratification. Read without checking the register it
  invites a reader to treat settled authority as unresolved and withhold behaviour the owner has
  approved — the mirror image of pre-empting an open decision, and just as wrong. Pass B
  Continuation 003 was briefed on exactly that premise.
- **Behavioural impact:** none. ADR-019 ratified OD-001 "as specified", so the content those
  documents carry **is** the ratified baseline. Only the status prose is stale.
- **Containment:** the trap is now closed by execution rather than by attention.
  `scripts/validate_volume_ii.py` resolves decision status only from each decision's own
  `Current Status` field in the register, never from requirement prose, and fails a contract that
  treats a ratified decision as pending or a pending decision as ratified. Three mutation-killed
  negative controls prove it.
- **Disposition:** a controlled Volume I correction, if authorized, belongs in a separate governed
  correction pass with its own ADR and impact mapping. It MUST NOT happen silently inside Volume
  II Pass B. No pending-decision blocker is created for OD-001, and S-05 is not reclassified as
  provisional or withheld.
