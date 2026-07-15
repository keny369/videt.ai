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
Documents `specification/000` through `specification/010` are established as the immutable foundation layer of the Product Architecture Manual.

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
