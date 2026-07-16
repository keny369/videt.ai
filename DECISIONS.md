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
