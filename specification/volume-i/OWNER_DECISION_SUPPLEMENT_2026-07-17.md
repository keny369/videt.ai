# Volume I Owner Decision Supplement — 2026-07-17

## Status

- Status: Owner decisions recorded; applied to the specification by the ADR-019 integration pass
- Session Date: 2026-07-17
- Decision Owner: Product Owner (Lee Powell), exercising Chief Product, Chief Architect and Chief Security authority
- Authorizing ADR: ADR-019 (owner ratification integration)
- Supplements: [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md)
- Purpose: record the three owner decisions that the ratification session left indeterminate, so that the integration pass can apply them without inferring owner intent

## Why This Record Exists

[RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md) is append-only by its own Change Control section: a correction to a recorded decision requires a new dated session record, and that file MUST NOT be edited to change a decision after the fact. This record is that new dated record. The ratification record is not altered.

The integration pass established that three of its twenty-one recorded decisions could not be applied as written, because each named an outcome that the Owner Decision Register reserves to owner approval and supplies nowhere in the repository:

| OD | Ratification record wording | Why it was indeterminate |
| --- | --- | --- |
| OD-012 | Resolved by replacement; seven mandatory conditions | The conditions are necessary, not sufficient. The record chose neither Option 2 nor Option 3, and OD-012's Exact Approval Wording requires an accompanying package — exact predicate, actor and approver separation, resource and action scope, immutability, event contract, Audit Evidence — that did not exist. |
| OD-022 | "Organization reactivation assurance as specified"; no option named | What was specified was the interim, under which `ReactivateOrganization` is registered and unreachable and which states that it approves no option. Ratifying it would have left a mandatory baseline workflow permanently unreachable. |
| OD-026 | "Last-administrator expiry protection as specified"; no option named | What was specified was the interim, under which the last-administrator expiry branch is unreachable exactly as built and `RoleExpiryBlocked` has no producer. |

The owner has now decided each. These decisions supersede the corresponding ambiguity in the ratification record. Every other decision in that record stands exactly as recorded there.

## Decisions Recorded

### OD-012 Emergency Cross-Organization Support Access

Approved: **Option 3** — an emergency bypass authorized outside the Incident record by a separate break-glass artifact.

Owner rationale, recorded as given: no standing privilege; a dedicated emergency-access workflow; explicit approval; fully audited; least privilege; time limited; easier to certify; and it does not pollute the Incident model. The owner expressly declined to overload the Incident aggregate with break-glass semantics.

The accompanying package required by OD-012's Exact Approval Wording is approved as follows:

- an explicit emergency predicate carried by the dedicated break-glass artifact, not by the Incident
- separate requesting and approving actors
- least privilege
- an explicit resource scope
- an explicit action scope
- immutable Audit Evidence
- a canonical emergency-access event contract
- a bounded lifetime

Option 1 is rejected: the no-break-glass posture is not ratified, and the fail-closed interim is superseded rather than approved. Option 2 is rejected on the rationale above.

Customer notification on emergency access remains subject to qualified legal review and is not approved by this record. It is the notification limb inherited from the Cluster 2 legal package under OD-011.

### OD-022 Organization Reactivation Identity Proof

Approved: **Option 1**, exactly as enumerated in the Owner Decision Register — add a fifth purpose-bound Identity Validation Receipt purpose `organization_reactivation` carrying the assurance version and `mfa_satisfied=true`, bound to Organization ID, issuer, and subject, 10-minute expiry, nonce-consumed only by the reactivation command, creating no Session.

This approval governs `organization.reactivate` only and decides nothing about the separate `account.reactivate` predicate, which is governed by OD-021 and remains Option 1 as ratified. OD-021 and OD-022 remain distinct decisions.

### OD-026 Last-Administrator Expiry Block Record And Notification Route

Approved: **Option 1**, exactly as enumerated in the Owner Decision Register — define `RoleExpiryBlockDecision` as a `decision` record, amend the effectiveness predicate so an Assignment carrying `expiry_blocked_last_admin` stays effective past `expires_at_utc` until the guard clears, and re-evaluate on each Organization authorization-epoch advance. The mandatory `RoleExpiryBlocked` route row is added, together with its required workflow and audit behaviour.

Owner rationale, recorded as given: it is explicit, deterministic, auditable, and introduces no hidden state.

As OD-026's Exact Approval Wording requires for Option 1, the owner accepts that an Assignment may remain effective beyond its stated `expires_at_utc` until the guard clears.

## Integration Constraints

These decisions authorize the integration pass to define the named contracts. They do not authorize any behaviour beyond them.

- Derive every contract detail not fixed above from already-accepted repository conventions — the existing Support Session requester/approver separation, the existing Audit Evidence and `security_audit` retention contracts, the existing notification route table, and the existing receipt and event envelope shapes. Do not mint a new convention where an accepted one applies.
- The emergency-access bounded lifetime is a numeric commercial or operational value. Under the ratification record's commercial clarification it is versioned policy configuration bound to an approved policy version, not an immutable Volume I constant.
- OD-012 Option 3 adds a capability and a workflow. That is authorized by this record and by ADR-019, and by neither ADR-017 nor ADR-018, whose constraint sets authorize no new capability.
- Customer notification for emergency access remains outstanding pending legal review and MUST NOT be specified as approved behaviour.

## Decisions Not Made By This Record

This record decides nothing about, and does not resolve:

- OD-011, OD-029, OD-030, OD-033, and the notification limb of OD-012 — the retention and deletion legal package, which additionally requires the prerequisite owner input recorded in the ratification session before legal review can begin
- OD-013 event tenant identity, which requires an explicit Chief Architect decision and is not inferred here
- OD-014, OD-023, OD-027, OD-031, OD-032, which remain classified exactly as the ratification record classifies them

## Change Control

This record is append-only. A correction to a decision recorded here requires a new dated session record; this file MUST NOT be edited to change a decision after the fact.
