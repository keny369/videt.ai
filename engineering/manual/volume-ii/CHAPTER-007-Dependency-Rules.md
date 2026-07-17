# engineering/manual/volume-ii/CHAPTER-007-Dependency-Rules.md

---
title: Dependency Rules
identifier: EM-II-007
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 7 — Dependency Rules

## 1. Purpose

This chapter establishes the mandatory dependency rules governing all software within the F1 platform.

Architectural quality is determined not only by the responsibilities of individual components, but also by the relationships between them.

Dependencies define those relationships.

Poor dependency management inevitably leads to architectural erosion, increased coupling, reduced testability and declining maintainability.

The purpose of this chapter is to ensure that dependency direction remains predictable, explicit and consistent throughout the lifetime of the platform.

---

# 2. Scope

This chapter governs:

- module dependencies;
- layer dependencies;
- service dependencies;
- framework dependencies;
- infrastructure dependencies;
- external integrations;
- compile-time dependencies;
- runtime dependencies.

Every software dependency SHALL comply with this chapter.

---

# 3. Architectural Philosophy

Dependencies SHALL express architectural intent.

A dependency exists because one component requires another to fulfil its responsibility.

Dependencies SHALL NOT exist merely because implementation is convenient.

Architectural convenience SHALL NEVER override architectural integrity.

---

# 4. Fundamental Dependency Rule

All dependencies SHALL point toward business behaviour.

The canonical dependency direction is:

```text
Interface
      │
      ▼
Application
      │
      ▼
Domain
      ▲
      │
Infrastructure
```

The Domain Layer SHALL have no knowledge of outer layers.

---

# 5. Inward Dependency Principle

Outer layers depend upon inner layers.

Inner layers SHALL NOT depend upon outer layers.

This rule SHALL remain true regardless of:

- programming language;
- framework;
- deployment architecture;
- persistence technology.

---

# 6. Domain Independence

The Domain Layer SHALL NOT directly depend upon:

- Rails
- Active Record
- PostgreSQL
- Redis
- Sidekiq
- HTTP
- JSON
- HTML
- GraphQL
- external APIs
- cloud providers

The Domain SHALL define business behaviour only.

---

# 7. Infrastructure Dependency

Infrastructure SHALL depend upon abstractions defined by the Domain.

Examples include:

- repository interfaces;
- event interfaces;
- storage interfaces;
- messaging interfaces.

Infrastructure SHALL implement those abstractions.

Infrastructure SHALL NOT redefine them.

---

# 8. Interface Dependency

The Interface Layer MAY depend upon:

- Application Services;
- request DTOs;
- response DTOs;
- authentication services;
- authorisation services.

The Interface Layer SHALL NOT bypass the Application Layer to manipulate Domain objects directly.

---

# 9. Application Dependency

The Application Layer MAY depend upon:

- Domain;
- repository interfaces;
- domain services;
- domain events;
- infrastructure abstractions through dependency injection.

The Application Layer SHALL NOT depend upon:

- HTTP;
- controllers;
- serializers;
- Active Record models;
- presentation components.

---

# 10. Dependency Inversion

The platform SHALL employ dependency inversion where required.

High-level policy SHALL own abstractions.

Low-level implementation SHALL depend upon those abstractions.

Example:

```text
AssessmentRepository (Domain Interface)

▲

AssessmentRepositoryPostgres (Infrastructure Implementation)
```

The abstraction owns the contract.

The implementation fulfils the contract.

---

# 11. Circular Dependencies

Circular dependencies are prohibited.

Examples:

```text
Assessment

↓

Evaluation

↓

Assessment
```

is prohibited.

Dependency graphs SHALL remain acyclic.

Repository validation SHOULD automatically detect cycles.

---

# 12. Shared Dependencies

Shared libraries SHALL remain intentionally small.

Shared components MAY contain:

- utility abstractions;
- infrastructure helpers;
- common primitives.

Shared components SHALL NOT become repositories for unrelated business logic.

Large "common" modules are prohibited.

---

# 13. Third-Party Dependencies

Third-party libraries SHALL satisfy the following criteria before adoption.

They SHALL:

- solve a clearly defined problem;
- possess active maintenance;
- have acceptable licensing;
- have acceptable security posture;
- minimise transitive dependency growth.

Every significant dependency SHALL possess documented engineering justification.

---

# 14. Framework Dependencies

Rails SHALL remain an implementation dependency.

Business behaviour SHALL remain independent of Rails APIs wherever practical.

Framework upgrades SHOULD minimise Domain impact.

---

# 15. Runtime Dependencies

Runtime dependencies SHALL be explicit.

Hidden runtime behaviour is prohibited.

Examples include:

- implicit service discovery;
- global mutable state;
- uncontrolled singleton access.

Runtime behaviour SHALL remain predictable.

---

# 16. Dependency Injection

Dependencies SHALL normally be supplied through explicit injection.

Construction SHALL remain separate from behaviour.

Service location SHOULD be avoided except where justified by framework infrastructure.

---

# 17. External Systems

External systems SHALL be accessed through infrastructure adapters.

The Domain SHALL remain unaware of:

- REST;
- GraphQL;
- SMTP;
- Redis protocols;
- PostgreSQL drivers;
- cloud SDKs.

Technology SHALL terminate at the Infrastructure Layer.

---

# 18. AI Engineering

AI coding agents SHALL:

- preserve dependency direction;
- avoid introducing framework dependencies into the Domain;
- avoid circular dependencies;
- avoid bypassing architectural layers;
- introduce abstractions before implementations where required.

AI SHALL stop implementation if dependency ownership is unclear.

---

# 19. Review Checklist

Reviewers SHALL verify:

## Dependency Direction

- [ ] Dependencies point inward.
- [ ] Domain remains independent.
- [ ] Infrastructure depends upon abstractions.

---

## Architecture

- [ ] No circular dependencies.
- [ ] Layer boundaries preserved.
- [ ] Module boundaries respected.

---

## Maintainability

- [ ] Third-party dependencies justified.
- [ ] Shared components remain cohesive.
- [ ] Framework coupling minimised.

---

# 20. Anti-Patterns

The following practices are prohibited.

- Circular dependencies.
- Domain objects importing Rails components.
- Controllers accessing persistence directly.
- Infrastructure modifying Aggregate internals.
- Shared "utility" modules containing business logic.
- Service Locator as the default dependency mechanism.
- Hidden singleton dependencies.
- Global mutable application state.
- Framework annotations throughout the Domain Model.

---

# 21. Compliance

Every dependency introduced into the F1 platform SHALL comply with the rules defined in this chapter.

Dependency violations SHALL be treated as architectural defects and corrected before merge.

Maintaining correct dependency direction is fundamental to preserving long-term architectural integrity.

---

# Cross References

- EM-II-001 Architecture Philosophy
- EM-II-003 Rails 8 Application Structure
- EM-II-004 Layered Architecture
- EM-II-005 Domain-Driven Design
- EM-II-006 Module Boundaries
- EM-II-008 Service Architecture
- EM-II-015 Dependency Injection
- Product Specification
- Architectural Decision Records