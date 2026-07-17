---
title: Technical Debt and Refactoring
identifier: EM-I-018
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 18 — Technical Debt and Refactoring

## 1. Purpose

This chapter establishes the engineering standards governing technical debt, refactoring and long-term maintainability within the F1 platform.

Technical debt is an unavoidable consequence of engineering trade-offs.

Undocumented technical debt, however, is an engineering failure.

The objective of this chapter is to ensure that every departure from the preferred engineering state is:

- intentional;
- visible;
- owned;
- measurable;
- reviewable;
- remediable.

---

# 2. Scope

This chapter applies to:

- application code;
- architecture;
- database schema;
- infrastructure;
- deployment automation;
- testing;
- documentation;
- operational tooling.

Every engineering discipline is responsible for managing technical debt.

---

# 3. Definition

Technical debt is any engineering compromise that intentionally accepts increased future maintenance cost in exchange for present benefit.

Examples include:

- temporary implementations;
- architectural shortcuts;
- deferred optimisation;
- duplicated infrastructure;
- incomplete automation;
- legacy compatibility mechanisms.

Technical debt SHALL NOT include engineering defects.

A defect is incorrect behaviour.

Technical debt is a conscious engineering compromise.

---

# 4. Principles

Engineering SHALL:

- minimise technical debt;
- document unavoidable debt;
- assign ownership;
- review debt regularly;
- eliminate debt when economically justified.

Engineering SHALL NOT create hidden debt.

---

# 5. Acceptable Technical Debt

Technical debt MAY be accepted when:

- delivery constraints exist;
- external dependencies exist;
- implementation sequencing requires temporary compromise;
- the compromise is documented;
- remediation has been planned.

Acceptance SHALL be explicit.

---

# 6. Unacceptable Technical Debt

The following SHALL NOT be accepted as technical debt:

- Specification violations;
- security vulnerabilities;
- data integrity risks;
- undocumented behaviour;
- architectural corruption;
- broken tests;
- missing authorisation;
- hidden dependencies.

These are engineering defects.

---

# 7. Debt Register

Significant technical debt SHALL be recorded.

Each debt item SHALL contain:

- identifier;
- description;
- category;
- owner;
- rationale;
- engineering impact;
- operational impact;
- remediation strategy;
- target review date;
- current status.

The debt register SHALL remain under version control.

---

# 8. Debt Categories

Technical debt SHOULD be categorised.

### TD-001 Architecture

Examples:

- temporary abstractions;
- dependency violations;
- layering compromises.

---

### TD-002 Implementation

Examples:

- duplicated logic;
- temporary algorithms;
- inefficient structures.

---

### TD-003 Infrastructure

Examples:

- manual deployment steps;
- temporary environments;
- unsupported tooling.

---

### TD-004 Testing

Examples:

- missing automation;
- incomplete integration testing;
- deferred performance testing.

---

### TD-005 Documentation

Examples:

- incomplete guides;
- outdated diagrams;
- missing operational procedures.

---

### TD-006 Operational

Examples:

- manual recovery;
- incomplete monitoring;
- temporary alerting.

---

# 9. Refactoring

Refactoring SHALL improve implementation without changing externally observable behaviour.

Acceptable refactoring includes:

- simplifying implementation;
- improving naming;
- reducing duplication;
- improving modularity;
- improving readability;
- improving maintainability;
- improving performance without behavioural change.

Refactoring SHALL preserve Specification compliance.

---

# 10. Behavioural Changes

If a proposed refactoring changes externally observable behaviour, it is no longer refactoring.

It becomes implementation governed by:

- the Product Specification;
- Engineering Manual;
- ADR process where applicable.

Behavioural change SHALL receive appropriate governance.

---

# 11. Continuous Improvement

Engineering SHALL continuously identify opportunities to:

- reduce complexity;
- simplify architecture;
- improve observability;
- improve testability;
- improve operational reliability.

Continuous improvement SHALL form part of normal engineering work.

---

# 12. AI Engineering

AI coding agents SHALL NOT introduce speculative abstractions.

AI-generated refactoring SHALL:

- preserve behaviour;
- preserve architecture;
- preserve traceability;
- preserve documentation.

AI SHALL NOT remove code solely because it appears unused without repository evidence.

---

# 13. Review Checklist

Reviewers SHALL verify:

- behaviour preserved;
- architecture preserved;
- Specification unchanged;
- debt documented where introduced;
- debt reduced where practical;
- documentation updated;
- tests remain valid.

---

# 14. Anti-Patterns

The following practices are prohibited.

- "We'll fix it later" without documentation.
- Introducing frameworks solely to reduce current effort.
- Removing tests during refactoring.
- Architectural shortcuts without ownership.
- Permanent temporary implementations.
- Large-scale rewrites without engineering justification.
- Refactoring mixed with unrelated feature implementation.

---

# 15. Compliance

Engineering SHALL actively manage technical debt throughout the lifetime of the platform.

Undocumented technical debt SHALL be treated as an engineering governance defect.

Refactoring SHALL strengthen the platform rather than merely changing its appearance.

---

# Cross References

- EM-I-005 Engineering Principles
- EM-I-006 Architectural Integrity
- EM-I-010 Definition of Done
- EM-I-011 Code Review Standard
- EM-I-017 Engineering Metrics and Quality Gates
- Product Specification
- Architectural Decision Records
