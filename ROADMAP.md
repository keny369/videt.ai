# Roadmap

## Objective

Deliver a complete Product Architecture Manual before implementation with constitutional dependency sequencing.

Pre-launch scope selection through the S-09 launch boundary is prioritised against
[governance/CUSTOMER_VALUE_CONSTITUTION.md](governance/CUSTOMER_VALUE_CONSTITUTION.md),
the product-value-prioritisation authority. It guides what customer value is built
and in what order; it does not override frozen technical, security, workflow or
governance contracts, nor authorise implementation.

## Baseline Date

2026-07-15

## Execution Gates

- Gate A: Foundation layer 000 through 020 MUST be accepted at version 1.0 before any downstream domain specification work proceeds.
- Gate B: The current accepted Volume I baseline, including any validated controlled correction, MUST be committed and tagged before Volume II technical design starts or resumes. Passed by `v1.3-volume-i-corrected`.
- Gate C: Volume II technical design may proceed from Gate B. Broad implementation additionally requires that no upstream Volume I blocker remains implementation-blocking for the work in question, an accepted Volume II baseline with zero critical/high implementation-disagreement risks, and approved slices. This gate is measured by implementation-blocking status, not by a count of blockers. A blocker ceases to be implementation-blocking when its governing Owner Decision is ratified and integrated into its canonical owner, or when that decision removes the governed behaviour entirely; a retired blocker requires no further correction. A slice whose command, read and event dependencies do not intersect a live blocker is not gated by that blocker. Two blockers recorded by Pass 001 remain live and implementation-blocking: `UPSTREAM-V1-PROJECT-LIFECYCLE-003`, governed by OD-014, and `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009`, governed by OD-023. Both Owner Decisions remain pending under their deterministic neutral interims, and this gate MUST NOT be read as resolving either.
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

- Status: Corrected and frozen at `v1.3-volume-i-corrected`; `v1.2-volume-i-frozen` retained as immutable history
- Deliverables:
  - canonical Volume I specification set under specification/volume-i
  - implementation-ready capability, workflow, rule, score-evidence, acceptance, and traceability definitions
  - owner decision register for unresolved policy and threshold choices
  - foundation 1.0 dependency compliance verification
  - accepted behavioural baseline changed only for demonstrated defects or approved owner decisions through controlled change

### M5 Experience and Interaction

- Status: Pass 001 complete for unblocked behavior; acceptance blocked by the frozen Volume I blockers recorded in the Volume II index
- Start Condition: Passed from `v1.3-volume-i-corrected`

### M6 Domain and State Deepening

- Status: Pass 001 complete for unblocked behavior; upstream-blocked operations withheld
- Start Condition: Passed within the integrated Volume II architecture pass

### M7 Data and Persistence

- Status: Pass 001 complete except blocked event/audit scope representation
- Start Condition: Passed within the integrated Volume II architecture pass

### M8 Search and Retrieval

- Status: Pass 001 complete
- Start Condition: Passed within the integrated Volume II architecture pass

### M9 AI and Evaluation

- Status: Pass 001 complete for deterministic and dormant-gated provider behavior
- Start Condition: Passed within the integrated Volume II architecture pass

### M10 API and Integration

- Status: Pass 001 complete for unblocked routes/integrations; blocked routes absent
- Start Condition: Passed within the integrated Volume II architecture pass

### M11 Implementation Planning

- Status: TDD sequencing complete; implementation gate blocked for any slice intersecting a live upstream Volume I blocker recorded in the Volume II index. `UPSTREAM-V1-PROJECT-LIFECYCLE-003` (OD-014) and `UPSTREAM-V1-CREDENTIAL-ROTATION-TOKEN-009` (OD-023) remain live; the remaining Pass 001 blockers are retired by ratified Owner Decisions integrated under ADR-019 and ADR-020
- Start Condition: Volume II acceptance, zero critical/high disagreement risk, and approved implementation slices

## Cross-Cutting Governance

- The Engineering Manual is ACCEPTED at `v1.7-engineering-manual-accepted` under ADR-022 and is the normative authority for engineering practice only. It holds no independent product-behaviour authority and MUST NOT be cited to settle a product-behaviour question.
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
