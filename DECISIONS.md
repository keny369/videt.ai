# Architecture Decision Records

This file is the canonical ADR registry until ADR entries are split into individual files.

## ADR-001: Canonical Source Of Truth

Status: Accepted
Date: 2026-07-15

Decision:
The repository itself is the single source of truth for product architecture. No parallel private specifications are authoritative.

Context:
Project quality depends on one canonical definition per concept and zero ambiguity about which document governs.

Consequences:

- all architecture updates must be committed in this repository
- duplicate definitions must be consolidated or removed
- references must point to canonical documents

## ADR-002: Documentation-First Delivery

Status: Accepted
Date: 2026-07-15

Decision:
No implementation is started until architecture specifications are complete for all required domains.

Context:
Rework risk is highest when implementation precedes architecture.

Consequences:

- roadmap prioritizes manual completion over prototyping
- implementation tasks depend on architecture acceptance criteria

## ADR-003: Product Category And Positioning

Status: Accepted
Date: 2026-07-15

Decision:
Project F1 is positioned as a Discoverability Intelligence Platform, not a generic SEO audit tool.

Context:
The product must unify traditional search discoverability and AI answer discoverability in one operating model.

Consequences:

- messaging, product scope and capability design center on discoverability outcomes
- score model includes both search and AI discoverability dimensions

## ADR-004: Non-Invasive Remediation Model

Status: Accepted
Date: 2026-07-15

Decision:
The platform generates implementation-ready remediation artifacts but does not directly modify customer production systems.

Context:
Direct write access increases security and liability burden and slows enterprise trust.

Consequences:

- platform outputs patches, prompts, snippets and task guides
- no automatic direct deployment in early architecture scope

## ADR-005: Initial Target Architecture Stack

Status: Accepted
Date: 2026-07-15

Decision:
Primary implementation target remains Rails 8 with PostgreSQL, Hotwire, Tailwind, Redis and Sidekiq.

Context:
The constitution already establishes this stack and it aligns with team execution constraints.

Consequences:

- downstream architecture documents optimize for this stack
- deviations require explicit ADR updates

## ADR-006: Immutable Foundation Layer

Status: Accepted
Date: 2026-07-15

Decision:
Documents `specification/000` through `specification/020` are established as the immutable foundation layer of the Product Architecture Manual.

Context:
Later volumes require stable, shared definitions and principles to avoid drift and contradictory architecture.

Consequences:

- all subsequent chapters must reference foundation documents instead of redefining core concepts
- changes to foundation documents require ADR updates and dependent chapter updates in the same pass
- foundation documents govern terminology, principles, decision process and documentation standards

## ADR-007: Sequencing Gate For Later Volumes

Status: Accepted
Date: 2026-07-15

Decision:
Product, UX, Database and API specifications beyond current Volume I scope are blocked until Volume I acceptance criteria are met.

Context:
Foundational architecture must be coherent and accepted before deeper domain specialization to avoid structural rework.

Consequences:

- roadmap milestones include explicit start gates for later volumes
- project state tracks gate compliance as an active control
- any exception requires explicit ADR with rationale and risk plan

## ADR-008: Foundation Dependency Model

Status: Accepted
Date: 2026-07-15

Decision:
The canonical dependency model is established from foundation layer 000-020 through implementation, and upstream constitutional documents MUST NOT silently depend on downstream implementation choices.

Context:
Dependency ambiguity creates contradictory specifications and rework.

Consequences:

- dependency graph is mandatory in manual control documents
- downstream layers MAY depend on upstream layers only
- sequencing gates are enforced through roadmap and review controls

## ADR-009: Test-Driven Development Policy

Status: Accepted
Date: 2026-07-15

Decision:
TDD is the default implementation discipline, with failing-test-first behavior required for production changes.

Context:
Behavior-first verification is required to preserve correctness and prevent regression drift.

Consequences:

- engineering principles include mandatory Red, Green, Refactor policy
- defect fixes require reproducing failing tests before code changes
- merge gates require passing test suite with exception governance for rare cases

## ADR-010: Documentation-As-Code Policy

Status: Accepted
Date: 2026-07-15

Decision:
Documentation is treated as governed system artifact with deterministic generation and mandatory traceability.

Context:
Separate narrative and implementation truths create operational and governance failure.

Consequences:

- documentation standards include mandatory documentation-as-code rules
- documentation drift is treated as build or review failure
- generated documentation is source-controlled through canonical generators

## ADR-011: Architecture Fitness-Function Policy

Status: Accepted
Date: 2026-07-15

Decision:
Architecture principles are enforced through a canonical fitness-function catalog with owners, gates, and exception process.

Context:
Unmeasured principles degrade over time and fail to protect architecture boundaries.

Consequences:

- fitness functions become release-governing controls
- unresolved numeric thresholds use provisional gates with deadlines
- exception handling requires bounded ADR-backed governance

## ADR-012: Foundation Baseline Version 1.0 And Controlled Change

Status: Accepted
Date: 2026-07-15

Decision:
Foundation 000-020 is declared baseline version 1.0 and immutable except through controlled change.

Context:
Foundational stability is required before downstream domain elaboration.

Consequences:

- normative foundation changes require ADR and impact mapping
- downstream affected specifications, tests, diagrams, schemas, and contracts must be identified
- compatibility and migration assessments are mandatory when applicable

## ADR-013: Canonical Diagram Authority Model

Status: Accepted
Date: 2026-07-15

Decision:
Each required architecture view has one canonical source diagram file in `diagrams/`, linked by foundation documents.

Context:
Conflicting diagram sources undermine architecture consistency.

Consequences:

- one authoritative source exists for each required architecture view
- duplicate boundary diagrams are prohibited
- diagram updates require linked specification updates in same change set

## ADR-014: Foundation Section Mapping Registry

Status: Accepted
Date: 2026-07-15

Decision:
Foundation documents that use stricter or legacy section structures are governed through a centralized section mapping registry in `specification/FOUNDATION_SECTION_MAPPINGS.md`.

Context:
Foundation policy requires 17 required sections or equivalent mapping. Several accepted baseline documents use equivalent structures that were not explicitly mapped.

Consequences:

- section conformance is auditable without forcing stylistic rewrites
- mapped documents must provide rationale where sections are non-applicable
- mapping registry must be updated in the same change set as mapped document changes

## ADR-015: Canonical Event Naming Alignment

Status: Accepted
Date: 2026-07-15

Decision:
Canonical domain and observability event names follow PascalCase and the domain event list in `specification/011 DOMAIN_MODEL.md` is treated as minimum cross-context coverage, with additional lifecycle and failure events defined by state and error models.

Context:
Event naming drift appeared across domain, state, and observability documents through mixed naming styles and incompatible event vocabularies.

Consequences:

- event terminology is normalized across domain, state, and observability docs
- observability coverage tables can reference canonical event vocabulary consistently
- downstream contracts and tests inherit a stable naming rule

## ADR-016: Intra-Foundation Dependency Precedence

Status: Accepted
Date: 2026-07-15

Decision:
Bidirectional cross-references among foundation documents are permitted as semantic links, but authority precedence remains fixed by the manual hierarchy and MUST NOT be inferred from dependency direction.

Context:
Architecture review identified dense cross-reference cycles within the foundation layer that could be misread as precedence inversion.

Consequences:

- dependency cycles do not redefine constitutional authority ordering
- contradiction resolution remains ADR-governed and hierarchy-governed
- review checks must assess contradictions instead of assuming topological dependency order

## ADR-017: Controlled Volume I Defect Corrections After Freeze

Status: Accepted
Date: 2026-07-16
Owner: Chief Architect
Reversibility: Difficult-to-reverse once downstream implementation or persisted data depends on the corrected contracts; change remains possible only through controlled, versioned Volume I replacement.

Decision:
Correct only the six demonstrated frozen-baseline defects DEF-V1-001 through DEF-V1-006 in the existing foundation, Volume I, diagram, acceptance, traceability, and control artifacts. The corrected behavior is:

- Mailgun dispatch provides at-least-once application attempt processing with local attempt deduplication, explicit provider-acceptance uncertainty, no automatic resend while uncertain, read-only reconciliation, acknowledged administrative replay, and no provider exactly-once claim
- existing Account sign-in uses a purpose-bound managed-identity receipt, exact Organization selection, lifecycle/assurance checks, current authorization context, deterministic logical destination, concurrent independent Sessions, and no Session refresh or F1 credential lockout
- reassessment remains manual and is additionally scheduled only by an active enabled Project policy with explicit anchored cadence, exact slot identity, conflict suppression, inactive-scope skip, and outage coalescing
- WF-001 self-service alone creates and activates the baseline BillingEntity and links its Plan Assignment without an external provider call; invoice/payment detail remains outside the core under the OD-008 interim
- Evidence vocabulary separates the Evidence record, Type, Source, Payload, Provenance, Classification, Measurement Evidence, Verification Evidence, and Audit Evidence; `operator_attestation` is recognized but unavailable and `operator_submission` is invalid
- CAP-019 inherits the accepted deterministic structured-only dashboard/history baseline and cannot imply narrative or an AI-provider call

Context:
Volume II discovery proved that the frozen wording permitted or required divergent, unsafe, or technically impossible implementations. ADR-012 requires an ADR-backed controlled change when normative foundation state, error, security, lifecycle, observability, or terminology contracts change after freeze. These corrections remove defects without adding a product capability or reopening unrelated behavior.

Constraints:

- external Mailgun acceptance cannot be made provider-idempotent across a lost response
- frozen Volume I behavior may change only to correct demonstrated defects or incorporate approved owner decisions
- the six corrections must remain deterministic, testable, provider/framework neutral where Volume I requires, and traceable through existing acceptance artifacts
- no software, physical API, database migration, new capability, or additional Volume II document is authorized

Options Considered:

1. Preserve `v1.2-volume-i-frozen` unchanged and let Volume II choose implementation behavior. Rejected because it preserves an impossible delivery guarantee and five observable behavior forks.
2. Apply only DEF-V1-001 through DEF-V1-006 through existing artifacts and align the two retained Volume II drafts. Chosen.
3. Reopen Volume I for a broad architecture-driven hardening pass. Rejected because it exceeds demonstrated-defect scope and would weaken the freeze boundary.

Evaluation Summary:
Option 2 is the only option that makes every listed contract technically achievable and deterministic while preserving unrelated frozen behavior, existing capabilities, owner-decision boundaries, and the Volume II pause. It changes more canonical documents than option 1 only because state, error, lifecycle, security, terminology, acceptance, and traceability must express one behavior; it changes materially less scope than option 3.

Chosen-Option Rationale:
The narrow correction set removes known implementation forks at their canonical owners, supplies executable interim behavior without inventing commercial values or provider guarantees, and gives Volume II one authoritative behavioral input. The associated compatibility cost is accepted because leaving the defects frozen would force noncompliant or divergent systems.

Consequences:

- the corrected Volume I and affected foundation documents must be committed and receive a successor frozen-baseline tag before Volume II resumes
- the two retained Volume II drafts may only align references and constraints to these corrections during this pass
- no software, physical endpoint, migration, provider integration, or additional Volume II architecture artifact is authorized by this decision
- future replacement of any corrected behavior requires the normal controlled Volume I change process

Risks And Mitigations:

- acknowledged replay or provider behavior can still produce duplicate external email; duplicate-tolerant user wording and idempotent product-action references contain the impact
- scheduled-recovery eligibility depends on retained due-time and current scope-state history; exact Audit Evidence and acceptance fixtures make missing history a detectable nonadmission rather than an inferred run
- canonical Evidence aliases could be reintroduced downstream; terminology scans and schema/contract tests prohibit them
- reserved BillingEntity states could be mistaken for executable states; state, error, workflow, acceptance, and retained-schema notes explicitly deny every baseline entry/exit except active-to-closed

Compatibility And Migration:
No shipped software or customer data exists to migrate. Existing document references and the two retained uncommitted Volume II drafts are aligned in this change; future wire/schema versions must inherit the corrected contracts rather than translate the rejected behavior.

Review Checkpoint:
Revalidate this decision when the successor frozen tag is created and again at the first Volume II architecture-baseline review, no later than 2026-08-27, for contradiction, unintended scope expansion, and implementability against the accepted fixtures.

## ADR-018: RC1 Release-Candidate Correction Programme

Status: Accepted
Date: 2026-07-16
Owner: Chief Architect
Reversibility: Reversible while no implementation depends on the corrected contracts; the identifier and precedence corrections are difficult to reverse once downstream artifacts cite them.

Decision:
Authorize a controlled correction programme against the defects recorded by the RC1 release-candidate review of Volume I, and defer the successor Volume I freeze until that programme completes and an RC2 regression audit returns no Critical or High finding. The programme corrects only demonstrated defects. It corrects in place only where existing authority already compels exactly one conformant answer, and registers an owner decision with deterministic fail-closed interim behaviour wherever the behaviour is genuinely unresolved.

Context:
The RC1 review recorded defects across four classes: governance statements that contradict the constitution or misidentify the baseline; foundation content that downstream artifacts rely on but cannot cite; product behaviour that no command surface can reach; and product behaviour whose specification admits more than one observable outcome. Volume II discovery independently recorded thirteen of the behavioural defects as upstream blockers and correctly declined to resolve them downstream. Three findings raised by the review were adversarially refuted and are expressly out of scope.

Authority And Precedence:
This ADR does not supersede any unchanged foundation requirement and MUST NOT be read as doing so. Under PM-REQ-003 the foundation layer outranks the ADR registry, and under 011 DOMAIN_MODEL.md an accepted ADR authorizes the PM-REQ-009 controlled-change process but does not by itself change a foundation requirement. Where this programme changes foundation content, the change is made in the foundation document itself with its impact mapping in the same change set, exactly as ADR-006 and ADR-012 require.

This ADR also records a governance defect in the repository's own history: commit `1e57f47` added the normative "Accepted Volume I Dashboard And History Boundary" section to `specification/008 AI_PRINCIPLES.md` and edited six Volume I documents with no ADR entry in that change set, contrary to ADR-006, ADR-012, and ROADMAP Gate D. That content is not reopened on its merits; it is brought under ADR governance here, and the identifiers `AI-REQ-023` and `AI-REQ-024` now make it citable.

Options Considered:

1. Freeze Volume I at `v1.3-volume-i-corrected` and let Volume II resolve the open ambiguities. Rejected: Volume II states that the ambiguities are product-behaviour choices it must not make, and a freeze would convert thirteen known implementation forks into permanent contract.
2. Correct every defect by architectural inference so the baseline reads as complete. Rejected: nineteen of twenty analysed behavioural defects admit more than one conformant answer once adversarial challenge is applied to each forced verdict, so inference would silently make product decisions and reproduce the failure the review exists to catch.
3. Correct what authority compels, register what it does not, and defer the freeze. Chosen.
4. Reopen Volume I for a broad redesign. Rejected: it exceeds demonstrated-defect scope and would discard behaviour that the review confirmed is sound, including complete acceptance and traceability coverage.

Chosen-Option Rationale:
Option 3 is the only option that leaves no defect silently unresolved while making no product decision on the owner's behalf. It preserves the verified-sound surface of Volume I — 97 individually asserted acceptance criteria, complete identifier traceability, the Evidence vocabulary, and the deterministic no-AI-narrative boundary — and confines change to demonstrated defects and their required alignment.

Consequences:

- Volume I is not frozen and `volume-i/INDEX.md` no longer claims that it is; its acceptance gate records a conditional pass for behavioural content and a fail for freeze readiness
- `v1.3-volume-i-corrected` at `5d725fa` is the current baseline; `v1.2-volume-i-frozen` and `v1.1-implementation-ready` are superseded history and are not implementation baselines
- `specification/008 AI_PRINCIPLES.md` carries stable `AI-REQ-001` through `AI-REQ-025` identifiers, appears in the foundation traceability matrix, and is a declared Volume I dependency; no AI policy, wording, modal force, or capability changes
- owner decisions registered by this programme carry deterministic fail-closed interim behaviour and exact blocking impact; each remains a release gate until its named owners approve it
- Volume II remains permitted for unblocked behaviour under Gate C and remains blocked from an architecture baseline and broad implementation until the upstream corrections land
- no software, physical endpoint, migration, or provider integration is authorized by this decision

Risks And Mitigations:

- registering rather than resolving behaviour leaves genuine product gates open; each registration states its exact blocking impact so no gate can be passed by inference
- fail-closed interim behaviour can disable an operationally useful path, notably emergency cross-tenant support access; the interim is recorded as a decision gate rather than a permanent design so the owner can restore it deliberately
- correcting authority precedence changes how future ADR/foundation conflicts resolve; the corrected ordering restates PM-REQ-003 verbatim rather than inventing an ordering
- adding identifiers to a foundation document could be mistaken for a policy change; the identifier convention section states explicitly that it adds identifiers only

Compatibility And Migration:
No shipped software or customer data exists to migrate. All 97 acceptance identifiers, CAP-001 through CAP-025, WF-001 through WF-018, PRULE-001 through PRULE-046, and PR-REQ-001 through PR-REQ-030 are preserved without renumbering. Behavioural corrections either restore an outcome that existing authority already compelled or fail closed pending an owner decision; none silently replaces accepted behaviour.

Review Checkpoint:
Revalidate at the RC2 regression audit. A successor Volume I freeze requires RC2 to return no Critical or High finding and every registered owner decision to state an unexpired gate. Reassess no later than 2026-08-27.

## ADR-019: Owner Ratification Integration And Volume I Pre-Legal Baseline

Status: Accepted
Date: 2026-07-17
Owner: Chief Architect
Reversibility: Low for the three foundation changes and for the decisions that remove behaviour, because downstream artifacts and any successor freeze cite the corrected contracts; medium for the added contracts while no implementation depends on them. No emitted event, persisted record, or customer datum exists to unwind.

Decision:
Integrate the owner decisions recorded on 2026-07-17 into the foundation, Volume I and the retained Volume II drafts as one atomic change set, and declare the result the Volume I ratified pre-legal baseline rather than the final Volume I freeze. Twenty-one decisions are applied. Four controlled foundation changes are made under PM-REQ-009. The retention and deletion legal package and OD-013 remain outstanding and continue to block production use and the final freeze.

Context:
The RC1 neutrality review found that 25 of 33 owner-decision interims already implemented one of their own stated options while the Owner Decision Register described them as pending. Volume I was therefore decided-but-unratified rather than under-designed. The owner disposed of every release-blocking decision in the 2026-07-17 session recorded at [specification/volume-i/RATIFICATION_SESSION_2026-07-17.md](specification/volume-i/RATIFICATION_SESSION_2026-07-17.md), and supplied the three decisions that session left indeterminate in [specification/volume-i/OWNER_DECISION_SUPPLEMENT_2026-07-17.md](specification/volume-i/OWNER_DECISION_SUPPLEMENT_2026-07-17.md).

Decision recording and normative integration are distinct acts. Both records are audit evidence and confer no authority by themselves; until this ADR's change set landed, the Owner Decision Register remained the operative text and continued to show these decisions as pending. This ADR is the controlled change that makes them normative.

Authority And Precedence:
This ADR does not supersede any unchanged foundation requirement and MUST NOT be read as doing so. Under PM-REQ-003 the foundation layer outranks the ADR registry. Where this change set changes foundation content, the change is made in the foundation document itself with its impact mapping in the same change set, exactly as ADR-006 and ADR-012 require. Four such changes are recorded below.

The ratification records are authoritative for what was decided. The repository — the Owner Decision Register, PM-REQ-009, the ADR thresholds, and the foundation documents — is authoritative for the integration obligations each decision creates. Where a recorded decision necessarily amended a higher-order artifact that the session did not name, the repository governed and the scope expanded accordingly. Four such expansions are recorded under Scope Adjustments below.

Controlled Foundation Changes Under PM-REQ-009:

