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

FU-11's diagnosis was corrected twice and both corrections are recorded. The third pass prescribed a NULL-safe rewrite of `crawls_coverage_status_check`. **THE REASON RECORDED HERE FOR SETTING THAT PRESCRIPTION ASIDE WAS ITSELF FALSE, and is corrected in place at ADR-115** (round 2 found ADR-111 had corrected five other places and missed this one, which is the first a reader tracing FU-11's history reaches). What is true: rewriting to the shape PROOF 29 evaluates — `x IS NULL OR x = ANY(...)` — IS a genuine no-op, because a CHECK admits both the UNKNOWN that `NULL = ANY(ARRAY['full','partial'])` yields and the TRUE that one yields. What is false as first written: the `IS NOT DISTINCT FROM` spelling the third pass NAMED is not admitted and is not a no-op. Its `ANY(...)` form is a PostgreSQL SYNTAX ERROR, and its only valid spelling — the pairwise `NULL IS NOT DISTINCT FROM 'full' OR NULL IS NOT DISTINCT FROM 'partial'` — evaluates to FALSE, not UNKNOWN, which a CHECK REFUSES: applying it would have rejected every `queued` and `running` Crawl, since those rows carry NULL in that column by design. NULL must be tested independently, because UNKNOWN is admitted and FALSE is not, and a proof that conflated them would pass on either. Applying the prescribed spelling would therefore not merely have produced a diff and left the hole open; it would have been a breaking change. PROOF 104 pins all four evaluations. The fault is in `crawls_terminal_shape`, whose terminal limb requires only `terminal_at IS NOT NULL`. The fourth pass then corrected the repair itself: requiring both columns on every terminal state would break `IdentityAccess::Infrastructure::CrawlStartStore#fail`, because a failed run carries a completion reason and no coverage. The conjunct must be scoped by state. It remains BLOCKING for S-07-009 and is not repaired here.

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

## ADR-091: FU-24 Resolved — A Fenced Scheduled-Action Lease Heartbeat, Not A Permanently Longer Lease

