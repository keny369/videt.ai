# engineering/manual/volume-iii/CHAPTER-009-Value-Object-Standards.md

---
title: Value Object Standards
identifier: EM-III-009
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 9 — Value Object Standards

## 1. Purpose

This chapter defines the mandatory standards governing Value Objects throughout the F1 platform.

Value Objects model descriptive business concepts that possess no independent identity.

They encapsulate validation, preserve invariants and improve the expressiveness of the Domain Model.

Every Value Object SHALL comply with this chapter.

---

# 2. Scope

This chapter governs:

- Value Objects;
- immutability;
- equality;
- validation;
- construction;
- composition;
- serialization;
- testing.

These standards apply throughout the Domain Layer.

---

# 3. Engineering Philosophy

A Value Object represents **what something is**, not **which specific thing it is**.

Two Value Objects with identical values SHALL be considered equal.

Business meaning SHALL take precedence over implementation convenience.

Value Objects SHALL make invalid business states impossible wherever practical.

---

# 4. Characteristics

Every Value Object SHALL:

- be immutable;
- possess no independent identity;
- compare by value;
- encapsulate validation;
- remain deterministic;
- expose business terminology.

Value Objects SHALL NOT contain persistence concerns.

---

# 5. Identity

Value Objects SHALL NOT possess identifiers.

Examples of prohibited fields include:

```ruby
id

uuid

created_at

updated_at
```

Identity belongs to Entities.

---

# 6. Immutability

Once constructed, a Value Object SHALL never change.

Mutation SHALL occur by constructing a new instance.

Example:

```ruby
new_score = ConfidenceScore.new(87)
```

rather than:

```ruby
score.value = 87
```

---

# 7. Construction

Construction SHALL guarantee validity.

Invalid Value Objects SHALL NOT exist.

Example:

```ruby
EmailAddress.new("invalid")
```

SHALL fail during construction.

Validation SHALL occur immediately.

---

# 8. Validation

Value Objects SHALL validate:

- structure;
- format;
- allowable range;
- canonical representation.

Business workflow validation SHALL remain elsewhere.

Example:

An EmailAddress validates email syntax.

It SHALL NOT determine whether an account exists.

---

# 9. Equality

Equality SHALL compare values.

Example:

```ruby
EmailAddress.new("user@example.com") ==
EmailAddress.new("user@example.com")
```

SHALL evaluate as true.

Object identity SHALL NOT determine equality.

---

# 10. Examples

Typical Value Objects include:

- EmailAddress
- DomainName
- ConfidenceScore
- Money
- CrawlDepth
- LanguageCode
- Url
- IssueFingerprint
- AssessmentIdentifier
- ProjectSlug

Business terminology SHALL determine Value Object boundaries.

---

# 11. Behaviour

Value Objects MAY contain behaviour.

Behaviour SHALL relate exclusively to the represented value.

Example:

```ruby
Money#add

Money#subtract

ConfidenceScore#greater_than?
```

Behaviour SHALL remain deterministic.

---

# 12. Serialization

Value Objects SHALL support explicit serialization where required.

Serialization SHALL preserve business meaning.

Serialization SHALL NOT expose implementation details.

---

# 13. Persistence

Repositories SHALL map Value Objects explicitly.

Persistence SHALL NOT alter business semantics.

Persistence models SHALL not replace Value Objects.

---

# 14. Composition

Value Objects MAY contain other Value Objects.

Example:

```text
PostalAddress

↓

CountryCode

PostalCode

StreetAddress
```

Composition SHALL preserve immutability.

---

# 15. Performance

Value Objects SHOULD remain lightweight.

Expensive computation SHOULD occur outside frequently constructed Value Objects.

Performance optimisation SHALL never compromise immutability.

---

# 16. Testing

Every Value Object SHALL possess tests covering:

- construction;
- validation;
- equality;
- serialization;
- behaviour.

Value Objects SHALL remain deterministic under all test conditions.

---

# 17. AI Engineering

AI coding agents SHALL:

- generate immutable Value Objects;
- encapsulate validation;
- preserve value equality;
- avoid identifiers;
- keep behaviour cohesive.

AI SHALL NOT convert Value Objects into Entities.

---

# 18. Review Checklist

Reviewers SHALL verify:

## Correctness

- [ ] Immutable.
- [ ] No identity.
- [ ] Value equality implemented.

---

## Architecture

- [ ] Validation encapsulated.
- [ ] No persistence.
- [ ] Business terminology preserved.

---

## Maintainability

- [ ] Behaviour cohesive.
- [ ] Tests complete.
- [ ] Serialization deterministic.

---

# 19. Anti-Patterns

The following practices are prohibited.

- Mutable Value Objects.
- Identity fields.
- Persistence logic.
- Active Record inheritance.
- Hidden validation.
- Generic wrapper classes.
- Behaviour unrelated to represented value.
- Equality based upon object identity.

---

# 20. Compliance

Every Value Object SHALL comply with these standards.

Value Objects are foundational to a rich Domain Model and SHALL remain immutable, expressive and deterministic throughout the lifetime of the platform.

---

# Cross References

- EM-II-005 Domain-Driven Design
- EM-III-004 Class Design Standards
- EM-III-005 Method Design Standards
- EM-III-008 Data Transfer Object Standards
- EM-III-010 Entity Standards
- Product Specification
- Architectural Decision Records