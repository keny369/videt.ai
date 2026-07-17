# engineering/manual/volume-iii/CHAPTER-010-Entity-Standards.md

---
title: Entity Standards
identifier: EM-III-010
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 10 — Entity Standards

## 1. Purpose

This chapter defines the mandatory engineering standards governing Entity implementation within the F1 platform.

Entities represent business concepts that possess a persistent identity throughout their lifecycle.

Unlike Value Objects, Entities are defined by **who they are**, not merely by the values they contain.

Entities SHALL model enduring business concepts while preserving business invariants and architectural integrity.

---

# 2. Scope

This chapter governs:

- Entity implementation;
- identity;
- lifecycle;
- state mutation;
- encapsulation;
- invariants;
- collaboration;
- persistence boundaries.

These standards apply exclusively to the Domain Layer.

---

# 3. Engineering Philosophy

Entities model business reality.

An Entity persists even as its attributes change.

Identity is permanent.

State is transient.

Business behaviour SHALL remain inside the Entity wherever that behaviour naturally belongs.

---

# 4. Characteristics

Every Entity SHALL possess:

- a unique identity;
- a business lifecycle;
- encapsulated state;
- business behaviour;
- invariant enforcement.

Entities SHALL NOT exist merely as data containers.

---

# 5. Identity

Identity SHALL be immutable.

Examples include:

- OrganisationId
- ProjectId
- AssessmentId
- EvaluationId
- IssueId

Identity SHALL survive:

- persistence;
- serialization;
- deployment;
- process restart.

Identity SHALL never change after creation.

---

# 6. State

Entity state MAY change.

State transitions SHALL occur only through explicit business behaviour.

Examples:

```ruby
assessment.complete!

project.archive!

organisation.reactivate!
```

Direct public mutation is prohibited.

---

# 7. Business Behaviour

Entities SHALL own behaviour directly related to their business responsibility.

Examples:

```ruby
Assessment#complete!

Issue#close!

Project#archive!
```

Behaviour SHALL preserve business invariants.

---

# 8. Invariants

Entities SHALL prevent invalid state transitions.

Invariant enforcement SHALL occur before state mutation.

Examples include:

- completed Assessments cannot restart;
- archived Projects cannot accept new Assessments;
- expired Role Assignments cannot grant authority.

Invalid transitions SHALL fail immediately.

---

# 9. Encapsulation

Internal state SHALL remain private.

External collaborators SHALL interact through business methods.

Public attribute mutation is prohibited.

Example:

Preferred:

```ruby
assessment.complete!
```

Not:

```ruby
assessment.status = "completed"
```

---

# 10. Equality

Entity equality SHALL be based upon identity.

Example:

```ruby
Assessment(id: 123)
```

equals

```ruby
Assessment(id: 123)
```

even if non-identity attributes differ.

Attribute equality belongs to Value Objects.

---

# 11. Collaboration

Entities MAY collaborate with:

- Value Objects;
- Domain Services;
- other Entities through Aggregate boundaries.

Entities SHALL NOT manipulate the internal state of unrelated Entities.

Collaboration SHALL preserve encapsulation.

---

# 12. Persistence

Entities SHALL remain persistence-independent.

Repositories SHALL persist Entities.

Entities SHALL NOT:

- execute SQL;
- inherit Active Record;
- reference persistence infrastructure.

Persistence belongs to Infrastructure.

---

# 13. Lifecycle

Every Entity SHALL possess a clearly defined lifecycle.

Examples include:

```text
Created

↓

Active

↓

Suspended

↓

Archived
```

Lifecycle transitions SHALL be explicit.

Hidden lifecycle changes are prohibited.

---

# 14. Construction

Entities SHALL be created only in valid states.

Construction SHALL establish required invariants.

Invalid Entities SHALL NOT exist.

Complex creation MAY be delegated to factories.

---

# 15. Events

Entities MAY create Domain Events.

Entities SHALL NOT publish them.

Publication remains the responsibility of the Application and Infrastructure layers.

---

# 16. Testing

Every Entity SHALL possess tests covering:

- creation;
- lifecycle;
- invariants;
- behaviour;
- equality;
- failure conditions.

Entity behaviour SHALL remain deterministic.

---

# 17. AI Engineering

AI coding agents SHALL:

- preserve Entity identity;
- encapsulate state;
- place business behaviour within Entities;
- preserve invariants;
- avoid anemic Domain Models.

AI SHALL NOT expose mutable Entity state.

---

# 18. Review Checklist

Reviewers SHALL verify:

## Identity

- [ ] Immutable identity.
- [ ] Equality by identity.
- [ ] Lifecycle defined.

---

## Behaviour

- [ ] Business behaviour encapsulated.
- [ ] Invariants enforced.
- [ ] Public mutation absent.

---

## Architecture

- [ ] Persistence independent.
- [ ] No framework leakage.
- [ ] Collaboration appropriate.

---

# 19. Anti-Patterns

The following practices are prohibited.

- Anemic Entities.
- Public mutable attributes.
- Business logic in repositories.
- Active Record as the Domain Entity.
- Equality based upon mutable attributes.
- Hidden lifecycle transitions.
- Infrastructure dependencies.
- Direct SQL.
- Generic Entity base classes containing business logic.

---

# 20. Compliance

Every Entity SHALL comply with these standards.

Entities form the foundation of the Domain Model and SHALL faithfully represent enduring business concepts throughout the lifetime of the platform.

---

# Cross References

- EM-II-005 Domain-Driven Design
- EM-II-010 Transaction Boundaries
- EM-III-004 Class Design Standards
- EM-III-009 Value Object Standards
- EM-III-011 Aggregate Standards
- Product Specification
- Architectural Decision Records