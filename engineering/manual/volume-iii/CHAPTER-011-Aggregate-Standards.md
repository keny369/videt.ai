---
title: Aggregate Standards
identifier: EM-III-011
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 11 — Aggregate Standards

## 1. Purpose

This chapter defines the mandatory engineering standards governing Aggregate implementation within the F1 platform.

Aggregates are the primary consistency boundary within the Domain Model.

They protect business invariants, coordinate Entity collaboration and define transactional consistency.

Every Aggregate SHALL comply with these standards.

---

# 2. Scope

This chapter governs:

- Aggregate Roots;
- Aggregate boundaries;
- consistency;
- transactional behaviour;
- Entity ownership;
- invariants;
- persistence;
- collaboration.

These standards apply exclusively to the Domain Layer.

---

# 3. Engineering Philosophy

An Aggregate represents a business consistency boundary.

Everything inside an Aggregate SHALL remain internally consistent.

Everything outside the Aggregate SHALL interact only through its Aggregate Root.

The Aggregate is the unit of transactional consistency.

---

# 4. Aggregate Root

Every Aggregate SHALL possess one Aggregate Root.

The Aggregate Root SHALL:

- expose the public business interface;
- protect business invariants;
- coordinate internal Entities;
- create Domain Events where appropriate.

External components SHALL communicate exclusively with the Aggregate Root.

---

# 5. Aggregate Boundaries

Aggregate boundaries SHALL be determined by business consistency requirements rather than database structure.

Aggregates SHALL remain:

- cohesive;
- self-contained;
- understandable;
- independently consistent.

Boundaries SHALL be intentionally designed.

---

# 6. Consistency

Every business invariant within an Aggregate SHALL be preserved before transaction completion.

The examples below use a fictional `Shipment` Aggregate from an unrelated domain, so that the pattern is illustrated without implying an F1 business rule:

- a Shipment cannot simultaneously be Dispatched and Cancelled;
- a Shipment cannot be delivered before it is dispatched.

The Aggregate Root SHALL enforce these rules.

An F1 invariant SHALL be implemented only where an accepted authority states it. Canonical F1 states and permitted transitions are owned by `specification/016 STATE_MODEL.md`, and the invariants that bind them are owned by the Volume I product rules. This manual SHALL NOT state, infer or illustrate an F1 business rule that no accepted authority defines.

---

# 7. Transactions

A single business transaction SHOULD normally modify one Aggregate.

Where multiple Aggregates participate in one workflow:

- orchestration SHALL occur in the Application Layer;
- eventual consistency SHOULD be preferred;
- transaction scope SHALL remain minimal.

Aggregates SHALL NOT coordinate distributed transactions.

---

# 8. Entity Ownership

Entities contained within an Aggregate SHALL not be modified directly by external callers.

Example:

```ruby
shipment.dispatch!
```

is valid.

Direct modification of child entities from outside the Aggregate is prohibited.

The Aggregate Root SHALL coordinate internal state changes.

---

# 9. References Between Aggregates

Aggregates SHOULD reference other Aggregates by identity rather than object reference.

Preferred:

```ruby
project_id
```

Not:

```ruby
project
```

This preserves independence and reduces coupling.

---

# 10. Aggregate Size

Aggregates SHOULD remain small.

Indicators that an Aggregate has become too large include:

- numerous unrelated responsibilities;
- excessive child entities;
- long transaction duration;
- high concurrency conflicts.

Large Aggregates SHALL be reviewed for decomposition.

---

# 11. Persistence

Repositories SHALL persist Aggregates atomically.

External components SHALL NOT persist individual internal Entities independently.

Aggregate persistence SHALL preserve consistency.

---

# 12. Domain Events

Aggregate Roots MAY create Domain Events.

Events SHALL describe completed business facts.

Event publication SHALL occur only after successful transaction commit.

Aggregate internals SHALL not publish events directly.

---

# 13. Lifecycle

Every Aggregate SHALL possess an explicit lifecycle where applicable.

Example:

```text
Created

↓

Dispatched

↓

Delivered
```

Lifecycle transitions SHALL be performed through business methods.

This is the fictional `Shipment` shape. An F1 Aggregate lifecycle SHALL be taken from `specification/016 STATE_MODEL.md`, which owns every F1 state and permitted transition.

---

# 14. Collaboration

Aggregates SHALL collaborate through:

- Application Services;
- Domain Services;
- Domain Events.

Aggregates SHALL NOT directly manipulate the internal state of other Aggregates.

---

# 15. Concurrency

Concurrency SHALL be managed at the Aggregate boundary.

Optimistic concurrency SHALL normally be preferred.

Conflict detection SHALL occur before transaction commit.

Business invariants SHALL never be compromised by concurrent execution.

---

# 16. Testing

Every Aggregate SHALL possess tests covering:

- creation;
- lifecycle transitions;
- invariants;
- concurrency behaviour;
- Domain Event creation;
- failure scenarios.

Aggregate behaviour SHALL remain deterministic.

---

# 17. AI Engineering

AI coding agents SHALL:

- preserve Aggregate boundaries;
- prevent direct Entity manipulation;
- enforce invariants within Aggregate Roots;
- minimise Aggregate size;
- preserve transactional consistency.

AI SHALL NOT create cross-Aggregate business coupling.

---

# 18. Review Checklist

Reviewers SHALL verify:

## Architecture

- [ ] Aggregate Root present.
- [ ] Boundary well defined.
- [ ] Consistency preserved.

---

## Behaviour

- [ ] Invariants enforced.
- [ ] Lifecycle explicit.
- [ ] Events created correctly.

---

## Maintainability

- [ ] Aggregate appropriately sized.
- [ ] External references by identity.
- [ ] Repository persistence atomic.

---

# 19. Anti-Patterns

The following practices are prohibited.

- Direct modification of child Entities.
- Cross-Aggregate transactions without justification.
- Large "God Aggregates."
- External persistence of internal Entities.
- Aggregate references through mutable object graphs.
- Business invariants outside the Aggregate.
- Infrastructure dependencies within Aggregates.
- Domain Events published directly from infrastructure.

---

# 20. Compliance

Every Aggregate SHALL comply with these standards.

Aggregates define the consistency model of the platform and are therefore fundamental to business correctness.

Architectural deviations require an approved ADR before implementation.

---

# Cross References

- EM-II-005 Domain-Driven Design
- EM-II-010 Transaction Boundaries
- EM-II-011 Persistence Architecture
- EM-III-010 Entity Standards
- EM-III-012 Domain Service Standards
- Product Specification
- Architectural Decision Records
