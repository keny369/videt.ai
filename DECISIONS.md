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
