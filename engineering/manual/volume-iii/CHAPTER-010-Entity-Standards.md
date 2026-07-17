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

Canonical entity identities are named by DM-REQ-001 in `specification/011 DOMAIN_MODEL.md`. Examples include:

- OrganizationId
- ProjectId
- EvaluationId
- IssueId

An identity SHALL NOT be introduced for an entity that DM-REQ-001 does not define.

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

The examples in sections 6 through 10 use a fictional `Shipment` entity from an unrelated domain. They illustrate an engineering pattern only. They are deliberately not F1 entities, because an example naming a real transition would imply product behaviour this manual has no authority to establish. Canonical F1 states, transitions and their command authority are owned by `specification/016 STATE_MODEL.md` and the Volume I workflow and permission contracts.

Examples:

```ruby
shipment.dispatch!

shipment.deliver!

shipment.cancel!
```

Direct public mutation is prohibited.

---

# 7. Business Behaviour

Entities SHALL own behaviour directly related to their business responsibility.

Examples:

```ruby
Shipment#dispatch!

Shipment#deliver!

Shipment#cancel!
```

Behaviour SHALL preserve business invariants.

An entity method SHALL NOT be introduced for an F1 transition that no accepted authority defines. Where a transition is named by the state model but its command authority is undefined or pending an Owner Decision, no entity method, service or route may be inferred, and the affected path SHALL remain unimplemented. Project pause, resume and archive are the current example: `specification/016 STATE_MODEL.md` names the transitions, Volume I defines no command for them, and OD-014 remains pending under `UPSTREAM-V1-PROJECT-LIFECYCLE-003`.

---

# 8. Invariants

Entities SHALL prevent invalid state transitions.

Invariant enforcement SHALL occur before state mutation.

Examples include:

- a delivered Shipment cannot be dispatched again;
- a cancelled Shipment cannot accept new items.

Invalid transitions SHALL fail immediately.

An F1 invariant SHALL be implemented only where an accepted authority states it. This manual SHALL NOT introduce a cross-entity business rule by example.

---

# 9. Encapsulation

Internal state SHALL remain private.

External collaborators SHALL interact through business methods.

Public attribute mutation is prohibited.

Example:

Preferred:

```ruby
shipment.dispatch!
```

Not:

```ruby
shipment.status = "dispatched"
```

---

# 10. Equality

Entity equality SHALL be based upon identity.

Example:

```ruby
Shipment(id: 123)
```

equals

```ruby
Shipment(id: 123)
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

The fictional `Shipment` lifecycle illustrates the shape only:

```text
Created

↓

Dispatched

↓

Delivered
```

Lifecycle transitions SHALL be explicit.

Hidden lifecycle changes are prohibited.

An F1 entity lifecycle SHALL be taken from `specification/016 STATE_MODEL.md` rather than from this example. The state model is the canonical owner of every F1 state, transition and terminal condition, and no state or edge may be inferred from the shape shown here.

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
