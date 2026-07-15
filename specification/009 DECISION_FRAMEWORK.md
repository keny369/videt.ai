# 009 DECISION_FRAMEWORK

## Document Control

- Status: Accepted baseline
- Version: 1.0.0
- Last updated: 2026-07-15
- Owner: Chief Architect
- Classification: Canonical

## Purpose

Define a consistent framework for making, documenting and revisiting decisions across product, architecture, engineering and operations.

## Scope

Applies to:

- strategic decisions
- product scope and prioritization decisions
- architecture and integration decisions
- engineering process and tooling decisions
- policy and governance decisions

## Decision Types

### Strategic Decisions

Company-shaping decisions with long time horizon and high reversal cost.

### Product Decisions

Feature, packaging, UX and workflow decisions affecting customer outcomes.

### Architecture Decisions

Boundary, data, reliability, infrastructure and integration decisions with systemic impact.

### Operational Decisions

Runbook, SLO, incident, support and monitoring decisions.

## Decision Rights

- Chief Architect owns cross-domain architecture coherence.
- Domain owners make domain-local decisions consistent with foundations.
- Conflicts escalate to Chief Architect with documented trade-offs.

## Required Decision Process

1. Define the decision question and urgency.
2. Define constraints from foundation documents and accepted ADRs.
3. Generate at least two viable options.
4. Evaluate options using the weighted rubric.
5. Select option and record rationale.
6. Document consequences and follow-up actions.
7. Publish or update ADR if threshold is met.

## Weighted Evaluation Rubric

Use a 1 to 5 score per criterion.

| Criterion | Weight |
| --- | --- |
| Customer value impact | 0.25 |
| Correctness and reliability impact | 0.20 |
| Security and privacy impact | 0.15 |
| Implementation and operational complexity | 0.15 |
| Cost impact (build and run) | 0.10 |
| Reversibility | 0.10 |
| Strategic alignment | 0.05 |

Overall score is weighted sum of criteria scores.

## ADR Threshold

ADR update is mandatory when any condition is true:

- impacts more than one architecture domain
- changes canonical terms, principles or quality gates
- introduces irreversible or high-cost commitments
- modifies security, privacy or compliance posture
- changes default stack or deployment model

## Decision Record Minimum Fields

- decision statement
- context and constraints
- options considered
- evaluation summary
- chosen option and rationale
- consequences and risks
- owner and date

## Reversibility Classification

Each decision must be classified as:

- reversible
- difficult-to-reverse
- effectively irreversible

Difficult and irreversible decisions require expanded risk analysis.

## Decision SLAs

- urgent incident-bound decisions: same day with retro documentation
- product and architecture decisions: within planning cycle
- strategic decisions: scheduled review with cross-domain stakeholders

## Escalation Policy

If disagreement persists after option scoring:

1. document unresolved assumptions
2. run focused evidence gathering
3. escalate to Chief Architect for final decision

## Post-Decision Review

Each major decision requires a review checkpoint to validate outcomes and unintended consequences.

Minimum review windows:

- tactical decisions: 2 to 4 weeks
- architecture decisions: 4 to 8 weeks
- strategic decisions: quarterly

## Anti-Patterns

Do not:

- decide by preference without explicit constraints
- skip option generation for non-urgent decisions
- close decisions without consequence tracking
- ship architecture-impacting changes without ADR traceability

## Acceptance Criteria

1. decision process is complete and repeatable
2. weighting rubric and ADR threshold are explicit
3. escalation and review loops are defined

## References

- [000 OVERVIEW.md](000 OVERVIEW.md)
- [001 PRODUCT_ARCHITECTURE_MANUAL.md](001 PRODUCT_ARCHITECTURE_MANUAL.md)
- [005 PRODUCT_PRINCIPLES.md](005 PRODUCT_PRINCIPLES.md)
- [007 ARCHITECTURE_PRINCIPLES.md](007 ARCHITECTURE_PRINCIPLES.md)
- [010 DOCUMENT_STANDARDS.md](010 DOCUMENT_STANDARDS.md)
- [../DECISIONS.md](../DECISIONS.md)
