---
title: Architectural Validation
identifier: EM-II-018
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 18 — Architectural Validation

## 1. Purpose

This chapter defines the architectural validation framework for the F1 platform.

Architectural validation ensures that the implemented software continuously conforms to the Product Specification, the Engineering Manual and all approved Architectural Decision Records (ADRs).

Architecture SHALL be verified continuously rather than assumed.

Every implementation SHALL be objectively validated before it is merged into the repository.

---

# 2. Scope

This chapter governs:

- architecture validation;
- compliance verification;
- architectural quality gates;
- automated validation;
- manual review;
- dependency analysis;
- repository conformance;
- architectural reporting.

Every production change SHALL satisfy these validation requirements.

---

# 3. Architectural Philosophy

Architecture is an executable contract.

Validation exists to detect deviation before defects become embedded in the codebase.

Architectural validation SHALL be:

- objective;
- repeatable;
- automated wherever practical;
- evidence-based.

Human judgement supplements automated validation but does not replace it.

---

# 4. Validation Objectives

Architectural validation SHALL verify:

- repository structure;
- dependency direction;
- module boundaries;
- layering;
- Domain independence;
- implementation traceability;
- architectural consistency;
- Engineering Manual compliance.

---

# 5. Validation Lifecycle

Every software change SHALL pass the following lifecycle.

```text
Implementation

↓

Static Validation

↓

Architecture Validation

↓

Code Review

↓

Continuous Integration

↓

Merge Approval
```

Failure at any stage SHALL prevent merge.

---

# 6. Validation Categories

Architectural validation SHALL comprise the following categories.

## Structure Validation

Verifies:

- directory structure;
- namespace consistency;
- module ownership;
- repository organisation.

---

## Dependency Validation

Verifies:

- inward dependency direction;
- absence of circular dependencies;
- framework isolation;
- interface ownership.

---

## Layer Validation

Verifies:

- Interface Layer responsibilities;
- Application Layer responsibilities;
- Domain Layer independence;
- Infrastructure isolation.

---

## Traceability Validation

Verifies:

- Product Specification references;
- ADR references;
- implementation ownership;
- engineering documentation.

---

## Quality Validation

Verifies:

- duplication;
- cohesion;
- complexity;
- maintainability.

---

# 7. Automated Validation

The repository SHALL automatically validate:

- dependency graphs;
- module boundaries;
- architecture rules;
- repository conventions;
- static analysis;
- linting;
- formatting;
- documentation references.

Automation SHALL execute on every Pull Request.

---

# 8. Manual Validation

Manual review SHALL verify:

- architectural intent;
- business correctness;
- implementation clarity;
- maintainability;
- engineering judgement.

Manual review SHALL complement automation.

---

# 9. Architectural Rules

Validation SHALL ensure that:

- Domain depends on nothing external;
- Infrastructure depends only on abstractions;
- controllers remain thin;
- Aggregates own business behaviour;
- repositories remain persistence abstractions;
- transactions remain Application-owned.

Violations SHALL prevent merge.

---

# 10. Repository Validation

Repository validation SHALL verify:

- directory placement;
- namespace alignment;
- ownership documentation;
- engineering standards;
- documentation completeness.

Repository drift SHALL be treated as an architectural defect.

---

# 11. Dependency Validation

Automated tooling SHOULD verify:

- acyclic dependencies;
- dependency direction;
- interface ownership;
- forbidden imports;
- layer violations.

Dependency validation SHALL execute continuously.

---

# 12. Complexity Validation

Validation SHOULD measure:

- cyclomatic complexity;
- class size;
- method size;
- dependency count;
- coupling;
- cohesion.

Thresholds SHALL be defined within Engineering Manual Volume IX.

---

# 13. Documentation Validation

Validation SHALL ensure:

- chapter identifiers remain valid;
- cross references resolve;
- ADR references remain current;
- repository documentation remains synchronised.

Broken documentation SHALL fail validation where practical.

---

# 14. Reporting

Validation reports SHALL include:

- validation outcome;
- detected violations;
- repository revision;
- execution timestamp;
- validator version.

Validation evidence SHALL remain reproducible.

---

# 15. Exceptions

Architectural exceptions require:

- documented rationale;
- approved ADR;
- engineering approval;
- traceable implementation.

Undocumented exceptions are prohibited.

---

# 16. AI Engineering

AI coding agents SHALL:

- satisfy all architectural validators before proposing completion;
- preserve repository conventions;
- preserve dependency rules;
- avoid suppressing validation failures;
- treat validator failures as implementation defects.

AI SHALL NOT bypass architectural validation.

---

# 17. Review Checklist

Reviewers SHALL verify:

## Validation

- [ ] Automated validation passed.
- [ ] Manual review completed.
- [ ] Architectural intent preserved.

---

## Architecture

- [ ] Layering correct.
- [ ] Dependencies correct.
- [ ] Repository structure preserved.

---

## Quality

- [ ] Complexity acceptable.
- [ ] Documentation updated.
- [ ] Traceability maintained.

---

# 18. Anti-Patterns

The following practices are prohibited.

- Merging with failing architectural validation.
- Ignoring dependency violations.
- Suppressing validator output.
- Treating warnings as acceptable without review.
- Manual exceptions without ADR approval.
- Repository drift.
- Hidden architectural coupling.
- Architecture changes without documentation.

---

# 19. Compliance

Architectural validation is mandatory for every repository change.

No implementation SHALL be merged until all mandatory architectural validation has successfully completed.

Validation evidence SHALL remain available for audit.

---

# Cross References

- EM-II-002 Repository Architecture
- EM-II-004 Layered Architecture
- EM-II-006 Module Boundaries
- EM-II-007 Dependency Rules
- EM-I-009 Pull Request Governance
- EM-I-010 Definition of Done
- Engineering Manual Volume IX — Quality Engineering
- Product Specification
- Architectural Decision Records
