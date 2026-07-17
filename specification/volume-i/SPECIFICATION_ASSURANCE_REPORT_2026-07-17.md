# Volume I Specification Assurance Report — 2026-07-17

## Status

- Status: Accepted assurance record for the `v1.4-volume-i-ratified-prelegal` milestone
- Date: 2026-07-17
- Owner: Chief Architect
- Milestone: Volume I ratified pre-legal baseline
- Authorizing ADR: ADR-019

## Purpose

Record why a reviewer should trust Volume I at this milestone, without reconstructing the correction history from commits and ADRs. This report asserts no normative behaviour. Where it and a normative document disagree, the normative document governs.

## Scope Of The Ratification Package

Twenty-one owner decisions were integrated across the foundation, Volume I and the retained Volume II drafts as one change set.

| Class | Count | Decisions |
| --- | --- | --- |
| Ratified as specified | 11 | OD-001, OD-002, OD-003, OD-005, OD-006, OD-007, OD-008, OD-009, OD-010, OD-019, OD-021 |
| Resolved by owner decision | 5 | OD-015, OD-017, OD-018, OD-024, OD-025 |
| Resolved by replacement | 3 | OD-012, OD-016, OD-020 |
| Resolved by supplemental owner decision | 2 | OD-022, OD-026 |

Sources of authority: [RATIFICATION_SESSION_2026-07-17.md](RATIFICATION_SESSION_2026-07-17.md) and [OWNER_DECISION_SUPPLEMENT_2026-07-17.md](OWNER_DECISION_SUPPLEMENT_2026-07-17.md). Both are append-only audit records. Neither confers authority by itself; ADR-019 is the controlled change that made these decisions normative.

Four PM-REQ-009 controlled foundation changes landed in the same change set: the Document row and the Session row of [../016 STATE_MODEL.md](../016%20STATE_MODEL.md), a new EmergencyAccessGrant row in the same document, and the WF-011 coverage row of [../018 OBSERVABILITY.md](../018%20OBSERVABILITY.md). Three of the four were not named by the ratification session; they were established from the repository's own governance requirements and are recorded in ADR-019.

## Scope Adjustments Discovered During Integration

The ratification session is authoritative for what was decided. The repository is authoritative for the obligations each decision creates. Five expansions were required and recorded rather than absorbed silently.

1. OD-012 was omitted from the integration brief's list of twenty; the session recorded twenty-one. It is resolved by replacement and was integrated.
2. OD-025 is a controlled foundation change to 018 OBSERVABILITY.md, per its own ADR Threshold. OD-024 is not a foundation change and is not recorded as one.
3. OD-016 is a controlled foundation change to the 016 STATE_MODEL.md Session row under SM-REQ-010.
4. OD-012 Option 3 requires an EmergencyAccessGrant state machine, because a break-glass artifact with a bounded lifetime and revocation is stateful under SM-REQ-001 and SM-REQ-002.
5. Three decisions — OD-012, OD-022 and OD-026 — could not be integrated as the session recorded them. OD-012's approval wording required an accompanying package that did not exist; OD-022 and OD-026 were recorded as ratified "as specified" without naming an option, where what was specified was an interim that approved no option and left the behaviour unreachable. Integration halted rather than infer owner intent, and the owner decided all three explicitly.

## Defects Found And Corrected

These are specification defects, not editorial ones. Each would have produced behaviour inconsistent with a ratified decision had implementation begun from the prior text.

| Defect | Nature | Correction |
| --- | --- | --- |
| WF-005 lacked OD-018's guard | The ratified single-initial-orchestration rule existed only in the Owner Decision Register. WF-005 guarded on existence of a promoted Evaluation, which is a different condition from pending-or-running. | Precondition, `Queued -> Running` re-check, and `F1-DOMAIN-409 / initial_evaluation_already_running` added with severity, retryability, recovery and concurrency behaviour. |
| WF-007 lacked OD-017's outcome | The workflow carried fingerprint, collision and preimage language but never stated that the second Issue is not created. The document looked complete while omitting the behavioural guarantee. | Full collision contract added at the Issue-derivation step. |
| `documents` CHECK admitted removed states | The schema constraint still enumerated `quarantined` and `retired` as forward-compatible migration shape after the canonical model removed them. Implementation could have persisted data violating the specification. | Constraint reduced to `('discovered','ingested','parsed','indexed')`. |
| Secondary artifacts asserted a superseded foundation | Fourteen negative assertions across Volume II, the schema and Volume I stated that behaviour was unreachable, unavailable or unresolved because of decisions since ratified. `APPLICATION_LAYER.md` asserted a foundation fact the foundation change had made false. | Each rewritten to reference the canonical contract that now governs, rather than deleting the negative statement. |
| Ratified decisions described as pending | Interim policy identifiers and disclaimer sentences survived for decisions the owner had approved. | Eleven identifiers renamed to their approved Version 1 identity across 56 references; disclaimers removed only where the owning decision is ratified. |
| ADR-019 misstated the acceptance count | The ADR predicted the acceptance identifier count would exceed 97. Re-running traceability proved it remains exactly 97. | ADR-019 corrected to state the actual result and the reason: new behaviour binds to existing capabilities and workflows. |

## Validation Activities Performed