1. OD-015 — [specification/016 STATE_MODEL.md](specification/016%20STATE_MODEL.md), Document row. The `quarantined` and `retired` Document states and the `DocumentQuarantined` and `DocumentRetired` events are removed. The canonical Document lifecycle becomes `discovered -> ingested -> parsed -> indexed`. The Evidence quarantine model is a separate state machine and is unaffected. Legal-retention behaviour is not absorbed into the Document state machine and remains governed by the outstanding legal package. Basis: the previous row admitted two states and named two events that no Volume I permission, command, actor, service authority, job or event could produce, and assigned Document transitions to an undefined "Data Lifecycle Context" naming two competing retirement producers.

2. OD-025 — [specification/018 OBSERVABILITY.md](specification/018%20OBSERVABILITY.md), WF-011 row of the Critical Workflow Observability Coverage table. The previous requirement was that "an admitted scheduled or manual run emits one provenance-complete `ReassessmentTriggered`". `ReassessmentTriggered` is removed as a canonical domain event and that clause is amended. This foundation change was not named by the ratification session; OD-025's own ADR Threshold in the Owner Decision Register states that resolution amends this coverage row through the PM-REQ-009 controlled foundation change under ADR-012 for every option, and the repository governed. Observability of reassessment is preserved, not weakened: no replacement event is invented, and coverage is carried entirely by already-accepted mechanisms — `ReassessmentScheduleEvaluated` for every ordinary or latest-coalesced due slot, the manual command's Audit Evidence under SM-REQ-004 for manual provenance, `EvaluationStarted` for the run that reaches Evaluation creation, `ReassessmentCompleted` for successful replacement, and `ReassessmentFailed`, `ReassessmentCanceled` and the linked Entitlement Decision for the non-executing branches. Trigger provenance — `trigger_kind`, policy identity, version and content hash, slot number and due time — is retained on the Reassessment Result record and its Audit Evidence rather than on a dedicated event. The previously unresolvable question of whether an Entitlement-blocked branch emits a trigger event does not arise, because no trigger event exists.

3. OD-016 — [specification/016 STATE_MODEL.md](specification/016%20STATE_MODEL.md), Session row. The row's trigger clause admitted `revoked` on "explicit security revocation" while naming a bounded context rather than an actor or permission as its Transition Authority, and Volume I defined no `session.*` permission. The row is amended to name the authority for both ratified paths and to admit user-initiated termination of the acting Session. This foundation change was not named by the ratification session; it is a transition-authority change requiring ADR governance under SM-REQ-010, and the repository governed. No new Session state and no new transition edge is introduced: `active`, `revoked` and `expired` and the existing `active -> revoked` edge are unchanged. The rule that concurrent Sessions do not revoke one another is preserved.

4. OD-012 — [specification/016 STATE_MODEL.md](specification/016%20STATE_MODEL.md), new EmergencyAccessGrant row. The owner approved emergency access under a dedicated break-glass artifact with a bounded lifetime and revocation, which makes that artifact stateful; SM-REQ-001 and SM-REQ-002 therefore require it to carry a canonical state machine, exactly as LegalHold does. The row is added with states `pending`, `active`, `rejected`, `revoked`, `expired`, modelled on the accepted Legal Hold two-person request-and-approve pattern, and introduces no new authorization mechanism. This foundation change was not named by the ratification session; it follows necessarily from OD-012 Option 3, and the repository governed. The Incident aggregate is not amended: its field list remains exhaustive and carries no break-glass semantics, which is the substance of the owner's rejection of Option 2.

Decisions Applied:

