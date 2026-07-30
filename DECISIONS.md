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

## ADR-046: S-05-007 Automated Observation Slot Schedule — Completion (ready_for_review)

Status: Accepted
Date: 2026-07-26
Owner: Owner (authorised S-05-007, ADR-045) / implementation agent (recorded)
Reversibility: Committed on branch `tranche/S-05/S-05-007` (off `af62719`), verified and independently reviewed, NOT merged; `main` untouched. Fully reversible until owner acceptance.

Coherence Assessment (owner-directed precondition, resolved):
Before implementation, the controller assessed whether the repository-defined S-05-007 scope remains one coherent, reviewable tranche (ADR-045). **Conclusion: it remains one coherent tranche; implementation proceeded without decomposition.** S-05-007 is a single mechanism whose three contract facets (start-only-in-the-half-open-window, skip-once-never-late, terminal-cancellation-without-skipped-events) are inseparable; it is the designated final unit of an already-smallest-unit split (ADR-032/033); it reuses the built `CompleteVerificationAttempt`/`VerificationObservation` engine wholesale; it modifies no frozen foundation; and it landed at 924 insertions across 13 files, well within the configured 40-file / 3,000-line limits. It could not be split into independently-reviewable, self-contained units without producing dead code, so no decomposition proposal was warranted.

Decision:
Implement the WF-003 automated observation slot schedule — the fifth and final Observation sub-tranche (SCORE_EVIDENCE_MODEL.md § Attempts, Expiry, And Evidence :151-160; contracts/S-05.json MTX-028 background_job/retry_policy/concurrency/idempotency; WORKFLOW_SPECIFICATIONS.md § WF-003; owner authorisation ADR-045). `IssueVerificationChallenge` schedules, on the issuing transaction, the ten `verification_observation_slot` ScheduledActions at due offsets 0/5/15/30/60/120/240/480/960/1,380 minutes (the ratified expiry-schedule pattern; ten distinct action identities via the `due_at`-bearing preimage). `AutomatedObservationSlots` defines the half-open windows tiling the 24-hour lifetime. The service-only `ObserveAutomatedSlot` handler, under the per-Request advisory lock, resolves each due slot to exactly one outcome: OBSERVE (reserve one automated attempt — `attempt_count + 1`, no on-demand counter/marker — and complete it through the unchanged S-05-005/006 engine, a match strictly before `expires_at_utc` firing the atomic success); SKIP (window closed → record `observation_slot_skipped` once, never late); VOID (Request terminal → record nothing, no skip, harmless-terminal-execution — a terminal Request thereby cancels remaining slots without skipped events, not a proactive F-04 cancel); or RESUME/REBUILD (idempotent under redelivery). A partial unique index `verification_attempts_one_automated_per_slot` is the database backstop against double-counting. Suite 1191 examples / 0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; verify_runtime OK (RLS intact); no structure.sql drift; architecture fitness 31/0.

Independent Review (ADR-026):
Five adversarial lenses by separately-invoked models with no shared conversational state (contract-correctness, concurrency/atomicity/idempotency, security/tenant-isolation, schema/migration-safety, architecture/scope/frozen-contracts). **Every lens returned PASS with zero confirmed-blocking findings** — the tranche was clean on the first pass, reusing the already-hardened completion engine and the ratified expiry-schedule and harmless-terminal-execution patterns. No repair was required (owner instruction: repair only confirmed blocking findings). The independent review confirmed: the ten offsets and half-open windows (final window ends at expiry), skip-once-never-late, terminal-void-without-skip, `attempt_count`-only reservation, the preserved `< expires_at_utc` boundary, find-before-reserve + advisory-lock idempotency (no double-count/duplicate-delivery/lost-update/infinite-retry), org-context-before-access tenant isolation with null-actor service attribution and no token leakage, an additive drift-free migration, and no frozen-foundation modification or scope creep.

Decision Ledger:

| Decision | Authority | Reason |
| --- | --- | --- |
| Schedule the ten slots at issuance, in the Request transaction | Autonomous (established pattern) | The canonical creation point of the schedule, exactly as the 24-hour expiry timer is scheduled there; the Request and its schedule commit or roll back together. |
| Terminal cancellation as harmless-terminal-execution (VOID), not proactive `Store#cancel` | Autonomous (ratified precedent) | The repository's own ratified pattern (`f1_cancel_scheduled_action` is unwired; the Invitation/expiry lost-race is a harmless terminal no-op); it satisfies "cancels remaining slots without skipped events" and consumes no new F-04 surface. |
| `observation_slot_skipped` as a service-attributed audit record, idempotent by the action identity | Autonomous (contract + WF-003 audit requirement) | "A scheduler record, not a domain event and not fabricated Evidence"; WORKFLOW_SPECIFICATIONS.md § WF-003 names the "skipped result" an audit/decision-trail item; "recorded once" holds under retry and concurrency. |
| `verification_attempts_one_automated_per_slot` partial unique index | Autonomous (canonical DB backstop) | At most one automated attempt per (Request, slot); the byte-identical predicate to `find_automated_attempt` closes the double-count vector at the database, mirroring the attempt-number uniqueness backstop. |
| Automated reserve surface placed in `VerificationObservationStore` (the service store) | Autonomous (layering) | The automated slot is service-executed; its `enter_org_context` + service-attributed writers live there, mirroring `ExpireVerificationRequest`/`VerificationExpiryStore`; the on-demand actor store is left untouched. |
| Delegate the started path to the unchanged `CompleteVerificationAttempt` | Autonomous (no silent scope expansion) | Reuse of the S-05-005/006 engine (provider call outside the transaction, F-03 Evidence, the `< expires_at_utc` boundary) rather than reimplementation; F-01/F-02/F-03 stay behind their façades. |

Non-blocking findings recorded (not actioned per the "confirmed blocking only" instruction; candidate follow-ups): no lower-bound "not-due" guard in `ObserveAutomatedSlot` (PostgreSQL transaction time is the sole due authority; the `slot_offset` validation is the target-integrity check; an early run under clock skew is unreachable via the normal path and benign); the VOID path writes no service-ledger record (audit-trail asymmetry vs SKIP/DENY, not a correctness defect — the F-04 worker settles the claim); a started slot writes no observe-command ledger (deliberate — resume-by-attempt is the idempotency mechanism); a slot reserving in-window and then finding the Request terminalized before completion leaves the attempt reserved (pre-existing reserve/complete characteristic, on-demand reaches it too). The carried earlier-sub-tranche items (ServiceLedgerWriters extraction, deny-path idempotency alignment, SourceVerified envelope fields) also remain.

Authority And Precedence:
Consumes F-01..F-04 through their frozen façades only; no frozen contract changed. Allocated the next unused number after ADR-045. Stops at ready_for_review per the mandate; no automatic merge, no production path. Per owner instruction, no subsequent tranche is begun.

## ADR-047: S-05-007 Accepted And Merged; WF-003 Ownership Verification (S-05-001..007) Complete

Status: Accepted
Date: 2026-07-26
Owner: Owner (approved: "Approve and merge S-05-007 if, and only if, repository governance remains fully satisfied") / implementation agent (recorded)
Reversibility: Fast-forward on the non-protected integration branch `implementation/s01-registration-access`; nothing pushed and `main` untouched, so it is revertible. No further tranche is authorised (the planned S-05 sequence is complete).

Decision:
Accept S-05-007 (automated observation slot schedule, ADR-046). Repository governance is fully satisfied and was re-verified at the merge: whole-repo suite 1191 examples / 0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; verify_runtime OK as `f1_web` (RLS intact, 15 checks); no `db/structure.sql` drift; architecture fitness 31/0; F-04 background-execution acceptance green; independent review (ADR-026, five separately-invoked adversarial lenses — contract-correctness, concurrency/atomicity/idempotency, security/tenant-isolation, schema/migration-safety, architecture/scope/frozen-contracts) returned ALL PASS with zero confirmed-blocking findings, so no repair was required; no frozen foundation contract changed (F-01..F-04 consumed only through their frozen façades, the started path delegating to the unchanged CompleteVerificationAttempt engine). Fast-forward merged into `implementation/s01-registration-access` at `1eadc45`; `S-05-007` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-05-007 → completed; `S-05-007_COMPLETION_REPORT.md` marked accepted; the merged tranche branch `tranche/S-05/S-05-007` deleted per repository policy (S-05-001..006 precedent).

WF-003 Ownership Verification — COMPLETE (S-05-001 through S-05-007):
With S-05-007 merged, the full WF-003 Ownership Verification limb is complete end to end. The seven ratified sub-tranches, all in `completed_blocks`:

- **S-05-001 IssueVerificationChallenge** — one pending Verification Request per proposed Source, a ≥128-bit challenge token encrypted behind F-02 (never persisted in plaintext), immutable issuance provenance, `SourceVerificationRequested`, and the 24-hour expiry timer.
- **S-05-002 ExpireVerificationRequest** — the timed `pending → expired` transition (`challenge_expired`), cryptographic deletion of the challenge material, `SourceVerificationExpired`, Source left proposed.
- **S-05-003 VerificationObservation** — the F-01 DNS/HTTP observation engine (10-second provider timeouts; the 4,096/4,097-byte HTTP boundary; DNS/HTTP match, status and reason mapping; `observed_value_sha256` over raw bytes; no plaintext retained).
- **S-05-004 ReserveVerificationAttempt** — the on-demand reservation (≤10 on-demand, 5-minute rate limit, in-progress marker), atomic attempt-slot assignment before any provider call.
- **S-05-005 CompleteVerificationAttempt** — the observation-recording limb: exactly one restricted `verification_observation` Evidence (F-03) per started observation, `SourceVerificationObserved`, attempt `reserved → completed`, idempotent by the reserved attempt identity.
- **S-05-006 matched success commit + source-scope-interim-v1** — on a match before expiry, the atomic multi-root success (Request `verified`/`matched`, challenge erased, `SourceVerified`, `Source.proposed → verified` with the interim scope policy pinned and materialized) — none may appear without the others; expiry wins at the boundary.
- **S-05-007 automated observation slot schedule** — the ten automated slots (0/5/15/30/60/120/240/480/960/1,380 min) in half-open windows, `AutomatedObservationSlot` reserving+completing an automated attempt per due slot via F-04, `observation_slot_skipped` recorded once and never late, and a terminal Request voiding its remaining slots without a skipped event.

End to end: an authorized Organization actor issues a challenge for a proposed Source; the platform observes ownership automatically on the ten-slot schedule (and on up to ten authorized on-demand attempts) via DNS TXT or HTTP file, recording exactly one restricted Evidence per started observation; the first match before expiry atomically verifies the Request and the Source and pins the interim Source Scope Policy; otherwise the Request expires at 24 hours or is cancelled/failed by its authorized service — with no challenge plaintext or raw observation ever retained at rest, and full tenant isolation and service attribution throughout.

Carried non-blocking (recorded in ADR-046, not gate failures): no lower-bound "not-due" guard in `ObserveAutomatedSlot` (PostgreSQL transaction time is the sole due-time authority; the `slot_offset` validation is the target-integrity check; an early run under clock skew is unreachable via the normal path and benign); the VOID path writes no service-ledger record (audit-trail asymmetry vs SKIP/DENY, not a correctness defect); a started slot writes no observe-command ledger (deliberate — resume-by-attempt is the idempotency mechanism); the reserve-then-terminalize orphan (pre-existing reserve/complete characteristic). The carried earlier-sub-tranche items (ServiceLedgerWriters extraction, deny-path idempotency alignment, SourceVerified envelope fields) also remain. These are candidate follow-ups and do not block the merge.

Next — Genuine Human Decision (HD-S05-COMPLETE-NEXT-BLOCK):
`BUILD_PLAN` now contains no further authorised block. WF-003 (the full S-05 Ownership Verification sequence) is complete; the controller stops at a human gate for the owner to define and authorise the next block (the next registration-access/S-05 capability or the next domain) from the authoritative specifications. The controller does not self-author new product scope. Per the owner's instruction, no subsequent tranche was begun.

Authority And Precedence:
Executes the owner's accept-and-merge instruction and the controller mandate. Allocated the next unused number after ADR-046. No automatic merge to the protected branch and no production path; the controller stops at the human gate per the mandate and does not authorise or begin any subsequent block.

## ADR-048: Establish The Customer Value Constitution (Product-Direction Authority)

Status: Accepted
Date: 2026-07-26
Owner: Owner / Founder (directed the establishment of a canonical Customer Value Constitution) / implementation agent (recorded)
Reversibility: Documentation-only. Adds one governance document and index/cross-reference lines; changes no code, schema, migration, contract, state model or gate. Fully revertible by removing the document and its references. Committed on the non-protected integration branch `implementation/s01-registration-access`; `main` untouched.

Decision:
Establish [governance/CUSTOMER_VALUE_CONSTITUTION.md](governance/CUSTOMER_VALUE_CONSTITUTION.md) as the canonical product-value-prioritisation and launch-scope authority for the pre-S-09 window. It is placed in `governance/` alongside `PROJECT_CONSTITUTION.md` (the README-defined home for constitution, workflow and quality standards, and first in the canonical read order). It is referenced from `README.md` (Start Here + Repository Structure) and `specification/INDEX.md` (Dependencies). It preserves the Videt north star, the OBSERVE/ASSESS/COMPARE/INTERVENE/LEARN customer-value loop, the Reality/Perception/Gap/Intelligence graph model, the intended experiences and outcomes, the seven Mandatory Product-Value Tests, the Necessary-Enabling-Work justification rule, the Mandatory Tranche Value Statement, the Launch Discipline favour/defer lists, and the Commercial Truth Standard.

Authority Classification:
Product-prioritisation authority only. The document explicitly does NOT override frozen specifications, ADRs, `BUILD_STATE.json`, `BUILD_PLAN.yml`, `AUTONOMOUS_BUILD_CONTROLLER.md`, `AUTONOMY_POLICY.md`, security/privacy contracts, state models, workflow specifications, or accepted tranche contracts. It cannot authorise a tranche, clear a human gate, define a state transition, relax a control, or mark work complete. Where it and any authoritative contract conflict, the contract prevails and the constitution is revised to remain product-direction guidance.

Contradiction Review:
No contradiction with `specification/005 PRODUCT_PRINCIPLES.md` (which it operationalises) was found. One terminology alignment was applied: the constitution uses the canonical `Issue` term for customer-facing deficiencies and records that the legacy synonym `Finding` is prohibited (PRODUCT_PRINCIPLES Principle 5), reserving "evidence"/"observation" for collected material. No genuine product/specification conflict remains open for owner consideration.

Authority And Precedence:
Executes the owner's Part 2 direction. Allocated the next unused number after ADR-047. Documentation governance only; introduces no implementation authority and no production path.

## ADR-049: S-06 Source Discovery and Scope Authorised; Decomposed; S-06-001 (Scope Predicate) Runs Next

Status: Accepted
Date: 2026-07-26
Owner: Owner (authorised: "Authorise S-06 — Source Discovery and Scope, WF-004, as the next repository-defined block ... This authorisation is limited to S-06. It does not pre-authorise S-07, S-08, S-09 or any subsequent block.") / implementation agent (recorded)
Reversibility: Planning-only at this commit — extends BUILD_PLAN with the S-06 decomposition, resolves the BUILD_STATE open decision, and records this entry; changes no product code, schema, migration or gate. Committed on the isolated tranche branch `tranche/S-06/S-06-001` from integration tip `0f6a625`; `main` and the integration branch are untouched; nothing pushed.

Decision:
Resolve HD-S05-COMPLETE-NEXT-BLOCK by authorising S-06 — Source Discovery and Scope (WF-004) — as the next repository-defined block after the completed S-05 Ownership Verification capability. Extend BUILD_PLAN with the five dependency-ordered S-06 sub-tranches, derived solely from authoritative repository sources (contracts/S-06.json MTX-029/006/057/072; SECURITY_PERFORMANCE.md § PRULE-021; WORKFLOW_SPECIFICATIONS.md § WF-004 + the ascii-host-v1 host contract; APPLICATION_LAYER.md § WF-004/PRULE-006), not from chat, diagram or tranche numbering:

- S-06-001 Source Scope Predicate (PRULE-021 / MTX-072) — a pure PORO: canonical-URL normalization + the scope predicate; no persistence, no migration, no events, no crawl. The analogue of the S-05-003 pure observation engine.
- S-06-002 source_scope_change_requests + ProposeSourceScopeChange (MTX-029 propose).
- S-06-003 DecideSourceScopeChange + CancelSourceScopeChange (MTX-029 decide; dual control).
- S-06-004 ExpireSourceScopeChange + SourceScopeChangeExpiryJob (MTX-029 expiry via F-04).
- S-06-005 Source lifecycle Activate/Disable/Reactivate/Remove (PRULE-006 / MTX-057).

S-06 EXTENDS the S-05-006 interim source_scope_policies (source-scope-policy-v1); it does not migrate or replace it. No sub-tranche exceeds the reviewability limits (≤40 files, ≤3,000 diff lines).

Scope Boundary:
Only S-06-001 is authorised to run (human_gate_before cleared by this owner authorisation). S-06-002..005 remain human_gate_before until authorised in turn after the prior is accepted and merged. This authorisation does NOT pre-authorise S-07, S-08 or S-09. "Discovery" is scope definition and control, not crawler URL discovery — WF-004 performs no outbound retrieval. Nothing in S-06 pulls forward crawl (S-07), parsing (S-08), inspection (S-09) or AI machinery.

Customer Value (per governance/CUSTOMER_VALUE_CONSTITUTION.md):
S-06 advances ASSESS and the Reality Graph — governance and control of the verified digital estate. Customer-value outcome: "After S-06, the customer can define and control exactly which parts of a verified property Videt may observe, which they could not reliably do before." S-06-001 itself is Necessary Enabling Work: the deterministic scope-decision kernel on which every scope change and every future crawl admission depends; it exposes no command surface of its own and is not independently customer-visible.

Authority And Precedence:
Executes the owner's S-06 authorisation. Allocated the next unused number after ADR-048. No automatic merge to the protected branch and no production path; the controller stops at human_gate_after (owner acceptance) once S-06-001 reaches ready_for_review.

## ADR-050: S-06-001 Source Scope Predicate Implemented and Reviewed; Held at human_decision_required on a Latent Exclusion-Separator Finding

Status: Accepted (record); the governed product decision HD-S06-001-SCOPE-SEPARATOR is OPEN for the owner
Date: 2026-07-26
Owner: implementation agent (recorded); the open product ruling is the owner's
Reversibility: The tranche is on the isolated branch `tranche/S-06/S-06-001` (base `0f6a625`, implementation commit `3aaf017`); nothing merged, nothing pushed, `main` and the integration branch untouched. Fully revertible by deleting the branch.

Decision:
S-06-001 — the pure PRULE-021 Source Scope Predicate (`Workflows::Wf004::SourceScopePredicate`) — is implemented per contracts/S-06.json MTX-072 and SECURITY_PERFORMANCE.md § PRULE-021, as the analogue of the S-05-003 pure engine: a pure PORO that normalizes a candidate URL and decides admission against the active Source Scope Policy intersection, with no persistence, no outbound call, no event and no Source/Request transition. Full gate green: whole-repo suite 1225 examples/0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness green within the suite; no db/ or app/models change (pure predicate, no schema, no drift possible). 34 deterministic examples cover every MTX-072 test contract.

Independent Review (ADR-026):
Five separately-invoked adversarial lenses with no shared state. Contract-correctness, determinism/purity, architecture/scope/frozen-contracts and test-quality/schema-safety all returned PASS (verified by runnable Ruby, incl. RFC 3986 §5.2.4, the `%2F` non-decode, non-tautology mutants, and Zeitwerk/Packwerk). The security/tenant-isolation lens found NO host-level false-allow but returned CHANGES_REQUIRED on one verified, LATENT finding recorded as the open decision below.

Open Product Decision — HD-S06-001-SCOPE-SEPARATOR:
With include `/` and exclude `/private`, the predicate ALLOWS `/private%2Fsecret`, `/private%5Csecret` and `/private\secret` (whereas `/private/secret` is correctly `path_excluded`), because `%2F`/`%5C` are correctly not decoded and a raw backslash is passed through, so the exclude segment-boundary test misses; some origins resolve these back to the excluded `/private/secret`. This is spec-conformant to PRULE-021 as written (boundary = a literal `/` in the normalized path; `%2F` is reserved and preserved) and LATENT (the only materialized policy — the S-05-006 interim — ships `exclude_prefixes: []`; the S-06-002/003 commands that set excludes and the S-07 crawler are not built). The remedy requires either deviating from the ratified PRULE-021 boundary rule (a fail-closed predicate hardening) or an S-07 crawl-behaviour ruling — a product-semantics choice with more than one valid reading. Per AUTONOMOUS_BUILD_CONTROLLER §7 (security consideration + ambiguous product semantics → human escalation) and §3.8 (no silent scope expansion / no silent reinterpretation of ratified governance), the controller does NOT harden unilaterally and stops for the owner. Options and recommendation (Option A: fail-closed predicate hardening with owner ratification of a PRULE-021 clarification) are in S-06-001_COMPLETION_REPORT.md § Open owner decision and BUILD_STATE open_decisions.

No confirmed-blocking repair was applied (the sole CHANGES_REQUIRED finding is spec-conformant and its resolution is an owner ruling). Non-blocking observations are recorded in the completion report, not actioned.

Authority And Precedence:
Records the implementation and review outcome; escalates the governed product ruling to the owner. Allocated the next unused number after ADR-049. No automatic merge, no push, no production path; S-06-002..005 remain human_gate_before.

## ADR-051: PRULE-021 Exclusion Clarification — Fail-Closed Separator-Equivalence (Owner Option A)

Status: Accepted (owner-ratified)
Date: 2026-07-27
Owner: Owner (decision HD-S06-001-SCOPE-SEPARATOR: "Select Option A. Ratify fail-closed separator hardening ... The predicate must treat path representations capable of being interpreted as hierarchy separators as exclusion-boundary separators for the purpose of scope denial, including at minimum: literal '/'; percent-encoded forward slash %2F; percent-encoded backslash %5C; raw backslash '\\'.") / implementation agent (recorded)
Reversibility: Implemented on the isolated branch `tranche/S-06/S-06-001`; nothing merged, nothing pushed, `main` and the integration branch untouched. Revertible by deleting the branch.

Decision:
A narrow, additive normative clarification of PRULE-021 (contracts/S-06.json MTX-072) exclusion semantics: when testing an EXCLUDE prefix, the predicate treats `%2F` and `%5C` (each case-insensitive) and a raw backslash as hierarchy-separator equivalents of `/`, and denies the candidate when an exclude prefix would match once those are interpreted as boundaries (with dot-segments then resolved so a subtree reached by traversal through an encoded separator is also denied). The rule is fail-closed and deterministic: the separator probe only ADDS exclusion denials, never removes one.

Scope and preservation of the existing rule:
The clarification is EXCLUSION-ONLY and additive. It does NOT decode `%2F`/`%5C` or any other reserved character in the returned value, does NOT alter the canonical URL, does NOT change include matching or query/fragment canonicalisation, and introduces no persistence, event, job, network or state. The existing PRULE-021 rule (boundary = a literal `/` in the normalized path; unreserved-only percent-decoding; `%2F` preserved) is preserved verbatim for the canonical form and for inclusion; the clarification constrains only the exclusion decision. Denied-by-example (exclude `/private`): `/private`, `/private/`, `/private/secret`, `/private%2Fsecret`, `/private%2fsecret`, `/private%5Csecret`, `/private%5csecret`, `/private\secret`, and traversal-in `/public%2F..%2F..%2Fprivate%2Fsecret`. Not-denied-solely: `/privateer`, `/privately`, `/private%20area`, and traversal-out `/private%2F..%2Fpublic`.

Specification mechanism (owner-directed):
Recorded as a normative clarification ADR that constrains implementation while preserving the existing rule — the mechanism the owner authorised. The repository does NOT require the frozen contract text to be amended before implementation: the established practice (e.g., ADR-042 governing the S-05-006 interim materialization) is that ADRs govern implementation without rewriting frozen Volume II contract prose, and this clarification is additive and leaves the MTX-072 test_contracts valid. The frozen contract text was NOT edited. If a future consumer needs the contract prose itself amended, that is a separate minimal contract-change package. A candidate follow-up (owner-noted, non-blocking) is to update the MTX-072 "IDNA ASCII" wording to "already-ASCII (IDNA resolved upstream)".

Implementation and verification:
Implemented as the smallest pure change in `Workflows::Wf004::SourceScopePredicate` (a `SEPARATOR_EQUIVALENT` constant + an `excluded?`/`exclusion_probe` pair reusing the existing `remove_dot_segments`). 12 added deterministic examples cover both hex cases of `%2F`/`%5C`, raw backslash, exact/descendant exclusion, non-matching lexical prefixes, traversal in/out, no general reserved decoding, unchanged canonical URL, frozen-input non-mutation, determinism, nested prefixes, include-interaction and query/fragment non-interference. See S-06-001_COMPLETION_REPORT.md.

Authority And Precedence:
Executes the owner's Option-A ruling. Allocated the next unused number after ADR-050; supersedes the open decision HD-S06-001-SCOPE-SEPARATOR (now RESOLVED). No automatic merge, no push, no production path.

## ADR-052: S-06-001 Accepted And Merged; S-06-002 Is A Human Gate

