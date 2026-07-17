# engineering/manual/volume-iii/CHAPTER-016-Error-Handling-Standards.md

---
title: Error Handling Standards
identifier: EM-III-016
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 16 — Error Handling Standards

## 1. Purpose

This chapter defines the mandatory engineering standards governing error handling throughout the F1 platform.

Errors are an expected aspect of software operation.

They SHALL be handled consistently, predictably and observably.

The objective of error handling is not merely to prevent crashes, but to preserve business correctness, operational reliability and diagnosability.

Every implementation SHALL comply with these standards.

---

# 2. Scope

This chapter governs:

- business errors;
- validation failures;
- infrastructure failures;
- exception handling;
- retry behaviour;
- error propagation;
- logging;
- observability.

These standards apply to every layer of the platform.

---

# 3. Engineering Philosophy

Errors SHALL be classified before they are handled.

Not all failures are exceptional.

Business outcomes are not software failures.

Programming defects are not business outcomes.

Infrastructure failures are not business decisions.

Each category SHALL be handled differently.

---

# 4. Error Categories

Errors SHALL belong to one of the following categories.

## Business Errors

Expected business outcomes.

Examples:

- insufficient permissions;
- workflow preconditions not satisfied;
- duplicate evaluation;
- expired session.

Business errors SHALL NOT be implemented through exceptions.

---

## Validation Errors

Input fails structural or business validation.

Validation failures SHALL return deterministic outcomes.

---

## Infrastructure Errors

Failures originating outside the Domain.

Examples:

- database unavailable;
- Redis unavailable;
- SMTP failure;
- network timeout;
- storage failure.

Infrastructure failures MAY use exceptions.

---

## Programming Errors

Implementation defects.

Examples:

- nil dereference;
- invariant violation;
- impossible state;
- unexpected dependency failure.

Programming defects SHALL fail fast.

---

# 5. Business Errors

Business errors SHALL be represented explicitly.

Preferred approaches include:

- Result Objects;
- Failure Objects;
- Domain Outcomes.

Business behaviour SHALL remain observable without exception handling.

---

# 6. Exceptions

Exceptions SHALL be reserved for exceptional situations.

Examples include:

- infrastructure failure;
- programming defects;
- unrecoverable runtime conditions.

Exceptions SHALL NOT control ordinary business flow.

---

# 7. Error Propagation

Errors SHALL propagate only as far as necessary.

Each architectural layer SHALL translate errors into representations appropriate for that layer.

Example:

```text
Database Timeout

↓

Infrastructure Exception

↓

Application Error

↓

API Error Response
```

Internal implementation details SHALL NOT leak externally.

---

# 8. Retry Behaviour

Retries SHALL occur only where operations are demonstrably safe.

Retry decisions SHALL consider:

- idempotency;
- operation type;
- business impact;
- external guarantees.

Blind retries are prohibited.

---

# 9. Error Messages

User-facing errors SHALL:

- be understandable;
- avoid implementation details;
- preserve security;
- support recovery where appropriate.

Internal diagnostics belong in operational logs.

---

# 10. Error Codes

Every externally observable error SHALL possess:

- a stable identifier;
- documented meaning;
- deterministic behaviour.

Error identifiers SHALL remain stable across releases unless superseded through formal governance.

---

# 11. Logging

Errors SHALL produce structured logs containing:

- timestamp;
- correlation identifier;
- severity;
- component;
- operation;
- error identifier;
- stack trace where appropriate.

Sensitive information SHALL never be logged.

---

# 12. Observability

Operational telemetry SHALL record:

- error frequency;
- error category;
- retry behaviour;
- failure trends;
- recovery outcomes.

Observability SHALL support incident diagnosis without requiring code inspection.

---

# 13. Recovery

Recoverable failures SHOULD:

- preserve business consistency;
- maintain idempotency;
- avoid partial state changes;
- provide deterministic outcomes.

Recovery SHALL never violate Product Specification semantics.

---

# 14. Security

Error handling SHALL avoid disclosing:

- implementation details;
- infrastructure topology;
- credentials;
- secrets;
- stack traces;
- internal object structures.

Security SHALL take precedence over diagnostic convenience.

---

# 15. Testing

Every significant error path SHALL possess tests covering:

- expected business failures;
- infrastructure failures;
- retry behaviour;
- recovery behaviour;
- observability.

Error handling SHALL be deterministic.

---

# 16. AI Engineering

AI coding agents SHALL:

- distinguish business errors from exceptions;
- preserve deterministic outcomes;
- avoid broad rescue blocks;
- propagate errors appropriately;
- maintain structured logging.

AI SHALL NOT suppress exceptions without explicit engineering justification.

---

# 17. Review Checklist

Reviewers SHALL verify:

## Classification

- [ ] Error category correct.
- [ ] Business errors explicit.
- [ ] Exceptions justified.

---

## Reliability

- [ ] Retry appropriate.
- [ ] Recovery deterministic.
- [ ] Partial state avoided.

---

## Operations

- [ ] Structured logging.
- [ ] Stable error identifiers.
- [ ] Observability preserved.

---

# 18. Anti-Patterns

The following practices are prohibited.

- Exceptions for ordinary business flow.
- Catch-all rescue blocks.
- Silent failure.
- Ignored exceptions.
- Logging secrets.
- User-visible stack traces.
- Retrying non-idempotent operations blindly.
- Swallowing infrastructure failures.
- Returning inconsistent error structures.

---

# 19. Compliance

Every implementation SHALL comply with these standards.

Correct error handling protects business correctness, operational resilience and long-term maintainability.

Architectural deviations require an approved ADR before implementation.

---

# Cross References

- EM-II-010 Transaction Boundaries
- EM-II-013 Background Processing
- EM-III-006 Service Object Standards
- EM-III-015 Validation Standards
- Engineering Manual Volume VIII — Security Engineering
- Engineering Manual Volume X — Production Operations
- Product Specification
- Architectural Decision Records