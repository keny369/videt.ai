---
title: Builder Standards
identifier: EM-III-014
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 14 — Builder Standards

## 1. Purpose

This chapter defines the mandatory standards governing the Builder pattern within the F1 platform.

Builders exist to assemble complex objects incrementally where construction cannot reasonably occur through constructors or Factories alone.

Builders SHALL manage construction.

They SHALL NOT implement business behaviour.

Every Builder SHALL comply with this chapter.

---

# 2. Scope

This chapter governs:

- Builder classes;
- staged object construction;
- complex configuration;
- immutable object assembly;
- fluent interfaces;
- construction validation.

These standards apply throughout the Application and Infrastructure Layers.

---

# 3. Engineering Philosophy

Builders exist to simplify complex construction.

Where construction remains simple, constructors or Factories SHALL be preferred.

The Builder pattern SHALL be introduced only where it materially improves readability and maintainability.

Builders SHALL remain rare.

---

# 4. Appropriate Use

Builders MAY be used where:

- object construction requires numerous optional parameters;
- configuration is incremental;
- object composition is complex;
- multiple construction stages exist;
- readability would otherwise suffer.

Builders SHALL NOT replace constructors by default.

---

# 5. Responsibilities

Builders SHALL:

- assemble valid objects;
- collect configuration;
- validate construction completeness;
- create immutable results.

Builders SHALL NOT:

- persist objects;
- own transactions;
- execute workflows;
- invoke repositories;
- implement business policy.

---

# 6. Construction Lifecycle

A Builder SHALL follow this lifecycle.

```text
Builder Created

↓

Configuration Applied

↓

Validation

↓

Object Built

↓

Builder Discarded
```

Builders SHOULD be treated as short-lived objects.

---

# 7. Fluent Interfaces

Builders MAY expose fluent interfaces.

Example:

```ruby
ReportBuilder
  .with_title(title)
  .with_sections(sections)
  .with_footer(footer)
  .build
```

Fluent interfaces SHALL remain readable.

Method chaining SHALL not obscure construction intent.

---

# 8. Validation

Builders SHALL verify:

- required fields;
- mandatory configuration;
- structural consistency.

Builders SHALL fail before producing invalid objects.

Business validation remains the responsibility of the Domain.

---

# 9. Immutable Results

Objects produced by Builders SHOULD be immutable.

Builders SHALL not expose partially constructed objects.

Construction SHALL complete before object publication.

---

# 10. State

Builder state SHALL remain internal.

External callers SHALL interact only through the Builder interface.

Internal mutable construction state SHALL never escape.

---

# 11. Reuse

Builders SHOULD NOT be reused.

Each Builder instance SHOULD create one completed object.

Reusing Builders risks hidden mutable state.

---

# 12. Dependencies

Builders SHALL receive dependencies explicitly.

Dependencies MAY include:

- identifier generators;
- serializers;
- configuration objects.

Builders SHALL NOT resolve dependencies dynamically.

---

# 13. Naming

Builder names SHALL describe the constructed object.

Examples:

```ruby
EvaluationReportBuilder

SearchQueryBuilder

NotificationPayloadBuilder
```

Generic names such as:

```ruby
Builder

ObjectBuilder

GenericBuilder
```

are prohibited.

---

# 14. Testing

Every Builder SHALL possess tests covering:

- successful construction;
- validation failures;
- optional configuration;
- immutable output;
- deterministic behaviour.

---

# 15. AI Engineering

AI coding agents SHALL:

- prefer constructors and Factories before introducing Builders;
- generate Builders only where construction complexity genuinely exists;
- preserve immutable output;
- avoid embedding business logic;
- keep Builders short-lived.

AI SHALL NOT use Builders as generic object containers.

---

# 16. Review Checklist

Reviewers SHALL verify:

## Construction

- [ ] Builder justified.
- [ ] Configuration readable.
- [ ] Validation complete.

---

## Architecture

- [ ] No business logic.
- [ ] No persistence.
- [ ] Immutable output.

---

## Maintainability

- [ ] Builder short-lived.
- [ ] Naming appropriate.
- [ ] Tests comprehensive.

---

# 17. Anti-Patterns

The following practices are prohibited.

- Builders containing business rules.
- Builders persisting objects.
- Reusable mutable Builders.
- Builders returning partially complete objects.
- Generic Builder implementations.
- Builders replacing ordinary constructors without justification.
- Infrastructure-aware Domain Builders.
- Hidden dependency resolution.

---

# 18. Compliance

Every Builder SHALL comply with these standards.

Builders exist solely to simplify complex object construction while preserving architectural clarity.

Architectural deviations require an approved ADR before implementation.

---

# Cross References

- EM-II-015 Dependency Injection
- EM-III-010 Entity Standards
- EM-III-011 Aggregate Standards
- EM-III-012 Domain Service Standards
- EM-III-013 Factory Standards
- EM-III-015 Validation Standards
- Product Specification
- Architectural Decision Records
