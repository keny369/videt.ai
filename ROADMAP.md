# Roadmap

## Objective

Deliver a complete Product Architecture Manual before implementation, with one canonical specification path from strategy to execution.

## Planning Horizon

Baseline date: 2026-07-15

## Execution Gates

- Gate A: Foundation layer (000 to 010) must be completed before Product, UX, Database or API specifications begin.
- Gate B: Volume I must be accepted before Volume II starts.
- Gate C: Architecture-impacting changes must update [DECISIONS.md](DECISIONS.md).

## Milestones

### M0 - Repository Normalization (2026-07-15 to 2026-07-16)

Status: Complete

Deliverables:

- upgraded index, state and roadmap control documents
- initial ADR baseline in [DECISIONS.md](DECISIONS.md)
- Volume I kickoff draft

Exit criteria:

- all control documents cross-reference consistently
- no contradictions between constitution, workflow and manual index

### M1 - Immutable Foundation Layer (2026-07-15 to 2026-07-15)

Status: Complete

Deliverables:

- authored and accepted foundation documents 000 to 010 under `specification/`
- established canonical glossary, terminology, principles and decision framework
- enforced reference-first rule for all future chapters

Exit criteria:

- all foundation files exist and are cross-referenced in [specification/INDEX.md](specification/INDEX.md)
- [DECISIONS.md](DECISIONS.md) records the foundation baseline as architecture policy
- project state and roadmap reflect sequencing gates

### M2 - Volume I Strategic Foundations (2026-07-15 to 2026-07-22)

Status: Active

Deliverables:

- market definition, segment architecture and positioning
- business model, pricing architecture and value metric
- product operating model and Discoverability Score framework
- foundational glossary and non-goals

Exit criteria:

- each section includes rationale, acceptance criteria, risks and references
- terminology is stable across README, INDEX, ROADMAP and Volume I
- Volume I references foundation documents instead of redefining shared concepts

### M3 - Volume II Product And UX Architecture (2026-07-22 to 2026-08-05)

Status: Not started

Start condition: Volume I accepted

Deliverables:

- information architecture
- primary user journeys and task models
- interaction design system requirements and accessibility constraints
- reporting and dashboard behavior specification

Exit criteria:

- all core workflows are specification-complete and testable
- wireframe and UX requirements map to explicit product capabilities

### M4 - Volume III Platform Architecture (2026-08-05 to 2026-08-19)

Status: Not started

Deliverables:

- bounded context map and domain decomposition
- service architecture, background job model and event contracts
- environment strategy and deployment topology baseline

Exit criteria:

- architecture supports throughput, reliability and cost targets
- non-functional requirements are measurable

### M5 - Volume IV Data, AI And API Architecture (2026-08-19 to 2026-09-09)

Status: Not started

Deliverables:

- database architecture and schema governance
- scoring engine and AI orchestration architecture
- external and internal API contracts

Exit criteria:

- traceable mapping from product capabilities to data and API contracts
- AI safety and evaluation requirements are explicit

### M6 - Volume V Engineering, Security, Operations And Finance (2026-09-09 to 2026-09-30)

Status: Not started

Deliverables:

- engineering standards, test strategy and delivery workflow
- security architecture, privacy model and controls
- operational runbooks and SLO design
- financial model architecture and planning mechanics

Exit criteria:

- implementation can begin without unresolved architecture blockers
- every critical decision has rationale and owner

## Cross-Cutting Governance Track

Applies to every milestone:

- update [DECISIONS.md](DECISIONS.md) for architectural decisions
- keep [PROJECT_STATE.md](PROJECT_STATE.md) current after each major merge
- verify quality sections defined in [governance/QUALITY_STANDARD.md](governance/QUALITY_STANDARD.md)
- reject duplicate definitions; refactor to canonical source
- enforce foundation reference-first policy from `specification/000` through `specification/010`

## Done Definition For Manual Completion

The manual is complete only when:

1. All required domains are fully specified: business, market, product, UX, architecture, database, AI, APIs, engineering, operations, finance, security, infrastructure and implementation.
2. Every volume is internally consistent and cross-referenced.
3. ADR log captures all major trade-offs.
4. No section contains placeholders, unresolved contradictions or undefined terminology.