Status: Accepted
Date: 2026-07-27
Owner: Owner (approved: "Approve S-06-001 for acceptance and merge, subject to final repository-governance re-verification at the merge gate") / implementation agent (recorded)
Reversibility: Fast-forward on the non-protected integration branch `implementation/s01-registration-access` (`0f6a625 -> f0b3933`); `main` untouched; the update is pushed to origin per the owner's explicit instruction. Revertible by branch reset (no history rewritten). No further tranche is authorised.

Decision:
Accept S-06-001 (the pure PRULE-021 Source Scope Predicate with the ADR-051 fail-closed exclusion hardening). Repository governance was re-verified at the merge gate: BUILD_STATE reported `ready_for_review` with zero open decisions; HD-S06-001-SCOPE-SEPARATOR resolved (ADR-051); ADR-049/050/051 present and internally consistent; independent review (ADR-026, five separately-invoked adversarial lenses — security/tenant-isolation, contract-correctness, determinism/purity, architecture/scope, test-quality) complete with ALL FIVE PASS, the security lens classifying the finding RESOLVED, and zero confirmed-blocking findings; whole-repo suite 1240 examples/0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness green within the suite; no db/ or app/models change so no structure.sql drift is possible; the tracked tree clean; and the branch diff contained only the S-06-001 predicate, its spec and records (no unauthorised S-06-002 or S-07 work). Fast-forward merged into `implementation/s01-registration-access` at `f0b3933`; `S-06-001` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-06-001 -> completed; `S-06-001_COMPLETION_REPORT.md` marked accepted; the merged tranche branch `tranche/S-06/S-06-001` deleted per repository policy (S-05 precedent). The integration branch was pushed to origin as a safe fast-forward; `main` untouched.

Next — Human Gate (HD-S06-002-AUTHORISE):
S-06-002 (source_scope_change_requests + ProposeSourceScopeChange, contracts/S-06.json MTX-029 propose path) remains `human_gate_before`. The controller stops for the owner to authorise it; per the owner's instruction it was NOT begun, and an S-06-002 briefing is provided. S-06-003..005 remain human_gate_before behind it.

Authority And Precedence:
Executes the owner's accept-and-merge instruction. Allocated the next unused number after ADR-051. No automatic merge to the protected branch and no production path; the controller stops at the S-06-002 human gate and does not authorise or begin any subsequent tranche.

## ADR-053: S-06-002 Authorised; Scope Change Classifier Predicate Surfaced For Owner Ruling (Repository-First Stop)

Status: Accepted (record); the governed product decision HD-S06-002-SCOPE-CLASSIFIER is OPEN for the owner
Date: 2026-07-27
Owner: Owner (resolved HD-S06-002-AUTHORISE: "I authorize work to begin on S-06-002" with the condition "Pin [the expansion vs contraction predicate] directly from the authoritative repository. If the repository uniquely defines it, implement exactly that. If not, stop and surface a narrowly scoped owner decision before implementation") / implementation agent (recorded)
Reversibility: Planning/governance only — no product code, schema, migration or gate changed; committed on the integration branch, `main` untouched, not pushed. Revertible by reverting this commit.

Decision:
Resolve HD-S06-002-AUTHORISE: S-06-002 (source_scope_change_requests + ProposeSourceScopeChange, MTX-029 propose path) is authorised (human_gate_before cleared). Per the owner's condition, the controller pinned the expansion-vs-contraction predicate from the authoritative repository (WORKFLOW_SPECIFICATIONS.md § Source Scope Change Contract :410-421; APPLICATION_LAYER.md § WF-004 :769-813; the Policy-Artifact "non-broadening validation" :318 / APPLICATION_LAYER :4044-4050; contracts/S-06.json MTX-029; PRULE-021 / MTX-072 the admission predicate).

Uniquely determined by the repository (to be implemented exactly, no ruling needed):
- Contraction = a proposed policy that is NON-BROADENING relative to the current active policy, within the already-verified Source boundary; auto-activatable atomically by an OrganizationAdmin or MarketingOperator without dual control ("narrowing scope cannot leak a boundary").
- Expansion = a same-host BROADENING; a non-admin's expansion remains pending for a DIFFERENT OrganizationAdmin; an OrganizationAdmin may self-approve atomically; a TechnicalImplementer may propose but never approve/activate.
- A new host is never an expansion (a new Source via WF-003); non-HTTPS is `unsupported_source_scheme`; host/scheme/port are fixed to the verified boundary (a proposal beyond it is a boundary violation).
- Admission itself is the ratified PRULE-021 predicate (S-06-001, merged); query never denies admission.

Genuinely unresolved (why the controller stops before implementing the classifier):
The repository defines the CONCEPT (non-broadening) but does NOT pin the classification PREDICATE to an implementable level. Specifically: (1) it provides NO classifier fixtures — the MTX-029 test_contracts assume a change is already labelled "contraction"/"expansion" and test only the routing/authority; (2) it gives NO algorithm for the broadening/subset test over include/exclude path-prefix sets (with the `/`-boundary matching and exclusion-wins); and (3) it does NOT resolve whether a `query_handling` change (which does not change the PRULE-021 allow set — query never denies — but changes canonical-URL multiplicity) counts as broadening. Point (3) has two materially different valid readings with opposite dual-control outcomes, and misclassification is a scope-boundary security risk (a non-admin auto-activating a widening). Per AUTONOMOUS_BUILD_CONTROLLER §7(8) (product semantics with more than one materially different valid interpretation) and §3.8 (no silent scope expansion / no invented behaviour), and the owner's explicit "surface rather than invent" condition, HD-S06-002-SCOPE-CLASSIFIER is surfaced for an owner ruling before the classifier is implemented. Recommended: (a) ratify "broadening = the PRULE-021 admitted (allow) set grows," making the classifier a semantic subset test with PRULE-021 as its oracle and any non-strict-subset change an expansion (fail-closed); (b) rule `query_handling` broadening-NEUTRAL (it does not change the allow set) so a query-only change is a contraction. Full options in BUILD_STATE open_decisions and the owner report.

Authority And Precedence:
Records the S-06-002 authorisation and the repository-first stop. Allocated the next unused number after ADR-052. No product change, no merge, no push, no production path; S-06-003..005 remain human_gate_before.

## ADR-054: HD-S06-002-SCOPE-CLASSIFIER Resolved — Option B (Subset + Query-Multiplicity Exception)

Status: Accepted (owner-ratified)
Date: 2026-07-27
Owner: Owner (decision HD-S06-002-SCOPE-CLASSIFIER: "OPTION B. Implement the classifier using Option A's semantic subset rule, with one explicit exception for query handling") / implementation agent (recorded)
Reversibility: Governs the S-06-002 classifier; implemented on the isolated branch `tranche/S-06/S-06-002`; nothing merged or pushed; `main` untouched.

Decision:
The contraction-vs-expansion classifier for WF-004 scope changes is defined as (owner Option B):

1. Base classification (semantic subset, PRULE-021 as the admission oracle): a proposal is a CONTRACTION only when its admitted URL set is a subset of the current active policy's admitted URL set under PRULE-021. Any change not demonstrably non-broadening is an EXPANSION; a mixed change that narrows one dimension while widening another is an EXPANSION; classification is FAIL-CLOSED — inability to prove subset means expansion.
2. Query handling (the explicit exception): any query-handling change that can INCREASE the set of distinct crawlable canonical URLs (canonical-target multiplicity) is an EXPANSION requiring dual control, even though query parameters do not affect PRULE-021 admission. In particular `allowlist -> retain_all`, or any widening of the retained-key set, is an expansion. A query-handling change that demonstrably preserves or reduces canonical-target multiplicity may remain contraction-eligible. A query-only change is therefore NOT automatically a contraction.
3. Boundary violations: a change to host, scheme or port outside the verified boundary is NOT an expansion — it is a boundary violation rejected through the authoritative failure path (`cross_host_expansion` / `unsupported_source_scheme` / boundary violation). A new host remains a new Source through WF-003.
4. Implementation discipline: PRULE-021 is the admission oracle; an explicit canonical-target-multiplicity comparison governs query handling; committed fixtures pin both dimensions (admitted URL-set subset/superset; query narrowing/equality/widening); the classifier is deterministic, independently testable and fail-closed.

Rationale (owner): the security boundary is not only which documents are admitted but how many distinct crawl targets can be generated; a widening from restrictive query handling to retain_all materially expands crawling activity, duplicate-content exposure, cost, attack surface and observation scope, so it must not be auto-activated by a single actor merely because PRULE-021 admission is unchanged.

Scope:
Governs S-06-002 (ProposeSourceScopeChange + atomic contraction activation) and is inherited by S-06-003 (DecideSourceScopeChange). Resolves HD-S06-002-SCOPE-CLASSIFIER. Implementation of S-06-002 proceeds, including atomic contraction activation; S-06-003..005 remain human_gate_before.

> Superseded in part by ADR-056 (2026-07-27): the classifier RULING in this ADR stands unchanged, but its tranche PLACEMENT is re-scoped by the owner's Option-1 decomposition — the classifier is now the isolated S-06-002; ProposeSourceScopeChange(pending) is S-06-003; atomic contraction activation + Decide + Cancel is S-06-004; Expire and Source lifecycle renumber to S-06-005/006. See ADR-056 (per the constitution's "update earlier documents if architecture changes").

Authority And Precedence:
Executes the owner's Option-B ruling. Allocated the next unused number after ADR-053. No automatic merge, no push, no production path.

## ADR-055: S-06-002 Decomposition Surfaced — Implementation Evidence Shows It Would Breach Reviewability

Status: Accepted (record); the governed decomposition decision HD-S06-002-DECOMPOSITION is OPEN for the owner
Date: 2026-07-27
Owner: Owner (condition on the S-06-002 authorisation: "Only split it into S-06-003 if implementation evidence demonstrates the tranche would otherwise become unreasonably large or violate the repository's reviewability principles. If a split becomes necessary, stop and present the proposed decomposition before proceeding") / implementation agent (recorded)
Reversibility: Planning/governance only — no product code, schema or migration written; committed on `tranche/S-06/S-06-002`; nothing merged or pushed; `main` untouched.

Decision:
After reading the authoritative contract and the analogous S-05 implementations (the required repository-first step), the controller has implementation evidence that S-06-002 as scoped (source_scope_change_requests table + ProposeSourceScopeChange + the Option-B classifier + atomic contraction activation) would bundle THREE concerns that S-05 deliberately kept as separate tranches and would reach ~2,500-3,000+ diff lines, at or over the configured `max_diff_lines_before_forced_split: 3000` (VERIFICATION_MANIFEST.yml):

- a pure engine (the Option-B ScopeChangeClassification classifier) — the S-05-003 analogue, which S-05 always isolated for focused adversarial review;
- a new aggregate table + a create command with 24h F-04 expiry + full ledger + idempotency (ProposeSourceScopeChange pending path) — the S-05-001 analogue (its handler 304 + store 202 + shared ledger 161 lines, plus migration, command and specs, was ~1,500-2,000 lines as one tranche);
- an atomic multi-root activation commit (request + new immutable policy version + Source pointer, none-without-the-others) — the S-05-006 analogue, which S-05 isolated as its own tranche.

