# engineering/manual/volume-i/CHAPTER-05-Engineering-Principles.md

---
title: Engineering Principles
identifier: EM-I-005
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 5 — Engineering Principles

## 1. Purpose

This chapter defines the enduring engineering principles that govern every technical decision made within the F1 platform.

Unlike implementation patterns, these principles are expected to remain stable throughout the lifetime of the platform. Technologies may change, frameworks may evolve and infrastructure may be replaced; these principles SHALL continue to govern engineering decisions unless explicitly superseded through the project's governance process.

Every engineer, reviewer and AI coding agent SHALL understand and apply these principles before introducing, modifying or approving any implementation.

---

# 2. Scope

These principles apply to:

- software architecture;
- application design;
- source code;
- testing;
- infrastructure;
- deployment;
- operational engineering;
- maintenance;
- documentation;
- refactoring.

No repository component is exempt.

---

# 3. Engineering Principles

## EP-001 — The Specification Is the Product

The Product Specification is not documentation describing the software.

The Product Specification defines the software.

Source code is an implementation of the Specification.

Engineering SHALL never treat the Specification as optional guidance.

---

## EP-002 — Architecture Before Code

Architecture SHALL precede implementation.

No engineer SHALL introduce structural behaviour merely because it appears technically useful.

Implementation follows architecture.

Architecture does not emerge from implementation.

---

## EP-003 — Every Behaviour Has One Owner

Every externally observable behaviour SHALL have exactly one canonical owner.

Business rules SHALL NOT be duplicated.

If multiple implementations require the same rule, they SHALL reference the canonical definition rather than creating independent interpretations.

---

## EP-004 — Correctness Before Performance

Performance optimisation SHALL NOT alter required behaviour.

Correctness is established first.

Performance improvements SHALL preserve externally observable semantics.

Where optimisation changes behaviour, an ADR is required.

---

## EP-005 — Explicit Over Implicit

The platform SHALL favour explicit behaviour.

Engineers SHALL avoid:

- hidden side effects;
- implicit configuration;
- undocumented conventions;
- magic values;
- invisible dependencies.

Every significant behaviour SHOULD be discoverable through the repository.

---

## EP-006 — Cohesion Before Convenience

Modules SHALL exist because they represent coherent responsibilities.

Utility classes created solely to avoid writing code SHALL be avoided.

Shared code SHALL exist only where genuine shared behaviour exists.

---

## EP-007 — Stable Interfaces

Public interfaces SHALL evolve deliberately.

Backward compatibility SHALL be considered whenever externally consumed interfaces change.

Breaking changes require explicit governance.

---

## EP-008 — Fail Safely

Failures SHALL:

- be detected;
- be observable;
- preserve data integrity;
- avoid silent corruption.

Systems SHALL fail predictably.

Unexpected success is preferable to silent inconsistency only when explicitly defined by the Specification.

---

## EP-009 — Observability Is Part of the Feature

A feature is incomplete until it is observable.

Every production capability SHALL expose sufficient evidence to support:

- diagnosis;
- audit;
- monitoring;
- operational support.

Logging and telemetry SHALL be designed, not appended.

---

## EP-010 — Security Is Continuous

Security SHALL influence every engineering activity.

Security review SHALL occur throughout implementation rather than solely before release.

Authentication, authorisation, validation, encryption and auditing SHALL be considered architectural concerns.

---

## EP-011 — Testability Is a Design Requirement

Testability SHALL influence design.

Components that cannot be tested independently SHALL be redesigned unless strong architectural justification exists.

Automated verification is preferred over manual verification.

---

## EP-012 — Simplicity Is a Competitive Advantage

Complexity carries permanent maintenance cost.

Engineers SHALL select the simplest implementation that satisfies:

- the Product Specification;
- architectural integrity;
- operational requirements;
- future maintainability.

Complexity requires justification.

Simplicity does not.

---

## EP-013 — Minimise Technical Debt

Technical debt SHALL be treated as an explicit engineering decision.

Debt SHALL:

- be identified;
- be documented;
- have an owner;
- have a remediation strategy.

Undocumented technical debt is prohibited.

---

## EP-014 — Automate Repetitive Work

Repeated manual engineering activities SHOULD become automated where practical.

Automation SHALL improve:

- consistency;
- quality;
- repeatability;
- reviewability.

Automation SHALL NOT obscure engineering intent.

---

## EP-015 — Documentation Is Part of the System

Documentation SHALL evolve with implementation.

Documentation is not an afterthought.

Documentation defects are engineering defects.

---

# 4. Engineering Trade-offs

Not every engineering objective can be maximised simultaneously.

Trade-offs SHALL follow the precedence defined in EM-I-002.

Where trade-offs affect architecture they SHALL be documented through an ADR.

Trade-offs SHALL never remain implicit.

---

# 5. Anti-Patterns

The following practices violate these principles.

- Copying business logic between services.
- Treating tests as the specification.
- Encoding business rules in controllers.
- Embedding workflow logic in user interfaces.
- Hidden database behaviour.
- Undocumented feature flags.
- Configuration that changes behaviour without governance.
- Infrastructure assumptions embedded in domain logic.
- Coupling unrelated modules for implementation convenience.
- Optimising before measuring.

---

# 6. Review Checklist

Reviewers SHALL confirm:

- Architectural boundaries are preserved.
- Behaviour originates from the Specification.
- Business rules have one canonical owner.
- Complexity is justified.
- Failure behaviour is explicit.
- Security has been considered.
- Testability has been preserved.
- Observability is sufficient.
- Documentation has been updated.
- Technical debt has been identified where introduced.

---

# 7. Compliance

These principles are mandatory.

Where implementation cannot satisfy a principle, the departure SHALL:

1. be documented;
2. identify the affected principle;
3. justify the exception;
4. receive approval through the project's governance process.

Repeated departures SHALL trigger an architectural review.

---

# Cross References

- EM-I-001 Engineering Philosophy
- EM-I-002 Engineering Objectives
- EM-I-003 Authority Hierarchy
- EM-I-004 Normative Language
- EM-I-007 Repository Governance
- Product Specification
- Architectural Decision Records