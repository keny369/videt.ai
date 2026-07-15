# Product Architecture Manual

## Purpose

Define the complete architecture of Project F1 across business, product, UX, platform, data, AI, API, engineering, operations, finance, security and infrastructure.

## Canonical Read Order

1. Constitution and governance
2. Immutable foundation documents 000 to 010
3. Volume I through Volume V
4. Derived design and implementation artifacts

## Canonical Rules

- This index is the navigation source of truth for the manual.
- Every chapter must cross-reference dependencies and upstream decisions.
- Any architecture change must update impacted earlier chapters and [DECISIONS.md](../DECISIONS.md).

## Foundation Layer (Immutable)

All subsequent specifications must reference these documents and must not redefine their concepts.

- [000 OVERVIEW.md](000 OVERVIEW.md): repository architecture orientation and authority hierarchy.
- [001 PRODUCT_ARCHITECTURE_MANUAL.md](001 PRODUCT_ARCHITECTURE_MANUAL.md): manual structure, lifecycle and quality gates.
- [002 GLOSSARY.md](002 GLOSSARY.md): canonical concept definitions.
- [003 TERMINOLOGY.md](003 TERMINOLOGY.md): naming and language conventions.
- [004 DESIGN_PRINCIPLES.md](004 DESIGN_PRINCIPLES.md): UX and interaction principles.
- [005 PRODUCT_PRINCIPLES.md](005 PRODUCT_PRINCIPLES.md): product strategy and prioritization principles.
- [006 ENGINEERING_PRINCIPLES.md](006 ENGINEERING_PRINCIPLES.md): engineering quality and delivery principles.
- [007 ARCHITECTURE_PRINCIPLES.md](007 ARCHITECTURE_PRINCIPLES.md): system design and boundary principles.
- [008 AI_PRINCIPLES.md](008 AI_PRINCIPLES.md): AI safety, quality and governance principles.
- [009 DECISION_FRAMEWORK.md](009 DECISION_FRAMEWORK.md): decision process and ADR threshold.
- [010 DOCUMENT_STANDARDS.md](010 DOCUMENT_STANDARDS.md): authoring and consistency standards.

## Domain Coverage Map

- Business and market: Volume I
- Product and UX: Volumes I and II
- Platform architecture and infrastructure: Volumes III and V
- Database and AI: Volume IV
- APIs and integrations: Volume IV
- Engineering and implementation: Volume V
- Operations and security: Volume V
- Finance and commercial operations: Volume V

## Volume Layer

### Volume I - Strategic Foundations (In Progress)

Document:

- [VOLUME_I_FOUNDATIONS.md](VOLUME_I_FOUNDATIONS.md)

Scope:

- mission, market architecture, business model and pricing
- product operating model and core workflows
- Discoverability Score architecture at conceptual level
- foundational terminology and non-goals

Status:

- Active
- Must comply with foundation references 000 to 010

### Volume II - Product And UX Architecture (Planned)

Scope:

- information architecture and user roles
- journey maps, task flows and interaction contracts
- reporting UX and accessibility requirements

Status:

- Not started
- Blocked until Volume I is accepted

### Volume III - Platform Architecture (Planned)

Scope:

- bounded contexts and domain boundaries
- service topology, asynchronous workflows and reliability model
- environment and deployment architecture

Status:

- Not started

### Volume IV - Data, AI And API Architecture (Planned)

Scope:

- relational and analytical schema design
- scoring model implementation architecture
- AI orchestration, prompts, evaluation and safety
- API contracts, versioning and integration model

Status:

- Not started

### Volume V - Engineering, Security, Operations And Finance (Planned)

Scope:

- engineering standards and implementation governance
- security controls, privacy model and threat boundaries
- operational runbooks, observability and SLO strategy
- financial model architecture and planning controls

Status:

- Not started

## Compliance Requirements For All Future Chapters

Every new or updated chapter must:

1. reference relevant foundation documents by link
2. avoid redefining glossary terms or principle sets
3. use terminology from [003 TERMINOLOGY.md](003 TERMINOLOGY.md)
4. trigger ADR updates when decision thresholds in [009 DECISION_FRAMEWORK.md](009 DECISION_FRAMEWORK.md) are met

## Dependencies

- Constitution: [../CLAUDE.md](../CLAUDE.md)
- Governance: [../governance/PROJECT_CONSTITUTION.md](../governance/PROJECT_CONSTITUTION.md)
- Quality bar: [../governance/QUALITY_STANDARD.md](../governance/QUALITY_STANDARD.md)
- Workflow: [../governance/WORKFLOW.md](../governance/WORKFLOW.md)
- ADR registry: [../DECISIONS.md](../DECISIONS.md)
- Initial research baseline: [../research/000-initial-concept.md](../research/000-initial-concept.md)
- Roadmap sequencing: [../ROADMAP.md](../ROADMAP.md)
- Current progress: [../PROJECT_STATE.md](../PROJECT_STATE.md)
