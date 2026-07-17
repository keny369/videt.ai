---
title: Appendix F — Engineering Glossary
identifier: EM-I-APP-F
version: 1.0
status: Normative
owner: Engineering Governance
---

# Appendix F — Engineering Glossary

## Purpose

This glossary establishes the canonical meaning of engineering terminology used throughout the Engineering Manual.

The purpose of the glossary is to ensure that engineers, reviewers, architects and AI coding agents interpret engineering terminology consistently.

Where terminology differs between common industry usage and the F1 Engineering Manual, **this glossary SHALL prevail**.

---

# A

## Aggregate

A consistency boundary within the Domain Model responsible for protecting business invariants.

Only the Aggregate Root MAY modify Aggregate state.

---

## Aggregate Root

The single entry point through which an Aggregate is modified.

---

## API Contract

The authoritative definition of an externally exposed interface.

API contracts define observable behaviour.

Implementations SHALL conform to the contract.

---

## Architectural Decision Record (ADR)

A permanent engineering record documenting a significant architectural decision, its rationale, alternatives and consequences.

---

## Architectural Drift

Gradual divergence between the implemented architecture and the approved architectural design.

Architectural drift is considered an engineering defect.

---

# B

## Behaviour

An externally observable action or outcome defined by the Product Specification.

Behaviour SHALL originate from the Specification rather than implementation.

---

## Bounded Context

A logical boundary within which terminology, behaviour and models possess one consistent meaning.

---

## Branch

A temporary line of repository development used to isolate engineering work.

---

## Business Rule

A rule governing product behaviour.

Business rules SHALL have exactly one canonical owner.

---

# C

## Canonical

The single authoritative definition.

Where multiple descriptions exist, one SHALL be designated canonical.

---

## Capability

A significant business function defined within the Product Specification.

Capabilities are implemented through workflows and supporting engineering components.

---

## CI/CD

Continuous Integration and Continuous Delivery (or Deployment).

The automated process responsible for validating and delivering engineering changes.

---

## Code Review

A structured engineering review performed before repository integration.

---

## Component

A coherent engineering unit responsible for one primary responsibility.

---

## Concurrency

The execution of multiple operations over overlapping periods of time.

Concurrency controls preserve correctness under simultaneous execution.

---

# D

## Definition of Done (DoD)

The mandatory criteria that engineering work must satisfy before completion.

---

## Definition of Ready (DoR)

The mandatory criteria that engineering work must satisfy before implementation begins.

---

## Dependency

A relationship in which one engineering component requires another.

Dependencies SHALL follow approved architectural direction.

---

## Deterministic

Producing the same result from the same inputs and state.

Deterministic behaviour is preferred throughout the platform.

---

## Domain

The engineering representation of business concepts and business rules.

---

## Domain Event

An immutable record that a significant business event has occurred.

Domain events SHALL be owned by the Product Specification.

---

# E

## Engineering Manual

The authoritative implementation standard governing software development within the F1 platform.

---

## Engineering Governance

The processes and standards ensuring engineering consistency, quality and architectural integrity.

---

## Engineering Standard

A mandatory implementation rule defined by the Engineering Manual.

---

# F

## Feature

A coherent unit of product functionality.

---

## Framework

A software platform providing reusable implementation capabilities.

Framework conventions SHALL NOT override Product Specification behaviour.

---

# G

## Governance

The collection of rules controlling engineering decisions and repository evolution.

---

# H

## Hotfix

A production correction addressing an urgent defect.

Hotfixes remain subject to engineering governance.

---

# I

## Implementation

The source code realising the Product Specification.

Implementation SHALL NOT redefine behaviour.

---

## Infrastructure

Technical services supporting the application, including persistence, networking and external integrations.

---

## Invariant

A business rule that must always remain true.

Aggregates are responsible for enforcing invariants.

---

# L

## Layer

A distinct architectural level with defined responsibilities.

Dependencies SHALL flow downward only.

---

## Logging

Structured operational evidence produced during execution.

Logging SHALL support diagnosis without changing production code.

---

# M

## Migration

A controlled modification to persistent storage structures.

---

## Monitoring

The continuous observation of operational health.

---

# O

## Observability

The ability to understand system behaviour through logs, metrics, traces and audit evidence.

---

## Owner Decision (OD)

A formally approved product decision integrated into its canonical owner.

Owner Decisions SHALL NOT exist solely as standalone documents.

---

# P

## Product Specification

The highest engineering authority defining required product behaviour.

---

## Pull Request (PR)

The formal engineering review unit through which repository changes are evaluated before integration.

---

# Q

## Quality Gate

A mandatory checkpoint that engineering work must satisfy before progressing to the next lifecycle stage.

---

# R

## Refactoring

Modification of implementation while preserving externally observable behaviour.

---

## Repository

The version-controlled collection of all engineering artefacts.

---

## Requirement

A mandatory statement describing required product or engineering behaviour.

---

## Risk

A potential event capable of negatively affecting engineering, operational or business outcomes.

---

# S

## Service

An implementation component responsible for performing one coherent responsibility.

---

## Source of Truth

The authoritative repository location for a specific engineering concept.

Only one canonical source SHALL exist.

---

## Specification

The Product Specification governing required platform behaviour.

---

## State Model

The authoritative model describing valid lifecycle states and transitions.

---

# T

## Technical Debt

A documented engineering compromise accepted with full understanding of its future maintenance cost.

---

## Traceability

The ability to connect requirements, implementation, testing and operational behaviour through authoritative references.

---

## Transaction

A unit of work executed atomically.

Transactions SHALL preserve data integrity.

---

# V

## Validation

Objective verification that engineering work satisfies defined standards.

---

## Version

A formally identified repository milestone representing a stable engineering state.

---

## Workflow

A defined sequence of business operations implementing a capability.

Workflows SHALL be governed by the Product Specification.

---

# Glossary Governance

New engineering terminology SHALL be added through the Engineering Manual governance process.

Existing definitions SHALL remain stable unless superseded by an approved revision.

Where uncertainty exists regarding terminology, this glossary SHALL be treated as authoritative.

---

# Cross References

- EM-I-003 Authority Hierarchy
- EM-I-004 Normative Language
- EM-I-014 Documentation Standards
- Product Specification
- Architectural Decision Records
