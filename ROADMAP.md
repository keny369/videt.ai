# Roadmap

## Objective

Deliver a complete Product Architecture Manual before implementation with constitutional dependency sequencing.

## Baseline Date

2026-07-15

## Execution Gates

- Gate A: Foundation layer 000 through 020 MUST be accepted at version 1.0 before any downstream domain specification work proceeds.
- Gate B: The current accepted Volume I baseline, including any validated controlled correction, MUST be committed and tagged before Volume II technical design starts or resumes.
- Gate C: Volume II technical design and implementation MUST remain paused until Gates A and B pass; implementation additionally requires approved Volume II slices.
- Gate D: Normative foundation changes MUST include ADR governance and impact mapping.

## Canonical Dependency Sequence

```text
000-020 Immutable Foundation
            |
            v
Volume I Product Foundations
            |
            v
Experience and Interaction
            |
            v
Domain and State
            |
            v
Data and Persistence
            |
            v
Search and Retrieval
            |
            v
AI and Evaluation
            |
            v
API and Integration
            |
            v
Implementation
```

## Milestones

### M0 Repository Normalization

- Status: Complete
- Deliverables: control docs baseline, ADR baseline, Volume I kickoff

### M1 Foundation 000-010

- Status: Complete
- Deliverables: initial immutable foundation layer

### M2 Foundation Extension 011-020

- Status: Complete
- Deliverables:
  - domain model, system boundaries, quality attributes
  - security model, data lifecycle, state model
  - error model, observability, versioning, extensibility
  - canonical diagrams and dependency graph
  - fitness-function governance, TDD policy, documentation-as-code policy

### M3 Foundation Governance Finalization

- Status: Complete
- Deliverables:
  - foundation baseline version declaration 1.0
  - traceability matrix
  - ADR set for dependency model and governance policies

### M4 Volume I Product Foundations

- Status: Frozen at `v1.2-volume-i-frozen`; ADR-017 controlled correction for DEF-V1-001 through DEF-V1-006 validated and pending commit plus successor frozen tag
- Deliverables:
  - canonical Volume I specification set under specification/volume-i
  - implementation-ready capability, workflow, rule, score-evidence, acceptance, and traceability definitions
  - owner decision register for unresolved policy and threshold choices
  - foundation 1.0 dependency compliance verification
  - accepted behavioural baseline changed only for demonstrated defects or approved owner decisions through controlled change

### M5 Experience and Interaction

- Status: Further Volume II expansion paused; the existing Rails architecture and PostgreSQL schema drafts are retained without new architecture documents
- Start Condition: ADR-017 corrected Volume I baseline committed and tagged

### M6 Domain and State Deepening

- Status: Paused
- Start Condition: M5 accepted

### M7 Data and Persistence

- Status: Paused
- Start Condition: M6 accepted

### M8 Search and Retrieval

- Status: Paused
- Start Condition: M7 accepted

### M9 AI and Evaluation

- Status: Paused
- Start Condition: M8 accepted

### M10 API and Integration

- Status: Paused
- Start Condition: M9 accepted

### M11 Implementation Planning

- Status: Paused
- Start Condition: M10 accepted and implementation gate approval

## Cross-Cutting Governance

- [DECISIONS.md](DECISIONS.md) MUST be updated for architecture-impacting changes.
- [PROJECT_STATE.md](PROJECT_STATE.md) MUST reflect gate and milestone status.
- [specification/FOUNDATION_TRACEABILITY_MATRIX.md](specification/FOUNDATION_TRACEABILITY_MATRIX.md) MUST remain current.
- [specification/INDEX.md](specification/INDEX.md) and [specification/001 PRODUCT_ARCHITECTURE_MANUAL.md](specification/001%20PRODUCT_ARCHITECTURE_MANUAL.md) MUST remain aligned.

## Done Definition For Manual Completion

Manual completion requires:

1. Full domain coverage across required architecture domains.
2. Sequenced dependency compliance across all layers.
3. Traceability from requirement through operational verification records.
4. Zero unresolved contradictions in accepted documents.
