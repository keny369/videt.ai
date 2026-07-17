# Volume I Owner Decision Record — Legal Baseline And Final Closure — 2026-07-17

## Status

- Status: Owner decisions recorded; applied to the specification by the ADR-020 integration pass
- Session Date: 2026-07-17
- Decision Owner: Product Owner (Lee Powell), exercising Chief Product, Chief Architect and Chief Security authority
- Authorizing ADR: ADR-020
- Supplements: [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md), [OWNER_DECISION_SUPPLEMENT_2026-07-17.md](OWNER_DECISION_SUPPLEMENT_2026-07-17.md), [LEGAL_REVIEW_RECORD_2026-07-17.md](LEGAL_REVIEW_RECORD_2026-07-17.md)
- Purpose: record the owner decisions closing the retention and legal cluster, event tenant identity, and the deletion-job direct-completion condition

## Why This Record Exists

The earlier records are append-only. This is a new dated record and edits none of them. [LEGAL_REVIEW_RECORD_2026-07-17.md](LEGAL_REVIEW_RECORD_2026-07-17.md) recorded that OD-011's original closure standard was unmet because it demanded repository-hosted counsel signatures, reviewer identities and package digests. The owner has now supplied the missing product and market scope, confirmed external counsel review, and narrowly amended that evidence standard. That record remains accurate as at its date and is superseded on the evidence-standard point only.

No decision here is backdated. Every decision below is dated 2026-07-17.

## Decisions Recorded

### OD-011 Retention Policy And Legal Review

Approved: **Option 1** — `retention-interim-v1` is adopted as the fixed Volume I retention baseline.

Facts recorded as given by the owner:

- The product is intended for worldwide availability.
- Its principal initial English-speaking markets are the United States, United Kingdom, Australia, New Zealand, Canada and South Africa.
- The owner employs a major external legal firm.
- External legal counsel reviewed the relevant product and retention position.
- Counsel raised no objection.
- The owner approves adoption of `retention-interim-v1` as the fixed Volume I baseline for that worldwide product and those principal markets.

Evidence model. Detailed counsel identities, privileged communications, workpapers and internal legal records remain outside the engineering repository by design. The repository states only what is true: that qualified external counsel review occurred, that no objection was raised, and that the owner approved the identified baseline for the stated scope. This record is **not** a legal opinion and MUST NOT be represented as one. No signature, reviewer identity, package attestation, legal opinion or privileged material is fabricated.

OD-011's Qualified Legal Approval element is narrowly amended under ADR-020 to accept exactly this evidence model. No other element of its approval package is relaxed.

Customer-configurable retention is not approved. Configurability remains disabled and is never inferred from a fixed policy.

### OD-012 Notification Limb

Closed insofar as it inherits OD-011. Customer notification on emergency access is determined against the same approved retention baseline and the same review record. The emergency-access architecture itself was already ratified under ADR-019 and is unchanged.

### OD-013 Event Tenant Identity

Approved: **Option 1 for every sub-decision.**

- All relevant events, Incidents and Investigations remain Organization-owned.
- Pre-Organization bootstrap activity uses the DM-REQ-013 substitution that WF-001, as the named onboarding contract, now expressly permits, confined to `BootstrapGrantIssued` and `BootstrapGrantExpired`.
- A platform-wide Incident is represented through coordinated per-Organization records.
- A cross-Organization Investigation is represented through coordinated per-Organization records.
- No `event_scope` discriminator is introduced.
- No platform-owned or cross-Organization-owned canonical event entity is introduced.
- DM-REQ-013 is not modified and the PM-REQ-009 foundation change associated with Option 2 is not performed.
- The business ability to coordinate platform-wide incidents and cross-Organization investigations is preserved and is modelled as orchestration over Organization-owned records.

Terminology is binding: canonical ownership is singular and always an Organization; coordination is a relationship between owned records and never an owner. Wording such as "platform-wide" or "cross-Organization" describes coordination and MUST NOT imply a platform-owned canonical record.

### OD-029 Evidence Retention Warning Producer

Approved: **Option 2** — WF-007 produces `EvidenceRetentionExpiring`, its Trigger extends to the Evidence Payload retention deadline, and the integrity-validation service is the authority.

### OD-030 Already-Invalid Evidence Payload Destruction

Approved: **Option 3** — path-split at the maximum instant. The LifecycleDeletionJob and its Deletion Evidence remain the Account-deletion and Organization-closure mechanism only; retention-expiry destruction is proved by a distinct `security_audit` deletion audit record; destruction stays on the existing capture cursor and 24-month maximum and is not accelerated to the accrued minimum.

### OD-033 LifecycleDeletionJob Direct Completion

Approved: **Option 3** — the direct `Queued -> Completed` edge is treated as unintended and removed by PM-REQ-009 controlled change to [../016 STATE_MODEL.md](../016%20STATE_MODEL.md). The lifecycle is asynchronous: every job enters the existing `running` state before completion, and no duplicate state is invented. No compatibility wording preserves the removed edge.

## Integration Constraints

- No price, jurisdiction, market, contractual promise, retention period, regulatory claim or customer commitment is invented. The markets above are recorded because the owner supplied them; the retention windows are those already recorded in `retention-interim-v1` and are unchanged.
- No new route, endpoint, capability, workflow, product rule, permission, error code or foundation concept is introduced except where strictly required by these decisions.
- Volume II exposure remains intentionally deferred to the Volume II baseline.

## Decisions Not Made By This Record

OD-014, OD-023, OD-027, OD-031 and OD-032 remain pending exactly as the ratification session classified them, and none blocks the Volume I freeze: OD-014, OD-023 and OD-031 are implementation-blocking with genuinely neutral interims, and OD-027 and OD-032 are Volume II-blocking.

## Change Control

This record is append-only. A correction to a decision recorded here requires a new dated record; this file MUST NOT be edited to change a decision after the fact.
