# 007 ARCHITECTURE_PRINCIPLES

## Status

- Status: Accepted
- Foundation Version: 1.0
- Last Updated: 2026-07-15

## Authority

This document defines constitutional architecture principles and fitness-function policy for F1.

All downstream architecture and implementation specifications MUST comply with these requirements.

## Purpose

Define architecture boundary principles and convert them into measurable fitness functions.

## Scope

This document governs:

- domain and module boundaries
- contract discipline
- reliability and consistency expectations
- architecture evolution controls
- architecture fitness-function framework

## Dependencies

- [001 PRODUCT_ARCHITECTURE_MANUAL.md](001%20PRODUCT_ARCHITECTURE_MANUAL.md)
- [006 ENGINEERING_PRINCIPLES.md](006%20ENGINEERING_PRINCIPLES.md)
- [008 AI_PRINCIPLES.md](008%20AI_PRINCIPLES.md)
- [009 DECISION_FRAMEWORK.md](009%20DECISION_FRAMEWORK.md)
- [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md)
- [018 OBSERVABILITY.md](018%20OBSERVABILITY.md)
- [019 VERSIONING.md](019%20VERSIONING.md)

## Definitions

- Architecture Fitness Function: Measurable rule that continuously validates architectural intent.
- Boundary Violation: Unauthorized dependency or access across defined architecture boundaries.
- Enforcement Stage: Development stage where a fitness function is evaluated.

## Assumptions

- F1 evolves through modular architecture with explicit boundaries.
- CI gate automation is available for static and dynamic checks.
- Some quantitative thresholds remain provisional and require owner decisions.

## Constraints

- Architecture rules MUST be measurable and enforceable.
- Fitness functions MUST have ownership and exception process.
- Fitness-function exceptions MUST be explicit and time-bounded.

## Normative Requirements

### Core Architecture Principles

ARC-REQ-001: Architecture boundaries MUST align with domain ownership.

ARC-REQ-002: Cross-boundary interactions MUST use published interfaces.

ARC-REQ-003: Unpublished internal interfaces MUST NOT be used by external modules.

ARC-REQ-004: State transitions and side effects MUST be observable and auditable.

ARC-REQ-005: Consistency and integrity constraints MUST be preserved under retries and failures.

ARC-REQ-006: Architecture evolution MUST preserve compatibility policy from [019 VERSIONING.md](019%20VERSIONING.md).

ARC-REQ-007: Architecture policy compliance MUST be validated by fitness functions at defined enforcement stages.

### Fitness-Function Governance

ARC-REQ-008: Every fitness function MUST include identifier, principle enforced, rationale, measurement method, pass condition, failure condition, enforcement stage, automation status, owner, and exception process.

ARC-REQ-009: Fitness functions with unresolved numeric thresholds MUST include provisional gate, owner, and decision deadline.

ARC-REQ-010: Release gates MUST fail for unmet mandatory fitness functions unless an approved exception exists.

### Fitness-Function Catalog

