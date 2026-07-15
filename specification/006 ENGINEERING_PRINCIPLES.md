# 006 ENGINEERING_PRINCIPLES

## Status

- Status: Accepted
- Foundation Version: 1.0
- Last Updated: 2026-07-15

## Authority

This document defines constitutional engineering policy for F1.

All implementation specifications MUST comply with these requirements.

## Purpose

Define enforceable engineering principles, delivery controls, and the mandatory TDD discipline.

## Scope

This document governs:

- implementation quality and reliability principles
- test strategy and deterministic execution controls
- merge and release engineering gates
- defect handling policy
- TDD default workflow

## Dependencies

- [001 PRODUCT_ARCHITECTURE_MANUAL.md](001%20PRODUCT_ARCHITECTURE_MANUAL.md)
- [007 ARCHITECTURE_PRINCIPLES.md](007%20ARCHITECTURE_PRINCIPLES.md)
- [008 AI_PRINCIPLES.md](008%20AI_PRINCIPLES.md)
- [010 DOCUMENT_STANDARDS.md](010%20DOCUMENT_STANDARDS.md)
- [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md)
- [017 ERROR_MODEL.md](017%20ERROR_MODEL.md)

## Definitions

- TDD: Test-driven development cycle with Red, Green, Refactor steps.
- Architecture Test: Automated test that validates dependency and module rules.
- Contract Test: Automated test that validates interface behavior across boundary.

## Assumptions

- Critical workflows include synchronous and asynchronous components.
- External dependencies require boundary isolation for deterministic tests.
- Engineering gates enforce merge quality.

## Constraints

- Production behavior changes MUST be test-backed.
- Tests MUST remain deterministic unless controlled probabilistic evaluation is explicitly specified.
- Engineering quality controls MUST be measurable.

## Normative Requirements

### Core Engineering Principles

ENG-REQ-001: Engineering decisions MUST prioritize clarity, correctness, and maintainability.

ENG-REQ-002: Service boundaries and adapters MUST follow canonical architecture boundaries.

ENG-REQ-003: Reliability controls MUST include idempotency, retry policy, timeout policy, and observable outcomes.

ENG-REQ-004: Security and privacy controls MUST be embedded into implementation defaults.

ENG-REQ-005: Every change MUST reference governing specification requirements.

### Mandatory TDD Policy

ENG-REQ-006: Production behavior MUST be introduced through a failing automated test.

ENG-REQ-007: The implementation cycle MUST follow Red, Green, Refactor.

ENG-REQ-008: Defects MUST first be reproduced with a failing test.

ENG-REQ-009: Tests MUST verify behavior instead of implementation detail.

ENG-REQ-010: Tests MUST remain deterministic unless a specification defines controlled probabilistic evaluation.

ENG-REQ-011: External dependencies MUST be isolated behind testable boundaries.

ENG-REQ-012: Time, randomness, network access, model responses, and external services MUST be controllable in tests.

ENG-REQ-013: Unit tests MUST protect domain invariants.

ENG-REQ-014: Integration tests MUST protect boundary contracts.

ENG-REQ-015: Contract tests MUST protect external interfaces.

ENG-REQ-016: End-to-end tests MUST cover critical user journeys.

ENG-REQ-017: Architecture tests MUST protect dependency and module rules.

ENG-REQ-018: Security tests MUST protect authorization and tenant isolation boundaries.

ENG-REQ-019: AI evaluation tests MUST protect retrieval, grounding, citation, safety, latency, and cost behavior.

ENG-REQ-020: A passing test suite MUST be required before merge.

ENG-REQ-021: Tests MUST NOT be deleted or weakened only to make a change pass.

ENG-REQ-022: Any changed requirement MUST update tests and documentation in the same change set.

### Exception Policy

ENG-REQ-023: TDD exceptions MUST be narrow, time-bounded, and documented with written justification.

ENG-REQ-024: Every exception MUST include owner, risk statement, compensating controls, and expiration date.

ENG-REQ-025: Expired exceptions MUST fail merge gate until resolved.

### Merge And Release Gates

ENG-REQ-026: Merge gates MUST include test pass, lint pass, formatting pass, and security scan pass.

ENG-REQ-027: Release gates MUST include compatibility and migration verification when interfaces or schemas change.

ENG-REQ-028: Documentation and traceability checks MUST pass before merge.

## Decisions

- DEC-006-01: TDD is the default implementation discipline.
- DEC-006-02: Deterministic testability is a constitutional quality gate.
- DEC-006-03: Exceptions are constrained by explicit governance.

## Non-goals

- This document does not prescribe a specific testing framework.
- This document does not define product roadmap priority.

## Risks

- Risk: teams bypass TDD under schedule pressure.
  Mitigation: merge gates MUST enforce failing-test-first evidence and exception policy.
- Risk: flaky tests reduce trust in gates.
  Mitigation: deterministic-control requirements and flake monitoring MUST be enforced.

## Verification

| Requirement Scope | Verification Method | Owner | Stage |
| --- | --- | --- | --- |
| TDD cycle compliance | PR template evidence and CI metadata checks | Chief Rails | PR and CI |
| Test coverage by type | Test inventory and architecture fitness functions | Chief Architect | CI |
| Exception policy compliance | Exception registry audit | Chief Architect | Release gate |

## Open Questions

- Which workflows require mutation testing in baseline release gates?
- Which deterministic-control helpers require shared tooling first?

## Related Documents

- [007 ARCHITECTURE_PRINCIPLES.md](007%20ARCHITECTURE_PRINCIPLES.md)
- [010 DOCUMENT_STANDARDS.md](010%20DOCUMENT_STANDARDS.md)
- [FOUNDATION_TRACEABILITY_MATRIX.md](FOUNDATION_TRACEABILITY_MATRIX.md)

## Change Control

Any normative change to this document MUST:

1. Include ADR reference.
2. Include merge gate impact and migration impact.
3. Include update plan for affected tests and documentation.
4. Update traceability matrix mappings.