Ratified as specified, with the approved option as recorded — OD-001 Option 2 (DNS TXT and HTTPS file ownership verification); OD-002 Option 1 (equal weighting of applicable score pillars as the Version 1 baseline); OD-003 Option 3 (numeric confidence `0.0000`–`1.0000` with displayed Low/Medium/High bands); OD-005 (QA and operational thresholds, subject to the commercial clarification); OD-006 Option 3 as implemented (entitlement enforcement semantics, subject to the commercial clarification); OD-007 Option 1 (one-directional Citation: exactly one AIResponse, exactly one Evidence, no direct Evaluation write link); OD-008 Option 2 (BillingEntity core with invoice and payment detail adapter-level); OD-009 Option 2 (disputed and review-required Issues excluded from published scoring and prioritisation until eligible); OD-010 Option 1 (the seven-check baseline catalogue, thresholds, impact mappings and measurement contracts); OD-019 Option 1 (the metered-read unit, subject to the commercial clarification); OD-021 Option 1 (Account reactivation proves only the acting administrator's current MFA-satisfied Session, restores state, creates no Session, consults no target identity).

OD-002 supersedes the earlier recommendation for a weighted distribution. Any later weighting change MUST use a new scoring-policy version and MUST NOT reinterpret historical Score Snapshots. OD-021 was ratified as Option 1 knowingly; it is approved behaviour and is not a neutral interim.

Resolved by owner decision — OD-015 (Document lifecycle simplification, above); OD-017 (on an Issue fingerprint collision the second Issue MUST NOT be created and the affected Evaluation fails closed on the existing canonical collision outcome and telemetry, with no silently persisted duplicate variant); OD-018 (only one initial Evaluation orchestration may exist per Project, and a second root Crawl request that would initiate another while one is pending or running is rejected deterministically, reusing the accepted WF-011 single-orchestration guard); OD-024 (`ComparisonGenerated` removed; comparison behaviour remains and emits no domain event); OD-025 (`ReassessmentTriggered` removed, above).

OD-024's and OD-025's approved outcomes are recorded as owner decisions rather than as option numbers. OD-025's outcome is not among that decision's three enumerated options, all of which retained the event; assigning it an option number would falsify the record.

Resolved by replacement — OD-012 Option 3 (emergency access via a dedicated break-glass workflow and artifact outside the Incident aggregate, with an explicit predicate, separate requesting and approving actors, least privilege, explicit resource and action scope, immutable Audit Evidence, a canonical emergency-access event contract and a bounded lifetime; no standing cross-tenant access; the no-break-glass posture is superseded, not ratified); OD-016 Option 3 (every authenticated user may terminate their current Session; authorized security personnel may revoke one identified Session; sign-out-everywhere remains deferred); OD-020 Option 1 (explicit read rows added to the Permission Baseline for Organization home data, Project, Source, Crawl, Evaluation, Notification inbox and Export enumeration, mirroring their existing mutation permissions).

Resolved by supplemental owner decision — OD-022 Option 1 (a fifth purpose-bound Identity Validation Receipt purpose `organization_reactivation`, carrying the assurance version and `mfa_satisfied=true`, bound to Organization ID, issuer and subject, 10-minute expiry, nonce-consumed only by the reactivation command, creating no Session); OD-026 Option 1 (`RoleExpiryBlockDecision` as a `decision` record, the effectiveness predicate amended so an Assignment carrying `expiry_blocked_last_admin` stays effective past `expires_at_utc` until the guard clears, re-evaluated on each Organization authorization-epoch advance, with the mandatory `RoleExpiryBlocked` route row added).

The ratification session recorded OD-022 and OD-026 as ratified "as specified" without naming an option. What was specified in each case was an interim that expressly approved no option and under which the behaviour was unreachable — `ReactivateOrganization` registered and denied by deny-by-default, and the last-administrator expiry branch unreachable exactly as built. Ratifying either as written would have left a mandatory baseline workflow permanently unreachable. The owner therefore decided both explicitly. OD-021 and OD-022 remain distinct decisions and are not merged; OD-022 governs `organization.reactivate` only.

Commercial policy and numeric configuration are separated. The commercial enforcement model, billing architecture and metering unit are approved as the Volume I baseline. Specific commercial numerals — daily read limits, crawl quotas, entitlement thresholds, warning thresholds, hard limits, grace periods and similar plan-specific quantities — are versioned policy configuration bound to an approved policy version, not immutable Volume I product constants. Volume I fixes what is measured, the metering unit, when entitlement evaluation occurs, how warning and enforcement behave, deterministic soft-limit and hard-limit semantics, policy-version binding, and audit and observability expectations. It does not fix a commercial numeral unless the ratification record identifies that value as intrinsic to the product. Retained numerals are marked as test fixtures, example policy values, or the approved current policy version. No price and no packaging tier is invented.

Scope Adjustments From The Session Record:
The ratification session is authoritative for what was decided but did not enumerate every obligation its decisions created. Three expansions are recorded so the audit trail explains why this change set is wider than that record:

1. OD-012 was omitted from the integration brief's decision list, which enumerated twenty; the session recorded twenty-one. OD-012 is resolved by replacement and is integrated here. Only its customer-notification limb remains outstanding.
2. OD-025 is a controlled foundation change to 018 OBSERVABILITY.md, which the session did not state. OD-024 is not a foundation change: the foundation cross-context event list is a stated minimum under ADR-015 and never named `ComparisonGenerated`, so its removal violates no foundation requirement and none is asserted here.
3. OD-016 is a controlled foundation change to the 016 STATE_MODEL.md Session row under SM-REQ-010, which the session did not state.
4. OD-012 Option 3 requires a controlled foundation change adding an EmergencyAccessGrant state machine to 016 STATE_MODEL.md, because a break-glass artifact with a bounded lifetime and revocation is stateful under SM-REQ-001 and SM-REQ-002. The session did not state this.

OD-031 is classified as implementation-blocking per the session record and is not part of the release-blocking legal package. It remains pending and is not altered by this change set.

Options Considered:

1. Integrate every decision and declare the final Volume I freeze. Rejected: the legal package and OD-013 are unresolved, and neither is resolvable by specification work. A freeze would either falsify their status or invent their answers.
2. Integrate nothing until the legal package and OD-013 clear. Rejected: twenty-one decisions are decided and unapplied, so the register misdescribes the specification as pending on questions the owner has answered. Leaving them unapplied preserves a known false statement for an unbounded period.
3. Integrate the decided set, keep the outstanding gates truthfully open, and tag a reviewable pre-legal baseline. Accepted.
4. Integrate the eighteen determinate decisions and record OD-012, OD-022 and OD-026 as decided-in-direction with mechanism outstanding. Rejected: it would leave three ratification clusters partially applied, which is worse than either a complete integration or none. The owner supplied the three decisions instead.

Consequences:

- four foundation changes land in this change set: the 016 Document row, the 016 Session row, the new 016 EmergencyAccessGrant row, and the 018 WF-011 coverage row; no other foundation content is altered
- the Volume I ratified pre-legal baseline is `v1.4-volume-i-ratified-prelegal`; it is a reviewable milestone and is not the final Volume I freeze, and no document may describe it as frozen or implementation-ready
- no ratified decision remains described as pending, interim or provisional in active normative text; interim policy identifiers for ratified decisions are renamed to their approved Version 1 policy identity, and historical audit text is retained only where marked historical
- `DocumentQuarantined`, `DocumentRetired`, `ComparisonGenerated` and `ReassessmentTriggered` have no active normative producer, consumer, route, manifest entry or acceptance claim; the Document `quarantined` and `retired` states are removed rather than reserved
- a new capability and workflow exist for emergency access, a new `session.*` permission and Session revoke-reason vocabulary exist for sign-out and single-session revocation, a fifth receipt purpose exists for Organization reactivation, and `RoleExpiryBlockDecision` exists in the authorization record architecture; none is authorized by ADR-017 or ADR-018, whose constraint sets authorize no new capability, and all are authorized here
- the acceptance identifier count remains exactly 97 and no identifier is added or renumbered. The behaviour added by OD-012, OD-016, OD-020, OD-022 and OD-026 binds to capabilities and workflows that already exist — emergency access to CAP-023 and WF-018, session termination to CAP-001, CAP-025, WF-001 and WF-013, customer-facing reads across the accepted read surface, Organization reactivation and the last-administrator block to WF-013 — so each is verified by strengthening the assertions of an existing acceptance identifier rather than minting a new one. Every ratified decision cites at least one defined acceptance identifier and none is dangling
- production release with real customer data remains blocked wherever legal approval is required; the absence of legal sign-off is not approval
- Volume II remains blocked from an architecture baseline and broad implementation; the retained drafts are aligned to the corrected contracts and are not expanded

Affected Downstream Documents:
[specification/002 GLOSSARY.md](specification/002%20GLOSSARY.md), [specification/011 DOMAIN_MODEL.md](specification/011%20DOMAIN_MODEL.md), [specification/014 SECURITY_MODEL.md](specification/014%20SECURITY_MODEL.md), [specification/015 DATA_LIFECYCLE.md](specification/015%20DATA_LIFECYCLE.md), [specification/017 ERROR_MODEL.md](specification/017%20ERROR_MODEL.md), [specification/FOUNDATION_TRACEABILITY_MATRIX.md](specification/FOUNDATION_TRACEABILITY_MATRIX.md), [specification/FOUNDATION_SECTION_MAPPINGS.md](specification/FOUNDATION_SECTION_MAPPINGS.md), and the Volume I set: INDEX, OWNER_DECISION_REGISTER, PRODUCT_DEFINITION, PRODUCT_RULES, CAPABILITY_MODEL, WORKFLOW_SPECIFICATIONS, SCORE_EVIDENCE_MODEL, ACCEPTANCE_AND_TEST_MAPPING, TRACEABILITY_MATRIX. Retained Volume II drafts: INDEX, API_CONTRACTS, APPLICATION_LAYER, BACKGROUND_PROCESSING, INTEGRATION_CONTRACTS, SECURITY_PERFORMANCE, TESTING_ARCHITECTURE.

Affected Tests, Diagrams, Schemas And Contracts:
Acceptance and test mapping for every capability, workflow and product rule named by the applied decisions; [diagrams/DOMAIN_MODEL.md](diagrams/DOMAIN_MODEL.md), [diagrams/DATA_LIFECYCLE.md](diagrams/DATA_LIFECYCLE.md), [diagrams/CONTAINER_ARCHITECTURE.md](diagrams/CONTAINER_ARCHITECTURE.md), [diagrams/SYSTEM_CONTEXT.md](diagrams/SYSTEM_CONTEXT.md); [schemas/POSTGRESQL_SCHEMA.md](schemas/POSTGRESQL_SCHEMA.md), whose executable event-registry manifest previously excluded five event names pending these decisions and is corrected here: the two removed Document events and the removed reassessment trigger event become permanent exclusions, while the last-administrator block event and the Issue collision event are admitted with exactly one producer each; [architecture/RAILS_APPLICATION_ARCHITECTURE.md](architecture/RAILS_APPLICATION_ARCHITECTURE.md); and the Volume II API, application-layer and event contracts carrying the corresponding upstream blocker identifiers.

Risks And Mitigations:

- removing an event named by a foundation requirement could silently weaken observability; the 018 coverage row is amended in this change set and its coverage is re-expressed through already-accepted events, audit evidence and records, so no coverage obligation is discharged by deletion alone
- adding a break-glass capability creates the strongest available path to cross-tenant customer data; it is authorized outside the Incident aggregate with separated requesting and approving actors, explicit resource and action scope, a bounded lifetime and immutable Audit Evidence, and its customer-notification limb is withheld pending legal review rather than assumed
- integrating decided behaviour while legal and OD-013 remain open could be misread as a freeze; the milestone is named pre-legal, the outstanding gates state their exact blocking impact, and no document claims implementation readiness
- renaming interim policy identifiers could erase a genuinely unresolved gate; each occurrence is classified before change, and identifiers bound to unresolved decisions — including the legal package, OD-013, OD-014, OD-023, OD-027, OD-031 and OD-032 — are retained unchanged
- an owner decision recorded without an option number could later be misread as an inference; OD-024, OD-025, OD-012, OD-016, OD-020, OD-022 and OD-026 each cite the record that decided them

Compatibility And Migration:
No shipped software, emitted event, persisted record or customer datum exists to migrate. CAP, WF, PRULE, PR-REQ, OD and ADR identifiers are preserved without renumbering; additions extend each family rather than reassigning it. The four removed events were never producible: each was already excluded from the executable event-registry manifest or had no defined producer, so no consumer, route or retained history depends on one and no event-contract version is broken. The removed Document `quarantined` and `retired` states were reserved and unreachable, so no Document can hold a removed state. OD-007's Citation direction, OD-002's equal-weight scoring policy and OD-010's check catalogue are ratified as already implemented and change no observable behaviour. Behaviour added by OD-012, OD-016, OD-020, OD-022 and OD-026 is new and supersedes no accepted contract. OD-026 Option 1 permits an Assignment to remain effective beyond its stated `expires_at_utc` until the guard clears; the owner accepted that consequence expressly.

Review Checkpoint:
This baseline is reviewable, not final. The successor Volume I freeze requires: qualified legal review of the retention, deletion and notification package to complete, preceded by the owner input it depends on — approved jurisdictions, markets, and customer and contract scope, none of which the repository currently contains; `AC-CAP-013`'s unsatisfiable 30-day expiry-warning criterion to be reconciled or changed; and an explicit Chief Architect decision on OD-013 event tenant identity, which no option may satisfy by inferring a synthetic platform tenant. The successor tag is the final Volume I freeze and MUST NOT be created while any of those gates is open. Reassess no later than 2026-08-27.

## ADR-020: Volume I Legal Closure, Event Ownership, And Freeze Baseline

Status: Accepted
Date: 2026-07-17
Owner: Chief Architect
Reversibility: Low. Downstream artifacts and the Volume I freeze cite these contracts, and the removed deletion-job edge and the Organization-ownership rule are load-bearing. No emitted event, persisted record or customer datum exists to unwind.

Decision:
Close the six owner decisions that blocked the Volume I freeze — OD-011, the OD-012 notification limb, OD-013, OD-029, OD-030 and OD-033 — integrate them across the foundation, Volume I and the retained Volume II drafts as one change set, and declare the result the final Volume I freeze. Three controlled foundation changes are made under PM-REQ-009. Five owner decisions remain pending and none blocks the freeze.

Context:
`v1.4-volume-i-ratified-prelegal` at `b2cb4ca` integrated 21 owner decisions and left two external gates: the retention and deletion legal package, and OD-013 event tenant identity. [specification/volume-i/LEGAL_REVIEW_RECORD_2026-07-17.md](specification/volume-i/LEGAL_REVIEW_RECORD_2026-07-17.md) recorded that OD-011 could not close because its standard demanded repository-hosted counsel signatures, reviewer identities and package digests that do not exist and that the owner forbade fabricating. The owner has since supplied the product and market scope, confirmed external counsel review with no objection, and narrowly amended the evidence standard. The decisions are recorded in [specification/volume-i/OWNER_DECISION_RECORD_2026-07-17_LEGAL_AND_CLOSURE.md](specification/volume-i/OWNER_DECISION_RECORD_2026-07-17_LEGAL_AND_CLOSURE.md).

Authority And Precedence:
This ADR does not supersede any unchanged foundation requirement. Under PM-REQ-003 the foundation outranks the ADR registry. Where this change set changes foundation content, the change is made in the foundation document itself with its impact mapping in the same change set, exactly as ADR-006 and ADR-012 require.

Controlled Foundation Changes Under PM-REQ-009:

1. OD-033 — [specification/016 STATE_MODEL.md](specification/016%20STATE_MODEL.md), LifecycleDeletionJob row. The `queued to completed` edge is removed and added to the row's invalid transitions; completion now occurs only from `running`. The owner treats the direct edge as unintended. The deletion lifecycle is asynchronous, so every job enters the existing `running` state before completing, including where the frozen manifest is empty or every member is already provably destroyed at admission. No duplicate state is invented; `running` already exists. WF-013's enumeration is restored and no longer asserts that the edge "is required by" the state model.

2. OD-029 — [specification/015 DATA_LIFECYCLE.md](specification/015%20DATA_LIFECYCLE.md). The retention-warning producer is reconciled from an unnamed "lifecycle service" to WF-007 under the integrity-validation service authority, matching the approved Option 2. This assigns an existing event to an existing workflow and creates no new workflow, capability, decision record, Evidence Payload state or notification route variant. It satisfies `AC-CAP-013`'s 30-day expiry-warning criterion, which previously had no producer and was therefore unsatisfiable.

3. OD-030 — [specification/015 DATA_LIFECYCLE.md](specification/015%20DATA_LIFECYCLE.md). Destruction of an Evidence Payload whose effective validation status is already `invalid` is proved by a distinct immutable `security_audit` deletion audit record rather than an Evidence Validation Decision, which cannot be appended to an already-invalid payload. Destruction stays on the existing capture cursor and 24-month maximum and is not accelerated to the accrued 30-day minimum. The LifecycleDeletionJob and its Deletion Evidence remain the Account-deletion and Organization-closure mechanism only. No retention window is changed.

OD-013 makes no foundation change. Option 1 consumes the DM-REQ-013 gate that already reserves the pre-Organization bootstrap substitution for "the named onboarding contract"; WF-001 now expressly names it. DM-REQ-013 is not modified, no `event_scope` discriminator is added, and the PM-REQ-009 change associated with Option 2 is expressly not performed.

Governance Amendment:
OD-011's Qualified Legal Approval element demanded repository-hosted reviewer identities, package digests and counsel signatures. Privileged legal material was never intended to live in the engineering repository. That element is narrowly amended to accept exactly four things: an append-only owner approval record; a factual record that qualified external legal counsel reviewed the position and raised no objection; the identified retention baseline; and the applicable product and market scope. Privileged detail is expressly excluded and its absence is by design. The repository MUST NOT fabricate a signature, reviewer identity, package digest or legal opinion, and MUST NOT present any record as a legal opinion. No other element of OD-011's approval package is relaxed: its retention, hold, destruction, backup, audit and customer-configuration decisions each remain required and are recorded.

Decisions Applied:

- OD-011 Option 1 — `retention-interim-v1` is the fixed Volume I retention baseline. Product scope is worldwide availability; principal initial English-speaking markets are the United States, United Kingdom, Australia, New Zealand, Canada and South Africa. Qualified external counsel reviewed the position and raised no objection. Customer-configurable retention is not approved and remains disabled.
- OD-012 notification limb — closed insofar as it inherits OD-011, against the same baseline and review record.
- OD-013 Option 1 for every sub-decision — all events, Incidents and Investigations are Organization-owned; a platform-wide Incident and a cross-Organization Investigation are coordinated per-Organization records linked by `correlation_id`; the pre-Organization bootstrap substitution is confined to `BootstrapGrantIssued` and `BootstrapGrantExpired`. `UPSTREAM-V1-EVENT-SCOPE-001` is retired.
- OD-029 Option 2, OD-030 Option 3, OD-033 Option 3 — as recorded above.

Options Considered:

1. Freeze without closing OD-011, treating counsel's no-objection as sufficient under the original standard. Rejected: the original standard required a named reviewer approving an identified digest, which does not exist; recording one would fabricate privileged material.
2. Close OD-013 with Option 2's `event_scope` discriminator, the position the ratification session summarised as recommended. Rejected: the Owner Decision Register recommends Option 1 for the bootstrap sub-decision only and records the other two as owner input required; Option 2 additionally requires a foundation change to DM-REQ-013 that the owner expressly declined.
3. Close OD-013 with Option 3, deleting platform and cross-Organization scope. Rejected: it discards a capability SEC-REQ-012 contemplates and WF-018 exists to provide.
4. Close the decisions, amend the evidence standard narrowly, and freeze. Accepted.

Consequences:

- Volume I is frozen at `v1.5-volume-i-frozen`. This is the authoritative Volume I implementation baseline and the PM-REQ-010 gate for Volume I is satisfied.
- Canonical ownership of every event, Incident and Investigation is singular and always an Organization. Coordination across Organizations is orchestration over Organization-owned records and never an owner. No document may use "platform-wide" or "cross-Organization" to imply a platform-owned canonical record.
- No LifecycleDeletionJob may complete without entering `running`. No compatibility path, schema shape, migration, function or grant may admit the removed edge.
- `retention-interim-v1` is a fixed approved baseline rather than an interim; its identifier is retained because renaming it would not change its content and the register names it explicitly as the approved option.
- Five owner decisions remain pending — OD-014, OD-023, OD-027, OD-031, OD-032 — exactly as the ratification session classified them. OD-014, OD-023 and OD-031 are implementation-blocking with genuinely neutral interims; OD-027 and OD-032 are Volume II-blocking. None blocks the Volume I freeze, and each retains deterministic interim behaviour and an exact blocking statement.
- Volume II remains blocked from an architecture baseline; the retained drafts are aligned to the corrected contracts and are not expanded.

Affected Downstream Documents:
[specification/015 DATA_LIFECYCLE.md](specification/015%20DATA_LIFECYCLE.md), [specification/016 STATE_MODEL.md](specification/016%20STATE_MODEL.md), and the Volume I set: INDEX, OWNER_DECISION_REGISTER, WORKFLOW_SPECIFICATIONS, ACCEPTANCE_AND_TEST_MAPPING, TRACEABILITY_MATRIX. Retained Volume II drafts: INDEX, API_CONTRACTS, APPLICATION_LAYER, BACKGROUND_PROCESSING. Schema: [schemas/POSTGRESQL_SCHEMA.md](schemas/POSTGRESQL_SCHEMA.md).

Affected Tests, Diagrams, Schemas And Contracts:
`AC-CAP-013` gains a producer and becomes satisfiable; `AC-WF-001` gains the bootstrap substitution assertion; `AC-WF-013` gains the removed-edge assertion; `AC-WF-017` and `AC-WF-018` gain the per-Organization decomposition assertion. [diagrams/DATA_LIFECYCLE.md](diagrams/DATA_LIFECYCLE.md) and [diagrams/DOMAIN_MODEL.md](diagrams/DOMAIN_MODEL.md) are checked against the removed edge and the ownership rule. The `lifecycle_deletion_jobs` and `audit_records` schema rows are reconciled.

Risks And Mitigations:

- Amending a legal-evidence standard could be read as weakening it; the amendment is narrow, changes only where the evidence lives rather than whether review occurred, expressly forbids fabricating any signature or opinion, and relaxes no other element of the package.
- Recording markets could be read as a contractual or regulatory claim; the record states worldwide availability and principal markets as owner-supplied product facts, makes no jurisdiction-specific legal conclusion, and is expressly not a legal opinion.
- Per-Organization decomposition could be misread as duplicating an event; each per-Organization record is a distinct canonical record with its own owner, not a copy, and `correlation_id` expresses coordination without conferring ownership.
- Freezing with five decisions pending could be misread as freezing over open blockers; each is classified non-blocking by the owner's own ratification record, retains a deterministic interim, and states its exact blocking impact.

Compatibility And Migration:
No shipped software, emitted event, persisted record or customer datum exists to migrate. No identifier is renumbered. The removed `queued to completed` edge was never executable: the OD-033 interim already forbade it, so no job can hold a state reached through it. The bootstrap substitution makes two previously suppressed events emittable and breaks no consumer. `retention-interim-v1` content is unchanged, so no retention window moves and no stored datum changes class.

Review Checkpoint:
Volume I is frozen. Reopening any contract in this change set requires a new ADR and the PM-REQ-009 process where foundation content is affected. The five pending decisions are reviewed at their own latest responsible decision points. Reassess no later than 2026-08-27.

## ADR-021: Scoped Authority Model, Engineering Manual Structural Correction, And Gate C Blocking-Status Basis

Status: Accepted
Date: 2026-07-17
Owner: Chief Architect
Reversibility: Medium. PM-REQ-003 is cited by the manual, the entrypoint and the ADR registry, and the scoped model changes how future conflicts resolve. No software, emitted event, persisted record or customer datum exists to unwind. Reverting would restore three mutually contradictory hierarchies and is not recommended.

Decision:
Replace the linear authority ladder with a scoped authority model in which scope is resolved before rank; reconcile the three conflicting hierarchies onto that single canonical model; correct the two structural defect classes that prevent authority metadata from being parsed, in the two authority chapters that carry them; and restate Roadmap Gate C on implementation-blocking status rather than a literal count of upstream blockers. OD-014 and OD-023 remain pending under their deterministic neutral interims and are expressly not resolved by this ADR.

Context:
Governance Pass 001 discovery established that the repository carried three mutually contradictory statements of authority precedence:

1. PM-REQ-003 in [specification/001 PRODUCT_ARCHITECTURE_MANUAL.md](specification/001%20PRODUCT_ARCHITECTURE_MANUAL.md): constitution, foundation, ADR registry, volume specifications, derived artifacts. It never places the Engineering Manual, Owner Decisions or canonical contracts, and that silence is what permitted the divergence below.
2. [engineering/manual/MANUAL_AUTHORITY.md](engineering/manual/MANUAL_AUTHORITY.md), echoed by [engineering/manual/IMPLEMENTATION_AGENT_ENTRYPOINT.md](engineering/manual/IMPLEMENTATION_AGENT_ENTRYPOINT.md): ratified ADRs and Owner Decisions rank above Engineering Manual content.
3. EM-I-003 in [engineering/manual/volume-i/CHAPTER-03-Authority-Hierarchy.md](engineering/manual/volume-i/CHAPTER-03-Authority-Hierarchy.md), echoed by EM-I-016 and the Volume I README: the Engineering Manual is Level 2, above ADRs at Level 3 and Owner Decisions at Level 4.

Models 2 and 3 are directly contradictory. An engineer holding a manual chapter that disagrees with a ratified Owner Decision obtained opposite answers depending on which document was consulted, and model 3 favoured the manual, which is the artifact with no product authority at all.

The root cause is the linear form itself. A single ladder must rank the Engineering Manual against the Product Specification, and any such ranking implies the manual carries product authority at some rank. That implication is false in every case, and no reordering of a linear ladder can remove it.

Authority And Precedence:
This ADR does not supersede any unchanged foundation requirement. Under PM-REQ-003 the foundation layer outranks the ADR registry. The change to PM-REQ-003 is therefore made in the foundation document itself with its impact mapping in the same change set, exactly as ADR-006, ADR-012 and PM-REQ-003.5 require. This ADR does not change product behaviour and creates no product semantics.

Controlled Foundation Change Under PM-REQ-009:

1. PM-REQ-003 - [specification/001 PRODUCT_ARCHITECTURE_MANUAL.md](specification/001%20PRODUCT_ARCHITECTURE_MANUAL.md). PM-REQ-003 becomes a scope-before-rank rule with six subrequirements. PM-REQ-003.1 names four scopes and their canonical owners. PM-REQ-003.2 preserves the accepted five-tier ordering verbatim as the product-behavior ladder, with the ADR registry stated to comprise accepted ADRs and ratified Owner Decisions integrated into their canonical owner. PM-REQ-003.3 adds the engineering-practice ladder. PM-REQ-003.4 excludes the Engineering Manual from product-behavior authority absolutely rather than by rank. PM-REQ-003.5 restates the existing ADR-006 and ADR-012 rule that an ADR authorizes controlled change but does not itself change foundation content. PM-REQ-003.6 requires implementation to stop on disputed scope. PM-REQ-014 is amended to cite scope as well as precedence. DEC-001-04 records the rationale. No tier of the accepted ordering is reordered, renumbered or removed.

Decisions Applied:

- The canonical model is scope-before-rank. An artifact outside its scope is inapplicable rather than outranked, and MUST NOT be cited to settle a decision belonging to another scope.
- Model 3 is corrected. EM-I-003 no longer ranks the Engineering Manual above ADRs and Owner Decisions; it holds no product-behavior authority at any rank. EM-I-016 and the Volume I README are corrected to match.
- Model 2 is preserved in substance and restated in scoped form. Its ordering was already correct for product behavior.
- Gate C is restated on implementation-blocking status. A blocker is discharged when its governing Owner Decision is ratified and integrated, or when that decision removes the governed behaviour. Eleven of the thirteen blockers recorded by Pass 001 are retired on that basis under ADR-019 and ADR-020, so a literal count of thirteen could never be satisfied and misstated the gate.
- OD-014 and OD-023 remain pending. `UPSTREAM-V1-PROJECT-LIFECYCLE-003` and `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` remain live and implementation-blocking under their deterministic neutral interims.

Structural Defects Corrected:
Authority metadata is carried in front matter that a conforming reader takes from byte 0 with unindented delimiters. Two defect classes made that metadata unparseable, and every one of the 249 chapters and appendices carries exactly one of them:

- `front_matter_not_at_start`, 70 files across Volumes I, II, III and two Volume IV chapters: a repository-path heading precedes the block, so a conforming reader sees no front matter and the identifier, status and owner are invisible.
- `indented_front_matter`, 177 files across Volumes IV through XII: the block is indented four spaces, making it an indented code block whose closing delimiter is not a terminator.

The manual validator passed throughout because it was written around both defects: it special-cased the path heading and stripped indentation before parsing. The bespoke workaround concealed the defect from the only tool that could have reported it.

The two authority chapters that carry the defects are corrected: EM-I-003 for the first class and EM-XII-002 for the second. The remaining 247 files are recorded in `scripts/front_matter_baseline.txt`. The check is enforced for every file not listed, the baseline may only shrink, and a listed file that begins to parse is reported as `stale_front_matter_baseline`. Volume I is frozen and MUST NOT be reformatted wholesale, which is why the baseline exists rather than a repository-wide rewrite.

Options Considered:

1. Pick one of the three hierarchies and delete the others. Rejected: every linear candidate retains the defect that ranking the manual against the Specification implies the manual holds product authority at some rank.
2. Reorder EM-I-003 to place ADRs and Owner Decisions above the Engineering Manual, keeping the ladder linear. Rejected: it resolves the contradiction between models 2 and 3 but preserves the root cause, and still implies a rank at which manual content could outrank a specification on some question.
3. Correct all 249 files' front matter. Rejected: it requires reformatting frozen Volume I wholesale against the freeze, for a defect class that a baselined check contains without touching frozen content.
4. Adopt scoped authority, correct the two named authority chapters, and baseline the rest. Accepted.

Consequences:

- Authority conflicts now resolve identically regardless of which document an engineer opens first, because all five statements restate one canonical model.
- The Engineering Manual can never outrank a ratified Owner Decision or an accepted ADR on product behaviour. PM-REQ-003.4 makes the exclusion absolute rather than a matter of rank.
- Gate C no longer requires correcting eleven already-retired blockers, and no longer moves when a blocker count changes.
- The manual validator enforces authority-metadata parseability for every corrected file and cannot silently exempt a clean file.
- 247 files retain a known, recorded structural defect. This is technical debt, not conformance, and it is registered as remaining work.
- Engineering Manual Volume III is recorded as carrying product-behaviour ownership conflicts, including examples that pre-empt pending OD-014. Remediation requires its own controlled change and does not occur in this pass.

Affected Downstream Documents:
[specification/001 PRODUCT_ARCHITECTURE_MANUAL.md](specification/001%20PRODUCT_ARCHITECTURE_MANUAL.md), [ROADMAP.md](ROADMAP.md), [engineering/manual/MANUAL_AUTHORITY.md](engineering/manual/MANUAL_AUTHORITY.md), [engineering/manual/IMPLEMENTATION_AGENT_ENTRYPOINT.md](engineering/manual/IMPLEMENTATION_AGENT_ENTRYPOINT.md), [engineering/manual/volume-i/CHAPTER-03-Authority-Hierarchy.md](engineering/manual/volume-i/CHAPTER-03-Authority-Hierarchy.md), [engineering/manual/volume-i/CHAPTER-16-AI-Engineering-Governance.md](engineering/manual/volume-i/CHAPTER-16-AI-Engineering-Governance.md), [engineering/manual/volume-i/README.md](engineering/manual/volume-i/README.md), [engineering/manual/volume-xii/CHAPTER-002-Authority-Hierarchy-and-Canonical-Ownership.md](engineering/manual/volume-xii/CHAPTER-002-Authority-Hierarchy-and-Canonical-Ownership.md), [engineering/manual/MANUAL_CHANGELOG.md](engineering/manual/MANUAL_CHANGELOG.md), [engineering/manual/MANUAL_VERSION_HISTORY.md](engineering/manual/MANUAL_VERSION_HISTORY.md), [engineering/manual/MANUAL_VALIDATION_REPORT.md](engineering/manual/MANUAL_VALIDATION_REPORT.md), [CHANGELOG.md](CHANGELOG.md), [PROJECT_STATE.md](PROJECT_STATE.md), [TODO.md](TODO.md).

Affected Tests, Diagrams, Schemas And Contracts:
No product test, diagram, schema or contract changes. `scripts/validate_engineering_manual.py` gains the `front_matter_not_at_start`, `indented_front_matter`, `front_matter_unterminated`, `front_matter_missing` and `stale_front_matter_baseline` checks, and `scripts/front_matter_baseline.txt` records the outstanding population. Three negative controls are added, one per new failure mode. No acceptance criterion changes, because no product behaviour changes.

Compatibility And Migration:
No shipped software, emitted event, persisted record or customer datum exists to migrate. No identifier is renumbered and no tier of the accepted PM-REQ-003 ordering is reordered or removed. The scoped model is a strict clarification of the accepted ordering for product behaviour and an addition for engineering practice; every conflict that previously resolved correctly under model 2 resolves identically now. Conflicts that previously resolved under model 3 in favour of the Engineering Manual now resolve in favour of the canonical owner, which is the correction being made. Gate C becomes satisfiable where the literal count made it unsatisfiable; it is not loosened, because a live blocker still blocks every slice that intersects it.

Risks And Mitigations:

- Scoped authority could be misread as granting the Engineering Manual product authority within its own scope. PM-REQ-003.4 states the exclusion absolutely rather than as a rank, and EM-I-003 repeats it at the point of use.
- A decision could be classified into the engineering-practice scope to escape product authority. PM-REQ-003.6 stops implementation on disputed scope and forbids selecting the scope that produces the preferred outcome.
- Restating Gate C on status could be read as weakening it or as resolving OD-014 or OD-023. The gate still blocks every slice intersecting a live blocker, both blockers are named as live, both decisions are named as pending under their interims, and the gate text expressly denies resolving either.
- Baselining 247 files could be read as accepting the defect permanently. The baseline may only shrink, a corrected file is reported as stale until delisted, entries are forbidden, and the population is registered as remaining work.

Review Checkpoint:
The scoped model is reviewed if any future document proposes a linear authority ladder. The front matter baseline is reviewed whenever a listed file is edited for any reason. The Volume III ownership conflicts are reviewed before Volume II begins. Reassess no later than 2026-08-27.

## ADR-022: Engineering Manual Product-Authority Remediation And Acceptance

Status: Accepted
Date: 2026-07-17
Owner: Chief Architect
Reversibility: Medium. The manual becomes the accepted engineering-practice authority that Specification Volume II consumes. No software, emitted event, persisted record or customer datum exists to unwind. Reverting would restore invented product contracts and is not recommended.

Decision:
Remove the residual product-behaviour breaches Governance Pass 001 recorded, retire the front matter debt at source, and accept the Engineering Manual at 12 volumes and 240 chapters as the normative authority for engineering practice only, with no independent product-behaviour authority. OD-014 and OD-023 remain pending under their deterministic neutral interims and are expressly not resolved.

Context:
ADR-021 reconciled authority and left one CONFLICT open: Engineering Manual Volume III established product behaviour it does not own. This ADR closes it. The audit understated the scope in two ways, both found by this pass and both verified before correction.

First, the OD-014 pre-emption was not confined to EM-III-010. Five sites across four chapters presented Project archive as an accepted command: `project.archive!` and `Project#archive!` in EM-III-010, `archive_project` in EM-III-005, `ProjectService.archive()` in EM-II-008, and `ArchiveProject` twice in EM-II-009. The Volume I permission contract defines `project.create` and `project.activate` only; `specification/016 STATE_MODEL.md` names the pause, resume and archive transitions but supplies no command, which is precisely the question OD-014 reserves.

Second, `Assessment` was never a Volume III defect alone. It appeared 65 times across 21 chapters in Volumes I through IV as a repository, service, command, DTO, factory, builder, job, cache key, module, table and route. `Assessment` occurs zero times as an entity anywhere in `specification/`; DM-REQ-001 does not define it. EM-III-003 and EM-II-005 both presented it in a list introduced as the terminology "defined by the Product Specification", so the manual invented an entity while claiming to quote its owner.

Authority And Precedence:
This ADR changes no foundation content and requires no PM-REQ-009 controlled change. It changes no product behaviour and creates no product semantics. Under PM-REQ-003 the manual is a derived implementation artifact with respect to product behaviour, so removing invented product contracts restores the boundary rather than altering it.

Decisions Applied:

- Product-behaviour breaches are removed. Every OD-014 pre-emption is corrected to the canonical `project.activate`, with the deferral stated and cited at the point of use. The invented `Assessment` entity is purged; naming and structure examples now use the canonical `Crawl` or `Evaluation` from DM-REQ-001, and behavioural examples use a fictional `Shipment` from an unrelated domain so that no example can imply an F1 transition. Invented events (`AssessmentCompleted`, `IssueDetected`, `RoleAssignmentExpired`, `OrganisationReactivated`) are replaced with the canonical `EvaluationCompleted`, `IssueCreated`, `IssueResolved` and `OrganizationReactivated`, each verified present in `specification/016 STATE_MODEL.md`. Asserted F1 routes are replaced with fictional ones. Invented state machines and cross-entity invariants in EM-III-010 and EM-III-011 are de-domained.
- Canonical spelling is enforced. 204 product-domain occurrences of `Organisation` are corrected to `Organization` across 190 files, and EM-VIII-007 is renamed to match. The ordinary-English word, as in "directory organisation", is a different word and is deliberately left alone.
- The front matter debt is retired at source rather than baselined. `textwrap.dedent` computed a longest-common indent that any column-zero interpolation collapsed to nothing, so the generator silently emitted indented front matter; `dedent_block` strips a fixed indent and cannot be defeated by interpolated content. All 237 remaining files are corrected mechanically under a proof that only structural syntax moved, `scripts/front_matter_baseline.txt` is deleted, and the structural check now has no exemptions.
- Enforcement replaces attention. Six executable checks now cover the defect classes this programme found: `invented_canonical_entity`, `undefined_product_route`, `pending_od_preemption`, `noncanonical_product_spelling`, `stale_authority_baseline` and `contradictory_authority_hierarchy`. Each has a negative control and each control is proved load-bearing by mutation.
- The Engineering Manual is ACCEPTED. It is the normative authority for engineering practice and holds no independent product-behaviour authority at any rank.

Defects Found By This Pass And Not By The Audit:

1. Four further OD-014 pre-emptions outside EM-III-010, found while verifying a rename rather than by the audit.
2. EM-I-001 was wrapped in a stray code fence, so the entire chapter rendered as a code block, and its final cross-reference carried paste junk including a non-breaking space. Seven further Volume I chapters carried a stray trailing fence. None was visible while the fence check exempted Volume I, and the corruption predates this programme.

Options Considered:

1. Replace `Assessment` with the canonical `Evaluation` throughout. Rejected: `Assessment` and `Evaluation` appear side by side as two distinct example entities in eight chapters, so the rename would collapse them and produce duplicate or nonsensical examples.
2. Replace every example entity with a fictional one. Rejected for terminology, event and schema chapters, whose purpose is to document real vocabulary; a fictional entity there would be actively misleading.
3. Correct the two authority chapters and leave the front matter baseline in place. Rejected: the generator would reintroduce the defect on the next regeneration, and a baseline that never shrinks is a permanent exemption.
4. Purge the invented entity, use canonical names where the manual documents vocabulary and fictional names where it illustrates behaviour, fix the generator, and retire the baseline. Accepted.

Consequences:

- The manual can be consumed by Specification Volume II without transmitting invented product contracts. This was the acceptance blocker.
- No example can quietly become product authority: an invented entity, an F1 route, a pre-empted Owner Decision, a non-canonical identifier spelling, a stale baseline and a linear authority ladder each now fail validation.
- Zero registered front matter debt. Every chapter and appendix carries authority metadata a conforming reader parses, proved by a reader written independently of the validator.
- The generator can no longer reintroduce either defect class, and regression tests fail if the fix is reverted.
- OD-014 and OD-023 remain pending. Their interims are unchanged and this acceptance resolves neither.

Affected Downstream Documents:
[ROADMAP.md](ROADMAP.md), [PROJECT_STATE.md](PROJECT_STATE.md), [CHANGELOG.md](CHANGELOG.md), [TODO.md](TODO.md), [specification/INDEX.md](specification/INDEX.md), [specification/volume-ii/INDEX.md](specification/volume-ii/INDEX.md), and the Engineering Manual master controls: MANUAL_VALIDATION_REPORT, MANUAL_CHANGELOG, MANUAL_VERSION_HISTORY, MASTER_INDEX.

Affected Tests, Diagrams, Schemas And Contracts:
No product test, diagram, schema or contract changes, because no product behaviour changes. `scripts/validate_engineering_manual.py` gains six ownership checks and eight negative controls; `scripts/test_generate_engineering_manual.py` is added; `scripts/front_matter_baseline.txt` is deleted. No acceptance criterion changes.

Compatibility And Migration:
No shipped software, emitted event, persisted record or customer datum exists to migrate. No identifier is renumbered. EM-VIII-007 keeps its identifier across the filename correction, and its index, master-index and traceability references move with it. The `Assessment` name had no canonical authority to preserve, so nothing downstream depends on it. The mechanical front matter pass moved only structural syntax under a per-file proof that content was preserved.

Risks And Mitigations:

- A fictional `Shipment` in behavioural examples could read as a real F1 concept. Each site states that it is fictional and from an unrelated domain, and names the canonical owner of the real contract.
- Purging an invented entity could remove genuine guidance. Only the entity name changed; every surrounding engineering rule is preserved verbatim, and the canonical replacements are verified present in DM-REQ-001.
- The ownership checks could produce false positives and erode trust. Two were found and fixed during this pass: a numbered reading order in EM-I-016 is a sequence rather than a ladder, and "organisational units" is an ordinary-English adjective. The checks are scoped accordingly.
- Accepting the manual could be read as authorising implementation or Volume II drafting. Acceptance is of engineering practice only; PM-REQ-010 and Gate C are unchanged, and both live blockers still block every slice that intersects them.

Review Checkpoint:
The ownership checks are reviewed if a false positive is reported or a new invented-entity class appears. Acceptance is revisited if OD-014 or OD-023 resolves in a way that changes engineering practice. Reassess no later than 2026-08-27.

## ADR-023: Volume II Freeze-Candidate Governance Repair And Successor Decision Registration

Status: Accepted
Date: 2026-07-17
Owner: Chief Architect
Reversibility: Reversible while no implementation depends on the re-anchored rationales; the two registered identifiers are difficult to reverse once downstream artifacts cite them.

Decision:
Authorize the governance repair required before the Volume II architecture baseline may be frozen, and defer that freeze until it completes. The repair does exactly three things and no more. First, it registers the two successor owner decisions that ratified Volume I text delegates but never registered — OD-034 and OD-035 — each as pending, with the deterministic fail-closed interim behaviour its delegating decision already ratified. Second, it re-anchors every Volume II citation of a retired upstream blocker tag to the authority that actually governs the behaviour, correcting the label and never the behaviour. Third, it corrects the derived artifacts that still carry pre-ratification shapes for decisions already integrated under ADR-019 and ADR-020. No product behaviour changes and no owner decision is resolved.

Context:
Pass B completed all 97 implementation-matrix rows against frozen Volume I. Two governance defects survived it, and both are labelling and graph defects rather than implementation gaps.

`scripts/validate_volume_ii.py` reports 72 sites where Volume II cites one of eight retired blocker tags as a live reason to defer, disable or refuse to route. `INDEX.md`'s registry is the status authority and records only `UPSTREAM-V1-PROJECT-LIFECYCLE-003` (OD-014) and `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` (OD-023) as LIVE. Every other tag is retired under ADR-019 or ADR-020 and each of its decisions records `Blocking Impact: None`. The failure runs in both directions: the same wrong label withholds behaviour the owner ratified and invites a reader to "unblock" objects the owner denied.

Separately, OD-020's Ratified Behavior and the normative binding text in `WORKFLOW_SPECIFICATIONS.md` each leave read authority over security, administrative and internal operational objects deny-by-default "pending a separate owner decision", and OD-020's Blocking Impact records that scope as out of scope for it rather than resolved by it. That separate decision had no identifier and no register entry. Volume II recorded the consequence precisely on MTX-095: the decision "has no OD number and is absent from the register's pending set, so it is neither a pending Owner Decision this row may withhold against nor a resolved one this row may implement." A citation cannot be re-anchored to a node that does not exist, so the graph had to be repaired before the citations could be.

OD-019 is the same shape. It ratified the metered-read unit and the fail-closed leg for an undeclared route, and booked the route-to-operation declaration table and `report.view`'s read surface as unpaid Costs. Neither exists. Its own Why The Decision Exists names the residual ambiguity — "the same navigation can reasonably resolve to `report.view` or `score.read`" — and classifies it as "a commercial and packaging choice rather than an architectural inference".

Authority And Precedence:
This ADR does not supersede any unchanged foundation requirement and MUST NOT be read as doing so. Under PM-REQ-003 authority is resolved by scope before rank; this change set is entirely within the product-behavior scope, where the foundation layer outranks the ADR registry. No foundation content changes, so PM-REQ-009 is not engaged and no controlled foundation change is performed or implied.

`specification/volume-i/OWNER_DECISION_REGISTER.md` is changed. That change is confined to adding two decisions, correcting a Status summary line the register's own decisions already contradicted, and adding an explicit statement that each decision's `Current Status` field is the sole status authority. No accepted behaviour, option, ratification, interim or identifier is altered, and no decision is renumbered. Registering a decision that ratified Volume I text expressly delegates is completion of the governance graph Volume I itself declares incomplete; it reopens no contract in the ADR-020 change set and therefore requires no successor Volume I freeze tag. `v1.5-volume-i-frozen` remains the authoritative Volume I product-behaviour baseline, and every behavioural contract it froze is byte-unchanged.

Options Considered:

1. Reconcile the 72 citations without registering the successor decisions. Rejected: the security and administrative read citations are substantively correct and mis-attributed, so removing the retired tag leaves them citing nothing, and the only alternatives are a false enablement or a silent deny with no authority.
2. Resolve the successor decisions by inference so the validator clears. Rejected: OD-020 expressly rejected deriving read from write, `CAPABILITY_MODEL.md:16` states an `Actor` line never grants authority, a Support Session scopes an already-permitted action and is never itself a read grant, and OD-019 classifies its residual as a commercial choice. Every inference route is closed by accepted authority, so inference would invent authority no document wrote and resolve two owner decisions by implementation.
3. Bulk-delete the 72 citations. Rejected: one validator signal covers three distinct defects, at least one citation is accidentally load-bearing, and deleting a citation whose obligation is unmet asserts an enablement nothing can honour.
4. Register what authority does not force, re-anchor what it does, correct the derived artifacts, and freeze. Chosen.

Chosen-Option Rationale:
Option 4 is the only option that leaves no citation unresolved while making no product decision on the owner's behalf. It applies the ADR-018 rule unchanged: correct in place only where existing authority already compels exactly one conformant answer, and register an owner decision with deterministic fail-closed interim behaviour wherever the behaviour is genuinely unresolved. Both registered decisions are recorded with the interim their delegating decision already ratified, so the repair makes the register describe the behaviour the repository already implements rather than changing it.

Decisions Registered:

- OD-034 Read Authority For Security, Administrative And Internal Operational Objects — Classification C, pending, Owner Required Chief Product and Chief Security. Interim: every named class stays deny-by-default exactly as OD-020 ratified. Scope follows the wider normative list in `WORKFLOW_SPECIFICATIONS.md`, which names Emergency Access Grant where OD-020's own sentence omits it, and expressly puts the classes OD-020's problem statement raised but neither carve-out sentence named — Integration/Credential, Account administration, Policy administration — to the owner rather than resolving them by silence. Only AC-PRULE-044 is gated, because its complete-fixture clause cannot be satisfied for an object class with no row.
- OD-035 Low-Cost Read Route-To-Operation Declaration And `report.view` Read Surface — Classification C, pending, Owner Required Chief Product. Interim: OD-019's ratified fail-closed leg, under which every metered read route resolves `operation_unknown` and Blocks with `contact_support`. Gates AC-CAP-024, AC-WF-015 and AC-PRULE-040.

Consequences:

- The pending set is seven: OD-014, OD-023, OD-027, OD-031, OD-032, OD-034 and OD-035. Each records deterministic fail-closed interim behaviour and an exact blocking impact, and none blocks the Volume I freeze or the Volume II baseline. The withheld-limb count rises from 18 rows to 22; the matrix stays 97 rows, 97 acceptance criteria, 97 complete and 0 outstanding.
- No retired blocker tag is cited as a live reason to withhold behaviour anywhere in scope. Where a deny survives, it cites the ratified decision that made it and, where one exists, the registered pending decision that will lift it.
- `v1.5-volume-i-frozen` remains the authoritative Volume I baseline and no behavioural contract in it changes. `v1.7-engineering-manual-accepted` is unchanged and no engineering-practice content is touched.
- Derived artifacts carrying pre-ratification shapes for OD-013, OD-016, OD-017, OD-024, OD-025 and OD-026 are corrected to the ratified shape at their canonical owners.
- No software, physical endpoint, migration, provider integration or additional Volume II architecture artifact is authorized by this decision.

Risks And Mitigations:

- Registering rather than resolving leaves two genuine product gates open. Each registration states its exact blocking impact and its interim, so no gate can be passed by inference, and each affected row names its withheld limb exactly rather than gesturing at it.
- Re-anchoring 72 citations could change behaviour under cover of a labelling correction. Every finding is classified individually in `specification/volume-ii/RETIRED_BLOCKER_CLASSIFICATION.md` against the question "what would break if this citation were simply deleted?", and each records whether behaviour changes. No deny becomes an allow.
- Correcting the register could be read as reopening frozen Volume I. The change adds two delegated nodes and corrects a summary line the register's own fields already contradicted; it alters no accepted behaviour, option, ratification or identifier, and the ADR-020 Review Checkpoint's requirement of a new ADR to reopen a contract in that change set is satisfied by this ADR without any contract being reopened.
- A future reader could mistake a registered pending decision for a blocker on the baseline. Each states `Volume II — no` and `Implementation — no`, and the Implementation Readiness Report proves non-blocking per row rather than asserting it.
- The same class of defect could recur. `scripts/validate_volume_ii.py` gains `unresolved_successor_decision`, which fails when a settled decision delegates a policy question to a successor that no registered decision supplies, and the retired-blocker check is widened to the full in-scope corpus rather than one directory. Each new rule carries a negative mutation control.

Compatibility And Migration:
No shipped software, emitted event, persisted record or customer datum exists to migrate. No identifier is renumbered and no acceptance criterion changes. Every behavioural correction restores an outcome that ratified authority already compelled, or preserves an existing deny under corrected authority; none silently replaces accepted behaviour or widens access.

Affected Downstream Documents:
[specification/volume-i/OWNER_DECISION_REGISTER.md](specification/volume-i/OWNER_DECISION_REGISTER.md) (registration only). The Volume II set: INDEX, API_CONTRACTS, APPLICATION_LAYER, BACKGROUND_PROCESSING, FRONTEND_ARCHITECTURE, RATIFICATION_STATUS_OVERLAY, IMPLEMENTATION_MATRIX (generated), SPECIFICATION_FREEZE_CANDIDATE, RETIRED_BLOCKER_CLASSIFICATION, IMPLEMENTATION_READINESS_REPORT, IMPLEMENTATION_ENTRY_MAP, IMPLEMENTATION_BACKLOG. Contract sources: S-16, S-17, S-18, S-19, S-20, S-21, S-22, S-23, S-24, S-XC. Schema: [schemas/POSTGRESQL_SCHEMA.md](schemas/POSTGRESQL_SCHEMA.md). Control: [ROADMAP.md](ROADMAP.md), [PROJECT_STATE.md](PROJECT_STATE.md), [CHANGELOG.md](CHANGELOG.md), [TODO.md](TODO.md).

## ADR-024: Shared Platform Foundations Precede Ownership Verification

Status: Accepted
Date: 2026-07-24
Owner: Owner (ratified) / implementation agent (recorded)
Reversibility: Reversible while no foundation is implemented; the dependency-ordering and command-vocabulary corrections are difficult to reverse once F-01..F-04 or S-05 depend on them.

Decision:
Ratify four shared platform foundations, and require them to precede S-05 Ownership Verification. Pre-implementation review of S-05 (recorded in `S-05_SEQUENCING_REVIEW.md`) demonstrated that S-05 is not a self-contained slice: it consumes an SSRF-safe outbound surface, envelope encryption with a key store, an append-only Evidence subsystem, and production-reachable background execution — none of which exist, and each of which the frozen specification assigned to a different slice. S-05 also crossed a security-critical outbound-surface ordering defect and its two governing Volume II sources named different WF-003 command classes. This decision introduces the four foundations as explicit, independently reviewable contracts, fixes the dependency order, and resolves the two defects. It does not implement the foundations and changes no ratified product behaviour.

The four foundations, and their canonical contracts:

1. **F-01 Shared Outbound Transport** — [specification/foundations/FOUNDATION-001_OUTBOUND_TRANSPORT.md](specification/foundations/FOUNDATION-001_OUTBOUND_TRANSPORT.md). The single guarded surface for all platform-originated DNS/HTTP; SSRF prevention before resolution and connection, DNS-rebinding pinning, redirect revalidation, size/timeout ceilings, secret redaction. Consumed by S-05 (verification observation) and S-07 (crawl).
2. **F-02 Envelope Encryption and Key Management** — [specification/foundations/FOUNDATION-002_ENVELOPE_ENCRYPTION.md](specification/foundations/FOUNDATION-002_ENVELOPE_ENCRYPTION.md). Authenticated envelope encryption behind a vendor-neutral `KeyProvider`; versioned keys, per-record DEKs, rotation, cryptographic erasure, no plaintext at rest.
3. **F-03 Evidence Producer Foundation** — [specification/foundations/FOUNDATION-003_EVIDENCE_PRODUCTION.md](specification/foundations/FOUNDATION-003_EVIDENCE_PRODUCTION.md). The append-only Evidence store and producer path. Producer-only; evaluation (validation decisions/heads, adjudication, interpretation) remains CAP-013/S-09.
4. **F-04 Background Execution Foundation** — [specification/foundations/FOUNDATION-004_BACKGROUND_EXECUTION.md](specification/foundations/FOUNDATION-004_BACKGROUND_EXECUTION.md). Production-reachable durable async execution on the existing ScheduledAction substrate + Sidekiq operational wiring; idempotent claim/lease/retry; no fake inline pathway.

Canonical dependency order (ratified):

```
F-01 -> F-02 -> F-03 -> F-04 -> S-05 -> S-06 -> S-03 ActivateProject completion -> S-07
```

Defects resolved:

- **DEF-1 (command vocabulary).** `APPLICATION_LAYER.md` (VII:108, "This section is the canonical owner of the WF-003 application contract") owns the WF-003 command vocabulary: `IssueVerificationChallenge`, `ReserveVerificationAttempt`, `CompleteVerificationAttempt`, `CancelVerificationRequest`, `ExpireVerificationRequest`, `FailVerificationRequest`; pending-challenge retrieval is the nonmutating query `QRY-021`, not a command. `contracts/S-05.json` MTX-028's divergent list (`CreateVerificationRequest`/`RetrievePendingChallenge`/`RequestOnDemandObservation`/`RunAutomatedObservationSlot`) is reconciled to that set. The Application Layer, not a slice JSON contract, is the naming authority for application commands.
- **DEF-2 (outbound surface ownership).** The statement that "S-07 owns the only outbound surface" is superseded: **all platform-originated network access passes through F-01**, and S-05 and S-07 are consumers of that one surface. There are never separate verification and crawler egress implementations. Ownership of the egress surface moves from S-07 to the F-01 foundation.

Further owner decisions ratified here:

- **KeyProvider.** F-02 depends on a vendor-neutral, versioned `KeyProvider`. The initial Genesis implementation loads a platform-managed key ring from deployment secrets, in the session-key style. No cloud-vendor secret service (AWS Secrets Manager, Google Secret Manager, Azure Key Vault, HashiCorp Vault) is hard-coded; the abstraction permits any of them later without a contract change.
- **Evidence producer/evaluator boundary.** S-05 (via F-03) may create the append-only Evidence store and produce `verification_observation` Evidence. CAP-013/S-09 retains ownership of evidence evaluation, validation heads, decisions, and the broader evidence lifecycle. Capture is separated from interpretation.

Context:
S-01..S-04 (M1 — Genesis Intake Complete) were self-contained slices with no outbound I/O, no at-rest cryptography beyond hashing, no Evidence, and no background execution. S-05 is the first slice requiring all four at once. The foundations were implicit in the specification and deferred by S-00's deliberate scope; making them explicit is completion of the dependency graph the specification itself assumes, not new scope. The verification *product* logic is fully specified (`SCORE_EVIDENCE_MODEL.md`; OD-001 ratified) and is unaffected.

Authority And Precedence:
This ADR changes no ratified product behaviour and reopens no behavioural contract. It corrects two Volume II labelling/ownership defects (a command-naming divergence and an egress-ownership statement) and makes a dependency-ordering and foundation-ownership decision within the product-architecture scope. `v1.5-volume-i-frozen` remains the authoritative Volume I baseline, byte-unchanged. No foundation-layer (000-020) content changes, so PM-REQ-009 is not engaged. `ADR-014` in this registry ("Foundation Section Mapping Registry") is unrelated and unchanged; this decision was allocated the next unused number after ADR-023.

Options Considered:

1. Implement S-05 as one monolith, inventing the SSRF adapter, encryption and Evidence subsystem inline. Rejected: it would let a product slice silently author shared security primitives and ship an unguarded outbound surface — the exact failure mode the project's governance forbids.
2. Ship a partial S-05 (requests that cannot verify), deferring the outbound observation. Rejected: it would be the first deliberately incomplete, non-production-reachable slice, weakening the established completeness standard.
3. Ratify the four foundations explicitly, fix the dependency order, resolve DEF-1/DEF-2, then build the foundations before S-05. Chosen.

Chosen-Option Rationale:
Option 3 makes the dependency graph explicit, keeps each foundation independently reviewable and production-reachable, and — because F-01 is the single shared egress surface — resolves DEF-2 structurally rather than duplicating egress logic. It preserves every ratified invariant, invents no security primitive under cover of a feature, and lets the platform catch up to the architecture it already implies before feature delivery resumes.

Consequences:

- S-05 is HELD until F-01..F-04 are contracted and built; the next implementation step is F-01, not S-05.
- One shared outbound surface exists platform-wide; S-05, S-07 and any future outbound consumer use it. No second egress path may be introduced.
- The WF-003 command vocabulary is the Application Layer's; `contracts/S-05.json` is reconciled to it.
- Encryption is KeyProvider-backed and vendor-neutral; Evidence is producer-only in this line, evaluation staying with CAP-013/S-09.
- No software, migration, endpoint or provider integration is authorized by this decision; F-01..F-04 are contracts to be implemented under their own reviews. S-01..S-04 remain complete and green (678 examples).

Affected Downstream Documents:
[specification/volume-ii/SLICE_REGISTER.md](specification/volume-ii/SLICE_REGISTER.md) (dependency order + foundation prerequisite for S-05), [specification/volume-ii/SECURITY_PERFORMANCE.md](specification/volume-ii/SECURITY_PERFORMANCE.md) (DEF-2 egress ownership), [specification/volume-ii/contracts/S-05.json](specification/volume-ii/contracts/S-05.json) (DEF-1 command set), [specification/volume-ii/contracts/S-07.json](specification/volume-ii/contracts/S-07.json) (F-01 consumer), [PROJECT_STATE.md](PROJECT_STATE.md), and the new [specification/foundations/](specification/foundations/) contracts. `contracts/S-06.json` and the crawl/evidence rows inherit the corrected ownership by reference and are not rewritten here. Unrelated ratified behaviour is unchanged.

Affected Tests, Diagrams, Schemas And Contracts:
No acceptance criterion changes and no diagram changes. `scripts/build_volume_ii_matrix.py` gains the OD-034 and OD-035 withheld-limb texts. `scripts/validate_volume_ii.py` gains `unresolved_successor_decision`, a widened retired-blocker scope and an anchor-integrity check, each with a negative mutation control, and gains regression coverage for the prior `unauthorized_verification_method` vacuity. `schemas/POSTGRESQL_SCHEMA.md` is corrected to the ratified OD-013 Option 1 shape for the Incident and Investigation tables and to the retired-blocker status for the reassessment, Role-expiry, Document-lifecycle and Issue-collision notes.

Review Checkpoint:
Revalidate when OD-034 or OD-035 is approved, because each lifts a named limb and each requires its own impact mapping at that point. Reassess no later than 2026-08-27.

## ADR-025: F-04 Background Execution Freeze — Work Dispatch Binding, Dispatch Retry, Envelope Lineage, and the G5/G6 Deferrals

Status: Accepted
Date: 2026-07-25
Owner: Owner (ratified scope + amendments) / implementation agent (recorded)
Reversibility: Difficult once S-05 and later slices depend on the frozen transport contract (the 8-field envelope, `work_id` = binding identity, the dispatch-retry semantics). The two deferrals (G5, G6) are additive and reversible.

Decision:
Freeze F-04 Background Execution as the last foundation before S-05, executing FOUNDATION-004 (ADR-024). Pre-freeze review (`F-04_COMPLETION_MATRIX.md`) found the interim skeleton implemented only the happy path; the reliability substrate the Jul-22 create migration (`20260722120007` :29-34) explicitly deferred to "the Redis/Sidekiq transport" slice was unbuilt. This decision builds and freezes that substrate and records two bounded deferrals with enforceable triggers. It changes no ratified product behaviour and invents no S-05 domain behaviour. Full completion/freeze detail: `F-04_FREEZE_REPORT.md`; frozen semantics: `F-04_TRANSPORT_DESIGN.md`.

Ratified scope decisions:

1. **G4 Work Dispatch Binding pulled INTO the freeze (not deferred).** FOUNDATION-004 property P1 is mandatory; absence from the enumerated acceptance criteria does not make it optional. A durable, insert-only, immutable `work_dispatch_bindings` row is minted in the claim transaction; its UUID **is** the envelope `work_id`; the worker resolves the authorised target THROUGH the binding (a keyed lookup, no constantisation or method dispatch), never from an envelope string. Freezing `work_id` as a scheduled-action locator and later re-meaning it as a binding identity would not be backwards-compatible (a UUID staying a UUID does not make the semantic change safe once consumers, logs, replay and idempotency depend on it). Generic `scheduled_action_dispatch` binds the action as both source and target; specialised targets are a later backwards-compatible extension (no S-05 Verification Request aggregate is invented here).
2. **Envelope conformed to the ratified eight fields** (BACKGROUND_PROCESSING.md :71-83); the interim six-field shape (`action_id`/`claim_owner`) is retired. Identifiers only, fail-closed parse.
3. **G7 correlation/causation carried PHYSICALLY in the envelope** (:81-82 lists both as envelope fields — the literal requirement, implemented rather than a DB-reload substitute). An acceptance test proves both reach the executing handler through the real Sidekiq path.
4. **G1/G2 infrastructure dispatch retry.** Failure to enqueue an already-persisted identity backs off at exactly 1/5/30/120/600 s; the sixth failure quarantines the transport record with `redis_dispatch_exhausted` and raises a redacted high alert (:313). `dispatched` is set at the worker claim CAS on the happy path (:119 blesses transfer before/after ack); only the enqueue-FAILURE path is added. Enqueue stays transaction-safe (rollback → no enqueue).

Deferred, with enforceable triggers (also in `F-04_FREEZE_REPORT.md` and enforced by a mechanism):

- **G5** queue-health gate + automatic recovery of `redis_dispatch_exhausted` records + `transport_recovery_generation` (:315). **Trigger:** mandatory before production is expected to auto-recover from a sustained Redis/Valkey outage. Not required for at-most-once or retry-exactness.
- **G6** full renewable leader-election lease (`scheduler_leases`, 15-second term + heartbeat) (:67, :112). **Trigger:** mandatory before more than one scheduler process may be configured or deployed. **Enforced now** by a LONG-LIVED singleton scheduler: `Platform::BackgroundExecution.run_scheduler` acquires `ScheduledActions::SchedulerLease` (a two-int session advisory lock) once and holds it for the process lifetime while it loops, so a second scheduler process cannot acquire it and exits without dispatching; `scheduler_lease_spec` proves exclusivity, failover, held-across-loop and front-door refusal. No committed operational configuration may run more than one scheduler process while G6 is deferred.

Foundation Evolution defect-fixes made in passing (no behaviour or contract change): the rewritten claim function preserves the executor-active `JOIN service_identities ... AND status='active'`; and the F-02 encryption fitness spec's internal-class regex was tightened from bare `Envelope` to the qualified `Encryption::Envelope` so it no longer false-positives on the unrelated `ScheduledActions::Envelope`.

Verification: 973 examples, 0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; `structure.sql` re-dumps with no drift; both databases build from empty. Independent adversarial architectural and security reviews returned no correctness or security must-fix; review-driven improvements applied (recorded in `F-04_FREEZE_REPORT.md`): (1) the single-scheduler control was strengthened to a process-lifetime held lease; (2) `Envelope.parse` validates UUID format so a malformed id fails closed cleanly; (3) the Dispatcher fails closed on a nil catalogue work_type. A subsequent read-only owner confirmation of nine freeze details found the single-scheduler control did not fully deliver two (a lost lease-holding connection was silently reconnected); the authorised bounded fixes were applied without otherwise re-opening F-04: (4) `TransportConnection.pinned` + `run_scheduler` fail closed (`:lease_lost`) on a lost lease connection and re-acquire on restart; (5) a real-Redis crash-before-ack proof; (6) production requires `rediss://`; (7) `specification/automatation/`→`specification/automation/`.

Authority And Precedence:
Executes ADR-024; reopens no behavioural contract and changes no foundation-layer (000-020) content, so PM-REQ-009 is not engaged. Allocated the next unused number after ADR-024. After this freeze the owner expects a broader architectural review before S-05 (and before any autonomous-build-controller design or implementation).

Review Checkpoint:
Re-engage G6 before configuring or deploying a second scheduler process; re-engage G5 before relying on automatic recovery from a sustained transport outage. Otherwise F-04 is frozen infrastructure: consume it, do not modify it except to fix a demonstrated defect, extend it backwards-compatibly, or improve performance without changing behaviour.

## ADR-026: Autonomous Build Controller v1 Approved For Operation

Status: Accepted
Date: 2026-07-25
Owner: Owner (approved for operation) / implementation agent (recorded)
Reversibility: The controller is internal tooling; disabling or replacing it changes no product code. The operational reviewer rule below is a safety constraint, not a reversible convenience.

Decision:
Approve Autonomous Build Controller v1 (block CTRL-01) for operation. It is repository-native, state-driven, bounded, branch-isolated, verification-gated and escalation-safe; its synthetic end-to-end proof and eight safety proofs pass, and the whole repository is green (1037 examples; Zeitwerk/Packwerk/Brakeman/bundler-audit clean). Full detail: `CONTROLLER_FREEZE_REPORT.md`; reconciliation: `specification/automation/RECONCILIATION.md`. The controller is approved as implementation infrastructure; it is not merged to a protected branch and performs no automatic merge or production action.

Operational rule (binding):
**Autonomous PRODUCT work (S-05 onward) requires a real INDEPENDENT reviewer — a separate provider or a separately invoked model with no shared conversational state — NOT the deterministic same-process `LocalReviewer` stub.** The stub is sufficient to prove orchestration and to run the synthetic self-test, but must never gate real product work. This rule is now enforced in the controller itself: a run configured with `require_independent_review` refuses (`blocked_external_dependency`) unless its reviewer reports `independent? == true`. The real reviewer adapter (`Adapters::ClaudeCodeReviewer`) and the discriminant are in place; a cross-provider reviewer remains a sensible operational improvement but does not block this approval.

Authority And Precedence:
Executes the CTRL-01 mandate (`specification/automation/AUTONOMOUS_BUILD_CONTROLLER.md`); changes no product behaviour and no frozen foundation. Allocated the next unused number after ADR-025. The first authorised product pilot is `S-05-001 IssueVerificationChallenge` (`CONTROLLER_FREEZE_REPORT.md` §proposed); it runs only under the operational rule above.

Review Checkpoint:
Before trusting autonomous implementation across many tranches, replace the stub with a genuine cross-provider reviewer. Re-review the controller if a defect surfaces in operation.

## ADR-027: S-05-001 IssueVerificationChallenge — First Autonomous Product Tranche

Status: Accepted
Date: 2026-07-25
Owner: Owner (approved the first pilot: "Run S-05-001") / implementation agent (recorded)
Reversibility: The tranche is committed on an isolated branch (`tranche/S-05/S-05-001`), verified and independently reviewed, but NOT merged. It is fully reversible until the owner accepts it. It changes no frozen foundation contract and no existing product behaviour.

Decision:
Implement the first S-05 limb — `Workflows::Wf003::IssueVerificationChallenge` (APPLICATION_LAYER §WF-003 / DEF-1, ADR-024; contracts/S-05.json MTX-028/051/056/071; SCORE_EVIDENCE_MODEL §Ownership-Verification; OD-001 ratified, ADR-019). An authorized OrganizationAdmin or TechnicalImplementer opens ownership verification for a proposed Source: one pending `verification_requests` row is created, one challenge token (>=128 bits) is issued and protected behind F-02 (only its F-02 ciphertext reference, a protection-profile key reference and the SHA-256 digest are stored; the plaintext is returned solely in the authorized response), and the 24-hour expiry is scheduled through F-04 (`verification_request_expire`, already in the ratified catalogue) — all in one atomic transaction with the `SourceVerificationRequested` event, restricted audit, command result and idempotency record. Run through the autonomous controller's discipline: enforced preflight/postflight gates, isolated tranche branch, deterministic verification, and an independent review (ADR-026). Suite 1073 examples / 0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; DB permissions/RLS OK; no structure.sql drift.

Decision Ledger (tranche-introduced decisions):
- **runtime_grants.rb additive new-table grant — Authority: Foundation Consumption Rule (backwards-compatible extension).** The new `verification_requests` table needs least-privilege runtime grants, and `lib/f1/runtime_grants.rb` is the single convergence point for runtime privileges (structure.sql carries none). That file is on the controller's `FrozenContracts` denylist, but the owner-ratified Foundation Consumption Rule authorizes a *backwards-compatible extension* (add a new table's grants without changing any existing grant or weakening an invariant) as act-don't-stop, and the owner's standing guidance is that infrastructure proceeds and "the next L3 stop is product semantics, not infrastructure." The grant is `SELECT, INSERT, UPDATE` (never DELETE; deletion is cryptographic erasure of the F-02 envelope), FORCE RLS preserved. Classified and recorded rather than escalated. **See the non-blocking recommendation below.**
- **F-02 wrapping-key provisioning substrate — Authority: reproducible-provisioning standard (autonomous).** S-05 is F-02's first real consumer, and F-02 froze without any key-ring bootstrap (`DeploymentKeySource` reads `F1_ENCRYPTION_KEY_RING`; the DB holds only the fingerprint). Added OUTSIDE the frozen surface: a fixed NON-SECRET dev/test key ring (`lib/f1/dev_encryption_key_ring`), an initializer defaulting the env var in local environments only (`Rails.env.local?`, empty-var guard), and an idempotent `f1:db:ensure_encryption_key` that registers the matching active version — wired into the provision route, the db:migrate hook and `bin/f1-provision-db`, mirroring `ensure_context_key`. Production/staging supply the ring out of band; the default never applies there.
- **`challenge_key_id` = protection-profile identifier — Authority: Assumption.** The SCORE_EVIDENCE contract lists both `challenge_ciphertext_reference` and `challenge_key_id`; F-02's frozen façade returns a single opaque `reference` and manages wrapping-key versions internally. Reaching around the façade for the internal key version would violate the Consumption Rule, so `challenge_key_id` records the stable non-secret protection-profile id (`challenge-token-envelope-v1`); both are nulled together on the later cryptographic-deletion limb.
- **AAD binding = (application=verification, record_type=verification_request, record_id=request id, purpose=challenge_token, tenant=org) — Authority: autonomous (security default).** Binds each ciphertext to its Request and tenant, so it cannot be relocated across Requests or Organizations.
- **`source.verify` Permission Baseline row and S-05 ErrorCatalog reasons — Authority: autonomous (data addition).** `source.verify` allows OrganizationAdmin and TechnicalImplementer (contracts/S-05.json permission_checks); the S-05 reason codes are added to the fixed error map. Neither changes evaluator/engine semantics.