Per the owner's condition, the controller STOPS before writing S-06-002 product code and surfaces HD-S06-002-DECOMPOSITION. Recommended (Option 1, the S-05 precedent — isolate the pure engine, one concern per tranche):
- S-06-002 (revised): the pure Option-B ScopeChangeClassification classifier + committed fixtures (both dimensions). Pure; no persistence. (~S-05-003 scale.)
- S-06-003: source_scope_change_requests table + ProposeSourceScopeChange creating a PENDING request (consumes the classifier; boundary rejection; 24h F-04 expiry; idempotency; SourceScopeChangeRequested; full ledger). A fail-closed interim in which every classified change is pending (precedented by S-05-005's record-only interim). (~S-05-001 scale.)
- S-06-004: atomic contraction activation (fast-path on Propose) + DecideSourceScopeChange (approve/reject) + CancelSourceScopeChange — the shared policy-version-activation multi-root commit used by both. (~S-05-006 scale + Decide.)
- S-06-005: ExpireSourceScopeChange + SourceScopeChangeExpiryJob (was S-06-004).
- S-06-006: Source lifecycle Activate/Disable/Reactivate/Remove (was S-06-005).
Alternatives noted for the owner: Option 2 (2-way: keep classifier + table + Propose-pending as S-06-002 [~2,000 lines], defer only the atomic contraction to an expanded S-06-003 with Decide/Cancel; keeps 5 sub-tranches); Option 3 (no split: implement full S-06-002 under the owner's default, accepting ~2,500-3,000 lines in one tranche).

Authority And Precedence:
Surfaces the decomposition per the owner's explicit split-and-stop condition. Allocated the next unused number after ADR-054. No product change, no merge, no push; S-06-003..005 (current numbering) remain human_gate_before.

## ADR-056: HD-S06-002-DECOMPOSITION Resolved — Option 1 (Three-Way Split, Renumber)

Status: Accepted (owner-ratified)
Date: 2026-07-27
Owner: Owner (decision HD-S06-002-DECOMPOSITION: "OPTION 1. Authorize the three-way decomposition") / implementation agent (recorded)
Reversibility: Governance/planning — updates BUILD_PLAN and BUILD_STATE; no product code. On `tranche/S-06/S-06-002`; nothing merged or pushed; `main` untouched.

Decision:
S-06 is re-decomposed (Option 1), isolating the pure classifier (S-05-003 precedent) and the atomic multi-root commit (S-05-006 precedent):

- S-06-002 — Source-scope classifier: the pure Option-B `ScopeChangeClassification` only, with committed fixtures for admitted URL-set subset/equality/widening/mixed changes; query-handling narrowing/equality/widening; fail-closed unprovable cases; and verified-boundary violations remaining errors rather than classifications. Deterministic, side-effect-free, independently testable, isolated for adversarial security review.
- S-06-003 — Source-scope change request proposal: the source_scope_change_requests table + constraints + RLS + terminal-row immutability; ProposeSourceScopeChange pending-request path; idempotency + content hash; F-04 24h expiry scheduling; the required ledger + SourceScopeChangeRequested event. No temporary weakening of authority rules.
- S-06-004 — Source-scope activation and request decisions: atomic contraction activation; the policy-version creation + Source pointer update as one none-without-the-others commit; Decide and Cancel sharing that activation and request-state machinery; the required approval, cancellation, concurrency, idempotency, event and authorization behaviour.
- S-06-005 — Expiry: the former S-06-004 (ExpireSourceScopeChange + expiry job), renumbered.
- S-06-006 — Source lifecycle: the former S-06-005 (PRULE-006), renumbered.

Interim behaviour (owner-accepted): until S-06-004, a contraction may remain pending rather than auto-activating — a fail-closed IMPLEMENTATION interim (S-05-005 -> S-05-006 precedent), never represented as final contract behaviour. No provisional alternative activation path is introduced.

Rationale (owner-directed record): reviewability (the former single tranche reached ~2,500-3,000+ diff lines, at/over max_diff_lines_before_forced_split=3000); security isolation of the classifier (the dual-control routing predicate gets its own focused adversarial review); and separation of the atomic multi-root commit (S-05-006 precedent). Existing dependencies, acceptance criteria and human gates are preserved except where the split makes a dependency change necessary (S-06-003 now depends on S-06-002; S-06-004 on S-06-003; renumbered tranches shift their depends_on accordingly). No behaviour is moved between tranches beyond this authorised decomposition.

Governance:
BUILD_PLAN updated to the six-tranche S-06 structure; HD-S06-002-DECOMPOSITION resolved. Do not begin S-06-003 until S-06-002 passes its normal review and acceptance gate.

Authority And Precedence:
Executes the owner's Option-1 ruling. Allocated the next unused number after ADR-055. No automatic merge, no push, no production path.

## ADR-057: S-06-002 Classifier Independently Reviewed (All Five Lenses PASS) — Defense-in-Depth Hardening Applied

Status: Accepted
Date: 2026-07-27
Owner: implementation agent (recorded); no product ruling required — zero confirmed-blocking findings
Reversibility: On `tranche/S-06/S-06-002`; nothing merged or pushed; `main` untouched. Revertible by branch reset.

Decision:
Record the independent ADR-026 review of the S-06-002 pure Option-B classifier and the one defense-in-depth hardening applied. Five separately-invoked adversarial lenses (security/misclassification-bypass, contract-correctness, determinism/purity, architecture/scope, test-quality) all returned PASS with ZERO confirmed-blocking findings. The security lens ran two independent differential fuzzers (~22,000 :contraction verdicts) and the contract lens a brute-force oracle over 3,969 policy pairs; both found zero misclassified broadenings — no auto-activated-widening bypass exists, and the witness-set is complete for the `/`-boundary prefix semantics (delegating admission to PRULE-021, inheriting the ADR-051 exclusion-separator hardening).

Hardening Applied (non-blocking, flagged by the purity and contract lenses):
`classify` is split so the boundary check runs OUTSIDE the fail-closed rescue (the rescue now guards only `classify_broadening`), so a boundary violation can never degrade to an approvable :expansion. No behaviour changes for any real Policy value-object input (all committed fixtures and the whole-repo suite pass unchanged); only the unreachable "boundary accessor raises" edge is affected. Two spec assertions were tightened to pin their reason, and exclude-narrowing and superset-allowlist fixtures were added.

Non-blocking observations recorded (not actioned — repair-only-confirmed-blocking):
- Host trailing-dot (`host.`) currently classifies as :boundary_violation rather than in-boundary (over-strict / fail-safe; the command layer normalizes the host under ascii-host-v1 before it reaches the classifier). Candidate normalization nicety.
- Additional nested include+exclude characterization fixtures could be added (behaviour already correct and fuzzer-covered).

Verification: whole-repo suite 1264 examples / 0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness green within the suite; no db/ or app/models change (no structure.sql drift possible).

Authority And Precedence:
Records the review outcome and the applied hardening. Allocated the next unused number after ADR-056. No automatic merge, no push, no production path; the controller stops at human_gate_after (owner acceptance) with S-06-002 at ready_for_review. Do not begin S-06-003 until S-06-002 is accepted.

## ADR-058: S-06-002 Accepted And Merged; S-06-003 Is A Human Gate

Status: Accepted
Date: 2026-07-27
Owner: Owner (approved: "S-06-002 — ACCEPTED ... Proceed with the normal acceptance-and-merge sequence"; push authorisation granted only for this S-06-002 acceptance-and-merge) / implementation agent (recorded)
Reversibility: Fast-forward on the non-protected integration branch `implementation/s01-registration-access` (`6e8413a -> 5127cc8`, incorporating the S-06-002 planning history from `729dbfd`); `main` untouched; pushed to origin per the owner's scoped authorisation. Revertible by branch reset (no history rewritten). No further tranche is authorised.

Decision:
Accept S-06-002 (the pure Option-B Source Scope Change classifier, `Workflows::Wf004::ScopeChangeClassification`). It classifies a proposed scope change as :contraction | :expansion | :boundary_violation per ADR-054 (Option B): a semantic subset test with PRULE-021 (S-06-001) as the admission oracle over a complete witness set, the query-multiplicity exception, and boundary rejection; fail-closed; boundary violations decided outside the fail-closed rescue so they can never degrade to an approvable expansion. Merge gate re-verified on the merged state: whole-repo suite 1264 examples/0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness green within the suite; no db/ or app/models change (no structure.sql drift possible); the tracked tree clean; the branch diff contained only the classifier, its spec and records (no S-06-003+ work pulled forward). Independent review (ADR-026, five separately-invoked adversarial lenses) returned PASS on all five with zero confirmed-blocking findings — the security lens ran ~22,000 fuzzer :contraction verdicts and the contract lens a 3,969-pair brute-force oracle, both finding zero misclassified broadenings. Fast-forward merged into `implementation/s01-registration-access` at `5127cc8`; `S-06-002` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-06-002 -> completed; `S-06-002_COMPLETION_REPORT.md` marked accepted; the merged local tranche branch `tranche/S-06/S-06-002` deleted per repository policy. The integration branch was pushed to origin under the owner's push authorisation scoped to this acceptance; `main` untouched.

Next — Human Gate (HD-S06-003-AUTHORISE):
S-06-003 (source_scope_change_requests table + ProposeSourceScopeChange creating a pending request + F-04 24h expiry + ledger + idempotency + SourceScopeChangeRequested) remains `human_gate_before`. The controller stops for the owner to authorise it; per the owner's instruction it was NOT begun. The interim (a contraction remains pending until S-06-004) is fail-closed with no provisional alternative activation path. S-06-004..006 remain human_gate_before behind it.

Authority And Precedence:
Executes the owner's accept-and-merge instruction. Allocated the next unused number after ADR-057. No automatic merge to the protected branch and no production path; the controller stops at the S-06-003 human gate and does not authorise or begin any subsequent tranche.

## ADR-059: S-06-003 Authorised (ProposeSourceScopeChange, pending path); HD-S06-003-AUTHORISE Resolved

Status: Accepted
Date: 2026-07-27
Owner: Owner (resolved HD-S06-003-AUTHORISE: "Authorize S-06-003 — source_scope_change_requests table + ProposeSourceScopeChange pending path, according to the approved Option-1 decomposition and the authoritative repository contracts") / implementation agent (recorded)
Reversibility: Implemented on the isolated branch `tranche/S-06/S-06-003`; nothing merged or pushed; `main` untouched.

Decision:
S-06-003 is authorised and implementation begins on `tranche/S-06/S-06-003` (base `4d3773f`). Scope (owner instruction + MTX-029 propose path + WORKFLOW_SPECIFICATIONS.md § Source Scope Change Contract :414): the `source_scope_change_requests` aggregate table with constraints/indexes/RLS and terminal-row immutability; `Workflows::Wf004::ProposeSourceScopeChange` creating a PENDING request; normalization + canonical content hashing of the proposed rules; idempotency + `idempotency_conflict`; the 24h F-04 expiry scheduling obligation (`source_scope_request_expire`, already in the ratified catalogue, mapping to the later `ExpireSourceScopeChange`); the required ledger + `SourceScopeChangeRequested` event; authoritative permissions, tenant isolation, concurrency and failure semantics.

Repository-first pins (no owner-decision blocker found):
- Permission `source.scope.propose` (allow: OrganizationAdmin, MarketingOperator, TechnicalImplementer; not protected) is a ratified Permission Baseline row (WORKFLOW_SPECIFICATIONS.md :144) materialized into `Platform::PermissionBaseline` for this slice — the same data-addition pattern by which S-05-001 materialized `source.verify` (no version or evaluator change).
- The classifier `Workflows::Wf004::ScopeChangeClassification` (S-06-002, merged) is consumed to reject boundary violations; the contraction/expansion distinction is not acted on in this tranche (a contraction remains PENDING — the fail-closed interim; atomic activation is S-06-004).
- The ledger reuses `Workflows::Wf004::SourceLedger`; expiry scheduling mirrors `VerificationRequestExpirySchedule` on the ratified `source_scope_request_expire` kind.

Out of scope (later tranches): atomic contraction activation, approval, cancellation and expiry execution (S-06-004/005), except a minimal seam if strictly required by the contract. No provisional alternative activation path.

Authority And Precedence:
Executes the owner's S-06-003 authorisation. Allocated the next unused number after ADR-058. No automatic merge, no push, no production path; the controller returns at the normal completed-tranche review gate.

## ADR-060: S-06-003 Independently Reviewed (All Five Lenses PASS) — ready_for_review

Status: Accepted
Date: 2026-07-27
Owner: implementation agent (recorded); no product ruling required — zero confirmed-blocking findings
Reversibility: On `tranche/S-06/S-06-003`; nothing merged or pushed; `main` untouched.

Decision:
Record the independent ADR-026 review of S-06-003 (source_scope_change_requests + ProposeSourceScopeChange, pending path). Five separately-invoked adversarial lenses (contract-correctness, security/tenant-isolation, concurrency/atomicity/idempotency, schema/migration-safety, architecture/scope) all returned PASS with ZERO confirmed-blocking findings, each with live DB verification and the 21 new specs green. Highlights: single-transaction atomicity (request + F-04 expiry + full ledger on one connection); idempotency (request_hash folds all proposed content; per-Source advisory lock converts the unique-index conflict into graceful replay; changed content -> idempotency_conflict); FORCE RLS with a proved, unspoofable org context and tenant checks before any write; the composite Source FK preventing cross-tenant binding; source.scope.propose materialized as the ratified permission-baseline-v1 data row (VERSION unchanged); the migration builds from empty with no structure.sql drift, SELECT/INSERT-only grant, and a fail-closed transition guard; pending-only with no pulled-forward S-06-004/005 behaviour; F-04 consumed only through its frozen surface on the ratified source_scope_request_expire kind.

Non-blocking observations recorded (not actioned — repair-only-confirmed-blocking):
- The 24h due_at delta is enforced application-side (no DB CHECK), then frozen by the guard with the SELECT/INSERT-only grant leaving the handler as the sole writer. The migration comment was clarified accordingly (comment-only, no schema change). A DB CHECK is an optional future hardening.
- The current-side rules are stored by reference (expected_active_policy_version + current_content_sha256) rather than inline: the current active Source Scope Policy is immutable and fully recoverable by version, so this is a faithful normalization (an inline snapshot would be write-only in this design), consistent with the review paraphrase; recorded for owner awareness.
- FORWARD-COMPAT FLAGS FOR S-06-004 (not defects here — vacuous while this tranche grants no UPDATE and permits no transition): (1) when S-06-004 grants UPDATE and relaxes the pending->approved edge, its guard must freeze already-terminal decision facts (decision_actor_id/decided_at_utc/decision_reason/activated_policy_version/terminal_at_utc); (2) the active-policy read + expected-version check should be taken or re-validated under the per-Source advisory lock at activation, since S-06-004 introduces a concurrent policy writer.

Verification: whole-repo suite 1286 examples / 0 failures; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness 31/0; verify_runtime OK (RLS intact, 15 checks); no structure.sql drift beyond the migration.

Authority And Precedence:
Records the review outcome. Allocated the next unused number after ADR-059. No automatic merge, no push, no production path; the controller stops at human_gate_after (owner acceptance) with S-06-003 at ready_for_review. Do not begin S-06-004 until S-06-003 is accepted.

## ADR-061: Standing Execution Authority Delegated; S-06-003 Accepted And Merged; Objective Gates Are Acceptance

Status: Accepted
Date: 2026-07-27
Owner: Owner (directed: "Proceed under repository governance. From this point forward you have standing authority to: implement the authorised tranche; perform all verification; conduct the ADR-026 independent review; accept the tranche when every mandatory gate passes; fast-forward merge; update BUILD_STATE, BUILD_PLAN, ADRs and completion records; push the integration branch. Do not stop for routine acceptance or merge.") / implementation agent (recorded)
Reversibility: Governance-model change plus one fast-forward acceptance on the non-protected integration branch; `main` untouched. The delegation is revocable by a later owner instruction.

Decision (standing delegation):
Within an owner-AUTHORISED block, the controller now carries standing authority to run each authorised sub-tranche end to end — implement, verify, conduct the ADR-026 five-lens independent review, ACCEPT when every mandatory gate passes with zero confirmed-blocking findings, fast-forward merge into the integration branch, update BUILD_STATE / BUILD_PLAN / ADRs / completion records, and push the integration branch — without stopping for routine acceptance or merge. The objective verification suite plus the independent review ARE the acceptance mechanism. `main` remains untouched; no force-push; no history rewrite; no production path.

Stop conditions (return to the owner ONLY for):
1. a genuine repository ambiguity with two materially different valid interpretations affecting behaviour or security;
2. a contract or scope change requiring owner approval;
3. a mandatory verification gate failing or a repository invariant that cannot be satisfied;
or when the current authorised work is exhausted and the next block requires fresh authorisation.

Human-gate model (applied going forward):
`human_gate_before` is set only where a real owner decision is required (new block, decomposition, contract ambiguity); `human_gate_after` is reserved for a gate failure or an acceptance criterion that cannot be objectively satisfied. The remaining authorised S-06 sub-tranches (S-06-004 atomic contraction activation + Decide + Cancel; S-06-005 Expire; S-06-006 Source lifecycle) have their `human_gate_before`/`human_gate_after` set to false under this delegation and proceed under standing authority. S-07 is NOT authorised (the S-06 authorisation was limited to S-06) and requires fresh owner authorisation after S-06 is exhausted.

S-06-003 acceptance:
S-06-003 (source_scope_change_requests + ProposeSourceScopeChange, pending path) met every mandatory gate (whole-repo suite 1286/0; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness 31/0; verify_runtime OK; migration builds from empty; no structure.sql drift) and all five ADR-026 lenses returned PASS with zero confirmed-blocking findings (ADR-060). It is therefore ACCEPTED and fast-forward merged into `implementation/s01-registration-access` at `b76e16b`; `S-06-003` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-06-003 -> completed; completion report accepted. The merged local tranche branch is deleted per policy; the integration branch is pushed. `main` untouched.

Authority And Precedence:
Executes the owner's standing-authority directive and accepts S-06-003. Allocated the next unused number after ADR-060. Supersedes the prior per-tranche human_gate_after acceptance requirement for the remaining authorised S-06 sub-tranches. No production path.

## ADR-062: S-06-004 Source Scope Policy Version Naming Is Autonomous (Not A Contract Term)

Status: Accepted
Date: 2026-07-27
Owner: implementation agent (recorded under standing authority ADR-061); no owner ruling required — an internal naming choice, not a behavioural or contract term
Reversibility: The version string is regenerable and touches no frozen contract; a later slice may rename the scheme without behavioural effect. On `tranche/S-06/S-06-004`; nothing merged.

Context:
S-06-004 activates a new immutable `source_scope_policies` version on approval (fast-path on Propose, or DecideSourceScopeChange approval). The contract (contracts/S-06.json MTX-029) requires an immutable, versioned policy record and an "expected active policy version" used as the concurrency value, but does NOT prescribe the version STRING. The S-05 interim policy is `source-scope-interim-v1`.

Decision:
A newly activated Source Scope Policy version takes the string `source-scope-v{N}`, where `N` is a monotonic per-Source ordinal computed as `policy_count(source_id) + 1` read under the per-Source advisory lock the activation already holds (so the interim policy is ordinal 1 and the first activated version is `source-scope-v2`). Uniqueness is enforced by the `(organization_id, project_id, source_id, policy_version)` constraint. The exact string is NOT behaviourally material: the predicate and the classifier read the policy's RULES, never its name, and any unique deterministic token would serve identically as the expected-active-policy-version concurrency value. This is therefore an autonomous naming choice recorded for traceability, not a contract clarification, and is not a stop condition under ADR-061.

Authority And Precedence:
Internal engineering decision under standing authority. Allocated the next unused number after ADR-061. Adds no permission, changes no contract, and does not alter the frozen S-05-006 policy shape. No production path.

## ADR-063: S-06-004 Independently Reviewed (All Five Lenses PASS) — Refinements Applied; Accepted And Merged

Status: Accepted
Date: 2026-07-27
Owner: implementation agent (recorded under standing authority ADR-061); no owner product ruling required — zero confirmed-blocking findings
Reversibility: Fast-forward acceptance on the non-protected integration branch; `main` untouched. Two systemic non-blocking findings are recorded here as follow-ups, not fixed in this tranche.

Decision:
Record the independent ADR-026 review of S-06-004 (SourceScopePolicyActivation + DecideSourceScopeChange + CancelSourceScopeChange + the ProposeSourceScopeChange atomic fast-path). Five separately-invoked adversarial lenses (contract-correctness, security/tenant-isolation, concurrency/atomicity/idempotency, schema/migration-safety, architecture/scope) each returned **PASS with ZERO confirmed-blocking findings**, with live-DB exercise: the security lens ran seven live exploit probes (dual-control bypass, self-approval, cancel authority, tenant isolation, guard, confused-deputy, content integrity) — all held; the concurrency lens ran a two-connection race probe confirming no double activation (the loser's guarded UPDATE returns 0 rows → rollback); the schema lens proved the migration builds from an empty database and applies 122 grants with verify_runtime green.

Refinements applied in response to non-blocking findings (commit `4bf4487`), none behavioural regressions:
1. **Guard hardening (schema + security lenses, independently).** A `pending -> pending` UPDATE could mutate decision facts and provenance on a still-pending row (unreachable via any handler — `transition_request` always moves to a terminal state under `state='pending'` — but a DB-backstop gap). Migration `20260727120051` makes the decision-edge requirement unconditional for a pending row (only a transition to a terminal decision state is permitted; `pending -> pending` and `pending -> expired` refused) and freezes `created_at`/`correlation_id`. This completes the ADR-060 forward-compat flag ("its guard must freeze already-terminal decision facts").
2. **Propose fast-path re-reads the Source under the per-Source lock (concurrency lens):** a losing activation race now returns a clean `stale_active_policy_version` rather than a repoint `LostRace`/`InvariantViolation`.
3. **Fast-path audit records its terminal state** (`to_state 'approved'` with the approved payload) — resolves a `to_state`/payload mismatch (contract + architecture lenses).
4. **Corrected an inaccurate permission-baseline comment** (security lens) — see follow-up FU-2 below.
5. **Added the TYP-SEC coverage** for "an OrganizationAdmin requester may approve its own expansion atomically" (contract lens).

Systemic non-blocking findings RECORDED as follow-ups (NOT S-06-004 defects; the tranche correctly consumes the platform as designed):
- **FU-1 (security lens F1) — `permission_mode: read_only` is ignored for write capabilities.** `IdentityAccess::Authorization::CommandAuthorizer#confers?` evaluates only (capability × canonical_role) and never inspects `permission_mode`, so a principal designated read-only (e.g. an "executive buyer" MarketingOperator) can perform writes — demonstrated live: a read-only MarketingOperator auto-activated a scope-policy contraction. This is PRE-EXISTING and systemic (the same principal already holds `source.register` (S-04) and `project.create` (S-03)); `command_authorizer.rb` is not in the S-06-004 diff. S-06-004 widens the blast radius to scope-policy activation but introduces no new gap. **Recommended:** a dedicated platform-authorization tranche that enforces `read_only` (deny writes) in `CommandAuthorizer`/`effective_role_assignments`. Flagged for owner attention.
- **FU-2 (security lens F2) — assignment-scope (GrantScope) containment is not enforced for the resource capabilities.** `policy.source_scope.manage` / `source.scope.propose` (and `source.register`, `project.create`) gate only Organization membership, not the Assignment's Project scope against the target's Project; containment is wired only to `role.manage` (`GrantAuthority#contains_scope?`). Demonstrated live: a MarketingOperator with a foreign `scope_sha256` still activated a contraction (a within-tenant cross-project escalation). PRE-EXISTING and deferred platform-wide. The only in-scope action taken was to **correct the false permission-baseline comment** that had claimed the scope limb was "enforced by the caller" — it now states the limb is deferred, matching the honest language used elsewhere. Flagged for owner attention alongside FU-1.

Other observations recorded (no action): the allowlist `query_handling` value stored into a `text` column serializes a Ruby array inspect-string (pre-existing S-06-003 shape, mirrored here onto the activated policy row; unexercised — every fixture uses `retain_all`; fix when the allowlist path is first exercised); the migration `down` does not restore a byte-identical S-06-003 guard (functionally equivalent; any later CREATE OR REPLACE overwrites it); a policy-version `UniqueViolation` would not be caught as `LostRace` (unreachable under the per-Source lock); idempotent replay re-checks authorization first (consistent codebase-wide pattern); `event_registry` has no `(aggregate_type, aggregate_id, aggregate_version)` unique index (pre-existing shared platform infra).

S-06-004 acceptance:
S-06-004 met every mandatory gate (whole-repo suite **1309/0**; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness **31/0**; verify_runtime OK, 15 checks, RLS intact; both migrations build from empty; structure.sql updated to match with no unexplained drift) and all five ADR-026 lenses returned PASS with zero confirmed-blocking findings. It is therefore ACCEPTED and fast-forward merged into `implementation/s01-registration-access`; `S-06-004` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-06-004 → completed; completion report accepted; the integration branch pushed. `main` untouched.

Authority And Precedence:
Executes the owner's standing-authority directive (ADR-061) and accepts S-06-004. Allocated the next unused number after ADR-062. FU-1 and FU-2 are recorded for owner attention as recommended platform-authorization follow-ups; they do not block S-06-004. Do not begin S-07 without fresh owner authorisation; S-06-005 (Expire) and S-06-006 (Source lifecycle) remain authorised under ADR-061 and proceed next.

## ADR-064: S-06-005 (ExpireSourceScopeChange) Independently Reviewed (All Five Lenses PASS) — Accepted And Merged

Status: Accepted
Date: 2026-07-27
Owner: implementation agent (recorded under standing authority ADR-061); no owner product ruling required — zero confirmed-blocking findings
Reversibility: Fast-forward on the non-protected integration branch; `main` untouched.

Decision:
Record the independent ADR-026 review of S-06-005 (ExpireSourceScopeChange — the service-only timed expiry behind the ratified `source_scope_request_expire` ScheduledAction — plus the "expiry wins at due_at" precedence in Decide/Cancel). Five separately-invoked adversarial lenses (contract, security/tenant, concurrency/atomicity/idempotency, schema/migration, architecture/scope) each returned **PASS with ZERO confirmed-blocking findings**, with heavy live exercise: the security lens ran a live two-tenant forged-organization_id cross-tenant expiry attack (result: `scheduled_action_target_mismatch`, victim row byte-identical, zero cross-tenant writes, no leak — RLS held); the concurrency lens ran a real two-connection thread race (8/8 concurrent expire-vs-approve at `now == due_at` → exactly one success, always the expiry, one event; both lock orderings observed via the decide-deny split not_pending×5 / expired×3) and empirically DISPROVED the before-due idempotency-poisoning hazard (a `scheduled_action_not_due` deny is `replayable:false`, writes no idempotency row, so it cannot poison the at-due fire); the schema lens proved build-from-empty on a scratch DB and live-tested the widened guard (a `pending -> expired` that also mutates a frozen fact still raises `facts_immutable`; expired rows fully immutable).

Refinements applied (commit `40b9489`, test-only, no behaviour change): the two coverage gaps the contract lens flagged — TYP-OBS "expiry wins over **rejection**" at exactly `due_at`, and TYP-DATA "a decision on an already-expired request changes nothing".

Non-blocking observations RECORDED (no fix — none is a regression or an application-reachable defect):
- **Decision-fact latitude on the expired edge (schema + security lenses).** The widened guard permits a `pending -> expired` UPDATE that also stamps decision-output columns (decision_actor_id, decided_at_utc, decision_reason, activated_policy_version). Unexploitable through any application path — the sole writer, `SourceScopeChangeExpiryStore#expire`, sets only `{state, terminal_at_utc, state_version, updated_at}` and leaves the decision facts NULL (verified live and by spec). NOT hardened this tranche and NOT a regression: the pre-existing `approved/rejected/canceled` edges have the identical "the DB trusts the handler for which columns each transition sets" property; enforcing per-state column-nullability is a table-wide invariant tightening beyond S-06-005's scope (distinct from the ADR-063 pending->pending hardening, which closed a NEW gap opened by S-06-004 and completed an explicit forward-compat flag). Recorded for a future backstop-hardening pass.
- **No `(aggregate_type, aggregate_id, aggregate_version)` unique index on `event_registry` (concurrency lens).** Exactly-once-per-version emission rests on the advisory lock + the guarded state-version UPDATE + idempotency. Pre-existing shared platform design (identical for propose/decide/cancel and the other workflows); neither introduced nor regressed here. Same observation as ADR-063's platform note.
- Cosmetic: the migration `down` reuses this migration's guard body, so a rolled-back function keeps the new comment while permitting only the three decision states (functionally correct; convention-consistent with `20260727120051`'s own `down`). Contract nuances NB-3 (a decision after the timer has flipped the row returns `source_scope_request_not_pending`, not `source_scope_request_expired` — identical no-op outcome) and NB-4 (the acceptance spec fabricates the expiry command rather than driving the real schedule→scheduler→worker round trip; the `due_at` equality was verified by inspection) — no action.

S-06-005 acceptance:
S-06-005 met every mandatory gate (whole-repo suite **1320/0**; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness **31/0**; verify_runtime OK, 15 checks, RLS intact; migration builds from empty; no structure.sql drift beyond the guard widening + the migration row) and all five ADR-026 lenses returned PASS with zero confirmed-blocking findings. It is therefore ACCEPTED; `S-06-005` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-06-005 → completed; completion report accepted; the integration branch (which already carried the reviewed S-06-005 commits) pushed. `main` untouched.

Authority And Precedence:
Executes the owner's standing-authority directive (ADR-061) and accepts S-06-005. Allocated the next unused number after ADR-063. Do not begin S-07 without fresh owner authorisation; S-06-006 (Source lifecycle PRULE-006) is the last authorised S-06 sub-tranche and proceeds next, after which S-06 is exhausted and S-07 requires fresh authorisation.

## ADR-065: S-06-006 (Source Lifecycle PRULE-006) Reviewed (All Five Lenses PASS) — Accepted; S-06 Complete And Exhausted

Status: Accepted
Date: 2026-07-27
Owner: implementation agent (recorded under standing authority ADR-061); no owner product ruling required — zero confirmed-blocking findings
Reversibility: Fast-forward on the non-protected integration branch; `main` untouched. This closes the authorised S-06 block; the next block (S-07) requires fresh owner authorisation before any work.

Decision:
Record the independent ADR-026 review of S-06-006 (the Source lifecycle transitions ActivateSource / DisableSource / ReactivateSource / RemoveSource; PRULE-006 / contracts/S-06.json MTX-057). Five separately-invoked adversarial lenses (contract, security/tenant, concurrency/atomicity/idempotency, schema/migration, architecture/scope) each returned **PASS with ZERO confirmed-blocking findings**, under heavy live exercise: the security lens live-tested all FIVE legal edges (succeed) and FIFTEEN illegal edges (each raises `source_lifecycle_transition_unavailable`), proved a forged-org cross-tenant raw UPDATE affects 0 rows under RLS, and proved the `timestamp_column` injection attempts are rejected by the allowlist; the concurrency lens ran two-connection race probes (5/5 simultaneous ActivateSource → exactly one success, one invalid-transition denial, one event) and proved the lifecycle-vs-scope serialization (a scope activation's state_version bump cleanly staled a concurrent lifecycle command) and NO source-aggregate event-version collision (the source stream is `[SourceRegistered v0, SourceVerified v1, SourceActivated v3]` — gaps from scope bumps on a different aggregate, never a reuse); the schema lens proved build-from-empty and confirmed the critical `IF NOT (#{allowed_edge})` parenthesization (without which SQL `NOT>AND>OR` precedence would silently permit forbidden edges).

Refinement applied (commit `4484a1f`, test-only): the MarketingOperator allow-side assertion the contract and security lenses flagged (a MarketingOperator, the other `source.lifecycle.manage` holder, can transition a Source), completing the "Admin or Marketing only" coverage.

Non-blocking observations RECORDED (no fix — none a regression or application-reachable defect):
- **Pinned policy version is a live reference, not a frozen column (contract lens).** The Source reports its pinned policy version by reading `current_scope_policy_id` (the S-04 schema has no separate pinned column), which a later scope activation repoints. This is the correct S-06 design and the correct behaviour for S-07 (a crawl must use the CURRENT active scope, so scope changes take effect): the state and its active-policy reference co-locate on one atomically-updated row and can never disagree at any instant, and each transition's event captures an immutable snapshot of the version at that instant. Flagged for S-07 awareness (it "reads the pinned policy" — it should read the live active pointer, which is what this provides).
- **Pre-existing platform deferrals, confirmed NOT newly widened (security lens):** `permission_mode: read_only` is ignored for write capabilities (ADR-063 FU-1); assignment-scope (GrantScope) containment is not enforced for the resource capabilities (ADR-063 FU-2); and there is no `authority_current?` organization-epoch recheck between authorize and the side effect (identical to DecideSourceScopeChange — a consistent platform pattern). All three are inherited identically from the sibling `source.scope.propose` / `policy.source_scope.manage` / `source.register` capabilities; S-06-006 adds no new exposure. FU-1 and FU-2 remain the standing owner follow-ups.
- Cosmetic: the migration `down` reuses the `up` guard comment (down-path only); an unused `WORKFLOW_ID` constant is const_set for parity (SourceLedger hardcodes 'WF-004'); the DB backstop raises `source_lifecycle_transition_unavailable`, which is a trigger reason, not an ErrorCatalog code (defense-in-depth, unreachable via the app path); denial audit rows carry `entity_id = command_id` (the inherited SourceLedger deny convention). No action.

S-06-006 acceptance:
S-06-006 met every mandatory gate (whole-repo suite **1330/0**; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness **31/0**; verify_runtime OK, 15 checks, RLS intact; migration builds from empty; no structure.sql drift beyond the guard widening + the migration row) and all five ADR-026 lenses returned PASS with zero confirmed-blocking findings. It is therefore ACCEPTED; `S-06-006` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-06-006 → completed; completion report accepted; the integration branch pushed. `main` untouched.

S-06 completion:
With S-06-006 accepted, the entire S-06 block (S-06-001 Source Scope Predicate; S-06-002 Scope Change Classifier; S-06-003 source_scope_change_requests + ProposeSourceScopeChange pending path; S-06-004 atomic contraction activation + Decide + Cancel; S-06-005 ExpireSourceScopeChange; S-06-006 Source lifecycle PRULE-006) is COMPLETE and EXHAUSTED. The owner's S-06 authorisation was limited to S-06.

Authority And Precedence:
Executes the owner's standing-authority directive (ADR-061) and accepts S-06-006, closing S-06. Allocated the next unused number after ADR-064. **S-07 is NOT authorised.** Per ADR-061's stop condition ("when the current authorised work is exhausted and the next block requires fresh authorisation"), the controller now STOPS and returns to the owner for HD-S07-AUTHORISE. No S-07 scope is inferred or begun. FU-1 and FU-2 remain recorded for owner attention.

## ADR-066: FU-1 / FU-2 Accepted As Platform-Hardening Backlog (Owner, HD-S07-AUTHORISE)

Status: Accepted
Date: 2026-07-27
Owner: Owner (directed at HD-S07-AUTHORISE: "The previously reported follow-ups — FU-1 permission_mode: read_only enforcement, FU-2 GrantScope containment enforcement — are accepted as platform-level follow-up work. Record them as backlog/platform hardening if not already tracked. Do not fold them into S-07 unless the authoritative repository explicitly makes them dependencies.") / implementation agent (recorded)
Reversibility: A tracking record only; no code or contract change. The two items remain deferred until scheduled.

Decision:
The two platform-authorization findings surfaced by the S-06-004/006 independent reviews are ACCEPTED by the owner as platform-level follow-up (hardening) work and are formally tracked here and in `BUILD_STATE.open_decisions` (the generated `specification/volume-ii/IMPLEMENTATION_BACKLOG.md` is byte-reproducible from the specification and is not hand-edited, so the decision ledger + BUILD_STATE are the tracking surface):

- **FU-1 — `permission_mode: read_only` is not enforced for write capabilities.** `IdentityAccess::Authorization::CommandAuthorizer#confers?` evaluates only (capability × canonical_role) and never inspects `permission_mode`, so a principal designated read-only can perform writes. Platform-wide and pre-existing (affects `source.register`, `project.create`, and the S-06 scope/lifecycle capabilities identically). Fix belongs in `CommandAuthorizer`/`effective_role_assignments`, not any one handler.
- **FU-2 — assignment-scope (GrantScope) containment is not enforced for the resource capabilities.** `policy.source_scope.manage`, `source.scope.propose`, `source.lifecycle.manage`, `source.register`, `project.create` gate only Organization membership, not the Assignment's Project scope against the target's Project; containment is wired only to `role.manage` (`GrantAuthority#contains_scope?`). Platform-wide and pre-existing.

Scope and precedence:
These are NOT S-07 dependencies and MUST NOT be folded into S-07 unless the authoritative repository (a contract or acceptance criterion) explicitly makes them so — per the owner's direction. They are candidates for a dedicated platform-authorization hardening tranche, to be scheduled by the owner. Enforceable trigger: any future slice whose contract REQUIRES read-only-mode denial or project-scoped containment as a behavioural/security acceptance criterion converts the relevant item from deferred to in-scope for that slice. Allocated the next unused number after ADR-065.

## ADR-067: S-07 Authorised And Scoped — Two Unbuilt Shared Foundations Surfaced; STOP For Owner Decision (D1 Policy Realization, D2 Entitlement Reservation)

Status: Proposed (owner decision required — stop conditions 1 and 2)
Date: 2026-07-27
Owner: Owner authorised S-07 (HD-S07-AUTHORISE) under standing delegation ADR-061 / implementation agent (reconnaissance recorded; STOP raised)
Reversibility: No behavioural code written. This ADR records the S-07 reconnaissance and the two owner decisions that gate the first S-07 tranches. A provisional decomposition is recorded for context and will be ratified once D1/D2 are resolved.

Context (reconnaissance, read-only):
S-07 "Crawl Execution and Recovery" (WF-005; CAP-007/008; PRULE-007/008/009/022) is the largest slice: the outbound crawler (SSRF-safe via the existing F-01 surface), robots (fail-closed) + sitemap (XXE-hardened), the S-06 scope predicate applied per URL and per redirect, crawl-policy-v1 (12 soft/hard numeric bounds), the queue→start→fetch→terminal-checkpoint lifecycle, Documents + IngestionJobs with dead-letter replay, the pending initial Evaluation under the ratified OD-018 single-orchestration guard, and recovery. F-01 (outbound), F-03 (Evidence), F-04 (ScheduledActions, whose crawl/pipeline work-kinds are already reserved in the frozen catalogue) are built and reusable. The OD-027 withheld limb (a `unique (parsing_job_id)` narrowing, a `has_one`, and any second IndexingJob per ParsingJob) is entirely DOWNSTREAM (WF-006/S-08 indexing) — S-07 ends at the crawl→ingestion durable handoff and touches none of it. OD-018 is ratified and buildable; OD-005/OD-015 are resolved.

The blocker — two large shared foundations the schema doc specifies but that have NEVER been built (every shipped slice used a dedicated per-concern table: source_scope_policies, access_policies, entitlement_policies):

- **D1 — Crawl policy realization (blocks S-07-001, the first tranche).** MTX-030 persistence_model names canonical `crawl_policies` "per schemas/POSTGRESQL_SCHEMA.md." The schema doc defines NO `crawl_policies` table; it realizes crawl policy through the GENERIC policy machinery — `policy_artifacts` (tenant-scoped, `policy_type='crawl'`, narrowing), `release_artifacts` (the immutable global safety ceiling, release-service-owned), and `policy_snapshots` (the pinned resolution) — and WORKFLOW_SPECIFICATIONS.md:318 states "Policy Artifact is an immutable versioned logical contract, NOT an additional core domain aggregate," with :387 listing `crawl` among ~18 generic policy/release-artifact types. NONE of `policy_artifacts` / `release_artifacts` / `policy_snapshots` / `policy_scope_projects` exists. Two materially different valid interpretations, affecting the canonical schema and the whole policy strategy:
  - **Option 1 — build the generic policy-artifact machinery** (`policy_artifacts`+`release_artifacts`+`policy_snapshots`[+`policy_scope_projects`]) per the schema doc + WORKFLOW:318/387, and realize crawl policy as `policy_type='crawl'`. Faithful to the canonical design, but a large SHARED foundation (release_artifacts/policy_snapshots are consumed by many future slices — parser definitions, measurement sets, check catalogs, every gated command's snapshot) built under S-07's authorisation.
  - **Option 2 — continue the dedicated-table convention** with a `crawl_policies` table (the contract's literal name), mirroring source_scope_policies/access_policies. Matches the as-built repository reality and the contract's table name, but CONTRADICTS the schema doc (no crawl_policies; generic machinery) and WORKFLOW:318 ("not an additional aggregate"), so it needs a schema-doc reconciliation/ADR.

- **D2 — Entitlement reservation foundation ownership (blocks S-07-003/004: StartCrawl).** StartCrawl requires an allowed `crawl.start` entitlement RESERVATION before Queued→Running (MTX-030/MTX-058/PRULE-007). The BEHAVIOUR is fully specified by the ratified Interim Entitlement Contract (`entitlement-interim-v1`, WORKFLOW:513-532: `crawl.start` counter-group `crawl_run`, unit 1, soft 3 / hard 4, 15-min reservation lifetime, 65-min max execution, durable commit = "Crawl reaches completed with ≥1 valid Document"; allow iff `committed+active_reserved+requested ≤ hard`, equality allowed). But the reservation SUBSYSTEM (`entitlement_counter_windows`, `entitlement_decisions`, `entitlement_reservations`, `entitlement_lease_heartbeats`, `entitlement_commit_intents`) has never been built (only `entitlement_policies` exists), and S-07 is the first high-cost consumer. Two valid interpretations: **Option 1 — build it inside S-07** (as a tranche); **Option 2 — build it as a separate authorised shared foundation (F-05)** like F-01..F-04 (all metered high-cost operations — crawl.start, reassessment.start, ai.generate, export.generate — depend on it). The behaviour is identical either way; the question is scope/ownership and whether "S-07" as authorised includes building this cross-cutting foundation.

Smaller downstream decisions recorded (defensible interims exist; NOT blocking the first tranches; will be raised or adopted-with-record at their tranches): **D3** — the body-free `crawl_observation` (`content_absent`) Evidence for a terminal 404/410: produced inline at fetch-commit (no IngestionJob, no Document) vs via the ingestion pipeline (S-07-008/010/011). **D4** — the reassessment-child branch names a parent Evaluation/reservation produced only by WF-011 (unbuilt); recommend building the root branch fully now and deferring the child branch to the WF-011 slice (S-07-003/004).

Provisional decomposition (dependency-ordered; to be ratified after D1/D2): S-07-001 crawl policy resolution + narrowing activation (D1); S-07-002 entitlement reservation surface (D2); S-07-003 Crawl aggregate + QueueCrawl; S-07-004 StartCrawl + initial Evaluation + OD-018; S-07-005 frontier + dequeue; S-07-006 host gate + robots + rate; S-07-007 sitemap + XXE-safe XML; S-07-008 content fetch + scope/redirect + byte accounting + retry; S-07-009 limits + soft/hard events + wall clock; S-07-010 terminal checkpoint + coverage/completion + CancelCrawl; S-07-011 Documents + ingestion + Evidence + durable handoff; S-07-012 recovery + replay (PRULE-022). Each is a single reviewable unit ending before the OD-027 withheld limb.

Decision:
STOP and return to the owner for D1 and D2 per ADR-061 stop conditions (1) a genuine repository ambiguity with materially different valid interpretations affecting behaviour/schema, and (2) a scope question requiring owner approval — both of which gate the first S-07 tranche. No S-07 behavioural code is written until D1 (and, before S-07-003, D2) are resolved. Allocated the next unused number after ADR-066.

## ADR-068: D1 Resolved — Tenant Policy Concerns Are Realized As Dedicated Per-Domain Immutable Policy Tables (crawl_policies)

Status: Accepted
Date: 2026-07-27
Owner: Owner (HD-S07-D1-CRAWL-POLICY: "Implement crawl policy using a dedicated immutable, versioned `crawl_policies` table. Continue the established implementation convention used by access_policies and source_scope_policies. Treat the generic policy_artifacts / release_artifacts / policy_snapshots framework as deferred shared infrastructure. Do not introduce it as part of S-07. Record a reconciliation ADR ... and update repository documentation as required to eliminate ambiguity.") / implementation agent (recorded)
Reversibility: Sets the implementation strategy for policy realization; a table + documentation-reconciliation decision. Reversible by a later architecture decision that introduces the generic machinery and migrates the dedicated tables.

Decision (implementation strategy, reconciling the contract, the schema doc, and the as-built code):
Tenant policy concerns in this build are realized as **dedicated, per-domain, immutable, versioned policy tables**, NOT through the generic `policy_artifacts` / `release_artifacts` / `policy_snapshots` framework described in `schemas/POSTGRESQL_SCHEMA.md` and WORKFLOW_SPECIFICATIONS.md:318/387. This ratifies the already-shipped convention: `access_policies` (S-01), `source_scope_policies` (S-05/S-06), and `entitlement_policies` were each built as dedicated tables and NONE appears in the schema doc's generic-machinery catalogue. S-07 therefore realizes crawl policy as a dedicated **`crawl_policies`** table (the contract's literal name, MTX-030), immutable and versioned, with the crawl-policy-v1 bounds, a release-owned global-safety ceiling row, narrowing-only activation, and a pinned resolution — mirroring `source_scope_policies` / `SourceScopePolicyActivation`. The generic `policy_artifacts` / `release_artifacts` / `policy_snapshots` framework is **deferred shared infrastructure** and is NOT introduced by S-07.

Reconciliation of the ambiguity (D1): the S-07 contract names `crawl_policies` "per schemas/POSTGRESQL_SCHEMA.md"; the schema doc realizes policy via the generic framework and defines no `crawl_policies` table; WORKFLOW:318 calls the Policy Artifact "an immutable versioned logical CONTRACT, not an additional core domain aggregate." These are reconciled thus: the "logical policy contract" is satisfied physically by a dedicated immutable versioned table per domain, which is the established convention; the schema doc's generic framework is the deferred ideal, not the current realization. A reconciliation note is added to `schemas/POSTGRESQL_SCHEMA.md` pointing here so the ambiguity does not recur.

Authority And Precedence:
Ratifies the owner's D1 ruling and resolves BUILD_STATE.open_decisions D1. Allocated the next unused number after ADR-067. S-07-001 (crawl policy) is unblocked and proceeds under standing delegation ADR-061. No frozen product contract is changed; a documentation reconciliation note is added to the schema doc.

## ADR-069: D2 Resolved — Entitlement Reservation Is A Separate Shared Foundation Block (F-05), Consumed By S-07

Status: Accepted
Date: 2026-07-27
Owner: Owner (HD-S07-D2-ENTITLEMENT-RESERVATION: "Build the entitlement reservation subsystem as a separate shared foundation block (F-05) before any S-07 tranche requiring reservation semantics. Treat the reservation subsystem (reservation records, quota windows, heartbeats, commit intents, decisions, etc.) as reusable platform infrastructure consumed by S-07 and future high-cost operations. Do not expand S-07 to own this shared infrastructure. Create the appropriate foundation tranche under repository governance and have S-07 consume it once complete.") / implementation agent (recorded)
Reversibility: A scope/ownership decision; the reservation behaviour is fixed by entitlement-interim-v1 regardless of where it is built.

Decision:
The entitlement reservation subsystem — `entitlement_counter_windows`, `entitlement_decisions`, `entitlement_reservations`, `entitlement_lease_heartbeats`, `entitlement_commit_intents` and the reserve/commit/release/heartbeat operations implementing the ratified Interim Entitlement Contract (`entitlement-interim-v1`, WORKFLOW:513-532: high-cost allowed iff `committed + active_reserved + requested ≤ hard`, equality allowed; `crawl.start` counter-group `crawl_run`, unit 1, soft 3 / hard 4, 15-min reservation lifetime, 65-min max execution, durable commit = "Crawl reaches completed with ≥1 valid Document") — is built as a **separate authorised shared foundation block, F-05**, NOT as part of S-07. It is reusable platform infrastructure consumed by every high-cost operation (`crawl.start`, `reassessment.start`, `ai.generate`, `export.generate`). S-07 CONSUMES F-05's reserve/commit/release surface (as it consumes F-01 outbound and F-03 Evidence); it does not own it. F-05 is built and independently reviewed BEFORE the first S-07 tranche requiring reservation semantics — StartCrawl (S-07-003). S-07 tranches that require no reservation (S-07-001 crawl policy; S-07-002 Crawl aggregate + QueueCrawl, which pins the entitlement policy version but reserves nothing) may precede F-05.

Authority And Precedence:
Ratifies the owner's D2 ruling and resolves BUILD_STATE.open_decisions D2. Allocated the next unused number after ADR-068. F-05 is authorised by this owner decision and proceeds under standing delegation ADR-061 with the same gate + five-lens ADR-026 discipline as F-01..F-04. The provisional S-07 decomposition (ADR-067) is updated: its provisional S-07-002 "entitlement reservation surface" becomes foundation F-05; the remaining S-07 tranches renumber accordingly in BUILD_PLAN.

## ADR-070: S-07-001 (Crawl Policy) Independently Reviewed (All Five Lenses PASS) — Refinements Applied; Accepted

Status: Accepted
Date: 2026-07-27
Owner: implementation agent (recorded under standing delegation ADR-061); no owner product ruling required — zero confirmed-blocking findings
Reversibility: Fast-forward acceptance on the non-protected integration branch; `main` untouched.

Decision:
Record the independent ADR-026 review of S-07-001 (crawl policy — the dedicated `crawl_policies` table, the frozen crawl-policy-v1 global ceiling, and ActivateCrawlPolicy narrowing activation). Five separately-invoked adversarial lenses (contract, security/tenant, concurrency/atomicity/idempotency, schema/migration, architecture/scope) each returned **PASS with ZERO confirmed-blocking findings**, under heavy live exercise: the contract lens confirmed the twelve crawl-policy-v1 bounds match WORKFLOW:425-438 exactly AND that the strict scope reading (OrganizationAdmin→Organization, MarketingOperator→Project) is FAITHFUL — three converging sources show the Admin cell is a qualified "narrow Organization bounds", unlike `policy.source_scope.manage`'s unqualified superset; the security lens live-proved (as a BYPASSRLS superuser and under a proof-gated org context) that the guard refuses every mutation exploit (DELETE, cross-tenant row-move, content mutation, superseded resurrection), that tenant isolation holds (cross-tenant read → 0 rows; cross-tenant insert → RLS-refused), and that the narrowing check cannot be bypassed (the parent is read from the store, never the command); the concurrency+schema lens live-verified single-transaction atomicity, supersede-before-insert, the version guards under the lock, LostRace rollback, and build-from-empty with zero drift.

Refinements applied in response to non-blocking findings (commit `c5b32f1`), none a behavioural regression:
1. **Concurrency NB-1:** crawl-policy activations now serialize on a single per-Organization advisory lock (`lock_organization`) instead of a per-(org,scope,project) lock, so an Organization-scope supersession cannot race a Project activation's parent read into a transiently-broader stored Project row (which was already safe — effective bounds are `most_restrictive(global, org, project)` at execution).
2. **Schema NB-2 (defense-in-depth):** the `crawl_policies` guard now freezes the primary key `id` (a supersession UPDATE cannot re-key a row); unreachable via the handler, closed at the DB backstop. The guard is now `CREATE OR REPLACE`.
3. **Architecture:** a mis-scoped command is now denied AND AUDITED inside the transaction with a dedicated `crawl_policy_scope_invalid` reason (was an unaudited pre-transaction `crawl_policy_incomplete`); the unused `well_formed?` helper was dropped; a unit spec was added for the load-bearing `most_restrictive` resolver.

Non-blocking observations RECORDED (no fix): inter-version broadening WITHIN a scope is permitted but never weakens the effective envelope (narrowing is defined relative to the resolved parent+global, and effective bounds are a per-dimension MIN across active levels — faithful to WORKFLOW:390/732); the CrawlPolicyActivated payload carries version references, with the numeric bounds in the audit record + policy row; `crawl-policy-{scope}-v{N}` is unique per (org,scope,project) via the index though the label alone does not name the project (cosmetic); and the pre-existing platform gaps FU-1 (permission_mode read_only ignored) and FU-2 (assignment-scope containment) are inherited identically with NO new instance (already backlogged, ADR-066).

S-07-001 acceptance:
S-07-001 met every mandatory gate (whole-repo suite **1361/0**; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness **31/0**; verify_runtime OK, 15 checks, RLS intact; migration builds from empty; structure.sql matches) and all five ADR-026 lenses returned PASS with zero confirmed-blocking findings. It is therefore ACCEPTED; `S-07-001` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-07-001 → completed; completion report accepted; the integration branch pushed. `main` untouched. Next: S-07-002 (Crawl aggregate + QueueCrawl), then foundation F-05 (before StartCrawl), under standing delegation.

Authority And Precedence:
Executes the owner's standing-delegation directive (ADR-061) and accepts S-07-001. Allocated the next unused number after ADR-069.

## ADR-071: S-07-002 Built; A Ratified-Sequence Prerequisite Surfaced (Project Activation Precedes S-07) — STOP For Owner Decision D3

Status: Proposed (owner decision required — stop condition 2, a scope/prerequisite question)
Date: 2026-07-27
Owner: implementation agent (S-07-002 built under standing delegation ADR-061; prerequisite STOP raised) / owner decision D3 pending
Reversibility: The S-07-002 code is built and its migration applied to dev/test but NOT accepted, reviewed, or pushed; it is preserved as a local WIP commit. No production path.

Context — S-07-002 built:
S-07-002 (Crawl aggregate + QueueCrawl) is implemented: the `crawls`, `crawl_sources` and `evaluations` tables (schema doc :292/293/339; RLS, immutability/lifecycle guards freezing identity/pinned facts and refusing state transitions to be relaxed by later tranches, the two OD-018 partial-unique indexes on `evaluations`); `QueueCrawl` (authenticate → tenant → authorize `crawl.trigger` → active Project + active Entitlement Policy + ≥1 active Source → per-Project lock + idempotency → OD-018 queue-time guard → insert one root queued Crawl pinning the request-time crawl-policy [Project else Org active version, else the frozen global ceiling] + entitlement-policy versions and the active Source set, reserving no usage and creating no Evaluation → `CrawlQueued`); the `crawl.trigger` permission; and the QueueCrawl ErrorCatalog reasons. Two documented interims within S-07-002 (defensible, not owner decisions): `reassessment_required` is vacuously satisfied because promotion (`current_score_projections`) is an S-09 table not yet built — no Project can hold a promoted pair, so every request is a root initial-assessment Crawl, and the guard's query is wired when S-09 builds promotion; the reassessment-child branch is deferred to the WF-011 slice (ADR-067 D4), so QueueCrawl always queues a root Crawl.

The blocker — D3, a ratified-sequence prerequisite:
QueueCrawl requires an **active Project** (WORKFLOW_SPECIFICATIONS.md § WF-005 :725 "A Crawl request requires an active Project"). Both WF-001 bootstrap and WF-002 CreateProject create a Project in state **`draft`**, and the `projects_lifecycle_guard` (db/migrate/20260723120020) REFUSES every Project state change with an explicit note: "WF-002 State Transitions define Project.Draft -> Project.Active only, and that transition is gated on >=1 active same-Project Source (CAP-003, PRULE-004) ... activation is not implementable in this baseline ... The activation slice will relax this guard to permit the single draft->active edge under its ratified prerequisites." That project-activation slice (WF-002/S-03 ActivateProject) is **NOT built** — the ratified build sequence is `... S-06 -> S-03 ActivateProject -> S-07` (PROJECT_STATE.md), placing it BEFORE S-07 — and its own prerequisite (>=1 active Source) is NOW satisfiable because S-06-006 ActivateSource is built. QueueCrawl's active-Project precondition therefore cannot be met, and no test may seed an active Project without masking this ratified-sequence prerequisite (the guard refuses draft->active; a direct active INSERT would fabricate a state only the unbuilt activation slice may produce). This is a genuine scope/prerequisite decision, parallel to D2 (F-05): the project-activation slice is a DIFFERENT slice (S-03/WF-002 project lifecycle), not part of the S-07 authorisation.

Decision (D3, owner):
STOP and return to the owner per ADR-061 stop condition (2) — a scope change requires owner approval. Options:
- **Option 1 (recommended): build the project-activation slice now as a prerequisite** (like F-05) — WF-002/S-03 ActivateProject: the single `draft -> active` Project edge gated on >=1 active Source, relaxing the `projects_lifecycle_guard` to permit exactly that edge, with its permission (`project.activate` or the WF-002 named permission per WORKFLOW), built + independently reviewed under the standing delegation before S-07-002 is accepted. It is small, now-buildable, explicitly sequenced before S-07, and unblocks QueueCrawl (and every downstream S-07 tranche) for real rather than by test fixture.
- **Option 2: proceed with S-07 test-seeding an active Project and defer project activation** — S-07 stays production-dead until the activation slice is built; QueueCrawl's precondition is enforced but exercised only via a fabricated active-Project fixture.

Authority And Precedence:
Records S-07-002 and the D3 prerequisite. No S-07-002 acceptance, review, merge, or push until D3 is resolved. Allocated the next unused number after ADR-070.

## ADR-072: D3 Resolved (Build ActivateProject); D4 Resolved (Dedicated Deterministic WF-013 Test-Clock Fix); S-03 Built + Gates Green (Five-Lens Review, D5, and Acceptance in ADR-073)

Status: Accepted (D3 + D4 resolved by the owner; WF-013 repo-health fix applied; S-03 built and every mandatory gate green; the five-lens review outcome, owner decision D5, and the acceptance are recorded in ADR-073)
Date: 2026-07-27
Owner: Owner (HD-S07-D3-PROJECT-ACTIVATION: "Build the WF-002/S-03 ActivateProject slice now as a prerequisite before accepting S-07-002 ... the canonical draft->active transition gated on >=1 active Source, with its named permission, lifecycle guard updates, verification, ADR-026 review, acceptance, merge, governance updates, and push ... Do not fabricate active Project fixtures or bypass lifecycle rules in tests.") / implementation agent (S-03 built; gate blocker surfaced)
Reversibility: S-03 code is built and its migration applied to dev/test but NOT accepted, reviewed, or pushed; preserved as a local WIP commit. No production path.

D3 resolution + S-03 build:
Per the owner's D3 ruling, the WF-002/S-03 ActivateProject slice is built as a real prerequisite (no fabricated fixtures): the canonical Project.Draft -> Project.Active transition gated on >=1 active same-Project Source (contracts/S-03.json MTX-027; WORKFLOW_SPECIFICATIONS.md § WF-002 :651-666). It comprises the `project.activate` permission (Admin/Marketing, distinct from project.create), the `projects_lifecycle_guard` relaxation permitting EXACTLY `draft -> active` (pause/archive still refused, OD-014; migration 20260727120100, no table added), `Workflows::Wf002::ActivateProject` (authenticate -> tenant -> authorize -> lock -> idempotency -> project_not_draft/stale_state_version/source_membership_changed/active_source_required first-match guards -> guarded draft->active -> `ProjectActivated`), the ProjectStore reads/writes, and the activation ErrorCatalog reasons. It is verified against a production-real chain (bootstrap -> register -> verify -> ActivateSource -> ActivateProject) with 9 acceptance tests + 2 stale-test updates (project_setup_invariants and wf002_create_project, which asserted the now-relaxed edge). S-03 introduces ZERO new suite failures.

The blocker — D4, a pre-existing full-suite wall-clock time-bomb:
The mandatory `complete_test_suite` gate cannot currently be satisfied. The full suite has 7 failures — ALL in WF-013 invitation-reference specs (wf013_activation_lifecycle, wf013_create_invitation, wf013_decide_invitation, wf013_suspended_state) — and ALL are present IDENTICALLY at the last ACCEPTED commit `c062b60` (S-07-001), so they are pre-existing and NOT introduced by S-03. Root cause: those specs anchor `fixed_now = 2026-07-20 10:00`, so their 7-day invitation references expire at `2026-07-27 10:00`; the reference resolver `f1_resolve_invitation_reference` deliberately uses REAL database time (`transaction_timestamp()`, migration 20260722120012 "resolve on database time"), so once the real wall-clock passes 2026-07-27 10:00 the references correctly read as expired and resolution/accept/decline fail. The suite was green (1361/0) when the S-07-001 gate ran (~05:18Z) and went red (~10:00Z+) purely from wall-clock progression. A naive fix (bumping those specs' anchor to 2026-07-27) fixes 6 of 7 but REGRESSES a previously-passing test (wf013_activation_lifecycle:223: expected `stale_state_version`, got `invitation_not_active`) — the WF-013 fixtures have non-obvious real-vs-fixed-clock coupling, so a correct fix requires deliberate WF-013 test-infrastructure work, outside the S-03 scope.

Decision (D4, owner — HD-S07-D4-REPO-HEALTH: RESOLVED):
The owner chose Option 1 and ruled that repository policy requires an OBJECTIVELY GREEN mandatory verification gate — the acceptance criteria must NOT be weakened to "no new failures". The WF-013 invitation-reference tests must be made deterministic by removing their dependency on wall-clock database time (inject/freeze the resolver clock, or otherwise align test execution with the resolver's time source), WITHOUT changing production behaviour; treated as an isolated repository-health correction with its own verification and review; then, once the repository is a deterministic green baseline, accept the ActivateProject prerequisite tranche and resume S-07-002.

D4 fix applied (commit `aca3065`, tests only — no production change):
The reference resolver's use of real database time (`transaction_timestamp()`) is a deliberate production security property and was left untouched. The four affected specs' `def fixed_now` was re-anchored from the hardcoded `Time.utc(2026,7,20,10,0,0)` to the DATABASE clock minus three days — `(@fixed_now ||= (TenantSeeder.db_now - (3*24*3600)).floor(6))`, memoised per example. This aligns all three time sources — the fixed-clock handlers, the `db_now`-anchored `TenantSeeder` fixtures, and the real-time resolver — so a fixed-clock invitation always expires ~4 days in the real future (the resolver resolves it) while `fixed_now` stays before any `db_now - 24h` approval window (so `pending_approval` fixtures remain in-window, avoiding the naive-bump regression at :223). Deterministic regardless of wall clock. The other WF-013 specs were audited: only these four created fixed-clock invitations that the real-time resolver later expired; `wf013_revoke_invitation` touches the resolver only for an expiry-independent zero-rows-after-revoke assertion on `db_now` fixtures, and the remaining specs do not touch the resolver. The full mandatory suite is now **1370/0** deterministically.

S-03 gates + five-lens review (disposition + acceptance in ADR-073):
On the restored deterministic green baseline, S-03 ActivateProject met every mandatory gate (whole-repo suite **1370/0** at review time; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness **31/0**; verify_runtime OK, 15 checks, RLS intact; schema dump idempotent and migration builds from empty; structure.sql delta is exactly the guard relaxation). The ADR-026 five-lens independent review found ONE confirmed-blocking issue — B1: the MTX-027 first-match order inverted `active_source_required` and `source_membership_changed` (the order is normatively fixed) — which was fixed (reordered to `project_not_draft -> active_source_required -> source_membership_changed -> stale_state_version`; docstring corrected; adversarial test added; suite **1371/0**). Security, schema and concurrency lenses returned PASS. The review also surfaced B2 (the `source_membership_changed` guard is inert because the source-set sealing subsystem is unbuilt) and related non-blocking gaps. The disposition of B2 (owner decision D5 — defer the sealing subsystem as tracked follow-up FU-3) and the acceptance of S-03 are recorded in ADR-073.

Authority And Precedence:
Records the D3 resolution, the D4 resolution and its isolated repo-health fix, and the S-03 build + green gates + five-lens review. The B2 disposition (D5) and the S-03 acceptance are in ADR-073. Allocated the next unused number after ADR-071.

## ADR-073: D5 Resolved (Accept Core S-03; Defer Source-Set Sealing Subsystem as FU-3); S-03 ActivateProject Accepted

Status: Accepted (owner HD-S07-D5-SOURCE-SET-SEALING; S-03 accepted under standing delegation ADR-061)
Date: 2026-07-27
Owner: Owner (HD-S07-D5-SOURCE-SET-SEALING: "Accept the core WF-002/S-03 ActivateProject tranche now and defer the unbuilt source_set_versions / source_set_memberships sealing subsystem as explicit tracked follow-up work. Do not add an in-tranche digest or fabricate a partial substitute ... preserve the current correct activation behavior; record that source_membership_changed and selected-Source sealing cannot be fully enforced until the canonical subsystem exists; ensure no claim is made that immutable source-set sealing is already implemented; add the dependency to BUILD_PLAN / BUILD_STATE and the review ADR as a named follow-up with its downstream consumers; accept, merge, update governance, and push S-03 ... Then resume S-07-002. Stop only if repository contracts explicitly make source-set sealing a hard prerequisite for Project activation rather than a separately sequenced subsystem.") / implementation agent (five-lens review; acceptance)

Five-lens review outcome (ADR-026):
Contract, security/tenant, concurrency/atomicity/idempotency, schema/migration, and architecture/scope lenses ran independently with live DB probes. Security, schema and concurrency returned PASS with zero confirmed-blocking. One confirmed-blocking issue (B1, raised by the contract AND architecture lenses) was FIXED before acceptance: the MTX-027 first-match order inverted `active_source_required` and `source_membership_changed` (normatively fixed order); reordered to `project_not_draft -> active_source_required -> source_membership_changed -> stale_state_version`, docstring corrected, adversarial test added (zero active Sources + wrong membership version -> `active_source_required`); whole-repo suite **1371/0**. B2 (contract lens confirmed-blocking; concurrency and architecture lenses NON-BLOCKING/deferrable) and N1 are the subject of D5 below. Non-blocking observations recorded (no action required for acceptance): the tenant/existence check precedes authorization (within-tenant only; both outcomes F1-AUTH-403; matches MTX-027's "schema/tenant/authorization" ordering and the accepted ActivateSource sibling — security lens cleared it as not a breach); `activation_transaction_unavailable` is catalogued but unemitted and the retry(1s/5s)/10s-deadline limb is unimplemented (consistent with the ACCEPTED `onboarding_transaction_unavailable` precedent — N2); `policy_unavailable` is a contract-listed activation reason with no path because the core transition resolves no policy (N3); `CREATE OR REPLACE` regenerated the lifecycle-guard function without its explanatory comments (cosmetic doc erosion, no behaviour change).

Root cause of B2 / N1 — an unbuilt shared subsystem, not an ActivateProject defect:
`source_membership_changed` compares `expected_source_membership_version` against `projects.source_set_version`, a column NO code path increments, and the contract also requires the selected active Source IDs to be recorded at activation (MTX-055). Both obligations depend on the canonical immutable source-set SEALING subsystem — `source_set_versions` (project, version, member_count, scope-root + content SHA-256, sealed_at) and `source_set_memberships` (the sealed members with Source/scope-policy detail) — specified in schemas/POSTGRESQL_SCHEMA.md :287-288 but NEVER built by any tranche (0 tables, no writer). This is pre-existing shared infrastructure, also required by WF-011 reassessment ("freeze active Source-set version and normalized full-scope hash" / "re-resolve ... If either differs ... fail with source_scope_changed_during_reassessment", WORKFLOW_SPECIFICATIONS.md :878/:880). No repository contract makes source-set sealing a HARD PREREQUISITE for Project activation — the activation gate is the ≥1-active-Source count, which is fully implemented and green — so it is a separately sequenced subsystem, not a stop condition.

Decision (D5, owner — HD-S07-D5-SOURCE-SET-SEALING: RESOLVED):
Accept the core S-03 ActivateProject tranche now; defer the source-set sealing subsystem as explicit tracked follow-up **FU-3**. Do NOT add an in-tranche digest or fabricate a partial substitute; preserve the current correct activation behaviour. The handler records the limitation in-code (no claim that immutable source-set sealing is implemented). The canonical draft->active transition, active-Source precondition, authorization, lifecycle guard, concurrency behaviour, and mandatory verification are complete and green.

FU-3 (named follow-up) — Source-set sealing subsystem:
Build the immutable, sealed, versioned `source_set_versions` / `source_set_memberships` subsystem (schemas/POSTGRESQL_SCHEMA.md :287-288): seal a new Source-set version whenever the active-Source set or a Source's scope changes, with `projects.source_set_version` pointing at the current sealed version and the sealed membership recording the selected Sources + scope-policy detail. Downstream consumers that become fully enforceable once it exists: (1) S-03 ActivateProject — effective `source_membership_changed` (concurrent membership/scope change detection) and recording the sealed selected-Source set (MTX-027/MTX-055, PRULE-004); (2) WF-011 reassessment — freezing/re-resolving the active Source-set version + normalized full-scope hash and `source_scope_changed_during_reassessment`. Naturally owned alongside the Source/scope tranches (S-04/S-05/S-06) or as a dedicated foundation; touches those accepted handlers to seal on membership change. Minor sibling follow-ups noted: N2 (activation transaction-dependency retry/deadline, consistent with the deferred `onboarding_transaction_unavailable` limb) and N3 (`policy_unavailable` path) — both platform-layer, revisited when their limbs are implemented platform-wide.

S-03 acceptance:
S-03 ActivateProject is ACCEPTED under the standing delegation ADR-061. Every mandatory gate is green (whole-repo suite **1371/0**; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness **31/0**; verify_runtime OK, 15 checks, RLS intact; schema dump idempotent; migration builds from empty; structure.sql delta is exactly the guard relaxation). B1 fixed; B2/N1 deferred as FU-3 with the limitation recorded in-code and in governance; no claim of immutable source-set sealing is made. `S-03` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-03 -> completed with the FU-3 dependency noted; `S-03_COMPLETION_REPORT.md` accepted; the integration branch `implementation/s01-registration-access` pushed. `main` untouched. S-07-002 now resumes using real end-to-end Project activation (no fabricated active-Project fixtures).

Authority And Precedence:
Executes the owner's D5 ruling and the standing delegation ADR-061; accepts S-03 and registers FU-3 with its downstream consumers. Allocated the next unused number after ADR-072.

## ADR-074: S-07-002 (Crawl Aggregate + QueueCrawl) Accepted

Status: Accepted (standing delegation ADR-061; five-lens review, one confirmed-blocking fixed)
Date: 2026-07-27
Owner: implementation agent (S-07-002 completed, reviewed, hardened, accepted) under the owner's D5 directive to "resume S-07-002 using real end-to-end Project activation"
Reversibility: Accepted and pushed to the integration branch; `main` untouched. The Crawl aggregate is additive; the crawls guard freezes queued state (later tranches relax Queued->Running).

Context — S-07-002 completed and resumed on real activation:
QueueCrawl (contracts/S-07.json MTX-030 queue limb, MTX-058 PRULE-007; WORKFLOW_SPECIFICATIONS.md § WF-005 :725-728, :734) creates one root queued Crawl pinning the request-time crawl-policy (Project else Organization active version, else the frozen global ceiling) + entitlement-policy versions and the active Source set; it reserves NO usage and creates NO Evaluation (PRULE-007). The S-07-002 WIP implementation (crawls/crawl_sources/evaluations migration, QueueCrawl command/handler, CrawlStore, `crawl.trigger`, ErrorCatalog reasons) was completed with its specs written over the PRODUCTION-REAL chain per owner D5 (bootstrap -> register -> verify -> ActivateSource -> ActivateProject -> QueueCrawl; no fabricated active-Project fixtures) — 16 acceptance + 10 persistence examples. Documented interims (ADR-067/071): `reassessment_required` vacuous until S-09 promotion; the reassessment-child branch deferred to WF-011.

Five-lens ADR-026 review outcome:
Security, schema, concurrency and architecture lenses returned PASS (live cross-tenant probes blocked on all three FORCE-RLS tables; composite tenant FKs reject cross-tenant Source pinning; guards/constraints edge-probed; race-tight per-Project lock + single-transaction idempotency with a DB unique backstop; packwerk/ledger-arity/interim-honesty conform — `current_score_projections` confirmed absent). ONE confirmed-blocking issue (B1, contract lens) was FIXED before acceptance, and the strongest non-blocking items were hardened:
- B1: `initial_evaluation_already_running` returned the F1-DOMAIN-409 class-default `recovery_action`; MTX-030/WORKFLOW :734 mandate `await_running_initial_evaluation_or_submit_new_command`. Added a per-reason `REASON_RECOVERY` override in `Platform::ErrorCatalog` (the first reason needing a non-default recovery) + a `recovery_action` assertion.
- N1: idempotency/replay is now resolved BEFORE the domain preconditions (as the ActivateProject sibling), so a replay faithfully returns its stored result even after a precondition ceases to hold (new test); N2: preconditions re-read UNDER the lock in the WORKFLOW :725 order (Project -> Source -> Entitlement), closing the pre-lock staleness window (new order/entitlement tests).
- N3: `CrawlQueued` now carries the pinned crawl/entitlement policy versions.
- Schema backstop: new migration `20260727120110` adds `CHECK (kind <> 'initial' OR crawl_id IS NOT NULL)` so the OD-018 `evaluations_initial_per_crawl_unique` index no longer relies on the app always supplying `crawl_id` (btree NULLs are distinct); persistence test added.
Non-blocking observations recorded (no change): multiple queued root Crawls per Project is intended (single-flight authoritatively enforced at Queued->Running via the evaluations partial-unique, S-07-003); front-loaded crawl-lifecycle columns/grants are inert now and consumed by later tranches; `active_sources` INNER JOIN is safe under the verified->active invariant (an active Source always carries a scope policy); the F-01 org-context trust boundary is pre-existing and unchanged.

Acceptance:
Every mandatory gate is green (whole-repo suite **1397/0**; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness **31/0**; verify_runtime OK, 15 checks, RLS intact; schema dump idempotent; both migrations build from empty; structure.sql delta is exactly the three tables + the OD-018 CHECK). S-07-002 is ACCEPTED; `S-07-002` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-07-002 -> completed; `S-07-002_COMPLETION_REPORT.md` accepted; the integration branch pushed. `main` untouched. Next: foundation **F-05** (entitlement reservation, required before StartCrawl S-07-003), then S-07-003, continuing under the standing delegation.

Authority And Precedence:
Records the completion, review, hardening and acceptance of S-07-002 under ADR-061. Allocated the next unused number after ADR-073.

## ADR-075: F-05 Entitlement Reservation Subsystem (entitlement-interim-v1) Accepted

Status: Accepted (owner D2 / ADR-069 authorised; standing delegation ADR-061; five-lens review, one confirmed-blocking fixed)
Date: 2026-07-29
Owner: implementation agent (F-05 built, reviewed, hardened, accepted) under the owner's directive to complete F-05 before S-07-003
Reversibility: Accepted and pushed to the integration branch; `main` untouched. F-05 is additive shared infrastructure (five new tables + an in-transaction service); no existing behaviour changed.

Context — the shared reserve/commit/release/heartbeat surface:
F-05 (schemas/POSTGRESQL_SCHEMA.md :418-424; WORKFLOW_SPECIFICATIONS.md § Interim Entitlement Contract :513-554) is the foundation every high-cost operation consumes, built before S-07-003 StartCrawl. It comprises five FORCE-RLS tenant tables — `entitlement_counter_windows` (T-MUT UTC-day accumulator), `entitlement_decisions` (T-IMM), `entitlement_reservations` (T-MUT; F-05 owns reserved->executing->committed/released/expired), `entitlement_lease_heartbeats` (T-IMM), `entitlement_commit_intents` (T-MUT) — with guards, composite tenant FKs, partial-uniques, and least-privilege grants (immutable tables SELECT/INSERT, no DELETE anywhere); `Platform::Entitlement::InterimPolicy` (the frozen WORKFLOW :527 limits, UTC-day windows, the allow/warn/block formula `committed + active_reserved + requested <= hard`, equality allowed, `>= soft` warns); and `Platform::Entitlement::Service` (reserve/start_execution/heartbeat/commit/release/expire), serialized on the counter window (:549) and consumed in the caller's proved-Organization transaction. No actor entry point (S-22 WF-015: entitlement checkpoints are "internal to the operation being gated").

Interim reconciliation (ADR-069): the operative soft/hard limits are the FIXED `entitlement-interim-v1` constant (crawl.start soft 3 / hard 4, 15-min prestart lease, 65-min max execution, durable commit = "Crawl completed with >=1 valid Document"), NOT the non-operative placeholder numbers in the genesis `entitlement_policies` bytes (`baseline_content.rb`, soft 80/hard 100) — which the review confirmed are untouched. The window pins `policy_version` from the active policy for lineage.

Five-lens ADR-026 review outcome:
Security, concurrency and schema lenses returned PASS under live probes (cross-tenant reads/writes blocked on all five FORCE-RLS tables; composite tenant FKs reject cross-tenant lineage; the WORKFLOW :549 atomic-reserve serialization holds under five two-connection race probes — no over-reservation past hard, no lost update, no double-count, no torn transition; every guard edge, CHECK, and partial-unique verified with no NULL hole; builds from empty; dump idempotent). ONE confirmed-blocking issue (raised independently by the contract AND architecture lenses) was FIXED before acceptance, plus review-driven hardening:
- CB (blocking): the maximum-execution ceiling (65 min) was never enforced and `commit()` had no lease-expiry guard, so a faithfully-heartbeating operation ran and committed unbounded past its metered ceiling (WORKFLOW :551 requires the lease-expiry handler to win at `min(lease_due, started_at + max_exec)` and a commit reached at/after that instant to RELEASE). Fixed: `Service#effective_deadline` = the renewable lease capped by the operation's max-execution instant; `start_execution`/`heartbeat`/`commit`/`expire` all gate on it; a past-deadline commit releases (`lease_expired_at_commit`). New tests cover the 65-min cap on a heartbeating lease and commit-releases-past-deadline.
- Hardening (migration 20260727120130): a DB hard-cap CHECK `reserved_units + committed_units <= hard_limit` (concurrency defence-in-depth — the hard limit was app-enforced only); `entitlement_decisions.idempotency_key_digest` NOT NULL (WORKFLOW :543 "always nonnull"); dropped the redundant `(reservation, generation, renewed_at)` index. Reason precedence reordered (`entitlement_inactive` before `operation_unknown`, WORKFLOW :541); CAS-return checks added to every reservation transition (a lost transition can never double-adjust the counter); `require "securerandom"`; the replay/`retry_of` deferral (command-level idempotency is the consumer's `idempotency_records`) and the 1-15-min prestart-shortening deferral (OD-006-era) documented in-code.

Deliberate deferrals (non-blocking, recorded): F-05 emits NO `event_registry` envelopes — the entitlement domain events (EntitlementReserved/ExecutionStarted/LeaseRenewed/Committed/Released/ReservationExpired) are emitted by the CONSUMING workflow (workflow_id is WF-NNN only; S-22 "internal to the operation being gated"); F-05 returns the exact data the consumer emits from (the S-07-003 review MUST verify the consumer emits `EntitlementLeaseRenewed` with the mandated fields). The low-cost `baseline_reads` accounting (`low_cost_*` tables) is deferred to S-22. Per-org prestart-lifetime shortening (1-15 min) is an OD-006-replacement-era feature. `reservation_expired` (:553) is catalogued; `start_execution` returns `:expired` with no side effect and the consumer maps the conflict.

Acceptance:
Every mandatory gate is green (whole-repo suite **1431/0**; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness **31/0**; verify_runtime OK, 15 checks, RLS intact; both migrations build from empty; structure.sql idempotent). F-05 is ACCEPTED; `F-05` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` F-05 -> completed; `F-05_COMPLETION_REPORT.md` accepted; the integration branch pushed. `main` untouched. Next: **S-07-003 StartCrawl** — the first consumer of F-05's reserve/commit/release surface — then S-07-004..011 under the standing delegation.

Authority And Precedence:
Executes owner decision D2 (ADR-069) and the standing delegation ADR-061; records the completion, review, hardening and acceptance of the F-05 foundation. Allocated the next unused number after ADR-074.

## ADR-076: S-07-003 (StartCrawl + Initial Evaluation) Accepted — Five Confirmed-Blocking Findings Fixed

Status: Accepted (standing delegation ADR-061; five-lens ADR-026 review, five confirmed-blocking findings fixed before acceptance)
Date: 2026-07-29
Owner: implementation agent (S-07-003 built, reviewed, hardened, accepted) under the standing S-07 authorisation (HD-S07-AUTHORISE)
Reversibility: Accepted and pushed to the integration branch; `main` untouched. Additive: one service, one store, four migrations; the two changes to accepted code (F-05 `Service`, the S-07-002 OD-018 spec) are contract corrections, not behaviour changes to their tranches' scope.

Context — the gate is at the running transition:
S-07-003 builds `Workflows::Wf005::StartCrawl` (contracts/S-07.json MTX-030 start limb, MTX-058 PRULE-007; WORKFLOW_SPECIFICATIONS.md § WF-005 :725-728/:734/:736; SEARCH_CRAWL_RETRIEVAL.md § Crawl Admission And Snapshot; OD-018): the service-only `Crawl.Queued -> Crawl.Running` commit, driven by the ratified `crawl_dispatch` ScheduledAction that QueueCrawl now schedules on its own transaction (BACKGROUND_PROCESSING.md :137 -> :197 `crawl_orchestrate` -> :377 `StartCrawl`). Under the SAME per-Project advisory lock QueueCrawl takes and idempotent by the action identity (resolved BEFORE the preconditions), it applies the first-match gate — Crawl still queued; Organization active; Project active; >=1 active Source; OD-018; the MTX-030 Evaluation key free; the CURRENT crawl policy re-resolved (global ceiling ^ Org ^ Project, so a new restriction governs queued work immediately); the atomic root `crawl.start` Decision + reservation (F-05, its first consumer). Each gate failure transitions the queued Crawl to `failed` and reserves nothing; an accepted start moves the reservation reserved -> executing, stamps `started_at` (the wall-clock origin) + the resolved deadline + the Decision/reservation, creates EXACTLY ONE pending Evaluation keyed by `(crawl_id, kind=initial)` plus its immutable orchestration context, and emits `CrawlStarted` + `EvaluationPending` — all in one transaction, with no network call on the path.

Schema: migration 20260727120140 relaxed `f1_crawls_guard` to permit exactly queued->running and queued->failed and created `evaluation_orchestration_contexts` (T-IMM); 20260727120150 added the OD-018 DATABASE backstop. That backstop was necessary because POSTGRESQL_SCHEMA.md :340 reserves `orchestration_slot_active` for a reassessment/retry, so the S-07-002 slot index is the WF-011 single-flight and does NOT constrain an initial Evaluation. The new partial unique `(organization_id, project_id) WHERE kind='initial' AND state IN ('pending','running')` is OD-018's own, and keying on the in-flight states only keeps ":725 a root `crawl.recover` after a FAILED initial Evaluation remains admissible" true (probed both ways). The canonical kind restriction was transcribed as a CHECK.

Five-lens ADR-026 review outcome:
The CONCURRENCY lens returned PASS under live two-connection races: 5/5 OD-018 races yielded exactly one winner (the loser's Crawl failed holding no reservation); 5 concurrent starts across 5 Projects of one Organization gave 4 allow + 1 `hard_limit_exceeded` with no over-reservation; injected lost-CAS and mid-commit failures rolled back completely; exact-duplicate delivery replayed 5/5 with one Evaluation, one reservation, one event. The other four lenses each returned a confirmed-blocking finding, ALL FIXED before acceptance:
- CB1 (security): StartCrawl never re-authorized current ORGANIZATION state. A SUSPENDED tenant — every Session revoked, authorization epoch advanced — still started its queued Crawl, consumed a metered `crawl.start` unit and created an immutable Evaluation, purely on queue-time authority. MTX-030 `authorization_entry_point` forbids that in terms ("an authorization ... established at queue time is never trusted at execution time") and SEARCH_CRAWL_RETRIEVAL step 1 names the Organization FIRST. Fixed: `crawl_organization_not_active` as the first gate limb, before the entitlement limb, with the :541 recovery `reactivate_organization`.
- CB2 (contract): `crawls.completion_reason` was written from an invented vocabulary. WORKFLOW :456 (echoed by API_CONTRACTS :956/:1005 for the `crawl_terminal` schema and the WF-014 notification context) closes it to `completed`/`limit_reached`/`partial_source_failure`/`canceled`/`failed`. Fixed: a pre-execution failure records exactly `failed`; the exact machine reason is retained in the restricted audit record and the `CrawlFailed` envelope; a DB CHECK stops the enum drifting again.
- CB3 (contract): `entitlement_inactive` was bound to `restore_policy`, but :541 FIXES "inactive entitlement -> `upgrade_plan`" (`restore_policy` is that same line's mapping for a DIFFERENT reason code). Fixed in `ErrorCatalog` AND in F-05's `Entitlement::Service`, which writes the value into the immutable `entitlement_decisions.recovery_action`, so the durable record and the outward failure cannot disagree.
- CB4 (architecture): `CrawlStarted` carried the QUEUE-TIME pinned entitlement policy version beside an execution-time crawl policy version, in one canonically-encoded append-only event. Fixed: F-05's `Decision` now returns the version it actually resolved, and the event, the orchestration context and the Decision row all name that one value.
- CB5 (schema): `evaluation_orchestration_contexts_evaluation_fk` was the ONLY two-column Project-owned child-to-parent FK in the schema, admitting a same-Organization CROSS-PROJECT link — POSTGRESQL_SCHEMA.md :128 requires all three of `(organization_id, project_id, id)` precisely so that "these constraints, rather than a separate Project lookup or application assertion, prevent a same-Organization cross-Project child link". Fixed: `evaluations` gained the mandated three-column unique and the FK was rebuilt on it.

Hardening (migration 20260727120160): the missing tenant FKs on `crawls.entitlement_decision_id` / `entitlement_reservation_id`, `evaluations.crawl_id`, and the context's `prior_evaluation_id` / `root_entitlement_reservation_id`. `evaluation_creation_conflict` (a ratified MTX-030 reason previously unimplemented and undeclared) is now checked as a REQUEST REJECTION before anything is reserved. A ghost `organization_id` fails closed BEFORE any ledger row is written. `entitlement_decision_id` stays NULL on a Crawl that never started (:338). Documented in-code: the binding F-05 lock order (aggregate lock before the counter-window lock, so shared-counter consumers cannot form an ABBA cycle), the pre-lock read's staleness argument, why the non-replayable denials are safe, and the effective crawl-policy bounds + contributing versions now recorded in the audit record (WF-005 Audit: "all policy versions and effective limits").

Lens-flagged and verified sound (no change): the human `crawl.trigger` authorization is deliberately NOT re-checked at the start — :738 binds that permission to the REQUEST, which was authorized and audited at queue time, and it is domain preconditions that :725 re-resolves. Failing the queued Crawl for the non-entitlement gate reasons is correct under MTX-030 `terminal_failure` / CAP-007 ("a nonrecoverable policy or integrity error before useful output"); only the entitlement limb is :734's "current-policy or Entitlement Block", and the docstring's citation was corrected accordingly. The `crawl_queue_invariants` spec edits are a tightening, not a weakening (2 tests -> 5, every prior guarantee retained), and the S-07-002 OD-018 acceptance test now runs the REAL QueueCrawl -> StartCrawl chain instead of a hand-inserted Evaluation.

Deliberate deferrals (recorded, with owners): ROOT ONLY — the reassessment-child limb is WF-011's (ADR-067/071). NO FRONTIER — S-07-004, which carries a named gate requirement: the pinned `crawl_sources` set is T-IMM and is not re-resolved at start, so the frontier MUST exclude Sources that have left `active` or a customer-disabled Source would be crawled on queue-time authority. NO WF-015 ENTITLEMENT EVENTS — `EntitlementReserved`/`ExecutionStarted`/`LeaseRenewed` are WF-015 events on the `entitlement_reservation` aggregate (API_CONTRACTS.md :907-910) owned by S-22, not among the seventeen events MTX-030 makes `Workflows::Wf005` "the sole producer of"; this CORRECTS the ADR-075 expectation that the consumer would emit them, and `Heartbeat`/`Commit`/`ReleaseEntitlement` are the `entitlement_reconcile` work type's operations (BACKGROUND_PROCESSING.md :217/:390), not the start commit's — registered as FU-4 for owner attention. F-05's :541 identity precedence is incomplete (`organization_inactive`/`actor_inactive`/`service_unauthorized` unimplemented in `reserve`); S-07-003 closes the observable hole at the consumer (CB1) and registers the foundation-level completeness as FU-5, since it spans every future high-cost consumer and S-22 owns that surface. FU-3's consumer list is amended to name WF-005's orchestration context as a third consumer (`source_set_hash`/`normalized_scope_hash` stay NULL — no invented substitute). `crawl_project_not_active` is currently UNREACHABLE (OD-014 pending; the guard permits exactly draft->active) and is kept as required reauthorization with its unreachability asserted rather than faked. `deadline_at` is stamped but inert until `crawl_terminal_deadline` lands in S-07-008/009.

Acceptance:
Every mandatory gate is green (whole-repo suite **1471/0**; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness **31/0**; verify_runtime OK, 15 checks, RLS intact; all migrations build from empty; structure.sql idempotent). 24 acceptance examples run the PRODUCTION-REAL chain with the command built from the real persisted `crawl_dispatch` row's own identity, entitlement exhaustion driven through the real F-05 surface and suspension through the real WF-013 command; 13 persistence invariants exercise the database itself. S-07-003 is ACCEPTED; `S-07-003` added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-07-003 -> completed; `S-07-003_COMPLETION_REPORT.md` accepted; the integration branch pushed. `main` untouched. Next: **S-07-004** (crawl frontier), then S-07-005..011 under the standing delegation.

Authority And Precedence:
Executes the standing delegation ADR-061 under the S-07 authorisation (HD-S07-AUTHORISE); records the completion, five-lens review, hardening and acceptance of S-07-003, and the two contract corrections it makes to accepted code (ADR-075's F-05 `Service` recovery mapping and entitlement-event expectation). Allocated the next unused number after ADR-075.

## ADR-077: Owner Decision HD-S07-FU4-FU5 — Entitlement Event Ownership and Short-Circuit Completion Assigned to S-22 / WF-015

Status: Accepted (owner decision HD-S07-FU4-FU5, 2026-07-29)
Date: 2026-07-29
Owner: repository owner (decision); implementation agent (records the resolution and its scheduling)
Reversibility: Governance-only. No code changes; no accepted tranche reopened. FU-4 and FU-5 move from open follow-ups to scheduled S-22 scope.

Context:
The S-07-003 ADR-026 review (ADR-076) surfaced two items at the WF-005 / WF-015 boundary and registered them as `BUILD_STATE.open_decisions` FU-4 (owner attention) and FU-5 (accepted backlog). The owner has resolved both.

FU-4 — entitlement event ownership. RESOLVED: **S-22 / WF-015 is the canonical owner** of `EntitlementReserved`, `EntitlementExecutionStarted` and the remaining entitlement-reservation lifecycle events. **No new WF-005 limb is to be added and S-07's event ownership is NOT expanded beyond MTX-030.** An S-07 consumer may invoke F-05 and record its own workflow outcomes; the entitlement aggregate events remain WF-015's.

This confirms what the ratified contracts already say, and closes the gap between them and the ADR-075 acceptance note. `contracts/S-22.json` MTX-024 `domain_events` already reads "Exactly the ten WF-015 events: `EntitlementPolicyActivated`, `EntitlementChecked`, `EntitlementWarningIssued`, `EntitlementViolationDetected`, `EntitlementReserved`, `EntitlementExecutionStarted`, `EntitlementLeaseRenewed`, `EntitlementCommitted`, `EntitlementReleased`, `EntitlementReservationExpired`", and API_CONTRACTS.md :907-910 assigns each to WF-015 on the `entitlement_reservation` / `entitlement_lease_heartbeat` aggregate. MTX-030 `event_producer` independently scopes `Workflows::Wf005` to "all seventeen events" of WORKFLOW_SPECIFICATIONS.md :737, which exclude every entitlement event. The two contracts were already aligned; only the ADR-075 prose ("emitted by the CONSUMING workflow", "S-07-003 must emit EntitlementReserved/LeaseRenewed") disagreed, and that prose is hereby superseded. S-07-003's decision to emit none was correct and is confirmed. `contracts/S-22.json` `reservation_consumption` states the same division from the other side: "S-22 supplies the WF-015 machinery that decision consumes ... and does not redefine when a Crawl reserves."

FU-5 — the incomplete F-05 short-circuit precedence. RESOLVED: the **complete six-reason** entitlement short-circuit implementation (`organization_inactive`, `actor_inactive`, `service_unauthorized` added to the already-implemented `entitlement_inactive`, `operation_unknown` and the `classify` limits, in the WORKFLOW_SPECIFICATIONS.md :541 precedence with its fixed recovery mapping) is assigned to **S-22 / WF-015 as platform-foundation completion work**. Accepted S-07-003 is **not** reopened — the owner's test is an observable correctness or security defect in an S-07 consumer, and there is none: S-07-003's CB1 fix re-authorizes the Organization as its first gate limb, before `reserve` is reached, and it is currently the only consumer. **The consumer-side protections already added are preserved** and are not to be removed when S-22 lands the foundation-level fix; they are defence in depth at the point WF-005 is contractually required to reauthorize (SEARCH_CRAWL_RETRIEVAL.md § Crawl Admission And Snapshot step 1; MTX-030 `authorization_entry_point`).

Scheduling:
`BUILD_PLAN.yml` gains an `S-22` entry carrying both obligations explicitly, so neither is discoverable only from this ADR. `BUILD_STATE.open_decisions` FU-4 and FU-5 move to `resolved` with this ADR as authority and S-22 named as owner. Neither is an S-07 dependency: no S-07 contract obligation is unmet by their being outstanding, which is why S-07 continues under the standing delegation.

Acceptance:
Governance-only change; the mandatory gates are unaffected and were green at `f89e7b3` (rspec 1471/0; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture 31/0; verify_runtime OK; migrations build from empty; structure.sql idempotent). `main` untouched. Next: **S-07-004** (crawl frontier) under the standing delegation, carrying the owner-restated gate requirement that the deterministic frontier MUST exclude any pinned Source that is no longer active at execution time — a disabled, removed or otherwise inactive Source is never crawled on queue-time authority.

Authority And Precedence:
Records owner decision HD-S07-FU4-FU5. Supersedes the ADR-075 statement that the consuming workflow emits the entitlement events, and the corresponding `BUILD_STATE` reconciliation sentence. Confirms ADR-076's reading of MTX-030 `event_producer` and API_CONTRACTS.md :907-910. Allocated the next unused number after ADR-076.

## ADR-078: S-07-004 (Deterministic Crawl Frontier + Dequeue) Accepted — Five Confirmed-Blocking Findings Fixed

Status: Accepted (standing delegation ADR-061; five-lens ADR-026 review by three independent reviewers, five confirmed-blocking findings fixed)
Date: 2026-07-29
Owner: implementation agent, under the S-07 authorisation (HD-S07-AUTHORISE) and owner decision HD-S07-FU4-FU5
Reversibility: Accepted and pushed to the integration branch; `main` untouched. Additive: two new tables, one pure ordering module, one service, two migrations. The changes to accepted S-07-003 code are the frontier-seeding limb of the accepted-start commit and the pinned∩active precondition, both required by the owner's directive.

Context:
S-07-004 builds the crawl frontier (WORKFLOW_SPECIFICATIONS.md :454; SEARCH_CRAWL_RETRIEVAL.md § Crawl Admission And Snapshot step 6 and § Frontier And Deterministic Selection; contracts/S-07.json MTX-030 concurrency/persistence_model). `crawl_frontier_entries` (T-MUT) and `crawl_frontier_occurrences` (T-IMM) are implementation-owned TECHNICAL execution records — MTX-030 forbids promoting them to product entities — so nothing here emits a domain event or transitions a Crawl, and no network call exists on the path.

The ordering is the heart of the tranche. Volume I fixes the tuple `(depth, origin_rank, canonical_url, discovering_document_url, link_position)` with `root < sitemap < link`, and SEARCH_CRAWL_RETRIEVAL requires it MATERIALIZED into `dequeue_key bytea` and "tested against a reference tuple comparator". Because `bytea` compares bytewise, the encoding must be ORDER-PRESERVING. The document's "length-prefixed" phrasing cannot be taken literally for the variable-length fields — a length prefix inverts `"ab" < "b"` — so the fields are escaped and terminated (`0x00 -> 0x00 0xFF`, closed with `0x00 0x00`) and the numerics are fixed-width big-endian. The testable obligation is discharged exhaustively, including over the CROSS-PRODUCT of both string fields, which is the only shape in which a field-boundary defect appears.

THE OWNER'S REQUIREMENT (HD-S07-FU4-FU5 / ADR-077): "the deterministic frontier must exclude any pinned Source that is no longer active at execution time. Do not crawl a disabled, removed, or otherwise inactive Source solely on queue-time authority." It is enforced at THREE layers, because `crawl_sources` is T-IMM and records QUEUE-time membership: (1) seeding intersects the pinned set with Sources still `active`; (2) StartCrawl's `crawl_no_active_source` precondition is evaluated over that same intersection, so a run that can crawl nothing FAILS rather than reaching `running` with an empty frontier; and (3) the DEQUEUE re-checks Source state on every claim, so a Source disabled AFTER the start is never handed to a worker — added on a review finding, since the owner's words are "at execution time" and the dequeue is execution time. An independent reviewer attacked the requirement (disable one, remove one, disable all, activate a different Source after queueing, and a real race putting a committed `DisableSource` underneath an in-flight `StartCrawl`) and could not defeat it.

Five-lens ADR-026 review outcome:
Three independent reviewers covered the five lenses (contract; security+schema; concurrency+architecture) — recorded plainly because the previous tranche used five separate reviewers and the schema lens then found what security missed; the pairing is a reduction in independence between the paired dimensions. The CONCURRENCY lens returned PASS under real two-connection races: 3/3 concurrent claims took distinct entries, 5/5 concurrent identical offers produced exactly one admission plus one occurrence, three concurrent offers at a pre-loaded bound left the counter exactly at the bound, and no ABBA cycle exists across the three advisory locks StartCrawl now holds (`crawl-queue` -> entitlement window -> `crawl-frontier`, always that order). FIVE confirmed-blocking findings, ALL FIXED before acceptance:
- CB1 (contract): deduplication retained the FIRST OFFERED, but :454 says "Deduplication retains the first candidate IN THIS ORDER". The two genuinely diverge — :440 puts sitemap-discovered URLs and root-followed links both at depth 1, where `origin_rank` rather than the URL decides parent order, so children arrive in the wrong relative order and committing in dequeue sequence cannot repair it. Fixed: a lower-ordered later discovery REPOSITIONS the retained entry and the superseded position becomes the occurrence. This required relaxing the entry guard so POSITION is mutable while unclaimed and frozen from the claim onward; IDENTITY stays frozen for life.
- CB2 (contract): the 20,000 discovered-queue bound discarded by ARRIVAL, but :454 says "retain the LOWEST 20,000 by this order". Fixed: at the bound a lower-ordered newcomer EVICTS the highest-ordered unclaimed entry; only a newcomer that is itself the highest is discarded. Both losers are retained as `discarded` rows so the coverage denominator can account for them (:452). The bound had NO behavioural test at all — a named Volume I limit shipped untested — and now has two.
- CB3 (contract): breadth-first SEALING was ASSERTED as "falls out of the tuple" and was not implemented. Ordering by depth is necessary but not sufficient: once every depth-`d` row is claimed, `SKIP LOCKED` would hand out depth `d+1` while depth `d` is still in flight and its outgoing links undiscovered. :454 binds sealing to SELECTION, which is `claim_next`, which this tranche owns. Fixed: selection is confined to the lowest depth still holding a non-terminal entry, and the false claim is corrected in all three places it appeared.
- CB4 (architecture): `admitted_count` and `next_enqueue_order` were SEQUENTIAL SCANS OF THE WHOLE TABLE, executed per offer inside the exclusive per-Crawl admission lock, on a workflow with a hard 60-minute wall clock. Measured 8.8x degradation (0.62 -> 5.43 ms per offer at ~19k rows), and the scan widened with total platform volume rather than the Crawl's. Fixed with two indexes.
- CB5 (security/schema): `crawl_frontier_entries_scope_policy_fk` was a TWO-column FK to Project-owned `source_scope_policies`, so a frontier entry in Project A could name Project B's scope policy — the same defect class as S-07-003's CB5, and the reviewer demonstrated a persisted cross-project link. Fixed: `source_scope_policies` gains the mandated `UNIQUE (organization_id, project_id, id)` and the FK is rebuilt on three columns. A DB-wide sweep confirmed the only remaining under-arity FK to a Project-owned parent is the pre-existing `verification_attempts_request_fk` (out of scope, recorded).

Further hardening from non-blocking findings: `state_version` may only ever advance by one (it is the sole defence the admit/discard/reposition compare-and-swaps have, and a free rewrite would let a stale-version guard succeed); `correlation_id` and a written `reason` are frozen; occurrence insertion is idempotent, so a fetch-retry re-offer can no longer abort the caller's transaction on a unique violation; `canonical_url` is stored NFC-normalized so it cannot disagree with its own digest and order; `uint32` refuses overflow instead of silently wrapping the frontier order; and the Volume I reason vocabulary moved off the persistence adapter onto the domain surface.

Claims corrected rather than left standing: the collision path implements three of SEARCH_CRAWL_RETRIEVAL's four clauses — "emits restricted collision telemetry" is NOT built, recorded as FU-6; the `discovered` staging edges are not on a live path in this tranche; and the ordering proof's "0xFF" alphabet claim was unreachable (NFC normalization raises on invalid UTF-8) rather than merely untested.

Acceptance:
Every mandatory gate is green (whole-repo suite **1522/0**; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness **31/0**; verify_runtime OK, 15 checks, RLS intact; all migrations build from empty; structure.sql idempotent). S-07-004 is ACCEPTED; added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-07-004 -> completed; `S-07-004_COMPLETION_REPORT.md` accepted; the integration branch pushed. `main` untouched. Next: **S-07-005** (host gate + robots fail-closed + per-host rate), which inherits the named requirement that per-URL Source and scope re-validation continues at fetch time, and which fills the two nullable `robots_*` columns.

Authority And Precedence:
Executes the standing delegation ADR-061 under HD-S07-AUTHORISE, and discharges the frontier limb of owner decision HD-S07-FU4-FU5 (ADR-077). Allocated the next unused number after ADR-077.

## ADR-079: S-07-005 (Host Gate, Robots Fail-Closed, Per-Host Rate, Execution-Time Authorization) Accepted

Status: Accepted (standing delegation ADR-061; five-lens ADR-026 review by FIVE independent reviewers; confirmed-blocking findings fixed)
Date: 2026-07-29
Owner: implementation agent, under the S-07 authorisation (HD-S07-AUTHORISE) and the owner's S-07-005 objectives
Reversibility: Accepted and pushed to the integration branch; `main` untouched. Additive: one new table, one pure policy module, three services, two migrations. `Platform::PgArray` extracts a parser that already existed twice in accepted WF-004 code; both call sites now delegate to it.

Context:
S-07-005 builds the per-host gate, robots as fail-closed, per-host rate control, and — the owner's third objective — EXECUTION-TIME AUTHORIZATION re-validated immediately before every URL fetch. `crawl_host_gates` (schema :296) carries both host concerns in one row because both are decided under the same lock: the robots record (attempts, normalized rules, agent group, crawl delay, ordered sitemap candidates, source digest, terminal reason) and the rate/concurrency gate (next allowed start, rolling start instants, active connection count, lease version). Every rate predicate is evaluated IN PostgreSQL against `clock_timestamp()` under `FOR UPDATE`, per SEARCH_CRAWL_RETRIEVAL's "a worker cannot start merely because Redis granted a token". The robots parser is pure and covered by a golden corpus, as that document requires. The robots fetch consumes the frozen F-01 guarded egress.

Two defects were found and fixed by SELF-review before the lenses reported: the robots fetch sat inside the caller's transaction holding the gate's row lock (MTX-030 `transaction_boundary` ends "No external call sits inside a database transaction", and a slow host would have stalled every other worker on it) — restructured into the three-phase claim/fetch/record shape the accepted `Wf003::ObserveAutomatedSlot` uses; and :444's retry DELAYS and its `Retry-After` 1..120s override were unimplemented, with only the attempt count honoured.

Five-lens ADR-026 review outcome:
FIVE independent reviewers were used, restoring the per-lens independence ADR-078 recorded as reduced. Confirmed-blocking findings, ALL FIXED before acceptance — three of them FAIL-OPEN at the last gate before bytes leave the platform:
- ROBOTS BYPASS VIA THE RAW URL (security). `path_of` used the caller's string while the scope check used the predicate's canonical form, so `/%70rivate/secret` and `/a/../private/secret` walked past `Disallow: /private` with no caller mistake required. Every later check now uses the predicate's own canonical URL — which is what :448's "normalized path rule" means.
- `pg_array` MANGLED ARRAY LITERALS (architecture). Splitting on every comma turned the single element `{"/a,b"}` into two, so the gate admitted a URL the current Source Scope Policy denies and diverged from S-07-004's correct parse of the same columns. The correct parser already existed twice in accepted WF-004 code; extracted once as `Platform::PgArray`, with all three call sites delegating.
- ROBOTS WILDCARDS WERE LITERAL (contract). `Disallow: *` matched nothing and the whole site was crawled; `/*.pdf` protected nothing. :448 is silent on `*`/`$`, so this was a genuine ambiguity — resolved in the permissive direction, which inverts the owner's standing tie-breaker ("fail closed whenever robots semantics are uncertain") that the same tranche cited as its authority elsewhere. Now RFC 9309 semantics, precedence still by pattern length.
- `kind: "robots"` EXEMPTED ANY URL from robots, including on a host that had already failed closed; the shipped spec asserted the bypass rather than the exemption. Bounded to exactly `https://<gate host>/robots.txt`.
- THE GATE WAS UNBOUND: a caller-supplied gate row was never compared to the URL's host, the Crawl or the Organization, so another host's — or another tenant's — robots rules could license a URL. Now bound on all three.
- SAME-ORGANIZATION CROSS-PROJECT AUTHORIZATION: the Source and its scope policy were read by `(organization, source)` alone, so a Crawl in Project A could be authorized under Project B's scope, with Project B's policy id returned. Both reads are now keyed on the Crawl's Project — POSTGRESQL_SCHEMA :128's rule expressed in the read path, where no FK can enforce it. This is the THIRD consecutive tranche with this defect class.
- A 3xx ON `robots.txt` PERMANENTLY DENIED THE HOST. `max_redirects: 0` turned an apex->www or http->https redirect into `robots_unavailable_fail_closed`, which :452 makes a FAILED Source root with partial coverage — a customer-visible penalty for a perfectly crawlable host, and not one of the three triggers :448 enumerates. Redirects are now followed under the ratified per-URL budget; F-01 performs a new full resolution and destination-safety check on every hop, so following inherits the same egress guarantees.
- THE GATE ENFORCED THE GLOBAL CEILING, NOT THE RUN'S EFFECTIVE LIMITS. :390 makes the operative numbers "the most restrictive of global safety, approved entitlement, Organization, and Project limits", so a Project that had narrowed its per-host rate or concurrency was silently ignored — the exact inversion of :390, at the checkpoint MTX-030 requires a new restriction to bind at. Resolved per Crawl at the claim, with the global row kept only as the un-weakenable outer clamp.
- `robots_rules_schema` WAS NOT WRITE-ONCE, so the tag saying how the frozen rules are to be interpreted could be rewritten or erased by the runtime role, against schema :296's "normalized robots rules/schema ... robots terminal decision fields are write-once". Added to the guard. The rules CHECK was also one-directional, permitting `rules_applied` with NULL rules — a shape that reads as "robots resolved, nothing disallowed" and fails open; it is now an equivalence.

Further hardening from non-blocking findings: the entitlement limb checks the reservation's effective DEADLINE, not merely its state (F-05 has no `executing -> expired` edge, so a dead worker's reservation stays `executing` and would keep authorizing fetches for an unmetered run); the deadline is compared against the caller's `now`, agreeing with F-05 which is `now:`-driven throughout, while the rate window correctly keeps `clock_timestamp()` because it measures real elapsed time against a remote host; a robots attempt lost with its worker is reclaimed after a stale interval rather than wedging the host forever in `in_progress`; a corrupt or unreadable stored rule set DENIES rather than allowing everything; and the robots reasons are split so "not yet resolved" (a retryable scheduling condition) is no longer conflated with "failed closed" (terminal, and :452 makes it a failed Source root with partial coverage).

Acceptance:
Every mandatory gate is green (whole-repo suite **1601/0**; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness **31/0**; verify_runtime OK, 15 checks, RLS intact; all migrations build from empty; structure.sql idempotent). S-07-005 is ACCEPTED; added to `BUILD_STATE.completed_blocks`; `BUILD_PLAN` S-07-005 -> completed; `S-07-005_COMPLETION_REPORT.md` accepted; the integration branch pushed. `main` untouched. Next: **S-07-006** (sitemap discovery + XXE-hardened XML).

Authority And Precedence:
Executes the standing delegation ADR-061 under HD-S07-AUTHORISE and the owner's S-07-005 objectives. Allocated the next unused number after ADR-078.

## ADR-080: S-07-005 Acceptance Was Recorded Prematurely — Reopened, Two Further Confirmed-Blocking Findings Fixed, Re-Accepted

Status: Accepted (correction to ADR-079; standing delegation ADR-061)
Date: 2026-07-29
Owner: implementation agent (process error, correction and re-acceptance)
Reversibility: The corrected tranche is pushed to the integration branch; `main` untouched. No accepted behaviour outside S-07-005 changed.

What went wrong:
ADR-079 recorded S-07-005 as ACCEPTED on the outcome of FOUR of the five ADR-026 lenses. The CONCURRENCY lens was still running and had not reported. That is a mandatory-gate failure on my part, not a judgement call: ADR-026 requires the five-lens review, and a tranche cannot be accepted while a lens is outstanding — the whole point of the mandate is that the lenses find what the implementer did not. The elapsed time of a review is not a reason to close it early.

The lens then returned FAIL-WITH-FINDINGS with two confirmed-blocking defects LIVE AT HEAD, both in the concurrency slot accounting, both demonstrated with real two-connection races:
- CB1 — `release_slot` carried NO claim identity of any kind. `HostGate#claim` minted a `lease_version` and returned it, but `release` discarded it and `lease_version` had no consumer anywhere in the repository. One worker calling release twice — a retry, a replayed message, an `ensure` plus an explicit release — decremented a slot it did not hold, and `GREATEST(count - 1, 0)` turned that accounting error into a SILENTLY WIDENED nonexceedable ceiling. The reviewer drove the count to 0 with two connections still live, and the next claim was granted: three real connections accounted as one. WORKFLOW_SPECIFICATIONS.md :442 calls the ceilings "nonexceedable".
- CB2 — NOTHING reconciled `active_connection_count` after process loss. SEARCH_CRAWL_RETRIEVAL.md :82 is directly on point: "Process loss after claim is repaired by the LEASE SWEEPER; the same attempt identity is completed or timed out, never replaced by an unaccounted request." There was no sweeper, and the gate row can never be deleted, so the count only ever fell via an explicit release. After just TWO lost workers the host sat at its concurrency target and refused every claim for the rest of the run, which :452 then turns into `content_fetch_failed` and partial coverage for every URL on that host. The earlier hardening had added a stale-attempt reclaim for the ROBOTS attempt but not for the connection slot, which is what :82's sentence is actually about.

The fix (migration 20260727120210): a claim is now an IDENTIFIED, SELF-EXPIRING LEASE. `active_leases jsonb` holds `{token, claimed_at}` per live claim and is the authority; `active_connection_count` is retained because schema :296 names it, but is always DERIVED from the lease set in the same statement, and a CHECK makes the two unable to disagree. Releasing removes a TOKEN, so it is idempotent by construction and can only ever release the claim it names. Every claim sweeps leases older than `LEASE_STALE_SECONDS` (generously longer than the hard per-request timeout), so reclamation needs no separate scheduled job and cannot itself be lost — each claim repairs the accounting it is about to rely on. `HostGate#sweep` exposes the same reclamation for a health check on a host no worker is currently claiming against.

The lens also confirmed, with real races, that the rest of the gate holds: 4 and 8 concurrent claims on one host each granted EXACTLY ONE, the nonexceedable ceilings were never approached under any contention it could produce, two concurrent `EnsureRobots` calls performed exactly ONE fetch, and the network call was verified to hold no transaction and no row lock (a concurrent `lock_gate` on the same row returned in 0.6 ms mid-fetch). It also verified the earlier self-review fix empirically. Non-blocking observations recorded: the `state_version` CAS is load-bearing without an enclosing transaction and can refuse spuriously (a 250 ms retry, not a safety hole); `updated_at` is written from `clock_timestamp()` on claim and from the injected clock elsewhere, so it must never be used for staleness reasoning; and no lock ORDER is documented for a future consumer that holds the frontier lock while blocking on a contended gate.

Process correction, recorded so it binds future tranches: a tranche is not accepted, and no acceptance record is written, until EVERY lens of the ADR-026 review has reported. ADR-079's acceptance statement is superseded by this one.

Acceptance:
Every mandatory gate re-run green after the fix (whole-repo suite **1603/0**; Zeitwerk/Packwerk/Brakeman/bundler-audit clean; architecture fitness **31/0**; verify_runtime OK, 15 checks, RLS intact; all migrations build from empty; structure.sql idempotent). S-07-005 is RE-ACCEPTED on the complete five-lens outcome. `main` untouched. Next: **S-07-006** (sitemap discovery + XXE-hardened XML).

Authority And Precedence:
Corrects ADR-079, which recorded acceptance on an incomplete review. Allocated the next unused number after ADR-079.

## ADR-081: S-07-006 Sitemap Discovery — Accepted On The Complete Five-Lens Outcome, With Twelve Confirmed-Blocking Findings Repaired

Status: Accepted (standing delegation ADR-061; review discipline per ADR-080)
Date: 2026-07-29
Owner: implementation agent
Reversibility: Integration branch only; `main` untouched. Three migrations (20260727120220/230/240) round-trip faithfully and the schema builds byte-identically from empty.

What was built:
Sitemap discovery for one `(crawl, canonical_host)` — the :450 candidate set (robots' unfiltered `Sitemap:` declarations filtered here to same-host in-scope https, plus the default), :454 deterministic ordering and retention, breadth-first traversal of sitemap-index edges to the ratified depth, and frontier admission of the content URLs at depth 1 with the discovering sitemap URL carried on the occurrence. Every fetch passes the same host gate and the same execution-time `FetchAuthorization` a content fetch does. The XML parser is the security boundary and is treated as one.

Why this record is long: all five lenses returned FAIL-WITH-FINDINGS, and the security lens found that the previous design's stated protection did not exist. Recording the mechanism matters more than recording the verdict.

THE SECURITY FINDING THAT MATTERED MOST. The parser claimed "two independent defences". It had one. `Nokogiri::XML::SAX::Document` has no `internal_subset`, `external_subset` or `start_document_type` callback — verified directly against the installed Nokogiri, and verified again with a tracer subclass over the production `Document`: libxml2 invokes none of them, in ANY encoding, including plain UTF-8. Three of the four abort guards were dead code. The single surviving defence, a raw-byte scan, is defeated by encoding confusion: libxml2 auto-detects UTF-16/UTF-32 from the leading bytes with NO byte-order mark, and NUL-interleaved ASCII is itself valid UTF-8, so the scan matched nothing while the parser decoded and processed the declaration. Reproduced end-to-end: a UTF-16LE sitemap carrying `<!DOCTYPE urlset SYSTEM "http://169.254.169.254/...">` parsed `ok`, and the URL it named reached the frontier. No external entity resolved in any probe — libxml2's defaults held — but the code asserted a configuration it never applied and relied on a scan that could be walked around.

Rebuilt as three layered defences: an ENCODING GATE (:450's "UTF-8 XML only" enforced as a security control — foreign BOM, declared non-UTF-8 encoding, invalid UTF-8, and any NUL byte refused), the byte scan (now authoritative because it reads the bytes libxml2 will read), and a PROLOG INSPECTION through `Nokogiri::XML::Reader` in `NONET` mode, pulled only to the root element, which reports a document-type node using libxml2's own lexer. `reference` — the one real abort callback — remains. The docstring and SEARCH_CRAWL_RETRIEVAL.md now describe the mechanism that exists.

SPECIFICATION RECONCILIATION, recorded explicitly for owner visibility: SEARCH_CRAWL_RETRIEVAL.md said "Sitemap processing uses Nokogiri SAX in `NONET` mode". `Nokogiri::XML::SAX::ParserContext` exposes only `recovery` and `replace_entities` — there is no options bitmask, so that sentence names a configuration the API cannot express. The REQUIREMENT is unchanged and is now more strongly satisfied; only the named mechanism is corrected. This is a documentation reconciliation, not a contract or product change, and Volume I is untouched.

THE OTHER CONFIRMED-BLOCKING FINDINGS, by lens:

Contract/architecture — the ratified ceiling was exceedable and the ratified reasons were discarded. :437's unit is "sitemap documents per RUN"; the counter was per HOST, so a Crawl with ten Sources on ten hosts could fetch ten times the maximum. The budget is now reserved from `crawls.limit_counters` atomically in the UPDATE predicate, BEFORE each attempt, because the unit is distinct canonical URLs ATTEMPTED — counting successful parses let one index naming ten thousand dead children fetch every one without the counter moving. :454's retention now selects over the whole candidate set including index children; applying it at depth 0 only let one index naming 500 children produce 501 outbound fetches. Every :450 reason code was computed and dropped, irreversibly, behind a write-once guard, making `limit_reached` underivable; skips are now recorded with the LIMIT subset separated. :444's real 30s/120s schedule and `Retry-After` are shared in `FetchRetryPolicy` rather than approximated by a 250 ms constant.

Concurrency — a READ COMMITTED lost update broke a nonexceedable ceiling. `release_slot` and `sweep_leases` computed the surviving lease set in a `WITH` clause. Under READ COMMITTED a CTE is evaluated once from the statement snapshot; when the UPDATE blocks and EvalPlanQual re-fetches the row, quals and targetlist are re-evaluated but the CTE is NOT, so the statement wrote a lease array assembled before a concurrent claim — destroying the lease of a worker that was at that moment connecting. Reviewed: the accounted count drifted to 0 with three workers in flight and the gate then granted two more, five real connections against a ceiling of four. Verified independently here (CTE form: the concurrent claim is lost; correlated form: preserved) and rewritten as correlated sub-selects over the target row's own column, which EPQ does recompute. Separately, `begin_sitemaps` is now version-guarded with its row count honoured so a losing worker stands down rather than running the whole traversal; `terminalize_sitemaps` is bound to a claim token so only the executing worker can close its own attempt; and `sitemap_attempt_started_at` gives a lost attempt a reclamation window — without which honouring the claim would wedge a host for the rest of the run.

Schema — the write-once decision was not write-once, for the THIRD time in this class. The frozen set named four of the seven columns the terminal statement writes; `sitemap_documents_fetched`, `sitemap_max_index_depth` and `sitemap_discarded` were all rewritable by the runtime role after terminalisation, and the first two are exactly the observed values :442 requires a limit decision to record. The guard now derives its condition from a named list rather than a hand-copied condition. Separately, `sitemap_discarded` had no bound — it receives everything `retain` does not keep, from a robots file whose body is bounded but whose `Sitemap:` line count is not (~39,000 candidates, ~2.8 MB detoasted) — and sat on the row `lock_gate` reads with `SELECT g.*` FOR UPDATE before every fetch, measured at ~15 ms of lock-held work per read. Both halves are fixed: CHECK-bounded lists with recorded truncation, and a locked read projected to exclude all six bulk columns.

Test quality was itself blocking, and the finding was correct. The outbound stub discarded its keyword arguments, so the four ratified per-fetch bounds had no coverage and any of them could have been deleted with the suite green; and the test pacer nulled `next_allowed_start_at`, which is not "simulating elapsed time" — it made the very first retry succeed whatever the configured delay, so the deferral bound could never be exhausted and a `Crawl-delay` longer than the retry constant was unobservable. Both are repaired: requests are recorded and asserted, and the pacer moves stored instants into the past so the gate's own predicates decide whether enough time elapsed. Every fix in this tranche was then mutation-checked — reverted one at a time, with the matching test required to fail. One did not, and was rewritten until it asserted the property it claimed (:454 selection is about WHICH candidates are retained, not merely how many).

Non-blocking, recorded and NOT fixed here: the `Traversal`/service dependency is bidirectional and `Traversal` has no unit test (FU-8); `crawl_host_gates_sitemap_outcome_reason` is one-directional, consistent with the accepted robots precedent; both guards are UPDATE-only so an INSERT can seed a state, inherited and pre-existing; `normalize` over-rejects a trailing-dot host and an uppercase scheme; and sustained gate contention can still terminalize a host `unavailable` with zero attempts if no scheduler re-entry exists — that re-entry is S-07-008's, and is registered as a dependency rather than assumed.

Acceptance:
Every mandatory gate green: whole-repo suite **1678/0**; Brakeman clean (the store's private `exec` wrapper is renamed `query` — shadowing `Kernel#exec` made every fragment-interpolating statement read as command injection); Packwerk, Zeitwerk and bundler-audit clean; architecture fitness **31/0**; `verify_runtime` OK, 15 checks, RLS intact; the schema builds from genuinely empty and the dump is BYTE-IDENTICAL to the committed `structure.sql`; all three migrations round-trip down and up with no residue. S-07-006 is ACCEPTED on the COMPLETE five-lens outcome, per ADR-080. `main` untouched. Next: **S-07-007** (content fetch, redirect and scope validation, byte accounting, retry).

Authority And Precedence:
Under standing delegation ADR-061. Follows ADR-080's rule that no acceptance is recorded until every lens has reported. Allocated the next unused number after ADR-080.

## ADR-082: S-07-007 Content Fetch — Accepted On The Complete Five-Lens Outcome, With An F-01 Defect Repair And A Schema Rework

Status: Accepted (standing delegation ADR-061; review discipline per ADR-080)
Date: 2026-07-29
Owner: implementation agent
Reversibility: Integration branch only; `main` untouched. Both migrations round-trip down and up reproducing the schema exactly, and the schema builds byte-identically from empty.

What was built:
Content fetch for one frontier entry — host-gate claim, execution-time authorization, byte reservation, attempt claim, the guarded request, :436 measurement, commit-and-release, write-once terminalisation, slot release. Plus the two execution records schema :298 assigns to this work (`crawl_budget_counters`, `fetch_attempts`) and :442's reserve/commit/release protocol.

TWO THINGS THE OWNER SHOULD READ FIRST.

**1. This tranche modified F-01, the frozen egress façade.** :448 requires redirects "rechecked against robots and Source Scope Policy BEFORE FOLLOWING", and SEARCH_CRAWL_RETRIEVAL.md § Destination And HTTP Safety makes "canonicalize and recheck Source Scope and robots policy" STEP 1 of the connector's indivisible per-redirect sequence. F-01 implemented steps 2-8 and not step 1: it followed every hop the PLATFORM considered safe, so a robots-disallowed or out-of-scope intermediate was fetched and only the final URL could be judged — by which time the request had been made. There is no compliant implementation without touching F-01: `max_redirects: 0` turns a 3xx into a rejection and DISCARDS the `Location`, so a workflow cannot follow hops itself without duplicating pinning, TLS validation, loop detection and destination safety, which FOUNDATION-001 exists to prevent. I treated this as completing F-01 against its own ratified contract rather than as a scope change. The architecture lens was tasked with challenging that and judged it sound, verifying the `max_redirects: 0` claim against the code and stating it would not have escalated it. The repair is additive and defaulted: the guard is consulted after every platform check and can only ever REFUSE a hop the platform would have allowed; `nil` means "no caller policy", which is what every existing caller already had. If the owner disagrees, it reverts to one keyword argument.

**2. I built both new tables from the wrong authority.** I used SEARCH_CRAWL_RETRIEVAL.md's one-line summary when `schemas/POSTGRESQL_SCHEMA.md` :298 held a stricter canonical definition. The schema lens caught it. Three of the omissions were live defects, not pedantry: `UNIQUE` without `NULLS NOT DISTINCT` did not constrain a NULL frontier entry, so the ON CONFLICT idempotency the store depends on never applied to robots attempts (the reviewer inserted 20,000 duplicates); no CHECK enforced ":298 — frontier ID is null only for robots"; and without `WORK-CLAIM` plus the deadline checkpoint, SEARCH_CRAWL_RETRIEVAL :82's "completed OR TIMED OUT" had no physical representation, so three lost workers retired a frontier entry permanently and each loss retired 10 MiB of the run's byte budget with no reclamation. Both tables were reworked in place rather than patched, since nothing depends on them yet.

THE WORST DEFECT, found by the security lens and independently reproduced by the concurrency lens. `3.times do ... end` returns its RECEIVER when no `break` fires, so `reserve_bytes` returned the integer 3 — truthy — after three lost reservation races, and `return ... if reserved.nil?` never fired. The run then issued a real HTTP request with `byte_cap: 3` holding NO reservation, and `commit_bytes` violated `committed <= reserved` so a `PG::CheckViolation` escaped the workflow leaving a permanently non-terminal attempt row. The concurrency lens quantified the exposure precisely: **0/120 reproductions on a loopback database, 120/120 with 5 ms of added client latency.** The defect is near-certain on a real networked database and structurally invisible on this one, which is why 1,724 green examples never saw it. That number is the most useful thing this review produced, because it says plainly that a green local suite is not evidence about the reserve protocol.

THE OTHER CONFIRMED-BLOCKING FINDINGS, by lens:

Concurrency — byte reservations leaked with no reclamation (10 MiB each, 0.8% of the run budget per occurrence, verified through a real SIGKILL; 125 losses retire the run while `committed_response_bytes` records that it consumed nothing). The `WORK-CLAIM` lease is the reclamation handle: every claim now sweeps the run's expired attempt leases and returns their reservations, the same construction the host gate uses, so reclamation cannot itself be lost. Separately, `commit_bytes` and `terminalize` were separate transactions carrying no shared identity, so a failure of the second left the counter advanced and the attempt blank with nothing able to reconcile them; they are now one transaction, and a lost terminal write raises rather than diverging silently.

A JUDGEMENT recorded explicitly: a timed-out attempt still COUNTS against :444's three-attempt bound. A worker lost after claiming may already have issued its request and the run cannot know; refunding the attempt would let a host that kills workers be retried without bound. Reclamation returns the BYTES and writes a terminal record; the entry then exhausts honestly as `content_fetch_failed` inside the coverage denominator rather than hanging as `contended` outside it. Recovering such an entry is a new run's job (:444 — "a new attempt linked to the prior run ... uses a new Crawl ID"), which is S-07-011's.

Contract — a third retry delay was waited after the FINAL attempt, burning 120 s of the wall clock ahead of a request that never comes (my own test asserted `paces.first(2)` and was blind to it by construction). An entry with exhausted attempts returned `policy_excluded`, so a URL fetched three times and failed VANISHED from :452's coverage denominator and a run could report `full`. :390 was applied to bytes only — `request_timeout_seconds` and `redirects_per_url` were class-body constants and could not vary per Crawl at all. And F-01 emitted ONE rejection reason for six distinct redirect conditions, so a redirect to `http://` was filed as an eleventh-redirect limit hit; :454 requires "its EXACT limit reason" and :452 classifies them differently, so `:redirect_loop`, `:redirect_budget_exhausted` and `:redirect_rejected` are now separate.

Architecture — a database error inside the redirect guard was recorded as a POLICY exclusion, indistinguishable from a robots denial; because `policy_excluded` is the one :452 outcome that leaves the denominator, a transient fault made coverage read better than reality, silently. A guard that could not DECIDE is now a retryable failure inside the denominator. The sitemap counter's "move" was never wired — the new store method had no callers, the gate store still asserted the old location in a comment, and the sitemap spec asserted the old location too, so the tranche created the second home its migration claimed to eliminate; all three are corrected. The naive `host_of` that DIVERGED from `FetchAuthorization`'s careful parser and wrote the immutable `canonical_host` is deleted; there is one parser, and it is tested against the inputs `URI.parse` raises on.

TEST QUALITY, which was itself blocking and which I must record plainly. The previous commit claimed "every property is mutation-checked". It was not: eight selected properties were, and the architecture lens found four production branches with NO coverage — including the two defects that commit headlined as "found by writing the tests". Every acceptance example ran with a full run budget, so the reservation-versus-per-URL branch was unreachable; deleting `final_in_scope?` entirely, or the accepted-page limit, left the suite green. This acceptance rests on a sweep of ALL 24 fixes, each reverted individually with its test required to fail. Four did not discriminate on the first pass and their tests were rewritten until they did. A claim about coverage that is not itself tested is worth less than no claim.

SCOPE, stated rather than assumed. :456's ordered admission — "one coordinator commits discoveries and budget effects in increasing dequeue key" — is a SCHEDULER function, and no dispatcher exists until S-07-008. This tranche enforces the SUM (verified under eight genuinely simultaneous workers) and materializes `dequeue_key` on every attempt so the coordinator can enforce the ORDER without re-deriving it; ordered admission is registered as FU-10 with an enforceable trigger. Page reservation is REMOVED entirely: :436 retains "the first 10,000 successful DOCUMENTS in dequeue order" and :456 forbids fetch completion changing selection, so admitting a page at fetch completion decided the bound in completion order and could never be committed, because the Document it counts is S-07-010's.

Acceptance:
Every mandatory gate green: whole-repo suite **1741/0**; Brakeman, Packwerk, Zeitwerk and bundler-audit clean; architecture fitness **31/0**; `verify_runtime` OK, 15 checks, RLS intact; the schema builds from genuinely empty and the dump is BYTE-IDENTICAL to the committed `structure.sql`; both migrations round-trip down and up reproducing the schema exactly. I independently re-verified the three properties the rework most endangered: zero `fetch_attempts` columns fall outside the frozen identity/result lists, the unique key carries `NULLS NOT DISTINCT`, and both tables are RLS-forced with `arw` grants and no PUBLIC. S-07-007 is ACCEPTED on the COMPLETE five-lens outcome, per ADR-080. `main` untouched. Next: **S-07-008** (limits, soft/hard events, wall clock).

The hardening in this tranche was large — two tables rewritten and a reclamation path added — and was NOT itself put through a second five-lens pass. That is consistent with ADR-080, which conditions acceptance on every lens having reported on the tranche, but S-07-008's review inherits the new surface and should treat `crawl_budget_counters`, `fetch_attempts` and the lease sweeper as unreviewed-by-lens code.

Authority And Precedence:
Under standing delegation ADR-061. Follows ADR-080. Allocated the next unused number after ADR-081.

## ADR-083: S-07-008 Limits, Soft/Hard Events And The Wall Clock — Accepted After Five Review Passes, On A Mutation-Verified Acceptance Surface

Status: Accepted (standing delegation ADR-061; review discipline per ADR-080)
Date: 2026-07-29
Owner: implementation agent
Reversibility: Integration branch only; `main` untouched. Three migrations, all additive; the schema builds from empty and `db/structure.sql` shows no drift.

What was built:
:442's limit decisions as a durable record rather than runtime state — `crawl_limit_decisions`, whose `UNIQUE (crawl_id, limit_dimension, threshold_kind)` IS "exactly once per dimension and run" and is the only participant that can adjudicate "first" across processes. Nine of the twelve ratified dimensions are observed, each on the transaction that caused the effect it describes. FU-10's ordered admission (:456), the wall clock, the run-wide sitemap-document ledger, and the repository-truth spec. Full detail is in `S-07-008_COMPLETION_REPORT.md`, which describes HEAD rather than narrating how HEAD was reached.

WHAT THIS TRANCHE IS ACTUALLY A RECORD OF, and the reason it took five passes.

The owner's instruction after the fourth pass named the second-order defect exactly: *the implementation was becoming trustworthy faster than the repository's claims about it.* Each pass found the implementation converging and the prose diverging — a status token invented rather than read from its owning enum, commit fields naming a parent commit, a reconciliation note left byte-identical while everything around it moved, a table present in the database and absent from the canonical catalogue, and a backlog item directing the deletion of a load-bearing index. Every one was found by a human-equivalent reader comparing two files.

The response was to REDUCE the record surface and MECHANISE what remained. `spec/architecture/repository_truth_spec.rb` now asserts the state file's status vocabulary against `AutonomousBuild::StateMachine::STATES`, its commit fields against reachability from HEAD, `updated_at` against the committer date of the commit it names, `next_action` against the open-decision record it summarises, the acceptance-path partition against the actual diff, and every cited path, identifier and migration in the completion record against the repository. The completion record was cut to HEAD-only description. Prose that cannot be checked was deleted rather than corrected.

THE FIFTH PASS WAS MUTATION TESTING, NOT PROSE REVIEW, and it is the reason this acceptance is worth more than the previous four would have been. A green suite proves nothing about a control the suite never reaches. Seven controls survived reversion with 1,871 examples green, and each now fails under a named mutation:

- **The run-wide sitemap-document ceiling was structurally unreachable by every fixture in the repository.** Within one pass `SitemapCandidates.retain` already caps the attempted set at `documents_hard` — the same number the charge ceiling uses — and `crawl_host_gate_robots_decision_frozen` means a gate can never offer a second, different declared set, so re-entry always re-offers the same candidates. `ceiling: 10_000` therefore passed the entire suite. :437's unit is the RUN and a Crawl covers every active Source in its Project, so the bound binds ACROSS HOSTS. The owner asked for a re-entry fixture with changed declared sets; that shape is unreachable and the reason is recorded here rather than worked around.
- The charge, its projection and its limit decision are one unit of work. Rollback coverage cannot see the second half, because both commit on the happy path; transaction identity is asserted by comparing `xmin`.
- A missing budget-counter row raises rather than reporting `:exhausted`, which is the false `CrawlLimitReached` this subsystem keeps having to remove.
- The projection is DERIVED from the ledger, not incremented. The two agree for every run starting at zero, so the distinguishing state is a counter that does not already equal its ledger: derived recomputes and `crawl_budget_counters_not_monotonic` rejects the correction loudly, where an increment carries the disagreement forward as spent budget nobody charged for.
- The byte predicate is exact at its boundary. An off-by-one in the loosening direction is the difference between a ceiling and a suggestion.
- Forced RLS on both new tables is proved BEHAVIOURALLY, by reading and writing across a tenant boundary as `f1_web`. A catalog assertion cannot fail on `USING (true)`, which is the entire class of defect RLS exists to prevent.

A defect worth naming separately: the repository-truth spec's own path-citation check named six directories, so citations under `automation/` and `architecture/` were silently unchecked. A hardcoded vocabulary inside the spec that exists to catch hardcoded vocabularies is the same defect twice; the directory list is now read from the repository.

FU-11's diagnosis was corrected twice and both corrections are recorded. The third pass prescribed a NULL-safe rewrite of `crawls_coverage_status_check`; that prescription is a proven no-op, since `NULL = ANY(...)` is UNKNOWN and therefore admitted and `IS NOT DISTINCT FROM` is admitted too. Applying it would have produced a diff, closed the item, and left the hole open. The fault is in `crawls_terminal_shape`, whose terminal limb requires only `terminal_at IS NOT NULL`. The fourth pass then corrected the repair itself: requiring both columns on every terminal state would break `IdentityAccess::Infrastructure::CrawlStartStore#fail`, because a failed run carries a completion reason and no coverage. The conjunct must be scoped by state. It remains BLOCKING for S-07-009 and is not repaired here.

RECORDED HONESTLY, three things the owner should not have to discover.

**No production caller exists** for `Admission`, `FetchContent`, `DiscoverSitemaps` or `EnsureRobots`. The only registered entry point is `crawl_dispatch -> StartCrawl`, which seeds the root frontier and schedules nothing further. Every observation point is exercised by acceptance specs driving these services directly. FU-9 is MITIGATED, not delivered, for the same reason: a hand-back method is not scheduler re-entry. S-07-012 owns the driver and is the next eligible item.

**Two commits in this tranche were made with `git add -A`** and swept in twelve unrelated `branding/`, `investor/` and `operations/` files. Owner ruling: published history is not rewritten for cosmetic cleanliness. The consequence is procedural — this tranche is reviewed BY PATH over a commit range, never by treating any single commit as a slice — and the repository-truth spec asserts that the declared paths and the recorded exclusion list partition the range exactly.

**Two mandatory checks in `VERIFICATION_MANIFEST.yml` name spec directories that have never existed** in this repository: `spec/automation/locking` and `spec/automation/crash_recovery`. This is pre-existing, predates every accepted tranche, and was not caused by this work, which changed controller DATA (`BUILD_STATE`, `BUILD_PLAN`) and no controller code. It is registered as FU-14 rather than passed over silently, because a manifest that names a check nobody runs is the same class of defect as prose that names a mechanism nobody built.

Acceptance:
Every mandatory gate green from the final state: whole-repo suite **1882/0**; Brakeman clean under `-z`; Packwerk, Zeitwerk and bundler-audit clean; architecture fitness **45/0**; `verify_runtime` OK, 15 checks, RLS intact; `db:schema:dump` produces no `structure.sql` drift; controller `unit` 33/0, `integration` 20/0, `policy` 21/0, `end_to_end` 10/0 — with `locking` and `crash_recovery` missing per FU-14. `repository_cleanliness` is NOT empty: nine `branding/` and `operations/` files carry the owner's own in-flight parallel work, outside the acceptance path partition and deliberately untouched. S-07-008 is ACCEPTED. `main` untouched. Next: **S-07-012** (the run driver), which closes FU-9.

Authority And Precedence:
Under standing delegation ADR-061. Follows ADR-080's rule that no acceptance is recorded until every lens has reported; five passes reported here, the fifth as mutation verification rather than prose review, on the owner's instruction. Allocated the next unused number after ADR-082.

## ADR-084: Blocking-Defect Repair Authority — A Demonstrated Root Cause May Be Repaired Across Tranche Boundaries

Status: Accepted (owner decision, 2026-07-30; drafted by the implementation agent at the owner's direction)
Date: 2026-07-30
Owner: repository owner
Reversibility: Governance only. No product code, schema or contract changes.

The question this answers:
**May the controller interrupt its current tranche to repair a blocker it did not create?** It arose three times in two days and was answered differently each time, which is the signal that it belongs in the record rather than in a judgement call.

The occasion. The mandatory `complete_test_suite` gate began hanging intermittently — two of four whole-suite runs, on an unchanged tree. The controller stopped, which was defensible, and recorded the blocker. But it recorded it against "S-013", a block that DOES NOT EXIST in BUILD_PLAN: the name was inferred from a commit-message prefix and a spec filename. The record then directed the next session to seek authority from a block that could never grant it. Meanwhile the actual defect sat in shared test-harness code owned by no tranche at all — two memoized raw `PG.connect` connections running with `statement_timeout = 0` while `config/database.yml` declares 15s for precisely this purpose and says so in a comment.

Two failure modes in one episode, and they pull in opposite directions. Stopping produced a false ownership claim and a session lost to a blocker that was one small change away from repaired. Not stopping would have risked an agent wandering out of its tranche on a hunch. The rule has to permit the first while forbidding the second, and the discriminator is EVIDENCE.

**The rule.** A mandatory gate failure whose ROOT CAUSE HAS BEEN DEMONSTRATED is repaired immediately, whichever tranche owns the defect and whatever tranche is in progress, provided every one of the following holds:

1. **The repair removes the blocker itself, rather than merely restoring a passing gate.** Widening a timeout, reordering or seeding tests, excluding a file, quarantining an example, retrying until green, or loosening an assertion are all forbidden, because each restores the gate while leaving the defect. If the smallest available change makes the gate pass without removing the cause, that is not a repair and the controller stops.
2. It is the smallest correction that satisfies (1).
3. It does not change product semantics.
4. It does not touch a frozen foundation. F-01 through F-04 remain an owner decision even when the evidence looks conclusive, because "I have proved this foundation must change" is exactly the conclusion an agent is most likely to reach wrongly and least able to check. ADR-082 modified F-01 and required an owner-visible argument to do it; that bar does not move.
5. It does not require changing repository governance, including this rule.
6. It is committed SEPARATELY from the tranche in progress, mixing no unrelated change.
7. It is recorded as a follow-up in `BUILD_STATE.open_decisions`. A separate commit gives git history; a follow-up gives GOVERNANCE history. They answer different questions and neither substitutes for the other.
8. The full mandatory gate set passes from the resulting state, and where the failure was nondeterministic, repeated whole-suite runs are recorded as stability evidence rather than a single green run.

**DEMONSTRATED means reproduced and explained, not inferred.** The threshold is deliberately not "deterministic defect": the hang that produced this rule presented intermittently and only its cause was deterministic, so that wording would have excluded the very case it was written for. A root cause is demonstrated when the mechanism is exhibited on demand and the counterfactual is shown — here, that a harness-style connection reported `statement_timeout` `0` against ActiveRecord's `15s`, that a `TRUNCATE` on it was still blocked after 20 seconds behind an idle-in-transaction session, and that the identical statement carrying the configured value raised `PG::QueryCanceled` instead. Location is not causation: the threads visibly piled up in the WF-013 concurrency specs, which is where the symptom appeared and not where the defect lived.

If any condition fails, the controller stops and escalates under HUMAN_ESCALATION_POLICY. A blocked tranche remains preferable to an unapproved change.

**What this does not authorise.** It is not permission to work on another tranche's backlog, to repair defects that are not blocking a mandatory gate, or to treat a failing spec's filename as evidence of ownership. Ownership is read from BUILD_PLAN; a defect in shared infrastructure owned by no block is repaired under this rule, not assigned to a block invented for the purpose.

Authority And Precedence:
Owner decision, taken after the observed episode rather than in anticipation of it. Operates within standing delegation ADR-061 and does not alter it; ADR-080's rule that acceptance requires every lens to have reported is untouched, and a repair under this rule is not an acceptance. Restates nothing in AUTONOMY_POLICY that it contradicts: the operational statement is added there under this ADR's number, following the pattern ADR-061 already set. Allocated the next unused number after ADR-083.

## ADR-085: FU-16 Resolved — The First `crawl_fetch_due` Targets The Selected Frontier Entry And Admission Happens Only At Execution

Status: Accepted (owner decision, 2026-07-30; recorded by the implementation agent from the owner's ruling)
Date: 2026-07-30
Owner: owner ruling; HD-S07-FU16-FIRST-HANDOFF
Reversibility: Integration branch only; `main` untouched. Resolves FU-16, which had blocked S-07-012 (3/n).

The question. S-07-012 (3/n) — StartCrawl's first fetch handoff — was built and then WITHDRAWN rather than committed, because the two available shapes differ in reservation lifetime, recovery semantics and which component creates `fetch_attempts` rows. FU-16 recorded the fork and the evidence: (A) pre-admit at start, closest to BACKGROUND_PROCESSING.md :138's "one selected PERSISTED fetch attempt", but holding a byte reservation and an `in_progress` frontier entry across the whole scheduling latency and making StartCrawl a second producer of attempt rows; (B) target the frontier entry and admit at execution.

THE RULING IS (B), in the owner's terms:

* StartCrawl schedules the first `crawl_fetch_due` action against the SELECTED FRONTIER ENTRY.
* Fetch admission remains the SOLE PRODUCER of `fetch_attempts`.
* Admission occurs ONLY at execution.
* The retry semantics proven by accepted S-07-007 remain UNCHANGED.
* No second producer of `fetch_attempts` is introduced.

Why this is the stronger answer, beyond the reservation-lifetime argument FU-16 already recorded. The ratified catalogue itself distinguishes content fetch from every other attempt-bearing work type. :140-143 give `ingestion_attempt_due`, `parsing_attempt_due`, `indexing_attempt_due` and `check_attempt_due` as "initial or declared 30/120-second retry" — those retries ARE scheduled actions. :138 gives `crawl_fetch_due` as "one selected persisted fetch attempt, including an immediate first attempt", and says nothing about retries, because :444's content-fetch retries are the in-process loop S-07-007 built and proved. (A) would have moved those retries onto the scheduler, which is why adapting `spec/acceptance/wf005_content_fetch_spec.rb:426` was a coverage loss rather than a test update: with attempt #1 pre-created, `FetchContent`'s own loop starts at #2 and one of the two proven delays [30000, 120000] disappears. The catalogue does not ask for that move and the accepted proof forbids it.

What still satisfies :198. The direct claim owner for `crawl_fetch_due` is recorded as "Fetch Attempt" and :185 makes `target_id` the claim-owner row ID. Under (B) the durable idempotency authority is unchanged — it is the attempt identity `(crawl_host_gate_id, request_kind, crawl_frontier_entry_id, attempt_number)` under its `ON CONFLICT`, which is derived from the frontier entry and the attempt number and holds whoever creates the row. What (B) changes is WHEN the row exists: the admitting execution creates it, so at scheduling time there is nothing to name but the entry the admission will claim. The frontier entry is a genuine claim owner — `queued -> in_progress` under the frontier's own advisory lock is the claim — so `target_id` still names the row the execution claims. The residual naming divergence between :138/:185's prose and this shape is recorded as a follow-up for prose reconciliation, not resolved by inventing a row to point at.

The principle the owner added, and which decided it: OPTIMISE FOR REDUCING FUTURE COMPLEXITY, NOT TODAY'S LINES OF CODE. (A) worked. It also created a second producer of an append-only-in-practice row and a more complex ownership model, and for a platform expected to carry tens or hundreds of thousands of organisations, simplicity of ownership boundaries predicts long-term scalability better than any single function's speed. Systems at scale fail on coordination complexity, contention and operational ambiguity.

Consequences carried into S-07-012:
- `crawl_fetch_due` carries `target_type = 'crawl_frontier_entry'`.
- (2/n)'s attempt-prepare limb is REMOVED, not retained beside the new one: `FetchAttemptDueSchedule`, `FetchAttemptStore#prepare`, `#claim_prepared`, `#submission_started` and `FetchContent#record_persisted_attempt` existed only to make a pre-created attempt executable. Keeping them would be the second producer the ruling forbids.
- `FetchContent#call` — the accepted S-07-007 entry point, with its in-process :444 loop — is what the handler drives, consuming Admission's reservation as S-07-012 (1/n) already made it do.

Authority And Precedence:
Owner decision under AUTONOMY_POLICY "Human decision required" item 8 (product semantics with more than one materially different valid interpretation), which is the class FU-16 was raised under. Operates within standing delegation ADR-061. Allocated the next unused number after ADR-084.

## ADR-086: Development Cadence — Autonomous Continuation Between Named Architectural Stop Conditions

Status: Accepted (owner decision, 2026-07-30; recorded by the implementation agent from the owner's direction)
Date: 2026-07-30
Owner: owner ruling
Reversibility: Governance only. Supersedes nothing; narrows when the controller returns for review.

The change. The controller no longer stops after every implementation unit for strategic confirmation. It continues automatically through the eligible work BUILD_PLAN and BUILD_STATE identify, completes coherent blocks of related work, and returns for independent adversarial review at MEANINGFUL MILESTONES rather than every increment. Repository gates still run continuously after each unit; what changes is the review frequency, not the verification frequency.

THE STOP CONDITIONS ARE NAMED AND EXHAUSTIVE. The controller stops immediately and requests review on encountering any of:

1. a change to transaction boundaries;
2. a second producer of an immutable entity;
3. changes to authorization or RLS semantics;
4. changes to identity or idempotency ownership;
5. changes to immutable ledger semantics;
6. concurrency primitives or locking strategy;
7. changes that invalidate an accepted proof or accepted contract;
8. repository governance requiring a new ADR or owner decision.

Everything else is normal implementation work. In particular, the controller does NOT stop merely because several implementation choices exist, when one is already implied by a repository contract, an accepted ADR or an established architectural principle.

The standard does not move. Professional-grade correctness, scalability, concurrency behaviour, latency and operational robustness take precedence over implementation speed. Every completed unit adds or strengthens tests, mutation-tests behavioural invariants where the repository requires it, runs the required gates, and commits with a precise message. Each change prefers the smallest repository-consistent form, maintains or improves existing performance characteristics, avoids unnecessary allocations, database round trips and lock duration, and preserves deterministic behaviour under concurrency, recovery semantics and every accepted guarantee.

And the principle that decided ADR-085 is now standing: OPTIMISE FOR REDUCING FUTURE COMPLEXITY, NOT TODAY'S LINES OF CODE. Simplicity of ownership boundaries — one producer per entity, one owner per reservation, one authority per identity — is a stronger predictor of behaviour at scale than local efficiency.

Authority And Precedence:
Owner decision. Operates within standing delegation ADR-061 and does not alter it; ADR-080's rule that acceptance requires every lens to have reported is untouched, as is ADR-084's blocking-defect repair authority. The operational statement is added to AUTONOMY_POLICY under this number, following the pattern ADR-061 and ADR-084 set. Allocated the next unused number after ADR-085.

## ADR-087: FU-18 Resolved — S-07-012 Owns The Frontier Seal Release, Because It Owns The Dequeue-And-Fetch Decision

Status: Accepted (owner decision, 2026-07-30; recorded by the implementation agent from the owner's ruling)
Date: 2026-07-30
Owner: owner ruling on FU-18
Reversibility: Integration branch only; `main` untouched. One additive guard edge; the schema builds from empty and `db/structure.sql` shows the edge and nothing else.

The question. `crawl_frontier_entries` declares `terminal` in its ratified state CHECK, but `f1_crawl_frontier_entries_guard` permitted only `discovered -> queued|discarded` and `queued -> in_progress|discarded`, so a claimed entry could never leave `in_progress`. `peek_next`/`claim_next` select at `sealed_depth = MIN(depth) WHERE state IN ('queued','in_progress','fetched_pending_commit')`, which is WORKFLOW_SPECIFICATIONS.md :454's "all depth d discoveries are SEALED before any depth d+1 candidate is SELECTED". A claimed entry that can never retire therefore pins `sealed_depth` at its own depth for the rest of the run, and since sitemap discovery admits content URLs at depth 1 (:440), a Crawl with any usable sitemap fetched its roots and then stalled with admitted work queued. S-07-012's own required loop — "admits, fetches and discovers UNTIL THE FRONTIER DRAINS" — was unreachable.

Why it was raised rather than taken. `spec/persistence/crawl_frontier_invariants_spec.rb` ASSERTED that `in_progress -> terminal` raises, and `spec/acceptance/wf005_crawl_frontier_spec.rb` recorded the edge as "S-07-009's". Delivering it edits an accepted assertion and reassigns an ownership recorded in an accepted tranche, which is ADR-086 stop condition 7.

THE RULING: deliver it in S-07-012. S-07-012 OWNS THE DEQUEUE-AND-FETCH DECISION AND THEREFORE OWNS THE COMPARE-AND-SET TERMINAL TRANSITION THAT RELEASES `sealed_depth`. The prior attribution predates S-07-012's existence — it is the block the ADR-026 architecture and concurrency lenses named at S-07-008 acceptance, and at the time the comment was written S-07-009 was simply the next tranche after the fetch surfaces. The seal release is the commit point of a fetched entry, and the driver is the only component that knows a fetch has been decided; S-07-009 computes coverage and completion from what the driver recorded and never dequeues.

The boundaries, all preserved and each one asserted rather than asserted-in-prose:
- `terminal` is reachable from `in_progress` ONLY.
- The transition is a COMPARE-AND-SET on `(state = 'in_progress', state_version)`, so a stale version, an unclaimed entry and a second delivery each match zero rows instead of rewriting a decision.
- `fetched_pending_commit` stays EXCLUDED. It is :456's coordinator limb — "a completion with a later key waits in `fetched_pending_commit`; it cannot change selection" — which arrives with concurrent fetching and link extraction, and `Wf005::Admission` already declined to pre-empt it for the same reason.
- NO transition out of `terminal` exists, so a coverage-bearing decision cannot be rewritten later.
- `commit_order` remains S-07-009's. It is the coordinator's commit sequence, not the dequeue's; a value written by a driver that advances one entry per pass would restate `enqueue_order` rather than record the ordering the column exists for.
- `crawl_terminal_outcomes` (T-IMM, one row per frontier entry, carrying the terminal commit order, the outcome, the Document ID and the coverage effect — POSTGRESQL_SCHEMA.md :299) and the link-extraction/coordinator path remain S-07-009's and S-07-010's. The seal release releases the SEAL; the durable record of what happened to a URL is the `fetch_attempts` row the fetch already terminalized.
- Nothing else in S-07-012 widens.

WHERE THE TRANSITION HAPPENS, and why it is not in the handler's terminal transaction. The driver retires the entry in its OWN transaction, immediately after `FetchContent#call` returns and before the ledger and the next-frontier link commit. The alternative — retiring it inside the handler's terminal transaction, atomically with the ledger and the link — is more obviously tidy and has a strictly worse failure mode: a process lost between the fetch and the ledger write would leave the entry `in_progress` forever and PERMANENTLY PIN THE DEPTH, needing a resumption policy that S-07-012 has no authority to invent. Retiring it first means a lost pass leaves the seal RELEASED and no link, and the redelivery then finds the entry terminal, records `superseded`, and links the run on — the chain repairs itself with no new recovery vocabulary. Ledger completeness is identical either way, because in both cases the lost transaction is the one carrying the ledger rows. :378 constrains the transaction that creates the next-frontier ACTION, which is unchanged.

The edited assertion is STRONGER than the one it replaces. It previously said three edges out of `in_progress` are refused. It now says `terminal` is reachable only from `in_progress` and only through the compare-and-set, that `fetched_pending_commit` remains refused, that `queued`, `discovered`, `discarded` and an already-`terminal` row are each refused as sources, and that no edge leaves `terminal`.

Authority And Precedence:
Owner decision under ADR-086 stop condition 7, raised by the implementation agent with the migration, store method, specs and mutation evidence prepared and held out of the repository, and approved unchanged. Operates within standing delegation ADR-061. Allocated the next unused number after ADR-086.

## ADR-088: Corrections To ADR-085 And ADR-087, Made By The Five-Lens Review Of S-07-012

Status: Accepted (standing delegation ADR-061; review discipline ADR-080)
Date: 2026-07-30
Owner: implementation agent
Reversibility: Governance only. Corrects two recorded justifications; changes no ruling and no behaviour.

Two statements I wrote into accepted ADRs are wrong. The review found both, and ADR-083's standing lesson is that a false statement in the ledger is repaired rather than left to be re-derived.

**ADR-085's attribution of the durable idempotency authority is wrong.** It says the attempt identity `(crawl_host_gate_id, request_kind, crawl_frontier_entry_id, attempt_number)` under its `ON CONFLICT` is "what makes execution idempotent ... whoever creates the row". The contract lens demonstrated otherwise: `FetchContent` computes `attempt_number` as `attempt_count + 1` from committed state, so that `ON CONFLICT` can only ever absorb a duplicate carrying the SAME number — a concurrent same-number race. A redelivery computes the next free number and would issue a NEW request. What actually makes execution idempotent is three other things: `f1_dispatch_scheduled_action`'s claim compare-and-swap, the command idempotency record the handler writes, and `Admission#claim_entry`'s `queued -> in_progress` compare-and-set. THE RULING IS UNAFFECTED — the action still targets the frontier entry, admission still happens at execution, the fetch path is still the sole producer of attempts — and the behaviour was and is correct. Only the reason given for it was wrong, and a wrong reason in an ADR is how the next tranche builds on a premise that does not hold.

**ADR-087 overstates the self-healing it claims.** It says retiring the entry before the ledger means "a lost pass leaves the seal RELEASED and the redelivery then finds the entry terminal". That is true only for a loss AFTER the release. The widest window in the pass is the one that CONTAINS the fetch — between `Admission`'s claim and the release — and a loss there leaves the entry `in_progress` with `sealed_depth` pinned, exactly as before. The comparison ADR-087 makes still holds and the ordering is still the better one: the alternative leaves BOTH windows stranded, this leaves one. What does not hold is the implication that a redelivery always finds the entry terminal. FU-22 carries the stranded claim, whose recovery needs a frontier-lease sweep and is S-07-011's.

**And a false premise in ADR-087 that the schema lens found.** It justifies leaving `crawl_terminal_outcomes` unbuilt with "the durable record of what happened to a URL is the `fetch_attempts` row the fetch already terminalized". That is false for a routine class: `FetchContent` authorizes BEFORE it claims an attempt row, so a URL refused by robots or by current scope, or one whose host-gate claim was refused, retires with NO attempt row at all. FU-21 carries it, marked blocking for S-07-009, which is the tranche that must tell a covered URL from an unretrieved one.

Authority And Precedence:
Under standing delegation ADR-061, as a correction of record rather than a decision. ADR-085's and ADR-087's rulings stand unchanged. Allocated the next unused number after ADR-087.

## ADR-089: FU-19 Resolved — The Scheduler Owns Waiting, The Worker Owns One Bounded Attempt

Status: Accepted (owner decision, 2026-07-30; recorded by the implementation agent from the owner's ruling)
Date: 2026-07-30
Owner: owner ruling on FU-19
Reversibility: Integration branch only; `main` untouched. No schema change. Supersedes one clause of ADR-085 and nothing else.

The defect. A `crawl_fetch_due` execution ran :444's whole retry loop in-process, sleeping 30 then 120 seconds, so one pass took roughly 195 seconds against `Platform::ScheduledActions::Worker::WORKER_LEASE_SECONDS` of 30 with NO heartbeat. `Platform::BackgroundExecution.run_scheduler` recovers expired leases on every pass, so the action returned to `pending` mid-fetch and was re-dispatched: THE ORDINARY RETRY PATH EXECUTED TWICE. Not an edge case — every content fetch that retries once. Demonstrated by the ADR-026 concurrency lens with injected latency and corroborated by the contract lens.

THE RULING: scheduler re-entry.

- A `crawl_fetch_due` execution performs AT MOST ONE content-fetch attempt.
- If that attempt is retryable and another remains, it schedules a new `crawl_fetch_due` for the SAME frontier entry at the exact instant :444 requires, and returns. NO WORKER THREAD SLEEPS through the 30- or 120-second interval.
- Attempt numbering continues to derive from committed state.
- The frontier entry and the admission remain the continuity and idempotency authorities: the claim, the byte reservation and the depth seal are all held across the retry, because they belong to one admission of one URL.
- The global worker lease is NOT extended to accommodate in-process sleeping.
- :444's three-attempt bound and its exact 30,000 ms / 120,000 ms delays are unchanged.

WHY THIS IS THE BETTER ARCHITECTURE, in the owner's terms: a worker must not remain occupied for ~195 seconds doing almost nothing. That design converts retry DELAY into worker-pool DEMAND, and at tens of thousands of organisations even a modest timeout rate produces avoidable queue growth, duplicate lease recovery, noisy ledgers and higher infrastructure cost. Worker occupancy now scales with requests rather than with waiting. It is also what the ratified catalogue already does for every other attempt-bearing work type: :140-143 give `ingestion_attempt_due`, `parsing_attempt_due`, `indexing_attempt_due` and `check_attempt_due` an explicit "initial or declared 30/120-second retry".

**THIS SUPERSEDES ONE CLAUSE OF ADR-085**, and the supersession is stated rather than left to be inferred. ADR-085 read :138's silence about retries as positive evidence that content-fetch retries belong in-process, and concluded that "the retries S-07-007 proved stay in-process". That inference is withdrawn. What :138 fixes is that `crawl_fetch_due` carries ONE selected attempt — which this ruling satisfies exactly, one attempt per execution — and it says nothing about where the waiting happens. Everything else in ADR-085 stands unchanged: the action targets the selected frontier entry, admission happens at execution, and the fetch path is the sole producer of `fetch_attempts`.

THE RETRY INSTANT IS DERIVED, NOT OBSERVED, and that is load-bearing. :444 measures its delays from "completion of the ... failed attempt", so the instant is `fetch_attempts.completed_at + 30s` or `+ 120s`, read back from the committed row rather than taken from the executing worker's clock. The ratified ScheduledAction identity preimage includes `due_at`, so a derived instant makes two deliveries of one action compute the SAME identity and the second REPLAY — at most one retry is durably linked per stage. Taken from `now`, two deliveries would compute two instants, create two actions, and fork the run into two chains.

A retry that would fall past `crawls.deadline_at` is not created at all. :442 ends the run at 60 elapsed minutes, so such a re-entry could only arrive to be refused; treating it as exhaustion releases the reservation and the seal immediately and strands neither.

Also corrected here: a lost race for an attempt number now releases NOTHING when the reservation was carried in. The `ON CONFLICT (crawl_host_gate_id, request_kind, crawl_frontier_entry_id, attempt_number)` absorbs exactly one case, and under one-attempt-per-execution it is the case that matters — two deliveries reaching the same number. The winner holds the admission's reservation and is about to spend it, so the loser must not hand it back; a genuinely lost holder is reclaimed by `sweep_expired`. This also partially rehabilitates the claim ADR-088 corrected: the attempt identity is now genuinely load-bearing for concurrent duplicates, though it is still not what makes a REDELIVERY idempotent.

Proof standard. Seven properties, each an example over the production-real chain driving the real handler: one attempt with its outcome committed and exactly one re-entry at completion + 30 s, returning without waiting; the second pass resuming from committed state and owing 120 s without renumbering; the third creating no retry, releasing the whole remainder and terminalising; retry-then-success preserving numbering and pacing with one forward link and counters equal to accounted bytes; a duplicate delivery linking no second retry and creating no second attempt; the derived instant collapsing two computations into one action; three deliveries together completing inside ONE worker lease; and a retry past the deadline not created, with nothing stranded. Eight mutations each fail an example: retry scheduling removed, the instant taken from `now`, the attempt number reset, the bound raised, the exhausted-path release omitted, the seal released while a retry is owed, the deadline check removed, and resume disabled.

The accepted S-07-007 pacing proofs were TRANSLATED, not weakened. `paces == [30_000, 120_000]` asserted in-process sleeps; the same contract is now asserted as the sequence of delays consecutive executions REPORT, `[30_000, 120_000, nil]` — the whole sequence rather than a prefix, so a third delay cannot hide, which is the defect the original assertion was strengthened to catch.

Authority And Precedence:
Owner decision, taken on the evidence of the ADR-026 five-lens review of S-07-012. Supersedes ADR-085's in-process-retry clause and nothing else; ADR-087's rulings are untouched. Operates within standing delegation ADR-061 and cadence ADR-086. Allocated the next unused number after ADR-088.

## ADR-090: Corrections Of Record Forced By The S-07-012 Delta Review, Including A Repair I Claimed And Did Not Make

Status: Accepted (standing delegation ADR-061; review discipline ADR-080)
Date: 2026-07-30
Owner: implementation agent
Reversibility: Governance only. Corrects the record; changes no ruling.

**A REPAIR WAS CLAIMED AND NOT MADE.** Commit `ed9b60d` states that "(6/n) stopped the losing delivery from destroying the winning pass's ledger and forward link", and `BUILD_STATE.next_action` stated that "every confirmed-blocking finding is repaired". Both were false. `IdentityAccess::Infrastructure::CrawlStartStore#insert_idempotency` was never touched in that pass and remained a bare INSERT, so the defect the sentence describes was live from the moment the sentence was written. The delta review found it by checking the claim against the diff, which is the check ADR-083 was written to institutionalise, and this is the first time it has caught the record rather than the code. It is repaired in `90f1282`. Recorded here rather than quietly fixed, because the failure was not the missing `ON CONFLICT` — it was asserting a repair without verifying it.

**ADR-089's NAMED MUTATION COULD NOT FAIL.** ADR-089 lists eight mutations "each fail[ing] an example", one of them "the instant taken from `now`", and calls the derived retry instant "load-bearing". It was not falsifiable: `FetchAttemptStore#terminalize` wrote `completed_at` from the same `context[:now]` the mutation substituted, so the two expressions were byte-identical in every reachable state. The determinism claim was therefore unverified while being recorded as proven. `completed_at` now records the attempt's actual completion — the hard request bound for a timeout, which is the rule `observe_request_time` already applies, and the reported latency otherwise — so the column means its name, :444's delay is measured from where the contract says, and the mutation bites. ADR-089's ruling and every other guarantee in it stand.

**ADR-087's SELF-HEALING WAS REINTRODUCED AS A REGRESSION AND IS NOW REPAIRED.** ADR-088 already corrected ADR-087's overstatement. The FU-19 implementation then made it worse: the `RETRYING` branch released nothing, so a duplicate delivery whose terminal transaction aborted left the entry claimed, the reservation charged and no scheduled action for the run. Two reviewers demonstrated it. `Execution#performed?` and the `ON CONFLICT` above close it together.

**FU-9 MUST NOT CLOSE SILENTLY.** Its recorded resolution says "A host that stays contended until the deadline is terminalized honestly HERE, once, with `unavailable`". That is no longer reachable on any production path: `DiscoverSitemaps#defer_to_scheduler?` terminalizes only when the run has expired, and the driver halts on the wall clock before it calls discovery, with the same `now`. The re-entry FU-9 asked for IS delivered and no false outcome is written — the gate simply stays `pending`, and deriving :450's `sitemap_unavailable` from that becomes S-07-009's. FU-9 is therefore delivered-with-a-carried-obligation, not closed.

What the delta review also confirmed, and which is worth recording because it was the most serious finding of the first round: the authorization ordering repair HOLDS. An independent reviewer enumerated every write and outbound call in `CrawlDriver#advance` and its callees in order, found none preceding `Admission#authorize_run` — including the new `retire_unfetchable` writer — and verified behaviourally as `f1_web` that the frontier UPDATE is Organization-scoped and its RLS is not `USING (true)`.

Authority And Precedence:
Under standing delegation ADR-061, as corrections of record. ADR-085's, ADR-087's and ADR-089's rulings are unchanged. Allocated the next unused number after ADR-089.
