---
title: Module Boundaries
identifier: EM-II-006
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 6 — Module Boundaries

## 1. Purpose

This chapter defines the canonical module boundaries used throughout the F1 platform.

Modules are the primary organisational units of the implementation architecture.

Each module represents a cohesive area of business capability with clearly defined responsibilities, ownership and interfaces.

The purpose of module boundaries is to minimise coupling while maximising cohesion, maintainability and independent evolution.

---

# 2. Scope

This chapter governs:

- module definition;
- module ownership;
- module interaction;
- dependency boundaries;
- public interfaces;
- internal implementation;
- shared functionality.

Every implementation component SHALL belong to one—and only one—module.

---

# 3. Architectural Philosophy

Modules exist to organise business capability rather than technical functionality.

A module SHALL encapsulate everything required to implement one coherent responsibility.

Modules SHALL communicate through explicit contracts.

Modules SHALL NOT expose internal implementation details.

---

# 4. Module Characteristics

Every module SHALL possess:

- a clearly defined business purpose;
- a bounded public interface;
- private internal implementation;
- explicit ownership;
- independent testability;
- minimal external dependencies.

Modules SHALL remain understandable in isolation.

---

# 5. Module Ownership

Each module SHALL have one engineering owner.

Ownership includes responsibility for:

- correctness;
- architectural integrity;
- documentation;
- testing;
- evolution;
- operational quality.

Ownership SHALL remain independent of individual personnel.

---

# 6. Public Interfaces

Every module SHALL expose only those interfaces required by other modules.

Public interfaces MAY include:

- commands;
- queries;
- domain events;
- repository interfaces;
- service interfaces.

Implementation classes SHALL remain private.

Modules SHALL expose behaviour rather than implementation.

---

# 7. Internal Implementation

Internal implementation SHALL remain invisible outside the module.

Examples include:

- helper classes;
- validation logic;
- private policies;
- implementation services;
- persistence mappings.

External modules SHALL NOT depend upon internal implementation.

---

# 8. Module Dependencies

Modules SHALL depend only upon:

- the Domain Layer;
- published module interfaces;
- approved shared infrastructure.

Modules SHALL NOT depend upon:

- another module's private implementation;
- another module's database schema;
- another module's internal services.

---

# 9. Cross-Module Communication

Modules SHALL communicate through one of the following mechanisms:

## Commands

Where immediate business behaviour is required.

---

## Queries

Where information is required.

Queries SHALL NOT modify business state.

---

## Domain Events

Where completed business occurrences are communicated.

Events SHALL remain immutable.

---

## Repository Interfaces

Where persistence abstractions are required.

Repository implementations SHALL remain private.

---

# 10. Shared Functionality

Shared functionality SHALL be introduced only when:

- duplication is demonstrably harmful;
- ownership cannot reasonably belong to one module;
- the abstraction is stable.

Shared modules SHALL remain intentionally small.

Premature shared abstractions are prohibited.

---

# 11. Module Lifecycle

Modules SHOULD evolve independently.

Changes within one module SHOULD minimise impact upon unrelated modules.

Module boundaries SHALL support long-term maintainability.

---

# 12. Cyclic Dependencies

Circular module dependencies are prohibited.

The dependency graph SHALL remain acyclic.

Example:

```
ModuleA

↓

ModuleB

↓

ModuleC
```

NOT

```
ModuleA

↓

ModuleB

↓

ModuleA
```

Repository validation SHOULD detect dependency cycles automatically.

---

# 13. Business Capability Alignment

Modules SHOULD align with Product Specification capabilities.

Examples include:

- Organizations
- Projects
- Evaluations
- Evidence
- Issues
- Notifications
- Billing
- Identity
- Search

Module names SHALL reflect business language.

---

# 14. Module Size

Modules SHOULD remain cohesive.

Indicators that a module has become too large include:

- unrelated responsibilities;
- frequent cross-module changes;
- excessive public interfaces;
- numerous internal dependencies.

Large modules SHOULD be decomposed through architectural review.

---

# 15. AI Engineering

AI coding agents SHALL:

- preserve module boundaries;
- avoid introducing cross-module shortcuts;
- avoid exposing private implementation;
- place new behaviour within the correct business module;
- request clarification where ownership is ambiguous.

AI SHALL NOT create new modules without architectural authority.

---

# 16. Review Checklist

Reviewers SHALL verify:

## Ownership

- [ ] Module responsibility clearly defined.
- [ ] Ownership appropriate.
- [ ] Business capability correctly represented.

---

## Boundaries

- [ ] Public interface minimal.
- [ ] Internal implementation hidden.
- [ ] No private dependency leakage.

---

## Dependencies

- [ ] No circular dependencies.
- [ ] Dependency direction preserved.
- [ ] Shared abstractions justified.

---

## Maintainability

- [ ] Module cohesive.
- [ ] Module understandable.
- [ ] Business terminology preserved.

---

# 17. Anti-Patterns

The following practices are prohibited.

- Circular module dependencies.
- Shared utility modules containing unrelated behaviour.
- Cross-module database access.
- Cross-module manipulation of Aggregate internals.
- Large "common" libraries containing business logic.
- Public exposure of implementation classes.
- Technology-oriented module naming.
- Creating modules solely to mirror Rails directories.

---

# 18. Compliance

Every implementation SHALL respect the module boundaries defined by this chapter.

New modules require architectural review.

Significant boundary changes SHALL require an approved ADR.

Module boundaries are a primary architectural control and SHALL remain stable throughout the lifetime of the platform.

---

# Cross References

- EM-II-001 Architecture Philosophy
- EM-II-004 Layered Architecture
- EM-II-005 Domain-Driven Design
- EM-II-007 Dependency Rules
- EM-II-008 Service Architecture
- Product Specification
- Architectural Decision Records
