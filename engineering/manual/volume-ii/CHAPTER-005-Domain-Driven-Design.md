# engineering/manual/volume-ii/CHAPTER-005-Domain-Driven-Design.md

---
title: Domain-Driven Design
identifier: EM-II-005
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 5 — Domain-Driven Design (DDD)

## 1. Purpose

This chapter establishes the Domain-Driven Design (DDD) principles governing the implementation of the F1 platform.

The Domain Model is the centre of the software architecture.

Every significant business rule, invariant and workflow SHALL originate within the Domain Layer.

The objective of this chapter is to ensure that implementation reflects the business rather than the underlying technology.

---

# 2. Scope

This chapter governs:

- aggregates;
- entities;
- value objects;
- domain services;
- domain events;
- repositories;
- bounded contexts;
- specifications;
- policies;
- invariants.

These standards apply to all business-domain implementation.

---

# 3. Domain Philosophy

The Domain Model SHALL express business language directly.

Business concepts SHALL be represented explicitly rather than inferred from database structure or framework conventions.

Technology SHALL support the Domain.

The Domain SHALL NOT adapt itself to technology.

---

# 4. Ubiquitous Language

Every Domain component SHALL use the terminology defined by the Product Specification.

Examples include:

- Assessment
- Evaluation
- Organisation
- Project
- Evidence
- Issue
- Workflow
- Role Assignment
- Emergency Access Grant

Alternative terminology SHALL NOT be introduced without an approved Product Specification or ADR change.

---

# 5. Bounded Contexts

The platform SHALL be divided into bounded contexts.

A bounded context owns:

- its terminology;
- its business rules;
- its aggregates;
- its repository interfaces;
- its domain events.

Cross-context communication SHALL occur only through explicit contracts.

---

# 6. Aggregates

An Aggregate is the primary consistency boundary.

Every Aggregate SHALL:

- enforce invariants;
- protect internal consistency;
- expose a single Aggregate Root;
- define transactional consistency.

External components SHALL interact only through the Aggregate Root.

---

## Aggregate Responsibilities

Aggregates SHALL:

- validate business rules;
- coordinate entities;
- manage state transitions;
- emit domain events;
- reject invalid operations.

Aggregates SHALL NOT:

- access databases;
- invoke HTTP services;
- send email;
- call Redis;
- publish directly to infrastructure.

---

# 7. Aggregate Roots

Each Aggregate SHALL expose exactly one Aggregate Root.

The Aggregate Root SHALL:

- control modification;
- preserve invariants;
- coordinate internal entities;
- determine valid lifecycle transitions.

No external component SHALL modify Aggregate internals directly.

---

# 8. Entities

Entities possess identity.

Entity identity SHALL remain stable throughout the entity's lifetime.

Entities MAY contain behaviour.

Entities SHALL NOT own persistence.

---

# 9. Value Objects

Value Objects are immutable.

They SHALL:

- possess no independent identity;
- compare by value;
- remain immutable after creation;
- encapsulate validation.

Examples include:

- EmailAddress
- DomainName
- Money
- ConfidenceScore
- CrawlDepth

Mutable Value Objects are prohibited.

---

# 10. Domain Services

Domain Services SHALL encapsulate behaviour that:

- belongs to the Domain;
- spans multiple Aggregates;
- cannot naturally belong to one Entity.

Domain Services SHALL remain stateless wherever practical.

---

# 11. Repository Interfaces

Repositories abstract persistence.

Repository interfaces belong to the Domain.

Repository implementations belong to Infrastructure.

Repositories SHALL expose business-oriented operations rather than database mechanics.

Example:

```
AssessmentRepository.find_for_project()

NOT

AssessmentRepository.find_by_sql(...)
```

---

# 12. Specifications

Specifications encapsulate complex business predicates.

Specifications SHALL:

- remain reusable;
- remain composable;
- avoid persistence concerns;
- avoid framework dependencies.

---

# 13. Policies

Policies define business decisions that may evolve independently of Aggregates.

Examples include:

- scoring policies;
- crawl policies;
- notification policies;
- confidence policies.

Policies SHALL remain deterministic.

---

# 14. Domain Events

Domain Events record business facts.

They SHALL:

- be immutable;
- describe completed business occurrences;
- originate from the Domain;
- remain technology independent.

Domain Events SHALL NOT contain infrastructure behaviour.

---

# 15. Invariants

Business invariants SHALL be enforced by Aggregates.

Examples include:

- valid state transitions;
- uniqueness constraints defined by business;
- lifecycle restrictions;
- authorisation preconditions.

Infrastructure SHALL support invariants but SHALL NOT replace Aggregate enforcement.

---

# 16. Factories

Factories MAY be introduced where Aggregate construction becomes complex.

Factories SHALL:

- enforce creation rules;
- initialise valid state;
- avoid persistence;
- remain within the Domain.

---

# 17. Identity

Entity identifiers SHALL:

- remain immutable;
- possess no business behaviour;
- avoid encoding implementation detail.

Identity generation SHALL remain independent of business rules.

---

# 18. AI Engineering

AI coding agents SHALL:

- preserve Aggregate boundaries;
- avoid placing business rules inside repositories;
- avoid framework dependencies in the Domain;
- preserve ubiquitous language;
- implement invariants only within Domain components.

AI SHALL NOT introduce anemic domain models.

---

# 19. Review Checklist

Reviewers SHALL verify:

## Domain Integrity

- [ ] Business rules reside in the Domain.
- [ ] Aggregates enforce invariants.
- [ ] Value Objects remain immutable.
- [ ] Repository interfaces remain technology independent.

---

## Architecture

- [ ] Domain independent of Rails.
- [ ] Domain independent of persistence.
- [ ] Domain independent of transport.
- [ ] Dependency direction preserved.

---

## Maintainability

- [ ] Ubiquitous language preserved.
- [ ] Behaviour cohesive.
- [ ] Responsibilities correctly assigned.

---

# 20. Anti-Patterns

The following practices are prohibited.

- Anemic Domain Models.
- Business logic inside Active Record models.
- Repository interfaces exposing SQL concepts.
- Mutable Value Objects.
- Infrastructure services inside Aggregates.
- Cross-Aggregate direct mutation.
- Framework-specific annotations inside Domain objects.
- Aggregates exposing mutable internal state.
- Business rules implemented in controllers or jobs.

---

# 21. Compliance

Every business-domain implementation SHALL comply with the principles defined in this chapter.

The Domain Layer is the canonical implementation of business behaviour.

Architectural departures require an approved ADR before implementation.

---

# Cross References

- EM-II-001 Architecture Philosophy
- EM-II-004 Layered Architecture
- EM-II-006 Module Boundaries
- EM-II-007 Dependency Rules
- EM-II-008 Service Architecture
- EM-II-011 Persistence Architecture
- Product Specification
- Architectural Decision Records