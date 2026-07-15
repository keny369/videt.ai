# 017 ERROR_MODEL

## Status

- Status: Accepted
- Foundation Version: 1.0
- Last Updated: 2026-07-15

## Authority

This document defines the canonical error taxonomy, exposure policy, recovery model, and escalation model for F1.

All specifications and implementation plans MUST use this error model.

## Purpose

Define failure classes, retry policies, user-visible behavior, internal behavior, and recovery expectations.

## Scope

This document covers:

- error taxonomy and classification
- retryable and non-retryable behavior
- partial failure and compensation
- user-visible and internal error handling
- correlation, logging, alerting, and escalation
- AI, retrieval, citation, parsing, and indexing failures

## Dependencies

- [013 QUALITY_ATTRIBUTES.md](013%20QUALITY_ATTRIBUTES.md)
- [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md)
- [016 STATE_MODEL.md](016%20STATE_MODEL.md)
- [018 OBSERVABILITY.md](018%20OBSERVABILITY.md)

## Definitions

- Retryable Error: Failure condition expected to succeed after bounded retry.
- Non-Retryable Error: Failure condition requiring correction or policy action.
- Partial Failure: Failure affecting a subset of workload while other subsets complete.
- Compensating Action: Explicit operation used to restore consistent domain state.

## Assumptions

- F1 workflows include synchronous requests and asynchronous pipelines.
- External dependencies fail independently.
- Error handling must support both customer clarity and operational diagnosis.

## Constraints

- Errors MUST be classified by canonical taxonomy.
- Sensitive details MUST NOT be exposed to end users.
- Retry behavior MUST be bounded and deterministic.

## Normative Requirements

### Error Taxonomy

ERR-REQ-001: Canonical error classes MUST include:

- user errors
- validation errors
- domain errors
- authentication errors
- authorization errors
- dependency errors
- timeout errors
- rate-limit errors
- capacity errors
- data-integrity errors
- AI errors
- retrieval errors
- citation errors
- parsing errors
- indexing errors

ERR-REQ-002: Every error instance MUST include class, code, severity, retryability, and correlation identifier.

ERR-REQ-003: Error code format MUST follow F1-CLASS-NNN.

### Retry And Timeout Behavior

ERR-REQ-004: Retryable errors MUST define max retries, backoff strategy, and terminal failure behavior.

ERR-REQ-005: Non-retryable errors MUST surface deterministic failure states without retry loops.

ERR-REQ-006: Timeout errors MUST map to explicit timeout class and transition path in [016 STATE_MODEL.md](016%20STATE_MODEL.md).

### Partial Failure And Compensation

ERR-REQ-007: Partial failures MUST preserve successful subset results and identify failed subset scope.

ERR-REQ-008: Compensating actions MUST be idempotent and auditable.

ERR-REQ-009: Compensation outcomes MUST be linked to originating error correlation identifiers.

### User-Visible Error Behavior

ERR-REQ-010: User-visible messages MUST include action guidance and support reference token.

ERR-REQ-011: User-visible messages MUST NOT expose stack traces, secret values, provider tokens, internal topology, or sensitive payload content.

ERR-REQ-012: User-visible severity labels MUST align with terminology and support policy.

### Internal Error Behavior

ERR-REQ-013: Internal logs MUST include correlation identifier, actor context, workflow context, and root error class.

ERR-REQ-014: Internal error records MUST include dependency metadata for external failures.

ERR-REQ-015: Security-sensitive errors MUST trigger security telemetry pathways.

### Correlation, Logging, Alerting, Escalation

ERR-REQ-016: Correlation identifiers MUST propagate across synchronous and asynchronous boundaries.

ERR-REQ-017: Alerting thresholds MUST be defined for critical error classes and reviewed each planning cycle.

ERR-REQ-018: Escalation paths MUST define owner, severity tier, and response target.

### Recovery Expectations

ERR-REQ-019: Every critical workflow MUST define recovery objective and expected operator action.

ERR-REQ-020: Recovered workflows MUST emit explicit recovery-complete events.

## Decisions

- DEC-017-01: Error taxonomy is constitutional and shared across all domains.
- DEC-017-02: User-facing error safety takes precedence over internal diagnostic verbosity.

## Non-goals

- This document does not define UI presentation design details.
- This document does not replace incident runbooks.

## Risks

- Risk: inconsistent error classifications across services.
  Mitigation: taxonomy checks MUST run in architecture review and test gates.
- Risk: overexposure of sensitive diagnostics.
  Mitigation: exposure policy tests MUST run in CI.

## Verification

| Requirement Scope | Verification Method | Owner | Stage |
| --- | --- | --- | --- |
| Taxonomy and code format | Static checks and test assertions | Chief Rails | CI |
| Exposure policy | Security tests and redaction checks | Chief Security | CI |
| Recovery and escalation | Incident simulation and runbook drills | Chief Security | Operations gate |

## Open Questions

- Which error classes require customer-visible status page updates by policy?
- Which workflows require automatic compensation versus operator confirmation?

## Related Documents

- [016 STATE_MODEL.md](016%20STATE_MODEL.md)
- [018 OBSERVABILITY.md](018%20OBSERVABILITY.md)
- [014 SECURITY_MODEL.md](014%20SECURITY_MODEL.md)
- [FOUNDATION_TRACEABILITY_MATRIX.md](FOUNDATION_TRACEABILITY_MATRIX.md)

## Change Control

Any normative change MUST:

1. Update taxonomy references in dependent documents.
2. Update tests and alerting mappings.
3. Include security review for exposure policy changes.
4. Include ADR reference.