Status: Accepted (owner decision, 2026-07-30; recorded by the implementation agent from the owner's ruling)
Date: 2026-07-30
Owner: owner ruling on FU-24
Reversibility: Integration branch only; `main` untouched. One additive transport function; the schema builds from empty and `db/structure.sql` carries it and nothing else.

The defect. `Platform::ScheduledActions::Worker::WORKER_LEASE_SECONDS` is 30 with no heartbeat, and legitimate work exceeds it by two routes ADR-089 did not close: one content attempt is bounded PER HOP, so the initial request plus the ratified 10-redirect budget is 11 connections at the 15-second hard timeout, and `Workflows::Wf005::DiscoverSitemaps` paces :444's 30 and 120 seconds between sitemap candidates. `Platform::BackgroundExecution.run_scheduler` recovers expired leases every pass, so a LIVE worker's action was returned to `pending` and executed twice.

THE RULING: a fenced heartbeat. ~~`WORKER_LEASE_SECONDS` stays short so a genuinely dead worker is recovered promptly~~; a live worker renews while it still owns legitimate work. A permanently longer lease was rejected for the right reason: it has to be sized for the worst legitimate case, so it hides duplicate execution by making every real recovery slower by exactly that amount.

> **BOUNDED BY ADR-094 AND ADR-095.** The struck clause no longer describes the built system, and the cost this paragraph weighed IS NOW INCURRED — which is recorded here rather than left to be discovered. `WORKER_LEASE_SECONDS` is now only the lease a caller REQUESTS; the duration is derived per :288 from the row's `product_attempt_deadline`, so for `crawl_fetch_due` a dead worker is recovered in up to the 15-minute cap rather than in 30 seconds. What ADR-091 rejected was sizing every lease for the worst case of any handler. What ADR-094 adopted is sizing EACH lease for the worst case OF ITS OWN ratified deadline, which is a different thing and is bounded by the cap; the ruling's reasoning survives, its factual clause does not.

**THE FENCE IS THE FEATURE.** The owner's correction is recorded because it is the whole difference between this and a worse race: an unconditional `UPDATE ... WHERE id = ?` would let a worker whose claim had already transferred silently extend the NEW owner's lease and resurrect its own. `f1_heartbeat_scheduled_action` therefore matches, in one statement on one row by primary key: the action identity; the claim owner, which is the worker's fencing token; the claim generation, which every reclaim increments; the expected executable state `dispatched`; and A LEASE THAT HAS NOT ALREADY LAPSED. That last predicate is the supersession check — once `lease_expires_at` is in the past the row is the sweep's to take, so a worker that has lost its window may not extend it.

**ON AN ORGANIZATION IDENTIFIER**, which the owner asked to be assessed rather than assumed: it is not added, and it would fence nothing. `scheduled_actions` is a transport table served by one scheduler across every tenant, the ratified transport functions are `SECURITY DEFINER` and take no organization, and the row's own `organization_id` is immutable under the guard. Ownership is established by `(claim_owner, claim_generation)`, a genuine token pair; an organization argument would assert a value the caller just read from the row it is renewing, and a caller able to pass the wrong token is equally able to pass the wrong organization. Tenant isolation on this path is the transport connection's, exactly as for claim, dispatch, settle and release. The function also takes NO TIME ARGUMENT, matching every current transport function, because :114 makes PostgreSQL transaction time the sole lease authority and a caller-supplied instant is a way to lie about when a lease should end.

**BOUNDED CADENCE.** Renewal is driven by ELAPSED TIME at a third of the lease, never by loop iterations, so heartbeat writes are bounded by how long work takes and not by how many redirects, sitemap candidates or fetches it performs. `renew_if_due` is safe to call at every boundary precisely because calling it more often does not write more often — 500 calls inside one interval produce zero writes.

**FAIL CLOSED ON A CONFIRMED ANSWER, AND ONLY THEN.** A renewal returning false is the database saying ownership moved, and the delivery stops at its next safe boundary: no further request, no attempt, no bytes, no terminal frontier state, no forward link and no ledger. A renewal that RAISES is a transport failure and says nothing about ownership — treating it as loss would abandon work the worker still owns, treating it as success would ignore a real transfer — so it is neither: the state stays held, the failure is counted, and the lease's own expiry remains the backstop. ~~The action is not settled either, and does not need to be: `f1_settle_scheduled_action` is already fenced on owner and generation, so a stale worker's settle matches zero rows.~~

> **CORRECTED BY ADR-092.** The struck sentence is FALSE — `f1_settle_scheduled_action` carries no lease predicate at all — and the paragraph's first sentence described an intent the implementation did not yet meet on the robots and sitemap paths. Both were demonstrated by review. Read this paragraph only through ADR-092.

**NO UNINTERRUPTIBLE GAP, AND THE PRODUCT INSTANT DOES NOT MOVE.** `LeaseKeeper#wait` divides a 30- or 120-second product wait at heartbeat deadlines against a MONOTONIC deadline fixed before the first sleep, so wake-ups neither shorten nor lengthen the interval WF-005 requires. No database connection is held while waiting. ~~Between redirect hops the renewal happens in the guard F-01 already calls per hop, so the frozen connector is untouched.~~

> **CORRECTED BY ADR-092.** True of the content path only. Robots and sitemap fetches passed no `redirect_guard` at all while still following the ten-redirect budget, so each was up to eleven bounded requests behind ONE renewal. Measured: 165 seconds, zero heartbeat writes, sweep reclaims.

**ONE IMPLEMENTATION FOR EVERY WORK TYPE.** `Lease` is set by the Worker around one handler invocation and read by product code at boundaries it already has; no workflow implements lease logic, and there is no crawl-fetch heartbeat separate from a sitemap one.

Proof standard. Eight properties proved against the real transport function and real rows: renewal by the owner; work exceeding the lease staying owned with no sweep able to take it; cadence following elapsed time rather than call count; a stale worker refused after transfer, changing nothing; renewal and recovery serializing to exactly one owner; ~~recovery at the ORDINARY lease rather than a worst case~~ (SUPERSEDED BY ADR-095: recovery is at the action's OWN derived lease, which is :288's 60-second floor for a kind that stamps no deadline and up to the 15-minute cap for one that does; PROOF 3 was corrected rather than left asserting the flat 30); a divided wait whose total is unchanged and which holds no connection; and a transport failure leaving ownership held. Eleven mutations; ten fail an example or fail to terminate. TWO SURVIVE AND ARE RECORDED RATHER THAN DRESSED UP: the `status = 'dispatched'` predicate and `renew`'s early return on a already-lost keeper are both redundant with the owner/generation fence in every reachable state — a non-`dispatched` row never carries the worker's owner — so they are defence in depth and an avoided write, not controls with independent force.

> **SUPERSEDED BY ADR-092.** This proof standard was met and was still not sufficient: every property above was proved at the KEEPER, and none of them asked whether the product paths reached a boundary at all. Two independent reviews found blocking defects the eight proofs could not see. ADR-092 records what was added and what remains unproved.

Authority And Precedence:
Owner decision on the evidence of the S-07-012 delta review. Supersedes nothing in ADR-089, which closed the :444 in-process-retry route; ADR-084's rule that a frozen foundation remains an owner decision is what made this an escalation rather than a repair. `lib/f1/runtime_grants.rb` gains one additive least-privilege function grant under the Foundation Consumption Rule, exactly as ADR-027 established. Allocated the next unused number after ADR-090.

## ADR-092: Corrections Of Record Forced By The Second FU-24 Review, And Two Ratified Rules I Have Not Implemented

Status: Accepted (implementation agent, under ADR-084 blocking-defect repair authority; the two deviations below are ESCALATIONS, not repairs)
Date: 2026-07-30
Owner: implementation agent, correcting ADR-091
Reversibility: Integration branch only; `main` untouched. No schema change; the repairs are workflow-level and one new method on `Platform::ScheduledActions::Lease`.

Two independent focused reviews of the FU-24 heartbeat each returned BLOCK. ADR-091 was written before either, and parts of it are false. This records what was wrong, what is now true, and what remains undone — because the failure mode of the first heartbeat was precisely a document that asserted properties the code did not have.

**CORRECTION 1 — THE SETTLE CLAIM WAS FALSE, AND IT WAS THE REASON FOR A REAL DEFECT.** ADR-091 stated "the action is not settled either, and does not need to be: `f1_settle_scheduled_action` is already fenced on owner and generation, so a stale worker's settle matches zero rows." That function carries NO lease predicate. In the window between a lease lapsing and the sweep running, the row is still `dispatched` under that owner and generation, so the settle MATCHES: the action completed having done nothing — no attempt, no ledger, no successor — and the crawl hung `running`. The false sentence is not incidental; it is the stated justification for omitting the release path, so the document caused the defect. `Worker#run_handler` now routes the lease-lost reason to `release`, which is :297's ratified recovery, and PROOF 10/11 demonstrate both halves against the real functions.

**CORRECTION 2 — THE HEARTBEAT DID NOT BEAT ON THE ORDINARY PATH.** ADR-091 stated that "between redirect hops the renewal happens in the guard F-01 already calls per hop". That was true of the content fetch and of nothing else. `EnsureRobots#fetch` and `DiscoverSitemaps#fetch` passed `max_redirects: 10` and NO `redirect_guard`, and F-01 takes a fresh deadline per hop, so each was up to eleven bounded requests — 165 seconds of request time, more with the per-hop resolver timeout — behind a single renewal under a 30-second lease. The reviewer measured it: two fetches, 165 seconds, ZERO heartbeat writes, then the real expired-lease sweep reclaiming the action underneath a live worker, which is the exact double-execution FU-24 exists to prevent. `Platform::ScheduledActions::Lease.redirect_guard` is now the single per-hop boundary and all three crawl fetch sites pass it; callers with their own per-hop policy compose through it rather than reimplementing lease handling.

**CORRECTION 3 — "NO TERMINAL FRONTIER STATE" WAS AN INTENT, NOT A PROPERTY.** A delivery with confirmed ownership loss still ran the sitemap traversal to completion: the `break`s in `fetch_paced` and `fetch_once` left only their own inner loops, so the traversal moved to the next candidate, requested it, spent the run-wide document budget, offered its content URLs to the frontier, and returned a terminal state that `DiscoverSitemaps#call` wrote to the WRITE-ONCE gate outcome — because `defer_to_scheduler?` is false when no `sitemap_gate_deferred` skip was recorded. Demonstrated. The traversal now ends at its next iteration and `call` reschedules above the FU-9 check, so a transferred delivery hands the claim back exactly as a contended one does. The same class of defect existed on the robots path in a worse form, since every robots terminal state is write-once and most are fail-closed: a guard-refused hop arrives as a plain rejection, which `classify` would have read as a permanent `robots_unavailable_fail_closed` decision for the whole run. `EnsureRobots#call` now relinquishes above `record`.

**CORRECTION 4 — THE PROOF STANDARD WAS MET AND WAS NOT SUFFICIENT.** All eight ADR-091 proofs were real and all eight passed while every defect above was live, because each proved a property of the KEEPER and none asked whether the product paths reached a boundary at all. Four proofs are added at the level where that is answerable: PROOF 12 drives the REAL `GuardedHttpClient` through a four-hop chain and counts renewals per hop; PROOF 13 confirms a transfer mid-chain refuses the next hop; PROOF 14 and PROOF 15 drive the real `EnsureRobots` and the real `DiscoverSitemaps` traversal under a genuine dispatched lease taken away by the ratified sweep, and assert that NOTHING is written. Each fails under a mutation of the line it covers. PROOF 15 uses TWO sitemap candidates deliberately: with one candidate the traversal has no next iteration and the boundary is not load-bearing, which is exactly why the single-candidate mutation survived the previous round and was recorded as untestable. It was testable; the test was merely not written, and calling that a limitation was wrong.

**TWO RATIFIED RULES ARE NOT IMPLEMENTED, AND THAT IS RECORDED HERE RATHER THAN DISCOVERED LATER.** BACKGROUND_PROCESSING.md :288-290 already ratifies this mechanism, which the first implementation approximated instead of reading — the interval rule is now implemented exactly (a third of the lease, floored, bounded 5 through 30) but two clauses are not:

- **:288's lease duration.** "Lease duration is `max(30 seconds, product_attempt_deadline - claim_time + 30 seconds)` capped at 15 minutes." `Worker::WORKER_LEASE_SECONDS` is a flat 30 with no reference to any product deadline. This is a change to the lease semantics of every work type, which is an owner decision under the standing stop conditions, not a repair. It is FU-25. ~~It is no longer load-bearing for the defects above — the per-hop boundary closes the unguarded window whatever the lease length —~~ but it remains an unimplemented ratified rule, and while it is unimplemented the `interval` clamp's degenerate case (a lease of 5 seconds or less renews exactly at expiry) is unreachable only by accident.

- **:290's authorization checkpoint.** "A heartbeat transaction verifies owner, claim generation, nonterminal state, CURRENT AUTHORIZATION/POLICY CHECKPOINT, and unexpired lease." Four of the five are implemented; the authorization/policy checkpoint is not — the function never consults the executing Service Identity or a policy version. That is authorization semantics, which is an owner decision. It is FU-26.

> **THE STRUCK CLAUSE IN THE FIRST BULLET: CORRECTED BY ADR-093, SUPERSEDED BY ADR-094 AND ADR-095.** It is FALSE and was DEMONSTRATED false. The per-hop boundary does not close the unguarded window, because one ratified hop is itself up to 30 seconds — F-01 takes the resolver timeout OUTSIDE the per-hop deadline — and there is no boundary INSIDE a single hop at which to renew. It is struck IN PLACE rather than corrected only at a distance, because ADR-093 named this exact pattern, a false claim standing as the justification for an omission, as the finding rather than the individual sentence; a reader of ADR-092 alone would otherwise still take it as established. Two further notes for the record: ADR-093 referred to it as the "no longer load-bearing FOR CORRECTNESS" sentence, and those words are not in it — the sentence is as struck above; and the bullet's quotation of :288 preserves the 30-second floor the document carried at the time, which ADR-095 has since corrected to 60.

**ONE JUDGEMENT, MADE EXPLICIT.** :290 says a heartbeat "never increments a product state version". `f1_heartbeat_scheduled_action` does `state_version = a.state_version + 1` on `scheduled_actions`. That is the TRANSPORT row's version, not a product state version; `lock_version` is untouched, no event or outbox row is written, and `due_at`/`not_before_at` are immutable under the row guard. I read this as within the prohibition. It is recorded because it is a reading, not a fact, and because a reviewer flagged that the column consequently stops being a count of state transitions.

Authority And Precedence:
Corrections 1-4 are repairs of confirmed blocking defects under ADR-084 and are made without escalation. FU-25 and FU-26 are NOT repairs and are not made: both change ratified semantics owned by the owner, and are recorded as open follow-ups with their exact clause references. Supersedes the struck sentences in ADR-091 and its proof-standard paragraph; nothing in ADR-089 or ADR-091's ruling is changed. Allocated the next unused number after ADR-091.

## ADR-093: The Third FU-24 Review — Two Repairs Taken, One Defect Escalated, And A Second False Justification Of Mine Corrected

Status: Accepted for the two repairs (ADR-084 blocking-defect authority); ESCALATED for the third, which is not mine to take
Date: 2026-07-30
Owner: implementation agent, correcting ADR-092
Reversibility: Integration branch only; `main` untouched. No schema change; one new store method and one classification branch.

The third independent focused review of the FU-24 heartbeat returned BLOCK with three findings, all demonstrated against the real database and the production WF-005 chain. Two are repaired here. The third is an architectural stop condition and is escalated as FU-25.

**REPAIRED — A CONFIRMED LEASE TRANSFER WAS RECORDED AS A POLICY EXCLUSION.** `Lease.redirect_guard` refuses a hop before the caller's authorization limb runs, so `FetchContent`'s `@guard_failed` stayed false and F-01's `redirect_policy_denied` was indistinguishable from a genuine scope denial. The result was a committed `fetch_attempt` reading `policy_excluded / redirect_policy_denied / retryable = f` for a URL nothing had refused — permanently OUTSIDE :452's coverage denominator, so coverage read better than reality on the strength of a decision the delivery had no standing to make. `@guard_failed` exists precisely to stop a non-policy fact being filed as a policy fact; a lease transfer is even less a policy fact than a database error. `transport_outcome` now classifies it as `redirect_check_unavailable`, retryable and in the denominator. PROOF 17; the mutation restores `policy_excluded`.

**REPAIRED — MY COMPARE-AND-SET FENCE DID NOT EXIST.** ADR-092 introduced `EnsureRobots#relinquish` and I wrote, in the code comment and in the BUILD_STATE note, that it was "compare-and-set on `state_version` under the row lock, so a gate the new owner has already moved matches zero rows". False. `defer_robots` fences on a `state_version` that `relinquish` re-reads under the row lock IN THE SAME TRANSACTION, so it can never fail against another owner; its only effective predicate was `robots_state = 'in_progress'`, which does not distinguish this worker's claim from a successor's. Demonstrated: a worker whose claim had legitimately been taken over under `begin_robots`' 300-second stale branch reverted the takeover, discarded a successful 200 robots response, and left two of :444's three attempts burned on a healthy host. `relinquish_robots` now fences on `robots_generation`, which `begin_robots` increments on every claim including the takeover, so it identifies the ATTEMPT rather than the row. PROOF 18; the mutation restores the clobber. The same unfenced shape exists on the pre-existing :444 retry limb and is recorded as FU-27 rather than swept in.

**ESCALATED — THE LEASE CANNOT SURVIVE ONE RATIFIED HOP, AND MY JUSTIFICATION FOR DEFERRING :288 WAS FALSE.** ADR-092 recorded :288's lease-duration rule as unimplemented and asserted that it was "no longer load-bearing for correctness" because the per-hop boundary closes the window "whatever the lease length". That is false and was demonstrated false. `GuardedHttpClient#attempt` takes the resolver timeout — clamped to `Ceilings::DNS_TIMEOUT_MAX_S` = 15 seconds — OUTSIDE the per-hop `deadline = monotonic + policy.timeout_s` of 15 seconds, so one ratified hop is up to 30 seconds: equal to the entire lease and three times the heartbeat interval. Measured: a single 30.5-second request lapsed the lease under a live worker with `last_heartbeat_at` still NULL and a valid robots response thrown away. The per-hop boundary took the exposure from ~165 seconds to ~30; it did not close it. The invariant that must hold is `lease_seconds > interval + max_hop_seconds`, and a flat 30 fails it while :288's ratified rule satisfies it.

**THIS IS THE SECOND TIME A FALSE SENTENCE OF MINE HAS STOOD AS THE JUSTIFICATION FOR AN OMISSION**, after ADR-091's settle claim. Both were reasoning I did not test, written in the register of something established. The pattern is the finding, not the individual sentences: where an ADR explains why something need NOT be done, that explanation is load-bearing and must be proved or marked unproved.

Why the third finding is not repaired here. `WORKER_LEASE_SECONDS` is F-04, a frozen foundation, which ADR-084 condition 4 reserves to the owner, and lease duration is a standing stop condition because it changes recovery latency and the contention profile of EVERY work type rather than the crawl path alone. The owner's FU-24 ruling also expressly rejected "a permanently longer lease" as an alternative to the heartbeat; whether implementing :288's ratified duration rule alongside the heartbeat falls inside that ruling is the owner's call. Forcing an unconditional renewal at each boundary was considered and rejected as insufficient: it leaves the gap at exactly the lease.

Authority And Precedence:
The two repairs are confirmed blocking defects under ADR-084 and are taken without escalation. FU-25 is escalated and S-07-012 is NOT accepted while it stands. Supersedes ADR-092's "no longer load-bearing for correctness" sentence and its FU-25 note; corrects the fence claim in ADR-092's Correction 3. Adds FU-27. Allocated the next unused number after ADR-092.

## ADR-094: FU-25 Resolved — :288's Derived Lease Duration, And The Heartbeat Named As Transitional

Status: Accepted (owner decision, 2026-07-30; recorded by the implementation agent from the owner's ruling)
Date: 2026-07-30
Owner: owner ruling on FU-25
Reversibility: Integration branch only; `main` untouched. One additive nullable column and a rewrite of the lease expression inside two existing transport functions; the schema builds from empty and `db/structure.sql` carries it.

The defect. `WORKER_LEASE_SECONDS` was a flat 30 seconds while ONE ratified redirect hop is up to 30: `GuardedHttpClient#attempt` takes the resolver timeout — clamped to `Ceilings::DNS_TIMEOUT_MAX_S` = 15 — OUTSIDE the per-hop `deadline = monotonic + policy.timeout_s` of 15. A heartbeat cannot save that, because there is no boundary inside a single hop at which to renew. Measured: one 30.5-second request, `last_heartbeat_at` still NULL, lease lost under a live worker, a valid `robots.txt` discarded — and because the pass now correctly relinquishes rather than deciding, every redelivery repeated it, so such a host could never be resolved inside the run's wall clock.

**THE RULING: IMPLEMENT THE RATIFIED RULE, NOT A TUNED NUMBER.** The owner's reasoning is recorded because it is the architectural point and not merely the choice. "The lease is smaller than one ratified redirect hop" means the heartbeat was compensating for a broken invariant. Heartbeats are the correct answer when work duration is genuinely unpredictable; this work is not, because the redirect budget, the per-hop timeout and the attempt deadline are all already ratified. Where a bound is derivable from the contract, ownership should be established BY CONSTRUCTION — "ownership is valid for exactly as long as the specification says legitimate work can exist" — rather than maintained by renewal. That is a stronger invariant, and it removes heartbeat traffic, renewal races, cadence tuning and a class of "did the renewal land before expiry?" question altogether.

**THE SHAPE.** The PRODUCER stamps `scheduled_actions.product_attempt_deadline`; transport does the arithmetic. `scheduled_actions` is a transport table served by one scheduler across every tenant and must not interpret product state — a claim function reaching into `crawls` would couple F-04 to WF-005 and to every future work type. `crawl_fetch_due` stamps the run deadline, which :442 already makes the bound on the execution and which `CrawlFetchDueSchedule#link` already resolves to clamp `due_at`. NULL means no product deadline and yields the caller's floor, so every kind that does not stamp one behaves exactly as before. The column is immutable under `f1_scheduled_actions_guard`: a deadline rewritable after the fact would be a way for a worker to widen its own ownership, which is precisely what the fence exists to prevent.

**A GATE CAUGHT A REAL SHAPE DEFECT AND WAS NOT WORKED AROUND.** The derivation was first extracted into a helper function, which is the obvious way to keep one source of truth across the claim and dispatch paths. `spec/platform/scheduled_actions/store_spec.rb` failed it, because any `%scheduled_action%` function accepting a `timestamptz` violates :114's rule that PostgreSQL transaction time is the sole due-time and lease authority — a function that accepts an instant is a way for a caller to lie about time. The gate was right. The arithmetic is inlined in both transport functions instead, written from one string in the migration, which keeps the single source of truth without adding a grantable surface to a table whose whole posture is that only `f1_platform_worker` may transition it.

**THE HEARTBEAT IS NOW EXPLICITLY TRANSITIONAL.** The owner's second ruling is as important as the first. :288 ends "A handler whose work can legitimately exceed 15 minutes divides it into checkpointed members; no individual claim exceeds the cap" — and one `crawl_fetch_due` pass can exceed it by far: robots, then a traversal bounded at 50 documents each with up to 3 attempts of ~30 seconds of hop time, then one content attempt. Ignoring :444's paces entirely that is 75 minutes against a 15-minute cap. Divided so one execution performs at most one bounded outbound unit, the worst case per claim is one document and the derived lease covers it by construction, at which point `LeaseKeeper`, `Lease`, `f1_heartbeat_scheduled_action` and every renewal boundary are DELETED rather than maintained. That division is FU-28 and is sequenced as its own tranche, for the reason the owner gave: it changes the UNIT OF EXECUTION rather than fixing a defect, and it invalidates accepted S-07-005/006 proofs that assert a full traversal in one call. Where accepted proofs become invalid the work is a redesign, not a repair, and it deserves its own acceptance history and its own architectural review instead of being smuggled into the acceptance of S-07-012. The heartbeat is a bridge; ADR-094 records that it must not become a destination.

Proof standard. PROOF 19 — the lease is derived, floored and capped, exercised at four points (an hour out takes the 900-second cap; two minutes out takes 150; a past deadline and a NULL both take the 30-second floor), and three of those four are values a flat lease cannot produce. PROOF 20 — the invariant `lease > interval + max_hop` holds for the derived lease and demonstrably FAILS for the flat 30, with `max_hop` computed from `Ceilings::DNS_TIMEOUT_MAX_S` and the ratified request timeout rather than written as a literal. PROOF 21 — the deadline is immutable, so ownership cannot be widened after the fact. PROOF 22 — the producer stamps it end to end over the production-real chain, and states plainly what it cannot show: the fixed 2026-07-27 test clock is behind `transaction_timestamp()`, so that fixture's deadline is genuinely past and correctly takes the floor. Mutation M16 removes the stamp and fails PROOF 22.

> **THIS PROOF-STANDARD PARAGRAPH IS CORRECTED BY ADR-095, AND THE CORRECTION IS THE POINT.** Three of its claims did not survive the focused review of the committed state.
>
> 1. **"the invariant holds for the derived lease" was FALSE OF THE PRODUCTION PATH.** PROOF 20 constructed a `LeaseKeeper` with the derived value. `Worker#lease_keeper_for` never does: it passes `WORKER_LEASE_SECONDS`. The example proved the invariant for a configuration that does not exist at runtime, and it passed while the defect below was live.
> 2. **THE DERIVATION WAS IMPLEMENTED IN TWO OF THREE LEASE WRITERS.** `f1_heartbeat_scheduled_action` was not changed and still wrote the caller's flat value, so ten seconds into a handler the first renewal COLLAPSED a 900-second derived lease to 30 and restored the exact defect ADR-094 was written to close. No behavioural example noticed, because none observed `lease_expires_at` after a heartbeat.
> 3. **"capped at 15 minutes" DESCRIBED THE RULE, NOT THE CODE.** The cap was written `greatest(interval '15 minutes', <caller request>)`, which above 900 seconds is not a cap: a caller passing 3600 received 3600. Harmless only because both callers pass a literal 30.
>
> The 30-second FLOOR this paragraph reports as correct behaviour is also now superseded: it could not satisfy the invariant it claims, and ADR-095 raises it to 60. ADR-094's RULING stands unchanged and is not reopened — the derived lease is right, the producer stamping it is right, and the reasoning about ownership by construction is right. What was wrong was the claim that it was fully implemented and fully proved. Corrected in place rather than rewritten, because an acceptance that quietly repaired its own proof record would be the same failure this ledger keeps catching.

Authority And Precedence:
Owner decision on the evidence of the third focused review. Resolves FU-25 and opens FU-28. Supersedes ADR-092's deferral of :288's lease-duration rule and ADR-093's escalation of it. ADR-091's ruling that a fenced heartbeat is preferable to a permanently longer lease stands for what it decided — this is not a permanently longer lease but the specification's own derivation — and is now bounded in time by FU-28. Allocated the next unused number after ADR-093. **AMENDED BY ADR-095**, which completes the implementation across the third lease writer, makes the cap absolute, corrects :288's floor, and reopens FU-25 until the repaired live behaviour is proved.

## ADR-095: The Lease Rule Made Coherent — The Third Writer, The Absolute Cap, And A Corrected Ratified Floor

Status: Accepted (owner ruling, 2026-07-30; recorded by the implementation agent from the owner's ruling)
Date: 2026-07-30
Owner: owner ruling on the focused review of 0de3f3e
Reversibility: Integration branch only; `main` untouched. One migration rewriting the lease expression inside three existing transport functions. No column, signature, grant, RLS policy or return shape changes. The schema builds from empty and `db/structure.sql` carries it.

**HOW THIS WAS FOUND, WHICH MATTERS AS MUCH AS WHAT WAS FOUND.** ADR-094 was recorded as resolving FU-25, with four proofs and a green suite. A focused review of the committed state — three independent reviewers, run because ADR-080 admits no acceptance until the lenses have reported on the state being accepted — returned BLOCK from all three, converging by different routes on one defect. The suite was green throughout. Every example that could have caught it restated the implementation's own numbers back to itself.

**DEFECT 1: THE DERIVATION WAS IMPLEMENTED IN TWO OF THE THREE FUNCTIONS THAT ASSIGN A LEASE.** `20260727120320` changed `f1_claim_due_scheduled_actions` and `f1_dispatch_scheduled_action`. It did not change `f1_heartbeat_scheduled_action`, which kept `lease_expires_at = v_now + make_interval(secs => greatest(p_lease_seconds, 1))` — and `Worker#lease_keeper_for` passes `WORKER_LEASE_SECONDS` = 30 to it. `Lease.owned?` renews on cadence and `Lease.redirect_guard` renews per hop, both reached inside ten seconds of an ordinary `crawl_fetch_due` handler. So a pass dispatched with a 900-second derived lease had it rewritten to 30 before its first slow hop, and from that instant the system was byte-for-byte in the state FU-25 was raised to repair: `30 > 10 + 30` is false, one 30.5-second hop lapses the lease under a live worker, the pass relinquishes, and every redelivery repeats it. THE RECORD SAID THE DEFECT WAS CLOSED. It was closed on two paths out of three, and the third was the one the worker actually takes.

**DEFECT 2: THE CAP WAS NOT A CAP.** It was written `greatest(interval '15 minutes', make_interval(secs => greatest(p_lease_seconds, 1)))`, so the ceiling rose to whatever the caller requested. Measured: `p_lease_seconds = 3600` yielded a 3600-second lease, four times :288's cap, during which a stuck worker holds the row against every recovery mechanism. Unreachable today only because both production call sites pass a literal 30 — sound by accident of current values, while ADR-094 and FU-25 both described an unconditional cap. That is the same shape as defect 1: a record describing a property the code does not have.

**DEFECT 3: :288'S OWN 30-SECOND FLOOR WAS INTERNALLY INCONSISTENT, AND THE RULING CORRECTS THE RATIFIED CONSTANT.** A lease must satisfy `lease > interval + max_hop`, where `interval` is :288's own one-third cadence and `max_hop` is F-01's resolver timeout (`Ceilings::DNS_TIMEOUT_MAX_S` = 15, taken OUTSIDE the per-hop deadline) plus the ratified hard request timeout (15). At the 30-second floor that reads `30 > 10 + 30`, which is false — so a lease held AT THE RATIFIED FLOOR could not survive one ratified hop. This is reachable rather than theoretical: the derived lease falls to the floor near a run deadline, because `CrawlFetchDueSchedule#link` clamps `due_at` to it, and for every action kind that stamps no `product_attempt_deadline` at all. THE OWNER'S RULING: correct the defective constant to 60 (`60 > 20 + 30`) rather than preserve a proof that is mathematically false. `specification/volume-ii/BACKGROUND_PROCESSING.md` :288 is amended in place with the reasoning attached, and the sentence "The cap is absolute: no caller-supplied lease request may exceed it" is added, because the first implementation showed that leaving it implied was enough for it not to be built.

**THE SHAPE OF THE REPAIR.** One canonical expression, written into all three functions from a single string in the migration:

```text
least(greatest(caller_request, 60 seconds, product_attempt_deadline - v_now + 30 seconds), 15 minutes)
```

`v_now` is `transaction_timestamp()` in every case, so :114's rule that PostgreSQL transaction time is the sole lease authority is unchanged. The deadline is the immutable stored column, so no caller supplies an instant. The caller argument survives as a FLOOR only: it can no longer raise the ceiling, and at 30 it is now dominated by the 60-second floor and therefore inert — kept so the contract does not silently narrow. There is deliberately NO monotonic `greatest(a.lease_expires_at, ...)` guard on the heartbeat: the derived value SHRINKS as `v_now` approaches the deadline, and that is correct, because ownership must be valid for exactly as long as legitimate work can exist and no longer. A monotonic guard would let ownership outlive the deadline it derives from.

**WHAT IS DELIBERATELY NOT REPAIRED HERE, AND WHY.** :288 ties the heartbeat interval to THE LEASE DURATION; `LeaseKeeper` divides `WORKER_LEASE_SECONDS` instead, because `f1_dispatch_scheduled_action` does not return the lease it set and the worker has no way to learn it. Closing that means changing the return shape of a frozen transport function, `F1::RuntimeGrants`, and the store's row mapping together. It is deferred as FU-29 rather than swept in, and the deferral is SAFE IN A NAMED DIRECTION: dividing 30 yields a 10-second interval against a lease of at least 60, so the worker renews more often than :288 requires and never later. A conservative cadence is a cost, not a correctness gap.

Proof standard. PROOF 19 — derived, floored and capped at five points, including the near-deadline region that made the 30-second floor a live defect. PROOF 20 — the invariant `lease > interval + max_hop` asserted across EVERY value the rule can produce, 60 through 900, not at one convenient point, with `max_hop` computed from the ratified ceilings; and the superseded floor of 30 asserted to FAIL it, so the defective constant cannot be restored silently. PROOF 21 — the deadline is immutable. PROOF 23 — the heartbeat DERIVES: a dispatched action with an hour-out deadline still holds ~900 seconds after a real renewal through the real function, which is the defect above, closed. PROOF 24 — the cap is absolute in all three writers: a caller requesting 3600 receives 900, with and without a product deadline, at claim, at dispatch and at heartbeat. PROOF 25 — all three writers carry ONE expression byte for byte, extracted from `pg_proc`; this is the structural proof, and it is the one that would have caught the original defect. `spec/architecture/scheduled_action_lease_rule_spec.rb` additionally parses :288's own sentence and fails if the database drifts from the document's numbers, or if the cap is ever expressed as anything but the outer bound.

Five mutations, each applied to the live functions and each failing a named example: the heartbeat writing the flat caller value (fails PROOF 23 at 30 seconds, exactly as measured in production); the heartbeat ignoring the stored deadline (fails PROOF 23 at 60); the outer `least` becoming a `greatest` (fails PROOF 19, PROOF 23 and the outer-bound check at 3630 seconds); the floor returning to 30 (fails PROOF 19, PROOF 22 and the document-conformance check); and the heartbeat permitted to shorten a derived lease to the worker constant (fails PROOF 23 and the drift check). PROOF 3 and the `lease_keeper_spec` header were CORRECTED rather than left standing, because both asserted recovery "within `WORKER_LEASE_SECONDS`", which is no longer true of any action kind.

Authority And Precedence:
Owner ruling on the focused review of 0de3f3e. Not a new architectural decision: ADR-094 already ruled the lease is derived, and this implements that ruling at the third writer it missed. Amends ADR-094's proof-standard paragraph, which claimed a completeness the code did not have; strikes in place the false clause in ADR-092 and the superseded clause in ADR-091, with the recovery-latency cost ADR-091 weighed now recorded as incurred. AMENDS THE RATIFIED `specification/volume-ii/BACKGROUND_PROCESSING.md` :288 — floor 30 to 60, and the cap made explicitly absolute — under the owner's express instruction, as a correction to a defective ratified constant rather than a change of intent. FU-25 was reopened by the review and closes with this ADR on the proved live behaviour. Opens FU-29. Allocated the next unused number after ADR-094.

## ADR-096: S-07-012 Accepted — The Run Driver, And What Its Acceptance Deliberately Does Not Claim

Status: Accepted (2026-07-30)
Date: 2026-07-30
Owner: standing delegation ADR-061; acceptance under the review discipline of ADR-080
Reversibility: Integration branch only; `main` untouched.

**S-07-012 IS ACCEPTED.** It delivered the thing every prior S-07 tranche presupposed: a driver. S-07-004 through S-07-008 built the execution surfaces and NOTHING IN PRODUCTION CALLED ANY OF THEM, so every claim about a run making progress — including S-07-008's own FU-9 "re-entry" — rested on a caller that did not exist. This tranche is that driver, the frontier seal release without which its loop could not cross a depth boundary, and the F-04 lease work the driver made reachable.

**THE REVIEW HISTORY IS PART OF THE RECORD, BECAUSE IT IS THE EVIDENCE.** One ADR-026 five-lens pass (four BLOCK), one three-lens delta pass over the repairs (three BLOCK), and three focused reviews. Five findings needed owner rulings and each was taken rather than assumed: ADR-085 (FU-16, admission at execution), ADR-087 (FU-18, the seal release), ADR-089 (FU-19, the scheduler owns waiting), ADR-091 as corrected by ADR-092 (FU-24, the fenced heartbeat), and ADR-094 as completed by ADR-095 (FU-25, the derived lease). ADR-080's rule that no tranche is accepted until the lenses have reported on THE STATE BEING ACCEPTED is what produced the last of those, and it earned its keep: the final focused review found that FU-25 had been recorded resolved on an implementation reaching two of the three functions that assign a lease, with a green suite, because every example restated the implementation's own arithmetic back to itself. **A tranche that had been declared ready twice was not ready either time. The gate found it both times.**

**WHAT IS ADDED TO `completed_blocks`, AND WHY IT IS NOT COSMETIC.** S-07-006 and S-07-007 were accepted on 2026-07-29 under ADR-081 and ADR-082, are marked `completed` in BUILD_PLAN, and were never added to the state file's list. S-07-009 declares `depends_on: [S-07-007, S-07-008, S-07-012]`, so the controller reading `depends_on` could not have made it eligible however many tranches were accepted. S-07-012 is added by this ADR. The list now matches BUILD_PLAN.

**FU-9 IS CLOSED BY EXPLICIT TRANSFER, NOT BY COMPLETION**, which is the distinction its own note demanded ("it must not be closed silently"). DELIVERED and proved: the scheduler re-entry, honouring the `retry_after` instant the sitemap gate release reports and re-entering the `run_byte_budget_contended` outcome. NOT DELIVERED: deriving :450's `sitemap_unavailable` for a `crawl_host_gates` row no production path can terminalize, because discovery writes that outcome only after the run expires while the driver halts on the same wall clock first with the same `now`. That obligation transfers WHOLE to S-07-009, which owns `crawls.coverage_status`, `crawls.completion_reason` and `crawl_terminal_outcomes`, and it is written into S-07-009's BUILD_PLAN preconditions rather than left inside a closed item where nothing would read it. No part of it belongs to FU-28 (which changes the unit of execution, not coverage derivation) or to S-07-011 (which owns the stranded-claim sweep, FU-22).

**WHAT THIS ACCEPTANCE EXPLICITLY DOES NOT CLAIM.** Three things, each stated so that accepting the tranche does not freeze a false sentence:

1. **:288 IS NOT FULLY IMPLEMENTED.** Its duration rule is (ADR-095), and its cadence rule is. Its third clause — "a handler whose work can legitimately exceed 15 minutes divides it into checkpointed members; no individual claim exceeds the cap" — is NOT. One `crawl_fetch_due` pass can run 75 minutes. That is FU-28.
2. **OWNERSHIP FOR `crawl_fetch_due` IS MAINTAINED BY RENEWAL, NOT ESTABLISHED BY CONSTRUCTION.** The heartbeat is transitional infrastructure, and ADR-094 already recorded that it must not become a destination. The derived lease does not remove it; it makes it correct in the interim.
3. **FU-15 IS NOT A FORMALITY.** The test-harness contention is BOUNDED, never disproved, and it recurred under concurrent reviewers with the blocking statement and holder named. It stays open.

**THE MECHANICAL CHECK NOW READS THE ACCEPTED RECORD.** `spec/architecture/repository_truth_spec.rb` named `S-07-008_COMPLETION_REPORT.md` by hand, so it validated a superseded tranche while the record being accepted was checked by nothing — a gap `S-07-012_COMPLETION_REPORT.md` had itself declared in its opening paragraph. It now derives the report from `acceptance_evidence.block`. The accepted paths and the excluded contamination partition `b48bf6e..f2b576e` exactly, with the four unrelated authorized commits inside it attributed to themselves.

Proof standard. 1977 examples, 0 failures, from a database provisioned FROM EMPTY. Brakeman, packwerk, zeitwerk and bundler-audit clean; `verify_runtime` 15 checks with RLS intact; no structure drift. Twenty-two mutations recorded in the completion report, each failing a named example, and the two that survived their first round are recorded as strengthened or as uncovered rather than waved off.

Authority And Precedence:
Acceptance under standing delegation ADR-061 and review discipline ADR-080. Closes FU-9 by transfer to S-07-009. Adds S-07-006, S-07-007 and S-07-012 to `completed_blocks`. Supersedes the S-07-008 scope of `acceptance_evidence`, which is retired rather than deleted — its ADR-083 acceptance stands on its own record. FU-11, FU-15, FU-17, FU-20, FU-21, FU-22, FU-23, FU-26, FU-27, FU-28 and FU-29 remain open, and FU-11 remains BLOCKING for the next block. Allocated the next unused number after ADR-095.

## ADR-097: FU-11 Repaired — Terminal Completeness Is Scoped By State, And The Two Diagnoses That Were Wrong

Status: Accepted (2026-07-30)
Date: 2026-07-30
Owner: standing delegation ADR-061; taken as S-07-009's blocking precondition
Reversibility: Integration branch only. One CHECK constraint replaced; reversible down and up, exercised.

The defect. A terminal `crawls` row could carry NULL in BOTH `coverage_status` and `completion_reason`, so a fully covered Crawl was byte-indistinguishable from one that recorded nothing. Repaired BEFORE S-07-009's body rather than inside it, because S-07-009 writes exactly those two columns and BUILD_PLAN names this its blocking precondition.

**THE DIAGNOSIS WAS WRONG TWICE, AND BOTH REFUTATIONS ARE KEPT.** Pass three of the S-07-008 review recorded this as a three-valued-logic hole in `crawls_coverage_status_check` and prescribed the `IS NOT DISTINCT FROM` form. THE PRESCRIPTION WAS SET ASIDE, AND THE REASON FIRST RECORDED HERE WAS ITSELF FALSE — corrected in place at ADR-111. What is true: `NULL = ANY(ARRAY['full','partial'])` yields UNKNOWN, which a CHECK admits, and the NULL-safe form PROOF 29 evaluates (`x IS NULL OR x = ANY(...)`) yields TRUE, which it also admits — so rewriting to THAT shape is a genuine no-op. What is false, as first written: the `IS NOT DISTINCT FROM` spelling the third pass NAMED is not a no-op at all. Its `ANY(...)` form is a syntax error and its pairwise form yields FALSE for a NULL, which a CHECK REFUSES, so applying it would have rejected every `queued` and `running` Crawl. Applying it would have produced a diff, closed the item, and left the hole exactly where it was. `crawls_coverage_status_check` is therefore DELIBERATELY UNTOUCHED, and PROOF 29 pins the no-op in a test so it cannot be reintroduced as a fix by a future reader who rediscovers the original reasoning.

The actual defect is ordinary two-valued logic in `crawls_terminal_shape`, whose terminal limb required only `terminal_at IS NOT NULL`. Measured against the live cluster before the repair, it admitted `state='completed'` with both columns NULL, `completed` with a reason and no coverage, and `failed` with neither.

**THE REPAIR IS SCOPED BY STATE, AND THE SCOPING IS THE REPAIR.** Every terminal state requires `completion_reason IS NOT NULL`; `state='completed'` additionally requires `coverage_status IS NOT NULL`. The obvious rule — "a terminal Crawl must carry both" — is WRONG, and it was demonstrated wrong as a mutation rather than argued against: it breaks `IdentityAccess::Infrastructure::CrawlStartStore#fail`, the only production writer of `completion_reason`, which records `state='failed'` with a reason and NO coverage. That is correct, not sloppy: a Crawl that failed before execution made no request, and there is no coverage to report on. The same mutation also fails two PRE-EXISTING accepted examples, which is the sharper signal — the naive form does not merely offend a new test, it contradicts behaviour two earlier tranches already proved.

Proof standard. PROOF 26 — a `completed` Crawl cannot be written with neither column, nor with only one. PROOF 27 — every terminal state needs a reason and only `completed` needs coverage, asserted over `failed` and `canceled`. PROOF 28 — the production fail path still writes the shape it has always written, driven through the REAL store rather than an insert shaped like it, so a future change to `fail` that stopped setting a reason fails here. PROOF 29 — a non-terminal Crawl still carries neither column, plus the no-op pin above. Two mutations: removing the conjunct fails PROOFs 26 and 27; the naive both-columns form fails PROOFs 27 and 28 and two accepted examples. `schemas/POSTGRESQL_SCHEMA.md`'s nullable declaration is reconciled rather than contradicted: the columns stay nullable and the state-scoped rule is stated beside them, because nullability alone cannot express a rule that depends on `state`.

One reading is recorded because it is a judgement, not a fact: `state <> 'completed' OR coverage_status IS NOT NULL` is written as a disjunction rather than a CASE. Inside that limb `state` is already known to be one of three terminal values and is NOT NULL on the column, so the disjunction is two-valued and cannot yield UNKNOWN. That is exactly the distinction the first diagnosis of this defect got wrong, so it is stated in the migration rather than assumed.

Authority And Precedence:
Resolves FU-11. Corrects, in place, the pass-three prescription recorded against it, which stands refuted rather than merely superseded. Does not touch the three genuine three-valued-logic holes found by the same sweep, which remain open under FU-12. S-07-009's second precondition, FU-21, is unaffected and next. Allocated the next unused number after ADR-096.

## ADR-098: FU-21 Closed — Every Retirement Records What Happened To The URL, In The Transaction That Retires It

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: standing delegation ADR-061; S-07-009's second precondition
Reversibility: Integration branch only. No schema change — the table landed at S-07-009 (2/n). Two driver call sites and one new store; revertible by removing them.

The defect, restated so the closure can be checked against it. A terminal frontier entry can carry no `fetch_attempts` row, so a covered URL was indistinguishable from an unretrieved one. `Workflows::Wf005::FetchContent` authorizes BEFORE it claims an attempt row, and :448's fail-closed robots host never reaches the fetch path at all, so an entry could be retired with no attempt and a NULL `reason` — the SAME bytes a fetched covered entry leaves, and irreversible, because the frontier guard admits no edge out of `terminal`.

**THE TABLE WAS NOT THE FIX, AND THE PREVIOUS COMMIT SAID SO.** S-07-009 (2/n) built `crawl_terminal_outcomes` and left FU-21 open on its own terms: "FU-21 closes when the driver writes, not when the table exists." This is the driver writing. `Workflows::Wf005::CrawlDriver` now records exactly one outcome per entry it retires, on both retirement paths — the decided fetch and :448's fail-closed host — and on neither of the paths that retire nothing.

**IN THE SAME TRANSACTION AS THE SEAL RELEASE, AND THAT IS DEMONSTRATED RATHER THAN ASSERTED.** PROOF 45 puts a conflicting row in the way so the INSERT must fail, and requires the entry to be left `in_progress`. Under the tidier two-transaction form the entry ends `terminal` with no classification — which is the original defect with an extra step, and irreversibly so. The compare-and-set on the claim is what gates the write, so a `superseded` redelivery reaches no INSERT at all and records nothing rather than a second opinion (PROOF 46); the `entry_once` constraint is the backstop, never the mechanism.

**TWO FIELDS ARE DERIVED IN SQL, DELIBERATELY.** `commit_order` is `MAX + 1` per run under the same per-Crawl frontier advisory lock that already makes admission happen in dequeue order, so :456's commit sequence is the dequeue sequence by construction rather than by a counter the writer keeps. `accounted_response_body_bytes` is SUMMED from the entry's committed content attempts, not taken from the retiring pass's own figure: :301 says "accounted byte totalS", a retried URL has more than one attempt, and the discriminator is exact — `FetchContent` classifies an HTTP error WITHOUT a measurement, so `Result#accounted_bytes` is 0 for a 503 whose attempt row records the real number. PROOF 48 fails under the last-attempt form.

`CoverageClassification` is the one duplication the design could not avoid: the CHECK's vocabulary lives in a migration class, which is not loadable at runtime. PROOF 41 rebuilds the map from the LIVE `pg_constraint` definition and asserts it against the module in both directions, and PROOF 42 pins the separately-declared `EnsureRobots::FAIL_CLOSED` token against the same catalogue — the failure if those drifted is silent where it matters least and fatal where it matters most, because a fail-closed host's entry could then not be retired at all.

Proof standard. PROOFs 41-42 (catalogue agreement) and 43-49 (the driver, over the production-real chain). Three mutations: the classification moved to a second transaction fails PROOF 45 on the atomicity property alone; the byte total taken from the last attempt fails PROOF 48; the fail-closed path writing nothing fails PROOF 44 AND two pre-existing accepted examples, which is the sharper signal.

What this does NOT claim. Nothing reads these rows yet — the terminal checkpoint that derives `crawls.coverage_status` and `crawls.completion_reason` from them is the next slice of this block. `document_id` stays NULL because Documents are S-07-010's, so `document_created` records CANDIDATE coverage exactly as the accepted migration recorded it. FU-22's stranded `in_progress` claim is untouched and remains S-07-011's.

Authority And Precedence:
Resolves FU-21. WORKFLOW_SPECIFICATIONS.md :452/:454/:456 and schemas/POSTGRESQL_SCHEMA.md :301 govern; DECISIONS ADR-087 governs the ordering of the seal release against the ledger, which is unchanged. Allocated the next unused number after ADR-097.

## ADR-099: The Crawl Terminal Edge Set Opened, And Two Closures Taken With It

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: standing delegation ADR-061; S-07-009's enabling schema change
Reversibility: Integration branch only. One trigger function replaced by `CREATE OR REPLACE`; `down` restores S-07-003's form verbatim. Exercised down and up on both databases.

The terminal checkpoint had no legal move. `f1_crawls_guard` admitted exactly `queued -> running` and `queued -> failed` — what S-07-003 needed, and all it opened, which its own migration recorded in terms ("running->terminal and cancel are relaxed by later tranches"). S-07-009 is that tranche, so the edge set is now WORKFLOW_SPECIFICATIONS.md :736's whole sentence and nothing wider: `queued -> running | failed | canceled`, `running -> completed | failed | canceled`.

**A MIGRATION THAT ONLY WIDENED WOULD HAVE REPEATED FU-11's DEFECT CLASS.** FU-11 was a column carrying the customer-visible answer with no rule saying it must be written; opening the terminal transition without a rule saying it may be written ONCE is the same shape. So two closures land with the relaxation, and each is a NEW refusal rather than a permission:

**A terminal Crawl is FROZEN, not merely unable to change state.** :458 — "terminal selection occurs ONCE at a serialized checkpoint". :735 — a recovery "creates a new linked `Crawl.Queued` attempt RATHER THAN TRANSITIONING THE OLD RECORD". MTX-030 — "no terminal Crawl is moved back to running". Confined to state changes, the guard would have left `coverage_status` and `completion_reason` freely rewritable on a finished run by an UPDATE that changes no state, so a second opinion about a customer's coverage would be indistinguishable from the first. There is no legitimate writer: `retry_generation`, `recovery_generation` and `recovery_of_id` belong to the NEW attempt a recovery creates, which is exactly what :735 says the old record must not absorb.

**The run's metering identity is fixed at the accepted start.** POSTGRESQL_SCHEMA.md :338 declares `entitlement_decision_id` and `entitlement_reservation_id` "NULL until start"; once stamped they name the reservation this run is committed or released against at the checkpoint (MTX-030: "commit or release its reservation EXACTLY ONCE"). Swapping either is an UPDATE that changes no state, so it would otherwise have passed every check on the table. Scoped on `OLD.started_at IS NOT NULL`, so the accepted start still stamps both in the same statement that leaves `queued` — PROOF 53 drives the REAL `CrawlStartStore#start` rather than an UPDATE shaped like it.

**A THIRD RULE WAS CONSIDERED, MEASURED, AND DELIBERATELY NOT TAKEN.** The same limb originally froze `started_at` and `deadline_at` too, and the argument for it is sound: :442 starts the wall clock at the `Queued -> Running` transition and `crawl_terminal_deadline` fires at exactly `deadline_at`, so a movable deadline makes the 60-minute ceiling renegotiable by an UPDATE that changes no state. It was WITHDRAWN because the cost was measured rather than guessed: it broke SIX PRE-EXISTING ACCEPTED EXAMPLES across four spec files, every one of which simulates an expired run by writing `deadline_at` backwards, and nothing in production writes either column after the start. Rewriting six accepted setups to buy defence in depth against a writer that does not exist is a deliberate change, not a side effect of the tranche that happened to notice it — and the better replacement setup (advance the injected clock instead of falsifying a column) is itself blocked on FU-31. It is recorded as FU-30, and PROOF 52 asserts that `deadline_at` IS still writable, so the gap is visible in the suite rather than assumed absent.

Proof standard. PROOF 50 enumerates the WHOLE 20-edge cross product rather than a chosen few, asserts the permitted set equals :736's six, and requires each refusal to name the rule that refused it — an edge out of a terminal state is refused because the row is finished, not because that pair is unlisted. PROOFs 51-53 cover the two closures and the start path they must not break. Three mutations: dropping the terminal freeze fails PROOFs 50 and 51; dropping the metering freeze fails PROOF 52; reverting to S-07-003's edge set fails PROOF 50.

One superseded example is replaced rather than deleted: `spec/persistence/crawl_start_invariants_spec.rb` asserted that `running -> completed` was REFUSED, which was true of the guard S-07-003 left and is the thing this migration changes. PROOF 50 replaces it with the full cross product, so the successor is stronger than the example it supersedes rather than merely different.

What this does NOT do. Nothing takes these edges yet — the checkpoint, `crawl_terminal_deadline`'s scheduling and `CancelCrawl` are the following slices. The guard is the precondition, deliberately landed on its own so the edge set is reviewable as a rule rather than inside the behaviour that first uses it.

**AND A DEFECT THIS SLICE FOUND WITHOUT FIXING, RECORDED AS FU-31 BECAUSE IT BLOCKS THE NEXT ONE.** Building the checkpoint's commit obligation exposed that NOTHING CALLS `Platform::Entitlement::Service#heartbeat`. :551 requires a running execution to hold "a renewable lease with a heartbeat at least every 5 minutes"; `start_execution` sets `lease_due = now + 15 minutes` and nothing renews it. Two live consequences: every run is capped at 15 minutes, because `Admission#authorize_run` requires `reservation_executing?` and that tests `lease_due > now` — so :442's 60-minute wall clock is unreachable and the terminal deadline fires on a run that stopped 45 minutes earlier; and the checkpoint's commit would ALWAYS degrade to a release, because `Service#commit` releases at or after `effective_deadline`, so a completed Crawl with valid Documents would never be counted against the customer's entitlement. The heartbeat's CALLER is the workload holding the lease, which is WF-005's; BUILD_PLAN gives S-22/WF-015 the `EntitlementLeaseRenewed` EVENT and says expressly that "S-07 consumers invoke F-05 and record their OWN WF-005 outcomes", so the invocation is S-07's and was assigned to no slice at all.

Authority And Precedence:
WORKFLOW_SPECIFICATIONS.md :736 fixes the edge set; :458 and :735 and MTX-030 fix the terminal freeze; :442 and BACKGROUND_PROCESSING.md :139 fix the clock freeze. `schemas/POSTGRESQL_SCHEMA.md` is reconciled beside the `crawls` row. Allocated the next unused number after ADR-098.

## ADR-100: FU-31 Resolved — The Run Renews Its Own Entitlement Lease, And Why Nothing Did

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: standing delegation ADR-061; found and taken inside S-07-009 because the checkpoint it blocks is S-07-009's
Reversibility: Integration branch only. One call and two private methods on `Wf005::CrawlDriver`; no schema change, no change to F-05.

`Platform::Entitlement::Service#heartbeat` was built by F-05 and HAD NO CALLER ANYWHERE IN THE REPOSITORY. WORKFLOW_SPECIFICATIONS.md :551 requires that "once execution starts, it holds a renewable lease with a heartbeat at least every 5 minutes"; `start_execution` sets `lease_due = now + 15 minutes` and nothing renewed it.

**TWO CONSEQUENCES, BOTH LIVE, AND THE FIRST IS THE ONE THAT MATTERS.** `Admission#authorize_run` and `FetchAuthorization` both require `reservation_executing?`, which tests `lease_due > now` — so from the fifteenth minute EVERY pass halted with `admission_entitlement_not_executing`, :442's sixty-minute wall clock was unreachable, and a `crawl_terminal_deadline` checkpoint would have fired on a run that stopped forty-five minutes earlier. PROOF 54 asserts exactly that as the regression: a pass at minute sixteen halts on the entitlement with forty-four minutes of budget left. The second consequence is quieter and worse: `Service#commit` RELEASES at or after the effective deadline, so the checkpoint's ratified "commit or release its reservation exactly once" would have satisfied its form and inverted its substance — a completed Crawl with valid Documents never counted against the customer's entitlement.

**WHY IT WENT MISSING, RECORDED SO THE GAP CLASS IS VISIBLE.** BUILD_PLAN gives S-22/WF-015 the `EntitlementLeaseRenewed` EVENT and says in terms that "S-07 consumers invoke F-05 and record their OWN WF-005 outcomes; they never emit these". So the EVENT was assigned and the INVOCATION was not, and each side could reasonably read the other as owning it. The caller has to be the workload that holds the lease, which is the run driver.

**ON CADENCE, NOT PER PASS, AND THE CADENCE IS READ FROM COMMITTED STATE.** `last_heartbeat_at` lives on the reservation row, so two deliveries of one action compute the same answer and a process loss cannot reset it. Renewing per pass would write one immutable heartbeat row per fetch — the write amplification F-04's `LeaseKeeper` already refused for this exact reason — and :551's own five-minute interval divides the fifteen-minute lease three times over. Placed AFTER `authorize_run`: a lease already past its deadline must not be renewed, and `heartbeat` refuses past the deadline on its own, so the two rules agree rather than one relying on the other. No event is emitted, per BUILD_PLAN.

Proof standard. PROOF 54 is the defect, asserted first so the renewal is demonstrably load-bearing. PROOF 55 pins the renewal to the pass's OWN instant, which is what :551 measures the fifteen minutes from. PROOF 56 pins the cadence: a pass one minute in writes nothing. PROOF 57 drives the real handler over a chain of passes six minutes apart until the frontier drains, spanning well past the lease, and asserts no pass halted, the reservation is still `executing`, and the heartbeat generations are consecutive from 1 with no gap. Two mutations: removing the renewal fails PROOFs 55 and 57; renewing unconditionally fails PROOFs 56 and 57.

What this does NOT claim. The heartbeat is per PASS-ON-CADENCE, not a background timer: a run whose passes are more than fifteen minutes apart still loses its lease, and correctly so, because :551's expiry is what reclaims a lease whose holder has gone. The chain's own maximum gap is :444's 120-second retry, so this is bounded by construction rather than by hope. `entitlement_lease_expire` (the reclaim side) remains unbuilt and is S-22's.

Authority And Precedence:
Resolves FU-31. WORKFLOW_SPECIFICATIONS.md :551 governs the lease and its cadence; MTX-030 governs the checkpoint's commit/release that this unblocks; BUILD_PLAN S-22 governs the event, which is deliberately not emitted here. Allocated the next unused number after ADR-099.

## ADR-101: The Terminal Checkpoint — :458's Selection, FU-9 Delivered, And The Second Instant The Evidence Forced

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: standing delegation ADR-061; S-07-009's tranche body
Reversibility: Integration branch only. No schema change. One new command, one new handler, one pure derivation, one schedule module, three store methods and one registry row; revertible by removing them.

Nothing terminalized a run. `f1_crawls_guard` admitted no edge out of `running` until ADR-099, nothing scheduled `crawl_terminal_deadline`, and a Crawl whose frontier drained stayed `running` for ever — the chain only links forward FROM a pass, and a run with no pass to make creates no link. This is :458's serialized terminal selection, its two events, its reservation settlement, and FU-9's transferred obligation.

**THE SERIALIZATION IS A ROW LOCK, AND THE COUNT IS ONE STATEMENT.** :458 — "terminal selection occurs ONCE at a serialized checkpoint." `SELECT ... FOR UPDATE` on the Crawl row is taken before any read that decides anything, so a second delivery BLOCKS, then sees the first one's decision and finds the Crawl terminal. Everything the selection needs is then counted in a single statement under that lock: eight separate reads would let the run change between them and produce a selection that no single state of the database ever justified.

**THE DERIVATION IS A PURE FUNCTION, AND THAT IS WHY IT COULD BE PROVED EXHAUSTIVELY.** `Wf005::TerminalSelection` has no database, no clock and no identity, so every combination of :458's precedence limbs is reachable in one line — where reaching some of them through a real run would need a Crawl that hit a hard limit AND lost a Source root AND left a candidate unevaluated. MTX-030 says the same thing from the other side: "coverage and readiness derivation are pure functions over the manifest."

**TWO QUESTIONS THAT LOOK LIKE ONE, KEPT APART.** :453's failure test is not :458's coverage test, and the completion reason is not the coverage status. A run of terminal 404s is :452-COVERED throughout and produced nothing, so it is FAILED (PROOF 71). A run that fetched everything it reached but left one candidate unevaluated at the bound completes with reason `completed` and coverage `partial` (PROOF 77). Deriving either from the other is the mistake, and the direction that matters is the one that makes coverage read better than the run was — which is why the mutation that derives coverage from the reason fails three named examples.

**FU-9's TRANSFERRED OBLIGATION IS DELIVERED HERE.** `DiscoverSitemaps` writes :450's terminal sitemap outcome only once the run has expired, and `CrawlDriver#advance` halts on the same wall clock BEFORE it calls discovery with the same `now` — so a gate under sustained contention stayed `pending` for ever and `sitemap_unavailable` was unreachable on every production path. At the checkpoint it is both reachable and TRUE: no candidate can ever be attempted from here, which is exactly the "after retries/validation" premise :450 conditions the outcome on. It is written through the ACCEPTED claim/terminalize surface rather than around the sitemap guard, which is the reason the guard is right — a worker still holding the claim BLOCKS the checkpoint from writing over a decision it is in the middle of making. A fail-closed robots host is skipped, because :448 denied it any sitemap to fail at and recording one would charge that host to the coverage measure twice (PROOF 68).

**THE SECOND INSTANT WAS FORCED BY EVIDENCE, NOT CHOSEN FOR LATENCY.** BACKGROUND_PROCESSING.md :139 makes `crawl_terminal_deadline` the "exact 60-minute terminal checkpoint", and the first design scheduled exactly one, at `crawls.deadline_at`. PROOF 60 then failed on a fact rather than a preference: :551 caps the entitlement lease at fifteen minutes since the last accepted heartbeat and `Entitlement::Service#commit` RELEASES rather than commits at or after that instant, so every run that finished its work before minute forty-five — which is every ordinary run — released its reservation, and `crawl.start` could never be committed against any customer's entitlement at all. MTX-030's "commit or release its reservation exactly once at the listed Crawl durable point" would have been satisfied in form and inverted in substance. So a pass that DRAINS the frontier now schedules the same checkpoint kind for its own instant, and PROOF 70 keeps the refuted alternative in the suite: at the deadline, on the same run, the commit is a release with `lease_expired_at_commit`.

Two scopes were considered and rejected for that second instant. A PINNED frontier does not schedule one: that is FU-22's stranded claim and S-07-011 will recover it, so terminalizing here would foreclose a recovery this tranche does not own. A HALTED pass does not either — :442's rule at a hard limit is to "stop scheduling affected work", and its deadline checkpoint is already due. The two actions are DISTINCT IDENTITIES (the preimage includes `due_at`), so both exist and both fire; :458's "once" is enforced by the Crawl row lock and the state machine, not by there being only one delivery, and the second one records `crawl_already_terminal` (PROOF 65).

**ONE JOB, TWO OF :377's FOUR OPERATIONS.** ":377 — `StartCrawl`, `CompleteCrawl`, `FailCrawl`, or `CancelCrawl`, SELECTED SOLELY FROM PERSISTED CRAWL/DEADLINE STATE." The kind is registered as `CompleteCrawl` and the same job selects `FailCrawl` from the counted facts; the audit record and the event both name which. `CancelCrawl` is deliberately not selected here — :458 settles cancellation by ORDER OF COMMIT, so a cancelled Crawl is already terminal when the checkpoint arrives, and a `canceled` limb in the derivation would be a second implementation of a rule the state machine already enforces (PROOF 79).

**THE ONE INTERIM BOUNDARY, STATED RATHER THAN HIDDEN.** :453's "zero valid Documents" is counted over `crawl_terminal_outcomes.outcome = 'document_created'`, because nothing creates a `documents` row yet. S-07-010 owns them, and the accepted `20260727120350` migration already ratified `document_created` with `document_id` NULL as the record of a fetch that did everything :436 asks of an accepted page. S-07-010 must confirm it against the artifact; until that artifact exists there is nothing truer to read, and inventing a stricter test would make every run fail for a reason about this build rather than about the customer's site.

Proof standard. PROOFs 58-70 drive the REAL registered handler over the production-real chain (the action's existence and instant, the four selection shapes, the two instants, replay, the terminal boundary, the due gate, and both FU-9 limbs). PROOFs 71-79 exercise the derivation exhaustively. Three mutations: reverting to the deadline-only checkpoint fails PROOFs 60 and 69; deriving coverage from the completion reason fails PROOFs 63, 76 and 77; skipping the FU-9 derivation fails PROOF 67.

Authority And Precedence:
WORKFLOW_SPECIFICATIONS.md :450, :452, :453, :458 and :551 govern; BACKGROUND_PROCESSING.md :139/:199/:377 govern the action and the operations; MTX-030 governs the serialized transaction and the reservation settlement. Delivers the obligation FU-9 transferred at ADR-096 and the `crawl_terminal_deadline` scheduling FU-22 named. `crawl_already_terminal` and `crawl_not_running` are added to `Platform::ErrorCatalog`; :458 names the first in terms. Allocated the next unused number after ADR-100.

## ADR-102: CancelCrawl — The Boundary Both Sides Take The Same Lock For

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: standing delegation ADR-061; S-07-009's last slice
Reversibility: Integration branch only. One command, one handler, one store writer, one permission-baseline row and two error codes; no schema change.

The last of :377's four crawl operations, and the only one that is an ACTOR command. API_CONTRACTS.md :279 routes it, :738 says "cancellation requires `crawl.cancel`", and :736 gives it two edges: `Crawl.Queued -> Crawl.Canceled` and `Crawl.Running -> Crawl.Canceled`.

**:458's BOUNDARY IS COMMIT ORDER, AND THAT IS WHY THIS IS A COMMAND AND NOT A DERIVATION.** "A cancellation committed STRICTLY BEFORE that checkpoint yields `Crawl.Canceled`; a cancellation at or after the checkpoint is rejected as `crawl_already_terminal`." Both this handler and the terminal checkpoint take `SELECT ... FOR UPDATE` on the same Crawl row before reading anything that decides, so one of them commits first and the other reads the winner's state rather than its own stale view. NEITHER IMPLEMENTS THE OTHER'S RULE: this refuses with exactly the token :458 names, the checkpoint finds a cancelled Crawl and derives nothing, and `f1_crawls_guard` (ADR-099) refuses every edge out of a terminal state so the loser could not write even if both tried. Three independent statements of one rule would drift; one rule with three parties that agree does not.

`expected_state_version` is the other half of the same boundary and is MTX-030's request schema for this command in terms ("Cancel: Crawl ID, expected state version"): a cancellation holding a version the run has moved past is refused rather than applied to a Crawl its sender was not looking at.

**THE RESERVATION IS RELEASED, NEVER COMMITTED.** ":551 — Cancellation or any terminal failure before the listed commit point RELEASES exactly once EVEN WHEN intermediate Documents or other partial artifacts exist; those artifacts remain governed by their workflow but are not a usage commitment." A cancelled run is never `crawl_completed_with_valid_document` whatever it fetched first, so the customer is not charged. A `queued` Crawl has no reservation at all (POSTGRESQL_SCHEMA :338 — "NULL until start") and the payload says `none` rather than guessing.

**`crawl.cancel` IS A SEPARATE PERMISSION EVEN THOUGH ITS CELLS ARE IDENTICAL.** :147 puts it in the same row as `crawl.trigger` — allow, allow, deny, deny, deny, deny — and :738 names it separately. It is transcribed as its own baseline entry with its own denial code, because collapsing two ratified permissions into one on the strength of today's cells agreeing is how a later divergence in the ratified table becomes silently unimplementable.

No `coverage_status`: `crawls_terminal_shape` requires it only of `completed` (ADR-097), and a cancelled run's coverage is not a number anyone should read — the run was stopped, not measured.

Proof standard. PROOFs 80-87 over the production-real chain: both of :736's edges, the reservation release and its absence, :458's token, the stale version, both sides of :147's permission row, exact replay, and POSTGRESQL_SCHEMA :128's cross-Project predicate asserted against a REAL second Project of the SAME Organization — which is the shape that makes Organization-scoped RLS an insufficient answer on its own. Three mutations: dropping the release fails PROOFs 80 and 86; ignoring the expected version fails PROOF 83; widening :147's row by one role fails PROOF 84.

Authority And Precedence:
WORKFLOW_SPECIFICATIONS.md :147, :458, :551, :736 and :738 govern; API_CONTRACTS.md :279 names the route, which has no HTTP adapter in this build for the same reason every other WF-005 actor command has none. Completes S-07-009's operation set. Allocated the next unused number after ADR-101.

## ADR-103: A Lost Compare-And-Set Is Classified, Not Rescued — StartCrawl Versus CancelCrawl

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: owner instruction at the S-07-009 acceptance boundary
Reversibility: Integration branch only. One classifier, one second-transaction refusal path and one error class on `Handlers::StartCrawl`; no schema change, no new lock.

The two commands serialize on DIFFERENT OBJECTS. `StartCrawl` takes the per-Project ADVISORY lock and then relies on a compare-and-set (`state = 'queued' AND state_version = $2`); `CancelCrawl` takes the Crawl ROW lock. So a cancellation can commit in the window between StartCrawl's authoritative read and its transition, and before this repair the SAME cancellation produced `crawl_not_queued` when it landed a moment earlier and a `Platform::InvariantViolation` when it landed a moment later. **Timing decided whether an ordinary race was a domain refusal or an invariant failure**, and that is the defect. Rollback prevented corrupted state throughout; it did not make the two reports the same fact.

**THE REPAIR IS A CLASSIFICATION, NOT A BLANKET RESCUE**, and the distinction is load-bearing. On a lost compare-and-set the handler RE-READS the Crawl, and the re-read is authoritative: the statement blocked on the row lock until the other transaction committed and then matched zero rows, so a fresh SELECT at READ COMMITTED sees what the winner committed rather than this transaction's older snapshot. Three outcomes: the row is gone (impossible under a guard that refuses DELETE, so it escalates); the state is no longer `queued` (the canonical harmless terminal execution, reported with the same reason code the same handler uses when it observes the transition before acting); the state is STILL `queued`, meaning `state_version` moved without the state moving, which the guard permits for a non-state update and which nothing in production does — so it escalates, because a lost race nobody can name is not the same fact as a cancellation. Rescuing every lost CAS as `crawl_not_queued` would have swallowed that third case, and PROOF 89 fails under exactly that mutation.

**THE REFUSAL IS WRITTEN IN A SECOND TRANSACTION, AND THAT IS WHY IT RAISES AT ALL.** By the time the compare-and-set fails, the attempt has written a command execution and moved the entitlement reservation `reserved -> executing`. Reporting the denial inline would commit BOTH beside it: an execution record for a start that did not happen, and a reservation left `executing` for a run that never ran, which nothing would ever commit or release. Raising out of `Platform::UnitOfWork.run` rolls the whole attempt back, and the denial is written cleanly against the state the winner left. PROOF 88 asserts zero `entitlement_reservations` and zero `crawl.start` `entitlement_decisions` rows for the Organization afterwards, which is the assertion that fails if the denial is moved inline.

The same classifier covers the pre-execution `fail` compare-and-set, which has the identical window.

Preserved exactly as required: the per-Project advisory serialization is unchanged, no new lock is taken and no lock order is introduced, the state guard and the expected-version guard are untouched, and the transactional rollback of the reservation and the frontier seeding is what the proof turns on.

**THE WINDOW IS FORCED, NOT WAITED FOR.** The proof uses the repository's own technique — a database trigger rather than a hook in production code, as `FailureInjector` already aborts a real statement — installed conditionally on `command_type = 'wf005.start_crawl'` so the cancellation running underneath does not block on the same gate. `RaceHarness#interleave` releases only once StartCrawl is OBSERVABLY blocked, read from `pg_locks`, so a run that degraded into a sequential one fails the example rather than passing quietly.

Two mutations: the blanket rescue fails PROOF 89; the pre-repair `raise LostRace` fails PROOF 88 with the exact `Platform::InvariantViolation` the defect produced.

Authority And Precedence:
Repairs a defect found at the S-07-009 acceptance boundary, in code accepted at S-07-003 and code written at S-07-009 (7/n). WORKFLOW_SPECIFICATIONS.md :736 governs the edge set; the `crawl_not_queued` token is S-07-003's own and is reused rather than added to. Allocated the next unused number after ADR-102.

## ADR-104: FU-30 Resolved — The Run's Clock Is Not Renegotiable, And The Harness Now Ages A Run The Way Production Does

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: owner instruction at the S-07-009 acceptance boundary
Reversibility: Integration branch only. One trigger function replaced by `CREATE OR REPLACE`; `down` restores ADR-099's form verbatim. Exercised down and up on both databases.

`crawls.started_at` and `crawls.deadline_at` were writable after the accepted start. ADR-099 froze the metering identity for the same reason and deliberately left these two, recording the cost as FU-30: the rule broke six pre-existing accepted examples whose harnesses simulate an expired run by writing `deadline_at` backwards. FU-31 has since removed the obstacle that made the replacement impossible, so this is that repair.

**WHY IT IS NOT MERELY UNTIDY TEST SUPPORT.** :442 starts wall-clock duration "at the atomic `Crawl.Queued -> Crawl.Running` transition" and BACKGROUND_PROCESSING.md :139 fires `crawl_terminal_deadline` at exactly `deadline_at`. Both are statements about a FIXED instant. A movable column makes the ceiling advisory: the run's bound, the instant its terminal checkpoint was scheduled for, and the elapsed figure every `wall_clock_run_duration` decision records would all derive from a value anything holding UPDATE could move afterwards, without changing `state` and therefore without meeting any other check on the table.

**A COLUMN-LEVEL REVOKE COULD NOT EXPRESS IT**, and that is worth stating because it is the obvious first answer. The accepted start WRITES both columns through the same UPDATE privilege the state machine needs, so the rule is not "this role may not write this column" but "not after `started_at` is set" — a predicate over the row, which only the trigger can carry. PROOF 90 therefore asserts the catalogue facts that make the mechanism real: the trigger exists, `tgenabled = 'O'`, its type bits include UPDATE, and its source names the column; then it drives a real UPDATE as the runtime role and requires the refusal.

**THE HARNESS NOW AGES A RUN THE WAY PRODUCTION AGES ONE.** All eight mutation sites across four spec files are gone. What replaces them is time passing: the examples advance the injected clock, and `Wf005CrawlChain#age_run_to` keeps :551's entitlement lease alive across the span through `Platform::Entitlement::Service#heartbeat` — the same production surface every pass has used since FU-31, at the same five-minute cadence :551 names. It is needed only because those examples drive `Admission`, `DiscoverSitemaps` or one pass directly rather than running the chain, so nothing else renews the lease. Before FU-31 this replacement was not available at all: a run could not honestly be sixty-one minutes old, because nothing renewed the lease and admission refused from minute fifteen. FU-30 was correctly blocked on FU-31 and is correctly taken after it.

**ONE ACCEPTED EXAMPLE CHANGED WHAT IT ASSERTS, AND THE CHANGE IS A CONSEQUENCE OF REMOVING A FICTION.** "Emits the wall-clock HARD limit when the deadline has passed" used `.sole` on the decision set. It could only do that because its fixture moved `deadline_at` back one second while leaving `started_at` where it was, producing a run that was past its deadline at ZERO elapsed minutes. No real run is that shape: with :442's ratified 45/60 pair, past the deadline IMPLIES past the soft bound, so a genuinely expired run always carries both crossings. The example now names the row it is about and additionally asserts `observed_value == 61`, which the old fixture could not have shown. That both fire is the next example's property and is unchanged.

Proof standard. PROOF 52 extended to both columns and both directions (`deadline_at = NULL` included, since erasing a ceiling is as effective as moving it), PROOF 90 for the catalogue and the runtime role. One mutation: leaving the clock writable fails PROOFs 52 and 90. `schemas/POSTGRESQL_SCHEMA.md` is reconciled beside the `crawls` row.

Authority And Precedence:
Resolves FU-30, which ADR-099 opened and recorded rather than took. WORKFLOW_SPECIFICATIONS.md :442 and BACKGROUND_PROCESSING.md :139 govern the fixed instant; POSTGRESQL_SCHEMA.md :338 governs the metering columns ADR-099 already froze. Allocated the next unused number after ADR-103.

## ADR-105: B7 Repaired — The Checkpoint Conforms To The Subsystem's Lock Order Instead Of Inventing Its Own

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: standing delegation ADR-061; repair of the ADR-080 acceptance round's most serious finding
Reversibility: Integration branch only. One statement added to `Handlers::CompleteCrawl#process`; no schema change, no new lock object.

`Handlers::CompleteCrawl` serialized on `crawls FOR UPDATE`; `CrawlDriver#retire` serializes on the `crawl-frontier:<crawl>` advisory lock, which it holds across BOTH the frontier terminalize and the `crawl_terminal_outcomes` INSERT. Nothing ordered the two, so the checkpoint could count a snapshot an in-flight pass invalidated a moment later.

**The observed state was internally inconsistent and permanent.** A run that had fetched a valid Document was recorded `state=failed, completion_reason=failed`, its reservation RELEASED, while `crawl_terminal_outcomes` said `document_created / covered` and `fetch_attempts` said `200`. The concurrency lens reproduced it three ways, including **at natural timing with no gate — a 150 ms fetch with the checkpoint fired 50 ms in, 10/10.** ADR-101 is what makes it ordinary rather than exotic: a drained pass schedules a checkpoint for its own instant, so checkpoint-concurrent-with-pass is this design's normal case. And ADR-099's terminal freeze makes it irreversible — `f1_crawls_guard` refuses every UPDATE of a terminal row, so nothing can ever correct it. Two decisions taken inside this block combine into a wrong, uncorrectable answer about a customer's run and their billing.

**THE REPAIR CONFORMS TO AN ORDER THAT ALREADY EXISTED RATHER THAN CHOOSING ONE.** `Admission#claim` takes the frontier advisory lock and then writes `crawl_budget_counters`, whose foreign key to `crawls` takes `FOR KEY SHARE` on that row. `retire` does the same through the outcome row's foreign key. Frontier THEN crawls is therefore the subsystem's established order, and the checkpoint now takes `lock_frontier` before `lock_crawl` — one statement, no new lock object, and it fences every in-flight retirement because `retire` holds that advisory lock for its whole transaction.

**CORRECTION (round 2, ADR-112 observation 1; recorded in place per the convention ADR-097 set for its own refutations). THE SENTENCE ABOVE IS TRUE OF THREE OF THE FOUR WRITERS AND FALSE OF THE FOURTH.** `Handlers::StartCrawl` takes the `crawls` ROW lock first, in `store.start`'s compare-and-set, and only then the frontier advisory lock, in `Frontier#seed_roots`. So "the subsystem's established order" was not established everywhere, and the repair conformed to an order three writers happened to share rather than to one the subsystem enforced. No reachable interleaving was demonstrated — a `crawl_terminal_deadline` action for a Crawl cannot exist until that same StartCrawl transaction commits, and a redelivered StartCrawl refuses before the compare-and-set — so this is a latent hazard rather than a live defect, and it is tracked as FU-38. **The direction the repair took is unchanged and is still the right one**; what was wrong was the claim that nothing could take the locks the other way round. ADR-113 relies on the corrected statement rather than this one: it takes a plain SELECT on `crawls` inside `retire` precisely so that it adds no new ordering.

**The obvious alternative was rejected, and it is the one the reviewing lens proposed.** Having `retire` take the crawls row lock before `lock_frontier` would repair this race and invert the order against `Admission`, which is how a deadlock is built. A repair that fixes one interleaving by creating the conditions for another is not a repair. The lens's own RACE 8 supplies the supporting evidence for the direction taken: once the outcome INSERT has run, the foreign key's key-share lock ALREADY blocks the checkpoint, which then counts correctly — so the only gap was the window before that INSERT, and the frontier lock closes exactly it.

Proof standard. PROOF 91 suspends `retire` between its terminalize and its INSERT with a trigger — the technique `FailureInjector` already establishes — and asserts, from `pg_locks`, that the checkpoint BLOCKS on the frontier key, then that it counts the committed retirement (`documents: 1`, `completed / full`, reservation `committed`).

**`RaceHarness#interleave` could not express this, and the reason is the repair itself.** `interleave` runs its `while_committing` operation to completion while the gated one is held; under this repair the checkpoint blocks on the lock the gated pass holds, so it would never complete and the harness would deadlock against its own gate. The example therefore uses the harness's primitives directly — the same `pg_locks` observation and the same "nothing is ordered by a sleep" rule — and asserts the blocking as the property under test rather than as a precondition. Mutation: removing the `lock_frontier` statement fails PROOF 91 at exactly that assertion, because the checkpoint no longer blocks.

Authority And Precedence:
Repairs B7 of `S-07-009_ACCEPTANCE_REVIEW.md`. WORKFLOW_SPECIFICATIONS.md :458 governs the serialized checkpoint; :453 and MTX-030 govern the state and the commit-or-release the defect corrupted. Allocated the next unused number after ADR-104.

## ADR-106: B8 Repaired — The Cadence Decision And The Renewal Are Made Under One Lock

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: standing delegation ADR-061; repair of an ADR-080 acceptance-round finding
Reversibility: Integration branch only. One statement added to `CrawlDriver#renew_entitlement_lease`; no schema change, no change to frozen F-05.

`renew_entitlement_lease` read the reservation with a plain SELECT, decided `heartbeat_due?`, and then called `Entitlement::Service#heartbeat`. That method locks and re-reads — but it never re-checks the CADENCE, because its contract is "renew this lease", not "renew it if due". The decision and the act were therefore made against different views of the same row.

**Two deliveries of one `crawl_fetch_due` are ordinary, and `CrawlStartStore` says so in its own words**: "the transport recovers an expired worker lease and re-dispatches". Both read the same stale row, both decided "due", and the loser then either

- violated `entitlement_lease_heartbeats_advances` (`renewed_lease_expires_at > prior_lease_expires_at`) as an **unhandled `PG::CheckViolation` out of the workflow**, when its clock was the earlier of the two; or
- wrote a **third heartbeat inside one five-minute window**, which refutes in terms the claim ADR-100 and this method's own comment both make — that the cadence is read from committed state so "two deliveries of one action compute the same answer".

**The repair takes F-05's own `lock_reservation` before the read.** The loser blocks, re-reads `last_heartbeat_at` as the winner left it, and finds the renewal no longer due. Nothing in frozen F-05 changes, and no new lock object is introduced — this is the lock `Service#heartbeat` already takes, taken one statement earlier so that the decision it informs is made under it.

Proof standard. PROOF 92 suspends the winner INSIDE its heartbeat, holding the reservation row, and requires the loser to be OBSERVABLY contending for that row before releasing. The observation is worth recording because it is not the harness's usual one: a `SELECT ... FOR UPDATE` waiter registers as an ungranted `transactionid` (or `tuple`) lock waiting on the holder's transaction, **not** as an ungranted lock on the relation — so `RaceHarness#blocked_on`, which reads advisory keys, cannot express it. The loser's clock is deliberately the EARLIER of the two, which is the interleaving that produced the `PG::CheckViolation`. Assertions: neither delivery raised, exactly one heartbeat row at generation 1, and the lease advanced from the winner's instant. Mutation: removing the `lock_reservation` statement reproduces the reported `PG::CheckViolation` verbatim.

Authority And Precedence:
Repairs B8 of `S-07-009_ACCEPTANCE_REVIEW.md`. WORKFLOW_SPECIFICATIONS.md :551 governs the renewable lease and its cadence; ADR-100 introduced the caller this corrects. Allocated the next unused number after ADR-105.

## ADR-107: B1 And B2 Repaired — :458's Third Sentence, And The Wall Clock Recorded Where It Ends The Run

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: standing delegation ADR-061; repair of two ADR-080 acceptance-round findings
Reversibility: Integration branch only. One limb on `Handlers::CancelCrawl`, one observation on `Handlers::CompleteCrawl`, one reader on `CrawlStartStore`; no schema change.

Two findings, one omission: neither the cancel path nor the checkpoint compared `now` with `crawls.deadline_at`, which `lock_crawl` returns to both.

**B1 — :458 HAS THREE SENTENCES ABOUT THE BOUNDARY AND THE IMPLEMENTATION CARRIED TWO.** The third reads: "At exactly the 60-minute boundary the WALL-CLOCK TERMINAL HANDLER WINS over a simultaneous cancellation." ADR-102 quotes the first two and stops at the second full stop, and so did the handler. The first two are settled by commit order and the row lock makes that a fact; the third cannot be, because it is an ASYMMETRY at an instant. Without it, whether a cancellation at minute sixty-one won was decided purely by whether the transport had yet delivered `crawl_terminal_deadline`.

**It is also a metering escape, which is why the security lens owned it.** :551 releases a reservation for a cancellation before the durable commit point; the checkpoint COMMITS one for a completed run. A `crawl.cancel` holder could therefore let a run consume its full sixty minutes of work and then cancel ahead of the checkpoint, choosing the release limb over the commit — repeatedly, from an ordinary MarketingOperator's authority. `>=`, not `>`, because "at exactly the boundary" is the case the sentence exists to settle; the mutation to `>` fails PROOF 93.

**B2 — A RUN ENDED BY ITS OWN WALL CLOCK RECORDED NOTHING ABOUT IT.** `Admission` observes the crossing when a PASS arrives past the deadline. The case the deadline action EXISTS for is the one where no pass ever does — FU-22's pinned run, and any run whose chain simply stopped — so :458's "any in-scope candidate not evaluated because of … wall-clock bound makes coverage partial AND RECORDS ITS EXACT LIMIT REASON" had no reason to record, and the run read `partial_source_failure` where :442 requires `limit_reached`.

The checkpoint now observes both thresholds before it counts, through the existing `Wf005::LimitDecisions`. **The decision table is the idempotence**: `crawl_limit_decisions` is unique on `(crawl_id, limit_dimension, threshold_kind)`, so a pass that already observed the crossing makes this a no-op and `CrawlLimitReached` still fires exactly once per dimension and run (PROOF 97). Nothing here counts or decides — the count reads the decision table like any other source, so the selection is derived identically whether a pass or the checkpoint recorded it. Both thresholds independently, for the reason `Admission#wall_clock` already records: a run that crossed the hard bound crossed the soft one on the way past it.

":442 — record … AFFECTED SOURCE AND URL COUNTS" is answered from the frontier rather than assumed: `CrawlStartStore#unevaluated_reach` counts the candidates the clock abandoned and the distinct Sources they belong to, over the SAME population `terminal_facts` counts as `unevaluated`, so the decision a customer reads and the coverage number they read cannot describe different sets.

Proof standard. PROOFs 93 and 94 bracket the instant from both sides — refused AT the boundary and one second past it, admitted one second before — so the limb is a boundary rather than "cancellation is unavailable near the end". PROOFs 95-97 cover the crossing recorded, the crossing correctly NOT recorded inside the deadline, and the idempotence against a pass that already made it. PROOF 97 records that its run reads `failed` rather than `limit_reached`, which is :458's precedence and not a defect: it halted on the clock before fetching, so it yielded zero valid Documents. Three mutations: removing the cancel limb fails PROOF 93; weakening `>=` to `>` fails PROOF 93; removing the checkpoint's observation fails PROOF 95.

A harness note worth recording: these examples seed a session AT the instant under test. The bootstrap session is issued at `fixed_now - 300` and is correctly `session_invalid` an hour later, which is real behaviour and not the property under test — a cancellation at the sixty-minute boundary is issued by someone who signed in near it.

Authority And Precedence:
Repairs B1 and B2 of `S-07-009_ACCEPTANCE_REVIEW.md`. WORKFLOW_SPECIFICATIONS.md :458 governs the boundary and the precedence, :442 the wall clock and what a hard limit records, :551 the release-versus-commit the escape exploited. Corrects ADR-102, which quoted :458 incompletely. Allocated the next unused number after ADR-106.

## ADR-108: B9 Repaired — Each Counted Fact Now Decides Something A Run Can Be Wrong About

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: standing delegation ADR-061; repair of an ADR-080 acceptance-round finding
Reversibility: Integration branch only. Specs and one spec helper; no production change.

`TerminalSelection` was proved exhaustively as a pure function with its facts handed in by hand. The SQL that SUPPLIES those facts — the part that can actually be wrong — had no behavioural anchor at all. Zeroing `uncovered`, `fetch_failures` or `hard_limits` in `count_facts` each left 218 examples green.

`uncovered` is :458's coverage denominator, so zeroing it turns `partial` into `full` — **the single error direction `CoverageClassification`'s own header says it exists to prevent** — and no example noticed. `completion_reason = 'limit_reached'` was never written to a real `crawls` row anywhere in the suite; it existed only inside the pure-function spec.

**TWO PROPERTIES OF THE RUN HAD TO BE ARRANGED BEFORE EITHER FACT COULD DECIDE ANYTHING**, and getting them wrong is what made the first three attempts at these examples prove nothing:

- **:452 makes a Source root succeed ONLY when its own depth-zero URL creates a Document.** A run whose single root failed is therefore `failed` by :453's second limb whatever else it fetched, and the fact under test never reaches the coverage question. Both examples use TWO Sources: one root succeeds, the other carries the defect.
- **The failure must not also trip a hard limit**, or `limit_reached` masks it. PROOF 98 uses three 5xx responses: :444 exhausts them into `content_fetch_failed`, and a 5xx trips no per-fetch hard limit — only a timeout, an over-limit body or redirect exhaustion do.

Two harness defects were found and fixed in the course of this, both of which had been silently weakening existing examples:

1. **`drain` executed every pass at `start_now`.** :444's retries are due at `completed_at + 30s`, so the handler refused them `scheduled_action_not_due` and every chain stopped one pass in. No example that needed a retry had been getting one. Each pass now runs at its own due instant, which is what the transport does.
2. **`outbound_by_path` answers as ONE canonical host** whatever it was asked. That is invisible with a single Source and silently fails a second Source's fetch on :436's final-URL scope check — which is exactly what happened, producing `policy_excluded / redirect_policy_denied` for a URL nothing had refused. `outbound_by_host_path` answers as the host it was asked.

Proof standard. PROOF 98 (a `content_fetch_failed` outcome decides `partial` and `partial_source_failure`, with `hard_limit_decisions` asserted at zero so the reading is unambiguous) and PROOF 99 (a REAL per-URL body limit recorded by the accepted observation point decides `limit_reached`, with a Document present so `failed` does not outrank it). Three mutations, each previously surviving at 218/0: `uncovered → 0` and `fetch_failures → 0` each fail PROOF 98; `hard_limits → 0` fails PROOF 99 and PROOF 95.

Authority And Precedence:
Repairs B9 of `S-07-009_ACCEPTANCE_REVIEW.md`. WORKFLOW_SPECIFICATIONS.md :442, :452 and :458 govern the facts and the precedence. No production behaviour changes; what changes is whether the suite can tell a correct implementation from an incorrect one. Allocated the next unused number after ADR-107.

## ADR-109: B10 Repaired — :458's "Once" Is Now Proved As A Race, Not As A Sequence

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: standing delegation ADR-061; repair of an ADR-080 acceptance-round finding
Reversibility: Integration branch only. Specs and one spec helper; no production change.

ADR-101 and ADR-102 both rest their central claim on the `FOR UPDATE` in `CrawlStartStore#lock_crawl`. **Deleting it left 218 examples green.** PROOF 64 and PROOF 82 are sequential; PROOF 65 mutates the row with the inspector before it acts. Nothing in the suite ran the two commands against each other.

**The failure mode if the lock is lost is the exact class ADR-103 was written to repair.** Both terminal handlers raise `Platform::InvariantViolation` on a lost compare-and-set, so the loser of a genuine race surfaced an invariant failure instead of :458's ratified `crawl_already_terminal` — timing deciding whether an ordinary race is a domain refusal or an invariant failure, which ADR-103 calls "the defect". The mutation reproduces it verbatim: `Platform::InvariantViolation: crawl terminal checkpoint lost its serialized transition`.

PROOFs 100 and 101 race `CompleteCrawl` and `CancelCrawl` against each other in BOTH orders and require the loser to report the ratified refusal.

**`RaceHarness#interleave` is unusable for this, for the same reason it was unusable in PROOF 91**, and the reason is worth stating once for whoever writes the next one: `interleave` runs its `while_committing` operation TO COMPLETION while the gated one is held, and here the gated operation holds the crawls row — so the committing one blocks on it and the harness deadlocks against its own gate. `race_on_the_crawl_row` expresses it with the primitives instead: gate the winner inside its transaction at its first statement, start the loser, observe the loser CONTENDING for the row, then release. The observation is an ungranted `transactionid` (or `tuple`) lock rather than an advisory key, because that is how a row-lock waiter registers — `blocked_on` cannot see it.

Authority And Precedence:
Repairs B10 of `S-07-009_ACCEPTANCE_REVIEW.md`. WORKFLOW_SPECIFICATIONS.md :458 governs the serialized checkpoint and the `crawl_already_terminal` token. No production behaviour changes. Allocated the next unused number after ADR-108.

## ADR-110: B3, B4 And B5 Repaired — The Envelope The Catalogue Defines, And The Link That Was Never There

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: standing delegation ADR-061; repair of three ADR-080 acceptance-round findings
Reversibility: Integration branch only. One migration (reversible, exercised), three envelope changes, one rewritten proof.

**B4 — the `crawl_terminal` extra schema is three members and the repository emitted two.** API_CONTRACTS.md :956: "`coverage_status` …, `completion_reason` …, AND `accepted_document_count: uint53`; values are null/zero before terminal derivation." `grep` over the repository returned nothing. The checkpoint computed the value — `facts.documents` — two lines before building the envelope and discarded it. Added to all three terminal events this block owns. `CrawlQueued` and `CrawlStarted` carry the same profile, also omit it, and both predate this range; that is recorded as FU-33 rather than repaired inside an acceptance round, because editing accepted blocks is a separate decision.

**B3 — two producers of `CrawlFailed` disagreed.** :808 gives `CrawlFailed` and `CrawlCanceled` the reason source `transition`; :938 requires the `state_transition` base member `transition_reason_code`, and that root `reason_code` "equals it exactly when the catalogue source is `transition`". Both terminal envelopes supplied neither — while WF-005's OWN pre-execution `CrawlFailed` in `Handlers::StartCrawl` set the root reason, and `CrawlStartStore`'s own comment asserted the machine reason "is retained where the contract puts it — the `CrawlFailed` envelope". `CrawlCompleted` correctly keeps both null: :807 gives it the source `none`, and :938 says a `none` source requires null.

**B5 — `source_id` was a Project-owned link with no foreign key at all, and the proof written to catch that could not see it.** `20260727120350` declared the column, constrained the other two, and omitted the third under a comment invoking :128 and FU-7 BY NAME. It was the only table in the schema carrying `source_id` without one; nine siblings have it. Probed as `f1_web`, it admitted both a cross-Project `source_id` and a fabricated UUID.

**The proof's blindness is the more important half.** PROOF 39 enumerated `pg_constraint … contype='f'` and asserted arity 3 on each row returned. **An absent foreign key has no arity**, so it passed on the two that existed while its own title — "so coverage cannot cross a Project" — was false. It now asserts the expected link SET first, and only then the arity. **CORRECTION (round 2, ADR-112 observation 3): the expected set is a LITERAL, not "derived from the columns that name a Project-owned parent" as first written here.** It catches a removed or missing link on the three columns it names, which is what B5 needed, and it would also fail on a legitimately added fourth link. Deriving the expectation from the schema — and doing it for every Project-owned foreign key rather than for one table — is FU-7's own standing recommendation, and the deriving check belongs there rather than here. A check that reads what is there cannot find what is missing, and this is the shape of check that must be preferred wherever :128 is asserted.

Proof standard. PROOF 102 (`CrawlCompleted` carries the count and a null reason), PROOF 103 (`CrawlFailed` carries both reason fields), PROOF 80 extended for `CrawlCanceled`, PROOF 39 rewritten as a link-set assertion and PROOF 39b for its behaviour. Three mutations: dropping the foreign key fails PROOFs 39 and 39b; dropping `accepted_document_count` fails PROOFs 102 and 103; dropping the transition reason fails PROOF 103. Migration reversibility exercised down and up.

Authority And Precedence:
Repairs B3, B4 and B5 of `S-07-009_ACCEPTANCE_REVIEW.md`. API_CONTRACTS.md :807-808, :938 and :956 govern the envelope; POSTGRESQL_SCHEMA.md :128 governs the link, and its `crawl_terminal_outcomes` row is reconciled. Opens FU-33 for the two pre-existing omissions. Allocated the next unused number after ADR-109.

## ADR-111: B6 And B11 Repaired — A Refutation That Was Itself False, Corrected In Four Places And Pinned

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: standing delegation ADR-061; repair of two ADR-080 acceptance-round findings
Reversibility: Integration branch only. Record corrections and one new proof; no production change.

**B6.** ADR-097, `20260727120340`'s header, `POSTGRESQL_SCHEMA.md`, the FU-11 note and PROOF 29's own comment all stated that the `IS NOT DISTINCT FROM` rewrite of `crawls_coverage_status_check` "yields TRUE" and was "a proven no-op, evaluated against the live cluster". Evaluated live:

```
NULL = ANY(ARRAY['full','partial'])                        -> UNKNOWN        a CHECK ADMITS
NULL IS NULL OR NULL = ANY(ARRAY['full','partial'])        -> true           a CHECK ADMITS   (PROOF 29)
NULL IS NOT DISTINCT FROM 'full' OR ... 'partial'          -> false          a CHECK REFUSES
NULL IS NOT DISTINCT FROM ANY(ARRAY['full','partial'])     -> SYNTAX ERROR
```

**The form as named does not parse, and its only valid spelling would refuse every `queued` and `running` Crawl** — those rows carry NULL in that column by design. So the claim was not merely imprecise: it was the opposite of true, and it cannot have been evaluated as written. PROOF 29 pins a DIFFERENT expression (`x IS NULL OR x = ANY(...)`), which genuinely is a no-op, so the proof never tested the proposition the record stated.

**This is the more dangerous of the two error shapes in this round.** That record exists specifically to stop a future implementer from applying the wrong fix after rediscovering the original reasoning, and as written it told them the wrong fix was harmless. The substantive conclusion is unaffected and was re-verified: the fault was `crawls_terminal_shape`, and `crawls_coverage_status_check` is correctly untouched.

All five statements are corrected in place rather than superseded, per the convention ADR-097 itself set for its own refutations. PROOF 104 pins the correction: the pairwise form is FALSE (not UNKNOWN — asserted separately, because UNKNOWN would be admitted and is the whole distinction), the `ANY(...)` form raises `PG::SyntaxError`, and a live `queued` Crawl is demonstrated to fail the predicate.

**B11.** `BUILD_STATE.next_action` said twice that FU-30 was "deliberately deferred" and "STAYING OPEN" while `open_decisions[FU-30].status` read `resolved`; it also said "seven commits" against nine and omitted ADR-103, ADR-104 and FU-32. `next_action` is what the controller reads. It has been rewritten at each repair in this round and now describes the state that exists.

Authority And Precedence:
Repairs B6 and B11 of `S-07-009_ACCEPTANCE_REVIEW.md`. Corrects ADR-097 in place. No production behaviour changes. Allocated the next unused number after ADR-110.

## ADR-112: S-07-009 Round 2 — Still NOT ACCEPTED; B7 Was Reported Closed And Is Not, And The B2 Repair Introduced A Defect

Status: Accepted (review record; standing delegation ADR-061; review discipline per ADR-026 and ADR-080)
Date: 2026-07-31
Owner: independent reviewer (no share in the repairs, no prior conversational state) / recorded
Reversibility: A review record and the follow-ups it opens. No production code changed in this round. Nothing merged, nothing pushed, no acceptance transition made.

The full five-lens round was re-run against the repaired candidate `7f043a2..95d37f4` — the whole block, not the repairs alone, because a repair is candidate material. **All five lenses returned FAIL. Three confirmed-blocking findings. S-07-009 REMAINS NOT ACCEPTED.** Detail, reproductions and the lens marginal-contribution table are in `S-07-009_ACCEPTANCE_REVIEW.md` § ROUND 2.

**NINE OF THE ELEVEN ROUND-1 BLOCKERS ARE INDEPENDENTLY CLOSED.** B1, B3, B4, B5, B8, B9, B10 and B11 were re-verified against the contracts and, where the repair ADRs named a mutation, by applying it: all fourteen named mutations were applied and reverted independently against the 721-example WF-005 acceptance surface, and every one kills its named proof. Round 1's four signature survivals — `uncovered → 0`, `fetch_failures → 0`, `hard_limits → 0` and `FOR UPDATE` deleted, each at 218/0 — are genuinely gone.

**R2-B1 — B7 IS NOT CLOSED, AND IT IS AGAIN THE ROUND'S MOST SERIOUS FINDING.** ADR-105 took the frontier advisory lock before the Crawl row lock, which fences a retirement already in flight. **A pass in its FETCH holds no lock at all**: `fetch_and_settle` performs the network request outside every transaction, correctly, and only afterwards opens `retire`'s transaction. ADR-105 states "the only gap was the window before that INSERT, and the frontier lock closes exactly it" — it closes the part of that window inside `retire`, not the part inside the fetch, **which is the window round 1's own reproduction (c) used** ("a 150 ms fetch with the checkpoint fired 50 ms in, 10/10"). Reproduced against HEAD three times out of three, byte-for-byte the state round 1 recorded: `crawls` `state=failed / completion_reason=failed / coverage_status=NULL`, reservation `released`, and `crawl_terminal_outcomes` saying `document_created / covered`. Still unrecoverable, because ADR-099's terminal freeze refuses every UPDATE of a terminal row. The CONTRACT lens reached the same place from the other end and named the missing rule: WORKFLOW_SPECIFICATIONS.md :442's "at 60 elapsed minutes, no new request starts **and incomplete requests are canceled**" — only the first half is implemented, `Admission`'s own comment says so, and no follow-up owns the second (FU-32 covers `CancelCrawl` only and says in terms that :442's wall-clock cancellation is a different obligation). The SECURITY lens establishes the metering half: a run that reached `crawl_completed_with_valid_document` in fact has its reservation released by timing.

**R2-B2 — THE B2 REPAIR INTRODUCED A NEW WRONG ANSWER.** `CompleteCrawl#observe_wall_clock` records the soft and hard `wall_clock_run_duration` crossings whenever `now >= deadline_at`, with no reference to whether the clock abandoned anything: the predicate is the CHECKPOINT'S DELIVERY INSTANT, not :458's "any in-scope candidate not evaluated". Reproduced deterministically — a run whose only candidate was fetched, whose frontier is entirely `terminal`, `uncovered 0 / unevaluated 0 / documents 1`, terminalized by its own deadline action, reads `completion_reason=limit_reached` and `coverage_status=partial` with a hard decision recording `affected_url_count 0 / affected_source_count 0`, and emits a real `CrawlLimitReached` for a dimension that bounded nothing. Four ratified sentences break at once (:458's `full` test, :458's precedence, :442's "affected Source and URL counts" and :442's exactly-once event). Before ADR-107 that run read `completed / full`, so this is a regression, and the terminal freeze makes it permanent. Transport latency alone now changes a customer's coverage verdict. All three of the repair's own proofs avoid the shape: PROOF 95 seeds an unevaluated candidate, PROOF 96 runs inside the deadline, PROOF 97's run yielded zero Documents.

**R2-B3 — B6'S CORRECTION MISSED A FIFTH PLACE, AND IT IS THE PLAINEST ONE.** ADR-111 corrected ADR-097, the `20260727120340` header, `POSTGRESQL_SCHEMA.md`, the FU-11 note and PROOF 29's comment. `DECISIONS.md:2236` — ADR-083, an ACCEPTED record and the one a reader tracing FU-11's history reaches first — still states "`IS NOT DISTINCT FROM` is admitted too". Re-evaluated live this round, confirming ADR-111 and refuting ADR-083: the pairwise form yields FALSE (a CHECK REFUSES) and the `ANY(...)` form is a syntax error. A blocker whose whole content is "a ratified record states the opposite of the truth" is not closed while a ratified record still states the opposite of the truth.

**WHAT THE ROUND SAYS ABOUT THE REPAIR PHASE, WHICH IS ITS REAL FINDING.** Every mandatory gate passes from the reviewed state — rspec **2055/0**, brakeman 0, packwerk clean, zeitwerk ok, bundler-audit clean, `verify_runtime` OK 15 checks with RLS intact, architecture fitness 58/0, no `structure.sql` drift, the schema **built from empty on a scratch database dumps byte-identical**, and all five migrations reverse and re-apply byte-identical — and the block still fails. **Two of round 2's three blockers are IN THE REPAIRS**: one closed the smaller half of its own window, one introduced a new defect, one stopped a place short. Every one of the fourteen mutations passes. **A mutation proof shows a repair is load-bearing; it never shows the repair is complete or correct.** Round 2 exists because round 1's repairs were not themselves reviewed; round 3 must review round 2's the same way. Eleven falling to three is what a successful repair phase and a failing one both look like from outside, and only re-running the round tells them apart.

Nine observations are recorded with lens attribution, including one that matters for the next repair: **ADR-105's central premise is factually false.** It argues the checkpoint "conforms to an order that already existed", but `Handlers::StartCrawl` takes the `crawls` row lock (`store.start`) BEFORE the frontier advisory lock (`Frontier#seed_roots`). No reachable interleaving was demonstrated — a `crawl_terminal_deadline` action cannot exist until that same StartCrawl transaction commits — but the invariant the repair rests on is not true of all four writers and nothing enforces it. Also recorded: `BUILD_STATE.implementation_commit`, `last_verified_commit` and `review_commit` remain inconsistent one field over from B11, which repaired `next_action` only.

The two harness corrections were reviewed as production test infrastructure and both are **correct and strictly stronger**: per-pass due-instant execution in `drain` (without which no :444 retry had ever run, silently) and `outbound_by_host_path` answering as the host it was asked (without which a second Source's fetch failed :436's final-URL scope check for a URL nothing had refused). Their placement outside the shared `Wf005CrawlChain` support module is recorded as an observation.

Authority And Precedence:
Records round 2 of the ADR-026 five-lens acceptance review required for S-07-009 by ADR-080's process correction. Re-opens B7 and B6 of `S-07-009_ACCEPTANCE_REVIEW.md` and finds ADR-107's repair defective; corrects ADR-105's stated premise. Makes NO acceptance transition. Opens FU-34, FU-35 and FU-36 in `BUILD_STATE.open_decisions`. Allocated the next unused number after ADR-111.

Review Checkpoint:
Repair in the order R2-B1, R2-B2, R2-B3, then the observations, then the 24 carried from round 1. Re-run the FULL five-lens round against the next repaired candidate, and review the repairs themselves as candidate material.

## ADR-113: FU-34 Repaired — :442's Cancellation Rule Implemented, Not The Interim Guard

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: Owner (decisive ruling: "Implement the ratified cancellation rule, not merely the interim guard. That is the repository-consistent choice because the contract already exists. The interim guard would make the contradiction less visible without completing the promised behaviour.") / implementation agent (recorded)
Reversibility: Integration branch only. Two files, no schema change, no new lock object, no change to frozen F-01.

Round 2 (ADR-112) found that B7 was reported closed and was not. ADR-105 took the frontier advisory lock before the Crawl row lock, which fences a retirement ALREADY INSIDE `retire`. **A pass in its FETCH holds no lock at all** — `fetch_and_settle` performs the network call outside every transaction, correctly, per MTX-030 — so the checkpoint could still count a snapshot the pass invalidated, and the review reproduced the original corrupt state 3/3 against the repaired candidate.

**THE OWNER RULED FOR THE RATIFIED RULE OVER THE SMALLER ONE, AND THE RULE ALREADY EXISTED.** WORKFLOW_SPECIFICATIONS.md :442: "At 60 elapsed minutes, **no new request starts and incomplete requests are canceled**." Only the first half was implemented, and `Workflows::Wf005::Admission`'s own comment said so in terms — "The first half is a decision about whether to hand a worker any work at all". The second half was owned by no follow-up: FU-32 covers `CancelCrawl` and states explicitly that :442's wall-clock cancellation is a different obligation.

**THE CANCELLATION IS ENFORCED AT THE REQUEST'S OWN BUDGET, AND F-01 DOES NOT CHANGE.** The frozen façade takes `timeout_s` and states that a caller "may ask for tighter, never wider", so `FetchContent#request_budget` bounds each request by the run's REMAINING wall clock whenever that is tighter than :390's resolved per-request ceiling. A request that would still be in flight at `deadline_at` now ends AT `deadline_at`: the customer's site is not still being read by a run that is over, and the bytes are never received. Past the deadline no request is made at all, which is the sentence's first half enforced at the request rather than only at admission. No new path to the network exists and `outbound_single_surface_spec` is untouched.

**A CANCELLED REQUEST IS NOT A FAILED URL, AND THE DISTINCTION IS THE POINT.** :452 classifies an exhausted timeout as `content_fetch_failed` — a failure of the URL, in the denominator, RETRYABLE. A request the run's own sixty minutes ended is :458's "in-scope candidate NOT EVALUATED because of … wall-clock bound", which is `limit_discarded` carrying ":454's exact limit reason", in the denominator, and owed no retry because :442 says to "stop scheduling affected work". Filing one as the other would blame the customer's site for the run's clock and would schedule two more requests a finished run may not make. The reason token is BOUND to `Admission::WALL_CLOCK` rather than spelled a second time: the clock refusing to start a request and the clock ending one are the same fact.

**THE SECOND HALF IS AN ORDERING, AND IT IS NOT A SUBSTITUTE FOR THE FIRST.** The clamp cannot reach the last microsecond: a request that COMPLETES at `deadline - ε` can still have its retirement commit at `deadline + ε`. `CrawlDriver#retire` therefore re-reads `crawls.state` **under the frontier advisory lock it already takes**, which is the same lock `Handlers::CompleteCrawl` takes first (ADR-105) — so exactly one of the two transactions holds it and the read is authoritative rather than advisory. Retirement first: the checkpoint blocks, the run is still `running`, the outcome commits, and the checkpoint counts it. Checkpoint first: it has committed its terminal selection, this read sees it, and the pass writes NOTHING — because :458 gives the run ONE selection and `f1_crawls_guard` refuses every edge out of a terminal state, so there is no state in which the classification could be counted. :458 settles exactly this by COMMIT ORDER, as it does for cancellation. A plain SELECT is deliberate: taking a row lock on `crawls` here would order this transaction crawls-then-frontier against `Admission`'s frontier-then-crawls, which is the inversion ADR-105 rejected for the driver. The same re-read is taken on `retire_unfetchable`, which writes the same kind of row.

**WITHOUT THE CANCELLATION, THE RE-READ WOULD BE THE INTERIM GUARD THE OWNER REJECTED** — silently discarding valid Documents for up to a full request timeout after the run ended, which suppresses the contradiction instead of removing it. The two halves are one repair and each is falsified separately below.

Proof standard. Seven proofs, and the adversarial set is the point: **every plausible INCOMPLETE repair fails a named proof.**

| incomplete repair | proofs that fail |
| --- | --- |
| no authoritative re-read in `retire` (checking only before the network call) | 110, 111 |
| no wall-clock clamp (checking only after terminalization; suppressing the outcome without cancelling) | 105, 107 |
| a cancellation classified as an ordinary failure | 106, 108 |
| a request may still START past the deadline | 108 |
| EVERY timeout treated as a wall-clock cancellation | 109 + 13 accepted examples |
| locking only inside retirement | 91 |
| write the outcome, then hide it in the pass report | 110, 111 |

PROOF 110 reproduces round 2's race at the natural window with NO trigger gate — the F-01 stub simply does not return until the example lets it, and the checkpoint is started only once the pass is OBSERVED inside the request — and asserts `crawl_terminal_outcomes` is EMPTY. PROOF 111 re-derives the recorded selection from the facts that exist through `TerminalSelection.derive` and asserts entitlement, coverage, outcomes, the attempt row and the frontier entry are mutually consistent; the attempt row is deliberately NOT suppressed, because the request completed and :442's "run-wide accounted bytes are EXACTLY sum(...)" must stay reproducible.

Gates: whole-repo suite **2062/0**; brakeman 0; packwerk clean; zeitwerk ok; bundler-audit clean; verify_runtime OK, 15 checks, RLS intact; no `structure.sql` drift.

Authority And Precedence:
Repairs FU-34 / R2-B1 of `S-07-009_ACCEPTANCE_REVIEW.md` § ROUND 2. Implements WORKFLOW_SPECIFICATIONS.md :442's second sentence, which was ratified and unimplemented; :452 and :458 govern the classification; MTX-030's "no external call sits inside a database transaction" is preserved. Corrects ADR-105, whose claim that the frontier lock closed the window was true only of the window inside `retire`. Changes no frozen foundation: F-01 is consumed through `timeout_s` exactly as its own contract invites. Allocated the next unused number after ADR-112. S-07-009 is NOT accepted by this commit.

Review Checkpoint:
Round 3 must race the checkpoint against a pass that is mid-REQUEST, not mid-retirement, and must confirm that a request cancelled by the run's clock is `limit_discarded` rather than `content_fetch_failed`.

## ADR-114: FU-35 Repaired — The Wall Clock Records What It Actually Bounded, Not When The Handler Arrived

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: standing delegation ADR-061; repair of an ADR-112 round-2 finding
Reversibility: Integration branch only. One predicate in `Handlers::CompleteCrawl`, one widened read in `CrawlStartStore`; no schema change, no migration.

ADR-107 gave the terminal checkpoint a wall-clock observation, because a run ended BY its own sixty minutes recorded nothing about them. The observation was gated on `now >= deadline_at` — **the checkpoint's DELIVERY INSTANT** — and round 2 showed what that costs: a run that fetched every in-scope candidate and drained was permanently recorded `completion_reason = limit_reached`, `coverage_status = partial`, with a hard `wall_clock_run_duration` decision recording `affected_url_count 0` and `affected_source_count 0`, and a real customer-visible `CrawlLimitReached` for a dimension that bounded nothing. Before ADR-107 the same run read `completed` / `full`, so it was a REGRESSION, and `f1_crawls_guard` refuses every correction.

**THE PREDICATE IS WHETHER THE DEADLINE PREVENTED AN EVALUATION.** :458 conditions the rule on there being something to condition it on — "**any in-scope candidate NOT EVALUATED** because of … wall-clock bound makes coverage partial and records its exact limit reason" — and :442's record is "dimension, configured value, observed value, **affected Source and URL counts**". A decision whose affected counts are zero is a decision nothing was affected by, which is not a limit hit but the absence of one. The count is now read FIRST and IS the predicate, not merely a field of the record.

**BOTH LIMBS ARE GATED, NOT ONLY THE HARD ONE.** A `CrawlSoftLimitApproaching` for a run that finished its work forty minutes earlier is the same false statement in a quieter voice, and `elapsed` here is measured to the checkpoint's ARRIVAL rather than to the end of the run's work, so on a drained run it is not the run's working duration at all. The mutation that gates only the hard limb fails three proofs.

**THE AFFECTED MEASURE HAS TWO POPULATIONS, BECAUSE ADR-113 CREATED THE SECOND.** `CrawlStartStore#unevaluated_reach` now unions the candidates the run never reached — the same population `terminal_facts` counts as `unevaluated`, so the decision a customer reads and the coverage number they read cannot describe different sets — with the candidates whose REQUEST :442's own cancellation ended. Those entries are `terminal` and carry a `crawl_terminal_outcomes` row, so they have left the first population entirely, and they are the clearest case of a candidate the deadline prevented from being evaluated. **Omitting them would let the repair for FU-34 silently suppress the record FU-35 exists to make correct**, which is the seam between the two repairs and is proved at it.

Proof standard. PROOF 112 (a fully covered, fully drained run terminalized AT its deadline reads `completed` / `full`, with no decision row and no limit event — the regression itself), PROOF 113 (**transport latency alone cannot change the verdict**: the same run through the drained checkpoint delivered a minute late, with `unevaluated_reach` asserted at zero so the predicate is read directly rather than inferred), PROOF 114 (a **partially** covered run that left nothing unevaluated records no crossing — stated from the partial side so the rule cannot be read as "drained runs are exempt"), PROOF 115 (**the seam**: a candidate whose request the clock cancelled IS an affected candidate, counted 1 URL / 1 Source), PROOF 116 (a cancellation refused at the boundary emits neither a decision nor a limit event). PROOFs 95, 96 and 97 are unchanged and still pass: 95's run has a genuinely unevaluated candidate, which is the case the rule is for.

Four mutations, each caught: ungating the observation entirely → 112, 113, 114; gating only the hard limb → 112, 113, 114; a predicate that never fires → 112, 113, 114; dropping the cancelled-request population from the affected measure, degraded rather than raised so it reads as a real regression → 115 alone.

Gates: whole-repo suite **2067/0**; brakeman 0; packwerk clean; zeitwerk ok; verify_runtime OK, 15 checks, RLS intact; no `structure.sql` drift.

Authority And Precedence:
Repairs FU-35 / R2-B2 of `S-07-009_ACCEPTANCE_REVIEW.md` § ROUND 2. Corrects ADR-107, whose observation was gated on the wrong instant. WORKFLOW_SPECIFICATIONS.md :442 governs what a hard-limit record contains and :458 what makes coverage partial. Composes with ADR-113, which created the second affected population. Allocated the next unused number after ADR-113. S-07-009 is NOT accepted by this commit.

## ADR-115: FU-36 Repaired — A Seventh Copy Nobody Had Named, And A Check That Does Not Rely On Someone Listing Them

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: standing delegation ADR-061; repair of an ADR-112 round-2 finding
Reversibility: Record corrections and one architecture-fitness example; no production change.

ADR-111 corrected the false `IS NOT DISTINCT FROM` refutation in five places and pinned the truth with PROOF 104. Round 2 found a SIXTH — ADR-083, `DECISIONS.md:2236`, an ACCEPTED record and the one a reader tracing FU-11's history reaches FIRST. **The repository-wide sweep this repair was instructed to run then found a SEVENTH that no review had named: `specification/automation/BUILD_PLAN.yml`, in S-07-009's own blocking-precondition note**, where it read "A NULL-safe rewrite of the enum check is a PROVEN NO-OP: … `IS NOT DISTINCT FROM` is admitted too."

Both are corrected in place, per the convention ADR-097 set for its own refutations. The exact distinction is preserved in each, because it is the whole content of the finding:

```
(NULL = ANY(ARRAY['full','partial'])) IS NULL                  -> t   UNKNOWN, and a CHECK ADMITS
NULL IS NULL OR NULL = ANY(ARRAY['full','partial'])            -> t   a CHECK ADMITS  (PROOF 29)
NULL IS NOT DISTINCT FROM 'full' OR ... 'partial'              -> f   a CHECK REFUSES
NULL IS NOT DISTINCT FROM ANY(ARRAY['full','partial'])         -> SYNTAX ERROR
```

**NULL MUST BE TESTED INDEPENDENTLY, and PROOF 104 already does**: UNKNOWN is admitted by a CHECK and FALSE is not, so a proof that conflated them would pass on either and prove neither. PROOF 104 asserts the pairwise form is FALSE *and separately* that it is not NULL, raises `PG::SyntaxError` on the `ANY(...)` form, and demonstrates a live `queued` Crawl failing the intended predicate. All four required distinctions were already pinned; what was missing was the records.

**CORRECTING SEVEN COPIES BY HAND IS THE DEFECT, NOT THE REPAIR.** ADR-111 corrected the copies it had been given and missed one; round 2 found that one and did not find the seventh. That is PROOF 39's mistake in a third costume — a check that reads what someone listed cannot find what nobody listed. So the durable half of this repair is an architecture-fitness example asserting over the RECORDS THEMSELVES: no authoritative record may claim the rewrite is a no-op or admitted without the refutation being present where the claim is made.

**THE FIRST VERSION OF THAT CHECK WAS ITSELF TOO WEAK, AND IT IS WORTH RECORDING WHY.** Scoped to the enclosing section, reverting ADR-083 to its false wording still PASSED — that ADR is long and carries refutation-shaped words about unrelated matters, so the section vouched for a claim it never addressed. The check would not have caught the very defect it exists for. It is now scoped to a 700-character window around each occurrence, which is where a reader actually meets the claim, and it was verified by REINTRODUCING the defect three ways: a new ADR asserting harmlessness, ADR-083 reverted to its false wording, and `BUILD_PLAN.yml` reverted to its false wording. All three fail; the clean tree passes. The known limitation — a false claim inserted inside a window that already carries the refutation — is stated in the example rather than papered over.

`20260727120280_crawl_limit_decision_reason_null_safe` uses `IS NOT DISTINCT FROM` CORRECTLY, and for exactly the property this refutation turns on: a NULL yields FALSE, which the CHECK refuses. It is named in the check so the rule is about the refuted CLAIM and not about the operator.

Gates: whole-repo suite **2068/0**; brakeman 0; packwerk clean; zeitwerk ok; bundler-audit clean; verify_runtime OK, 15 checks, RLS intact; no `structure.sql` drift.

Authority And Precedence:
Repairs FU-36 / R2-B3 of `S-07-009_ACCEPTANCE_REVIEW.md` § ROUND 2. Corrects ADR-083 and `BUILD_PLAN.yml` in place. Completes ADR-111, which corrected five of seven. No production behaviour changes. Allocated the next unused number after ADR-114. S-07-009 is NOT accepted by this commit.

## ADR-116: The Round-2 Observations Dispositioned — Four Repaired Because They Are False Records, The Rest Carried

Status: Accepted (2026-07-31)
Date: 2026-07-31
Owner: standing delegation ADR-061
Reversibility: Record corrections, one spec comment and one catalogue move; no production change.

The three round-2 blockers are repaired (ADR-113, ADR-114, ADR-115). This dispositions the nine round-2 observations and confirms the standing of the twenty-four carried from round 1, so none is lost and none is silently repaired.

**THE LINE TAKEN.** `AUTONOMY_POLICY.md` is explicit that a repair mandate "is not permission to work on another tranche's backlog, nor to repair defects that are not blocking a mandatory gate", and the ADR-030 precedent is that governance repairs confirmed-blocking findings only. So an observation is repaired here ONLY when it is a false or misleading RECORD THIS BLOCK ITSELF WROTE — which is the B6 defect class, the one that has now cost three rounds, and which is cheap to correct and expensive to leave.

**REPAIRED** (four, all records):
- **O1 — ADR-105's central premise is false.** It justified the checkpoint's lock order with "frontier THEN crawls is the subsystem's established order". That is true of `Admission#claim`, `CrawlDriver#retire` and `CrawlFetchDueSchedule.link_next` and FALSE of `Handlers::StartCrawl`, which takes the `crawls` row lock in its compare-and-set and only then the frontier advisory lock. Corrected in place. No reachable interleaving exists — a `crawl_terminal_deadline` action cannot exist until that StartCrawl transaction commits — so the hazard is latent and tracked as **FU-38**. The repair's DIRECTION is unaffected and still right; ADR-113 relies on the corrected statement, which is why it takes a plain SELECT inside `retire` rather than a row lock.
- **O2 — PROOF 91 proves the sub-window, not the property.** Its scope is now stated in the example: it gates the outcome INSERT, so the pass it races is already inside `retire`. The general property is PROOF 110's, and ADR-105 claimed it without proving it.
- **O3 — ADR-110 overstated PROOF 39's rewrite** as "derived from the columns that name a Project-owned parent". The expected set is a literal for one table. Corrected in place; the deriving check over every Project-owned foreign key is FU-7's own recommendation and its note is amended to say the deriving half is still unbuilt.
- **O7 — S-07-009's two blockquotes split the canonical schema catalogue**, so roughly twenty-five rows from `crawl_sources` onward formed a table with no header row and rendered as literal pipe text. Moved below the table. **The identical pre-existing split at :272-274 is deliberately NOT touched**: it predates this block, and editing an accepted region to match is a separate decision. It is recorded under FU-37 instead.

**CLOSED BY A BLOCKER REPAIR**: O5 (:442's second half unimplemented and owned by no follow-up) — ADR-113.

**CARRIED, NOT REPAIRED** (three, with reasons):
- **O4 — the commit fields read as a contradiction and are not one.** `implementation_commit`, `last_verified_commit` and `acceptance_evidence` all describe the LAST ACCEPTED tranche, and `spec/architecture/repository_truth_spec.rb` enforces that pairing — they cannot be repointed at an unaccepted tranche without breaking the invariant that catches a fabricated acceptance. The defect is the controller schema's NAMES, not the values. A reconciliation sentence now says which tranche each field describes, which removes the ambiguity a reader hit without weakening the check.
- **O6 — `CancelCrawl` reports `crawl_already_terminal` for a Crawl that is still `running` past its deadline.** Faithful to :458's ratified token and to the repair round 1 prescribed. It does mean a run whose checkpoint delivery is lost is cancellable by no principal. That is an owner-visible product question about a ratified token, not a defect to be fixed inside a repair phase.
- **O8 — three outbound stubs across two spec files**, none in the shared `Wf005CrawlChain` module the repository extracted to end exactly this drift. Real, and against CLAUDE.md's one-canonical-source standard. Consolidating touches accepted spec files broadly and blocks no gate.

**THE TWENTY-FOUR ROUND-1 OBSERVATIONS REMAIN OPEN AND UNPROMOTED.** That includes the three `BUILD_STATE` had flagged for the re-review to decide — the FU-9 `absent`/`unavailable` reasoning, the swallowed `begin_sitemaps` refusal, and the checkpoint's claim blanking `sitemap_candidates`. Round 2 examined them and promoted none. They are carried under **FU-37** with their lens attribution intact, because a round that merges findings without provenance destroys the marginal-contribution measure it is supposed to feed.

**FU-32 AND FU-33 WERE NOT TOUCHED.** Both are owner decisions — in-pass cancellation, and `accepted_document_count` on two events in accepted blocks — and converting an owner decision into an implementation choice because it happened to be adjacent to a repair is precisely what a repair phase must not do.

Authority And Precedence:
Dispositions the observations of `S-07-009_ACCEPTANCE_REVIEW.md` § ROUND 2 and confirms the standing of § ROUND 1's. Corrects ADR-105 and ADR-110 in place. Opens FU-37 and FU-38; amends FU-7. Allocated the next unused number after ADR-115. S-07-009 is NOT accepted by this commit, and round 3 must be run by a fresh independent session.

## ADR-117: Owner Rulings For The S-07-009 Round-5 Repair Tranche — Exact Authority And Stop Boundary

Status: Authorized (2026-08-03)
Date: 2026-08-03
Owner: explicit owner ruling at the S-07-009 round-5 repair boundary
Reversibility: Integration branch only. The authorization permits the repairs below and one new frozen architecture check; it makes no acceptance transition.

The owner accepted the independent architectural memorandum's three decisions and authorized a repair tranche in an exact order. This ADR records that authority so a later diff can be tested against the permission that produced it rather than against an inferred mandate.

**PROVENANCE, CORRECTED 2026-08-04 (round-6 blocker R6-8; ADR-120).** This paragraph previously said the ADR recorded the authority "before implementation", and git refutes it: ADR-117 is absent from `f7472aa` and from its parent, and first appears in `5860bb4` alongside the repairs it authorizes. The owner's ruling did precede the work, in conversation. The written record did not, and AUTONOMOUS_BUILD_CONTROLLER.md §3.1 is explicit that "chat sessions are not authoritative state" — so a record asserting a repository order the repository does not show is the defect, not the ordering itself. The rulings below are unaffected and remain authorized; only the claim about when they were written down is withdrawn. `spec/architecture/repository_truth_spec.rb` now fails on the withdrawn sentence, so it cannot return.

**R5-3 — ADMISSION LOCKING.** `Workflows::Wf005::Admission` may change even though it belongs to the accepted S-07-008 tranche. The governing invariant is: any Admission transaction that will continue into the frontier critical section and acquire any `crawls` tuple lock, including the implicit `FOR KEY SHARE` taken by a child-row foreign key, must acquire `crawl-frontier:<crawl>` first and then re-read and re-authorize the Crawl under that lock before its first durable effect. The terminal-handler order remains frontier advisory lock then `crawls FOR UPDATE`. This authority does **not** permit reversing `CancelCrawl` or `CompleteCrawl`, removing `lock_crawl` or its `FOR UPDATE`, substituting deadlock retry for the repair, or holding the frontier lock across outbound work. The proof must exercise both orientations on real PostgreSQL, repeat the relevant orientation with `CompleteCrawl` where reachable, make decision-then-frontier fail deterministically, and prove structurally at the real `crawl_limit_decisions` insert that soft fall-through already holds the correct advisory lock.

**R5-1 — LIMIT SEMANTICS.** The owner ratified separate answers for local work-item disposition, delay, scheduling stop, hard-decision production, decision reason, terminal completion reason, coverage effect and affected-count ownership. A hard decision's `decision_reason_code = limit_reached` does not itself force `crawls.completion_reason = limit_reached`. The four residual run-stopping dimensions under WORKFLOW_SPECIFICATIONS.md :442 are `accepted_pages_per_run`, `discovered_url_queue`, `accounted_response_body_bytes_per_run` and `wall_clock_run_duration`. Rate and concurrency ceilings are pacing controls and produce no crawl-limit decision. Sitemap terminal overrides remain governed by :450. Affected Source and URL counts are the causal population known at the immutable first decision, never a later cumulative total. The memorandum's full twelve-dimension matrix is authoritative. Code, proof, comment and record must stop collapsing these questions into `hard_limits > 0`, including `RUN_STOPPING`, `other_hard_limit?`, terminal facts, PROOF 99, PROOF 131 and sitemap-derived terminal facts.

**R5-2 — THE ONE FROZEN CHECK.** Exactly `spec/architecture/wf005_time_single_surface_spec.rb` is authorized. It is limited to WF-005 PostgreSQL timestamp decoding through `Platform::PgInstant`; it must derive tracked Ruby files recursively under `app/workflows/wf005/`, parse Ruby syntax rather than comments, detect local parsing and type-dispatch decoders, prove its detector with conforming and violating synthetic examples, prove a nonempty corpus with canonical use, and directly exercise typed `Time`, text, nil, subsecond preservation, non-mutating UTC conversion and the 59.99/60-minute boundary. Existing frozen checks, `FrozenContracts`, F-01 through F-04, and any family of new checks remain out of bounds. The check may not expand into limits, locks, event envelopes, deadlines or acceptance-history derivation.

**ORDER AND TERMINUS.** Record this ruling; repair and prove R5-3; implement the canonical semantics and terminal-forcing facts; add an independent PgInstant checkpoint boundary proof; create the one authorized check; only then repair R5-4, R5-5 and state records; run every mandatory gate; inspect and commit the complete repair tranche. Do not repair unrelated backlog items. Do not commission Round 6. Do not accept S-07-009. Completion means reporting the final candidate range, gates, mutation and structural evidence and any genuine remaining owner decision, then stopping.

Authority And Precedence:
This explicit owner ruling supersedes the round-5 review's instruction to commission Round 6 and resolves the architectural owner decisions raised at that boundary. It does not supersede the contracts it interprets, broaden the tranche beyond the named repairs, authorize another frozen path, or change S-07-009's status from NOT ACCEPTED.

## ADR-118: The Owner-Commissioned Independent Review Of The Complete S-07-009 Repair — All Five Lenses Fail

Status: Accepted review record (2026-08-03); S-07-009 is NOT accepted
Date: 2026-08-03
Owner: explicit instruction to commission one fresh independent acceptance review of the complete resulting state through `cf2059e`
Reversibility: Governance record only. No candidate, production, migration, test or frozen-path repair is authorized or made.

The owner accepted the round-5 repair work as completed, then explicitly commissioned the next independent ADR-026 acceptance review against the complete resulting state through `cf2059e`: the implementation candidate pinned at `7f043a2..5860bb4` plus the record-only governance commit `cf2059e`. That instruction superseded ADR-117's earlier “do not commission Round 6” terminus for this review only. Five fresh contexts that authored none of the repair reviewed the exact resulting-state range `7f043a2..cf2059e`, one context per contract, concurrency, security, schema and architecture lens. Reviewers shared no conclusions, changed no files and were prohibited from repairing findings.

**ALL FIVE LENSES RETURNED FAIL. NINE CONFIRMED-BLOCKING FINDINGS. S-07-009 REMAINS NOT ACCEPTED.** The complete evidence and provenance are recorded in `S-07-009_ACCEPTANCE_REVIEW.md` § ROUND 6. In dependency-neutral summary: R6-1, Admission reuses a pre-wait instant and can claim after the Crawl/entitlement deadline; R6-2, hard-expired Admission and the schema can append immutable terminal facts after a terminal commit; R6-3, in-progress sitemap discovery can commit URLs/outcomes after the checkpoint; R6-4, pending sitemap state is converted to unavailable without :450's antecedents; R6-5, CancelCrawl can act on human authority revoked while it waits; R6-6, CompleteCrawl settles entitlement with a pre-wait instant; R6-7, the authorized Ripper detector admits obvious local decoder/type-dispatch spellings; R6-8, ADR-117's “recorded before implementation” claim is false in git history; R6-9, the completion report says 13 distinct outcome proof identifiers when there are 16.

Three blockers were reproduced as deterministic real-PostgreSQL/application interleavings after 91 focused examples remained green: Admission claimed and reserved after the real deadline; hard-expired Admission committed both wall-clock decisions after cancellation committed; and sitemap discovery inserted `/late` after CompleteCrawl committed a failed Crawl. Read-only catalog evidence independently proves the terminal child-fact set is not closed on parent terminalization. The architecture detector returned no findings for `Time.zone.parse`, `Time.rfc3339`, no-parentheses `respond_to?`, and `Time === value`.

No acceptance transition is made. No repair cycle is commissioned. S-07-010 and S-07-011 remain blocked on S-07-009. The outstanding owner decisions FU-32, FU-33, FU-43 and R3-P1..R3-P3 remain unchanged.

Authority And Precedence:
Records the exact owner-commissioned review outcome and supersedes only ADR-117's no-review stop boundary. It does not supersede ADR-117's semantic rulings, authorize implementation, resolve any blocker, accept S-07-009, or alter unrelated backlog ownership. Allocated the next unused number after ADR-117.

## ADR-119: S-07-009 Review Boundary Terminology Corrected — Candidate At `5860bb4`, Complete State Through `cf2059e`

Status: Accepted record correction (2026-08-03); review verdict unchanged
Date: 2026-08-03
Owner: explicit correction to the instruction that commissioned ADR-118's independent review
Reversibility: Governance wording only. No reviewed byte, finding, verdict, candidate, production path or acceptance state changes.

The owner's commissioning prompt called `cf2059e` the candidate endpoint. The owner has corrected that terminology: the implementation candidate is pinned at `7f043a2..5860bb4`; `cf2059e` is the governance-record commit above it. The required independent review scope was the **complete resulting state through `cf2059e`**, which is exactly what all five fresh contexts inspected. The review therefore remains valid and complete; only the label applied to the two boundaries was wrong.

ADR-118 and `S-07-009_ACCEPTANCE_REVIEW.md` now state the distinction explicitly. ADR-118's nine blockers, five FAIL verdicts and review commit `9d8da35` are unchanged. S-07-009 remains NOT ACCEPTED and no repair is authorized.

Authority And Precedence:
Corrects the terminology of the owner's immediately preceding review instruction and ADR-118. It does not alter ADR-117's repair pin, the bytes reviewed through `cf2059e`, or any outstanding owner decision. Allocated the next unused number after ADR-118.

## ADR-120: The Round-6 Owner Rulings — Nine Blockers Are Five Concepts, Each Repaired Once At Its Owner

Status: Authorized and implemented (2026-08-04); S-07-009 remains NOT ACCEPTED
Date: 2026-08-04
Owner: explicit owner rulings issued at the round-6 repair boundary, superseding ADR-117's stop terminus for this programme only
Reversibility: Integration branch only. The authorization permits the repairs below, one new migration and one change to an existing frozen check; it makes no acceptance transition.

The owner directed a classification of ADR-118's nine confirmed blockers before any repair, and that
classification found five root concepts rather than nine independent defects. The owner then issued four
rulings and an ordered implementation programme. **The rulings are recorded here with their exact scope,
and this ADR does not claim to precede the implementation** — see ADR-117's corrected provenance
paragraph and R6-8 below for why that distinction is now written down rather than assumed.

**RULING 1 — POST-WAIT DECISIONS MUST USE CURRENT TRUTH (R6-1, R6-5, R6-6).** Any handler that waits on
a lock before an irreversible decision must, after acquiring it, re-read authoritative state, take its
decision instant from database time, re-check any time-sensitive lease or deadline, re-check current
authorization where the command depends on human authority, and make no durable write from a pre-wait
snapshot. Applied as one canonical rule, not as three local patches. For `CancelCrawl` the platform-wide
`authority_current?` deferral recorded at ADR-063/S-06-006 does **not** apply once a command can wait
before an irreversible effect; that deferral continues to cover handlers that authorize and act with no
wait between the two.

**RULING 2 — A TERMINAL CRAWL HAS A CLOSED FACT SET (R6-2, R6-3).** Once a Crawl is terminal, no new
child fact may be inserted for it. A post-terminal child fact is a data-integrity violation, not an
accepted timing window. The rule is owned at the database boundary so every producer is covered;
application checks may remain as defence in depth but are not the canonical enforcement. A stale or late
worker must receive a controlled domain outcome and must not append facts after terminalization.

**RULING 3 — VOLUME I :450 GOVERNS THE SITEMAP PENDING STATE (R6-4).** An unattempted pending sitemap
gate must not be converted into `sitemap_unavailable`. That outcome requires :450's antecedents — a
declared sitemap, or a qualifying default response — followed by failure after the required retries or
validation. The later FU-9 transfer, BUILD_PLAN, BUILD_STATE, implementation and PROOF 67 are reconciled
to this ruling and no contradictory governance text is retained.

**RULING 4 — RECOVERY AND EVENTUAL TERMINATION.** Every nonterminal state must have a deterministic path
to completion, bounded retry or re-entry, stale-claim recovery, explicit failure, cancellation, deadline
terminalization, or authorised replay. No pending, in-progress, leased or claimed record may rely on
indefinite waiting. For this tranche the ruling is bounded to: stale and late work cannot mutate a
terminal Crawl; a blocked handler revalidates after waiting; the crawl-level deadline still provides the
final terminal boundary; and all existing lease, scheduled re-entry and terminal-checkpoint behaviour is
preserved. S-07-011's recovery-and-replay feature set is **not** pulled forward, and residual
stranded-claim recovery stays recorded under FU-22 rather than given an ad hoc substitute here.

**WHAT WAS BUILT, ONE OWNER PER CONCEPT.**

* `Platform::PgInstant.after_wait` is the decision instant, computed by PostgreSQL as the caller's
  instant plus `clock_timestamp() - transaction_timestamp()`. It is an ADVANCE and not a raw
  `clock_timestamp()` reading because `crawls.deadline_at`, `crawls.started_at` and
  `entitlement_reservations.lease_due` are all written by an application clock;
  `CrawlHostGateStore#reservation_executing?` already records that two surfaces judging one reservation
  against two clocks is the defect to avoid. `Workflows::Wf005::PostWaitDecision` states the rule and owns
  :458's terminal vocabulary and the `authority_current?` call site for waiting handlers.
* `f1_crawl_child_fact_closed` (migration `20260727120390`) closes the fact set on INSERT for
  `crawl_limit_decisions`, `crawl_terminal_outcomes`, `crawl_frontier_entries`,
  `crawl_frontier_occurrences` and `crawl_host_gates`, and on UPDATE of the sitemap and robots outcome
  columns. It takes `FOR KEY SHARE` on the parent — the same lock the composite foreign key already takes
  in the same statement — so the subsystem's one lock order is unchanged and no new cycle is reachable.
  It is an AFTER trigger, because a BEFORE trigger runs ahead of a policy's WITH CHECK limb and would
  answer a cross-tenant write with a state message; PROOF 40b exists to prove that refusal is RLS.
* Admission's unlocked hard-expired branch is removed. Both wall-clock thresholds are now recorded by the
  single post-lock `wall_clock` call, after revalidation, so a run cancelled during the wait is refused
  `admission_crawl_not_running` before either is written.
* `CompleteCrawl#resolve_pending_sitemaps` is removed and `TerminalSelection::Facts` gains
  `unattempted_discovery`, which lowers coverage under :458's not-evaluated sentence and deliberately does
  not touch :452's completion reason.

**THE ONE FROZEN-PATH CHANGE, NAMED AND AUTHORIZED.**
`spec/architecture/wf005_time_single_surface_spec.rb` is a frozen path under
`AutonomousBuild::FrozenContracts`, and the owner's programme names it explicitly for repair under R6-7.
That instruction is the authority for the change, which is recorded here rather than inferred from the
diff. The check keeps ADR-117 R5-2's narrow scope — WF-005 PostgreSQL timestamp decoding through
`Platform::PgInstant` — and does not expand into limits, locks, event envelopes, deadlines or
acceptance-history derivation. Its detector is inverted from an enumeration of four forbidden spellings
into a structural ban on naming `Time` or `DateTime` in the tracked corpus, which the corpus already
satisfies, plus a ban on naming the UTC protocol as data. No new family of checks is created.

**R6-8 AND R6-9, AND THE STRUCTURAL CAUSE UNDER BOTH.** ADR-117's "records that authority before
implementation" is withdrawn as false of git and corrected in place. The completion report's proof counts
are now derived rather than maintained. The cause under both is that
`spec/architecture/repository_truth_spec.rb` bound only `acceptance_evidence.block`, the last ACCEPTED
tranche, so the report of the tranche under review was validated by nothing for the entire period five
review rounds spent reading it — which is where R4-8, R5-4, R5-5, R6-8 and R6-9 all accumulated. It now
also binds `BUILD_STATE.current_tranche`, re-counts every proof row from the file it names, resolves that
report's path and migration citations, and fails on the withdrawn provenance sentence.

Authority And Precedence:
These rulings supersede ADR-117's "do not commission Round 6" terminus for this programme and withdraw the
FU-9 transfer recorded at ADR-096 and in S-07-009's BUILD_PLAN preconditions. They do not supersede the
contracts they interpret, do not broaden the tranche beyond the named repairs, do not authorize another
frozen path beyond the one named above, do not accept S-07-009, and do not resolve FU-32, FU-33, FU-43 or
R3-P1..R3-P3. Allocated the next unused number after ADR-119.

## ADR-121: The Independent Acceptance Review Of The Round-6 Repair — Three Of Five Lenses Fail

Status: Accepted review record (2026-08-04); S-07-009 is NOT accepted
Date: 2026-08-04
Owner: explicit owner instruction to run the final independent acceptance review for S-07-009
Reversibility: Governance record only. No candidate, production, migration, test or frozen-path repair is authorized or made.

The owner instructed that the owner's unrelated working-tree materials be committed separately, that a
clean isolated worktree be created, and that a fresh independent ADR-026 five-lens review run against
the complete resulting state, assuming every round-6 repair incorrect until independently verified.

**OWNER MATERIALS, SEPARATED: `9720d25`.** Five owner-authored markdown files under `branding/`,
`investor/`, `operations/captures/` and `research/`. Screened before committing: all UTF-8 text, no
credential, key, token, connection string, dump or binary. Verified by the architecture and security
lenses to touch zero files under `app/ db/ spec/ specification/ schemas/ lib/ config/ governance/
DECISIONS.md`, and neither `4e2d8cf` nor `72724f1` touches any owner-material path. It is outside the
acceptance diff and is not product implementation evidence.

**VERDICT: FAIL. FIVE CONFIRMED-BLOCKING FINDINGS. S-07-009 REMAINS NOT ACCEPTED.** Contract
PASS_WITH_OBSERVATIONS, schema PASS_WITH_OBSERVATIONS, concurrency FAIL (C-1, C-2), security FAIL
(SEC-B1), architecture FAIL (A-1, A-2). Complete evidence, provenance, reproductions and repair
ownership are in `S-07-009_ACCEPTANCE_REVIEW.md` § ROUND 7. In dependency-neutral summary: C-1,
`after_wait` measures elapsed time only since `BEGIN` and is blind to the driver's pre-transaction
outbound window, where a run can pass its deadline and still be admitted 10,485,760 bytes; C-2, Ruling
2's controlled-outcome half is implemented at one producer and `EnsureRobots` surfaces a raw
`PG::RaiseException` a worker classifies as a defect; SEC-B1, `QueueCrawl` and `ActivateCrawlPolicy`
also authorize a human capability and then wait on a blocking advisory lock, and both commit on a
revoked authority; A-1, the timestamp check's "structural ban" is still an enumeration and nine
decoder/dispatch forms enter the tracked corpus with it green; A-2, the record states false
mechanically countable facts about itself, which is the R6-9 class recurring inside the repair that
closes R6-9.

**A METHODOLOGY FAULT IN THE REVIEW'S OWN SETUP, RECORDED BECAUSE IT IS THE KIND OF THING THAT OTHERWISE
GETS FORGOTTEN.** The coordinator isolated a database per lens but let all five share one worktree, and
then authorized them to apply temporary mutations to tracked files. Three lenses independently observed
foreign live mutations mid-run. This breaks the repository's own one-session-per-worktree rule, at the
setup rather than in the candidate. It was detected by the lenses themselves, the coordinator halted
further tracked-file mutation, and every finding was re-verified in clean conditions by the lens that
raised it. No mutation was banked; the review worktree ended pristine at `9720d25` with no commit in
it. Any future review must give each lens its own worktree, not merely its own database.

**WHAT THE ROUND CONFIRMS GENUINELY REPAIRED**, so the next tranche does not re-litigate it: R6-5, R6-6
and R6-8 are closed; R6-2 and R6-3's database enforcement is real and is the enforcer rather than the
application pre-read; :450's three states are genuinely distinguished on provably disjoint predicates;
the migration is exactly reversible, purely additive and weakens no existing guard; lock order is one
order throughout with zero deadlocks in 48 contended operations; all four round-6 detector escapes are
closed; and every claimed round-6 mutation was independently re-run and killed its named proofs.

Authority And Precedence:
Records the outcome of the owner-commissioned final acceptance review. It makes no acceptance
transition, authorizes no repair, resolves no blocker, and alters no outstanding owner decision. FU-32,
FU-33, FU-43 and R3-P1..R3-P3 remain unchanged. S-07-010 and S-07-011 remain blocked on S-07-009.
Allocated the next unused number after ADR-120.

## ADR-122: Owner Authority For The Round-7 Repair — Conform S-07-009 To Its Approved Specification

Status: Authorized and implemented (2026-08-04); S-07-009 is NOT accepted
Date: 2026-08-04
Owner: explicit owner instruction granting authority to repair S-07-009 into conformance with its already approved specification
Reversibility: Integration branch only. The authorization permits the repairs below and one minimum-extent change to a frozen path; it makes no acceptance transition.

**THIS ADR DOES NOT CLAIM TO PRECEDE THE IMPLEMENTATION.** ADR-117 made that claim, git refuted it, and
round 6 recorded it as blocker R6-8. The owner's authority was given before the work; this written record
was committed with it, and `spec/architecture/repository_truth_spec.rb` now fails on the withdrawn phrasing.

**THE GRANT.** Authority to repair S-07-009 so the implementation conforms to the already approved
specification, closing the five confirmed blockers recorded by the round-7 independent review (ADR-121,
`S-07-009_ACCEPTANCE_REVIEW.md` § ROUND 7): C-1, C-2, SEC-B1, A-1 and A-2.

**THE FROZEN-PATH LIMB, AND ITS EXACT BOUNDS.** Explicit authority to modify
`spec/architecture/wf005_time_single_surface_spec.rb` — a frozen path under
`AutonomousBuild::FrozenContracts` — but **only to the minimum extent necessary to implement the already
approved contract**, and expressly NOT to redesign, expand, weaken, reinterpret or replace the frozen
contract. The change made under it keeps ADR-117 R5-2's scope exactly: WF-005 PostgreSQL timestamp
decoding through `Platform::PgInstant`, with no expansion into limits, locks, event envelopes, deadlines
or acceptance-history derivation, and no new family of checks. It adds one rule, about the RECEIVER
rather than the name, because A-1 established that a rule about names can be renamed around.

**MANDATORY EXECUTION ISOLATION, NOW A HARD INVARIANT.** One worktree per active implementation, review,
mutation or acceptance session. Round 7's own review broke this — five lenses shared one worktree while
holding separate databases, and three observed foreign live mutations mid-run — and the owner has made
the invariant explicit: each session gets a clean dedicated worktree and its own database resources, no
parallel session may mutate tracked files in the same worktree, each review lens gets its own worktree,
and violation is a process failure requiring the affected evidence to be discarded and re-run cleanly.
This repair session selected the primary worktree, verified exclusive (one worktree, clean tree, zero
other sessions on the database) before any change.

**WHAT WAS BUILT.**

* C-1 — `Platform::PgInstant.after_wait` takes an explicit `anchored_at`, and `Platform::PgInstant.anchor`
  captures it. The advance is measured from where the caller's instant was TRUE rather than from `BEGIN`,
  because `CrawlDriver#advance` captures `now` and then fetches robots and discovers sitemaps outside every
  transaction. The anchor is read in the same unit of work that loads the Crawl, so it costs no round trip.
* C-2 — `Workflows::Wf005::ClosedFactSet` is the single owner of the controlled-outcome translation, and
  `DiscoverSitemaps`, `EnsureRobots` and the driver's gate creation all route through it.
* SEC-B1 — `Handlers::QueueCrawl` and `Handlers::ActivateCrawlPolicy` re-check `authority_current?` through
  `Wf005::PostWaitDecision` after their blocking advisory wait and immediately before their irreversible act.
* A-1 — the detector gains a third, structural rule and a runtime-DERIVED timestamp vocabulary, and rule 2
  extends to a banned constant reached as a string.
* A-2 — the false "two `.getutc` method calls" claim is corrected to nine and located; PROOF 145's margin is
  stated once, as 400ms; the proof table is re-derived.

**THE TWO MUTATION SURVIVORS THE REVIEW FOUND.** The closure's UPDATE `WHEN` predicate is now pinned on all
seven outcome columns and the narrowing mutation kills PROOF 157. The `:551` equality survivor is NOT
closed: it belongs to F-05, `app/platform/entitlement/service.rb` is outside the S-07-009 range, and it is
recorded as **FU-44** with owner, failure model and the exact proof required. It is not silently ignored
and it is not claimed closed.

Authority And Precedence:
Grants repair authority for S-07-009 and records the one-worktree-per-session invariant. It makes no
acceptance transition, does not accept S-07-009, does not authorize S-07-010, and does not resolve FU-32,
FU-33, FU-43, FU-44 or R3-P1..R3-P3. Allocated the next unused number after ADR-121.

## ADR-123: The Independent Acceptance Review Of The Round-7 Repair — Four Of Five Lenses Fail

Status: Accepted review record (2026-08-04); S-07-009 is NOT accepted
Date: 2026-08-04
Owner: explicit owner instruction to perform the complete independent acceptance review of the repaired S-07-009 candidate
Reversibility: Governance record only. No candidate, production, migration, test or frozen-path repair is authorized or made.

Five fresh lenses reviewed the complete resulting state at review HEAD `5dadf7f`, each in its OWN clean
worktree with its OWN database provisioned from empty, under the hard isolation invariant ADR-122
records. Implementation candidate `7f043a2..e1f5bab`; governance `5dadf7f`; excluded `9720d25` (owner
materials), `5261cee` and `d52e66a` (round-7 findings records).

**VERDICT: FAIL. NINE CONFIRMED-BLOCKING FINDINGS. S-07-009 REMAINS NOT ACCEPTED.** Contract FAIL,
concurrency FAIL, security FAIL, architecture FAIL, schema PASS_WITH_OBSERVATIONS. Complete evidence,
reproductions and repair ownership are in `S-07-009_ACCEPTANCE_REVIEW.md` § ROUND 8.

**THE SHAPE OF THE ROUND, WHICH IS THE FINDING THAT MATTERS.** Eight of the nine blockers are PROOF
defects rather than behaviour defects. Three lenses independently verified that the shipped code is
correct on every path they exercised: C-1's anchor makes elapsed time before and after `BEGIN`
equivalent, C-2's producers return controlled outcomes, and SEC-B1's two handlers both refuse under an
observed ungranted waiter with the authorization epoch advanced underneath. What fails is what DEFENDS
those repairs — R8-1 (the anchor is unproved at the driver, and nulling it there survives 2148
examples), R8-3 (PROOF 168 never reaches the code it names), R8-4 (`ActivateCrawlPolicy`'s recheck has
no proof at all, and deleting it survives 388 examples), R8-5 (both SEC-B1 proofs are branch-depth-one
and a one-line bypass is demonstrably exploitable), R8-6 (rule 3's receiver predicate is a new
enumeration, and round 6's `command_call` escape recurs inside it), R8-7 and R8-8 (the record states
mechanically checkable falsehoods about itself, including a candidate range and an authority that are
still round-6 values, and an FU-44 failure model the repository refutes three times out of three).

**THE ONE BEHAVIOUR DEFECT IS R8-2.** `FetchContent#settle` writes `crawl_limit_decisions` through a
bare unit of work with no `ClosedFactSet.translate`, on the one path that spends unbounded real time
outside every lock. Round 7 enumerated two producers; the repair fixed those two; this third was named
by neither. Reproduced end to end.

**R8-9 IS NEWLY DISCOVERED AND WAS RECORDED NOWHERE.** `Admission#wall_clock_expired?` weakened from
`<=` to `<` survives the entire suite. :442 says "AT 60 elapsed minutes", so equality is refusal, and
round 4's R4-1 found this same boundary broken once already. It is the FU-44 defect class inside
S-07-009's own file and inside the candidate range.

**AN ISOLATION GAP IN THIS REVIEW'S OWN SETUP, RECORDED RATHER THAN GLOSSED.** Worktrees and databases
were isolated per lens, as ADR-122 requires. REDIS WAS NOT. The shared instance at `127.0.0.1:6379/0`
produced one spurious `f04_background_execution_acceptance_spec.rb` failure in the concurrency lens's
full-suite sweep, which passes 8/8 in isolation. No finding recorded here rests on that run. A future
review must isolate Redis alongside the worktree and the database.

**WHAT THE ROUND CONFIRMS GENUINELY REPAIRED**, so a repair tranche does not re-litigate it: C-1, C-2 and
SEC-B1 are all behaviourally correct and independently reproduced; the recheck and the protected write
provably share one transaction, backend and advisory lock; there is no fourth waiting WF-005 handler and
`ActivateProject` does not share the `crawl-queue:` key; the schema is clean, reversible byte-identical
across five cycles, rebuilds from empty identically, pins all seven outcome columns, and grants `f1_web`
nothing new; all thirteen proof-table counts and the nine `.getutc` sites are exact.

Authority And Precedence:
Records the outcome of the owner-commissioned independent acceptance review. It makes no acceptance
transition, authorizes no repair, resolves no blocker, and alters no outstanding owner decision. FU-32,
FU-33, FU-43, FU-44 and R3-P1..R3-P3 remain unchanged. S-07-010 and S-07-011 remain blocked on
S-07-009. Allocated the next unused number after ADR-122.

## ADR-124: Owner Authority For The Round-9 Repair — Repair The PROOF System, Not Only The Code

Status: Authorized and implemented (2026-08-04); S-07-009 is NOT accepted
Date: 2026-08-04
Owner: explicit owner instruction granting authority to repair the nine blockers recorded by the round-8 independent acceptance review, and to strengthen the proof system until it detects the false implementations that review identified
Reversibility: Integration branch only. The authorization permits the repairs below, including production changes at R8-2 and R8-9 and minimum-extent frozen-path changes; it makes no acceptance transition.

**THIS ADR DOES NOT CLAIM TO PRECEDE THE IMPLEMENTATION.** ADR-117 made that claim, git refuted it, and
round 6 recorded it as blocker R6-8. The owner's authority was given before the work; this written record
was committed with it.

**WHAT ROUND 8 ACTUALLY FOUND, AND WHY THIS ROUND IS DIFFERENT IN KIND.** Eight of the nine blockers were
PROOF defects rather than behaviour defects. Three lenses independently verified the shipped code correct
on every path they exercised; what failed was what defends it. A control no proof pins is a control the
next tranche deletes silently, and this tranche's own history is the argument — R5-2, R6-7 and A-1 were
each that failure one round earlier. The owner's instruction is therefore explicit that adding tests is
not the deliverable: every mutation must be PROVED to have landed, every proof must be PROVED to reach the
production path it claims to defend, and every failure must occur for the intended reason.

**THE GRANT.** Authority to repair R8-1 through R8-9; to make the production changes R8-2 and R8-9
require; to change tests, mutations, corpora, fixtures, architecture rules, repository-truth records and
governance; to make the minimum frozen-path changes necessary to implement the already approved contract;
to correct or remove false, stale, incomplete or contradictory evidence; and to re-derive FU-44 from clean
evidence. It is NOT authority to redesign the approved contract, broaden product scope, weaken security,
alter acceptance standards, or convert proof defects into observations.

**THE HARD ISOLATION INVARIANT, EXTENDED TO REDIS.** ADR-122 made one worktree and one database per
active session mandatory. Round 8 kept that and recorded its own remaining gap rather than glossing it:
Redis at `127.0.0.1:6379/0` was shared across lenses and produced one spurious F-04 failure. The owner has
now extended the invariant to Redis, temporary files, ports, queues and every other mutable external
resource. This repair session ran in a dedicated worktree at `/Users/leepowell/websites/F1-r9-impl`, on
`f1_test_r9impl` provisioned from empty, against an ISOLATED Redis at `127.0.0.1:6390` started for this
session alone.

**WHAT WAS BUILT.** Two production repairs, four new proof surfaces, and two instruments.

* **R8-2 — the translation boundary moved from "each producer someone remembered" to THE PASS.** An
  execution census of the corpus found governed writes reaching PostgreSQL from EIGHT WF-005 source lines,
  not the three the record named. `CrawlDriver#advance` now runs inside `ClosedFactSet.translate`, so
  every governed write a stale worker can make — existing, added later, or never enumerated — is covered;
  `FetchContent` gained its own translation at its entry point, covering both `settle` and the host-gate
  claim; and `DiscoverSitemaps` stopped re-implementing the translation inline and now calls it.
* **R8-9 — :442's boundary has one owner.** `Platform::PgInstant.expired?` replaces four separate
  comparisons in `Admission`, `CrawlDriver`, `DiscoverSitemaps` and `CompleteCrawl`. The `<=` survived the
  entire suite because no proof could construct exact equality: the instant those four compared came from
  `after_wait`, whose advance is microseconds nobody can predict. At the owner, the operands are chosen
  rather than measured, and the boundary is pinned at one microsecond either side.
* **R8-1, R8-3, R8-4, R8-5 — proofs that drive the real production entry points.** Nothing new calls
  `Admission`, `CrawlDriver` or a handler's internals directly: every proof enters at the registered
  `crawl_fetch_due` handler or at the real command handler, which is precisely what PROOF 164, 165 and 168
  did not do.
* **R8-6 — rule 3 inverted on both axes.** A call is recognised by Ruby's three call OPERATORS rather than
  by Ripper's node kinds, and a receiver must be PROVED in memory rather than proved to be a row. Forty-one
  bypass forms are injected into the real source of a real tracked file and all forty-one are caught;
  fifteen legitimate forms are injected the same way and none is.
* **R8-7 — the truth gate measures instead of comparing two records.** Suite size is now taken from
  `rspec --dry-run`, the candidate range must agree between record and state file AND be reachable, the
  round count must equal the review record's headings, and frozen-path claims must equal what
  `FrozenContracts.frozen_changes` returns.
* **THE TWO INSTRUMENTS.** `GovernedWriteSentinel` observes every governed write at the wire and records
  which WF-005 line issued it and whether the translation was on the stack; `ExecutionProbe` reports the
  lines Ruby actually executed. Together they answer the question round 8 turned on — did this proof reach
  the code it names — mechanically rather than by assertion.

**FU-44 IS SUPERSEDED, NOT CARRIED.** Its stated failure model was false and the reason is exact:
`app/platform/entitlement/service.rb` contains THREE identical `if now >= effective_deadline(r)`
comparisons, and an unscoped substitution lands on the FIRST — `start_execution` at :113 — not on
`commit` at :150, which is the site FU-44 names. With the mutation verified applied at :150 by diff, the
named example fails deterministically, four times out of four. The follow-up is closed as an erroneous
record. **A DIFFERENT AND REAL SURVIVOR WAS FOUND IN ITS PLACE**: `start_execution`'s prestart boundary at
:113 genuinely survived the entire entitlement suite, and it is now closed by a named boundary proof that
kills it three times out of three. No F-05 implementation was changed to preserve FU-44's existence.

**THE MUTATION LEDGER.** `specification/automation/S-07-009_MUTATION_LEDGER.json` is written by the
harness, entry by entry, and records for each mutation that it LANDED (confirmed against git, not
intended), the command, the examples run, the failures observed, the failing example names and the
verdict. The harness aborts rather than record a verdict for an edit git cannot see, which is the exact
failure that produced FU-44. `repository_truth_spec.rb` fails if the record names a mutation the ledger
does not contain, or if any ledger entry lacks confirmation that it landed.

Authority And Precedence:
Grants repair authority for S-07-009 round 9 and extends the isolation invariant to Redis and every other
mutable external resource. It makes no acceptance transition, does not accept S-07-009, does not authorize
S-07-010, and does not resolve FU-32, FU-33, FU-43 or R3-P1..R3-P3. It SUPERSEDES FU-44. Allocated the
next unused number after ADR-123.

## ADR-125: The Independent Acceptance Review Of The Round-9 Repair — Four Of Five Lenses Fail

Status: Recorded (2026-08-04); S-07-009 is NOT accepted
Date: 2026-08-04
Owner: the round-9 five-lens independent acceptance review, run under ADR-124
Reversibility: Record only. It authorizes no repair, makes no acceptance transition and changes no contract.

**THE ROUND.** Candidate `7f043a2..6fda00d`, governance `ca655b0`, review HEAD `ca655b0`, full ADR-026
five-lens form. **FAIL — four of five lenses, SEVEN confirmed-blocking findings.** The complete record,
with reproductions, is `S-07-009_ACCEPTANCE_REVIEW.md` § ROUND 9.

**THE ISOLATION INVARIANT WAS MET IN FULL FOR THE FIRST TIME.** Six worktrees, six databases
provisioned from empty, and six separate Redis servers on six ports with six directories — the gap
round 8 recorded against its own setup, closed. No worktree, database, Redis instance, port or
temporary directory was shared, and every lens ended with no modified tracked file.

**WHAT THE ROUND ESTABLISHED, AND IT IS THE FINDING THAT MATTERS.** The round-9 repair closed six of
the nine round-8 blockers by execution — R8-1, R8-3, R8-4, R8-8, R8-9, and the schema surface entirely
— and both production changes are sound under adversarial probing. **But it reproduced its own failure
mode one step later in the three places it mattered most.** R8-2 was an enumeration of producers, and
round 9 replaced it with an enumeration of EXCEPTIONS, missing a third producer
(`Frontier#seed_roots` under `StartCrawl`). R8-5 was an enumeration of branches, and round 9 replaced
it with an enumeration of AXES, missing a third axis that is EXPLOITABLE and survives the entire suite.
R8-6 was an enumeration of receiver shapes, and round 9 replaced it with an enumeration of BINDING
FORMS, missing four classes. A rule that fails closed on the axis someone thought of still fails open
on the axis nobody did, and that is now this tranche's defining pattern across three consecutive
rounds.

**THE SECOND LESSON IS ABOUT INSTRUMENTS.** The two the repair introduced are the strongest thing in
the tranche, and the reason this round could be precise: `GovernedWriteSentinel`'s suite-wide rule
FIRED on the unclassified producer the moment a lens drove the path the corpus does not. Both were
proved non-vacuous by blinding them. **And one of them does not observe what three ratified records
say it observes**: `ExecutionProbe`'s `expect_reached_recheck` resolves the control to the `unless`
line, and a leading-dot continuation line never fires a `:line` event, so the assertion passes in a run
where the guard is provably short-circuited past. An instrument is a claim like any other and needs its
own proof; the record's phrase "asserts it REACHED its control" was not true.

**THREE RECORDS STATE SOMETHING THE REPOSITORY REFUTES**, all introduced by the repair and all of the
R8-7 class it was closing: "forty-one bypass forms" where the file declares 40; "EIGHT WF-005 source
lines" where a census measures 17; and the `ExecutionProbe` claim above. The truth gate could not catch
any of them — and its own frozen-path limb, written to catch exactly this, never executes because a
regex expects a literal space where the record wraps the phrase across a line.

**ONE REAL :442 VIOLATION WAS REPRODUCED AND IS OUTSIDE THE CANDIDATE RANGE.** The C-1 anchor has one
consumer; every other :442-sensitive decision in the pass uses the un-anchored instant, so a pass
entering inside its deadline and crossing it during the robots fetch starts a sitemap request 0.659s
after the run is over. The repository asserts the opposite by name at
`spec/acceptance/wf005_record_fetch_attempt_spec.rb:729`. Pre-existing, untouched by the range, and
recorded here because no round has recorded it. It needs its own follow-up and an owner decision.

Authority And Precedence:
Records the outcome of the round-9 independent acceptance review. It makes no acceptance transition,
authorizes no repair, resolves no blocker and alters no owner decision. FU-32, FU-33, FU-43 and
R3-P1..R3-P3 are unchanged; FU-44 remains correctly SUPERSEDED by ADR-124. S-07-010 and S-07-011 remain
blocked on S-07-009. Allocated the next unused number after ADR-124.

## ADR-126: Owner Authority For The Round-10 Repair — Remove The Enumeration Pattern, Not Only Its Latest Instance

Status: Authorized and implemented (2026-08-04); S-07-009 is NOT accepted
Date: 2026-08-04
Owner: explicit owner instruction granting authority to begin the next repair cycle, with the objective stated as removing the recurring failure pattern rather than patching R9-1..R9-7
Reversibility: Integration branch only. It permits production refactoring within the repair surface, replacement of defective proof mechanisms, and the separate :442 follow-up; it makes no acceptance transition.

**THE PATTERN, NAMED BY THE OWNER AND CONFIRMED BY THE RECORD.** Nine rounds have failed, and three of
them failed the same way: an incomplete enumeration replaced by a narrower enumeration. Round 6 banned
four AST spellings; round 7 walked nine forms past it. Round 7 banned two names; round 8 walked thirty
of forty-one past it. Round 8 banned a receiver shape; round 9 walked four binding classes past it.
Round 8 named two authority axes; round 9 drove both and its review found a third, exploitable. Round 9
classified two translation exceptions; its review found a third producer under one of those very
handlers. **The lists were not too short. Syntax and lists were being asked to decide questions about
values, callers and reachability.**

**THE GOVERNING REPAIR PRINCIPLE THE OWNER IMPOSED**, in order: a production invariant that makes the
invalid state impossible; a runtime or database invariant covering all callers; a semantic check over
parsed structure or execution; a mechanically derived census; and a narrow syntactic rule only where
the repository proves syntax IS the complete contract surface. Every repair below is placed against
that order, and where a lower tier was chosen the reason is recorded.

**WHAT WAS BUILT.**

* **R9-3 — the write refuses (tier 1).** `Wf005::AuthorityAttestation` is minted only by a passing
  post-wait recheck and demanded by every protected commit in all three human-authorized handlers. No
  Boolean arrangement, operand order, helper extraction or short-circuit reaches a commit with proof
  it did not perform. `AuthoritySentinel` adds the suite-wide half: a human-authorized WF-005 command
  that SUCCEEDS and WRITES must have evaluated `CommandAuthorizer.authority_current?`, judged across
  every example the repository runs, so the axis never has to be anticipated.
* **R9-5 and R9-7 — the taint is the value (tier 2).** A `timestamptz` read by WF-005 arrives wrapped;
  assignment, multiple assignment, `&:symbol`, containers, aliases and helper methods all carry it
  because it is the object rather than the spelling. `Platform::RunDeadline` answers :442's questions
  and exposes no comparison and no raw instant, so there is nothing left to reimplement behind an
  indirection. The five decode escapes round 9 could not catch, and the method-indirection escape that
  defeated its boundary rule, all raise.
* **R9-1 — no exceptions (tier 1 and 2).** Both command handlers now translate, so
  `CLASSIFIED_UNTRANSLATED` is EMPTY; completeness is a runtime census over every execution API
  `PG::Connection` exposes rather than a list of producers or of exceptions.
* **R9-4 — invocation, not location (tier 3).** `ExecutionProbe.watch` observes `:call`; `line_of`
  refuses to resolve a control to a continuation line Ruby never reports, so the vacuous negative
  assertion is now impossible rather than discouraged. Six self-tests hold the instrument to its claims.
* **R9-2 — the fact leaves the prose.** The completion report carries an `f1-evidence` block, and an
  absent or unparseable block FAILS rather than skips.
* **R9-6 — the harness is in the repository.** `AutonomousBuild::MutationHarness` applies, verifies and
  restores; every ledger entry carries its exact substitution; the gate proves each entry names a real
  file and a `from` text occurring EXACTLY ONCE, which rejects fabricated, stale and wrong-identical-site
  entries — the class that invalidated FU-44.

**THE :442 CROSS-DEADLINE DEFECT IS REPAIRED, NOT DEFERRED.** A pass consulted the wall clock once, at
entry, and then made network requests; one entering a second inside its deadline and spending 1.6
seconds on robots started a sitemap request 0.659s after the run was over. `Wf005::RunBoundedOutbound`
binds the façade every producer is handed to the run's deadline and checks it AT THE MOMENT OF EACH
REQUEST, against the pass's anchored instant rather than a raw database clock. `DeadlinePassed`
descends from `Exception` because every producer's `rescue StandardError` would otherwise turn a
stopped run into a RETRYABLE fault. PROOF 194-197 drive real request ordering and deliberately do not
pre-resolve the window they test.

**WHAT THE MUTATION LEDGER FOUND ABOUT THIS REPAIR.** Three of fourteen mutations survived their first
replay, and all three were defects in the proof system rather than in the code: one boundary proof was
still testing `PgInstant.expired?` after the boundary moved into the value object — a proof defending
DEAD CODE — and two entries named proofs that did not drive the path they claimed. The dead method is
deleted, the proofs re-aimed, and the ledger now stands at 14 of 14 killed with every entry verified
replayable from the repository.

**GATE RELIABILITY.** `wf013_organization_lifecycle_concurrency_spec.rb` joined two threads with no
bound, so a wedged pair hung the headline gate forever instead of failing it. The join is now bounded
by the repository's existing `RaceHarness::TIMEOUT_SECONDS` and reports thread states and backtraces on
expiry. The race is preserved, not serialised.

Authority And Precedence:
Grants repair authority for S-07-009 round 10 and for the :442 follow-up. It makes no acceptance
transition, does not accept S-07-009, does not authorize S-07-010, and does not resolve FU-32, FU-33,
FU-43 or R3-P1..R3-P3. Allocated the next unused number after ADR-125.

---

## ADR-129: Database Bootstrap Provenance — Model C, Baseline Plus Forward Migrations

Date: 2026-08-04
Status: Accepted
Scope: Repository-wide prerequisite. Not a tranche.

Context:

The S-07-009 round-3 review recorded R3-P2 — that `bin/f1db db:migrate` against an empty database
loads `db/structure.sql` and runs zero migrations — and no round acted on it because it was outside
every candidate range. It is not a tranche defect. It invalidates the meaning of "from empty"
everywhere the phrase appears, and this ADR dispositions it.

**THE MECHANISM, NAMED EXACTLY.** `db:migrate` calls `DatabaseTasks.migrate_all`, which calls
`initialize_database` for each config (activerecord-8.1.3.1
`lib/active_record/tasks/database_tasks.rb:243`). That method (`:651-669`) asks whether the
`schema_migrations` table exists; on an empty database it does not, so — because a schema dump path
exists — it calls `load_schema`. `db/structure.sql` carries `INSERT INTO schema_migrations` rows for
all 70 versions, so the migration run that follows finds nothing pending and executes nothing.

**REPRODUCED WITH A CONTROLLED MARKER, NOT INFERRED FROM SCHEMA CORRECTNESS.** A sentinel migration
dated after every real one was added to `db/migrate`. `structure.sql` cannot contain it and its
recorded versions cannot name it, so its fate separates the two operations. From a database created
with 0 tables, 0 functions, 0 extensions and no `schema_migrations`:

| Observation | Value |
| --- | --- |
| exit status of `bin/f1db db:migrate` | 0 |
| migrations reporting `migrating` | **1 — the sentinel, and only the sentinel** |
| of the 70 retained migrations, executed | **0** |
| tables afterwards | 56 |
| `schema_migrations` rows afterwards | 71 (70 imported by the structure load, 1 from the sentinel) |
| `f1_find_invitation_acceptance_replay` present | yes — a function **no migration creates**, so its presence is independent proof the structure file was loaded |

**THE RETAINED CHAIN CANNOT REPLAY, AND THIS IS NOT ONE BAD MIGRATION.** With the schema dump moved
aside so the chain is the only thing that can build the database, it dies at **14 of 71**:

```
== 20260722120013 CreateInvitationActivation: migrated (0.0021s)
== 20260722120014 CreateOrganizationLifecycle: migrating
PG::DuplicateColumn: ERROR:  column "lifecycle_reason" of relation "organizations" already exists
```

`20260721120004_create_tenant_accounts_sessions.rb:68` CREATES `organizations` with a
`lifecycle_reason` column, and `20260722120014_create_organization_lifecycle.rb:25` ADDS it. An
earlier migration was amended to contain a column a later migration introduces. The retained chain is
therefore not a faithful history of how any database was built; it is a set of files that were edited
after the fact, which is ordinary and harmless in a pre-release repository and fatal to any claim
that replaying them proves anything.

**THE CHAIN ALSO CANNOT PRODUCE THE CANONICAL SCHEMA.** Of 63 functions in `db/structure.sql`, one —
`f1_find_invitation_acceptance_replay` — is created by no migration at all. Even a fully repaired
chain would end at a different schema than the one the repository ships.

**THE EXISTING GATE IS THE CLOSED LOOP.** `VERIFICATION_MANIFEST.yml:83`,
`migration_safety_no_drift`, runs `bin/f1db db:schema:dump && git diff --exit-code db/structure.sql`
against a database that was itself built by loading `db/structure.sql`. It compares a file with a
dump of itself and cannot fail for any migration reason, while its own comment states that "migration
safety here is 'the schema builds from empty'".

**AND THE BOOTSTRAP COMMAND MUTATES THE CANONICAL ARTIFACT.** `db:migrate` invokes `db:_dump`, so a
provisioning run REWRITES `db/structure.sql` in the working tree. The sentinel run above added
`CREATE TABLE public.f1_bootstrap_probe` and a version row to the repository's canonical schema file
as a side effect of provisioning a scratch test database.

Decision:

**MODEL C — BASELINE PLUS FORWARD MIGRATIONS.**

Model B (migration chain is canonical bootstrap) is REJECTED on evidence, not preference: it would
require repairing a chain that was retroactively edited, and back-filling DDL the chain has never
contained. Replaying a rewritten history proves nothing about any upgrade any installation performed,
so the work would buy a green gate and no real assurance.

Model A (structure load is canonical, migrations are not bootstrap artifacts) is REJECTED because it
permanently forfeits upgrade-path proof. This repository has no deployed installation today, which is
exactly why a baseline can be cut cleanly NOW and never again this cheaply.

Model C is adopted:

1. An immutable, named BASELINE schema is established, cut from the canonical current schema, with
   the last pre-baseline migration version recorded alongside it.
2. New databases are created by loading the baseline, then executing EVERY post-baseline migration.
3. The 70 pre-baseline migrations are retained as HISTORICAL RECORDS. They are not the supported
   bootstrap chain and the repository must stop claiming they are.
4. Every post-baseline migration must replay from the baseline, and a gate proves it — including the
   adversarial case that a run executing ZERO migrations while one is pending is a FAILURE.
5. The resulting schema is compared mechanically to the canonical schema.
6. Supported upgrade origins are stated explicitly. Today that set contains exactly one member: the
   baseline. It grows as releases are cut.

**THE REPOSITORY MAY NOT REMAIN IN AN IMPLICIT HYBRID STATE**, which is what it is in now: a
structure load that calls itself a migration build.

Consequences:

The phrase "from empty" is retired unqualified. Every authoritative record carrying it, or "clean
database", "fresh database", "all migrations", "migration replay" or "provisioned from scratch", must
be classified as STRUCTURE LOAD, MIGRATION-CHAIN BUILD, BASELINE-PLUS-FORWARD BUILD or UNKNOWN, and
corrected. 25 files carry such language.

This ADR does NOT accept S-07-009, does not resolve R10-10 or the WF-013 stability failure, and does
not authorise progression. A corrected bootstrap process cannot convert a blocked item into an
accepted one.

Authority And Precedence:

Repository-wide. It supersedes the standing interpretation of `migration_safety_no_drift` and every
record that describes a structure load as a migration-chain build. Allocated the next unused number
after ADR-128; ADR-127 and ADR-128 are recorded on `repair/s07-009-r10`, which is preserved unmerged.

---

## ADR-130: PREREQ-DB-BOOTSTRAP Accepted — And The Two Mandatory Gates That Have Never Executed

Date: 2026-08-05
Status: Accepted
Owner: standing delegation ADR-061; acceptance under the review discipline of ADR-080
Reversibility: Integration branch only; `main` untouched.
Scope: Repository-wide prerequisite. NOT a tranche, and deliberately not recorded as one.

**PREREQ-DB-BOOTSTRAP IS ACCEPTED.** It replaces a bootstrap route that loaded `db/structure.sql`
while reporting "provisioned from empty", a gate that diffed a file against a dump of itself, and 24
evidence claims across 17 files describing an operation no run in this repository had performed. The
finding, the Model C disposition and the evidence are in ADR-129 and
`PREREQ-DB-BOOTSTRAP_REPORT.md`.

**IT IS NOT RECORDED AS A TRANCHE.** `current_tranche`, `implementation_commit`,
`last_verified_commit` and `acceptance_evidence` continue to describe S-07-012 at `f2b576e`, because
`spec/architecture/repository_truth_spec.rb` derives six checks from that pairing and putting a
prerequisite identifier into it silently disables all six — which happened once during this work and
is the reason FU-47 exists. The acceptance is recorded in `completed_prerequisites`, a separate
structure with its own validating check, so a prerequisite cannot be accepted by asserting it.

**THE SCOPE CHECK CAUGHT A REAL DEFECT AND THE BRANCH WAS REBUILT.** The reviewed branch
`prerequisite/db-bootstrap-provenance@77ba137` carried the correct substantive change and also 2,531
files of bootsnap cache, logs, and `config/master.key` — a Rails master key — because `git add -A`
ran in a worktree with no ignore rules. The root cause is that the repository's root `.gitignore`
exists on disk but is UNTRACKED, since this machine's global ignore file ignores every `.gitignore`,
and `git worktree add` materialises only tracked files. **Neither contaminated branch was ever
pushed; `origin` has never held the key.** The accepted branch is a scope-clean rebuild at
`75627f7`: 29 files, 7,269 insertions, every file bootstrap provenance or a corrected claim. The
hazard is closed for every existing and future worktree through the repository's shared
`info/exclude`, verified by creating a fresh worktree and confirming that a planted
`config/master.key` and `tmp/` are no longer offered to `git add -A`. The durable fix is FU-46.

**WHAT THIS ACCEPTANCE EXPLICITLY DOES NOT CLAIM.**

1. **TWO MANDATORY GATES HAVE NEVER EXECUTED, AND THIS ITEM DID NOT FIX THEM.**
   `controller_crash_recovery` and `controller_locking` name `spec/automation/crash_recovery` and
   `spec/automation/locking`. **Neither path has ever existed** — not at `52818fc`, not at the commit
   that introduced the manifest entries. `controller_locking`'s subject matter is covered elsewhere
   (`spec/automation/integration/git_lock_record_spec.rb` among others); `controller_crash_recovery`
   has NO coverage anywhere in `spec/automation/`. So "every mandatory gate passes" has been
   unsatisfiable for every acceptance this repository has made, including the prior ones. It is
   pre-existing, unrelated to database bootstrap, and outside a diff the owner required be limited to
   bootstrap provenance. It is FU-45 and it is BLOCKING. Accepting this item on the gates that CAN
   execute is a deliberate, recorded exception rather than a silent one.
2. **THE DIFF EXCEEDS `max_diff_lines_before_forced_split: 3000`** at 7,269 lines. 6,563 of those are
   `db/baseline/BASELINE.sql`, a single generated snapshot of the canonical schema. Excluding it the
   diff is 706 lines. Splitting an immutable one-file artifact would satisfy the counter and inform
   nobody, so the threshold is recorded as knowingly exceeded rather than worked around.
3. **IT DOES NOT PROVE ANY UPGRADE PATH.** The supported-upgrade-origin set declared in
   `db/baseline/BASELINE.json` contains exactly one member, the baseline itself. Upgrade-path proof
   begins when the second origin exists.
4. **IT DOES NOT TOUCH S-07-009's BLOCKERS.** S-07-009's schema evidence is invalidated by the
   finding; none of its blockers was caused by it and none is cleared by fixing it.

Proof standard. Every mandatory gate that can execute, run from the final branch state against a
database built by `bin/f1-db-bootstrap`: rspec 2248/0; brakeman 0; packwerk clean; bundler-audit
clean; zeitwerk ok; `verify_runtime` 15 checks with RLS intact; no structure drift; architecture
fitness 149/0; concurrency 116/0; redis/sidekiq acceptance 8/0; stale-lease recovery 14/0; controller
unit 33/0, integration 20/0, policy 21/0, end-to-end 10/0; and `bin/f1-db-bootstrap-gate` 9/9 with
its own three controls mutation-tested and killed.

Authority And Precedence:
Acceptance under standing delegation ADR-061 and review discipline ADR-080. Records
PREREQ-DB-BOOTSTRAP in `completed_prerequisites`. Does NOT add to `completed_blocks`, does not alter
`current_tranche`, does not accept S-07-009, and does not authorise S-07-010 or S-07-011. Opens
FU-45 (BLOCKING), FU-46 and FU-47. Allocated the next unused number after ADR-129.

---

## ADR-131: The WF-013 Concurrency Hang Was The Harness Contending With Itself

Date: 2026-08-05
Status: Accepted
Scope: Repository-level stability. Not a tranche, and not an S-07-009 defect.

Context:

`spec/acceptance/wf013_organization_lifecycle_concurrency_spec.rb:188` intermittently ended with a
racing thread parked until `RaceHarness::TIMEOUT_SECONDS` expired, roughly one full-suite run in
three, while passing in isolation. It was first observed during the S-07-009 round-11 work and was
hypothesised there to be caused by that round's newly prepended write observer. **That hypothesis was
refuted**: the hang reproduced on `prerequisite/db-bootstrap-provenance`, which carries none of that
instrumentation. It is older than the tranche that was blamed for it.

Decision:

**IT IS A HARNESS DEFECT, AND IT IS SPECIFIC.** This was the ONLY `race(...)` call in the file that
constructed its sessions INSIDE the racing lambdas:

```ruby
race(-> { suspend(session_for(w)) }, -> { create_invitation(session_for(w)) })
```

`TenantSeeder.create_session` writes. Both threads therefore began by contending in the HARNESS
rather than in the commands under test, and the stuck backtrace named `create_session` beneath
`exec_params`, not any lifecycle command. The sibling example twenty lines above races the identical
pair — `suspend` against `create_invitation` — with its sessions hoisted out of the threads, and has
never hung.

The sessions are now seeded before the threads start. **The race under test is not weakened, it is
isolated**: both threads still start together and still contend for the same lifecycle locks, but
they now start AT the commands, so what contends is the thing the example is about.

Evidence:

| State | Full-suite runs | Hangs |
| --- | --- | --- |
| before | 5 | 2 |
| after | 4 | 0 |

**THIS IS EVIDENCE, NOT PROOF.** Four consecutive clean runs do not establish the absence of an
intermittent defect. What raises confidence beyond the count is that the mechanism is understood and
named, the fix removes exactly that mechanism, and the example now matches the sibling that never
exhibited the behaviour. If it recurs, this ADR is the record of what was ruled out.

Consequences:

The mandatory `complete_test_suite` gate passes. This does NOT accept S-07-009 or clear any of its
blockers. It removes one of the five, and the owner's rule stands: S-07-009 may not claim acceptance
while any stability violation is live.

Authority And Precedence:
Repository-level stability repair, recorded separately from S-07-009 because it is not an S-07-009
defect. Corrects the round-11 attribution in `S-07-009_ACCEPTANCE_REVIEW.md`, which had already been
amended to record the hypothesis as refuted. Allocated the next unused number after ADR-130.

## ADR-132: D7 — The Antecedent Becomes `:335`'s Protected Side Effect, And FU-48 Is Taken

Date: 2026-08-05
Status: Accepted
Owner authority: the D7 instruction, which records FU-48 as an explicit owner decision and places it
in scope.

Context:

`b2e8cfb` recorded D7 rather than patching it, and its diagnosis was half right in a way that would
have produced the wrong repair. It said the sentinel's rule "now fires on an idempotent replay, which
correctly writes its execution record without re-reading authority". **A replay writes no execution
record.** `CancelCrawl#replay` loads the stored result and returns it; it executes no data-modifying
statement at all. What satisfied the antecedent was `CrawlStartStore#lock_crawl`, a
`SELECT ... FOR UPDATE`, matched by `\bUPDATE\b` inside `FOR UPDATE`.

So the sentinel's header was TRUE where it said a replay writes nothing. The DOOR was false, for the
third time, and each form was greener than the last: anchored (blind to every CTE write), `UPDATE\s+\w`
(blind to every update), and the HEAD form (blind to nothing and deaf to the difference between a
write and a row lock). `PROOF 232` certified all three, because it only ever asked whether the real
writes matched and never what else did.

Decision:

1. **The antecedent is `:335`'s own concept.** "A running privileged operation rechecks at each
   durable checkpoint and stops before the next PROTECTED SIDE EFFECT after revocation." A governed
   write is a data-modifying statement, in any shape, whose target relation carries product facts.
2. **PostgreSQL answers, and nothing parses SQL.** `EXPLAIN (GENERIC_PLAN, FORMAT JSON)` on the real
   statement; every `ModifyTable` node names a relation it modifies. `AuthoritySentinel::WRITE_VERB`
   is deleted and there is no pattern left to certify.
3. **The governed set is read from `pg_trigger` at run time**, and the classification is checked
   against a property it does not use (`pg_attribute`), because the dangerous direction — a product
   aggregate called command evidence — is silent.
4. **The replay exemption is deleted and nothing replaces it.** Correct replay falls outside the
   antecedent by what it does.
5. **`FOR KEY SHARE` is replaced by `FOR SHARE` at all three authority reads.** The round-two claim
   that `FOR KEY SHARE` conflicts with an epoch advance is FALSE — the advance is a non-key update
   taking `FOR NO KEY UPDATE`, which does not conflict with it. Measured on the real row and the real
   revocation statement.
6. **FU-48 is implemented.** Each protected write carries `WriteAuthority` — the grants the decision
   relied on, and the role the ratified scope rule demands — and PostgreSQL re-reads them under
   `FOR SHARE` in the same statement as the transition.

What was ruled out, and why:

**Reusing `GovernedWriteSentinel`'s governed set**, which the blocker ledger proposed. That set is
`f1_crawl_child_fact_closed` — owner ruling 2's CHILD-fact closure — and contains neither `crawls`
nor `crawl_policies`. Adopting it would have made the antecedent unsatisfiable and the headline
invariant would have gone quiet while reporting success. Both modules now carry the disambiguation.

**Re-deriving the permission baseline in SQL.** The six-step algorithm reads two kinds of input: one
immutable for the life of a deploy, one ordinary row state another transaction can move while this
one waits. Only the second can go stale and only the second belongs in the statement. A second copy
of the baseline in the database would be two sources of truth for one authority.

**Implementing Assignment-scope CONTAINMENT.** That is FU-2, a pre-existing platform-wide deferral
recorded for every resource capability and backlogged under ADR-066. Inventing it under a repair
would be new authorization semantics. The axis is given a place at the write; the predicate is not.

Consequences:

An epoch advance for an Organization now waits behind any WF-005 human command that has reached its
protected write, for the few statements between that write and commit. Two authorized commands for
one Organization still proceed together, because `FOR SHARE` does not conflict with itself.

This does NOT accept S-07-009. It closes D7, D8, D9 and FU-48 with production fixes and direct
proofs. Acceptance remains an independent five-lens review's decision.

Authority And Precedence:
S-07-009 repair authority under the D7 instruction; FU-48 under the owner decision it carries.
Supersedes the D7 candidate repair recorded in `S-07-009_BLOCKER_LEDGER.md` at `b2e8cfb`, whose
diagnosis and proposed mechanism are both corrected here. Allocated the next unused number after
ADR-131.

## ADR-133: Round 15 — Two Live Authority Defects, And The Proof Gaps That Hid Them

Date: 2026-08-05
Status: Accepted
Owner authority: the overnight autonomous-build instruction, which directs that Category A and
Category B findings be repaired on discovery, that Category C findings be recorded and repaired where
repository acceptance rules require it, and that work continue rather than stop at the first defect.
Scope: S-07-009. `main` untouched; no merge; no push; no acceptance claimed.

Context:

The D7 candidate `b2e8cfb..ea8ef8d` (ADR-132), records `c398434`, was put through a full ADR-026
five-lens independent review in five isolated worktrees, five databases built by its own Model C
bootstrap, and five dedicated Redis instances. Every mandatory gate passed at the candidate before the
round began — rspec 2407/0 three times consecutively with no hang, zeitwerk, packwerk, brakeman,
bundler-audit, `verify_runtime`, no structure drift, the bootstrap gate's nine checks, and a mutation
ledger of 92 definitions independently regenerated twice with no verdict difference.

**FOUR OF FIVE LENSES RETURNED FAIL, AND TWO OF THE EIGHT BLOCKING FINDINGS WERE LIVE PRODUCTION
DEFECTS.** Both were introduced by FU-48 — the repair that put the capability axis at the write — and
neither was visible to any existing proof.

Decision:

1. **R15-SEC-1 — THE GRANT'S LIFETIME IS JUDGED AFTER THE WAIT, IN ALL THREE WRITES.** `QueueCrawl`
   and `ActivateCrawlPolicy` each constructed a `PostWaitDecision`, used it to mint the attestation,
   and then handed the write the instant the command ENTERED WITH. The expiry conjunct was therefore
   evaluated against a clock reading taken before an unbounded advisory-lock wait, and a Role
   Assignment that expired during that wait still conferred — reproduced live, committing both a Crawl
   and an immutable Organization-scope crawl policy on a grant that had expired three seconds earlier.
   `CancelCrawl` was correct, and its correctness was the finding: one line, `d = d.merge(now:
   post_wait.now)`, which `PostWaitDecision`'s own rules 2 and 5 already required. Both handlers now
   adopt the instant they were already computing. PROOF 259/260 fail at `c398434` and pass here; PROOF
   261 is the regression lock on the handler that was already right; each is paired with a control
   that must SUCCEED under the identical wait.

2. **R15-CONC-1 — ONE LOCK ORDER FOR THE TWO AUTHORITY ROWS, EVERYWHERE.** FU-48 gave every protected
   write a second locked relation: `organizations` then `role_assignments`, inside one statement.
   `RevokeRoleAssignment` and `ExpireRoleAssignment` wrote them the other way round in one
   transaction, and nothing serialized the two sides. That is a cycle. Reproduced 13/13 through the
   real handler, and over 80 jittered rounds: 20 deaths of the customer's command, 8 of the
   revocation, decided by arrival order. Nothing rescues `PG::TRDeadlockDetected` anywhere in `app`,
   `lib` or `automation`. The three WF-013 handlers now advance the epoch FIRST. Both writes stay in
   the same transaction, keep their guards and still raise `LostRace` on zero rows: only which row the
   transaction holds first changes. `DecideRoleAssignment` cannot form the cycle — its target is
   `pending`, which the capability CTE filters out before asking for a lock — and is reordered anyway,
   because an exception maintained per handler is the enumeration this tranche exists to remove.

3. **A15-1 — THE BATTERY IS WRITTEN ONCE AND RUN AT EVERY PROTECTED WRITE.** The capability predicate
   exists at three writes and the proofs enumerated which (write, conjunct) pairs were exercised; ten
   conjuncts could be deleted with the whole suite green. `wf005_grant_battery_spec.rb` drives seven
   cases — revoked, version moved, scope moved, expired, not yet effective, no grant at all, and a
   control that must commit — against all three writes, and PROOF 252b/252c drive a real grant
   revocation against the queue and policy writes while each is blocked mid-flight. All ten deletions
   verified killed.

4. **A15-2 — THE HANDLER SET IS THE NAMESPACE, WALKED.** It was a non-recursive directory glob plus a
   filename-to-constant derivation, and the observer was prepended into the instance ancestry alone. A
   handler one directory deeper, or one exposing `def self.call`, was invisible — and invisible is
   greener. Discovery is now every class under `Workflows::Wf005::Handlers`, however nested, with the
   observer in both ancestries.

5. **R15-CONC-2 — ONE CLASSIFIER, WITH THE FIRST SPEC IT HAS EVER HAD.** D7 recorded that both replay
   paths of `MutationHarness` classify identically. They did not: the correction had reached `replay`
   and left `replay_trigger` ending `else "broken"`. No ledger verdict was wrong — every trigger
   mutation kills with failing examples, so the divergent branch is unreached — so this was a false
   record and a latent asymmetry. The two copies are now one.

6. **THREE FALSE RECORDS CORRECTED WHERE THEY STOOD**: the "79 of 82" / "79 of 89" definition counts
   (measured: 82 of 92 at the time, 91 of 101 now); `ProtectedEffectDoor`'s claim of a whole-suite
   cross-check that does not exist and could not, because a refusal still PLANS a modification of the
   guarded relation; and the same file's claim that the catalogue cannot move under a run, which six
   specs falsify additively. Five dead public readers are deleted from `AuthorityAttestation` — `authority`, `transaction_id`, `actor_account_id`, `epoch`, `capability`; two were added by D7 and three predate it, and all five were callerless (round-16 contract observation 3 corrects round 15's "four ... added by D7") — and two mutation
   definitions that killed on `PG::IndeterminateDatatype` — an orphaned bind parameter, so the
   statement never executed — are rewritten to die on their own semantics.

What was ruled out, and why:

**REORDERING THE WF-005 SIDE INSTEAD.** Both locks are taken inside one statement, so their order is a
property of the statement rather than of Ruby, and forcing the reverse would mean making the
capability CTE depend on the epoch CTE — which collapses the two reason codes the contract
distinguishes. The WF-013 side has two separate statements and reorders cleanly.

**DROPPING `FOR SHARE OF ra` TO BREAK THE CYCLE.** It would work, and it would restore exactly the
premise D8 removed: safety resting on "every transition that removes a grant also advances the epoch
in the same transaction", an enumeration nobody wrote down.

**EXTRACTING THE CAPABILITY CTE TO ONE SQL FRAGMENT.** The right shape, and not taken tonight: it
moves the text every existing mutation definition patches, and the fourteen-round history of this
tranche is largely repairs introducing new defects. The battery makes the three copies provably agree
— any drift fails seven cases at the drifting write — so the duplication is recorded as an open
improvement rather than repaired under a review cycle.

Consequences:

An epoch advance and a role-assignment revocation now wait behind an in-flight WF-005 human command
for the few statements between its protected write and its commit, and no longer deadlock with it.
Two authorized commands for one Organization still proceed together. `QueueCrawl` and
`ActivateCrawlPolicy` now stamp their rows with the post-wait instant, as `CancelCrawl` already did.

**THIS DOES NOT ACCEPT S-07-009.** The repaired state is a NEW candidate and requires its own
independent review; a repair round has never yet been accepted on the strength of its own author's
verification in this tranche. S-07-010 and S-07-011 remain blocked.

Authority And Precedence:
S-07-009 repair authority under the overnight instruction's Category A/B rule. Supersedes nothing;
corrects the D9 closure recorded in ADR-132 and the record claims listed at point 6. Allocated the
next unused number after ADR-132.

## ADR-134: Round 16 — The Repair Was Right And Its Evidence Was Not

Date: 2026-08-05
Status: Accepted
Owner authority: the overnight autonomous-build instruction (Category A/B repaired on discovery,
Category C recorded and repaired where acceptance rules require it).
Scope: S-07-009. `main` untouched; no merge; no push; no acceptance claimed.

Context:

ADR-133's repaired state was put through a second full ADR-026 five-lens round in the same five
isolated environments. **Three of five lenses returned FAIL with five confirmed-blocking findings, and
every one of them is about EVIDENCE rather than behaviour.** Both live production defects round 10
found were independently confirmed repaired — the security lens by an exploit it built from scratch
and then defeated by reverting the one repair line, the concurrency lens by a 3x2 real-handler
deadlock matrix, 40 jittered rounds and a reversed-order control that still deadlocks on demand.

**THE HEADLINE FINDING WAS FOUND BY THREE LENSES INDEPENDENTLY.** ADR-133 changed three WF-013
handlers and proved one. Reverting `ExpireRoleAssignment` left 144 examples green while a real
`PG::TRDeadlockDetected` went through the timed-expiry path — the tranche's own defect class, inside
the repair written to remove it, in an ADR that names the principle in the sentence it breaks: "an
exception maintained per handler is the enumeration this tranche exists to remove."

Decision:

1. **PROOF 262 IS PARAMETERISED OVER EVERY HANDLER THAT CAN HOLD AN ACTIVE GRANT ROW.**
   `RevokeRoleAssignment` and `ExpireRoleAssignment` are each measured — the expiry through the
   ScheduledAction worker, which is the only way production drives it — and reverting either now
   fails.
2. **`DecideRoleAssignment` IS NOT PROVED BY MEASUREMENT AND NO LONGER CLAIMS TO BE.** PROOF 262b
   measures the property that exempts it instead: a protected write's capability CTE requires
   `ra.status = 'active'`, a qual applied before `FOR SHARE OF ra`, so a PENDING row is filtered out
   of the plan and never locked — proved by handing a protected write an authority naming a pending
   grant and observing `capability_authorized: false`. Its reorder is uniformity, not safety, and the
   records now say which.
3. **EVERY MUTATION DEFINITION KEEPS ITS BIND PARAMETERS.** `d3-authority-always-true` and
   `d6-a-predicate-removed` orphaned a parameter, so the statement died of `IndeterminateDatatype`
   before the write was attempted and the kill said only that the file still type-checks. ADR-133
   stated this rule generally and applied it to the two instances round 15 enumerated; a
   statement-scoped scan of all 101 definitions found two more, and both are rewritten. **THAT SCAN
   WAS INCOMPLETE AND ROUND 17 FOUND A THIRD** (`d6-a-state-predicate-omitted`), recorded at ADR-135:
   the rule stated here was right and its application was not.
4. **THE FALSE RECORDS ARE CORRECTED WHERE THEY STAND**: the D9 direction (measured — `replay`
   carried the correction, `replay_trigger` did not); the finding count (eight, not six, with
   `R15-CTR-1` given the disposition it never had); "four dead public members added by D7" (five
   readers removed, three of which predate D7); and `A15-4`, cited twice in the mutation set and
   defined nowhere, now recorded.
5. **THE TWO MISSING PROOFS EXIST.** PROOF 261b is the must-succeed control PROOF 261 lacked while its
   file claimed every proof had one; the `def self.call` and nested-inside-a-class discovery escapes
   both have examples. The namespace walk now recurses into classes and decides membership by whether
   a constant can be CALLED, which is what being an entry point means.
6. **THREE INSTRUMENT HAZARDS ADDRESSED — AND THE FIRST WAS NOT CLOSED BY THIS REPAIR** (round-17
   finding S-R17-1). Splitting the cleanup into separate statements under a short `lock_timeout`
   cannot help, because `DROP TRIGGER` is both the FIRST statement and the one needing the strongest
   lock: one ordinary open reader still leaks the identical set. What it bought is 2.1s instead of
   15s and a guarantee that a LATER failure cannot roll back an earlier drop. ADR-135 records the
   actual closure. The other two hold: the probe function pins `search_path`, and `LOCK_TIMEOUT` no
   longer collides between two proof files that both decide `:blocked` vs `:committed` by it.

What was ruled out, and why:

**PROVING `DecideRoleAssignment`'S ORDER BY MEASUREMENT.** It needs a protected pending grant and a
SecurityOperator approver, and the property it would prove is not the one that matters — the handler
cannot form the cycle at all. Measuring the exemption is both cheaper and stronger, because it fails
if the exemption ever stops holding.

**CORRECTING ADR-133 BY EDITING ITS TEXT — AND THIS PARAGRAPH WAS FALSE WHEN IT WAS WRITTEN
(round-17 finding C17-3).** The same commit that recorded this ADR edited ADR-133 twice, changing its
finding count and its dead-member sentence in place. Decision 4 above says the opposite in as many
words ("THE FALSE RECORDS ARE CORRECTED WHERE THEY STAND"), and the repository shows the edits. What
was actually decided, and is recorded here so the next reader is not misled: a false FIGURE inside an
accepted ADR is corrected in place with a forward reference to the round that measured it, because
leaving a number known to be wrong is worse than amending the record; the ADR's REASONING and
decisions are never rewritten.

Consequences:

The candidate's behaviour is unchanged by this ADR except in the mutation definitions and the proofs;
the only production change is none. What changes is that the lock-order property is now bound at both
handlers that can violate it, and that four records say what the repository contains.

**THIS DOES NOT ACCEPT S-07-009.** No round has yet returned PASS on the state it reviewed, and the
round-16 repairs make a new candidate. S-07-010 and S-07-011 remain blocked.

Authority And Precedence:
S-07-009 repair authority under the overnight instruction. Corrects the record claims listed at points
2 and 4 of ADR-133. Allocated the next unused number after ADR-133.

## ADR-135: Round 17 — The Capability Was Never Sent To The Database

Date: 2026-08-06
Status: Accepted
Owner authority: the overnight autonomous-build instruction.
Scope: S-07-009. `main` untouched; no merge; no push; no acceptance claimed.

Context:

The third consecutive five-lens round on this tranche. Three of five lenses returned FAIL with six
confirmed-blocking findings and **no production defect**. The schema lens returned
PASS_WITH_OBSERVATIONS after rebuilding a reference database and matching the live one on all nine
fingerprint dimensions, and after 40 deadlock-free rounds at 4,000 organizations and 20,000 grants.
The concurrency lens also returned PASS_WITH_OBSERVATIONS, after this ADR was first written and after
the round record had said it had not returned; both records are corrected. It re-confirmed the cycle
closed at every pair it could build, and found two things about the instrument rather than the code
(recorded at decision 7).

**THE FINDING THAT MATTERS IS THAT FU-48 WAS NEVER FINISHED.** FU-48 exists because the capability
axis "was enforced ONLY in Ruby, one deletion away from nothing". `WriteAuthority` carried
`capability` and never bound it into any statement. The capability CTE asked whether a carried grant
is still LIVE — status, version, scope, effectiveness, expiry — and never what the grant CONFERS. An
account whose only active Assignment is `TechnicalImplementer`, a role the ratified baseline denies
`crawl.trigger` and `crawl.cancel` outright, was authorised by the write; so was a capability string
that does not exist in the baseline. `ActivateCrawlPolicy` was safe only because `SCOPE_ROLE`'s roles
happen to lie inside its capability's cell. Three files claimed the opposite in as many words.

It is **not a live bypass**: the Ruby `confers?` check still refuses, and is mutation-covered. What
was missing is the owner-mandated write-level counterpart, and what was false is the record.

Decision:

1. **THE CAPABILITY IS CARRIED AND BOUND.** `WriteAuthority` gains `allowed_roles` — the ratified
   `Platform::PermissionBaseline::CAPABILITIES` cell for the capability under test — and each of the
   three protected writes gains `AND ra.canonical_role = ANY ($n::text[])`. ADR-132 ruled out
   re-deriving the six-step algorithm in SQL and this does not do that: the cell is IMMUTABLE FOR THE
   LIFE OF A DEPLOY and is read once in Ruby, exactly as `required_role` already carried the ratified
   scope rule. What the statement re-reads is still only row state another transaction can move.
   `same_principal?` compares the new member, so an attestation minted for one capability cannot be
   presented at a write carrying another's cell. The battery gains the case that would have caught
   it — a grant that is LIVE but whose role the baseline denies — at all three writes, and three
   mutations bind it.
2. **PROOF 262b MEASURES THE LOCK.** Its first version asserted an OUTCOME and called it the same fact
   as "the row was never locked", which it is not, and was insensitive to the qual it named. A pending
   row is now held `FOR UPDATE` on a second connection and the protected write must NOT block on it,
   with an ACTIVE-row control that must. PROOF 262c binds the exemption's other premise — the store
   methods only ever write a `pending` row — and PROOF 262d requires the probe itself to be able to
   report the other answer, driven through the real store methods in the reversed order.
3. **THE THIRD TYPING MUTATION IS REWRITTEN.** `d6-a-state-predicate-omitted` orphaned `$12`; all
   twelve of its recorded failures were the same `PG::IndeterminateDatatype`, including the positive
   control. ADR-134's scan claimed "exactly two more" and is corrected there.
4. **THE PROBE CLEANUP NO LONGER MASKS OR LEAKS SILENTLY.** ADR-134 recorded the hazard as closed; it
   was not, because `DROP TRIGGER` is both the first statement and the one needing the strongest lock,
   so splitting the batch cannot help. The cleanup no longer raises (a raise in an `ensure` replaces
   the example's real failure and skipped the `lock_timeout` reset, both introduced by ADR-134), it
   always restores `lock_timeout`, and anything it cannot drop fails the run at suite end by name.
5. **THE SINGLETON OBSERVER IS BOUND, AND ITS LABEL WAS WRONG.** Deleting
   `handler.singleton_class.prepend(CommandObserver)` left the architecture suite green. Installing it
   is now a method a spec can call, and driving a `def self.call` handler through it revealed that the
   frame was being labelled `Module` — the observer fired, the census recorded a handler called
   "Module", and `executed_handlers` never held the real name, which is the completeness limb that
   notices an undriven handler. `is_a?(Module)` replaces `is_a?(Class)`.
6. **FOUR RECORDS CORRECTED**: ADR-134's ruled-out paragraph (which stated the opposite of what its
   own commit did), the blocker ledger's A15-3 row, the completion report's headline count and round
   attribution, and a round-15 finding an unbounded string replace had inserted into the ROUND 4
   record.

What was ruled out:

**BINDING THE CAPABILITY STRING ITSELF INTO THE STATEMENT.** It would require the database to hold the
baseline, which is the second copy ADR-132 refused. The cell is the same fact in the form the
statement can check.

Consequences:

Every protected write now refuses a grant whose role the ratified baseline does not admit for the
capability being spent, independently of any Ruby check. FU-52 is closed by this and its follow-up
entry is retired.

7. **THE PROBE MEASURED A RELATION LOCK AND WAS ITSELF UNSTABLE.** `RowExclusiveLock` on
   `organizations` is taken by ANY data-modifying statement against the relation, including one that
   matches no row — so a handler running `UPDATE organizations ... AND false` and then writing the
   grant row FIRST reported "organizations first", with the cycle live and every example green. The
   predicate is now `o.xmin = pg_current_xact_id()`, true only of a row this transaction actually
   wrote. And the stability runs found the probe's own DDL cascading: `DROP TRIGGER` needs ACCESS
   EXCLUSIVE, one contended cleanup leaves the trigger installed, and every later example then fails
   `already exists` — 4 and 14 failures in two full-suite runs at the committed candidate. Setup is
   idempotent now, the reversed-order control no longer holds the relation against its own cleanup,
   and three consecutive full-suite runs are clean.

**THIS DOES NOT ACCEPT S-07-009.** Sixteen rounds have run and none has returned PASS on the state it
reviewed.

Authority And Precedence:
S-07-009 repair authority under the overnight instruction. Corrects ADR-134 decisions 3 and 6 and its
ruled-out section, in place, with forward references. Allocated the next unused number after ADR-134.

## ADR-136: Round 18 — The Same Ratified Row, One Column Over

Date: 2026-08-06
Status: Accepted
Owner authority: the overnight autonomous-build instruction.
Scope: S-07-009. `main` untouched; no merge; no push; no acceptance claimed.

Context:

Round 18 existed to review the one production change round 17 made — the capability cell at the
protected write — which no lens had seen. Three of five lenses returned FAIL with nine confirmed
findings and **no live bypass**. The concurrency lens returned PASS_WITH_OBSERVATIONS and established
that the new predicate re-reads an IMMUTABLE column, so nothing can move it under the statement, and
that it strictly shrinks the lock footprint.

**THE FINDING IS THE SAME SHAPE AS ROUND 17'S, ONE COLUMN OVER.** `Platform::PermissionBaseline::CAPABILITIES`
is keyed by `canonical_role` ALONE — the module says so in its own words, "THE SIXTH COLUMN OF THE SAME
ROW, WHICH `CAPABILITIES` CANNOT EXPRESS" — and `confers?` is three conjuncts. Round 17 bound one. A
Read-Only Executive Buyer, the `(MarketingOperator, read_only, executive_buyer)` tuple whose ratified
cell reads `deny`, carries a role that IS in the cell: at the store it irreversibly cancelled a running
Crawl, and through the real handler with the single Ruby line at `command_authorizer.rb` deleted it did
the same.

Decision:

1. **THE SIXTH COLUMN IS CARRIED.** `read_only_permitted` comes from the ratified
   `READ_ONLY_CAPABILITIES`, and all three writes bind
   `($n::boolean OR ra.permission_mode <> 'read_only')`. The battery gains a case that SEEDS a
   read-only grant — the lifecycle guard freezes `permission_mode`, which is why this axis cannot be
   reached by moving a row underneath a decision — at every write, bound by three mutations.
2. **THE DERIVATION IS BOUND.** The cell was bound into the statement and not into the value:
   replacing `CAPABILITIES.fetch(capability)` with a union of every cell restored round 17's exploit
   with 50 examples green. PROOF 265 drives the production builder for a capability whose cell
   excludes the actor's role and requires refusal, with a must-succeed control;
   `r18-cell-derivation-unioned` binds it.
3. **TWO PROOFS MEASURED SOMETHING ELSE.** PROOF 262b used a pending `SecurityOperator` grant, which
   the capability cell excluded on its own; it now uses a role the cell admits, and BOTH excluding
   limbs must go before it fails. PROOF 262c read the store's SOURCE and stayed green when the guard
   was deleted from the SQL and the words left in a comment; it now drives the store.
4. **THE CLEANUP DROPPED THE TABLE AND LEFT THE TRIGGER THAT WRITES TO IT.** The table goes only if
   the trigger went; the `SET lock_timeout` is inside a rescue (outside it, a failure there masked the
   example, recorded no residue and leaked all three objects while the suite-end check passed); and
   the residue check READS THE CATALOGUE, which also removes its false positives and its blindness to
   a leak from an earlier process.

What was ruled out, and why:

**BOUNDING THE PROBE'S SETUP.** Round 18 measured it waiting 43.6s against an ordinary reader, so a
`lock_timeout` looked obviously right. Measured: the bounded acquisition turns that wait into a genuine
DEADLOCK against this file's own concurrency probes — seven failures instead of one. A wait that
resolves beats a cycle that aborts. The bound stays off and the exposure is recorded rather than traded
for a worse one.

Consequences:

Every protected write now refuses a grant whose role the ratified baseline does not admit **and** one
held in a permission mode the baseline does not let spend that capability, independently of any Ruby
check. Two conjuncts of `confers?` are now at the write; the third — the protected-grant gate — is
not, and the next round should look there first.

**THIS DOES NOT ACCEPT S-07-009.** Seventeen rounds, none returning PASS on the state it reviewed.

Authority And Precedence:
S-07-009 repair authority under the overnight instruction. Allocated the next unused number after
ADR-135.

## ADR-137: Round 19 — The Evidence System Reviewed Itself, And Three Of Its Claims Were False

Date: 2026-08-06
Status: Accepted
Scope: S-07-009. Candidate `b2e8cfb..dd78732`, reviewed at `fcc80c0`.

Context:

The eighteenth ADR-026 five-lens round, run in five isolated worktrees against five isolated
databases. Its brief was the one limb three consecutive rounds had each found unbound: the THIRD
conjunct of `CommandAuthorizer#confers?`, the protected-grant gate, and any remaining limb of the
ratified `:314` row the protected writes do not carry.

**VERDICT: FAIL. One of five lenses. Four confirmed-blocking findings, all in range, and for the
first time in this tranche's history NONE of them is in the product — all four are in the EVIDENCE.**

| Lens | Verdict | Confirmed blocking |
| --- | --- | --- |
| Contract-correctness | FAIL | R19-CTR-1, R19-CTR-2, R19-CTR-3, R19-CTR-4 |
| Security / tenant-isolation | PASS in range | none in range; R19-SEC-2 is out of range |
| Concurrency / atomicity | PASS_WITH_OBSERVATIONS | none |
| Schema / migration-safety | PASS | none |
| Architecture / scope / test-quality | PASS | none |

Decision:

**THE PROTECTED-GRANT CONJUNCT IS VACUOUS, AND THE QUESTION IS CLOSED.** All five lenses rebuilt the
evidence independently from the ratified text. Three reasons hold, any ONE of which is sufficient:

1. `:333` — "This enumeration is the authority for which grants are protected" — names none of
   `crawl.trigger`, `crawl.cancel`, `policy.crawl.manage`, and neither `:147` nor `:173` contains
   protected wording, so `:335`'s converse rule does not pull them in. `PROTECTED` has 15 keys and
   none of the three, so `confers?:130` short-circuits before the allowlist and bootstrap limbs.
2. `WriteAuthority.for` is reachable from exactly three call sites, all carrying those three
   capabilities. The handlers that DO spend protected capabilities — WF-013 `role.manage`,
   `invitation.approve` — use no `WriteAuthority` write at all. No consumer can present a protected
   capability to a protected write.
3. `f1_role_assignments_lifecycle_guard` makes `protected_permission_allowlist` and
   `bootstrap_admin_exception` IMMUTABLE for an active grant. Neither can go stale under a running
   command, which is precisely the criterion ADR-132 uses to decide what belongs in the statement.

Measured, not asserted: replacing the entire gate with `true` leaves the WF-005 battery at 115
examples / 0 failures while WF-013 fails three. The mutation is load-bearing — just never for these
capabilities.

The remaining limbs of `:314` were enumerated field by field against the three CTEs. Every liveness
qual `effective_role_assignments` applies is carried at all three writes. The Ruby-only limbs are the
Access Policy (step 2), Account status and Organization status; the first cannot change because
`one_active_access_policy_per_org` is a partial unique index and the runtime role holds only
`SELECT, INSERT` with a single writer at genesis, the second because the only two `UPDATE accounts`
statements set `status = 'active'`, and the third advances the epoch, which IS bound. **There is no
liveness limb the decision evaluates that the write does not carry.**

**THE FOUR BLOCKERS, AND WHAT THEY HAVE IN COMMON.** Each is a record or a proof asserting a property
the repository does not have.

**R19-CTR-1 — A PROOF ROUND 18 RECORDED AS REPLACED WAS ONLY DUPLICATED BESIDE.** `dd78732` is 78
insertions and 3 deletions and its it-block diff is additions only. `wf005_authority_lock_order_spec`
carried PROOF 262c twice — the round-18 driven version AND the round-17 source-scan version that
round 18 rejected — and PROOF 262d twice, byte for byte. Applying round 18's own named defeat (guard
out of the `WHERE`, words left in a comment) failed the driven proof at `:421` and left the rejected
one GREEN at `:487`. Three records state it had been replaced. Repaired by deletion; independently
found by two lenses (R19-CTR-1, R19-CONC-7).

**R19-CTR-2 — THE PRINCIPAL CONJUNCT WAS BOUND BY NOTHING, AND FU-50'S BASIS IS REFUTED.** FU-50
recorded that the battery makes the three CTE copies provably agree because "any drift fails seven
cases at the drifting write". Replacing `ra.account_id = $n::uuid` with a same-arity tautology left
all 27 battery examples green, and across the whole suite the only reaction was
`repository_truth_spec`'s byte-digest staleness check — which fires identically for a COMMENT-ONLY
edit. Nothing in 2464 examples could tell the deletion of an authorization qual from a comment. Every
existing case moves the GRANT; none asked whose grant it is. Repaired with one shared-example case
that fails at exactly the drifting write, verified independently at all three.

**R19-CTR-3 and R19-CTR-4 — RECORDS CLAIMING PROPERTIES THE REPOSITORY DOES NOT HAVE.** The
completion report's header described round 17 while the pinned candidate was round 18's, omitted
ADR-136, and its Identity table pinned a FIVE-ROUND-STALE candidate and repair authority — the same
R8-7 shape, in the same table, because `repository_truth_spec` reads the candidate only from the
`f1-evidence` block. And the report claimed the ledger verifier "requires each row's commit to be
HEAD"; it requires ancestry, `MutationHarness` says so in its own comment, and no row's commit was
HEAD while the gate passed.

**R19-SEC-3, TAKEN THOUGH THE LENS GRADED IT NON-BLOCKING.** The `read_only_permitted` DERIVATION was
unbound: replacing it with `true` survived 68 examples, because `authority_fixture.rb` carries its own
copy of the same expression. This is round 18's CB-2 one column over, and CB-2 was confirmed blocking
with no live bypass either. PROOF 266 drives the production builder with a real read-only grant and
fails on the exploit assertion when the derivation is mutated.

Consequences:

Ledger regenerated at the repair head: 114 definitions, 114 killed, 0 survived, 0 broken. The two new
definitions — `r19-read-only-derivation-constant` and `r19-account-qual-unbound` — both kill, and the
two rows whose `failing_examples` named the deleted duplicates now correctly name one line each.

**THIS DOES NOT ACCEPT S-07-009.** Eighteen rounds, none returning PASS on the state it reviewed. The
round-19 repairs make a NEW candidate that no lens has reviewed, and the tranche's own history is that
each repair round has produced findings in the round that followed. A twentieth round is required.

**WHAT ROUND 19 CHANGES ABOUT THE OUTLOOK.** For the first time no lens found a product defect in
range, four of five lenses returned PASS, and the limb that failed three consecutive rounds is closed
by three independent arguments rather than by another repair. The findings have moved from the
authorization semantics into the evidence system that measures them.

**CARRIED EXPOSURE CLOSED.** BUILD_STATE recorded the lock-order probe's deliberately unbounded setup
as live exposure. It is bounded: `PgTestConnection` sets `statement_timeout = 15s`, measured at 17.28s
to `PG::QueryCanceled` with a complete residue report. It degrades to a failing example, never a hang,
and is not a stability violation.

Authority And Precedence:
S-07-009 repair authority. R19-SEC-2 is expressly NOT taken under it and is recorded as FU-54 for an
owner decision, following the precedent of the round-2 `:442` violation ("it needs a follow-up of its
own and an owner decision; this review opens neither") and of ADR-131. Allocated the next unused
number after ADR-136.

## ADR-138: Round 19's Adversarial Pass Refuted Round 19's Own Repair

Date: 2026-08-06
Status: Accepted
Scope: S-07-009. The round-19 repair head, `67f7ee6`.

Context:

ADR-061 requires that a round returning no confirmed blockers independently challenge its own
conclusion before acceptance. Round 19 DID return blockers, and the challenge was run anyway against
the three claims the round rested on: that the protected-grant conjunct is vacuous, that the two new
proofs are sound, and that the R19-CTR-1 deletion lost no coverage.

**IT REFUTED THE SECOND CLAIM, AND THE REFUTATION IS A LIVE EXPLOIT.**

Decision:

**R-ADV-2 — THE DERIVATIONS WERE BOUND AT ONE CAPABILITY EACH.** `WriteAuthority.for` reads the
ratified cell PER CAPABILITY. PROOF 265 drives one write and PROOF 266 drove one write, so each bound
its derivation for ONE capability. Every other read-only or denied-role case in the suite builds its
authority through `AuthorityFixture`, which carries its OWN copy of both expressions and therefore
cannot bind either. Measured: breaking `read_only_permitted` for `crawl.trigger` ALONE, or for
`policy.crawl.manage` ALONE, or breaking `allowed_roles` for `crawl.trigger` ALONE, left **all 1185
acceptance examples green**. Independently reconfirmed here across `spec/acceptance` plus
`spec/architecture`, where the ONLY failure was `repository_truth_spec`'s byte-digest staleness check
— which fires identically for a comment-only edit.

And the property is genuinely broken, not merely untested. With the first mutation applied, a
Read-Only Executive Buyer — the tuple whose ratified `:147` cell reads `deny` — QUEUES A CRAWL:

    HEAD:       capability_authorized=false  inserted=0
    ro-trigger: capability_authorized=true   inserted=1

**THIS IS ROUND-18 CB-1 ONE CAPABILITY OVER, INSIDE THE ROUND-19 REPAIR FOR IT**, and it is this
tranche's signature shape: a control proved at one instance and assumed at the others — the exact
defect class round 16 was called for, recurring for the fourth time.

REPAIR, AND WHY IT IS STRUCTURAL RATHER THAN THREE MORE PROOFS. Both cases now live in the battery's
SHARED EXAMPLES, so they run at every write the battery ENUMERATES and a fourth protected write
inherits them THE MOMENT IT IS ADDED TO `WRITES`. That last clause is a correction: this sentence
originally read "by construction … a fourth protected write would inherit them", and the following
review refuted it by construction (finding F-2). It built a fourth protected write carrying the same
authority CTE with two conjuncts removed; outside `WRITES` the whole suite stayed at 2472/0 with
Zeitwerk, Packwerk and Brakeman clean, and the identical file added to `WRITES` produced 48 examples
with 3 failures. The inheritance is real but it is triggered by a hand-maintained literal, not by
construction. FU-61 records the gap; the battery's own header (`:22-24`) always stated the
precondition correctly. Each seeds a grant for the ACTOR'S OWN account — so the principal qual passes — and builds the
authority through the PRODUCTION BUILDER for that write's real capability: a `MarketingOperator`
read-only grant, whose role is inside all three cells so only the sixth column can refuse it; and a
`TechnicalImplementer` grant, which the ratified table denies all three capabilities and which the
battery's `required_role: nil` leaves `allowed_roles` alone to refuse. Each asserts the ratified cell
still has the shape the case depends on, so neither can go vacuous if the table is amended.

VERIFICATION. All three capability-scoped mutations now die, each at exactly the write whose capability
was broken and at no other:

    read_only broken for crawl.trigger ONLY       -> [1:2:10] the queue insert
    read_only broken for policy.crawl.manage ONLY -> [1:3:10] the policy activation
    allowed_roles broken for crawl.trigger ONLY   -> [1:2:11] the queue insert

All three are registered as ledger definitions.

**WHAT SURVIVED THE CHALLENGE.** The R19-CTR-1 deletion lost no coverage: the two PROOF 262d blocks
were byte-identical, both 262c variants covered `activate` and `reject`, and the deleted source scan's
unique catch set is exactly {edits removing the literal text while still refusing an active row},
every member of which leaves the security property intact. The battery's principal-conjunct case was
attacked with a per-qual attribution probe and refuses on `account_ok` alone at all three writes — not
vacuous.

**WHAT WAS NARROWED.** The vacuity of the protected-grant conjunct HOLDS for the three capabilities in
play, but its "three independent grounds" were not independent. The SQL has no analogue of the Ruby
short-circuit: the write never reads `protected_permission_allowlist` or `bootstrap_admin_exception`
for ANY capability. Measured — a `role.manage` authority presented to `CrawlStartStore#cancel`: Ruby
`authorize` DENIES (`missing_authority`), the write AUTHORIZES and cancels a running Crawl. It is
latent only because no production caller passes a protected capability and `CAPABILITIES.fetch` fails
closed for 13 of the 15. The real support is ground (b), a CALLER CENSUS — which is the "one deletion
away from nothing" shape FU-48 exists to remove. `WriteAuthority.for` has FOUR call sites in `app/`,
not three: the three handlers plus `authority_attestation.rb:66`, and both it and
`PostWaitDecision#authority_attestation` take a free `capability:` parameter. Recorded as FU-58.

Also corrected: `f1_role_assignments_lifecycle_guard` is BEFORE UPDATE only. There is no INSERT
trigger and no CHECK constraining an active row's allowlist, so an INSERT may create an ACTIVE grant
with any protected allowlist and `bootstrap_admin_exception = true`; dual control at insert time is
Ruby-only. It does not reach the writes — an INSERT mints a new id and the CTE joins on the carried
`g.id` and `g.state_version` — but ground (c) is not the guarantee it was stated to be. FU-59.

Consequences:

**S-07-009 IS STILL NOT ACCEPTED, AND ROUND 19 IS NOT A PASS.** A round whose own repair contained a
live exploit of the class it was repairing cannot be an acceptance round. Ledger regenerated with the
three new definitions. The next five-lens round reviews the repair range and should be directed FIRST
at whether any remaining control is proved at one instance and assumed at the others.

Authority And Precedence:
S-07-009 repair authority; the adversarial pass is the ADR-061 self-challenge. Allocated the next
unused number after ADR-137.

---

## ADR-139: FU-63 — The Battery Was Parameterised By Write, And Not By Configuration

Date: 2026-08-06
Status: Accepted
Scope: S-07-009 repair. Evidence only: no production behaviour is changed by this ADR, and none was
found defective by round 20.

Context:

Round 20 returned DO NOT ACCEPT with FU-63 as its blocker: **five authorization controls in the
WF-005 write path were proved at one instance and assumed at the others.** 78 narrowly-scoped,
arity-preserving mutations; 48 survived; 5 confirmed against the full 1191-example acceptance corpus.

**NO REACHABLE PRODUCT DEFECT WAS FOUND, AND NONE IS REPAIRED HERE.** Twelve probes against the real
stores and handlers passed at HEAD, and a 63,000-tuple differential across the five deciders found
only `required_role` (by design) and FU-58 (latent). These were EVIDENCE gaps, the category ADR-138
recorded for its own round.

A15-1 made the battery run at every WRITE. What round 20 measured is that it still ran at ONE VALUE
of everything else:

* `g.id = ra.id` was bound by NOTHING at any of the three writes. Unbound at the queue write the
  battery was 36 examples / 0 failures, and driven at the store it QUEUED A CRAWL ON A REVOKED GRANT.
  The round-19 foreign-account case does not bind it: `TenantSeeder` inserts `state_version 0` with a
  NULL scope while the bootstrap grant is `state_version 1` with a scope digest, so that case is
  discriminated by the VERSION and SCOPE conjuncts and never reaches identity.
* Every driver used ORGANIZATION scope with `required_role: nil`, so THE ENTIRE PROJECT-SCOPE
  CONFIGURATION of `ActivateCrawlPolicy` had no write-level negative proof. `read_only_permitted`
  derived as `!required_role.nil?` is FALSE in every case that existed and TRUE on the one production
  path that carries a scope rule; driven, A READ-ONLY EXECUTIVE BUYER ACTIVATES AN IMMUTABLE
  PROJECT-SCOPE CRAWL POLICY.
* `same_principal?` compares TEN members and PROOF 251 bound ONE.
* "Refused BEFORE the lock" was proved only for an actor holding NO Assignment.
* `ra.status = 'active'` was bound only against `revoked`.

Decision:

**THE BATTERY IS PARAMETERISED BY CONFIGURATION, NOT ONLY BY WRITE.** FU-63's six-part repair,
implemented in full:

1. **The negative role population is DERIVED FROM `:135`.** `spec/support/ratified_permission_baseline.rb`
   parses the ratified Permission Baseline table once, and the battery drives one refusal case per
   canonical role whose cell for that capability reads `deny` — replacing a hand-picked
   `TechnicalImplementer`. `permission_baseline_transcription_spec.rb` now reads the SAME parser
   rather than carrying a second copy of it, and asserts that the denied set is the exact complement
   of the transcribed allow-set for every materialized capability.
2. **`WRITES` carries each write's PRODUCTION `required_role`, and the policy write appears at BOTH
   ratified scopes.** The fourth entry is the Project-scope configuration `SCOPE_ROLE["project"]`
   names, seeded with the MarketingOperator grant it demands.
3. **Grant identity is bound by a COLLISION.** The carried tuple names a REVOKED Assignment while a
   LIVE sibling of the same principal sits at the same version and the same scope, so every
   non-identity conjunct is satisfied by the sibling and identity is the only thing left that can
   refuse. `one_active_assignment_per_tuple` is a partial index over `status = 'active'`, which is
   what lets the pair differ in nothing else. Two grants at the same version is a production shape
   (`invitation_store.rb:113`).
4. **`require!` is driven over `WriteAuthority.members`.** Each of the ten members is perturbed in
   turn and must be refused, with the unperturbed authority accepted first so the sweep cannot pass
   vacuously. The subject is the `Data` class itself, so a member added later is covered the day it
   is added — demonstrated during implementation: the first draft enumerated nine perturbations and
   the derivation failed on the tenth, `allowed_roles`, rather than skipping it.
5. **PROOF 255/256/257 drive every unauthorized shape**, not only the emptiest one: an Account with no
   Assignment, then one per denied role, each a real active effective grant. PROOF 257c adds the
   Project-scope counterpart of 257b, which had the pre-lock property at neither layer.
6. **The status conjunct is swept over the whole vocabulary**, read from the column's CHECK
   constraint rather than listed, at every write.

Evidence:

| Proof file | Before | After |
| --- | --- | --- |
| `spec/acceptance/wf005_grant_battery_spec.rb` | 36 | 68 |
| `spec/acceptance/wf005_capability_write_authority_spec.rb` | 22 | 24 |
| `spec/architecture/permission_baseline_transcription_spec.rb` | 5 | 6 |

Twenty-one round-20 definitions were added to the mutation set and replayed by the repository's own
harness. **Twenty are killed. One survives, and is recorded as EQUIVALENT with its reason:**

`r20-cancel-status-admits-pending` widens the status conjunct to admit `pending`. A pending Role
Assignment CANNOT BE EFFECTIVE — the table's CHECK `role_assignment_pending_is_not_effective` forbids
it — and the same CTE requires `ra.effective_at IS NOT NULL`. No row the database can hold is
admitted by the widening, so it cannot change the outcome of any execution. That is an equivalent
mutation, not an unbound control, and it is not excused in prose: the battery drives every status the
CHECK admits at every write, and asserts that the CHECK still exists, so if it is ever dropped the
equivalence fails loudly instead of ageing into a false record. Its discriminating sibling,
`ra.status <> 'pending'`, is killed at all three writes.

**WHAT IS DERIVED AND WHAT IS STILL A LIST.** Round 20 refuted ADR-138's "by construction"
inheritance claim by building a fourth protected write that inherited nothing while the suite stayed
green, so this repair does not restate that claim in a wider form. Two of the three populations here
ARE derived and cannot drift: the denied ROLES come from the ratified document, and
`same_principal?`'s members come from the `Data` class. **`WRITES` IS STILL A HAND-MAINTAINED LIST**,
and enforcing its completeness is FU-61, which remains open. What this repair adds for the policy
write alone is a totality check: `SCOPE_ROLE`'s keys are exactly the two scopes `valid_scope_shape?`
admits, none of its values is nil, and both are driven by the battery — which is also the premise
that makes widening `allowed_roles` for `policy.crawl.manage` equivalent rather than unbound, since
`required_role` pins a single role at every production configuration of that write.

Consequences:

FU-63 is RESOLVED. This ADR does NOT accept S-07-009: the repair produces a new candidate that no
lens has reviewed, and this tranche's history is that every repair round produced findings in the
round after it. The next action is a fresh five-lens review of the resulting candidate.

FU-37, FU-49, FU-50, FU-51, FU-53, FU-54 (owner), FU-55, FU-56, FU-57, FU-58, FU-59, FU-60, FU-61 and
FU-62 remain open and unchanged.

Authority And Precedence:
S-07-009 repair authority under the owner's autonomous build execution directive of 2026-08-06, which
reopens S-07-009 implementation and directs the FU-63 repair first. Allocated the next unused number
after ADR-138.

---

## ADR-140: FU-54 — The Ratified Protected-Grant Enumeration Was Three Entries Short, And One Was Live

Date: 2026-08-06
Status: Accepted
Scope: `Platform::PermissionBaseline::PROTECTED` and the transcription check that governs it.
PRE-EXISTING and OUTSIDE the S-07-009 candidate range; taken here under the owner's autonomous build
execution directive rather than deferred as another tranche's backlog.

Context:

`WORKFLOW_SPECIFICATIONS.md:333` enumerates the protected grants and `:335` states that "This
enumeration is the authority for which grants are protected". It names EIGHTEEN permissions.
`Platform::PermissionBaseline::PROTECTED` carried FIFTEEN.

**NOTHING COULD SEE THE GAP.** `permission_baseline_transcription_spec.rb` checked `CAPABILITIES`
against `:135` in two dimensions — the role cells, and the Read-Only Executive Buyer column — and had
NO third dimension for `PROTECTED` against `:333`. Round 20 measured the consequence directly:
deleting a ratified `PROTECTED` entry left the full suite at 2472/0.

Two omissions were harmless. `security.investigation.approve` (`:185`, SecurityOperator "protected
explicit grant") and the SecurityOperator `organization.close` arm (`:139`, "protected approval only")
are under-grants in the fail-closed direction, because SecurityOperator is already protected through
other keys; only the exactness of `:240`'s protected-permission preview was wrong.

**THE THIRD WAS A LIVE AUTHORIZATION DEFECT, REPRODUCED BEFORE IT WAS REPAIRED.** `:175` makes
BillingOperator the ONLY role whose `policy.entitlement.manage` cell reads `allow`, and BillingOperator
appears in no other entry, so `protected_role?("BillingOperator")` was FALSE.
`request_role_assignment.rb:61` therefore classed such a request non-protected, `GrantAuthority.evaluate`
ran with `direct: true`, and the approval requirement never fired. Measured at HEAD before the repair,
through the real handler: a lone OrganizationAdmin requesting a BillingOperator grant got
`success=true`, `status=active`, `approval_due_at=nil`, and an empty allowlist — an immediately-active,
never-expiring grant carrying protected authority, issued on one administrator's say-so.

That contradicts `:333` ("approval within 24 hours by a SecurityOperator other than the requester"),
`:316` (mandatory active expiry) and `:140` (an OrganizationAdmin's `role.manage` cell is confined to
"non-protected tenant grants").

Decision:

**TRANSCRIBE THE ENUMERATION IN FULL, AND GIVE IT THE DIMENSION THAT WOULD HAVE CAUGHT THE GAP.**

`PROTECTED` gains `policy.entitlement.manage => [BillingOperator]`,
`security.investigation.approve => [SecurityOperator]` and `organization.close => [SecurityOperator]`.

`organization.close` carries ONLY its SecurityOperator arm, because `:333` says so in words: "the
OrganizationAdmin baseline cell permitting a closure request for the actor's own Organization is not a
protected grant and is unchanged." Every other entry takes its whole non-deny row. That single
exception is recorded as DATA in `spec/support/ratified_permission_baseline.rb`, checked against the
document, so adding a second exception is a visible act rather than a reader's judgement.

**DIMENSION 3.** `permission_baseline_transcription_spec.rb` now derives the whole map from `:333`'s
sentence plus `:135`'s cells and compares `PROTECTED` to it. The subject is the document, not a second
literal beside the first.

**AND THE BEHAVIOURAL HALF.** `spec/acceptance/wf013_protected_enumeration_spec.rb` drives the real
`RequestRoleAssignment` handler for EVERY canonical role the ratified enumeration protects — derived,
not hand-picked — and requires each to land `pending` with a 24-hour approval deadline, no
`effective_at`, and an empty allowlist. A non-protected role is the control and must still land
`active`, so the rule is the enumeration rather than a blanket refusal. The expiry is supplied so the
refusal cannot be over-determined by `role_expiry_required`, which fires first when it is absent.

Evidence:

Three mutations, replayed by the repository's own harness, all KILLED — the same deletions that left
the suite green before this repair:

| mutation | result |
| --- | --- |
| `fu54-protected-entitlement-entry-deleted` | killed, 3 failures |
| `fu54-protected-close-arm-widened` | killed, 1 failure |
| `fu54-protected-investigation-entry-deleted` | killed, 1 failure |

One fixture encoded a classification it does not own: `wf013_activation_lifecycle_spec` seeded three
roles including BillingOperator and asserted three activation timers. A protected Invitation correctly
goes to approval and gets no activation timer. The roles and the expected count are now DERIVED from
the enumeration. The invariant under test — every active Invitation has exactly one timer at its own
expiry instant — is unchanged and was never broken.

Consequences:

**CUSTOMER-VISIBLE, AND STATED PLAINLY.** A BillingOperator grant now requires approval by a different
SecurityOperator within 24 hours and a mandatory expiry. An Organization holding no SecurityOperator
cannot create a BillingOperator directly; `:333`'s first-SecurityOperator path is the route to one.
This is what the ratified specification requires, and the previous behaviour was the defect — but it
is a real change to an accepted workflow and the owner should know it happened rather than read it in
a diff.

**IT IS NOT RETROACTIVE.** `protected_role?` governs the GRANT path — invitation classification and
role-assignment request classification — not the USE path. Existing active BillingOperator Assignments
are unaffected; `policy.entitlement.manage` is not materialized in `CAPABILITIES`, so no authorization
decision changes.

FU-54 is RESOLVED. This ADR does not accept S-07-009 and does not change any WF-005 behaviour.

Authority And Precedence:
Taken under the owner's autonomous build execution directive of 2026-08-06, whose Tier 1 rule governs
authorization defects and whose owner-interaction threshold this does not meet: the repository
resolves the specification question outright (`:335` — "this enumeration is the authority"), the
change strengthens rather than weakens authorization, and no frozen contract is touched.
`AUTONOMY_POLICY`'s "not another tranche's backlog" limit is what had held it as
`owner_decision_required`; the directive supersedes that limit and the reasoning is recorded here
rather than assumed. Allocated the next unused number after ADR-139.

---

## ADR-141: FU-43 — F-01 Gets A Total Request Deadline, And `deadline_at` Becomes A Real Boundary

Date: 2026-08-06
Status: Accepted
Scope: **A RATIFIED EVOLUTION OF A FROZEN FOUNDATION.** `FOUNDATION-001` Shared Outbound Transport,
property 6a. Five frozen paths change.

Context:

FU-43 was opened at round 3 (R3-4 half a) and has been `owner_decision_required` ever since, because
`AUTONOMY_POLICY:177` and `AUTONOMOUS_BUILD_CONTROLLER.md:169` make any change to a frozen foundation
a mandatory human escalation. Half (b) — anchoring the budget to the pass's own elapsed time — was
repaired at the time. **Half (a) could not be repaired by any caller.**

`RequestPolicy#timeout_s` was documented as "the connect-plus-response deadline for ONE connection
attempt (each redirect hop is a fresh attempt with its own budget)", and `GuardedHttpClient#attempt`
implemented exactly that: a fresh `resolver.resolve(timeout_s: policy.timeout_s)` and a fresh
`deadline = monotonic + policy.timeout_s` at every hop. At the ratified `max_redirects` ceiling of 10,
one `Outbound.fetch` bounded at N seconds could therefore run `(10 + 1) × (dns + response)` — the
acceptance review measured **11.1×**, and up to 22× with DNS timing.

**SO `deadline_at` WAS NOT A BOUNDARY.** A crawl the run's wall clock was supposed to end could still
be reading a customer's site minutes later. `FetchContent` believed otherwise and said so in a
comment: passing the run's remaining wall clock as `timeout_s` "needs no change to F-01". That was
half true — it bounded one connection attempt — and the other half is this defect. No caller-side fix
existed: the façade accepted only a per-attempt number, so the only lever was `max_redirects`.

Decision:

**ONE `fetch` HAS ONE WALL-CLOCK BOUNDARY.** The owner ratified the evolution on 2026-08-06 and
declined both alternatives — capping redirects as a mitigation, and documenting the overrun as
accepted behaviour.

`RequestPolicy` gains `total_timeout_s`. DNS resolution, connection setup, TLS negotiation, response
headers, body reads and every redirect hop spend that one budget. No hop re-arms anything. When it is
exhausted the client stops deterministically and reports the ratified `:timeout` outcome, which the
existing crawl-lifecycle contracts already classify and audit.

**THE PER-ATTEMPT TIMEOUT SURVIVES ONLY AS A SUBORDINATE CEILING.** Every operation asks
`policy.effective_timeout_s(remaining)`, which is `[timeout_s, remaining].min` — one place, so no
operation can be handed a budget the total does not have.

**THE TOTAL IS CLAMPED TO THE SAME HARD BOUND AS THE PER-ATTEMPT CEILING** (`TOTAL_REQUEST_TIMEOUT_MAX_S
= CONNECT_RESPONSE_TIMEOUT_MAX_S`, 15s, PRULE-008). The overrun is now arithmetically impossible
rather than merely discouraged: no `fetch` can exceed fifteen seconds of wall clock however many hops
it follows.

**A CALLER CANNOT ACCIDENTALLY BYPASS IT** (owner requirement 6). `total_timeout_s` defaults to
`timeout_s`, so a caller supplying only a per-attempt number gets that number as its TOTAL — the
tightest reading, not an unbounded one. There is no shape of `Outbound.fetch` without a total. Every
existing call site is therefore strictly tighter than before with no change: `FetchContent` already
passes the run's remaining wall clock, and that argument now means what its comment always claimed.

Evidence:

`spec/platform/outbound/total_deadline_spec.rb` — a **maximum-length redirect chain**, ten hops, with
seams that burn real time, measured on the wall clock:

- the chain completes and returns 200 when the budget allows it (non-vacuity: eleven opens, terminal
  host reached, elapsed greater than the chain's own cost);
- under a budget smaller than the chain costs the outcome is `:timeout`, **fewer than eleven
  connections are opened**, the terminal host is never reached, and elapsed is below the budget plus
  one hop — it stops early rather than reporting late;
- no connection is ever handed a deadline past the total boundary;
- the caller's `redirect_guard` is not consulted once the budget is exhausted;
- every operation is handed the lesser of the two bounds, and the remaining budget strictly shrinks
  across hops;
- the per-attempt ceiling still binds when it is the tighter of the two;
- omitting `total_timeout_s` yields the per-attempt value, and a caller asking for 600s gets the
  platform ceiling.

Five mutations, each restoring one limb of the old behaviour, all KILLED:
`fu43-connect-deadline-rearmed-per-hop`, `fu43-resolver-deadline-rearmed-per-hop`,
`fu43-pre-hop-budget-check-removed`, `fu43-total-budget-defaults-to-ceiling`,
`fu43-effective-timeout-ignores-remaining`.

**TWO OF THEM SURVIVED THE FIRST DRAFT OF THAT FILE, AND BOTH WERE GAPS IN THE PROOF RATHER THAN IN
THE CODE.** The harness burned its time in the resolver and in `open`, so the connect/read cap was
bound by nothing — reverting it survived all six examples. And deleting the pre-hop budget check left
every outcome identical, because the check at the top of `attempt` catches the exhausted budget one
step later; what differs is that the CALLER'S `redirect_guard` — `:448`'s robots and Source Scope
recheck, which in production takes a per-gate lock and writes an authorization decision — is consulted
for a hop that can never be made. That is PRULE-039's reasoning exactly, and it is this tranche's
signature defect appearing inside the repair for a different instance of it. The connector now records
the absolute deadline it is handed and the guard records its invocations.

**THREE RECORDS THE OLD BEHAVIOUR MADE TRUE ARE CORRECTED WHERE THEY STAND**, rather than left to read
as live hazards: `Lease` and `EnsureRobots` both cited "~165 seconds" for one call, and
`DiscoverSitemaps` "~330 seconds" for two. One call is now bounded at fifteen. The per-hop renewal
boundaries those comments justify are UNCHANGED and still correct — a 30-second lease against a
15-second call leaves no margin for the second fetch, and `redirect_guard` is also `:448`'s recheck,
which is not a leasing concern — only the arithmetic was false.

Consequences:

FU-43 is RESOLVED. Every platform-originated request is now bounded by a real wall clock, which is
what `:442`'s "incomplete requests are canceled" requires and what `deadline_at` has always claimed.

Behaviour is strictly tighter everywhere, and that is a real change: a single-attempt request that
previously had `timeout_s` for DNS *and* `timeout_s` for connect+response now has one budget covering
both. S-05 verification (10s, 0 redirects) and the WF-005 robots, sitemap and content paths all run
inside the ratified ceilings and the full suite is green, but a customer site that was answering just
inside the old doubled budget will now time out. That is the specified behaviour, not a regression.

Authority And Precedence:
Owner decision of 2026-08-06, which ratifies the frozen-contract evolution, requires the total
deadline as the authoritative correction for FU-43, and explicitly declines the lower-redirect
mitigation and any documentation of the overrun as accepted behaviour. `FOUNDATION-001` property 6a
records the evolution in the contract itself. Allocated the next unused number after ADR-140.

---

## ADR-142: S-07-009 Is Accepted

Date: 2026-08-06
Status: Accepted
Scope: Acceptance of the S-07-009 tranche. Also records the constrained ADR-080 review that
authorises it, and the one finding that review made.

Context:

S-07-009 returned NOT ACCEPTED eighteen recorded five-lens rounds running, plus the round-20 pass
that opened FU-63. Round 20 found no reachable product defect on any axis — twelve probes against the
real stores and handlers passed at HEAD, and a 63,000-tuple differential across the five deciders
found only `required_role` (by design) and FU-58 (latent). **Every blocker was in the evidence.**

FU-63's six-part structural repair is complete (ADR-139) and its own defect-focused review closed
three further gaps in it. The owner then directed two changes outside the tranche: FU-54's ratified
protected-grant enumeration (ADR-140) and FU-43's total request deadline, F-01's ratified
frozen-contract evolution (ADR-141).

The owner authorised acceptance conditional on ONE independent, defect-focused review, constrained to
FU-63's repair, the newly added production-shaped configurations, the mutation classifications and
claimed equivalence, the independent binding of every security-relevant conjunct, and FU-54 as a
separate behavioural change — with an explicit instruction not to reopen the twenty-round history.

Decision:

**S-07-009 IS ACCEPTED.** The review found no demonstrated release blocker.

**IT FOUND ONE REAL DEFECT, AND IT WAS REPAIRED RATHER THAN CARRIED.** Building the
conjunct-by-site coverage matrix the ledger implies — rather than reading the ledger — showed that
FU-63 had made the BATTERY run every case at every write while the LEDGER still measured four
conjuncts at ONE write and assumed the copies: `g.scope_hex` and `ra.effective_at` at the
cancellation alone, `ra.expires_at` at everything but the policy write, and the scope-rule cell blank
at the queue. That is this tranche's signature shape one level up. Five new mutations closed it and
ALL FIVE DIE, so the battery's cases did discriminate at every site and now that is measured. The
sixth cell is recorded as EQUIVALENT with its premise: no production caller of the queue insert sends
a `required_role`, and the row states what would have to change for that to stop being true.

**WHAT THE REVIEW CONFIRMED.** Every one of round 20's five confirmed survivors now dies. The two
surviving mutations in the ledger are both recorded equivalences whose premises are asserted
executably — the `role_assignment_pending_is_not_effective` CHECK, and `SCOPE_ROLE`'s totality
against `valid_scope_shape?`. The derived populations that cannot drift are the denied ROLES (from
the ratified document) and `same_principal?`'s members (from the `Data` class); `WRITES` remains a
hand-maintained list and FU-61 remains open, which this record states rather than papers over.

**FU-54, VERIFIED AGAINST THE OWNER'S FIVE QUESTIONS.** The implementation is derived from `:333` +
`:135` and gated by a third transcription dimension. Approval and expiry are enforced: every ratified
protected role lands `pending` with a 24-hour approval deadline, no `effective_at` and an empty
allowlist, with a non-protected control that still lands `active`. NOTHING IS RETROACTIVE — none of
the three newly protected permissions is materialized in `CAPABILITIES`, so no live authorization
decision changes. An Organization without a SecurityOperator fails safely and visibly: the request is
pending, confers nothing, and expires unapproved. There is no authorization deadlock and no
impossible bootstrap state — WF-001 genesis is untouched, and a BillingOperator confers NOTHING
materialized in this build because `policy.entitlement.manage` belongs to the unbuilt CAP-024 / S-22.

**ONE CONSEQUENCE IS RECORDED AS FU-64 RATHER THAN LEFT IN PROSE.** Making BillingOperator protected
also routes its REVOCATION through `role_protected_authority_required`, so an existing BillingOperator
Assignment now needs a SecurityOperator to revoke — and no Organization can obtain one until the
security-bootstrap service is built (`decide_role_assignment.rb:111` refuses the first SecurityOperator
by design, pre-existing and unchanged here). It blocks nothing today because the role confers nothing
materialized. It MUST be resolved before S-22 materializes `policy.entitlement.manage`.

Evidence:

Candidate `b2e8cfb..4c1d0a1`, 52 files, every one under a declared path and the excluded set EMPTY.
rspec 2522/0; architecture 245/0 with 1 pending; brakeman 0; packwerk clean; zeitwerk ok;
bundler-audit clean; controller unit 39/0, integration 20/0, policy 21/0, crash_recovery 5/0,
locking 5/0, end_to_end 10/0; verify_runtime 15 checks with RLS intact; no structure drift;
`bin/f1-db-bootstrap-gate` 9/9; mutation ledger 155 definitions, 153 killed, 2 recorded equivalent,
0 broken.

Consequences:

`completed_blocks` gains S-07-009. `current_tranche` moves to **S-07-010** — Documents, ingestion,
Evidence and durable handoff — which `BUILD_PLAN.yml` gates on S-07-009 alone. S-07-011 remains gated
on S-07-010.

Open follow-ups carried, none blocking: FU-2, FU-3, FU-6, FU-7, FU-8, FU-12, FU-13, FU-14, FU-15,
FU-17, FU-20, FU-22, FU-23, FU-26, FU-27, FU-28, FU-29, FU-32, FU-33, FU-37, FU-39, FU-40, FU-42,
FU-46, FU-47, FU-49, FU-50, FU-51, FU-53, FU-55, FU-56, FU-57, FU-58, FU-59, FU-60, FU-61, FU-62 and
the newly opened FU-64.

Authority And Precedence:
Acceptance under standing delegation ADR-061 and review discipline ADR-080, on the owner's explicit
condition of 2026-08-06: one independent defect-focused review over the pinned candidate range, no
reopening of the closed history, and acceptance when no demonstrated blocker remains. Allocated the
next unused number after ADR-141.

## ADR-143: S-07-010 Built — The Durable Handoff, With Body Staging On F-02 As A Recorded Interim, And D3 Resolved Inline

Status: Accepted (implementation and verification); the tranche is NOT accepted as a block — the
independent ADR-026 five-lens review has not run, and ADR-061 makes that review half of the
acceptance mechanism.
Date: 2026-08-06
Owner: implementation agent under standing delegation ADR-061 / ADR-086; no owner ruling was required
Reversibility: Two migrations and one new workflow limb. The staging decision below is the only part
that a later block would migrate rather than simply change, and FU-65 states the migration.

Decision:

Record the S-07-010 build — Documents, Ingestion Jobs, their attempt history, the `ingestion-interim-v1`
lifecycle, F-03 `source_document` and `content_absent` Evidence, and the durable handoff into parsing
(WORKFLOW_SPECIFICATIONS.md :460-466; contracts/S-07.json MTX-008). It ENDS BEFORE the OD-027 withheld
limb: no `parsing_jobs`, no `indexing_jobs`, no `has_one`, no `unique (parsing_job_id)`.

**1. The durable handoff is a CONSTRAINT.** MTX-008 makes the handoff "the succeeded IngestionJob with
its valid `source_document` Evidence" and :464 says "No Document may become ingested or enter the parse
manifest WITHOUT that valid Evidence". `ingestion_jobs_succeeded_carries_evidence` and
`ingestion_jobs_evidence_only_on_success` are those two sentences as CHECKs, so a succeeded job without
its handoff is unrepresentable rather than merely unwritten — which is what lets S-08 read
`state = 'succeeded'` without re-validating every row of :472's manifest.

**2. D3 is resolved INLINE, which is the narrow reading.** ADR-067 left open whether :452's body-free
`content_absent` observation is produced at fetch-commit or through the ingestion pipeline. The pipeline
reading cannot be built without inventing product state: an IngestionJob's identity is keyed on
`fetched_body_sha256` and a 404 has no body; its Document would have no `fetched_object_id`, `byte_size`
or `content_sha256`; and :464's success path — the only path that produces Evidence — is defined as
creating a `source_document` and moving a Document `discovered -> ingested`. :452 says this outcome has
none of those. It is therefore produced in the same transaction that retires the frontier entry, with
no job and no Document, exactly as :452 describes it.

**3. BODY STAGING IS F-02, AND THAT IS AN INTERIM WITH ITS REASON STATED.** :462 requires staged bytes
that are "immutable and inaccessible to product reads"; :464 destroys the "separate staging reference"
at success; :466 destroys them at 24 hours. The canonical home is `stored_objects`
(POSTGRESQL_SCHEMA.md :231, `storage_provider CHECK ('aws_s3')`) — a shared platform table that has
never been built, that no S-07 tranche owns, and whose construction needs an external paid provider,
which the autonomy policy makes an OWNER decision rather than an implementer's. Building it here would
repeat exactly what D1 and D2 were escalated for.

F-02 supplies all three properties through a frozen public contract this repository already uses for
precisely this purpose — S-05 stores its redacted verification payload "behind an F-02 reference":
`protect` returns a capability, there is no product read path to the ciphertext, and `erase` is a
record-level cryptographic destruction. The staged record's AAD purpose is `temporary_processing`,
which is the retention class SCORE_EVIDENCE_MODEL.md names for "staging bytes before Evidence
creation". The Evidence payload is a SEPARATE retained record — which is why :464 calls the destroyed
one "the separate staging reference" — so destroying the staging copy cannot dangle the Evidence.
`documents.fetched_object_id` names the staged object and keeps naming it after destruction, exactly
as a `stored_objects` row survives its own `destroyed` transition. FU-65 carries the migration.

**4. The classification of crawled content is DERIVED, not chosen.** SCORE_EVIDENCE_MODEL.md defines
`public` as "lawfully public source content" and `confidential` as "customer-PROVIDED nonpublic
content". F-01 makes every crawl request anonymous and unauthenticated, so anything a Crawl can reach
is content the Source serves to any client on the internet. Over-classifying is NOT the safe direction
here: the same document says "declassification is PROHIBITED", so a defensive `restricted` could never
be lowered and would put every crawled page behind a security grant that does not exist. The value is a
per-job column so a later capture policy can classify differently.

**5. The action targets the JOB, not the attempt, and this is stronger than ADR-085's analogue.**
BACKGROUND_PROCESSING.md :200 records `ingestion_attempt_due`'s direct claim owner as "Ingestion
Attempt". An attempt row created at SCHEDULING time would consume one of :466's three attempts without
ever running, because `attempt_count` is `COUNT(*)` over `ingestion_attempts`; and the retry action is
minted by the transaction that RECORDS THE FAILURE, so the failing execution would be creating its
successor's attempt — a second producer, which ADR-085 refused. The job is a genuine claim owner
(`queued -> running` under a compare-and-set IS the claim) and the durable idempotency authority is
unchanged: `(ingestion_job_id, attempt_number)` under its `ON CONFLICT`. Unlike `crawl_frontier_entry`,
`ingestion_job` IS a member of the entity-type vocabulary API_CONTRACTS.md declares closed, so FU-17's
divergence does not extend to this kind.

Three defects were found by the tranche's own acceptance chain and its self-review, and repaired
rather than worked around:

**(a) The lifecycle guard evaluated the edge set on EVERY update**, so `succeeded -> succeeded` was an
illegal transition — and :464's own next sentence, "deletes the separate staging reference", is an
UPDATE of a succeeded row that changes no state. The repair is NOT a self-edge in the edge set: that
would let a writer consume a `state_version` for a transition that did not happen and break another
worker's compare-and-set for no reason. A state-preserving update is admitted and separately forbidden
from advancing the version.

**(b) A CONTENDED delivery stranded its job for ever.** `ScheduledActions::Worker#run_handler`
SETTLES every result that is not a confirmed lease loss, so a delivery that found a live
`ingestion_attempts` lease correctly reported `ingestion_attempt_contended` and ENDED ITS OWN ACTION.
If the incumbent then died, the job sat `running` behind a lease that would lapse with nothing pending
to notice it — permanently, because :466's retry is only ever minted by a settle that never happens and
`running_work_sweep_due` has no registered handler. Any worker crash whose action is re-dispatched
inside the 300-second attempt lease reaches it. The repair is a SUCCESSOR rather than a longer lease or
a new sweep kind: one `ingestion_attempt_due` at the incumbent's own lease boundary, read from the
committed attempt row so two contended deliveries compute one action identity — the rule ADR-089
established for :444's retry instant, applied to the same class of race. It cannot spin, and the reason
is the state machine rather than a counter: by that instant the job is either settled (the successor
gets `ingestion_job_not_runnable` and mints nothing) or its lease has expired (the successor reclaims
it and applies :466).

**(c) `spec/architecture/repository_truth_spec.rb` hardcoded two S-07-009 artefacts** — the mutation
ledger and the acceptance-review record — inside a block titled "the record of THE TRANCHE CURRENTLY
UNDER REVIEW", while every sibling check derives its subject from `current_tranche`. That is the exact
defect :191 already corrected for `report_path`. It was not cosmetic: the ledger binds each verdict to
the BYTES of the file it was measured against, so the first tranche to touch one of those files makes
the ACCEPTED ledger stale and the gate reports a defect in a record nobody is reviewing. Both are now
derived, both skip when the tranche has no such record, and `f1:mutations:regenerate` takes a `SET`
from a closed registry so a second tranche can regenerate its own ledger at all.

Verification from the candidate state: rspec 2575/0; brakeman 0 warnings; packwerk and zeitwerk clean;
`bin/f1db f1:db:verify_runtime` 15 checks with RLS intact; architecture 245/0; structure file matches
the current schema; mutation ledger 22 definitions, 22 killed, 0 survived, 0 broken.

Consequences:

`current_tranche` remains S-07-010 and the block is NOT added to `completed_blocks`: ADR-061 makes the
objective verification suite PLUS the independent ADR-026 five-lens review the acceptance mechanism,
and only the first half has run. What this ADR records is that the implementation is complete against
the governing text, every mandatory gate is green, and an adversarial self-review against :460-466,
:452, MTX-008 and MTX-030 found and repaired the three defects above.

Three follow-ups are opened: FU-65 (the `stored_objects` migration for staged bodies), FU-66
(:464's `malware_or_active_content_detected` check is not performed — there is no scanning provider and
adding one is an owner decision), and FU-67 (accepted WF-005 events omit `prior_aggregate_version` /
`committed_aggregate_version`, which API_CONTRACTS.md :938 lists as base members of every `created` and
`state_transition` payload; the S-07-010 events carry them and the earlier ones do not).

Authority And Precedence:
Standing delegation ADR-061 and development cadence ADR-086. No architectural stop condition was met:
no frozen foundation changed (F-02 and F-03 are consumed through their public contracts), no accepted
proof was invalidated, and no product semantics had two materially different valid readings — D3's two
readings were resolved by :452's own text rather than by preference. Allocated the next unused number
after ADR-142.

## ADR-144: S-07-010 Adversarial Round 1 — Three Findings, All Repaired; The Tranche Still Cannot Be Accepted, And The Reason Is ADR-026

Status: Accepted (the three repairs); the S-07-010 tranche remains NOT accepted
Date: 2026-08-07
Owner: implementation agent (adversarial round conducted in-session; the independence limitation is recorded rather than worked around)
Reversibility: One trigger migration, six proofs and six mutation definitions. No frozen foundation changed.

Decision:

Record an adversarial round over candidate `780b1a4..8f55c9e`, its three findings and their repairs,
and the reason the round does not discharge ADR-061's acceptance condition.

**R1-1 — the durable handoff could cross a Project boundary. Acceptance-blocking. Repaired.**
`ingestion_jobs.evidence_id` carried a two-column foreign key, so a job in Project A could name
Evidence belonging to Project B of the same Organization. This was MEASURED rather than inferred: the
round drove the UPDATE live and the database accepted it. POSTGRESQL_SCHEMA.md :128 requires all three
of `(organization_id, project_id, id)` "rather than a separate Project lookup or application
assertion", and this is FU-7's class for the FOURTH time. It is blocking rather than cosmetic because
MTX-008 makes the column THE durable handoff, :472 makes the parse manifest read it, and :472 classes
a cross-boundary manifest reference as `input_manifest_invalid`. Repaired by
`f1_ingestion_job_evidence_contained`, which matches organization, project AND source and fails closed
on an unreadable row. NOT by the three-column key: that needs a UNIQUE on `evidence`, F-03's table, and
AUTONOMY_POLICY makes a frozen-foundation change an owner decision that ADR-029's additive exception
does not cover. FU-68 carries the structural form.

The repository's own guard then caught the repair: the first version compared Sources with
`IS NOT DISTINCT FROM`, which `repository_truth_spec` refuses anywhere in an authoritative record
(ADR-111, ADR-115). The replacement is better rather than merely permitted, because
`e.source_id IS NOT NULL AND e.source_id = NEW.source_id` states that non-Source-scoped Evidence is a
REFUSAL, where plain `=` would yield NULL and be misreported as an unreadable row.

**R1-2 — four of :464's eight first-match refusals were unproved, and the ORDER was unproved at all.
Acceptance-blocking. Repaired.** Only `staged_body_missing` and `fetched_body_digest_mismatch` were
asserted anywhere in `spec/`. :464 calls the eight "first-match", which makes the order normative, and
ADR-072 records exactly this class as a confirmed-blocking finding at S-03 ("the MTX-027 first-match
order inverted ... the order is normatively fixed"). PROOFs 175a-175f now cover the four missing
refusals and both order properties. `malware_or_active_content_detected` is deliberately given NO
test: it does not run, FU-66 says so, and a test asserting otherwise would be the false record the
suite exists to prevent.

**R1-3 — FU-65 asserted something false about the implementation. Governance truth. Corrected.**
It claimed "both destruction points are proved". :464's success-path destruction is implemented and
proved; :466's "then destroys them" at the 24-hour bound has NO EXECUTOR, so a dead-lettered job's
staged ciphertext is retained indefinitely. Corrected in place and carried as FU-69 with its owner
named from MTX-008 retention, rather than absorbed by a sentence in another follow-up. What S-07-010
owns, the refusal at the bound, fails closed and is proved.

Why the tranche is still NOT accepted:

ADR-026's binding operational rule is that autonomous product work requires "a real INDEPENDENT
reviewer — a separate provider or a separately invoked model with NO SHARED CONVERSATIONAL STATE".
This round was conducted by the implementer, in the implementer's own session, with full knowledge of
every decision under review. It is a genuine adversarial round and it found three real defects,
including one measured live against the database; it is not the reviewer ADR-026 requires, and
recording it as one would be precisely the false claim about the repository that
`spec/architecture/repository_truth_spec.rb` exists to catch. ADR-080 is the standing precedent: a
tranche accepted on an incomplete review was recorded as a mandatory-gate failure rather than a
judgement call, and the same reasoning applies with more force to a review that is complete but not
independent.

`S-07-010_ACCEPTANCE_REVIEW.md` is therefore NOT created, `completed_blocks` does not gain S-07-010,
`review_commit` stays empty and `status` stays `reviewing`. What the round leaves behind is a stronger
candidate and a shorter list for whoever reviews it.

Verification from the repaired state: rspec 2584/0; brakeman 0 warnings; packwerk, zeitwerk and
bundler-audit clean; `bin/f1db f1:db:verify_runtime` 15 checks with RLS intact; architecture 245/0; no
structure drift; `bin/f1-db-bootstrap-gate` 9/9; mutation ledger 28 definitions, 28 killed, 0 survived,
0 broken.

Authority And Precedence:
Repairs under standing delegation ADR-061 and blocking-defect repair authority ADR-084; the
non-acceptance under ADR-026's independent-reviewer rule and ADR-080's precedent. Opens FU-68 and
FU-69 and corrects FU-65. Allocated the next unused number after ADR-143.

---

## ADR-145: FU-13, FU-40 And FU-50 — The Catalogue Names The Table The Database Has, A Failed Review Becomes A Record, And A Protected Write's Organization Comes From The Session

Status: Accepted
Date: 2026-08-10
Owner: implementation agent under the owner's three decisions of 2026-08-10 (FU-13 "correct the
catalogue to `evidence`, the database wins"; FU-40 "a minimal `failed_attempts` record shape and the
real failures backfilled"; FU-50 "bind `authority.organization_id` at all three protected writes")
Reversibility: One catalogue row, one controller field shape, one authority predicate and its
refusal. No frozen foundation changed. No migration. No contract change.

Decision:

Take the three small, already-decided follow-ups that were clearing the record before S-07-011, and
record what measuring them changed about the record itself.

**FU-13 — THE CATALOGUE NAMED A TABLE THAT DOES NOT EXIST, AND THE DATABASE WINS.**
`schemas/POSTGRESQL_SCHEMA.md :337` catalogued the Evidence table as `evidences`. No table has ever
carried that name: the live table is `evidence`, which is what `wf007_evaluation_spec.rb` joins and
what `runtime_grants.rb` grants on. So the real table appeared under no name and the catalogue named
one that does not exist. The two available repairs — rename the live table, or rename the catalogue
row — are opposite answers to the same question, WHICH NAME IS RATIFIED, and that is why the record
had been left open for an owner. The owner ruled that the database wins. The catalogue row now reads
`evidence`, and `evidence` has left the exempt list in `repository_truth_spec`'s "represents every
application table" check, so the catalogue is held to the name rather than excused from it. MEASURED:
restoring `evidences` fails that example naming `evidence` exactly. The plural forms elsewhere in the
catalogue — `check_result_evidences`, `issue_evidences`, `recommendation_evidences` and the rest —
are DIFFERENT TABLES and are untouched, and API_CONTRACTS.md's `/evidences/:id/validation-decisions`
is an HTTP path in a frozen contract, not a table name, and is untouched too.

**FU-40 — `failed_attempts` HAS A SHAPE, A WRITER AND THE REAL HISTORY; AND THE NUMBER IN THE RECORD
WAS WRONG.** The field was REQUIRED, VALIDATED AS AN ARRAY and given a dedicated
`append_failed_attempt`, and it accepted any hash at all, so its only caller in the repository was
its own unit spec. `BuildState::FAILED_ATTEMPT_KEYS` now names the seven members a reader needs to
re-derive a failure — attempt, tranche, candidate_range, outcome, mechanism, blocking_findings,
record — with a closed `outcome` enumeration and a pinned-range check that refuses `..HEAD`.
Validation runs on LOAD as well as on APPEND, so a row that arrived by a hand edit is checked like
any other.

FU-40's own note said six failures. THAT NUMBER IS STALE AND WAS NOT COPIED. `S-07-009_ACCEPTANCE_REVIEW.md`
carries FOURTEEN round headings and every one of them records `VERDICT: FAIL … NOT ACCEPTED`. The
backfill is those fourteen, each with the candidate range its own section pins and the
blocking-finding count its own verdict states. Two further checks in `repository_truth_spec` DERIVE
that set from the review records rather than restating it, so a fifteenth failed round that is not
recorded fails the gate instead of waiting for a reviewer, and they walk every `*_ACCEPTANCE_REVIEW.md`
rather than `current_tranche`'s alone — the tranche under review is precisely the one with no review
record yet. NOT RECONCILED HERE: ADR-142's prose says S-07-009 "returned NOT ACCEPTED eighteen
recorded five-lens rounds running". The review record's headings are 1..14 and the later rounds it
discusses in prose are numbered on a different scheme. Fourteen is what the repository holds as
per-round evidence and is therefore what is recorded; the eighteen is left standing in ADR-142 and
named here rather than silently overwritten.

**A LATENT CONTROLLER DEFECT WAS FOUND BY WRITING THE FIRST PROOF, AND REPAIRED.** `do_review` wrote
its result to `review.json`, a fixed name, and run records are APPEND-ONLY. So the SECOND review in a
run — the only kind that can exist after a review returns `changes_required` — raised "run-record
artifact already exists" out of `run_tranche`, which rescues `Stop`, `PolicyViolation` and
`SchemaError` and not that. THE REVIEW-FAILURE LOOP-BACK HAD THEREFORE NEVER ONCE COMPLETED, which is
the deeper reason the field stayed empty: there was no writer AND no reachable path to one. Measured,
not inferred — the first FU-40 example written against that path failed exactly there. The artifact
is now numbered by repair cycle, as `verification_repair_n.json` and `repair_n.json` already were.
`append_failed_attempt` is called from that branch, and a state-write failure records a
`failed_attempt_not_recorded` event rather than vanishing.

**FU-50 — ALL THREE PROTECTED WRITES BIND THE AUTHENTICATED AUTHORITY'S ORGANIZATION, AND THE
DIVERGENCE IS REFUSED RATHER THAN RESOLVED IN SILENCE.** `CrawlStartStore#cancel` bound
`authority.organization_id`; `CrawlStore#insert_crawl` and `CrawlPolicyStore#activate_version` bound
`row[:organization_id]`. Re-traced at every call site, those are THE SAME VALUE today — `QueueCrawl#commit`
and `ActivateCrawlPolicy` both set `org = actor.organization_id` and build their authority from the
same actor — so what was unproved was never that the writes disagreed. It was that NOTHING ENFORCED
their agreement, and round 20 had measured `ra.organization_id` as bound by nothing across the whole
suite. Both authority limbs at both row-bound writes now take a parameter carrying
`authority.organization_id`; the row's organization remains the value INSERTED and the scope the
supersession selects, which is what it is for.

THE REBINDING ALONE WOULD HAVE MOVED THE HAZARD RATHER THAN REMOVED IT, and that is why this record
also carries a refusal the owner's sentence did not name. After the rebinding, a caller passing a
foreign row organization would have had the authority limbs answer about the AUTHENTICATED
Organization while the row still carried another one, leaving `crawls_context` /
`crawl_policies_context` to refuse the write — an RLS error from the database instead of a broken
contract at the store, and a control held only by a policy this layer does not own.
`WriteAuthority#governs!` therefore refuses the divergence before the statement, raising
`Platform::InvariantViolation` — reachable only from an implementation defect, never from a caller's
legitimate input — and naming both organizations. Nothing reachable today changes: no production
caller can produce a divergence, which is why this is behaviour-preserving and why it needed proving
rather than assuming.

WHAT PROVES WHICH HALF, STATED EXACTLY, BECAUSE THEY CANNOT BOTH BE PROVED THE SAME WAY. A
behavioural proof of the BINDING needs the two values to differ at the write, and the refusal makes
that unreachable. So the refusal is proved by execution against a real second Organization
bootstrapped through the real WF-001 chain (`spec/acceptance/wf005_write_authority_organization_spec.rb`,
five examples, two of them non-vacuity controls that must still commit), and the binding is proved by
`spec/architecture/capability_cte_equivalence_spec.rb`, which resolves the placeholder each store
puts in its two organization slots back through the store's own parameter list and requires
`authority.organization_id`. That closes the half round 19 recorded as R19-ARCH-3: the existing
equivalence gate normalises every `$n` to `$?` and structurally cannot see an operand.

Evidence:

rspec MEASURED BEFORE AND AFTER, serially, with no dev worker running: 2981 examples / 0 failures /
1 pending at the branch head before this work; 2997 / 0 / 1 after. Architecture 267/0 before,
271/0 after. Every behaviour change was reverted individually and its proof required to fail:
restoring `evidences` fails "represents every application table" naming `evidence`; emptying
`failed_attempts` fails the derivation against the review records; deleting the queue write's
`governs!` fails exactly one acceptance example; deleting the policy write's fails exactly two;
rebinding the queue write's capability CTE to `$4` fails the operand gate naming
`IdentityAccess::Infrastructure::CrawlStore#insert_crawl` and the expression `row[:organization_id]`.
brakeman 0; packwerk clean with no stale violations; zeitwerk clean; `bin/f1db f1:db:verify_runtime`
15 checks with RLS intact; no structure drift.

BUNDLER-AUDIT WAS NOT CLEAN WHEN THIS WORK STARTED, FOR A REASON THAT HAS NOTHING TO DO WITH IT.
`bundle-audit check --update` pulled advisory database commit `60a4518` (2026-08-09) and reported
CVE-2026-71847 / GHSA-9hj4-r449-hfvc against `json 2.21.1`: `JSON::ResumableParser#partial_value`
dereferences a freed input buffer on a truncated duplicate-key stream. The advisory is newer than the
figure the handover recorded, so the gate went red without a line of this repository changing.
`bundle update json --conservative` moved the lockfile to `json 2.21.2`, one transitive patch release
and no other gem, and the suite was re-measured from that state. It is recorded here rather than in a
tranche record because it is a dependency fact, not a design decision, and none of AUTONOMY_POLICY's
nineteen escalation triggers covers a patch-level security fix to an existing free gem — it
strengthens the property trigger 5 protects.

ZERO calls were made to OpenAI, Anthropic, Google or any model provider. No adapter was added, no
API key was read, and no dormant-adapter guard was touched.

Consequences:

FU-13, FU-40 and FU-50 are resolved. `failed_attempts` is now a governed field: a review that returns
NOT ACCEPTED lands in it, and the gate refuses a state file whose failures disagree with the review
records. The mutation ledger for the tranche under review (S-07-010) binds none of the files changed
here, so no ledger row went stale and none was re-sealed. S-07-010 remains `reviewing` and is NOT
accepted by this record.

Authority And Precedence:
The three repairs under the owner's decisions of 2026-08-10 and standing delegation ADR-061. The
FU-50 refusal is the second of the two repairs FU-50's own note enumerates, taken alongside the
binding the owner named because the binding alone relocates the hazard onto RLS. The controller
artifact-naming repair under blocking-defect repair authority ADR-084: it is the reason the decided
FU-40 writer could not otherwise execute. Corrects FU-40's "six" to the fourteen the review record
holds. Allocated the next unused number after ADR-144.

---

## ADR-146: FU-33 And FU-67 — The Crawl Events Carry Exactly Their Closed Profile, The Two CAP-007 Counts Are Re-Homed, And The Envelope Is A Bigger Question Than Either Record Knew

Status: Accepted
Date: 2026-08-10
Owner: implementation agent under the owner's decision of 2026-08-10: "FU-33 and FU-67 conform to the
closed event profile. The two CAP-007 observability members are re-homed, not deleted. Record an ADR."
Reversibility: Five event payload literals and one shared envelope builder. No frozen contract, no
migration, no schema change. The canonical bytes of five WF-005 event types change.

Decision:

**THE FIVE WF-005 CRAWL-AGGREGATE EVENTS NOW CARRY EXACTLY THEIR PROFILE.** API_CONTRACTS.md :933 is
unambiguous — a selected profile has "the exact base members below, followed by exactly the members in
its catalogue-selected extra schema", and "there is no free-form `details`, `metadata`, `attributes` or
extension object". `CrawlQueued` carried seven members and NOT ONE of them belonged to its profile;
`CrawlStarted` carried eight of which six did not; the `CompleteCrawl` terminal envelope and
`CrawlCanceled` were missing both aggregate-version base members and carrying `crawl_id`, which
duplicates the root `affected_entity_id`; `StartCrawl`'s pre-execution `CrawlFailed` was missing five.
All five now emit the base members of their profile plus `crawl_terminal`'s three, with the
contract's own null/zero values before terminal derivation.

**TWO PRODUCERS OF ONE EVENT TYPE WERE BROUGHT INTO AGREEMENT, WHICH NEITHER RECORD ASKED FOR AND BOTH
IMPLY.** `CrawlFailed` is emitted by `CompleteCrawl` AND by `StartCrawl`, and the two disagreed about
its members. That is ADR-110's own defect class one event type along, and repairing one producer while
leaving the other would have recreated it. `CrawlCanceled` is included for the same reason: it is the
same profile, the same aggregate and the same extra schema, and a corpus that conforms in four events
out of five is the incoherence FU-33 said should not be carried.

**THE TWO CAP-007 COUNTS ARE RE-HOMED, NOT DELETED, AND THAT IS ASSERTED RATHER THAN CLAIMED.**
`frontier_root_count` and `excluded_inactive_source_count` were added to `CrawlStarted` deliberately,
because CAP-007 observability requires them and because they "make a queue-time/execution-time
Source-set divergence visible". The closed profile has nowhere to put them. They remain in the AUDIT
RECORD the same commit writes — alongside `pinned_source_count`, which was never in the event — and in
the command result, and WORKFLOW_SPECIFICATIONS.md :740 puts "per-Source root status" in exactly that
obligation. One example drives the real chain and requires all three to be readable from the audit
payload AND absent from the event. The same is true of the five facts dropped from `CrawlQueued`:
`kind`, `source_count` and the two requested policy versions were already in that command's audit
record, and `crawl_id` is the aggregate id the event row carries in a column.

**THE GATE DERIVES ITS EXPECTATION FROM THE RATIFIED DOCUMENT AND ITS SUBJECT FROM THE EMITTED BYTES.**
`spec/acceptance/wf005_event_profile_conformance_spec.rb` parses the root member enumeration and both
"Closed profile payloads" tables out of API_CONTRACTS.md, drives the production chain, and compares
against `event_registry.event_bytes` — what a consumer actually receives and what `event_sha256` is
computed over, rather than a source literal the ledger could reshape. A member added to a profile in
the contract becomes required with no edit to the spec, which is the whole reason FU-33's
hand-maintained delta had to be re-measured in two consecutive tranches. The parse is asserted before
anything depends on it, because a format change that emptied it would make every comparison pass
vacuously.

**WHAT TAKING THIS MEASURED, WHICH NEITHER RECORD KNEW, AND WHICH IS OPENED AS FU-74 RATHER THAN
ABSORBED.** API_CONTRACTS.md :703 makes `event_payload: object<EventProfilePayload>` a NESTED member of
the event root. NO EMITTER IN THIS REPOSITORY NESTS IT — not one of the twenty-odd envelope builders
across WF-001 to WF-013 — so `event_payload` appears in no emitted byte sequence at all. Every envelope
instead flattens its profile members into the root and adds root members :703 does not admit
(`account_id`, `requester_account_id`, `organization_epoch`, `state_version`, and `scheduled_action_id`
in the S-07-010 builders) while omitting `related_entities`, `governing_versions` and `output_hash`.
THIS CORRECTS FU-33's CONTROL: "the S-07-010 events were re-read as the control and they conform
exactly" is true of profile members and false of the envelope. It is not repaired here, and the reason
is not caution: it is identical in every workflow, it is a question about the contract rather than
about WF-005, and repairing it would change the canonical bytes and `event_sha256` of every event this
platform has ever emitted. `ENVELOPE_SURPLUS` in the gate names exactly the five surplus members that
exist today, so a sixth fails rather than accumulating quietly, and FU-74 carries the decision.

Evidence:

rspec measured serially before and after with no dev worker running. Every behaviour change was
reverted individually and its proof required to fail, naming the event and the member: re-adding
`kind` to `CrawlQueued` fails with "carries kind, which is neither a root member nor a member of its
closed profile"; deleting `accepted_document_count` from `CrawlStarted` fails with "omits
accepted_document_count"; replacing the terminal envelope's two version members with `crawl_id` fails
naming both omissions. brakeman 0; packwerk clean with no stale violations; zeitwerk clean;
bundler-audit clean at json 2.21.2; `bin/f1db f1:db:verify_runtime` 15 checks with RLS intact; no
structure drift.

NOT CLAIMED. This does not assert that the WF-005 events conform to :703's ROOT object — they do not,
and neither does any other event in the platform; FU-74 states the delta exactly. It does not touch
`EvaluationPending` or `CrawlPolicyActivated`, which are different aggregates on different profiles and
are named by neither record; `CrawlPolicyActivated` in particular is wholesale non-conformant against
the `policy_activation` profile and is recorded in FU-74's scope rather than repaired in passing.

ZERO calls were made to OpenAI, Anthropic, Google or any model provider.

Consequences:

FU-33 and FU-67 are resolved. FU-74 is opened. The canonical bytes of `CrawlQueued`, `CrawlStarted`,
`CrawlCanceled`, `CrawlCompleted` and `CrawlFailed` change, which is an owner-visible envelope
correction to accepted tranches and is why this record exists. S-07-010 remains `reviewing` and is NOT
accepted by this record.

Authority And Precedence:
The conformance under the owner's decision of 2026-08-10 and standing delegation ADR-061. The
inclusion of `CrawlCanceled` and `StartCrawl`'s `CrawlFailed` under ADR-110's precedent that two
producers of one event type may not disagree about its shape. FU-74 opened under the AUTONOMY_POLICY
rule that a contract question with more than one materially valid reading is the owner's. Allocated
the next unused number after ADR-145.

---

## ADR-147: FU-58, FU-53 And FU-57 — The Write Carries The Whole Baseline, Writes Only Inside Its Tenant, And Is Measured At Every Instance Rather Than One

Status: Accepted
Date: 2026-08-10
Owner: implementation agent under standing delegation ADR-061
Reversibility: One authority member, one conjunct repeated at three writes, one predicate on one
UPDATE. No frozen contract, no migration, no schema change, no ratified document edited.

Decision:

Three records describe three residues on the SAME three protected writes, and the two instruments they
each needed — FU-61's repository-derived `WRITES` registry and FU-50's operand gate — were built in
the two preceding tranches. They are taken together.

**FU-58 — THE STATEMENT CARRIED THE BASELINE MINUS ITS PROTECTED LIMB, AND NOW CARRIES ALL OF IT.**
`CommandAuthorizer#confers?` is four limbs: the baseline cell, the mode cell, and then — for a
capability in `PROTECTED` — the Assignment's bootstrap-admin exception or its approved
`protected_permission_allowlist`. `return true unless PROTECTED.key?(capability)` is a property of the
Ruby evaluator with no analogue in SQL, so three stores said "this is the baseline CARRIED" while
carrying two limbs of four. `WriteAuthority` now derives a `protected_capability` boolean once — the
same shape `read_only_permitted` already has for the sixth column — and all three capability CTEs bind
`AND (NOT $n::boolean OR ra.bootstrap_admin_exception OR ra.protected_permission_allowlist @>
to_jsonb($m::text))`, which is that limb exactly. What the statement re-reads is still only row state
another transaction can move.

THE OPTION THE RECORD PREFERRED WAS NOT TAKEN, AND THE REASON IS EVIDENCE. FU-58 proposed refusing at
the builder — `WriteAuthority.for` raising for a `PROTECTED` capability — as "smaller and fails
closed". It is smaller. It also leaves the SQL unable to answer the question, so the next protected
write inherits the same gap, and it makes the defect UNPROVABLE BY EXECUTION: nothing could then drive
the statement with a protected capability to show that it refuses.

**FU-58's OWN MEASUREMENT WAS STALE AND IS CORRECTED.** The record reads "Ruby `authorize` DENIES
(`missing_authority`, granting=0)". Driven today, `authorize` ALLOWS, because it aggregates over EVERY
effective Assignment and the WF-001 bootstrap grant carries `bootstrap_admin_exception`, which
`confers?` accepts. THE DIVERGENCE IS PER GRANT, NOT PER ACTOR — which is the level the write works
at, since it re-reads the grants the decision relied on. Proved that way: an ordinary OrganizationAdmin
Assignment with an empty allowlist and no exception, for which `PermissionBaseline.protected_grant?`
is false, was authorized by the write and cancelled a running Crawl.

THREE EXAMPLES, BECAUSE ONE WOULD HAVE BEEN SATISFIED BY A BLANKET DENIAL. The refusal; the ADMISSION
once :314's approved allowlist carries the capability, seeded through the only transition
`f1_role_assignments_lifecycle_guard` permits (`pending -> active`, which refused a first draft that
edited an active row — the guard working); and a non-protected capability still admitted, without
which a limb keyed on an empty allowlist would break every production cancellation. The exposed
surface is DERIVED, not transcribed: `CAPABILITIES ∩ PROTECTED` is required to be exactly
`role.manage` and `invitation.approve`, and every other `PROTECTED` key is required to raise `KeyError`
from `CAPABILITIES.fetch`.

**FU-53 — `cancel` JUDGED AUTHORITY AGAINST THE SESSION AND WROTE AGAINST AN UNQUALIFIED ID.** Both
authority limbs bound `authority.organization_id` and the `UPDATE crawls` named only `id`, `state` and
`state_version`, so the statement asked "may this actor cancel in THEIR Organization" and then
cancelled whatever row carried that id. It now carries `AND organization_id = $5::uuid`, bound to the
AUTHORITY's organization — the same answer ADR-145 settled at the other two writes.

**HALF OF FU-53 WAS ALREADY CLOSED WHEN IT WAS READ, AND THE OTHER HALF IS NOT WHAT FU-50 REPAIRED.**
The mirror it records at `crawl_store#insert_crawl` was closed by ADR-145. What remained is the half
it names first, and `governs!` does not reach it: `cancel` takes an id rather than a row, so there is
no caller-supplied organization to refuse — the containment had to be on the target instead.

PROVED THE WAY THE RECORD'S OWN MEASUREMENT COULD NOT BE. Round 19 drove this through a real session
and concluded "only RLS stopped the write", which is an observation about the database's policy rather
than about the statement — and a policy is not the store's contract. `DbInspector`'s connection is a
BYPASSRLS superuser, which the harness already relies on for cross-principal reads. Driven on it
against the pre-change code, an attacker with entirely valid authority in their own Organization
CANCELLED a victim Organization's running Crawl: `epoch_authorized: true, capability_authorized: true,
moved: 1`, and `f1_crawls_guard` makes that terminal state unrecoverable. With the predicate, `moved:
0` and the Crawl stays running, while the legitimate same-Organization cancellation on the same
connection still applies.

**FU-57 — PROOF 264's MEASUREMENT NOW RUNS AT EVERY WRITE INSTEAD OF ONE.** The global lock order is
`organizations` before `role_assignments`, and the WF-013 half is derived from the WF-005 half holding
— which was measured at `QueueCrawl` alone. The measurement now runs against every DISTINCT write in
`ProtectedWrites.covered`, the registry FU-61's completeness gate proves against the repository, so a
fourth protected write is measured the day it is registered rather than inheriting this proof.
PROOF 264's advisory-lock scaffolding is gone: it existed to get the HANDLER blocked at a known point,
and driving the STORE directly needs none. The order HOLDS at all three, including
`CrawlPolicyStore#activate_version`, whose two `EXISTS` sit in one CTE where `order_qual_clauses` sorts
by estimated cost — which is worth more now than when the record was written, because FU-58 has just
added a conjunct to that CTE and the record predicted exactly that kind of change would move the
estimate.

**TWO OF THIS TRANCHE'S OWN PROOFS WERE WRONG FIRST, AND BOTH FAILURES ARE RECORDED RATHER THAN
QUIETLY FIXED.** The lock-order measurement first held "the Organization's first active grant" and
timed out inside the full acceptance run while passing alone: the capability CTE joins `unnest(...)`
against `role_assignments`, so holding a row the carried grant set does not name blocks NOTHING and
the write runs straight through. It now holds `authority.grant_ids.first` and asserts the set is
non-empty, so an unblocked statement fails as an unblocked statement. And `LOCK_TIMEOUT` was declared
at describe level, where a constant lands on `Object`; `spec_constant_scope_spec` failed on the
collision with `wf005_authority_lock_concurrency_spec.rb` the moment the file was added, which is that
gate doing exactly what FU-42 built it for.

Evidence:

rspec measured serially with no dev worker running: 3003 / 0 / 1 pending before, 3013 / 0 / 1 after.
Architecture 271/0 before and after — no architecture example was added. Each repair reverted
individually and its proof required to fail on its own assertion: removing `cancel`'s organization
predicate fails exactly one example with `moved: 1` against a foreign Organization; removing the
protected limb fails exactly one, and it was re-measured AGAINST THE TRUE PRE-CHANGE CODE — conjunct
AND both parameters together, because dropping the conjunct alone makes PostgreSQL reject the bind and
produces a crash rather than a failed expectation, which is weaker evidence. brakeman 0; packwerk
clean with no stale violations; zeitwerk clean; bundler-audit clean; `bin/f1db f1:db:verify_runtime`
15 checks with RLS intact; no structure drift.

NOT CLAIMED, AND NAMED RATHER THAN LEFT IMPLICIT. FU-57's measurement is a gate against a future
reordering; it does not prove the planner cannot reorder. The FU-58 limb is bound at the three writes
that exist — a fourth inherits the conjunct through the equivalence gate's multiset comparison, not
through anything that makes it impossible to omit. `wf013_organization_lifecycle_concurrency_spec.rb`
was seen failing once in an acceptance-only run with `stale_authorization_epoch` where it expects
`session_invalid` or `organization_inactive`; it passed three consecutive isolated runs and both full
suite runs with these changes present, so it is recorded as an observed flake and NOT as a repair
this tranche made or a defect it introduced.

ZERO calls were made to OpenAI, Anthropic, Google or any model provider.

Consequences:

FU-53, FU-57 and FU-58 are resolved, and with FU-49 and FU-50 that closes every residue on the
protected writes except FU-2 — Assignment-scope containment — which is platform-wide and remains the
owner's. S-07-010 remains `reviewing` and is NOT accepted by this record.

Authority And Precedence:
Repairs under standing delegation ADR-061. The FU-58 limb follows ADR-132's rule that the baseline is
read ONCE in Ruby and carried as a value rather than re-derived in SQL. Corrects FU-58's per-actor
measurement to a per-grant one and FU-53's already-closed mirror half. Allocated the next unused
number after ADR-146.
