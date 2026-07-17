# Volume I Legal Review Record — 2026-07-17

## Status

- Status: Owner approval and counsel consultation recorded; the OD-011 qualified-legal-approval standard is NOT met
- Date: 2026-07-17
- Recorded By: Chief Architect
- Milestone Context: `v1.4-volume-i-ratified-prelegal` at `b2cb4ca`
- Effect On Freeze: none. This record does not satisfy any freeze prerequisite and does not open the OD-011 production or contractual gate.

## Purpose

Record the owner's approval and the fact of counsel consultation as durable audit evidence, and state precisely which elements of the repository's own legal-approval standard remain unsatisfied. This record asserts no normative behaviour and confers no authority.

This document is NOT a legal opinion. The repository contains no legal opinion, no named reviewer, and no reviewed package digest.

## What The Owner Provided On 2026-07-17

Recorded as given:

1. The owner approves the product, architecture, operational, commercial, security, privacy and governance proposals presently recorded in the repository, except where a document explicitly requires a choice that cannot logically be inferred from those proposals.
2. The owner has consulted legal counsel.
3. Legal counsel has no objection to the proposals presently recorded.
4. The owner authorizes completion of the remaining legal package, closure of the remaining Volume I decisions, final validation, commit and creation of the final Volume I freeze tag, subject to the constraints below.
5. No prices, jurisdictions, markets, contractual promises, retention periods, regulatory claims or customer commitments may be invented merely to obtain closure.
6. Where an unresolved item already contains a clearly recommended or default option consistent with the ratified architecture, it may be adopted through the proper owner-decision mechanism.
7. Where a decision requires factual information the repository does not contain and which cannot be inferred safely, it MUST NOT be fabricated; the missing owner input is recorded and the item left open.

## Scope Actually Reviewed

The owner's approval attaches to the proposals **as presently recorded in the repository**. At `b2cb4ca` the recorded retention model is `retention-interim-v1` in [../015 DATA_LIFECYCLE.md](../015%20DATA_LIFECYCLE.md), which OD-011 describes as interim and which no owner has approved as final.

The consultation is recorded as a consultation. Its scope, the materials placed before counsel, and the questions asked are not recorded in this repository and are not asserted here.

## Assumptions

None are made. This record infers nothing from the owner statement beyond its literal content.

## Exclusions

This record expressly does not establish, and MUST NOT be read as establishing:

- any jurisdiction or set of jurisdictions;
- any market or customer segment;
- any customer type, contract template, or contractual commitment;
- any data category beyond those already recorded;
- any retention period, deletion deadline, or backup deadline beyond those already recorded as interim;
- any regulatory conclusion or compliance claim;
- the identity, capacity, or qualification of any legal reviewer;
- approval of any specific immutable policy package or its digest.

## Why This Does Not Close OD-011

OD-011 defines its own closure standard. Its approval package requires, verbatim from [OWNER_DECISION_REGISTER.md](OWNER_DECISION_REGISTER.md):

> Qualified legal approval: reviewer identity and capacity, jurisdictions and material legal assumptions reviewed, package identity/version/digest, approval or conditions, signed UTC time, and separate Chief Security and Chief Product signatures over that same digest.

and its Exact Approval Wording requires each named owner to sign an identical statement naming the selected option, the policy package identity and immutable version, its canonical SHA-256 digest, the jurisdictions, markets and customer/contract scope, and the effective UTC time, and attesting that a named qualified legal reviewer approved that same digest.

None of the following exists in the repository or was supplied with the owner instruction:

| Required element | Present |
| --- | --- |
| Selected option | No |
| Policy package identity and immutable version | No |
| Canonical SHA-256 digest of that package | No |
| Jurisdictions | No |
| Markets | No |
| Customer and contract scope | No |
| Material legal assumptions reviewed | No |
| Reviewer identity and capacity | No |
| Reviewer approval over that digest, with signed UTC time | No |
| Separate Chief Security and Chief Product signatures over that digest | No |

"Counsel has no objection to the proposals presently recorded" is a consultation outcome. It is not a qualified reviewer of record approving an identified immutable package for an identified jurisdiction and market scope. The repository's standard requires the latter, and the owner's own constraint 5 forbids inventing jurisdictions or markets to satisfy it.

This requirement binds every OD-011 option, including Option 1, because the Exact Approval Wording names the jurisdiction, market and contract scope for whichever option is selected.

## Effect On Dependent Decisions

- OD-012's customer-notification limb inherits this dependency, because "notification where contractually or legally required" is a determination inside the same package. It remains outstanding. The emergency-access architecture itself is ratified and integrated under ADR-019 and is unaffected.
- OD-029 and OD-030 are architectural rather than jurisdiction-dependent. Their Owner Required fields name Chief Architect, Chief Product and Chief Security, not qualified legal review. Each carries a recommended option and each is closeable under the owner's authorization without any fact this record lacks. They are not closed by this record.
- OD-033's own text states that the choice is genuinely open and that no accepted authority prefers either option; its recommendation is conditional on whether a foundation edge was intended, which the repository does not record. It requires an owner choice.
- `AC-CAP-013`'s 30-day expiry-warning criterion remains unsatisfiable until OD-029 assigns a producer for `EvidenceRetentionExpiring`.

## Production And Implementation Effect

Unchanged. Storing production customer data remains blocked under OD-011. Every retention, hold, deletion, backup, audit and configurability claim remains blocked. Under PM-REQ-010 implementation work MUST NOT begin until the foundation and required volume gates are accepted, and those gates remain open.

The prelaunch and non-production posture under the exact `retention-interim-v1` interim and its data restrictions is unchanged and remains operable.

## Change Control

This record is append-only. A correction requires a new dated record; this file MUST NOT be edited to change a recorded statement after the fact. When the missing elements are supplied, a new dated legal-approval record supersedes this one and OD-011 closes through the Owner Decision Register.