Independent Review (ADR-026):
Reviewed by a separately invoked model with no shared conversational state, against the committed diff. Verdict: **pass_with_observations, zero blocking findings**. It confirmed token-at-rest secrecy, tenant/actor isolation, atomic single-transaction commit, least-privilege additive grants, correct AAD binding, dev-key-ring gating, and frozen-façade compliance. Review-driven repairs applied: a restricted security access-log audit is now written on every challenge redelivery (replay) and on `challenge_redelivery_unavailable` (S-05.json audit_record: "retrieval and replay each append a restricted security access log"); two security-property tests were added (a different same-org actor reusing the idempotency key gets `verification_in_progress`, never the token; a ciphertext cannot be revealed under another Request's AAD record binding); and two clarity comments. Non-blocking notes for future limbs: production key-rotation version selection, and the idempotency `(target_type, target_id)` labelling.

Authority And Precedence:
Consumes F-01..F-04 through their frozen façades only; changes no frozen foundation contract. Allocated the next unused number after ADR-026. Stops at `ready_for_review` per the controller mandate; no automatic merge, no production path.

Non-Blocking Owner Recommendation (controller refinement):
The controller's `FrozenContracts` denylist (v1) escalates on ANY change to `lib/f1/runtime_grants.rb`, but EVERY future tenant-table slice (S-06, S-07, …) must add an additive least-privilege grant there — that file's own charter says "Update this module … when a table … changes." The v1 controller has no evolution-rule exception, so it would escalate on every new-table grant, contradicting the ratified Foundation Consumption Rule and the owner's "infrastructure proceeds" guidance. Recommendation: refine `FrozenContracts` to distinguish an additive new-table grant (no existing grant changed, no privilege widened, FORCE RLS preserved) — which proceeds under the Consumption Rule — from a privilege-boundary change (a new DELETE, a widened role, a weakened RLS predicate) — which still escalates. This is a controller-enforcement change (a security tripwire) and is left for owner ratification rather than made autonomously here.

## ADR-028: S-05-001 Accepted And Merged; Next Tranche (S-05-002) Is A Human Decision

Status: Accepted
Date: 2026-07-26
Owner: Owner (approved: "Approve and merge S-05-001 …") / implementation agent (recorded)
Reversibility: The merge is a fast-forward on the non-protected integration branch `implementation/s01-registration-access`; nothing is pushed and `main` is untouched, so it is revertible. The next-tranche question below is left open for the owner.

Decision:
Accept S-05-001 IssueVerificationChallenge. Its review artifacts, verification and independent review satisfy repository governance: two independent reviews (ADR-026, separately invoked models with no shared conversational state) returned pass_with_observations with zero blocking findings and all recommendations applied; whole-repo suite 1076 examples / 0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; `verify_runtime` OK (RLS intact); no `structure.sql` drift; the only frozen-path touch (`lib/f1/runtime_grants.rb`) is the additive least-privilege grant classified under the Foundation Consumption Rule (ADR-027). Fast-forward merged into `implementation/s01-registration-access` at `d35a4c9`; `S-05-001` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-05-001 → completed; `S-05-001_COMPLETION_REPORT.md` marked accepted.

Next Tranche — Genuine Human Decision (HD-S05-002-SCOPE):
Per BUILD_STATE/BUILD_PLAN (authoritative), the next block is **S-05-002**, which is `human_gate_before: true` with scope `TO_BE_DEFINED_FROM_AUTHORITATIVE_SOURCES`. The WF-003 command vocabulary is ratified (Issue / Reserve / Complete / Cancel / Expire / Fail; retrieval is QRY-021), but **no authoritative source dictates the S-05 sub-limb build order** — the freeze report only ever defined S-05-001. Choosing the next limb is therefore a product-sequencing decision, and the standing instruction is "do not skip, reorder or manually select tranches." The enforced controller (`bin/autonomous-build run-next`) stops at this human gate with `human_decision_required`. This is a genuine human decision, not a defect or a skip: the controller is following its own rules and the authoritative plan.

Recommended Option:
**S-05-002 = `ExpireVerificationRequest`.** S-05-001 schedules a `verification_request_expire` action whose handler (`ExpireVerificationRequest`, per the ratified catalogue) does not yet exist, so a real deployment would carry a dangling scheduled action. Building the expiry handler next closes that loop, is small (pending → expired, `SourceVerificationExpired`, schedule cryptographic deletion), consumes no outbound surface and produces no Evidence, and keeps the request lifecycle safe before the large observation limb. Alternatives: `CancelVerificationRequest` (also small), or the observation limb `ReserveVerificationAttempt` + `CompleteVerificationAttempt` (the core proposed → verified transition; the most product-semantic and largest — consumes F-01 outbound and F-03 Evidence and the DNS/HTTP predicates; likely warrants its own review checkpoint).

Also For This Decision (carry-over from ADR-027):
Ratify or decline the controller `FrozenContracts` refinement so an additive new-table grant is not a mandatory escalation. It recurs immediately: the observation limb adds a `verification_attempts` table (another additive `runtime_grants` entry).

Authority And Precedence:
Executes the owner's accept-and-merge instruction and the controller mandate. Allocated the next unused number after ADR-027. No automatic merge to the protected branch and no production path. Stops at the human gate per the mandate.

## ADR-029: S-05-002 Designated (ExpireVerificationRequest); FrozenContracts Refinement Ratified

Status: Accepted
Date: 2026-07-26
Owner: Owner (designated the tranche and ratified the refinement) / implementation agent (recorded)
Reversibility: The designation queues a tranche that stops at ready_for_review (revertible). The FrozenContracts refinement is a controller-enforcement change landed with its own tests and independent review.

Decision 1 — Next tranche designated:
Resolving HD-S05-002-SCOPE (ADR-028), the owner designates **S-05-002 = `Workflows::Wf003::ExpireVerificationRequest`** and clears its `human_gate_before`. Scope (contracts/S-05.json MTX-028/005/051; SCORE_EVIDENCE_MODEL § Attempts, Expiry, And Evidence): the service-executed handler for the due `verification_request_expire` ScheduledAction that S-05-001 schedules transitions a still-pending Request `pending -> expired` with reason `challenge_expired` at `expires_at_utc`, emits `SourceVerificationExpired` exactly once, makes challenge redelivery unavailable and destroys the challenge material (F-02 erase; the digest and access audit survive), and relaxes the `verification_requests` lifecycle guard for exactly the `pending -> expired` edge. It leaves the Source `proposed`, runs no observation, and closes the dangling `verification_request_expire` action left by S-05-001. Runs to `ready_for_review` under the controller; the tranche after S-05-002 must NOT be begun.

Decision 2 — FrozenContracts refinement ratified (from ADR-027):
The controller `FrozenContracts` denylist is refined so a **purely additive new-table grant** to `lib/f1/runtime_grants.rb` (no existing grant changed, no line removed, no `DELETE` privilege introduced, FORCE RLS preserved) is a backwards-compatible extension under the Foundation Consumption Rule and does **not** escalate, while any **privilege-boundary change** (a new `DELETE`, a widened role, a modified/removed existing grant, or a change to any other frozen surface — the F-01..F-04 façades and their single-surface fitness specs) still escalates as a mandatory human decision. Implemented as a content-aware, fail-closed classifier (any non-additive or non-parseable change escalates) with its own `spec/automation` tests and an independent review, committed as controller housekeeping (the controller is internal tooling; precedent: the CTRL housekeeping commit).

Authority And Precedence:
Executes the owner's designation and ratification. Allocated the next unused number after ADR-028. No automatic merge to the protected branch, no production path; the product tranche stops at ready_for_review.

## ADR-030: S-05-002 ExpireVerificationRequest — Completion (ready_for_review)

Status: Accepted
Date: 2026-07-26
Owner: Owner (designated the tranche, ADR-029) / implementation agent (recorded)
Reversibility: Committed on branch `tranche/S-05/S-05-002` (off `58383dd`), verified and independently reviewed, NOT merged; `main` untouched, nothing pushed. Fully reversible until owner acceptance.

Decision:
Implement the WF-003 expiry limb `Workflows::Wf003::ExpireVerificationRequest` (SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And Evidence; contracts/S-05.json MTX-028/005/051). The service-only handler for the due `verification_request_expire` ScheduledAction that S-05-001 schedules transitions a still-pending Request `pending -> expired` with reason `challenge_expired`, cryptographically destroys the challenge material (F-02 erase, atomic with the transition), emits `SourceVerificationExpired` exactly once, and leaves the Source `proposed`. Service-attributed (null human actor); the immutable challenge digest and the audit survive. It closes the dangling `verification_request_expire` action left by S-05-001. Migration relaxes the `verification_requests` lifecycle guard for exactly the `pending -> expired` edge; the registry maps the kind to the handler (fail-closed). Suite 1103 examples / 0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; verify_runtime OK; no structure.sql drift.

Independent Review (ADR-026):
A separately invoked model with no shared conversational state reviewed the committed diff: **pass_with_observations, zero blocking findings**. It confirmed atomic challenge destruction (capture-before-null, same transaction, no destroyed-but-not-expired or expired-but-not-destroyed state, no double-erase), the minimal-and-correct guard relaxation (only pending->expired; every other transition still refused; identity/issuance still frozen), the due/target guards and "equality at expires_at is due", idempotent replay, state-version-guarded concurrency, service attribution, and frozen-façade compliance. Review-driven repairs applied (test-only, no product change): an end-to-end assertion that redelivery is unavailable through the issuance path after expiry (terminal replay returns no token), and a not-found-target test.

Decision Ledger:
| Decision | Authority | Reason |
| --- | --- | --- |
| Relax the lifecycle guard for exactly `pending -> expired` | Autonomous (the plan's edge) | The expiry limb's one ratified transition; every other edge stays refused. |
| Service-attributed `VerificationExpiryStore` (RoleExpiryStore shape, WF-003) | Autonomous (established pattern) | Expiry is the lifecycle service's act, null human actor (exactly_one_actor_or_service). |
| `verification_request_not_pending` -> F1-DOMAIN-409 | Autonomous (data addition) | A timer for an already-terminal Request is a harmless state conflict (mirrors role_assignment_not_active). |
| Inline F-02 erase (immediate) rather than a scheduled 60s deletion job | Assumption (behaviourally stronger; plan-authorized) | See the FLAGGED divergence below. |

FLAGGED Volume I divergence (owner reconciliation, not silently changed):
The canonical `SCORE_EVIDENCE_MODEL.md` (§ Verification Request) and `contracts/S-05.json` MTX-028 `background_job` describe the terminal transaction as SCHEDULING cryptographic deletion (a `ChallengeCryptographicDeletionJob` / the reserved `verification_material_destroy` action kind, `catalogue.rb`), with "destroyed within 60 seconds." This tranche destroys the material INLINE in the terminal transaction (0s, atomic) — a strict strengthening that meets every observable guarantee (immediate redelivery unavailability, digest + audit survive) and is authorized by the BUILD_PLAN S-05-002 scope. Consequences: (a) `verification_material_destroy` is now an orphaned catalogue kind (nothing schedules it, no handler), and (b) the Volume I prose still says the deletion is a scheduled 60s job. Per the constitution ("one canonical source of truth; update earlier documents if architecture changes"), this should be reconciled — update the model/contract prose and/or retire the reserved kind. Recorded as a flagged Volume I item for owner reconciliation (the S-04 `organization_inactive` precedent: a later slice surfaces a Volume I divergence rather than rewriting frozen Volume I).

Authority And Precedence:
Consumes F-01..F-04 through their frozen façades only; no frozen contract changed. Allocated the next unused number after ADR-029. Stops at ready_for_review per the mandate; no automatic merge, no production path. Per owner instruction, the tranche after S-05-002 is NOT begun.

## ADR-031: S-05-002 Accepted And Merged

Status: Accepted
Date: 2026-07-26
Owner: Owner (approved: "Approve and merge S-05-002 …") / implementation agent (recorded)
Reversibility: Fast-forward on the non-protected integration branch; nothing pushed, `main` untouched; revertible.

Decision:
Accept S-05-002 ExpireVerificationRequest. Repository gates satisfied: independent review (ADR-026) pass_with_observations with zero blocking findings; suite 1103 examples / 0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; verify_runtime OK; no structure.sql drift; no frozen contract changed. Fast-forward merged into `implementation/s01-registration-access` at `92eb065`; `S-05-002` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-05-002 → completed; completion report marked accepted.

Outstanding (carried, non-blocking): the ADR-030 flagged Volume I reconciliation (inline F-02 erase vs the canonical scheduled 60s `verification_material_destroy` deletion prose; orphaned reserved kind) remains for owner reconciliation; it is a documentation/prose divergence, not a gate failure, so it does not block the merge.

Authority And Precedence:
Executes the owner's accept-and-merge instruction. Allocated the next unused number after ADR-030. No automatic merge to the protected branch; no production path.

## ADR-032: S-05-003 Observation Limb Is Too Large — Proposed Split (stop for owner approval)

Status: Proposed (awaiting owner approval)
Date: 2026-07-26
Owner: Implementation agent (proposal) / Owner (approval required)
Reversibility: No product code written. This is a BUILD_PLAN proposal only; nothing is implemented until the owner approves the split and authorises the first sub-tranche.

Context:
The owner designated S-05-003 = "Observation (Reserve + Complete)" and instructed: "If implementation reveals that the Observation limb is too large to remain a single coherent tranche, stop before implementation and propose a repository update that splits it into smaller authorised tranches." Pre-implementation scoping against contracts/S-05.json (MTX-028/051), SCORE_EVIDENCE_MODEL.md § Attempts/Expiry/Evidence and § DNS/HTTP methods, and schemas/POSTGRESQL_SCHEMA.md :288/:286 confirms it is too large.

Why it is too large (each item is a full tranche's worth, comparable to F-01 or S-05-001/002):
1. A complete SSRF-safe outbound OBSERVATION ENGINE consuming F-01: DNS TXT (_f1-verify.<host>, exact match, segment concatenation, case/whitespace rules, observed_value_sha256, resolver reasons) and HTTPS file (/.well-known/f1-verification.txt, 200 + <=4KiB + trailing-LF, the exact 4096/4097-byte boundary + hashing, no redirects, status mapping), with 14 reason codes.
2. A NEW verification_attempts table (T-MUT/LINEAGE/WORK-CLAIM — tied into F-04's work-dispatch/claim machinery: `verification_observe` claims `verification_attempts`) plus ReserveVerificationAttempt (atomic id/count/marker, on-demand limit(10)/rate(5min)/concurrency).
3. CompleteVerificationAttempt producing exactly one restricted verification_observation Evidence (F-03) + SourceVerificationObserved per started observation, with idempotent retry.
4. The atomic multi-root SUCCESS commit — Request verified/matched + redelivery disablement + SourceVerified + Source.proposed->verified — "none may appear without the others".
5. source-scope-interim-v1 materialization via a SourceScopePolicyRepository — the Source Scope sub-system (source_set_versions / source_set_memberships / source_scope_change_requests), which is S-06 territory.
6. The 10-slot AUTOMATED SCHEDULE (0..1380 min half-open windows, AutomatedObservationSlotJob, observation_slot_skipped, terminal-state cancellation).

Bundling all six into one tranche violates the controller's smallest-reviewable-tranche standard and would be unreviewable.

Proposed split (five sub-tranches, dependency order; each derived from the authoritative sources, NOT invented; recorded in BUILD_PLAN as status: proposed, human_gate_before: true):
- **S-05-003** Outbound observation engine (pure; F-01 only) — the DNS/HTTP predicates + hashing + reason vocabulary. No persistence.
- **S-05-004** verification_attempts table + ReserveVerificationAttempt — reservation, counts, marker, on-demand guards.
- **S-05-005** CompleteVerificationAttempt (observation recording) — run the engine; one verification_observation Evidence (F-03) + SourceVerificationObserved + Request completion; NON-verifying outcomes leave the Source proposed.
- **S-05-006** Matched success commit + source-scope-interim-v1 — the atomic Request-verified + Source proposed->verified + scope-policy materialization. **Carries an architectural dependency (below).**
- **S-05-007** Automated observation slot schedule — the 10 half-open slots + skip logic (F-04).

Flagged architectural dependency (genuine human decision, blocks S-05-006):
The success commit requires materializing source-scope-interim-v1 (SourceScopePolicyRepository) — the Source Scope Policy artifact, which is the S-06 Source Scope sub-system. The owner must decide whether the minimal materialization artifact is built inside S-05-006, or is an S-06 prerequisite that must precede it (a possible second foundation-style sequencing question, echoing the F-01..F-04 wall that preceded S-05). This can be deferred until S-05-006 is reached, but it should be decided before S-05-006.

Recommendation:
Approve the five-sub-tranche split and authorise **S-05-003 (the observation engine)** as the next tranche — it is the largest self-contained, pure, F-01-only unit and the natural first build (mirroring how F-01 preceded its consumers), and it unblocks S-05-004/005 without touching persistence. Decide the scope-policy dependency (item above) before S-05-006.

Authority And Precedence:
No frozen contract touched; no product code written. Allocated the next unused number after ADR-031. The controller is stopped at human_decision_required per the owner's explicit escape-hatch instruction; the tranche after the (approved) next one is not begun.

## ADR-033: S-05-003 Observation Split Accepted; S-05-003 Authorised

Status: Accepted
Date: 2026-07-26
Owner: Owner (approved: "Approve ADR-032 … Accept the five-sub-tranche decomposition") / implementation agent (recorded)
Reversibility: Plan/state change plus a product tranche that stops at ready_for_review; revertible.

Decision:
Approve ADR-032. The Observation limb decomposes into the authoritative sequence S-05-003..S-05-007 (BUILD_PLAN updated: the split blocks are no longer "proposed"; S-05-003 is `planned` with `human_gate_before: false`; S-05-004..007 are `not_started` with `human_gate_before: true` until authorised in turn). Authorise **S-05-003 — the pure F-01 outbound observation engine** as the next tranche and run it to `ready_for_review` under the controller (enforced preflight/postflight, deterministic verification, independent review, records, commits). Do not begin S-05-004.

The flagged architectural dependency (source-scope-interim-v1 / Source Scope, S-06) is carried forward; it blocks S-05-006 only and will be decided before that sub-tranche.

Authority And Precedence:
Resolves HD-S05-003-SPLIT. Allocated the next unused number after ADR-032. No frozen contract changed; no automatic merge; no production path.

## ADR-034: S-05-003 Observation Engine — Completion (ready_for_review)

Status: Accepted
Date: 2026-07-26
Owner: Owner (authorised S-05-003, ADR-033) / implementation agent (recorded)
Reversibility: Committed on branch `tranche/S-05/S-05-003` (off `05c2011`), verified and independently reviewed, NOT merged; `main` untouched. Fully reversible.

Decision:
Implement the first Observation sub-tranche — `Workflows::Wf003::VerificationObservation`, the pure outbound observation engine (SCORE_EVIDENCE_MODEL.md § DNS TXT / HTTP File Method; contracts/S-05.json MTX-028). Given (method, canonical_host, token) it performs one guarded observation through the frozen F-01 façade and applies the ratified predicate, returning the network outcome, nullable status, received byte count, observed_value_sha256, match decision and one of the 14 reason codes. DNS: `_f1-verify.<host>`, exact ASCII match, per-record segment concatenation, case/whitespace failures, the LF-joined-UTF-8-record-values hash (null on absent), resolver reasons. HTTP: `/.well-known/f1-verification.txt`, 200 + ≤4KiB + ≤1 trailing-LF equality, the 4096/4097 boundary + raw-bytes hashing, no redirects, the full status/transport mapping. It performs no persistence, produces no Evidence and transitions nothing (later sub-tranches). Restricted-safe: no plaintext token or raw content in the output. Suite 1123 examples / 0 failures; architecture fitness 31/0 (consumes ONLY F-01; no second egress); Brakeman/Packwerk/Zeitwerk clean; no structure.sql change (pure engine).

Independent Review (ADR-026):
A separately invoked model with no shared conversational state reviewed the committed diff and byte-level-reproduced the hashing and boundary rules: **pass_with_observations, zero blocking findings**. It confirmed DNS byte-exactness + hash, HTTP hash-before-trim, the 4096/4097 boundary, the status/transport mapping, the match-decision invariant (matched / definite-non-match=not_matched / dependency-failure=indeterminate), restricted-safety and frozen-façade compliance. Review-driven repairs applied (no behavior change): corrected the SSRF-rejection comment (that path is reachable and correctly indeterminate) and added tests for the non-redirect rejected path, the :resolver_failure reason_code, and hash-before-trim on the trailing-LF path.

Decision Ledger:
| Decision | Authority | Reason |
| --- | --- | --- |
| Engine consumes F-01 via injected `outbound:` (default Platform::Outbound) | Autonomous | Deterministic tests with no live network; still the single frozen egress surface. |
| Match decision = matched / not_matched / indeterminate by reason class | Autonomous (contract) | Definite non-matches are not_matched; dependency failures are indeterminate (stay pending). |
| DNS hash over raw resolver octets (`.b`), LF byte between records | Assumption | Byte-identical to UTF-8 for realistic ASCII TXT content; robust for arbitrary DNS character-strings. |
| `dns_response_code` left null (F-01 surfaces no rcode) | Assumption | The reason code (e.g. dns_nxdomain) carries the semantic; the field is nullable. |

Authority And Precedence:
Consumes only the frozen F-01 façade; no frozen contract changed. Allocated the next unused number after ADR-033. Stops at ready_for_review; no automatic merge, no production path. Per owner instruction, S-05-004 is NOT begun.

## ADR-035: S-05-003 Accepted And Merged; Next Tranche (S-05-004) Is A Human Gate

Status: Accepted
Date: 2026-07-26
Owner: Owner (approved: "Approve and merge the current tranche if, and only if, all repository governance requirements are satisfied") / implementation agent (recorded)
Reversibility: Fast-forward on the non-protected integration branch `implementation/s01-registration-access`; nothing pushed and `main` untouched, so it is revertible. The next-tranche authorisation below is left open for the owner.

Decision:
Accept S-05-003 — the pure outbound observation engine `Workflows::Wf003::VerificationObservation` (ADR-034). Repository governance is fully satisfied and was re-verified at the merge, not taken on the completion report's word:
- Verification (re-run at the tranche tip d1712e6): whole-repo suite 1124 examples / 0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness 31/0 (the F-01 single-surface fence — the engine consumes only the frozen `Platform::Outbound` façade); no `db/structure.sql` change (a pure engine with no migration, so `migration_safety_no_drift` is not a required check for this tranche). A `db:schema:dump` drift observed during checking was a stale local development database missing the already-merged S-05-001/002 migrations, not a tranche defect; the working tree was restored.
- Independent review (ADR-026): the recorded review (ADR-034) was pass_with_observations with zero blocking findings; in addition, a fresh independent re-review of the committed diff by four separately-invoked lenses with no shared conversational state (contract-correctness, restricted-safety/security, test-adequacy, architecture/frozen-contract) returned **PASS_NO_BLOCKING** — 0 blocking findings raised, 0 confirmed-blocking after an adversarial verify pass, 15 non-blocking findings (9 observations, 5 false-positives, 1 low). Nothing required repair (governance repairs confirmed blocking findings only).
- Scope: the diff is 6 files / 517 lines (the engine + its spec + record files); it touches no frozen-foundation path (`app/platform/**`, `lib/f1/runtime_grants.rb`, `db/**` all untouched), so no frozen-contract escalation applies.

Fast-forward merged into `implementation/s01-registration-access` at `d1712e6`; `S-05-003` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-05-003 → completed; `S-05-003_COMPLETION_REPORT.md` marked accepted; the merged tranche branch `tranche/S-05/S-05-003` deleted per repository policy (S-05-001/002 precedent).

Non-blocking findings recorded for later limbs (do not block this merge; no confirmed defect):
- A 3xx response surfaced by F-01 as a plain response without a Location header maps to `http_status_mismatch` rather than `http_redirect_rejected` — both are `not_matched` with identical request-lifecycle effect; a defensible edge interpretation.
- A DNS `:destination_host_invalid` refusal maps to `dns_temporary_failure`/indeterminate; `canonical_host` is validated at Request creation, so this is effectively unreachable, and keeping it pending never verifies and never disables.
- Field-level test-coverage gap (low): `network_outcome` is asserted for only some reason codes (three currently-correct predicates lack an assertion on that field). No hidden defect; a candidate test-only addition for a future limb.

Next Tranche — Genuine Human Decision (HD-S05-004-AUTHORISE):
Per BUILD_STATE/BUILD_PLAN (authoritative), the next block is **S-05-004** (verification_attempts + ReserveVerificationAttempt), which is `human_gate_before: true` and remains unauthorised under the owner-accepted Observation split (ADR-033: "S-05-004..007 remain human_gate_before until authorised in turn"). Its scope is already fixed by the split and BUILD_PLAN, so this is an authorise-to-proceed gate, not a scope choice. The enforced controller stops here with `human_decision_required`; per "do not manually choose, skip, reorder or combine tranches", the controller does not self-authorise the next tranche. This is a genuine human gate, not a defect or a skip.

Recommended Option:
**Authorise S-05-004 as specified.** It is the next block in the authoritative dependency sequence S-05-003..S-05-007, introduces the `verification_attempts` WORK-CLAIM table and the atomic `ReserveVerificationAttempt` (with the on-demand limit(10) / rate(5min) / concurrency guards), and unblocks S-05-005/006. It adds an additive least-privilege grant to `lib/f1/runtime_grants.rb`, already ratified as non-escalating under the FrozenContracts additive-new-table rule (ADR-029). The flagged source-scope-interim-v1 / Source Scope (S-06) architectural dependency affects S-05-006 only and need not be decided now.

Authority And Precedence:
Executes the owner's conditional accept-and-merge instruction and the controller mandate. Allocated the next unused number after ADR-034. No automatic merge to the protected branch and no production path; the controller stops at the human gate per the mandate.

## ADR-036: S-05-004 Authorised (verification_attempts + ReserveVerificationAttempt); Human Gate Cleared

Status: Accepted
Date: 2026-07-26
Owner: Owner (approved: "Authorise S-05-004 as specified in BUILD_PLAN and ADR-033. Clear its human_gate_before ... Then execute S-05-004 through the autonomous controller.") / implementation agent (recorded)
Reversibility: Plan/state change plus a product tranche that stops at ready_for_review on an isolated branch; revertible until owner acceptance. `main` untouched.

Decision:
Resolving HD-S05-004-AUTHORISE (ADR-035), the owner authorises **S-05-004 — `verification_attempts` table + `Workflows::Wf003::ReserveVerificationAttempt`** exactly as specified in BUILD_PLAN and the owner-accepted Observation split (ADR-033), and clears its `human_gate_before`. No scope change: the scope was already fixed by the split. Scope (contracts/S-05.json; SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And Evidence; schemas/POSTGRESQL_SCHEMA.md):
- the `verification_attempts` table — attempt lifecycle (reserved/running/completed/quarantined), trigger (automated/on_demand), slot offset, outcome columns, `unique (verification_request_id, attempt_number)`, forced tenant RLS, and a lifecycle/immutability guard;
- `ReserveVerificationAttempt` — the atomic reservation that allocates the next `attempt_number`, increments the Request's counts and sets the in-progress marker, serialized on the Request (concurrent reserves cannot share a slot);
- the three on-demand denials at their exact boundaries — `on_demand_limit_reached` (10), `on_demand_observation_in_progress`, `on_demand_rate_limited` (5 min) — with `attempt_count` never incrementing on a rejection.

Out of scope (later sub-tranches, unchanged): running the observation (S-05-003 engine is consumed later), Evidence (F-03), the matched success commit, the automated slot schedule. No frozen foundation contract change, no destructive migration, no production path.

Additive grant note (ratified precedent): S-05-004 adds a new tenant table, so it adds an additive least-privilege grant to `lib/f1/runtime_grants.rb` — a backwards-compatible extension that does **not** escalate under the FrozenContracts additive-new-table rule (ADR-029).

Authority And Precedence:
Executes the owner's authorisation and the controller mandate. Allocated the next unused number after ADR-035. Runs to `ready_for_review` under the controller (isolated branch `tranche/S-05/S-05-004`, enforced preflight/postflight, deterministic verification, independent review, records, commits); no automatic merge, no production path. Per owner instruction, S-05-005 is NOT to be begun.

## ADR-037: S-05-004 verification_attempts + ReserveVerificationAttempt — Completion (ready_for_review)

Status: Accepted
Date: 2026-07-26
Owner: Owner (authorised S-05-004, ADR-036) / implementation agent (recorded)
Reversibility: Committed on branch `tranche/S-05/S-05-004` (off `891e295`), verified and independently reviewed, NOT merged; `main` untouched, nothing pushed. Fully reversible until owner acceptance.

Decision:
Implement the WF-003 on-demand reservation limb — the `verification_attempts` child table of the `verification_requests` aggregate and `Workflows::Wf003::ReserveVerificationAttempt` (schemas/POSTGRESQL_SCHEMA.md :288; SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And Evidence; contracts/S-05.json MTX-028). An authorized actor (`source.verify`) reserves the next attempt slot on a pending Request: serialized on the Request under the expiry service's advisory-lock key, it atomically inserts one `reserved` on_demand attempt (`attempt_number = attempt_count + 1`), increments the total and on-demand counts and stores `on_demand_in_progress_attempt_id`, with the count/marker `UPDATE` guarded on `request_status = 'pending' AND state_version = <read>` (a lost race rolls the whole reservation back). The four denials hold at their exact boundaries and write nothing (so `attempt_count` never moves): `verification_request_not_pending`, `on_demand_limit_reached` (count = 10), `on_demand_observation_in_progress` (marker set), `on_demand_rate_limited` (`now < last + 5 min`; equality allowed). Idempotency is checked before the state-version check so an exact replay returns the same reserved attempt despite the advanced version. The table has forced RLS, composite FKs to `verification_requests`/`sources`, `unique (verification_request_id, attempt_number)`, the `reserved_has_no_outcome` and `slot_offset_matches_origin` CHECKs, and a lifecycle guard that freezes the reservation and withholds every state transition until the completion limb. No provider call, no Evidence, no domain event, no Request or Source transition (all later limbs). Suite 1149 examples / 0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; verify_runtime OK (RLS intact); no structure.sql drift; architecture fitness 31/0.

Independent Review (ADR-026):
Five adversarial lenses by separately-invoked models with no shared conversational state (contract-correctness, security/tenant-isolation, migration/schema, test-adequacy, architecture/frozen-contract): **PASS_NO_BLOCKING — zero blocking findings, zero confirmed-blocking after the verify pass.** Confirmed the reservation atomicity, the four boundary denials, `attempt_count`-unchanged-on-rejection, the state-version guard, the idempotency-before-version ordering, the migration against the canonical schema (no drift), the RLS/FK/CHECK/guard invariants, least-privilege grant (no DELETE), and frozen-façade compliance. Review-driven repairs applied (comment/dead-code accuracy only, no behaviour change; the prior tranches' "comment accuracy" precedent): corrected the outcome-order docstring and removed three unused migration constants.

Decision Ledger:
| Decision | Authority | Reason |
| --- | --- | --- |
| `verification_attempts` grant SELECT/INSERT/UPDATE (no DELETE) | Foundation Consumption Rule (additive new-table, ADR-029) | The reserve inserts and later limbs transition the attempt in place; deletion never happens (quarantine/terminal are state transitions). Non-escalating. |
| `attempt_number = attempt_count + 1` under the per-Request lock | Autonomous (contract) | The serialized reservation makes the number dense and unique; `unique (verification_request_id, attempt_number)` backstops it. |
| Reserve-specific `deny` override keyed on the Request | Autonomous (established pattern) | The shared VerificationLedger `deny` builds its payload from `command.source_id`; the reserve command's target is the Request (no source_id member), so the override records the Request and threads the Source through the authorization decision only. |
| Idempotency checked before the state-version check | Autonomous (correctness) | A successful reserve advances the Request version; an exact replay must return the same attempt, not `stale_state_version`. |
| S-04 forward-guard specs no longer assert `verification_attempts` absent | Autonomous (internal consistency; constitution "update earlier documents") | The table now legitimately exists; the source-set/scope tables remain asserted absent. |

Non-blocking findings recorded (not actioned per the owner's "confirmed blocking only" instruction; carried for owner consideration or a later limb): (medium) no direct two-racer concurrency test — the property is enforced by the advisory lock + state-version guard + the unique index (the last proven in the invariants spec); (low) the rate-limit reject boundary could be pinned tighter than 4 min; (observation) no direct test that a denied reserve writes no idempotency record; (observation) `idempotency_conflict` is ordered after the on-demand denials, matching IssueVerificationChallenge; (considered/dismissed) the WORK-CLAIM tag on `verification_attempts` refers to `work_dispatch_bindings` referencing it (POSTGRESQL_SCHEMA.md :226), not claim columns on the attempt table, so the :288 column list is implemented exactly.

Authority And Precedence:
Consumes F-01..F-04 through their frozen façades only; no frozen contract changed. Allocated the next unused number after ADR-036. Stops at ready_for_review per the mandate; no automatic merge, no production path. Per owner instruction, S-05-005 is NOT begun.

## ADR-038: S-05-004 Accepted And Merged; Next Tranche (S-05-005) Is A Human Gate

Status: Accepted
Date: 2026-07-26
Owner: Owner (approved: "Approve and merge S-05-004 if, and only if, repository governance is fully satisfied") / implementation agent (recorded)
Reversibility: Fast-forward on the non-protected integration branch `implementation/s01-registration-access`; nothing pushed and `main` untouched, so it is revertible. The next-tranche authorisation is recorded separately (ADR-039).

Decision:
Accept S-05-004 (verification_attempts + ReserveVerificationAttempt, ADR-037). Repository governance is fully satisfied and was re-verified at the merge: whole-repo suite 1149 examples / 0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; verify_runtime OK (RLS intact); no `db/structure.sql` drift; architecture fitness 31/0; independent review (ADR-026, five separately-invoked adversarial lenses with no shared conversational state) PASS_NO_BLOCKING with zero confirmed-blocking findings; the only frozen-path touch (`lib/f1/runtime_grants.rb`) is the additive least-privilege `verification_attempts` grant (no DELETE) under the FrozenContracts additive-new-table rule (ADR-029, ADR-037). Fast-forward merged into `implementation/s01-registration-access` at `dd802a0`; `S-05-004` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-05-004 → completed; `S-05-004_COMPLETION_REPORT.md` marked accepted; the merged tranche branch `tranche/S-05/S-05-004` deleted per repository policy (S-05-001/002/003 precedent).

Carried non-blocking (recorded in ADR-037, not gate failures): no direct two-racer concurrency test (the property is enforced by the advisory lock + state-version guard + the unique attempt index, the last proven in the invariants spec); a tighter rate-limit reject boundary; and a direct denial-not-recorded test. These are candidate follow-ups and do not block the merge.

Next Tranche — Genuine Human Decision (HD-S05-005-AUTHORISE):
Per BUILD_STATE/BUILD_PLAN, the next block is **S-05-005** (CompleteVerificationAttempt — observation recording + F-03 Evidence), which is `human_gate_before: true` and remains unauthorised under the owner-accepted Observation split (ADR-033: "S-05-004..007 remain human_gate_before until authorised in turn"). Its scope is fixed by the split, so this is an authorise-to-proceed gate, not a scope choice. The controller stops at `human_decision_required`; it does not self-authorise the next tranche.

Recommended Option:
**Authorise S-05-005 as specified.** It runs the S-05-003 observation engine for a reserved attempt (the provider call outside the transaction; only the recorded outcome committed), persists exactly one restricted `verification_observation` Evidence (F-03) + `SourceVerificationObserved`, updates the Request completion/last-observed fields and clears the in-progress marker, and leaves the Source `proposed` on any non-verifying outcome (the matched success commit is S-05-006). The flagged Source Scope / S-06 dependency affects S-05-006 only and need not be decided now.

Authority And Precedence:
Executes the owner's accept-and-merge instruction and the controller mandate. Allocated the next unused number after ADR-037. No automatic merge to the protected branch and no production path; the controller stops at the human gate per the mandate.

## ADR-039: S-05-005 Authorised (CompleteVerificationAttempt — observation recording + F-03 Evidence); Human Gate Cleared

Status: Accepted
Date: 2026-07-26
Owner: Owner (approved: "Record owner authorisation for S-05-005 by clearing its human_gate_before exactly as specified in BUILD_PLAN and ADR-033. Then execute S-05-005 through the autonomous controller.") / implementation agent (recorded)
Reversibility: Plan/state change plus a product tranche that stops at ready_for_review on an isolated branch; revertible until owner acceptance. `main` untouched.

Decision:
Resolving HD-S05-005-AUTHORISE (ADR-038), the owner authorises **S-05-005 — `Workflows::Wf003::CompleteVerificationAttempt`** exactly as specified in BUILD_PLAN and the owner-accepted Observation split (ADR-033), and clears its `human_gate_before`. No scope change. Scope (contracts/S-05.json MTX-028/051/056; SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And Evidence, § Ownership-Verification Evidence Contract):
- run the S-05-003 observation engine (`Workflows::Wf003::VerificationObservation`) for a reserved attempt — the provider call OUTSIDE the transaction, only the recorded outcome committed;
- persist exactly one restricted `verification_observation` Evidence (F-03) per started observation, whether matched, not matched or indeterminate, with no plaintext token and no raw DNS/HTTP content;
- append exactly one `SourceVerificationObserved` referencing that Evidence; update the Request completion/last-observed fields; clear the in-progress marker; transition the attempt reserved → running → completed (or quarantined);
- idempotent retry under the reserved slot/attempt identity (a completion-persistence failure retries the same attempt and consumes no second count);
- a not_matched / indeterminate / dependency-failure outcome records the observation and leaves the Source `proposed`.

Out of scope (later sub-tranches, unchanged): the matched success commit + Source `proposed → verified` + `source-scope-interim-v1` materialization (S-05-006, which carries the flagged Source Scope / S-06 architectural dependency), and the automated slot schedule (S-05-007). No frozen foundation contract change, no destructive migration, no production path.

Authority And Precedence:
Executes the owner's authorisation and the controller mandate. Allocated the next unused number after ADR-038. Runs to `ready_for_review` under the controller (isolated branch `tranche/S-05/S-05-005`, enforced preflight/postflight, deterministic verification, independent review, records, commits); no automatic merge, no production path. Per owner instruction, S-05-006 is NOT to be begun.

## ADR-040: S-05-005 CompleteVerificationAttempt — Completion (ready_for_review)

Status: Accepted
Date: 2026-07-26
Owner: Owner (authorised S-05-005, ADR-039) / implementation agent (recorded)
Reversibility: Committed on branch `tranche/S-05/S-05-005` (off `e96cb3d`), verified and independently reviewed, NOT merged; `main` untouched, nothing pushed. Fully reversible until owner acceptance.

Decision:
Implement the WF-003 observation-recording limb `Workflows::Wf003::CompleteVerificationAttempt` (SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And Evidence and § Evidence Contract; contracts/S-05.json MTX-028/051/056). The service-executed handler runs a reserved attempt's observation through the S-05-003 engine and records the outcome: the provider call is OUTSIDE every transaction (read-and-reveal transaction → engine → completion transaction; only the recorded outcome is committed); it persists exactly one restricted `verification_observation` Evidence (F-03, the first real F-03 producer) with its redacted payload behind an F-02 reference — never the plaintext token or raw content — through the frozen `Platform::Evidence.produce` surface, idempotent on `(organization_id, producer_id, attempt_id)`; it appends exactly one `SourceVerificationObserved` referencing that Evidence, transitions the attempt `reserved → completed`, and updates the Request `last_observed_at_utc` / on-demand marker / `last_on_demand_completed_at_utc` with `request_status` held `pending`. A matched observation is RECORDED only — the Source is left `proposed` and the Request `pending` (the matched success commit is S-05-006). Completion is idempotent by the reserved attempt identity (a persisted completion replays; a persistence failure leaves the attempt reserved for a retry that consumes no second count). The migration relaxes exactly the `reserved → completed` guard edge (mirroring S-05-002); no new table, column, index or grant. Suite 1158 examples / 0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; verify_runtime OK (RLS intact); no structure.sql drift; architecture fitness green (incl. the F-03 evidence single-surface fence).

Independent Review (ADR-026):
Five adversarial lenses by separately-invoked models with no shared conversational state (contract-correctness, security/no-secret-at-rest, F-03/F-02 integration, concurrency/idempotency, architecture/frozen-contract): **PASS_NO_BLOCKING — zero blocking findings, zero confirmed-blocking after the verify pass.** Confirmed the provider-call-outside-every-transaction structure, the single restricted Evidence + single observed event per observation, the atomic version-guarded record with LostRace rollback (Evidence, F-02 ciphertext and ledger together), the token confined to the reveal/provider phases and absent from every persisted column, the Evidence Record shape against the canonical F-03 acceptance test, the single-surface producer usage and transaction-sharing atomicity, the transaction-local proved context across the two transactions, service attribution, and frozen-façade compliance. One review-driven repair applied (comment accuracy only, no behaviour change): corrected the service-store duplication note (this is the third structural copy; a ServiceLedgerWriters extraction is a deferred follow-up).

Decision Ledger:
| Decision | Authority | Reason |
| --- | --- | --- |
| Provider call outside the transaction via a two-transaction handler (read+reveal → engine → commit) | Autonomous (contract) | transaction_boundary: "the provider call itself is outside every transaction." The org proved-context is transaction-local (set_config(...,true)), so the second UnitOfWork re-enters cleanly. |
| One restricted verification_observation Evidence via `Platform::Evidence.produce` (default store) | Foundation Consumption Rule | The default store shares the UnitOfWork's ActiveRecord::Base.connection, so the Evidence commits atomically; referencing the internal EvidenceStore would break the single-surface fitness. |
| Idempotent by the reserved attempt identity (idempotency_key = verification_attempt_id) | Autonomous (contract) | "Observation completion is idempotent by reserved slot/attempt identity"; the locked re-read + the Evidence unique key + the version-guarded UPDATEs make a retry replay or re-run under the same attempt with no second count. |
| Service-attributed, no permission check | Autonomous (MTX-051) | "the transition is a consequence of a matched predicate, not of an actor's permission"; authority was established at reservation. |
| Relax exactly `reserved → completed` | Autonomous (the plan's edge) | The one recording transition; running/quarantined stay refused (mirrors S-05-002). |
| SourceVerificationObserved event_profile = `attempt` | Autonomous (fixed CHECK set) | The event_registry profile set has no "observation" literal; `attempt` denotes an observation attempt. |
| VerificationObservationStore duplicates the service writers | Autonomous (established pattern) | Third structural copy; the ServiceLedgerWriters extraction is recorded as a deferred follow-up (it would edit merged stores). |

Non-blocking findings recorded (not actioned per the owner's "confirmed blocking only" instruction; carried for owner consideration or a later limb): started/completed instants coincide because a command carries a single clock `now`; the deny path writes no idempotency record (diverging from ExpireVerificationRequest); a Request going terminal between the provider call and the commit records no Evidence and leaves the attempt reserved (a later cleanup); the at-rest token-absence assertion could also pin command_results, and a true concurrent two-racer completion test could join the sequential idempotency coverage.

Authority And Precedence:
Consumes F-01..F-04 through their frozen façades only; no frozen contract changed. Allocated the next unused number after ADR-039. Stops at ready_for_review per the mandate; no automatic merge, no production path. Per owner instruction, S-05-006 is NOT begun.

## ADR-041: S-05-005 Accepted And Merged; S-05-006 Is A Human Gate Carrying The Source-Scope Dependency

Status: Accepted
Date: 2026-07-26
Owner: Owner (approved: "Approve and merge S-05-005 if, and only if, repository governance is fully satisfied") / implementation agent (recorded)
Reversibility: Fast-forward on the non-protected integration branch `implementation/s01-registration-access`; nothing pushed and `main` untouched, so it is revertible. S-05-006 is NOT authorised (a decision package was prepared instead).

Decision:
Accept S-05-005 (CompleteVerificationAttempt — observation recording + F-03 Evidence, ADR-040). Repository governance is fully satisfied and was re-verified at the merge: whole-repo suite 1158 examples / 0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; verify_runtime OK (RLS intact); no `db/structure.sql` drift; architecture fitness green (incl. the F-03 evidence single-surface fence); independent review (ADR-026, five separately-invoked adversarial lenses with no shared conversational state) PASS_NO_BLOCKING with zero confirmed-blocking findings; no frozen foundation contract changed (foundations consumed only through their façades, Evidence written only through `Platform::Evidence.produce`). Fast-forward merged into `implementation/s01-registration-access` at `feec2fd`; `S-05-005` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-05-005 → completed; `S-05-005_COMPLETION_REPORT.md` marked accepted; the merged tranche branch `tranche/S-05/S-05-005` deleted per repository policy (S-05-001/002/003/004 precedent).

Carried non-blocking (recorded in ADR-040, not gate failures): the started/completed instants coincide under the single-clock RequestContext; the completion deny path writes no idempotency record (diverging from ExpireVerificationRequest); a Request going terminal between the provider call and the commit records no Evidence; two test-coverage additions (command_results token-absence, a concurrent two-racer completion); and a warranted ServiceLedgerWriters extraction at the third service-store copy. These are candidate follow-ups and do not block the merge.

Next Tranche — Genuine Human Decision (HD-S05-006-SCOPE-AND-DEPENDENCY):
Per BUILD_STATE/BUILD_PLAN, the next block is **S-05-006** (matched success commit + source-scope-interim-v1), which is `human_gate_before: true` and remains unauthorised under the owner-accepted Observation split (ADR-033). It additionally carries the flagged architectural dependency first raised in ADR-032 and carried through ADR-033: the success commit must materialize `source-scope-interim-v1` via a `SourceScopePolicyRepository`, which is the S-06 Source Scope sub-system (`source_set_versions` / `source_set_memberships` / `source_scope_change_requests`). This is both a `human_gate_before` authorisation and a genuine product-sequencing/architectural decision, so the controller stops here; it does not self-authorise S-05-006 and does not resolve the dependency. Per the owner's instruction, S-05-006 was NOT begun; a decision package was prepared for the owner gate.

Options (repository-recognised, from BUILD_PLAN S-05-006 open_question):
- **A** — Build a minimal `source-scope-interim-v1` materialization inside S-05-006 (the smallest `SourceScopePolicyRepository` write the success commit needs), deferring the full S-06 Source Scope sub-system.
- **B** — Sequence a minimal Source Scope foundation BEFORE S-05-006 (a new precursor tranche), so S-05-006 consumes a ready artifact; may need its own foundation-style sequencing.
- **C** — Split S-05-006: land the atomic success commit WITHOUT scope materialization first, then add `source-scope-interim-v1` as a distinct authorised sub-tranche once the Source Scope shape is decided.

Recommended Option:
**Option A**, grounded in the repository's own precedent: the Observation limb was split precisely to keep each tranche the smallest self-contained unit (ADR-032/033), and F-03's `evaluation_id` was made nullable "the evaluations capability does not exist yet" — the same deferral discipline. A minimal, versioned `source-scope-interim-v1` materialization (exactly what the atomic success commit needs, no S-06 change-request/lifecycle machinery) keeps `SourceVerified` and the scope artifact inseparable in one transaction as the contract's "none may appear without the others" demands, without pulling the full S-06 Source Scope sub-system forward. Option B risks an F-01..F-04-style foundation wall ahead of a single consumer; Option C risks shipping a `SourceVerified` success commit whose contract-mandated scope materialization is temporarily absent (a "none-may-appear-without-the-others" violation in the interim). The reasoning and consequences are laid out in full in the owner decision package accompanying this ADR. The owner decides; the controller does not.

Authority And Precedence:
Executes the owner's accept-and-merge instruction and the controller mandate. Allocated the next unused number after ADR-040. No automatic merge to the protected branch and no production path; the controller stops at the human gate per the mandate and does not authorise S-05-006 or modify repository governance.

## ADR-042: S-05-006 Authorised (matched success commit + source-scope-interim-v1); Option A; Human Gate Cleared

Status: Accepted
Date: 2026-07-26
Owner: Owner (approved: "Owner decision: APPROVED. Select Option A. Authorise S-05-006 exactly as defined in BUILD_PLAN and ADR-033.") / implementation agent (recorded)
Reversibility: Plan/state change plus a product tranche that stops at ready_for_review on an isolated branch; revertible until owner acceptance. `main` untouched.

Decision 1 — Next tranche authorised:
Resolving HD-S05-006-SCOPE-AND-DEPENDENCY (ADR-041), the owner authorises **S-05-006 — the matched success commit + source-scope-interim-v1 materialization** exactly as specified in BUILD_PLAN and the owner-accepted Observation split (ADR-033), and clears its `human_gate_before`. Scope (contracts/S-05.json MTX-028/051/056; SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And Evidence; WORKFLOW_SPECIFICATIONS.md § WF-003): on a **matched** observation, the atomic multi-root commit inside the CompleteVerificationAttempt completion transaction — Request `verified`/`matched`, immediate challenge-redelivery disablement (F-02 erase), `SourceVerified`, `Source.proposed → verified` (the `sources` guard relaxed for exactly that edge, state-version guarded) — together with the materialization of `source-scope-interim-v1`. None may appear without the others (proven by fixture); the transition fires exactly once (state-version guarded); a non-matched outcome is unchanged from S-05-005 (records the observation, leaves the Source proposed).

Decision 2 — Architectural dependency resolved (Option A, from ADR-041):
The `source-scope-interim-v1` materialization is built **minimally within S-05-006** via a `SourceScopePolicyRepository` — the smallest write the success commit needs — **modelled to the canonical Source Scope Policy schema** (schemas/POSTGRESQL_SCHEMA.md) so the S-06 Source Scope sub-system (`source_set_versions` / `source_set_memberships` / `source_scope_change_requests`) EXTENDS it rather than replacing or migrating it. Only the fixed interim policy is materialized (WORKFLOW_SPECIFICATIONS.md :412: HTTPS, default port, verified canonical host only, include prefix `/`, no exclude prefix, `retain_all`). No expansion into the full S-06 sub-system; the change-request/source-set machinery remains S-06 scope.

Grounding (from the ADRs and BUILD_PLAN): the contract makes scope materialization inseparable from `SourceVerified` (contracts/S-05.json :44/:112 — "none may appear without the others"), which rules out splitting it out (the ADR-041 Option C); the interim policy is fixed and fully specified, so a full Source Scope foundation ahead of one consumer (Option B) contradicts the ratified smallest-tranche split discipline (ADR-032/033); F-03's nullable `evaluation_id` deferral is the precedent for materializing the minimal artifact now while the full sub-system lands later, provided the minimal table follows the canonical schema.

Authority And Precedence:
Executes the owner's authorisation and Option-A selection and the controller mandate. Allocated the next unused number after ADR-041. Runs to `ready_for_review` under the controller (isolated branch `tranche/S-05/S-05-006`, enforced preflight/postflight, deterministic verification, independent review, records, commits); no automatic merge, no production path. Scope is strictly the repository-defined S-05-006 responsibilities. Per owner instruction, S-05-007 is NOT to be begun.

## ADR-043: S-05-006 Matched Success Commit + source-scope-interim-v1 — Completion (ready_for_review)

Status: Accepted
Date: 2026-07-26
Owner: Owner (authorised S-05-006 + Option A, ADR-042) / implementation agent (recorded)
Reversibility: Committed on branch `tranche/S-05/S-05-006` (off `af25168`), verified and independently reviewed, NOT merged; `main` untouched. Fully reversible until owner acceptance.

Decision:
Implement the WF-003 matched-verification success commit, extending `Workflows::Wf003::CompleteVerificationAttempt` (SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And Evidence; contracts/S-05.json MTX-028/051/056; WORKFLOW_SPECIFICATIONS.md § WF-003; owner Option A, ADR-042). On a matched observation committing BEFORE expiry, the completion transaction commits the atomic multi-root success — materialize `source-scope-interim-v1`, Request `pending → verified`/`matched` with the F-02 challenge erased (digest survives), Source `proposed → verified` with the interim policy pinned, and `SourceVerified` — none without the others, guarded on the expected Request and Source state versions (a lost race rolls the whole completion back). A matched observation committing at/after `expires_at_utc` records but does NOT verify (expiry wins at equality); a non-match records only (S-05-005). The minimal, canonical-shaped `source_scope_policies` table (S-06.json MTX-029) is immutable (T-IMM) and modelled so S-06 EXTENDS it; the two guard edges relaxed are exactly `sources proposed → verified` and `verification_requests pending → verified`. Suite 1173 examples / 0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; verify_runtime OK (RLS intact); no structure.sql drift; architecture fitness 31/0.

Independent Review (ADR-026):
Five adversarial lenses by separately-invoked models with no shared conversational state. The first pass returned **BLOCK — two confirmed-blocking findings (the same defect)**: the matched success commit did not enforce the `expires_at_utc` boundary, so a matched observation committing at/after expiry could wrongly verify (contract: "an observation completing at or after expires_at_utc cannot verify; at exact equality expiry wins"). **Repair applied (confirmed-blocking only, S-05-006 3/n):** verification now gates on `now < expires_at_utc` (strict), with a defence-in-depth guard in `verify_request_on_match` and two boundary specs. A focused independent re-review of the repair delta confirmed **RESOLVED, no new blocking issue**; the tranche now carries **zero confirmed-blocking findings**.

Decision Ledger:
| Decision | Authority | Reason |
| --- | --- | --- |
| Minimal, canonical-shaped `source_scope_policies` (Option A) | Owner-ratified (ADR-042) | The smallest artifact the success commit needs, modelled to S-06.json MTX-029 so S-06 extends it; no S-06 change-request/source-set machinery. |
| Relax exactly `sources proposed → verified` and `verification_requests pending → verified` | Autonomous (the plan's edges) | The S-05-006 ratified transitions; every other Source/Request edge stays refused. |
| Verify only when `now < expires_at_utc` (strict) | Autonomous (contract; confirmed-blocking repair) | "At exact equality expiry wins"; app gate + DB backstop; a matched-but-expired observation records only. |
| `source_scope_policies` immutable (T-IMM: trigger + SELECT/INSERT grant) | Autonomous (canonical) | "Each version is immutable; a new version is inserted rather than updated" (S-06.json MTX-029). |
| SourceVerified on the Source aggregate, service-attributed | Autonomous (established pattern) | The observation is the lifecycle service's act; authority was established at reservation (MTX-051). |

Non-blocking findings recorded (not actioned per the owner's "confirmed blocking only" instruction; candidate follow-ups): the SourceVerified event envelope omits `idempotency_identity_hash`/`input_hash` (a minor consistency gap vs SourceVerificationObserved); the F-02 erase runs between the two guarded UPDATEs (transactional, safe); only the exact-equality expiry boundary is tested (strictly-after is a-fortiori); a true concurrent two-racer verification test could join the sequential exactly-once coverage; and the app-clock expiry boundary is a deliberate, documented platform choice. The carried S-05-005 items (ServiceLedgerWriters extraction, deny-path idempotency) also remain.

Authority And Precedence:
Consumes F-01..F-04 through their frozen façades only; no frozen contract changed. Allocated the next unused number after ADR-042. Stops at ready_for_review per the mandate; no automatic merge, no production path. Per owner instruction, S-05-007 is NOT begun.

## ADR-044: S-05-006 Accepted And Merged; S-05-007 Is A Human Gate (the final Observation sub-tranche)

Status: Accepted
Date: 2026-07-26
Owner: Owner (approved: "Approve and merge S-05-006 if, and only if, repository governance is fully satisfied") / implementation agent (recorded)
Reversibility: Fast-forward on the non-protected integration branch `implementation/s01-registration-access`; nothing pushed and `main` untouched, so it is revertible. S-05-007 is NOT authorised (a briefing was prepared instead).

Decision:
Accept S-05-006 (matched success commit + source-scope-interim-v1, ADR-043). Repository governance is fully satisfied and was re-verified at the merge: whole-repo suite 1173 examples / 0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; verify_runtime OK (RLS intact); no `db/structure.sql` drift; architecture fitness 31/0; independent review (ADR-026, five separately-invoked adversarial lenses) found one confirmed-blocking defect (the missing `expires_at_utc` verify gate), which was repaired and confirmed RESOLVED by a focused independent re-review, leaving zero confirmed-blocking findings; no frozen foundation contract changed. Fast-forward merged into `implementation/s01-registration-access` at `578a6cf`; `S-05-006` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-05-006 → completed; `S-05-006_COMPLETION_REPORT.md` marked accepted; the merged tranche branch `tranche/S-05/S-05-006` deleted per repository policy (S-05-001..005 precedent).

Carried non-blocking (recorded in ADR-043, not gate failures): the SourceVerified event envelope consistency fields; the deny-path idempotency alignment (S-05-005); the ServiceLedgerWriters extraction (third service-store copy, S-05-005); and a couple of additional concurrency/coverage tests. These are candidate follow-ups and do not block the merge.

Next Tranche — Genuine Human Decision (HD-S05-007-AUTHORISE):
Per BUILD_STATE/BUILD_PLAN, the next block is **S-05-007** (automated observation slot schedule), the FINAL Observation sub-tranche of the owner-accepted split (ADR-033). It is `human_gate_before: true` and remains unauthorised; its scope is fixed by BUILD_PLAN, so this is an authorise-to-proceed gate. The controller stops here and does not self-authorise. Per the owner's instruction, S-05-007 was NOT begun; an owner briefing (scope, dependencies, size, risks, decomposition recommendation) was prepared instead.

Authority And Precedence:
Executes the owner's accept-and-merge instruction and the controller mandate. Allocated the next unused number after ADR-043. No automatic merge to the protected branch and no production path; the controller stops at the human gate per the mandate.

## ADR-045: S-05-007 Authorised (automated observation slot schedule); Human Gate Cleared

Status: Accepted
Date: 2026-07-26
Owner: Owner (approved: "Owner decision: APPROVED. Authorise S-05-007 exactly as defined in BUILD_PLAN. Record this owner decision in the authoritative repository records and clear S-05-007's human_gate_before. Execute S-05-007 as a single coherent tranche. Before implementation begins, assess whether the repository-defined scope remains one coherent, reviewable tranche.") / implementation agent (recorded)
Reversibility: Plan/state change plus a product tranche that stops at ready_for_review on an isolated branch; revertible until owner acceptance. `main` untouched.

Decision:
Resolving HD-S05-007-AUTHORISE (ADR-044), the owner authorises **S-05-007 — the automated observation slot schedule** exactly as specified in BUILD_PLAN, and clears its `human_gate_before`. No scope change. This is the FINAL Observation sub-tranche of the owner-accepted Observation split (ADR-033); on acceptance it completes the WF-003 Ownership Verification limb (S-05-001..007). Scope (contracts/S-05.json MTX-028 `background_job`/`retry_policy`/`concurrency`, MTX-051, MTX-056; SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And Evidence :151–160; WORKFLOW_SPECIFICATIONS.md § WF-003):

- the automated slots at due offsets 0, 5, 15, 30, 60, 120, 240, 480, 960 and 1,380 minutes after issuance, each starting only in its half-open window from its due time to the next offset (the final window ending at expiry);
- an `AutomatedObservationSlotJob` per due slot that reserves and completes an automated attempt (attempt origin `automated`, slot offset set) via the S-05-004 reservation + S-05-005/006 completion engine, executed through F-04 background execution;
- `observation_slot_skipped` recorded exactly once for an unstarted slot when its window closes, never run late; at an exact-boundary the earlier slot is skipped and the later slot is eligible; a terminal Request state cancels all remaining slots without skipped events. `observation_slot_skipped` is a scheduler record, not a domain event and not fabricated Evidence.

Out of scope (BUILD_PLAN): frozen foundation contract changes, destructive migrations, production deployment; on-demand acceptance (S-05-004), scoring/evaluation and Source activation (S-06 lifecycle).

Coherence Assessment (owner-directed precondition):
Per the owner's instruction, before implementation begins the controller assesses whether the repository-defined S-05-007 scope remains one coherent, reviewable tranche. If — and only if — it cannot reasonably remain a single coherent tranche while preserving repository standards for reviewability, the controller stops before implementation, makes no behavioural changes, and presents a decomposition proposal with clear tranche boundaries and rationale for owner approval. Otherwise it proceeds under the autonomous controller. The assessment and its outcome are recorded in the S-05-007 completion record.

Authority And Precedence:
Executes the owner's authorisation and the controller mandate. Allocated the next unused number after ADR-044. Runs to `ready_for_review` under the controller (isolated branch `tranche/S-05/S-05-007`, enforced preflight/postflight, deterministic verification, independent review, records, commits); no automatic merge, no production path; repair only confirmed blocking findings. Scope is strictly the repository-defined S-05-007 responsibilities. Per owner instruction, no subsequent tranche is to be begun.
