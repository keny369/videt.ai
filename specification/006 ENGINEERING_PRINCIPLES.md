# 006 ENGINEERING_PRINCIPLES

## Document Control

- Status: Accepted baseline
- Version: 1.0.0
- Last updated: 2026-07-15
- Owner: Chief Rails
- Reviewer: Chief Architect
- Classification: Canonical

## Purpose

Define engineering principles for implementation quality, reliability, maintainability and delivery discipline.

## Scope

Applies to:

- application code architecture
- testing strategy
- integration behavior
- operational quality controls
- delivery workflow

## Principle 1: Clarity Over Cleverness

Code and architecture should be obvious to future maintainers.

Implications:

- favor explicit design over abstraction for its own sake
- keep modules focused and responsibilities narrow

## Principle 2: Convention With Intentional Deviation

Default to framework conventions. Deviations require explicit rationale and ADR traceability.

## Principle 3: Correctness Before Optimization

Correct, testable behavior is a prerequisite for performance optimization.

## Principle 4: Testability Is A Design Constraint

Design components so behavior can be validated at the correct scope with deterministic tests.

## Principle 5: Reliability By Default

Background processing, retries and external integration behavior must be idempotent and observable.

## Principle 6: Secure Defaults

Security controls must be embedded into standard implementation patterns.

## Principle 7: Observability Built In

Critical flows must emit logs, metrics and traces that support diagnosis without code changes.

## Principle 8: Backward-Compatible Evolution

Data contracts and APIs should evolve with compatibility windows and explicit deprecation plans.

## Principle 9: Small, Reversible Changes

Prefer incremental, reversible changes over large irreversible rewrites.

## Principle 10: Cost-Aware Engineering

Design choices should consider run cost, maintenance cost and support burden.

## Baseline Engineering Practices

- use service objects and POROs for non-trivial business logic
- separate orchestration concerns from pure domain logic
- keep controller and UI layers thin
- use background jobs for long-running or retry-prone operations

## Testing Principles

- unit tests validate domain logic behavior
- integration tests validate contracts between components
- end-to-end tests validate critical user workflows
- test suites must include both success and failure paths

## Delivery Principles

- every change references the governing specification chapter
- high-impact changes include ADR updates
- pull requests must document behavior change and risk profile

## Failure Handling Principles

- transient failures use bounded retries with jitter
- permanent failures must produce actionable error states
- user-visible failures require clear recovery guidance

## Data Handling Principles

- data integrity constraints belong in both application and database design
- write operations must be traceable to actor and context
- migrations should be safe for production-scale data evolution

## Acceptance Criteria

1. principles provide concrete engineering guidance
2. reliability, testing and security are first-class constraints
3. baseline practices align with project constitution

## References

- [../CLAUDE.md](../CLAUDE.md)
- [007 ARCHITECTURE_PRINCIPLES.md](007 ARCHITECTURE_PRINCIPLES.md)
- [008 AI_PRINCIPLES.md](008 AI_PRINCIPLES.md)
- [009 DECISION_FRAMEWORK.md](009 DECISION_FRAMEWORK.md)
