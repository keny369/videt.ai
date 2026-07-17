---
title: Rails 8 Framework Philosophy
identifier: EM-IV-001
version: 1.0
status: Normative
owner: Engineering Governance
---

# Chapter 1 — Rails 8 Framework Philosophy

## 1. Purpose

This chapter establishes the governing philosophy for the use of Ruby on Rails 8 within the F1 platform.

Rails is the implementation framework selected by the engineering organisation.

It is **not** the architecture.

It is **not** the product model.

It is **not** the source of business behaviour.

Rails exists solely to implement the Product Specification within the architectural constraints defined by Engineering Manual Volumes I–III.

---

# 2. Scope

This chapter governs:

- Rails framework usage;
- framework conventions;
- Rails components;
- architectural boundaries;
- framework upgrades;
- engineering expectations.

Every Rails implementation SHALL comply.

---

# 3. Framework Philosophy

Rails is an implementation tool.

Architecture SHALL determine framework usage.

Framework conventions SHALL be followed only where they reinforce the approved architecture.

Where Rails conventions conflict with the Product Specification, the Engineering Manual or an approved ADR, repository governance SHALL prevail.

---

# 4. Architectural Position

Rails occupies the Infrastructure and Interface Layers.

The Domain Layer SHALL remain substantially independent of Rails.

Business behaviour SHALL never depend upon:

- Active Record callbacks;
- controller filters;
- Rails configuration magic;
- framework lifecycle hooks.

---

# 5. Guiding Principles

Framework usage SHALL satisfy the following principles.

### RF-001 — Architecture First

Architecture governs framework usage.

---

### RF-002 — Explicit Behaviour

Explicit implementation SHALL be preferred over implicit framework behaviour.

---

### RF-003 — Stable Boundaries

Framework APIs SHALL terminate at architectural boundaries.

---

### RF-004 — Upgradeability

Framework-specific code SHALL remain isolated to minimise upgrade cost.

---

### RF-005 — Testability

Framework usage SHALL improve—not reduce—testability.

---

# 6. Approved Rails Components

The platform MAY use:

- Action Controller;
- Active Record;
- Active Job;
- Action Mailer;
- Action Cable;
- Active Support;
- Active Model;
- Active Storage;
- Action Dispatch.

Usage SHALL comply with subsequent chapters of this volume.

---

# 7. Framework Isolation

The Domain SHALL remain isolated from:

- Action Controller;
- Active Record;
- Active Job;
- Action Mailer;
- Active Support extensions that introduce framework coupling.

Framework dependencies SHALL terminate before entering the Domain Model.

---

# 8. Convention Over Configuration

Rails conventions SHOULD be followed where they:

- improve consistency;
- reduce unnecessary configuration;
- preserve architecture.

Framework convenience SHALL never justify architectural compromise.

---

# 9. Configuration

Framework configuration SHALL be:

- explicit;
- documented;
- reproducible;
- version-controlled.

Runtime behaviour SHALL not depend upon undocumented configuration.

---

# 10. Upgrades

Rails upgrades SHALL be treated as engineering projects.

Every upgrade SHALL include:

- compatibility assessment;
- regression testing;
- architecture validation;
- operational verification.

Framework upgrades SHALL never alter Product Specification behaviour.

---

# 11. Extensions

Third-party Rails extensions SHALL satisfy:

- architectural compatibility;
- security review;
- maintenance viability;
- operational suitability.

Framework plugins SHALL not replace core architectural patterns.

---

# 12. Performance

Framework optimisation SHALL occur only after measurement.

Premature optimisation is prohibited.

Performance improvements SHALL preserve readability and architectural integrity.

---

# 13. AI Engineering

AI coding agents SHALL:

- use Rails idiomatically;
- preserve architectural boundaries;
- avoid framework magic where explicit implementation is clearer;
- generate upgrade-friendly implementations;
- avoid introducing unnecessary dependencies upon Rails internals.

AI SHALL treat Rails as an implementation framework rather than an architectural model.

---

# 14. Review Checklist

Reviewers SHALL verify:

## Architecture

- [ ] Framework isolated.
- [ ] Domain independent.
- [ ] Explicit behaviour preserved.

---

## Framework

- [ ] Rails conventions appropriate.
- [ ] Configuration documented.
- [ ] Upgradeability maintained.

---

## Maintainability

- [ ] Readable implementation.
- [ ] Minimal framework coupling.
- [ ] Tests unaffected.

---

# 15. Anti-Patterns

The following practices are prohibited.

- Framework-driven architecture.
- Business logic in controllers.
- Business logic in Active Record callbacks.
- Hidden framework behaviour.
- Undocumented Rails configuration.
- Global monkey patches.
- Framework convenience overriding Product Specification.
- Tight coupling to Rails internals.

---

# 16. Compliance

Every Rails implementation SHALL comply with this philosophy.

Rails is a powerful implementation framework.

Its purpose within the F1 platform is to implement the approved architecture—not define it.

---

# Cross References

- Engineering Manual Volume II — Architecture
- Engineering Manual Volume III — Engineering Standards
- EM-IV-002 Rails Application Structure
- EM-IV-003 Zeitwerk Standards
- Product Specification
- Architectural Decision Records
