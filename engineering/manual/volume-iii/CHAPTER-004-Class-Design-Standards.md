---
title: Class Design Standards
identifier: EM-III-004
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 4 — Class Design Standards

## 1. Purpose

This chapter defines the mandatory standards governing class design throughout the F1 platform.

Classes are the primary unit of implementation.

Well-designed classes produce software that is understandable, testable, extensible and maintainable.

Poorly designed classes inevitably produce architectural erosion regardless of framework quality.

Every class introduced into the repository SHALL comply with this chapter.

---

# 2. Scope

This chapter governs:

- class responsibilities;
- cohesion;
- coupling;
- inheritance;
- composition;
- visibility;
- interfaces;
- lifecycle;
- maintainability.

---

# 3. Design Philosophy

A class exists to model one concept.

A class SHALL possess one primary responsibility.

Responsibilities SHALL remain explicit and cohesive.

Classes SHALL model business language rather than technical convenience.

---

# 4. Single Responsibility Principle

Every class SHALL have exactly one reason to change.

Changes caused by unrelated business requirements indicate multiple responsibilities.

Such classes SHALL be decomposed.

---

# 5. Cohesion

Classes SHALL exhibit high cohesion.

Everything contained within a class SHALL contribute directly to its stated responsibility.

Low cohesion SHALL be treated as an architectural defect.

---

# 6. Coupling

Classes SHALL minimise dependencies.

Dependencies SHALL be:

- explicit;
- injected;
- stable;
- justified.

Hidden dependencies are prohibited.

---

# 7. Class Size

Classes SHOULD remain small.

Guidance:

- normally fewer than 300 lines;
- exceptionally larger classes require documented justification.

Large classes are indicators—not proof—of excessive responsibility.

---

# 8. Public Interface

Public methods SHALL define the business capability of the class.

Everything not intended for external use SHALL remain private.

Public interfaces SHOULD remain intentionally small.

---

# 9. Visibility

Use visibility deliberately.

### Public

Business behaviour.

### Protected

Subclass collaboration only where justified.

### Private

Implementation detail.

Avoid unnecessary exposure.

---

# 10. Constructors

Constructors SHALL:

- establish valid state;
- receive dependencies;
- avoid business behaviour;
- avoid persistence.

Complex construction SHALL be delegated to factories.

---

# 11. Composition

Composition SHALL be preferred over inheritance.

Where behaviour can be assembled, composition SHOULD be chosen.

Inheritance SHALL model genuine "is-a" relationships.

Implementation reuse alone does not justify inheritance.

---

# 12. Inheritance

Inheritance SHOULD remain shallow.

Deep inheritance hierarchies are discouraged.

Framework inheritance SHALL be minimised where possible.

Business behaviour SHALL not depend upon inheritance depth.

---

# 13. Mutable State

Classes SHOULD minimise mutable state.

Mutation SHALL be:

- explicit;
- predictable;
- observable.

Immutable objects SHALL be preferred wherever practical.

---

# 14. Collaboration

Classes SHALL collaborate through well-defined interfaces.

Classes SHALL NOT manipulate the internal state of collaborating classes.

Encapsulation SHALL be preserved.

---

# 15. Framework Independence

Business classes SHALL remain substantially independent of Rails.

Framework behaviour SHALL terminate at architectural boundaries.

The Domain SHALL remain free of framework-specific implementation.

---

# 16. Documentation

Every public class SHALL include concise documentation describing:

- responsibility;
- ownership;
- collaborators where significant.

Documentation SHALL describe intent rather than implementation.

---

# 17. Testing

Every class SHALL be independently testable.

Hidden global dependencies are prohibited.

Dependency injection SHALL support isolated unit testing.

---

# 18. AI Engineering

AI coding agents SHALL:

- create cohesive classes;
- minimise public interfaces;
- avoid God Objects;
- prefer composition;
- preserve encapsulation.

AI SHALL split responsibilities rather than enlarge existing classes unnecessarily.

---

# 19. Review Checklist

Reviewers SHALL verify:

## Responsibility

- [ ] Single responsibility.
- [ ] High cohesion.
- [ ] Clear ownership.

---

## Architecture

- [ ] Dependencies explicit.
- [ ] Encapsulation preserved.
- [ ] Framework isolation maintained.

---

## Maintainability

- [ ] Class appropriately sized.
- [ ] Interface minimal.
- [ ] Collaboration understandable.

---

# 20. Anti-Patterns

The following practices are prohibited.

- God Objects.
- Large Manager classes.
- Utility classes containing unrelated behaviour.
- Deep inheritance hierarchies.
- Hidden mutable state.
- Public data structures replacing behaviour.
- Framework-specific Domain classes.
- Circular class dependencies.
- Classes performing unrelated business functions.

---

# 21. Compliance

Every class committed to the repository SHALL comply with these standards.

Class quality directly determines architectural quality.

Engineering discipline at the class level is therefore mandatory.

---

# Cross References

- EM-III-001 Rails 8 Engineering Philosophy
- EM-III-002 Ruby Coding Standards
- EM-III-003 Naming Conventions
- EM-III-005 Method Design Standards
- EM-II-005 Domain-Driven Design
- Product Specification
- Architectural Decision Records
