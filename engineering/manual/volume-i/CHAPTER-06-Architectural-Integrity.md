---
title: Architectural Integrity
identifier: EM-I-006
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 6 — Architectural Integrity

## 1. Purpose

The long-term value of the F1 platform depends not only upon implementing the Product Specification correctly, but upon preserving the integrity of the architecture over time.

This chapter defines the engineering standards that prevent architectural drift, uncontrolled complexity and erosion of design quality.

Architectural integrity SHALL be treated as a continuous engineering responsibility rather than a one-time design activity.

---

# 2. Scope

This chapter governs:

- application architecture;
- domain modelling;
- service boundaries;
- infrastructure boundaries;
- dependency management;
- software composition;
- refactoring;
- architectural evolution.

It applies equally to new implementation and modification of existing components.

---

# 3. Definition

Architectural integrity is the continued alignment between:

- the Product Specification;
- the Engineering Manual;
- Architectural Decision Records;
- source code;
- operational behaviour.

An implementation possesses architectural integrity when every significant design decision can be traced to an approved architectural authority.

---

# 4. Architectural Objectives

Engineering SHALL preserve:

- clarity;
- cohesion;
- determinism;
- consistency;
- traceability;
- maintainability;
- evolvability.

No implementation convenience SHALL justify degradation of these objectives.

---

# 5. Architectural Boundaries

The platform SHALL be organised into clearly defined layers.

A simplified dependency hierarchy is:

```
Presentation

↓

Application

↓

Domain

↓

Infrastructure
```

Dependencies SHALL flow downward only.

Lower layers SHALL NOT depend upon higher layers.

---

# 6. Layer Responsibilities

## Presentation Layer

Responsible for:

- HTTP transport;
- API serialization;
- request validation;
- response generation.

The Presentation Layer SHALL NOT contain business rules.

---

## Application Layer

Responsible for:

- orchestration;
- command execution;
- transaction boundaries;
- workflow coordination.

The Application Layer SHALL NOT implement business policy.

---

## Domain Layer

Responsible for:

- business rules;
- invariants;
- aggregate behaviour;
- state transitions.

Business behaviour SHALL exist here unless explicitly defined otherwise.

---

## Infrastructure Layer

Responsible for:

- persistence;
- messaging;
- external systems;
- storage;
- networking.

Infrastructure SHALL implement technical capabilities.

Infrastructure SHALL NOT define business behaviour.

---

# 7. Dependency Rules

Dependencies SHALL satisfy the following principles.

## DR-001

Presentation MAY depend upon Application.

---

## DR-002

Application MAY depend upon Domain.

---

## DR-003

Infrastructure MAY depend upon Domain contracts.

---

## DR-004

Domain SHALL NOT depend upon infrastructure implementation.

---

## DR-005

Circular dependencies are prohibited.

---

## DR-006

Cross-layer shortcuts are prohibited.

Example:

Presentation directly querying PostgreSQL.

This violates architectural integrity.

---

# 8. Architectural Drift

Architectural drift occurs when implementation gradually departs from the approved architecture without explicit governance.

Examples include:

- duplicated business rules;
- infrastructure-aware domain models;
- controller-centric business logic;
- service-layer bypasses;
- undocumented integration paths;
- hidden shared state.

Architectural drift SHALL be treated as a repository defect.

---

# 9. Refactoring

Refactoring SHALL preserve externally observable behaviour.

Acceptable refactoring includes:

- reducing duplication;
- improving readability;
- simplifying dependencies;
- improving modularity;
- improving performance without behavioural change.

Refactoring SHALL NOT introduce new product behaviour.

Behavioural changes require Specification authority.

---

# 10. Architectural Evolution

Architecture SHALL evolve deliberately.

Changes affecting:

- domain boundaries;
- aggregate ownership;
- persistence model;
- messaging model;
- workflow structure;
- public APIs;
- security architecture;

require governance through the ADR process.

---

# 11. Design Review

Major implementation work SHALL include an architectural review.

The review SHALL evaluate:

- layer boundaries;
- dependency direction;
- module cohesion;
- coupling;
- scalability;
- observability;
- security;
- maintainability.

Review findings SHALL be recorded.

---

# 12. Technical Debt

Architectural shortcuts SHALL be considered technical debt.

Every architectural debt item SHALL identify:

- description;
- rationale;
- impact;
- owner;
- remediation strategy;
- review date.

Undocumented architectural debt is prohibited.

---

# 13. AI Engineering

AI coding agents SHALL preserve architectural integrity.

An AI agent SHALL NOT:

- invent architectural layers;
- introduce alternative patterns;
- bypass workflow services;
- duplicate Specification behaviour;
- relocate business rules across architectural boundaries.

Where uncertainty exists, the AI SHALL stop and report the ambiguity rather than selecting an implementation independently.

---

# 14. Review Checklist

Every architectural review SHALL confirm:

- Layer boundaries are preserved.
- Dependency direction is correct.
- No circular dependencies exist.
- Business rules remain in the Domain Layer.
- Infrastructure concerns remain isolated.
- Architectural drift has not occurred.
- Public behaviour remains Specification-compliant.
- Architectural changes reference approved ADRs.
- Documentation reflects implementation.

---

# 15. Compliance

Compliance with this chapter is mandatory.

Any implementation found to violate architectural integrity SHALL be corrected before merge unless an explicit ADR authorises the departure.

Repeated violations SHALL trigger an architecture review of the affected subsystem.

---

# Cross References

- EM-I-001 Engineering Philosophy
- EM-I-002 Engineering Objectives
- EM-I-003 Authority Hierarchy
- EM-I-005 Engineering Principles
- EM-I-012 Architectural Decision Records
- Volume II — Rails 8 Architecture Standards
- Volume III — Domain Model & Workflow Engine
- Product Specification
