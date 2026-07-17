# engineering/manual/volume-iii/CHAPTER-013-Factory-Standards.md

---
title: Factory Standards
identifier: EM-III-013
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 13 — Factory Standards

## 1. Purpose

This chapter defines the mandatory engineering standards governing Factories within the F1 platform.

Factories encapsulate complex object construction.

Their purpose is to ensure that Domain objects are created in valid, consistent states while preventing construction complexity from leaking into business behaviour.

Factories SHALL create objects.

They SHALL NOT become business services.

---

# 2. Scope

This chapter governs:

- Factory classes;
- Aggregate creation;
- Entity creation;
- Value Object composition;
- complex object construction;
- initialization;
- dependency ownership.

These standards apply throughout the Domain and Application Layers.

---

# 3. Engineering Philosophy

Object construction is a distinct engineering concern.

Business behaviour belongs to Domain objects.

Construction complexity belongs to Factories.

Factories SHALL improve readability without weakening the Domain Model.

---

# 4. When Factories SHALL Be Used

Factories SHOULD be introduced when:

- Aggregate construction is complex;
- multiple Value Objects require coordination;
- business invariants must be established during creation;
- construction requires multiple collaborators;
- construction logic would otherwise obscure business behaviour.

Simple object creation SHALL NOT require a Factory.

---

# 5. Responsibilities

Factories SHALL:

- construct valid Domain objects;
- assemble required collaborators;
- establish initial invariants;
- encapsulate construction complexity.

Factories SHALL NOT:

- persist objects;
- own transactions;
- publish events;
- invoke infrastructure;
- execute workflows.

---

# 6. Aggregate Creation

Factories MAY create Aggregate Roots.

Example:

```ruby
AssessmentFactory.create(
  command
)
```

The resulting Aggregate SHALL already satisfy all mandatory invariants.

Factories SHALL NOT create partially valid Aggregates.

---

# 7. Entity Creation

Factories MAY create Entities where:

- construction is complex;
- identity generation requires coordination;
- multiple Value Objects participate.

Simple Entities SHOULD be created directly.

---

# 8. Value Object Composition

Factories MAY assemble multiple Value Objects into larger business structures.

Example:

```text
AssessmentFactory

↓

Assessment

↓

ConfidenceScore

AssessmentIdentifier

AssessmentStatus
```

Construction SHALL remain explicit.

---

# 9. Identity Generation

Identity generation MAY occur within Factories.

Identifiers SHALL:

- be immutable;
- be unique;
- possess no business meaning.

Identity strategy SHALL remain independent of persistence.

---

# 10. Validation

Factories SHALL verify construction preconditions.

Factories SHALL NOT duplicate ongoing business validation performed by Entities or Aggregates.

Construction validation ensures valid creation.

Business validation governs subsequent behaviour.

---

# 11. Dependencies

Factories SHALL receive dependencies explicitly.

Examples include:

- identifier generators;
- policy abstractions;
- Domain Services.

Factories SHALL NOT instantiate infrastructure directly.

---

# 12. Naming

Factory names SHALL describe the object constructed.

Examples:

```ruby
AssessmentFactory

ProjectFactory

EvaluationFactory
```

Generic names are prohibited.

Examples:

```ruby
Builder

Creator

Maker

Utility
```

---

# 13. Return Values

Factories SHALL return:

- one valid Domain object;
- one valid Aggregate;
- one valid Value Object.

Factories SHALL NOT return arbitrary collections unless construction explicitly requires them.

---

# 14. Persistence

Factories SHALL NOT save objects.

Persistence remains the responsibility of repositories.

Construction and persistence SHALL remain separate.

---

# 15. Testing

Every Factory SHALL possess tests covering:

- successful construction;
- invariant establishment;
- invalid construction;
- dependency interaction;
- deterministic behaviour.

Factories SHALL remain independently testable.

---

# 16. AI Engineering

AI coding agents SHALL:

- introduce Factories only where construction complexity justifies them;
- preserve Domain invariants;
- avoid persistence inside Factories;
- inject dependencies explicitly;
- return fully valid Domain objects.

AI SHALL NOT create Factories merely to satisfy design fashion.

---

# 17. Review Checklist

Reviewers SHALL verify:

## Construction

- [ ] Object fully valid.
- [ ] Invariants established.
- [ ] Complexity justified.

---

## Architecture

- [ ] No persistence.
- [ ] No transactions.
- [ ] Dependencies explicit.

---

## Maintainability

- [ ] Naming appropriate.
- [ ] Construction readable.
- [ ] Tests complete.

---

# 18. Anti-Patterns

The following practices are prohibited.

- Factories persisting objects.
- Factories publishing events.
- Generic Builder classes.
- Factories containing business workflows.
- Hidden dependency construction.
- Returning partially valid objects.
- Infrastructure-aware Domain Factories.
- Massive "ObjectFactory" implementations creating unrelated types.

---

# 19. Compliance

Every Factory SHALL comply with these standards.

Factories exist to simplify construction while preserving the integrity of the Domain Model.

Architectural deviations require an approved ADR before implementation.

---

# Cross References

- EM-II-005 Domain-Driven Design
- EM-II-015 Dependency Injection
- EM-III-010 Entity Standards
- EM-III-011 Aggregate Standards
- EM-III-012 Domain Service Standards
- EM-III-014 Builder Standards
- Product Specification
- Architectural Decision Records