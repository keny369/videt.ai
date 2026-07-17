# engineering/manual/volume-iii/CHAPTER-001-Rails-8-Engineering-Philosophy.md

---
title: Rails 8 Engineering Philosophy
identifier: EM-III-001
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 1 — Rails 8 Engineering Philosophy

## 1. Purpose

This chapter establishes the engineering philosophy governing every line of Ruby and Rails code written for the F1 platform.

The Engineering Manual Volume II defined *architecture*.

Volume III defines *implementation*.

Its purpose is to ensure that every engineer, contractor and AI coding agent writes software that is indistinguishable in quality, structure and engineering discipline.

Consistency is treated as an engineering feature.

---

# 2. Scope

This chapter governs:

- Ruby implementation;
- Rails implementation;
- engineering principles;
- framework usage;
- maintainability;
- readability;
- long-term evolution.

Every Ruby file committed to the repository SHALL comply.

---

# 3. Philosophy

Rails is used because it is productive.

It is **not** permitted to dictate architecture.

Business behaviour originates from:

- the Product Specification;
- the Domain Model;
- approved ADRs.

Rails exists only to implement those decisions.

---

# 4. Engineering Priorities

Every implementation decision SHALL be evaluated in the following order.

1. Correctness
2. Architectural fidelity
3. Maintainability
4. Readability
5. Testability
6. Operational reliability
7. Performance
8. Developer convenience

Convenience SHALL never override correctness.

---

# 5. Primary Principles

The following principles govern every implementation.

### RP-001

Software SHALL be understandable before it is clever.

---

### RP-002

Explicit behaviour is preferred over implicit behaviour.

---

### RP-003

Simple implementations are preferred over compact implementations.

---

### RP-004

Business language SHALL appear directly in code.

---

### RP-005

Framework behaviour SHALL remain visible.

Hidden Rails magic SHOULD be minimised.

---

### RP-006

Every public class SHALL possess one clearly defined responsibility.

---

### RP-007

Code SHALL optimise for the next engineer rather than the current engineer.

---

# 6. Repository Mindset

The repository SHALL read as though written by one engineering organisation rather than many individual programmers.

Personal coding styles SHALL yield to repository consistency.

Repository consistency is a governance requirement.

---

# 7. Ruby Philosophy

Ruby SHALL be written idiomatically without becoming obscure.

Readable Ruby is preferred to "clever Ruby."

Engineers SHALL optimise for clarity.

---

# 8. Rails Philosophy

Rails conventions SHOULD be followed unless they conflict with:

- the Product Specification;
- the Engineering Manual;
- an approved ADR.

Where conflict exists, repository governance takes precedence over framework convention.

---

# 9. Code Ownership

Every source file SHALL possess an identifiable architectural owner.

Ownership includes responsibility for:

- correctness;
- maintenance;
- documentation;
- future evolution.

Ownership survives personnel changes.

---

# 10. Long-Term Thinking

Implementation SHALL optimise for software expected to remain in production for many years.

Temporary shortcuts SHALL require explicit engineering approval.

---

# 11. AI Engineering

AI coding agents SHALL optimise for:

- consistency;
- determinism;
- maintainability;
- explicitness.

AI SHALL avoid:

- speculative abstractions;
- unnecessary metaprogramming;
- framework tricks;
- hidden behaviour.

---

# 12. Definition of Quality

High-quality software SHALL exhibit:

- low coupling;
- high cohesion;
- deterministic behaviour;
- explicit dependencies;
- comprehensive tests;
- operational observability;
- clear naming;
- architectural traceability.

---

# 13. Review Checklist

Reviewers SHALL verify:

- [ ] Code is readable.
- [ ] Business terminology preserved.
- [ ] Rails used appropriately.
- [ ] Simplicity preferred.
- [ ] Repository conventions followed.

---

# 14. Anti-Patterns

The following practices are prohibited.

- Clever code replacing readable code.
- Hidden framework behaviour.
- Personal coding conventions.
- Premature optimisation.
- Framework-driven architecture.
- Undocumented engineering shortcuts.
- Excessive metaprogramming.
- Magic constants.
- Hidden global state.

---

# 15. Compliance

Every Ruby implementation SHALL comply with this philosophy.

This chapter defines the engineering culture of the repository.

Every subsequent chapter in Volume III expands these principles into specific implementation standards.

---

# Cross References

- Engineering Manual Volume I
- Engineering Manual Volume II
- Product Specification
- Architectural Decision Records