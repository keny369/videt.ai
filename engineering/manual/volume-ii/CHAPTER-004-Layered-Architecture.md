# engineering/manual/volume-ii/CHAPTER-004-Layered-Architecture.md

---
title: Layered Architecture
identifier: EM-II-004
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 4 — Layered Architecture

## 1. Purpose

This chapter establishes the canonical layered architecture for the F1 platform.

The layered architecture exists to separate concerns, preserve business integrity and ensure that technology decisions remain independent of business behaviour.

Every implementation SHALL respect the architectural layers defined in this chapter.

---

# 2. Scope

This chapter governs:

- architectural layers;
- layer responsibilities;
- dependency direction;
- communication between layers;
- ownership of business logic;
- architectural boundaries.

Every software component SHALL belong to one—and only one—architectural layer.

---

# 3. Architectural Philosophy

The platform adopts a strict layered architecture.

Each layer exists to fulfil one engineering responsibility.

Layers SHALL collaborate only through explicitly defined contracts.

Layers SHALL NOT bypass intermediate layers unless explicitly authorised by an accepted ADR.

---

# 4. Canonical Layer Stack

The F1 platform SHALL comprise the following layers.

```
┌──────────────────────────────┐
│ Interface Layer              │
├──────────────────────────────┤
│ Application Layer            │
├──────────────────────────────┤
│ Domain Layer                 │
├──────────────────────────────┤
│ Infrastructure Layer         │
├──────────────────────────────┤
│ Persistence & External Systems│
└──────────────────────────────┘
```

The Domain Layer is the architectural centre.

---

# 5. Interface Layer

## Purpose

The Interface Layer adapts external requests into application commands and adapts application results into externally consumable responses.

### Responsibilities

The Interface Layer SHALL:

- receive requests;
- authenticate callers;
- authorise access;
- validate request structure;
- invoke Application Services;
- translate responses;
- map exceptions to transport-specific representations.

### It SHALL NOT:

- contain business rules;
- perform workflow orchestration;
- manipulate persistence;
- publish domain events;
- implement pricing or scoring.

Examples include:

- HTTP controllers;
- serializers;
- presenters;
- request validators;
- authentication adapters.

---

# 6. Application Layer

## Purpose

The Application Layer coordinates business use cases.

It orchestrates work.

It does not define business rules.

### Responsibilities

The Application Layer SHALL:

- coordinate workflows;
- invoke aggregates;
- invoke repositories;
- manage transactions;
- publish domain events;
- enforce application-level sequencing.

### It SHALL NOT:

- implement domain invariants;
- own business policy;
- contain infrastructure code;
- contain presentation logic.

---

# 7. Domain Layer

## Purpose

The Domain Layer contains the business model.

It is the most important architectural layer.

### Responsibilities

The Domain Layer SHALL contain:

- aggregates;
- entities;
- value objects;
- domain services;
- specifications;
- policies;
- repository interfaces;
- domain events.

The Domain SHALL define business behaviour.

### The Domain SHALL NOT depend upon:

- Rails;
- Active Record;
- Redis;
- HTTP;
- PostgreSQL;
- JSON;
- external APIs.

---

# 8. Infrastructure Layer

## Purpose

Infrastructure implements technical capabilities required by the Domain and Application layers.

### Responsibilities

Infrastructure SHALL provide:

- persistence implementations;
- Redis adapters;
- PostgreSQL adapters;
- Sidekiq integration;
- external APIs;
- file storage;
- telemetry;
- messaging;
- email delivery.

Infrastructure SHALL implement interfaces defined elsewhere.

Infrastructure SHALL NOT define business behaviour.

---

# 9. Persistence Layer

Persistence is treated as an infrastructure concern.

Responsibilities include:

- database access;
- schema evolution;
- indexing;
- transaction support;
- query execution.

Persistence SHALL remain invisible to the Domain.

---

# 10. Layer Communication

Permitted communication:

```
Interface

↓

Application

↓

Domain

↓

Infrastructure
```

Infrastructure MAY call external systems.

External systems SHALL NOT directly invoke the Domain.

---

# 11. Dependency Rule

Dependencies SHALL always point inward.

```
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

Infrastructure depends on Domain abstractions.

The Domain never depends on Infrastructure implementations.

---

# 12. Cross-Layer Communication

Direct communication between non-adjacent layers is prohibited.

Examples of prohibited interactions include:

- Controllers calling repositories directly.
- Infrastructure modifying aggregates directly.
- Domain invoking HTTP clients.
- Domain executing SQL.
- Serializers invoking persistence.

Cross-layer shortcuts create architectural coupling and SHALL NOT be introduced.

---

# 13. Layer Ownership

| Layer          | Owns                     |
| -------------- | ------------------------ |
| Interface      | Transport concerns       |
| Application    | Use-case orchestration   |
| Domain         | Business behaviour       |
| Infrastructure | Technical implementation |
| Persistence    | Data storage             |

Ownership SHALL remain exclusive.

---

# 14. Error Propagation

Errors SHALL propagate upward through architectural layers.

Each layer MAY translate errors into representations appropriate for its responsibility.

Examples:

- Domain → Domain exception.
- Application → Workflow failure.
- Interface → HTTP response.
- Infrastructure → Technical exception.

Business semantics SHALL originate within the Domain.

---

# 15. Transactions

Transaction boundaries SHALL normally be owned by the Application Layer.

The Domain SHALL remain unaware of transaction implementation.

Infrastructure SHALL execute transaction mechanics.

---

# 16. AI Engineering

AI coding agents SHALL:

- preserve layer boundaries;
- avoid dependency inversion violations;
- avoid cross-layer shortcuts;
- avoid placing business logic in Interface or Infrastructure layers;
- request clarification where ownership is uncertain.

---

# 17. Review Checklist

Reviewers SHALL verify:

## Layer Ownership

- [ ] Responsibility correctly assigned.
- [ ] Business logic located in Domain.
- [ ] Technical logic located in Infrastructure.

---

## Dependencies

- [ ] Dependency direction correct.
- [ ] No inward violations.
- [ ] No circular dependencies.

---

## Architecture

- [ ] Domain isolated.
- [ ] Framework leakage absent.
- [ ] Layer boundaries preserved.

---

# 18. Anti-Patterns

The following practices are prohibited.

- Fat controllers.
- Fat Active Record models.
- SQL inside Application Services.
- HTTP clients inside the Domain.
- Infrastructure modifying aggregates.
- Business logic inside serializers.
- Direct repository access from controllers.
- Cross-layer dependency shortcuts.
- Circular dependencies between layers.

---

# 19. Compliance

Every software component SHALL belong to one architectural layer and shall respect the dependency rules defined in this chapter.

Architectural exceptions require an approved ADR before implementation.

The layered architecture is mandatory and SHALL remain stable throughout the lifetime of the platform.

---

# Cross References

- EM-II-001 Architecture Philosophy
- EM-II-002 Repository Architecture
- EM-II-003 Rails 8 Application Structure
- EM-II-005 Domain-Driven Design
- EM-II-007 Dependency Rules
- EM-II-010 Transaction Boundaries
- Product Specification
- Architectural Decision Records