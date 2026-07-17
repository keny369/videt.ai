---
title: Testing Standards
identifier: EM-III-018
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 18 — Testing Standards

## 1. Purpose

This chapter defines the mandatory engineering standards governing testing throughout the F1 platform.

Testing exists to demonstrate that the implemented system faithfully satisfies the Product Specification while preserving architectural integrity.

Tests SHALL verify observable behaviour rather than implementation detail.

Every production implementation SHALL comply with these standards.

---

# 2. Scope

This chapter governs:

- unit testing;
- integration testing;
- contract testing;
- end-to-end testing;
- architectural testing;
- regression testing;
- test organisation;
- test quality.

These standards apply to all executable software.

---

# 3. Engineering Philosophy

Testing is evidence.

It SHALL demonstrate correctness rather than increase coverage statistics.

The objective of testing is confidence in business behaviour.

High coverage without meaningful assertions is not considered quality.

---

# 4. Testing Pyramid

The platform SHALL adopt the following testing strategy.

```text
End-to-End Tests

↓

Integration Tests

↓

Unit Tests
```

Most tests SHOULD be unit tests.

Fewer SHOULD be integration tests.

Only essential scenarios SHOULD become end-to-end tests.

---

# 5. Unit Tests

Unit tests SHALL verify individual classes in isolation.

Dependencies SHALL be replaced with test doubles where appropriate.

Unit tests SHALL be:

- deterministic;
- fast;
- independent;
- repeatable.

A unit test SHALL not require external infrastructure.

---

# 6. Integration Tests

Integration tests SHALL verify collaboration between components.

Examples include:

- repository persistence;
- PostgreSQL integration;
- Redis integration;
- background jobs;
- event publication.

Integration tests SHALL validate architectural boundaries.

---

# 7. End-to-End Tests

End-to-end tests SHALL verify complete business workflows.

Examples include:

- account registration;
- organization creation;
- crawl execution;
- evaluation completion.

End-to-end tests SHALL exercise externally observable behaviour.

---

# 8. Contract Tests

Contract tests SHALL verify:

- API compatibility;
- event schemas;
- external integrations;
- interface stability.

Contract tests SHALL prevent integration drift.

---

# 9. Architectural Tests

Architectural tests SHALL verify:

- dependency direction;
- module boundaries;
- layering;
- repository conventions;
- framework isolation.

Architecture SHALL be continuously validated.

---

# 10. Test Naming

Test names SHALL describe observable behaviour.

Preferred format:

```text
returns_conflict_when_evaluation_already_running
```

rather than:

```text
test_method_one
```

Behaviour-focused naming SHALL be used consistently.

---

# 11. Test Structure

Tests SHOULD follow:

```text
Arrange

↓

Act

↓

Assert
```

Each test SHALL verify one primary behavioural outcome.

---

# 12. Determinism

Tests SHALL remain deterministic.

Tests SHALL NOT depend upon:

- execution order;
- current time without control;
- network availability;
- shared mutable state;
- random data without fixed seeds.

A test SHALL produce identical outcomes under identical conditions.

---

# 13. Fixtures

Fixtures SHOULD remain minimal.

Factories SHALL generally be preferred over large static fixtures.

Test data SHALL communicate business intent.

Unused fixture data is prohibited.

---

# 14. Mocking

Mocks SHALL be used sparingly.

Mock behaviour SHALL represent architectural collaboration rather than implementation internals.

Over-mocking is discouraged.

Business behaviour SHOULD remain directly observable.

---

# 15. Coverage

Code coverage MAY be measured.

Coverage SHALL NOT be treated as the primary measure of software quality.

Meaningful assertions take precedence over numerical coverage.

---

# 16. Regression Testing

Every resolved production defect SHOULD introduce a regression test.

Regression tests SHALL remain permanently unless the corresponding behaviour is formally removed.

---

# 17. Performance

The complete automated test suite SHOULD remain suitable for continuous integration.

Slow tests SHALL be identified and reviewed.

Excessively slow test suites reduce engineering effectiveness.

---

# 18. AI Engineering

AI coding agents SHALL:

- generate behaviour-focused tests;
- preserve deterministic execution;
- minimise unnecessary mocks;
- test observable outcomes;
- avoid implementation-coupled assertions.

AI SHALL NOT optimise solely for code coverage.

---

# 19. Review Checklist

Reviewers SHALL verify:

## Behaviour

- [ ] Behaviour tested.
- [ ] Assertions meaningful.
- [ ] Business terminology preserved.

---

## Reliability

- [ ] Tests deterministic.
- [ ] Independent execution.
- [ ] Appropriate isolation.

---

## Maintainability

- [ ] Readable.
- [ ] Minimal fixtures.
- [ ] Naming appropriate.

---

# 20. Anti-Patterns

The following practices are prohibited.

- Tests dependent upon execution order.
- Hidden shared state.
- Testing private methods directly.
- Excessive mocking.
- Assertions against implementation details.
- Sleeping to wait for asynchronous behaviour.
- Flaky tests.
- Coverage-driven testing without behavioural verification.
- Production defects without regression tests.

---

# 21. Compliance

Every production implementation SHALL comply with these testing standards.

Testing is the primary engineering evidence that the Product Specification has been implemented correctly and continues to remain correct throughout the lifetime of the platform.

---

# Cross References

- EM-I-010 Definition of Done
- EM-I-011 Code Review
- EM-II-018 Architectural Validation
- EM-III-015 Validation Standards
- EM-III-016 Error Handling Standards
- Engineering Manual Volume IX — Quality Engineering
- Product Specification
- Architectural Decision Records
