# engineering/manual/volume-iii/CHAPTER-002-Ruby-Coding-Standards.md

---
title: Ruby Coding Standards
identifier: EM-III-002
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 2 — Ruby Coding Standards

## 1. Purpose

This chapter defines the mandatory Ruby coding standards for the F1 platform.

These standards ensure that all Ruby code is:

- readable;
- deterministic;
- maintainable;
- testable;
- consistent.

Every Ruby source file SHALL comply with these standards.

---

# 2. Scope

This chapter governs:

- Ruby syntax;
- formatting;
- naming;
- language features;
- object design;
- method construction;
- constants;
- immutability;
- documentation.

---

# 3. Engineering Philosophy

Ruby SHALL be written for engineers rather than interpreters.

Readable code is preferred over concise code.

Explicit code is preferred over clever code.

Every implementation SHALL optimise for long-term maintainability.

---

# 4. Ruby Version

The repository SHALL target one approved Ruby version.

Every production environment SHALL use the identical major and minor Ruby release.

Multiple supported Ruby versions are prohibited unless approved by ADR.

---

# 5. Formatting

Formatting SHALL remain automatic.

The repository SHALL use:

- RuboCop
- Standard formatting rules
- UTF-8 encoding
- LF line endings

Formatting SHALL NOT become a matter of personal preference.

---

# 6. File Structure

Every Ruby source file SHOULD follow this order.

```ruby
# frozen_string_literal: true

module ...

class ...

CONSTANTS

initialize

public methods

protected methods

private methods

end

end
```

Structure SHALL remain consistent throughout the repository.

---

# 7. Naming

Names SHALL communicate business meaning.

Examples:

```ruby
Assessment

Project

Evaluation

Evidence

Issue
```

Names SHALL avoid technical implementation language where business terminology exists.

---

## Good

```ruby
AssessmentRepository

IssueDetectionService

EvidenceExtractor
```

---

## Poor

```ruby
Processor

Manager

Helper

Utility

Thing
```

---

# 8. Methods

Methods SHALL:

- perform one responsibility;
- remain short;
- remain readable;
- minimise branching.

Guideline:

Approximately 20 lines or fewer.

Exceptions require engineering justification.

---

# 9. Parameters

Parameter lists SHOULD remain small.

Prefer:

```ruby
perform(command)
```

rather than:

```ruby
perform(
  organisation,
  project,
  assessment,
  evidence,
  settings,
  options,
  retry_count
)
```

Where parameter growth occurs, introduce an explicit Value Object or DTO.

---

# 10. Immutability

Immutable objects SHALL be preferred.

Value Objects SHALL always be immutable.

Mutation SHALL remain explicit.

Hidden mutation is prohibited.

---

# 11. Constants

Constants SHALL:

- be frozen;
- remain immutable;
- possess meaningful names.

Magic numbers are prohibited.

Example:

```ruby
MAX_RETRY_ATTEMPTS = 5
```

rather than

```ruby
retry > 5
```

---

# 12. Conditionals

Prefer early returns.

Example:

```ruby
return unless authorised?

perform_operation
```

rather than deeply nested conditionals.

Nesting SHOULD remain shallow.

---

# 13. Iteration

Prefer expressive Enumerable operations.

Examples:

```ruby
map

select

reject

find

each_with_object
```

Avoid unnecessarily complex iterator chains.

Readability takes precedence.

---

# 14. Exceptions

Exceptions SHALL represent exceptional situations.

Exceptions SHALL NOT replace ordinary control flow.

Business validation SHOULD normally return explicit business outcomes rather than relying upon exception handling.

---

# 15. Monkey Patching

Monkey patching is prohibited.

Core Ruby classes SHALL NOT be modified.

Extensions SHALL occur through composition.

---

# 16. Metaprogramming

Metaprogramming SHALL be used sparingly.

It requires explicit engineering justification.

Code generation that obscures behaviour is discouraged.

Explicit implementation is preferred.

---

# 17. Comments

Code SHALL explain itself.

Comments SHOULD explain:

- why;

not

- what.

Outdated comments are prohibited.

---

# 18. Documentation

Every public class SHALL possess concise documentation describing:

- responsibility;
- ownership;
- significant behaviour.

Complex algorithms SHALL include implementation notes where appropriate.

---

# 19. AI Engineering

AI coding agents SHALL:

- generate explicit Ruby;
- avoid unnecessary metaprogramming;
- avoid hidden language tricks;
- preserve repository naming conventions;
- optimise for readability.

Generated Ruby SHALL resemble code written by an experienced senior engineer.

---

# 20. Review Checklist

Reviewers SHALL verify:

## Readability

- [ ] Clear naming.
- [ ] Small methods.
- [ ] Minimal nesting.

---

## Maintainability

- [ ] Constants extracted.
- [ ] Comments appropriate.
- [ ] Immutability preserved.

---

## Ruby

- [ ] Idiomatic Ruby.
- [ ] Formatting correct.
- [ ] No hidden behaviour.

---

# 21. Anti-Patterns

The following practices are prohibited.

- Monkey patching.
- Clever metaprogramming.
- Magic numbers.
- Long parameter lists.
- Deep nesting.
- Hidden mutation.
- Generic helper methods.
- Single-letter variable names.
- Excessively compact Ruby.

---

# 22. Compliance

Every Ruby implementation SHALL comply with this chapter.

Consistency across the repository is a mandatory engineering objective.

Ruby code SHALL prioritise clarity, correctness and maintainability above stylistic preference.

---

# Cross References

- EM-III-001 Rails 8 Engineering Philosophy
- EM-III-003 Naming Conventions
- EM-III-004 Class Design Standards
- EM-III-005 Method Design Standards
- EM-I-011 Code Review
- Product Specification
- Architectural Decision Records