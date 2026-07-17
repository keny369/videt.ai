---
title: Domain Service Standards
identifier: EM-III-012
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 12 — Domain Service Standards

## 1. Purpose

This chapter defines the mandatory standards governing Domain Services within the F1 platform.

Domain Services exist to encapsulate business behaviour that cannot naturally belong to a single Entity, Value Object or Aggregate.

Domain Services SHALL represent business concepts.

They SHALL NOT become procedural utility classes.

Every Domain Service SHALL comply with this chapter.

---

# 2. Scope

This chapter governs:

- Domain Services;
- business algorithms;
- cross-Aggregate behaviour;
- business policies;
- domain collaboration;
- dependency rules;
- implementation standards.

These standards apply exclusively to the Domain Layer.

---

# 3. Engineering Philosophy

A Domain Service represents business capability.

If behaviour belongs naturally within an Entity or Value Object, it SHALL remain there.

Domain Services exist only when no single Domain object can legitimately own the behaviour.

Their introduction SHALL be deliberate rather than convenient.

---

# 4. Appropriate Use

A Domain Service MAY be introduced where:

- behaviour spans multiple Aggregates;
- multiple Entities participate equally;
- complex business policy exists independently of persistence;
- business algorithms lack natural ownership.

Domain Services SHALL NOT exist merely to reduce class size.

---

# 5. Responsibilities

Domain Services SHALL:

- implement business behaviour;
- preserve business terminology;
- coordinate Domain collaboration;
- enforce business policy where ownership spans multiple objects.

Domain Services SHALL NOT:

- own transactions;
- persist data;
- invoke infrastructure;
- publish events;
- construct repositories.

---

# 6. Domain Purity

Domain Services SHALL remain framework-independent.

They SHALL NOT depend upon:

- Rails;
- Active Record;
- Redis;
- HTTP;
- PostgreSQL;
- Sidekiq.

The Domain Layer SHALL remain technically isolated.

---

# 7. Dependencies

Dependencies SHALL consist only of:

- Domain interfaces;
- Value Objects;
- Entities;
- Aggregates;
- Domain abstractions.

Infrastructure dependencies are prohibited.

Dependency injection SHALL remain explicit.

---

# 8. Stateless Design

Domain Services SHOULD remain stateless.

State SHALL normally reside within:

- Entities;
- Value Objects;
- Aggregates.

Stateless services improve determinism and testability.

---

# 9. Public Interface

A Domain Service SHOULD expose one primary business capability.

Example:

```ruby
IssueFingerprintComparisonService
```

Example interface:

```ruby
compare(candidate, existing)
```

The public interface SHALL communicate business intent.

---

# 10. Business Policies

Business policies spanning multiple Domain objects MAY reside within Domain Services.

Examples include:

- issue similarity determination;
- confidence calculation;
- evaluation policy;
- workflow eligibility;
- recommendation ranking.

Policies SHALL remain deterministic.

---

# 11. Collaboration

Domain Services MAY invoke:

- Entities;
- Value Objects;
- other Domain Services where justified.

Circular Domain Service dependencies are prohibited.

Application Services SHALL orchestrate Domain Service execution where necessary.

---

# 12. Transactions

Domain Services SHALL NOT own transaction boundaries.

Transactions remain the responsibility of the Application Layer.

Domain Services SHALL remain unaware of persistence mechanics.

---

# 13. Error Handling

Domain Services SHALL distinguish between:

- invalid business state;
- business policy failure;
- programming defects.

Business failures SHOULD be expressed through Domain outcomes.

Infrastructure exceptions SHALL NOT originate within the Domain.

---

# 14. Naming

Names SHALL describe business capability.

Examples:

```ruby
IssueFingerprintComparisonService

ConfidenceScoringService

RecommendationRankingService

OrganizationEligibilityService
```

Generic names are prohibited.

Examples:

```ruby
Helper

Processor

Manager

Utility
```

---

# 15. Testing

Every Domain Service SHALL possess tests covering:

- business behaviour;
- policy evaluation;
- boundary conditions;
- deterministic outcomes.

Domain Services SHALL be independently testable without infrastructure.

---

# 16. AI Engineering

AI coding agents SHALL:

- introduce Domain Services only when justified;
- preserve Domain purity;
- avoid framework dependencies;
- implement business terminology;
- avoid procedural utility classes.

AI SHALL first attempt to place behaviour inside existing Domain objects before creating a Domain Service.

---

# 17. Review Checklist

Reviewers SHALL verify:

## Domain

- [ ] Business behaviour appropriate.
- [ ] No framework dependencies.
- [ ] Stateless where practical.

---

## Architecture

- [ ] Transactions absent.
- [ ] Persistence absent.
- [ ] Dependencies explicit.

---

## Maintainability

- [ ] Business terminology preserved.
- [ ] Service justified.
- [ ] Tests comprehensive.

---

# 18. Anti-Patterns

The following practices are prohibited.

- Utility classes masquerading as Domain Services.
- Framework-aware Domain Services.
- Domain Services owning transactions.
- Persistence logic.
- Event publication.
- Infrastructure dependencies.
- Procedural "Manager" classes.
- Circular Domain Service dependencies.
- Generic catch-all business services.

---

# 19. Compliance

Every Domain Service SHALL comply with these standards.

Domain Services exist to strengthen the Domain Model—not to replace it.

Their introduction SHALL always improve business clarity and architectural cohesion.

---

# Cross References

- EM-II-005 Domain-Driven Design
- EM-II-008 Service Architecture
- EM-II-015 Dependency Injection
- EM-III-006 Service Object Standards
- EM-III-011 Aggregate Standards
- EM-III-013 Factory Standards
- Product Specification
- Architectural Decision Records