| Identifier | Principle Enforced | Rationale | Measurement Method | Pass Condition | Failure Condition | Enforcement Stage | Automation Status | Owner | Exception Process |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| FF-001 | Boundary integrity | Prevent dependency cycles | Dependency graph analysis | No prohibited cycles | Any prohibited cycle detected | CI | Planned | Chief Architect | FF-EXC-001 |
| FF-002 | Module boundary integrity | Protect module contracts | Import and namespace rules test | No boundary violation | Unauthorized module dependency | CI | Planned | Chief Architect | FF-EXC-001 |
| FF-003 | Layering integrity | Preserve architecture layering | Layer rule static analysis | No upward-layer violations | Layer violation found | CI | Planned | Chief Architect | FF-EXC-001 |
| FF-004 | Interface discipline | Prevent unpublished interface access | Public surface allowlist checks | Only published interfaces used | Internal interface imported externally | CI | Planned | Chief Rails | FF-EXC-001 |
| FF-005 | Test posture | Protect behavioral coverage | Test inventory checks by workflow | Required test types exist for critical workflows | Missing required test type | CI | Planned | Chief Rails | FF-EXC-001 |
| FF-006 | Mutation quality posture | Detect weak assertions | Mutation testing in scoped modules | Mutation score meets approved threshold by 2026-09-01 | Mutation score below threshold after deadline | CI | Planned | Chief Rails | FF-EXC-001 |
| FF-007 | Static correctness | Prevent avoidable defects | Static analysis run | No blocking static-analysis findings | Blocking static-analysis findings present | CI | Planned | Chief Rails | FF-EXC-001 |
| FF-008 | Type safety | Prevent type contract drift | Type checking run | No blocking type errors | Blocking type errors | CI | Planned | Chief Rails | FF-EXC-001 |
| FF-009 | Lint consistency | Enforce style and risk rules | Lint run | No blocking lint violations | Blocking lint violations | CI | Automated | Chief Rails | FF-EXC-001 |
| FF-010 | Formatting consistency | Prevent formatting drift | Formatting check | No formatting drift | Formatting drift present | CI | Automated | Chief Rails | FF-EXC-001 |
| FF-011 | Documentation coverage | Prevent undocumented public behavior | Documentation coverage checks | Public surfaces documented | Missing required documentation | CI and PR | Planned | Chief Architect | FF-EXC-001 |
| FF-012 | API compatibility | Protect consumer stability | API compatibility diff checks | No unauthorized breaking change | Unauthorized breaking change | CI and release | Planned | Chief Architect | FF-EXC-001 |
| FF-013 | Schema compatibility | Protect data contract stability | Schema compatibility checks | Schema changes satisfy policy | Policy-violating schema change | CI and release | Planned | Chief Rails | FF-EXC-001 |
| FF-014 | Migration reversibility | Reduce migration risk | Migration review and test harness | Reversibility classification and rollback plan exist | Missing reversibility evidence | CI and release | Planned | Chief Rails | FF-EXC-001 |
| FF-015 | Performance regression | Prevent latency regressions | Performance benchmark comparison | No regression beyond approved envelope by 2026-08-20 | Regression beyond envelope after deadline | CI and release | Planned | Chief Rails | FF-EXC-001 |
| FF-016 | Query performance | Prevent inefficient data access | Query analysis and benchmark | Query budgets remain within approved envelope by 2026-08-25 | Query budget violation after deadline | CI | Planned | Chief Rails | FF-EXC-001 |
| FF-017 | Error-rate regression | Protect reliability | Error rate trend analysis | Error rate remains within quality envelope from QA-REQ table | Envelope breach | Release | Planned | Chief Architect | FF-EXC-001 |
| FF-018 | Observability coverage | Ensure diagnosability | Workflow telemetry coverage checks | Success and failure signals exist for critical workflows | Missing required signals | CI and release | Planned | Chief Security | FF-EXC-001 |
| FF-019 | Security scanning | Detect security flaws early | Security scan suite | No blocking security findings | Blocking security findings present | CI | Planned | Chief Security | FF-EXC-001 |
| FF-020 | Secret detection | Prevent credential leaks | Secret scanning checks | No detected secrets in versioned artifacts | Secret detected | CI | Automated | Chief Security | FF-EXC-001 |
| FF-021 | Dependency vulnerability posture | Reduce supply chain risk | Vulnerability scan and policy threshold | No unapproved high-severity vulnerabilities | Unapproved high-severity vulnerability | CI and release | Planned | Chief Security | FF-EXC-001 |
| FF-022 | AI evaluation regression | Protect AI quality | AI evaluation suite comparison | AI quality metrics remain within approved envelope by 2026-08-30 | Envelope breach after deadline | CI and release | Planned | Chief AI | FF-EXC-001 |
| FF-023 | Citation validity | Protect evidence trust | Citation validation checks | Citation validity meets approved gate from [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md) | Citation validity below gate | CI and release | Planned | Chief AI | FF-EXC-001 |
| FF-024 | Retrieval quality | Protect relevance quality | Retrieval benchmark suite | Retrieval quality remains within approved envelope by 2026-08-30 | Envelope breach after deadline | CI and release | Planned | Chief AI | FF-EXC-001 |
| FF-025 | Cost-budget regression | Protect unit economics | Cost telemetry regression checks | Workflow cost remains within approved budget envelope | Budget envelope breach | Release | Planned | Chief Product | FF-EXC-001 |
| FF-026 | Accessibility checks | Protect accessibility baseline | Automated accessibility checks plus manual audit gate | Accessibility checks pass required gate | Required accessibility gate fails | CI and release | Planned | Chief UX | FF-EXC-001 |

FF-EXC-001: Exception process MUST require written justification, owner, bounded duration, compensating controls, and ADR reference. Exceptions MUST expire on or before declared date.

## Decisions

- DEC-007-01: Architecture policy is enforced through fitness functions, not review narrative alone.
- DEC-007-02: Quantitative thresholds without evidence use provisional gates with explicit decision deadlines.

## Non-goals

- This document does not define tool-specific configuration syntax.
- This document does not define team staffing models.

## Risks

- Risk: automation coverage lag leaves architecture drift undetected.
  Mitigation: planned fitness functions MUST include delivery deadlines in roadmap and state tracking.
- Risk: exception abuse weakens architecture policy.
  Mitigation: FF-EXC-001 governance and expiration controls.

## Verification

| Requirement Scope | Verification Method | Owner | Stage |
| --- | --- | --- | --- |
| Principle compliance | Architecture review with fitness-function evidence | Chief Architect | Release gate |
| Fitness-function completeness | Catalog audit against ARC-REQ-008 | Chief Architect | PR review |
| Exception governance | Exception registry audit | Chief Architect | Release gate |

## Open Questions

- Which planned fitness functions require first-wave automation before Volume IV work?
- Which retrieval quality benchmarks provide stable baseline for FF-024 threshold resolution?

## Related Documents

- [006 ENGINEERING_PRINCIPLES.md](006%20ENGINEERING_PRINCIPLES.md)
- [010 DOCUMENT_STANDARDS.md](010%20DOCUMENT_STANDARDS.md)
- [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md)
- [FOUNDATION_TRACEABILITY_MATRIX.md](FOUNDATION_TRACEABILITY_MATRIX.md)

## Change Control

Any normative change MUST:

1. Update affected fitness-function rows and owners.
2. Update verification and release gate expectations.
3. Include ADR reference and compatibility assessment.
4. Update traceability mappings.
