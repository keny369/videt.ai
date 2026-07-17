---
title: Validation Standards
identifier: EM-III-015
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 15 — Validation Standards

## 1. Purpose

This chapter defines the mandatory validation standards for the F1 platform.

Validation ensures that data entering the system is structurally correct, semantically meaningful and compliant with business rules before it affects persistent business state.

Validation SHALL occur at clearly defined architectural boundaries.

Each layer SHALL validate only those concerns it owns.

---

# 2. Scope

This chapter governs:

- input validation;
- command validation;
- API validation;
- DTO validation;
- Domain validation;
- persistence validation;
- error reporting;
- validation architecture.

These standards apply to every externally supplied input.

---

# 3. Engineering Philosophy

Validation is layered.

Each architectural layer validates only its own responsibilities.

Validation SHALL NOT be duplicated unnecessarily.

Business rules SHALL remain within the Domain Model.

---

# 4. Validation Layers

Validation SHALL occur in the following order.

```text
HTTP Request

↓

Request Validation

↓

DTO Validation

↓

Application Validation

↓

Domain Validation

↓

Persistence Constraints
```

Each layer SHALL assume previous layers have completed successfully.

---

# 5. Request Validation

The Interface Layer SHALL validate:

- required fields;
- supported formats;
- data types;
- payload structure;
- request size;
- media type.

Request validation SHALL NOT evaluate business policy.

---

# 6. DTO Validation

DTOs SHALL validate:

- mandatory attributes;
- structural correctness;
- identifier format;
- UUID syntax;
- email syntax;
- URL syntax;
- timestamp format.

DTOs SHALL remain independent of business workflows.

---

# 7. Application Validation

Application Services MAY validate:

- command completeness;
- dependency availability;
- request context;
- authentication state;
- authorization prerequisites.

Application Services SHALL NOT own business invariants.

---

# 8. Domain Validation

The Domain SHALL validate:

- business invariants;
- lifecycle transitions;
- workflow rules;
- policy decisions;
- Aggregate consistency;
- Entity correctness.

Business validation SHALL always remain authoritative.

---

# 9. Persistence Validation

Persistence SHALL enforce:

- foreign keys;
- uniqueness constraints;
- not-null constraints;
- check constraints.

Persistence SHALL reinforce Domain correctness.

Persistence SHALL NOT replace the Domain Model.

---

# 10. Validation Outcomes

Validation SHALL produce deterministic outcomes.

Every failure SHALL include:

- error identifier;
- failure reason;
- affected field where applicable;
- recoverability;
- correlation identifier.

Validation SHALL never fail silently.

---

# 11. Error Messages

Validation messages SHALL:

- be understandable;
- avoid internal implementation detail;
- avoid stack traces;
- avoid infrastructure disclosure.

Internal diagnostics SHALL remain within operational logs.

---

# 12. Validation Ordering

Validation SHOULD fail as early as practical.

Expensive business operations SHALL NOT execute after known validation failure.

Fail-fast behaviour improves reliability and operational efficiency.

---

# 13. Reuse

Validation logic SHALL exist in one authoritative location.

Duplicate validation increases maintenance cost and risks inconsistent behaviour.

Business validation SHALL not be copied across architectural layers.

---

# 14. Security

Validation SHALL treat all external input as untrusted.

Validation SHALL defend against:

- malformed payloads;
- injection attacks;
- oversized requests;
- unsupported content;
- unexpected values.

Validation SHALL occur before processing.

---

# 15. Observability

Validation failures SHALL produce:

- structured logs;
- validation metrics;
- correlation identifiers;
- operational visibility.

Repeated validation failures SHOULD support operational analysis.

---

# 16. AI Engineering

AI coding agents SHALL:

- validate at the correct architectural layer;
- avoid duplicated validation;
- preserve Domain authority;
- generate deterministic validation outcomes;
- avoid embedding business policy within controllers.

AI SHALL NOT confuse structural validation with business validation.

---

# 17. Review Checklist

Reviewers SHALL verify:

## Layering

- [ ] Validation at correct layer.
- [ ] Domain authority preserved.
- [ ] No unnecessary duplication.

---

## Correctness

- [ ] Fail-fast behaviour.
- [ ] Clear outcomes.
- [ ] Appropriate error reporting.

---

## Security

- [ ] External input validated.
- [ ] Sensitive information protected.
- [ ] Injection risks addressed.

---

# 18. Anti-Patterns

The following practices are prohibited.

- Business validation inside controllers.
- Duplicate validation logic.
- Silent validation failures.
- Database-only validation.
- Validation through exceptions alone.
- User-visible stack traces.
- Framework validation replacing Domain invariants.
- Hidden validation side effects.

---

# 19. Compliance

Every validation implementation SHALL comply with these standards.

Validation protects both architectural integrity and business correctness.

Each layer SHALL validate only the responsibilities it owns.

---

# Cross References

- EM-II-004 Layered Architecture
- EM-II-005 Domain-Driven Design
- EM-II-008 Service Architecture
- EM-III-008 Data Transfer Object Standards
- EM-III-010 Entity Standards
- EM-III-011 Aggregate Standards
- Engineering Manual Volume VIII — Security Engineering
- Product Specification
- Architectural Decision Records