Nine validators were run against the complete corpus. Each was first subjected to a negative control: a known defect of the class it detects was injected into a copy, and the validator was required to catch it. A validator that cannot fail is not evidence. All nine passed their negative control.

| Validator | Negative control | Result on corpus |
| --- | --- | --- |
| Local link resolution | Injected nonexistent target | 0 findings |
| Markdown table shape | Injected ragged row | 1 finding, pre-existing at HEAD, documented below |
| Removed events absent | Injected a removed event reference | 0 findings |
| Owner decision status integrity | Flipped a ratified status to pending | 0 findings |
| Acceptance integrity | Deleted an acceptance row | 0 findings; 97 defined, 0 duplicates, 97 with planned test types |
| No dangling acceptance references | Injected an undefined acceptance ID | 0 findings |
| Foundation free of removed events | Injected a removed event into 018 | 0 findings |
| Document enum reduced | Restored removed enum members | 0 findings |
| Ratified interim identifiers renamed | Reverted an approved identifier | 0 findings |

Completeness chain: all 21 ratified decisions have an observable consequence in a normative contract, at least one defined acceptance identifier, at least one canonical requirement, and a planned verification method. 21 of 21 chains complete, 0 gaps.

Accidental-expansion review across the full diff: 0 API routes, 0 capabilities, 0 workflows, 0 product rules, 0 acceptance identifiers, 0 error codes and 0 test types added. Every new permission traces to OD-012, OD-016 or OD-020.

An earlier verification pass in this programme produced a false green because of a defective checker. It was found, the checker was corrected, and the defects it had concealed were fixed. The final verification is more credible than the intermediate one for that reason, and the negative-control discipline above exists because of it.

## Known Unresolved Gates

Volume I remains BLOCKED. Neither gate is resolvable by specification work, and the absence of sign-off is not approval.

- Retention and deletion legal package. Affects OD-011, OD-029, OD-030, OD-033, and the customer-notification limb of OD-012. OD-011 requires qualified legal review by its own terms and no reviewer has signed. A prerequisite owner input is required before legal review can begin: approved jurisdictions, markets, and customer and contract scope. The repository contains no jurisdiction, customer-type, contract-template or data-category information. This is an owner input, not a legal one. `AC-CAP-013`'s 30-day expiry-warning criterion is currently unsatisfiable and must be reconciled or changed.
- OD-013 event tenant identity. The canonical event envelope requires `organization_id`, which cannot truthfully represent pre-Organization bootstrap events, platform-scope Incidents, or cross-Organization Investigations. An explicit Chief Architect decision is required. No option may satisfy it by inferring a synthetic platform tenant. `UPSTREAM-V1-EVENT-SCOPE-001` remains a genuine blocker.

Production release with real customer data remains blocked wherever legal approval is required. Under PM-REQ-010, implementation work MUST NOT begin until the foundation and required volume gates are accepted.

## Known Intentional Deferrals

These are deliberate boundaries of this package, not omissions.

- Volume II exposure. Ten upstream blockers were retired because their upstream decision is now resolved. Their corresponding API surface, transport contract, routing, serialization and application-layer exposure remain intentionally deferred until the Volume II baseline. This package ratifies the semantic contract only and defines no route, endpoint, command, serializer or transport.
- Three upstream blockers remain genuine and untouched: `UPSTREAM-V1-EVENT-SCOPE-001` (OD-013), `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` (OD-023), `UPSTREAM-V1-PROJECT-LIFECYCLE-003` (OD-014).
- Ten owner decisions remain pending with deterministic interim behaviour: OD-011, OD-013, OD-014, OD-023, OD-027, OD-029, OD-030, OD-031, OD-032, OD-033. OD-031 is implementation-blocking and is not part of the release-blocking legal package.
- Twelve interim contracts registered under ADR-018 have no owning owner decision. This ratification did not resolve them, so they retain their interim identity. `onboarding-interim-v1` is a composite contract that no single owner decision gates and was not promoted.
- Sign-out-everywhere is deferred under OD-016. Read authority over security, administrative and internal operational objects remains deny-by-default pending a separate owner decision under OD-020.

## Unrelated Defect Documented, Not Corrected

A ragged Markdown table exists at `specification/volume-ii/API_CONTRACTS.md` in the extra-schemas section. It is present at the pre-integration baseline `3e5df2f` and is unrelated to the ratification. It was not corrected here because it is not a mechanically forced integration defect, and correcting it would expand this package. It should be addressed by a separate change.

## Readiness Assessment

Ready for legal review. The retention, deletion and notification package can be submitted once the owner supplies the prerequisite jurisdictions, markets, and customer and contract scope, which the repository does not currently contain.

Ready for architectural review of OD-013. The architectural recommendation on record is an explicit `event_scope` discriminator with conditional tenant identity, avoiding synthetic platform tenants. Any option narrowing the universal `organization_id` requirement is a foundation change to DM-REQ-013 requiring PM-REQ-009 and an ADR, and additionally requires removing two frozen sentences that would otherwise forbid it.

Not ready for implementation. PM-REQ-010 gates implementation on accepted foundation and volume gates, and two gates remain open.

Not a freeze. This milestone is a reviewable pre-legal baseline. The successor Volume I freeze is a separate artifact and MUST NOT be created while either gate remains open.
