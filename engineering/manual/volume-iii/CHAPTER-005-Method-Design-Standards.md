---
title: Method Design Standards
identifier: EM-III-005
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 5 — Method Design Standards

## 1. Purpose

This chapter establishes the mandatory standards governing method design throughout the F1 platform.

Methods are the smallest unit of executable behaviour.

Well-designed methods make software predictable, readable, testable and maintainable.

Poor method design rapidly increases complexity regardless of overall architecture.

Every method committed to the repository SHALL comply with this chapter.

---

# 2. Scope

This chapter governs:

- method responsibilities;
- method size;
- parameters;
- return values;
- visibility;
- complexity;
- side effects;
- error handling.

These standards apply to all Ruby implementation.

---

# 3. Design Philosophy

A method SHALL perform one clearly defined task.

A reader SHOULD understand the purpose of a method by reading:

- its name;
- its parameters;
- its return value.

Implementation details SHOULD be secondary.

---

# 4. Single Responsibility

Each method SHALL have one responsibility.

Indicators that a method possesses multiple responsibilities include:

- numerous conditional branches;
- multiple unrelated outcomes;
- repeated state mutation;
- orchestration mixed with calculation.

Such methods SHALL be decomposed.

---

# 5. Method Size

Methods SHOULD remain short.

Engineering guidance:

- normally fewer than **20 executable lines**;
- methods exceeding **40 lines** require engineering justification.

Long methods increase cognitive load and reduce testability.

---

# 6. Parameters

Methods SHOULD accept the smallest practical number of parameters.

Preferred:

```ruby
perform(command)
```

Acceptable:

```ruby
perform(project, crawl)
```

Avoid:

```ruby
perform(
  organization,
  user,
  project,
  crawl,
  options,
  settings,
  retries,
  logger
)
```

Where parameter lists become large, introduce an explicit Value Object or DTO.

---

# 7. Return Values

Methods SHALL return one clear result.

Return values SHALL remain predictable.

A method SHOULD NOT sometimes return:

- nil;
- Boolean;
- object;
- Array;

depending upon execution path.

Return semantics SHALL remain stable.

---

# 8. Side Effects

Methods SHALL minimise side effects.

A caller SHOULD easily understand what state may change.

Hidden mutation is prohibited.

Queries SHALL remain side-effect free.

Commands SHALL make mutation explicit.

---

# 9. Visibility

Method visibility SHALL be chosen deliberately.

## Public

Defines business capability.

---

## Protected

Used only where subclass collaboration is genuinely required.

---

## Private

Implementation detail.

Default visibility SHOULD be private unless external invocation is required.

---

# 10. Naming

Method names SHALL describe behaviour.

Examples:

```ruby
create_crawl

publish_event

activate_project

calculate_score
```

Boolean methods SHALL use predicates.

Examples:

```ruby
valid?

expired?

completed?

authorised?
```

---

# 11. Complexity

Methods SHOULD minimise:

- nesting;
- branching;
- recursion;
- temporary state.

Early returns are preferred over deep nesting.

Cyclomatic complexity SHOULD remain low.

---

# 12. Guard Clauses

Guard clauses SHOULD be preferred.

Example:

```ruby
return unless authorised?

perform_operation
```

rather than:

```ruby
if authorised?
  perform_operation
end
```

Guard clauses improve readability.

---

# 13. Exceptions

Methods SHALL use exceptions only for exceptional situations.

Business validation SHALL normally return explicit business outcomes.

Exceptions SHALL NOT become ordinary control flow.

---

# 14. Idempotency

Where required by the Product Specification, methods SHALL remain idempotent.

Repeated execution SHALL preserve business correctness.

Idempotency requirements SHALL remain explicit.

---

# 15. Documentation

Complex methods SHOULD include concise documentation explaining:

- business intent;
- important assumptions;
- non-obvious algorithms.

Documentation SHALL explain *why*, not *what*.

---

# 16. Testing

Every public method SHALL be testable independently.

Methods with excessive dependency requirements SHOULD be refactored.

Method design SHALL facilitate isolated testing.

---

# 17. AI Engineering

AI coding agents SHALL:

- generate small methods;
- preserve single responsibility;
- minimise parameters;
- avoid hidden side effects;
- prefer guard clauses;
- avoid deeply nested logic.

AI SHALL decompose complexity rather than enlarge existing methods.

---

# 18. Review Checklist

Reviewers SHALL verify:

## Responsibility

- [ ] One responsibility.
- [ ] Clear business purpose.
- [ ] Appropriate visibility.

---

## Readability

- [ ] Short method.
- [ ] Guard clauses used.
- [ ] Clear naming.

---

## Maintainability

- [ ] Stable return value.
- [ ] Minimal parameters.
- [ ] Low complexity.

---

# 19. Anti-Patterns

The following practices are prohibited.

- Long methods.
- Deep nesting.
- Hidden side effects.
- Boolean flag parameters controlling unrelated behaviour.
- Mixed query and command behaviour.
- Returning inconsistent types.
- Catch-all rescue blocks.
- Exception-driven control flow.
- Methods performing unrelated business operations.

---

# 20. Compliance

Every method committed to the repository SHALL comply with this chapter.

Method quality determines class quality, and class quality determines architectural quality.

Method discipline is therefore mandatory.

---

# Cross References

- EM-III-001 Rails 8 Engineering Philosophy
- EM-III-002 Ruby Coding Standards
- EM-III-004 Class Design Standards
- EM-III-006 Service Object Standards
- EM-II-008 Service Architecture
- Product Specification
- Architectural Decision Records
