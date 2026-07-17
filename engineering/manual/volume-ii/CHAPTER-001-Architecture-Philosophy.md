---
title: Architecture Philosophy
identifier: EM-II-001
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 1 — Architecture Philosophy

## 1. Purpose

This chapter establishes the architectural philosophy governing every software component within the F1 platform.

Architecture is the translation layer between the Product Specification and executable software.

Its purpose is to ensure that implementation remains:

- faithful to the Specification;
- deterministic;
- maintainable;
- testable;
- observable;
- evolvable.

The architecture SHALL optimise long-term correctness over short-term implementation convenience.

---

# 2. Scope

This chapter governs:

- architectural principles;
- implementation philosophy;
- dependency direction;
- business logic ownership;
- framework usage;
- software boundaries;
- architectural decision making.

Every software component SHALL comply with these principles.

---

# 3. Architecture Objectives

The architecture SHALL achieve the following objectives.

## AP-001 — Specification Fidelity

The Product Specification defines behaviour.

Architecture exists solely to implement that behaviour.

Implementation SHALL NOT redefine product behaviour.

---

## AP-002 — Explicit Design

Software SHALL favour explicit engineering decisions over implicit framework conventions.

Engineering intent SHALL be visible from repository structure.

---

## AP-003 — Separation of Concerns

Every architectural component SHALL possess one primary responsibility.

Responsibilities SHALL remain clearly separated.

---

## AP-004 — Business Independence

Business rules SHALL remain independent of:

- Rails;
- PostgreSQL;
- Redis;
- Sidekiq;
- HTTP;
- JSON;
- external APIs.

Technology SHALL support the business model.

The business model SHALL never depend upon technology.

---

## AP-005 — Deterministic Behaviour

Identical inputs applied to identical business state SHALL produce identical outcomes.

Deterministic behaviour SHALL be preferred throughout the platform.

---

## AP-006 — Observable Systems

Every production behaviour SHALL be diagnosable using:

- logs;
- metrics;
- traces;
- audit evidence.

Architecture SHALL support observability from inception.

---

# 4. Architectural Principles

The following principles govern all implementation.

---

## Principle 1

Business behaviour SHALL originate only from the Product Specification.

---

## Principle 2

Architecture SHALL preserve Specification authority.

Implementation SHALL never invent behaviour.

---

## Principle 3

Business rules SHALL exist exactly once.

Duplicate implementations are prohibited.

---

## Principle 4

Dependencies SHALL point inward.

Outer layers depend upon inner layers.

Inner layers SHALL remain independent.

---

## Principle 5

Frameworks are replaceable.

The business model SHALL remain largely unaffected by framework replacement.

---

## Principle 6

Infrastructure is an implementation concern.

Infrastructure SHALL never own business behaviour.

---

## Principle 7

Architecture SHALL minimise coupling.

Components SHALL interact only through explicitly defined contracts.

---

## Principle 8

Every architectural decision SHALL improve maintainability.

Short-term convenience SHALL NOT justify permanent architectural degradation.

---

# 5. Architectural Layers

The platform SHALL comprise the following logical layers.

```
Presentation

↓

Application

↓

Domain

↓

Infrastructure

↓

Persistence
```

Responsibility SHALL flow downward.

Dependencies SHALL flow inward.

Business rules SHALL reside in the Domain Layer.

---

# 6. Domain First

The Domain Layer is the architectural centre of the platform.

Everything else exists to support it.

The Domain SHALL contain:

- business rules;
- invariants;
- workflows;
- aggregate behaviour;
- domain services;
- domain events.

The Domain SHALL NOT contain framework-specific implementation.

---

# 7. Framework Philosophy

Rails is an implementation framework.

Rails SHALL provide:

- routing;
- controllers;
- persistence adapters;
- dependency wiring;
- configuration;
- bootstrapping.

Rails SHALL NOT define business behaviour.

Framework conventions SHALL be overridden whenever necessary to preserve architectural clarity.

---

# 8. Simplicity

Architecture SHALL favour simplicity.

Simple architecture is characterised by:

- explicit dependencies;
- understandable modules;
- minimal abstraction;
- coherent responsibilities;
- low cognitive load.

Complexity SHALL require engineering justification.

---

# 9. Evolution

Architecture SHALL support controlled evolution.

Evolution SHALL occur through:

- Product Specification;
- Engineering Manual;
- ADRs;
- repository governance.

Implementation SHALL evolve deliberately rather than organically.

---

# 10. AI Engineering

AI coding agents SHALL:

- derive implementation from repository authorities;
- preserve architectural boundaries;
- avoid introducing alternative patterns;
- stop when architectural authority is unclear.

AI SHALL NOT optimise architecture independently.

---

# 11. Review Checklist

Reviewers SHALL verify:

## Authority

- [ ] Behaviour originates from the Product Specification.
- [ ] Architecture complies with accepted ADRs.
- [ ] Engineering Manual standards followed.

---

## Architecture

- [ ] Responsibilities clearly separated.
- [ ] Dependencies correct.
- [ ] Domain isolated.
- [ ] Infrastructure independent.
- [ ] No framework leakage.

---

## Quality

- [ ] Architecture simplified where possible.
- [ ] Coupling minimised.
- [ ] Observability preserved.
- [ ] Maintainability improved.

---

# 12. Anti-Patterns

The following practices are prohibited.

- Framework-first architecture.
- Business logic inside controllers.
- Business logic inside models solely because Rails permits it.
- Infrastructure depending upon presentation.
- Domain depending upon infrastructure.
- Hidden architectural dependencies.
- Multiple implementations of identical business rules.
- Framework conventions overriding repository authority.

---

# 13. Compliance

Every software component SHALL comply with this architectural philosophy.

Architectural departures require an approved ADR before implementation.

The architecture exists to faithfully realise the Product Specification—not to reinterpret it.

---

# Cross References

- Engineering Manual Volume I
- EM-II-002 Repository Architecture
- EM-II-004 Layered Architecture
- EM-II-005 Domain-Driven Design
- EM-II-007 Dependency Rules
- Product Specification
- Architectural Decision Records
