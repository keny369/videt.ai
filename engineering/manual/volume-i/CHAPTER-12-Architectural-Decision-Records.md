---
title: Architectural Decision Records
identifier: EM-I-012
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 12 — Architectural Decision Records (ADRs)

## 1. Purpose

Architectural Decision Records (ADRs) provide the permanent engineering record of significant architectural decisions made throughout the lifecycle of the F1 platform.

The purpose of an ADR is not merely to document what decision was made.

Its purpose is to preserve:

- architectural intent;
- engineering rationale;
- alternatives considered;
- implementation consequences;
- future maintenance context.

An engineer SHALL be able to understand *why* an architectural decision exists years after the original implementation.

---

# 2. Scope

An ADR SHALL be created whenever a decision materially affects:

- system architecture;
- architectural boundaries;
- implementation patterns;
- persistence architecture;
- messaging;
- security architecture;
- deployment architecture;
- operational model;
- engineering governance.

Minor implementation decisions SHALL NOT require ADRs.

---

# 3. Relationship to the Product Specification

The Product Specification defines required behaviour.

An ADR defines engineering decisions supporting that behaviour.

An ADR SHALL NOT redefine product behaviour.

If an ADR implies behavioural change, the Product Specification SHALL be updated first or concurrently.

The Specification remains the higher authority.

---

# 4. ADR Lifecycle

Every ADR SHALL progress through the following lifecycle.

## Proposed

The problem has been identified.

No implementation SHALL depend upon a Proposed ADR.

---

## Under Review

Alternatives are being evaluated.

Engineering discussion SHALL remain evidence-based.

Implementation MAY proceed only where explicitly authorised.

---

## Accepted

The decision has been approved.

Implementation SHALL comply with the ADR.

---

## Superseded

A newer ADR replaces the decision.

The superseded ADR SHALL remain in the repository.

Repository history SHALL remain complete.

---

## Withdrawn

The proposal was rejected.

Withdrawn ADRs SHALL remain discoverable for historical context.

---

# 5. ADR Numbering

Every ADR SHALL possess a permanent identifier.

Example:

```
ADR-001

ADR-019

ADR-041
```

Identifiers SHALL NEVER be reused.

Deleted identifiers are prohibited.

---

# 6. ADR Structure

Every ADR SHALL contain the following sections.

## Metadata

- Identifier
- Title
- Status
- Date
- Owner
- Reviewers

---

## Context

Describe:

- the engineering problem;
- background;
- constraints;
- assumptions.

---

## Decision

State the approved decision unambiguously.

---

## Alternatives Considered

Document reasonable alternatives.

Each alternative SHALL explain:

- advantages;
- disadvantages;
- rejection rationale.

---

## Consequences

Describe:

- engineering impact;
- operational impact;
- migration impact;
- maintenance implications;
- risks.

---

## Cross References

Reference:

- Product Specification identifiers;
- Engineering Manual chapters;
- related ADRs;
- Owner Decisions.

---

# 7. Decision Criteria

Architectural decisions SHOULD consider:

- correctness;
- simplicity;
- maintainability;
- scalability;
- observability;
- security;
- operational cost;
- implementation complexity;
- future evolution.

Trade-offs SHALL be explicit.

---

# 8. Ownership

Every ADR SHALL have an identified owner.

The owner is responsible for:

- maintaining accuracy;
- coordinating updates;
- recording supersession;
- ensuring implementation alignment.

Ownership SHALL survive personnel changes.

---

# 9. Implementation

Implementation SHALL NOT diverge from an Accepted ADR.

Where implementation reveals deficiencies:

1. Stop.
2. Raise a revised ADR.
3. Review.
4. Approve.
5. Continue implementation.

Source code SHALL NOT silently redefine architectural decisions.

---

# 10. Supersession

Architecture evolves.

When an ADR becomes obsolete:

- create a successor ADR;
- reference the predecessor;
- preserve repository history;
- update cross references.

Historical ADRs SHALL remain immutable.

---

# 11. AI Engineering

AI coding agents SHALL:

- read applicable ADRs before implementation;
- preserve accepted architectural decisions;
- avoid introducing alternative architectural patterns;
- escalate ambiguity rather than inventing architecture.

AI SHALL NOT authorise architectural change.

---

# 12. Review Checklist

Reviewers SHALL verify:

- architectural problem clearly stated;
- decision unambiguous;
- alternatives evaluated;
- consequences documented;
- Product Specification alignment confirmed;
- Engineering Manual alignment confirmed;
- implementation impact identified;
- ownership recorded.

---

# 13. Anti-Patterns

The following practices are prohibited.

- ADRs created after implementation solely to justify decisions.
- Architectural changes without ADRs where required.
- Deleting superseded ADRs.
- Treating ADRs as informal notes.
- Recording implementation details instead of architectural decisions.
- Contradicting accepted ADRs in source code.

---

# 14. Compliance

Accepted ADRs are normative engineering artefacts.

Implementation SHALL comply with accepted ADRs until they are formally superseded.

Architectural changes lacking appropriate ADR governance SHALL NOT be merged.

---

# Cross References

- EM-I-003 Authority Hierarchy
- EM-I-005 Engineering Principles
- EM-I-006 Architectural Integrity
- EM-I-007 Repository Governance
- EM-I-016 Traceability
- Product Specification
